import AppKit
import CoreText

private enum MagnifierLensPanelLayout {
    static let borderWidth: CGFloat = 1.5
    static let innerWidth: CGFloat = 176
    static let infoRowHeight: CGFloat = 23
    static let infoVerticalInset: CGFloat = 10
    static let cornerRadius: CGFloat = 10
    static let reticleSize: CGFloat = 9
    static let gridDivisionCount = 8
    static let background = NSColor(srgbRed: 0.17, green: 0.18, blue: 0.20, alpha: 0.94)
    static let gridColor = NSColor.white.withAlphaComponent(0.65)

    static var accent: NSColor {
        NSColor(srgbRed: 0, green: 0.80, blue: 1, alpha: 1)
    }

    static var panelWidth: CGFloat { innerWidth + borderWidth * 2 }

    static var showHistoryHint: Bool {
        Defaults.magnifierLensPanelShowFormatHint && Defaults.isHistoryCacheAvailable
    }

    static var infoRowCount: Int {
        2
            + (Defaults.magnifierLensPanelShowCopyHint ? 1 : 0)
            + (showHistoryHint ? 1 : 0)
    }

    static var infoHeight: CGFloat {
        CGFloat(infoRowCount) * infoRowHeight + infoVerticalInset * 2
    }

    static var panelSize: NSSize {
        NSSize(
            width: ceil(panelWidth),
            height: ceil(borderWidth * 2 + innerWidth + infoHeight)
        )
    }

    /// Odd source-pixel count so one pixel sits under the crosshair.
    static func sourcePixelCount(innerWidth: CGFloat) -> Int {
        let raw = Int((innerWidth / CGFloat(Defaults.magnifierLensPanelMagnification)).rounded())
        let odd = raw.isMultiple(of: 2) ? raw + 1 : raw
        return min(21, max(5, odd))
    }
}

/// Cursor-adjacent magnifier color picker shown on the overlay's idle state.
///
/// Replaces the legacy "drag to screenshot" cursor chip while the user has not
/// yet started dragging a selection rectangle. Displays absolute desktop
/// coordinates, a magnification of the pixel neighborhood around the cursor,
/// and the current pixel value in either HEX or RGB. Listens for mouse-move
/// events to follow the cursor but never blocks input. Visual values are read
/// from `Defaults`, whose fallback values define the built-in lens style.
final class MagnifierLensPanelWindow: NSPanel {

    enum Format {
        case hex
        case rgb
    }

    /// Single-pixel sRGB sample. Channels are 0-255 integers.
    struct Sample: Equatable {
        let r: Int
        let g: Int
        let b: Int
    }

    private static let edgeMargin: CGFloat = 8

    /// Computes the panel size that fits the square magnifier plus coordinate,
    /// color, and optional shortcut-hint rows.
    private static func computePanelSize() -> NSSize {
        MagnifierLensPanelLayout.panelSize
    }

    private let lensView: MagnifierLensPanelView
    private var mouseMonitor: Any?
    private let panelSize: NSSize
    private var pendingSnapshot: CGImage?
    private var pendingScreenFrame: NSRect = .zero
    private var pendingMouseLocation: NSPoint = .zero
    private var pendingFormat: Format = .hex
    private var hasPendingContent = false
    private var contentDisplayLink: CADisplayLink?
    private var lastAppliedPixelPoint: CGPoint?
    private var lastAppliedSample: Sample?
    private var lastAppliedFormat: Format?
    private var lastPanelOrigin: NSPoint?

    init() {
        let size = Self.computePanelSize()
        self.panelSize = size
        self.lensView = MagnifierLensPanelView(frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        sharingType = .none
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = lensView
    }

    deinit {
        stopTracking()
        stopContentDisplayLink()
    }

    func show() {
        orderFrontRegardless()
        startTracking()
        startContentDisplayLink()
        hasPendingContent = true
        pendingMouseLocation = NSEvent.mouseLocation
    }

    func dismiss() {
        stopTracking()
        stopContentDisplayLink()
        orderOut(nil)
    }

    func update(
        snapshot: CGImage?,
        screenFrame: NSRect,
        mouseLocation: NSPoint,
        format: Format
    ) {
        pendingSnapshot = snapshot
        pendingScreenFrame = screenFrame
        pendingMouseLocation = mouseLocation
        pendingFormat = format
        hasPendingContent = true
        startContentDisplayLink()
    }

    func setFormat(_ format: Format) {
        pendingFormat = format
        hasPendingContent = true
        startContentDisplayLink()
        lensView.format = format
    }

    func refreshDisplay() {
        lensView.needsDisplay = true
    }

    /// Returns the current sample and pixel location the lens is displaying.
    /// Used by the overlay controller to perform the actual copy on ⌘+C.
    var currentSample: Sample? { lensView.currentSample }
    var currentPixelPoint: CGPoint { lensView.currentPixelPoint }

    // MARK: - Position tracking

    private func startTracking() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self else { return event }
            self.pendingMouseLocation = NSEvent.mouseLocation
            self.hasPendingContent = true
            self.startContentDisplayLink()
            return event
        }
    }

    private func stopTracking() {
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
        }
    }

    private func startContentDisplayLink() {
        guard contentDisplayLink == nil else { return }
        let link = lensView.displayLink(
            target: self,
            selector: #selector(applyPendingContent)
        )
        contentDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func stopContentDisplayLink() {
        contentDisplayLink?.invalidate()
        contentDisplayLink = nil
        hasPendingContent = false
    }

    @objc private func applyPendingContent() {
        guard hasPendingContent else { return }
        hasPendingContent = false
        applyQueuedContent()
        updatePosition(mouseLocation: pendingMouseLocation)
    }

    private func applyQueuedContent() {
        guard let snapshot = pendingSnapshot else {
            if lastAppliedSample != nil {
                lensView.clear()
                lastAppliedSample = nil
                lastAppliedPixelPoint = nil
            }
            return
        }
        let pixelPoint = MagnifierLensPanelSampler.pixelCoordinate(
            globalPoint: pendingMouseLocation,
            screenFrame: pendingScreenFrame,
            snapshotSize: CGSize(width: snapshot.width, height: snapshot.height)
        )
        let sample = MagnifierLensPanelSampler.sample(image: snapshot, at: pixelPoint)
            ?? Sample(r: 0, g: 0, b: 0)
        guard lastAppliedPixelPoint != pixelPoint
                || lastAppliedSample != sample
                || lastAppliedFormat != pendingFormat else {
            return
        }
        lastAppliedPixelPoint = pixelPoint
        lastAppliedSample = sample
        lastAppliedFormat = pendingFormat
        lensView.update(
            sample: sample,
            pixelPoint: pixelPoint,
            mouseLocation: pendingMouseLocation,
            snapshot: snapshot,
            screenFrame: pendingScreenFrame,
            format: pendingFormat
        )
    }

    private func updatePosition(mouseLocation loc: NSPoint? = nil) {
        let loc = loc ?? NSEvent.mouseLocation
        let offsetX = CGFloat(Defaults.magnifierLensPanelOffsetX)
        let offsetY = CGFloat(Defaults.magnifierLensPanelOffsetY)
        // Default: panel sits directly below the cursor. AppKit panel origin
        // is the bottom-left corner, so panel.top = origin.y + height →
        // origin.y = cursor.y - offsetY - height.
        var origin = NSPoint(
            x: loc.x + offsetX,
            y: loc.y - offsetY - panelSize.height
        )
        if let screen = NSScreen.screens.first(where: { screen in
            let f = screen.frame
            return loc.x >= f.minX && loc.x <= f.maxX
                && loc.y >= f.minY && loc.y <= f.maxY
        }) {
            let frame = screen.frame
            let panelRight = origin.x + panelSize.width
            if panelRight > frame.maxX - Self.edgeMargin {
                origin.x = loc.x - offsetX - panelSize.width
            }
            if origin.y < frame.minY + Self.edgeMargin {
                origin.y = loc.y + offsetY
            }
        }
        if lastPanelOrigin != origin {
            lastPanelOrigin = origin
            setFrameOrigin(origin)
        }
    }
}

/// Pure helpers for reading a single pixel from a `CGImage` and mapping a
/// global mouse location onto the image's coordinate space. Kept as a free
/// namespace so unit tests can exercise them without an `NSPanel`.
enum MagnifierLensPanelSampler {

    /// Maps an AppKit global mouse location (y-up) onto the CGImage coordinate
    /// space (y-down) of the supplied snapshot, accounting for the screen's
    /// pixel-to-point scale factor.
    static func pixelCoordinate(
        globalPoint: NSPoint,
        screenFrame: NSRect,
        snapshotSize: CGSize
    ) -> CGPoint {
        let scaleX = snapshotSize.width / max(screenFrame.width, 1)
        let scaleY = snapshotSize.height / max(screenFrame.height, 1)
        let xInScreen = ((globalPoint.x - screenFrame.origin.x) * scaleX).rounded()
        let yInScreenFromTop = ((screenFrame.maxY - globalPoint.y) * scaleY).rounded()
        let maxX = max(0, snapshotSize.width - 1)
        let maxY = max(0, snapshotSize.height - 1)
        return CGPoint(
            x: min(max(0, xInScreen), maxX),
            y: min(max(0, yInScreenFromTop), maxY)
        )
    }

    /// Samples a single pixel from `image` at `point` (CGImage coords). Returns
    /// `nil` if the point lies outside the image bounds or the context cannot
    /// be allocated.
    static func sample(image: CGImage, at point: CGPoint) -> MagnifierLensPanelWindow.Sample? {
        guard point.x >= 0, point.y >= 0,
              point.x < CGFloat(image.width),
              point.y < CGFloat(image.height) else {
            return nil
        }
        let pixelX = Int(point.x)
        let pixelY = Int(point.y)
        let cropRect = CGRect(x: pixelX, y: pixelY, width: 1, height: 1)
        let sampledImage = image.cropping(to: cropRect) ?? image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .none
        if sampledImage === image {
            // Fallback for bitmaps that refuse a 1×1 crop: position the
            // target pixel onto the 1×1 context without resampling neighbors.
            let drawRect = CGRect(
                x: -point.x,
                y: 1 + point.y - CGFloat(image.height),
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
            context.draw(image, in: drawRect)
        } else {
            context.draw(sampledImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        return MagnifierLensPanelWindow.Sample(
            r: Int(pixelData[0]),
            g: Int(pixelData[1]),
            b: Int(pixelData[2])
        )
    }

    /// Picks the dark- or light-mode background color according to the user's
    /// `followSystemAppearance` preference. Pass `effectiveAppearance` from
    /// the view that needs to draw so this works regardless of AppKit quirks.
    static func backgroundColor(forAppearance appearance: NSAppearance) -> NSColor {
        if Defaults.magnifierLensPanelFollowSystemAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
            return isDark ? darkBackgroundColor() : lightBackgroundColor()
        }
        return darkBackgroundColor()
    }

    static func darkBackgroundColor() -> NSColor {
        NSColor(
            srgbRed: CGFloat(Defaults.magnifierLensPanelDarkBackgroundRed),
            green: CGFloat(Defaults.magnifierLensPanelDarkBackgroundGreen),
            blue: CGFloat(Defaults.magnifierLensPanelDarkBackgroundBlue),
            alpha: CGFloat(Defaults.magnifierLensPanelDarkBackgroundAlpha)
        )
    }

    static func lightBackgroundColor() -> NSColor {
        NSColor(
            srgbRed: CGFloat(Defaults.magnifierLensPanelLightBackgroundRed),
            green: CGFloat(Defaults.magnifierLensPanelLightBackgroundGreen),
            blue: CGFloat(Defaults.magnifierLensPanelLightBackgroundBlue),
            alpha: CGFloat(Defaults.magnifierLensPanelLightBackgroundAlpha)
        )
    }
}

final class MagnifierLensPanelView: NSView {

    var format: MagnifierLensPanelWindow.Format = .hex {
        didSet { needsDisplay = true }
    }

    private(set) var currentSample: MagnifierLensPanelWindow.Sample?
    private(set) var currentPixelPoint: CGPoint = .zero
    private var mouseLocation: NSPoint = .zero
    private var snapshot: CGImage?

    // Layout
    private let infoLeftPadding: CGFloat = 10
    private let infoRightPadding: CGFloat = 10
    private let infoColumnGap: CGFloat = 6

    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    private static let tipFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    func clear() {
        currentSample = nil
        snapshot = nil
        needsDisplay = true
    }

    func update(
        sample: MagnifierLensPanelWindow.Sample,
        pixelPoint: CGPoint,
        mouseLocation: NSPoint,
        snapshot: CGImage,
        screenFrame _: NSRect,
        format: MagnifierLensPanelWindow.Format
    ) {
        self.currentSample = sample
        self.currentPixelPoint = pixelPoint
        self.mouseLocation = mouseLocation
        self.snapshot = snapshot
        self.format = format
        needsDisplay = true
    }

    // 绘制统一的深色浮层背景、放大区域和青色外框
    override func draw(_ dirtyRect: NSRect) {
        let border = MagnifierLensPanelLayout.borderWidth
        let hudRect = bounds.insetBy(dx: border / 2, dy: border / 2)
        let inner = hudRect.insetBy(dx: border / 2, dy: border / 2)
        let bgPath = NSBezierPath(
            roundedRect: hudRect,
            xRadius: MagnifierLensPanelLayout.cornerRadius,
            yRadius: MagnifierLensPanelLayout.cornerRadius
        )
        MagnifierLensPanelLayout.background.setFill()
        bgPath.fill()
        NSGraphicsContext.current?.saveGraphicsState()
        bgPath.addClip()
        // 在圆角裁剪范围内绘制图像和信息，防止边角内容溢出
        drawContent(in: inner)
        NSGraphicsContext.current?.restoreGraphicsState()
        MagnifierLensPanelLayout.accent.setStroke()
        bgPath.lineWidth = border
        bgPath.lineJoinStyle = .round
        bgPath.stroke()
    }

    // 将正方形放大区域和下方信息区拼接为连续面板
    private func drawContent(in inner: NSRect) {
        let magnifiedRect = NSRect(
            x: inner.minX, y: inner.maxY - inner.width,
            width: inner.width, height: inner.width
        )
        drawMagnifiedArea(in: magnifiedRect)
        drawDivider(at: magnifiedRect.minY, in: inner)
        drawInfo(in: NSRect(
            x: inner.minX,
            y: inner.minY,
            width: inner.width,
            height: magnifiedRect.minY - inner.minY
        ))
    }

    // 用与外框相同的青色线分隔放大区域和信息区
    private func drawDivider(at y: CGFloat, in inner: NSRect) {
        MagnifierLensPanelLayout.accent.setStroke()
        let line = NSBezierPath()
        line.lineWidth = MagnifierLensPanelLayout.borderWidth
        line.move(to: NSPoint(x: inner.minX, y: y))
        line.line(to: NSPoint(x: inner.maxX, y: y))
        line.stroke()
    }

    private func drawMagnifiedArea(in rect: NSRect) {
        NSColor(calibratedWhite: 0.12, alpha: 0.55).setFill()
        NSBezierPath(rect: rect).fill()

        guard let snapshot else {
            drawGridAndReticle(in: rect)
            return
        }

        let pixelCount = MagnifierLensPanelLayout.sourcePixelCount(innerWidth: rect.width)
        let cell = rect.width / CGFloat(pixelCount)
        let half = CGFloat(pixelCount / 2)
        let desiredX = currentPixelPoint.x - half
        let desiredY = currentPixelPoint.y - half
        let sourceX = max(0, desiredX)
        let sourceY = max(0, desiredY)
        let clampedWidth = min(CGFloat(pixelCount), CGFloat(snapshot.width) - sourceX)
        let clampedHeight = min(CGFloat(pixelCount), CGFloat(snapshot.height) - sourceY)

        if clampedWidth > 0, clampedHeight > 0,
           let cropped = snapshot.cropping(to: CGRect(
            x: sourceX, y: sourceY, width: clampedWidth, height: clampedHeight
           )),
           let context = NSGraphicsContext.current?.cgContext {
            let missingLeft = sourceX - desiredX
            let cursorOffsetY = currentPixelPoint.y - sourceY
            let drawMaxY = rect.midY + (cursorOffsetY + 0.5) * cell
            let drawRect = NSRect(
                x: rect.minX + missingLeft * cell,
                y: drawMaxY - clampedHeight * cell,
                width: clampedWidth * cell,
                height: clampedHeight * cell
            )

            context.saveGState()
            context.clip(to: rect)
            context.interpolationQuality = .none
            context.draw(cropped, in: drawRect)
            context.restoreGState()
        }

        drawGridAndReticle(in: rect)
    }

    // 分层绘制像素网格、定位轴和中心取色框
    private func drawGridAndReticle(in rect: NSRect) {
        drawGuideGrid(in: rect)
        drawCrosshair(in: rect)
        drawSampleReticle(in: rect)
    }

    // 固定八等分辅助网格，中央分隔线由青色十字线单独绘制
    private func drawGuideGrid(in rect: NSRect) {
        let divisions = MagnifierLensPanelLayout.gridDivisionCount
        let cell = rect.width / CGFloat(divisions)
        MagnifierLensPanelLayout.gridColor.setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for i in 1..<divisions where i != divisions / 2 {
            let offset = CGFloat(i) * cell
            grid.move(to: NSPoint(x: rect.minX + offset, y: rect.minY))
            grid.line(to: NSPoint(x: rect.minX + offset, y: rect.maxY))
            grid.move(to: NSPoint(x: rect.minX, y: rect.minY + offset))
            grid.line(to: NSPoint(x: rect.maxX, y: rect.minY + offset))
        }
        grid.stroke()
    }

    // 绘制贯穿放大区域中心的青色十字定位线
    private func drawCrosshair(in rect: NSRect) {
        MagnifierLensPanelLayout.accent.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = MagnifierLensPanelLayout.borderWidth
        cross.move(to: NSPoint(x: rect.minX, y: rect.midY))
        cross.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        cross.move(to: NSPoint(x: rect.midX, y: rect.minY))
        cross.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        cross.stroke()
    }

    // 用当前像素填充中心小方框，避免十字线遮挡真实色值
    private func drawSampleReticle(in rect: NSRect) {
        let side = MagnifierLensPanelLayout.reticleSize
        let centerRect = NSRect(
            x: rect.midX - side / 2, y: rect.midY - side / 2,
            width: side, height: side
        )
        let sample = currentSample ?? .init(r: 43, g: 46, b: 51)
        NSColor(srgbRed: CGFloat(sample.r) / 255, green: CGFloat(sample.g) / 255,
                blue: CGFloat(sample.b) / 255, alpha: 1).setFill()
        let reticle = NSBezierPath(roundedRect: centerRect, xRadius: 1.5, yRadius: 1.5)
        reticle.fill()
        NSColor.white.setStroke()
        reticle.lineWidth = 1.5
        reticle.stroke()
    }

    // 依次绘制坐标、色值和已启用的快捷操作提示
    private func drawInfo(in area: NSRect) {
        let labelParagraphStyle = NSMutableParagraphStyle()
        labelParagraphStyle.lineBreakMode = .byTruncatingTail
        let valueParagraphStyle = NSMutableParagraphStyle()
        valueParagraphStyle.alignment = .right
        valueParagraphStyle.lineBreakMode = .byTruncatingHead

        let primaryText = NSColor.white
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: primaryText,
            .paragraphStyle: labelParagraphStyle,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.valueFont,
            .foregroundColor: primaryText,
            .paragraphStyle: valueParagraphStyle,
        ]
        let tipAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.tipFont,
            .foregroundColor: primaryText.withAlphaComponent(0.92),
        ]

        // 从信息区顶部计算固定行高，确保动态内容不会改变布局
        func rowY(forIndexFromTop i: Int) -> CGFloat {
            area.maxY
                - MagnifierLensPanelLayout.infoVerticalInset
                - CGFloat(i + 1) * MagnifierLensPanelLayout.infoRowHeight
        }

        var nextRow = 0
        if currentSample != nil {
            let coordsValue: String
            switch Defaults.magnifierLensPanelCoordinateMode {
            case .points:
                coordsValue = "\(Int(mouseLocation.x)), \(Int(mouseLocation.y))"
            case .pixels:
                coordsValue = "\(Int(currentPixelPoint.x)), \(Int(currentPixelPoint.y))"
            }
            drawInfoRow(
                label: L10n.magnifierLensPanelCoordinatesLabel,
                value: coordsValue,
                labelAttrs: labelAttrs,
                valueAttrs: valueAttrs,
                in: area,
                at: rowY(forIndexFromTop: nextRow)
            )
            nextRow += 1
        }

        if let sample = currentSample {
            let colorValue: String
            switch format {
            case .hex:
                colorValue = hexString(sample)
            case .rgb:
                colorValue = "\(sample.r), \(sample.g), \(sample.b)"
            }
            drawInfoRow(
                label: L10n.magnifierLensPanelColorValueLabel,
                value: colorValue,
                labelAttrs: labelAttrs,
                valueAttrs: valueAttrs,
                in: area,
                at: rowY(forIndexFromTop: nextRow)
            )
            nextRow += 1
        }

        if Defaults.magnifierLensPanelShowCopyHint {
            drawHintRow(
                label: L10n.magnifierLensPanelCopyHint,
                value: nil,
                attrs: tipAttrs,
                in: area,
                at: rowY(forIndexFromTop: nextRow)
            )
            nextRow += 1
        }
        if MagnifierLensPanelLayout.showHistoryHint {
            drawHintRow(
                label: L10n.magnifierLensPanelHistoryHint,
                value: nil,
                attrs: tipAttrs,
                in: area,
                at: rowY(forIndexFromTop: nextRow)
            )
        }
    }

    // 为坐标和颜色共用双列布局，给完整 RGB 数值预留可用空间
    private func drawInfoRow(
        label: String,
        value: String,
        labelAttrs: [NSAttributedString.Key: Any],
        valueAttrs: [NSAttributedString.Key: Any],
        in area: NSRect,
        at y: CGFloat
    ) {
        let valueRightEdge = area.maxX - infoRightPadding
        let availableColumnWidth = max(
            0,
            valueRightEdge - (area.minX + infoLeftPadding) - infoColumnGap
        )
        let measuredLabelWidth = ceil((label as NSString).size(withAttributes: labelAttrs).width)
        let labelWidth = min(measuredLabelWidth, floor(availableColumnWidth * 0.44))
        let valueX = area.minX + infoLeftPadding + labelWidth + infoColumnGap
        let valueWidth = max(0, valueRightEdge - valueX)
        let labelRect = NSRect(
            x: area.minX + infoLeftPadding,
            y: y,
            width: labelWidth,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        let valueRect = NSRect(
            x: valueX,
            y: y,
            width: valueWidth,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        let labelLine = coreTextLine(
            label,
            attrs: labelAttrs,
            fitting: labelRect.width,
            truncation: .end
        )
        let valueLine = coreTextLine(
            value,
            attrs: valueAttrs,
            fitting: valueRect.width,
            truncation: .start
        )
        drawCoreTextLine(labelLine, inkCenteredIn: labelRect, rightAligned: false)
        drawCoreTextLine(valueLine, inkCenteredIn: valueRect, rightAligned: true)
    }

    private func coreTextLine(
        _ text: String,
        attrs: [NSAttributedString.Key: Any],
        fitting width: CGFloat,
        truncation: CTLineTruncationType
    ) -> CTLine {
        let sourceLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attrs)
        )
        let sourceWidth = CGFloat(CTLineGetTypographicBounds(sourceLine, nil, nil, nil))
        guard sourceWidth > width else { return sourceLine }

        let tokenLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: "…", attributes: attrs)
        )
        return CTLineCreateTruncatedLine(
            sourceLine,
            Double(max(0, width)),
            truncation,
            tokenLine
        ) ?? sourceLine
    }

    private func drawCoreTextLine(
        _ line: CTLine,
        inkCenteredIn rect: NSRect,
        rightAligned: Bool
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var inkBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let typographicWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if inkBounds.isEmpty {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            inkBounds = CGRect(
                x: 0,
                y: -descent,
                width: typographicWidth,
                height: ascent + descent
            )
        }
        let originX = rightAligned
            ? rect.maxX - min(typographicWidth, rect.width)
            : rect.minX
        let baselineY = rect.midY - inkBounds.midY

        context.saveGState()
        context.clip(to: rect)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: originX, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawHintRow(
        label: String,
        value: String?,
        attrs: [NSAttributedString.Key: Any],
        in area: NSRect,
        at y: CGFloat
    ) {
        let rowRect = NSRect(
            x: area.minX + infoLeftPadding,
            y: y,
            width: area.width - infoLeftPadding - infoRightPadding,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        var labelRect = rowRect

        if let value {
            let sourceValueLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: value, attributes: attrs)
            )
            let valueWidth = min(
                rowRect.width,
                ceil(CGFloat(CTLineGetTypographicBounds(
                    sourceValueLine,
                    nil,
                    nil,
                    nil
                )))
            )
            let valueRect = NSRect(
                x: rowRect.maxX - valueWidth,
                y: y,
                width: valueWidth,
                height: MagnifierLensPanelLayout.infoRowHeight
            )
            labelRect.size.width = max(
                0,
                valueRect.minX - infoColumnGap - labelRect.minX
            )
            let valueLine = coreTextLine(
                value,
                attrs: attrs,
                fitting: valueRect.width,
                truncation: .end
            )
            drawCoreTextLine(valueLine, inkCenteredIn: valueRect, rightAligned: true)
        }

        let labelLine = coreTextLine(
            label,
            attrs: attrs,
            fitting: labelRect.width,
            truncation: .end
        )
        drawCoreTextLine(labelLine, inkCenteredIn: labelRect, rightAligned: false)
    }

    private func hexString(_ sample: MagnifierLensPanelWindow.Sample) -> String {
        String(format: "#%02X%02X%02X", sample.r, sample.g, sample.b)
    }
}
