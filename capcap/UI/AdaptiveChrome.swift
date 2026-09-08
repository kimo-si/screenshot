import AppKit

/// Shared semantic colors for capcap's floating dialogs and editor chrome
///
/// AppKit semantic colors already follow the effective appearance when they
/// are used for text or drawing. Layer colors are different: assigning a
/// `CGColor` resolves the color once, so layer-backed views must resolve again
/// from `viewDidChangeEffectiveAppearance`
enum AdaptiveChrome {
    static let floatingBackground = NSColor(
        name: NSColor.Name("capcap.floatingBackground")
    ) { appearance in
        isDark(appearance)
            ? NSColor(white: 0.15, alpha: 0.94)
            : NSColor(white: 0.98, alpha: 0.96)
    }

    static let toolbarBackground = NSColor(
        name: NSColor.Name("capcap.toolbarBackground")
    ) { appearance in
        isDark(appearance)
            ? NSColor(white: 0.12, alpha: 0.90)
            : NSColor(white: 0.97, alpha: 0.94)
    }

    static let panelBackground = NSColor(
        name: NSColor.Name("capcap.panelBackground")
    ) { appearance in
        isDark(appearance)
            ? NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 0.98)
            : NSColor(calibratedRed: 0.97, green: 0.975, blue: 0.985, alpha: 0.98)
    }

    static let popoverBackground = NSColor(
        name: NSColor.Name("capcap.popoverBackground")
    ) { appearance in
        isDark(appearance)
            ? NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
            : NSColor(calibratedWhite: 0.99, alpha: 1)
    }

    static let cardBackground = NSColor(
        name: NSColor.Name("capcap.cardBackground")
    ) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.055)
    }

    static let border = NSColor(
        name: NSColor.Name("capcap.border")
    ) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.16)
    }

    static let subtleFill = NSColor(
        name: NSColor.Name("capcap.subtleFill")
    ) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.08)
    }

    static let selectedFill = NSColor(
        name: NSColor.Name("capcap.selectedFill")
    ) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.15)
            : NSColor.black.withAlphaComponent(0.10)
    }

    static let hoverFill = NSColor(
        name: NSColor.Name("capcap.hoverFill")
    ) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.22)
            : NSColor.black.withAlphaComponent(0.10)
    }

    static let separator = NSColor(
        name: NSColor.Name("capcap.separator")
    ) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.20)
            : NSColor.black.withAlphaComponent(0.16)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func resolvedColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }

    static func resolvedCGColor(_ color: NSColor, for appearance: NSAppearance) -> CGColor {
        resolvedColor(color, for: appearance).cgColor
    }
}

/// Shared geometry and surface metrics for compact floating operation bars
/// such as the recording HUD and the PIN image toolbar
enum FloatingControlChrome {
    static let height: CGFloat = 32
    static let buttonSide: CGFloat = 24
    static let cornerRadius: CGFloat = 10
    static let borderWidth: CGFloat = 0.5
    static let gap: CGFloat = 8
    static let screenEdgeInset: CGFloat = 4

    static func origin(
        for size: NSSize,
        relativeTo anchorRect: NSRect,
        visibleFrame: NSRect?
    ) -> NSPoint {
        var origin = NSPoint(
            x: anchorRect.maxX - size.width - gap,
            y: anchorRect.maxY + gap
        )

        guard let visibleFrame else { return origin }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = anchorRect.minY - size.height - gap
        }
        origin.x = max(
            visibleFrame.minX + screenEdgeInset,
            min(origin.x, visibleFrame.maxX - size.width - screenEdgeInset)
        )
        origin.y = max(
            visibleFrame.minY + screenEdgeInset,
            min(origin.y, visibleFrame.maxY - size.height - screenEdgeInset)
        )
        return origin
    }
}

/// Layer-backed rounded surface whose colors continue to follow live system
/// appearance changes
final class AdaptiveChromeSurfaceView: NSView {
    enum Style {
        case floating
        case toolbar
        case panel
        case popover
        case card

        var backgroundColor: NSColor {
            switch self {
            case .floating: return AdaptiveChrome.floatingBackground
            case .toolbar: return AdaptiveChrome.toolbarBackground
            case .panel: return AdaptiveChrome.panelBackground
            case .popover: return AdaptiveChrome.popoverBackground
            case .card: return AdaptiveChrome.cardBackground
            }
        }
    }

    var style: Style {
        didSet { applyAppearance() }
    }
    var cornerRadius: CGFloat {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var borderWidth: CGFloat {
        didSet { layer?.borderWidth = borderWidth }
    }

    init(style: Style, cornerRadius: CGFloat = 0, borderWidth: CGFloat = 0) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = cornerRadius > 0
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.borderWidth = borderWidth
        layer.backgroundColor = AdaptiveChrome.resolvedCGColor(style.backgroundColor, for: effectiveAppearance)
        layer.borderColor = AdaptiveChrome.resolvedCGColor(AdaptiveChrome.border, for: effectiveAppearance)
    }
}

/// A one-pixel semantic separator for layer-composited HUD layouts
final class AdaptiveSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        layer?.backgroundColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.separator,
            for: effectiveAppearance
        )
    }
}

// 按参考图统一编辑工具栏的深灰玻璃、低饱和透色和图标配色
enum FrostedHUDChrome {
    static let cornerRadius: CGFloat = 12
    static let borderWidth: CGFloat = 1
    static let borderColor = NSColor.white.withAlphaComponent(0.30)
    static let glassTint = color(0x2C2D30, alpha: 0.75)
    static let iconColor = color(0xD3D6D8)
    static let cancelColor = color(0xFF3038)
    static let saveColor = color(0x00A9FF)
    static let confirmColor = color(0x00DF9A)
    static let emojiColor = color(0x7651F5)
    static let surfaceColors = [0x2C2D30, 0x324052, 0x3D4D52, 0x414649,
                                0x395056, 0x324354, 0x2C2D30].map { color($0, alpha: 0.90) }
    static let highlightColors = [NSColor.white.withAlphaComponent(0.13), NSColor.white.withAlphaComponent(0)]

    // 将参考图的 sRGB 色值转换为 AppKit 颜色，集中管理透明度
    private static func color(_ rgb: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

/// Frosted-glass backdrop used on macOS versions that don't have Liquid Glass.
final class FrostedGlassBackdropView: NSVisualEffectView {
    static let edgeInset: CGFloat = 2

    // 配置原生背景模糊与深灰透光层，边框由外层统一绘制
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = FrostedHUDChrome.glassTint.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 采用参考图中的短圆角，而不是半圆端头
    func applyCornerRadius() {
        layer?.cornerRadius = min(FrostedHUDChrome.cornerRadius, min(bounds.width, bounds.height) / 2)
    }
}

/// Shared host for the editor's rounded frosted-glass HUDs.
///
/// On macOS 26+ this is real Liquid Glass (`NSGlassEffectView`). Older systems
/// fall back to a HUD visual-effect capsule. Buttons must live in
/// `contentHost` so the glass can treat them as its content and keep them
/// legible as it adapts to the screenshot underneath.
class FrostedHUDView: NSView {
    let glassBackdrop: NSView
    let contentHost = NSView()
    private let borderLayer = CAShapeLayer()
    private let surfaceColorLayer = CAGradientLayer()
    private let highlightLayer = CAGradientLayer()

    var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return glassBackdrop is NSGlassEffectView
        }
        return false
    }

    // 使用原生玻璃承载工具按钮，并统一深灰色调
    override init(frame frameRect: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frameRect)
            glass.style = .regular
            glass.tintColor = FrostedHUDChrome.glassTint
            glass.contentView = contentHost
            glassBackdrop = glass
        } else {
            glassBackdrop = FrostedGlassBackdropView(frame: frameRect)
        }
        super.init(frame: frameRect)
        configureChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func addSubview(_ view: NSView) {
        if view === glassBackdrop || view === contentHost {
            super.addSubview(view)
            return
        }
        contentHost.addSubview(view)
    }

    override func addSubview(
        _ view: NSView,
        positioned place: NSWindow.OrderingMode,
        relativeTo otherView: NSView?
    ) {
        if view === glassBackdrop || view === contentHost {
            super.addSubview(view, positioned: place, relativeTo: otherView)
            return
        }
        contentHost.addSubview(view, positioned: place, relativeTo: otherView)
    }

    override func layout() {
        super.layout()
        layoutChrome()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Liquid Glass supplies its own depth and edge lighting. The fallback
        // HUD still needs a drop shadow around the punched capsule.
        guard !usesLiquidGlass else { return }

        let inner = bounds.insetBy(
            dx: FrostedGlassBackdropView.edgeInset,
            dy: FrostedGlassBackdropView.edgeInset
        )
        guard inner.width > 0, inner.height > 0 else { return }
        let radius = min(FrostedHUDChrome.cornerRadius, min(inner.width, inner.height) / 2)
        let path = NSBezierPath(roundedRect: inner, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // 固定深色外观以保持白色图标清晰，并在玻璃表面上方添加连续亮边
    private func configureChrome() {
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        contentHost.autoresizingMask = [.width, .height]
        // 在原生模糊之上稳定参考图配色，避免桌面亮度把工具栏染成银白色
        configureSurfaceColors()
        if usesLiquidGlass {
            super.addSubview(glassBackdrop)
        } else {
            super.addSubview(glassBackdrop, positioned: .below, relativeTo: nil)
            super.addSubview(contentHost)
        }
        borderLayer.fillColor = nil
        borderLayer.strokeColor = FrostedHUDChrome.borderColor.cgColor
        borderLayer.lineWidth = FrostedHUDChrome.borderWidth
        borderLayer.zPosition = 1
        layer?.addSublayer(borderLayer)
        layoutChrome()
    }

    // 色层置于按钮下方，保留原生模糊和内容的点击区域
    private func configureSurfaceColors() {
        contentHost.wantsLayer = true
        surfaceColorLayer.colors = FrostedHUDChrome.surfaceColors.map(\.cgColor)
        highlightLayer.colors = FrostedHUDChrome.highlightColors.map(\.cgColor)
        surfaceColorLayer.zPosition = -2
        highlightLayer.zPosition = -1
        contentHost.layer?.insertSublayer(surfaceColorLayer, at: 0)
        contentHost.layer?.insertSublayer(highlightLayer, at: 1)
    }

    // 将玻璃材质和描边同步到工具栏尺寸，保持横竖工具栏样式一致
    private func layoutChrome() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if usesLiquidGlass {
            glassBackdrop.frame = bounds
            if #available(macOS 26.0, *) {
                (glassBackdrop as? NSGlassEffectView)?.cornerRadius =
                    min(FrostedHUDChrome.cornerRadius, min(bounds.width, bounds.height) / 2)
            }
            contentHost.frame = CGRect(origin: .zero, size: bounds.size)
            layoutSurfaceColors()
            updateBorderPath()
            return
        }

        glassBackdrop.frame = bounds.insetBy(
            dx: FrostedGlassBackdropView.edgeInset,
            dy: FrostedGlassBackdropView.edgeInset
        )
        (glassBackdrop as? FrostedGlassBackdropView)?.applyCornerRadius()
        contentHost.frame = bounds
        layoutSurfaceColors()
        updateBorderPath()
    }

    // 横竖工具栏沿长轴透出蓝青色，短轴只保留一层柔和顶部高光
    private func layoutSurfaceColors() {
        let rect = contentHost.convert(glassBackdrop.bounds, from: glassBackdrop)
        let horizontal = rect.width >= rect.height
        for colorLayer in [surfaceColorLayer, highlightLayer] {
            colorLayer.frame = rect
            colorLayer.cornerRadius = min(FrostedHUDChrome.cornerRadius, min(rect.width, rect.height) / 2)
            colorLayer.masksToBounds = true
        }
        surfaceColorLayer.startPoint = horizontal ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0.5, y: 1)
        surfaceColorLayer.endPoint = horizontal ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0.5, y: 0)
        highlightLayer.startPoint = horizontal ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 0, y: 0.5)
        highlightLayer.endPoint = horizontal ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 1, y: 0.5)
    }

    // 描边位于材质轮廓内侧，不拦截按钮或拖动手柄的鼠标事件
    private func updateBorderPath() {
        let inset = FrostedHUDChrome.borderWidth / 2
        let rect = glassBackdrop.frame.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { borderLayer.path = nil; return }
        let radius = min(FrostedHUDChrome.cornerRadius, min(glassBackdrop.frame.width, glassBackdrop.frame.height) / 2)
        borderLayer.frame = bounds
        borderLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        borderLayer.path = CGPath(roundedRect: rect, cornerWidth: max(0, radius - inset),
                                  cornerHeight: max(0, radius - inset), transform: nil)
    }
}
