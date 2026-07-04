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
        HStack(spacing: 10) {
            toolbarGroup(EditorToolbarAction.drawingTools)
            toolbarDivider
            colorPalette
            toolbarDivider
            strokeWidthPicker
            toolbarDivider
            toolbarGroup(EditorToolbarAction.historyCommands)
            toolbarDivider
            toolbarGroup(EditorToolbarAction.outputCommands)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.regularMaterial)
    }

    private func toolbarGroup(_ actions: [EditorToolbarAction]) -> some View {
        HStack(spacing: 5) {
            ForEach(actions) { action in
                Button {
                    viewModel.perform(action)
                } label: {
                    Image(systemName: action.systemImageName)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(EditorToolbarButtonStyle(isSelected: viewModel.isSelected(action)))
                .help("\(action.title) (\(action.shortcutHint))")
                .editorKeyboardShortcut(for: action)
            }
        }
    }

    private var colorPalette: some View {
        HStack(spacing: 5) {
            ForEach(EditorViewModel.strokeColorOptions) { option in
                Button {
                    viewModel.setStrokeColor(option)
                } label: {
                    Circle()
                        .fill(Color(nsColor: option.color))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(
                                    viewModel.isStrokeColorSelected(option)
                                        ? Color.accentColor
                                        : Color(nsColor: .separatorColor),
                                    lineWidth: viewModel.isStrokeColorSelected(option) ? 2 : 1
                                )
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stroke Color: \(option.name)")
            }
        }
    }

    private var strokeWidthPicker: some View {
        HStack(spacing: 5) {
            ForEach(EditorViewModel.strokeWidthOptions, id: \.self) { width in
                Button {
                    viewModel.setStrokeWidth(width)
                } label: {
                    Capsule()
                        .fill(Color(nsColor: .labelColor))
                        .frame(width: 21, height: max(2, min(width, 8)))
                        .frame(width: 32, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    viewModel.isStrokeWidthSelected(width)
                                        ? Color.accentColor.opacity(0.18)
                                        : Color(nsColor: .controlBackgroundColor).opacity(0.64)
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Stroke Width: \(Int(width))")
            }
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 2)
    }
}

private struct EditorToolbarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        }

        if isPressed {
            return Color(nsColor: .selectedControlColor).opacity(0.32)
        }

        return Color(nsColor: .controlBackgroundColor).opacity(0.72)
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

private final class EditorCanvasNSView: NSView {
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
        renderAnnotationLayers()
        needsLayout = true
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
        cursor(for: nil).set()
    }

    private func renderAnnotationLayers() {
        annotationLayerRenderer.render(
            annotations: annotationObjects,
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

    private func cursor(for imagePoint: CGPoint?) -> NSCursor {
        guard let imagePoint,
              let viewModel
        else {
            return drawingToolIsActive ? .crosshair : .arrow
        }

        switch viewModel.hitTestAnnotation(at: imagePoint, tolerance: hitTestTolerance) {
        case .resize:
            return .crosshair
        case .annotation:
            return .openHand
        case .empty:
            return drawingToolIsActive ? .crosshair : .arrow
        }
    }

    private var drawingToolIsActive: Bool {
        activeTool == .arrow || activeTool == .rectangle
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
        case .oval, .text, .highlight, .blurPixelate, .undo, .redo, .copy, .save:
            self
        }
    }
}
