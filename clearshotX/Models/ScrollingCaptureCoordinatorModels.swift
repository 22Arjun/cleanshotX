//
//  ScrollingCaptureCoordinatorModels.swift
//  clearshotX
//

import Foundation

enum ScrollingCaptureMode: Equatable {
    case manual
    case automatic
}

enum ScrollingCaptureHUDPhase: Equatable {
    case starting
    case ready
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
    var mode: ScrollingCaptureMode?

    static let starting = ScrollingCaptureHUDState(
        phase: .starting,
        acceptedFrameCount: 0,
        rejectedFrameCount: 0,
        outputPixelWidth: 0,
        outputPixelHeight: 0,
        mode: nil
    )

    var title: String {
        switch phase {
        case .starting:
            "Preparing scrolling capture…"
        case .ready:
            "Choose scrolling mode"
        case .capturing:
            switch mode {
            case .manual:
                acceptedFrameCount <= 1 ? "Manual scrolling capture" : "Capturing scroll"
            case .automatic:
                acceptedFrameCount <= 1 ? "Auto-scrolling page" : "Capturing page"
            case nil:
                "Capturing page"
            }
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
        case .ready:
            "Scroll yourself, or let ClearshotX drive the page after you choose Auto Scroll."
        case .capturing:
            switch mode {
            case .manual:
                "Scroll naturally inside the selected area. ClearshotX will capture settled movement."
            case .automatic:
                "ClearshotX is scrolling and capturing each settled page step."
            case nil:
                "Capturing each settled page step."
            }
        case .guidance:
            "Retrying this area with a smaller automatic scroll step."
        case .paused:
            switch mode {
            case .manual:
                "Resume when you are ready to keep capturing manual scroll movement."
            case .automatic:
                "Resume to continue automatic scrolling from this position."
            case nil:
                "Resume to continue capturing."
            }
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

    var canStartAutoScroll: Bool {
        phase == .ready
    }

    var canStartManualScroll: Bool {
        phase == .ready
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
            outputPixelHeight: progress.outputPixelHeight,
            mode: mode
        )
    }
}
