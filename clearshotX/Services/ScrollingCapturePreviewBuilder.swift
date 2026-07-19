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
    private let scaleStep: CGFloat = 0.96

    private var previewImage: CGImage?
    private var sourceWidth = 0
    private var sourceHeight = 0

    init(
        maximumSize: CGSize = CGSize(width: 232, height: 420),
        contentInsets: ScrollingCaptureContentInsets
    ) {
        self.maximumSize = CGSize(
            width: max(1, maximumSize.width),
            height: max(1, maximumSize.height)
        )
        self.contentInsets = contentInsets
    }

    func apply(
        frame: CGImage,
        decision: ScrollingCaptureFrameDecision
    ) -> CGImage? {
        switch decision {
        case let .started(progress):
            sourceWidth = max(1, progress.outputPixelWidth)
            sourceHeight = max(1, progress.outputPixelHeight)
            let renderedImage = renderFirstFrame(frame)
            previewImage = renderedImage
            return renderedImage

        case let .appended(progress):
            guard sourceWidth == frame.width,
                  progress.outputPixelHeight > sourceHeight
            else {
                return nil
            }
            // The compositor's height is authoritative. Besides making safely
            // coalesced preview requests possible, this also keeps the miniature
            // synchronized when sticky-content insets change its effective body.
            let newSourceHeight = progress.outputPixelHeight
            let appendedHeight = newSourceHeight - sourceHeight
            let maximumRecoverableHeight = frame.height - min(
                contentInsets.bottom,
                frame.height
            )
            guard appendedHeight <= maximumRecoverableHeight else {
                // The preview renderer fell more than one viewport behind. There
                // are no pixels for that gap in this frame, so freeze the last
                // truthful miniature instead of inventing or stretching rows.
                return nil
            }
            let renderedImage = renderAppend(
                frame: frame,
                appendedHeight: appendedHeight,
                newSourceHeight: newSourceHeight
            )
            if let renderedImage {
                previewImage = renderedImage
            }
            sourceHeight = newSourceHeight
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

    private func renderAppend(
        frame: CGImage,
        appendedHeight: Int,
        newSourceHeight: Int
    ) -> CGImage? {
        guard let previewImage else { return renderFirstFrame(frame) }

        let bottomInset = min(contentInsets.bottom, frame.height)
        let oldBodySourceHeight = max(0, sourceHeight - bottomInset)
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
        let stripHeight = min(appendedHeight, movingBottom)
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
        let rawScale = min(
            1,
            maximumSize.width / CGFloat(sourceWidth),
            maximumSize.height / CGFloat(sourceHeight)
        )
        let widthLimitedScale = min(1, maximumSize.width / CGFloat(sourceWidth))

        // Once height becomes the limiting dimension, quantizing the backing
        // scale prevents the already-built page from being resampled on every
        // accepted strip. Four-percent tiers are visually smooth while reducing
        // cumulative thumbnail blur and CPU work by an order of magnitude.
        let scale: CGFloat
        if rawScale >= widthLimitedScale {
            scale = widthLimitedScale
        } else {
            let tier = ceil(log(rawScale / widthLimitedScale) / log(scaleStep))
            scale = widthLimitedScale * pow(scaleStep, max(0, tier))
        }
        return CGSize(
            width: min(maximumSize.width, max(1, (CGFloat(sourceWidth) * scale).rounded())),
            height: min(maximumSize.height, max(1, (CGFloat(sourceHeight) * scale).rounded()))
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

/// Builds the miniature away from both ScreenCaptureKit's delivery queue and the
/// native stitching lock. Accepted frames stay ordered, rendering is bounded to a
/// tiny bitmap, and presentation is latest-wins at a display-friendly cadence.
nonisolated final class ScrollingCapturePreviewPipeline: @unchecked Sendable {
    typealias Publication = @Sendable (CGImage) -> Void

    private struct Request: @unchecked Sendable {
        let frame: CGImage
        let decision: ScrollingCaptureFrameDecision
    }

    private let queue = DispatchQueue(
        label: "com.clearshotx.scrolling-preview",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )
    private let stateLock = NSLock()
    private let builder: ScrollingCapturePreviewBuilder
    private let contentInsets: ScrollingCaptureContentInsets
    private let publication: Publication
    private let minimumPublicationInterval: TimeInterval
    // One pending request plus the request currently being rendered is enough.
    // Keeping a longer FIFO makes the HUD faithfully show old page states while
    // the native capture has already moved on, which feels like capture latency.
    private let maximumPendingRequestCount = 1

    private var pendingRequests: [Request] = []
    private var isDrainScheduled = false
    private var isActive = true

    // Accessed only on `queue`.
    private var latestRenderedImage: CGImage?
    private var lastPublicationTime: TimeInterval = 0
    private var isPublicationScheduled = false

    init(
        maximumSize: CGSize = CGSize(width: 232, height: 420),
        contentInsets: ScrollingCaptureContentInsets,
        maximumPublicationsPerSecond: Double = 30,
        publication: @escaping Publication
    ) {
        builder = ScrollingCapturePreviewBuilder(
            maximumSize: maximumSize,
            contentInsets: contentInsets
        )
        self.contentInsets = contentInsets
        self.publication = publication
        minimumPublicationInterval = 1 / max(1, maximumPublicationsPerSecond)
    }

    func submit(frame: CGImage, decision: ScrollingCaptureFrameDecision) {
        guard decision.changesPreview else { return }

        stateLock.lock()
        guard isActive else {
            stateLock.unlock()
            return
        }

        let request = Request(frame: frame, decision: decision)
        if pendingRequests.count < maximumPendingRequestCount {
            pendingRequests.append(request)
        } else if let merged = merge(pendingRequests.last, with: request) {
            // Coalescing is lossless while the latest viewport still contains all
            // rows added since the prior pending request. This bounds retained
            // native images even if the main display is temporarily busy.
            pendingRequests[pendingRequests.count - 1] = merged
        } else {
            // Retain the earlier bridge when the latest viewport cannot represent
            // every missing row. The renderer will consume that bridge next; a
            // subsequent submission can then catch up without fabricated pixels.
        }

        let shouldSchedule = !isDrainScheduled
        isDrainScheduled = true
        stateLock.unlock()

        if shouldSchedule {
            queue.async { [weak self] in self?.drain() }
        }
    }

    func stop() {
        stateLock.lock()
        isActive = false
        pendingRequests.removeAll(keepingCapacity: false)
        stateLock.unlock()
    }

    private func drain() {
        while let request = takeNextRequest() {
            autoreleasepool {
                if let image = builder.apply(
                    frame: request.frame,
                    decision: request.decision
                ) {
                    latestRenderedImage = image
                    offerPublication()
                }
            }
        }
    }

    private func takeNextRequest() -> Request? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isActive, !pendingRequests.isEmpty else {
            isDrainScheduled = false
            return nil
        }
        return pendingRequests.removeFirst()
    }

    private func offerPublication() {
        let now = ProcessInfo.processInfo.systemUptime
        let remaining = minimumPublicationInterval - (now - lastPublicationTime)
        if remaining <= 0 {
            publishLatest(now: now)
        } else if !isPublicationScheduled {
            isPublicationScheduled = true
            queue.asyncAfter(deadline: .now() + remaining) { [weak self] in
                guard let self else { return }
                self.isPublicationScheduled = false
                self.publishLatest(now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func publishLatest(now: TimeInterval) {
        guard isStillActive(), let image = latestRenderedImage else { return }
        latestRenderedImage = nil
        lastPublicationTime = now
        publication(image)
    }

    private func isStillActive() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isActive
    }

    private func merge(_ previous: Request?, with latest: Request) -> Request? {
        guard let previous,
              case let .appended(previousProgress) = previous.decision,
              case let .appended(latestProgress) = latest.decision,
              let previousOffset = previousProgress.lastAlignment?.verticalOffset
        else {
            return nil
        }

        let heightBeforePrevious = previousProgress.outputPixelHeight - previousOffset
        let combinedHeight = latestProgress.outputPixelHeight - heightBeforePrevious
        let movingHeight = latest.frame.height - contentInsets.bottom
        guard combinedHeight > 0, combinedHeight <= movingHeight else { return nil }
        return latest
    }
}

private extension ScrollingCaptureFrameDecision {
    nonisolated var changesPreview: Bool {
        switch self {
        case .started, .appended:
            true
        case .rebased, .duplicate, .rejected, .reachedOutputLimit:
            false
        }
    }
}
