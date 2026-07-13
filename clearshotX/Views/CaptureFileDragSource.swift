//
//  CaptureFileDragSource.swift
//  clearshotX
//
//  Created by Codex on 13/07/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    private var activePasteboardWriter: NSFilePromiseProvider?
    private var activeDragDirectoryURL: URL?
    private var localMouseMonitor: Any?

    deinit {
        removeLocalMouseMonitor()
    }

    override var isFlipped: Bool {
        true
    }

    // The quick-access panel is transparent. Explicitly keep thumbnail drags
    // from being interpreted as background window drags by AppKit.
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeLocalMouseMonitor()
        } else {
            installLocalMouseMonitorIfNeeded()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        _ = beginDragIfNeeded(with: event)
    }

    private func beginDragIfNeeded(with event: NSEvent) -> Bool {
        guard !hasStartedDrag,
              let fileURL,
              let sourceImage,
              let mouseDownLocation
        else {
            return false
        }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(
            currentLocation.x - mouseDownLocation.x,
            currentLocation.y - mouseDownLocation.y
        )
        guard distance >= dragThreshold else {
            return false
        }

        didStartSecurityScopedAccess = fileURL.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSSound.beep()
            resetDragState()
            return false
        }

        guard let pngData = pngData(for: fileURL, fallbackImage: sourceImage) else {
            NSSound.beep()
            resetDragState()
            return false
        }

        guard let dragFileURL = makeDragFile(
            pngData: pngData,
            fileName: promisedFileName(for: fileURL)
        ) else {
            NSSound.beep()
            resetDragState()
            return false
        }

        let promiseDelegate = CaptureFilePromiseDelegate(
            fileName: promisedFileName(for: fileURL),
            pngData: pngData
        )
        let pasteboardWriter = NSFilePromiseProvider(
            fileType: UTType.data.identifier,
            delegate: promiseDelegate
        )
        // NSFilePromiseProvider keeps its delegate weakly. Retain the delegate
        // through userInfo until the destination finishes requesting the file.
        pasteboardWriter.userInfo = promiseDelegate
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

        let session = beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
        addCompatibleRepresentations(
            to: session.draggingPasteboard,
            fileURL: dragFileURL,
            pngData: pngData,
            tiffData: sourceImage.tiffRepresentation
        )
        return true
    }

    private func installLocalMouseMonitorIfNeeded() {
        guard localMouseMonitor == nil else {
            return
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMonitoredMouseEvent(event) ?? event
        }
    }

    private func removeLocalMouseMonitor() {
        guard let localMouseMonitor else {
            return
        }

        NSEvent.removeMonitor(localMouseMonitor)
        self.localMouseMonitor = nil
    }

    private func handleMonitoredMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else {
            return event
        }

        switch event.type {
        case .leftMouseDown:
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else {
                return event
            }

            mouseDownLocation = location
            hasStartedDrag = false
            return event

        case .leftMouseDragged:
            guard mouseDownLocation != nil else {
                return event
            }

            // The controls sit above this view and normally own their mouse
            // sequence. Consume only the event that crosses the threshold;
            // AppKit's dragging session owns the remaining drag events.
            return beginDragIfNeeded(with: event) ? nil : event

        case .leftMouseUp:
            if !hasStartedDrag {
                resetDragState()
            }
            return event

        default:
            return event
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint
    ) {
        onDragBegan?()
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
        [.copy, .generic]
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
        let dragDirectoryURL = activeDragDirectoryURL
        activeDragDirectoryURL = nil
        resetDragState()
        removeDragDirectory(
            dragDirectoryURL,
            after: didDrop ? 60 * 60 : 0
        )
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

    private func promisedFileName(for fileURL: URL) -> String {
        let fileName = fileURL.lastPathComponent
        if fileName.lowercased().hasSuffix(".png") {
            return fileName
        }

        return fileName + ".png"
    }

    private func pngData(for fileURL: URL, fallbackImage: NSImage) -> Data? {
        if let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) {
            return data
        }

        guard let tiffData = fallbackImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private func makeDragFile(pngData: Data, fileName: String) -> URL? {
        let fileManager = FileManager.default
        let exportsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ClearShotX-DragExports", isDirectory: true)
        removeExpiredDragDirectories(in: exportsDirectory)

        let dragDirectory = exportsDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dragFileURL = dragDirectory.appendingPathComponent(fileName)

        do {
            try fileManager.createDirectory(
                at: dragDirectory,
                withIntermediateDirectories: true
            )
            try pngData.write(to: dragFileURL, options: .atomic)
            activeDragDirectoryURL = dragDirectory
            return dragFileURL
        } catch {
            try? fileManager.removeItem(at: dragDirectory)
            return nil
        }
    }

    private func removeExpiredDragDirectories(in exportsDirectory: URL) {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let expirationDate = Date().addingTimeInterval(-24 * 60 * 60)
        for directory in directories {
            guard let values = try? directory.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            ),
            values.isDirectory == true,
            let modificationDate = values.contentModificationDate,
            modificationDate < expirationDate
            else {
                continue
            }

            try? fileManager.removeItem(at: directory)
        }
    }

    private func addCompatibleRepresentations(
        to pasteboard: NSPasteboard,
        fileURL: URL,
        pngData: Data,
        tiffData: Data?
    ) {
        pasteboard.setString(fileURL.absoluteString, forType: .fileURL)
        pasteboard.setData(pngData, forType: .png)
        if let tiffData {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    private func removeDragDirectory(_ directoryURL: URL?, after delay: TimeInterval) {
        guard let directoryURL else {
            return
        }

        let remove: @Sendable () -> Void = {
            _ = try? FileManager.default.removeItem(at: directoryURL)
        }

        if delay <= 0 {
            remove()
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: remove
        )
    }

    private func resetDragState() {
        if didStartSecurityScopedAccess {
            fileURL?.stopAccessingSecurityScopedResource()
            didStartSecurityScopedAccess = false
        }

        mouseDownLocation = nil
        hasStartedDrag = false
        activePasteboardWriter = nil
        if let activeDragDirectoryURL {
            try? FileManager.default.removeItem(at: activeDragDirectoryURL)
            self.activeDragDirectoryURL = nil
        }
    }
}

private final class CaptureFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let fileName: String
    private let pngData: Data
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.22Arjun.clearshotX.capture-file-promise"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(fileName: String, pngData: Data) {
        self.fileName = fileName
        self.pngData = pngData
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        fileName
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        promiseQueue
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        do {
            try pngData.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
