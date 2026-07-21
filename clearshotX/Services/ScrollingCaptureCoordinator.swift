//
//  ScrollingCaptureCoordinator.swift
//  clearshotX
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScrollingCaptureCoordinator {
    typealias Completion = (Result<CaptureResult?, Error>) -> Void

    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case capturing
        case paused
        case finishing
        case cancelling
    }

    private(set) var phase: Phase = .idle

    private let frameSource: ScrollingCaptureFrameSourcing
    private let autoCapture: ScrollingCaptureAutoCapturing?
    private let captureStore: CaptureStoring
    private let hudPresenter: ScrollingCaptureHUDPresenting
    private let configuration: ScrollingCaptureConfiguration
    private let postEventAccessProvider: () -> Bool

    private var activeCaptureID: UUID?
    private var selectedRegion: CGRect?
    private var geometry: ScrollingCaptureRegionGeometry?
    private var worker: ScrollingCaptureWorker?
    private var activeMode: ScrollingCaptureMode?
    private var completion: Completion?
    private var hudViewModel: ScrollingCaptureHUDViewModel?
    private var hudState: ScrollingCaptureHUDState = .starting
    private var consecutiveRejections = 0

    init(
        frameSource: ScrollingCaptureFrameSourcing = ScrollingCaptureFrameSource(),
        autoCapture: ScrollingCaptureAutoCapturing? = nil,
        usesAutomaticCapture: Bool = true,
        captureStore: CaptureStoring? = nil,
        hudPresenter: ScrollingCaptureHUDPresenting? = nil,
        configuration: ScrollingCaptureConfiguration = ScrollingCaptureConfiguration(),
        postEventAccessProvider: @escaping () -> Bool = {
            CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        }
    ) {
        self.frameSource = frameSource
        self.autoCapture = usesAutomaticCapture
            ? autoCapture ?? ScrollingCaptureAutoCaptureController(
                captureConfiguration: configuration
            )
            : nil
        self.captureStore = captureStore ?? CaptureStore()
        self.hudPresenter = hudPresenter ?? ScrollingCaptureHUDManager()
        self.configuration = configuration
        self.postEventAccessProvider = postEventAccessProvider
    }

    func start(
        selectedRegion: CGRect,
        completion: @escaping Completion
    ) async throws {
        guard phase == .idle else {
            throw ScrollingCaptureFrameSourceError.alreadyRunning
        }

        let captureID = UUID()
        let hudViewModel = ScrollingCaptureHUDViewModel(
            finish: { [weak self] in self?.finish() },
            cancel: { [weak self] in self?.cancel() },
            togglePause: { [weak self] in self?.togglePause() },
            startAutoScroll: { [weak self] in self?.startAutoScroll() },
            startManualScroll: { [weak self] in self?.startManualScroll() }
        )

        activeCaptureID = captureID
        self.selectedRegion = selectedRegion
        worker = nil
        activeMode = nil
        self.completion = completion
        self.hudViewModel = hudViewModel
        hudState = .starting
        consecutiveRejections = 0
        phase = .starting
        hudPresenter.show(viewModel: hudViewModel, adjacentTo: selectedRegion)

        do {
            if autoCapture != nil {
                phase = .ready
                hudState.phase = .ready
                hudViewModel.update(hudState)
                return
            }

            try await beginManualCapture(
                selectedRegion: selectedRegion,
                captureID: captureID
            )
        } catch {
            guard activeCaptureID == captureID else { return }
            reset()
            throw error
        }
    }

    func startManualScroll() {
        guard phase == .ready,
              let selectedRegion,
              let captureID = activeCaptureID
        else {
            return
        }

        phase = .starting
        hudState.phase = .starting
        hudState.mode = .manual
        hudViewModel?.update(hudState)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.beginManualCapture(
                    selectedRegion: selectedRegion,
                    captureID: captureID
                )
            } catch {
                guard self.activeCaptureID == captureID else { return }
                self.complete(.failure(error), captureID: captureID)
            }
        }
    }

    func startAutoScroll() {
        guard phase == .ready,
              let autoCapture,
              let selectedRegion,
              let captureID = activeCaptureID
        else {
            return
        }

        activeMode = .automatic
        guard postEventAccessProvider() else {
            complete(
                .failure(ScrollingCaptureAutoCaptureError.postEventPermissionDenied),
                captureID: captureID
            )
            return
        }

        phase = .starting
        hudState.phase = .starting
        hudState.mode = .automatic
        hudViewModel?.update(hudState)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let geometry = try await autoCapture.start(
                    selectedRegion: selectedRegion,
                    onProgress: { [weak self] decision in
                        Task { @MainActor [weak self] in
                            self?.handleAutoProgress(decision, captureID: captureID)
                        }
                    },
                    onPreview: { [weak self] image in
                        Task { @MainActor [weak self] in
                            guard self?.activeCaptureID == captureID else { return }
                            self?.hudViewModel?.updatePreview(image)
                        }
                    },
                    onCompletion: { [weak self] result in
                        Task { @MainActor [weak self] in
                            self?.handleAutoCompletion(result, captureID: captureID)
                        }
                    }
                )
                guard self.activeCaptureID == captureID else {
                    autoCapture.cancel()
                    return
                }
                self.geometry = geometry
                self.phase = .capturing
                self.hudState.phase = .capturing
                self.hudViewModel?.update(self.hudState)
            } catch {
                guard self.activeCaptureID == captureID else { return }
                self.complete(.failure(error), captureID: captureID)
            }
        }
    }

    private func beginManualCapture(
        selectedRegion: CGRect,
        captureID: UUID
    ) async throws {
        let worker = ScrollingCaptureWorker(
            configuration: configuration,
            previewPublication: { [weak self] image in
                Task { @MainActor [weak self] in
                    guard self?.activeCaptureID == captureID else { return }
                    self?.hudViewModel?.updatePreview(image)
                }
            }
        )
        self.worker = worker
        activeMode = .manual
        hudState.mode = .manual

        let geometry = try await frameSource.start(
            selectedRegion: selectedRegion,
            onFrame: { [weak self, weak worker] frame in
                guard let worker,
                      let result = worker.ingest(frame.image)
                else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.handle(result, captureID: captureID)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleSourceFailure(error, captureID: captureID)
                }
            }
        )

        guard activeCaptureID == captureID else {
            try? await frameSource.stop()
            return
        }

        self.geometry = geometry
        phase = .capturing
        hudState.phase = .capturing
        hudViewModel?.update(hudState)
    }

    func finish() {
        guard phase == .capturing || phase == .paused,
              let captureID = activeCaptureID
        else {
            return
        }
        if activeMode == .automatic, let autoCapture {
            phase = .finishing
            hudState.phase = .finishing
            hudViewModel?.update(hudState)
            autoCapture.finish()
        } else {
            finalize(captureID: captureID, stopSource: true, fallbackError: nil)
        }
    }

    func cancel() {
        guard phase != .idle,
              phase != .cancelling,
              let captureID = activeCaptureID
        else {
            return
        }

        let wasReady = phase == .ready
        phase = .cancelling
        if wasReady {
            complete(.success(nil), captureID: captureID)
            return
        }

        if activeMode == .automatic, let autoCapture {
            autoCapture.cancel()
            return
        }
        guard activeMode == .manual, let worker else {
            complete(.success(nil), captureID: captureID)
            return
        }
        frameSource.setFrameDeliveryEnabled(false)
        worker.cancel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.frameSource.stop()
            self.complete(.success(nil), captureID: captureID)
        }
    }

    func togglePause() {
        if activeMode == .automatic, let autoCapture {
            switch phase {
            case .capturing:
                autoCapture.setPaused(true)
                phase = .paused
                hudState.phase = .paused
                hudViewModel?.update(hudState)
            case .paused:
                autoCapture.setPaused(false)
                phase = .capturing
                hudState.phase = .capturing
                hudViewModel?.update(hudState)
            default:
                break
            }
            return
        }

        guard activeMode == .manual, let worker else { return }

        switch phase {
        case .capturing:
            frameSource.setFrameDeliveryEnabled(false)
            worker.pause()
            phase = .paused
            hudState.phase = .paused
            hudViewModel?.update(hudState)

        case .paused:
            worker.resume()
            frameSource.setFrameDeliveryEnabled(true)
            phase = .capturing
            hudState.phase = .capturing
            hudViewModel?.update(hudState)

        default:
            break
        }
    }

    private func handle(
        _ result: Result<ScrollingCaptureWorkerUpdate, Error>,
        captureID: UUID
    ) {
        guard activeCaptureID == captureID,
              activeMode == .manual,
              phase == .capturing || phase == .starting
        else {
            return
        }

        switch result {
        case let .success(update):
            let decision = update.decision
            hudState = ScrollingCaptureHUDReducer.applying(
                decision,
                to: hudState,
                consecutiveRejections: &consecutiveRejections
            )
            hudViewModel?.update(hudState)

            if case .reachedOutputLimit = decision {
                finalize(captureID: captureID, stopSource: true, fallbackError: nil)
            }

        case let .failure(error):
            finalize(captureID: captureID, stopSource: true, fallbackError: error)
        }
    }

    private func handleSourceFailure(_ error: Error, captureID: UUID) {
        guard activeCaptureID == captureID,
              phase != .finishing,
              phase != .cancelling
        else {
            return
        }
        finalize(captureID: captureID, stopSource: false, fallbackError: error)
    }

    private func handleAutoProgress(
        _ decision: ScrollingCaptureFrameDecision,
        captureID: UUID
    ) {
        guard activeCaptureID == captureID,
              activeMode == .automatic,
              phase == .starting || phase == .capturing || phase == .paused else {
            return
        }
        hudState = ScrollingCaptureHUDReducer.applying(
            decision,
            to: hudState,
            consecutiveRejections: &consecutiveRejections
        )
        if phase == .paused {
            hudState.phase = .paused
        }
        hudViewModel?.update(hudState)
    }

    private func handleAutoCompletion(
        _ result: Result<CGImage?, Error>,
        captureID: UUID
    ) {
        guard activeCaptureID == captureID else { return }
        switch result {
        case let .success(image?):
            do {
                let capture = try makeCaptureResult(
                    image: image,
                    selectedRegion: selectedRegion,
                    geometry: geometry
                )
                complete(.success(capture), captureID: captureID)
            } catch {
                complete(.failure(error), captureID: captureID)
            }
        case .success(nil):
            complete(.success(nil), captureID: captureID)
        case let .failure(error):
            complete(.failure(error), captureID: captureID)
        }
    }

    private func finalize(
        captureID: UUID,
        stopSource: Bool,
        fallbackError: Error?
    ) {
        guard activeCaptureID == captureID,
              phase != .finishing,
              phase != .cancelling,
              let worker
        else {
            return
        }

        phase = .finishing
        frameSource.setFrameDeliveryEnabled(false)
        hudState.phase = .finishing
        hudViewModel?.update(hudState)

        Task { @MainActor [weak self] in
            guard let self else { return }
            if stopSource {
                try? await self.frameSource.stop()
            }

            let assembledImage: Result<CGImage, Error> = await Task.detached(
                priority: .userInitiated
            ) {
                Result { try worker.finish() }
            }.value

            guard self.activeCaptureID == captureID else { return }

            switch assembledImage {
            case let .success(image):
                do {
                    let capture = try self.makeCaptureResult(
                        image: image,
                        selectedRegion: self.selectedRegion,
                        geometry: self.geometry
                    )
                    self.complete(.success(capture), captureID: captureID)
                } catch {
                    self.complete(.failure(error), captureID: captureID)
                }

            case let .failure(error):
                self.complete(
                    .failure(fallbackError ?? error),
                    captureID: captureID
                )
            }
        }
    }

    private func makeCaptureResult(
        image: CGImage,
        selectedRegion: CGRect?,
        geometry: ScrollingCaptureRegionGeometry?
    ) throws -> CaptureResult {
        let storedCapture = try captureStore.store(image)
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        return CaptureResult(
            image: nsImage,
            fileURL: storedCapture.fileURL,
            dragFileURL: storedCapture.dragFileURL,
            pixelWidth: image.width,
            pixelHeight: image.height,
            screenFrame: geometry?.displayFrame ?? selectedRegion ?? .zero
        )
    }

    private func complete(
        _ result: Result<CaptureResult?, Error>,
        captureID: UUID
    ) {
        guard activeCaptureID == captureID else { return }
        let completion = self.completion
        reset()
        completion?(result)
    }

    private func reset() {
        hudPresenter.dismiss()
        phase = .idle
        activeCaptureID = nil
        selectedRegion = nil
        geometry = nil
        worker = nil
        activeMode = nil
        completion = nil
        hudViewModel = nil
        hudState = .starting
        consecutiveRejections = 0
    }
}

private nonisolated final class ScrollingCaptureWorker: @unchecked Sendable {
    private let lock = NSLock()
    private let session: ScrollingCaptureSession
    private let previewPipeline: ScrollingCapturePreviewPipeline
    private var isActive = true
    private var isPaused = false
    private var needsRebase = false

    init(
        configuration: ScrollingCaptureConfiguration,
        previewPublication: @escaping ScrollingCapturePreviewPipeline.Publication
    ) {
        session = ScrollingCaptureSession(configuration: configuration)
        previewPipeline = ScrollingCapturePreviewPipeline(
            contentInsets: configuration.contentInsets,
            publication: previewPublication
        )
    }

    func ingest(
        _ image: CGImage
    ) -> Result<ScrollingCaptureWorkerUpdate, Error>? {
        lock.lock()
        guard isActive, !isPaused else {
            lock.unlock()
            return nil
        }

        let result: Result<ScrollingCaptureWorkerUpdate, Error>
        do {
            let decision: ScrollingCaptureFrameDecision
            if needsRebase {
                decision = try session.rebase(image)
                needsRebase = false
            } else {
                decision = try session.ingest(image)
            }
            result = .success(ScrollingCaptureWorkerUpdate(decision: decision))
        } catch {
            result = .failure(error)
        }
        lock.unlock()

        // Preview work owns a separate lock and serial queue. Even its bounded
        // enqueue bookkeeping stays outside the native session's critical section.
        if case let .success(update) = result {
            previewPipeline.submit(frame: image, decision: update.decision)
        }
        return result
    }

    func finish() throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { throw ScrollingCaptureError.noFrames }
        isActive = false
        previewPipeline.stop()
        return try session.finish()
    }

    func cancel() {
        lock.lock()
        isActive = false
        previewPipeline.stop()
        lock.unlock()
    }

    func pause() {
        lock.lock()
        if isActive {
            isPaused = true
        }
        lock.unlock()
    }

    func resume() {
        lock.lock()
        if isActive, isPaused {
            isPaused = false
            needsRebase = true
        }
        lock.unlock()
    }
}

private nonisolated struct ScrollingCaptureWorkerUpdate: Sendable {
    let decision: ScrollingCaptureFrameDecision
}
