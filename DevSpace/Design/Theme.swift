import AppKit
import SwiftUI

/// Design tokens. A monochrome graphite base with a single restrained ink accent;
/// risk levels use desaturated natural tones instead of traffic-light colors.
enum Theme {
    // Accent: deep ink in light mode, pale mist in dark mode.
    static let accent = Color(light: 0x2B3447, dark: 0xD5DCE8)
    static let onAccent = Color(light: 0xF7F7F5, dark: 0x15181E)

    // Data palette — fixed categorical order, validated for CVD separation
    // (light on #FFFFFF, dark on #1E2024). Each hue follows one entity everywhere.
    static let indigo = Color(light: 0x4C5FD0, dark: 0x7A86F0)
    static let teal = Color(light: 0x1F9AA8, dark: 0x0FA0AF)
    static let ochre = Color(light: 0xC0853A, dark: 0xB07C36)
    static let rose = Color(light: 0xD0587E, dark: 0xD9668D)
    static let lavender = Color(light: 0x8A6FCF, dark: 0x8F78D8)
    static let dataOther = Color.primary.opacity(0.16)

    // Risk tones (status — never reused as series colors). Validated as a set for
    // color-vision separation: emerald, amber, raspberry, blue slate.
    static let sage = Color(light: 0x2A9A5E, dark: 0x34A874)
    static let sand = Color(light: 0xC29512, dark: 0xBC8A1E)
    static let clay = Color(light: 0xC8445E, dark: 0xDD5C7C)
    /// "Something to clean here" dot in the sidebar and on Overview cards.
    static let attention = Color(light: 0xE5484D, dark: 0xFF6369)
    /// The user's own files in the Files Inspector.
    static let slate = Color(light: 0x5470B0, dark: 0x6A84C8)

    // Surfaces.
    static let canvas = Color(light: 0xF6F5F2, dark: 0x16171A)
    static let card = Color(light: 0xFFFFFF, dark: 0x1E2024)
    static let hairline = Color.primary.opacity(0.08)
    static let track = Color.primary.opacity(0.06)

    static let radius: CGFloat = 14
    static let gutter: CGFloat = 28
}

extension Font {
    /// Large figures: light weight, tabular digits.
    static let figure = Font.system(size: 46, weight: .light).monospacedDigit()
    static let figureSmall = Font.system(size: 26, weight: .light).monospacedDigit()
    static let pageTitle = Font.system(size: 26, weight: .semibold)
    static let eyebrow = Font.system(size: 10.5, weight: .semibold)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Int64 {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false  // "0 KB", not "Zero KB"
        return formatter
    }()

    var formattedBytes: String { Self.byteFormatter.string(fromByteCount: self) }
}
