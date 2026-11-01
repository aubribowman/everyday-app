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

enum Theme {
    static let appName = "EverydayApp"

    static let background  = Color(hex: 0xF9F6EE)   // cream page
    static let surface     = Color(hex: 0xFFFDF8)   // warm white cards
    static let ink         = Color(hex: 0x3B1F2B)   // deep plum text
    static let muted       = Color(hex: 0x857B7E)   // secondary text
    static let hairline    = Palette.linen          // borders, dividers

    static let forest      = Color(hex: 0x5B5D33)   // primary: Olive, deepened so white text stays readable
    static let sage        = Color(hex: 0xE3E4D4)   // Olive tint: hero card, Work events
    static let peach       = Color(hex: 0xF6DFE2)   // Peony tint: Personal events, avatar
    static let peachInk    = Palette.cherry         // Cherry text on Peony
    static let lavender    = Color(hex: 0xDCE0E9)   // Sky tint: reminders
    static let lavenderInk = Palette.thunder        // Thunder text on Sky
    static let lemon       = Color(hex: 0xF5E7CA)   // Lemon tint: list cards
    static let lemonInk    = Color(hex: 0x7A5B1E)   // deep mustard text on Lemon
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
