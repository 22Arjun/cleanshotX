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
        self.state = state
    }

    func updatePreview(_ image: CGImage?) {
        previewImage = image
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
