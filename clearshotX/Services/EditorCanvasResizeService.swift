//
//  EditorCanvasResizeService.swift
//  clearshotX
//
//  Created by Codex on 05/07/26.
//

import AppKit
import QuartzCore

@MainActor
protocol EditorCanvasResizing {
    func resizedCanvasImage(from image: NSImage, to cropRect: CGRect, fillColor: NSColor) -> NSImage?
    func rotatedClockwiseImage(from image: NSImage) -> NSImage?
    func flippedImage(from image: NSImage, horizontally: Bool) -> NSImage?
}

@MainActor
final class EditorCanvasResizeService: EditorCanvasResizing {
    func resizedCanvasImage(from image: NSImage, to cropRect: CGRect, fillColor: NSColor) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let canvasSize = image.editorResizeCanvasSize
        let targetRect = cropRect.standardizedForEditor
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              targetRect.width >= 1,
              targetRect.height >= 1
        else {
            return nil
        }

        let scaleX = CGFloat(sourceImage.width) / canvasSize.width
        let scaleY = CGFloat(sourceImage.height) / canvasSize.height
        let outputPixelSize = CGSize(
            width: max(1, round(targetRect.width * scaleX)),
            height: max(1, round(targetRect.height * scaleY))
        )

        guard let context = CGContext(
            data: nil,
            width: Int(outputPixelSize.width),
            height: Int(outputPixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: targetRect.size)
        rootLayer.bounds = CGRect(origin: .zero, size: targetRect.size)
        rootLayer.masksToBounds = true
        rootLayer.contentsScale = 1

        let imageLayer = CALayer()
        imageLayer.frame = CGRect(
            x: -targetRect.minX,
            y: -targetRect.minY,
            width: canvasSize.width,
            height: canvasSize.height
        )
        imageLayer.contents = sourceImage
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        rootLayer.addSublayer(imageLayer)

        context.interpolationQuality = .high
        context.setFillColor(fillColor.cgColor)
        context.fill(CGRect(origin: .zero, size: outputPixelSize))

        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        rootLayer.render(in: context)
        context.restoreGState()

        guard let resizedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: resizedImage, size: targetRect.size)
    }

    func rotatedClockwiseImage(from image: NSImage) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = bitmapContext(
                width: sourceImage.height,
                height: sourceImage.width,
                colorSpace: sourceImage.colorSpace
              )
        else {
            return nil
        }

        let outputPixelSize = CGSize(width: sourceImage.height, height: sourceImage.width)
        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: outputPixelSize))
        context.translateBy(x: outputPixelSize.width, y: 0)
        context.rotate(by: .pi / 2)
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        )

        guard let transformedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: transformedImage, size: CGSize(width: image.editorResizeCanvasSize.height, height: image.editorResizeCanvasSize.width))
    }

    func flippedImage(from image: NSImage, horizontally: Bool) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = bitmapContext(
                width: sourceImage.width,
                height: sourceImage.height,
                colorSpace: sourceImage.colorSpace
              )
        else {
            return nil
        }

        let outputPixelSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: outputPixelSize))

        if horizontally {
            context.translateBy(x: outputPixelSize.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: outputPixelSize.height)
            context.scaleBy(x: 1, y: -1)
        }

        context.draw(sourceImage, in: CGRect(origin: .zero, size: outputPixelSize))

        guard let transformedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: transformedImage, size: image.editorResizeCanvasSize)
    }

    private func bitmapContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace?
    ) -> CGContext? {
        CGContext(
            data: nil,
            width: max(1, width),
            height: max(1, height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

private extension NSImage {
    var editorResizeCanvasSize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSSize(width: 960, height: 540)
        }

        return NSSize(width: cgImage.width, height: cgImage.height)
    }
}
