//
//  ScrollingCaptureHUDManager.swift
//  clearshotX
//

import AppKit
import Combine
import SwiftUI

@MainActor
protocol ScrollingCaptureHUDPresenting: AnyObject {
    func show(
        viewModel: ScrollingCaptureHUDViewModel,
        adjacentTo selectedRegion: CGRect
    )
    func dismiss()
}

/// Presents the active capture as one continuous experience: a persistent crop
/// frame, a chrome-free page miniature, and compact controls anchored to the crop.
/// All app-owned windows are excluded by the ScreenCaptureKit content filter.
@MainActor
final class ScrollingCaptureHUDManager: ScrollingCaptureHUDPresenting {
    private let previewMaximumSize = NSSize(width: 232, height: 420)
    private let controlsSize = NSSize(width: 276, height: 54)
    private let edgeMargin: CGFloat = 12

    private var frameWindows: [ScrollingCaptureFrameWindow] = []
    private var previewPanel: NSPanel?
    private var controlsPanel: NSPanel?
    private var previewObservation: AnyCancellable?

    func show(
        viewModel: ScrollingCaptureHUDViewModel,
        adjacentTo selectedRegion: CGRect
    ) {
        dismiss()
        showPersistentFrame(for: selectedRegion)

        // The panel begins effectively invisible. Its first accepted page image
        // gives it the exact miniature aspect ratio; no loading card is exposed.
        let previewSize = NSSize(width: 1, height: 1)
        let previewPanel = makePanel(contentSize: previewSize)
        previewPanel.ignoresMouseEvents = true
        let previewView = NSHostingView(
            rootView: ScrollingCaptureHUDView(viewModel: viewModel)
        )
        previewView.frame = NSRect(origin: .zero, size: previewSize)
        previewView.autoresizingMask = [.width, .height]
        previewPanel.contentView = previewView
        previewPanel.setFrame(
            previewPanelFrame(
                adjacentTo: selectedRegion,
                contentSize: previewSize
            ),
            display: false
        )
        previewPanel.orderFrontRegardless()
        self.previewPanel = previewPanel

        previewObservation = viewModel.$previewImage
            .compactMap { $0 }
            .sink { [weak self, weak previewPanel] image in
                guard let self, let previewPanel else { return }
                self.resizePreviewPanel(
                    previewPanel,
                    for: image,
                    adjacentTo: selectedRegion
                )
            }

        let controlsPanel = makePanel(contentSize: controlsSize)
        let controlsView = NSHostingView(
            rootView: ScrollingCaptureControlsView(viewModel: viewModel)
        )
        controlsView.frame = NSRect(origin: .zero, size: controlsSize)
        controlsPanel.contentView = controlsView
        controlsPanel.setFrame(
            controlsPanelFrame(for: selectedRegion),
            display: false
        )
        controlsPanel.orderFrontRegardless()
        self.controlsPanel = controlsPanel
    }

    func dismiss() {
        previewObservation?.cancel()
        previewObservation = nil

        previewPanel?.orderOut(nil)
        previewPanel?.contentView = nil
        previewPanel = nil

        controlsPanel?.orderOut(nil)
        controlsPanel?.contentView = nil
        controlsPanel = nil

        frameWindows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
        }
        frameWindows.removeAll()
    }

    private func showPersistentFrame(for region: CGRect) {
        frameWindows = NSScreen.screens.map { screen in
            let overlay = ScrollingCaptureFrameView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                selectedRegion: region,
                backingScale: max(1, screen.backingScaleFactor)
            )
            let window = ScrollingCaptureFrameWindow(screen: screen, overlay: overlay)
            window.orderFrontRegardless()
            return window
        }
    }

    private func makePanel(contentSize: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func previewPanelFrame(
        adjacentTo region: CGRect,
        contentSize: NSSize
    ) -> CGRect {
        let screenFrame = captureScreen(for: region)?.frame ?? region
        // Keep the top of the page miniature stable while its captured length
        // grows downward. This makes progress legible instead of making the HUD
        // jump around its center on every accepted strip.
        let topAlignedY = clamp(
            region.maxY - contentSize.height,
            minimum: screenFrame.minY + edgeMargin,
            maximum: screenFrame.maxY - contentSize.height - edgeMargin
        )

        let rightX = region.maxX + edgeMargin
        if rightX + contentSize.width <= screenFrame.maxX - edgeMargin {
            return CGRect(
                origin: CGPoint(x: rightX, y: topAlignedY),
                size: contentSize
            )
        }

        let leftX = region.minX - edgeMargin - contentSize.width
        if leftX >= screenFrame.minX + edgeMargin {
            return CGRect(
                origin: CGPoint(x: leftX, y: topAlignedY),
                size: contentSize
            )
        }

        let centeredX = clamp(
            region.midX - contentSize.width / 2,
            minimum: screenFrame.minX + edgeMargin,
            maximum: screenFrame.maxX - contentSize.width - edgeMargin
        )
        let aboveY = region.maxY + edgeMargin
        if aboveY + contentSize.height <= screenFrame.maxY - edgeMargin {
            return CGRect(origin: CGPoint(x: centeredX, y: aboveY), size: contentSize)
        }

        let belowY = region.minY - edgeMargin - contentSize.height
        if belowY >= screenFrame.minY + edgeMargin {
            return CGRect(origin: CGPoint(x: centeredX, y: belowY), size: contentSize)
        }

        // A near-fullscreen selection has no external side. Keep the preview near
        // the upper trailing corner; it remains excluded from the captured pixels.
        return CGRect(
            origin: CGPoint(
                x: screenFrame.maxX - contentSize.width - edgeMargin,
                y: screenFrame.maxY - contentSize.height - edgeMargin
            ),
            size: contentSize
        )
    }

    private func resizePreviewPanel(
        _ panel: NSPanel,
        for image: CGImage,
        adjacentTo region: CGRect
    ) {
        guard image.width > 0, image.height > 0 else { return }

        let screenFrame = captureScreen(for: region)?.frame ?? region
        let availableHeight = max(1, screenFrame.height - edgeMargin * 2)
        let bounds = NSSize(
            width: min(previewMaximumSize.width, max(1, screenFrame.width - edgeMargin * 2)),
            height: min(previewMaximumSize.height, availableHeight)
        )
        let scale = min(
            bounds.width / CGFloat(image.width),
            bounds.height / CGFloat(image.height)
        )
        let contentSize = NSSize(
            width: max(1, CGFloat(image.width) * scale),
            height: max(1, CGFloat(image.height) * scale)
        )
        let targetFrame = previewPanelFrame(
            adjacentTo: region,
            contentSize: contentSize
        )

        // The first page appears immediately. Later accepted strips smoothly
        // lengthen the miniature while its top edge remains visually anchored.
        guard panel.frame.width > 1.5, panel.frame.height > 1.5 else {
            panel.setFrame(targetFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func controlsPanelFrame(for region: CGRect) -> CGRect {
        let screenFrame = captureScreen(for: region)?.frame ?? region
        let x = clamp(
            region.midX - controlsSize.width / 2,
            minimum: screenFrame.minX + edgeMargin,
            maximum: screenFrame.maxX - controlsSize.width - edgeMargin
        )
        let preferredY = region.minY + 10
        let y = clamp(
            preferredY,
            minimum: screenFrame.minY + edgeMargin,
            maximum: screenFrame.maxY - controlsSize.height - edgeMargin
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: controlsSize)
    }

    private func captureScreen(for region: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, region) < intersectionArea(rhs.frame, region)
        }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else { return minimum }
        return min(max(value, minimum), maximum)
    }
}

private final class ScrollingCaptureFrameWindow: NSWindow {
    init(screen: NSScreen, overlay: ScrollingCaptureFrameView) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
        isOpaque = false
        level = .screenSaver
        contentView = overlay
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScrollingCaptureFrameView: NSView {
    private let screenFrame: CGRect
    private let selectedRegion: CGRect
    private let backingScale: CGFloat

    init(
        frame frameRect: NSRect,
        screenFrame: CGRect,
        selectedRegion: CGRect,
        backingScale: CGFloat
    ) {
        self.screenFrame = screenFrame
        self.selectedRegion = selectedRegion
        self.backingScale = backingScale
        super.init(frame: frameRect)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        let dimPath = NSBezierPath(rect: bounds)
        let visibleSelection = selectedRegion.intersection(screenFrame)
        if !visibleSelection.isNull {
            dimPath.append(NSBezierPath(rect: localRect(for: visibleSelection)))
            dimPath.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.38).setFill()
        dimPath.fill()

        guard !visibleSelection.isNull else { return }
        let border = NSBezierPath(rect: localRect(for: selectedRegion))
        border.lineWidth = 2 / backingScale
        NSColor.white.setStroke()
        border.stroke()
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
