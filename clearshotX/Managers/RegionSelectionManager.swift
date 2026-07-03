//
//  RegionSelectionManager.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit

@MainActor
final class RegionSelectionManager {
    private var overlayWindows: [RegionSelectionWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func selectRegion() async -> CGRect? {
        guard continuation == nil else {
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
            let window = RegionSelectionWindow(screen: screen)
            let overlayView = RegionSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size)
            )

            overlayView.onComplete = { [weak self, weak window] localRect in
                guard let self, let window else {
                    return
                }

                let globalRect = CGRect(
                    x: window.frame.minX + localRect.minX,
                    y: window.frame.minY + localRect.minY,
                    width: localRect.width,
                    height: localRect.height
                )

                self.finish(with: globalRect)
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
        NSCursor.crosshair.set()
    }

    private func finish(with rect: CGRect?) {
        overlayWindows.forEach { window in
            window.orderOut(nil)
        }
        overlayWindows.removeAll()

        NSCursor.arrow.set()

        continuation?.resume(returning: rect)
        continuation = nil
    }
}

private final class RegionSelectionWindow: NSWindow {
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

private final class RegionSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let selectionRect, selectionRect.width >= 4, selectionRect.height >= 4 else {
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

        guard let selectionRect else {
            NSColor.black.withAlphaComponent(0.42).setFill()
            bounds.fill()
            drawInstruction()
            return
        }

        let dimPath = NSBezierPath(rect: bounds)
        dimPath.append(NSBezierPath(rect: selectionRect))
        dimPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill()
        dimPath.fill()

        let borderPath = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        NSColor.controlAccentColor.setStroke()
        borderPath.lineWidth = 2
        borderPath.stroke()

        drawSizeLabel(for: selectionRect)
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func cancel() {
        startPoint = nil
        currentPoint = nil
        onCancel?()
    }

    private func drawInstruction() {
        let text = "Drag to select a capture region. Press Esc to cancel."
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

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let padding: CGFloat = 8
        let labelRect = CGRect(
            x: rect.minX,
            y: max(bounds.minY + 8, rect.minY - textSize.height - padding * 2 - 6),
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.72).setFill()
        backgroundPath.fill()

        attributedText.draw(in: labelRect.insetBy(dx: padding, dy: padding))
    }
}
