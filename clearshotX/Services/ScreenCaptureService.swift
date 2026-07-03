//
//  ScreenCaptureService.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenCaptureServiceError: LocalizedError {
    case permissionDenied
    case noDisplayAvailable
    case noWindowAvailable
    case invalidRegion
    case noImageReturned
    case pngDestinationCreationFailed
    case pngWriteFailed
    case appSupportDirectoryUnavailable

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
        case .pngDestinationCreationFailed:
            "Could not create a PNG destination for the capture."
        case .pngWriteFailed:
            "Could not write the captured PNG to disk."
        case .appSupportDirectoryUnavailable:
            "Could not locate the app support directory."
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
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func captureFullScreen() async throws -> CaptureResult {
        guard hasScreenRecordingPermission() else {
            requestScreenRecordingPermission()
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

        let fileURL = try savePNG(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: fileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height
        )
    }

    func captureRegion(_ region: CGRect) async throws -> CaptureResult {
        guard hasScreenRecordingPermission() else {
            requestScreenRecordingPermission()
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
        configuration.sourceRect = captureRect
        configuration.width = max(1, Int(captureRect.width * scale))
        configuration.height = max(1, Int(captureRect.height * scale))
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let fileURL = try savePNG(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: fileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height
        )
    }

    func availableWindows() async throws -> [SCWindow] {
        guard hasScreenRecordingPermission() else {
            requestScreenRecordingPermission()
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
        guard hasScreenRecordingPermission() else {
            requestScreenRecordingPermission()
            throw ScreenCaptureServiceError.permissionDenied
        }

        guard window.frame.width > 0, window.frame.height > 0 else {
            throw ScreenCaptureServiceError.noWindowAvailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
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

        let fileURL = try savePNG(cgImage)
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return CaptureResult(
            image: image,
            fileURL: fileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height
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

    private func savePNG(_ image: CGImage) throws -> URL {
        let directoryURL = try captureDirectoryURL()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("\(captureFileName()).png")

        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureServiceError.pngDestinationCreationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureServiceError.pngWriteFailed
        }

        return fileURL
    }

    private func captureDirectoryURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ScreenCaptureServiceError.appSupportDirectoryUnavailable
        }

        return applicationSupportURL
            .appendingPathComponent("ClearshotX", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    private func captureFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "ClearshotX-\(formatter.string(from: Date()))"
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
