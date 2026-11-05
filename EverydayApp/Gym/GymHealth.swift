import Foundation
import HealthKit

/// Saves finished workouts to Apple Health, so they show in the Health and Fitness apps.
///
/// Each one is saved as Traditional Strength Training, from your first set to when you tap
/// Finish workout, with an estimate of the calories you burned. Those calories count toward
/// your Move ring. (Exercise minutes come from Apple Watch; apps can't add to that ring.)
enum GymHealth {
    /// Turned on in Gym › Schedule & Health.
    static let settingKey = "gymSavesToHealth"

    private static let store = HKHealthStore()

    /// iPads and Macs don't have the Health app.
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static var isOn: Bool { UserDefaults.standard.bool(forKey: settingKey) }

    /// Asks once. True if you allowed saving workouts.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        let save: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.bodyMass)]   // for the calorie estimate
        do {
            try await store.requestAuthorization(toShare: save, read: read)
        } catch {
            return false
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// When the workout started and ended. Uses your first set when that makes sense;
    /// otherwise (you ticked everything at the end, or the start is from hours ago) 45 minutes.
    static func times(startedAt: Date?, finishedAt end: Date = .now) -> (start: Date, end: Date) {
        if let startedAt {
            let length = end.timeIntervalSince(startedAt)
            if length >= 10 * 60 && length <= 4 * 60 * 60 { return (startedAt, end) }
        }
        return (end.addingTimeInterval(-45 * 60), end)
    }

    static func save(start: Date, end: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        try await builder.beginCollection(at: start)
        let calories = estimatedCalories(kilograms: await bodyMass() ?? 70,
                                         hours: end.timeIntervalSince(start) / 3600)
        let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                      quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                                      start: start, end: end)
        try await builder.addSamples([energy])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    /// Weight training burns about 3.5 times your resting rate (its "MET" value).
    static func estimatedCalories(kilograms: Double, hours: Double) -> Double {
        (3.5 * kilograms * hours).rounded()
    }

    /// Your latest weight in Health, if you've let the app read it.
    private static func bodyMass() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        let latest = try? await descriptor.result(for: store).first
        return latest?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }
}
