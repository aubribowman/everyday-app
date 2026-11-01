import SwiftUI

// MARK: - Design tokens (matched to the mockup)

enum Theme {
    static let appName = "EverydayApp"

    static let background  = Color(hex: 0xF7F6F1)  // warm off-white page
    static let surface     = Color.white            // cards
    static let ink         = Color(hex: 0x1F2A24)   // primary text
    static let muted       = Color(hex: 0x7B827C)   // secondary text
    static let hairline    = Color(hex: 0xE8E7E0)   // card borders, dividers
    static let forest      = Color(hex: 0x3D5C49)   // buttons, accents
    static let sage        = Color(hex: 0xE6EDE1)   // green cards
    static let peach       = Color(hex: 0xF7E5DA)
    static let peachInk    = Color(hex: 0xA9644A)
    static let lavender    = Color(hex: 0xECEAF5)
    static let lavenderInk = Color(hex: 0x6E6A99)
}

/// The three card colors a list can use.
enum CardTint: String, CaseIterable, Identifiable {
    case sage, peach, lavender

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var fill: Color {
        switch self {
        case .sage: Theme.sage
        case .peach: Theme.peach
        case .lavender: Theme.lavender
        }
    }

    var ink: Color {
        switch self {
        case .sage: Theme.forest
        case .peach: Theme.peachInk
        case .lavender: Theme.lavenderInk
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
