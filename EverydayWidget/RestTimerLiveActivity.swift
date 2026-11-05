import ActivityKit
import SwiftUI
import WidgetKit

/// Same as RestTimerAttributes in the app (EverydayApp/RestTimer.swift); keep the two the same.
nonisolated struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var next: String
    }
    var workout: String
}

/// The rest countdown on the Lock Screen and in the Dynamic Island.
/// iOS counts down on its own, so it keeps going while the app is closed.
/// Once the time is up (the activity goes "stale"), it says so instead of sitting at 0:00.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            lockScreen(context.state, workout: context.attributes.workout, isOver: context.isStale)
                .activityBackgroundTint(WTheme.background)
                .activitySystemActionForegroundColor(WTheme.forest)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(WTheme.sage)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state, isOver: context.isStale)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.next)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        ProgressView(timerInterval: context.state.start...context.state.end,
                                     countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(WTheme.sage)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(WTheme.sage)
            } compactTrailing: {
                countdown(context.state, isOver: context.isStale)
                    .frame(width: 44)
                    .foregroundStyle(WTheme.sage)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(WTheme.sage)
            }
        }
    }

    /// The Lock Screen banner: the workout, what's next, and the countdown.
    private func lockScreen(_ state: RestTimerAttributes.ContentState, workout: String,
                            isOver: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(isOver ? "REST'S OVER" : "REST", systemImage: isOver ? "checkmark.circle" : "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WTheme.forest)
                    Text(state.next)
                        .font(.headline)
                        .foregroundStyle(WTheme.ink)
                        .lineLimit(1)
                    Text(workout)
                        .font(.caption)
                        .foregroundStyle(WTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                countdown(state, isOver: isOver)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(WTheme.ink)
            }
            ProgressView(timerInterval: state.start...state.end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(WTheme.forest)
        }
        .padding(16)
    }

    /// "1:23", counting down to 0:00, then "Go".
    @ViewBuilder
    private func countdown(_ state: RestTimerAttributes.ContentState, isOver: Bool) -> some View {
        if isOver {
            Text("Go")
        } else {
            Text(timerInterval: state.start...state.end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}
