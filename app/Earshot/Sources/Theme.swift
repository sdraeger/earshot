import AppKit
import SwiftUI

/// Earshot's colors: warm paper, dark ink and one green accent, each with a
/// dark-mode value. Applied with `.tint(Theme.accent)` at each window's root.
enum Theme {
    static let accent = Color(light: 0x3B7A57, dark: 0x7BC496)
    static let paper = Color(light: 0xFBF9F4, dark: 0x22211F)
    static let card = Color(light: 0xF3EFE6, dark: 0x2C2B28)
    static let hairline = Color(light: 0xE4DED2, dark: 0x3B3936)
}

extension Color {
    /// A color that follows the system appearance, from two 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1,
            )
        })
    }
}
