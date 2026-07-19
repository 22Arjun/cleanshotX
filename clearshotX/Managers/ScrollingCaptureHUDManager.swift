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

@MainActor
final class ScrollingCaptureHUDManager: ScrollingCaptureHUDPresenting {
    private let contentSize = NSSize(width: 360, height: 430)
    private let edgeMargin: CGFloat = 12
    private var panel: NSPanel?

    func show(
        viewModel: ScrollingCaptureHUDViewModel,
        adjacentTo selectedRegion: CGRect
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let hostingView = NSHostingView(
            rootView: ScrollingCaptureHUDView(viewModel: viewModel)
        )
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        panel.contentView = hostingView
        panel.setFrame(
            panelFrame(adjacentTo: selectedRegion),
            display: false
        )
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func makePanel() -> NSPanel {
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
        panel.level = .floating
        return panel
    }

    private func panelFrame(adjacentTo region: CGRect) -> CGRect {
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(region).area < rhs.frame.intersection(region).area
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? region

        let centeredY = min(
            max(region.midY - contentSize.height / 2, visibleFrame.minY),
            visibleFrame.maxY - contentSize.height
        )
        let rightX = region.maxX + edgeMargin
        if rightX + contentSize.width <= visibleFrame.maxX {
            return CGRect(origin: CGPoint(x: rightX, y: centeredY), size: contentSize)
        }

        let leftX = region.minX - edgeMargin - contentSize.width
        if leftX >= visibleFrame.minX {
            return CGRect(origin: CGPoint(x: leftX, y: centeredY), size: contentSize)
        }

        let centeredX = min(
            max(region.midX - contentSize.width / 2, visibleFrame.minX),
            visibleFrame.maxX - contentSize.width
        )
        let aboveY = region.maxY + edgeMargin
        if aboveY + contentSize.height <= visibleFrame.maxY {
            return CGRect(origin: CGPoint(x: centeredX, y: aboveY), size: contentSize)
        }

        let belowY = region.minY - edgeMargin - contentSize.height
        if belowY >= visibleFrame.minY {
            return CGRect(origin: CGPoint(x: centeredX, y: belowY), size: contentSize)
        }

        let fallbackOrigin = CGPoint(
            x: visibleFrame.maxX - contentSize.width,
            y: visibleFrame.maxY - contentSize.height
        )
        return CGRect(origin: fallbackOrigin, size: contentSize)
    }
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}
