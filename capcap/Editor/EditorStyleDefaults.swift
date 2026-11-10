import AppKit

enum EditorStyleDefaults {
    static let paletteColors: [NSColor] = [
        NSColor(srgbRed: 0.95, green: 0.36, blue: 0.53, alpha: 1),  // Pink
        NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1),   // Red
        NSColor(srgbRed: 1.0, green: 0.64, blue: 0.22, alpha: 1),   // Orange
        NSColor(srgbRed: 1.0, green: 0.84, blue: 0.28, alpha: 1),   // Yellow
        NSColor(srgbRed: 0.39, green: 0.78, blue: 0.43, alpha: 1),  // Green
        NSColor(srgbRed: 0.20, green: 0.51, blue: 0.96, alpha: 1),  // Blue
        .black,
        .white,
    ]

    static var primaryColor: NSColor {
        color(fromHex: Defaults.lastEditorColorHex) ?? paletteColors[1]
    }

    static var markerColor: NSColor {
        color(fromHex: Defaults.lastMarkerColorHex) ?? paletteColors[3]
    }

    static let standardLineSizes: [CGFloat] = [2, 4, 6]
    static let markerLineSizes: [CGFloat] = [3, 5, 8]

    static var standardLineWidth: CGFloat { CGFloat(Defaults.lastEditorLineWidth) }
    static var markerLineWidth: CGFloat { CGFloat(Defaults.lastMarkerLineWidth) }

    private static func color(fromHex hex: String?) -> NSColor? {
        guard var trimmed = hex?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return nil
        }
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
