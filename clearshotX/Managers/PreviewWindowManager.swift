//
//  PreviewWindowManager.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import SwiftUI

final class PreviewWindowManager {
    private var previewWindow: NSWindow?

    func showPreview(for capture: CaptureResult, clipboardService: ClipboardService) {
        let previewView = CapturePreviewView(
            capture: capture,
            onCopy: {
                clipboardService.copy(capture.image)
            },
            onRevealInFinder: {
                NSWorkspace.shared.activateFileViewerSelecting([capture.fileURL])
            }
        )

        if let previewWindow {
            previewWindow.contentView = NSHostingView(rootView: previewView)
            previewWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClearshotX Preview"
        window.center()
        window.contentMinSize = NSSize(width: 520, height: 380)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: previewView)

        previewWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
