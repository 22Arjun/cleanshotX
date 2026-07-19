//
//  ScrollingCaptureSession.swift
//  clearshotX
//

import CoreGraphics
import Foundation

/// Owns one scrolling-capture transaction. Feed it settled, same-sized viewport
/// frames from a single serial processing queue. It retains only accepted image
/// strips, so duplicate and rejected stream frames are released immediately.
nonisolated final class ScrollingCaptureSession {
    let configuration: ScrollingCaptureConfiguration

    private let analyzer: ScrollingCaptureFrameAnalyzer
    private var compositor: ScrollingCaptureCompositor?
    private var referenceFrame: CGImage?
    private var acceptedFrameCount = 0
    private var rejectedFrameCount = 0
    private var lastAlignment: ScrollingCaptureAlignment?

    init(configuration: ScrollingCaptureConfiguration = ScrollingCaptureConfiguration()) {
        self.configuration = configuration
        analyzer = ScrollingCaptureFrameAnalyzer(configuration: configuration)
    }

    func ingest(_ frame: CGImage) throws -> ScrollingCaptureFrameDecision {
        let initialPixelCount = frame.width.multipliedReportingOverflow(by: frame.height)
        let insetHeight = configuration.contentInsets.top.addingReportingOverflow(
            configuration.contentInsets.bottom
        )
        guard frame.width > 0,
              frame.height > 0,
              configuration.maximumAnalysisWidth > 0,
              configuration.maximumAnalysisHeight > 0,
              configuration.minimumScrollDistance > 0,
              configuration.maximumScrollFraction > 0,
              configuration.maximumScrollFraction < 1,
              configuration.minimumOverlapFraction > 0,
              configuration.minimumOverlapFraction < 1,
              !insetHeight.overflow,
              insetHeight.partialValue < frame.height,
              configuration.maximumOutputHeight >= frame.height,
              !initialPixelCount.overflow,
              configuration.maximumOutputPixelCount >= initialPixelCount.partialValue
        else {
            throw ScrollingCaptureError.invalidConfiguration
        }

        guard let referenceFrame else {
            compositor = try ScrollingCaptureCompositor(
                firstFrame: frame,
                contentInsets: configuration.contentInsets
            )
            self.referenceFrame = frame
            acceptedFrameCount = 1
            return .started(progress())
        }

        guard referenceFrame.width == frame.width, referenceFrame.height == frame.height else {
            throw ScrollingCaptureError.inconsistentFrameSize(
                expected: CGSize(width: referenceFrame.width, height: referenceFrame.height),
                actual: CGSize(width: frame.width, height: frame.height)
            )
        }

        switch analyzer.analyze(previous: referenceFrame, current: frame) {
        case .duplicate:
            return .duplicate(progress())

        case let .rejected(reason):
            rejectedFrameCount += 1
            return .rejected(reason, progress())

        case let .aligned(alignment):
            guard let compositor else {
                throw ScrollingCaptureError.noFrames
            }

            let proposedHeight = compositor.outputHeight + alignment.verticalOffset
            let proposedPixelCount = proposedHeight.multipliedReportingOverflow(by: frame.width)
            guard proposedHeight <= configuration.maximumOutputHeight,
                  !proposedPixelCount.overflow,
                  proposedPixelCount.partialValue <= configuration.maximumOutputPixelCount
            else {
                return .reachedOutputLimit(progress())
            }

            try compositor.append(frame: frame, verticalOffset: alignment.verticalOffset)
            self.referenceFrame = frame
            acceptedFrameCount += 1
            lastAlignment = alignment
            return .appended(progress())
        }
    }

    func finish() throws -> CGImage {
        guard let compositor else {
            throw ScrollingCaptureError.noFrames
        }
        return try compositor.makeImage()
    }

    /// Replaces the registration reference without adding output rows. This lets a
    /// paused capture ignore transitional UI and continue from the settled viewport.
    func rebase(_ frame: CGImage) throws -> ScrollingCaptureFrameDecision {
        guard let referenceFrame, compositor != nil else {
            return try ingest(frame)
        }
        guard referenceFrame.width == frame.width,
              referenceFrame.height == frame.height
        else {
            throw ScrollingCaptureError.inconsistentFrameSize(
                expected: CGSize(width: referenceFrame.width, height: referenceFrame.height),
                actual: CGSize(width: frame.width, height: frame.height)
            )
        }

        self.referenceFrame = frame
        try compositor?.replaceFooter(from: frame)
        return .rebased(progress())
    }

    private func progress() -> ScrollingCaptureProgress {
        ScrollingCaptureProgress(
            acceptedFrameCount: acceptedFrameCount,
            rejectedFrameCount: rejectedFrameCount,
            outputPixelWidth: compositor?.outputWidth ?? 0,
            outputPixelHeight: compositor?.outputHeight ?? 0,
            lastAlignment: lastAlignment
        )
    }
}

private nonisolated final class ScrollingCaptureCompositor {
    private struct Segment {
        let image: CGImage
    }

    let outputWidth: Int
    private(set) var outputHeight: Int

    private let frameHeight: Int
    private let contentInsets: ScrollingCaptureContentInsets
    private var segments: [Segment] = []
    private var finalFooter: CGImage?

    init(firstFrame: CGImage, contentInsets: ScrollingCaptureContentInsets) throws {
        outputWidth = firstFrame.width
        frameHeight = firstFrame.height
        self.contentInsets = contentInsets
        outputHeight = firstFrame.height

        let bodyHeight = frameHeight - contentInsets.bottom
        guard bodyHeight > contentInsets.top,
              let body = Self.copying(
                image: firstFrame,
                topLeftPixelRect: CGRect(x: 0, y: 0, width: outputWidth, height: bodyHeight)
              )
        else {
            throw ScrollingCaptureError.imageCreationFailed
        }
        segments.append(Segment(image: body))
        finalFooter = try Self.copyFooter(
            from: firstFrame,
            bottomInset: contentInsets.bottom
        )
    }

    func append(frame: CGImage, verticalOffset: Int) throws {
        let movingBottom = frameHeight - contentInsets.bottom
        let movingHeight = movingBottom - contentInsets.top
        guard verticalOffset > 0,
              verticalOffset <= movingHeight,
              let strip = Self.copying(
                image: frame,
                topLeftPixelRect: CGRect(
                    x: 0,
                    y: movingBottom - verticalOffset,
                    width: outputWidth,
                    height: verticalOffset
                )
              )
        else {
            throw ScrollingCaptureError.imageCreationFailed
        }

        segments.append(Segment(image: strip))
        finalFooter = try Self.copyFooter(
            from: frame,
            bottomInset: contentInsets.bottom
        )
        outputHeight += verticalOffset
    }

    func replaceFooter(from frame: CGImage) throws {
        finalFooter = try Self.copyFooter(
            from: frame,
            bottomInset: contentInsets.bottom
        )
    }

    func makeImage() throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingCaptureError.imageCreationFailed
        }

        context.interpolationQuality = .none
        var destinationTop = 0
        for segment in segments {
            Self.drawTopAligned(
                segment.image,
                at: destinationTop,
                outputHeight: outputHeight,
                in: context
            )
            destinationTop += segment.image.height
        }

        if let finalFooter {
            Self.drawTopAligned(
                finalFooter,
                at: destinationTop,
                outputHeight: outputHeight,
                in: context
            )
        }

        guard let image = context.makeImage() else {
            throw ScrollingCaptureError.imageCreationFailed
        }
        return image
    }

    private static func copyFooter(from image: CGImage, bottomInset: Int) throws -> CGImage? {
        guard bottomInset > 0 else { return nil }
        guard let footer = copying(
            image: image,
            topLeftPixelRect: CGRect(
                x: 0,
                y: image.height - bottomInset,
                width: image.width,
                height: bottomInset
            )
        ) else {
            throw ScrollingCaptureError.imageCreationFailed
        }
        return footer
    }

    private static func copying(image: CGImage, topLeftPixelRect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = topLeftPixelRect.integral.intersection(bounds)
        guard cropRect.width > 0,
              cropRect.height > 0,
              let croppedImage = image.cropping(to: cropRect)
        else {
            return nil
        }

        let width = Int(cropRect.width)
        let height = Int(cropRect.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .none
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func drawTopAligned(
        _ image: CGImage,
        at destinationTop: Int,
        outputHeight: Int,
        in context: CGContext
    ) {
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: outputHeight - destinationTop - image.height,
                width: image.width,
                height: image.height
            )
        )
    }
}
