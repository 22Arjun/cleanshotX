//
//  EditorViewModel.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Combine
import Foundation
import Vision

enum EditorTool: String, CaseIterable, Identifiable {
    case drawing
    case arrow
    case line
    case numbering
    case rectangle
    case filledRectangle
    case oval
    case text
    case textHighlight
    case smartTextHighlight
    case highlight
    case blurPixelate
    case crop

    var id: String {
        rawValue
    }
}

struct EditorStrokeColorOption: Identifiable {
    let id: String
    let name: String
    let color: NSColor
}

struct EditorTextBackgroundColorOption: Identifiable {
    let id: String
    let name: String
    let color: NSColor?
}

struct EditorTextFormattingCommand: Equatable {
    enum Kind: Equatable {
        case foreground
        case background
        case baseFont
    }

    let id = UUID()
    let kind: Kind
    let color: NSColor?
}

struct EditorCropRatioOption: Identifiable, Equatable {
    let id: String
    let title: String
    let ratio: CGFloat?
    let usesOriginalImageRatio: Bool
    let usesCustomRatio: Bool

    init(
        id: String,
        title: String,
        ratio: CGFloat?,
        usesOriginalImageRatio: Bool = false,
        usesCustomRatio: Bool = false
    ) {
        self.id = id
        self.title = title
        self.ratio = ratio
        self.usesOriginalImageRatio = usesOriginalImageRatio
        self.usesCustomRatio = usesCustomRatio
    }
}

struct EditorCropFillColorOption: Identifiable {
    let id: String
    let name: String
    let color: NSColor
}

enum EditorCropFrameHitResult: Equatable {
    case resize(EditorCropFrameHandle)
    case move
    case empty
}

enum EditorCropFrameHandle: Equatable, CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum EditorToolbarAction: String, CaseIterable, Identifiable {
    case drawing
    case arrow
    case line
    case numbering
    case rectangle
    case filledRectangle
    case oval
    case text
    case textHighlight
    case smartTextHighlight
    case highlight
    case blurPixelate
    case crop
    case undo
    case redo
    case copy
    case save

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .drawing:
            "Drawing"
        case .arrow:
            "Arrow"
        case .line:
            "Line"
        case .numbering:
            "Numbering"
        case .rectangle:
            "Rectangle"
        case .filledRectangle:
            "Filled Rectangle"
        case .oval:
            "Oval"
        case .text:
            "Text"
        case .textHighlight:
            "Text Highlight"
        case .smartTextHighlight:
            "Smart Highlighter"
        case .highlight:
            "Spotlight Highlight"
        case .blurPixelate:
            "Blur/Pixelate"
        case .crop:
            "Crop/Resize Canvas"
        case .undo:
            "Undo"
        case .redo:
            "Redo"
        case .copy:
            "Copy"
        case .save:
            "Save"
        }
    }

    var systemImageName: String {
        switch self {
        case .drawing:
            "pencil.tip"
        case .arrow:
            "arrow.up.right"
        case .line:
            "line.diagonal"
        case .numbering:
            "number.circle.fill"
        case .rectangle:
            "rectangle"
        case .filledRectangle:
            "rectangle.fill"
        case .oval:
            "oval"
        case .text:
            "textformat"
        case .textHighlight:
            "highlighter"
        case .smartTextHighlight:
            "sparkles"
        case .highlight:
            "viewfinder"
        case .blurPixelate:
            "square.grid.3x3.fill"
        case .crop:
            "crop"
        case .undo:
            "arrow.uturn.backward"
        case .redo:
            "arrow.uturn.forward"
        case .copy:
            "doc.on.doc"
        case .save:
            "square.and.arrow.down"
        }
    }

    var shortcutHint: String {
        switch self {
        case .drawing:
            "D"
        case .arrow:
            "A"
        case .line:
            "L"
        case .numbering:
            "N"
        case .rectangle:
            "R"
        case .filledRectangle:
            "F"
        case .oval:
            "O"
        case .text:
            "T"
        case .textHighlight:
            "M"
        case .smartTextHighlight:
            "S"
        case .highlight:
            "H"
        case .blurPixelate:
            "B"
        case .crop:
            "X"
        case .undo:
            "⌘Z"
        case .redo:
            "⇧⌘Z"
        case .copy:
            "⌘C"
        case .save:
            "⌘S"
        }
    }

    var tool: EditorTool? {
        switch self {
        case .drawing:
            .drawing
        case .arrow:
            .arrow
        case .line:
            .line
        case .numbering:
            .numbering
        case .rectangle:
            .rectangle
        case .filledRectangle:
            .filledRectangle
        case .oval:
            .oval
        case .text:
            .text
        case .textHighlight:
            .textHighlight
        case .smartTextHighlight:
            .smartTextHighlight
        case .highlight:
            .highlight
        case .blurPixelate:
            .blurPixelate
        case .crop:
            .crop
        case .undo, .redo, .copy, .save:
            nil
        }
    }

    static let drawingTools: [EditorToolbarAction] = [
        .drawing,
        .arrow,
        .line,
        .numbering,
        .rectangle,
        .filledRectangle,
        .oval,
        .text,
        .textHighlight,
        .smartTextHighlight,
        .highlight,
        .blurPixelate,
        .crop
    ]

    static let historyCommands: [EditorToolbarAction] = [
        .undo,
        .redo
    ]

    static let outputCommands: [EditorToolbarAction] = [
        .copy,
        .save
    ]
}

@MainActor
final class EditorViewModel: ObservableObject {
    static let strokeColorOptions: [EditorStrokeColorOption] = [
        EditorStrokeColorOption(id: "red", name: "Red", color: .systemRed),
        EditorStrokeColorOption(id: "pink", name: "Pink", color: .systemPink),
        EditorStrokeColorOption(id: "yellow", name: "Yellow", color: .systemYellow),
        EditorStrokeColorOption(id: "green", name: "Green", color: .systemGreen),
        EditorStrokeColorOption(id: "blue", name: "Blue", color: .systemBlue),
        EditorStrokeColorOption(id: "navy", name: "Navy", color: NSColor(calibratedRed: 0.13, green: 0.28, blue: 0.45, alpha: 1)),
        EditorStrokeColorOption(id: "white", name: "White", color: .white),
        EditorStrokeColorOption(id: "black", name: "Black", color: .black)
    ]
    static let textBackgroundColorOptions: [EditorTextBackgroundColorOption] = [
        EditorTextBackgroundColorOption(id: "clear", name: "None", color: nil),
        EditorTextBackgroundColorOption(id: "pink", name: "Light Pink", color: NSColor.systemPink.withAlphaComponent(0.16)),
        EditorTextBackgroundColorOption(id: "yellow", name: "Soft Yellow", color: NSColor.systemYellow.withAlphaComponent(0.28)),
        EditorTextBackgroundColorOption(id: "green", name: "Soft Green", color: NSColor.systemGreen.withAlphaComponent(0.22)),
        EditorTextBackgroundColorOption(id: "blue", name: "Soft Blue", color: NSColor.systemBlue.withAlphaComponent(0.2)),
        EditorTextBackgroundColorOption(id: "navy", name: "Deep Blue", color: NSColor(calibratedRed: 0.13, green: 0.28, blue: 0.45, alpha: 1)),
        EditorTextBackgroundColorOption(id: "black", name: "Black", color: .black),
        EditorTextBackgroundColorOption(id: "white", name: "White", color: .white)
    ]

    static let strokeWidthOptions: [CGFloat] = [2, 4, 6, 8, 10, 12]
    static let textSizeOptions: [CGFloat] = [16, 24, 32, 44]
    static let cropRatioOptions: [EditorCropRatioOption] = [
        EditorCropRatioOption(id: "custom", title: "Custom Ratio", ratio: nil, usesCustomRatio: true),
        EditorCropRatioOption(id: "freeform", title: "Freeform", ratio: nil),
        EditorCropRatioOption(id: "original", title: "Original Ratio", ratio: nil, usesOriginalImageRatio: true),
        EditorCropRatioOption(id: "square", title: "1 : 1 (Square)", ratio: 1),
        EditorCropRatioOption(id: "fiveFour", title: "5 : 4 (10 : 8)", ratio: 5 / 4),
        EditorCropRatioOption(id: "sevenFive", title: "7 : 5", ratio: 7 / 5),
        EditorCropRatioOption(id: "fourThree", title: "4 : 3", ratio: 4 / 3),
        EditorCropRatioOption(id: "threeTwo", title: "3 : 2 (6 : 4)", ratio: 3 / 2),
        EditorCropRatioOption(id: "sixteenNine", title: "16 : 9", ratio: 16 / 9)
    ]
    static let cropFillColorOptions: [EditorCropFillColorOption] = [
        EditorCropFillColorOption(id: "transparent", name: "Transparent", color: .clear),
        EditorCropFillColorOption(id: "black", name: "Black", color: .black),
        EditorCropFillColorOption(id: "white", name: "White", color: .white),
        EditorCropFillColorOption(id: "red", name: "Red", color: .systemRed),
        EditorCropFillColorOption(id: "orange", name: "Orange", color: .systemOrange),
        EditorCropFillColorOption(id: "yellow", name: "Yellow", color: .systemYellow),
        EditorCropFillColorOption(id: "green", name: "Green", color: .systemGreen),
        EditorCropFillColorOption(id: "blue", name: "Blue", color: .systemBlue),
        EditorCropFillColorOption(id: "purple", name: "Purple", color: .systemPurple),
        EditorCropFillColorOption(id: "gray", name: "Gray", color: .systemGray)
    ]

    let id = UUID()
    let sourceFileURL: URL?

    @Published private(set) var image: NSImage
    @Published private(set) var annotationObjects: [AnnotationObject] = []
    @Published private(set) var activeTool: EditorTool?
    @Published private(set) var selectedAnnotationID: UUID?
    @Published private(set) var draftAnnotationObject: AnnotationObject?
    @Published private(set) var draftCropRect: CGRect?
    @Published private(set) var selectedStrokeColorID = "red"
    @Published private(set) var selectedTextBackgroundColorID = "pink"
    @Published private(set) var selectedStrokeWidth: CGFloat = 4
    @Published private(set) var selectedArrowStyle: AnnotationArrowStyle = .standard
    @Published private(set) var selectedTextSize: CGFloat = 24
    @Published private(set) var selectedTextFontFamily: AnnotationTextFontFamily = .standard
    @Published private(set) var selectedOpacity: CGFloat = 1
    @Published private(set) var selectedPixelateIntensity: CGFloat = 4
    @Published private(set) var selectedImageEffect: AnnotationImageEffect = .pixelate
    @Published private(set) var selectedHighlightIntensity: CGFloat = 0.45
    @Published private(set) var selectedSpotlightShape: AnnotationSpotlightShape = .rectangle
    @Published private(set) var selectedCropRatioID = "freeform"
    @Published private(set) var customCropRatio: CGFloat?
    @Published private(set) var selectedCropFillColorID = "transparent"
    @Published private(set) var isCropGridVisible = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var textFormattingCommand: EditorTextFormattingCommand?

    private let annotationInteractionService: AnnotationInteractionServicing
    private let outputService: EditorOutputServicing
    private let canvasResizeService: EditorCanvasResizing
    private let smartTextRecognitionService = SmartTextRecognitionService()
    private var activeDragSession: EditorDragSession?
    private var textEditingInitialState: EditorHistoryState?
    private var activeTextEditingAnnotationID: UUID?
    private var opacityEditingInitialState: EditorHistoryState?
    private var pixelateIntensityEditingInitialState: EditorHistoryState?
    private var highlightIntensityEditingInitialState: EditorHistoryState?
    private var smartTextWordCache: SmartTextWordCache?
    private var undoStack: [EditorHistoryState] = []
    private var redoStack: [EditorHistoryState] = []
    private var imageRevision = UUID()
    private let historyLimit = 80
    private let minimumCropFrameLength: CGFloat = 16
    private let cropNewFrameDragThreshold: CGFloat = 4

    var selectedStrokeColor: NSColor {
        Self.strokeColorOptions.first { option in
            option.id == selectedStrokeColorID
        }?.color ?? .systemRed
    }

    var selectedTextBackgroundColor: NSColor? {
        Self.textBackgroundColorOptions.first { option in
            option.id == selectedTextBackgroundColorID
        }?.color ?? NSColor.systemPink.withAlphaComponent(0.16)
    }

    var isTextEditingActive: Bool {
        activeTextEditingAnnotationID != nil
    }

    var usesTextControls: Bool {
        activeTool == .text || selectedAnnotation?.kind == .text || isTextEditingActive
    }

    var selectedTextFontFamilyTitle: String {
        selectedTextFontFamily.title
    }

    var isCropModeActive: Bool {
        activeTool == .crop
    }

    var shouldShowArrowStyleMenu: Bool {
        activeTool == .arrow || selectedAnnotation?.kind == .arrow
    }

    var usesBadgeSizeControl: Bool {
        activeTool == .numbering || selectedAnnotation?.kind == .numbering
    }

    var usesMarkerSizeControl: Bool {
        activeTool == .textHighlight ||
            activeTool == .smartTextHighlight ||
            selectedAnnotation?.kind == .textHighlight ||
            selectedAnnotation?.kind == .smartTextHighlight
    }

    var shouldShowHighlightIntensitySlider: Bool {
        activeTool == .highlight || selectedAnnotation?.kind == .highlight
    }

    var shouldShowPixelateIntensitySlider: Bool {
        activeTool == .blurPixelate || selectedAnnotation?.kind == .blurPixelate
    }

    var selectedSpotlightShapeTitle: String {
        selectedSpotlightShape.title
    }

    var selectedImageEffectTitle: String {
        selectedImageEffect.title
    }

    var selectedArrowStyleTitle: String {
        selectedArrowStyle.title
    }

    var selectedCropRatioTitle: String {
        if selectedCropRatioOption.usesCustomRatio,
           let customCropRatio {
            return "Custom \(formattedRatioTitle(for: customCropRatio))"
        }

        return selectedCropRatioOption.title
    }

    var cropFramePixelWidth: Int {
        Int(round((draftCropRect ?? currentCanvasBounds).standardizedForEditor.width))
    }

    var cropFramePixelHeight: Int {
        Int(round((draftCropRect ?? currentCanvasBounds).standardizedForEditor.height))
    }

    var canvasPixelSizeTitle: String {
        "\(cropFramePixelWidth) × \(cropFramePixelHeight) px"
    }

    var selectedCropFillColor: NSColor {
        selectedCropFillColorOption.color
    }

    var selectedCropFillColorName: String {
        selectedCropFillColorOption.name
    }

    private var selectedCropRatioOption: EditorCropRatioOption {
        Self.cropRatioOptions.first { option in
            option.id == selectedCropRatioID
        } ?? Self.defaultCropRatioOption
    }

    private static var defaultCropRatioOption: EditorCropRatioOption {
        cropRatioOptions.first { option in
            option.id == "freeform"
        } ?? cropRatioOptions[0]
    }

    private var selectedCropFillColorOption: EditorCropFillColorOption {
        Self.cropFillColorOptions.first { option in
            option.id == selectedCropFillColorID
        } ?? Self.cropFillColorOptions[0]
    }

    private var selectedAnnotation: AnnotationObject? {
        guard let selectedAnnotationID else {
            return nil
        }

        return annotation(withID: selectedAnnotationID)
    }

    private var currentCanvasBounds: CGRect {
        CGRect(origin: .zero, size: image.editorHistoryCanvasSize)
    }

    init(
        image: NSImage,
        sourceFileURL: URL? = nil,
        annotationInteractionService: AnnotationInteractionServicing? = nil,
        outputService: EditorOutputServicing? = nil,
        canvasResizeService: EditorCanvasResizing? = nil
    ) {
        self.image = image
        self.sourceFileURL = sourceFileURL
        self.annotationInteractionService = annotationInteractionService ?? AnnotationInteractionService()
        self.outputService = outputService ?? EditorOutputService()
        self.canvasResizeService = canvasResizeService ?? EditorCanvasResizeService()
    }

    func perform(_ action: EditorToolbarAction) {
        if action == .crop {
            toggleCropTool()
            return
        }

        if let tool = action.tool {
            selectTool(tool)
            return
        }

        switch action {
        case .undo:
            undo()
        case .redo:
            redo()
        case .copy:
            copy()
        case .save:
            save()
        case .drawing, .arrow, .line, .numbering, .rectangle, .filledRectangle, .oval, .text, .textHighlight, .smartTextHighlight, .highlight, .blurPixelate, .crop:
            break
        }
    }

    func isSelected(_ action: EditorToolbarAction) -> Bool {
        guard let tool = action.tool else {
            return false
        }

        return activeTool == tool
    }

    func isEnabled(_ action: EditorToolbarAction) -> Bool {
        switch action {
        case .undo:
            canUndo
        case .redo:
            canRedo
        case .drawing, .arrow, .line, .numbering, .rectangle, .filledRectangle, .oval, .text, .textHighlight, .smartTextHighlight, .highlight, .blurPixelate, .crop, .copy, .save:
            true
        }
    }

    func setStrokeColor(_ option: EditorStrokeColorOption) {
        let previousState = currentHistoryState()
        selectedStrokeColorID = option.id

        if isTextEditingActive {
            textFormattingCommand = EditorTextFormattingCommand(
                kind: .foreground,
                color: option.color
            )
            return
        }

        if applyActiveStyleToSelectedAnnotation() {
            recordUndoState(previousState)
        }
    }

    func setTextBackgroundColor(_ option: EditorTextBackgroundColorOption) {
        selectedTextBackgroundColorID = option.id

        guard isTextEditingActive else {
            return
        }

        textFormattingCommand = EditorTextFormattingCommand(
            kind: .background,
            color: option.color
        )
    }

    func setStrokeWidth(_ width: CGFloat) {
        let previousState = currentHistoryState()
        selectedStrokeWidth = width

        if applyActiveStyleToSelectedAnnotation() {
            recordUndoState(previousState)
        }
    }

    func setArrowStyle(_ arrowStyle: AnnotationArrowStyle) {
        let previousState = currentHistoryState()
        selectedArrowStyle = arrowStyle

        if applyActiveStyleToSelectedAnnotation(only: .arrow) {
            recordUndoState(previousState)
        }
    }

    func setTextSize(_ size: CGFloat) {
        let previousState = currentHistoryState()
        selectedTextSize = size

        if applyActiveStyleToSelectedAnnotation(only: .text),
           !isTextEditingActive {
            recordUndoState(previousState)
        }

        if isTextEditingActive {
            textFormattingCommand = EditorTextFormattingCommand(
                kind: .baseFont,
                color: nil
            )
        }
    }

    func setTextFontFamily(_ fontFamily: AnnotationTextFontFamily) {
        let previousState = currentHistoryState()
        selectedTextFontFamily = fontFamily

        if applyActiveStyleToSelectedAnnotation(only: .text),
           !isTextEditingActive {
            recordUndoState(previousState)
        }

        if isTextEditingActive {
            textFormattingCommand = EditorTextFormattingCommand(
                kind: .baseFont,
                color: nil
            )
        }
    }

    func beginOpacityEditing() {
        opacityEditingInitialState = currentHistoryState()
    }

    func setOpacity(_ opacity: CGFloat) {
        let previousState = currentHistoryState()
        let steppedOpacity = (opacity * 20).rounded() / 20
        let normalizedOpacity = min(max(steppedOpacity, 0.1), 1)

        guard normalizedOpacity != selectedOpacity else {
            return
        }

        selectedOpacity = normalizedOpacity
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )

        if applyActiveStyleToSelectedAnnotation(),
           opacityEditingInitialState == nil {
            recordUndoState(previousState)
        }
    }

    func endOpacityEditing() {
        guard let initialState = opacityEditingInitialState else {
            return
        }

        opacityEditingInitialState = nil
        commitHistoryTransition(from: initialState)
    }

    func beginPixelateIntensityEditing() {
        pixelateIntensityEditingInitialState = currentHistoryState()
    }

    func setPixelateIntensity(_ intensity: CGFloat) {
        let previousState = currentHistoryState()
        let normalizedIntensity = min(max((intensity * 2).rounded() / 2, 1), 12)

        guard normalizedIntensity != selectedPixelateIntensity else {
            return
        }

        selectedPixelateIntensity = normalizedIntensity
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )

        if applyActiveStyleToSelectedAnnotation(only: .blurPixelate),
           pixelateIntensityEditingInitialState == nil {
            recordUndoState(previousState)
        }
    }

    func endPixelateIntensityEditing() {
        guard let initialState = pixelateIntensityEditingInitialState else {
            return
        }

        pixelateIntensityEditingInitialState = nil
        commitHistoryTransition(from: initialState)
    }

    func setImageEffect(_ imageEffect: AnnotationImageEffect) {
        let previousState = currentHistoryState()
        selectedImageEffect = imageEffect

        if applyActiveStyleToSelectedAnnotation(only: .blurPixelate) {
            recordUndoState(previousState)
        }
    }

    func isImageEffectSelected(_ imageEffect: AnnotationImageEffect) -> Bool {
        selectedImageEffect == imageEffect
    }

    func beginHighlightIntensityEditing() {
        highlightIntensityEditingInitialState = currentHistoryState()
    }

    func setSpotlightShape(_ shape: AnnotationSpotlightShape) {
        let previousState = currentHistoryState()
        selectedSpotlightShape = shape

        if applyActiveStyleToSelectedAnnotation(only: .highlight) {
            recordUndoState(previousState)
        }
    }

    func isSpotlightShapeSelected(_ shape: AnnotationSpotlightShape) -> Bool {
        selectedSpotlightShape == shape
    }

    func setHighlightIntensity(_ intensity: CGFloat) {
        let previousState = currentHistoryState()
        let steppedIntensity = (intensity * 20).rounded() / 20
        let normalizedIntensity = min(max(steppedIntensity, 0.1), 0.85)

        guard normalizedIntensity != selectedHighlightIntensity else {
            return
        }

        selectedHighlightIntensity = normalizedIntensity
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )

        if applyActiveStyleToSelectedAnnotation(only: .highlight),
           highlightIntensityEditingInitialState == nil {
            recordUndoState(previousState)
        }
    }

    func endHighlightIntensityEditing() {
        guard let initialState = highlightIntensityEditingInitialState else {
            return
        }

        highlightIntensityEditingInitialState = nil
        commitHistoryTransition(from: initialState)
    }

    func isStrokeColorSelected(_ option: EditorStrokeColorOption) -> Bool {
        selectedStrokeColorID == option.id
    }

    func isTextBackgroundColorSelected(_ option: EditorTextBackgroundColorOption) -> Bool {
        selectedTextBackgroundColorID == option.id
    }

    func isStrokeWidthSelected(_ width: CGFloat) -> Bool {
        selectedStrokeWidth == width
    }

    func isArrowStyleSelected(_ arrowStyle: AnnotationArrowStyle) -> Bool {
        selectedArrowStyle == arrowStyle
    }

    func isTextSizeSelected(_ size: CGFloat) -> Bool {
        selectedTextSize == size
    }

    func isTextFontFamilySelected(_ fontFamily: AnnotationTextFontFamily) -> Bool {
        selectedTextFontFamily == fontFamily
    }

    func isCropRatioSelected(_ option: EditorCropRatioOption) -> Bool {
        selectedCropRatioID == option.id
    }

    func setCropRatio(_ option: EditorCropRatioOption) {
        if option.usesCustomRatio {
            customCropRatio = currentCropFrameRatio()
        }

        selectedCropRatioID = option.id
        updateCropFrameForSelectedRatio()
    }

    func setCropFramePixelWidth(_ width: Int) {
        updateDraftCropFrameSize(changedAxis: .width, value: CGFloat(width))
    }

    func setCropFramePixelHeight(_ height: Int) {
        updateDraftCropFrameSize(changedAxis: .height, value: CGFloat(height))
    }

    func isCropFillColorSelected(_ option: EditorCropFillColorOption) -> Bool {
        selectedCropFillColorID == option.id
    }

    func setCropFillColor(_ option: EditorCropFillColorOption) {
        selectedCropFillColorID = option.id
    }

    func rotateCropImageClockwise() {
        transformCanvasImage(.rotateClockwise)
    }

    func flipCropImageHorizontally() {
        transformCanvasImage(.flipHorizontally)
    }

    func flipCropImageVertically() {
        transformCanvasImage(.flipVertically)
    }

    @discardableResult
    func beginTextAnnotation(at point: CGPoint) -> UUID {
        let previousState = currentHistoryState()
        let annotation = AnnotationObject.text(
            rect: defaultTextRect(at: point),
            text: "",
            style: activeAnnotationStyle()
        )

        annotationObjects.append(annotation)
        selectedAnnotationID = annotation.id
        draftAnnotationObject = nil
        activeDragSession = nil
        textEditingInitialState = previousState
        activeTextEditingAnnotationID = annotation.id
        return annotation.id
    }

    @discardableResult
    func beginTextEditing(annotationID: UUID) -> Bool {
        guard let annotation = annotation(withID: annotationID),
              annotation.kind == .text
        else {
            return false
        }

        selectedAnnotationID = annotationID
        syncTextStyleFromSelectedAnnotation(annotation)
        draftAnnotationObject = nil
        activeDragSession = nil
        textEditingInitialState = currentHistoryState()
        activeTextEditingAnnotationID = annotationID
        return true
    }

    func updateEditingText(
        annotationID: UUID,
        text: String,
        runs: [AnnotationTextRun],
        rect: CGRect
    ) {
        guard let annotation = annotation(withID: annotationID),
              annotation.kind == .text
        else {
            return
        }

        updateAnnotation(
            withID: annotationID,
            to: annotation.updatingText(text, runs: runs, rect: rect)
        )
    }

    func endTextEditing(annotationID: UUID) {
        guard let initialHistoryState = textEditingInitialState else {
            return
        }

        if let annotation = annotation(withID: annotationID),
           case let .text(_, text, _) = annotation.geometry,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotationObjects.removeAll { annotation in
                annotation.id == annotationID
            }

            if selectedAnnotationID == annotationID {
                selectedAnnotationID = nil
            }
        }

        textEditingInitialState = nil
        activeTextEditingAnnotationID = nil
        commitHistoryTransition(from: initialHistoryState)
    }

    func textAnnotation(withID id: UUID) -> AnnotationObject? {
        guard let annotation = annotation(withID: id),
              annotation.kind == .text
        else {
            return nil
        }

        return annotation
    }

    func beginCanvasInteraction(
        at point: CGPoint,
        hitResult: AnnotationHitResult
    ) {
        draftAnnotationObject = nil

        if activeTool == .crop {
            beginCropFrameInteraction(at: point, hitResult: .empty)
            return
        }

        switch hitResult {
        case let .resize(annotationID, handle):
            guard let annotation = annotation(withID: annotationID) else {
                return
            }

            selectedAnnotationID = annotationID
            syncArrowStyleFromSelectedAnnotation(annotation)
            syncPixelateIntensityFromSelectedAnnotation(annotation)
            syncHighlightIntensityFromSelectedAnnotation(annotation)
            syncTextStyleFromSelectedAnnotation(annotation)
            activeDragSession = .resizing(
                annotationID: annotationID,
                handle: handle,
                originalAnnotation: annotation,
                initialHistoryState: currentHistoryState()
            )
        case let .annotation(annotationID):
            guard let annotation = annotation(withID: annotationID) else {
                return
            }

            selectedAnnotationID = annotationID
            syncArrowStyleFromSelectedAnnotation(annotation)
            syncPixelateIntensityFromSelectedAnnotation(annotation)
            syncHighlightIntensityFromSelectedAnnotation(annotation)
            syncTextStyleFromSelectedAnnotation(annotation)
            activeDragSession = .moving(
                annotationID: annotationID,
                startPoint: point,
                originalAnnotation: annotation,
                initialHistoryState: currentHistoryState()
            )
        case .empty:
            selectedAnnotationID = nil

            if activeTool == .numbering {
                placeNextNumberingBadge(at: point)
                return
            }

            if activeTool == .smartTextHighlight {
                prepareSmartTextWordCache()
                draftAnnotationObject = nil
                activeDragSession = .drawing(tool: .smartTextHighlight, startPoint: point, points: [point])
                return
            }

            if activeTool == .drawing {
                draftAnnotationObject = nil
                activeDragSession = .drawing(tool: .drawing, startPoint: point, points: [point])
                return
            }

            guard let activeTool,
                  let draftAnnotation = annotationInteractionService.makeAnnotation(
                    tool: activeTool,
                    startPoint: point,
                    endPoint: point,
                    style: activeAnnotationStyle()
                  )
            else {
                activeDragSession = nil
                return
            }

            draftAnnotationObject = draftAnnotation
            activeDragSession = .drawing(tool: activeTool, startPoint: point, points: [point])
        }
    }

    func beginCropFrameInteraction(
        at point: CGPoint,
        hitResult: EditorCropFrameHitResult
    ) {
        guard activeTool == .crop else {
            return
        }

        selectedAnnotationID = nil
        draftAnnotationObject = nil

        let cropRect = (draftCropRect ?? defaultCropFrame()).standardizedForEditor
        draftCropRect = cropRect

        switch hitResult {
        case let .resize(handle):
            isCropGridVisible = true
            activeDragSession = .resizingCropFrame(
                handle: handle,
                originalRect: cropRect
            )
        case .move:
            isCropGridVisible = false
            activeDragSession = .movingCropFrame(
                startPoint: point,
                originalRect: cropRect
            )
        case .empty:
            let startPoint = point.clamped(to: currentCanvasBounds)
            isCropGridVisible = false
            activeDragSession = .drawingCropFrame(
                startPoint: startPoint,
                originalRect: cropRect,
                hasStartedDrawing: false
            )
        }
    }

    func updateCanvasInteraction(
        to point: CGPoint,
        constrainingCropToOriginalRatio: Bool = false
    ) {
        guard let activeDragSession else {
            return
        }

        switch activeDragSession {
        case let .drawing(tool, startPoint, points):
            let updatedPoints = smartDragPoints(from: points, appending: point)

            if tool == .smartTextHighlight {
                draftAnnotationObject = smartTextHighlightAnnotation(
                    for: updatedPoints,
                    style: activeAnnotationStyle()
                )
            } else if tool == .drawing {
                draftAnnotationObject = annotationInteractionService.makeDrawingAnnotation(
                    points: updatedPoints,
                    style: activeAnnotationStyle()
                )
            } else {
                draftAnnotationObject = annotationInteractionService.makeAnnotation(
                    tool: tool,
                    startPoint: startPoint,
                    endPoint: point,
                    style: activeAnnotationStyle()
                )
            }

            self.activeDragSession = .drawing(tool: tool, startPoint: startPoint, points: updatedPoints)
        case let .drawingCropFrame(startPoint, originalRect, hasStartedDrawing):
            let clampedPoint = point.clamped(to: currentCanvasBounds)
            let dragDistance = hypot(clampedPoint.x - startPoint.x, clampedPoint.y - startPoint.y)
            let shouldDrawNewFrame = hasStartedDrawing || dragDistance >= cropNewFrameDragThreshold

            guard shouldDrawNewFrame else {
                draftCropRect = originalRect
                return
            }

            let targetRatio = constrainingCropToOriginalRatio
                ? originalImageCropRatio()
                : selectedCropRatio()
            draftCropRect = cropRect(
                from: startPoint,
                to: clampedPoint,
                targetRatio: targetRatio
            )
            .clampedInside(currentCanvasBounds, minimumSize: 1)
            self.activeDragSession = .drawingCropFrame(
                startPoint: startPoint,
                originalRect: originalRect,
                hasStartedDrawing: true
            )
        case let .movingCropFrame(startPoint, originalRect):
            draftCropRect = originalRect.offsetBy(
                dx: point.x - startPoint.x,
                dy: point.y - startPoint.y
            )
            .movedInside(currentCanvasBounds)
            .standardizedForEditor
        case let .resizingCropFrame(handle, originalRect):
            draftCropRect = resizedCropFrame(
                originalRect,
                using: handle,
                to: point,
                constrainingToOriginalRatio: constrainingCropToOriginalRatio
            )
        case let .moving(annotationID, startPoint, originalAnnotation, _):
            let translation = CGSize(
                width: point.x - startPoint.x,
                height: point.y - startPoint.y
            )
            updateAnnotation(
                withID: annotationID,
                to: originalAnnotation.translated(by: translation)
            )
        case let .resizing(annotationID, handle, originalAnnotation, _):
            updateAnnotation(
                withID: annotationID,
                to: originalAnnotation.resized(using: handle, to: point)
            )
        }
    }

    func endCanvasInteraction() {
        switch activeDragSession {
        case .drawing:
            if let draftAnnotationObject,
               annotationInteractionService.shouldCommit(draftAnnotationObject) {
                let previousState = currentHistoryState()

                if draftAnnotationObject.kind == .highlight {
                    annotationObjects.removeAll { annotation in
                        annotation.kind == .highlight
                    }
                }

                annotationObjects.append(draftAnnotationObject)
                selectedAnnotationID = draftAnnotationObject.id
                recordUndoState(previousState)
            }
        case let .drawingCropFrame(_, originalRect, hasStartedDrawing):
            if !hasStartedDrawing {
                draftCropRect = originalRect
            } else if let draftCropRect,
                      !shouldCommitCrop(draftCropRect) {
                self.draftCropRect = originalRect
            }
        case .movingCropFrame, .resizingCropFrame:
            break
        case let .moving(_, _, _, initialHistoryState),
             let .resizing(_, _, _, initialHistoryState):
            commitHistoryTransition(from: initialHistoryState)
        case .none:
            break
        }

        draftAnnotationObject = nil
        isCropGridVisible = false
        activeDragSession = nil
    }

    func hitTestAnnotation(at point: CGPoint, tolerance: CGFloat) -> AnnotationHitResult {
        annotationInteractionService.hitTest(
            point: point,
            annotations: annotationObjects,
            selectedAnnotationID: selectedAnnotationID,
            tolerance: tolerance
        )
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else {
            return
        }

        let previousState = currentHistoryState()
        annotationObjects.removeAll { annotation in
            annotation.id == selectedAnnotationID
        }
        self.selectedAnnotationID = nil
        draftAnnotationObject = nil
        draftCropRect = nil
        isCropGridVisible = false
        activeDragSession = nil
        recordUndoState(previousState)
    }

    func deselectAnnotation() {
        selectedAnnotationID = nil
    }

    func clearActiveTool() {
        activeTool = nil
        selectedAnnotationID = nil
        draftAnnotationObject = nil
        draftCropRect = nil
        isCropGridVisible = false
        activeDragSession = nil
    }

    func cancelCropMode() {
        clearActiveTool()
    }

    func applyCurrentCropFrame() {
        guard activeTool == .crop,
              let draftCropRect,
              shouldCommitCrop(draftCropRect)
        else {
            clearActiveTool()
            return
        }

        let previousState = currentHistoryState()

        if applyCanvasCrop(to: draftCropRect) {
            recordUndoState(previousState)
        }

        clearActiveTool()
    }

    func handleShortcut(_ shortcut: String) -> Bool {
        switch shortcut.lowercased() {
        case "d":
            selectTool(.drawing)
            return true
        case "a":
            selectTool(.arrow)
            return true
        case "l":
            selectTool(.line)
            return true
        case "n":
            selectTool(.numbering)
            return true
        case "r":
            selectTool(.rectangle)
            return true
        case "f":
            selectTool(.filledRectangle)
            return true
        case "o":
            selectTool(.oval)
            return true
        case "t":
            selectTool(.text)
            return true
        case "m":
            selectTool(.textHighlight)
            return true
        case "s":
            selectTool(.smartTextHighlight)
            return true
        case "h":
            selectTool(.highlight)
            return true
        case "b":
            selectTool(.blurPixelate)
            return true
        case "x":
            toggleCropTool()
            return true
        default:
            return false
        }
    }

    func undo() {
        guard let previousState = undoStack.popLast() else {
            updateHistoryAvailability()
            return
        }

        redoStack.append(currentHistoryState())
        restore(previousState)
        updateHistoryAvailability()
    }

    func redo() {
        guard let nextState = redoStack.popLast() else {
            updateHistoryAvailability()
            return
        }

        undoStack.append(currentHistoryState())
        restore(nextState)
        updateHistoryAvailability()
    }

    private func copy() {
        outputService.copy(image: image, annotations: annotationObjects)
    }

    private func save() {
        outputService.save(image: image, sourceFileURL: sourceFileURL, annotations: annotationObjects)
    }

    private func applyCanvasCrop(to cropRect: CGRect) -> Bool {
        let normalizedCropRect = cropRect.standardizedForEditor
        let canvasBounds = currentCanvasBounds

        guard !normalizedCropRect.isNearlyEqual(to: canvasBounds),
              let resizedImage = canvasResizeService.resizedCanvasImage(
                from: image,
                to: normalizedCropRect,
                fillColor: selectedCropFillColor
              )
        else {
            return false
        }

        let translation = CGSize(
            width: -normalizedCropRect.minX,
            height: -normalizedCropRect.minY
        )

        image = resizedImage
        imageRevision = UUID()
        annotationObjects = annotationObjects.map { annotation in
            annotation.translated(by: translation)
        }
        selectedAnnotationID = nil
        draftAnnotationObject = nil
        draftCropRect = nil
        return true
    }

    private func transformCanvasImage(_ transform: EditorCanvasImageTransform) {
        let canvasSize = image.editorHistoryCanvasSize
        guard canvasSize.width > 0,
              canvasSize.height > 0
        else {
            return
        }

        let transformedImage: NSImage?
        let transformedAnnotations: [AnnotationObject]
        let transformedCropRect: CGRect?

        switch transform {
        case .rotateClockwise:
            transformedImage = canvasResizeService.rotatedClockwiseImage(from: image)
            transformedAnnotations = annotationObjects.map { annotation in
                annotation.rotatedClockwise(in: canvasSize)
            }
            transformedCropRect = draftCropRect?.transformedByMappingCorners { point in
                CGPoint(x: canvasSize.height - point.y, y: point.x)
            }
        case .flipHorizontally:
            transformedImage = canvasResizeService.flippedImage(from: image, horizontally: true)
            transformedAnnotations = annotationObjects.map { annotation in
                annotation.flippedHorizontally(in: canvasSize)
            }
            transformedCropRect = draftCropRect?.transformedByMappingCorners { point in
                CGPoint(x: canvasSize.width - point.x, y: point.y)
            }
        case .flipVertically:
            transformedImage = canvasResizeService.flippedImage(from: image, horizontally: false)
            transformedAnnotations = annotationObjects.map { annotation in
                annotation.flippedVertically(in: canvasSize)
            }
            transformedCropRect = draftCropRect?.transformedByMappingCorners { point in
                CGPoint(x: point.x, y: canvasSize.height - point.y)
            }
        }

        guard let transformedImage else {
            return
        }

        let previousState = currentHistoryState()
        image = transformedImage
        imageRevision = UUID()
        annotationObjects = transformedAnnotations
        selectedAnnotationID = nil
        draftAnnotationObject = nil
        activeDragSession = nil
        isCropGridVisible = false

        if activeTool == .crop {
            draftCropRect = (transformedCropRect ?? currentCanvasBounds)
                .clampedInside(currentCanvasBounds, minimumSize: minimumCropFrameLength)
        } else {
            draftCropRect = nil
        }

        recordUndoState(previousState)
    }

    private func shouldCommitCrop(_ rect: CGRect) -> Bool {
        let normalizedRect = rect.standardizedForEditor
        return normalizedRect.width >= 8 && normalizedRect.height >= 8
    }

    private func updateCropFrameForSelectedRatio() {
        guard activeTool == .crop else {
            return
        }

        draftCropRect = adjustedCropFrameForSelectedRatio(from: draftCropRect)
    }

    private func updateDraftCropFrameSize(
        changedAxis: EditorCropFrameDimensionAxis,
        value: CGFloat
    ) {
        guard activeTool == .crop else {
            return
        }

        let bounds = currentCanvasBounds
        guard bounds.width > 0,
              bounds.height > 0
        else {
            return
        }

        let currentRect = (draftCropRect ?? defaultCropFrame()).standardizedForEditor
        let center = CGPoint(x: currentRect.midX, y: currentRect.midY)
        let minimumLength = minimumCropFrameLength
        let ratio = selectedCropRatio()
        var width = currentRect.width
        var height = currentRect.height

        if let ratio {
            switch changedAxis {
            case .width:
                let maximumWidth = max(minimumLength, min(bounds.width, bounds.height * ratio))
                width = clamped(value, lowerBound: minimumLength, upperBound: maximumWidth)
                height = width / ratio
            case .height:
                let maximumHeight = max(minimumLength, min(bounds.height, bounds.width / ratio))
                height = clamped(value, lowerBound: minimumLength, upperBound: maximumHeight)
                width = height * ratio
            }
        } else {
            switch changedAxis {
            case .width:
                width = clamped(value, lowerBound: minimumLength, upperBound: bounds.width)
            case .height:
                height = clamped(value, lowerBound: minimumLength, upperBound: bounds.height)
            }
        }

        draftCropRect = CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        .clampedInside(bounds, minimumSize: minimumLength)
        .standardizedForEditor
    }

    private func defaultCropFrame() -> CGRect {
        adjustedCropFrameForSelectedRatio(from: nil)
    }

    private func adjustedCropFrameForSelectedRatio(from currentRect: CGRect?) -> CGRect {
        let canvasBounds = currentCanvasBounds
        guard canvasBounds.width > 0,
              canvasBounds.height > 0
        else {
            return CGRect(x: 0, y: 0, width: 960, height: 540)
        }

        guard let targetRatio = selectedCropRatio() else {
            return (currentRect?.standardizedForEditor ?? canvasBounds)
                .clampedInside(canvasBounds, minimumSize: minimumCropFrameLength)
        }

        let baseRect = currentRect?.standardizedForEditor ?? canvasBounds
        let center = CGPoint(x: baseRect.midX, y: baseRect.midY)
        let maxWidth = min(baseRect.width, canvasBounds.width)
        let maxHeight = min(baseRect.height, canvasBounds.height)
        var width = maxWidth
        var height = width / targetRatio

        if height > maxHeight {
            height = maxHeight
            width = height * targetRatio
        }

        let fittedSize = CGSize(
            width: max(8, min(width, canvasBounds.width)),
            height: max(8, min(height, canvasBounds.height))
        )

        return CGRect(
            x: center.x - fittedSize.width / 2,
            y: center.y - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        .movedInside(canvasBounds)
        .standardizedForEditor
    }

    private func resizedCropFrame(
        _ originalRect: CGRect,
        using handle: EditorCropFrameHandle,
        to point: CGPoint,
        constrainingToOriginalRatio: Bool
    ) -> CGRect {
        let rect = originalRect.standardizedForEditor
        let canvasBounds = currentCanvasBounds
        let clampedPoint = point.clamped(to: canvasBounds)
        let targetRatio = constrainingToOriginalRatio && handle.isCorner
            ? originalImageCropRatio()
            : selectedCropRatio()

        guard let targetRatio,
              handle.isCorner
        else {
            return freeformCropFrame(
                rect,
                using: handle,
                to: clampedPoint,
                in: canvasBounds
            )
        }

        switch handle {
        case .topLeft:
            return cropRect(from: CGPoint(x: rect.maxX, y: rect.maxY), to: clampedPoint, targetRatio: targetRatio)
                .clampedInside(canvasBounds, minimumSize: minimumCropFrameLength)
        case .topRight:
            return cropRect(from: CGPoint(x: rect.minX, y: rect.maxY), to: clampedPoint, targetRatio: targetRatio)
                .clampedInside(canvasBounds, minimumSize: minimumCropFrameLength)
        case .bottomRight:
            return cropRect(from: CGPoint(x: rect.minX, y: rect.minY), to: clampedPoint, targetRatio: targetRatio)
                .clampedInside(canvasBounds, minimumSize: minimumCropFrameLength)
        case .bottomLeft:
            return cropRect(from: CGPoint(x: rect.maxX, y: rect.minY), to: clampedPoint, targetRatio: targetRatio)
                .clampedInside(canvasBounds, minimumSize: minimumCropFrameLength)
        case .top:
            return ratioCropFrameByChangingHeight(
                rect,
                anchoredEdge: .bottom,
                to: clampedPoint.y,
                ratio: targetRatio,
                in: canvasBounds
            )
        case .right:
            return ratioCropFrameByChangingWidth(
                rect,
                anchoredEdge: .left,
                to: clampedPoint.x,
                ratio: targetRatio,
                in: canvasBounds
            )
        case .bottom:
            return ratioCropFrameByChangingHeight(
                rect,
                anchoredEdge: .top,
                to: clampedPoint.y,
                ratio: targetRatio,
                in: canvasBounds
            )
        case .left:
            return ratioCropFrameByChangingWidth(
                rect,
                anchoredEdge: .right,
                to: clampedPoint.x,
                ratio: targetRatio,
                in: canvasBounds
            )
        }
    }

    private func freeformCropFrame(
        _ originalRect: CGRect,
        using handle: EditorCropFrameHandle,
        to point: CGPoint,
        in bounds: CGRect
    ) -> CGRect {
        let rect = originalRect.standardizedForEditor
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeft:
            minX = clamped(point.x, lowerBound: bounds.minX, upperBound: maxX - minimumCropFrameLength)
            minY = clamped(point.y, lowerBound: bounds.minY, upperBound: maxY - minimumCropFrameLength)
        case .top:
            minY = clamped(point.y, lowerBound: bounds.minY, upperBound: maxY - minimumCropFrameLength)
        case .topRight:
            maxX = clamped(point.x, lowerBound: minX + minimumCropFrameLength, upperBound: bounds.maxX)
            minY = clamped(point.y, lowerBound: bounds.minY, upperBound: maxY - minimumCropFrameLength)
        case .right:
            maxX = clamped(point.x, lowerBound: minX + minimumCropFrameLength, upperBound: bounds.maxX)
        case .bottomRight:
            maxX = clamped(point.x, lowerBound: minX + minimumCropFrameLength, upperBound: bounds.maxX)
            maxY = clamped(point.y, lowerBound: minY + minimumCropFrameLength, upperBound: bounds.maxY)
        case .bottom:
            maxY = clamped(point.y, lowerBound: minY + minimumCropFrameLength, upperBound: bounds.maxY)
        case .bottomLeft:
            minX = clamped(point.x, lowerBound: bounds.minX, upperBound: maxX - minimumCropFrameLength)
            maxY = clamped(point.y, lowerBound: minY + minimumCropFrameLength, upperBound: bounds.maxY)
        case .left:
            minX = clamped(point.x, lowerBound: bounds.minX, upperBound: maxX - minimumCropFrameLength)
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private func clamped(
        _ value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }

    private func ratioCropFrameByChangingWidth(
        _ originalRect: CGRect,
        anchoredEdge: HorizontalCropFrameEdge,
        to xPosition: CGFloat,
        ratio: CGFloat,
        in bounds: CGRect
    ) -> CGRect {
        let rect = originalRect.standardizedForEditor
        let centerY = rect.midY
        let availableHeight = max(
            minimumCropFrameLength,
            min(centerY - bounds.minY, bounds.maxY - centerY) * 2
        )
        let maximumWidthFromHeight = availableHeight * ratio
        let maximumWidthFromAnchor = anchoredEdge == .left
            ? bounds.maxX - rect.minX
            : rect.maxX - bounds.minX
        let maximumWidth = max(
            minimumCropFrameLength,
            min(maximumWidthFromHeight, maximumWidthFromAnchor)
        )
        let requestedWidth = anchoredEdge == .left
            ? xPosition - rect.minX
            : rect.maxX - xPosition
        let width = min(max(minimumCropFrameLength, requestedWidth), maximumWidth)
        let height = width / ratio
        let originX = anchoredEdge == .left ? rect.minX : rect.maxX - width

        return CGRect(
            x: originX,
            y: centerY - height / 2,
            width: width,
            height: height
        )
        .clampedInside(bounds, minimumSize: minimumCropFrameLength)
    }

    private func ratioCropFrameByChangingHeight(
        _ originalRect: CGRect,
        anchoredEdge: VerticalCropFrameEdge,
        to yPosition: CGFloat,
        ratio: CGFloat,
        in bounds: CGRect
    ) -> CGRect {
        let rect = originalRect.standardizedForEditor
        let centerX = rect.midX
        let availableWidth = max(
            minimumCropFrameLength,
            min(centerX - bounds.minX, bounds.maxX - centerX) * 2
        )
        let maximumHeightFromWidth = availableWidth / ratio
        let maximumHeightFromAnchor = anchoredEdge == .top
            ? bounds.maxY - rect.minY
            : rect.maxY - bounds.minY
        let maximumHeight = max(
            minimumCropFrameLength,
            min(maximumHeightFromWidth, maximumHeightFromAnchor)
        )
        let requestedHeight = anchoredEdge == .top
            ? yPosition - rect.minY
            : rect.maxY - yPosition
        let height = min(max(minimumCropFrameLength, requestedHeight), maximumHeight)
        let width = height * ratio
        let originY = anchoredEdge == .top ? rect.minY : rect.maxY - height

        return CGRect(
            x: centerX - width / 2,
            y: originY,
            width: width,
            height: height
        )
        .clampedInside(bounds, minimumSize: minimumCropFrameLength)
    }

    private func cropRect(
        from startPoint: CGPoint,
        to point: CGPoint,
        targetRatio: CGFloat?
    ) -> CGRect {
        let rawWidth = point.x - startPoint.x
        let rawHeight = point.y - startPoint.y

        guard let targetRatio,
              abs(rawWidth) >= 1,
              abs(rawHeight) >= 1
        else {
            return CGRect(
                x: startPoint.x,
                y: startPoint.y,
                width: rawWidth,
                height: rawHeight
            ).standardizedForEditor
        }

        let widthSign: CGFloat = rawWidth >= 0 ? 1 : -1
        let heightSign: CGFloat = rawHeight >= 0 ? 1 : -1
        var constrainedWidth = abs(rawWidth)
        var constrainedHeight = abs(rawHeight)

        if constrainedWidth / constrainedHeight > targetRatio {
            constrainedWidth = constrainedHeight * targetRatio
        } else {
            constrainedHeight = constrainedWidth / targetRatio
        }

        return CGRect(
            x: startPoint.x,
            y: startPoint.y,
            width: constrainedWidth * widthSign,
            height: constrainedHeight * heightSign
        ).standardizedForEditor
    }

    private func selectedCropRatio() -> CGFloat? {
        let option = selectedCropRatioOption

        if option.usesCustomRatio {
            return customCropRatio ?? currentCropFrameRatio()
        }

        if option.usesOriginalImageRatio {
            let canvasSize = image.editorHistoryCanvasSize
            guard canvasSize.width > 0,
                  canvasSize.height > 0
            else {
                return nil
            }

            return canvasSize.width / canvasSize.height
        }

        return option.ratio
    }

    private func currentCropFrameRatio() -> CGFloat? {
        let rect = (draftCropRect ?? currentCanvasBounds).standardizedForEditor
        guard rect.width > 0,
              rect.height > 0
        else {
            return nil
        }

        return rect.width / rect.height
    }

    private func formattedRatioTitle(for ratio: CGFloat) -> String {
        guard ratio.isFinite,
              ratio > 0
        else {
            return "Ratio"
        }

        let denominator: CGFloat = 100
        let numerator = max(1, round(ratio * denominator))
        let divisor = greatestCommonDivisor(Int(numerator), Int(denominator))
        let left = Int(numerator) / divisor
        let right = Int(denominator) / divisor
        return "\(left) : \(right)"
    }

    private func greatestCommonDivisor(_ firstValue: Int, _ secondValue: Int) -> Int {
        var firstValue = abs(firstValue)
        var secondValue = abs(secondValue)

        while secondValue != 0 {
            let remainder = firstValue % secondValue
            firstValue = secondValue
            secondValue = remainder
        }

        return max(firstValue, 1)
    }

    private func originalImageCropRatio() -> CGFloat? {
        let canvasSize = image.editorHistoryCanvasSize
        guard canvasSize.width > 0,
              canvasSize.height > 0
        else {
            return nil
        }

        return canvasSize.width / canvasSize.height
    }

    private func selectTool(_ tool: EditorTool) {
        activeTool = tool
        selectedAnnotationID = nil
        draftAnnotationObject = nil
        activeDragSession = nil
        isCropGridVisible = false

        if tool == .crop {
            draftCropRect = adjustedCropFrameForSelectedRatio(from: currentCanvasBounds)
        } else {
            draftCropRect = nil
        }

        if tool == .smartTextHighlight {
            prepareSmartTextWordCache()
        }
    }

    private func toggleCropTool() {
        if activeTool == .crop {
            clearActiveTool()
        } else {
            selectTool(.crop)
        }
    }

    private func activeAnnotationStyle() -> AnnotationStyle {
        AnnotationStyle(
            strokeColor: selectedStrokeColor,
            fillColor: .clear,
            lineWidth: selectedStrokeWidth,
            opacity: selectedOpacity,
            fontSize: selectedTextSize,
            textFontFamily: selectedTextFontFamily,
            effectIntensity: selectedPixelateIntensity,
            imageEffect: selectedImageEffect,
            spotlightIntensity: selectedHighlightIntensity,
            spotlightShape: selectedSpotlightShape,
            arrowStyle: selectedArrowStyle
        )
    }

    private func prepareSmartTextWordCache() {
        _ = smartTextWordsForCurrentImage()
    }

    private func smartTextHighlightAnnotation(
        for dragPoints: [CGPoint],
        style: AnnotationStyle
    ) -> AnnotationObject? {
        guard dragPoints.count > 1,
              dragPoints.totalDistance >= 4
        else {
            return nil
        }

        let selectedWords = smartTextWordsForCurrentImage()
            .filter { word in
                smartDragPath(
                    points: dragPoints,
                    touches: word.rect,
                    style: style
                )
            }

        let highlightRects = smartTextHighlightRects(
            for: selectedWords,
            style: style
        )

        guard !highlightRects.isEmpty else {
            return nil
        }

        return AnnotationObject.smartTextHighlight(
            rects: highlightRects,
            style: style
        )
    }

    private func smartTextWordsForCurrentImage() -> [SmartTextWord] {
        let canvasSize = image.editorHistoryCanvasSize

        if let smartTextWordCache,
           smartTextWordCache.imageRevision == imageRevision,
           smartTextWordCache.canvasSize == canvasSize {
            return smartTextWordCache.words
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            smartTextWordCache = SmartTextWordCache(
                imageRevision: imageRevision,
                canvasSize: canvasSize,
                words: []
            )
            return []
        }

        let words = smartTextRecognitionService.recognizedTextWords(
            in: cgImage,
            canvasSize: canvasSize
        )
        smartTextWordCache = SmartTextWordCache(
            imageRevision: imageRevision,
            canvasSize: canvasSize,
            words: words
        )

        return words
    }

    private func smartTextHighlightRects(
        for words: [SmartTextWord],
        style: AnnotationStyle
    ) -> [CGRect] {
        guard !words.isEmpty else {
            return []
        }

        var highlightRects: [CGRect] = []
        let wordsByLine = Dictionary(grouping: words) { word in
            word.lineIndex
        }

        for lineIndex in wordsByLine.keys.sorted() {
            guard let lineWords = wordsByLine[lineIndex]?.sorted(by: { firstWord, secondWord in
                firstWord.wordIndex < secondWord.wordIndex
            }) else {
                continue
            }

            var currentRunRect: CGRect?
            var previousWordIndex: Int?

            for word in lineWords {
                let wordRect = word.rect.standardizedForEditor

                if let runRect = currentRunRect,
                   let previousWordIndex,
                   word.wordIndex == previousWordIndex + 1 {
                    currentRunRect = runRect.union(wordRect).standardizedForEditor
                } else {
                    if let currentRunRect {
                        highlightRects.append(paddedSmartTextRect(currentRunRect, style: style))
                    }

                    currentRunRect = wordRect
                }

                previousWordIndex = word.wordIndex
            }

            if let currentRunRect {
                highlightRects.append(paddedSmartTextRect(currentRunRect, style: style))
            }
        }

        return highlightRects
            .filter { rect in
                rect.width >= 4 && rect.height >= 4
            }
            .sortedForSmartTextHighlight()
    }

    private func smartDragPoints(from points: [CGPoint], appending point: CGPoint) -> [CGPoint] {
        guard let lastPoint = points.last else {
            return [point]
        }

        if lastPoint.distance(to: point) < 1.5 {
            return points
        }

        return points + [point]
    }

    private func smartDragPath(
        points: [CGPoint],
        touches rect: CGRect,
        style: AnnotationStyle
    ) -> Bool {
        guard points.count > 1 else {
            return false
        }

        return zip(points, points.dropFirst()).contains { startPoint, endPoint in
            smartDragPath(
                from: startPoint,
                to: endPoint,
                touches: rect,
                style: style
            )
        }
    }

    private func smartDragPath(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        touches textRect: CGRect,
        style: AnnotationStyle
    ) -> Bool {
        let normalizedTextRect = textRect.standardizedForEditor
        let tolerance = max(4, min(14, normalizedTextRect.height * 0.35 + style.lineWidth * 0.9))
        let expandedTextRect = normalizedTextRect.insetBy(dx: -tolerance, dy: -tolerance)
        let dragBounds = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        .insetBy(dx: -tolerance, dy: -tolerance)

        guard dragBounds.intersects(expandedTextRect) else {
            return false
        }

        return distanceFromLineSegment(
            start: startPoint,
            end: endPoint,
            to: normalizedTextRect
        ) <= tolerance
    }

    private func paddedSmartTextRect(_ textRect: CGRect, style: AnnotationStyle) -> CGRect {
        let rect = textRect.standardizedForEditor
        let horizontalPadding = max(3, min(10, rect.height * 0.28 + style.lineWidth * 0.25))
        let verticalPadding = max(2, min(8, rect.height * 0.18 + style.lineWidth * 0.18))
        let paddedRect = rect
            .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
            .intersection(currentCanvasBounds)

        guard !paddedRect.isNull else {
            return .zero
        }

        return paddedRect.standardizedForEditor
    }

    private func distanceFromLineSegment(start: CGPoint, end: CGPoint, to rect: CGRect) -> CGFloat {
        let normalizedRect = rect.standardizedForEditor

        if normalizedRect.contains(start) ||
            normalizedRect.contains(end) ||
            lineSegmentIntersectsRect(start: start, end: end, rect: normalizedRect) {
            return 0
        }

        let corners = [
            CGPoint(x: normalizedRect.minX, y: normalizedRect.minY),
            CGPoint(x: normalizedRect.maxX, y: normalizedRect.minY),
            CGPoint(x: normalizedRect.maxX, y: normalizedRect.maxY),
            CGPoint(x: normalizedRect.minX, y: normalizedRect.maxY)
        ]
        let cornerDistance = corners
            .map { corner in corner.distanceToLineSegment(start: start, end: end) }
            .min() ?? .greatestFiniteMagnitude

        return min(
            cornerDistance,
            start.distance(to: normalizedRect),
            end.distance(to: normalizedRect)
        )
    }

    private func lineSegmentIntersectsRect(start: CGPoint, end: CGPoint, rect: CGRect) -> Bool {
        if rect.contains(start) || rect.contains(end) {
            return true
        }

        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        return lineSegmentsIntersect(start, end, topLeft, topRight) ||
            lineSegmentsIntersect(start, end, topRight, bottomRight) ||
            lineSegmentsIntersect(start, end, bottomRight, bottomLeft) ||
            lineSegmentsIntersect(start, end, bottomLeft, topLeft)
    }

    private func lineSegmentsIntersect(
        _ firstStart: CGPoint,
        _ firstEnd: CGPoint,
        _ secondStart: CGPoint,
        _ secondEnd: CGPoint
    ) -> Bool {
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        func rangesOverlap(_ firstMin: CGFloat, _ firstMax: CGFloat, _ secondMin: CGFloat, _ secondMax: CGFloat) -> Bool {
            max(firstMin, secondMin) <= min(firstMax, secondMax) + 0.001
        }

        let firstCrossStart = cross(firstStart, firstEnd, secondStart)
        let firstCrossEnd = cross(firstStart, firstEnd, secondEnd)
        let secondCrossStart = cross(secondStart, secondEnd, firstStart)
        let secondCrossEnd = cross(secondStart, secondEnd, firstEnd)

        if abs(firstCrossStart) <= 0.001,
           abs(firstCrossEnd) <= 0.001,
           abs(secondCrossStart) <= 0.001,
           abs(secondCrossEnd) <= 0.001 {
            return rangesOverlap(
                min(firstStart.x, firstEnd.x),
                max(firstStart.x, firstEnd.x),
                min(secondStart.x, secondEnd.x),
                max(secondStart.x, secondEnd.x)
            ) && rangesOverlap(
                min(firstStart.y, firstEnd.y),
                max(firstStart.y, firstEnd.y),
                min(secondStart.y, secondEnd.y),
                max(secondStart.y, secondEnd.y)
            )
        }

        return firstCrossStart * firstCrossEnd <= 0 &&
            secondCrossStart * secondCrossEnd <= 0
    }

    private func placeNextNumberingBadge(at point: CGPoint) {
        let previousState = currentHistoryState()
        let style = activeAnnotationStyle()
        let diameter = AnnotationObject.numberingBadgeDiameter(for: style.lineWidth)
        let centeredRect = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        .movedInside(currentCanvasBounds)
        let annotation = AnnotationObject.numberingBadge(
            center: CGPoint(x: centeredRect.midX, y: centeredRect.midY),
            number: nextNumberingValue(),
            style: style
        )

        annotationObjects.append(annotation)
        selectedAnnotationID = annotation.id
        activeDragSession = nil
        recordUndoState(previousState)
    }

    private func nextNumberingValue() -> Int {
        let highestNumber = annotationObjects
            .filter { annotation in annotation.kind == .numbering }
            .compactMap(\.number)
            .max() ?? 0

        return highestNumber == Int.max ? Int.max : highestNumber + 1
    }

    private func syncArrowStyleFromSelectedAnnotation(_ annotation: AnnotationObject) {
        guard annotation.kind == .arrow else {
            return
        }

        selectedArrowStyle = annotation.style.arrowStyle
    }

    private func syncPixelateIntensityFromSelectedAnnotation(_ annotation: AnnotationObject) {
        guard annotation.kind == .blurPixelate else {
            return
        }

        selectedPixelateIntensity = min(max(annotation.style.effectIntensity, 1), 12)
        selectedImageEffect = annotation.style.imageEffect
    }

    private func syncHighlightIntensityFromSelectedAnnotation(_ annotation: AnnotationObject) {
        guard annotation.kind == .highlight else {
            return
        }

        selectedHighlightIntensity = annotation.style.spotlightIntensity
        selectedSpotlightShape = annotation.style.spotlightShape
    }

    private func syncTextStyleFromSelectedAnnotation(_ annotation: AnnotationObject) {
        guard annotation.kind == .text else {
            return
        }

        selectedTextSize = annotation.style.fontSize
        selectedTextFontFamily = annotation.style.textFontFamily
    }

    private func annotation(withID id: UUID) -> AnnotationObject? {
        annotationObjects.first { annotation in
            annotation.id == id
        }
    }

    private func updateAnnotation(withID id: UUID, to updatedAnnotation: AnnotationObject) {
        guard let index = annotationObjects.firstIndex(where: { annotation in
            annotation.id == id
        }) else {
            return
        }

        annotationObjects[index] = updatedAnnotation
    }

    @discardableResult
    private func applyActiveStyleToSelectedAnnotation(only kind: AnnotationObjectKind? = nil) -> Bool {
        guard let selectedAnnotationID,
              let annotation = annotation(withID: selectedAnnotationID)
        else {
            return false
        }

        if let kind, annotation.kind != kind {
            return false
        }

        let styledAnnotation = annotation.applyingStyle(activeAnnotationStyle())

        guard styledAnnotation != annotation else {
            return false
        }

        updateAnnotation(withID: selectedAnnotationID, to: styledAnnotation)
        return true
    }

    private func currentHistoryState() -> EditorHistoryState {
        EditorHistoryState(
            image: image,
            imageRevision: imageRevision,
            annotationObjects: annotationObjects,
            selectedAnnotationID: selectedAnnotationID
        )
    }

    private func restore(_ state: EditorHistoryState) {
        image = state.image
        imageRevision = state.imageRevision
        annotationObjects = state.annotationObjects
        selectedAnnotationID = state.selectedAnnotationID
        draftAnnotationObject = nil
        draftCropRect = nil
        activeDragSession = nil
        isCropGridVisible = false
        textEditingInitialState = nil
        activeTextEditingAnnotationID = nil
    }

    private func commitHistoryTransition(from previousState: EditorHistoryState) {
        guard currentHistoryState() != previousState else {
            return
        }

        recordUndoState(previousState)
    }

    private func recordUndoState(_ state: EditorHistoryState) {
        guard currentHistoryState() != state else {
            updateHistoryAvailability()
            return
        }

        undoStack.append(state)

        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }

        redoStack.removeAll()
        updateHistoryAvailability()
    }

    private func updateHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func defaultTextRect(at point: CGPoint) -> CGRect {
        CGRect(
            x: point.x,
            y: point.y,
            width: 260,
            height: max(48, selectedTextSize * 2.2)
        )
    }
}

private enum EditorDragSession {
    case drawing(tool: EditorTool, startPoint: CGPoint, points: [CGPoint])
    case drawingCropFrame(
        startPoint: CGPoint,
        originalRect: CGRect,
        hasStartedDrawing: Bool
    )
    case movingCropFrame(
        startPoint: CGPoint,
        originalRect: CGRect
    )
    case resizingCropFrame(
        handle: EditorCropFrameHandle,
        originalRect: CGRect
    )
    case moving(
        annotationID: UUID,
        startPoint: CGPoint,
        originalAnnotation: AnnotationObject,
        initialHistoryState: EditorHistoryState
    )
    case resizing(
        annotationID: UUID,
        handle: AnnotationResizeHandle,
        originalAnnotation: AnnotationObject,
        initialHistoryState: EditorHistoryState
    )
}

private extension EditorCropFrameHandle {
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            return true
        case .top, .right, .bottom, .left:
            return false
        }
    }
}

private enum HorizontalCropFrameEdge {
    case left
    case right
}

private enum VerticalCropFrameEdge {
    case top
    case bottom
}

private enum EditorCropFrameDimensionAxis {
    case width
    case height
}

private enum EditorCanvasImageTransform {
    case rotateClockwise
    case flipHorizontally
    case flipVertically
}

private struct EditorHistoryState: Equatable {
    let image: NSImage
    let imageRevision: UUID
    let annotationObjects: [AnnotationObject]
    let selectedAnnotationID: UUID?

    static func == (lhs: EditorHistoryState, rhs: EditorHistoryState) -> Bool {
        lhs.imageRevision == rhs.imageRevision &&
            lhs.annotationObjects == rhs.annotationObjects &&
            lhs.selectedAnnotationID == rhs.selectedAnnotationID
    }
}

private struct SmartTextWordCache {
    let imageRevision: UUID
    let canvasSize: CGSize
    let words: [SmartTextWord]
}

private struct SmartTextWord {
    let rect: CGRect
    let lineIndex: Int
    let wordIndex: Int
}

private final class SmartTextRecognitionService {
    func recognizedTextWords(in image: CGImage, canvasSize: CGSize) -> [SmartTextWord] {
        guard canvasSize.width > 0,
              canvasSize.height > 0
        else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.006

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? [])
            .enumerated()
            .flatMap { lineIndex, observation in
                recognizedWords(
                    in: observation,
                    lineIndex: lineIndex,
                    canvasSize: canvasSize
                )
            }
    }

    private func recognizedWords(
        in observation: VNRecognizedTextObservation,
        lineIndex: Int,
        canvasSize: CGSize
    ) -> [SmartTextWord] {
        guard let candidate = observation.topCandidates(1).first else {
            return []
        }

        var words: [SmartTextWord] = []
        var wordIndex = 0
        let text = candidate.string

        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .localized]
        ) { _, substringRange, _, _ in
            guard let wordObservation = try? candidate.boundingBox(for: substringRange) else {
                return
            }

            let rect = self.rect(fromNormalizedBoundingBox: wordObservation.boundingBox, canvasSize: canvasSize)
            guard rect.width >= 2,
                  rect.height >= 3
            else {
                return
            }

            words.append(
                SmartTextWord(
                    rect: rect.standardizedForEditor,
                    lineIndex: lineIndex,
                    wordIndex: wordIndex
                )
            )
            wordIndex += 1
        }

        return words
    }

    private func rect(fromNormalizedBoundingBox boundingBox: CGRect, canvasSize: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.minX * canvasSize.width,
            y: (1 - boundingBox.maxY) * canvasSize.height,
            width: boundingBox.width * canvasSize.width,
            height: boundingBox.height * canvasSize.height
        )
        .standardizedForEditor
    }
}

private extension NSImage {
    var editorHistoryCanvasSize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSSize(width: 960, height: 540)
        }

        return NSSize(width: cgImage.width, height: cgImage.height)
    }
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }

    func movedInside(_ bounds: CGRect) -> CGRect {
        var rect = self

        if rect.width <= bounds.width {
            rect.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        }

        if rect.height <= bounds.height {
            rect.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        }

        return rect
    }

    func clampedInside(_ bounds: CGRect, minimumSize: CGFloat) -> CGRect {
        var rect = standardizedForEditor
        rect.size.width = min(max(rect.width, minimumSize), bounds.width)
        rect.size.height = min(max(rect.height, minimumSize), bounds.height)
        return rect.movedInside(bounds)
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(x - point.x, y - point.y)
    }

    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }

    func distanceToLineSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(x - start.x, y - start.y)
        }

        let progress = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(
            x: start.x + progress * dx,
            y: start.y + progress * dy
        )

        return hypot(x - projection.x, y - projection.y)
    }

    func distance(to rect: CGRect) -> CGFloat {
        let normalizedRect = rect.standardizedForEditor
        let dx = max(max(normalizedRect.minX - x, 0), x - normalizedRect.maxX)
        let dy = max(max(normalizedRect.minY - y, 0), y - normalizedRect.maxY)
        return hypot(dx, dy)
    }
}

private extension [CGPoint] {
    var totalDistance: CGFloat {
        guard count > 1 else {
            return 0
        }

        return zip(self, dropFirst()).reduce(0) { distance, points in
            distance + points.0.distance(to: points.1)
        }
    }
}

private extension [CGRect] {
    func sortedForSmartTextHighlight() -> [CGRect] {
        let normalizedRects = map(\.standardizedForEditor)

        return normalizedRects.sorted { firstRect, secondRect in
            let verticalDistance = abs(firstRect.midY - secondRect.midY)
            let rowTolerance = Swift.max(firstRect.height, secondRect.height) * 0.55

            if verticalDistance > rowTolerance {
                return firstRect.minY < secondRect.minY
            }

            return firstRect.minX < secondRect.minX
        }
    }
}
