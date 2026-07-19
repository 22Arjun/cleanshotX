//
//  ScrollingCaptureFrameAnalyzer.swift
//  clearshotX
//

import CoreGraphics
import Foundation

/// Registers two same-sized viewport frames under the constrained transform used by
/// scrolling capture: content moves vertically while the selected viewport is fixed.
/// Constraining the problem to one axis is both faster and more reliable than a
/// general panorama/homography stitcher for text-heavy interfaces.
nonisolated final class ScrollingCaptureFrameAnalyzer {
    let configuration: ScrollingCaptureConfiguration

    private var referencePlane: LumaPlane?
    private var candidatePlane: LumaPlane?
    private var activeContentInsets: ScrollingCaptureContentInsets

    init(configuration: ScrollingCaptureConfiguration) {
        self.configuration = configuration
        activeContentInsets = configuration.contentInsets
    }

    /// Locks automatically detected sticky chrome out of every later comparison.
    /// Explicit configuration remains the lower bound and is never reduced.
    func updateContentInsets(_ detected: ScrollingCaptureContentInsets) {
        activeContentInsets = ScrollingCaptureContentInsets(
            top: max(configuration.contentInsets.top, detected.top),
            bottom: max(configuration.contentInsets.bottom, detected.bottom)
        )
    }

    func analyze(previous: CGImage, current: CGImage) -> ScrollingCaptureAnalysisResult {
        guard previous.width == current.width,
              previous.height == current.height,
              let previousPlane = LumaPlane(
                image: previous,
                maximumWidth: configuration.maximumAnalysisWidth,
                maximumHeight: configuration.maximumAnalysisHeight
              ),
              let currentPlane = LumaPlane(
                image: current,
                maximumWidth: configuration.maximumAnalysisWidth,
                maximumHeight: configuration.maximumAnalysisHeight
              ),
              previousPlane.width == currentPlane.width,
              previousPlane.height == currentPlane.height
        else {
            return .rejected(.invalidFrame)
        }

        return analyze(previous: previousPlane, current: currentPlane)
    }

    /// Prepares one downsampled registration reference. The session keeps this
    /// small luma plane instead of retaining and reconverting a native-size frame.
    @discardableResult
    func setReference(_ image: CGImage) -> Bool {
        guard let plane = makePlane(image) else {
            referencePlane = nil
            candidatePlane = nil
            return false
        }
        referencePlane = plane
        candidatePlane = nil
        return true
    }

    /// Converts only the new candidate. Accepted candidates can be promoted to the
    /// next reference without another Core Graphics downsample pass.
    func analyze(current: CGImage) -> ScrollingCaptureAnalysisResult {
        guard let previousPlane = referencePlane,
              let currentPlane = makePlane(current),
              previousPlane.width == currentPlane.width,
              previousPlane.height == currentPlane.height
        else {
            candidatePlane = nil
            return .rejected(.invalidFrame)
        }
        candidatePlane = currentPlane
        return analyze(previous: previousPlane, current: currentPlane)
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

    private func makePlane(_ image: CGImage) -> LumaPlane? {
        LumaPlane(
            image: image,
            maximumWidth: configuration.maximumAnalysisWidth,
            maximumHeight: configuration.maximumAnalysisHeight
        )
    }

    private func analyze(
        previous previousPlane: LumaPlane,
        current currentPlane: LumaPlane
    ) -> ScrollingCaptureAnalysisResult {

        let topInset = min(
            previousPlane.height,
            Int((Double(activeContentInsets.top) * previousPlane.verticalScale).rounded())
        )
        let bottomInset = min(
            previousPlane.height - topInset,
            Int((Double(activeContentInsets.bottom) * previousPlane.verticalScale).rounded())
        )
        let contentHeight = previousPlane.height - topInset - bottomInset
        guard contentHeight >= 4 else {
            return .rejected(.insufficientOverlap)
        }

        let minimumShift = max(
            1,
            Int((Double(configuration.minimumScrollDistance) * previousPlane.verticalScale).rounded())
        )
        let minimumOverlap = max(
            2,
            Int((Double(contentHeight) * configuration.minimumOverlapFraction).rounded(.up))
        )
        let maximumShift = min(
            contentHeight - minimumOverlap,
            Int((Double(contentHeight) * configuration.maximumScrollFraction).rounded(.down))
        )
        guard minimumShift <= maximumShift else {
            return .rejected(.insufficientOverlap)
        }

        // Score zero movement before looking for a scroll. A stopped page may still
        // contain a blinking caret, video, lazy image, or antialiasing changes. The
        // robust feature score intentionally ignores one disagreeing vertical band,
        // allowing those frames to remain stationary instead of inventing movement.
        let stationary = registrationScore(
            previous: previousPlane,
            current: currentPlane,
            previousStartRow: topInset,
            currentStartRow: topInset,
            rowCount: contentHeight,
            samplingStride: 2
        )

        let forwardCandidates = alignmentCandidates(
            previous: previousPlane,
            current: currentPlane,
            topInset: topInset,
            contentHeight: contentHeight,
            minimumShift: minimumShift,
            maximumShift: maximumShift,
            direction: .forward
        )
        guard let best = forwardCandidates.min(by: { $0.score.value < $1.score.value }) else {
            return .rejected(.insufficientOverlap)
        }

        let stationaryClearlyWins = stationary.value <= configuration.stationaryDifferenceThreshold
            && stationary.value <= best.score.value * 0.82
        if stationary.value <= configuration.duplicateDifferenceThreshold
            || stationaryClearlyWins {
            return .duplicate(difference: stationary.value)
        }

        // Compare against a genuinely different forward hypothesis. Repeated menu
        // rows, cards, and lines of text otherwise form deceptively sharp minima.
        let confidenceNeighborhood = max(2, Int((previousPlane.verticalScale * 6).rounded(.up)))
        let secondBestDifference = forwardCandidates
            .filter { abs($0.shift - best.shift) > confidenceNeighborhood }
            .map(\.score.value)
            .min() ?? 1
        let uniqueness = max(
            0,
            (secondBestDifference - best.score.value) / max(secondBestDifference, 0.000_001)
        )

        // Search the prohibited (upward-content) transform too. A legitimate
        // downward scroll should be materially more plausible than this inverse
        // explanation. If both directions fit, the page is repetitive/ambiguous and
        // skipping the frame is safer than permanently cutting the output.
        let reverseBest = alignmentCandidates(
            previous: previousPlane,
            current: currentPlane,
            topInset: topInset,
            contentHeight: contentHeight,
            minimumShift: minimumShift,
            maximumShift: maximumShift,
            direction: .reverse,
            refinementSeedCount: 2
        )
        .map(\.score.value)
        .min() ?? 1
        let directionConfidence = max(
            0,
            (reverseBest - best.score.value) / max(reverseBest, 0.000_001)
        )
        let matchQuality = max(
            0,
            1 - best.score.value / max(configuration.maximumAlignmentDifference, 0.000_001)
        )
        let textureConfidence = min(
            1,
            best.score.textureFraction
                / max(configuration.minimumRegistrationTextureFraction * 3, 0.000_001)
        )
        let confidence = min(
            matchQuality,
            uniqueness,
            directionConfidence,
            best.score.bandAgreement,
            textureConfidence
        )

        guard best.score.value <= configuration.maximumAlignmentDifference,
              best.score.textureFraction >= configuration.minimumRegistrationTextureFraction,
              best.score.informativeBandCount >= 2,
              best.score.bandAgreement >= configuration.minimumRegistrationBandAgreement,
              directionConfidence >= configuration.minimumDirectionConfidence,
              confidence >= configuration.minimumAlignmentConfidence
        else {
            return .rejected(
                .noReliableAlignment(
                    bestDifference: best.score.value,
                    confidence: confidence
                )
            )
        }

        let fullResolutionOffset = max(
            configuration.minimumScrollDistance,
            Int((Double(best.shift) / previousPlane.verticalScale).rounded())
        )
        return .aligned(
            ScrollingCaptureAlignment(
                verticalOffset: fullResolutionOffset,
                difference: best.score.value,
                confidence: confidence
            )
        )
    }

    private enum RegistrationDirection {
        case forward
        case reverse
    }

    private struct AlignmentCandidate {
        let shift: Int
        let score: RegistrationScore
    }

    private struct RegistrationScore {
        let value: Double
        let textureFraction: Double
        let informativeBandCount: Int
        let bandAgreement: Double
    }

    /// Hierarchical search keeps the larger, vertically detailed analysis plane
    /// affordable: find several coarse minima, then evaluate every nearby row. This
    /// preserves fast-scroll range without paying for a full dense search.
    private func alignmentCandidates(
        previous: LumaPlane,
        current: LumaPlane,
        topInset: Int,
        contentHeight: Int,
        minimumShift: Int,
        maximumShift: Int,
        direction: RegistrationDirection,
        refinementSeedCount: Int = 4
    ) -> [AlignmentCandidate] {
        // Evaluate every row at the bounded analysis resolution. Sparse stepping
        // can completely miss the true minimum on text and other high-frequency
        // content: the scores one row either side of an exact match need not be
        // locally smooth. The coarse pass is still inexpensive because it samples
        // every fourth row/column, while the best hypotheses receive a denser pass.
        let coarseStep = 1
        var coarse: [AlignmentCandidate] = []
        var shift = minimumShift
        while shift <= maximumShift {
            coarse.append(
                scoreCandidate(
                    previous: previous,
                    current: current,
                    topInset: topInset,
                    contentHeight: contentHeight,
                    shift: shift,
                    direction: direction,
                    samplingStride: 4
                )
            )
            shift += coarseStep
        }
        if coarse.last?.shift != maximumShift {
            coarse.append(
                scoreCandidate(
                    previous: previous,
                    current: current,
                    topInset: topInset,
                    contentHeight: contentHeight,
                    shift: maximumShift,
                    direction: direction,
                    samplingStride: 4
                )
            )
        }

        let seeds = coarse.sorted { $0.score.value < $1.score.value }
            .prefix(max(1, refinementSeedCount))
        var refinedByShift: [Int: AlignmentCandidate] = [:]
        for seed in seeds {
            let lower = max(minimumShift, seed.shift - coarseStep)
            let upper = min(maximumShift, seed.shift + coarseStep)
            for refinedShift in lower...upper {
                refinedByShift[refinedShift] = scoreCandidate(
                    previous: previous,
                    current: current,
                    topInset: topInset,
                    contentHeight: contentHeight,
                    shift: refinedShift,
                    direction: direction,
                    samplingStride: 2
                )
            }
        }

        // Preserve coarse alternative minima for the uniqueness gate while letting
        // their refined equivalents replace them where available.
        for candidate in coarse where refinedByShift[candidate.shift] == nil {
            refinedByShift[candidate.shift] = candidate
        }
        return Array(refinedByShift.values)
    }

    private func scoreCandidate(
        previous: LumaPlane,
        current: LumaPlane,
        topInset: Int,
        contentHeight: Int,
        shift: Int,
        direction: RegistrationDirection,
        samplingStride: Int
    ) -> AlignmentCandidate {
        let overlap = contentHeight - shift
        let starts: (previous: Int, current: Int)
        switch direction {
        case .forward:
            starts = (topInset + shift, topInset)
        case .reverse:
            starts = (topInset, topInset + shift)
        }
        return AlignmentCandidate(
            shift: shift,
            score: registrationScore(
                previous: previous,
                current: current,
                previousStartRow: starts.previous,
                currentStartRow: starts.current,
                rowCount: overlap,
                samplingStride: samplingStride
            )
        )
    }

    /// Combines luminance and edge agreement, then checks independent vertical
    /// bands. Text occupies few pixels on a white page; edge-weighted samples keep
    /// those pixels decisive. Dropping only the single worst band tolerates one
    /// animated/lazy-loaded region without letting broad disagreement pass.
    private func registrationScore(
        previous: LumaPlane,
        current: LumaPlane,
        previousStartRow: Int,
        currentStartRow: Int,
        rowCount: Int,
        samplingStride: Int
    ) -> RegistrationScore {
        guard rowCount > 2 else {
            return RegistrationScore(
                value: 1,
                textureFraction: 0,
                informativeBandCount: 0,
                bandAgreement: 0
            )
        }

        // Ignore a narrow edge band where scrollbars and window borders commonly
        // animate independently of document content.
        let edgeInset = min(max(1, previous.width / 32), max(0, previous.width / 4))
        let startColumn = edgeInset
        let endColumn = max(startColumn + 1, previous.width - edgeInset)
        let stride = max(1, samplingStride)
        let bandCount = 6
        var bands = Array(repeating: RegistrationBand(), count: bandCount)
        var totalLumaDifference = 0.0
        var totalFeatureDifference = 0.0
        var texturedSampleCount = 0
        var sampleCount = 0

        var row = 1
        while row < rowCount {
            let previousRow = previousStartRow + row
            let currentRow = currentStartRow + row
            let previousBase = previousRow * previous.width
            let currentBase = currentRow * current.width
            let previousPriorBase = (previousRow - 1) * previous.width
            let currentPriorBase = (currentRow - 1) * current.width
            let bandIndex = min(bandCount - 1, row * bandCount / rowCount)

            var column = max(startColumn + 1, 1)
            while column < endColumn {
                let previousValue = Int(previous.pixels[previousBase + column])
                let currentValue = Int(current.pixels[currentBase + column])
                let lumaDifference = Double(abs(previousValue - currentValue)) / 255
                let previousGradient = min(
                    255,
                    abs(previousValue - Int(previous.pixels[previousPriorBase + column]))
                        + abs(previousValue - Int(previous.pixels[previousBase + column - 1]))
                )
                let currentGradient = min(
                    255,
                    abs(currentValue - Int(current.pixels[currentPriorBase + column]))
                        + abs(currentValue - Int(current.pixels[currentBase + column - 1]))
                )
                let isTextured = max(previousGradient, currentGradient) >= 12

                totalLumaDifference += lumaDifference
                bands[bandIndex].lumaDifference += lumaDifference
                bands[bandIndex].sampleCount += 1
                if isTextured {
                    let gradientDifference = Double(abs(previousGradient - currentGradient)) / 255
                    let featureDifference = lumaDifference * 0.55 + gradientDifference * 0.45
                    totalFeatureDifference += featureDifference
                    texturedSampleCount += 1
                    bands[bandIndex].featureDifference += featureDifference
                    bands[bandIndex].texturedSampleCount += 1
                }
                sampleCount += 1
                column += stride
            }
            row += stride
        }

        guard sampleCount > 0 else {
            return RegistrationScore(
                value: 1,
                textureFraction: 0,
                informativeBandCount: 0,
                bandAgreement: 0
            )
        }

        let meanLuma = totalLumaDifference / Double(sampleCount)
        let meanFeature = texturedSampleCount > 0
            ? totalFeatureDifference / Double(texturedSampleCount)
            : meanLuma
        let informativeBands = bands.filter {
            $0.texturedSampleCount >= max(4, $0.sampleCount / 200)
        }
        let bandValues = informativeBands.map { band -> Double in
            let luma = band.lumaDifference / Double(max(1, band.sampleCount))
            let feature = band.featureDifference / Double(max(1, band.texturedSampleCount))
            return luma * 0.35 + feature * 0.65
        }
        let sortedBandValues = bandValues.sorted()
        let robustBandValue: Double
        if sortedBandValues.count >= 5 {
            // A sticky header and a sticky footer can occupy two independent
            // boundary bands. Ignore at most those two outliers during the first
            // alignment; the native continuity pass then detects their exact rows.
            let retained = sortedBandValues.dropLast(2)
            robustBandValue = retained.reduce(0, +) / Double(retained.count)
        } else if sortedBandValues.count >= 4 {
            robustBandValue = sortedBandValues.dropLast().reduce(0, +)
                / Double(sortedBandValues.count - 1)
        } else if !sortedBandValues.isEmpty {
            robustBandValue = sortedBandValues.reduce(0, +) / Double(sortedBandValues.count)
        } else {
            robustBandValue = meanLuma
        }
        let agreementThreshold = max(
            configuration.maximumAlignmentDifference * 1.35,
            robustBandValue * 1.8 + 0.002
        )
        let agreeingBands = bandValues.filter { $0 <= agreementThreshold }.count
        let bandAgreement = bandValues.isEmpty
            ? 0
            : Double(agreeingBands) / Double(bandValues.count)
        let combinedValue = meanLuma * 0.12
            + meanFeature * 0.28
            + robustBandValue * 0.60

        return RegistrationScore(
            value: combinedValue,
            textureFraction: Double(texturedSampleCount) / Double(sampleCount),
            informativeBandCount: informativeBands.count,
            bandAgreement: bandAgreement
        )
    }
}

private nonisolated struct RegistrationBand {
    var lumaDifference = 0.0
    var featureDifference = 0.0
    var sampleCount = 0
    var texturedSampleCount = 0
}

private nonisolated struct LumaPlane {
    let width: Int
    let height: Int
    let verticalScale: Double
    let pixels: [UInt8]

    init?(image: CGImage, maximumWidth: Int, maximumHeight: Int) {
        guard image.width > 0,
              image.height > 0,
              maximumWidth > 0,
              maximumHeight > 0
        else {
            return nil
        }

        // Vertical offset accuracy and horizontal discriminating detail have
        // different requirements. Sample each axis independently so a very wide
        // Retina selection does not collapse vertical registration resolution.
        let sampledWidth = max(1, min(image.width, maximumWidth))
        let sampledHeight = max(1, min(image.height, maximumHeight))

        var storage = [UInt8](repeating: 0, count: sampledWidth * sampledHeight)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let didDraw = storage.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: sampledWidth,
                    height: sampledHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: sampledWidth,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: sampledWidth, height: sampledHeight)
            )
            return true
        }
        guard didDraw else { return nil }
        width = sampledWidth
        height = sampledHeight
        verticalScale = Double(sampledHeight) / Double(image.height)
        pixels = storage
    }
}
