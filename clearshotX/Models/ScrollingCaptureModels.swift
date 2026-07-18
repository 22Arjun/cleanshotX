//
//  ScrollingCaptureModels.swift
//  clearshotX
//

import CoreGraphics
import Foundation

nonisolated struct ScrollingCaptureContentInsets: Equatable, Sendable {
    var top: Int
    var bottom: Int

    static let zero = ScrollingCaptureContentInsets(top: 0, bottom: 0)

    init(top: Int, bottom: Int) {
        self.top = max(0, top)
        self.bottom = max(0, bottom)
    }
}

nonisolated struct ScrollingCaptureConfiguration: Equatable, Sendable {
    /// Frames are reduced before registration. This bounds registration work while
    /// retaining enough horizontal detail to distinguish text and interface rows.
    var maximumAnalysisWidth = 192
    var maximumAnalysisHeight = 320

    /// A smaller movement is treated as an unstable/duplicate frame instead of a
    /// useful scroll step.
    var minimumScrollDistance = 8
    var maximumScrollFraction = 0.82
    var minimumOverlapFraction = 0.18

    /// Mean absolute luma differences are normalized to 0...1.
    var duplicateDifferenceThreshold = 0.012
    var maximumAlignmentDifference = 0.075
    var minimumAlignmentConfidence = 0.16

    /// Fixed top/bottom chrome can be excluded from registration and emitted once.
    /// Automatic fixed-band detection will populate this in a later pipeline stage.
    var contentInsets: ScrollingCaptureContentInsets = .zero

    /// Guardrails prevent a malicious or accidental endless session from exhausting
    /// address space while still allowing very long captures.
    var maximumOutputHeight = 60_000
    var maximumOutputPixelCount = 80_000_000
}

nonisolated struct ScrollingCaptureAlignment: Equatable, Sendable {
    let verticalOffset: Int
    let difference: Double
    let confidence: Double
}

nonisolated enum ScrollingCaptureAnalysisRejection: Equatable, Sendable {
    case invalidFrame
    case insufficientOverlap
    case noReliableAlignment(bestDifference: Double, confidence: Double)
}

nonisolated enum ScrollingCaptureAnalysisResult: Equatable, Sendable {
    case duplicate(difference: Double)
    case aligned(ScrollingCaptureAlignment)
    case rejected(ScrollingCaptureAnalysisRejection)
}

nonisolated struct ScrollingCaptureProgress: Equatable, Sendable {
    let acceptedFrameCount: Int
    let rejectedFrameCount: Int
    let outputPixelWidth: Int
    let outputPixelHeight: Int
    let lastAlignment: ScrollingCaptureAlignment?
}

nonisolated enum ScrollingCaptureFrameDecision: Equatable, Sendable {
    case started(ScrollingCaptureProgress)
    case appended(ScrollingCaptureProgress)
    case duplicate(ScrollingCaptureProgress)
    case rejected(ScrollingCaptureAnalysisRejection, ScrollingCaptureProgress)
    case reachedOutputLimit(ScrollingCaptureProgress)
}

nonisolated enum ScrollingCaptureError: LocalizedError, Equatable {
    case invalidConfiguration
    case inconsistentFrameSize(expected: CGSize, actual: CGSize)
    case noFrames
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "The scrolling capture configuration is not valid for this region."
        case let .inconsistentFrameSize(expected, actual):
            "The scrolling region changed size from \(Int(expected.width))×\(Int(expected.height)) to \(Int(actual.width))×\(Int(actual.height))."
        case .noFrames:
            "No usable scrolling capture frames were received."
        case .imageCreationFailed:
            "ClearshotX could not assemble the scrolling capture image."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .inconsistentFrameSize:
            "Keep the selected window and scrolling area at the same size until capture finishes."
        case .noFrames:
            "Keep the scrolling area visible, then try the capture again."
        default:
            "Try a smaller scrolling region or a shorter capture."
        }
    }
}
