//
//  AnnotationLayerRenderer.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import CoreImage
import QuartzCore

struct AnnotationRenderContext {
    let sourceImage: CGImage?
    let canvasSize: CGSize
}

protocol AnnotationShapeRendering {
    var kind: AnnotationObjectKind { get }

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer
    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool
    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect]
    func selectionPath(for annotation: AnnotationObject) -> CGPath
}

final class AnnotationRendererRegistry {
    private let renderers: [AnnotationShapeRendering]

    init(renderers: [AnnotationShapeRendering] = [
        ArrowAnnotationRenderer(),
        LineAnnotationRenderer(),
        NumberingAnnotationRenderer(),
        RectangleAnnotationRenderer(),
        FilledRectangleAnnotationRenderer(),
        OvalAnnotationRenderer(),
        HighlightAnnotationRenderer(),
        BlurPixelateAnnotationRenderer(),
        TextAnnotationRenderer()
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
        sourceImage: CGImage?,
        in containerLayer: CALayer,
        contentsScale: CGFloat,
        selectionHandleSize: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.sublayers = []

        let renderContext = AnnotationRenderContext(
            sourceImage: sourceImage,
            canvasSize: containerLayer.bounds.size
        )
        let committedAnnotations = draftAnnotation?.kind == .highlight
            ? annotations.filter { annotation in annotation.kind != .highlight }
            : annotations
        let visualAnnotations = (committedAnnotations + (draftAnnotation.map { [$0] } ?? []))
            .sortedForEditorRendering()

        for annotation in visualAnnotations {
            let layer = addLayer(
                for: annotation,
                to: containerLayer,
                context: renderContext,
                contentsScale: contentsScale
            )

            if annotation.id == draftAnnotation?.id,
               annotation.kind != .highlight,
               annotation.kind != .blurPixelate {
                layer.opacity = 0.82
            }
        }

        if let selectedAnnotation = annotations.first(where: { annotation in
            annotation.id == selectedAnnotationID
        }) {
            addSelectionLayer(
                for: selectedAnnotation,
                to: containerLayer,
                contentsScale: contentsScale,
                handleSize: selectionHandleSize
            )
        }

        CATransaction.commit()
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        registry.renderer(for: annotation.kind)?.resizeHandles(for: annotation, size: size) ?? [:]
    }

    private func addLayer(
        for annotation: AnnotationObject,
        to containerLayer: CALayer,
        context: AnnotationRenderContext,
        contentsScale: CGFloat
    ) -> CALayer {
        let layer = registry.renderer(for: annotation.kind)?.makeLayer(for: annotation, context: context) ?? CALayer()

        if layer.frame == .zero {
            layer.frame = containerLayer.bounds
        }

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

private extension [AnnotationObject] {
    func sortedForEditorRendering() -> [AnnotationObject] {
        filter { annotation in
            annotation.kind == .blurPixelate
        } + filter { annotation in
            annotation.kind == .highlight
        } + filter { annotation in
            annotation.kind != .blurPixelate && annotation.kind != .highlight
        }
    }
}

final class ArrowAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.arrow

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        let layer = CAShapeLayer()
        layer.path = arrowPath(for: annotation)
        layer.fillColor = annotation.style.strokeColor.cgColor
        layer.strokeColor = NSColor.clear.cgColor
        layer.lineWidth = 0
        layer.lineJoin = .round
        layer.allowsEdgeAntialiasing = true
        layer.opacity = Float(annotation.style.opacity)
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        guard case let .arrow(start, end) = annotation.geometry else {
            return false
        }

        let expandedTolerance = max(tolerance, annotation.style.lineWidth + 6)
        return arrowPath(for: annotation).contains(point)
            || point.distanceToLineSegment(start: start, end: end) <= expandedTolerance
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
        switch annotation.style.arrowStyle {
        case .standard:
            standardArrowPath(for: annotation)
        case .fancy:
            fancyArrowPath(for: annotation)
        }
    }

    private func standardArrowPath(for annotation: AnnotationObject) -> CGPath {
        let path = CGMutablePath()

        guard case let .arrow(start, end) = annotation.geometry else {
            return path
        }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = hypot(deltaX, deltaY)
        let unit = length > 0.5
            ? CGVector(dx: deltaX / length, dy: deltaY / length)
            : CGVector(dx: 1, dy: 0)
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)

        let selectedWidth = max(1, annotation.style.lineWidth)
        let tailWidth = max(5.5, selectedWidth * 1.45)
        let tailHalfWidth = tailWidth / 2
        let neckWidth = max(18, selectedWidth * 4.1)
        let neckHalfWidth = neckWidth / 2
        let headWidth = max(68, neckWidth * 3.35)
        let headHalfWidth = headWidth / 2
        let headLength = max(58, headWidth * 0.82)
        let minimumShaftLength = max(36, neckWidth * 3.2)
        let renderLength = max(length, headLength + minimumShaftLength)
        let renderStart = length >= renderLength
            ? start
            : offset(end, along: unit, distance: -renderLength)
        let headBaseCenter = offset(end, along: unit, distance: -headLength)
        let neckCenter = headBaseCenter

        let tailLeft = offset(renderStart, along: perpendicular, distance: tailHalfWidth)
        let tailRight = offset(renderStart, along: perpendicular, distance: -tailHalfWidth)
        let tailCapControlLeft = offset(
            offset(renderStart, along: unit, distance: -tailHalfWidth * 1.35),
            along: perpendicular,
            distance: tailHalfWidth
        )
        let tailCapControlRight = offset(
            offset(renderStart, along: unit, distance: -tailHalfWidth * 1.35),
            along: perpendicular,
            distance: -tailHalfWidth
        )

        let leftNeck = offset(neckCenter, along: perpendicular, distance: neckHalfWidth)
        let rightNeck = offset(neckCenter, along: perpendicular, distance: -neckHalfWidth)
        let leftHeadBase = offset(headBaseCenter, along: perpendicular, distance: headHalfWidth)
        let rightHeadBase = offset(headBaseCenter, along: perpendicular, distance: -headHalfWidth)
        let baseCornerRadius = min(headHalfWidth * 0.16, max(8, neckWidth * 0.34))
        let leftBaseInner = offset(headBaseCenter, along: perpendicular, distance: neckHalfWidth)
        let rightBaseInner = offset(headBaseCenter, along: perpendicular, distance: -neckHalfWidth)
        let leftBaseCornerStart = offset(leftHeadBase, along: perpendicular, distance: -baseCornerRadius)
        let leftBaseCornerEnd = offset(
            offset(leftHeadBase, along: unit, distance: baseCornerRadius * 0.82),
            along: perpendicular,
            distance: -baseCornerRadius * 0.34
        )
        let rightBaseCornerStart = offset(
            offset(rightHeadBase, along: unit, distance: baseCornerRadius * 0.82),
            along: perpendicular,
            distance: baseCornerRadius * 0.34
        )
        let rightBaseCornerEnd = offset(rightHeadBase, along: perpendicular, distance: baseCornerRadius)
        let tipRoundness = min(headLength * 0.12, max(5.5, neckWidth * 0.22))
        let roundedTipLeft = offset(
            offset(end, along: unit, distance: -tipRoundness),
            along: perpendicular,
            distance: tipRoundness * 0.38
        )
        let roundedTipRight = offset(
            offset(end, along: unit, distance: -tipRoundness),
            along: perpendicular,
            distance: -tipRoundness * 0.38
        )

        let shaftLength = max(1, hypot(neckCenter.x - renderStart.x, neckCenter.y - renderStart.y))
        let leftShaftControlA = offset(
            offset(renderStart, along: unit, distance: shaftLength * 0.34),
            along: perpendicular,
            distance: tailHalfWidth * 1.08
        )
        let leftShaftControlB = offset(
            offset(neckCenter, along: unit, distance: -shaftLength * 0.24),
            along: perpendicular,
            distance: neckHalfWidth * 0.82
        )
        let rightShaftControlA = offset(
            offset(neckCenter, along: unit, distance: -shaftLength * 0.24),
            along: perpendicular,
            distance: -neckHalfWidth * 0.82
        )
        let rightShaftControlB = offset(
            offset(renderStart, along: unit, distance: shaftLength * 0.34),
            along: perpendicular,
            distance: -tailHalfWidth * 1.08
        )

        path.move(to: tailLeft)
        path.addCurve(to: leftNeck, control1: leftShaftControlA, control2: leftShaftControlB)
        path.addLine(to: leftBaseInner)
        path.addLine(to: leftBaseCornerStart)
        path.addQuadCurve(to: leftBaseCornerEnd, control: leftHeadBase)
        path.addLine(to: roundedTipLeft)
        path.addQuadCurve(to: roundedTipRight, control: end)
        path.addLine(to: rightBaseCornerStart)
        path.addQuadCurve(to: rightBaseCornerEnd, control: rightHeadBase)
        path.addLine(to: rightBaseInner)
        path.addLine(to: rightNeck)
        path.addCurve(to: tailRight, control1: rightShaftControlA, control2: rightShaftControlB)
        path.addCurve(
            to: tailLeft,
            control1: tailCapControlRight,
            control2: tailCapControlLeft
        )
        path.closeSubpath()

        return path
    }

    private func fancyArrowPath(for annotation: AnnotationObject) -> CGPath {
        let path = CGMutablePath()

        guard case let .arrow(start, end) = annotation.geometry else {
            return path
        }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = hypot(deltaX, deltaY)
        let unit = length > 0.5
            ? CGVector(dx: deltaX / length, dy: deltaY / length)
            : CGVector(dx: 1, dy: 0)
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)

        let selectedWidth = max(1, annotation.style.lineWidth)
        // CleanShot-style arrows are tapered: a narrow rounded tail grows into a dominant head.
        // These ratios are based on the selected width only, so long and short arrows stay visually consistent.
        let bodyEndWidth = max(9.5, selectedWidth * 1.35 + 6.8)
        let bodyEndHalfWidth = bodyEndWidth / 2
        let tailWidth = max(4.8, bodyEndWidth * 0.5)
        let tailHalfWidth = tailWidth / 2
        let headWidth = max(72, bodyEndWidth * 7)
        let headHalfWidth = headWidth / 2
        let headLength = max(76, headWidth * 1.06)
        let notchDepth = max(28, headLength * 0.46)
        let minimumShaftLength = max(28, bodyEndWidth * 4.6)
        let renderLength = max(length, headLength + minimumShaftLength)
        let renderStart = length >= renderLength
            ? start
            : offset(end, along: unit, distance: -renderLength)
        let bodyLength = max(1, renderLength - headLength + notchDepth)

        let headBackCenter = offset(end, along: unit, distance: -headLength)
        let neckCenter = offset(headBackCenter, along: unit, distance: notchDepth)
        let neckHalfWidth = min(bodyEndHalfWidth, headHalfWidth * 0.18)
        let leftNeck = offset(neckCenter, along: perpendicular, distance: neckHalfWidth)
        let rightNeck = offset(neckCenter, along: perpendicular, distance: -neckHalfWidth)
        let leftWing = offset(headBackCenter, along: perpendicular, distance: headHalfWidth)
        let rightWing = offset(headBackCenter, along: perpendicular, distance: -headHalfWidth)

        let wingCornerForward = min(headLength * 0.15, max(8, bodyEndWidth * 1.35))
        let wingCornerInset = min(headHalfWidth * 0.11, max(3.5, bodyEndWidth * 0.54))
        let leftRearCorner = offset(leftWing, along: perpendicular, distance: -wingCornerInset)
        let leftOuterCorner = offset(
            offset(leftWing, along: unit, distance: wingCornerForward),
            along: perpendicular,
            distance: -wingCornerInset * 0.38
        )
        let rightOuterCorner = offset(
            offset(rightWing, along: unit, distance: wingCornerForward),
            along: perpendicular,
            distance: wingCornerInset * 0.38
        )
        let rightRearCorner = offset(rightWing, along: perpendicular, distance: wingCornerInset)

        let tipRoundness = min(headLength * 0.1, max(4.5, bodyEndWidth * 0.66))
        let roundedTipLeft = offset(
            offset(end, along: unit, distance: -tipRoundness),
            along: perpendicular,
            distance: tipRoundness * 0.42
        )
        let roundedTipRight = offset(
            offset(end, along: unit, distance: -tipRoundness),
            along: perpendicular,
            distance: -tipRoundness * 0.42
        )

        let tailLeft = offset(renderStart, along: perpendicular, distance: tailHalfWidth)
        let tailRight = offset(renderStart, along: perpendicular, distance: -tailHalfWidth)
        let tailCapControlLeft = offset(
            offset(renderStart, along: unit, distance: -tailHalfWidth * 1.35),
            along: perpendicular,
            distance: tailHalfWidth
        )
        let tailCapControlRight = offset(
            offset(renderStart, along: unit, distance: -tailHalfWidth * 1.35),
            along: perpendicular,
            distance: -tailHalfWidth
        )

        let leftBodyControlA = offset(
            offset(renderStart, along: unit, distance: bodyLength * 0.38),
            along: perpendicular,
            distance: tailHalfWidth * 1.08
        )
        let leftBodyControlB = offset(
            offset(neckCenter, along: unit, distance: -bodyLength * 0.16),
            along: perpendicular,
            distance: neckHalfWidth * 1.02
        )
        let rightBodyControlA = offset(
            offset(neckCenter, along: unit, distance: -bodyLength * 0.16),
            along: perpendicular,
            distance: -neckHalfWidth * 1.02
        )
        let rightBodyControlB = offset(
            offset(renderStart, along: unit, distance: bodyLength * 0.38),
            along: perpendicular,
            distance: -tailHalfWidth * 1.08
        )

        let leftNeckControl = offset(
            offset(neckCenter, along: unit, distance: -notchDepth * 0.72),
            along: perpendicular,
            distance: bodyEndHalfWidth + (headHalfWidth - bodyEndHalfWidth) * 0.08
        )
        let leftWingControl = offset(
            offset(headBackCenter, along: unit, distance: headLength * 0.08),
            along: perpendicular,
            distance: headHalfWidth * 0.98
        )
        let rightWingControl = offset(
            offset(headBackCenter, along: unit, distance: headLength * 0.08),
            along: perpendicular,
            distance: -headHalfWidth * 0.98
        )
        let rightNeckControl = offset(
            offset(neckCenter, along: unit, distance: -notchDepth * 0.72),
            along: perpendicular,
            distance: -(bodyEndHalfWidth + (headHalfWidth - bodyEndHalfWidth) * 0.08)
        )

        path.move(to: tailLeft)
        path.addCurve(to: leftNeck, control1: leftBodyControlA, control2: leftBodyControlB)
        path.addCurve(to: leftRearCorner, control1: leftNeckControl, control2: leftWingControl)
        path.addQuadCurve(to: leftOuterCorner, control: leftWing)
        path.addLine(to: roundedTipLeft)
        path.addQuadCurve(to: roundedTipRight, control: end)
        path.addLine(to: rightOuterCorner)
        path.addQuadCurve(to: rightRearCorner, control: rightWing)
        path.addCurve(to: rightNeck, control1: rightWingControl, control2: rightNeckControl)
        path.addCurve(to: tailRight, control1: rightBodyControlA, control2: rightBodyControlB)
        path.addCurve(
            to: tailLeft,
            control1: tailCapControlRight,
            control2: tailCapControlLeft
        )
        path.closeSubpath()

        return path
    }

    private func offset(_ point: CGPoint, along vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x + vector.dx * distance,
            y: point.y + vector.dy * distance
        )
    }
}

final class LineAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.line

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        let layer = CAShapeLayer()
        layer.path = linePath(for: annotation)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = annotation.style.strokeColor.cgColor
        layer.lineWidth = annotation.style.lineWidth
        layer.lineCap = .round
        layer.allowsEdgeAntialiasing = true
        layer.opacity = Float(annotation.style.opacity)
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        guard case let .arrow(start, end) = annotation.geometry else {
            return false
        }

        let expandedTolerance = max(tolerance, annotation.style.lineWidth / 2 + 4)
        return point.distanceToLineSegment(start: start, end: end) <= expandedTolerance
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
        linePath(for: annotation)
    }

    private func linePath(for annotation: AnnotationObject) -> CGPath {
        let path = CGMutablePath()

        guard case let .arrow(start, end) = annotation.geometry else {
            return path
        }

        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

final class NumberingAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.numbering

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: context.canvasSize)
        container.opacity = Float(annotation.style.opacity)

        let badgePath = badgePath(for: annotation)
        let badgeLayer = CAShapeLayer()
        badgeLayer.frame = container.bounds
        badgeLayer.path = badgePath
        badgeLayer.fillColor = annotation.style.strokeColor.cgColor
        badgeLayer.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        badgeLayer.lineWidth = 1
        badgeLayer.shadowColor = NSColor.black.cgColor
        badgeLayer.shadowOpacity = 0.22
        badgeLayer.shadowRadius = 3
        badgeLayer.shadowOffset = CGSize(width: 0, height: 1.5)
        badgeLayer.shadowPath = badgePath
        badgeLayer.allowsEdgeAntialiasing = true
        container.addSublayer(badgeLayer)

        guard let number = annotation.number else {
            return container
        }

        let rect = badgeRect(for: annotation)
        let textLayer = CATextLayer()
        textLayer.frame = textFrame(for: rect)
        textLayer.string = attributedNumber(number, in: rect)
        textLayer.alignmentMode = .center
        textLayer.truncationMode = .none
        textLayer.isWrapped = false
        textLayer.contentsGravity = .center
        textLayer.contentsScale = 2
        textLayer.allowsEdgeAntialiasing = true
        container.addSublayer(textLayer)
        return container
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        let rect = badgeRect(for: annotation).insetBy(dx: -tolerance, dy: -tolerance)
        guard rect.width > 0, rect.height > 0 else {
            return false
        }

        let normalizedX = (point.x - rect.midX) / (rect.width / 2)
        let normalizedY = (point.y - rect.midY) / (rect.height / 2)
        return normalizedX * normalizedX + normalizedY * normalizedY <= 1
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        [:]
    }

    func selectionPath(for annotation: AnnotationObject) -> CGPath {
        badgePath(for: annotation)
    }

    private func badgePath(for annotation: AnnotationObject) -> CGPath {
        CGPath(ellipseIn: badgeRect(for: annotation), transform: nil)
    }

    private func badgeRect(for annotation: AnnotationObject) -> CGRect {
        guard case let .oval(rect) = annotation.geometry else {
            return .zero
        }

        return rect.standardizedForEditor
    }

    private func textFrame(for rect: CGRect) -> CGRect {
        let height = rect.height * 0.72
        return CGRect(
            x: rect.minX + rect.width * 0.08,
            y: rect.midY - height / 2,
            width: rect.width * 0.84,
            height: height
        )
    }

    private func attributedNumber(_ number: Int, in rect: CGRect) -> NSAttributedString {
        let text = String(number)
        let digitCount = CGFloat(text.count)
        let widthScale = min(0.54, 0.78 / max(1, digitCount * 0.56))
        let fontSize = max(10, rect.width * widthScale)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}

final class RectangleAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.rectangle

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
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

final class FilledRectangleAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.filledRectangle

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        let layer = CAShapeLayer()
        layer.path = rectanglePath(for: annotation)
        layer.fillColor = annotation.style.strokeColor.cgColor
        layer.strokeColor = annotation.style.strokeColor.cgColor
        layer.lineWidth = 0
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

final class OvalAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.oval

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        let layer = CAShapeLayer()
        layer.path = ovalPath(for: annotation)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = annotation.style.strokeColor.cgColor
        layer.lineWidth = annotation.style.lineWidth
        layer.opacity = Float(annotation.style.opacity)
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        guard case let .oval(rect) = annotation.geometry else {
            return false
        }

        return rect.standardizedForEditor.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        guard case let .oval(rect) = annotation.geometry else {
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
        ovalPath(for: annotation)
    }

    private func ovalPath(for annotation: AnnotationObject) -> CGPath {
        guard case let .oval(rect) = annotation.geometry else {
            return CGMutablePath()
        }

        return CGPath(ellipseIn: rect.standardizedForEditor, transform: nil)
    }
}

final class HighlightAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.highlight

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        let layer = CAShapeLayer()
        layer.path = spotlightMaskPath(for: annotation, canvasSize: context.canvasSize)
        layer.fillRule = .evenOdd
        layer.fillColor = NSColor.black.cgColor
        layer.strokeColor = NSColor.clear.cgColor
        layer.lineWidth = 0
        layer.opacity = Float(min(max(annotation.style.spotlightIntensity, 0.1), 0.85))
        layer.allowsEdgeAntialiasing = true
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        let path = highlightedRegionPath(for: annotation)
        return path.contains(point)
            || path.copy(
                strokingWithWidth: tolerance * 2,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 2
            ).contains(point)
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        guard case let .highlight(rect) = annotation.geometry else {
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
        highlightedRegionPath(for: annotation)
    }

    private func spotlightMaskPath(for annotation: AnnotationObject, canvasSize: CGSize) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: canvasSize))
        path.addPath(highlightedRegionPath(for: annotation))
        return path
    }

    private func highlightedRegionPath(for annotation: AnnotationObject) -> CGPath {
        guard case let .highlight(rect) = annotation.geometry else {
            return CGMutablePath()
        }

        let normalizedRect = rect.standardizedForEditor

        switch annotation.style.spotlightShape {
        case .rectangle:
            return CGPath(rect: normalizedRect, transform: nil)
        case .roundedRectangle:
            let cornerRadius = min(18, max(4, min(normalizedRect.width, normalizedRect.height) * 0.12))
            return CGPath(
                roundedRect: normalizedRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        case .oval:
            return CGPath(ellipseIn: normalizedRect, transform: nil)
        case .triangle:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: normalizedRect.midX, y: normalizedRect.minY))
            path.addLine(to: CGPoint(x: normalizedRect.maxX, y: normalizedRect.maxY))
            path.addLine(to: CGPoint(x: normalizedRect.minX, y: normalizedRect.maxY))
            path.closeSubpath()
            return path
        case .diamond:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: normalizedRect.midX, y: normalizedRect.minY))
            path.addLine(to: CGPoint(x: normalizedRect.maxX, y: normalizedRect.midY))
            path.addLine(to: CGPoint(x: normalizedRect.midX, y: normalizedRect.maxY))
            path.addLine(to: CGPoint(x: normalizedRect.minX, y: normalizedRect.midY))
            path.closeSubpath()
            return path
        }
    }
}

final class BlurPixelateAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.blurPixelate

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        guard case let .blurPixelate(rect) = annotation.geometry else {
            return CALayer()
        }

        let normalizedRect = rect.standardizedForEditor
        guard normalizedRect.width >= 1,
              normalizedRect.height >= 1,
              let sourceImage = context.sourceImage,
              let pixelatedImage = pixelatedImage(
                for: normalizedRect,
                annotation: annotation,
                sourceImage: sourceImage,
                canvasSize: context.canvasSize
              )
        else {
            return placeholderLayer(for: normalizedRect)
        }

        let layer = CALayer()
        layer.frame = normalizedRect
        layer.contents = pixelatedImage
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.masksToBounds = true
        layer.cornerRadius = cornerRadius(for: normalizedRect)
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        guard case let .blurPixelate(rect) = annotation.geometry else {
            return false
        }

        return rect.standardizedForEditor
            .insetBy(dx: -tolerance, dy: -tolerance)
            .contains(point)
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        guard case let .blurPixelate(rect) = annotation.geometry else {
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
        guard case let .blurPixelate(rect) = annotation.geometry else {
            return CGMutablePath()
        }

        let normalizedRect = rect.standardizedForEditor
        return CGPath(
            roundedRect: normalizedRect,
            cornerWidth: cornerRadius(for: normalizedRect),
            cornerHeight: cornerRadius(for: normalizedRect),
            transform: nil
        )
    }

    private func pixelatedImage(
        for rect: CGRect,
        annotation: AnnotationObject,
        sourceImage: CGImage,
        canvasSize: CGSize
    ) -> CGImage? {
        guard let pixelRect = sourcePixelRect(
            for: rect,
            sourceImage: sourceImage,
            canvasSize: canvasSize
        ) else {
            return nil
        }

        let inputImage = CIImage(cgImage: sourceImage)
        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(inputImage.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: pixelRect.midX, y: pixelRect.midY), forKey: kCIInputCenterKey)
        filter?.setValue(pixelationScale(for: annotation, pixelRect: pixelRect, sourceImage: sourceImage, canvasSize: canvasSize), forKey: kCIInputScaleKey)

        guard let outputImage = filter?.outputImage?.cropped(to: pixelRect) else {
            return nil
        }

        return ciContext.createCGImage(outputImage, from: pixelRect)
    }

    private func sourcePixelRect(
        for rect: CGRect,
        sourceImage: CGImage,
        canvasSize: CGSize
    ) -> CGRect? {
        guard canvasSize.width > 0,
              canvasSize.height > 0
        else {
            return nil
        }

        let sourceExtent = CGRect(
            x: 0,
            y: 0,
            width: sourceImage.width,
            height: sourceImage.height
        )
        let scaleX = sourceExtent.width / canvasSize.width
        let scaleY = sourceExtent.height / canvasSize.height
        let pixelRect = CGRect(
            x: rect.minX * scaleX,
            y: sourceExtent.height - rect.maxY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        .integral
        .intersection(sourceExtent)

        guard !pixelRect.isNull,
              pixelRect.width >= 1,
              pixelRect.height >= 1
        else {
            return nil
        }

        return pixelRect
    }

    private func pixelationScale(
        for annotation: AnnotationObject,
        pixelRect: CGRect,
        sourceImage: CGImage,
        canvasSize: CGSize
    ) -> CGFloat {
        let pixelRatio = max(
            CGFloat(sourceImage.width) / max(canvasSize.width, 1),
            CGFloat(sourceImage.height) / max(canvasSize.height, 1)
        )
        let requestedScale = annotation.style.effectIntensity * 5 * pixelRatio
        return min(max(6, requestedScale), max(pixelRect.width, pixelRect.height))
    }

    private func placeholderLayer(for rect: CGRect) -> CALayer {
        let layer = CAShapeLayer()
        layer.frame = .zero
        layer.path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius(for: rect),
            cornerHeight: cornerRadius(for: rect),
            transform: nil
        )
        layer.fillColor = NSColor.black.withAlphaComponent(0.32).cgColor
        return layer
    }

    private func cornerRadius(for rect: CGRect) -> CGFloat {
        min(4, max(1.5, min(rect.width, rect.height) * 0.08))
    }
}

final class TextAnnotationRenderer: AnnotationShapeRendering {
    let kind = AnnotationObjectKind.text

    func makeLayer(for annotation: AnnotationObject, context: AnnotationRenderContext) -> CALayer {
        let layer = CATextLayer()
        layer.frame = textRect(for: annotation)
        layer.string = attributedText(for: annotation)
        layer.alignmentMode = .left
        layer.truncationMode = .none
        layer.isWrapped = true
        layer.contentsGravity = .topLeft
        layer.opacity = Float(annotation.style.opacity)
        layer.allowsEdgeAntialiasing = true
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        textRect(for: annotation)
            .insetBy(dx: -tolerance, dy: -tolerance)
            .contains(point)
    }

    func resizeHandles(for annotation: AnnotationObject, size: CGFloat) -> [AnnotationResizeHandle: CGRect] {
        let normalizedRect = textRect(for: annotation).standardizedForEditor

        return [
            .topLeft: handleRect(centeredAt: CGPoint(x: normalizedRect.minX, y: normalizedRect.minY), size: size),
            .topRight: handleRect(centeredAt: CGPoint(x: normalizedRect.maxX, y: normalizedRect.minY), size: size),
            .bottomLeft: handleRect(centeredAt: CGPoint(x: normalizedRect.minX, y: normalizedRect.maxY), size: size),
            .bottomRight: handleRect(centeredAt: CGPoint(x: normalizedRect.maxX, y: normalizedRect.maxY), size: size)
        ]
    }

    func selectionPath(for annotation: AnnotationObject) -> CGPath {
        CGPath(rect: textRect(for: annotation), transform: nil)
    }

    private func attributedText(for annotation: AnnotationObject) -> NSAttributedString {
        guard case let .text(_, text) = annotation.geometry else {
            return NSAttributedString()
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .semibold),
                .foregroundColor: annotation.style.strokeColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func textRect(for annotation: AnnotationObject) -> CGRect {
        guard case let .text(rect, _) = annotation.geometry else {
            return .zero
        }

        return rect.standardizedForEditor
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
