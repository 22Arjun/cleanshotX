//
//  SettingsWindowManager.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowManager {
    #if DEBUG
    private let windowSize = NSSize(width: 520, height: 720)
    #else
    private let windowSize = NSSize(width: 520, height: 630)
    #endif

    private var window: NSWindow?
    private var windowDelegate: SettingsWindowCloseDelegate?

    func show(viewModel: AppShellViewModel) {
        let closeDelegate = SettingsWindowCloseDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        let view = SettingsView(viewModel: viewModel)

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
        window.title = "ClearshotX Settings"
        window.backgroundColor = .windowBackgroundColor
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = closeDelegate

        self.window = window
        windowDelegate = closeDelegate
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class SettingsWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
