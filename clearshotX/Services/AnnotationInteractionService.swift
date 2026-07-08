//
//  AnnotationInteractionService.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Foundation

enum AnnotationHitResult: Equatable {
    case resize(annotationID: UUID, handle: AnnotationResizeHandle)
    case annotation(UUID)
    case empty
}

protocol AnnotationInteractionServicing {
    func makeAnnotation(
        tool: EditorTool,
        startPoint: CGPoint,
        endPoint: CGPoint,
        style: AnnotationStyle
    ) -> AnnotationObject?

    func shouldCommit(_ annotation: AnnotationObject) -> Bool
    func hitTest(
        point: CGPoint,
        annotations: [AnnotationObject],
        selectedAnnotationID: UUID?,
        tolerance: CGFloat
    ) -> AnnotationHitResult
}

final class AnnotationInteractionService: AnnotationInteractionServicing {
    private let rendererRegistry: AnnotationRendererRegistry

    init(rendererRegistry: AnnotationRendererRegistry = AnnotationRendererRegistry()) {
        self.rendererRegistry = rendererRegistry
    }

    func makeAnnotation(
        tool: EditorTool,
        startPoint: CGPoint,
        endPoint: CGPoint,
        style: AnnotationStyle
    ) -> AnnotationObject? {
        switch tool {
        case .arrow:
            return AnnotationObject.arrow(start: startPoint, end: endPoint, style: style)
        case .line:
            return AnnotationObject.line(start: startPoint, end: endPoint, style: style)
        case .numbering:
            return nil
        case .rectangle:
            return AnnotationObject.rectangle(
                rect: CGRect(
                    x: startPoint.x,
                    y: startPoint.y,
                    width: endPoint.x - startPoint.x,
                    height: endPoint.y - startPoint.y
                ),
                style: style
            )
        case .filledRectangle:
            return AnnotationObject.filledRectangle(
                rect: CGRect(
                    x: startPoint.x,
                    y: startPoint.y,
                    width: endPoint.x - startPoint.x,
                    height: endPoint.y - startPoint.y
                ),
                style: style
            )
        case .oval:
            return AnnotationObject.oval(
                rect: CGRect(
                    x: startPoint.x,
                    y: startPoint.y,
                    width: endPoint.x - startPoint.x,
                    height: endPoint.y - startPoint.y
                ),
                style: style
            )
        case .highlight:
            return AnnotationObject.highlight(
                rect: CGRect(
                    x: startPoint.x,
                    y: startPoint.y,
                    width: endPoint.x - startPoint.x,
                    height: endPoint.y - startPoint.y
                ),
                style: style
            )
        case .blurPixelate:
            return AnnotationObject.blurPixelate(
                rect: CGRect(
                    x: startPoint.x,
                    y: startPoint.y,
                    width: endPoint.x - startPoint.x,
                    height: endPoint.y - startPoint.y
                ),
                style: style
            )
        case .text, .crop:
            return nil
        case .textHighlight:
            return AnnotationObject.textHighlight(
                rect: textHighlightRect(
                    from: startPoint,
                    to: endPoint,
                    lineWidth: style.lineWidth
                ),
                style: style
            )
        }
    }

    func shouldCommit(_ annotation: AnnotationObject) -> Bool {
        switch annotation.geometry {
        case let .arrow(start, end):
            return hypot(end.x - start.x, end.y - start.y) >= 8
        case let .rectangle(rect), let .oval(rect), let .highlight(rect), let .blurPixelate(rect):
            return rect.standardizedForEditor.width >= 8 && rect.standardizedForEditor.height >= 8
        case let .textHighlight(rect):
            return rect.standardizedForEditor.width >= 12
        case let .text(_, text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func hitTest(
        point: CGPoint,
        annotations: [AnnotationObject],
        selectedAnnotationID: UUID?,
        tolerance: CGFloat
    ) -> AnnotationHitResult {
        if let selectedAnnotationID,
           let selectedAnnotation = annotations.first(where: { annotation in
               annotation.id == selectedAnnotationID
           }),
           let renderer = rendererRegistry.renderer(for: selectedAnnotation.kind) {
            for (handle, frame) in renderer.resizeHandles(for: selectedAnnotation, size: 12) where frame.contains(point) {
                return .resize(annotationID: selectedAnnotationID, handle: handle)
            }
        }

        for annotation in annotations.sortedForEditorHitTesting() {
            guard let renderer = rendererRegistry.renderer(for: annotation.kind) else {
                continue
            }

            if renderer.hitTest(point, annotation: annotation, tolerance: tolerance) {
                return .annotation(annotation.id)
            }
        }

        return .empty
    }

    private func textHighlightRect(from startPoint: CGPoint, to endPoint: CGPoint, lineWidth: CGFloat) -> CGRect {
        let normalizedWidth = abs(endPoint.x - startPoint.x)
        let markerHeight = max(12, lineWidth * 4.5)
        let verticalTravel = abs(endPoint.y - startPoint.y)
        let height = max(markerHeight, min(markerHeight * 1.45, verticalTravel))
        let midY = (startPoint.y + endPoint.y) / 2

        return CGRect(
            x: min(startPoint.x, endPoint.x),
            y: midY - height / 2,
            width: normalizedWidth,
            height: height
        )
        .standardizedForEditor
    }
}

private extension [AnnotationObject] {
    func sortedForEditorHitTesting() -> [AnnotationObject] {
        let newestFirst = reversed()

        return newestFirst.filter { annotation in
            annotation.kind != .highlight && annotation.kind != .blurPixelate
        } + newestFirst.filter { annotation in
            annotation.kind == .blurPixelate
        } + newestFirst.filter { annotation in
            annotation.kind == .highlight
        }
    }
}
