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
            "Z"
        case .redo:
            "Y"
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

    let id = UUID()
    let image: NSImage
    let sourceFileURL: URL?

    @Published private(set) var annotationObjects: [AnnotationObject] = []
    @Published private(set) var activeTool: EditorTool?
    @Published private(set) var selectedAnnotationID: UUID?
    @Published private(set) var draftAnnotationObject: AnnotationObject?
    @Published private(set) var selectedStrokeColorID = "red"
    @Published private(set) var selectedStrokeWidth: CGFloat = 4

    private let annotationInteractionService: AnnotationInteractionServicing
    private var activeDragSession: EditorDragSession?

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

    func setStrokeColor(_ option: EditorStrokeColorOption) {
        selectedStrokeColorID = option.id
    }

    func setStrokeWidth(_ width: CGFloat) {
        selectedStrokeWidth = width
    }

    func isStrokeColorSelected(_ option: EditorStrokeColorOption) -> Bool {
        selectedStrokeColorID == option.id
    }

    func isStrokeWidthSelected(_ width: CGFloat) -> Bool {
        selectedStrokeWidth == width
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
                originalAnnotation: annotation
            )
        case let .annotation(annotationID):
            guard let annotation = annotation(withID: annotationID) else {
                return
            }

            selectedAnnotationID = annotationID
            activeDragSession = .moving(
                annotationID: annotationID,
                startPoint: point,
                originalAnnotation: annotation
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
        case let .moving(annotationID, startPoint, originalAnnotation):
            let translation = CGSize(
                width: point.x - startPoint.x,
                height: point.y - startPoint.y
            )
            updateAnnotation(
                withID: annotationID,
                to: originalAnnotation.translated(by: translation)
            )
        case let .resizing(annotationID, handle, originalAnnotation):
            updateAnnotation(
                withID: annotationID,
                to: originalAnnotation.resized(using: handle, to: point)
            )
        }
    }

    func endCanvasInteraction() {
        if let draftAnnotationObject,
           annotationInteractionService.shouldCommit(draftAnnotationObject) {
            annotationObjects.append(draftAnnotationObject)
            selectedAnnotationID = draftAnnotationObject.id
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

        annotationObjects.removeAll { annotation in
            annotation.id == selectedAnnotationID
        }
        self.selectedAnnotationID = nil
        draftAnnotationObject = nil
        activeDragSession = nil
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
        default:
            return false
        }
    }

    private func undo() {
        logStub("Undo requested")
    }

    private func redo() {
        logStub("Redo requested")
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
            opacity: 1
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
}

private enum EditorDragSession {
    case drawing(tool: EditorTool, startPoint: CGPoint)
    case moving(annotationID: UUID, startPoint: CGPoint, originalAnnotation: AnnotationObject)
    case resizing(annotationID: UUID, handle: AnnotationResizeHandle, originalAnnotation: AnnotationObject)
}
