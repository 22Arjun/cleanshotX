//
//  ScreenCaptureService.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureServiceError: LocalizedError {
    case permissionDenied
    case noDisplayAvailable
    case noWindowAvailable
    case invalidRegion
    case noImageReturned

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is not active yet."
        case .noDisplayAvailable:
            "No display was available to capture."
        case .noWindowAvailable:
            "No capturable window was available."
        case .invalidRegion:
            "The selected capture region is not valid."
        case .noImageReturned:
            "ScreenCaptureKit did not return an image."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            "Enable ClearshotX in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen ClearshotX. macOS usually does not apply this permission to an already-running app."
        default:
            nil
        }
    }
}

struct DisplayRegionCapture {
    let image: CGImage
    let globalRect: CGRect
    let scale: CGFloat
}

final class ScreenCaptureService {
    private let captureStore: CaptureStoring
    private var didRequestScreenRecordingPermission = false

    init(captureStore: CaptureStoring? = nil) {
        self.captureStore = captureStore ?? CaptureStore()
    }

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        guard !didRequestScreenRecordingPermission else {
            return hasScreenRecordingPermission()
        }

        didRequestScreenRecordingPermission = true
        return CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func captureFullScreen() async throws -> CaptureResult {
        guard ensureScreenRecordingPermission() else {
            throw ScreenCaptureServiceError.permissionDenied
        }

        let content = try await SCShareableContent.current

        guard let display = preferredDisplay(from: content.displays) else {
            throw ScreenCaptureServiceError.noDisplayAvailable
        }

        let excludedApplications = content.applications.filter { application in
            application.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        filter.includeMenuBar = true

        let configuration = SCStreamConfiguration()
        let pixelSize = outputPixelSize(for: filter, fallbackDisplay: display)
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let storedCapture = try captureStore.store(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: storedCapture.fileURL,
            dragFileURL: storedCapture.dragFileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            screenFrame: display.frame
        )
    }

    func captureRegion(_ region: CGRect) async throws -> CaptureResult {
        guard ensureScreenRecordingPermission() else {
            throw ScreenCaptureServiceError.permissionDenied
        }

        guard region.width > 0, region.height > 0 else {
            throw ScreenCaptureServiceError.invalidRegion
        }

        let content = try await SCShareableContent.current

        let displayRegions: [(display: SCDisplay, frame: CGRect, captureRect: CGRect)] =
            content.displays.compactMap { display in
                let displayFrame = appKitFrame(for: display)
                let intersection = region.intersection(displayFrame)
                guard !intersection.isNull,
                      intersection.width > 0,
                      intersection.height > 0
                else {
                    return nil
                }
                return (
                    display: display,
                    frame: displayFrame,
                    captureRect: intersection
                )
            }

        guard !displayRegions.isEmpty else {
            throw ScreenCaptureServiceError.noDisplayAvailable
        }

        let excludedApplications = content.applications.filter { application in
            application.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        var captures: [DisplayRegionCapture] = []
        captures.reserveCapacity(displayRegions.count)
        for displayRegion in displayRegions {
            captures.append(
                try await captureDisplayRegion(
                    displayRegion.captureRect,
                    on: displayRegion.display,
                    displayFrame: displayRegion.frame,
                    excludingApplications: excludedApplications
                )
            )
        }

        let cgImage: CGImage
        if captures.count == 1,
           let onlyDisplayFrame = displayRegions.first?.frame,
           onlyDisplayFrame.contains(region)
        {
            cgImage = captures[0].image
        } else {
            cgImage = try Self.compositeRegionImage(from: captures, selectedRegion: region)
        }

        let presentationDisplay = displayRegions.max { lhs, rhs in
            lhs.captureRect.area < rhs.captureRect.area
        }

        let storedCapture = try captureStore.store(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: storedCapture.fileURL,
            dragFileURL: storedCapture.dragFileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            screenFrame: presentationDisplay?.frame ?? region
        )
    }

    private func captureDisplayRegion(
        _ captureRect: CGRect,
        on display: SCDisplay,
        displayFrame: CGRect,
        excludingApplications: [SCRunningApplication]
    ) async throws -> DisplayRegionCapture {
        // The selection overlay uses AppKit's global, bottom-left coordinate space.
        // ScreenCaptureKit expects a display-local crop rectangle with a top-left
        // origin, so both the display offset and vertical orientation must change.
        let proposedSourceRect = CGRect(
            x: captureRect.minX - displayFrame.minX,
            y: displayFrame.maxY - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludingApplications,
            exceptingWindows: []
        )
        filter.includeMenuBar = true

        let scale = max(1, CGFloat(filter.pointPixelScale))
        let displayLocalBounds = CGRect(origin: .zero, size: displayFrame.size)
        let sourceRect = proposedSourceRect
            .pixelAligned(scale: scale)
            .intersection(displayLocalBounds)
        guard !sourceRect.isNull,
              sourceRect.width > 0,
              sourceRect.height > 0
        else {
            throw ScreenCaptureServiceError.invalidRegion
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int((sourceRect.width * scale).rounded()))
        configuration.height = max(1, Int((sourceRect.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let globalRect = CGRect(
            x: displayFrame.minX + sourceRect.minX,
            y: displayFrame.maxY - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        )

        return DisplayRegionCapture(
            image: image,
            globalRect: globalRect,
            scale: scale
        )
    }

    static func compositeRegionImage(
        from captures: [DisplayRegionCapture],
        selectedRegion: CGRect
    ) throws -> CGImage {
        guard let outputScale = captures.map(\.scale).max() else {
            throw ScreenCaptureServiceError.noImageReturned
        }

        let outputRect = selectedRegion.pixelAligned(scale: outputScale)
        let pixelWidth = max(1, Int((outputRect.width * outputScale).rounded()))
        let pixelHeight = max(1, Int((outputRect.height * outputScale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw ScreenCaptureServiceError.noImageReturned
        }

        // A rectangular image must also represent empty space in offset monitor
        // layouts. Black matches the WindowServer's treatment of that desktop gap.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        for capture in captures {
            // Use the highest intersected display scale for a coherent canvas.
            // Lower-density display pieces are resampled; Retina pieces stay native.
            let destinationRect = CGRect(
                x: (capture.globalRect.minX - outputRect.minX) * outputScale,
                y: (capture.globalRect.minY - outputRect.minY) * outputScale,
                width: capture.globalRect.width * outputScale,
                height: capture.globalRect.height * outputScale
            )
            context.interpolationQuality = capture.scale == outputScale ? .none : .high
            context.draw(capture.image, in: destinationRect)
        }

        guard let image = context.makeImage() else {
            throw ScreenCaptureServiceError.noImageReturned
        }
        return image
    }

    private func appKitFrame(for display: SCDisplay) -> CGRect {
        NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else {
                return false
            }
            return screenNumber == display.displayID
        }?.frame ?? display.frame
    }

    func availableWindows() async throws -> [SCWindow] {
        guard ensureScreenRecordingPermission() else {
            throw ScreenCaptureServiceError.permissionDenied
        }

        let content = try await SCShareableContent.current
        let currentBundleIdentifier = Bundle.main.bundleIdentifier

        return content.windows
            .filter { window in
                guard window.isOnScreen, window.frame.width >= 48, window.frame.height >= 48 else {
                    return false
                }

                return window.owningApplication?.bundleIdentifier != currentBundleIdentifier
            }
    }

    func captureWindow(_ window: SCWindow) async throws -> CaptureResult {
        guard ensureScreenRecordingPermission() else {
            throw ScreenCaptureServiceError.permissionDenied
        }

        guard window.frame.width > 0, window.frame.height > 0 else {
            throw ScreenCaptureServiceError.noWindowAvailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let content = try await SCShareableContent.current
        let display = display(containing: window.frame, from: content.displays)
        let configuration = SCStreamConfiguration()
        let pixelSize = outputPixelSize(for: filter, fallbackRect: window.frame)
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let storedCapture = try captureStore.store(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: storedCapture.fileURL,
            dragFileURL: storedCapture.dragFileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            screenFrame: display?.frame ?? NSScreen.main?.frame ?? .zero
        )
    }

    private func preferredDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        guard let mainScreenDisplayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return displays.first
        }

        return displays.first { display in
            display.displayID == mainScreenDisplayID
        } ?? displays.first
    }

    private func ensureScreenRecordingPermission() -> Bool {
        if hasScreenRecordingPermission() {
            return true
        }

        _ = requestScreenRecordingPermission()
        return hasScreenRecordingPermission()
    }

    private func display(containing region: CGRect, from displays: [SCDisplay]) -> SCDisplay? {
        displays
            .map { display in
                (display: display, intersectionArea: region.intersection(display.frame).area)
            }
            .filter { item in
                item.intersectionArea > 0
            }
            .max { lhs, rhs in
                lhs.intersectionArea < rhs.intersectionArea
            }?
            .display
    }

    private func outputPixelSize(for filter: SCContentFilter, fallbackDisplay display: SCDisplay) -> (width: Int, height: Int) {
        let scale = CGFloat(filter.pointPixelScale)
        let contentRect = filter.contentRect

        if contentRect.width > 0, contentRect.height > 0, scale > 0 {
            return (
                width: max(1, Int(contentRect.width * scale)),
                height: max(1, Int(contentRect.height * scale))
            )
        }

        return (
            width: max(1, display.width),
            height: max(1, display.height)
        )
    }

    private func outputPixelSize(for filter: SCContentFilter, fallbackRect rect: CGRect) -> (width: Int, height: Int) {
        let scale = CGFloat(filter.pointPixelScale)
        let contentRect = filter.contentRect
        let outputRect = contentRect.width > 0 && contentRect.height > 0 ? contentRect : rect
        let outputScale = scale > 0 ? scale : NSScreen.main?.backingScaleFactor ?? 2

        return (
            width: max(1, Int(outputRect.width * outputScale)),
            height: max(1, Int(outputRect.height * outputScale))
        )
    }

}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else {
            return 0
        }

        return max(0, width) * max(0, height)
    }

    func pixelAligned(scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let minimumX = floor(minX * scale) / scale
        let minimumY = floor(minY * scale) / scale
        let maximumX = ceil(maxX * scale) / scale
        let maximumY = ceil(maxY * scale) / scale

        return CGRect(
            x: minimumX,
            y: minimumY,
            width: max(0, maximumX - minimumX),
            height: max(0, maximumY - minimumY)
        )
    }
}
