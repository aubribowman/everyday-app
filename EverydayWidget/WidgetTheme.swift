import SwiftUI
import UIKit

/// The app's colors, copied for the widget (the widget can't see the app's Theme.swift).
enum WTheme {
    static let background = Color(light: 0xF5F1E6, dark: 0x131A16)
    static let ink = Color(light: 0x1F2D24, dark: 0xEEF0E6)
    static let muted = Color(light: 0x5E6B60, dark: 0x9AA597)
    static let forest = Color(light: 0x2F4A3A, dark: 0xA9C8A8)
    static let sage = Color(light: 0xE3E8DA, dark: 0x23302A)
    static let peach = Color(light: 0xF3DCCD, dark: 0x3A2620)
    static let peachInk = Color(light: 0xB4552F, dark: 0xE8A483)
}

extension Color {
    /// A color that switches between two hex values for Light and Dark mode.
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}
