//
//  EditorViewModel.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Combine
import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case oval
    case text
    case highlight
    case blurPixelate

    var id: String {
        rawValue
    }
}

struct EditorStrokeColorOption: Identifiable {
    let id: String
    let name: String
    let color: NSColor
}

enum EditorToolbarAction: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case oval
    case text
    case highlight
    case blurPixelate
    case undo
    case redo
    case copy
    case save

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .arrow:
            "Arrow"
        case .rectangle:
            "Rectangle"
        case .oval:
            "Oval"
        case .text:
            "Text"
        case .highlight:
            "Highlight"
        case .blurPixelate:
            "Blur/Pixelate"
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
        case .arrow:
            "arrow.up.right"
        case .rectangle:
            "rectangle"
        case .oval:
            "oval"
        case .text:
            "textformat"
        case .highlight:
            "highlighter"
        case .blurPixelate:
            "square.grid.3x3.fill"
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
        case .arrow:
            "A"
        case .rectangle:
            "R"
        case .oval:
            "O"
        case .text:
            "T"
        case .highlight:
            "H"
        case .blurPixelate:
            "B"
        case .undo:
            "⌘Z"
        case .redo:
            "⇧⌘Z"
        case .copy:
            "C"
        case .save:
            "S"
        }
    }

    var tool: EditorTool? {
        switch self {
        case .arrow:
            .arrow
        case .rectangle:
            .rectangle
        case .oval:
            .oval
        case .text:
            .text
        case .highlight:
            .highlight
        case .blurPixelate:
            .blurPixelate
        case .undo, .redo, .copy, .save:
            nil
        }
    }

    static let drawingTools: [EditorToolbarAction] = [
        .arrow,
        .rectangle,
        .oval,
        .text,
        .highlight,
        .blurPixelate
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
        EditorStrokeColorOption(id: "yellow", name: "Yellow", color: .systemYellow),
        EditorStrokeColorOption(id: "green", name: "Green", color: .systemGreen),
        EditorStrokeColorOption(id: "blue", name: "Blue", color: .systemBlue),
        EditorStrokeColorOption(id: "white", name: "White", color: .white),
        EditorStrokeColorOption(id: "black", name: "Black", color: .black)
    ]

    static let strokeWidthOptions: [CGFloat] = [2, 4, 6, 8]
    static let textSizeOptions: [CGFloat] = [16, 24, 32, 44]
    static let opacityOptions: [CGFloat] = [1, 0.75, 0.5]

    let id = UUID()
    let image: NSImage
    let sourceFileURL: URL?

    @Published private(set) var annotationObjects: [AnnotationObject] = []
    @Published private(set) var activeTool: EditorTool?
    @Published private(set) var selectedAnnotationID: UUID?
    @Published private(set) var draftAnnotationObject: AnnotationObject?
    @Published private(set) var selectedStrokeColorID = "red"
    @Published private(set) var selectedStrokeWidth: CGFloat = 4
    @Published private(set) var selectedTextSize: CGFloat = 24
    @Published private(set) var selectedOpacity: CGFloat = 1
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private let annotationInteractionService: AnnotationInteractionServicing
    private var activeDragSession: EditorDragSession?
    private var textEditingInitialState: EditorHistoryState?
    private var undoStack: [EditorHistoryState] = []
    private var redoStack: [EditorHistoryState] = []
    private let historyLimit = 80

    var selectedStrokeColor: NSColor {
        Self.strokeColorOptions.first { option in
            option.id == selectedStrokeColorID
        }?.color ?? .systemRed
    }

    init(
        image: NSImage,
        sourceFileURL: URL? = nil,
        annotationInteractionService: AnnotationInteractionServicing? = nil
    ) {
        self.image = image
        self.sourceFileURL = sourceFileURL
        self.annotationInteractionService = annotationInteractionService ?? AnnotationInteractionService()
    }

    func perform(_ action: EditorToolbarAction) {
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
        case .arrow, .rectangle, .oval, .text, .highlight, .blurPixelate:
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
        case .arrow, .rectangle, .oval, .text, .highlight, .blurPixelate, .copy, .save:
            true
        }
    }

    func setStrokeColor(_ option: EditorStrokeColorOption) {
        let previousState = currentHistoryState()
        selectedStrokeColorID = option.id

        if applyActiveStyleToSelectedAnnotation() {
            recordUndoState(previousState)
        }
    }

    func setStrokeWidth(_ width: CGFloat) {
        let previousState = currentHistoryState()
        selectedStrokeWidth = width

        if applyActiveStyleToSelectedAnnotation() {
            recordUndoState(previousState)
        }
    }

    func setTextSize(_ size: CGFloat) {
        let previousState = currentHistoryState()
        selectedTextSize = size

        if applyActiveStyleToSelectedAnnotation(only: .text) {
            recordUndoState(previousState)
        }
    }

    func setOpacity(_ opacity: CGFloat) {
        let previousState = currentHistoryState()
        selectedOpacity = opacity

        if applyActiveStyleToSelectedAnnotation() {
            recordUndoState(previousState)
        }
    }

    func isStrokeColorSelected(_ option: EditorStrokeColorOption) -> Bool {
        selectedStrokeColorID == option.id
    }

    func isStrokeWidthSelected(_ width: CGFloat) -> Bool {
        selectedStrokeWidth == width
    }

    func isTextSizeSelected(_ size: CGFloat) -> Bool {
        selectedTextSize == size
    }

    func isOpacitySelected(_ opacity: CGFloat) -> Bool {
        selectedOpacity == opacity
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
        return annotation.id
    }

    @discardableResult
    func beginTextEditing(annotationID: UUID) -> Bool {
        guard annotation(withID: annotationID)?.kind == .text else {
            return false
        }

        selectedAnnotationID = annotationID
        draftAnnotationObject = nil
        activeDragSession = nil
        textEditingInitialState = currentHistoryState()
        return true
    }

    func updateEditingText(annotationID: UUID, text: String, rect: CGRect) {
        guard let annotation = annotation(withID: annotationID),
              annotation.kind == .text
        else {
            return
        }

        updateAnnotation(
            withID: annotationID,
            to: annotation.updatingText(text, rect: rect)
        )
    }

    func endTextEditing(annotationID: UUID) {
        guard let initialHistoryState = textEditingInitialState else {
            return
        }

        if let annotation = annotation(withID: annotationID),
           case let .text(_, text) = annotation.geometry,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotationObjects.removeAll { annotation in
                annotation.id == annotationID
            }

            if selectedAnnotationID == annotationID {
                selectedAnnotationID = nil
            }
        }

        textEditingInitialState = nil
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

        switch hitResult {
        case let .resize(annotationID, handle):
            guard let annotation = annotation(withID: annotationID) else {
                return
            }

            selectedAnnotationID = annotationID
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
            activeDragSession = .moving(
                annotationID: annotationID,
                startPoint: point,
                originalAnnotation: annotation,
                initialHistoryState: currentHistoryState()
            )
        case .empty:
            selectedAnnotationID = nil

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
            activeDragSession = .drawing(tool: activeTool, startPoint: point)
        }
    }

    func updateCanvasInteraction(to point: CGPoint) {
        guard let activeDragSession else {
            return
        }

        switch activeDragSession {
        case let .drawing(tool, startPoint):
            draftAnnotationObject = annotationInteractionService.makeAnnotation(
                tool: tool,
                startPoint: startPoint,
                endPoint: point,
                style: activeAnnotationStyle()
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
                annotationObjects.append(draftAnnotationObject)
                selectedAnnotationID = draftAnnotationObject.id
                recordUndoState(previousState)
            }
        case let .moving(_, _, _, initialHistoryState),
             let .resizing(_, _, _, initialHistoryState):
            commitHistoryTransition(from: initialHistoryState)
        case .none:
            break
        }

        draftAnnotationObject = nil
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
        activeDragSession = nil
    }

    func handleShortcut(_ shortcut: String) -> Bool {
        switch shortcut.lowercased() {
        case "a":
            selectTool(.arrow)
            return true
        case "r":
            selectTool(.rectangle)
            return true
        case "o":
            selectTool(.oval)
            return true
        case "t":
            selectTool(.text)
            return true
        case "h":
            selectTool(.highlight)
            return true
        case "b":
            selectTool(.blurPixelate)
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
        logStub("Copy requested")
    }

    private func save() {
        logStub("Save requested")
    }

    private func logStub(_ message: String) {
        print("ClearshotX Editor stub: \(message)")
    }

    private func selectTool(_ tool: EditorTool) {
        activeTool = tool
        selectedAnnotationID = nil
        draftAnnotationObject = nil
        activeDragSession = nil
    }

    private func activeAnnotationStyle() -> AnnotationStyle {
        AnnotationStyle(
            strokeColor: selectedStrokeColor,
            fillColor: .clear,
            lineWidth: selectedStrokeWidth,
            opacity: selectedOpacity,
            fontSize: selectedTextSize,
            effectIntensity: selectedStrokeWidth
        )
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
            annotationObjects: annotationObjects,
            selectedAnnotationID: selectedAnnotationID
        )
    }

    private func restore(_ state: EditorHistoryState) {
        annotationObjects = state.annotationObjects
        selectedAnnotationID = state.selectedAnnotationID
        draftAnnotationObject = nil
        activeDragSession = nil
        textEditingInitialState = nil
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
    case drawing(tool: EditorTool, startPoint: CGPoint)
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

private struct EditorHistoryState: Equatable {
    let annotationObjects: [AnnotationObject]
    let selectedAnnotationID: UUID?
}
