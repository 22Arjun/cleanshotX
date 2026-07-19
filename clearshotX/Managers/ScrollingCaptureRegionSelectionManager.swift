//
//  ScrollingCaptureRegionSelectionManager.swift
//  clearshotX
//

import AppKit

@MainActor
protocol ScrollingCaptureRegionSelecting: AnyObject {
    func selectRegion() async -> CGRect?
    func dismissSelectionOverlay()
}

/// A dedicated two-stage selector for scrolling capture. Unlike ordinary region
/// capture, mouse-up does not commit the rectangle: the user can move, resize,
/// nudge, and inspect the native pixel dimensions before starting the stream.
@MainActor
final class ScrollingCaptureRegionSelectionManager: ScrollingCaptureRegionSelecting {
    private var windows: [ScrollingRegionSelectionWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var escapeMonitor: Any?
    private var previousApplication: NSRunningApplication?
    private var isSelecting = false

    func selectRegion() async -> CGRect? {
        guard !isSelecting else { return nil }
        isSelecting = true
        previousApplication = NSWorkspace.shared.frontmostApplication

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            presentSelectionWindows()
        }
    }

    func dismissSelectionOverlay() {
        removeEscapeMonitor()
        windows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        NSCursor.arrow.set()
    }

    private func presentSelectionWindows() {
        let displays = NSScreen.screens.map {
            ScrollingSelectionDisplay(
                frame: $0.frame,
                backingScale: max(1, $0.backingScaleFactor)
            )
        }
        guard !displays.isEmpty else {
            complete(with: nil, preserveOverlay: false)
            return
        }

        let state = ScrollingRegionSelectionState(displays: displays)
        windows = NSScreen.screens.map { screen in
            let selectionView = ScrollingRegionSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                backingScale: max(1, screen.backingScaleFactor),
                state: state
            )
            let window = ScrollingRegionSelectionWindow(
                screen: screen,
                selectionView: selectionView
            )
            selectionView.onChange = { [weak self] in
                self?.windows.forEach { $0.selectionView.needsDisplay = true }
            }
            selectionView.onConfirm = { [weak self] rect in
                self?.complete(with: rect, preserveOverlay: true)
            }
            selectionView.onCancel = { [weak self] in
                self?.complete(with: nil, preserveOverlay: false)
            }
            return window
        }

        installEscapeMonitor()
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }

        let mouseLocation = NSEvent.mouseLocation
        let activeWindow = windows.first(where: { $0.frame.contains(mouseLocation) })
            ?? windows.first
        activeWindow?.makeKeyAndOrderFront(nil)
        activeWindow?.makeFirstResponder(activeWindow?.selectionView)
        NSCursor.crosshair.set()
    }

    private func complete(with rect: CGRect?, preserveOverlay: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        isSelecting = false
        removeEscapeMonitor()

        if preserveOverlay, let rect {
            windows.forEach { window in
                window.selectionView.lockSelection()
                window.ignoresMouseEvents = true
            }
            reactivatePreviousApplication()
            continuation.resume(returning: rect)
        } else {
            dismissSelectionOverlay()
            reactivatePreviousApplication()
            continuation.resume(returning: nil)
        }
    }

    private func reactivatePreviousApplication() {
        guard let previousApplication,
              previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return
        }
        previousApplication.activate(options: [])
        self.previousApplication = nil
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.complete(with: nil, preserveOverlay: false)
            return nil
        }
    }

    private func removeEscapeMonitor() {
        guard let escapeMonitor else { return }
        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }
}

private struct ScrollingSelectionDisplay {
    let frame: CGRect
    let backingScale: CGFloat
}

private enum ScrollingSelectionHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

private enum ScrollingSelectionOperation {
    case drawing(anchor: CGPoint)
    case moving(anchor: CGPoint, original: CGRect)
    case resizing(handle: ScrollingSelectionHandle, anchor: CGPoint, original: CGRect)
}

private final class ScrollingRegionSelectionState {
    private let displays: [ScrollingSelectionDisplay]
    private(set) var selectionRect: CGRect?
    private(set) var activeDisplay: ScrollingSelectionDisplay?
    private(set) var operation: ScrollingSelectionOperation?
    private(set) var isLocked = false

    private let minimumSize = CGSize(width: 80, height: 60)

    init(displays: [ScrollingSelectionDisplay]) {
        self.displays = displays
    }

    var isReady: Bool {
        guard let selectionRect else { return false }
        return selectionRect.width >= minimumSize.width
            && selectionRect.height >= minimumSize.height
    }

    var pixelDimensions: CGSize? {
        guard let selectionRect, let activeDisplay else { return nil }
        return CGSize(
            width: (selectionRect.width * activeDisplay.backingScale).rounded(),
            height: (selectionRect.height * activeDisplay.backingScale).rounded()
        )
    }

    func begin(at point: CGPoint) {
        guard !isLocked,
              let display = displays.first(where: { $0.frame.contains(point) })
        else {
            return
        }
        activeDisplay = display

        if let selectionRect, isReady {
            if let handle = handle(at: point, in: selectionRect) {
                operation = .resizing(handle: handle, anchor: point, original: selectionRect)
                return
            }
            if selectionRect.contains(point) {
                operation = .moving(anchor: point, original: selectionRect)
                return
            }
        }

        selectionRect = CGRect(origin: point, size: .zero)
        operation = .drawing(anchor: point)
    }

    func update(to proposedPoint: CGPoint) {
        guard !isLocked,
              let operation,
              let display = activeDisplay
        else {
            return
        }
        let point = proposedPoint.clamped(to: display.frame)

        switch operation {
        case let .drawing(anchor):
            selectionRect = aligned(
                CGRect(
                    x: min(anchor.x, point.x),
                    y: min(anchor.y, point.y),
                    width: abs(point.x - anchor.x),
                    height: abs(point.y - anchor.y)
                ),
                display: display
            )

        case let .moving(anchor, original):
            let proposed = CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y)
            let delta = CGVector(
                dx: min(
                    max(proposed.dx, display.frame.minX - original.minX),
                    display.frame.maxX - original.maxX
                ),
                dy: min(
                    max(proposed.dy, display.frame.minY - original.minY),
                    display.frame.maxY - original.maxY
                )
            )
            selectionRect = aligned(
                original.offsetBy(dx: delta.dx, dy: delta.dy),
                display: display
            )

        case let .resizing(handle, _, original):
            selectionRect = aligned(
                resized(original, handle: handle, to: point, bounds: display.frame),
                display: display
            )
        }
    }

    func endOperation() {
        operation = nil
        if !isReady {
            selectionRect = nil
            activeDisplay = nil
        }
    }

    func lock() {
        operation = nil
        isLocked = true
    }

    func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard !isLocked,
              let display = activeDisplay,
              let selectionRect
        else {
            return
        }
        let stepX = dx / display.backingScale
        let stepY = dy / display.backingScale

        if resize {
            let point = CGPoint(
                x: selectionRect.maxX + stepX,
                y: selectionRect.maxY + stepY
            )
            self.selectionRect = aligned(
                resized(
                    selectionRect,
                    handle: .topRight,
                    to: point.clamped(to: display.frame),
                    bounds: display.frame
                ),
                display: display
            )
        } else {
            let proposed = selectionRect.offsetBy(dx: stepX, dy: stepY)
            let clampedX = min(
                max(proposed.minX, display.frame.minX),
                display.frame.maxX - proposed.width
            )
            let clampedY = min(
                max(proposed.minY, display.frame.minY),
                display.frame.maxY - proposed.height
            )
            self.selectionRect = aligned(
                CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: proposed.size),
                display: display
            )
        }
    }

    func handle(at point: CGPoint, in rect: CGRect? = nil) -> ScrollingSelectionHandle? {
        guard let rect = rect ?? selectionRect else { return nil }
        return ScrollingSelectionHandle.allCases.first { handle in
            handleRect(for: handle, selectionRect: rect).contains(point)
        }
    }

    func handleRect(
        for handle: ScrollingSelectionHandle,
        selectionRect: CGRect
    ) -> CGRect {
        let center: CGPoint
        switch handle {
        case .topLeft:
            center = CGPoint(x: selectionRect.minX, y: selectionRect.maxY)
        case .top:
            center = CGPoint(x: selectionRect.midX, y: selectionRect.maxY)
        case .topRight:
            center = CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)
        case .right:
            center = CGPoint(x: selectionRect.maxX, y: selectionRect.midY)
        case .bottomRight:
            center = CGPoint(x: selectionRect.maxX, y: selectionRect.minY)
        case .bottom:
            center = CGPoint(x: selectionRect.midX, y: selectionRect.minY)
        case .bottomLeft:
            center = CGPoint(x: selectionRect.minX, y: selectionRect.minY)
        case .left:
            center = CGPoint(x: selectionRect.minX, y: selectionRect.midY)
        }
        return CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
    }

    private func resized(
        _ original: CGRect,
        handle: ScrollingSelectionHandle,
        to point: CGPoint,
        bounds: CGRect
    ) -> CGRect {
        var minimumX = original.minX
        var maximumX = original.maxX
        var minimumY = original.minY
        var maximumY = original.maxY

        switch handle {
        case .topLeft, .left, .bottomLeft:
            minimumX = min(point.x, maximumX - minimumSize.width)
        case .topRight, .right, .bottomRight:
            maximumX = max(point.x, minimumX + minimumSize.width)
        case .top, .bottom:
            break
        }

        switch handle {
        case .topLeft, .top, .topRight:
            maximumY = max(point.y, minimumY + minimumSize.height)
        case .bottomLeft, .bottom, .bottomRight:
            minimumY = min(point.y, maximumY - minimumSize.height)
        case .left, .right:
            break
        }

        return CGRect(
            x: max(bounds.minX, minimumX),
            y: max(bounds.minY, minimumY),
            width: min(bounds.maxX, maximumX) - max(bounds.minX, minimumX),
            height: min(bounds.maxY, maximumY) - max(bounds.minY, minimumY)
        )
    }

    private func aligned(_ rect: CGRect, display: ScrollingSelectionDisplay) -> CGRect {
        let scale = display.backingScale
        let minimumX = (rect.minX * scale).rounded() / scale
        let minimumY = (rect.minY * scale).rounded() / scale
        let maximumX = (rect.maxX * scale).rounded() / scale
        let maximumY = (rect.maxY * scale).rounded() / scale
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: max(0, maximumX - minimumX),
            height: max(0, maximumY - minimumY)
        ).intersection(display.frame)
    }
}

private final class ScrollingRegionSelectionView: NSView {
    var onChange: (() -> Void)?
    var onConfirm: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let screenFrame: CGRect
    private let backingScale: CGFloat
    private let state: ScrollingRegionSelectionState
    private var trackingArea: NSTrackingArea?
    private var pressedControl: Control?

    private enum Control {
        case cancel
        case start
    }

    init(
        frame frameRect: NSRect,
        screenFrame: CGRect,
        backingScale: CGFloat,
        state: ScrollingRegionSelectionState
    ) {
        self.screenFrame = screenFrame
        self.backingScale = backingScale
        self.state = state
        super.init(frame: frameRect)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: globalPoint(for: event))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: globalPoint(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(for: event)
        if let control = control(at: point) {
            pressedControl = control
            needsDisplay = true
            return
        }
        state.begin(at: point)
        onChange?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedControl == nil else { return }
        state.update(to: globalPoint(for: event))
        onChange?()
    }

    override func mouseUp(with event: NSEvent) {
        let point = globalPoint(for: event)
        if let pressedControl {
            self.pressedControl = nil
            needsDisplay = true
            guard control(at: point) == pressedControl else { return }
            switch pressedControl {
            case .cancel:
                onCancel?()
            case .start:
                confirm()
            }
            return
        }
        state.update(to: point)
        state.endOperation()
        onChange?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            confirm()
        case 53:
            onCancel?()
        case 123, 124, 125, 126:
            let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: (CGFloat, CGFloat)
            switch event.keyCode {
            case 123: delta = (-amount, 0)
            case 124: delta = (amount, 0)
            case 125: delta = (0, -amount)
            default: delta = (0, amount)
            }
            state.nudge(
                dx: delta.0,
                dy: delta.1,
                resize: event.modifierFlags.contains(.option)
            )
            onChange?()
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        let dimPath = NSBezierPath(rect: bounds)
        if let selectionRect = state.selectionRect {
            let visible = selectionRect.intersection(screenFrame)
            if !visible.isNull {
                dimPath.append(NSBezierPath(rect: localRect(for: visible)))
                dimPath.windingRule = .evenOdd
            }
        }
        NSColor.black.withAlphaComponent(0.48).setFill()
        dimPath.fill()

        guard let selectionRect = state.selectionRect,
              !selectionRect.intersection(screenFrame).isNull
        else {
            drawHint("Draw the scrolling area", at: CGPoint(x: bounds.midX, y: 42))
            return
        }

        let localSelection = localRect(for: selectionRect)
        let border = NSBezierPath(rect: localSelection)
        border.lineWidth = 2 / backingScale
        NSColor.white.setStroke()
        border.stroke()

        if !state.isLocked, state.isReady {
            drawHandles(selectionRect: selectionRect)
            drawDimensions(selectionRect: localSelection)
            drawControls(selectionRect: selectionRect)
        }
    }

    func lockSelection() {
        state.lock()
        needsDisplay = true
    }

    private func confirm() {
        guard state.isReady, let selectionRect = state.selectionRect else { return }
        onConfirm?(selectionRect)
    }

    private func drawHandles(selectionRect: CGRect) {
        for handle in ScrollingSelectionHandle.allCases {
            let globalRect = state.handleRect(for: handle, selectionRect: selectionRect)
            let visible = globalRect.intersection(screenFrame)
            guard !visible.isNull else { continue }
            let local = localRect(for: globalRect)
            let handlePath = NSBezierPath(ovalIn: local.insetBy(dx: 3, dy: 3))
            NSColor.black.withAlphaComponent(0.32).setFill()
            NSBezierPath(ovalIn: local).fill()
            NSColor.white.setFill()
            handlePath.fill()
        }
    }

    private func drawDimensions(selectionRect: CGRect) {
        guard let dimensions = state.pixelDimensions else { return }
        let text = "\(Int(dimensions.width)) × \(Int(dimensions.height)) px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let labelHeight = textSize.height + 9
        let labelY = selectionRect.width < 480
            ? selectionRect.maxY - labelHeight - 10
            : selectionRect.minY + 10
        let labelRect = CGRect(
            x: selectionRect.minX + 10,
            y: labelY,
            width: textSize.width + 16,
            height: labelHeight
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 7, yRadius: 7).fill()
        attributed.draw(
            at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4)
        )
    }

    private func drawControls(selectionRect: CGRect) {
        guard screenFrame.contains(CGPoint(x: selectionRect.midX, y: selectionRect.minY)) else {
            return
        }
        let rects = controlRects(for: selectionRect)
        drawPill(
            title: "Cancel",
            symbol: "xmark",
            rect: localRect(for: rects.cancel),
            emphasized: false,
            pressed: pressedControl == .cancel
        )
        drawPill(
            title: "Start Capture",
            symbol: "checkmark",
            rect: localRect(for: rects.start),
            emphasized: true,
            pressed: pressedControl == .start
        )
    }

    private func drawPill(
        title: String,
        symbol: String,
        rect: CGRect,
        emphasized: Bool,
        pressed: Bool
    ) {
        let fillColor: NSColor = emphasized ? .white : .black.withAlphaComponent(0.76)
        fillColor.withAlphaComponent(pressed ? 0.72 : 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            .fill()

        let color: NSColor = emphasized ? .black : .white
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        {
            image.draw(
                in: CGRect(x: rect.minX + 12, y: rect.midY - 6, width: 12, height: 12),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: color,
        ]
        NSAttributedString(string: title, attributes: attributes).draw(
            at: CGPoint(x: rect.minX + 30, y: rect.midY - 7)
        )
    }

    private func drawHint(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let rect = CGRect(
            x: point.x - size.width / 2 - 12,
            y: point.y - 8,
            width: size.width + 24,
            height: size.height + 12
        )
        NSColor.black.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        attributed.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 6))
    }

    private func control(at point: CGPoint) -> Control? {
        guard !state.isLocked,
              state.isReady,
              let selectionRect = state.selectionRect,
              screenFrame.contains(CGPoint(x: selectionRect.midX, y: selectionRect.minY))
        else {
            return nil
        }
        let rects = controlRects(for: selectionRect)
        if rects.cancel.contains(point) { return .cancel }
        if rects.start.contains(point) { return .start }
        return nil
    }

    private func controlRects(for selectionRect: CGRect) -> (cancel: CGRect, start: CGRect) {
        let gap: CGFloat = 8
        let cancelWidth: CGFloat = 92
        let startWidth: CGFloat = 132
        let height: CGFloat = 36
        let totalWidth = cancelWidth + gap + startWidth
        let proposedX = selectionRect.midX - totalWidth / 2
        let x = min(
            max(proposedX, screenFrame.minX + 10),
            screenFrame.maxX - totalWidth - 10
        )
        let y = max(screenFrame.minY + 10, selectionRect.minY + 10)
        return (
            CGRect(x: x, y: y, width: cancelWidth, height: height),
            CGRect(x: x + cancelWidth + gap, y: y, width: startWidth, height: height)
        )
    }

    private func updateCursor(at point: CGPoint) {
        if control(at: point) != nil {
            NSCursor.pointingHand.set()
        } else if state.handle(at: point) != nil {
            NSCursor.crosshair.set()
        } else if state.selectionRect?.contains(point) == true, state.isReady {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: screenFrame.minX + local.x, y: screenFrame.minY + local.y)
    }

    private func localRect(for globalRect: CGRect) -> CGRect {
        CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: globalRect.minY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        )
    }
}

private final class ScrollingRegionSelectionWindow: NSWindow {
    let selectionView: ScrollingRegionSelectionView

    init(screen: NSScreen, selectionView: ScrollingRegionSelectionView) {
        self.selectionView = selectionView
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isOpaque = false
        level = .screenSaver
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}
