//
//  ScrollingCaptureHUDViewModel.swift
//  clearshotX
//

import Combine
import CoreGraphics

@MainActor
final class ScrollingCaptureHUDViewModel: ObservableObject {
    @Published private(set) var state: ScrollingCaptureHUDState = .starting
    @Published private(set) var previewImage: CGImage?

    private let finishHandler: () -> Void
    private let cancelHandler: () -> Void
    private let pauseHandler: () -> Void
    private var pendingState: ScrollingCaptureHUDState?
    private var statePublicationTask: Task<Void, Never>?

    init(
        finish: @escaping () -> Void,
        cancel: @escaping () -> Void,
        togglePause: @escaping () -> Void
    ) {
        finishHandler = finish
        cancelHandler = cancel
        pauseHandler = togglePause
    }

    func update(_ state: ScrollingCaptureHUDState) {
        guard state != self.state else { return }

        // Control availability and phase transitions must feel immediate. Numeric
        // progress can be coalesced: publishing it for every 30 fps stream sample
        // only makes SwiftUI redo work that is invisible between display frames.
        if state.phase != self.state.phase || state.canFinish != self.state.canFinish {
            statePublicationTask?.cancel()
            statePublicationTask = nil
            pendingState = nil
            self.state = state
            return
        }

        pendingState = state
        guard statePublicationTask == nil else { return }
        statePublicationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard !Task.isCancelled, let self else { return }
            if let pendingState = self.pendingState {
                self.state = pendingState
            }
            self.pendingState = nil
            self.statePublicationTask = nil
        }
    }

    func updatePreview(_ image: CGImage?) {
        previewImage = image
    }

    deinit {
        statePublicationTask?.cancel()
    }

    func finish() {
        guard state.canFinish else { return }
        finishHandler()
    }

    func cancel() {
        cancelHandler()
    }

    func togglePause() {
        guard state.canPause else { return }
        pauseHandler()
    }
}
