import SwiftUI

// MARK: - Palette (Saphinka Design)

enum Palette {
    static let peony   = Color(hex: 0xE5A3AD)
    static let cherry  = Color(hex: 0x8E2A21)
    static let sky     = Color(hex: 0x9AA7C0)
    static let thunder = Color(hex: 0x434F70)
    static let linen   = Color(hex: 0xE5E0D1)
    static let lemon   = Color(hex: 0xEACE94)
    static let olive   = Color(hex: 0x83854E)
}

// MARK: - Design tokens
// The token names (forest, sage, peach, lavender) are kept from the first
// version so no other file has to change. Each comment shows what it maps to now.

// Each token has a light-mode and a dark-mode color. iOS switches between them
// automatically when the phone's appearance changes (Settings → Display & Brightness).
// The dark colors come from the dark app icon: olive-black, sage green and soft pink.

enum Theme {
    static let appName = "EverydayApp"

    static let background  = Color(light: 0xF9F6EE, dark: 0x1C1D17)   // cream page / olive-black page
    static let surface     = Color(light: 0xFFFDF8, dark: 0x26281F)   // warm white cards / raised dark cards
    static let ink         = Color(light: 0x3B1F2B, dark: 0xF0EBDD)   // deep plum text / warm off-white text
    static let muted       = Color(light: 0x857B7E, dark: 0xA29D92)   // secondary text
    static let hairline    = Color(light: 0xE5E0D1, dark: 0x36382C)   // borders, dividers

    static let forest      = Color(light: 0x5B5D33, dark: 0xC9CEA6)   // primary: deep Olive / pale sage (the icon's stem)
    static let onPrimary   = Color(light: 0xFFFFFF, dark: 0x1C1D17)   // text and icons drawn on top of `forest`
    static let sage        = Color(light: 0xE3E4D4, dark: 0x31342A)   // Olive tint: hero card, Work events
    static let peach       = Color(light: 0xF6DFE2, dark: 0x3D2A2E)   // Peony tint: Personal events, avatar
    static let peachInk    = Color(light: 0x8E2A21, dark: 0xF0B3BC)   // Cherry text on Peony
    static let lavender    = Color(light: 0xDCE0E9, dark: 0x2A2F3B)   // Sky tint: reminders
    static let lavenderInk = Color(light: 0x434F70, dark: 0xB9C3DA)   // Thunder text on Sky
    static let lemon       = Color(light: 0xF5E7CA, dark: 0x3A3222)   // Lemon tint: list cards
    static let lemonInk    = Color(light: 0x7A5B1E, dark: 0xE8CC92)   // deep mustard text on Lemon
}

/// The app's Light / Dark choice in Settings. "System" follows the iPhone's own setting.
/// Saved as text ("system", "light", "dark") so it survives app restarts.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `.unspecified` = don't force anything, let iOS decide.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies the choice to the app's windows. (Done on the window rather than with
    /// SwiftUI's `.preferredColorScheme`, because that leaves open sheets stuck in
    /// the old mode when switching back to System.)
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

/// The card colors a list can use. Raw values stay the same so saved lists keep their color.
enum CardTint: String, CaseIterable, Identifiable {
    case sage, peach, lavender, lemon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sage: "Olive"
        case .peach: "Peony"
        case .lavender: "Sky"
        case .lemon: "Lemon"
        }
    }

    var fill: Color {
        switch self {
        case .sage: Theme.sage
        case .peach: Theme.peach
        case .lavender: Theme.lavender
        case .lemon: Theme.lemon
        }
    }

    var ink: Color {
        switch self {
        case .sage: Theme.forest
        case .peach: Theme.peachInk
        case .lavender: Theme.lavenderInk
        case .lemon: Theme.lemonInk
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that switches automatically between light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Card style

struct CardStyle: ViewModifier {
    var fill: Color

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: fill == Theme.surface ? 1 : 0)
            )
    }
}

extension View {
    func card(_ fill: Color = Theme.surface) -> some View {
        modifier(CardStyle(fill: fill))
    }
}

// MARK: - Date helpers

private let meridiemFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "a"
    return f
}()

extension Date {
    /// "5:00"
    var clock: String { formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)) }
    /// "PM"
    var meridiem: String { meridiemFormatter.string(from: self) }
    /// "5:00 PM"
    var timeText: String { formatted(date: .omitted, time: .shortened) }

    /// "Today, 5:00 PM" / "Tomorrow, 5:00 PM" / "Wed, Oct 28, 5:00 PM"
    var dayTimeText: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today, \(timeText)" }
        if cal.isDateInTomorrow(self) { return "Tomorrow, \(timeText)" }
        return "\(formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(timeText)"
    }

    /// "Today, October 26 · 5:00 PM"
    var longDayTime: String {
        let day = formatted(.dateTime.month(.wide).day())
        let prefix = Calendar.current.isDateInToday(self) ? "Today, " : ""
        return "\(prefix)\(day) · \(timeText)"
    }
}

extension Calendar {
    /// Weeks that start on Monday, like the mockup.
    static var mondayFirst: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }
}
