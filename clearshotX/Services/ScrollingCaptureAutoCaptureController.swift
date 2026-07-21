//
//  ScrollingCaptureAutoCaptureController.swift
//  clearshotX
//

import CoreGraphics
import Foundation

nonisolated struct ScrollingCaptureAutoCaptureConfiguration: Equatable, Sendable {
    /// Scroll in AppKit points; the captured offset is measured independently in
    /// native pixels, so Retina output never depends on this estimate.
    var viewportStepFraction = 0.58
    var minimumStepPoints = 12
    var maximumRetries = 5
    var initialSettleDelay: Duration = .milliseconds(40)
    var settleProbeDelay: Duration = .milliseconds(18)
    var maximumSettleProbes = 5
    var stationaryStepsToFinish = 2
    var maximumSteps = 1_000
}

nonisolated enum ScrollingCaptureAutoCaptureError: LocalizedError, Equatable {
    case alreadyRunning
    case notPrepared
    case eventCreationFailed
    case postEventPermissionDenied
    case unreliableAlignment
    case invalidScrollRegion
    case frameAcquisitionTimedOut

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "An automatic scrolling capture is already running."
        case .notPrepared:
            "The automatic scrolling capture source was not prepared."
        case .eventCreationFailed:
            "ClearshotX could not create the automatic scroll event."
        case .postEventPermissionDenied:
            "Automatic scrolling needs permission to control this Mac."
        case .unreliableAlignment:
            "The page could not be aligned reliably, so capture stopped before making a broken seam."
        case .invalidScrollRegion:
            "The selected region is too small for automatic scrolling capture."
        case .frameAcquisitionTimedOut:
            "ClearshotX did not receive a new frame from the selected area in time."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreliableAlignment:
            "Keep the page unobstructed and try a slightly taller region."
        case .postEventPermissionDenied:
            "Allow ClearshotX in System Settings › Privacy & Security › Accessibility, then try again."
        case .frameAcquisitionTimedOut:
            "Keep the selected area visible on screen, then try again."
        default:
            "Select the scrolling region again and retry."
        }
    }
}

nonisolated protocol ScrollingCaptureAutoCapturing: AnyObject, Sendable {
    typealias ProgressHandler = @Sendable (ScrollingCaptureFrameDecision) -> Void
    typealias PreviewHandler = @Sendable (CGImage) -> Void
    typealias CompletionHandler = @Sendable (Result<CGImage?, Error>) -> Void

    func start(
        selectedRegion: CGRect,
        onProgress: @escaping ProgressHandler,
        onPreview: @escaping PreviewHandler,
        onCompletion: @escaping CompletionHandler
    ) async throws -> ScrollingCaptureRegionGeometry

    func setPaused(_ isPaused: Bool)
    func finish()
    func cancel()
}

/// Owns the deterministic capture loop: scroll, settle, capture, register, append.
/// No user scroll cadence enters the algorithm. Low-confidence motion is undone
/// before a smaller delta is attempted, so a retry can never leave a document gap.
nonisolated final class ScrollingCaptureAutoCaptureController:
    ScrollingCaptureAutoCapturing,
    @unchecked Sendable
{
    private struct ControlState {
        var isRunning = false
        var isPaused = false
        var shouldFinish = false
        var isCancelled = false
    }

    private struct StepResult {
        let frame: CGImage
        let match: ScrollingCaptureStitchMatch
    }

    private let frameSource: ScrollingCaptureDiscreteFrameSourcing
    private let scrollDriver: ScrollingCaptureScrollDriving
    private let stitchEngine: ScrollingCaptureStitchEngine
    private let captureConfiguration: ScrollingCaptureConfiguration
    private let autoConfiguration: ScrollingCaptureAutoCaptureConfiguration
    private let lock = NSLock()
    private var control = ControlState()
    private var captureTask: Task<Void, Never>?

    init(
        frameSource: ScrollingCaptureDiscreteFrameSourcing =
            ScrollingCaptureContinuousDiscreteFrameSource(),
        scrollDriver: ScrollingCaptureScrollDriving = ScrollingCaptureCGEventScrollDriver(),
        stitchEngine: ScrollingCaptureStitchEngine = ScrollingCaptureStitchEngine(),
        captureConfiguration: ScrollingCaptureConfiguration = .init(),
        autoConfiguration: ScrollingCaptureAutoCaptureConfiguration = .init()
    ) {
        self.frameSource = frameSource
        self.scrollDriver = scrollDriver
        self.stitchEngine = stitchEngine
        self.captureConfiguration = captureConfiguration
        self.autoConfiguration = autoConfiguration
    }

    func start(
        selectedRegion: CGRect,
        onProgress: @escaping ProgressHandler,
        onPreview: @escaping PreviewHandler,
        onCompletion: @escaping CompletionHandler
    ) async throws -> ScrollingCaptureRegionGeometry {
        guard selectedRegion.width >= 2, selectedRegion.height >= 2 else {
            throw ScrollingCaptureAutoCaptureError.invalidScrollRegion
        }
        try reserveStart()
        do {
            let geometry = try await frameSource.prepare(selectedRegion: selectedRegion)
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let result: Result<CGImage?, Error>
                do {
                    result = .success(
                        try await self.run(
                            geometry: geometry,
                            onProgress: onProgress,
                            onPreview: onPreview
                        )
                    )
                } catch is CancellationError {
                    result = .success(nil)
                } catch {
                    result = .failure(error)
                }
                await self.frameSource.stop()
                self.clearState()
                onCompletion(result)
            }
            install(task: task)
            return geometry
        } catch {
            clearState()
            await frameSource.stop()
            throw error
        }
    }

    func setPaused(_ isPaused: Bool) {
        lock.lock()
        if control.isRunning, !control.isCancelled {
            control.isPaused = isPaused
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        if control.isRunning, !control.isCancelled {
            control.shouldFinish = true
            control.isPaused = false
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        control.isCancelled = true
        control.isPaused = false
        let task = captureTask
        lock.unlock()
        task?.cancel()
    }

    private func run(
        geometry: ScrollingCaptureRegionGeometry,
        onProgress: @escaping ProgressHandler,
        onPreview: @escaping PreviewHandler
    ) async throws -> CGImage? {
        var previous = try await frameSource.captureFrame()
        let compositor = try ScrollingCaptureCompositor(
            firstFrame: previous,
            contentInsets: captureConfiguration.contentInsets
        )
        let previewPipeline = ScrollingCapturePreviewPipeline(
            contentInsets: captureConfiguration.contentInsets,
            publication: onPreview
        )
        defer { previewPipeline.stop() }

        var acceptedFrames = 1
        var rejectedFrames = 0
        var lastAlignment: ScrollingCaptureAlignment?
        var progress = makeProgress(
            compositor: compositor,
            acceptedFrames: acceptedFrames,
            rejectedFrames: rejectedFrames,
            lastAlignment: lastAlignment
        )
        let started = ScrollingCaptureFrameDecision.started(progress)
        onProgress(started)
        previewPipeline.submit(frame: previous, decision: started)

        let selectionCenter = CGPoint(
            x: geometry.globalRect.midX,
            y: geometry.globalRect.midY
        )
        let baseDelta = max(
            autoConfiguration.minimumStepPoints,
            Int((geometry.globalRect.height * autoConfiguration.viewportStepFraction).rounded())
        )
        var stationaryCount = 0
        var steps = 0

        captureLoop: while steps < autoConfiguration.maximumSteps {
            try Task.checkCancellation()
            try await waitWhilePaused()
            let state = currentControl()
            if state.isCancelled { return nil }
            if state.shouldFinish { break }

            let step = try await captureReliableStep(
                previous: previous,
                initialDelta: baseDelta,
                location: selectionCenter
            )
            steps += 1

            switch step.match.disposition {
            case .stationary:
                stationaryCount += 1
                previous = step.frame
                try compositor.refreshDeferredPixels(from: step.frame)
                progress = makeProgress(
                    compositor: compositor,
                    acceptedFrames: acceptedFrames,
                    rejectedFrames: rejectedFrames,
                    lastAlignment: lastAlignment
                )
                onProgress(.duplicate(progress))
                if stationaryCount >= autoConfiguration.stationaryStepsToFinish {
                    break captureLoop
                }

            case .accept:
                stationaryCount = 0
                if acceptedFrames == 1 {
                    try compositor.updateContentInsets(
                        step.match.detectedContentInsets,
                        latestFrame: step.frame
                    )
                }
                let proposedHeight = compositor.outputHeight + step.match.verticalOffset
                let pixels = compositor.outputWidth.multipliedReportingOverflow(
                    by: proposedHeight
                )
                guard proposedHeight <= captureConfiguration.maximumOutputHeight,
                      !pixels.overflow,
                      pixels.partialValue <= captureConfiguration.maximumOutputPixelCount else {
                    progress = makeProgress(
                        compositor: compositor,
                        acceptedFrames: acceptedFrames,
                        rejectedFrames: rejectedFrames,
                        lastAlignment: lastAlignment
                    )
                    onProgress(.reachedOutputLimit(progress))
                    return try compositor.makeImage()
                }

                try compositor.append(
                    frame: step.frame,
                    verticalOffset: step.match.verticalOffset
                )
                // The settle probe is a second same-position observation, so the
                // newest native strip is safe to commit without waiting another step.
                try compositor.refreshDeferredPixels(from: step.frame)
                previous = step.frame
                acceptedFrames += 1
                lastAlignment = ScrollingCaptureAlignment(
                    verticalOffset: step.match.verticalOffset,
                    difference: Double(max(0, 1 - step.match.correlation)),
                    confidence: Double(step.match.correlation)
                )
                progress = makeProgress(
                    compositor: compositor,
                    acceptedFrames: acceptedFrames,
                    rejectedFrames: rejectedFrames,
                    lastAlignment: lastAlignment
                )
                let decision = ScrollingCaptureFrameDecision.appended(progress)
                onProgress(decision)
                previewPipeline.submit(frame: step.frame, decision: decision)

            case .retryWithSmallerScrollDelta:
                // captureReliableStep exhausts retries before returning this case.
                rejectedFrames += 1
                throw ScrollingCaptureAutoCaptureError.unreliableAlignment
            }
        }

        return try compositor.makeImage()
    }

    private func captureReliableStep(
        previous: CGImage,
        initialDelta: Int,
        location: CGPoint
    ) async throws -> StepResult {
        var delta = initialDelta
        var best: StepResult?

        for attempt in 0..<max(1, autoConfiguration.maximumRetries) {
            try Task.checkCancellation()
            try scrollDriver.scroll(verticalDelta: delta, at: location)
            let candidate = try await captureSettledFrame()
            let match = try stitchEngine.match(previous: previous, current: candidate)
            let result = StepResult(frame: candidate, match: match)

            if match.disposition != .retryWithSmallerScrollDelta {
                return result
            }
            if best == nil || match.correlation > best!.match.correlation {
                best = result
            }
            guard attempt + 1 < autoConfiguration.maximumRetries,
                  delta / 2 >= autoConfiguration.minimumStepPoints else {
                break
            }

            // Undo the rejected step before retrying. Waiting for that rollback to
            // settle preserves the previous frame as the exact registration base.
            try scrollDriver.scroll(verticalDelta: -delta, at: location)
            _ = try await captureSettledFrame()
            delta /= 2
        }
        if let best { return best }
        return StepResult(
            frame: previous,
            match: try stitchEngine.match(previous: previous, current: previous)
        )
    }

    private func captureSettledFrame() async throws -> CGImage {
        try await Task.sleep(for: autoConfiguration.initialSettleDelay)
        var latest = try await frameSource.captureFrame()
        guard autoConfiguration.maximumSettleProbes > 0 else { return latest }

        for _ in 0..<autoConfiguration.maximumSettleProbes {
            try Task.checkCancellation()
            try await Task.sleep(for: autoConfiguration.settleProbeDelay)
            let probe = try await frameSource.captureFrame()
            if let match = try? stitchEngine.match(previous: latest, current: probe),
               match.isStationary {
                return probe
            }
            latest = probe
        }
        // Dynamic ads/video may never become pixel-identical. The newest frame is
        // still the most settled observation and remains subject to the seam gate.
        return latest
    }

    private func waitWhilePaused() async throws {
        while currentControl().isPaused {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func makeProgress(
        compositor: ScrollingCaptureCompositor,
        acceptedFrames: Int,
        rejectedFrames: Int,
        lastAlignment: ScrollingCaptureAlignment?
    ) -> ScrollingCaptureProgress {
        ScrollingCaptureProgress(
            acceptedFrameCount: acceptedFrames,
            rejectedFrameCount: rejectedFrames,
            outputPixelWidth: compositor.outputWidth,
            outputPixelHeight: compositor.outputHeight,
            lastAlignment: lastAlignment
        )
    }

    private func reserveStart() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !control.isRunning else {
            throw ScrollingCaptureAutoCaptureError.alreadyRunning
        }
        control = ControlState(isRunning: true)
    }

    private func install(task: Task<Void, Never>) {
        lock.lock()
        // A scripted/very small capture can finish before start() stores its task.
        // Do not resurrect a completed run in that race.
        if control.isRunning {
            captureTask = task
        }
        lock.unlock()
    }

    private func currentControl() -> ControlState {
        lock.lock()
        defer { lock.unlock() }
        return control
    }

    private func clearState() {
        lock.lock()
        control = ControlState()
        captureTask = nil
        lock.unlock()
    }
}
