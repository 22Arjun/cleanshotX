//
//  HotkeySetupWindowManager.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import SwiftUI

@MainActor
final class HotkeySetupWindowManager {
    private let windowSize = NSSize(width: 720, height: 620)
    private var window: NSWindow?
    private var windowDelegate: WindowCloseDelegate?
    private var viewModel: HotkeyOnboardingFlowViewModel?

    func show(viewModel: HotkeyOnboardingFlowViewModel) {
        self.viewModel = viewModel

        let closeDelegate = WindowCloseDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
            self?.viewModel = nil
        }

        let view = HotkeyOnboardingFlowView(viewModel: viewModel)

        if let window {
            window.contentView = NSHostingView(rootView: view)
            window.delegate = closeDelegate
            windowDelegate = closeDelegate
            window.setContentSize(windowSize)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "ClearshotX Setup"
        window.backgroundColor = .windowBackgroundColor
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = closeDelegate

        self.window = window
        windowDelegate = closeDelegate
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let window else {
            return
        }

        window.close()
        self.window = nil
        windowDelegate = nil
        viewModel = nil
    }
}

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
