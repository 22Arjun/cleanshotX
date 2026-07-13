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
    let onClick: () -> Void
    let onDragBegan: () -> Void
    let onDragEnded: (_ didDrop: Bool) -> Void

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
        view.onClick = onClick
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

final class CaptureFileDragSourceView: NSView, NSDraggingSource {
    var fileURL: URL?
    var sourceImage: NSImage?
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((_ didDrop: Bool) -> Void)?

    private let dragThreshold: CGFloat = 4
    private var mouseDownLocation: CGPoint?
    private var hasStartedDrag = false
    private var didStartSecurityScopedAccess = false
    private var activePasteboardWriter: CaptureDragPasteboardWriter?

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        hasStartedDrag = false
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

        let pasteboardWriter = CaptureDragPasteboardWriter(
            fileURL: fileURL,
            image: sourceImage
        )
        activePasteboardWriter = pasteboardWriter
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
        let previewSize = dragPreviewSize(for: sourceImage.size)
        let previewImage = dragPreview(for: sourceImage, size: previewSize)
        draggingItem.setDraggingFrame(
            NSRect(
                x: currentLocation.x - previewSize.width / 2,
                y: currentLocation.y - previewSize.height / 2,
                width: previewSize.width,
                height: previewSize.height
            ),
            contents: previewImage
        )

        hasStartedDrag = true
        onDragBegan?()

        let session = beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        if !hasStartedDrag {
            resetDragState()
            onClick?()
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

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let didDrop = !operation.isEmpty
        resetDragState()
        onDragEnded?(didDrop)
    }

    private func dragPreviewSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: 120, height: 80)
        }

        let scale = min(180 / imageSize.width, 120 / imageSize.height, 1)
        return NSSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
    }

    private func dragPreview(for image: NSImage, size: NSSize) -> NSImage {
        let preview = NSImage(size: size)
        preview.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        image.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        preview.unlockFocus()
        return preview
    }

    private func resetDragState() {
        if didStartSecurityScopedAccess {
            fileURL?.stopAccessingSecurityScopedResource()
            didStartSecurityScopedAccess = false
        }

        mouseDownLocation = nil
        hasStartedDrag = false
        activePasteboardWriter = nil
    }
}

private final class CaptureDragPasteboardWriter: NSObject, NSPasteboardWriting {
    private let fileURL: URL
    private let image: NSImage

    init(fileURL: URL, image: NSImage) {
        self.fileURL = fileURL
        self.image = image
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .png, .tiff]
    }

    func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        type == .fileURL ? [] : .promised
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            fileURL.absoluteString
        case .png:
            pngData()
        case .tiff:
            image.tiffRepresentation
        default:
            nil
        }
    }

    private func pngData() -> Data? {
        if let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) {
            return data
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
