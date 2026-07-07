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
    case oval(CGRect)
    case text(rect: CGRect, text: String)
    case highlight(CGRect)
    case blurPixelate(CGRect)

    var bounds: CGRect {
        switch self {
        case let .arrow(start, end):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case let .rectangle(rect), let .oval(rect), let .highlight(rect), let .blurPixelate(rect):
            return rect.standardizedForEditor
        case let .text(rect, _):
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
        case let .oval(rect):
            return .oval(rect.offsetBy(dx: translation.width, dy: translation.height))
        case let .text(rect, text):
            return .text(rect: rect.offsetBy(dx: translation.width, dy: translation.height), text: text)
        case let .highlight(rect):
            return .highlight(rect.offsetBy(dx: translation.width, dy: translation.height))
        case let .blurPixelate(rect):
            return .blurPixelate(rect.offsetBy(dx: translation.width, dy: translation.height))
        }
    }

    func rotatedClockwise(in canvasSize: CGSize) -> AnnotationGeometry {
        switch self {
        case let .arrow(start, end):
            return .arrow(
                start: start.rotatedClockwise(in: canvasSize),
                end: end.rotatedClockwise(in: canvasSize)
            )
        case let .rectangle(rect):
            return .rectangle(rect.transformedByMappingCorners { $0.rotatedClockwise(in: canvasSize) })
        case let .oval(rect):
            return .oval(rect.transformedByMappingCorners { $0.rotatedClockwise(in: canvasSize) })
        case let .text(rect, text):
            return .text(rect: rect.transformedByMappingCorners { $0.rotatedClockwise(in: canvasSize) }, text: text)
        case let .highlight(rect):
            return .highlight(rect.transformedByMappingCorners { $0.rotatedClockwise(in: canvasSize) })
        case let .blurPixelate(rect):
            return .blurPixelate(rect.transformedByMappingCorners { $0.rotatedClockwise(in: canvasSize) })
        }
    }

    func flippedHorizontally(in canvasSize: CGSize) -> AnnotationGeometry {
        switch self {
        case let .arrow(start, end):
            return .arrow(
                start: start.flippedHorizontally(in: canvasSize),
                end: end.flippedHorizontally(in: canvasSize)
            )
        case let .rectangle(rect):
            return .rectangle(rect.transformedByMappingCorners { $0.flippedHorizontally(in: canvasSize) })
        case let .oval(rect):
            return .oval(rect.transformedByMappingCorners { $0.flippedHorizontally(in: canvasSize) })
        case let .text(rect, text):
            return .text(rect: rect.transformedByMappingCorners { $0.flippedHorizontally(in: canvasSize) }, text: text)
        case let .highlight(rect):
            return .highlight(rect.transformedByMappingCorners { $0.flippedHorizontally(in: canvasSize) })
        case let .blurPixelate(rect):
            return .blurPixelate(rect.transformedByMappingCorners { $0.flippedHorizontally(in: canvasSize) })
        }
    }

    func flippedVertically(in canvasSize: CGSize) -> AnnotationGeometry {
        switch self {
        case let .arrow(start, end):
            return .arrow(
                start: start.flippedVertically(in: canvasSize),
                end: end.flippedVertically(in: canvasSize)
            )
        case let .rectangle(rect):
            return .rectangle(rect.transformedByMappingCorners { $0.flippedVertically(in: canvasSize) })
        case let .oval(rect):
            return .oval(rect.transformedByMappingCorners { $0.flippedVertically(in: canvasSize) })
        case let .text(rect, text):
            return .text(rect: rect.transformedByMappingCorners { $0.flippedVertically(in: canvasSize) }, text: text)
        case let .highlight(rect):
            return .highlight(rect.transformedByMappingCorners { $0.flippedVertically(in: canvasSize) })
        case let .blurPixelate(rect):
            return .blurPixelate(rect.transformedByMappingCorners { $0.flippedVertically(in: canvasSize) })
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
        case let .oval(rect):
            let normalizedRect = rect.standardizedForEditor

            switch handle {
            case .topLeft:
                return .oval(
                    CGRect(
                        x: point.x,
                        y: point.y,
                        width: normalizedRect.maxX - point.x,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .topRight:
                return .oval(
                    CGRect(
                        x: normalizedRect.minX,
                        y: point.y,
                        width: point.x - normalizedRect.minX,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .bottomLeft:
                return .oval(
                    CGRect(
                        x: point.x,
                        y: normalizedRect.minY,
                        width: normalizedRect.maxX - point.x,
                        height: point.y - normalizedRect.minY
                    ).standardizedForEditor
                )
            case .bottomRight:
                return .oval(
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
        case let .text(rect, text):
            let normalizedRect = rect.standardizedForEditor

            switch handle {
            case .topLeft:
                return .text(
                    rect: CGRect(
                        x: point.x,
                        y: point.y,
                        width: normalizedRect.maxX - point.x,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor,
                    text: text
                )
            case .topRight:
                return .text(
                    rect: CGRect(
                        x: normalizedRect.minX,
                        y: point.y,
                        width: point.x - normalizedRect.minX,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor,
                    text: text
                )
            case .bottomLeft:
                return .text(
                    rect: CGRect(
                        x: point.x,
                        y: normalizedRect.minY,
                        width: normalizedRect.maxX - point.x,
                        height: point.y - normalizedRect.minY
                    ).standardizedForEditor,
                    text: text
                )
            case .bottomRight:
                return .text(
                    rect: CGRect(
                        x: normalizedRect.minX,
                        y: normalizedRect.minY,
                        width: point.x - normalizedRect.minX,
                        height: point.y - normalizedRect.minY
                    ).standardizedForEditor,
                    text: text
                )
            case .startPoint, .endPoint:
                return self
            }
        case let .highlight(rect):
            let normalizedRect = rect.standardizedForEditor

            switch handle {
            case .topLeft:
                return .highlight(
                    CGRect(
                        x: point.x,
                        y: point.y,
                        width: normalizedRect.maxX - point.x,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .topRight:
                return .highlight(
                    CGRect(
                        x: normalizedRect.minX,
                        y: point.y,
                        width: point.x - normalizedRect.minX,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .bottomLeft:
                return .highlight(
                    CGRect(
                        x: point.x,
                        y: normalizedRect.minY,
                        width: normalizedRect.maxX - point.x,
                        height: point.y - normalizedRect.minY
                    ).standardizedForEditor
                )
            case .bottomRight:
                return .highlight(
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
        case let .blurPixelate(rect):
            let normalizedRect = rect.standardizedForEditor

            switch handle {
            case .topLeft:
                return .blurPixelate(
                    CGRect(
                        x: point.x,
                        y: point.y,
                        width: normalizedRect.maxX - point.x,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .topRight:
                return .blurPixelate(
                    CGRect(
                        x: normalizedRect.minX,
                        y: point.y,
                        width: point.x - normalizedRect.minX,
                        height: normalizedRect.maxY - point.y
                    ).standardizedForEditor
                )
            case .bottomLeft:
                return .blurPixelate(
                    CGRect(
                        x: point.x,
                        y: normalizedRect.minY,
                        width: normalizedRect.maxX - point.x,
                        height: point.y - normalizedRect.minY
                    ).standardizedForEditor
                )
            case .bottomRight:
                return .blurPixelate(
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
    var fontSize: CGFloat = 24
    var effectIntensity: CGFloat = 4
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

    static func oval(
        id: UUID = UUID(),
        rect: CGRect,
        style: AnnotationStyle
    ) -> AnnotationObject {
        AnnotationObject(
            id: id,
            kind: .oval,
            geometry: .oval(rect.standardizedForEditor),
            style: style
        )
    }

    static func text(
        id: UUID = UUID(),
        rect: CGRect,
        text: String,
        style: AnnotationStyle
    ) -> AnnotationObject {
        AnnotationObject(
            id: id,
            kind: .text,
            geometry: .text(rect: rect.standardizedForEditor, text: text),
            style: style
        )
    }

    static func highlight(
        id: UUID = UUID(),
        rect: CGRect,
        style: AnnotationStyle
    ) -> AnnotationObject {
        AnnotationObject(
            id: id,
            kind: .highlight,
            geometry: .highlight(rect.standardizedForEditor),
            style: style
        )
    }

    static func blurPixelate(
        id: UUID = UUID(),
        rect: CGRect,
        style: AnnotationStyle
    ) -> AnnotationObject {
        AnnotationObject(
            id: id,
            kind: .blurPixelate,
            geometry: .blurPixelate(rect.standardizedForEditor),
            style: style
        )
    }

    func translated(by translation: CGSize) -> AnnotationObject {
        var object = self
        object.geometry = geometry.translated(by: translation)
        return object
    }

    func rotatedClockwise(in canvasSize: CGSize) -> AnnotationObject {
        var object = self
        object.geometry = geometry.rotatedClockwise(in: canvasSize)
        return object
    }

    func flippedHorizontally(in canvasSize: CGSize) -> AnnotationObject {
        var object = self
        object.geometry = geometry.flippedHorizontally(in: canvasSize)
        return object
    }

    func flippedVertically(in canvasSize: CGSize) -> AnnotationObject {
        var object = self
        object.geometry = geometry.flippedVertically(in: canvasSize)
        return object
    }

    func resized(using handle: AnnotationResizeHandle, to point: CGPoint) -> AnnotationObject {
        var object = self
        object.geometry = geometry.resized(using: handle, to: point)
        return object
    }

    func applyingStyle(_ style: AnnotationStyle) -> AnnotationObject {
        var object = self
        object.style = style
        return object
    }

    func updatingText(_ text: String, rect: CGRect? = nil) -> AnnotationObject {
        guard case let .text(currentRect, _) = geometry else {
            return self
        }

        var object = self
        object.geometry = .text(rect: (rect ?? currentRect).standardizedForEditor, text: text)
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

    func transformedByMappingCorners(_ transform: (CGPoint) -> CGPoint) -> CGRect {
        let rect = standardizedForEditor
        let transformedCorners = [
            transform(CGPoint(x: rect.minX, y: rect.minY)),
            transform(CGPoint(x: rect.maxX, y: rect.minY)),
            transform(CGPoint(x: rect.maxX, y: rect.maxY)),
            transform(CGPoint(x: rect.minX, y: rect.maxY))
        ]
        let minX = transformedCorners.map(\.x).min() ?? 0
        let minY = transformedCorners.map(\.y).min() ?? 0
        let maxX = transformedCorners.map(\.x).max() ?? 0
        let maxY = transformedCorners.map(\.y).max() ?? 0

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .standardizedForEditor
    }
}

private extension CGPoint {
    func rotatedClockwise(in canvasSize: CGSize) -> CGPoint {
        CGPoint(x: canvasSize.height - y, y: x)
    }

    func flippedHorizontally(in canvasSize: CGSize) -> CGPoint {
        CGPoint(x: canvasSize.width - x, y: y)
    }

    func flippedVertically(in canvasSize: CGSize) -> CGPoint {
        CGPoint(x: x, y: canvasSize.height - y)
    }
}
