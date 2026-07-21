import CoreGraphics
import CoreVideo
import ScreenCaptureKit
import XCTest

@testable import clearshotX

final class ScrollingCaptureRegionResolverTests: XCTestCase {
    func testConvertsAppKitGlobalRegionToDisplayLocalTopLeftCoordinates() throws {
        let display = ScrollingCaptureDisplayDescriptor(
            displayID: 42,
            frame: CGRect(x: 1_000, y: -200, width: 800, height: 600),
            pointPixelScale: 2
        )

        let geometry = try ScrollingCaptureRegionResolver.resolve(
            selectedRegion: CGRect(x: 1_100, y: 0, width: 300, height: 150),
            displays: [display]
        )

        XCTAssertEqual(geometry.displayID, 42)
        XCTAssertEqual(geometry.sourceRect, CGRect(x: 100, y: 250, width: 300, height: 150))
        XCTAssertEqual(geometry.globalRect, CGRect(x: 1_100, y: 0, width: 300, height: 150))
        XCTAssertEqual(geometry.pixelWidth, 600)
        XCTAssertEqual(geometry.pixelHeight, 300)
    }

    func testPixelAlignsFractionalRetinaSelectionOutward() throws {
        let display = ScrollingCaptureDisplayDescriptor(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            pointPixelScale: 2
        )

        let geometry = try ScrollingCaptureRegionResolver.resolve(
            selectedRegion: CGRect(x: 10.2, y: 20.2, width: 100.1, height: 80.1),
            displays: [display]
        )

        XCTAssertEqual(geometry.sourceRect.minX, 10, accuracy: 0.001)
        XCTAssertEqual(geometry.sourceRect.maxX, 110.5, accuracy: 0.001)
        XCTAssertEqual(geometry.sourceRect.minY, 499.5, accuracy: 0.001)
        XCTAssertEqual(geometry.sourceRect.maxY, 580, accuracy: 0.001)
        XCTAssertEqual(geometry.pixelWidth, 201)
        XCTAssertEqual(geometry.pixelHeight, 161)
    }

    func testRejectsSelectionSpanningDisplays() {
        let displays = [
            ScrollingCaptureDisplayDescriptor(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                pointPixelScale: 1
            ),
            ScrollingCaptureDisplayDescriptor(
                displayID: 2,
                frame: CGRect(x: 800, y: 0, width: 800, height: 600),
                pointPixelScale: 2
            ),
        ]

        XCTAssertThrowsError(
            try ScrollingCaptureRegionResolver.resolve(
                selectedRegion: CGRect(x: 700, y: 100, width: 200, height: 300),
                displays: displays
            )
        ) { error in
            XCTAssertEqual(
                error as? ScrollingCaptureFrameSourceError,
                .regionSpansMultipleDisplays
            )
        }
    }
}

final class ScrollingCaptureFrameGateTests: XCTestCase {
    func testAcceptsOnlyCompleteExpectedSizeFrames() {
        XCTAssertTrue(
            ScrollingCaptureFrameGate.shouldProcess(
                status: .complete,
                pixelWidth: 600,
                pixelHeight: 400,
                expectedWidth: 600,
                expectedHeight: 400
            )
        )
        XCTAssertFalse(
            ScrollingCaptureFrameGate.shouldProcess(
                status: .idle,
                pixelWidth: 600,
                pixelHeight: 400,
                expectedWidth: 600,
                expectedHeight: 400
            )
        )
        XCTAssertFalse(
            ScrollingCaptureFrameGate.shouldProcess(
                status: .complete,
                pixelWidth: 599,
                pixelHeight: 400,
                expectedWidth: 600,
                expectedHeight: 400
            )
        )
    }
}

final class ScrollingCaptureFrameImagingTests: XCTestCase {
    func testConvertsBGRAPixelBufferPreservingChannelOrderAndValues() throws {
        let width = 2
        let height = 2
        var unmanagedBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &unmanagedBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(unmanagedBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)
        // In-memory byte order for kCVPixelFormatType_32BGRA is B, G, R, A.
        setBGRAPixel(base, row: 0, column: 0, bytesPerRow: bytesPerRow, b: 10, g: 20, r: 200)
        setBGRAPixel(base, row: 0, column: 1, bytesPerRow: bytesPerRow, b: 250, g: 5, r: 1)
        setBGRAPixel(base, row: 1, column: 0, bytesPerRow: bytesPerRow, b: 0, g: 0, r: 0)
        setBGRAPixel(base, row: 1, column: 1, bytesPerRow: bytesPerRow, b: 200, g: 150, r: 100)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let image = try XCTUnwrap(ScrollingCaptureFrameImaging.makeCGImage(from: pixelBuffer))
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)

        let rgba = try rgbaPixels(image)
        XCTAssertEqual(rgba[0], [200, 20, 10, 255], "top-left should read back as R,G,B,A")
        XCTAssertEqual(rgba[1], [1, 5, 250, 255], "top-right should read back as R,G,B,A")
        XCTAssertEqual(rgba[2], [0, 0, 0, 255], "bottom-left should read back as R,G,B,A")
        XCTAssertEqual(rgba[3], [100, 150, 200, 255], "bottom-right should read back as R,G,B,A")
    }

    private func setBGRAPixel(
        _ base: UnsafeMutablePointer<UInt8>,
        row: Int,
        column: Int,
        bytesPerRow: Int,
        b: UInt8,
        g: UInt8,
        r: UInt8,
        a: UInt8 = 255
    ) {
        let offset = row * bytesPerRow + column * 4
        base[offset] = b
        base[offset + 1] = g
        base[offset + 2] = r
        base[offset + 3] = a
    }

    private func rgbaPixels(_ image: CGImage) throws -> [[UInt8]] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(
            bytes.withUnsafeMutableBytes { buffer in
                CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            }
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { Array(bytes[$0..<$0 + 4]) }
    }
}

final class LatestValueProcessorTests: XCTestCase {
    func testBusyProcessorDropsStalePendingValues() {
        let startedFirst = expectation(description: "Started first value")
        let processedLatest = expectation(description: "Processed latest value")
        let releaseFirst = DispatchSemaphore(value: 0)
        let processed = LockedValues<Int>()

        let processor = LatestValueProcessor<Int>(
            queue: DispatchQueue(label: "LatestValueProcessorTests")
        ) { value in
            processed.append(value)

            if value == 1 {
                startedFirst.fulfill()
                _ = releaseFirst.wait(timeout: .now() + 2)
            } else if value == 3 {
                processedLatest.fulfill()
            }
        }

        processor.submit(1)
        wait(for: [startedFirst], timeout: 2)
        processor.submit(2)
        processor.submit(3)
        releaseFirst.signal()
        wait(for: [processedLatest], timeout: 2)

        XCTAssertEqual(processed.snapshot(), [1, 3])
    }
}

private nonisolated final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
