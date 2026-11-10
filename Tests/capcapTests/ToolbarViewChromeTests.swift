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

    // 分组间隙不能移动按钮到背景之外，按钮仍分发原来的工具动作
    func testGroupedToolbarPreservesHitTargetsAndActions() throws {
        for size in [Defaults.toolbarButtonSizeMin, Defaults.toolbarButtonSizeMax] {
            Defaults.toolbarButtonSize = size
            let items: [ToolbarItemID] = [.arrow, .undo, .ocr, .confirm]
            let toolbar = ToolbarView(items: items, orientation: .horizontal)
            toolbar.layout()
            XCTAssertEqual(toolbar.surfaceRects.count, 2)
            var triggered: [ToolbarItemID] = []
            toolbar.onItemTriggered = { triggered.append($0) }
            for item in items {
                let frame = try XCTUnwrap(toolbar.frame(for: item))
                XCTAssertTrue(toolbar.surfaceRects.contains { $0.contains(frame) })
                let hit = try XCTUnwrap(toolbar.hitTest(NSPoint(x: frame.midX, y: frame.midY)) as? ToolButton)
                hit.performClick(nil)
            }
            XCTAssertEqual(triggered, items)
        }
    }

    // 每次粗细预设点击只开启和提交一次调整，兼容选中标注的撤销机制
    func testStrokePresetCommitsOneAdjustment() throws {
        let control = StrokeSizeControl(
            frame: NSRect(x: 0, y: 0, width: 118, height: 24),
            sizes: [2, 4, 6], value: 3, minValue: 1, maxValue: 16)
        var events: [String] = []
        control.onEditingBegan = { events.append("begin") }
        control.onValueChanged = { events.append("value:\(Int($0))") }
        control.onEditingEnded = { events.append("end") }
        let mediumButton = try XCTUnwrap(control.subviews.compactMap { $0 as? NSButton }.first { $0.tag == 1 })
        mediumButton.performClick(nil)
        XCTAssertEqual(control.value, 4)
        XCTAssertEqual(events, ["begin", "value:4", "end"])
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
