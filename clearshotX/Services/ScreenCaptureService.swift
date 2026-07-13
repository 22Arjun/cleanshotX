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

        let fileURL = try captureStore.store(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: fileURL,
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

        guard let display = display(containing: region, from: content.displays) else {
            throw ScreenCaptureServiceError.noDisplayAvailable
        }

        let captureRect = region.intersection(display.frame)

        guard captureRect.width > 0, captureRect.height > 0 else {
            throw ScreenCaptureServiceError.invalidRegion
        }

        // The selection overlay uses AppKit's global, bottom-left coordinate space.
        // ScreenCaptureKit expects a display-local crop rectangle with a top-left
        // origin, so both the display offset and vertical orientation must change.
        let sourceRect = CGRect(
            x: captureRect.minX - display.frame.minX,
            y: display.frame.maxY - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )
        .integral

        guard sourceRect.width > 0, sourceRect.height > 0 else {
            throw ScreenCaptureServiceError.invalidRegion
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
        let scale = CGFloat(filter.pointPixelScale)
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int(sourceRect.width * scale))
        configuration.height = max(1, Int(sourceRect.height * scale))
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let fileURL = try captureStore.store(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: fileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            screenFrame: display.frame
        )
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

        let fileURL = try captureStore.store(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: fileURL,
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
}
