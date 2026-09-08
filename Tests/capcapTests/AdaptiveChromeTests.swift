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

    // 检查新旧系统均采用短圆角玻璃，并保持原生模糊路径
    func testFrostedHUDViewInstallsRoundedGlassSurface() throws {
        let hud = FrostedHUDView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        hud.layoutSubtreeIfNeeded()

        if #available(macOS 26.0, *) {
            XCTAssertTrue(hud.usesLiquidGlass)
            let glass = try XCTUnwrap(hud.glassBackdrop as? NSGlassEffectView)
            XCTAssertEqual(glass.superview, hud)
            XCTAssertEqual(glass.style, .regular)
            XCTAssertTrue(glass.contentView === hud.contentHost)
            XCTAssertEqual(glass.frame, hud.bounds)
            XCTAssertEqual(glass.cornerRadius, 12, accuracy: 0.01)
            XCTAssertEqual(glass.tintColor, FrostedHUDChrome.glassTint)
        } else {
            XCTAssertFalse(hud.usesLiquidGlass)
            let glass = try XCTUnwrap(hud.glassBackdrop as? FrostedGlassBackdropView)
            XCTAssertEqual(glass.superview, hud)
            XCTAssertEqual(glass.material, .hudWindow)
            XCTAssertEqual(glass.blendingMode, .behindWindow)
            XCTAssertEqual(glass.state, .active)
            XCTAssertEqual(
                glass.frame,
                hud.bounds.insetBy(
                    dx: FrostedGlassBackdropView.edgeInset,
                    dy: FrostedGlassBackdropView.edgeInset
                )
            )
            let cornerRadius = try XCTUnwrap(glass.layer?.cornerRadius)
            XCTAssertEqual(cornerRadius, 12, accuracy: 0.01)
        }
    }

    func testFrostedHUDViewPlacesButtonsInsideGlassContent() {
        let hud = FrostedHUDView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        let button = NSView(frame: NSRect(x: 8, y: 6, width: 32, height: 32))
        hud.addSubview(button)
        hud.layoutSubtreeIfNeeded()

        XCTAssertEqual(button.superview, hud.contentHost)
        XCTAssertFalse(button.superview === hud)
    }

    // 检查亮边随横竖工具栏尺寸更新，且不会抢占按钮点击
    func testGlassBorderTracksResizeWithoutBlockingButtons() throws {
        let hud = FrostedHUDView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        let button = NSView(frame: NSRect(x: 8, y: 6, width: 32, height: 32))
        hud.addSubview(button)
        for size in [NSSize(width: 240, height: 44), NSSize(width: 44, height: 240)] {
            hud.setFrameSize(size)
            hud.layout()
            hud.layoutSubtreeIfNeeded()
            let border = try XCTUnwrap(hud.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
            XCTAssertEqual(border.lineWidth, 1)
            XCTAssertEqual(border.strokeColor?.alpha ?? 0, 0.30, accuracy: 0.01)
            XCTAssertNil(border.fillColor)
            XCTAssertEqual(border.path?.boundingBoxOfPath, hud.glassBackdrop.frame.insetBy(dx: 0.5, dy: 0.5))
            let target = hud.hitTest(NSPoint(x: 24, y: 22))
            XCTAssertTrue(target === button, "Unexpected hit target: \(String(describing: target))")
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
