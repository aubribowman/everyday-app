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

/// The bar at the bottom of a workout while you rest: time left, what's next, −15 / +15 / Skip.
struct RestBar: View {
    let timer: RestTimer

    var body: some View {
        if let start = timer.start, let end = timer.end {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let total = max(end.timeIntervalSince(start), 1)
                let left = max(end.timeIntervalSince(context.date), 0)
                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("REST")
                                .font(.caption2.weight(.semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.onPrimary.opacity(0.8))
                            Text(timer.next)
                                .font(.subheadline)
                                .foregroundStyle(Theme.onPrimary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.onPrimary)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(left.rounded(.up)))
                    }
                    ProgressView(value: left, total: total)
                        .tint(Theme.onPrimary)
                    HStack(spacing: 10) {
                        barButton("−15") { timer.add(-15) }
                        barButton("+15") { timer.add(15) }
                        Spacer()
                        barButton("Skip") { withAnimation(.snappy) { timer.skip() } }
                    }
                }
                .padding(16)
                .background(Theme.forest, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Rest, \(Int(left.rounded(.up))) seconds left. \(timer.next)")
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func barButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.forest)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.onPrimary, in: Capsule())
            .buttonStyle(.plain)
    }
}
