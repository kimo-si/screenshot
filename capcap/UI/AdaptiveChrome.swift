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

// 编辑器专用的炭灰表面与粉色交互色，不受截图和系统外观影响
enum FrostedHUDChrome {
    static let cornerRadius: CGFloat = 12
    static let borderWidth: CGFloat = 0.5
    static let borderColor = NSColor.white.withAlphaComponent(0.10)
    static let backgroundColor = color(0x4B4B4D, alpha: 0.98)
    static let iconColor = color(0xEBEBED)
    static let accentColor = color(0xF35B87)
    static let hoverFill = NSColor.white.withAlphaComponent(0.12)
    static let selectedIconColor = NSColor.white
    static let groupGap: CGFloat = 6
    static let swatchSize: CGFloat = 24
    static let swatchGap: CGFloat = 6

    // 将参考图中的 sRGB 色值转换为 AppKit 颜色
    private static func color(_ rgb: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

/// 编辑器浮动工具栏的共享底板，按钮与底板分层以保留完整点击区域
class FrostedHUDView: NSView {
    let contentHost = NSView()
    private let surfaceLayer = CAShapeLayer()

    /// 子类可以提供多个底板区域，在同一排工具中形成分组
    var surfaceRects: [NSRect] { [bounds] }

    // 固定深色外观，避免浅色系统主题降低图标与控件的对比度
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        surfaceLayer.fillColor = FrostedHUDChrome.backgroundColor.cgColor
        surfaceLayer.strokeColor = FrostedHUDChrome.borderColor.cgColor
        surfaceLayer.lineWidth = FrostedHUDChrome.borderWidth
        layer?.addSublayer(surfaceLayer)
        contentHost.frame = bounds
        contentHost.autoresizingMask = [.width, .height]
        super.addSubview(contentHost)
    }

    // 工具栏仅支持代码构建
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    // 将按钮放在底板上方，保持现有工具栏的添加接口
    override func addSubview(_ view: NSView) {
        guard view !== contentHost else { super.addSubview(view); return }
        contentHost.addSubview(view)
    }

    // 保留浮动工具栏内部视图的叠放顺序
    override func addSubview(
        _ view: NSView,
        positioned place: NSWindow.OrderingMode,
        relativeTo otherView: NSView?
    ) {
        guard view !== contentHost else {
            super.addSubview(view, positioned: place, relativeTo: otherView)
            return
        }
        contentHost.addSubview(view, positioned: place, relativeTo: otherView)
    }

    // 尺寸变化时同步底板轮廓，禁止隐式动画造成按钮与背景错位
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        contentHost.frame = bounds
        surfaceLayer.frame = bounds
        surfaceLayer.contentsScale = window?.backingScaleFactor ?? 2
        surfaceLayer.path = surfacePath()
    }

    // 为每个分组创建独立圆角轮廓，使分组间隙保持透明
    private func surfacePath() -> CGPath {
        let path = CGMutablePath()
        let inset = FrostedHUDChrome.borderWidth / 2
        for frame in surfaceRects where frame.width > 0 && frame.height > 0 {
            let rect = frame.insetBy(dx: inset, dy: inset)
            let radius = min(FrostedHUDChrome.cornerRadius, min(rect.width, rect.height) / 2)
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }
}
