import CoreGraphics
import XCTest

@testable import clearshotX

final class ScrollingCaptureFrameAnalyzerTests: XCTestCase {
    func testFindsDeterministicVerticalScrollOffset() throws {
        let document = makeDocument(width: 72, height: 260)
        let first = try crop(document, y: 0, height: 120)
        let second = try crop(document, y: 37, height: 120)
        let analyzer = ScrollingCaptureFrameAnalyzer(configuration: testConfiguration())

        guard case let .aligned(alignment) = analyzer.analyze(
            previous: first,
            current: second
        ) else {
            return XCTFail("Expected the frames to align.")
        }

        XCTAssertEqual(alignment.verticalOffset, 37, accuracy: 1)
        XCTAssertLessThan(alignment.difference, 0.01)
        XCTAssertGreaterThan(alignment.confidence, 0.5)
    }

    func testRejectsIdenticalFrameAsDuplicate() throws {
        let document = makeDocument(width: 72, height: 180)
        let frame = try crop(document, y: 12, height: 120)
        let analyzer = ScrollingCaptureFrameAnalyzer(configuration: testConfiguration())

        guard case let .duplicate(difference) = analyzer.analyze(
            previous: frame,
            current: frame
        ) else {
            return XCTFail("Expected an identical frame to be ignored.")
        }

        XCTAssertEqual(difference, 0, accuracy: 0.000_001)
    }

    func testRejectsAmbiguousFlatFrames() throws {
        let first = solidImage(width: 72, height: 120, value: 90)
        let second = solidImage(width: 72, height: 120, value: 130)
        let analyzer = ScrollingCaptureFrameAnalyzer(configuration: testConfiguration())

        guard case let .rejected(reason) = analyzer.analyze(
            previous: first,
            current: second
        ) else {
            return XCTFail("Expected flat frames to be ambiguous.")
        }

        guard case .noReliableAlignment = reason else {
            return XCTFail("Expected a confidence rejection, got \(reason).")
        }
    }
}

final class ScrollingCaptureSessionTests: XCTestCase {
    func testSessionBuildsDocumentWithoutDuplicateOverlap() throws {
        let document = makeDocument(width: 64, height: 280)
        let first = try crop(document, y: 0, height: 120)
        let second = try crop(document, y: 32, height: 120)
        let third = try crop(document, y: 73, height: 120)
        let session = ScrollingCaptureSession(configuration: testConfiguration())

        guard case .started = try session.ingest(first) else {
            return XCTFail("Expected the session to start.")
        }
        guard case .appended = try session.ingest(second) else {
            return XCTFail("Expected the second frame to append.")
        }
        guard case let .appended(progress) = try session.ingest(third) else {
            return XCTFail("Expected the third frame to append.")
        }

        XCTAssertEqual(progress.acceptedFrameCount, 3)
        XCTAssertEqual(progress.outputPixelHeight, 193, accuracy: 2)

        let output = try session.finish()
        XCTAssertEqual(output.width, 64)
        XCTAssertEqual(output.height, progress.outputPixelHeight)

        let expected = try crop(document, y: 0, height: output.height)
        XCTAssertLessThan(meanPixelDifference(output, expected), 0.005)
    }

    func testSessionKeepsFixedHeaderAndLatestFooterOnce() throws {
        let document = makeDocument(width: 64, height: 260)
        let first = viewport(
            document: document,
            documentOffset: 0,
            height: 120,
            header: 12,
            footer: 10,
            footerValue: 40
        )
        let second = viewport(
            document: document,
            documentOffset: 31,
            height: 120,
            header: 12,
            footer: 10,
            footerValue: 220
        )
        var configuration = testConfiguration()
        configuration.contentInsets = ScrollingCaptureContentInsets(top: 12, bottom: 10)
        let session = ScrollingCaptureSession(configuration: configuration)

        _ = try session.ingest(first)
        guard case let .appended(progress) = try session.ingest(second) else {
            return XCTFail("Expected the content viewport to align.")
        }

        let output = try session.finish()
        XCTAssertEqual(output.height, progress.outputPixelHeight)
        XCTAssertEqual(pixelValue(output, x: 2, yFromTop: 2), 15, accuracy: 2)
        XCTAssertEqual(pixelValue(output, x: 2, yFromTop: output.height - 2), 220, accuracy: 2)
    }

    func testSessionStopsBeforeConfiguredOutputLimit() throws {
        let document = makeDocument(width: 64, height: 220)
        let first = try crop(document, y: 0, height: 100)
        let second = try crop(document, y: 30, height: 100)
        var configuration = testConfiguration()
        configuration.maximumOutputHeight = 120
        configuration.maximumOutputPixelCount = 64 * 120
        let session = ScrollingCaptureSession(configuration: configuration)

        _ = try session.ingest(first)
        guard case let .reachedOutputLimit(progress) = try session.ingest(second) else {
            return XCTFail("Expected the configured limit to stop the append.")
        }

        XCTAssertEqual(progress.acceptedFrameCount, 1)
        XCTAssertEqual(try session.finish().height, 100)
    }

    func testSessionRejectsViewportResize() throws {
        let session = ScrollingCaptureSession(configuration: testConfiguration())
        _ = try session.ingest(makeDocument(width: 64, height: 100))

        XCTAssertThrowsError(try session.ingest(makeDocument(width: 62, height: 100))) { error in
            guard case ScrollingCaptureError.inconsistentFrameSize = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

private func testConfiguration() -> ScrollingCaptureConfiguration {
    var configuration = ScrollingCaptureConfiguration()
    configuration.maximumAnalysisWidth = 128
    configuration.maximumAnalysisHeight = 240
    configuration.minimumScrollDistance = 4
    configuration.minimumAlignmentConfidence = 0.08
    configuration.maximumAlignmentDifference = 0.10
    configuration.maximumOutputPixelCount = 20_000_000
    return configuration
}

private func makeDocument(width: Int, height: Int) -> CGImage {
    rgbaImage(width: width, height: height) { x, y in
        let value = UInt8((y &* 47 &+ x &* 29 &+ (y / 7) &* 83 &+ (x / 5) &* 31) % 256)
        return value
    }
}

private func solidImage(width: Int, height: Int, value: UInt8) -> CGImage {
    rgbaImage(width: width, height: height) { _, _ in value }
}

private func viewport(
    document: CGImage,
    documentOffset: Int,
    height: Int,
    header: Int,
    footer: Int,
    footerValue: UInt8
) -> CGImage {
    let documentPixels = grayscalePixels(document)
    return rgbaImage(width: document.width, height: height) { x, y in
        if y < header { return 15 }
        if y >= height - footer { return footerValue }
        let sourceY = documentOffset + y - header
        return documentPixels[sourceY * document.width + x]
    }
}

private func crop(_ image: CGImage, y: Int, height: Int) throws -> CGImage {
    try XCTUnwrap(
        image.cropping(
            to: CGRect(x: 0, y: y, width: image.width, height: height)
        )
    )
}

private func rgbaImage(
    width: Int,
    height: Int,
    value: (Int, Int) -> UInt8
) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let component = value(x, y)
            let offset = (y * width + x) * 4
            bytes[offset] = component
            bytes[offset + 1] = component
            bytes[offset + 2] = component
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

private func grayscalePixels(_ image: CGImage) -> [UInt8] {
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
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
}

private func meanPixelDifference(_ lhs: CGImage, _ rhs: CGImage) -> Double {
    guard lhs.width == rhs.width, lhs.height == rhs.height else { return 1 }
    let lhsPixels = grayscalePixels(lhs)
    let rhsPixels = grayscalePixels(rhs)
    let total = zip(lhsPixels, rhsPixels).reduce(0) { partial, pair in
        partial + abs(Int(pair.0) - Int(pair.1))
    }
    return Double(total) / Double(lhsPixels.count * 255)
}

private func pixelValue(_ image: CGImage, x: Int, yFromTop: Int) -> Double {
    Double(grayscalePixels(image)[yFromTop * image.width + x])
}
