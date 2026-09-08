import AppKit
import CoreGraphics

/// Shared overlay chrome for screenshot selection: the same corner radius that
/// clips exported images, and the user-configurable RGB border color.
enum CaptureSelectionChrome {
    static var cornerRadius: CGFloat {
        WindowEffects.cornerRadiusPoints
    }

    static var borderColor: NSColor {
        NSColor(
            srgbRed: CGFloat(Defaults.selectionBorderRed) / 255,
            green: CGFloat(Defaults.selectionBorderGreen) / 255,
            blue: CGFloat(Defaults.selectionBorderBlue) / 255,
            alpha: 1
        )
    }

    static func applyBorderColor(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else {
            return
        }
        Defaults.selectionBorderRed = Int((rgb.redComponent * 255).rounded())
        Defaults.selectionBorderGreen = Int((rgb.greenComponent * 255).rounded())
        Defaults.selectionBorderBlue = Int((rgb.blueComponent * 255).rounded())
    }

    static func clampedRadius(for rect: CGRect, radius: CGFloat? = nil) -> CGFloat {
        let requested = radius ?? cornerRadius
        guard requested > 0, rect.width > 0, rect.height > 0 else { return 0 }
        return min(requested, min(rect.width, rect.height) / 2)
    }

    static func path(for rect: CGRect, radius: CGFloat? = nil) -> CGPath {
        let corner = clampedRadius(for: rect, radius: radius)
        if corner <= 0 {
            return CGPath(rect: rect, transform: nil)
        }
        return CGPath(
            roundedRect: rect,
            cornerWidth: corner,
            cornerHeight: corner,
            transform: nil
        )
    }
}
