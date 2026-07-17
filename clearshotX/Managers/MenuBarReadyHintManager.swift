//
//  MenuBarReadyHintManager.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import OSLog
import SwiftUI

@MainActor
final class MenuBarReadyHintManager {
    private let panelSize = NSSize(width: 176, height: 42)
    private let dismissDelay: TimeInterval = 3.0
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "MenuBarReadyHint"
    )

    private var panel: NSPanel?
    private var popover: NSPopover?
    private var dismissWorkItem: DispatchWorkItem?

    func showReadyHint(attachedTo anchorView: NSView?, pointingTo anchorFrame: NSRect?) {
        dismissWorkItem?.cancel()

        guard let anchorView else {
            showReadyHint(pointingTo: anchorFrame)
            return
        }

        logger.info("Showing menu bar ready hint as attached popover")
        panel?.orderOut(nil)

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.contentSize = NSSize(width: 184, height: 36)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarReadyPopoverView()
        )

        self.popover?.close()
        self.popover = popover
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)

        scheduleDismiss()
    }

    func showReadyHint(pointingTo anchorFrame: NSRect?) {
        logger.info("Showing menu bar ready hint; anchor exists: \(anchorFrame != nil, privacy: .public)")
        dismissWorkItem?.cancel()
        popover?.close()
        popover = nil

        let panel = panel ?? makePanel()
        self.panel = panel

        let finalFrame = hintFrame(pointingTo: anchorFrame)
        let pointerX = pointerX(anchorFrame: anchorFrame, panelFrame: finalFrame)
        logger.info("Menu bar ready hint frame x=\(finalFrame.origin.x, privacy: .public), y=\(finalFrame.origin.y, privacy: .public), pointerX=\(pointerX, privacy: .public)")

        let hostingView = MenuBarHintHostingView(rootView: MenuBarReadyHintView(pointerX: pointerX))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView
        panel.setContentSize(panelSize)

        let startFrame = finalFrame.offsetBy(dx: 0, dy: 5)
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0

        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else {
                return
            }

            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
                panel.animator().alphaValue = 1
            }

            self.scheduleDismiss()
        }
    }

    private func makePanel() -> MenuBarHintPanel {
        let panel = MenuBarHintPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        return panel
    }

    private func hintFrame(pointingTo anchorFrame: NSRect?) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let fallbackX = visibleFrame.maxX - panelSize.width - 44
        let proposedX = anchorFrame.map { $0.midX - (panelSize.width / 2) } ?? fallbackX
        let clampedX = min(max(proposedX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let proposedY = anchorFrame.map { $0.minY - panelSize.height - 3 } ?? (visibleFrame.maxY - panelSize.height - 8)

        return NSRect(
            x: clampedX,
            y: proposedY,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func pointerX(anchorFrame: NSRect?, panelFrame: NSRect) -> CGFloat {
        guard let anchorFrame else {
            return panelSize.width / 2
        }

        return min(max(anchorFrame.midX - panelFrame.minX, 18), panelSize.width - 18)
    }

    private func scheduleDismiss() {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismiss()
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: workItem)
    }

    private func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        popover?.close()
        popover = nil

        guard let panel, panel.isVisible else {
            return
        }

        let finalFrame = panel.frame.offsetBy(dx: 0, dy: 5)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

private struct MenuBarReadyPopoverView: View {
    var body: some View {
        Text("ClearshotX is ready")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(width: 176, height: 28)
            .background(.black, in: Capsule(style: .continuous))
            .padding(4)
            .frame(width: 184, height: 36)
            .background(Color.clear)
    }
}

private struct MenuBarReadyHintView: View {
    let pointerX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            MenuBarHintPointer()
                .fill(.black)
                .frame(width: 16, height: 10)
                .offset(x: pointerX - 8, y: 2)

            Text("ClearshotX is ready")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .padding(.horizontal, 13)
                .frame(width: 176, height: 28)
                .background(.black, in: Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 5)
                .padding(.top, 8)
        }
        .frame(width: 176, height: 42)
    }
}

private struct MenuBarHintPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private final class MenuBarHintPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class MenuBarHintHostingView: NSHostingView<MenuBarReadyHintView> {
    override var isOpaque: Bool {
        false
    }

    required init(rootView: MenuBarReadyHintView) {
        super.init(rootView: rootView)
        setupTransparency()
    }

    @available(*, unavailable)
    required init(rootView: MenuBarReadyHintView, ignoresSafeArea: Bool) {
        fatalError("init(rootView:ignoresSafeArea:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupTransparency()
        window?.backgroundColor = .clear
        window?.isOpaque = false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    private func setupTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}
