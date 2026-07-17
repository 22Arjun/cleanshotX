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
    private var cursorMonitor: Any?
    private var isSelecting = false

    func selectRegion(
        magnifierMode: RegionMagnifierMode,
        magnifierZoom: RegionMagnifierZoom,
        magnifierSize: RegionMagnifierSize,
        magnifierShowsPixelColor: Bool
    ) async -> CGRect? {
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
            showOverlays(
                snapshots: snapshots,
                magnifierMode: magnifierMode,
                magnifierZoom: magnifierZoom,
                magnifierSize: magnifierSize,
                magnifierShowsPixelColor: magnifierShowsPixelColor
            )
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
        snapshots: [CGDirectDisplayID: CGImage],
        magnifierMode: RegionMagnifierMode,
        magnifierZoom: RegionMagnifierZoom,
        magnifierSize: RegionMagnifierSize,
        magnifierShowsPixelColor: Bool
    ) {
        overlayWindows = NSScreen.screens.map { screen in
            let window = RegionSelectionWindow(screen: screen)
            let overlayView = RegionSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                snapshot: screen.displayID.flatMap { snapshots[$0] },
                backingScale: screen.backingScaleFactor,
                magnifierMode: magnifierMode,
                magnifierZoom: magnifierZoom,
                magnifierSize: magnifierSize,
                magnifierShowsPixelColor: magnifierShowsPixelColor
            )

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
        installCursorMonitor()
        NSApp.activate(ignoringOtherApps: true)

        overlayWindows.forEach { window in window.orderFrontRegardless() }

        let mouseLocation = NSEvent.mouseLocation
        let activeWindow =
            overlayWindows.first { $0.frame.contains(mouseLocation) } ?? overlayWindows.first
        activeWindow?.makeKeyAndOrderFront(nil)
        activeWindow?.makeFirstResponder(activeWindow?.contentView)

        overlayWindows.forEach { window in
            if let contentView = window.contentView {
                window.invalidateCursorRects(for: contentView)
            }
        }
        enforceCrosshairCursor()

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.enforceCrosshairCursor()
        }
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

    private func installCursorMonitor() {
        removeCursorMonitor()
        cursorMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .cursorUpdate]
        ) { [weak self] event in
            self?.enforceCrosshairCursor()
            return event
        }
    }

    private func removeCursorMonitor() {
        guard let cursorMonitor else { return }

        NSEvent.removeMonitor(cursorMonitor)
        self.cursorMonitor = nil
    }

    private func enforceCrosshairCursor() {
        guard isSelecting, continuation != nil else { return }
        NSCursor.crosshair.set()
    }

    private func finish(with rect: CGRect?) {
        guard let continuation else { return }

        self.continuation = nil
        removeEscapeMonitor()
        removeCursorMonitor()

        overlayWindows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()

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

private struct RegionResizeModifiers: OptionSet, Equatable {
    let rawValue: UInt8

    static let fromCenter = RegionResizeModifiers(rawValue: 1 << 0)
    static let lockAxis = RegionResizeModifiers(rawValue: 1 << 1)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: RegionResizeModifiers = []
        if eventFlags.contains(.option) { modifiers.insert(.fromCenter) }
        if eventFlags.contains(.shift) { modifiers.insert(.lockAxis) }
        self = modifiers
    }
}

private enum RegionResizeAxis {
    case horizontal
    case vertical
}

private final class RegionSelectionViewModel {
    let bounds: CGRect
    let backingScale: CGFloat

    private(set) var startPoint: CGPoint?
    private(set) var currentPoint: CGPoint?
    private(set) var cursorPoint: CGPoint?

    private var movementAnchor: CGPoint?
    private var movementStartPoint: CGPoint?
    private var movementCurrentPoint: CGPoint?

    private var resizeModifiers: RegionResizeModifiers = []
    private var resizePointerAnchor: CGPoint?
    private var resizeStartPoint: CGPoint?
    private var resizeCurrentPoint: CGPoint?
    private var lockedResizeAxis: RegionResizeAxis?
    private var canLockResizeAxis = false

    var hasStartedSelection: Bool { startPoint != nil }
    var isMovingSelection: Bool { movementAnchor != nil }

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

    func beginSelection(at point: CGPoint, modifiers: RegionResizeModifiers) {
        let point = point.clamped(to: bounds)
        startPoint = point
        currentPoint = point
        cursorPoint = point
        rebaseResizing(at: point, modifiers: modifiers)
    }

    func updateSelection(to point: CGPoint, modifiers: RegionResizeModifiers) {
        let point = point.clamped(to: bounds)

        if modifiers != resizeModifiers {
            rebaseResizing(at: cursorPoint ?? point, modifiers: modifiers)
        }

        guard let resizePointerAnchor,
              let resizeStartPoint,
              let resizeCurrentPoint
        else {
            currentPoint = point
            cursorPoint = point
            return
        }

        var delta = CGVector(
            dx: point.x - resizePointerAnchor.x,
            dy: point.y - resizePointerAnchor.y
        )
        delta = axisLockedDelta(delta, modifiers: modifiers)

        if modifiers.contains(.fromCenter) {
            delta = clampedCenteredResizeDelta(
                delta,
                startPoint: resizeStartPoint,
                currentPoint: resizeCurrentPoint
            )
            startPoint = resizeStartPoint.translated(
                by: CGVector(dx: -delta.dx, dy: -delta.dy)
            )
            currentPoint = resizeCurrentPoint.translated(by: delta)
        } else {
            startPoint = resizeStartPoint
            currentPoint = resizeCurrentPoint.translated(by: delta).clamped(to: bounds)
        }

        cursorPoint = point
    }

    func rebaseResizing(at point: CGPoint, modifiers: RegionResizeModifiers) {
        let point = point.clamped(to: bounds)
        resizeModifiers = modifiers
        resizePointerAnchor = point
        resizeStartPoint = startPoint ?? point
        resizeCurrentPoint = currentPoint ?? point
        lockedResizeAxis = nil
        canLockResizeAxis = selectionRect.map {
            $0.width > 0 && $0.height > 0
        } ?? false
        cursorPoint = point
    }

    func beginMovingSelection() {
        guard !isMovingSelection,
              let selectionRect,
              selectionRect.width > 0,
              selectionRect.height > 0,
              let startPoint,
              let currentPoint,
              let cursorPoint
        else {
            return
        }

        movementAnchor = cursorPoint
        movementStartPoint = startPoint
        movementCurrentPoint = currentPoint
    }

    func moveSelection(to point: CGPoint) {
        guard let movementAnchor,
              let movementStartPoint,
              let movementCurrentPoint
        else {
            return
        }

        let point = point.clamped(to: bounds)
        let originalRect = CGRect(
            x: min(movementStartPoint.x, movementCurrentPoint.x),
            y: min(movementStartPoint.y, movementCurrentPoint.y),
            width: abs(movementCurrentPoint.x - movementStartPoint.x),
            height: abs(movementCurrentPoint.y - movementStartPoint.y)
        )
        let proposedDelta = CGVector(
            dx: point.x - movementAnchor.x,
            dy: point.y - movementAnchor.y
        )
        let delta = clampedTranslation(proposedDelta, for: originalRect)

        startPoint = movementStartPoint.translated(by: delta)
        currentPoint = movementCurrentPoint.translated(by: delta)
        cursorPoint = point
    }

    func endMovingSelection() {
        movementAnchor = nil
        movementStartPoint = nil
        movementCurrentPoint = nil
    }

    @discardableResult
    func nudgeActiveCorner(by proposedDelta: CGVector, fromCenter: Bool) -> Bool {
        guard let startPoint,
              let currentPoint
        else {
            return false
        }

        let delta: CGVector
        if fromCenter {
            delta = clampedCenteredResizeDelta(
                proposedDelta,
                startPoint: startPoint,
                currentPoint: currentPoint
            )
            self.startPoint = startPoint.translated(
                by: CGVector(dx: -delta.dx, dy: -delta.dy)
            )
        } else {
            let adjustedPoint = currentPoint.translated(by: proposedDelta).clamped(to: bounds)
            delta = CGVector(
                dx: adjustedPoint.x - currentPoint.x,
                dy: adjustedPoint.y - currentPoint.y
            )
        }

        let adjustedPoint = currentPoint.translated(by: delta)
        self.currentPoint = adjustedPoint
        cursorPoint = adjustedPoint
        return delta.dx != 0 || delta.dy != 0
    }

    @discardableResult
    func nudgeSelection(by proposedDelta: CGVector) -> Bool {
        guard let startPoint,
              let currentPoint
        else {
            return false
        }

        let rawRect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        guard rawRect.width > 0, rawRect.height > 0 else {
            return false
        }

        let delta = clampedTranslation(proposedDelta, for: rawRect)
        self.startPoint = startPoint.translated(by: delta)
        self.currentPoint = currentPoint.translated(by: delta)

        if isMovingSelection {
            movementAnchor = self.currentPoint
            movementStartPoint = self.startPoint
            movementCurrentPoint = self.currentPoint
            cursorPoint = self.currentPoint
        } else {
            cursorPoint = self.currentPoint
        }
        return delta.dx != 0 || delta.dy != 0
    }

    func clearSelection() {
        startPoint = nil
        currentPoint = nil
        resizePointerAnchor = nil
        resizeStartPoint = nil
        resizeCurrentPoint = nil
        lockedResizeAxis = nil
        canLockResizeAxis = false
        endMovingSelection()
    }

    private func axisLockedDelta(
        _ delta: CGVector,
        modifiers: RegionResizeModifiers
    ) -> CGVector {
        guard modifiers.contains(.lockAxis), canLockResizeAxis else {
            return delta
        }

        if lockedResizeAxis == nil, delta.dx != 0 || delta.dy != 0 {
            lockedResizeAxis = abs(delta.dx) >= abs(delta.dy) ? .horizontal : .vertical
        }

        switch lockedResizeAxis {
        case .horizontal:
            return CGVector(dx: delta.dx, dy: 0)
        case .vertical:
            return CGVector(dx: 0, dy: delta.dy)
        case nil:
            return .zero
        }
    }

    private func clampedCenteredResizeDelta(
        _ delta: CGVector,
        startPoint: CGPoint,
        currentPoint: CGPoint
    ) -> CGVector {
        let minimumDX = max(
            bounds.minX - currentPoint.x,
            startPoint.x - bounds.maxX
        )
        let maximumDX = min(
            bounds.maxX - currentPoint.x,
            startPoint.x - bounds.minX
        )
        let minimumDY = max(
            bounds.minY - currentPoint.y,
            startPoint.y - bounds.maxY
        )
        let maximumDY = min(
            bounds.maxY - currentPoint.y,
            startPoint.y - bounds.minY
        )

        return CGVector(
            dx: min(max(delta.dx, minimumDX), maximumDX),
            dy: min(max(delta.dy, minimumDY), maximumDY)
        )
    }

    private func clampedTranslation(_ delta: CGVector, for rect: CGRect) -> CGVector {
        CGVector(
            dx: min(
                max(delta.dx, bounds.minX - rect.minX),
                bounds.maxX - rect.maxX
            ),
            dy: min(
                max(delta.dy, bounds.minY - rect.minY),
                bounds.maxY - rect.maxY
            )
        )
    }
}

private enum RegionLoupeQuadrant: CaseIterable {
    case upperRight
    case upperLeft
    case lowerRight
    case lowerLeft

    var direction: CGVector {
        switch self {
        case .upperRight:
            CGVector(dx: 1, dy: 1)
        case .upperLeft:
            CGVector(dx: -1, dy: 1)
        case .lowerRight:
            CGVector(dx: 1, dy: -1)
        case .lowerLeft:
            CGVector(dx: -1, dy: -1)
        }
    }

    func rect(near cursorPoint: CGPoint, size: CGSize, offset: CGFloat) -> CGRect {
        let x = direction.dx > 0
            ? cursorPoint.x + offset
            : cursorPoint.x - size.width - offset
        let y = direction.dy > 0
            ? cursorPoint.y + offset
            : cursorPoint.y - size.height - offset

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private struct RegionLoupePlacement {
    private struct Candidate {
        let index: Int
        let rect: CGRect
        let overflow: CGFloat
        let selectionOverlap: CGFloat
        let dragAlignment: CGFloat
    }

    static func rect(
        near cursorPoint: CGPoint,
        dragOrigin: CGPoint?,
        selectionRect: CGRect?,
        within bounds: CGRect,
        size: CGSize,
        offset: CGFloat,
        edgeInset: CGFloat
    ) -> CGRect {
        let safeBounds = bounds.insetBy(dx: edgeInset, dy: edgeInset)
        let avoidedSelection = selectionRect?.insetBy(dx: -12, dy: -12)
        let dragDirection = dragOrigin.map {
            CGVector(dx: cursorPoint.x - $0.x, dy: cursorPoint.y - $0.y)
        }

        let candidates = RegionLoupeQuadrant.allCases.enumerated().map { index, quadrant in
            let rect = quadrant.rect(near: cursorPoint, size: size, offset: offset)
            return Candidate(
                index: index,
                rect: rect,
                overflow: overflowDistance(of: rect, outside: safeBounds),
                selectionOverlap: overlapArea(of: rect, with: avoidedSelection),
                dragAlignment: alignment(of: quadrant.direction, with: dragDirection)
            )
        }

        let bestCandidate = candidates.min { lhs, rhs in
            if lhs.overflow != rhs.overflow {
                return lhs.overflow < rhs.overflow
            }
            if lhs.selectionOverlap != rhs.selectionOverlap {
                return lhs.selectionOverlap < rhs.selectionOverlap
            }
            if lhs.dragAlignment != rhs.dragAlignment {
                return lhs.dragAlignment > rhs.dragAlignment
            }
            return lhs.index < rhs.index
        }

        guard var rect = bestCandidate?.rect else {
            return CGRect(origin: cursorPoint, size: size)
        }

        rect.origin.x = min(max(safeBounds.minX, rect.minX), safeBounds.maxX - rect.width)
        rect.origin.y = min(max(safeBounds.minY, rect.minY), safeBounds.maxY - rect.height)
        return rect
    }

    private static func overflowDistance(of rect: CGRect, outside bounds: CGRect) -> CGFloat {
        max(0, bounds.minX - rect.minX)
            + max(0, rect.maxX - bounds.maxX)
            + max(0, bounds.minY - rect.minY)
            + max(0, rect.maxY - bounds.maxY)
    }

    private static func overlapArea(of rect: CGRect, with otherRect: CGRect?) -> CGFloat {
        guard let otherRect else {
            return 0
        }

        let intersection = rect.intersection(otherRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private static func alignment(
        of candidateDirection: CGVector,
        with dragDirection: CGVector?
    ) -> CGFloat {
        guard let dragDirection else {
            return 0
        }

        let dragLength = hypot(dragDirection.dx, dragDirection.dy)
        guard dragLength >= 2 else {
            return 0
        }

        return (
            candidateDirection.dx * dragDirection.dx
                + candidateDirection.dy * dragDirection.dy
        ) / (sqrt(2) * dragLength)
    }
}

private struct RegionPixelColor {
    let red: Int
    let green: Int
    let blue: Int

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var rgb: String {
        "RGB \(red) \(green) \(blue)"
    }

    var color: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

private final class RegionSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let snapshot: CGImage?
    private let magnifierMode: RegionMagnifierMode
    private let magnifierZoom: RegionMagnifierZoom
    private let magnifierSize: RegionMagnifierSize
    private let magnifierShowsPixelColor: Bool
    private let viewModel: RegionSelectionViewModel
    private var cursorTrackingArea: NSTrackingArea?
    private var isSpacePressed = false
    private var resizeModifiers: RegionResizeModifiers = []
    private var keyboardPointerOffset = CGVector.zero

    init(
        frame frameRect: NSRect,
        snapshot: CGImage?,
        backingScale: CGFloat,
        magnifierMode: RegionMagnifierMode,
        magnifierZoom: RegionMagnifierZoom,
        magnifierSize: RegionMagnifierSize,
        magnifierShowsPixelColor: Bool
    ) {
        self.snapshot = snapshot
        self.magnifierMode = magnifierMode
        self.magnifierZoom = magnifierZoom
        self.magnifierSize = magnifierSize
        self.magnifierShowsPixelColor = magnifierShowsPixelColor
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
        window?.invalidateCursorRects(for: self)
        enforceCrosshairCursor()

        guard let window else { return }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        viewModel.moveCursor(to: convert(windowPoint, from: nil))
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .activeAlways,
                .inVisibleRect,
                .mouseMoved,
                .mouseEnteredAndExited,
                .cursorUpdate,
            ],
            owner: self
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        enforceCrosshairCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        enforceCrosshairCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        enforceCrosshairCursor()
        viewModel.moveCursor(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        enforceCrosshairCursor()
        keyboardPointerOffset = .zero
        resizeModifiers = RegionResizeModifiers(eventFlags: event.modifierFlags)
        viewModel.beginSelection(
            at: convert(event.locationInWindow, from: nil),
            modifiers: resizeModifiers
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        enforceCrosshairCursor()
        let point = selectionPoint(for: event)
        resizeModifiers = RegionResizeModifiers(eventFlags: event.modifierFlags)
        if isSpacePressed {
            viewModel.beginMovingSelection()
            if viewModel.isMovingSelection {
                viewModel.moveSelection(to: point)
            } else {
                viewModel.updateSelection(to: point, modifiers: resizeModifiers)
            }
        } else {
            viewModel.endMovingSelection()
            viewModel.updateSelection(to: point, modifiers: resizeModifiers)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        enforceCrosshairCursor()
        let point = selectionPoint(for: event)
        if viewModel.isMovingSelection {
            viewModel.moveSelection(to: point)
        } else {
            resizeModifiers = RegionResizeModifiers(eventFlags: event.modifierFlags)
            viewModel.updateSelection(to: point, modifiers: resizeModifiers)
        }
        viewModel.endMovingSelection()

        guard let selectionRect = viewModel.selectionRect,
            let dimensions = viewModel.pixelDimensions, dimensions.width >= 2,
            dimensions.height >= 2
        else {
            cancel()
            return
        }

        onComplete?(selectionRect)
    }

    override func flagsChanged(with event: NSEvent) {
        let updatedModifiers = RegionResizeModifiers(eventFlags: event.modifierFlags)
        guard updatedModifiers != resizeModifiers else {
            super.flagsChanged(with: event)
            return
        }

        resizeModifiers = updatedModifiers
        if viewModel.hasStartedSelection,
           !isSpacePressed,
           let cursorPoint = viewModel.cursorPoint
        {
            viewModel.rebaseResizing(at: cursorPoint, modifiers: resizeModifiers)
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            cancel()
        case 49:
            if !event.isARepeat {
                isSpacePressed = true
                viewModel.beginMovingSelection()
                needsDisplay = true
            }
        case 123, 124, 125, 126:
            nudgeSelection(for: event)
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else {
            super.keyUp(with: event)
            return
        }

        isSpacePressed = false
        viewModel.endMovingSelection()
        if let cursorPoint = viewModel.cursorPoint {
            viewModel.rebaseResizing(at: cursorPoint, modifiers: resizeModifiers)
        }
        needsDisplay = true
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

    private func enforceCrosshairCursor() {
        NSCursor.crosshair.set()
    }

    private func nudgeSelection(for event: NSEvent) {
        let pixelStep: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let step = pixelStep / viewModel.backingScale
        let delta: CGVector

        switch event.keyCode {
        case 123:
            delta = CGVector(dx: -step, dy: 0)
        case 124:
            delta = CGVector(dx: step, dy: 0)
        case 125:
            delta = CGVector(dx: 0, dy: -step)
        case 126:
            delta = CGVector(dx: 0, dy: step)
        default:
            return
        }

        let previousCurrentPoint = viewModel.currentPoint
        resizeModifiers = RegionResizeModifiers(eventFlags: event.modifierFlags)
        let didAdjust = isSpacePressed
            ? viewModel.nudgeSelection(by: delta)
            : viewModel.nudgeActiveCorner(
                by: delta,
                fromCenter: resizeModifiers.contains(.fromCenter)
            )
        guard didAdjust,
              let previousCurrentPoint,
              let currentPoint = viewModel.currentPoint
        else {
            return
        }

        keyboardPointerOffset.dx += currentPoint.x - previousCurrentPoint.x
        keyboardPointerOffset.dy += currentPoint.y - previousCurrentPoint.y
        viewModel.rebaseResizing(at: currentPoint, modifiers: resizeModifiers)
        needsDisplay = true
    }

    private func selectionPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: point.x + keyboardPointerOffset.dx,
            y: point.y + keyboardPointerOffset.dy
        ).clamped(to: bounds)
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

        let loupeRect = loupeRect(near: cursorPoint)
        let contentInset: CGFloat = 6
        let imageRect = loupeRect.insetBy(dx: contentInset, dy: contentInset)
        let sampleWidth = samplePixelCount(
            for: imageRect.width,
            maximum: snapshot.width
        )
        let sampleHeight = samplePixelCount(
            for: imageRect.height,
            maximum: snapshot.height
        )
        guard sampleWidth > 0, sampleHeight > 0 else { return }

        let scaleX = CGFloat(snapshot.width) / bounds.width
        let scaleY = CGFloat(snapshot.height) / bounds.height
        let pixelX = cursorPoint.x * scaleX
        let pixelY = (bounds.height - cursorPoint.y) * scaleY
        let targetPixelX = min(
            max(0, Int(floor(pixelX))),
            snapshot.width - 1
        )
        let targetPixelY = min(
            max(0, Int(floor(pixelY))),
            snapshot.height - 1
        )
        let cropOriginX = min(
            max(0, targetPixelX - sampleWidth / 2),
            snapshot.width - sampleWidth
        )
        let cropOriginY = min(
            max(0, targetPixelY - sampleHeight / 2),
            snapshot.height - sampleHeight
        )
        let cropRect = CGRect(
            x: CGFloat(cropOriginX),
            y: CGFloat(cropOriginY),
            width: CGFloat(sampleWidth),
            height: CGFloat(sampleHeight)
        )

        guard let croppedImage = snapshot.cropping(to: cropRect) else { return }

        let outerCornerRadius: CGFloat = 14
        let innerCornerRadius: CGFloat = 9

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        NSColor.black.withAlphaComponent(0.92).setFill()
        NSBezierPath(
            roundedRect: loupeRect,
            xRadius: outerCornerRadius,
            yRadius: outerCornerRadius
        ).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            roundedRect: imageRect,
            xRadius: innerCornerRadius,
            yRadius: innerCornerRadius
        ).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        let image = NSImage(
            cgImage: croppedImage,
            size: NSSize(width: CGFloat(sampleWidth), height: CGFloat(sampleHeight))
        )
        image.draw(
            in: imageRect,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        NSGraphicsContext.restoreGraphicsState()

        let pixelSize = CGSize(
            width: imageRect.width / CGFloat(sampleWidth),
            height: imageRect.height / CGFloat(sampleHeight)
        )
        let targetPixelRect = CGRect(
            x: imageRect.minX + CGFloat(targetPixelX - cropOriginX) * pixelSize.width,
            y: imageRect.maxY
                - CGFloat(targetPixelY - cropOriginY + 1) * pixelSize.height,
            width: pixelSize.width,
            height: pixelSize.height
        )
        drawLoupeCrosshair(in: imageRect, targetPixelRect: targetPixelRect)

        if magnifierShowsPixelColor,
           let pixelColor = pixelColor(
               in: snapshot,
               x: targetPixelX,
               y: targetPixelY
           ) {
            drawPixelColorReadout(
                pixelColor,
                in: imageRect,
                avoiding: targetPixelRect,
                cornerRadius: innerCornerRadius
            )
        }

        let outline = NSBezierPath(
            roundedRect: loupeRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: outerCornerRadius,
            yRadius: outerCornerRadius
        )
        outline.lineWidth = 1
        NSColor.white.withAlphaComponent(0.92).setStroke()
        outline.stroke()
    }

    private func loupeRect(near cursorPoint: CGPoint) -> CGRect {
        let offset: CGFloat = 22
        let edgeInset: CGFloat = 8

        return RegionLoupePlacement.rect(
            near: cursorPoint,
            dragOrigin: viewModel.startPoint,
            selectionRect: viewModel.selectionRect,
            within: bounds,
            size: magnifierSize.dimensions,
            offset: offset,
            edgeInset: edgeInset
        )
    }

    private func samplePixelCount(for displayLength: CGFloat, maximum: Int) -> Int {
        let desiredCount = max(
            1,
            Int((displayLength / CGFloat(magnifierZoom.rawValue)).rounded())
        )
        let oddCount = desiredCount.isMultiple(of: 2) ? desiredCount + 1 : desiredCount
        return min(maximum, oddCount)
    }

    private func drawLoupeCrosshair(in rect: CGRect, targetPixelRect: CGRect) {
        let horizontal = NSBezierPath()
        horizontal.move(to: CGPoint(x: rect.minX, y: targetPixelRect.midY))
        horizontal.line(to: CGPoint(x: rect.maxX, y: targetPixelRect.midY))
        horizontal.lineWidth = 1

        let vertical = NSBezierPath()
        vertical.move(to: CGPoint(x: targetPixelRect.midX, y: rect.minY))
        vertical.line(to: CGPoint(x: targetPixelRect.midX, y: rect.maxY))
        vertical.lineWidth = 1

        NSColor.black.withAlphaComponent(0.62).setStroke()
        horizontal.stroke()
        vertical.stroke()

        let centerPath = NSBezierPath(rect: targetPixelRect)
        centerPath.lineWidth = 1
        NSColor.white.setStroke()
        centerPath.stroke()
    }

    private func pixelColor(in image: CGImage, x: Int, y: Int) -> RegionPixelColor? {
        let pixelRect = CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1)
        guard let pixelImage = image.cropping(to: pixelRect) else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let address = buffer.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: address,
                      width: 1,
                      height: 1,
                      bitsPerComponent: 8,
                      bytesPerRow: 4,
                      space: colorSpace,
                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                          | CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }

        guard rendered else {
            return nil
        }

        let alpha = Int(bytes[3])
        func unpremultiplied(_ component: UInt8) -> Int {
            guard alpha > 0, alpha < 255 else {
                return Int(component)
            }
            return min(255, Int(component) * 255 / alpha)
        }

        return RegionPixelColor(
            red: unpremultiplied(bytes[0]),
            green: unpremultiplied(bytes[1]),
            blue: unpremultiplied(bytes[2])
        )
    }

    private func drawPixelColorReadout(
        _ pixelColor: RegionPixelColor,
        in imageRect: CGRect,
        avoiding targetPixelRect: CGRect,
        cornerRadius: CGFloat
    ) {
        let footerHeight = min(26, imageRect.height * 0.40)
        let footerY = targetPixelRect.midY >= imageRect.midY
            ? imageRect.minY
            : imageRect.maxY - footerHeight
        let footerRect = CGRect(
            x: imageRect.minX,
            y: footerY,
            width: imageRect.width,
            height: footerHeight
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            roundedRect: imageRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).addClip()

        NSColor.black.withAlphaComponent(0.84).setFill()
        footerRect.fill()

        let separator = NSBezierPath()
        let separatorY = footerRect.minY == imageRect.minY
            ? footerRect.maxY
            : footerRect.minY
        separator.move(to: CGPoint(x: footerRect.minX, y: separatorY))
        separator.line(to: CGPoint(x: footerRect.maxX, y: separatorY))
        separator.lineWidth = 1 / viewModel.backingScale
        NSColor.white.withAlphaComponent(0.26).setStroke()
        separator.stroke()

        let swatchSide = min(14, footerRect.height - 10)
        let swatchRect = CGRect(
            x: footerRect.minX + 6,
            y: footerRect.midY - swatchSide / 2,
            width: swatchSide,
            height: swatchSide
        )
        let swatchPath = NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3)
        pixelColor.color.setFill()
        swatchPath.fill()
        NSColor.white.withAlphaComponent(0.72).setStroke()
        swatchPath.lineWidth = 0.75
        swatchPath.stroke()

        let textX = swatchRect.maxX + 6
        let textWidth = max(0, footerRect.maxX - textX - 4)
        let hexText = NSAttributedString(
            string: pixelColor.hex,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        let rgbText = NSAttributedString(
            string: pixelColor.rgb,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.76),
            ]
        )
        hexText.draw(
            in: CGRect(
                x: textX,
                y: footerRect.midY,
                width: textWidth,
                height: footerRect.height / 2
            )
        )
        rgbText.draw(
            in: CGRect(
                x: textX,
                y: footerRect.minY + 3,
                width: textWidth,
                height: footerRect.height / 2
            )
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private func cancel() {
        isSpacePressed = false
        keyboardPointerOffset = .zero
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

    fileprivate func translated(by delta: CGVector) -> CGPoint {
        CGPoint(x: x + delta.dx, y: y + delta.dy)
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
