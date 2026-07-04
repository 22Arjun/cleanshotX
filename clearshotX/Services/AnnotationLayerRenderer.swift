//
//  AnnotationLayerRenderer.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import QuartzCore

protocol AnnotationShapeRendering {
    var kind: AnnotationObjectKind { get }

    func makeLayer(for annotation: AnnotationObject) -> CAShapeLayer
    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool
    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect]
    func selectionPath(for annotation: AnnotationObject) -> CGPath
}

final class AnnotationRendererRegistry {
    private let renderers: [AnnotationShapeRendering]

    init(renderers: [AnnotationShapeRendering] = [
        ArrowAnnotationRenderer(),
        RectangleAnnotationRenderer()
    ]) {
        self.renderers = renderers
    }

    func renderer(for kind: AnnotationObjectKind) -> AnnotationShapeRendering? {
        renderers.first { renderer in
            renderer.kind == kind
        }
    }
}

final class AnnotationLayerRenderer {
    private let registry: AnnotationRendererRegistry

    init(registry: AnnotationRendererRegistry = AnnotationRendererRegistry()) {
        self.registry = registry
    }

    func render(
        annotations: [AnnotationObject],
        draftAnnotation: AnnotationObject?,
        selectedAnnotationID: UUID?,
        in containerLayer: CALayer,
        contentsScale: CGFloat,
        selectionHandleSize: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.sublayers = []

        for annotation in annotations {
            _ = addLayer(for: annotation, to: containerLayer, contentsScale: contentsScale)

            if annotation.id == selectedAnnotationID {
                addSelectionLayer(
                    for: annotation,
                    to: containerLayer,
                    contentsScale: contentsScale,
                    handleSize: selectionHandleSize
                )
            }
        }

        if let draftAnnotation {
            let draftLayer = addLayer(for: draftAnnotation, to: containerLayer, contentsScale: contentsScale)
            draftLayer.opacity = 0.82
        }

        CATransaction.commit()
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        registry.renderer(for: annotation.kind)?.resizeHandles(for: annotation, size: size) ?? [:]
    }

    private func addLayer(
        for annotation: AnnotationObject,
        to containerLayer: CALayer,
        contentsScale: CGFloat
    ) -> CAShapeLayer {
        let layer = registry.renderer(for: annotation.kind)?.makeLayer(for: annotation) ?? CAShapeLayer()
        layer.frame = containerLayer.bounds
        layer.contentsScale = contentsScale
        containerLayer.addSublayer(layer)
        return layer
    }

    private func addSelectionLayer(
        for annotation: AnnotationObject,
        to containerLayer: CALayer,
        contentsScale: CGFloat,
        handleSize: CGFloat
    ) {
        guard let renderer = registry.renderer(for: annotation.kind) else {
            return
        }

        let selectionLayer = CAShapeLayer()
        selectionLayer.frame = containerLayer.bounds
        selectionLayer.path = renderer.selectionPath(for: annotation)
        selectionLayer.fillColor = NSColor.clear.cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.lineDashPattern = [5, 4]
        selectionLayer.lineWidth = 1
        selectionLayer.contentsScale = contentsScale
        containerLayer.addSublayer(selectionLayer)

        for handleFrame in renderer.resizeHandles(for: annotation, size: handleSize).values {
            let handleLayer = CAShapeLayer()
            handleLayer.frame = containerLayer.bounds
            handleLayer.path = CGPath(
                roundedRect: handleFrame,
                cornerWidth: 2,
                cornerHeight: 2,
                transform: nil
            )
            handleLayer.fillColor = NSColor.white.cgColor
            handleLayer.strokeColor = NSColor.controlAccentColor.cgColor
            handleLayer.lineWidth = 1.5
            handleLayer.contentsScale = contentsScale
            containerLayer.addSublayer(handleLayer)
        }
    }
}

final class ArrowAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.arrow

    func makeLayer(for annotation: AnnotationObject) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = arrowPath(for: annotation)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = annotation.style.strokeColor.cgColor
        layer.lineWidth = annotation.style.lineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.opacity = Float(annotation.style.opacity)
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        guard case let .arrow(start, end) = annotation.geometry else {
            return false
        }

        let expandedTolerance = max(tolerance, annotation.style.lineWidth + 6)
        return point.distanceToLineSegment(start: start, end: end) <= expandedTolerance
            || resizeHandles(for: annotation, size: expandedTolerance * 1.4).values.contains { handle in
                handle.contains(point)
            }
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        guard case let .arrow(start, end) = annotation.geometry else {
            return [:]
        }

        return [
            .startPoint: handleRect(centeredAt: start, size: size),
            .endPoint: handleRect(centeredAt: end, size: size)
        ]
    }

    func selectionPath(for annotation: AnnotationObject) -> CGPath {
        arrowPath(for: annotation)
    }

    private func arrowPath(for annotation: AnnotationObject) -> CGPath {
        let path = CGMutablePath()

        guard case let .arrow(start, end) = annotation.geometry else {
            return path
        }

        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowHeadLength = max(14, annotation.style.lineWidth * 4.2)
        let arrowHeadSpread = CGFloat.pi / 7
        let leftPoint = CGPoint(
            x: end.x - arrowHeadLength * cos(angle - arrowHeadSpread),
            y: end.y - arrowHeadLength * sin(angle - arrowHeadSpread)
        )
        let rightPoint = CGPoint(
            x: end.x - arrowHeadLength * cos(angle + arrowHeadSpread),
            y: end.y - arrowHeadLength * sin(angle + arrowHeadSpread)
        )

        path.move(to: leftPoint)
        path.addLine(to: end)
        path.addLine(to: rightPoint)

        return path
    }
}

final class RectangleAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.rectangle

    func makeLayer(for annotation: AnnotationObject) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = rectanglePath(for: annotation)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = annotation.style.strokeColor.cgColor
        layer.lineWidth = annotation.style.lineWidth
        layer.lineJoin = .round
        layer.opacity = Float(annotation.style.opacity)
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        guard case let .rectangle(rect) = annotation.geometry else {
            return false
        }

        return rect.standardizedForEditor.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        guard case let .rectangle(rect) = annotation.geometry else {
            return [:]
        }

        let normalizedRect = rect.standardizedForEditor

        return [
            .topLeft: handleRect(centeredAt: CGPoint(x: normalizedRect.minX, y: normalizedRect.minY), size: size),
            .topRight: handleRect(centeredAt: CGPoint(x: normalizedRect.maxX, y: normalizedRect.minY), size: size),
            .bottomLeft: handleRect(centeredAt: CGPoint(x: normalizedRect.minX, y: normalizedRect.maxY), size: size),
            .bottomRight: handleRect(centeredAt: CGPoint(x: normalizedRect.maxX, y: normalizedRect.maxY), size: size)
        ]
    }

    func selectionPath(for annotation: AnnotationObject) -> CGPath {
        rectanglePath(for: annotation)
    }

    private func rectanglePath(for annotation: AnnotationObject) -> CGPath {
        guard case let .rectangle(rect) = annotation.geometry else {
            return CGMutablePath()
        }

        return CGPath(rect: rect.standardizedForEditor, transform: nil)
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

private extension CGPoint {
    func distanceToLineSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let segment = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let segmentLengthSquared = segment.dx * segment.dx + segment.dy * segment.dy

        guard segmentLengthSquared > 0 else {
            return hypot(x - start.x, y - start.y)
        }

        let rawT = ((x - start.x) * segment.dx + (y - start.y) * segment.dy) / segmentLengthSquared
        let t = min(1, max(0, rawT))
        let projectedPoint = CGPoint(
            x: start.x + t * segment.dx,
            y: start.y + t * segment.dy
        )

        return hypot(x - projectedPoint.x, y - projectedPoint.y)
    }
}
