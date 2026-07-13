//
//  QuickAccessOverlayManager.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import SwiftUI

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
    private let pinnedPanelSpacing: CGFloat = 14
    private let captureExportService: CaptureExportServicing
    private let captureStore: CaptureStoring

    private var panelSize: NSSize {
        NSSize(
            width: thumbnailSize.width + shadowLeftOutset + shadowRightOutset,
            height: thumbnailSize.height + shadowTopOutset + shadowBottomOutset
        )
    }

    private var panel: QuickAccessPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var currentCapture: CaptureResult?
    private var pinnedPanels: [PinnedPanel] = []
    private var isDraggingCapture = false

    init(
        captureExportService: CaptureExportServicing? = nil,
        captureStore: CaptureStoring? = nil
    ) {
        self.captureExportService = captureExportService ?? CaptureExportService()
        self.captureStore = captureStore ?? CaptureStore()
    }

    func show(
        capture: CaptureResult,
        clipboardService: ClipboardService,
        editorWindowManager: EditorWindowManager
    ) {
        currentCapture = capture
        isDraggingCapture = false
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
            onDragBegan: { [weak self] in
                self?.beginDraggingCapture()
            },
            onDragEnded: { [weak self] didDrop in
                self?.finishDraggingCapture(didDrop: didDrop)
            },
            onEdit: { [weak self, editorWindowManager] in
                self?.dismiss(animated: true)
                editorWindowManager.showEditor(for: capture)
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
        guard !isDraggingCapture else {
            return
        }

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
        isDraggingCapture = false

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

        captureExportService.saveCapture(
            at: capture.fileURL,
            suggestedFileName: capture.fileURL.lastPathComponent
        ) { [weak self] result in
            guard let self else {
                return
            }

            if case let .failure(error) = result {
                presentSaveError(error)
            }

            scheduleDismiss()
        }
    }

    private func beginDraggingCapture() {
        isDraggingCapture = true
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func finishDraggingCapture(didDrop: Bool) {
        isDraggingCapture = false

        if didDrop {
            dismiss(animated: true)
            return
        }

        if !didDrop {
            scheduleDismiss()
        }
    }

    private func pin(_ capture: CaptureResult) {
        let size = pinnedSize(for: capture)
        guard let thumbnail = pinnedImage(for: capture, size: size) else {
            NSSound.beep()
            return
        }

        let frame = pinnedFrame(
            size: size,
            sourceFrame: panel?.frame ?? overlayFrame(for: capture),
            screenFrame: capture.screenFrame
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

        let hostingView = TransparentHostingView(
            rootView: PinnedCaptureView(image: thumbnail) { [weak self, weak panel] in
                guard let panel else {
                    return
                }

                panel.orderOut(nil)
                self?.pinnedPanels.removeAll { $0.panel === panel }
            }
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setContentSize(size)

        pinnedPanels.append(PinnedPanel(panel: panel))
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
            try captureStore.removeCapture(at: capture.fileURL)
        } catch {
            NSSound.beep()
        }

        dismiss(animated: true)
    }

    private func presentSaveError(_ error: CaptureExportError) {
        let alert = NSAlert(error: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    private func pinnedFrame(
        size: NSSize,
        sourceFrame: NSRect,
        screenFrame: CGRect
    ) -> NSRect {
        let screen = screen(for: screenFrame) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? sourceFrame
        let offset = CGFloat(pinnedPanels.count % 8) * pinnedPanelSpacing

        let proposedFrame = NSRect(
            x: sourceFrame.maxX - size.width + offset,
            y: sourceFrame.maxY + 12 - offset,
            width: size.width,
            height: size.height
        )

        return proposedFrame.clamped(to: visibleFrame, padding: 12)
    }

    private func pinnedImage(for capture: CaptureResult, size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        capture.image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        thumbnail.unlockFocus()
        return thumbnail
    }
}

private struct PinnedPanel {
    let id = UUID()
    let panel: NSPanel
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
    let image: NSImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
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

    func clamped(to bounds: CGRect, padding: CGFloat) -> CGRect {
        guard !bounds.isNull, !bounds.isInfinite else {
            return self
        }

        let maxX = bounds.maxX - width - padding
        let maxY = bounds.maxY - height - padding
        let minX = bounds.minX + padding
        let minY = bounds.minY + padding

        return CGRect(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY),
            width: width,
            height: height
        )
    }
}
