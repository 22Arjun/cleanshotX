//
//  ScrollingCaptureFrameSource.swift
//  clearshotX
//

import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Live ScreenCaptureKit source for one fixed, single-display scrolling viewport.
/// Frame delivery is intentionally independent from stitching so capture lifecycle,
/// UI, and the registration algorithm can evolve and be tested separately.
nonisolated final class ScrollingCaptureFrameSource: NSObject,
    ScrollingCaptureFrameSourcing,
    @unchecked Sendable
{
    private struct QueuedFrame: @unchecked Sendable {
        let sampleBuffer: CMSampleBuffer
        let deliveryGeneration: UInt64
    }

    typealias FrameHandler = @Sendable (ScrollingCaptureStreamFrame) -> Void
    typealias FailureHandler = @Sendable (Error) -> Void

    private let sampleQueue = DispatchQueue(
        label: "com.clearshotx.scrolling-capture.samples",
        qos: .userInteractive
    )
    private let processingQueue = DispatchQueue(
        label: "com.clearshotx.scrolling-capture.processing",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    private var stream: SCStream?
    private var geometry: ScrollingCaptureRegionGeometry?
    private var frameHandler: FrameHandler?
    private var failureHandler: FailureHandler?
    private var processor: LatestValueProcessor<QueuedFrame>?
    private var isStarting = false
    private var isStopping = false
    private var isFrameDeliveryEnabled = false
    private var deliveryGeneration: UInt64 = 0

    func start(
        selectedRegion: CGRect,
        onFrame: @escaping FrameHandler,
        onFailure: @escaping FailureHandler
    ) async throws -> ScrollingCaptureRegionGeometry {
        try reserveStart()
        do {
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

            let excludedApplications = content.applications.filter { application in
                application.bundleIdentifier == Bundle.main.bundleIdentifier
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
            // Native-resolution output is never scaled down. A 30 fps acquisition
            // cadence keeps adjacent frames overlapping even during quick trackpad
            // movement; latest-wins backpressure still bounds analysis to one frame.
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 3
            configuration.showsCursor = false
            configuration.scalesToFit = false
            configuration.captureResolution = .best

            let stream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: self
            )
            let processor = LatestValueProcessor<QueuedFrame>(
                queue: processingQueue
            ) { [weak self] queuedFrame in
                self?.process(queuedFrame)
            }

            installState(
                stream: stream,
                geometry: geometry,
                frameHandler: onFrame,
                failureHandler: onFailure,
                processor: processor
            )
            try stream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: sampleQueue
            )
            try await stream.startCapture()
            return geometry
        } catch {
            clearState(cancelProcessor: true)
            throw error
        }
    }

    func stop() async throws {
        let activeStream = prepareToStop()
        guard let activeStream else { return }
        defer { clearState(cancelProcessor: true) }
        try await activeStream.stopCapture()
        try? activeStream.removeStreamOutput(self, type: .screen)
    }

    func setFrameDeliveryEnabled(_ isEnabled: Bool) {
        stateLock.lock()
        if isFrameDeliveryEnabled != isEnabled {
            isFrameDeliveryEnabled = isEnabled
            deliveryGeneration &+= 1
        }
        stateLock.unlock()
    }

    private func process(_ queuedFrame: QueuedFrame) {
        let sampleBuffer = queuedFrame.sampleBuffer
        guard let attachment = sampleBuffer.frameAttachment,
              let statusRawValue = attachment[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let (geometry, frameHandler, isFrameDeliveryEnabled, deliveryGeneration) =
            currentFrameState()
        guard let geometry,
              let frameHandler,
              isFrameDeliveryEnabled,
              queuedFrame.deliveryGeneration == deliveryGeneration,
              ScrollingCaptureFrameGate.shouldProcess(
                status: status,
                pixelWidth: CVPixelBufferGetWidth(pixelBuffer),
                pixelHeight: CVPixelBufferGetHeight(pixelBuffer),
                expectedWidth: geometry.pixelWidth,
                expectedHeight: geometry.pixelHeight
              )
        else {
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            return
        }

        let dirtyRects = attachment[SCStreamFrameInfo.dirtyRects] as? [CGRect] ?? []
        let contentRect = attachment[SCStreamFrameInfo.contentRect] as? CGRect
        let scaleFactor = (attachment[SCStreamFrameInfo.scaleFactor] as? NSNumber)
            .map { CGFloat(truncating: $0) }
        frameHandler(
            ScrollingCaptureStreamFrame(
                image: cgImage,
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                dirtyRects: dirtyRects,
                contentRect: contentRect,
                scaleFactor: scaleFactor
            )
        )
    }

    private func clearState(cancelProcessor: Bool) {
        stateLock.lock()
        let activeProcessor = processor
        stream = nil
        geometry = nil
        frameHandler = nil
        failureHandler = nil
        processor = nil
        isStarting = false
        isStopping = false
        isFrameDeliveryEnabled = false
        deliveryGeneration &+= 1
        stateLock.unlock()

        if cancelProcessor {
            activeProcessor?.cancel()
        }
    }

    private func reserveStart() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard stream == nil, !isStarting else {
            throw ScrollingCaptureFrameSourceError.alreadyRunning
        }
        isStarting = true
        isStopping = false
    }

    private func installState(
        stream: SCStream,
        geometry: ScrollingCaptureRegionGeometry,
        frameHandler: @escaping FrameHandler,
        failureHandler: @escaping FailureHandler,
        processor: LatestValueProcessor<QueuedFrame>
    ) {
        stateLock.lock()
        self.stream = stream
        self.geometry = geometry
        self.frameHandler = frameHandler
        self.failureHandler = failureHandler
        self.processor = processor
        isStarting = false
        isFrameDeliveryEnabled = true
        deliveryGeneration &+= 1
        stateLock.unlock()
    }

    private func prepareToStop() -> SCStream? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let stream else { return nil }
        isStopping = true
        return stream
    }

    private func currentFrameState() -> (
        ScrollingCaptureRegionGeometry?,
        FrameHandler?,
        Bool,
        UInt64
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (geometry, frameHandler, isFrameDeliveryEnabled, deliveryGeneration)
    }

    private func currentSubmissionState() -> (
        LatestValueProcessor<QueuedFrame>?,
        isEnabled: Bool,
        deliveryGeneration: UInt64
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (processor, isFrameDeliveryEnabled, deliveryGeneration)
    }

    private func failureState() -> (FailureHandler?, shouldNotify: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (failureHandler, !isStopping)
    }
}

nonisolated extension ScrollingCaptureFrameSource: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }

        let submissionState = currentSubmissionState()
        guard submissionState.isEnabled,
              let processor = submissionState.0
        else {
            return
        }
        processor.submit(
            QueuedFrame(
                sampleBuffer: sampleBuffer,
                deliveryGeneration: submissionState.deliveryGeneration
            )
        )
    }
}

nonisolated extension ScrollingCaptureFrameSource: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let (failureHandler, shouldNotify) = failureState()
        clearState(cancelProcessor: true)
        if shouldNotify {
            failureHandler?(error)
        }
    }
}

private nonisolated extension CMSampleBuffer {
    var frameAttachment: [SCStreamFrameInfo: Any]? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            self,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]] else {
            return nil
        }
        return attachments.first
    }
}
