import AppKit
import QuartzCore
import XCTest

@testable import capcap

final class CaptureSelectionChromeTests: XCTestCase {
    private let borderKeys = [
        "selectionBorderRed",
        "selectionBorderGreen",
        "selectionBorderBlue"
    ]

    override func setUp() {
        super.setUp()
        borderKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        borderKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testOverlayPathUsesRoundedRectAtRequestedRadius() {
        let rect = CGRect(x: 10, y: 20, width: 200, height: 120)
        let path = CaptureSelectionChrome.path(for: rect, radius: 16)
        let expected = CGPath(
            roundedRect: rect,
            cornerWidth: 16,
            cornerHeight: 16,
            transform: nil
        )
        XCTAssertEqual(path, expected)
    }

    func testOverlayPathIsARectWhenRadiusIsZero() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 40)
        let path = CaptureSelectionChrome.path(for: rect, radius: 0)
        XCTAssertEqual(path, CGPath(rect: rect, transform: nil))
    }

    func testOverlayPathClampsRadiusToHalfTheShortSide() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 80)
        let path = CaptureSelectionChrome.path(for: rect, radius: 40)
        let expected = CGPath(
            roundedRect: rect,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        XCTAssertEqual(path, expected)
    }

    // 验证选区默认使用参考图中的白色轮廓
    func testSelectionBorderColorDefaultsToWhite() {
        XCTAssertEqual(Defaults.selectionBorderRed, 255)
        XCTAssertEqual(Defaults.selectionBorderGreen, 255)
        XCTAssertEqual(Defaults.selectionBorderBlue, 255)

        let color = CaptureSelectionChrome.borderColor.usingColorSpace(.sRGB)
        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(color?.greenComponent ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(color?.blueComponent ?? -1, 1, accuracy: 0.01)
    }

    func testSelectionBorderChannelsClampToByteRange() {
        Defaults.selectionBorderRed = 400
        Defaults.selectionBorderGreen = -8
        Defaults.selectionBorderBlue = 12
        XCTAssertEqual(Defaults.selectionBorderRed, 255)
        XCTAssertEqual(Defaults.selectionBorderGreen, 0)
        XCTAssertEqual(Defaults.selectionBorderBlue, 12)
    }

    func testSelectionViewBorderUsesConfiguredRGBAndRoundedPath() throws {
        let savedRadius = UserDefaults.standard.object(forKey: "windowCornerRadius")
        Defaults.windowCornerRadius = 18
        Defaults.selectionBorderRed = 255
        Defaults.selectionBorderGreen = 0
        Defaults.selectionBorderBlue = 128
        defer {
            if let savedRadius {
                UserDefaults.standard.set(savedRadius, forKey: "windowCornerRadius")
            } else {
                UserDefaults.standard.removeObject(forKey: "windowCornerRadius")
            }
        }

        let view = SelectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let selection = NSRect(x: 50, y: 40, width: 180, height: 100)
        view.updateSelectionRect(selection)
        view.layout()

        let border = try XCTUnwrap(borderShapeLayer(in: view))
        XCTAssertNil(border.lineDashPattern)
        let expected = try XCTUnwrap(sRGBComponents(CaptureSelectionChrome.borderColor.cgColor))
        let actual = try XCTUnwrap(sRGBComponents(border.strokeColor))
        XCTAssertEqual(actual.red, expected.red, accuracy: 0.02)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0.02)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0.02)

        let borderRect = selection.insetBy(dx: -1, dy: -1)
        XCTAssertEqual(
            border.path,
            CaptureSelectionChrome.path(for: borderRect, radius: 18)
        )

        let dimming = try XCTUnwrap(dimmingShapeLayer(in: view))
        XCTAssertEqual(dimming.fillRule, .evenOdd)
        let dimmingPath = try XCTUnwrap(dimming.path)
        XCTAssertFalse(
            dimmingPath.contains(CGPoint(x: selection.midX, y: selection.midY), using: .evenOdd)
        )
        XCTAssertTrue(
            dimmingPath.contains(
                CGPoint(x: selection.minX + 1, y: selection.minY + 1),
                using: .evenOdd
            )
        )
    }

    func testRegionCaptureExportAppliesConfiguredCornerRadius() throws {
        let savedRadius = UserDefaults.standard.object(forKey: "windowCornerRadius")
        Defaults.windowCornerRadius = 20
        defer {
            if let savedRadius {
                UserDefaults.standard.set(savedRadius, forKey: "windowCornerRadius")
            } else {
                UserDefaults.standard.removeObject(forKey: "windowCornerRadius")
            }
        }

        let image = makeOpaqueImage(width: 80, height: 80)
        let shaped = WindowEffects.applyCaptureCornerRadius(image)
        XCTAssertEqual(try alpha(at: CGPoint(x: 0, y: 0), in: shaped), 0)
        XCTAssertEqual(try alpha(at: CGPoint(x: 40, y: 40), in: shaped), 255)
    }

    // 验证经过窗口时不出现亮区或尺寸提示，主动单击后才形成选区
    func testIdleWindowHoverDoesNotExposeAnUnselectedWindow() throws {
        let (window, view) = try makeWindowHoverFixture()
        defer { window.contentView = nil }
        view.mouseMoved(with: try mouseEvent(.mouseMoved, in: window))
        XCTAssertNil(view.currentSelectionRect)
        let mask = try XCTUnwrap(dimmingShapeLayer(in: view)?.path)
        XCTAssertEqual(mask, CGPath(rect: view.bounds, transform: nil))
        XCTAssertTrue(try XCTUnwrap(borderShapeLayer(in: view)).isHidden)
        XCTAssertTrue(try XCTUnwrap(view.subviews.last).isHidden)

        // 主动单击仍能捕获识别到的窗口，证明测试确实经过了窗口检测分支
        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: window))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: window))
        XCTAssertEqual(view.currentSelectionRect, NSRect(x: 50, y: 50, width: 200, height: 150))
        let selectedMask = try XCTUnwrap(dimmingShapeLayer(in: view)?.path)
        XCTAssertFalse(selectedMask.contains(CGPoint(x: 100, y: 100), using: .evenOdd))
    }

    // 创建固定窗口检测快照，不依赖桌面上真实应用的窗口布局
    private func makeWindowHoverFixture() throws -> (NSWindow, SelectionView) {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        let detector = WindowDetector()
        detector.apply([DetectedWindow(name: "Fixture", windowID: 42, layer: 0,
                                        frame: CGRect(x: screen.frame.minX + 50,
                                                      y: screen.frame.height - 200,
                                                      width: 200, height: 150))])
        view.windowDetector = detector
        return (window, view)
    }

    // 生成测试鼠标事件，所有事件落在已知候选窗口内部
    private func mouseEvent(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100),
                                        modifierFlags: [], timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil,
                                        eventNumber: 0, clickCount: 1, pressure: 0))
    }

    private func sRGBComponents(_ color: CGColor?) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try XCTUnwrap(
            color?.converted(to: space, intent: .defaultIntent, options: nil)
        )
        let components = try XCTUnwrap(converted.components)
        XCTAssertGreaterThanOrEqual(components.count, 3)
        return (components[0], components[1], components[2])
    }

    private func borderShapeLayer(in view: SelectionView) -> CAShapeLayer? {
        overlayShapeLayers(in: view).first { layer in
            layer.fillColor == nil || (layer.fillColor?.alpha ?? 1) == 0
        }
    }

    private func dimmingShapeLayer(in view: SelectionView) -> CAShapeLayer? {
        overlayShapeLayers(in: view).first { $0.fillRule == .evenOdd }
    }

    private func overlayShapeLayers(in view: SelectionView) -> [CAShapeLayer] {
        view.subviews.flatMap { subview in
            (subview.layer?.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        }
    }

    private func makeOpaqueImage(width: Int, height: Int) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let cgImage = pixels.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
        return NSImage(
            cgImage: cgImage!,
            size: NSSize(width: width, height: height)
        )
    }

    private func alpha(at point: CGPoint, in image: NSImage) throws -> UInt8 {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let pixel = try XCTUnwrap(cgImage.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        let drew = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(drew)
        return rgba[3]
    }
}
