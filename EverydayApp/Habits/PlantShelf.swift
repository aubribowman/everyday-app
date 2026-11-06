// The plant shelf on Today: each habit is a little plant in a terracotta pot.
// It grows as you check in and blooms once the habit is done for the day.

import SwiftUI
import SwiftData

/// One habit as a potted plant, with its name, a progress bar and a short status.
/// Tap to check in (tap a bloomed plant to take one back).
struct PlantPot: View {
    @Environment(\.modelContext) private var context
    let habit: Habit

    private var progress: Double { habit.progressToday }

    /// "Bloomed · 5 days", "3 of 8" or "Tap to water".
    private var status: String {
        if habit.isDoneToday {
            return habit.streak > 1 ? "Bloomed · \(habit.streak) days" : "Bloomed today"
        }
        if habit.target > 1 { return "\(habit.countToday) of \(habit.target)" }
        return "Tap to water"
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { habit.tap(in: context) }
        } label: {
            VStack(spacing: 5) {
                PlantDrawing(stage: PlantStage(habit))
                    .frame(width: 70, height: 74)
                Text(habit.name)
                    .font(.sans(.footnote, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Capsule()
                    .fill(Theme.surface)
                    .frame(width: 62, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(PlantColors.stem).frame(width: 62 * progress)
                    }
                Text(status)
                    .font(.sans(.caption))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: habit.isDoneToday) { _, done in done }
        .sensoryFeedback(.increase, trigger: habit.countToday)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), \(status)")
        .accessibilityHint(habit.isDoneToday ? "Double-tap to take one back" : "Double-tap to check in")
    }
}

/// The empty pot at the end of the shelf that adds a new habit.
struct EmptyPot: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    PlantDrawing(stage: .seed, empty: true)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.forest)
                        .offset(y: -10)
                }
                .frame(width: 70, height: 74)
                Text("Add habit")
                    .font(.sans(.footnote, .semibold))
                    .foregroundStyle(Theme.forest)
                Text("Plant a seed")
                    .font(.sans(.caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 11)   // lines up with the other pots' status text
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add habit")
    }
}

/// The plant colors, the same in light and dark mode (they sit on the sage shelf).
enum PlantColors {
    static let stem = Color(hex: 0x3F6B4B)
    static let leaf = Color(hex: 0x5C8A63)
    static let potRim = Color(hex: 0xB4552F)
    static let pot = Color(hex: 0xC9734B)
    static let petal = Color(hex: 0xE79A86)
    static let pollen = Color(hex: 0xF5D38A)
    static let shelf = Color(hex: 0xA9825D)
    static let soil = Color(hex: 0x6B4A33)
}

/// How far along a habit is today, shown as how grown its plant is.
enum PlantStage: CaseIterable {
    case seed     // nothing yet today
    case sprout   // started
    case leafy    // at least halfway
    case bloom    // done for the day

    init(_ habit: Habit) {
        let progress = habit.progressToday
        if habit.isDoneToday { self = .bloom }
        else if progress >= 0.5 { self = .leafy }
        else if progress > 0 { self = .sprout }
        else { self = .seed }
    }

    var name: String {
        switch self {
        case .seed: "Seed"
        case .sprout: "Sprout"
        case .leafy: "Leafy"
        case .bloom: "Bloom"
        }
    }

    var meaning: String {
        switch self {
        case .seed: "Not yet"
        case .sprout: "Started"
        case .leafy: "Halfway"
        case .bloom: "Done today"
        }
    }
}

/// Draws a pot with a plant at one of four stages (see PlantStage).
/// Drawn on a 60 × 64 grid, the same as the mockup, and scaled to fit.
struct PlantDrawing: View {
    var stage: PlantStage
    var empty = false

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width / 60, size.height / 64)
            ctx.translateBy(x: (size.width - 60 * scale) / 2, y: (size.height - 64 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)

            if !empty { drawPlant(in: &ctx) }

            // The pot: a rim and a tapered body.
            ctx.fill(Path(roundedRect: CGRect(x: 12, y: 40, width: 36, height: 6), cornerRadius: 3),
                     with: .color(PlantColors.potRim.opacity(empty ? 0.45 : 1)))
            var body = Path()
            body.move(to: CGPoint(x: 14, y: 46))
            body.addLine(to: CGPoint(x: 46, y: 46))
            body.addLine(to: CGPoint(x: 42, y: 62))
            body.addLine(to: CGPoint(x: 18, y: 62))
            body.closeSubpath()
            ctx.fill(body, with: .color(PlantColors.pot.opacity(empty ? 0.45 : 1)))
        }
        .accessibilityHidden(true)
    }

    private func drawPlant(in ctx: inout GraphicsContext) {
        let stem = StrokeStyle(lineWidth: 2.6, lineCap: .round)
        switch stage {
        case .seed:
            // A little mound of soil.
            ctx.fill(Path(ellipseIn: CGRect(x: 21, y: 35.5, width: 18, height: 9)), with: .color(PlantColors.soil))
        case .sprout:
            ctx.stroke(line(from: 41, to: 33), with: .color(PlantColors.stem), style: stem)
            ctx.fill(leaf(base: CGPoint(x: 30, y: 35), tip: CGPoint(x: 22, y: 29)), with: .color(PlantColors.leaf))
        case .leafy:
            ctx.stroke(line(from: 41, to: 20), with: .color(PlantColors.stem), style: stem)
            ctx.fill(leaf(base: CGPoint(x: 30, y: 34), tip: CGPoint(x: 16, y: 23)), with: .color(PlantColors.leaf))
            ctx.fill(leaf(base: CGPoint(x: 30, y: 28), tip: CGPoint(x: 44, y: 17)), with: .color(PlantColors.stem))
        case .bloom:
            ctx.stroke(line(from: 41, to: 12), with: .color(PlantColors.stem), style: stem)
            ctx.fill(leaf(base: CGPoint(x: 30, y: 36), tip: CGPoint(x: 15, y: 24)), with: .color(PlantColors.leaf))
            ctx.fill(leaf(base: CGPoint(x: 30, y: 30), tip: CGPoint(x: 45, y: 18)), with: .color(PlantColors.stem))
            ctx.fill(leaf(base: CGPoint(x: 30, y: 23), tip: CGPoint(x: 19, y: 15)), with: .color(PlantColors.stem))
            ctx.fill(Path(ellipseIn: CGRect(x: 23.5, y: 2.5, width: 13, height: 13)), with: .color(PlantColors.petal))
            ctx.fill(Path(ellipseIn: CGRect(x: 27.5, y: 6.5, width: 5, height: 5)), with: .color(PlantColors.pollen))
        }
    }

    /// The stem: a vertical line at x = 30.
    private func line(from bottom: Double, to top: Double) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 30, y: bottom))
            p.addLine(to: CGPoint(x: 30, y: top))
        }
    }

    /// A leaf shape from where it joins the stem out to its tip.
    private func leaf(base: CGPoint, tip: CGPoint) -> Path {
        Path { p in
            p.move(to: base)
            p.addCurve(to: tip,
                       control1: CGPoint(x: (base.x + tip.x) / 2 + (tip.x - base.x) * 0.1, y: base.y),
                       control2: CGPoint(x: tip.x, y: (base.y + tip.y) / 2))
            p.addCurve(to: base,
                       control1: CGPoint(x: (base.x + tip.x) / 2, y: tip.y),
                       control2: CGPoint(x: base.x, y: (base.y + tip.y) / 2 + (tip.y - base.y) * 0.1))
            p.closeSubpath()
        }
    }
}
