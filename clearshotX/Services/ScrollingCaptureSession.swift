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
    private let continuityValidator: ScrollingCaptureContinuityValidator
    private var compositor: ScrollingCaptureCompositor?
    private var referenceSize: CGSize?
    private var acceptedFrameCount = 0
    private var rejectedFrameCount = 0
    private var lastAlignment: ScrollingCaptureAlignment?

    init(configuration: ScrollingCaptureConfiguration = ScrollingCaptureConfiguration()) {
        self.configuration = configuration
        analyzer = ScrollingCaptureFrameAnalyzer(configuration: configuration)
        continuityValidator = ScrollingCaptureContinuityValidator(configuration: configuration)
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

        guard let referenceSize else {
            compositor = try ScrollingCaptureCompositor(
                firstFrame: frame,
                contentInsets: configuration.contentInsets
            )
            guard analyzer.setReference(frame),
                  continuityValidator.setReference(frame)
            else {
                compositor = nil
                throw ScrollingCaptureError.imageCreationFailed
            }
            self.referenceSize = CGSize(width: frame.width, height: frame.height)
            acceptedFrameCount = 1
            return .started(progress())
        }

        guard Int(referenceSize.width) == frame.width,
              Int(referenceSize.height) == frame.height
        else {
            throw ScrollingCaptureError.inconsistentFrameSize(
                expected: referenceSize,
                actual: CGSize(width: frame.width, height: frame.height)
            )
        }

        switch analyzer.analyze(current: frame) {
        case .duplicate:
            if continuityValidator.candidateIsStationary(frame) {
                try compositor?.refreshDeferredPixels(from: frame)
            }
            continuityValidator.discardCandidate()
            analyzer.discardCandidate()
            return .duplicate(progress())

        case let .rejected(reason):
            if let recoveredAlignment = continuityValidator.recover(candidate: frame) {
                return try appendValidated(frame, alignment: recoveredAlignment)
            }
            // A browser can repaint images, fonts, or animations while the scroll
            // position is unchanged. Such a frame is not a new document strip, but
            // it is a better source for pixels that have not been committed yet.
            if continuityValidator.preparedCandidateIsStationary() {
                try compositor?.refreshDeferredPixels(from: frame)
            }
            continuityValidator.discardCandidate()
            analyzer.discardCandidate()
            rejectedFrameCount += 1
            return .rejected(reason, progress())

        case let .aligned(alignment):
            guard let refinedAlignment = continuityValidator.refine(
                candidate: frame,
                proposed: alignment
            ) else {
                continuityValidator.discardCandidate()
                analyzer.discardCandidate()
                rejectedFrameCount += 1
                return .rejected(
                    .noReliableAlignment(
                        bestDifference: alignment.difference,
                        confidence: alignment.confidence
                    ),
                    progress()
                )
            }
            return try appendValidated(frame, alignment: refinedAlignment)
        }
    }

    func finish() throws -> CGImage {
        guard let compositor else {
            throw ScrollingCaptureError.noFrames
        }
        return try compositor.makeImage()
    }

    /// Resuming must prove continuity with the last accepted viewport. Blindly
    /// rebasing here can silently omit everything the user scrolled past while the
    /// stream was paused, so the first resumed frame goes through normal ingestion.
    func rebase(_ frame: CGImage) throws -> ScrollingCaptureFrameDecision {
        try ingest(frame)
    }

    private func appendValidated(
        _ frame: CGImage,
        alignment: ScrollingCaptureAlignment
    ) throws -> ScrollingCaptureFrameDecision {
        guard let compositor else {
            throw ScrollingCaptureError.noFrames
        }
        if let detectedInsets = continuityValidator.detectedContentInsets {
            analyzer.updateContentInsets(detectedInsets)
            try compositor.updateContentInsets(
                detectedInsets,
                latestFrame: frame
            )
        }

        let proposedHeight = compositor.outputHeight + alignment.verticalOffset
        let proposedPixelCount = proposedHeight.multipliedReportingOverflow(by: frame.width)
        guard proposedHeight <= configuration.maximumOutputHeight,
              !proposedPixelCount.overflow,
              proposedPixelCount.partialValue <= configuration.maximumOutputPixelCount
        else {
            continuityValidator.discardCandidate()
            analyzer.discardCandidate()
            return .reachedOutputLimit(progress())
        }

        try compositor.append(frame: frame, verticalOffset: alignment.verticalOffset)
        continuityValidator.acceptCandidateAsReference()
        analyzer.acceptCandidateAsReference()
        acceptedFrameCount += 1
        lastAlignment = alignment
        return .appended(progress())
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

/// A second, full-height registration pass protects the compositor from the two
/// errors that are most visible in text-heavy captures: downsample rounding at the
/// seam and stationary repaints being mistaken for scroll motion. It never changes
/// output pixels; it only verifies and refines the integer row offset.
private nonisolated final class ScrollingCaptureContinuityValidator {
    private enum Direction {
        case forward
        case reverse
    }

    private struct OffsetScore {
        let offset: Int
        let difference: Double
    }

    private let configuration: ScrollingCaptureConfiguration
    private var referencePlane: ContinuityPlane?
    private var candidatePlane: ContinuityPlane?
    private var activeContentInsets: ScrollingCaptureContentInsets
    private(set) var detectedContentInsets: ScrollingCaptureContentInsets?

    init(configuration: ScrollingCaptureConfiguration) {
        self.configuration = configuration
        activeContentInsets = configuration.contentInsets
    }

    @discardableResult
    func setReference(_ image: CGImage) -> Bool {
        guard let plane = ContinuityPlane(image: image) else {
            referencePlane = nil
            candidatePlane = nil
            return false
        }
        referencePlane = plane
        candidatePlane = nil
        return true
    }

    /// Returns true only when zero movement is materially more plausible than
    /// either small forward or reverse movement. This permits a settled browser
    /// repaint to refresh deferred pixels without advancing the document position.
    func candidateIsStationary(_ image: CGImage) -> Bool {
        guard prepareCandidate(image) else { return false }
        return preparedCandidateIsStationary()
    }

    /// Evaluates the candidate already prepared by `recover(candidate:)`.
    /// Reusing it avoids rebuilding a full-height luma plane on the expensive
    /// recovery path when the frame turns out to be a settled repaint.
    func preparedCandidateIsStationary() -> Bool {
        guard let referencePlane,
              let candidatePlane,
              let content = contentRows(in: referencePlane)
        else {
            return false
        }

        let zero = difference(
            previous: referencePlane,
            current: candidatePlane,
            content: content,
            offset: 0,
            direction: .forward
        )
        let maximumProbe = min(
            max(2, sampledOffset(configuration.minimumScrollDistance + 6, in: referencePlane)),
            max(1, content.count - 2)
        )
        guard maximumProbe >= 1 else { return false }

        let forward = bestScore(
            previous: referencePlane,
            current: candidatePlane,
            content: content,
            offsets: 1...maximumProbe,
            direction: .forward
        )?.difference ?? 1
        let reverse = bestScore(
            previous: referencePlane,
            current: candidatePlane,
            content: content,
            offsets: 1...maximumProbe,
            direction: .reverse
        )?.difference ?? 1
        let bestMotion = min(forward, reverse)
        let qualityLimit = max(
            configuration.duplicateDifferenceThreshold * 2.5,
            configuration.maximumAlignmentDifference * 0.70
        )

        return zero <= qualityLimit
            && zero + 0.001_5 < bestMotion
            && zero <= bestMotion * 0.92
    }

    func refine(
        candidate image: CGImage,
        proposed: ScrollingCaptureAlignment
    ) -> ScrollingCaptureAlignment? {
        guard prepareCandidate(image),
              let referencePlane,
              let candidatePlane
        else {
            return nil
        }

        let proposedOffset = sampledOffset(proposed.verticalOffset, in: referencePlane)
        if configuration.contentInsets == .zero,
           activeContentInsets == .zero {
            let detected = detectFixedContentInsets(
                previous: referencePlane,
                current: candidatePlane,
                approximateOffset: proposedOffset
            )
            if detected != .zero {
                activeContentInsets = detected
                detectedContentInsets = detected
            }
        }
        guard let content = contentRows(in: referencePlane) else { return nil }
        let radius = max(2, sampledOffset(6, in: referencePlane))
        let minimumOffset = max(
            1,
            sampledOffset(configuration.minimumScrollDistance, in: referencePlane)
        )
        let maximumOffset = min(
            content.count - 2,
            sampledOffset(
                Int(Double(content.count) / referencePlane.verticalScale
                    * configuration.maximumScrollFraction),
                in: referencePlane
            )
        )
        let lowerBound = max(minimumOffset, proposedOffset - radius)
        let upperBound = min(maximumOffset, proposedOffset + radius)
        guard lowerBound <= upperBound,
              let forward = bestScore(
                  previous: referencePlane,
                  current: candidatePlane,
                  content: content,
                  offsets: lowerBound...upperBound,
                  direction: .forward
              )
        else {
            return nil
        }

        let zero = difference(
            previous: referencePlane,
            current: candidatePlane,
            content: content,
            offset: 0,
            direction: .forward
        )
        let reverseLower = max(1, forward.offset - radius)
        let reverseUpper = min(content.count - 2, forward.offset + radius)
        let reverse = reverseLower <= reverseUpper
            ? bestScore(
                previous: referencePlane,
                current: candidatePlane,
                content: content,
                offsets: reverseLower...reverseUpper,
                direction: .reverse
            )?.difference
            : nil

        let qualityLimit = max(
            configuration.maximumAlignmentDifference * 1.15,
            0.025
        )
        let motionImprovement = (zero - forward.difference) / max(zero, 0.000_001)
        guard forward.difference <= qualityLimit,
              forward.difference + 0.001_5 < zero,
              motionImprovement >= 0.06,
              reverse.map({ forward.difference <= $0 * 0.94 }) ?? true
        else {
            return nil
        }

        let fullResolutionOffset = max(
            configuration.minimumScrollDistance,
            Int((Double(forward.offset) / referencePlane.verticalScale).rounded())
        )
        return ScrollingCaptureAlignment(
            verticalOffset: fullResolutionOffset,
            difference: forward.difference,
            confidence: min(proposed.confidence, max(0, motionImprovement))
        )
    }

    /// Rare fail-safe for Retina offsets that fall between coarse-plane rows.
    /// It searches native vertical rows with sparse samples, then densely verifies
    /// only the winning neighborhood. Ambiguous or reverse explanations still fail.
    func recover(candidate image: CGImage) -> ScrollingCaptureAlignment? {
        guard prepareCandidate(image),
              let referencePlane,
              let candidatePlane,
              let initialContent = contentRows(in: referencePlane)
        else {
            return nil
        }

        let minimumOffset = max(
            1,
            sampledOffset(configuration.minimumScrollDistance, in: referencePlane)
        )
        let maximumOffset = min(
            initialContent.count - 2,
            Int((Double(initialContent.count) * configuration.maximumScrollFraction).rounded(.down))
        )
        guard minimumOffset <= maximumOffset else { return nil }

        // This full-range sweep is the most expensive step in the whole capture
        // pipeline: every offset in a range that can span hundreds of rows is
        // evaluated so a genuinely unrelated, similarly-good offset elsewhere can
        // still be detected (the uniqueness gate below), and so a real minimum
        // one row off from a coarser sample is never missed on Retina content.
        // An offset stride was tried here to bound the sweep's cost and caused
        // `testTallRetinaViewportRefinesEverySeamAtNativeRowResolution` to miss
        // the true offset — the buffer-pointer speedup below is the safe win.
        var sparseScores: [OffsetScore] = []
        sparseScores.reserveCapacity(maximumOffset - minimumOffset + 1)
        for offset in minimumOffset...maximumOffset {
            sparseScores.append(
                OffsetScore(
                    offset: offset,
                    difference: sparseDifference(
                        previous: referencePlane,
                        current: candidatePlane,
                        content: initialContent,
                        offset: offset,
                        direction: .forward
                    )
                )
            )
        }
        guard let sparseBest = sparseScores.min(by: { $0.difference < $1.difference }) else {
            return nil
        }

        if configuration.contentInsets == .zero,
           activeContentInsets == .zero {
            let detected = detectFixedContentInsets(
                previous: referencePlane,
                current: candidatePlane,
                approximateOffset: sparseBest.offset
            )
            if detected != .zero {
                activeContentInsets = detected
                detectedContentInsets = detected
            }
        }
        guard let content = contentRows(in: referencePlane) else { return nil }

        let radius = 4
        let lower = max(minimumOffset, sparseBest.offset - radius)
        let upper = min(content.count - 2, sparseBest.offset + radius)
        guard lower <= upper,
              let forward = bestScore(
                previous: referencePlane,
                current: candidatePlane,
                content: content,
                offsets: lower...upper,
                direction: .forward
              )
        else {
            return nil
        }

        let zero = difference(
            previous: referencePlane,
            current: candidatePlane,
            content: content,
            offset: 0,
            direction: .forward
        )
        let reverseLower = max(1, forward.offset - 6)
        let reverseUpper = min(content.count - 2, forward.offset + 6)
        let reverse = reverseLower <= reverseUpper
            ? bestScore(
                previous: referencePlane,
                current: candidatePlane,
                content: content,
                offsets: reverseLower...reverseUpper,
                direction: .reverse
              )?.difference ?? 1
            : 1
        let distinctSecond = sparseScores
            .filter { abs($0.offset - sparseBest.offset) > 8 }
            .map(\.difference)
            .min() ?? 1
        let uniqueness = max(
            0,
            (distinctSecond - sparseBest.difference) / max(distinctSecond, 0.000_001)
        )
        let motionImprovement = (zero - forward.difference) / max(zero, 0.000_001)
        let qualityLimit = max(configuration.maximumAlignmentDifference * 1.15, 0.025)
        guard forward.difference <= qualityLimit,
              forward.difference + 0.001_5 < zero,
              forward.difference <= reverse * 0.94,
              uniqueness >= 0.12,
              motionImprovement >= 0.08
        else {
            return nil
        }

        return ScrollingCaptureAlignment(
            verticalOffset: forward.offset,
            difference: forward.difference,
            confidence: min(1, min(uniqueness, motionImprovement))
        )
    }

    func acceptCandidateAsReference() {
        if let candidatePlane {
            referencePlane = candidatePlane
        }
        self.candidatePlane = nil
    }

    func discardCandidate() {
        candidatePlane = nil
    }

    private func prepareCandidate(_ image: CGImage) -> Bool {
        guard let referencePlane,
              let plane = ContinuityPlane(image: image),
              plane.width == referencePlane.width,
              plane.height == referencePlane.height
        else {
            candidatePlane = nil
            return false
        }
        candidatePlane = plane
        return true
    }

    private func contentRows(in plane: ContinuityPlane) -> Range<Int>? {
        let top = min(
            plane.height,
            sampledOffset(activeContentInsets.top, in: plane)
        )
        let bottom = min(
            plane.height - top,
            sampledOffset(activeContentInsets.bottom, in: plane)
        )
        let end = plane.height - bottom
        guard end - top >= 4 else { return nil }
        return top..<end
    }

    private func sampledOffset(_ offset: Int, in plane: ContinuityPlane) -> Int {
        max(0, Int((Double(offset) * plane.verticalScale).rounded()))
    }

    /// Detects sticky bands only at viewport boundaries. A row must agree at zero
    /// motion and disagree with the document-motion hypothesis; this distinction
    /// avoids treating ordinary repeated page rows as application chrome.
    private func detectFixedContentInsets(
        previous: ContinuityPlane,
        current: ContinuityPlane,
        approximateOffset: Int
    ) -> ScrollingCaptureContentInsets {
        guard approximateOffset > 0,
              previous.height == current.height,
              previous.width == current.width
        else {
            return .zero
        }

        let maximumBand = max(0, min(previous.height / 4, previous.height - 4))
        guard maximumBand >= 4 else { return .zero }
        let stableThreshold = min(
            0.015,
            max(0.004, configuration.duplicateDifferenceThreshold * 0.85)
        )
        let separation = max(0.010, stableThreshold * 1.6)

        // Fixed bars commonly begin/end with several rows of plain padding. Those
        // rows are stable at zero motion but can look just like the page's white
        // background under the moving hypothesis, so they are neutral rather than
        // negative evidence. Search through a bounded padding gap and require a
        // cluster of discriminating rows near the viewport boundary.
        let maximumPaddingGap = max(8, min(24, previous.height / 24))
        let maximumLeadingPadding = max(8, min(32, previous.height / 32))

        var topFirstEvidence = -1
        var topLastEvidence = -1
        var topEvidenceCount = 0
        var rowsSinceTopEvidence = 0
        for row in 0..<maximumBand {
            let zero = rowDifference(
                previous: previous,
                previousRow: row,
                current: current,
                currentRow: row
            )
            let movingRow = row + approximateOffset
            let moving = movingRow < previous.height
                ? rowDifference(
                    previous: previous,
                    previousRow: movingRow,
                    current: current,
                    currentRow: row
                )
                : 1
            if zero <= stableThreshold, moving >= zero + separation {
                if topFirstEvidence < 0 { topFirstEvidence = row }
                topLastEvidence = row
                topEvidenceCount += 1
                rowsSinceTopEvidence = 0
            } else if topFirstEvidence >= 0 {
                rowsSinceTopEvidence += 1
                if rowsSinceTopEvidence > maximumPaddingGap { break }
            }
        }

        var bottomLastEvidence = previous.height
        var bottomFirstEvidence = previous.height
        var bottomEvidenceCount = 0
        var rowsSinceBottomEvidence = 0
        let bottomLimit = max(0, previous.height - maximumBand)
        if previous.height > 0 {
            for row in stride(from: previous.height - 1, through: bottomLimit, by: -1) {
                let zero = rowDifference(
                    previous: previous,
                    previousRow: row,
                    current: current,
                    currentRow: row
                )
                let alternativeRow = row - approximateOffset
                let alternative = alternativeRow >= 0
                    ? rowDifference(
                        previous: previous,
                        previousRow: alternativeRow,
                        current: current,
                        currentRow: row
                    )
                    : 1
                if zero <= stableThreshold, alternative >= zero + separation {
                    if bottomLastEvidence == previous.height { bottomLastEvidence = row }
                    bottomFirstEvidence = row
                    bottomEvidenceCount += 1
                    rowsSinceBottomEvidence = 0
                } else if bottomLastEvidence < previous.height {
                    rowsSinceBottomEvidence += 1
                    if rowsSinceBottomEvidence > maximumPaddingGap { break }
                }
            }
        }

        let hasReliableTopCluster = topEvidenceCount >= 4
            && topFirstEvidence <= maximumLeadingPadding
        let hasReliableBottomCluster = bottomEvidenceCount >= 4
            && previous.height - 1 - bottomLastEvidence <= maximumLeadingPadding
        let sampledTop = hasReliableTopCluster ? topLastEvidence + 1 : 0
        let sampledBottom = hasReliableBottomCluster
            ? previous.height - bottomFirstEvidence
            : 0
        let scale = max(previous.verticalScale, 0.000_001)
        let top = Int((Double(sampledTop) / scale).rounded())
        let bottom = Int((Double(sampledBottom) / scale).rounded())
        guard top + bottom < previous.height / 2 else { return .zero }
        return ScrollingCaptureContentInsets(top: top, bottom: bottom)
    }

    private func rowDifference(
        previous: ContinuityPlane,
        previousRow: Int,
        current: ContinuityPlane,
        currentRow: Int
    ) -> Double {
        guard previousRow >= 0,
              previousRow < previous.height,
              currentRow >= 0,
              currentRow < current.height
        else {
            return 1
        }
        let edgeInset = min(max(1, previous.width / 32), previous.width / 4)
        let start = edgeInset
        let end = max(start + 1, previous.width - edgeInset)
        let previousBase = previousRow * previous.width
        let currentBase = currentRow * current.width
        var total = 0
        for column in start..<end {
            total += abs(
                Int(previous.pixels[previousBase + column])
                    - Int(current.pixels[currentBase + column])
            )
        }
        return Double(total) / Double(max(1, end - start) * 255)
    }

    private func sparseDifference(
        previous: ContinuityPlane,
        current: ContinuityPlane,
        content: Range<Int>,
        offset: Int,
        direction: Direction
    ) -> Double {
        let rowCount = content.count - offset
        guard rowCount > 0 else { return 1 }
        let previousStart: Int
        let currentStart: Int
        switch direction {
        case .forward:
            previousStart = content.lowerBound + offset
            currentStart = content.lowerBound
        case .reverse:
            previousStart = content.lowerBound
            currentStart = content.lowerBound + offset
        }

        let edgeInset = min(max(1, previous.width / 32), previous.width / 4)
        let endColumn = max(edgeInset + 1, previous.width - edgeInset)
        let rowStride = max(4, rowCount / 180)
        let columnStride = max(3, (endColumn - edgeInset) / 48)
        let previousWidth = previous.width
        let currentWidth = current.width

        var total = 0
        var samples = 0
        // This is the hottest loop in the whole capture pipeline: it runs for
        // every offset in a full-range recovery sweep. Unsafe buffer pointers
        // remove Array's bounds-check and uniqueness-check overhead per access
        // without changing a single computed value.
        previous.pixels.withUnsafeBufferPointer { previousPixels in
            current.pixels.withUnsafeBufferPointer { currentPixels in
                var row = 0
                while row < rowCount {
                    let previousBase = (previousStart + row) * previousWidth
                    let currentBase = (currentStart + row) * currentWidth
                    var column = edgeInset
                    while column < endColumn {
                        total += abs(
                            Int(previousPixels[previousBase + column])
                                - Int(currentPixels[currentBase + column])
                        )
                        samples += 1
                        column += columnStride
                    }
                    row += rowStride
                }
            }
        }
        guard samples > 0 else { return 1 }
        return Double(total) / Double(samples * 255)
    }

    private func bestScore(
        previous: ContinuityPlane,
        current: ContinuityPlane,
        content: Range<Int>,
        offsets: ClosedRange<Int>,
        direction: Direction
    ) -> OffsetScore? {
        offsets.lazy
            .filter { $0 > 0 && $0 < content.count }
            .map {
                OffsetScore(
                    offset: $0,
                    difference: self.difference(
                        previous: previous,
                        current: current,
                        content: content,
                        offset: $0,
                        direction: direction
                    )
                )
            }
            .min { $0.difference < $1.difference }
    }

    private func difference(
        previous: ContinuityPlane,
        current: ContinuityPlane,
        content: Range<Int>,
        offset: Int,
        direction: Direction
    ) -> Double {
        let rowCount = content.count - offset
        guard rowCount > 0 else { return 1 }

        let previousStart: Int
        let currentStart: Int
        switch direction {
        case .forward:
            previousStart = content.lowerBound + offset
            currentStart = content.lowerBound
        case .reverse:
            previousStart = content.lowerBound
            currentStart = content.lowerBound + offset
        }

        let edgeInset = min(max(1, previous.width / 32), max(0, previous.width / 4))
        let startColumn = edgeInset
        let endColumn = max(startColumn + 1, previous.width - edgeInset)
        let rowStride = rowCount > 1_200 ? 2 : 1
        let previousWidth = previous.width
        let currentWidth = current.width

        var total = 0
        var samples = 0
        previous.pixels.withUnsafeBufferPointer { previousPixels in
            current.pixels.withUnsafeBufferPointer { currentPixels in
                var row = 0
                while row < rowCount {
                    let previousBase = (previousStart + row) * previousWidth
                    let currentBase = (currentStart + row) * currentWidth
                    var column = startColumn
                    while column < endColumn {
                        total += abs(
                            Int(previousPixels[previousBase + column])
                                - Int(currentPixels[currentBase + column])
                        )
                        samples += 1
                        column += 1
                    }
                    row += rowStride
                }
            }
        }
        guard samples > 0 else { return 1 }
        return Double(total) / Double(samples * 255)
    }
}

/// Registration is horizontally reduced for speed while vertical rows remain
/// native. The refinement searches only a tiny neighborhood around the coarse
/// result, so preserving every physical row is both bounded and exact on Retina
/// and unusually tall displays.
private nonisolated struct ContinuityPlane {
    let width: Int
    let height: Int
    let verticalScale: Double
    let pixels: [UInt8]

    init?(image: CGImage, maximumWidth: Int = 192) {
        guard image.width > 0, image.height > 0 else { return nil }
        let width = max(1, min(maximumWidth, image.width))
        let height = image.height

        var storage = [UInt8](repeating: 0, count: width * height)
        let didDraw = storage.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        self.width = width
        self.height = height
        verticalScale = Double(height) / Double(image.height)
        pixels = storage
    }
}

/// Native-pixel strip compositor shared by manual and automatic capture. It never
/// scales a source frame and keeps fixed top/bottom chrome exactly once.
nonisolated final class ScrollingCaptureCompositor {
    private struct Segment {
        let image: CGImage
    }

    /// Rows at the leading edge of a newly exposed viewport are the most likely to
    /// be mid-rasterization. Keep a bounded native frame and defer those rows until
    /// a later aligned (or settled duplicate) frame can supply cleaner pixels.
    private struct DeferredTail {
        let frame: CGImage
        let height: Int
        let isTemporallyConfirmed: Bool
    }

    let outputWidth: Int
    private(set) var outputHeight: Int

    private let frameHeight: Int
    private var contentInsets: ScrollingCaptureContentInsets
    private var segments: [Segment] = []
    private var deferredTail: DeferredTail?
    private var finalFooter: CGImage?
    private var requiresTemporalConfirmation = true

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

    /// Applies automatically detected sticky chrome while moving pixels are still
    /// speculative. Detection may need two aligned deliveries (for example, a
    /// navbar that becomes sticky only after the first scroll), so a deferred tail
    /// is allowed here. No moving strip may already be irreversible.
    ///
    /// The pending tail stores a source frame rather than a crop. Updating the
    /// insets before it is committed therefore makes its eventual source range use
    /// the new moving-content boundary and prevents fixed chrome from entering the
    /// document. If that tail is taller than the newly discovered content area,
    /// continuity was never observable; fail closed rather than manufacture rows.
    func updateContentInsets(
        _ detected: ScrollingCaptureContentInsets,
        latestFrame: CGImage
    ) throws {
        let resolved = ScrollingCaptureContentInsets(
            top: max(contentInsets.top, detected.top),
            bottom: max(contentInsets.bottom, detected.bottom)
        )
        guard resolved != contentInsets else { return }

        let resolvedMovingHeight = frameHeight - resolved.top - resolved.bottom
        guard segments.count == 1,
              resolvedMovingHeight > 0,
              deferredTail.map({ $0.height <= resolvedMovingHeight }) ?? true,
              let firstFrame = segments.first?.image,
              firstFrame.height >= frameHeight - resolved.bottom,
              let firstBody = Self.copying(
                image: firstFrame,
                topLeftPixelRect: CGRect(
                    x: 0,
                    y: 0,
                    width: outputWidth,
                    height: frameHeight - resolved.bottom
                )
              ) else {
            throw ScrollingCaptureError.imageCreationFailed
        }
        contentInsets = resolved
        segments[0] = Segment(image: firstBody)
        finalFooter = try Self.copyFooter(
            from: latestFrame,
            bottomInset: resolved.bottom
        )
    }

    func append(frame: CGImage, verticalOffset: Int) throws {
        let movingBottom = frameHeight - contentInsets.bottom
        let movingHeight = movingBottom - contentInsets.top
        guard verticalOffset > 0, verticalOffset <= movingHeight else {
            throw ScrollingCaptureError.imageCreationFailed
        }

        if requiresTemporalConfirmation {
            if let deferredTail, deferredTail.isTemporallyConfirmed {
                try commit(deferredTail)
            }
            self.deferredTail = DeferredTail(
                frame: frame,
                height: verticalOffset,
                isTemporallyConfirmed: false
            )
            requiresTemporalConfirmation = false
        } else if let deferredTail {
            let combinedHeight = deferredTail.height + verticalOffset
            let maximumDeferredHeight = max(1, Int(Double(movingHeight) * 0.55))

            if combinedHeight <= maximumDeferredHeight {
                // The current frame still contains the entire deferred document
                // range, so keep the newer pixels and postpone the seam.
                self.deferredTail = DeferredTail(
                    frame: frame,
                    height: combinedHeight,
                    // A P→C→D chain corroborates the first movement. Later
                    // continuous frames inherit that established direction.
                    isTemporallyConfirmed: true
                )
            } else {
                // Prefer the later frame for the older tail whenever it still
                // overlaps. Otherwise fall back to the frame that originally
                // contained those rows; a document gap is never fabricated.
                let sourceFrame: CGImage
                let sourceTop: Int
                if combinedHeight <= movingHeight {
                    sourceFrame = frame
                    sourceTop = movingBottom - combinedHeight
                } else {
                    sourceFrame = deferredTail.frame
                    sourceTop = movingBottom - deferredTail.height
                }
                guard let settledStrip = Self.copying(
                    image: sourceFrame,
                    topLeftPixelRect: CGRect(
                        x: 0,
                        y: sourceTop,
                        width: outputWidth,
                        height: deferredTail.height
                    )
                ) else {
                    throw ScrollingCaptureError.imageCreationFailed
                }
                segments.append(Segment(image: settledStrip))
                self.deferredTail = DeferredTail(
                    frame: frame,
                    height: verticalOffset,
                    isTemporallyConfirmed: true
                )
            }
        } else {
            deferredTail = DeferredTail(
                frame: frame,
                height: verticalOffset,
                isTemporallyConfirmed: false
            )
        }

        finalFooter = try Self.copyFooter(
            from: frame,
            bottomInset: contentInsets.bottom
        )
        outputHeight += verticalOffset
    }

    /// Refreshes only uncommitted pixels. Already assembled rows are immutable, so
    /// a late-loading image can improve the pending tail without damaging history.
    func refreshDeferredPixels(from frame: CGImage) throws {
        if let deferredTail {
            self.deferredTail = DeferredTail(
                frame: frame,
                height: deferredTail.height,
                // A settled frame at the same viewport provides the temporal
                // confirmation required before these rows become irreversible.
                isTemporallyConfirmed: true
            )
        } else if segments.count == 1 {
            let bodyHeight = frameHeight - contentInsets.bottom
            guard let body = Self.copying(
                image: frame,
                topLeftPixelRect: CGRect(
                    x: 0,
                    y: 0,
                    width: outputWidth,
                    height: bodyHeight
                )
            ) else {
                throw ScrollingCaptureError.imageCreationFailed
            }
            segments[0] = Segment(image: body)
        }
        finalFooter = try Self.copyFooter(
            from: frame,
            bottomInset: contentInsets.bottom
        )
        requiresTemporalConfirmation = true
    }

    func makeImage() throws -> CGImage {
        if let deferredTail {
            if deferredTail.isTemporallyConfirmed {
                try commit(deferredTail)
            } else {
                // Never make a one-frame alignment irreversible. Finishing within
                // a single display interval may omit that speculative tail, but it
                // cannot introduce a corrupt seam into the saved capture.
                outputHeight -= deferredTail.height
            }
            self.deferredTail = nil
        }

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

    private func commit(_ deferredTail: DeferredTail) throws {
        let movingBottom = frameHeight - contentInsets.bottom
        guard let strip = Self.copying(
            image: deferredTail.frame,
            topLeftPixelRect: CGRect(
                x: 0,
                y: movingBottom - deferredTail.height,
                width: outputWidth,
                height: deferredTail.height
            )
        ) else {
            throw ScrollingCaptureError.imageCreationFailed
        }
        segments.append(Segment(image: strip))
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
