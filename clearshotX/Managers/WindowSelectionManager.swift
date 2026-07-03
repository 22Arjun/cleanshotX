//
//  WindowSelectionManager.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import ScreenCaptureKit

@MainActor
final class WindowSelectionManager {
    private var overlayWindows: [WindowSelectionWindow] = []
    private var continuation: CheckedContinuation<SCWindow?, Never>?
    private var candidates: [WindowSelectionCandidate] = []

    func selectWindow(from windows: [SCWindow]) async -> SCWindow? {
        guard continuation == nil else {
            return nil
        }

        candidates = windows
            .map(WindowSelectionCandidate.init(window:))
            .filter { candidate in
                candidate.frame.width >= 48 && candidate.frame.height >= 48
            }

        guard !candidates.isEmpty else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.async { [weak self] in
                self?.showOverlays()
            }
        }
    }

    private func showOverlays() {
        overlayWindows = NSScreen.screens.map { screen in
            let window = WindowSelectionWindow(screen: screen)
            let overlayView = WindowSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                candidates: candidates
            )

            overlayView.onComplete = { [weak self] candidate in
                self?.finish(with: candidate.window)
            }

            overlayView.onCancel = { [weak self] in
                self?.finish(with: nil)
            }

            window.contentView = overlayView
            return window
        }

        NSApp.activate(ignoringOtherApps: true)

        overlayWindows.forEach { window in
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.contentView?.window?.makeFirstResponder(window.contentView)
        }

        overlayWindows.first?.makeKeyAndOrderFront(nil)
        NSCursor.arrow.set()
    }

    private func finish(with window: SCWindow?) {
        overlayWindows.forEach { window in
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        candidates.removeAll()

        NSCursor.arrow.set()

        continuation?.resume(returning: window)
        continuation = nil
    }
}

private struct WindowSelectionCandidate {
    let window: SCWindow
    let frame: CGRect
    let title: String

    init(window: SCWindow) {
        self.window = window
        frame = window.frame

        let appName = window.owningApplication?.applicationName
        let windowTitle = window.title

        switch (appName?.isEmpty == false ? appName : nil, windowTitle?.isEmpty == false ? windowTitle : nil) {
        case let (.some(appName), .some(windowTitle)):
            title = "\(appName) - \(windowTitle)"
        case let (.some(appName), nil):
            title = appName
        case let (nil, .some(windowTitle)):
            title = windowTitle
        default:
            title = "Window"
        }
    }
}

private final class WindowSelectionWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class WindowSelectionView: NSView {
    var onComplete: ((WindowSelectionCandidate) -> Void)?
    var onCancel: (() -> Void)?

    private let screenFrame: CGRect
    private let candidates: [WindowSelectionCandidate]
    private var hoveredCandidate: WindowSelectionCandidate?

    init(frame frameRect: NSRect, screenFrame: CGRect, candidates: [WindowSelectionCandidate]) {
        self.screenFrame = screenFrame
        self.candidates = candidates
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        updateHover(with: event)

        guard let hoveredCandidate else {
            return
        }

        onComplete?(hoveredCandidate)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let hoveredCandidate else {
            drawInstruction()
            return
        }

        let highlightRect = localRect(for: hoveredCandidate.frame)
        let dimPath = NSBezierPath(rect: bounds)
        dimPath.append(NSBezierPath(rect: highlightRect))
        dimPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.38).setFill()
        dimPath.fill()

        let borderPath = NSBezierPath(roundedRect: highlightRect, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.setStroke()
        borderPath.lineWidth = 3
        borderPath.stroke()

        drawLabel(hoveredCandidate.title, near: highlightRect)
    }

    private func updateHover(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = CGPoint(
            x: screenFrame.minX + localPoint.x,
            y: screenFrame.minY + localPoint.y
        )

        let nextCandidate = candidates
            .filter { candidate in
                candidate.frame.contains(globalPoint)
            }
            .min { lhs, rhs in
                lhs.frame.area < rhs.frame.area
            }

        guard nextCandidate?.window.windowID != hoveredCandidate?.window.windowID else {
            return
        }

        hoveredCandidate = nextCandidate
        needsDisplay = true
    }

    private func localRect(for globalRect: CGRect) -> CGRect {
        CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: globalRect.minY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        ).intersection(bounds)
    }

    private func drawInstruction() {
        let text = "Move over a window and click to capture. Press Esc to cancel."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let size = attributedText.size()
        let rect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        attributedText.draw(in: rect)
    }

    private func drawLabel(_ text: String, near rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let padding: CGFloat = 8
        let maxWidth = min(textSize.width + padding * 2, bounds.width - 24)
        let labelRect = CGRect(
            x: min(max(bounds.minX + 12, rect.minX), bounds.maxX - maxWidth - 12),
            y: max(bounds.minY + 12, rect.minY - textSize.height - padding * 2 - 8),
            width: maxWidth,
            height: textSize.height + padding * 2
        )

        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.76).setFill()
        backgroundPath.fill()

        attributedText.draw(in: labelRect.insetBy(dx: padding, dy: padding))
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else {
            return 0
        }

        return max(0, width) * max(0, height)
    }
}
