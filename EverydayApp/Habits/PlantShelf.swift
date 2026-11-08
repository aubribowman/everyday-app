// The plant shelf on Today: each habit is a little plant in a terracotta pot.
// The plant game: every day you do a habit waters its plant and it grows a little.
// Over days it goes Seed → Sprout → Leafy → Bud → Bloom → Flourish (see PlantStage).
// Skip a day and it gets thirsty; keep skipping and it shrinks (see Habit.growth).

import SwiftUI
import SwiftData

/// One habit as a potted plant: its name, how close it is to the next stage, and today's status.
/// Tap to water it (tap again once watered to take it back).
struct PlantPot: View {
    @Environment(\.modelContext) private var context
    let habit: Habit

    @State private var splash = 0                 // bumps to play the water drops
    @State private var grewInto: PlantStage?      // shows "Grew to Bud!" for a moment

    /// "Watered · 5 days", "3 of 8", "Thirsty!" or "Tap to water".
    private var status: String {
        if habit.isDoneToday {
            return habit.streak > 1 ? "Watered · \(habit.streak) days" : "Watered today"
        }
        if habit.isThirsty { return "Thirsty!" }
        if habit.target > 1 { return "\(habit.countToday) of \(habit.target)" }
        return "Tap to water"
    }

    /// "Leafy, 2 days to Bud"
    private var growthLine: String {
        let stage = habit.stage
        guard let next = stage.next, let days = habit.daysToNextStage else { return "\(stage.name), fully grown" }
        return "\(stage.name), \(days) \(days == 1 ? "day" : "days") to \(next.name)"
    }

    var body: some View {
        Button(action: water) {
            VStack(spacing: 5) {
                PlantDrawing(stage: habit.stage, thirsty: habit.isThirsty)
                    .frame(width: 70, height: 74)
                    .id(habit.stage)
                    .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                    .overlay(alignment: .top) { WaterDrops(trigger: splash) }
                    .overlay(alignment: .top) {
                        if let grewInto {
                            Label("\(grewInto.name)!", systemImage: "sparkles")
                                .font(.sans(.caption, .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(PlantColors.pollen, in: Capsule())
                                .offset(y: -6)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                Text(habit.name)
                    .font(.sans(.footnote, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                // How close the plant is to its next stage.
                Capsule()
                    .fill(Theme.surface)
                    .frame(width: 62, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(PlantColors.stem).frame(width: 62 * habit.stageProgress)
                    }
                Text(status)
                    .font(.sans(.caption, habit.isThirsty ? .semibold : nil))
                    .foregroundStyle(habit.isThirsty ? Theme.terracotta : Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: habit.isDoneToday) { _, done in done }
        .sensoryFeedback(.increase, trigger: habit.countToday)
        .sensoryFeedback(.levelChange, trigger: grewInto) { _, new in new != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), \(status). \(growthLine)")
        .accessibilityHint(habit.isDoneToday ? "Double-tap to take one back" : "Double-tap to water")
    }

    /// Checks in, plays the water drops, and celebrates if the plant grew a stage.
    private func water() {
        let before = habit.stage
        let wasDone = habit.isDoneToday
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { habit.tap(in: context) }
        guard !wasDone else { return }
        splash += 1
        let after = habit.stage
        guard after > before else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { grewInto = after }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.3)) { grewInto = nil }
        }
    }
}

/// Three water drops that fall onto the plant each time `trigger` changes.
struct WaterDrops: View {
    var trigger: Int

    private struct Frame { var opacity = 0.0; var y = -4.0 }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Image(systemName: "drop.fill")
                    .font(.system(size: 9))
                    .offset(y: i == 1 ? -5 : 0)
            }
        }
        .foregroundStyle(Color(hex: 0x6FA8C9))
        .keyframeAnimator(initialValue: Frame(), trigger: trigger) { content, frame in
            content.opacity(frame.opacity).offset(y: frame.y)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.05)
                LinearKeyframe(1, duration: 0.3)
                LinearKeyframe(0, duration: 0.2)
            }
            KeyframeTrack(\.y) {
                LinearKeyframe(-4, duration: 0.01)
                CubicKeyframe(18, duration: 0.55)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// How grown a plant is. It moves up a stage as its habit's growth points add up (see Habit.growth).
enum PlantStage: Int, CaseIterable, Comparable {
    case seed, sprout, leafy, bud, bloom, flourish

    init(growth: Int) {
        self = Self.allCases.last { $0.threshold <= growth } ?? .seed
    }

    static func < (a: PlantStage, b: PlantStage) -> Bool { a.rawValue < b.rawValue }

    /// Growth points needed to reach this stage.
    var threshold: Int {
        switch self {
        case .seed: 0
        case .sprout: 1
        case .leafy: 3
        case .bud: 7
        case .bloom: 14
        case .flourish: 30
        }
    }

    var next: PlantStage? { PlantStage(rawValue: rawValue + 1) }

    var name: String {
        switch self {
        case .seed: "Seed"
        case .sprout: "Sprout"
        case .leafy: "Leafy"
        case .bud: "Bud"
        case .bloom: "Bloom"
        case .flourish: "Flourish"
        }
    }

    /// When you get there, for the key on the Habits screen.
    var meaning: String {
        switch self {
        case .seed: "Start"
        case .sprout: "1 day"
        case .leafy: "3 days"
        case .bud: "1 week"
        case .bloom: "2 weeks"
        case .flourish: "30 days"
        }
    }
}

extension Habit {
    var stage: PlantStage { PlantStage(growth: growth) }

    /// How far from this stage to the next, from 0 to 1 (1 once it flourishes).
    var stageProgress: Double {
        let points = growth
        let stage = PlantStage(growth: points)
        guard let next = stage.next else { return 1 }
        return Double(points - stage.threshold) / Double(next.threshold - stage.threshold)
    }

    /// Days of watering until the next stage, or nil once it flourishes.
    var daysToNextStage: Int? {
        let points = growth
        return PlantStage(growth: points).next.map { $0.threshold - points }
    }
}

/// Draws a pot with a plant at one of six stages (see PlantStage). A thirsty plant
/// droops and fades. Drawn on a 60 × 64 grid, the same as the mockup, and scaled to fit.
struct PlantDrawing: View {
    var stage: PlantStage
    var thirsty = false
    var empty = false

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width / 60, size.height / 64)
            ctx.translateBy(x: (size.width - 60 * scale) / 2, y: (size.height - 64 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)

            if !empty {
                ctx.drawLayer { plant in
                    if thirsty {
                        // Lean over from the soil.
                        plant.translateBy(x: 30, y: 41)
                        plant.rotate(by: .degrees(12))
                        plant.translateBy(x: -30, y: -41)
                    }
                    drawPlant(in: &plant)
                }
            }

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

    // Thirsty plants turn a dry olive.
    private var stemColor: Color { thirsty ? Color(hex: 0x86834F) : PlantColors.stem }
    private var leafColor: Color { thirsty ? Color(hex: 0xA6A167) : PlantColors.leaf }
    private var petalColor: Color { thirsty ? Color(hex: 0xC9A08F) : PlantColors.petal }

    private func drawPlant(in ctx: inout GraphicsContext) {
        let stem = StrokeStyle(lineWidth: 2.6, lineCap: .round)
        switch stage {
        case .seed:
            // A little mound of soil.
            ctx.fill(Path(ellipseIn: CGRect(x: 21, y: 35.5, width: 18, height: 9)), with: .color(PlantColors.soil))
        case .sprout:
            ctx.stroke(line(from: 41, to: 33), with: .color(stemColor), style: stem)
            ctx.fill(leaf(base: CGPoint(x: 30, y: 35), tip: CGPoint(x: 22, y: 29)), with: .color(leafColor))
        case .leafy:
            ctx.stroke(line(from: 41, to: 20), with: .color(stemColor), style: stem)
            ctx.fill(leaf(base: CGPoint(x: 30, y: 34), tip: CGPoint(x: 16, y: 23)), with: .color(leafColor))
            ctx.fill(leaf(base: CGPoint(x: 30, y: 28), tip: CGPoint(x: 44, y: 17)), with: .color(stemColor))
        case .bud:
            ctx.stroke(line(from: 41, to: 13), with: .color(stemColor), style: stem)
            drawLeaves(in: &ctx)
            // A closed bud: green with a blush of petal at the tip.
            ctx.fill(Path(ellipseIn: CGRect(x: 26, y: 5, width: 8, height: 11)), with: .color(leafColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 27.5, y: 4, width: 5, height: 6)), with: .color(petalColor))
        case .bloom:
            ctx.stroke(line(from: 41, to: 12), with: .color(stemColor), style: stem)
            drawLeaves(in: &ctx)
            flower(in: &ctx, at: CGPoint(x: 30, y: 9), size: 13)
        case .flourish:
            ctx.stroke(line(from: 41, to: 12), with: .color(stemColor), style: stem)
            drawLeaves(in: &ctx)
            flower(in: &ctx, at: CGPoint(x: 13, y: 22), size: 8)
            flower(in: &ctx, at: CGPoint(x: 47, y: 16), size: 8)
            flower(in: &ctx, at: CGPoint(x: 30, y: 8.5), size: 15)
        }
    }

    /// The three leaves of a grown plant.
    private func drawLeaves(in ctx: inout GraphicsContext) {
        ctx.fill(leaf(base: CGPoint(x: 30, y: 36), tip: CGPoint(x: 15, y: 24)), with: .color(leafColor))
        ctx.fill(leaf(base: CGPoint(x: 30, y: 30), tip: CGPoint(x: 45, y: 18)), with: .color(stemColor))
        ctx.fill(leaf(base: CGPoint(x: 30, y: 23), tip: CGPoint(x: 19, y: 15)), with: .color(stemColor))
    }

    /// A round flower with a pollen center.
    private func flower(in ctx: inout GraphicsContext, at center: CGPoint, size: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)),
                 with: .color(petalColor))
        let middle = size * 0.38
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - middle / 2, y: center.y - middle / 2, width: middle, height: middle)),
                 with: .color(PlantColors.pollen))
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
