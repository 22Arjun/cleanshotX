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
                draftCropRect: viewModel.draftCropRect,
                isCropGridVisible: viewModel.isCropGridVisible,
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
    private static let cropDimensionFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isCropModeActive {
                cropToolbarContent
            } else {
                annotationToolbarContent
            }
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
        .overlay {
            EditorToolbarCursorShield()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var annotationToolbarContent: some View {
        Group {
            toolButtonGroup(EditorToolbarAction.drawingTools)
            colorPalette
            strokeWidthPicker
            textSizeMenu
            opacityMenu
            Spacer(minLength: 12)
            toolButtonGroup(EditorToolbarAction.historyCommands)
            toolButtonGroup(EditorToolbarAction.outputCommands)
        }
    }

    private var cropToolbarContent: some View {
        Group {
            cropModeButtonGroup
            cropRatioMenu
            cropDimensionControls
            cropCanvasColorMenu
            toolbarDivider
            cropTransformControls
            toolbarDivider
            cropImageSizeMenu
            Spacer(minLength: 12)
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
                .accessibilityLabel(action.title)
                .accessibilityHint("Shortcut \(action.shortcutHint)")
                .toolbarCursor(viewModel.isEnabled(action) ? .pointingHand : .arrow)
            }
        }
        .toolbarGroupChrome()
    }

    private var cropRatioMenu: some View {
        Menu {
            if let customOption = cropRatioOption(id: "custom") {
                Button {
                    viewModel.setCropRatio(customOption)
                } label: {
                    cropRatioMenuItem(customOption)
                }
                .help("Lock the crop frame to its current ratio")
            }

            Divider()

            if let freeformOption = cropRatioOption(id: "freeform") {
                Button {
                    viewModel.setCropRatio(freeformOption)
                } label: {
                    cropRatioMenuItem(freeformOption)
                }
            }

            Divider()

            ForEach(EditorViewModel.cropRatioOptions.filter { option in
                option.id != "custom" && option.id != "freeform"
            }) { option in
                Button {
                    viewModel.setCropRatio(option)
                } label: {
                    cropRatioMenuItem(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "aspectratio")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(viewModel.selectedCropRatioTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(minWidth: 96, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .foregroundStyle(Color(nsColor: .labelColor).opacity(0.9))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .help("Crop Ratio: \(viewModel.selectedCropRatioTitle)")
        .accessibilityLabel("Crop Ratio")
        .accessibilityValue(viewModel.selectedCropRatioTitle)
        .toolbarGroupChrome()
        .toolbarCursor(.pointingHand)
    }

    private func cropRatioOption(id: String) -> EditorCropRatioOption? {
        EditorViewModel.cropRatioOptions.first { option in
            option.id == id
        }
    }

    private func cropRatioMenuItem(_ option: EditorCropRatioOption) -> some View {
        HStack {
            if viewModel.isCropRatioSelected(option) {
                Image(systemName: "checkmark")
            }

            Text(option.title)
        }
    }

    private var cropModeButtonGroup: some View {
        HStack(spacing: 3) {
            Button {
                viewModel.perform(.crop)
            } label: {
                Image(systemName: EditorToolbarAction.crop.systemImageName)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 34, height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(EditorToolbarButtonStyle(isSelected: true))
            .help("Exit Crop Mode (\(EditorToolbarAction.crop.shortcutHint))")
            .editorKeyboardShortcut(for: .crop)
            .accessibilityLabel("Exit Crop Mode")
            .accessibilityHint("Return to annotation tools")
            .toolbarCursor(.pointingHand)
        }
        .toolbarGroupChrome()
    }

    private var cropDimensionControls: some View {
        HStack(spacing: 8) {
            cropDimensionField(
                value: Binding(
                    get: { viewModel.cropFramePixelWidth },
                    set: { viewModel.setCropFramePixelWidth($0) }
                ),
                accessibilityLabel: "Crop Width"
            )

            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 18)
                .help("Crop dimensions")
                .accessibilityHidden(true)

            cropDimensionField(
                value: Binding(
                    get: { viewModel.cropFramePixelHeight },
                    set: { viewModel.setCropFramePixelHeight($0) }
                ),
                accessibilityLabel: "Crop Height"
            )
        }
    }

    private func cropDimensionField(
        value: Binding<Int>,
        accessibilityLabel: String
    ) -> some View {
        TextField("", value: value, formatter: Self.cropDimensionFormatter)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(nsColor: .labelColor).opacity(0.9))
            .frame(width: 74, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.52), lineWidth: 1)
            }
            .help("\(accessibilityLabel) in pixels")
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(value.wrappedValue) pixels")
            .toolbarCursor(.iBeam)
    }

    private var cropCanvasColorMenu: some View {
        Menu {
            ForEach(EditorViewModel.cropFillColorOptions) { option in
                Button {
                    viewModel.setCropFillColor(option)
                } label: {
                    Label {
                        Text(viewModel.isCropFillColorSelected(option) ? "✓ \(option.name)" : "  \(option.name)")
                    } icon: {
                        Image(nsImage: cropFillSwatchImage(color: option.color, size: 16))
                            .renderingMode(.original)
                    }
                }
            }
        } label: {
            Image(nsImage: cropFillSwatchImage(color: viewModel.selectedCropFillColor, size: 24))
                .renderingMode(.original)
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .frame(width: 34, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Canvas Fill Color: \(viewModel.selectedCropFillColorName)")
        .accessibilityLabel("Canvas Fill Color")
        .accessibilityValue(viewModel.selectedCropFillColorName)
        .toolbarGroupChrome()
        .toolbarCursor(.pointingHand)
    }

    private var cropTransformControls: some View {
        HStack(spacing: 3) {
            Button {
                viewModel.rotateCropImageClockwise()
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 34, height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(EditorToolbarButtonStyle(isSelected: false))
            .help("Rotate 90° Clockwise")
            .accessibilityLabel("Rotate 90 Degrees Clockwise")
            .toolbarCursor(.pointingHand)

            Button {
                viewModel.flipCropImageHorizontally()
            } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 34, height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(EditorToolbarButtonStyle(isSelected: false))
            .help("Flip Horizontally")
            .accessibilityLabel("Flip Horizontally")
            .toolbarCursor(.pointingHand)

            Button {
                viewModel.flipCropImageVertically()
            } label: {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 34, height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(EditorToolbarButtonStyle(isSelected: false))
            .help("Flip Vertically")
            .accessibilityLabel("Flip Vertically")
            .toolbarCursor(.pointingHand)
        }
        .toolbarGroupChrome()
    }

    private var cropImageSizeMenu: some View {
        HStack(spacing: 8) {
            Text("Image size:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Text(viewModel.canvasPixelSizeTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: .labelColor).opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .help("Image Size: \(viewModel.canvasPixelSizeTitle)")
        .accessibilityLabel("Image Size")
        .accessibilityValue(viewModel.canvasPixelSizeTitle)
        .toolbarGroupChrome()
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
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
                .accessibilityLabel("Stroke Color \(option.name)")
                .toolbarCursor(.pointingHand)
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
                .help(viewModel.activeTool == .blurPixelate ? "Pixelate Strength: \(Int(width))" : "Stroke Width: \(Int(width))")
                .accessibilityLabel(viewModel.activeTool == .blurPixelate ? "Pixelate Strength \(Int(width))" : "Stroke Width \(Int(width))")
                .toolbarCursor(.pointingHand)
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
        .accessibilityLabel("Text Size")
        .accessibilityValue("\(Int(viewModel.selectedTextSize)) points")
        .toolbarGroupChrome()
        .toolbarCursor(.pointingHand)
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
        .accessibilityLabel("Opacity")
        .accessibilityValue("\(Int(viewModel.selectedOpacity * 100)) percent")
        .toolbarGroupChrome()
        .toolbarCursor(.pointingHand)
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

    func toolbarCursor(_ cursor: EditorToolbarCursorKind) -> some View {
        overlay {
            EditorToolbarCursorRegion(cursor: cursor.nsCursor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum EditorToolbarCursorKind: Equatable {
    case arrow
    case pointingHand
    case iBeam

    var nsCursor: NSCursor {
        switch self {
        case .arrow:
            .arrow
        case .pointingHand:
            .pointingHand
        case .iBeam:
            .iBeam
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

private struct EditorToolbarCursorShield: NSViewRepresentable {
    func makeNSView(context: Context) -> EditorToolbarCursorShieldNSView {
        EditorToolbarCursorShieldNSView()
    }

    func updateNSView(_ nsView: EditorToolbarCursorShieldNSView, context: Context) {}
}

private final class EditorToolbarCursorShieldNSView: NSView {
    private var localMouseMonitor: Any?
    private var trackingArea: NSTrackingArea?

    deinit {
        removeLocalMouseMonitor()
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        removeLocalMouseMonitor()

        guard window != nil else {
            return
        }

        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseMoved,
                .leftMouseDown,
                .leftMouseDragged,
                .leftMouseUp,
                .rightMouseDown,
                .rightMouseDragged,
                .rightMouseUp,
                .otherMouseDown,
                .otherMouseDragged,
                .otherMouseUp
            ]
        ) { [weak self] event in
            self?.updateToolbarCursor(for: event)
            return event
        }
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updateToolbarCursor(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateToolbarCursor(for: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateToolbarCursor(for: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    private func updateToolbarCursor(for event: NSEvent) {
        guard let window,
              event.window === window
        else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else {
            return
        }

        setCursor(cursorForToolbar(atWindowPoint: event.locationInWindow))
        scheduleToolbarCursorUpdateAfterEventDispatch(for: event.window)
    }

    private func cursorForToolbar(atWindowPoint windowPoint: CGPoint) -> NSCursor {
        // Crop/canvas code uses crosshair, but the toolbar is its own cursor zone:
        // only arrow, pointing-hand, and text insertion cursors are valid here.
        if let cursorRegion = cursorRegion(atWindowPoint: windowPoint) {
            return sanitizedToolbarCursor(cursorRegion.cursor)
        }

        if let appKitCursor = cursorForNativeControl(atWindowPoint: windowPoint) {
            return sanitizedToolbarCursor(appKitCursor)
        }

        return .arrow
    }

    private func scheduleToolbarCursorUpdateAfterEventDispatch(for eventWindow: NSWindow?) {
        DispatchQueue.main.async { [weak self, weak eventWindow] in
            guard let self,
                  let eventWindow,
                  eventWindow === self.window
            else {
                return
            }

            let currentWindowPoint = eventWindow.mouseLocationOutsideOfEventStream
            let currentPoint = self.convert(currentWindowPoint, from: nil)
            guard self.bounds.contains(currentPoint) else {
                return
            }

            self.setCursor(self.cursorForToolbar(atWindowPoint: currentWindowPoint))
        }
    }

    private func cursorRegion(atWindowPoint windowPoint: CGPoint) -> EditorToolbarCursorRegionNSView? {
        guard let contentView = window?.contentView else {
            return nil
        }

        return cursorRegion(atWindowPoint: windowPoint, in: contentView)
    }

    private func cursorRegion(
        atWindowPoint windowPoint: CGPoint,
        in view: NSView
    ) -> EditorToolbarCursorRegionNSView? {
        for subview in view.subviews.reversed() {
            if let region = cursorRegion(atWindowPoint: windowPoint, in: subview) {
                return region
            }
        }

        guard let region = view as? EditorToolbarCursorRegionNSView,
              !region.isHidden,
              region.alphaValue > 0,
              region.window === window
        else {
            return nil
        }

        let point = region.convert(windowPoint, from: nil)
        return region.bounds.contains(point) ? region : nil
    }

    private func cursorForNativeControl(atWindowPoint windowPoint: CGPoint) -> NSCursor? {
        guard let contentView = window?.contentView else {
            return nil
        }

        let contentPoint = contentView.convert(windowPoint, from: nil)
        guard let hitView = contentView.hitTest(contentPoint) else {
            return nil
        }

        if hitView.hasSuperview(ofType: NSTextField.self) ||
            hitView.hasSuperview(ofType: NSTextView.self) {
            return .iBeam
        }

        if hitView.hasSuperview(ofType: NSButton.self) ||
            hitView.hasClassName(containing: "Button") ||
            hitView.hasClassName(containing: "Menu") ||
            hitView.hasClassName(containing: "PopUp") {
            return .pointingHand
        }

        return nil
    }

    private func setCursor(_ cursor: NSCursor) {
        sanitizedToolbarCursor(cursor).set()
    }

    @discardableResult
    static func applyToolbarCursorIfNeeded(
        in window: NSWindow?,
        at windowPoint: CGPoint
    ) -> Bool {
        guard let window,
              let contentView = window.contentView,
              let shield = toolbarShield(
                atWindowPoint: windowPoint,
                in: contentView,
                window: window
              )
        else {
            return false
        }

        shield.setCursor(shield.cursorForToolbar(atWindowPoint: windowPoint))
        return true
    }

    private static func toolbarShield(
        atWindowPoint windowPoint: CGPoint,
        in view: NSView,
        window: NSWindow
    ) -> EditorToolbarCursorShieldNSView? {
        for subview in view.subviews.reversed() {
            if let shield = toolbarShield(atWindowPoint: windowPoint, in: subview, window: window) {
                return shield
            }
        }

        guard let shield = view as? EditorToolbarCursorShieldNSView,
              shield.window === window,
              !shield.isHidden,
              shield.alphaValue > 0
        else {
            return nil
        }

        let point = shield.convert(windowPoint, from: nil)
        return shield.bounds.contains(point) ? shield : nil
    }

    private func sanitizedToolbarCursor(_ cursor: NSCursor) -> NSCursor {
        if cursor === NSCursor.pointingHand {
            return .pointingHand
        }

        if cursor === NSCursor.iBeam {
            return .iBeam
        }

        return .arrow
    }

    private func removeLocalMouseMonitor() {
        guard let localMouseMonitor else {
            return
        }

        NSEvent.removeMonitor(localMouseMonitor)
        self.localMouseMonitor = nil
    }
}

private struct EditorToolbarCursorRegion: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> EditorToolbarCursorRegionNSView {
        EditorToolbarCursorRegionNSView(cursor: cursor)
    }

    func updateNSView(_ nsView: EditorToolbarCursorRegionNSView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class EditorToolbarCursorRegionNSView: NSView {
    var cursor: NSCursor {
        didSet {}
    }

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private func cropFillSwatchImage(color: NSColor, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let circleRect = rect.insetBy(dx: 1.5, dy: 1.5)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    image.isTemplate = false

    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    rect.fill()

    if color.alphaComponent <= 0.01 {
        NSGraphicsContext.saveGraphicsState()
        circlePath.addClip()
        let tileSize = max(3, size / 4)
        let columns = Int(ceil(size / tileSize))
        let rows = Int(ceil(size / tileSize))

        for row in 0..<rows {
            for column in 0..<columns {
                let isLightTile = (row + column).isMultiple(of: 2)
                let tileRect = CGRect(
                    x: CGFloat(column) * tileSize,
                    y: CGFloat(row) * tileSize,
                    width: tileSize,
                    height: tileSize
                )
                (isLightTile ? NSColor.textBackgroundColor : NSColor.separatorColor.withAlphaComponent(0.72)).setFill()
                tileRect.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    } else {
        color.setFill()
        circlePath.fill()
    }

    NSColor.separatorColor.withAlphaComponent(0.88).setStroke()
    circlePath.lineWidth = 1
    circlePath.stroke()
    image.unlockFocus()

    return image
}

private struct EditorCanvasView: NSViewRepresentable {
    let viewModel: EditorViewModel
    let image: NSImage
    let annotationObjects: [AnnotationObject]
    let draftAnnotationObject: AnnotationObject?
    let draftCropRect: CGRect?
    let isCropGridVisible: Bool
    let selectedAnnotationID: UUID?
    let activeTool: EditorTool?

    func makeNSView(context: Context) -> EditorCanvasNSView {
        let view = EditorCanvasNSView()
        view.configure(
            viewModel: viewModel,
            image: image,
            annotationObjects: annotationObjects,
            draftAnnotationObject: draftAnnotationObject,
            draftCropRect: draftCropRect,
            isCropGridVisible: isCropGridVisible,
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
            draftCropRect: draftCropRect,
            isCropGridVisible: isCropGridVisible,
            selectedAnnotationID: selectedAnnotationID,
            activeTool: activeTool
        )
    }
}

private final class EditorCanvasNSView: NSView, NSTextViewDelegate {
    private let imageContainerLayer = CALayer()
    private let imageLayer = CALayer()
    private let annotationContainerLayer = CALayer()
    private let cropOverlayLayer = CAShapeLayer()
    private let cropActionBar = NSVisualEffectView()
    private let cropCancelButton = CropActionButton(title: "Cancel", target: nil, action: nil)
    private let cropApplyButton = CropActionButton(title: "Crop", target: nil, action: nil)
    private let annotationLayerRenderer = AnnotationLayerRenderer()
    private static let northWestSouthEastResizeCursor = makeDiagonalResizeCursor(kind: .northWestSouthEast)
    private static let northEastSouthWestResizeCursor = makeDiagonalResizeCursor(kind: .northEastSouthWest)

    private weak var viewModel: EditorViewModel?
    private var currentImage: NSImage?
    private var currentCGImage: CGImage?
    private var annotationObjects: [AnnotationObject] = []
    private var draftAnnotationObject: AnnotationObject?
    private var draftCropRect: CGRect?
    private var isCropGridVisible = false
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
        setupCropActionBar()
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
        layoutCropActionBar()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)

        if cropActionButtonContains(viewPoint) {
            NSCursor.pointingHand.set()
            return
        }

        if activeTool == .crop {
            setCanvasCursor(
                cursorForCropFrame(at: cropPoint(from: viewPoint)),
                atWindowPoint: event.locationInWindow
            )
        } else {
            setCanvasCursor(
                cursor(for: imagePoint(from: viewPoint, clamped: false)),
                atWindowPoint: event.locationInWindow
            )
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        if activeTextView != nil {
            finishActiveTextEditing()
        }

        if activeTool == .crop {
            guard let point = cropPoint(from: event),
                  let viewModel
            else {
                viewModel?.deselectAnnotation()
                renderAnnotationLayers()
                return
            }

            viewModel.beginCropFrameInteraction(
                at: point,
                hitResult: cropFrameHitResult(at: point)
            )
            refreshFromViewModel()
            return
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
        let eventPoint = activeTool == .crop ? cropPoint(from: event) : imagePoint(from: event, clamped: true)

        guard let point = eventPoint,
              let viewModel
        else {
            return
        }

        if activeTool == .crop {
            viewModel.updateCanvasInteraction(
                to: point,
                constrainingCropToOriginalRatio: event.modifierFlags.contains(.shift)
            )
        } else {
            viewModel.updateCanvasInteraction(to: point)
        }
        refreshFromViewModel()
    }

    override func mouseUp(with event: NSEvent) {
        guard let viewModel else {
            return
        }

        let eventPoint = activeTool == .crop ? cropPoint(from: event) : imagePoint(from: event, clamped: true)

        if let point = eventPoint {
            if activeTool == .crop {
                viewModel.updateCanvasInteraction(
                    to: point,
                    constrainingCropToOriginalRatio: event.modifierFlags.contains(.shift)
                )
            } else {
                viewModel.updateCanvasInteraction(to: point)
            }
        }

        viewModel.endCanvasInteraction()
        refreshFromViewModel()
    }

    override func keyDown(with event: NSEvent) {
        guard let viewModel else {
            super.keyDown(with: event)
            return
        }

        if activeTool == .crop {
            switch event.keyCode {
            case 36, 76:
                viewModel.applyCurrentCropFrame()
                refreshFromViewModel()
                return
            case 53:
                viewModel.cancelCropMode()
                refreshFromViewModel()
                return
            default:
                break
            }
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
                case "c":
                    viewModel.perform(.copy)
                    return
                case "s":
                    viewModel.perform(.save)
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
        draftCropRect: CGRect?,
        isCropGridVisible: Bool,
        selectedAnnotationID: UUID?,
        activeTool: EditorTool?
    ) {
        self.viewModel = viewModel
        if currentImage !== image {
            currentImage = image
            currentCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            imageLayer.contents = currentCGImage
        }
        self.annotationObjects = annotationObjects
        self.draftAnnotationObject = draftAnnotationObject
        self.draftCropRect = draftCropRect
        self.isCropGridVisible = isCropGridVisible
        self.selectedAnnotationID = selectedAnnotationID
        self.activeTool = activeTool
        removeTextEditorIfAnnotationDisappeared()
        renderAnnotationLayers()
        renderCropOverlay()
        layoutCropActionBar()
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

        cropOverlayLayer.name = "CropOverlayLayer"
        cropOverlayLayer.fillColor = NSColor.black.withAlphaComponent(0.38).cgColor
        cropOverlayLayer.strokeColor = NSColor.clear.cgColor
        cropOverlayLayer.fillRule = .evenOdd
        cropOverlayLayer.allowsEdgeAntialiasing = true
        cropOverlayLayer.isHidden = true

        layer?.addSublayer(imageContainerLayer)
        imageContainerLayer.addSublayer(imageLayer)
        imageContainerLayer.addSublayer(annotationContainerLayer)
        imageContainerLayer.addSublayer(cropOverlayLayer)
        updateLayerScale()
    }

    private func setupCropActionBar() {
        cropActionBar.blendingMode = .withinWindow
        cropActionBar.material = .hudWindow
        cropActionBar.state = .active
        cropActionBar.wantsLayer = true
        cropActionBar.layer?.cornerRadius = 9
        cropActionBar.layer?.masksToBounds = true
        cropActionBar.isHidden = true

        configureCropActionButton(cropCancelButton, title: "Cancel", action: #selector(cancelCropFromActionBar))
        configureCropActionButton(cropApplyButton, title: "Crop", action: #selector(applyCropFromActionBar))

        cropActionBar.addSubview(cropCancelButton)
        cropActionBar.addSubview(cropApplyButton)
        addSubview(cropActionBar)
    }

    private func configureCropActionButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
    }

    @objc private func cancelCropFromActionBar() {
        viewModel?.cancelCropMode()
        refreshFromViewModel()
    }

    @objc private func applyCropFromActionBar() {
        viewModel?.applyCurrentCropFrame()
        refreshFromViewModel()
    }

    private func layoutCanvasLayers() {
        guard let currentImage else {
            imageContainerLayer.frame = .zero
            imageFrameInView = .zero
            imageDisplayScale = 1
            cropOverlayLayer.isHidden = true
            cropActionBar.isHidden = true
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
        cropOverlayLayer.frame = imageContainerLayer.bounds
        imageContainerLayer.shadowPath = CGPath(
            roundedRect: imageContainerLayer.bounds,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        CATransaction.commit()

        renderAnnotationLayers()
        renderCropOverlay()
    }

    private func refreshFromViewModel() {
        guard let viewModel else {
            return
        }

        annotationObjects = viewModel.annotationObjects
        draftAnnotationObject = viewModel.draftAnnotationObject
        draftCropRect = viewModel.draftCropRect
        isCropGridVisible = viewModel.isCropGridVisible
        selectedAnnotationID = viewModel.selectedAnnotationID
        activeTool = viewModel.activeTool
        renderAnnotationLayers()
        renderCropOverlay()
        updateActiveTextEditorFrame()
        updateCursorForCurrentMouseLocation()
    }

    private func renderAnnotationLayers() {
        let visibleAnnotations = annotationObjects.filter { annotation in
            annotation.id != activeTextAnnotationID
        }

        annotationLayerRenderer.render(
            annotations: visibleAnnotations,
            draftAnnotation: draftAnnotationObject,
            selectedAnnotationID: selectedAnnotationID,
            sourceImage: currentCGImage,
            in: annotationContainerLayer,
            contentsScale: currentLayerScale,
            selectionHandleSize: max(8, 8 / imageDisplayScale)
        )
    }

    private func renderCropOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        guard let draftCropRect,
              draftCropRect.width >= 1,
              draftCropRect.height >= 1
        else {
            cropOverlayLayer.path = nil
            cropOverlayLayer.sublayers = nil
            cropOverlayLayer.isHidden = true
            cropActionBar.isHidden = true
            CATransaction.commit()
            return
        }

        let cropRect = draftCropRect
            .standardizedForEditor
            .intersection(imageContainerLayer.bounds)

        cropOverlayLayer.isHidden = false
        cropOverlayLayer.frame = imageContainerLayer.bounds
        cropOverlayLayer.path = cropDimmingPath(for: cropRect, in: imageContainerLayer.bounds)
        cropOverlayLayer.contentsScale = currentLayerScale
        cropOverlayLayer.sublayers = cropFrameDecorationLayers(for: cropRect)
        CATransaction.commit()
        layoutCropActionBar()
    }

    private func cropDimmingPath(for cropRect: CGRect, in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(cropRect)
        return path
    }

    private func cropFrameDecorationLayers(for cropRect: CGRect) -> [CALayer] {
        var layers: [CALayer] = [cropBorderLayer(for: cropRect)]

        if isCropGridVisible {
            layers.append(cropGridLayer(for: cropRect))
        }

        layers.append(contentsOf: cropHandleLayers(for: cropRect))
        return layers
    }

    private func layoutCropActionBar() {
        guard activeTool == .crop,
              let draftCropRect,
              draftCropRect.width >= 1,
              draftCropRect.height >= 1,
              imageFrameInView.width > 0,
              imageFrameInView.height > 0
        else {
            cropActionBar.isHidden = true
            return
        }

        let cropViewRect = viewRect(forImageRect: draftCropRect.standardizedForEditor)
        let barSize = CGSize(width: 130, height: 34)
        let gap: CGFloat = 10
        let inset: CGFloat = 10
        let preferredY = cropViewRect.maxY + gap
        let fallbackY = cropViewRect.minY - barSize.height - gap
        let y = preferredY + barSize.height <= bounds.maxY - inset
            ? preferredY
            : max(bounds.minY + inset, fallbackY)
        let unclampedX = cropViewRect.midX - barSize.width / 2
        let x = min(max(unclampedX, bounds.minX + inset), bounds.maxX - barSize.width - inset)

        cropActionBar.frame = CGRect(origin: CGPoint(x: x, y: y), size: barSize)
        cropCancelButton.frame = CGRect(x: 7, y: 5, width: 60, height: 24)
        cropApplyButton.frame = CGRect(x: 70, y: 5, width: 53, height: 24)
        cropActionBar.isHidden = false
    }

    private func cropActionButtonContains(_ point: CGPoint) -> Bool {
        guard !cropActionBar.isHidden else {
            return false
        }

        let pointInActionBar = cropActionBar.convert(point, from: self)
        return cropCancelButton.frame.contains(pointInActionBar) ||
            cropApplyButton.frame.contains(pointInActionBar)
    }

    private func cropBorderLayer(for rect: CGRect) -> CALayer {
        let layer = CAShapeLayer()
        layer.frame = imageContainerLayer.bounds
        layer.path = cropFramePath(for: rect)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = NSColor.white.cgColor
        layer.lineWidth = max(1.5, 1.5 / imageDisplayScale)
        layer.lineJoin = .round
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 4 / max(imageDisplayScale, 0.1)
        layer.shadowOffset = CGSize(width: 0, height: 1 / max(imageDisplayScale, 0.1))
        layer.contentsScale = currentLayerScale
        return layer
    }

    private func cropGridLayer(for rect: CGRect) -> CALayer {
        let layer = CAShapeLayer()
        layer.frame = imageContainerLayer.bounds
        layer.path = cropGridPath(for: rect)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = NSColor.white.withAlphaComponent(0.42).cgColor
        layer.lineWidth = max(0.8, 0.8 / imageDisplayScale)
        layer.contentsScale = currentLayerScale
        return layer
    }

    private func cropFramePath(for rect: CGRect) -> CGPath {
        CGPath(rect: rect, transform: nil)
    }

    private func cropGridPath(for rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let firstVertical = rect.minX + rect.width / 3
        let secondVertical = rect.minX + rect.width * 2 / 3
        let firstHorizontal = rect.minY + rect.height / 3
        let secondHorizontal = rect.minY + rect.height * 2 / 3

        path.move(to: CGPoint(x: firstVertical, y: rect.minY))
        path.addLine(to: CGPoint(x: firstVertical, y: rect.maxY))
        path.move(to: CGPoint(x: secondVertical, y: rect.minY))
        path.addLine(to: CGPoint(x: secondVertical, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: firstHorizontal))
        path.addLine(to: CGPoint(x: rect.maxX, y: firstHorizontal))
        path.move(to: CGPoint(x: rect.minX, y: secondHorizontal))
        path.addLine(to: CGPoint(x: rect.maxX, y: secondHorizontal))

        return path
    }

    private func cropHandleLayers(for cropRect: CGRect) -> [CALayer] {
        EditorCropFrameHandle.allCases.map { handle in
            let displayRect = cropHandleVisualRect(for: handle, cropRect: cropRect)
            let layer = CAShapeLayer()
            layer.frame = imageContainerLayer.bounds
            layer.path = CGPath(
                roundedRect: displayRect,
                cornerWidth: min(displayRect.width, displayRect.height) / 2,
                cornerHeight: min(displayRect.width, displayRect.height) / 2,
                transform: nil
            )
            layer.fillColor = NSColor.white.cgColor
            layer.strokeColor = NSColor.black.withAlphaComponent(0.28).cgColor
            layer.lineWidth = max(0.8, 0.8 / imageDisplayScale)
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.25
            layer.shadowRadius = 3 / max(imageDisplayScale, 0.1)
            layer.shadowOffset = CGSize(width: 0, height: 1 / max(imageDisplayScale, 0.1))
            layer.contentsScale = currentLayerScale
            return layer
        }
    }

    private func updateLayerScale() {
        layer?.contentsScale = currentLayerScale
        imageContainerLayer.contentsScale = currentLayerScale
        imageLayer.contentsScale = currentLayerScale
        annotationContainerLayer.contentsScale = currentLayerScale
        cropOverlayLayer.contentsScale = currentLayerScale
    }

    private var currentLayerScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var hitTestTolerance: CGFloat {
        max(6, 10 / imageDisplayScale)
    }

    private var cropHandleSize: CGFloat {
        max(14, 16 / imageDisplayScale)
    }

    private func cropFrameHitResult(at point: CGPoint) -> EditorCropFrameHitResult {
        guard let cropRect = draftCropRect?.standardizedForEditor else {
            return .empty
        }

        for (handle, rect) in cropFrameHandles(for: cropRect) where rect.contains(point) {
            return .resize(handle)
        }

        if cropRect.insetBy(dx: -hitTestTolerance, dy: -hitTestTolerance).contains(point) {
            return .move
        }

        return .empty
    }

    private func cropFrameHandles(for cropRect: CGRect) -> [EditorCropFrameHandle: CGRect] {
        [
            .topLeft: handleRect(centeredAt: CGPoint(x: cropRect.minX, y: cropRect.minY), size: cropHandleSize),
            .top: handleRect(centeredAt: CGPoint(x: cropRect.midX, y: cropRect.minY), size: cropHandleSize),
            .topRight: handleRect(centeredAt: CGPoint(x: cropRect.maxX, y: cropRect.minY), size: cropHandleSize),
            .right: handleRect(centeredAt: CGPoint(x: cropRect.maxX, y: cropRect.midY), size: cropHandleSize),
            .bottomRight: handleRect(centeredAt: CGPoint(x: cropRect.maxX, y: cropRect.maxY), size: cropHandleSize),
            .bottom: handleRect(centeredAt: CGPoint(x: cropRect.midX, y: cropRect.maxY), size: cropHandleSize),
            .bottomLeft: handleRect(centeredAt: CGPoint(x: cropRect.minX, y: cropRect.maxY), size: cropHandleSize),
            .left: handleRect(centeredAt: CGPoint(x: cropRect.minX, y: cropRect.midY), size: cropHandleSize)
        ]
    }

    private func cropHandleVisualRect(for handle: EditorCropFrameHandle, cropRect: CGRect) -> CGRect {
        let shortSide = max(5, 6 / imageDisplayScale)
        let longSide = max(18, 24 / imageDisplayScale)
        let cornerSide = max(8, 10 / imageDisplayScale)

        switch handle {
        case .topLeft:
            return handleRect(centeredAt: CGPoint(x: cropRect.minX, y: cropRect.minY), size: cornerSide)
        case .top:
            return CGRect(
                x: cropRect.midX - longSide / 2,
                y: cropRect.minY - shortSide / 2,
                width: longSide,
                height: shortSide
            )
        case .topRight:
            return handleRect(centeredAt: CGPoint(x: cropRect.maxX, y: cropRect.minY), size: cornerSide)
        case .right:
            return CGRect(
                x: cropRect.maxX - shortSide / 2,
                y: cropRect.midY - longSide / 2,
                width: shortSide,
                height: longSide
            )
        case .bottomRight:
            return handleRect(centeredAt: CGPoint(x: cropRect.maxX, y: cropRect.maxY), size: cornerSide)
        case .bottom:
            return CGRect(
                x: cropRect.midX - longSide / 2,
                y: cropRect.maxY - shortSide / 2,
                width: longSide,
                height: shortSide
            )
        case .bottomLeft:
            return handleRect(centeredAt: CGPoint(x: cropRect.minX, y: cropRect.maxY), size: cornerSide)
        case .left:
            return CGRect(
                x: cropRect.minX - shortSide / 2,
                y: cropRect.midY - longSide / 2,
                width: shortSide,
                height: longSide
            )
        }
    }

    private func cursorForCropFrame(at point: CGPoint?) -> NSCursor {
        guard let point else {
            return .arrow
        }

        switch cropFrameHitResult(at: point) {
        case let .resize(handle):
            return cursor(forCropHandle: handle)
        case .move:
            return .openHand
        case .empty:
            return .crosshair
        }
    }

    private func cursor(forCropHandle handle: EditorCropFrameHandle) -> NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(position: frameResizePosition(for: handle), directions: .all)
        }

        switch handle {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return Self.northWestSouthEastResizeCursor
        case .topRight, .bottomLeft:
            return Self.northEastSouthWestResizeCursor
        }
    }

    @available(macOS 15.0, *)
    private func frameResizePosition(for handle: EditorCropFrameHandle) -> NSCursor.FrameResizePosition {
        switch handle {
        case .topLeft:
            return .topLeft
        case .top:
            return .top
        case .topRight:
            return .topRight
        case .right:
            return .right
        case .bottomRight:
            return .bottomRight
        case .bottom:
            return .bottom
        case .bottomLeft:
            return .bottomLeft
        case .left:
            return .left
        }
    }

    private func imagePoint(from event: NSEvent, clamped: Bool) -> CGPoint? {
        imagePoint(from: convert(event.locationInWindow, from: nil), clamped: clamped)
    }

    private func cropPoint(from event: NSEvent) -> CGPoint? {
        cropPoint(from: convert(event.locationInWindow, from: nil))
    }

    private func cropPoint(from viewPoint: CGPoint) -> CGPoint? {
        guard imageFrameInView.width > 0,
              imageFrameInView.height > 0,
              imageDisplayScale > 0
        else {
            return nil
        }

        return CGPoint(
            x: (viewPoint.x - imageFrameInView.minX) / imageDisplayScale,
            y: (viewPoint.y - imageFrameInView.minY) / imageDisplayScale
        )
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

    private func updateCursorForCurrentMouseLocation() {
        guard let window else {
            NSCursor.arrow.set()
            return
        }

        let windowPoint = window.mouseLocationOutsideOfEventStream
        let viewPoint = convert(windowPoint, from: nil)
        guard bounds.contains(viewPoint) else {
            if EditorToolbarCursorShieldNSView.applyToolbarCursorIfNeeded(in: window, at: windowPoint) {
                return
            }

            NSCursor.arrow.set()
            return
        }

        if cropActionButtonContains(viewPoint) {
            NSCursor.pointingHand.set()
            return
        }

        if activeTool == .crop {
            setCanvasCursor(cursorForCropFrame(at: cropPoint(from: viewPoint)), atWindowPoint: windowPoint)
        } else {
            setCanvasCursor(cursor(for: imagePoint(from: viewPoint, clamped: false)), atWindowPoint: windowPoint)
        }
    }

    private func setCanvasCursor(_ cursor: NSCursor, atWindowPoint windowPoint: CGPoint) {
        if EditorToolbarCursorShieldNSView.applyToolbarCursorIfNeeded(in: window, at: windowPoint) {
            return
        }

        cursor.set()
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
        activeTool == .arrow ||
            activeTool == .rectangle ||
            activeTool == .oval ||
            activeTool == .highlight ||
            activeTool == .blurPixelate ||
            activeTool == .crop
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

private final class CropActionButton: NSButton {
    private var cursorTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private enum CropDiagonalResizeCursorKind {
    case northWestSouthEast
    case northEastSouthWest

    var endpoints: (CGPoint, CGPoint) {
        switch self {
        case .northWestSouthEast:
            return (CGPoint(x: 5, y: 19), CGPoint(x: 19, y: 5))
        case .northEastSouthWest:
            return (CGPoint(x: 19, y: 19), CGPoint(x: 5, y: 5))
        }
    }
}

private func makeDiagonalResizeCursor(kind: CropDiagonalResizeCursorKind) -> NSCursor {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    let (startPoint, endPoint) = kind.endpoints

    image.lockFocus()
    drawDiagonalResizeCursorStroke(from: startPoint, to: endPoint, color: .white, lineWidth: 4.8, headLength: 6.4, headWidth: 5.4)
    drawDiagonalResizeCursorStroke(from: startPoint, to: endPoint, color: .black, lineWidth: 2.4, headLength: 5.3, headWidth: 3.9)
    image.unlockFocus()

    return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
}

private func drawDiagonalResizeCursorStroke(
    from startPoint: CGPoint,
    to endPoint: CGPoint,
    color: NSColor,
    lineWidth: CGFloat,
    headLength: CGFloat,
    headWidth: CGFloat
) {
    color.setStroke()
    color.setFill()

    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.move(to: startPoint)
    path.line(to: endPoint)
    path.stroke()

    drawCursorArrowhead(
        tip: endPoint,
        toward: startPoint,
        length: headLength,
        width: headWidth
    )
    drawCursorArrowhead(
        tip: startPoint,
        toward: endPoint,
        length: headLength,
        width: headWidth
    )
}

private func drawCursorArrowhead(
    tip: CGPoint,
    toward oppositePoint: CGPoint,
    length: CGFloat,
    width: CGFloat
) {
    let dx = tip.x - oppositePoint.x
    let dy = tip.y - oppositePoint.y
    let magnitude = max(sqrt(dx * dx + dy * dy), 0.001)
    let unit = CGPoint(x: dx / magnitude, y: dy / magnitude)
    let perpendicular = CGPoint(x: -unit.y, y: unit.x)
    let base = CGPoint(x: tip.x - unit.x * length, y: tip.y - unit.y * length)

    let arrowhead = NSBezierPath()
    arrowhead.move(to: tip)
    arrowhead.line(to: CGPoint(x: base.x + perpendicular.x * width, y: base.y + perpendicular.y * width))
    arrowhead.line(to: CGPoint(x: base.x - perpendicular.x * width, y: base.y - perpendicular.y * width))
    arrowhead.close()
    arrowhead.fill()
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

private extension NSView {
    func hasSuperview<T: NSView>(ofType type: T.Type) -> Bool {
        var view: NSView? = self

        while let currentView = view {
            if currentView is T {
                return true
            }

            view = currentView.superview
        }

        return false
    }

    func hasClassName(containing fragment: String) -> Bool {
        var view: NSView? = self

        while let currentView = view {
            if NSStringFromClass(type(of: currentView)).localizedCaseInsensitiveContains(fragment) {
                return true
            }

            view = currentView.superview
        }

        return false
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

private func handleRect(centeredAt point: CGPoint, size: CGFloat) -> CGRect {
    CGRect(
        x: point.x - size / 2,
        y: point.y - size / 2,
        width: size,
        height: size
    )
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
        case .highlight:
            keyboardShortcut("h", modifiers: [])
        case .blurPixelate:
            keyboardShortcut("b", modifiers: [])
        case .crop:
            keyboardShortcut("x", modifiers: [])
        case .undo:
            keyboardShortcut("z", modifiers: [.command])
        case .redo:
            keyboardShortcut("z", modifiers: [.command, .shift])
        case .copy:
            keyboardShortcut("c", modifiers: [.command])
        case .save:
            keyboardShortcut("s", modifiers: [.command])
        }
    }
}
