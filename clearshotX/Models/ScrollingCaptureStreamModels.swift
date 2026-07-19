//
//  ScrollingCaptureStreamModels.swift
//  clearshotX
//

import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

nonisolated struct ScrollingCaptureDisplayDescriptor: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let pointPixelScale: CGFloat
}

nonisolated struct ScrollingCaptureRegionGeometry: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let displayFrame: CGRect
    let globalRect: CGRect
    let sourceRect: CGRect
    let pointPixelScale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
}

nonisolated struct ScrollingCaptureStreamFrame: Sendable {
    let image: CGImage
    let presentationTime: CMTime
    let dirtyRects: [CGRect]
    let contentRect: CGRect?
    let scaleFactor: CGFloat?
}

nonisolated protocol ScrollingCaptureFrameSourcing: AnyObject, Sendable {
    func start(
        selectedRegion: CGRect,
        onFrame: @escaping @Sendable (ScrollingCaptureStreamFrame) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) async throws -> ScrollingCaptureRegionGeometry

    func stop() async throws
    func setFrameDeliveryEnabled(_ isEnabled: Bool)
}

nonisolated enum ScrollingCaptureFrameSourceError: LocalizedError, Equatable {
    case alreadyRunning
    case noDisplayAvailable
    case regionSpansMultipleDisplays
    case invalidRegion
    case selectedDisplayUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A scrolling capture is already running."
        case .noDisplayAvailable:
            "No display contains the selected scrolling area."
        case .regionSpansMultipleDisplays:
            "Scrolling capture must stay on one display."
        case .invalidRegion:
            "The selected scrolling area is not valid."
        case .selectedDisplayUnavailable:
            "The display containing the scrolling area is no longer available."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .regionSpansMultipleDisplays:
            "Select an area entirely inside one display."
        case .selectedDisplayUnavailable:
            "Keep the selected display connected and try again."
        default:
            "Select the scrolling area again and retry."
        }
    }
}

nonisolated enum ScrollingCaptureRegionResolver {
    static func resolve(
        selectedRegion: CGRect,
        displays: [ScrollingCaptureDisplayDescriptor]
    ) throws -> ScrollingCaptureRegionGeometry {
        guard !selectedRegion.isNull,
              !selectedRegion.isInfinite,
              selectedRegion.width > 0,
              selectedRegion.height > 0
        else {
            throw ScrollingCaptureFrameSourceError.invalidRegion
        }

        let intersectingDisplays = displays.filter { display in
            let intersection = selectedRegion.intersection(display.frame)
            return !intersection.isNull && intersection.width > 0 && intersection.height > 0
        }
        guard !intersectingDisplays.isEmpty else {
            throw ScrollingCaptureFrameSourceError.noDisplayAvailable
        }

        guard let display = intersectingDisplays.first(where: { descriptor in
            descriptor.frame.contains(selectedRegion)
        }) else {
            if intersectingDisplays.count > 1 {
                throw ScrollingCaptureFrameSourceError.regionSpansMultipleDisplays
            }
            throw ScrollingCaptureFrameSourceError.invalidRegion
        }

        let scale = max(1, display.pointPixelScale)
        let displayLocalBounds = CGRect(origin: .zero, size: display.frame.size)
        let proposedSourceRect = CGRect(
            x: selectedRegion.minX - display.frame.minX,
            y: display.frame.maxY - selectedRegion.maxY,
            width: selectedRegion.width,
            height: selectedRegion.height
        )
        let sourceRect = proposedSourceRect
            .pixelAligned(scale: scale)
            .intersection(displayLocalBounds)
        guard !sourceRect.isNull,
              sourceRect.width > 0,
              sourceRect.height > 0
        else {
            throw ScrollingCaptureFrameSourceError.invalidRegion
        }

        let globalRect = CGRect(
            x: display.frame.minX + sourceRect.minX,
            y: display.frame.maxY - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        )
        return ScrollingCaptureRegionGeometry(
            displayID: display.displayID,
            displayFrame: display.frame,
            globalRect: globalRect,
            sourceRect: sourceRect,
            pointPixelScale: scale,
            pixelWidth: max(1, Int((sourceRect.width * scale).rounded())),
            pixelHeight: max(1, Int((sourceRect.height * scale).rounded()))
        )
    }
}

nonisolated struct ScrollingCaptureFrameGate {
    static func shouldProcess(
        status: SCFrameStatus,
        pixelWidth: Int,
        pixelHeight: Int,
        expectedWidth: Int,
        expectedHeight: Int
    ) -> Bool {
        status == .complete
            && pixelWidth == expectedWidth
            && pixelHeight == expectedHeight
    }
}

private nonisolated extension CGRect {
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
