import ActivityKit
import SwiftUI
import UIKit
import UserNotifications

/// What the Lock Screen and Dynamic Island show during a rest.
/// The widget has its own copy (EverydayWidget/RestTimerLiveActivity.swift); keep the two the same.
nonisolated struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var next: String        // "Set 2 of 3 · Leg Press"
    }
    var workout: String         // "PF Leg x Glutes Day"
}

/// The rest countdown between sets. One at a time, shared by the whole app.
///
/// While it runs you see it at the bottom of the workout, on the Lock Screen and in the
/// Dynamic Island. When it's over your phone buzzes and a notification says what's next,
/// even if the app is closed.
@MainActor
@Observable
final class RestTimer {
    static let shared = RestTimer()
    /// Task reminders leave notifications with this name alone (see Reminders.swift).
    static let notificationID = "rest-timer"

    private(set) var start: Date?
    private(set) var end: Date?
    private(set) var next = ""

    private var workout = ""
    private var finishTask: Task<Void, Never>?
    private var activity: Activity<RestTimerAttributes>?

    var isRunning: Bool { end.map { $0 > .now } ?? false }

    /// Starts a new rest, replacing any running one. `next` is shown on the Lock Screen
    /// and in the notification ("Set 2 of 3 · Leg Press").
    func begin(seconds: Int, next: String, workout: String) {
        let now = Date.now
        start = now
        end = now.addingTimeInterval(TimeInterval(seconds))
        self.next = next
        self.workout = workout
        scheduleEverything()
    }

    /// +15 or −15 seconds. Going below zero ends the rest.
    func add(_ seconds: Int) {
        guard let current = end else { return }
        let newEnd = current.addingTimeInterval(TimeInterval(seconds))
        if newEnd <= .now.addingTimeInterval(1) {
            skip()
        } else {
            end = newEnd
            scheduleEverything()
        }
    }

    /// Ends the rest early.
    func skip() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        clear()
    }

    /// Called when the app comes back, in case the rest ended while it was closed.
    func checkExpired() {
        if let end, end <= .now { clear() }
        // A finished countdown from before the app was closed would otherwise stay up.
        if !isRunning { endStrayActivities() }
    }

    // MARK: Behind the scenes

    /// Sets up all three ways the rest ends: a buzz if the app is open, a notification
    /// if it isn't, and the Lock Screen / Dynamic Island countdown.
    private func scheduleEverything() {
        guard let start, let end else { return }

        // Buzz when it's over (if the app is open).
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self?.clear()
        }

        // A notification for when the app is closed or the phone is locked.
        let next = next
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let content = UNMutableNotificationContent()
            content.title = "Rest's over"
            content.body = next
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(end.timeIntervalSinceNow, 1),
                                                            repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.notificationID,
                                                        content: content, trigger: trigger))
        }

        // The Lock Screen / Dynamic Island countdown.
        let state = RestTimerAttributes.ContentState(start: start, end: end, next: next)
        let content = ActivityContent(state: state, staleDate: end)
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            endStrayActivities()
            activity = try? Activity.request(attributes: RestTimerAttributes(workout: workout),
                                             content: content)
        }
    }

    /// Forgets the current rest and removes the Lock Screen countdown.
    private func clear() {
        finishTask?.cancel()
        finishTask = nil
        start = nil
        end = nil
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }

    /// A countdown left over from before the app was closed.
    private func endStrayActivities() {
        for old in Activity<RestTimerAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

/// The dark green bar at the bottom of a workout while you rest: time left, what's next, −15 / +15 / Skip.
struct RestBar: View {
    let timer: RestTimer

    var body: some View {
        if let start = timer.start, let end = timer.end {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let total = max(end.timeIntervalSince(start), 1)
                let left = max(end.timeIntervalSince(context.date), 0)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("REST")
                            .font(.sans(.caption2, .bold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.onHero.opacity(0.8))
                        Text(Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                            .font(.display(.largeTitle))
                            .monospacedDigit()
                            .foregroundStyle(Theme.onHero)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(left.rounded(.up)))
                        Text(timer.next)
                            .font(.sans(.footnote))
                            .foregroundStyle(Theme.onHero.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 4)
                    roundButton("−15", fill: Theme.onHero.opacity(0.16), text: Theme.onHero) { timer.add(-15) }
                    roundButton("+15", fill: Theme.onHero.opacity(0.16), text: Theme.onHero) { timer.add(15) }
                    roundButton("Skip", fill: Theme.honey, text: Palette.ink) { withAnimation(.snappy) { timer.skip() } }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                // The rest so far fills in, faintly, from the left.
                .background(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.onHero.opacity(0.06))
                            .frame(width: geo.size.width * (1 - left / total))
                    }
                }
                .background(Theme.hero)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Rest, \(Int(left.rounded(.up))) seconds left. \(timer.next)")
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func roundButton(_ title: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.sans(.subheadline, .semibold))
                .foregroundStyle(text)
                .frame(width: 54, height: 54)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
