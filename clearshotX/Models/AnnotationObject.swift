//
//  AnnotationObject.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Foundation

enum AnnotationObjectKind: String, CaseIterable, Identifiable {
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

enum AnnotationResizeHandle: String, CaseIterable {
    case startPoint
    case endPoint
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

enum AnnotationGeometry: Equatable {
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(CGRect)

    var bounds: CGRect {
        switch self {
        case let .arrow(start, end):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case let .rectangle(rect):
            return rect.standardizedForEditor
        }
    }

    func translated(by translation: CGSize) -> AnnotationGeometry {
        switch self {
        case let .arrow(start, end):
            return .arrow(
                start: CGPoint(x: start.x + translation.width, y: start.y + translation.height),
                end: CGPoint(x: end.x + translation.width, y: end.y + translation.height)
            )
        case let .rectangle(rect):
            return .rectangle(rect.offsetBy(dx: translation.width, dy: translation.height))
        }
    }

    func resized(using handle: AnnotationResizeHandle, to point: CGPoint) -> AnnotationGeometry {
        switch self {
        case let .arrow(start, end):
            switch handle {
            case .startPoint:
                return .arrow(start: point, end: end)
            case .endPoint:
                return .arrow(start: start, end: point)
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                return self
            }
        case let .rectangle(rect):
            let normalizedRect = rect.standardizedForEditor

            switch handle {
            case .topLeft:
                return .rectangle(
                    CGRect(
                        x: point.x,
                        y: point.y,
                        width: normalizedRect.maxX - point.x,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .topRight:
                return .rectangle(
                    CGRect(
                        x: normalizedRect.minX,
                        y: point.y,
                        width: point.x - normalizedRect.minX,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .bottomLeft:
                return .rectangle(
                    CGRect(
                        x: point.x,
                        y: normalizedRect.minY,
                        width: normalizedRect.maxX - point.x,
                        height: point.y - normalizedRect.minY
                    ).standardizedForEditor
                )
            case .bottomRight:
                return .rectangle(
                    CGRect(
                        x: normalizedRect.minX,
                        y: normalizedRect.minY,
                        width: point.x - normalizedRect.minX,
                        height: point.y - normalizedRect.minY
                    ).standardizedForEditor
                )
            case .startPoint, .endPoint:
                return self
            }
        }
    }
}

struct AnnotationStyle: Equatable {
    var strokeColor: NSColor = .controlAccentColor
    var fillColor: NSColor = .clear
    var lineWidth: CGFloat = 3
    var opacity: CGFloat = 1
}

struct AnnotationObject: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationObjectKind
    var geometry: AnnotationGeometry
    var style: AnnotationStyle

    var bounds: CGRect {
        geometry.bounds
    }

    init(
        id: UUID = UUID(),
        kind: AnnotationObjectKind,
        geometry: AnnotationGeometry,
        style: AnnotationStyle = AnnotationStyle()
    ) {
        self.id = id
        self.kind = kind
        self.geometry = geometry
        self.style = style
    }

    static func arrow(
        id: UUID = UUID(),
        start: CGPoint,
        end: CGPoint,
        style: AnnotationStyle
    ) -> AnnotationObject {
        AnnotationObject(
            id: id,
            kind: .arrow,
            geometry: .arrow(start: start, end: end),
            style: style
        )
    }

    static func rectangle(
        id: UUID = UUID(),
        rect: CGRect,
        style: AnnotationStyle
    ) -> AnnotationObject {
        AnnotationObject(
            id: id,
            kind: .rectangle,
            geometry: .rectangle(rect.standardizedForEditor),
            style: style
        )
    }

    func translated(by translation: CGSize) -> AnnotationObject {
        var object = self
        object.geometry = geometry.translated(by: translation)
        return object
    }

    func resized(using handle: AnnotationResizeHandle, to point: CGPoint) -> AnnotationObject {
        var object = self
        object.geometry = geometry.resized(using: handle, to: point)
        return object
    }
}

extension CGRect {
    var standardizedForEditor: CGRect {
        CGRect(
            x: width >= 0 ? minX : maxX,
            y: height >= 0 ? minY : maxY,
            width: abs(width),
            height: abs(height)
        )
    }
}
