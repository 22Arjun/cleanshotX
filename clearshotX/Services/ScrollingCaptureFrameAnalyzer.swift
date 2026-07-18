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
nonisolated struct ScrollingCaptureFrameAnalyzer {
    let configuration: ScrollingCaptureConfiguration

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

        let topInset = min(
            previousPlane.height,
            Int((Double(configuration.contentInsets.top) * previousPlane.verticalScale).rounded())
        )
        let bottomInset = min(
            previousPlane.height - topInset,
            Int((Double(configuration.contentInsets.bottom) * previousPlane.verticalScale).rounded())
        )
        let contentHeight = previousPlane.height - topInset - bottomInset
        guard contentHeight >= 4 else {
            return .rejected(.insufficientOverlap)
        }

        let duplicateDifference = meanAbsoluteDifference(
            previous: previousPlane,
            current: currentPlane,
            previousStartRow: topInset,
            currentStartRow: topInset,
            rowCount: contentHeight
        )
        if duplicateDifference <= configuration.duplicateDifferenceThreshold {
            return .duplicate(difference: duplicateDifference)
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

        var candidates: [(shift: Int, difference: Double)] = []
        candidates.reserveCapacity(maximumShift - minimumShift + 1)

        for shift in minimumShift...maximumShift {
            let overlap = contentHeight - shift
            let difference = meanAbsoluteDifference(
                previous: previousPlane,
                current: currentPlane,
                previousStartRow: topInset + shift,
                currentStartRow: topInset,
                rowCount: overlap
            )
            candidates.append((shift, difference))
        }

        guard let best = candidates.min(by: { $0.difference < $1.difference }) else {
            return .rejected(.insufficientOverlap)
        }

        // Adjacent offsets often have correlated scores after downsampling. Compare
        // against the best meaningfully different hypothesis to measure ambiguity.
        let confidenceNeighborhood = max(2, Int((previousPlane.verticalScale * 4).rounded()))
        let secondBestDifference = candidates
            .filter { abs($0.shift - best.shift) > confidenceNeighborhood }
            .map(\.difference)
            .min() ?? 1
        let uniqueness = max(
            0,
            (secondBestDifference - best.difference) / max(secondBestDifference, 0.000_001)
        )
        let matchQuality = max(
            0,
            1 - best.difference / max(configuration.maximumAlignmentDifference, 0.000_001)
        )
        let confidence = min(matchQuality, uniqueness)

        guard best.difference <= configuration.maximumAlignmentDifference,
              confidence >= configuration.minimumAlignmentConfidence
        else {
            return .rejected(
                .noReliableAlignment(
                    bestDifference: best.difference,
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
                difference: best.difference,
                confidence: confidence
            )
        )
    }

    private func meanAbsoluteDifference(
        previous: LumaPlane,
        current: LumaPlane,
        previousStartRow: Int,
        currentStartRow: Int,
        rowCount: Int
    ) -> Double {
        guard rowCount > 0 else { return 1 }

        // Ignore a narrow edge band where scrollbars and window borders commonly
        // animate independently of document content.
        let edgeInset = min(max(1, previous.width / 32), max(0, previous.width / 4))
        let startColumn = edgeInset
        let endColumn = max(startColumn + 1, previous.width - edgeInset)
        let columnStride = previous.width > 128 ? 2 : 1
        let rowStride = rowCount > 180 ? 2 : 1

        var totalDifference = 0
        var sampleCount = 0

        var row = 0
        while row < rowCount {
            let previousBase = (previousStartRow + row) * previous.width
            let currentBase = (currentStartRow + row) * current.width

            var column = startColumn
            while column < endColumn {
                totalDifference += abs(
                    Int(previous.pixels[previousBase + column])
                        - Int(current.pixels[currentBase + column])
                )
                sampleCount += 1
                column += columnStride
            }
            row += rowStride
        }

        guard sampleCount > 0 else { return 1 }
        return Double(totalDifference) / Double(sampleCount * 255)
    }
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

        let scale = min(
            1,
            min(
                Double(maximumWidth) / Double(image.width),
                Double(maximumHeight) / Double(image.height)
            )
        )
        let sampledWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let sampledHeight = max(1, Int((Double(image.height) * scale).rounded()))

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
