import CoreGraphics
import XCTest

@testable import clearshotX

/// Regression coverage for the failure modes that produce plausible-looking but
/// internally sliced scrolling captures. These tests intentionally verify the
/// assembled pixels, not only the reported offset or output dimensions.
final class ScrollingCaptureAdversarialRegressionTests: XCTestCase {
    func testStoppingOnRepeatedFramesThenResumingKeepsEveryDocumentRow() throws {
        let document = adversarialNoiseDocument(width: 112, height: 720)
        let viewportHeight = 180
        let session = ScrollingCaptureSession(configuration: adversarialConfiguration())

        guard case .started = try session.ingest(
            adversarialCrop(document, y: 0, height: viewportHeight)
        ) else {
            return XCTFail("Expected the capture to start.")
        }

        let stoppedFrame = adversarialCrop(document, y: 47, height: viewportHeight)
        guard case .appended = try session.ingest(stoppedFrame) else {
            return XCTFail("Expected the first scroll movement to append.")
        }

        // A real stream continues delivering frames while the user reads the page.
        // None of those frames may add output or replace the last good reference.
        for _ in 0..<24 {
            guard case let .duplicate(progress) = try session.ingest(stoppedFrame) else {
                return XCTFail("A settled viewport must be treated as a duplicate.")
            }
            XCTAssertEqual(progress.acceptedFrameCount, 2)
            XCTAssertEqual(progress.outputPixelHeight, viewportHeight + 47)
        }

        let resumedOffsets = [68, 121, 158, 244]
        for offset in resumedOffsets {
            guard case .appended = try session.ingest(
                adversarialCrop(document, y: offset, height: viewportHeight)
            ) else {
                return XCTFail("Expected capture to resume cleanly at offset \(offset).")
            }
        }

        let output = try session.finish()
        let expected = adversarialCrop(
            document,
            y: 0,
            height: try XCTUnwrap(resumedOffsets.last) + viewportHeight
        )
        assertPixelEquivalent(output, expected)
    }

    func testFastVariableScrollOffsetsReconstructTheDocumentWithoutSlices() throws {
        let document = adversarialNoiseDocument(width: 128, height: 900)
        let viewportHeight = 192
        let offsets = [0, 13, 79, 104, 193, 227, 352, 399, 527]
        let session = ScrollingCaptureSession(configuration: adversarialConfiguration())

        for (index, offset) in offsets.enumerated() {
            let decision = try session.ingest(
                adversarialCrop(document, y: offset, height: viewportHeight)
            )
            switch (index, decision) {
            case (0, .started), (_, .appended):
                break
            default:
                XCTFail("Unexpected decision at variable offset \(offset): \(decision)")
            }
        }

        let output = try session.finish()
        let expected = adversarialCrop(
            document,
            y: 0,
            height: try XCTUnwrap(offsets.last) + viewportHeight
        )
        assertPixelEquivalent(output, expected)
    }

    func testConfiguredFixedHeaderAndFooterAppearExactlyOnce() throws {
        let document = adversarialPageDocument(width: 120, height: 620)
        let viewportHeight = 180
        let headerHeight = 18
        let footerHeight = 14
        let offsets = [0, 37, 91, 156, 238]
        var configuration = adversarialConfiguration()
        configuration.contentInsets = ScrollingCaptureContentInsets(
            top: headerHeight,
            bottom: footerHeight
        )
        let session = ScrollingCaptureSession(configuration: configuration)

        for offset in offsets {
            _ = try session.ingest(
                adversarialStickyViewport(
                    document: document,
                    documentOffset: offset,
                    viewportHeight: viewportHeight,
                    headerHeight: headerHeight,
                    footerHeight: footerHeight
                )
            )
        }

        let output = try session.finish()
        let expected = adversarialExpectedStickyCapture(
            document: document,
            finalDocumentOffset: try XCTUnwrap(offsets.last),
            viewportHeight: viewportHeight,
            headerHeight: headerHeight,
            footerHeight: footerHeight
        )
        assertPixelEquivalent(output, expected)
    }

    func testDefaultCaptureDoesNotSpliceMovingContentWithStickyChrome() throws {
        let document = adversarialPageDocument(width: 120, height: 620)
        let viewportHeight = 180
        let headerHeight = 18
        let footerHeight = 14
        let offsets = [0, 41, 96, 163, 231]
        let session = ScrollingCaptureSession(configuration: adversarialConfiguration())

        for offset in offsets {
            let decision = try session.ingest(
                adversarialStickyViewport(
                    document: document,
                    documentOffset: offset,
                    viewportHeight: viewportHeight,
                    headerHeight: headerHeight,
                    footerHeight: footerHeight
                )
            )
            if case .rejected = decision {
                return XCTFail(
                    "Sticky application chrome must not prevent reliable scrolling registration at offset \(offset): \(decision)"
                )
            }
        }

        let output = try session.finish()
        let expected = adversarialExpectedStickyCapture(
            document: document,
            finalDocumentOffset: try XCTUnwrap(offsets.last),
            viewportHeight: viewportHeight,
            headerHeight: headerHeight,
            footerHeight: footerHeight
        )
        assertPixelEquivalent(
            output,
            expected,
            message: "Sticky header/footer pixels were repeated into the moving document."
        )
    }

    func testLargeImageCrossingSeveralSeamsIsNeverCutOrRepeated() throws {
        let document = adversarialImageHeavyDocument(width: 132, height: 760)
        let viewportHeight = 190
        // Every boundary falls inside either an image or a text row.
        let offsets = [0, 31, 86, 143, 219, 301, 408]
        let session = ScrollingCaptureSession(configuration: adversarialConfiguration())

        for offset in offsets {
            _ = try session.ingest(
                adversarialCrop(document, y: offset, height: viewportHeight)
            )
        }

        let output = try session.finish()
        let expected = adversarialCrop(
            document,
            y: 0,
            height: try XCTUnwrap(offsets.last) + viewportHeight
        )
        assertPixelEquivalent(
            output,
            expected,
            message: "An image/text boundary was cut, repeated, or shifted at a seam."
        )
    }

    func testAmbiguousRepeatingRowsAreRejectedInsteadOfSilentlyMisaligned() throws {
        let document = adversarialPeriodicDocument(width: 112, height: 480, period: 24)
        let first = adversarialCrop(document, y: 0, height: 168)
        let ambiguous = adversarialCrop(document, y: 43, height: 168)
        let analyzer = ScrollingCaptureFrameAnalyzer(configuration: adversarialConfiguration())

        guard case let .rejected(reason) = analyzer.analyze(
            previous: first,
            current: ambiguous
        ) else {
            return XCTFail("A periodic page must not produce a guessed seam offset.")
        }
        guard case .noReliableAlignment = reason else {
            return XCTFail("Expected ambiguity rejection, got \(reason).")
        }

        let session = ScrollingCaptureSession(configuration: adversarialConfiguration())
        _ = try session.ingest(first)
        guard case .rejected = try session.ingest(ambiguous) else {
            return XCTFail("The session must preserve its last good reference on ambiguity.")
        }
        assertPixelEquivalent(try session.finish(), first)
    }

    func testReverseAndSubthresholdJitterCannotPoisonForwardCapture() throws {
        let document = adversarialNoiseDocument(width: 116, height: 620)
        let viewportHeight = 176
        let session = ScrollingCaptureSession(configuration: adversarialConfiguration())

        _ = try session.ingest(adversarialCrop(document, y: 0, height: viewportHeight))
        _ = try session.ingest(adversarialCrop(document, y: 54, height: viewportHeight))

        for jitteredOffset in [51, 53, 52, 55, 50] {
            let decision = try session.ingest(
                adversarialCrop(document, y: jitteredOffset, height: viewportHeight)
            )
            if case .appended = decision {
                XCTFail("Reverse/subthreshold jitter was mistaken for forward movement at \(jitteredOffset).")
            }
        }

        guard case .appended = try session.ingest(
            adversarialCrop(document, y: 119, height: viewportHeight)
        ) else {
            return XCTFail("Forward capture did not recover after reverse jitter.")
        }

        let output = try session.finish()
        let expected = adversarialCrop(document, y: 0, height: 119 + viewportHeight)
        assertPixelEquivalent(output, expected)
    }

    func testLargeGapIsRejectedWithoutPoisoningNextOverlappingFrame() throws {
        let document = adversarialNoiseDocument(width: 124, height: 860)
        let viewportHeight = 180
        var configuration = adversarialConfiguration()
        configuration.maximumScrollFraction = 0.70
        configuration.minimumOverlapFraction = 0.30
        let session = ScrollingCaptureSession(configuration: configuration)

        _ = try session.ingest(adversarialCrop(document, y: 0, height: viewportHeight))

        guard case .rejected = try session.ingest(
            adversarialCrop(document, y: 166, height: viewportHeight)
        ) else {
            return XCTFail("A frame without the configured overlap must be rejected.")
        }

        guard case .appended = try session.ingest(
            adversarialCrop(document, y: 73, height: viewportHeight)
        ) else {
            return XCTFail("A valid overlap did not recover after the gap.")
        }

        guard case .rejected = try session.ingest(
            adversarialCrop(document, y: 290, height: viewportHeight)
        ) else {
            return XCTFail("A second no-overlap jump must be rejected.")
        }

        guard case .appended = try session.ingest(
            adversarialCrop(document, y: 131, height: viewportHeight)
        ) else {
            return XCTFail("The second valid overlap did not recover after the gap.")
        }

        let output = try session.finish()
        let expected = adversarialCrop(document, y: 0, height: 131 + viewportHeight)
        assertPixelEquivalent(output, expected)
    }

    func testLateLoadingImageAtAStoppedOffsetIsNotInventedAsScrollMovement() throws {
        let document = adversarialPageDocument(width: 128, height: 520)
        let base = adversarialCrop(document, y: 0, height: 180)
        let loaded = adversarialReplacingRect(
            in: base,
            rect: CGRect(x: 18, y: 58, width: 92, height: 76),
            seed: 0xC1EA_5EED
        )
        let analyzer = ScrollingCaptureFrameAnalyzer(configuration: adversarialConfiguration())

        let result = analyzer.analyze(previous: base, current: loaded)
        if case let .aligned(alignment) = result {
            XCTFail(
                "A same-offset image update was invented as \(alignment.verticalOffset) px of scrolling."
            )
        }
    }

    func testTallRetinaViewportRefinesEverySeamAtNativeRowResolution() throws {
        let document = adversarialNoiseDocument(width: 144, height: 3_200)
        let viewportHeight = 1_500
        // None of these offsets maps cleanly through a 320-row coarse plane.
        let offsets = [0, 137, 389, 704, 1_003]
        var configuration = adversarialConfiguration()
        configuration.maximumAnalysisHeight = 320
        let session = ScrollingCaptureSession(configuration: configuration)

        for (index, offset) in offsets.enumerated() {
            let frame = adversarialCrop(document, y: offset, height: viewportHeight)
            let decision = try session.ingest(frame)
            switch (index, decision) {
            case (0, .started), (_, .appended):
                break
            default:
                return XCTFail("Native-row alignment failed at offset \(offset): \(decision)")
            }
        }

        let finalFrame = adversarialCrop(
            document,
            y: try XCTUnwrap(offsets.last),
            height: viewportHeight
        )
        guard case .duplicate = try session.ingest(finalFrame) else {
            return XCTFail("The final Retina strip did not settle.")
        }

        let output = try session.finish()
        let expected = adversarialCrop(
            document,
            y: 0,
            height: try XCTUnwrap(offsets.last) + viewportHeight
        )
        assertPixelEquivalent(
            output,
            expected,
            message: "Coarse registration rounding cut or repeated native Retina rows."
        )
    }
}

private func adversarialConfiguration() -> ScrollingCaptureConfiguration {
    var configuration = ScrollingCaptureConfiguration()
    configuration.maximumAnalysisWidth = 192
    configuration.maximumAnalysisHeight = 320
    configuration.maximumOutputHeight = 20_000
    configuration.maximumOutputPixelCount = 40_000_000
    return configuration
}

private func adversarialNoiseDocument(width: Int, height: Int) -> CGImage {
    adversarialImage(width: width, height: height) { x, y in
        adversarialNoise(x: x, y: y, seed: 0x51C0_11A7)
    }
}

private func adversarialPageDocument(width: Int, height: Int) -> CGImage {
    adversarialImage(width: width, height: height) { x, y in
        let section = y / 96
        let sectionY = y % 96

        if sectionY < 9, x > 8, x < width - 8 {
            return UInt8(26 + (section * 19) % 60)
        }
        if (18..<23).contains(sectionY), x > 12, x < width - 20 - (section * 7) % 28 {
            return UInt8(58 + (section * 13) % 90)
        }
        if (31..<35).contains(sectionY), x > 12, x < width - 42 {
            return 118
        }
        if (48..<82).contains(sectionY), x > 15, x < width - 15 {
            return adversarialNoise(x: x / 2, y: y / 2, seed: UInt64(section + 1))
        }

        // Real pages contain long near-white areas. A very small stable texture
        // avoids making the synthetic fixture depend on Core Graphics rounding.
        return UInt8(246 + Int(adversarialNoise(x: x, y: y, seed: 7) % 7))
    }
}

private func adversarialImageHeavyDocument(width: Int, height: Int) -> CGImage {
    adversarialImage(width: width, height: height) { x, y in
        if (72..<338).contains(y), (9..<(width - 9)).contains(x) {
            let tile = ((x / 11) + (y / 13)) % 2
            let texture = Int(adversarialNoise(x: x, y: y, seed: 0x1A6E)) % 46
            return UInt8(tile == 0 ? 25 + texture : 178 + texture)
        }
        if (382..<566).contains(y), (17..<(width - 17)).contains(x) {
            return adversarialNoise(x: x * 3, y: y * 5, seed: 0xB10C)
        }
        if y % 43 < 5, x > 7, x < width - 24 - (y / 43) % 31 {
            return UInt8(30 + (y / 43) * 9)
        }
        return UInt8(242 + Int(adversarialNoise(x: x, y: y, seed: 0xFA6E) % 11))
    }
}

private func adversarialPeriodicDocument(width: Int, height: Int, period: Int) -> CGImage {
    adversarialImage(width: width, height: height) { x, y in
        let repeatedY = y % period
        if repeatedY < 4, x > 8, x < width - 8 {
            return UInt8(35 + (x * 17) % 80)
        }
        if (9..<12).contains(repeatedY), x > 16, x < width - 28 {
            return 105
        }
        return 244
    }
}

private func adversarialStickyViewport(
    document: CGImage,
    documentOffset: Int,
    viewportHeight: Int,
    headerHeight: Int,
    footerHeight: Int
) -> CGImage {
    let pixels = adversarialGrayscalePixels(document)
    return adversarialImage(width: document.width, height: viewportHeight) { x, y in
        if y < headerHeight {
            if y < 4 { return 18 }
            if y > 8, y < 13, x > 7, x < 42 { return 72 }
            return 232
        }
        if y >= viewportHeight - footerHeight {
            if y == viewportHeight - footerHeight { return 92 }
            return UInt8(218 + (x / 13) % 16)
        }
        let documentY = documentOffset + y - headerHeight
        return pixels[documentY * document.width + x]
    }
}

private func adversarialExpectedStickyCapture(
    document: CGImage,
    finalDocumentOffset: Int,
    viewportHeight: Int,
    headerHeight: Int,
    footerHeight: Int
) -> CGImage {
    let bodyHeight = viewportHeight - headerHeight - footerHeight
    let height = headerHeight + bodyHeight + finalDocumentOffset + footerHeight
    let documentPixels = adversarialGrayscalePixels(document)
    return adversarialImage(width: document.width, height: height) { x, y in
        if y < headerHeight {
            if y < 4 { return 18 }
            if y > 8, y < 13, x > 7, x < 42 { return 72 }
            return 232
        }
        if y >= height - footerHeight {
            if y == height - footerHeight { return 92 }
            return UInt8(218 + (x / 13) % 16)
        }
        let documentY = y - headerHeight
        return documentPixels[documentY * document.width + x]
    }
}

private func adversarialReplacingRect(
    in image: CGImage,
    rect: CGRect,
    seed: UInt64
) -> CGImage {
    let source = adversarialGrayscalePixels(image)
    return adversarialImage(width: image.width, height: image.height) { x, y in
        if rect.contains(CGPoint(x: x, y: y)) {
            return adversarialNoise(x: x, y: y, seed: seed)
        }
        return source[y * image.width + x]
    }
}

private func adversarialNoise(x: Int, y: Int, seed: UInt64) -> UInt8 {
    var value = UInt64(x + 1) &* 0x9E37_79B1_85EB_CA87
    value ^= UInt64(y + 1) &* 0xC2B2_AE3D_27D4_EB4F
    value ^= seed &* 0x1656_67B1_9E37_79F9
    value ^= value >> 30
    value &*= 0xBF58_476D_1CE4_E5B9
    value ^= value >> 27
    value &*= 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return UInt8(truncatingIfNeeded: value >> 24)
}

private func adversarialCrop(_ image: CGImage, y: Int, height: Int) -> CGImage {
    guard let cropped = image.cropping(
        to: CGRect(x: 0, y: y, width: image.width, height: height)
    ) else {
        XCTFail("Could not crop adversarial fixture at y=\(y), height=\(height).")
        return image
    }
    return cropped
}

private func adversarialImage(
    width: Int,
    height: Int,
    value: (Int, Int) -> UInt8
) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let component = value(x, y)
            let index = (y * width + x) * 4
            bytes[index] = component
            bytes[index + 1] = component
            bytes[index + 2] = component
        }
    }

    let data = Data(bytes)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func adversarialGrayscalePixels(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
}

private func assertPixelEquivalent(
    _ actual: CGImage,
    _ expected: CGImage,
    message: String = "The assembled capture differs from the source document.",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.width, expected.width, message, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, message, file: file, line: line)
    guard actual.width == expected.width, actual.height == expected.height else { return }

    let actualPixels = adversarialGrayscalePixels(actual)
    let expectedPixels = adversarialGrayscalePixels(expected)
    var differingPixelCount = 0
    var largestDifference = 0
    for (actualPixel, expectedPixel) in zip(actualPixels, expectedPixels) {
        let difference = abs(Int(actualPixel) - Int(expectedPixel))
        if difference > 1 {
            differingPixelCount += 1
            largestDifference = max(largestDifference, difference)
        }
    }

    XCTAssertEqual(
        differingPixelCount,
        0,
        "\(message) \(differingPixelCount) pixels differ; maximum luma error \(largestDifference).",
        file: file,
        line: line
    )
}
