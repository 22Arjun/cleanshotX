//
//  EditorWindowManager.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class EditorWindowManager {
    private let minimumWorkingSize = NSSize(width: 960, height: 460)
    private let defaultToolbarWidth: CGFloat = 1_220
    private let cropToolbarWidth: CGFloat = 1_320
    private let textToolbarWidth: CGFloat = 1_370
    private let maximumPreferredSize = NSSize(width: 1_400, height: 900)
    private let toolbarHeight: CGFloat = 62
    private let canvasHorizontalPadding: CGFloat = 96
    private let canvasVerticalPadding: CGFloat = 112
    private let screenHorizontalMargin: CGFloat = 20
    private let screenVerticalMargin: CGFloat = 24
    private let outputService: EditorOutputServicing

    private var windows: [UUID: EditorWindowRecord] = [:]

    init(outputService: EditorOutputServicing? = nil) {
        self.outputService = outputService ?? EditorOutputService()
    }

    func showEditor(for capture: CaptureResult) {
        showEditor(
            image: capture.image,
            sourceFileURL: capture.fileURL,
            preferredScreen: screen(for: capture.screenFrame)
        )
    }

    func showEditor(
        image: NSImage,
        sourceFileURL: URL? = nil,
        preferredScreen: NSScreen? = nil
    ) {
        let viewModel = EditorViewModel(
            image: image,
            sourceFileURL: sourceFileURL,
            outputService: outputService
        )
        let editorView = EditorView(viewModel: viewModel)
        let windowID = viewModel.id
        let targetScreen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        let closeDelegate = EditorWindowCloseDelegate { [weak self] in
            self?.windows[windowID] = nil
        }
        let contentSize = preferredContentSize(
            for: image,
            viewModel: viewModel,
            screen: targetScreen
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.contentMinSize = minimumContentSize(for: targetScreen)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.tabbingMode = .disallowed
        window.delegate = closeDelegate
        window.contentView = NSHostingView(rootView: editorView)
        center(window, on: targetScreen)

        let layoutObserver = Publishers.CombineLatest(
            viewModel.$activeTool,
            viewModel.$selectedAnnotationID
        )
        .dropFirst()
        .sink { [weak self, weak window, weak viewModel] _, _ in
            guard let self,
                  let window,
                  let viewModel
            else {
                return
            }

            self.expandWindowIfNeeded(window, for: viewModel, preferredScreen: targetScreen)
        }

        windows[windowID] = EditorWindowRecord(
            window: window,
            closeDelegate: closeDelegate,
            layoutObserver: layoutObserver
        )

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func preferredContentSize(
        for image: NSImage,
        viewModel: EditorViewModel,
        screen: NSScreen?
    ) -> NSSize {
        let screenCapacity = contentCapacity(for: screen)
        let screenLimitedSize = NSSize(
            width: min(maximumPreferredSize.width, screenCapacity.width),
            height: min(maximumPreferredSize.height, screenCapacity.height)
        )
        let availableCanvasSize = NSSize(
            width: max(1, screenLimitedSize.width - canvasHorizontalPadding),
            height: max(1, screenLimitedSize.height - toolbarHeight - canvasVerticalPadding)
        )
        let fittedImageSize = image.editorDisplaySize.aspectFitted(in: availableCanvasSize)
        let minimumSize = minimumContentSize(for: screen)
        let toolbarWidth = min(recommendedToolbarWidth(for: viewModel), screenCapacity.width)

        return NSSize(
            width: min(
                screenLimitedSize.width,
                max(minimumSize.width, toolbarWidth, fittedImageSize.width + canvasHorizontalPadding)
            ),
            height: min(
                screenLimitedSize.height,
                max(
                    minimumSize.height,
                    fittedImageSize.height + toolbarHeight + canvasVerticalPadding
                )
            )
        )
    }

    private func minimumContentSize(for screen: NSScreen?) -> NSSize {
        let capacity = contentCapacity(for: screen)
        return NSSize(
            width: min(minimumWorkingSize.width, capacity.width),
            height: min(minimumWorkingSize.height, capacity.height)
        )
    }

    private func contentCapacity(for screen: NSScreen?) -> NSSize {
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSSize(
            width: max(1, visibleFrame.width - screenHorizontalMargin * 2),
            height: max(1, visibleFrame.height - screenVerticalMargin * 2)
        )
    }

    private func recommendedToolbarWidth(for viewModel: EditorViewModel) -> CGFloat {
        if viewModel.isCropModeActive {
            return cropToolbarWidth
        }

        if viewModel.usesTextControls || viewModel.isTextEditingActive {
            return textToolbarWidth
        }

        return defaultToolbarWidth
    }

    private func expandWindowIfNeeded(
        _ window: NSWindow,
        for viewModel: EditorViewModel,
        preferredScreen: NSScreen?
    ) {
        let targetScreen = window.screen ?? preferredScreen ?? NSScreen.main
        let maximumWidth = contentCapacity(for: targetScreen).width
        let targetContentWidth = min(recommendedToolbarWidth(for: viewModel), maximumWidth)
        let currentContentWidth = window.contentLayoutRect.width

        guard targetContentWidth > currentContentWidth + 1 else {
            return
        }

        let targetContentRect = NSRect(
            origin: .zero,
            size: NSSize(width: targetContentWidth, height: window.contentLayoutRect.height)
        )
        var targetFrame = NSWindow.frameRect(
            forContentRect: targetContentRect,
            styleMask: window.styleMask
        )
        targetFrame.origin.x = window.frame.midX - targetFrame.width / 2
        targetFrame.origin.y = window.frame.minY
        targetFrame = frame(targetFrame, fittedHorizontallyTo: targetScreen?.visibleFrame)
        window.setFrame(targetFrame, display: true, animate: true)
    }

    private func center(_ window: NSWindow, on screen: NSScreen?) {
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        var frame = window.frame
        frame.origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrame(frame, display: false)
    }

    private func frame(_ frame: NSRect, fittedHorizontallyTo visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else {
            return frame
        }

        var fittedFrame = frame
        let minimumX = visibleFrame.minX + screenHorizontalMargin
        let maximumX = visibleFrame.maxX - screenHorizontalMargin - fittedFrame.width
        fittedFrame.origin.x = maximumX >= minimumX
            ? min(max(fittedFrame.minX, minimumX), maximumX)
            : visibleFrame.midX - fittedFrame.width / 2
        return fittedFrame
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.equalTo(frame)
        } ?? NSScreen.screens.max { lhs, rhs in
            intersectionArea(of: lhs.frame, and: frame) < intersectionArea(of: rhs.frame, and: frame)
        }
    }

    private func intersectionArea(of firstRect: CGRect, and secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }
}

private struct EditorWindowRecord {
    let window: NSWindow
    let closeDelegate: EditorWindowCloseDelegate
    let layoutObserver: AnyCancellable
}

private final class EditorWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private extension NSImage {
    var editorDisplaySize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSSize(width: 960, height: 540)
        }

        return NSSize(width: cgImage.width, height: cgImage.height)
    }
}

private extension NSSize {
    func aspectFitted(in boundingSize: NSSize) -> NSSize {
        guard width > 0, height > 0, boundingSize.width > 0, boundingSize.height > 0 else {
            return .zero
        }

        let scale = min(boundingSize.width / width, boundingSize.height / height, 1)
        return NSSize(width: width * scale, height: height * scale)
    }
}
