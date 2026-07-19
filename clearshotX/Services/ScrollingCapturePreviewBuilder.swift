//
//  ScrollingCapturePreviewBuilder.swift
//  clearshotX
//

import CoreGraphics
import Foundation

/// Maintains a small representation of the accepted document. Its decoded memory
/// is permanently bounded by `maximumSize`, regardless of final capture length.
nonisolated final class ScrollingCapturePreviewBuilder {
    private let maximumSize: CGSize
    private let contentInsets: ScrollingCaptureContentInsets

    private var previewImage: CGImage?
    private var sourceWidth = 0
    private var sourceHeight = 0

    init(
        maximumSize: CGSize = CGSize(width: 240, height: 280),
        contentInsets: ScrollingCaptureContentInsets
    ) {
        self.maximumSize = maximumSize
        self.contentInsets = contentInsets
    }

    func apply(
        frame: CGImage,
        decision: ScrollingCaptureFrameDecision
    ) -> CGImage? {
        switch decision {
        case .started:
            sourceWidth = frame.width
            sourceHeight = frame.height
            let renderedImage = renderFirstFrame(frame)
            previewImage = renderedImage
            return renderedImage

        case let .appended(progress):
            guard sourceWidth == frame.width,
                  let verticalOffset = progress.lastAlignment?.verticalOffset,
                  verticalOffset > 0
            else {
                return nil
            }
            let renderedImage = renderAppend(frame: frame, verticalOffset: verticalOffset)
            if let renderedImage {
                previewImage = renderedImage
            }
            sourceHeight += verticalOffset
            return renderedImage

        case .rebased, .duplicate, .rejected, .reachedOutputLimit:
            // The preview has not changed, so avoid publishing an identical image
            // and triggering a redundant SwiftUI render.
            return nil
        }
    }

    private func renderFirstFrame(_ frame: CGImage) -> CGImage? {
        let targetSize = fittedPixelSize(sourceWidth: frame.width, sourceHeight: frame.height)
        guard let context = makeContext(size: targetSize) else { return nil }
        context.interpolationQuality = .medium
        context.draw(
            frame,
            in: CGRect(origin: .zero, size: targetSize)
        )
        return context.makeImage()
    }

    private func renderAppend(frame: CGImage, verticalOffset: Int) -> CGImage? {
        guard let previewImage else { return renderFirstFrame(frame) }

        let bottomInset = min(contentInsets.bottom, frame.height)
        let oldBodySourceHeight = max(0, sourceHeight - bottomInset)
        let newSourceHeight = sourceHeight + verticalOffset
        let targetSize = fittedPixelSize(
            sourceWidth: sourceWidth,
            sourceHeight: newSourceHeight
        )
        guard let context = makeContext(size: targetSize) else { return nil }
        context.interpolationQuality = .medium

        let scale = targetSize.height / CGFloat(newSourceHeight)
        var destinationTop: CGFloat = 0

        if oldBodySourceHeight > 0 {
            let oldBodyFraction = CGFloat(oldBodySourceHeight) / CGFloat(sourceHeight)
            let oldPreviewBodyHeight = max(
                1,
                Int((CGFloat(previewImage.height) * oldBodyFraction).rounded(.down))
            )
            if let oldBody = previewImage.cropping(
                to: CGRect(
                    x: 0,
                    y: 0,
                    width: previewImage.width,
                    height: min(previewImage.height, oldPreviewBodyHeight)
                )
            ) {
                let destinationHeight = CGFloat(oldBodySourceHeight) * scale
                drawTopAligned(
                    oldBody,
                    at: destinationTop,
                    height: destinationHeight,
                    canvasSize: targetSize,
                    context: context
                )
                destinationTop += destinationHeight
            }
        }

        let movingBottom = frame.height - bottomInset
        let stripHeight = min(verticalOffset, movingBottom)
        if stripHeight > 0,
           let strip = frame.cropping(
               to: CGRect(
                   x: 0,
                   y: movingBottom - stripHeight,
                   width: frame.width,
                   height: stripHeight
               )
           ) {
            let destinationHeight = CGFloat(stripHeight) * scale
            drawTopAligned(
                strip,
                at: destinationTop,
                height: destinationHeight,
                canvasSize: targetSize,
                context: context
            )
            destinationTop += destinationHeight
        }

        if bottomInset > 0,
           let footer = frame.cropping(
               to: CGRect(
                   x: 0,
                   y: frame.height - bottomInset,
                   width: frame.width,
                   height: bottomInset
               )
           ) {
            drawTopAligned(
                footer,
                at: destinationTop,
                height: CGFloat(bottomInset) * scale,
                canvasSize: targetSize,
                context: context
            )
        }

        return context.makeImage()
    }

    private func fittedPixelSize(sourceWidth: Int, sourceHeight: Int) -> CGSize {
        guard sourceWidth > 0, sourceHeight > 0 else { return CGSize(width: 1, height: 1) }
        let scale = min(
            1,
            maximumSize.width / CGFloat(sourceWidth),
            maximumSize.height / CGFloat(sourceHeight)
        )
        return CGSize(
            width: max(1, (CGFloat(sourceWidth) * scale).rounded()),
            height: max(1, (CGFloat(sourceHeight) * scale).rounded())
        )
    }

    private func makeContext(size: CGSize) -> CGContext? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: max(1, Int(size.width)),
            height: max(1, Int(size.height)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func drawTopAligned(
        _ image: CGImage,
        at destinationTop: CGFloat,
        height: CGFloat,
        canvasSize: CGSize,
        context: CGContext
    ) {
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: canvasSize.height - destinationTop - height,
                width: canvasSize.width,
                height: height
            )
        )
    }
}
