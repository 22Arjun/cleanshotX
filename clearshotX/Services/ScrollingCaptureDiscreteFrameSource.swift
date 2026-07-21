//
//  ScrollingCaptureDiscreteFrameSource.swift
//  clearshotX
//

import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Captures one exact native-resolution viewport on demand. The filter and stream
/// configuration are prepared once and reused for every auto-scroll step.
nonisolated final class ScrollingCaptureDiscreteFrameSource:
    ScrollingCaptureDiscreteFrameSourcing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var filter: SCContentFilter?
    private var streamConfiguration: SCStreamConfiguration?
    private var geometry: ScrollingCaptureRegionGeometry?

    func prepare(
        selectedRegion: CGRect
    ) async throws -> ScrollingCaptureRegionGeometry {
        let content = try await SCShareableContent.current
        let descriptors = NSScreen.screens.compactMap {
            screen -> ScrollingCaptureDisplayDescriptor? in
            guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else {
                return nil
            }
            return ScrollingCaptureDisplayDescriptor(
                displayID: displayID,
                frame: screen.frame,
                pointPixelScale: screen.backingScaleFactor
            )
        }
        let geometry = try ScrollingCaptureRegionResolver.resolve(
            selectedRegion: selectedRegion,
            displays: descriptors
        )
        guard let display = content.displays.first(where: {
            $0.displayID == geometry.displayID
        }) else {
            throw ScrollingCaptureFrameSourceError.selectedDisplayUnavailable
        }

        let excludedApplications = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        filter.includeMenuBar = true

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect
        configuration.width = geometry.pixelWidth
        configuration.height = geometry.pixelHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        configuration.shouldBeOpaque = true

        installPreparedState(
            filter: filter,
            configuration: configuration,
            geometry: geometry
        )
        return geometry
    }

    func captureFrame() async throws -> CGImage {
        let state = preparedState()
        guard let filter = state.filter,
              let configuration = state.configuration,
              let geometry = state.geometry else {
            throw ScrollingCaptureAutoCaptureError.notPrepared
        }
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard image.width == geometry.pixelWidth,
              image.height == geometry.pixelHeight else {
            throw ScrollingCaptureError.inconsistentFrameSize(
                expected: CGSize(width: geometry.pixelWidth, height: geometry.pixelHeight),
                actual: CGSize(width: image.width, height: image.height)
            )
        }
        return image
    }

    func stop() async {
        clearPreparedState()
    }

    private func installPreparedState(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        geometry: ScrollingCaptureRegionGeometry
    ) {
        lock.lock()
        self.filter = filter
        streamConfiguration = configuration
        self.geometry = geometry
        lock.unlock()
    }

    private func clearPreparedState() {
        lock.lock()
        filter = nil
        streamConfiguration = nil
        geometry = nil
        lock.unlock()
    }

    private func preparedState() -> (
        filter: SCContentFilter?,
        configuration: SCStreamConfiguration?,
        geometry: ScrollingCaptureRegionGeometry?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (filter, streamConfiguration, geometry)
    }
}

/// Satisfies the discrete "capture on demand" contract using the same persistent,
/// low-latency `SCStream` that manual capture streams from, instead of requesting
/// a brand-new `SCScreenshotManager` screenshot for every step.
///
/// `SCScreenshotManager.captureImage` re-establishes capture state on every call,
/// which is appropriate for an occasional single screenshot but adds real,
/// avoidable round-trip latency when it runs once per scroll step, repeatedly,
/// for the whole capture. A continuous stream amortizes that setup cost once and
/// keeps a frame ready essentially all the time.
///
/// `captureFrame()` still returns only a frame strictly newer than the one it
/// last handed back, which preserves the same correctness property the discrete
/// contract documents: a synthetic scroll step is never registered against a
/// stale, pre-scroll frame.
nonisolated final class ScrollingCaptureContinuousDiscreteFrameSource:
    ScrollingCaptureDiscreteFrameSourcing,
    @unchecked Sendable
{
    private let continuousSource: ScrollingCaptureFrameSourcing
    private let pollInterval: Duration
    private let acquisitionTimeout: Duration

    private let lock = NSLock()
    private var latestFrame: CGImage?
    private var latestSequence: UInt64 = 0
    private var lastReturnedSequence: UInt64 = 0

    init(
        continuousSource: ScrollingCaptureFrameSourcing = ScrollingCaptureFrameSource(),
        pollInterval: Duration = .milliseconds(3),
        acquisitionTimeout: Duration = .milliseconds(750)
    ) {
        self.continuousSource = continuousSource
        self.pollInterval = pollInterval
        self.acquisitionTimeout = acquisitionTimeout
    }

    func prepare(selectedRegion: CGRect) async throws -> ScrollingCaptureRegionGeometry {
        try await continuousSource.start(
            selectedRegion: selectedRegion,
            onFrame: { [weak self] frame in self?.store(frame.image) },
            onFailure: { _ in
                // A mid-capture stream failure surfaces through the next
                // captureFrame() timeout instead of a separate error path, so
                // the auto-capture loop's existing failure handling still applies.
            }
        )
    }

    func captureFrame() async throws -> CGImage {
        let deadline = ContinuousClock.now.advanced(by: acquisitionTimeout)
        while true {
            // The baseline is whatever this caller last consumed, not whatever
            // happened to be buffered the instant this call started: a frame that
            // arrived while the caller was still sleeping (e.g. mid-settle-delay)
            // is legitimately fresh and must be returned immediately, not awaited
            // past again.
            if let frame = takeFreshFrame() {
                return frame
            }
            guard ContinuousClock.now < deadline else {
                throw ScrollingCaptureAutoCaptureError.frameAcquisitionTimedOut
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    func stop() async {
        try? await continuousSource.stop()
        lock.lock()
        latestFrame = nil
        latestSequence = 0
        lastReturnedSequence = 0
        lock.unlock()
    }

    private func store(_ image: CGImage) {
        lock.lock()
        latestFrame = image
        latestSequence &+= 1
        lock.unlock()
    }

    private func takeFreshFrame() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let latestFrame, latestSequence > lastReturnedSequence else { return nil }
        lastReturnedSequence = latestSequence
        return latestFrame
    }
}

/// Posts continuous pixel-wheel events at the selection center. CGEvent uses a
/// top-left desktop origin while AppKit selection geometry uses bottom-left.
nonisolated final class ScrollingCaptureCGEventScrollDriver:
    ScrollingCaptureScrollDriving,
    @unchecked Sendable
{
    private let eventSource = CGEventSource(stateID: .combinedSessionState)

    func scroll(verticalDelta: Int, at appKitPoint: CGPoint) throws {
        guard verticalDelta != 0 else { return }
        guard CGPreflightPostEventAccess() else {
            throw ScrollingCaptureAutoCaptureError.postEventPermissionDenied
        }
        // The first screen owns the AppKit global origin/menu bar. Using its top
        // preserves correct Quartz coordinates for displays above or below it.
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? appKitPoint.y
        let quartzPoint = CGPoint(
            x: appKitPoint.x,
            y: desktopTop - appKitPoint.y
        )
        let wheelDelta = Int32(clamping: -verticalDelta)
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: wheelDelta,
            wheel2: 0,
            wheel3: 0
        ) else {
            throw ScrollingCaptureAutoCaptureError.eventCreationFailed
        }
        event.location = quartzPoint
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: Int64(wheelDelta)
        )
        event.post(tap: .cghidEventTap)
    }
}
