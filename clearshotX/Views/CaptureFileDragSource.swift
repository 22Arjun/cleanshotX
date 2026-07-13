//
//  CaptureFileDragSource.swift
//  clearshotX
//
//  Created by Codex on 13/07/26.
//

import AppKit
import SwiftUI

struct CaptureFileDragSource: NSViewRepresentable {
    let fileURL: URL
    let image: NSImage
    let onDragBegan: () -> Void
    let onDragEnded: (_ didDrop: Bool, _ shouldKeepSourceVisible: Bool) -> Void

    func makeNSView(context: Context) -> CaptureFileDragSourceView {
        let view = CaptureFileDragSourceView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: CaptureFileDragSourceView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: CaptureFileDragSourceView) {
        view.fileURL = fileURL
        view.sourceImage = image
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

final class CaptureFileDragSourceView: NSView, NSDraggingSource {
    var fileURL: URL?
    var sourceImage: NSImage?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((_ didDrop: Bool, _ shouldKeepSourceVisible: Bool) -> Void)?

    private let dragThreshold: CGFloat = 3
    private var mouseDownLocation: CGPoint?
    private var hasStartedDrag = false
    private var shouldKeepSourceVisible = false
    private var didStartSecurityScopedAccess = false

    override var isFlipped: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        hasStartedDrag = false
        shouldKeepSourceVisible = event.modifierFlags.contains(.option)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasStartedDrag,
              let fileURL,
              let sourceImage,
              let mouseDownLocation
        else {
            return
        }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(
            currentLocation.x - mouseDownLocation.x,
            currentLocation.y - mouseDownLocation.y
        )
        guard distance >= dragThreshold else {
            return
        }

        didStartSecurityScopedAccess = fileURL.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSSound.beep()
            resetDragState()
            return
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let previewSize = dragPreviewSize(for: sourceImage.size)
        draggingItem.setDraggingFrame(
            NSRect(
                x: currentLocation.x - previewSize.width / 2,
                y: currentLocation.y - previewSize.height / 2,
                width: previewSize.width,
                height: previewSize.height
            ),
            contents: sourceImage
        )

        hasStartedDrag = true
        shouldKeepSourceVisible = event.modifierFlags.contains(.option)
        onDragBegan?()

        let session = beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        if !hasStartedDrag {
            resetDragState()
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        shouldKeepSourceVisible = NSEvent.modifierFlags.contains(.option)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let didDrop = !operation.isEmpty
        let keepSourceVisible = shouldKeepSourceVisible
        resetDragState()
        onDragEnded?(didDrop, keepSourceVisible)
    }

    private func dragPreviewSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: 120, height: 80)
        }

        let scale = min(160 / imageSize.width, 100 / imageSize.height, 1)
        return NSSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
    }

    private func resetDragState() {
        if didStartSecurityScopedAccess {
            fileURL?.stopAccessingSecurityScopedResource()
            didStartSecurityScopedAccess = false
        }

        mouseDownLocation = nil
        hasStartedDrag = false
        shouldKeepSourceVisible = false
    }
}
