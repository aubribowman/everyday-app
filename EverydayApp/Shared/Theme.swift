// Colors, fonts, card style and date formatting used throughout the app.
// Use the `Theme` colors in views, never `Palette` directly, so dark mode keeps working.

import SwiftUI
import CoreText

// MARK: - Palette (Greenhouse + Sprout)

/// The raw plant colors. `Theme` below picks from these for each light/dark mode.
enum Palette {
    static let cream      = Color(hex: 0xF5F1E6)   // page background
    static let fern       = Color(hex: 0x2F4A3A)   // primary green
    static let sage       = Color(hex: 0xE3E8DA)   // soft green tint
    static let terracotta = Color(hex: 0xB4552F)   // clay pots, accents
    static let honey      = Color(hex: 0xEFD18F)   // warm highlight
    static let ink        = Color(hex: 0x1F2D24)   // dark text on light chips (both modes)
}

// MARK: - Design tokens
// The token names (forest, sage, peach, lavender, lemon) are kept from the first
// version so no other file has to change. Each comment shows what it maps to now.

// Each token has a light-mode and a dark-mode color. iOS switches between them
// automatically when the phone's appearance changes (Settings → Display & Brightness).
// Dark mode is a night greenhouse: deep green-black with pale fern greens.

/// The colors views use. Each one has a light and a dark version.
enum Theme {
    static let appName = "EverydayApp"

    static let background  = Color(light: 0xF5F1E6, dark: 0x131A16)   // cream page / green-black page
    static let surface     = Color(light: 0xFBF9F3, dark: 0x1C2520)   // warm white cards / raised dark cards
    static let ink         = Color(light: 0x1F2D24, dark: 0xEEF0E6)   // deep green text / warm off-white text
    static let muted       = Color(light: 0x5E6B60, dark: 0x9AA597)   // secondary text
    static let hairline    = Color(light: 0xE2DCCB, dark: 0x2C3730)   // borders, dividers

    static let forest      = Color(light: 0x2F4A3A, dark: 0xA9C8A8)   // primary: Fern / pale fern
    static let onPrimary   = Color(light: 0xFBF9F3, dark: 0x131A16)   // text and icons drawn on top of `forest`
    static let sage        = Color(light: 0xE3E8DA, dark: 0x23302A)   // Sage tint: Work events
    static let peach       = Color(light: 0xF3DCCD, dark: 0x3A2620)   // Clay tint: Personal events, avatar
    static let peachInk    = Color(light: 0xB4552F, dark: 0xE8A483)   // Terracotta text on Clay
    static let lavender    = Color(light: 0xF5E4BC, dark: 0x3A3020)   // Honey tint: reminders
    static let lavenderInk = Color(light: 0x7A5418, dark: 0xE8C98A)   // deep amber text on Honey
    static let lemon       = Color(light: 0xEADFE6, dark: 0x33283A)   // Bloom tint (soft orchid): list cards
    static let lemonInk    = Color(light: 0x6B4460, dark: 0xD7B9DA)   // plum text on Bloom

    static let terracotta  = Color(light: 0xB4552F, dark: 0xE08B62)   // italic accents, clay pots
    static let honey       = Color(light: 0xEFD18F, dark: 0xD9B866)   // warm highlights
    static let hero        = Color(light: 0x2F4A3A, dark: 0x22382B)   // deep fern hero card (dark in both modes)
    static let onHero      = Color(light: 0xF5F1E6, dark: 0xEEF0E6)   // cream text on `hero`
}

// MARK: - Fonts
// Headings use Instrument Serif (its italic is used for one-word accents) and
// everything else uses Instrument Sans. Both are free Google Fonts (SIL Open Font
// License, see Fonts/OFL.txt) bundled in Shared/Fonts and loaded at launch.

enum AppFonts {
    static let serif = "InstrumentSerif-Regular"
    static let serifItalic = "InstrumentSerif-Italic"
    static let sans = "Instrument Sans"

    /// Loads the bundled font files. Called once from EverydayApp.init.
    static func register() {
        for name in ["InstrumentSerif-Regular", "InstrumentSerif-Italic", "InstrumentSans"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        // Navigation bar titles in sheets ("New task", "Settings"…) use the serif too.
        let bar = UINavigationBar.appearance()
        if let title = UIFont(name: serif, size: 21) {
            bar.titleTextAttributes = [.font: title]
        }
        if let large = UIFont(name: serif, size: 38) {
            bar.largeTitleTextAttributes = [.font: large]
        }
    }

    /// Point sizes for each text style. They still grow and shrink with the
    /// iPhone's text size setting, because the fonts are made `relativeTo:` the style.
    static func size(of style: Font.TextStyle, display: Bool) -> CGFloat {
        // Instrument Serif runs small, so headings get a few extra points.
        switch style {
        case .largeTitle: display ? 40 : 34
        case .title: display ? 33 : 28
        case .title2: display ? 27 : 22
        case .title3: display ? 24 : 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

extension Font {
    /// Instrument Serif, for screen titles and section headings.
    /// `italic: true` is for single-word accents like the name in "Good morning, Aubri".
    static func display(_ style: TextStyle = .largeTitle, italic: Bool = false) -> Font {
        .custom(italic ? AppFonts.serifItalic : AppFonts.serif,
                size: AppFonts.size(of: style, display: true), relativeTo: style)
    }

    /// Instrument Sans, for everything else. `.headline` is semibold, like the system's.
    static func sans(_ style: TextStyle = .body, _ weight: Weight? = nil) -> Font {
        .custom(AppFonts.sans, size: AppFonts.size(of: style, display: false), relativeTo: style)
            .weight(weight ?? (style == .headline ? .semibold : .regular))
    }
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
        case .sage: "Sage"
        case .peach: "Clay"
        case .lavender: "Honey"
        case .lemon: "Bloom"
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
    /// `Color(hex: 0xE5A3AD)`
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
    /// `UIColor(hex: 0xE5A3AD)`
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

/// The rounded card look. Use it through `.card()`.
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
    /// Gives a Form or List in a sheet the cream page color instead of iOS's gray.
    func themedForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    /// Rounded card with padding. Plain (surface) cards get a thin border; tinted ones don't.
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
