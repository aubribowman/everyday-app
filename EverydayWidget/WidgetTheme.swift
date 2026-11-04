import SwiftUI
import UIKit

/// The app's colors, copied for the widget (the widget can't see the app's Theme.swift).
enum WTheme {
    static let background = Color(light: 0xF9F6EE, dark: 0x1C1D17)
    static let ink = Color(light: 0x3B1F2B, dark: 0xF0EBDD)
    static let muted = Color(light: 0x857B7E, dark: 0xA29D92)
    static let forest = Color(light: 0x5B5D33, dark: 0xC9CEA6)
    static let sage = Color(light: 0xE3E4D4, dark: 0x31342A)
    static let peach = Color(light: 0xF6DFE2, dark: 0x3D2A2E)
    static let peachInk = Color(light: 0x8E2A21, dark: 0xF0B3BC)
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
