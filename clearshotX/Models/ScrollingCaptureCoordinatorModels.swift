//
//  ScrollingCaptureCoordinatorModels.swift
//  clearshotX
//

import Foundation

enum ScrollingCaptureHUDPhase: Equatable {
    case starting
    case capturing
    case guidance
    case paused
    case finishing
}

struct ScrollingCaptureHUDState: Equatable {
    var phase: ScrollingCaptureHUDPhase
    var acceptedFrameCount: Int
    var rejectedFrameCount: Int
    var outputPixelWidth: Int
    var outputPixelHeight: Int

    static let starting = ScrollingCaptureHUDState(
        phase: .starting,
        acceptedFrameCount: 0,
        rejectedFrameCount: 0,
        outputPixelWidth: 0,
        outputPixelHeight: 0
    )

    var title: String {
        switch phase {
        case .starting:
            "Preparing scrolling capture…"
        case .capturing:
            acceptedFrameCount <= 1 ? "Start scrolling" : "Capturing as you scroll"
        case .guidance:
            "Scroll a little slower"
        case .paused:
            "Capture paused"
        case .finishing:
            "Finishing capture…"
        }
    }

    var detail: String {
        switch phase {
        case .starting:
            "Connecting to the selected area"
        case .capturing:
            "Keep the area still horizontally, then finish when the page is complete."
        case .guidance:
            "Small, steady vertical steps produce the cleanest result."
        case .paused:
            "Adjust the page, then resume from the same scroll position."
        case .finishing:
            "Assembling and saving the accepted pixels"
        }
    }

    var dimensionsText: String? {
        guard outputPixelWidth > 0, outputPixelHeight > 0 else { return nil }
        return "\(outputPixelWidth) × \(outputPixelHeight) px"
    }

    var canFinish: Bool {
        acceptedFrameCount > 0 && phase != .finishing
    }

    var canPause: Bool {
        phase == .capturing || phase == .guidance || phase == .paused
    }

    var pauseButtonTitle: String {
        phase == .paused ? "Resume" : "Pause"
    }

    var acceptedFramesText: String {
        "\(acceptedFrameCount) \(acceptedFrameCount == 1 ? "frame" : "frames")"
    }
}

enum ScrollingCaptureHUDReducer {
    static let guidanceRejectionThreshold = 5

    static func applying(
        _ decision: ScrollingCaptureFrameDecision,
        to state: ScrollingCaptureHUDState,
        consecutiveRejections: inout Int
    ) -> ScrollingCaptureHUDState {
        switch decision {
        case let .started(progress), let .appended(progress):
            consecutiveRejections = 0
            return state.updating(progress: progress, phase: .capturing)

        case let .rebased(progress):
            consecutiveRejections = 0
            return state.updating(progress: progress, phase: .capturing)

        case let .duplicate(progress):
            return state.updating(progress: progress, phase: state.phase)

        case let .rejected(_, progress):
            consecutiveRejections += 1
            let phase: ScrollingCaptureHUDPhase = consecutiveRejections
                >= guidanceRejectionThreshold ? .guidance : .capturing
            return state.updating(progress: progress, phase: phase)

        case let .reachedOutputLimit(progress):
            consecutiveRejections = 0
            return state.updating(progress: progress, phase: .finishing)
        }
    }
}

private extension ScrollingCaptureHUDState {
    func updating(
        progress: ScrollingCaptureProgress,
        phase: ScrollingCaptureHUDPhase
    ) -> ScrollingCaptureHUDState {
        ScrollingCaptureHUDState(
            phase: phase,
            acceptedFrameCount: progress.acceptedFrameCount,
            rejectedFrameCount: progress.rejectedFrameCount,
            outputPixelWidth: progress.outputPixelWidth,
            outputPixelHeight: progress.outputPixelHeight
        )
    }
}
