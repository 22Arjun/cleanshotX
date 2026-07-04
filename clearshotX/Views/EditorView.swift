//
//  EditorView.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import QuartzCore
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbarView(viewModel: viewModel)
            Divider()
            EditorCanvasView(
                viewModel: viewModel,
                image: viewModel.image,
                annotationObjects: viewModel.annotationObjects,
                draftAnnotationObject: viewModel.draftAnnotationObject,
                selectedAnnotationID: viewModel.selectedAnnotationID,
                activeTool: viewModel.activeTool
            )
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EditorToolbarView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 8) {
            toolButtonGroup(EditorToolbarAction.drawingTools)
            colorPalette
            strokeWidthPicker
            textSizeMenu
            opacityMenu
            Spacer(minLength: 12)
            toolButtonGroup(EditorToolbarAction.historyCommands)
            toolButtonGroup(EditorToolbarAction.outputCommands)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.72))
                        .frame(height: 1)
                }
        }
    }

    private func toolButtonGroup(_ actions: [EditorToolbarAction]) -> some View {
        HStack(spacing: 3) {
            ForEach(actions) { action in
                Button {
                    viewModel.perform(action)
                } label: {
                    Image(systemName: action.systemImageName)
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 34, height: 34)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(EditorToolbarButtonStyle(isSelected: viewModel.isSelected(action)))
                .disabled(!viewModel.isEnabled(action))
                .help("\(action.title) (\(action.shortcutHint))")
                .editorKeyboardShortcut(for: action)
            }
        }
        .toolbarGroupChrome()
    }

    private var colorPalette: some View {
        HStack(spacing: 3) {
            ForEach(EditorViewModel.strokeColorOptions) { option in
                Button {
                    viewModel.setStrokeColor(option)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                viewModel.isStrokeColorSelected(option)
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.clear
                            )

                        Circle()
                            .fill(Color(nsColor: option.color))
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.78), lineWidth: 1)
                            }
                            .overlay {
                                if viewModel.isStrokeColorSelected(option) {
                                    Circle()
                                        .stroke(Color.accentColor, lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                }
                            }
                    }
                    .frame(width: 34, height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(EditorPaletteButtonStyle(isSelected: viewModel.isStrokeColorSelected(option)))
                .help("Stroke Color: \(option.name)")
            }
        }
        .toolbarGroupChrome()
    }

    private var strokeWidthPicker: some View {
        HStack(spacing: 3) {
            ForEach(EditorViewModel.strokeWidthOptions, id: \.self) { width in
                Button {
                    viewModel.setStrokeWidth(width)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                viewModel.isStrokeWidthSelected(width)
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.clear
                            )

                        Capsule()
                            .fill(
                                viewModel.isStrokeWidthSelected(width)
                                    ? Color.accentColor
                                    : Color(nsColor: .labelColor).opacity(0.82)
                            )
                            .frame(width: 20, height: max(2, min(width, 8)))
                    }
                    .frame(width: 34, height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(EditorPaletteButtonStyle(isSelected: viewModel.isStrokeWidthSelected(width)))
                .help("Stroke Width: \(Int(width))")
            }
        }
        .toolbarGroupChrome()
    }

    private var textSizeMenu: some View {
        Menu {
            ForEach(EditorViewModel.textSizeOptions, id: \.self) { size in
                Button {
                    viewModel.setTextSize(size)
                } label: {
                    HStack {
                        if viewModel.isTextSizeSelected(size) {
                            Image(systemName: "checkmark")
                        }
                        Text("\(Int(size)) pt")
                    }
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.clear)

                Text("A")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor).opacity(0.88))
            }
            .frame(width: 34, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .help("Text Size: \(Int(viewModel.selectedTextSize)) pt")
        .toolbarGroupChrome()
    }

    private var opacityMenu: some View {
        Menu {
            ForEach(EditorViewModel.opacityOptions, id: \.self) { opacity in
                Button {
                    viewModel.setOpacity(opacity)
                } label: {
                    HStack {
                        if viewModel.isOpacitySelected(opacity) {
                            Image(systemName: "checkmark")
                        }
                        Text("\(Int(opacity * 100))%")
                    }
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.clear)

                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(nsColor: viewModel.selectedStrokeColor).opacity(viewModel.selectedOpacity))
            }
            .frame(width: 34, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .help("Opacity: \(Int(viewModel.selectedOpacity * 100))%")
        .toolbarGroupChrome()
    }
}

private extension View {
    func toolbarGroupChrome() -> some View {
        padding(4)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
    }
}

private struct EditorToolbarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
    }

    private var foregroundColor: Color {
        isSelected ? Color.white : Color(nsColor: .labelColor).opacity(0.88)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        }

        if isPressed {
            return Color(nsColor: .selectedControlColor).opacity(0.28)
        }

        return Color.clear
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.white.opacity(0.22)
        }

        if isPressed {
            return Color(nsColor: .separatorColor).opacity(0.72)
        }

        return Color.clear
    }
}

private struct EditorPaletteButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color(nsColor: .selectedControlColor).opacity(0.22) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct EditorCanvasView: NSViewRepresentable {
    let viewModel: EditorViewModel
    let image: NSImage
    let annotationObjects: [AnnotationObject]
    let draftAnnotationObject: AnnotationObject?
    let selectedAnnotationID: UUID?
    let activeTool: EditorTool?

    func makeNSView(context: Context) -> EditorCanvasNSView {
        let view = EditorCanvasNSView()
        view.configure(
            viewModel: viewModel,
            image: image,
            annotationObjects: annotationObjects,
            draftAnnotationObject: draftAnnotationObject,
            selectedAnnotationID: selectedAnnotationID,
            activeTool: activeTool
        )
        return view
    }

    func updateNSView(_ nsView: EditorCanvasNSView, context: Context) {
        nsView.configure(
            viewModel: viewModel,
            image: image,
            annotationObjects: annotationObjects,
            draftAnnotationObject: draftAnnotationObject,
            selectedAnnotationID: selectedAnnotationID,
            activeTool: activeTool
        )
    }
}

private final class EditorCanvasNSView: NSView, NSTextViewDelegate {
    private let imageContainerLayer = CALayer()
    private let imageLayer = CALayer()
    private let annotationContainerLayer = CALayer()
    private let annotationLayerRenderer = AnnotationLayerRenderer()

    private weak var viewModel: EditorViewModel?
    private var currentImage: NSImage?
    private var annotationObjects: [AnnotationObject] = []
    private var draftAnnotationObject: AnnotationObject?
    private var selectedAnnotationID: UUID?
    private var activeTool: EditorTool?
    private var imageFrameInView: CGRect = .zero
    private var imageDisplayScale: CGFloat = 1
    private var trackingArea: NSTrackingArea?
    private var activeTextView: AnnotationTextView?
    private var activeTextAnnotationID: UUID?
    private var isFinishingTextEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerScale()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
    }

    override func layout() {
        super.layout()
        layoutCanvasLayers()
        updateActiveTextEditorFrame()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor(for: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(for: imagePoint(from: event, clamped: false)).set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        if activeTextView != nil {
            finishActiveTextEditing()
        }

        guard let point = imagePoint(from: event, clamped: false),
              let viewModel
        else {
            viewModel?.deselectAnnotation()
            renderAnnotationLayers()
            return
        }

        let hitResult = viewModel.hitTestAnnotation(
            at: point,
            tolerance: hitTestTolerance
        )

        if handleTextInteraction(at: point, hitResult: hitResult, event: event) {
            return
        }

        viewModel.beginCanvasInteraction(at: point, hitResult: hitResult)
        refreshFromViewModel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = imagePoint(from: event, clamped: true),
              let viewModel
        else {
            return
        }

        viewModel.updateCanvasInteraction(to: point)
        refreshFromViewModel()
    }

    override func mouseUp(with event: NSEvent) {
        guard let viewModel else {
            return
        }

        if let point = imagePoint(from: event, clamped: true) {
            viewModel.updateCanvasInteraction(to: point)
        }

        viewModel.endCanvasInteraction()
        refreshFromViewModel()
    }

    override func keyDown(with event: NSEvent) {
        guard let viewModel else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 51, 117:
            viewModel.deleteSelectedAnnotation()
            refreshFromViewModel()
        case 53:
            viewModel.clearActiveTool()
            refreshFromViewModel()
        default:
            if event.modifierFlags.contains(.command),
               let shortcut = event.charactersIgnoringModifiers?.lowercased() {
                switch shortcut {
                case "z" where event.modifierFlags.contains(.shift):
                    viewModel.redo()
                    refreshFromViewModel()
                    return
                case "z":
                    viewModel.undo()
                    refreshFromViewModel()
                    return
                case "y":
                    viewModel.redo()
                    refreshFromViewModel()
                    return
                default:
                    break
                }
            }

            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let shortcut = event.charactersIgnoringModifiers,
                  viewModel.handleShortcut(shortcut)
            else {
                super.keyDown(with: event)
                return
            }

            refreshFromViewModel()
        }
    }

    func configure(
        viewModel: EditorViewModel,
        image: NSImage,
        annotationObjects: [AnnotationObject],
        draftAnnotationObject: AnnotationObject?,
        selectedAnnotationID: UUID?,
        activeTool: EditorTool?
    ) {
        self.viewModel = viewModel
        currentImage = image
        self.annotationObjects = annotationObjects
        self.draftAnnotationObject = draftAnnotationObject
        self.selectedAnnotationID = selectedAnnotationID
        self.activeTool = activeTool
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        removeTextEditorIfAnnotationDisappeared()
        renderAnnotationLayers()
        needsLayout = true
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === activeTextView else {
            return
        }

        resizeActiveTextEditorToFitContent()
        syncActiveTextEditorToViewModel()
    }

    func textDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextView === activeTextView,
              !isFinishingTextEditing
        else {
            return
        }

        finishActiveTextEditing()
    }

    private func handleTextInteraction(
        at point: CGPoint,
        hitResult: AnnotationHitResult,
        event: NSEvent
    ) -> Bool {
        guard let viewModel else {
            return false
        }

        if case let .annotation(annotationID) = hitResult,
           event.clickCount >= 2,
           viewModel.beginTextEditing(annotationID: annotationID) {
            refreshFromViewModel()
            beginTextEditor(for: annotationID)
            return true
        }

        guard activeTool == .text else {
            return false
        }

        switch hitResult {
        case .resize:
            return false
        case let .annotation(annotationID):
            guard viewModel.beginTextEditing(annotationID: annotationID) else {
                return false
            }

            refreshFromViewModel()
            beginTextEditor(for: annotationID)
            return true
        case .empty:
            let annotationID = viewModel.beginTextAnnotation(at: point)
            refreshFromViewModel()
            beginTextEditor(for: annotationID)
            return true
        }
    }

    private func beginTextEditor(for annotationID: UUID) {
        finishActiveTextEditing()

        guard let viewModel,
              let annotation = viewModel.textAnnotation(withID: annotationID),
              case let .text(rect, text) = annotation.geometry
        else {
            return
        }

        let textView = AnnotationTextView(frame: viewRect(forImageRect: rect.standardizedForEditor))
        textView.delegate = self
        textView.string = text
        textView.font = NSFont.systemFont(
            ofSize: max(8, annotation.style.fontSize * imageDisplayScale),
            weight: .semibold
        )
        textView.textColor = annotation.style.strokeColor.withAlphaComponent(annotation.style.opacity)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 4, height: 3)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: textView.bounds.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.onCommit = { [weak self] in
            self?.finishActiveTextEditing()
        }
        textView.wantsLayer = true
        textView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        textView.layer?.borderWidth = 1.5
        textView.layer?.cornerRadius = 4

        addSubview(textView)
        activeTextView = textView
        activeTextAnnotationID = annotationID
        renderAnnotationLayers()
        resizeActiveTextEditorToFitContent()
        window?.makeFirstResponder(textView)

        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    private func finishActiveTextEditing() {
        guard let textView = activeTextView,
              let annotationID = activeTextAnnotationID,
              let viewModel
        else {
            return
        }

        isFinishingTextEditing = true
        syncActiveTextEditorToViewModel()
        textView.delegate = nil
        textView.removeFromSuperview()
        activeTextView = nil
        activeTextAnnotationID = nil
        viewModel.endTextEditing(annotationID: annotationID)
        isFinishingTextEditing = false
        refreshFromViewModel()
        window?.makeFirstResponder(self)
    }

    private func removeTextEditorIfAnnotationDisappeared() {
        guard let activeTextAnnotationID,
              !annotationObjects.contains(where: { annotation in
                  annotation.id == activeTextAnnotationID
              })
        else {
            return
        }

        activeTextView?.delegate = nil
        activeTextView?.removeFromSuperview()
        activeTextView = nil
        self.activeTextAnnotationID = nil
    }

    private func syncActiveTextEditorToViewModel() {
        guard let textView = activeTextView,
              let annotationID = activeTextAnnotationID,
              imageDisplayScale > 0
        else {
            return
        }

        viewModel?.updateEditingText(
            annotationID: annotationID,
            text: textView.string,
            rect: imageRect(forViewRect: textView.frame)
        )
    }

    private func resizeActiveTextEditorToFitContent() {
        guard let textView = activeTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let targetHeight = ceil(
            max(
                36,
                usedRect.height + textView.textContainerInset.height * 2 + 10
            )
        )
        let maxHeight = max(36, imageFrameInView.maxY - textView.frame.minY)

        var frame = textView.frame
        frame.size.height = min(maxHeight, targetHeight)
        textView.frame = frame
        syncActiveTextEditorToViewModel()
    }

    private func updateActiveTextEditorFrame() {
        guard let activeTextAnnotationID,
              let annotation = viewModel?.textAnnotation(withID: activeTextAnnotationID),
              case let .text(rect, _) = annotation.geometry
        else {
            return
        }

        activeTextView?.frame = viewRect(forImageRect: rect.standardizedForEditor)
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        layer?.masksToBounds = true

        imageContainerLayer.shadowColor = NSColor.black.cgColor
        imageContainerLayer.shadowOpacity = 0.22
        imageContainerLayer.shadowRadius = 20
        imageContainerLayer.shadowOffset = CGSize(width: 0, height: 10)

        imageLayer.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        imageLayer.cornerRadius = 10
        imageLayer.masksToBounds = true

        // Core Animation layers are the canvas foundation here because future tools can map
        // each annotation object to its own CALayer/CAShapeLayer for ordering, hit testing,
        // transforms, and export without making SwiftUI redraw the captured bitmap itself.
        annotationContainerLayer.name = "AnnotationContainerLayer"
        annotationContainerLayer.cornerRadius = 10
        annotationContainerLayer.masksToBounds = true

        layer?.addSublayer(imageContainerLayer)
        imageContainerLayer.addSublayer(imageLayer)
        imageContainerLayer.addSublayer(annotationContainerLayer)
        updateLayerScale()
    }

    private func layoutCanvasLayers() {
        guard let currentImage else {
            imageContainerLayer.frame = .zero
            imageFrameInView = .zero
            imageDisplayScale = 1
            return
        }

        let availableBounds = bounds.insetBy(dx: 28, dy: 28)
        let imageSize = currentImage.editorCanvasSize
        imageDisplayScale = imageSize.aspectFitScale(in: availableBounds.size)
        let fittedSize = NSSize(
            width: imageSize.width * imageDisplayScale,
            height: imageSize.height * imageDisplayScale
        )
        let imageFrame = CGRect(
            x: availableBounds.midX - fittedSize.width / 2,
            y: availableBounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        imageFrameInView = imageFrame

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageContainerLayer.bounds = CGRect(origin: .zero, size: imageSize)
        imageContainerLayer.position = CGPoint(x: imageFrame.midX, y: imageFrame.midY)
        imageContainerLayer.setAffineTransform(
            CGAffineTransform(scaleX: imageDisplayScale, y: imageDisplayScale)
        )
        imageLayer.frame = imageContainerLayer.bounds
        annotationContainerLayer.frame = imageContainerLayer.bounds
        imageContainerLayer.shadowPath = CGPath(
            roundedRect: imageContainerLayer.bounds,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        CATransaction.commit()

        renderAnnotationLayers()
    }

    private func refreshFromViewModel() {
        guard let viewModel else {
            return
        }

        annotationObjects = viewModel.annotationObjects
        draftAnnotationObject = viewModel.draftAnnotationObject
        selectedAnnotationID = viewModel.selectedAnnotationID
        activeTool = viewModel.activeTool
        renderAnnotationLayers()
        updateActiveTextEditorFrame()
        cursor(for: nil).set()
    }

    private func renderAnnotationLayers() {
        let visibleAnnotations = annotationObjects.filter { annotation in
            annotation.id != activeTextAnnotationID
        }

        annotationLayerRenderer.render(
            annotations: visibleAnnotations,
            draftAnnotation: draftAnnotationObject,
            selectedAnnotationID: selectedAnnotationID,
            in: annotationContainerLayer,
            contentsScale: currentLayerScale,
            selectionHandleSize: max(8, 8 / imageDisplayScale)
        )
    }

    private func updateLayerScale() {
        layer?.contentsScale = currentLayerScale
        imageContainerLayer.contentsScale = currentLayerScale
        imageLayer.contentsScale = currentLayerScale
        annotationContainerLayer.contentsScale = currentLayerScale
    }

    private var currentLayerScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var hitTestTolerance: CGFloat {
        max(6, 10 / imageDisplayScale)
    }

    private func imagePoint(from event: NSEvent, clamped: Bool) -> CGPoint? {
        imagePoint(from: convert(event.locationInWindow, from: nil), clamped: clamped)
    }

    private func imagePoint(from viewPoint: CGPoint, clamped: Bool) -> CGPoint? {
        guard imageFrameInView.width > 0, imageFrameInView.height > 0 else {
            return nil
        }

        guard clamped || imageFrameInView.contains(viewPoint) else {
            return nil
        }

        let rawPoint = CGPoint(
            x: (viewPoint.x - imageFrameInView.minX) / imageDisplayScale,
            y: (viewPoint.y - imageFrameInView.minY) / imageDisplayScale
        )

        guard clamped else {
            return rawPoint
        }

        return rawPoint.clamped(to: annotationContainerLayer.bounds)
    }

    private func viewRect(forImageRect imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageFrameInView.minX + imageRect.minX * imageDisplayScale,
            y: imageFrameInView.minY + imageRect.minY * imageDisplayScale,
            width: imageRect.width * imageDisplayScale,
            height: imageRect.height * imageDisplayScale
        )
    }

    private func imageRect(forViewRect viewRect: CGRect) -> CGRect {
        CGRect(
            x: (viewRect.minX - imageFrameInView.minX) / imageDisplayScale,
            y: (viewRect.minY - imageFrameInView.minY) / imageDisplayScale,
            width: viewRect.width / imageDisplayScale,
            height: viewRect.height / imageDisplayScale
        ).standardizedForEditor
    }

    private func cursor(for imagePoint: CGPoint?) -> NSCursor {
        guard let imagePoint,
              let viewModel
        else {
            return activeTool == .text ? .iBeam : drawingToolIsActive ? .crosshair : .arrow
        }

        switch viewModel.hitTestAnnotation(at: imagePoint, tolerance: hitTestTolerance) {
        case .resize:
            return .crosshair
        case let .annotation(annotationID):
            if activeTool == .text,
               viewModel.textAnnotation(withID: annotationID) != nil {
                return .iBeam
            }

            return .openHand
        case .empty:
            if activeTool == .text {
                return .iBeam
            }

            return drawingToolIsActive ? .crosshair : .arrow
        }
    }

    private var drawingToolIsActive: Bool {
        activeTool == .arrow || activeTool == .rectangle || activeTool == .oval
    }
}

private final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 ||
            (event.keyCode == 36 && event.modifierFlags.contains(.command)) {
            onCommit?()
            return
        }

        super.keyDown(with: event)
    }
}

private extension NSImage {
    var editorCanvasSize: NSSize {
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

        let scale = min(boundingSize.width / width, boundingSize.height / height)
        return NSSize(width: width * scale, height: height * scale)
    }

    func aspectFitScale(in boundingSize: NSSize) -> CGFloat {
        guard width > 0, height > 0, boundingSize.width > 0, boundingSize.height > 0 else {
            return 1
        }

        return min(boundingSize.width / width, boundingSize.height / height, 1)
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}

private extension View {
    @ViewBuilder
    func editorKeyboardShortcut(for action: EditorToolbarAction) -> some View {
        switch action {
        case .arrow:
            keyboardShortcut("a", modifiers: [])
        case .rectangle:
            keyboardShortcut("r", modifiers: [])
        case .oval:
            keyboardShortcut("o", modifiers: [])
        case .text:
            keyboardShortcut("t", modifiers: [])
        case .undo:
            keyboardShortcut("z", modifiers: [.command])
        case .redo:
            keyboardShortcut("z", modifiers: [.command, .shift])
        case .highlight, .blurPixelate, .copy, .save:
            self
        }
    }
}
