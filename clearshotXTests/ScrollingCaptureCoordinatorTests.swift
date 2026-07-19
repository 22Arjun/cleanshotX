import CoreGraphics
import CoreMedia
import XCTest

@testable import clearshotX

final class ScrollingCaptureHUDReducerTests: XCTestCase {
    func testShowsGuidanceOnlyAfterARejectionStreakAndRecoversOnAppend() {
        var state = ScrollingCaptureHUDState.starting
        var consecutiveRejections = 0
        let progress = ScrollingCaptureProgress(
            acceptedFrameCount: 1,
            rejectedFrameCount: 1,
            outputPixelWidth: 600,
            outputPixelHeight: 400,
            lastAlignment: nil
        )

        for index in 1...ScrollingCaptureHUDReducer.guidanceRejectionThreshold {
            state = ScrollingCaptureHUDReducer.applying(
                .rejected(.insufficientOverlap, progress),
                to: state,
                consecutiveRejections: &consecutiveRejections
            )
            XCTAssertEqual(
                state.phase,
                index == ScrollingCaptureHUDReducer.guidanceRejectionThreshold
                    ? .guidance
                    : .capturing
            )
        }

        state = ScrollingCaptureHUDReducer.applying(
            .appended(progress),
            to: state,
            consecutiveRejections: &consecutiveRejections
        )

        XCTAssertEqual(state.phase, .capturing)
        XCTAssertEqual(consecutiveRejections, 0)
        XCTAssertEqual(state.dimensionsText, "600 × 400 px")
    }
}

@MainActor
final class ScrollingCaptureCoordinatorTests: XCTestCase {
    func testCancelStopsSourceDismissesHUDAndReturnsNoCapture() async throws {
        let source = FakeScrollingFrameSource()
        let hud = FakeScrollingHUDPresenter()
        let store = FakeCaptureStore()
        let coordinator = ScrollingCaptureCoordinator(
            frameSource: source,
            captureStore: store,
            hudPresenter: hud
        )
        let completed = expectation(description: "Capture cancelled")
        var receivedCapture: CaptureResult?

        try await coordinator.start(
            selectedRegion: CGRect(x: 10, y: 20, width: 300, height: 200)
        ) { result in
            if case let .success(capture) = result {
                receivedCapture = capture
            }
            completed.fulfill()
        }

        XCTAssertEqual(coordinator.phase, .capturing)
        XCTAssertEqual(hud.showCount, 1)

        coordinator.cancel()
        await fulfillment(of: [completed], timeout: 2)

        XCTAssertNil(receivedCapture)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(store.storeCount, 0)
        XCTAssertEqual(hud.dismissCount, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testFinishStoresFirstFrameAndReturnsNormalCaptureResult() async throws {
        let source = FakeScrollingFrameSource()
        let hud = FakeScrollingHUDPresenter()
        let store = FakeCaptureStore()
        let coordinator = ScrollingCaptureCoordinator(
            frameSource: source,
            captureStore: store,
            hudPresenter: hud
        )
        let completed = expectation(description: "Capture finished")
        var receivedResult: Result<CaptureResult?, Error>?

        try await coordinator.start(
            selectedRegion: CGRect(x: 10, y: 20, width: 4, height: 3)
        ) { result in
            receivedResult = result
            completed.fulfill()
        }

        source.emit(image: makeSolidImage(width: 4, height: 3))
        await Task.yield()
        XCTAssertEqual(hud.viewModel?.state.acceptedFrameCount, 1)

        coordinator.finish()
        await fulfillment(of: [completed], timeout: 2)

        guard case let .success(capture?) = receivedResult else {
            return XCTFail("Expected a stored capture result")
        }
        XCTAssertEqual(capture.pixelWidth, 4)
        XCTAssertEqual(capture.pixelHeight, 3)
        XCTAssertEqual(store.storeCount, 1)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }
}

private nonisolated final class FakeScrollingFrameSource:
    ScrollingCaptureFrameSourcing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var frameHandler: (@Sendable (ScrollingCaptureStreamFrame) -> Void)?
    private var stops = 0

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    func start(
        selectedRegion: CGRect,
        onFrame: @escaping @Sendable (ScrollingCaptureStreamFrame) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) async throws -> ScrollingCaptureRegionGeometry {
        setFrameHandler(onFrame)
        return ScrollingCaptureRegionGeometry(
            displayID: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            globalRect: selectedRegion,
            sourceRect: selectedRegion,
            pointPixelScale: 1,
            pixelWidth: Int(selectedRegion.width),
            pixelHeight: Int(selectedRegion.height)
        )
    }

    func stop() async throws {
        recordStop()
    }

    func setFrameDeliveryEnabled(_ isEnabled: Bool) {}

    private func setFrameHandler(
        _ frameHandler: @escaping @Sendable (ScrollingCaptureStreamFrame) -> Void
    ) {
        lock.lock()
        self.frameHandler = frameHandler
        lock.unlock()
    }

    private func recordStop() {
        lock.lock()
        stops += 1
        frameHandler = nil
        lock.unlock()
    }

    func emit(image: CGImage) {
        lock.lock()
        let frameHandler = self.frameHandler
        lock.unlock()
        frameHandler?(
            ScrollingCaptureStreamFrame(
                image: image,
                presentationTime: .zero,
                dirtyRects: [],
                contentRect: nil,
                scaleFactor: 1
            )
        )
    }
}

@MainActor
private final class FakeScrollingHUDPresenter: ScrollingCaptureHUDPresenting {
    private(set) var showCount = 0
    private(set) var dismissCount = 0
    private(set) var viewModel: ScrollingCaptureHUDViewModel?

    func show(
        viewModel: ScrollingCaptureHUDViewModel,
        adjacentTo selectedRegion: CGRect
    ) {
        showCount += 1
        self.viewModel = viewModel
    }

    func dismiss() {
        dismissCount += 1
        viewModel = nil
    }
}

@MainActor
private final class FakeCaptureStore: CaptureStoring {
    private(set) var storeCount = 0

    func store(_ image: CGImage) throws -> StoredCapture {
        storeCount += 1
        return StoredCapture(
            fileURL: URL(fileURLWithPath: "/tmp/scrolling-capture.png"),
            dragFileURL: URL(fileURLWithPath: "/tmp/scrolling-capture.png")
        )
    }

    func removeCapture(at url: URL, dragFileURL: URL?) throws {}
    func removeExpiredCaptures() throws {}
}

private func makeSolidImage(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
