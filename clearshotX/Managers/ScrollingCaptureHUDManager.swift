//
//  ScrollingCaptureHUDManager.swift
//  clearshotX
//

import AppKit
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
/// frame, a narrow live-result strip, and compact controls anchored to the crop.
/// All app-owned windows are excluded by the ScreenCaptureKit content filter.
@MainActor
final class ScrollingCaptureHUDManager: ScrollingCaptureHUDPresenting {
    private let previewWidth: CGFloat = 232
    private let controlsSize = NSSize(width: 276, height: 54)
    private let edgeMargin: CGFloat = 12

    private var frameWindows: [ScrollingCaptureFrameWindow] = []
    private var previewPanel: NSPanel?
    private var controlsPanel: NSPanel?

    func show(
        viewModel: ScrollingCaptureHUDViewModel,
        adjacentTo selectedRegion: CGRect
    ) {
        dismiss()
        showPersistentFrame(for: selectedRegion)

        let previewSize = NSSize(
            width: previewWidth,
            height: min(420, max(270, selectedRegion.height))
        )
        let previewPanel = makePanel(contentSize: previewSize)
        let previewView = NSHostingView(
            rootView: ScrollingCaptureHUDView(viewModel: viewModel)
        )
        previewView.frame = NSRect(origin: .zero, size: previewSize)
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
        let centeredY = clamp(
            region.midY - contentSize.height / 2,
            minimum: screenFrame.minY + edgeMargin,
            maximum: screenFrame.maxY - contentSize.height - edgeMargin
        )

        let rightX = region.maxX + edgeMargin
        if rightX + contentSize.width <= screenFrame.maxX - edgeMargin {
            return CGRect(
                origin: CGPoint(x: rightX, y: centeredY),
                size: contentSize
            )
        }

        let leftX = region.minX - edgeMargin - contentSize.width
        if leftX >= screenFrame.minX + edgeMargin {
            return CGRect(
                origin: CGPoint(x: leftX, y: centeredY),
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
