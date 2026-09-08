import AppKit
import XCTest

@testable import capcap

final class ToolbarViewChromeTests: XCTestCase {
    private let toolbarSizeKey = "toolbarButtonSize"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: toolbarSizeKey)
        Defaults.toolbarButtonSize = Defaults.toolbarButtonSizeDefault
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: toolbarSizeKey)
        super.tearDown()
    }

    func testToolbarPreferredSizeIsCompact() {
        Defaults.toolbarButtonSize = 26
        let toolbar = ToolbarView(items: [.confirm, .save, .pin], orientation: .horizontal)

        XCTAssertEqual(ToolbarView.buttonSize, 26)
        XCTAssertEqual(toolbar.preferredSize.height, 34)
        let expectedWidth: CGFloat = 10 * 2 + 26 * 3 + 4 * 2
        XCTAssertEqual(toolbar.preferredSize.width, expectedWidth)
    }

    func testVerticalToolbarPreferredSizeIsCompact() {
        Defaults.toolbarButtonSize = 26
        let toolbar = ToolbarView(items: [.confirm, .save], orientation: .vertical)

        XCTAssertEqual(toolbar.preferredSize.width, 34)
        let expectedHeight: CGFloat = 10 * 2 + 26 * 2 + 4
        XCTAssertEqual(toolbar.preferredSize.height, expectedHeight)
    }

    func testToolbarPreferredSizeFollowsConfiguredButtonSize() {
        Defaults.toolbarButtonSize = 32
        let toolbar = ToolbarView(items: [.confirm], orientation: .horizontal)

        XCTAssertEqual(ToolbarView.buttonSize, 32)
        XCTAssertEqual(
            toolbar.preferredSize.height,
            ToolbarView.buttonSize + ToolbarView.crossPadding * 2
        )
        XCTAssertGreaterThan(toolbar.preferredSize.height, 34)
    }

    func testToolbarButtonSizeClampsToSupportedRange() {
        Defaults.toolbarButtonSize = 8
        XCTAssertEqual(Defaults.toolbarButtonSize, Defaults.toolbarButtonSizeMin)
        Defaults.toolbarButtonSize = 80
        XCTAssertEqual(Defaults.toolbarButtonSize, Defaults.toolbarButtonSizeMax)
    }

    func testToolButtonHoverLightsBackground() throws {
        let button = ToolButton(
            frame: NSRect(x: 0, y: 0, width: 26, height: 26),
            symbolName: "pencil",
            normalColor: .white,
            selectedColor: NSColor.systemGreen
        )

        XCTAssertFalse(button.isHovered)
        let idleAlpha = try sampleFillAlpha(in: button)

        button.mouseEntered(with: try hoverEvent())
        XCTAssertTrue(button.isHovered)
        let hoveredAlpha = try sampleFillAlpha(in: button)

        XCTAssertGreaterThan(hoveredAlpha, idleAlpha + 0.04)
        XCTAssertGreaterThan(hoveredAlpha, 0.08)

        button.mouseExited(with: try hoverEvent())
        XCTAssertFalse(button.isHovered)
    }

    func testSelectedToolButtonKeepsSelectedFillWhileHovered() throws {
        let button = ToolButton(
            frame: NSRect(x: 0, y: 0, width: 26, height: 26),
            symbolName: "pencil",
            normalColor: .white,
            selectedColor: NSColor.systemGreen
        )
        button.isSelected = true
        let selectedAlpha = try sampleFillAlpha(in: button)

        button.mouseEntered(with: try hoverEvent())
        XCTAssertTrue(button.isHovered)
        let hoveredSelectedAlpha = try sampleFillAlpha(in: button)

        XCTAssertEqual(hoveredSelectedAlpha, selectedAlpha, accuracy: 0.03)
        XCTAssertGreaterThan(selectedAlpha, 0.08)
    }

    private func sampleFillAlpha(in button: ToolButton) throws -> CGFloat {
        let width = Int(button.bounds.width)
        let height = Int(button.bounds.height)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = button.bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        button.bounds.fill()
        button.draw(button.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let color = try XCTUnwrap(
            rep.colorAt(x: 5, y: height / 2)?.usingColorSpace(.deviceRGB)
        )
        return color.alphaComponent
    }

    private func hoverEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        ))
    }
}
