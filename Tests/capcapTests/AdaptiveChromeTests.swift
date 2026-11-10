import AppKit
import XCTest
@testable import capcap

final class AdaptiveChromeTests: XCTestCase {
    func testAppearanceClassification() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertFalse(AdaptiveChrome.isDark(light))
        XCTAssertTrue(AdaptiveChrome.isDark(dark))
    }

    func testToolbarBackgroundResolvesDifferentlyAcrossAppearances() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightColor = try colorComponents(
            AdaptiveChrome.resolvedCGColor(AdaptiveChrome.toolbarBackground, for: light)
        )
        let darkColor = try colorComponents(
            AdaptiveChrome.resolvedCGColor(AdaptiveChrome.toolbarBackground, for: dark)
        )

        XCTAssertGreaterThan(lightColor.red, darkColor.red)
        XCTAssertGreaterThan(lightColor.green, darkColor.green)
        XCTAssertGreaterThan(lightColor.blue, darkColor.blue)
    }

    func testFloatingControlOriginUsesExternalTopRightPlacement() {
        let origin = FloatingControlChrome.origin(
            for: NSSize(width: 216, height: 32),
            relativeTo: NSRect(x: 100, y: 100, width: 300, height: 200),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(origin.x, 176)
        XCTAssertEqual(origin.y, 308)
    }

    func testFloatingControlOriginFallsBelowWhenTopSpaceIsUnavailable() {
        let origin = FloatingControlChrome.origin(
            for: NSSize(width: 216, height: 32),
            relativeTo: NSRect(x: 100, y: 700, width: 300, height: 180),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(origin.x, 176)
        XCTAssertEqual(origin.y, 660)
    }

    // 深浅主题下都使用稳定的炭灰底板，不让截图亮度改变图标对比度
    func testEditorHUDKeepsDarkAppearanceAndMatteSurface() throws {
        let hud = FrostedHUDView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        hud.layout()
        XCTAssertTrue(AdaptiveChrome.isDark(hud.effectiveAppearance))
        let surface = try XCTUnwrap(hud.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        let fill = try XCTUnwrap(surface.fillColor)
        XCTAssertGreaterThan(fill.alpha, 0.95)
        let components = try colorComponents(fill)
        XCTAssertEqual(components.red, components.green, accuracy: 0.01)
        XCTAssertLessThan(components.blue, 0.35)
    }

    // 底板更新和横竖布局变化后，按钮仍能接收点击
    func testMatteSurfaceTracksResizeWithoutBlockingButtons() throws {
        let hud = FrostedHUDView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        let button = NSView(frame: NSRect(x: 8, y: 6, width: 32, height: 32))
        hud.addSubview(button)
        for size in [NSSize(width: 240, height: 44), NSSize(width: 44, height: 240)] {
            hud.setFrameSize(size)
            hud.layout()
            hud.layoutSubtreeIfNeeded()
            let surface = try XCTUnwrap(hud.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
            XCTAssertEqual(surface.path?.boundingBoxOfPath, hud.bounds.insetBy(dx: 0.25, dy: 0.25))
            XCTAssertTrue(button.superview === hud.contentHost)
            XCTAssertTrue(hud.hitTest(NSPoint(x: 24, y: 22)) === button)
        }
    }

    private func colorComponents(_ color: CGColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let converted = try XCTUnwrap(
            color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        )
        let components = try XCTUnwrap(converted.components)
        XCTAssertGreaterThanOrEqual(components.count, 3)
        return (components[0], components[1], components[2])
    }
}
