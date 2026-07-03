//
//  QuickAccessOverlayManager.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class QuickAccessOverlayManager {
    private let thumbnailSize = NSSize(width: 180, height: 120)
    private let shadowLeftOutset: CGFloat = 84
    private let shadowRightOutset: CGFloat = 84
    private let shadowTopOutset: CGFloat = 72
    private let shadowBottomOutset: CGFloat = 132
    private let screenLeftMargin: CGFloat = 20
    private let screenBottomMargin: CGFloat = 55
    private let slideDistance: CGFloat = 14
    private let dismissDelay: TimeInterval = 5

    private var panelSize: NSSize {
        NSSize(
            width: thumbnailSize.width + shadowLeftOutset + shadowRightOutset,
            height: thumbnailSize.height + shadowTopOutset + shadowBottomOutset
        )
    }

    private var panel: QuickAccessPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var currentCapture: CaptureResult?
    private var pinnedPanels: [NSPanel] = []

    func show(
        capture: CaptureResult,
        clipboardService: ClipboardService,
        previewWindowManager: PreviewWindowManager
    ) {
        currentCapture = capture
        dismissWorkItem?.cancel()

        let overlayView = QuickAccessOverlayView(
            capture: capture,
            onHoverChanged: { [weak self] isHovering in
                self?.setHovering(isHovering)
            },
            onCopy: { [weak self, clipboardService] in
                clipboardService.copy(capture.image)
                self?.scheduleDismiss()
            },
            onSave: { [weak self] in
                self?.save(capture)
            },
            onEdit: { [weak self, previewWindowManager, clipboardService] in
                self?.dismiss(animated: true)
                previewWindowManager.showPreview(for: capture, clipboardService: clipboardService)
            },
            onPin: { [weak self] in
                self?.pin(capture)
            },
            onDelete: { [weak self] in
                self?.delete(capture)
            },
            onClose: { [weak self] in
                self?.dismiss(animated: true)
            }
        )

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = makeRoundedHostingView(rootView: overlayView)

        let finalFrame = overlayFrame(for: capture)
        let startFrame = finalFrame.offsetBy(dx: 0, dy: -slideDistance)
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }

        scheduleDismiss()
    }

    private func makePanel() -> QuickAccessPanel {
        let panel = QuickAccessPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        return panel
    }

    private func makeRoundedHostingView<Content: View>(rootView: Content) -> NSView {
        let hostingView = TransparentHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.layer?.masksToBounds = false
        return hostingView
    }

    private func overlayFrame(for capture: CaptureResult) -> NSRect {
        let screen = screen(for: capture.screenFrame) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        return NSRect(
            x: visibleFrame.minX + screenLeftMargin - shadowLeftOutset,
            y: visibleFrame.minY + screenBottomMargin - shadowBottomOutset,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.equalTo(frame)
        } ?? NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }
    }

    private func setHovering(_ isHovering: Bool) {
        if isHovering {
            dismissWorkItem?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismiss(animated: true)
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: workItem)
    }

    private func dismiss(animated: Bool) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        currentCapture = nil

        guard let panel, panel.isVisible else {
            return
        }

        let finalFrame = panel.frame.offsetBy(dx: 0, dy: -slideDistance)

        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func save(_ capture: CaptureResult) {
        dismissWorkItem?.cancel()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = capture.fileURL.lastPathComponent

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard response == .OK, let destinationURL = panel.url else {
                    self?.scheduleDismiss()
                    return
                }

                do {
                    if destinationURL != capture.fileURL, FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }

                    if destinationURL != capture.fileURL {
                        try FileManager.default.copyItem(at: capture.fileURL, to: destinationURL)
                    }

                    self?.scheduleDismiss()
                } catch {
                    NSSound.beep()
                    self?.scheduleDismiss()
                }
            }
        }
    }

    private func pin(_ capture: CaptureResult) {
        let size = pinnedSize(for: capture)
        let sourceFrame = panel?.frame ?? overlayFrame(for: capture)
        let frame = NSRect(
            x: sourceFrame.maxX - size.width,
            y: sourceFrame.maxY + 12,
            width: size.width,
            height: size.height
        )

        let panel = QuickAccessPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        panel.contentView = TransparentHostingView(
            rootView: PinnedCaptureView(capture: capture) { [weak self, weak panel] in
                guard let panel else {
                    return
                }

                panel.orderOut(nil)
                self?.pinnedPanels.removeAll { $0 === panel }
            }
        )

        pinnedPanels.append(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        dismiss(animated: true)
    }

    private func delete(_ capture: CaptureResult) {
        do {
            if FileManager.default.fileExists(atPath: capture.fileURL.path) {
                try FileManager.default.removeItem(at: capture.fileURL)
            }
        } catch {
            NSSound.beep()
        }

        dismiss(animated: true)
    }

    private func pinnedSize(for capture: CaptureResult) -> NSSize {
        let maxWidth: CGFloat = 360
        let maxHeight: CGFloat = 260
        let imageSize = capture.image.size
        let widthScale = maxWidth / max(1, imageSize.width)
        let heightScale = maxHeight / max(1, imageSize.height)
        let scale = min(widthScale, heightScale, 1)

        return NSSize(
            width: max(180, imageSize.width * scale),
            height: max(120, imageSize.height * scale)
        )
    }
}

private final class QuickAccessPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        setupTransparency()
    }

    @available(*, unavailable)
    required init(rootView: Content, ignoresSafeArea: Bool) {
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

private struct PinnedCaptureView: View {
    let capture: CaptureResult
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: capture.image)
                .resizable()
                .scaledToFit()
                .background(.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(7)
            .help("Close")
        }
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
