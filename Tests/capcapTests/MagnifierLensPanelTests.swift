import XCTest
import AppKit
@testable import capcap

final class MagnifierLensPanelTests: XCTestCase {

    // 从实际渲染图验证每个象限四格，中心分隔线为青色且格内没有额外白线
    func testLensGridHasEightRowsAndColumnsWithCentralCyanDividers() throws {
        let bitmap = try renderLensPreview()
        let scale = CGFloat(bitmap.pixelsWide) / 179
        for division in 1..<8 {
            let position = 1.5 + CGFloat(division) * 22
            let vertical = try previewColor(bitmap, x: position, y: 12.5, scale: scale)
            let horizontal = try previewColor(bitmap, x: 12.5, y: position, scale: scale)
            for color in [vertical, horizontal] {
                XCTAssertGreaterThan(color.greenComponent, 0.45)
                XCTAssertGreaterThan(color.blueComponent, 0.45)
                if division == 4 {
                    XCTAssertLessThan(color.redComponent, 0.15)
                } else {
                    XCTAssertGreaterThan(color.redComponent, 0.45)
                }
            }
        }
        // 扫描两条穿过格子内部的线，防止旧版九等分网格叠加残留
        for coordinate in 3..<176 where (4...20).contains(coordinate % 22) {
            XCTAssertLessThan(try previewColor(bitmap, x: CGFloat(coordinate), y: 12.5, scale: scale).redComponent, 0.2)
            XCTAssertLessThan(try previewColor(bitmap, x: 12.5, y: CGFloat(coordinate), scale: scale).redComponent, 0.2)
        }
    }

    // 按视图坐标读取位图颜色，兼容普通与 Retina 缩放比例
    private func previewColor(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat,
                              scale: CGFloat) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
    }

    // 验证浅色系统外观下仍使用深色面板，中心色块不被十字线覆盖
    func testLensKeepsDarkBackgroundAndUnobscuredSample() throws {
        let bitmap = try renderLensPreview()
        let image = try XCTUnwrap(bitmap.cgImage)
        let scale = CGFloat(bitmap.pixelsWide) / 179
        let center = try XCTUnwrap(MagnifierLensPanelSampler.sample(
            image: image, at: CGPoint(x: 89.5 * scale, y: 89.5 * scale)
        ))
        // AppKit 的色彩空间转换可能产生一个色阶的舍入误差
        XCTAssertEqual(Double(center.r), 10, accuracy: 1)
        XCTAssertEqual(Double(center.g), 14, accuracy: 1)
        XCTAssertEqual(Double(center.b), 20, accuracy: 1)
        let background = try XCTUnwrap(bitmap.colorAt(
            x: Int(5 * scale), y: Int(205 * scale)
        )?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(background.redComponent, 0.14)
        XCTAssertLessThan(background.redComponent, 0.25)
        XCTAssertLessThan(background.greenComponent, 0.25)
        XCTAssertLessThan(background.blueComponent, 0.25)
        XCTAssertGreaterThan(background.alphaComponent, 0.9)
        if let path = ProcessInfo.processInfo.environment["CAPCAP_LENS_PREVIEW_PATH"] {
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    // 使用真实 AppKit 绘制路径生成与截图面板相同的位图
    private func renderLensPreview() throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let size = NSSize(width: 179, height: 291)
        let view = MagnifierLensPanelView(frame: NSRect(origin: .zero, size: size))
        view.appearance = NSAppearance(named: .aqua)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor(srgbRed: 10.0 / 255, green: 14.0 / 255,
                                    blue: 20.0 / 255, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        view.update(sample: .init(r: 10, g: 14, b: 20), pixelPoint: CGPoint(x: 16, y: 16),
                    mouseLocation: CGPoint(x: 2434, y: 1635), snapshot: try XCTUnwrap(context.makeImage()),
                    screenFrame: NSRect(x: 0, y: 0, width: 32, height: 32), format: .hex)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    func testPixelCoordinateMapsGlobalToImageSpace() {
        // Screen occupies (0, 0) → (1440, 900) in points. Snapshot is 2880×1800
        // (2x scale). Cursor is at the screen center (720, 450).
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let snapshotSize = CGSize(width: 2880, height: 1800)
        let globalPoint = NSPoint(x: 720, y: 450)

        let mapped = MagnifierLensPanelSampler.pixelCoordinate(
            globalPoint: globalPoint,
            screenFrame: screenFrame,
            snapshotSize: snapshotSize
        )

        XCTAssertEqual(mapped.x, 1440, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 900, accuracy: 0.001)
    }

    func testPixelCoordinateHandlesOffsetScreens() {
        // Secondary screen placed to the LEFT of the primary. Its AppKit frame
        // starts at x = -1920 and extends to x = 0. Cursor sits at the
        // secondary screen's center in absolute desktop coords.
        let screenFrame = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let snapshotSize = CGSize(width: 1920, height: 1080)
        let globalPoint = NSPoint(x: -960, y: 540)

        let mapped = MagnifierLensPanelSampler.pixelCoordinate(
            globalPoint: globalPoint,
            screenFrame: screenFrame,
            snapshotSize: snapshotSize
        )

        XCTAssertEqual(mapped.x, 960, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 540, accuracy: 0.001)
    }

    func testSampleReadsSinglePixelFromImage() throws {
        let width = 4
        let height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width

        // Build a 4x4 image where every pixel is the same RGB value
        // (152, 77, 23).
        var pixels = [UInt8]()
        pixels.reserveCapacity(bytesPerRow * height)
        for _ in 0..<(width * height) {
            pixels.append(contentsOf: [152, 77, 23, 255])
        }

        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        let sample = MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 2, y: 2))
        XCTAssertEqual(sample, MagnifierLensPanelWindow.Sample(r: 152, g: 77, b: 23))
    }

    /// Verifies the y-axis is read correctly: each row of the snapshot
    /// has a distinct colour so a flipped sample would be detected.
    func testSampleRespectsYAxisOrientation() throws {
        let width = 4
        let height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = 4 * width

        // Row 0 (top): red. Row 3 (bottom): blue. Middle rows: green.
        let rows: [[UInt8]] = [
            [255, 0,   0,   255],
            [0,   255, 0,   255],
            [0,   255, 0,   255],
            [0,   0,   255, 255],
        ]
        var pixels = [UInt8]()
        for row in rows {
            for _ in 0..<width { pixels.append(contentsOf: row) }
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        XCTAssertEqual(
            MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 2, y: 0)),
            MagnifierLensPanelWindow.Sample(r: 255, g: 0, b: 0)
        )
        XCTAssertEqual(
            MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 2, y: 3)),
            MagnifierLensPanelWindow.Sample(r: 0, g: 0, b: 255)
        )
        XCTAssertEqual(
            MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 2, y: 1)),
            MagnifierLensPanelWindow.Sample(r: 0, g: 255, b: 0)
        )
    }

    func testSampleRespectsXAxisOrientation() throws {
        let width = 4
        let height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = 4 * width
        let pixels: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 0, 255,
        ]
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        XCTAssertEqual(
            MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 0, y: 0)),
            MagnifierLensPanelWindow.Sample(r: 255, g: 0, b: 0)
        )
        XCTAssertEqual(
            MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 1, y: 0)),
            MagnifierLensPanelWindow.Sample(r: 0, g: 255, b: 0)
        )
        XCTAssertEqual(
            MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 2, y: 0)),
            MagnifierLensPanelWindow.Sample(r: 0, g: 0, b: 255)
        )
        XCTAssertEqual(
            MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 3, y: 0)),
            MagnifierLensPanelWindow.Sample(r: 255, g: 255, b: 0)
        )
    }

    func testPixelCoordinateClampsToValidRange() {
        // Mouse on the very top edge of the screen should map to the top row
        // (y=0), not out-of-bounds.
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let snapshotSize = CGSize(width: 2880, height: 1800)
        let mapped = MagnifierLensPanelSampler.pixelCoordinate(
            globalPoint: NSPoint(x: 720, y: 900), // top edge in AppKit coords
            screenFrame: screenFrame,
            snapshotSize: snapshotSize
        )
        XCTAssertEqual(mapped.y, 0, accuracy: 0.001)
    }

    func testSampleReturnsNilForOutOfBoundsPoint() throws {
        let width = 4
        let height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = 4 * width

        let pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        XCTAssertNil(MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: -1, y: 0)))
        XCTAssertNil(MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 0, y: -1)))
        XCTAssertNil(MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 4, y: 0)))
        XCTAssertNil(MagnifierLensPanelSampler.sample(image: image, at: CGPoint(x: 0, y: 4)))
    }

    func testHexStringFormat() {
        let sample = MagnifierLensPanelWindow.Sample(r: 0x98, g: 0x4D, b: 0x17)
        let hex = String(format: "#%02X%02X%02X", sample.r, sample.g, sample.b)
        XCTAssertEqual(hex, "#984D17")
    }

    func testRgbStringFormat() {
        let rgb = L10n.magnifierLensPanelRgbString(r: 152, g: 77, b: 23)
        XCTAssertTrue(rgb.contains("152"))
        XCTAssertTrue(rgb.contains("77"))
        XCTAssertTrue(rgb.contains("23"))
    }

    func testHintLabelsIncludeTheirShortcuts() {
        XCTAssertTrue(L10n.magnifierLensPanelCopyHint.contains("C"))
        XCTAssertTrue(L10n.magnifierLensPanelHistoryHint.contains("H"))
        XCTAssertFalse(L10n.magnifierLensPanelCopyHint.isEmpty)
        XCTAssertFalse(L10n.magnifierLensPanelHistoryHint.isEmpty)
        XCTAssertFalse(L10n.magnifierLensPanelAspectFree.isEmpty)
    }

    func testDefaultsLensVisualDefaults() {
        let keys = [
            "magnifierLensPanelMagnifiedSize",
            "magnifierLensPanelMagnification",
            "magnifierLensPanelOffsetX",
            "magnifierLensPanelOffsetY",
            "magnifierLensPanelShowCopyHint",
            "magnifierLensPanelShowShiftHint",
            "magnifierLensPanelFollowSystemAppearance",
            "magnifierLensPanelDarkBackgroundAlpha",
            "magnifierLensPanelLightBackgroundAlpha",
            "magnifierLensPanelDarkBackgroundRed",
            "magnifierLensPanelLightBackgroundGreen",
            "magnifierLensPanelCrosshairRed",
            "magnifierLensPanelCrosshairGreen",
            "magnifierLensPanelCrosshairBlue",
            "magnifierLensPanelCrosshairAlpha",
            "magnifierLensPanelCrosshairWidth",
        ]
        defer {
            for key in keys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        // Magnified size defaults to 144.
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelMagnifiedSize")
        XCTAssertEqual(Defaults.magnifierLensPanelMagnifiedSize, 144)
        Defaults.magnifierLensPanelMagnifiedSize = 123
        XCTAssertEqual(Defaults.magnifierLensPanelMagnifiedSize, 144)
        Defaults.magnifierLensPanelMagnifiedSize = 192
        XCTAssertEqual(Defaults.magnifierLensPanelMagnifiedSize, 192)
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelMagnification")
        XCTAssertEqual(Defaults.magnifierLensPanelMagnification, 22.0, accuracy: 0.001)
        Defaults.magnifierLensPanelMagnification = .infinity
        XCTAssertEqual(Defaults.magnifierLensPanelMagnification, 22.0, accuracy: 0.001)
        Defaults.magnifierLensPanelMagnification = 0.25
        XCTAssertEqual(Defaults.magnifierLensPanelMagnification, 1.0, accuracy: 0.001)
        Defaults.magnifierLensPanelMagnification = 40
        XCTAssertEqual(Defaults.magnifierLensPanelMagnification, 32.0, accuracy: 0.001)
        Defaults.magnifierLensPanelMagnification = 8
        XCTAssertEqual(Defaults.magnifierLensPanelMagnification, 8.0, accuracy: 0.001)
        // Offsets default to (15, 15).
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelOffsetX")
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelOffsetY")
        XCTAssertEqual(Defaults.magnifierLensPanelOffsetX, 15)
        XCTAssertEqual(Defaults.magnifierLensPanelOffsetY, 15)
        // Hint toggles default on.
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelShowCopyHint")
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelShowShiftHint")
        XCTAssertTrue(Defaults.magnifierLensPanelShowCopyHint)
        XCTAssertTrue(Defaults.magnifierLensPanelShowFormatHint)
        // Follow-system defaults on; dark/light RGBA defaults match docs.
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelFollowSystemAppearance")
        XCTAssertTrue(Defaults.magnifierLensPanelFollowSystemAppearance)
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelDarkBackgroundAlpha")
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelLightBackgroundAlpha")
        XCTAssertEqual(Defaults.magnifierLensPanelDarkBackgroundAlpha, 0.8, accuracy: 0.001)
        XCTAssertEqual(Defaults.magnifierLensPanelLightBackgroundAlpha, 0.8, accuracy: 0.001)
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelCrosshairRed")
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelCrosshairGreen")
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelCrosshairBlue")
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelCrosshairAlpha")
        UserDefaults.standard.removeObject(forKey: "magnifierLensPanelCrosshairWidth")
        XCTAssertEqual(Defaults.magnifierLensPanelCrosshairRed, 0xA8 / 255.0, accuracy: 0.001)
        XCTAssertEqual(Defaults.magnifierLensPanelCrosshairGreen, 0xBD / 255.0, accuracy: 0.001)
        XCTAssertEqual(Defaults.magnifierLensPanelCrosshairBlue, 0xFC / 255.0, accuracy: 0.001)
        XCTAssertEqual(Defaults.magnifierLensPanelCrosshairAlpha, 0.65, accuracy: 0.001)
        XCTAssertEqual(Defaults.magnifierLensPanelCrosshairWidth, 6.0, accuracy: 0.001)
        // Alpha setter clamps to 0…1.
        Defaults.magnifierLensPanelDarkBackgroundAlpha = 5
        XCTAssertEqual(Defaults.magnifierLensPanelDarkBackgroundAlpha, 1.0, accuracy: 0.001)
        Defaults.magnifierLensPanelDarkBackgroundAlpha = -1
        XCTAssertEqual(Defaults.magnifierLensPanelDarkBackgroundAlpha, 0.0, accuracy: 0.001)
        Defaults.magnifierLensPanelDarkBackgroundRed = 5
        XCTAssertEqual(Defaults.magnifierLensPanelDarkBackgroundRed, 1.0, accuracy: 0.001)
        Defaults.magnifierLensPanelDarkBackgroundRed = -1
        XCTAssertEqual(Defaults.magnifierLensPanelDarkBackgroundRed, 0.0, accuracy: 0.001)
        Defaults.magnifierLensPanelLightBackgroundGreen = 5
        XCTAssertEqual(Defaults.magnifierLensPanelLightBackgroundGreen, 1.0, accuracy: 0.001)
        Defaults.magnifierLensPanelLightBackgroundGreen = -1
        XCTAssertEqual(Defaults.magnifierLensPanelLightBackgroundGreen, 0.0, accuracy: 0.001)
        Defaults.magnifierLensPanelCrosshairBlue = 5
        XCTAssertEqual(Defaults.magnifierLensPanelCrosshairBlue, 1.0, accuracy: 0.001)
        Defaults.magnifierLensPanelCrosshairBlue = -1
        XCTAssertEqual(Defaults.magnifierLensPanelCrosshairBlue, 0.0, accuracy: 0.001)
    }
}
