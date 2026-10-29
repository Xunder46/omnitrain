// ios/Runner/HealthEffortChannel.swift
//
// Plan 90 D-6: the session's effort rating goes into Apple Fitness as the
// workout's Workout Effort. The `health` plugin has no effort support, so
// the Dart gateway (`lib/core/services/health_platform_gateway_io.dart`)
// calls this channel on iOS only.
//
// Methods (arguments are milliseconds since the epoch):
//   requestAuthorization          -> "asked" | "unavailable"
//   set   {start, end, score}     -> "written" | "leftAlone" | "noWorkout" | "unavailable"
//   clear {start, end}            -> "cleared" | "unavailable"
//
// The workout is this app's own (HKSource.default()) whose start lies in
// [start, end), the same lookup the plugin's delete uses; the earliest one
// if several. An effort another source saved (the owner's own value in
// Fitness) is never replaced. Before iOS 18, or on any error, every method
// answers "unavailable". Pinned by `test/health_effort_native_test.dart`.

import Flutter
import HealthKit

final class HealthEffortChannel {
  static let channelName = "omnitrain/health_effort"

  private let channel: FlutterMethodChannel
  private let healthStore = HKHealthStore()

  private init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: HealthEffortChannel.channelName,
      binaryMessenger: messenger
    )
  }

  /// Registers the channel. The caller keeps the returned object alive.
  static func register(with messenger: FlutterBinaryMessenger) -> HealthEffortChannel {
    let instance = HealthEffortChannel(messenger: messenger)
    instance.channel.setMethodCallHandler { [weak instance] call, result in
      guard let instance = instance else {
        result("unavailable")
        return
      }
      instance.handle(call, result: result)
    }
    return instance
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 18.0, *) else {
      result("unavailable")
      return
    }
    guard HKHealthStore.isHealthDataAvailable() else {
      result("unavailable")
      return
    }
    let store = HealthEffortStore(healthStore: healthStore)
    let args = call.arguments as? [String: Any] ?? [:]
    let start = HealthEffortChannel.date(args["start"])
    let end = HealthEffortChannel.date(args["end"])
    switch call.method {
    case "requestAuthorization":
      answer(result) { try await store.requestAuthorization() }
    case "set":
      guard let start = start, let end = end,
        let score = (args["score"] as? NSNumber)?.doubleValue
      else {
        result("unavailable")
        return
      }
      answer(result) { try await store.set(start: start, end: end, score: score) }
    case "clear":
      guard let start = start, let end = end else {
        result("unavailable")
        return
      }
      answer(result) { try await store.clear(start: start, end: end) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Runs [work] off the platform thread and answers on the main thread;
  /// a thrown error answers "unavailable".
  private func answer(
    _ result: @escaping FlutterResult,
    _ work: @escaping () async throws -> String
  ) {
    Task {
      let reply: String
      do {
        reply = try await work()
      } catch {
        reply = "unavailable"
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  private static func date(_ value: Any?) -> Date? {
    guard let ms = (value as? NSNumber)?.doubleValue else { return nil }
    return Date(timeIntervalSince1970: ms / 1000)
  }
}

private enum HealthEffortError: Error {
  case refused
}

@available(iOS 18.0, *)
private final class HealthEffortStore {
  private let healthStore: HKHealthStore
  private let effortType = HKQuantityType(.workoutEffortScore)

  init(healthStore: HKHealthStore) {
    self.healthStore = healthStore
  }

  /// Share and read the effort type. The workout type is in the share set
  /// too so switching "Write workouts" on shows one Health sheet: the
  /// plugin's own workout request that follows then has nothing new to ask.
  func requestAuthorization() async throws -> String {
    try await healthStore.requestAuthorization(
      toShare: [effortType, HKObjectType.workoutType()],
      read: [effortType]
    )
    return "asked"
  }

  func set(start: Date, end: Date, score: Double) async throws -> String {
    guard let workout = try await ownWorkout(start: start, end: end) else {
      return "noWorkout"
    }
    let related = try await relatedEfforts(workout)
    if related.contains(where: { !isOwn($0) }) {
      return "leftAlone"
    }
    if !related.isEmpty {
      try await healthStore.delete(related)
    }
    let sample = HKQuantitySample(
      type: effortType,
      quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: score),
      start: workout.startDate,
      end: workout.endDate
    )
    try await healthStore.save(sample)
    do {
      try await relate(sample, to: workout)
    } catch {
      // Never leave an unrelated effort behind (plan 90 L-2).
      try? await healthStore.delete(sample)
      throw error
    }
    return "written"
  }

  func clear(start: Date, end: Date) async throws -> String {
    guard let workout = try await ownWorkout(start: start, end: end) else {
      return "cleared"
    }
    let own = try await relatedEfforts(workout).filter(isOwn)
    if !own.isEmpty {
      try await healthStore.delete(own)
    }
    return "cleared"
  }

  private func ownWorkout(start: Date, end: Date) async throws -> HKWorkout? {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
      HKQuery.predicateForObjects(from: HKSource.default()),
    ])
    let query = HKSampleQueryDescriptor(
      predicates: [.workout(predicate)],
      sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
      limit: 1
    )
    return try await query.result(for: healthStore).first
  }

  private func relatedEfforts(_ workout: HKWorkout) async throws -> [HKQuantitySample] {
    let query = HKSampleQueryDescriptor(
      predicates: [
        .quantitySample(
          type: effortType,
          predicate: HKQuery.predicateForWorkoutEffortSamplesRelated(
            workout: workout,
            activity: nil
          )
        )
      ],
      sortDescriptors: []
    )
    return try await query.result(for: healthStore)
  }

  private func relate(_ sample: HKQuantitySample, to workout: HKWorkout) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil) { success, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: HealthEffortError.refused)
        }
      }
    }
  }

  private func isOwn(_ sample: HKSample) -> Bool {
    sample.sourceRevision.source.bundleIdentifier == HKSource.default().bundleIdentifier
  }
}
