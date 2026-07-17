import CoreGraphics
import Foundation
import XCTest

@testable import clearshotX

@MainActor
final class RegionSelectionGeometryTests: XCTestCase {
    private let desktopBounds = CGRect(x: 0, y: 0, width: 1_600, height: 900)
    private let displays = [
        RegionDisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 800, height: 900),
            backingScale: 1
        ),
        RegionDisplayGeometry(
            frame: CGRect(x: 800, y: 0, width: 800, height: 900),
            backingScale: 2
        ),
    ]

    func testSingleDisplayDimensionsUseThatDisplaysScale() {
        let model = makeModel()

        model.beginSelection(at: CGPoint(x: 100, y: 100), modifiers: [])
        model.updateSelection(to: CGPoint(x: 200, y: 150), modifiers: [])

        XCTAssertEqual(model.pixelDimensions?.width, 100)
        XCTAssertEqual(model.pixelDimensions?.height, 50)
    }

    func testCrossDisplayDimensionsUseHighestIntersectedScale() {
        let model = makeModel()

        model.beginSelection(at: CGPoint(x: 700, y: 100), modifiers: [])
        model.updateSelection(to: CGPoint(x: 900, y: 200), modifiers: [])

        XCTAssertEqual(model.pixelDimensions?.width, 400)
        XCTAssertEqual(model.pixelDimensions?.height, 200)
    }

    func testVerticallyOffsetDisplayParticipatesInScaleCalculation() {
        let model = RegionSelectionViewModel(
            bounds: CGRect(x: 0, y: 0, width: 800, height: 1_800),
            displays: [
                RegionDisplayGeometry(
                    frame: CGRect(x: 0, y: 0, width: 800, height: 900),
                    backingScale: 1
                ),
                RegionDisplayGeometry(
                    frame: CGRect(x: 0, y: 900, width: 800, height: 900),
                    backingScale: 2
                ),
            ]
        )

        model.beginSelection(at: CGPoint(x: 100, y: 800), modifiers: [])
        model.updateSelection(to: CGPoint(x: 200, y: 1_000), modifiers: [])

        XCTAssertEqual(model.pixelDimensions?.width, 200)
        XCTAssertEqual(model.pixelDimensions?.height, 400)
    }

    func testOptionResizePreservesCenter() {
        let model = makeModel()
        model.beginSelection(at: CGPoint(x: 100, y: 100), modifiers: [])
        model.updateSelection(to: CGPoint(x: 200, y: 160), modifiers: [])

        model.rebaseResizing(
            at: CGPoint(x: 200, y: 160),
            modifiers: [.fromCenter]
        )
        model.updateSelection(
            to: CGPoint(x: 220, y: 170),
            modifiers: [.fromCenter]
        )

        assertRect(
            model.selectionRect,
            equals: CGRect(x: 80, y: 90, width: 140, height: 80)
        )
        guard let selectionRect = model.selectionRect else {
            XCTFail("Expected a selection rectangle.")
            return
        }
        XCTAssertEqual(selectionRect.midX, 150, accuracy: 0.001)
        XCTAssertEqual(selectionRect.midY, 130, accuracy: 0.001)
    }

    func testShiftResizeLocksDominantAxis() {
        let model = makeModel()
        model.beginSelection(at: CGPoint(x: 100, y: 100), modifiers: [])
        model.updateSelection(to: CGPoint(x: 200, y: 160), modifiers: [])

        model.rebaseResizing(
            at: CGPoint(x: 200, y: 160),
            modifiers: [.lockAxis]
        )
        model.updateSelection(
            to: CGPoint(x: 230, y: 168),
            modifiers: [.lockAxis]
        )

        assertRect(
            model.selectionRect,
            equals: CGRect(x: 100, y: 100, width: 130, height: 60)
        )
    }

    func testModifierRebaseDoesNotJumpSelection() {
        let model = makeModel()
        model.beginSelection(at: CGPoint(x: 100, y: 100), modifiers: [])
        model.updateSelection(to: CGPoint(x: 240, y: 180), modifiers: [])
        let originalRect = model.selectionRect

        model.rebaseResizing(
            at: CGPoint(x: 240, y: 180),
            modifiers: [.fromCenter, .lockAxis]
        )
        assertRect(model.selectionRect, equals: originalRect)

        model.rebaseResizing(at: CGPoint(x: 240, y: 180), modifiers: [])
        assertRect(model.selectionRect, equals: originalRect)
    }

    func testCenteredResizeClampsBothEdgesToDesktop() {
        let model = RegionSelectionViewModel(
            bounds: CGRect(x: 0, y: 0, width: 300, height: 300),
            displays: [
                RegionDisplayGeometry(
                    frame: CGRect(x: 0, y: 0, width: 300, height: 300),
                    backingScale: 1
                )
            ]
        )
        model.beginSelection(at: CGPoint(x: 100, y: 100), modifiers: [])
        model.updateSelection(to: CGPoint(x: 200, y: 200), modifiers: [])
        model.rebaseResizing(
            at: CGPoint(x: 200, y: 200),
            modifiers: [.fromCenter]
        )

        model.updateSelection(
            to: CGPoint(x: 500, y: 500),
            modifiers: [.fromCenter]
        )

        assertRect(
            model.selectionRect,
            equals: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
    }

    func testSpaceMovementPreservesSizeAcrossDisplayBoundary() {
        let model = makeModel()
        model.beginSelection(at: CGPoint(x: 650, y: 100), modifiers: [])
        model.updateSelection(to: CGPoint(x: 750, y: 150), modifiers: [])

        model.beginMovingSelection()
        model.moveSelection(to: CGPoint(x: 900, y: 250))

        assertRect(
            model.selectionRect,
            equals: CGRect(x: 800, y: 200, width: 100, height: 50)
        )
    }

    private func makeModel() -> RegionSelectionViewModel {
        RegionSelectionViewModel(bounds: desktopBounds, displays: displays)
    }

    private func assertRect(
        _ actual: CGRect?,
        equals expected: CGRect?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual, let expected else {
            XCTAssertEqual(actual, expected, file: file, line: line)
            return
        }

        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}

@MainActor
final class RegionRenderOptimizationTests: XCTestCase {
    func testDirtyRegionsOnlyContainChangedSelectionStrips() {
        let oldRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let newRect = CGRect(x: 10, y: 0, width: 100, height: 100)

        let changedAreas = RegionDirtyRegionCalculator.changedAreas(
            from: oldRect,
            to: newRect
        )

        XCTAssertEqual(changedAreas.count, 2)
        XCTAssertTrue(changedAreas.contains(CGRect(x: 0, y: 0, width: 10, height: 100)))
        XCTAssertTrue(changedAreas.contains(CGRect(x: 100, y: 0, width: 10, height: 100)))
        XCTAssertEqual(
            changedAreas.reduce(0) { $0 + $1.width * $1.height },
            2_000,
            accuracy: 0.001
        )
    }

    func testDirtyRegionsHandleSelectionAppearingAndDisappearing() {
        let rect = CGRect(x: 20, y: 30, width: 40, height: 50)

        XCTAssertEqual(
            RegionDirtyRegionCalculator.changedAreas(from: nil, to: rect),
            [rect]
        )
        XCTAssertEqual(
            RegionDirtyRegionCalculator.changedAreas(from: rect, to: nil),
            [rect]
        )
        XCTAssertTrue(
            RegionDirtyRegionCalculator.changedAreas(from: rect, to: rect).isEmpty
        )
    }

    func testReusablePixelSamplerUsesTopOriginCoordinates() throws {
        let image = try ScreenCaptureService.compositeRegionImage(
            from: [
                DisplayRegionCapture(
                    image: solidImage(red: 255, green: 0, blue: 0),
                    globalRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    scale: 1
                ),
                DisplayRegionCapture(
                    image: solidImage(red: 0, green: 0, blue: 255),
                    globalRect: CGRect(x: 0, y: 1, width: 1, height: 1),
                    scale: 1
                ),
            ],
            selectedRegion: CGRect(x: 0, y: 0, width: 1, height: 2)
        )
        let sampler = try XCTUnwrap(RegionPixelSampler(image: image))

        XCTAssertEqual(sampler.color(x: 0, y: 0), RegionPixelColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(sampler.color(x: 0, y: 1), RegionPixelColor(red: 255, green: 0, blue: 0))
        XCTAssertNil(sampler.color(x: -1, y: 0))
        XCTAssertNil(sampler.color(x: 0, y: 2))
    }

    private func solidImage(red: Int, green: Int, blue: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [
                    CGFloat(red) / 255,
                    CGFloat(green) / 255,
                    CGFloat(blue) / 255,
                    1,
                ]
            )!
        )
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}

@MainActor
final class RegionCaptureCompositorTests: XCTestCase {
    func testVerticallyArrangedDisplayPiecesKeepCorrectOrientation() throws {
        let result = try ScreenCaptureService.compositeRegionImage(
            from: [
                DisplayRegionCapture(
                    image: solidImage(width: 2, height: 1, red: 255, green: 0, blue: 0),
                    globalRect: CGRect(x: 0, y: 0, width: 2, height: 1),
                    scale: 1
                ),
                DisplayRegionCapture(
                    image: solidImage(width: 2, height: 1, red: 0, green: 0, blue: 255),
                    globalRect: CGRect(x: 0, y: 1, width: 2, height: 1),
                    scale: 1
                ),
            ],
            selectedRegion: CGRect(x: 0, y: 0, width: 2, height: 2)
        )

        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
        assertPixel(result, x: 0, yFromTop: 0, red: 0, green: 0, blue: 255)
        assertPixel(result, x: 0, yFromTop: 1, red: 255, green: 0, blue: 0)
    }

    func testOffsetMonitorGapIsFilledBlack() throws {
        let result = try ScreenCaptureService.compositeRegionImage(
            from: [
                DisplayRegionCapture(
                    image: solidImage(width: 1, height: 1, red: 255, green: 0, blue: 0),
                    globalRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    scale: 1
                ),
                DisplayRegionCapture(
                    image: solidImage(width: 1, height: 1, red: 0, green: 0, blue: 255),
                    globalRect: CGRect(x: 2, y: 0, width: 1, height: 1),
                    scale: 1
                ),
            ],
            selectedRegion: CGRect(x: 0, y: 0, width: 3, height: 1)
        )

        assertPixel(result, x: 0, yFromTop: 0, red: 255, green: 0, blue: 0)
        assertPixel(result, x: 1, yFromTop: 0, red: 0, green: 0, blue: 0)
        assertPixel(result, x: 2, yFromTop: 0, red: 0, green: 0, blue: 255)
    }

    func testMixedScalePiecesUseHighestScaleCanvas() throws {
        let result = try ScreenCaptureService.compositeRegionImage(
            from: [
                DisplayRegionCapture(
                    image: solidImage(width: 1, height: 1, red: 255, green: 0, blue: 0),
                    globalRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    scale: 1
                ),
                DisplayRegionCapture(
                    image: solidImage(width: 2, height: 2, red: 0, green: 0, blue: 255),
                    globalRect: CGRect(x: 1, y: 0, width: 1, height: 1),
                    scale: 2
                ),
            ],
            selectedRegion: CGRect(x: 0, y: 0, width: 2, height: 1)
        )

        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 2)
        assertPixel(result, x: 0, yFromTop: 0, red: 255, green: 0, blue: 0)
        assertPixel(result, x: 3, yFromTop: 0, red: 0, green: 0, blue: 255)
    }

    private func solidImage(
        width: Int,
        height: Int,
        red: Int,
        green: Int,
        blue: Int
    ) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [
                    CGFloat(red) / 255,
                    CGFloat(green) / 255,
                    CGFloat(blue) / 255,
                    1,
                ]
            )!
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func assertPixel(
        _ image: CGImage,
        x: Int,
        yFromTop: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let providerData = image.dataProvider?.data else {
            XCTFail("The image has no pixel data.", file: file, line: line)
            return
        }

        let data = providerData as Data
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = yFromTop * image.bytesPerRow + x * bytesPerPixel
        guard bytesPerPixel >= 4, offset + 3 < data.count else {
            XCTFail("The requested pixel is outside the image data.", file: file, line: line)
            return
        }

        XCTAssertEqual(data[offset], red, file: file, line: line)
        XCTAssertEqual(data[offset + 1], green, file: file, line: line)
        XCTAssertEqual(data[offset + 2], blue, file: file, line: line)
        XCTAssertEqual(data[offset + 3], 255, file: file, line: line)
    }
}
