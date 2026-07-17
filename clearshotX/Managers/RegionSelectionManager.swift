//
//  RegionSelectionManager.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import ScreenCaptureKit

@MainActor final class RegionSelectionManager {
    private let captureDelay: Duration = .milliseconds(50)

    private var overlayWindows: [RegionSelectionWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var escapeMonitor: Any?
    private var isSelecting = false
    private var didPushCursor = false

    func selectRegion(magnifierMode: RegionMagnifierMode) async -> CGRect? {
        guard !isSelecting else { return nil }

        isSelecting = true
        let snapshots: [CGDirectDisplayID: CGImage]
        if magnifierMode == .off {
            snapshots = [:]
        } else {
            snapshots = await captureScreenSnapshots()
        }

        guard !Task.isCancelled else {
            isSelecting = false
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showOverlays(snapshots: snapshots, magnifierMode: magnifierMode)
        }
    }

    private func captureScreenSnapshots() async -> [CGDirectDisplayID: CGImage] {
        guard let content = try? await SCShareableContent.current else { return [:] }

        let excludedApplications = content.applications.filter { application in
            application.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        var snapshots: [CGDirectDisplayID: CGImage] = [:]

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            let filter = SCContentFilter(
                display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            filter.includeMenuBar = true

            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = false
            configuration.scalesToFit = false

            if let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
            {
                snapshots[displayID] = image
            }
        }

        return snapshots
    }

    private func showOverlays(
        snapshots: [CGDirectDisplayID: CGImage], magnifierMode: RegionMagnifierMode
    ) {
        overlayWindows = NSScreen.screens.map { screen in
            let window = RegionSelectionWindow(screen: screen)
            let overlayView = RegionSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                snapshot: screen.displayID.flatMap { snapshots[$0] },
                backingScale: screen.backingScaleFactor, magnifierMode: magnifierMode)

            overlayView.onComplete = { [weak self, weak window] localRect in
                guard let self, let window else { return }

                let globalRect = CGRect(
                    x: window.frame.minX + localRect.minX, y: window.frame.minY + localRect.minY,
                    width: localRect.width, height: localRect.height)
                finish(with: globalRect)
            }

            overlayView.onCancel = { [weak self] in self?.finish(with: nil) }

            window.contentView = overlayView
            return window
        }

        guard !overlayWindows.isEmpty else {
            finish(with: nil)
            return
        }

        installEscapeMonitor()
        NSApp.activate(ignoringOtherApps: true)

        overlayWindows.forEach { window in window.orderFrontRegardless() }

        let mouseLocation = NSEvent.mouseLocation
        let activeWindow =
            overlayWindows.first { $0.frame.contains(mouseLocation) } ?? overlayWindows.first
        activeWindow?.makeKeyAndOrderFront(nil)
        activeWindow?.makeFirstResponder(activeWindow?.contentView)

        NSCursor.crosshair.push()
        didPushCursor = true
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }

            Task { @MainActor in self?.finish(with: nil) }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        guard let escapeMonitor else { return }

        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }

    private func finish(with rect: CGRect?) {
        guard let continuation else { return }

        self.continuation = nil
        removeEscapeMonitor()

        overlayWindows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()

        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
        NSCursor.arrow.set()

        let captureDelay = self.captureDelay
        Task { @MainActor [weak self] in
            if rect != nil { try? await Task.sleep(for: captureDelay) }

            continuation.resume(returning: rect)
            self?.isSelecting = false
        }
    }
}

private final class RegionSelectionWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }
}

private final class RegionSelectionViewModel {
    let bounds: CGRect
    let backingScale: CGFloat

    private(set) var startPoint: CGPoint?
    private(set) var currentPoint: CGPoint?
    private(set) var cursorPoint: CGPoint?

    var hasStartedSelection: Bool { startPoint != nil }

    init(bounds: CGRect, backingScale: CGFloat) {
        self.bounds = bounds
        self.backingScale = max(1, backingScale)
    }

    var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }

        return CGRect(
            x: min(startPoint.x, currentPoint.x), y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x), height: abs(currentPoint.y - startPoint.y)
        ).pixelAligned(scale: backingScale).intersection(bounds)
    }

    var pixelDimensions: (width: Int, height: Int)? {
        guard let selectionRect else { return nil }

        return (
            width: Int((selectionRect.width * backingScale).rounded()),
            height: Int((selectionRect.height * backingScale).rounded())
        )
    }

    func moveCursor(to point: CGPoint) { cursorPoint = point.clamped(to: bounds) }

    func beginSelection(at point: CGPoint) {
        let point = point.clamped(to: bounds)
        startPoint = point
        currentPoint = point
        cursorPoint = point
    }

    func updateSelection(to point: CGPoint) {
        let point = point.clamped(to: bounds)
        currentPoint = point
        cursorPoint = point
    }

    func clearSelection() {
        startPoint = nil
        currentPoint = nil
    }
}

private final class RegionSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let snapshot: CGImage?
    private let magnifierMode: RegionMagnifierMode
    private let viewModel: RegionSelectionViewModel
    private var cursorTrackingArea: NSTrackingArea?

    init(
        frame frameRect: NSRect, snapshot: CGImage?, backingScale: CGFloat,
        magnifierMode: RegionMagnifierMode
    ) {
        self.snapshot = snapshot
        self.magnifierMode = magnifierMode
        self.viewModel = RegionSelectionViewModel(
            bounds: NSRect(origin: .zero, size: frameRect.size), backingScale: backingScale)
        super.init(frame: frameRect)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        guard let window else { return }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        viewModel.moveCursor(to: convert(windowPoint, from: nil))
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }

        let trackingArea = NSTrackingArea(
            rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseMoved], owner: self)
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseMoved(with event: NSEvent) {
        viewModel.moveCursor(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        viewModel.beginSelection(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        viewModel.updateSelection(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        viewModel.updateSelection(to: convert(event.locationInWindow, from: nil))

        guard let selectionRect = viewModel.selectionRect,
            let dimensions = viewModel.pixelDimensions, dimensions.width >= 2,
            dimensions.height >= 2
        else {
            cancel()
            return
        }

        onComplete?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancel()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDimmedOverlay()

        if let selectionRect = viewModel.selectionRect {
            drawSelectionBorder(for: selectionRect)
            drawSizeLabel(for: selectionRect)
        }

        if shouldShowMagnifier, let cursorPoint = viewModel.cursorPoint {
            drawLoupe(near: cursorPoint)
        }
    }

    private var shouldShowMagnifier: Bool {
        switch magnifierMode {
        case .automatic: !viewModel.hasStartedSelection
        case .always: true
        case .off: false
        }
    }

    private func drawDimmedOverlay() {
        let dimPath = NSBezierPath(rect: bounds)
        if let selectionRect = viewModel.selectionRect {
            dimPath.append(NSBezierPath(rect: selectionRect))
            dimPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.30).setFill()
        dimPath.fill()
    }

    private func drawSelectionBorder(for rect: CGRect) {
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 1 / viewModel.backingScale
        NSColor.white.setStroke()
        borderPath.stroke()
    }

    private func drawSizeLabel(for rect: CGRect) {
        guard let dimensions = viewModel.pixelDimensions else { return }

        let text = "\(dimensions.width) × \(dimensions.height)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 5
        let labelSize = CGSize(
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2)

        var labelOrigin = CGPoint(
            x: rect.midX - labelSize.width / 2, y: rect.minY - labelSize.height - 8)
        if labelOrigin.y < bounds.minY + 8 { labelOrigin.y = rect.maxY + 8 }
        labelOrigin.x = min(max(bounds.minX + 8, labelOrigin.x), bounds.maxX - labelSize.width - 8)

        let labelRect = CGRect(origin: labelOrigin, size: labelSize)
        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.78).setFill()
        backgroundPath.fill()

        attributedText.draw(in: labelRect.insetBy(dx: horizontalPadding, dy: verticalPadding))
    }

    private func drawLoupe(near cursorPoint: CGPoint) {
        guard let snapshot, bounds.width > 0, bounds.height > 0 else { return }

        let sampleSide = min(15, snapshot.width, snapshot.height)
        guard sampleSide > 0 else { return }

        let scaleX = CGFloat(snapshot.width) / bounds.width
        let scaleY = CGFloat(snapshot.height) / bounds.height
        let pixelX = cursorPoint.x * scaleX
        let pixelY = (bounds.height - cursorPoint.y) * scaleY
        let sampleSideValue = CGFloat(sampleSide)
        let cropOriginX = min(
            max(0, floor(pixelX - sampleSideValue / 2)), CGFloat(snapshot.width - sampleSide))
        let cropOriginY = min(
            max(0, floor(pixelY - sampleSideValue / 2)), CGFloat(snapshot.height - sampleSide))
        let cropRect = CGRect(
            x: cropOriginX, y: cropOriginY, width: sampleSideValue, height: sampleSideValue)

        guard let croppedImage = snapshot.cropping(to: cropRect) else { return }

        let loupeRect = loupeRect(near: cursorPoint)
        let imageRect = loupeRect.insetBy(dx: 5, dy: 5)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        NSColor.black.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: loupeRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: imageRect).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        let image = NSImage(
            cgImage: croppedImage, size: NSSize(width: sampleSide, height: sampleSide))
        image.draw(
            in: imageRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none])
        NSGraphicsContext.restoreGraphicsState()

        let outline = NSBezierPath(ovalIn: loupeRect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        NSColor.white.withAlphaComponent(0.92).setStroke()
        outline.stroke()

        drawLoupeCrosshair(in: imageRect)
    }

    private func loupeRect(near cursorPoint: CGPoint) -> CGRect {
        let diameter: CGFloat = 104
        let offset: CGFloat = 22
        let edgeInset: CGFloat = 8
        var x = cursorPoint.x + offset
        var y = cursorPoint.y + offset

        if x + diameter > bounds.maxX - edgeInset { x = cursorPoint.x - diameter - offset }
        if y + diameter > bounds.maxY - edgeInset { y = cursorPoint.y - diameter - offset }

        x = min(max(bounds.minX + edgeInset, x), bounds.maxX - diameter - edgeInset)
        y = min(max(bounds.minY + edgeInset, y), bounds.maxY - diameter - edgeInset)
        return CGRect(x: x, y: y, width: diameter, height: diameter)
    }

    private func drawLoupeCrosshair(in rect: CGRect) {
        let horizontal = NSBezierPath()
        horizontal.move(to: CGPoint(x: rect.minX, y: rect.midY))
        horizontal.line(to: CGPoint(x: rect.maxX, y: rect.midY))
        horizontal.lineWidth = 1

        let vertical = NSBezierPath()
        vertical.move(to: CGPoint(x: rect.midX, y: rect.minY))
        vertical.line(to: CGPoint(x: rect.midX, y: rect.maxY))
        vertical.lineWidth = 1

        NSColor.black.withAlphaComponent(0.62).setStroke()
        horizontal.stroke()
        vertical.stroke()

        let centerPixel = CGRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)
        let centerPath = NSBezierPath(rect: centerPixel)
        centerPath.lineWidth = 1
        NSColor.white.setStroke()
        centerPath.stroke()
    }

    private func cancel() {
        viewModel.clearSelection()
        needsDisplay = true
        onCancel?()
    }
}

extension NSScreen {
    fileprivate var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

extension CGPoint {
    fileprivate func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(rect.minX, x), rect.maxX), y: min(max(rect.minY, y), rect.maxY))
    }
}

extension CGRect {
    fileprivate func pixelAligned(scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let minimumX = floor(minX * scale) / scale
        let minimumY = floor(minY * scale) / scale
        let maximumX = ceil(maxX * scale) / scale
        let maximumY = ceil(maxY * scale) / scale

        return CGRect(
            x: minimumX, y: minimumY, width: max(0, maximumX - minimumX),
            height: max(0, maximumY - minimumY))
    }
}
