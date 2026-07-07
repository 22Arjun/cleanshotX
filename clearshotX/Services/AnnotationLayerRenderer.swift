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
        RectangleAnnotationRenderer(),
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
        let visualAnnotations = (annotations + (draftAnnotation.map { [$0] } ?? []))
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
        let path = CGMutablePath()

        guard case let .arrow(start, end) = annotation.geometry else {
            return path
        }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = hypot(deltaX, deltaY)
        guard length > 1 else {
            return path
        }

        let unit = CGVector(dx: deltaX / length, dy: deltaY / length)
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)

        let thickness = max(1, annotation.style.lineWidth)
        let tailWidth = min(max(6, thickness * 2.35), max(4, length * 0.17))
        let shaftEndWidth = min(max(tailWidth * 1.72, thickness * 4.5), max(tailWidth, length * 0.26))
        let headWidth = min(max(shaftEndWidth * 2.08, thickness * 9.5), max(shaftEndWidth * 1.45, length * 0.46))
        let headLength = min(max(headWidth * 0.88, thickness * 9.8), max(10, length * 0.34))
        let shaftLength = max(2, length - headLength)
        let headBase = CGPoint(
            x: end.x - unit.dx * headLength,
            y: end.y - unit.dy * headLength
        )

        let tailHalfWidth = tailWidth / 2
        let shaftHalfWidth = shaftEndWidth / 2
        let headHalfWidth = headWidth / 2
        let tailCapCenter = offset(start, along: unit, distance: min(tailHalfWidth, shaftLength * 0.22))
        let tailBackControl = offset(start, along: unit, distance: -tailHalfWidth * 0.48)
        let tipRoundness = min(3, max(1.1, headWidth * 0.035))

        let tailLeft = offset(tailCapCenter, along: perpendicular, distance: tailHalfWidth)
        let tailRight = offset(tailCapCenter, along: perpendicular, distance: -tailHalfWidth)
        let shaftJoinLeft = offset(headBase, along: perpendicular, distance: shaftHalfWidth)
        let shaftJoinRight = offset(headBase, along: perpendicular, distance: -shaftHalfWidth)
        let headBaseLeft = offset(headBase, along: perpendicular, distance: headHalfWidth)
        let headBaseRight = offset(headBase, along: perpendicular, distance: -headHalfWidth)
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

        let leftShaftControlA = offset(
            offset(start, along: unit, distance: shaftLength * 0.34),
            along: perpendicular,
            distance: tailHalfWidth * 1.03
        )
        let leftShaftControlB = offset(
            offset(headBase, along: unit, distance: -shaftLength * 0.24),
            along: perpendicular,
            distance: shaftHalfWidth * 0.98
        )
        let leftShoulderControl = offset(
            offset(headBase, along: unit, distance: -headLength * 0.08),
            along: perpendicular,
            distance: shaftHalfWidth + (headHalfWidth - shaftHalfWidth) * 0.42
        )
        let rightShoulderControl = offset(
            offset(headBase, along: unit, distance: -headLength * 0.08),
            along: perpendicular,
            distance: -(shaftHalfWidth + (headHalfWidth - shaftHalfWidth) * 0.42)
        )
        let rightShaftControlA = offset(
            offset(headBase, along: unit, distance: -shaftLength * 0.24),
            along: perpendicular,
            distance: -shaftHalfWidth * 0.98
        )
        let rightShaftControlB = offset(
            offset(start, along: unit, distance: shaftLength * 0.34),
            along: perpendicular,
            distance: -tailHalfWidth * 1.03
        )

        path.move(to: tailLeft)
        path.addCurve(to: shaftJoinLeft, control1: leftShaftControlA, control2: leftShaftControlB)
        path.addQuadCurve(to: headBaseLeft, control: leftShoulderControl)
        path.addLine(to: roundedTipLeft)
        path.addQuadCurve(to: roundedTipRight, control: end)
        path.addLine(to: headBaseRight)
        path.addQuadCurve(to: shaftJoinRight, control: rightShoulderControl)
        path.addCurve(to: tailRight, control1: rightShaftControlA, control2: rightShaftControlB)
        path.addQuadCurve(to: tailLeft, control: tailBackControl)
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
        layer.path = highlightPath(for: annotation)
        layer.fillColor = annotation.style.strokeColor.cgColor
        layer.strokeColor = NSColor.clear.cgColor
        layer.lineWidth = 0
        layer.lineJoin = .round
        layer.opacity = Float(effectiveOpacity(for: annotation))
        layer.allowsEdgeAntialiasing = true
        return layer
    }

    func hitTest(_ point: CGPoint, annotation: AnnotationObject, tolerance: CGFloat) -> Bool {
        guard case let .highlight(rect) = annotation.geometry else {
            return false
        }

        return rect.standardizedForEditor
            .insetBy(dx: -tolerance, dy: -tolerance)
            .contains(point)
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
        highlightPath(for: annotation)
    }

    private func highlightPath(for annotation: AnnotationObject) -> CGPath {
        guard case let .highlight(rect) = annotation.geometry else {
            return CGMutablePath()
        }

        let normalizedRect = rect.standardizedForEditor
        let cornerRadius = min(4, max(1.5, min(normalizedRect.width, normalizedRect.height) * 0.08))
        return CGPath(
            roundedRect: normalizedRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    private func effectiveOpacity(for annotation: AnnotationObject) -> CGFloat {
        max(0.14, min(0.42, annotation.style.opacity * 0.42))
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
