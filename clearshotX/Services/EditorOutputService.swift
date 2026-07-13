//
//  EditorOutputService.swift
//  clearshotX
//
//  Created by Codex on 05/07/26.
//

import AppKit

@MainActor
protocol EditorOutputServicing {
    @discardableResult
    func copy(image: NSImage, annotations: [AnnotationObject]) -> Bool

    func save(image: NSImage, sourceFileURL: URL?, annotations: [AnnotationObject])
}

@MainActor
final class EditorOutputService: EditorOutputServicing {
    private let clipboardService: ClipboardService
    private let flattenedImageRenderer: EditorFlattenedImageRendering
    private let captureExportService: CaptureExportServicing

    init(
        clipboardService: ClipboardService? = nil,
        flattenedImageRenderer: EditorFlattenedImageRendering? = nil,
        captureExportService: CaptureExportServicing? = nil
    ) {
        self.clipboardService = clipboardService ?? ClipboardService()
        self.flattenedImageRenderer = flattenedImageRenderer ?? EditorFlattenedImageRenderer()
        self.captureExportService = captureExportService ?? CaptureExportService()
    }

    @discardableResult
    func copy(image: NSImage, annotations: [AnnotationObject]) -> Bool {
        guard let flattenedImage = flattenedImageRenderer.render(image: image, annotations: annotations) else {
            NSSound.beep()
            return false
        }

        return clipboardService.copy(flattenedImage)
    }

    func save(image: NSImage, sourceFileURL: URL?, annotations: [AnnotationObject]) {
        guard let flattenedImage = flattenedImageRenderer.render(image: image, annotations: annotations),
              let pngData = flattenedImage.pngData()
        else {
            NSSound.beep()
            return
        }

        captureExportService.savePNGData(
            pngData,
            suggestedFileName: defaultFileName(sourceFileURL: sourceFileURL)
        ) { result in
            if case let .failure(error) = result {
                Self.presentSaveError(error)
            }
        }
    }

    private func defaultFileName(sourceFileURL: URL?) -> String {
        let fallbackName = "Annotated Screenshot"
        let baseName = sourceFileURL?.deletingPathExtension().lastPathComponent ?? fallbackName

        if baseName.localizedCaseInsensitiveContains("annotated") {
            return "\(baseName).png"
        }

        return "\(baseName)-annotated.png"
    }

    private static func presentSaveError(_ error: CaptureExportError) {
        let alert = NSAlert(error: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
protocol EditorFlattenedImageRendering {
    func render(image: NSImage, annotations: [AnnotationObject]) -> NSImage?
}

@MainActor
final class EditorFlattenedImageRenderer: EditorFlattenedImageRendering {
    private let annotationLayerRenderer = AnnotationLayerRenderer()

    func render(image: NSImage, annotations: [AnnotationObject]) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let canvasSize = image.editorExportCanvasSize
        guard canvasSize.width > 0,
              canvasSize.height > 0
        else {
            return nil
        }

        let outputSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        guard let context = CGContext(
            data: nil,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rootLayer = makeLayerTree(
            sourceImage: sourceImage,
            canvasSize: canvasSize,
            annotations: annotations
        )
        let scaleX = outputSize.width / canvasSize.width
        let scaleY = outputSize.height / canvasSize.height

        context.interpolationQuality = .high
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: outputSize))

        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        rootLayer.render(in: context)
        context.restoreGState()

        guard let flattenedImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: flattenedImage, size: canvasSize)
    }

    private func makeLayerTree(
        sourceImage: CGImage,
        canvasSize: CGSize,
        annotations: [AnnotationObject]
    ) -> CALayer {
        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: canvasSize)
        rootLayer.bounds = CGRect(origin: .zero, size: canvasSize)
        rootLayer.contentsScale = 1
        rootLayer.masksToBounds = true

        let imageLayer = CALayer()
        imageLayer.frame = rootLayer.bounds
        imageLayer.contents = sourceImage
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        rootLayer.addSublayer(imageLayer)

        let annotationContainerLayer = CALayer()
        annotationContainerLayer.frame = rootLayer.bounds
        annotationContainerLayer.masksToBounds = true
        annotationContainerLayer.contentsScale = 1
        rootLayer.addSublayer(annotationContainerLayer)

        annotationLayerRenderer.render(
            annotations: annotations,
            draftAnnotation: nil,
            selectedAnnotationID: nil,
            sourceImage: sourceImage,
            in: annotationContainerLayer,
            contentsScale: 1,
            selectionHandleSize: 0
        )

        return rootLayer
    }
}

private extension NSImage {
    var editorExportCanvasSize: NSSize {
        if size.width > 0, size.height > 0 {
            return size
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSSize(width: 960, height: 540)
        }

        return NSSize(width: cgImage.width, height: cgImage.height)
    }

    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        bitmapRepresentation.size = size
        return bitmapRepresentation.representation(using: .png, properties: [:])
    }
}
