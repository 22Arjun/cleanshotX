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

final class ScrollingCapturePreviewBuilderTests: XCTestCase {
    func testShortPageKeepsItsNaturalAspectWithoutUpscaling() throws {
        let builder = ScrollingCapturePreviewBuilder(
            maximumSize: CGSize(width: 240, height: 420),
            contentInsets: .zero
        )
        let frame = makeSolidImage(width: 120, height: 80)
        let progress = ScrollingCaptureProgress(
            acceptedFrameCount: 1,
            rejectedFrameCount: 0,
            outputPixelWidth: 120,
            outputPixelHeight: 80,
            lastAlignment: nil
        )

        let preview = try XCTUnwrap(builder.apply(frame: frame, decision: .started(progress)))

        XCTAssertEqual(preview.width, 120)
        XCTAssertEqual(preview.height, 80)
    }

    func testGrowingPageAlwaysRepresentsWholeDocumentWithinBoundedPixels() throws {
        let maximumSize = CGSize(width: 100, height: 160)
        let builder = ScrollingCapturePreviewBuilder(
            maximumSize: maximumSize,
            contentInsets: .zero
        )
        let frame = makeSolidImage(width: 200, height: 120)
        let started = ScrollingCaptureProgress(
            acceptedFrameCount: 1,
            rejectedFrameCount: 0,
            outputPixelWidth: 200,
            outputPixelHeight: 120,
            lastAlignment: nil
        )
        _ = try XCTUnwrap(builder.apply(frame: frame, decision: .started(started)))

        var latestPreview: CGImage?
        for index in 1...10 {
            let outputHeight = 120 + index * 60
            let progress = ScrollingCaptureProgress(
                acceptedFrameCount: index + 1,
                rejectedFrameCount: 0,
                outputPixelWidth: 200,
                outputPixelHeight: outputHeight,
                lastAlignment: ScrollingCaptureAlignment(
                    verticalOffset: 60,
                    difference: 0,
                    confidence: 1
                )
            )
            latestPreview = builder.apply(frame: frame, decision: .appended(progress))
        }

        let preview = try XCTUnwrap(latestPreview)
        XCTAssertLessThanOrEqual(preview.width, Int(maximumSize.width))
        XCTAssertLessThanOrEqual(preview.height, Int(maximumSize.height))

        let expectedAspect = 200.0 / 720.0
        let actualAspect = Double(preview.width) / Double(preview.height)
        XCTAssertEqual(actualAspect, expectedAspect, accuracy: 0.015)
    }

    func testCoalescedProgressUsesLatestViewportWithoutLosingDocumentAspect() throws {
        let builder = ScrollingCapturePreviewBuilder(
            maximumSize: CGSize(width: 100, height: 160),
            contentInsets: .zero
        )
        let frame = makeSolidImage(width: 200, height: 120)
        let started = ScrollingCaptureProgress(
            acceptedFrameCount: 1,
            rejectedFrameCount: 0,
            outputPixelWidth: 200,
            outputPixelHeight: 120,
            lastAlignment: nil
        )
        _ = try XCTUnwrap(builder.apply(frame: frame, decision: .started(started)))

        // Represents two 60-pixel updates coalesced into one request. The latest
        // viewport still contains the complete newly exposed range.
        let coalesced = ScrollingCaptureProgress(
            acceptedFrameCount: 3,
            rejectedFrameCount: 0,
            outputPixelWidth: 200,
            outputPixelHeight: 240,
            lastAlignment: ScrollingCaptureAlignment(
                verticalOffset: 60,
                difference: 0,
                confidence: 1
            )
        )
        let preview = try XCTUnwrap(
            builder.apply(frame: frame, decision: .appended(coalesced))
        )

        XCTAssertEqual(
            Double(preview.width) / Double(preview.height),
            200.0 / 240.0,
            accuracy: 0.015
        )
    }

    func testUnrecoverablePreviewGapFreezesInsteadOfStretchingPixels() throws {
        let builder = ScrollingCapturePreviewBuilder(
            maximumSize: CGSize(width: 100, height: 160),
            contentInsets: .zero
        )
        let frame = makeSolidImage(width: 200, height: 120)
        let started = ScrollingCaptureProgress(
            acceptedFrameCount: 1,
            rejectedFrameCount: 0,
            outputPixelWidth: 200,
            outputPixelHeight: 120,
            lastAlignment: nil
        )
        _ = try XCTUnwrap(builder.apply(frame: frame, decision: .started(started)))

        let unrecoverable = ScrollingCaptureProgress(
            acceptedFrameCount: 4,
            rejectedFrameCount: 0,
            outputPixelWidth: 200,
            outputPixelHeight: 300,
            lastAlignment: ScrollingCaptureAlignment(
                verticalOffset: 60,
                difference: 0,
                confidence: 1
            )
        )
        XCTAssertNil(builder.apply(frame: frame, decision: .appended(unrecoverable)))

        // A later bridge from the still-truthful prefix remains possible because
        // the rejected HUD update did not advance the builder's source position.
        let recoverable = ScrollingCaptureProgress(
            acceptedFrameCount: 2,
            rejectedFrameCount: 0,
            outputPixelWidth: 200,
            outputPixelHeight: 180,
            lastAlignment: ScrollingCaptureAlignment(
                verticalOffset: 60,
                difference: 0,
                confidence: 1
            )
        )
        XCTAssertNotNil(builder.apply(frame: frame, decision: .appended(recoverable)))
    }
}

@MainActor
final class ScrollingCaptureCoordinatorTests: XCTestCase {
    func testAutomaticCaptureWaitsForExplicitStartButton() async throws {
        let autoCapture = FakeAutoCapture()
        let hud = FakeScrollingHUDPresenter()
        let coordinator = ScrollingCaptureCoordinator(
            autoCapture: autoCapture,
            captureStore: FakeCaptureStore(),
            hudPresenter: hud,
            postEventAccessProvider: { true }
        )
        let started = expectation(description: "Auto capture started")
        let completed = expectation(description: "Started capture cancelled")
        autoCapture.onStart = {
            started.fulfill()
        }

        try await coordinator.start(
            selectedRegion: CGRect(x: 10, y: 20, width: 300, height: 200)
        ) { _ in
            completed.fulfill()
        }

        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(hud.viewModel?.state.phase, .ready)
        XCTAssertEqual(autoCapture.startCount, 0)

        hud.viewModel?.startAutoScroll()
        await fulfillment(of: [started], timeout: 2)
        await Task.yield()

        XCTAssertEqual(autoCapture.startCount, 1)
        XCTAssertEqual(coordinator.phase, .capturing)

        coordinator.cancel()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testCancelBeforeAutoScrollStartsDismissesWithoutStartingCapture() async throws {
        let autoCapture = FakeAutoCapture()
        let hud = FakeScrollingHUDPresenter()
        let coordinator = ScrollingCaptureCoordinator(
            autoCapture: autoCapture,
            captureStore: FakeCaptureStore(),
            hudPresenter: hud,
            postEventAccessProvider: { true }
        )
        let completed = expectation(description: "Ready capture cancelled")
        var receivedCapture: CaptureResult?

        try await coordinator.start(
            selectedRegion: CGRect(x: 10, y: 20, width: 300, height: 200)
        ) { result in
            if case let .success(capture) = result {
                receivedCapture = capture
            }
            completed.fulfill()
        }

        hud.viewModel?.cancel()
        await fulfillment(of: [completed], timeout: 2)

        XCTAssertNil(receivedCapture)
        XCTAssertEqual(autoCapture.startCount, 0)
        XCTAssertEqual(hud.dismissCount, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testManualScrollCanBeChosenWhenAutoScrollIsAvailable() async throws {
        let source = FakeScrollingFrameSource()
        let autoCapture = FakeAutoCapture()
        let hud = FakeScrollingHUDPresenter()
        let store = FakeCaptureStore()
        let coordinator = ScrollingCaptureCoordinator(
            frameSource: source,
            autoCapture: autoCapture,
            captureStore: store,
            hudPresenter: hud,
            postEventAccessProvider: { true }
        )
        let started = expectation(description: "Manual source started")
        let completed = expectation(description: "Manual capture finished")
        var receivedResult: Result<CaptureResult?, Error>?
        source.onStart = {
            started.fulfill()
        }

        try await coordinator.start(
            selectedRegion: CGRect(x: 10, y: 20, width: 4, height: 3)
        ) { result in
            receivedResult = result
            completed.fulfill()
        }

        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(source.startCount, 0)
        XCTAssertEqual(autoCapture.startCount, 0)

        hud.viewModel?.startManualScroll()
        await fulfillment(of: [started], timeout: 2)
        await Task.yield()

        XCTAssertEqual(coordinator.phase, .capturing)
        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(autoCapture.startCount, 0)

        source.emit(image: makeSolidImage(width: 4, height: 3))
        await Task.yield()
        XCTAssertEqual(hud.viewModel?.state.mode, .manual)
        XCTAssertEqual(hud.viewModel?.state.acceptedFrameCount, 1)

        coordinator.finish()
        await fulfillment(of: [completed], timeout: 2)

        guard case let .success(capture?) = receivedResult else {
            return XCTFail("Expected a stored manual capture")
        }
        XCTAssertEqual(capture.pixelWidth, 4)
        XCTAssertEqual(capture.pixelHeight, 3)
        XCTAssertEqual(store.storeCount, 1)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testAutoScrollPermissionIsRequestedOnlyWhenStartButtonIsPressed() async throws {
        let autoCapture = FakeAutoCapture()
        let hud = FakeScrollingHUDPresenter()
        let coordinator = ScrollingCaptureCoordinator(
            autoCapture: autoCapture,
            captureStore: FakeCaptureStore(),
            hudPresenter: hud,
            postEventAccessProvider: { false }
        )
        let completed = expectation(description: "Permission denied")
        var receivedError: Error?

        try await coordinator.start(
            selectedRegion: CGRect(x: 10, y: 20, width: 300, height: 200)
        ) { result in
            if case let .failure(error) = result {
                receivedError = error
            }
            completed.fulfill()
        }

        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(autoCapture.startCount, 0)

        hud.viewModel?.startAutoScroll()
        await fulfillment(of: [completed], timeout: 2)

        XCTAssertEqual(
            receivedError as? ScrollingCaptureAutoCaptureError,
            .postEventPermissionDenied
        )
        XCTAssertEqual(autoCapture.startCount, 0)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testCancelStopsSourceDismissesHUDAndReturnsNoCapture() async throws {
        let source = FakeScrollingFrameSource()
        let hud = FakeScrollingHUDPresenter()
        let store = FakeCaptureStore()
        let coordinator = ScrollingCaptureCoordinator(
            frameSource: source,
            autoCapture: nil,
            usesAutomaticCapture: false,
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
            autoCapture: nil,
            usesAutomaticCapture: false,
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

final class ScrollingCaptureContinuousDiscreteFrameSourceTests: XCTestCase {
    func testCaptureFrameNeverReturnsAFrameAlreadyHandedToAnEarlierCall() async throws {
        let source = FakeScrollingFrameSource()
        let adapter = ScrollingCaptureContinuousDiscreteFrameSource(
            continuousSource: source,
            pollInterval: .milliseconds(1),
            acquisitionTimeout: .milliseconds(500)
        )
        _ = try await adapter.prepare(
            selectedRegion: CGRect(x: 0, y: 0, width: 4, height: 3)
        )

        let first = makeSolidImage(width: 4, height: 3)
        source.emit(image: first)
        let capturedFirst = try await adapter.captureFrame()
        XCTAssertTrue(capturedFirst === first)

        // No newer frame exists yet; the call must wait rather than replay `first`.
        let waitTask = Task { try await adapter.captureFrame() }
        try await Task.sleep(for: .milliseconds(30))

        let second = makeSolidImage(width: 4, height: 3)
        source.emit(image: second)
        let capturedSecond = try await waitTask.value
        XCTAssertTrue(capturedSecond === second)
        XCTAssertFalse(capturedSecond === first)
    }

    func testCaptureFrameTimesOutWhenNoFrameEverArrives() async throws {
        let source = FakeScrollingFrameSource()
        let adapter = ScrollingCaptureContinuousDiscreteFrameSource(
            continuousSource: source,
            pollInterval: .milliseconds(1),
            acquisitionTimeout: .milliseconds(20)
        )
        _ = try await adapter.prepare(
            selectedRegion: CGRect(x: 0, y: 0, width: 4, height: 3)
        )

        do {
            _ = try await adapter.captureFrame()
            XCTFail("Expected a frame acquisition timeout error")
        } catch let error as ScrollingCaptureAutoCaptureError {
            XCTAssertEqual(error, .frameAcquisitionTimedOut)
        }
    }

    func testStopClearsBufferedFrameSoALaterPrepareStartsFresh() async throws {
        let source = FakeScrollingFrameSource()
        let adapter = ScrollingCaptureContinuousDiscreteFrameSource(
            continuousSource: source,
            pollInterval: .milliseconds(1),
            acquisitionTimeout: .milliseconds(20)
        )
        _ = try await adapter.prepare(
            selectedRegion: CGRect(x: 0, y: 0, width: 4, height: 3)
        )
        source.emit(image: makeSolidImage(width: 4, height: 3))
        _ = try await adapter.captureFrame()

        await adapter.stop()

        do {
            _ = try await adapter.captureFrame()
            XCTFail("Expected a timeout after stop() cleared buffered state")
        } catch let error as ScrollingCaptureAutoCaptureError {
            XCTAssertEqual(error, .frameAcquisitionTimedOut)
        }
    }
}

private nonisolated final class FakeScrollingFrameSource:
    ScrollingCaptureFrameSourcing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var frameHandler: (@Sendable (ScrollingCaptureStreamFrame) -> Void)?
    private var starts = 0
    private var stops = 0
    var onStart: (() -> Void)?

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

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
        recordStart()
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

    private func recordStart() {
        lock.lock()
        starts += 1
        let onStart = self.onStart
        lock.unlock()
        onStart?()
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

private nonisolated final class FakeAutoCapture:
    ScrollingCaptureAutoCapturing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var starts = 0
    private var completion: CompletionHandler?
    var onStart: (() -> Void)?

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    func start(
        selectedRegion: CGRect,
        onProgress: @escaping ProgressHandler,
        onPreview: @escaping PreviewHandler,
        onCompletion: @escaping CompletionHandler
    ) async throws -> ScrollingCaptureRegionGeometry {
        recordStart(onCompletion)
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

    func setPaused(_ isPaused: Bool) {}
    func finish() {}

    func cancel() {
        let completion = takeCompletion()
        completion?(.success(nil))
    }

    private func recordStart(_ completion: @escaping CompletionHandler) {
        lock.lock()
        starts += 1
        self.completion = completion
        let onStart = self.onStart
        lock.unlock()
        onStart?()
    }

    private func takeCompletion() -> CompletionHandler? {
        lock.lock()
        defer { lock.unlock() }
        let completion = self.completion
        self.completion = nil
        return completion
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
