// The phone's reference data on its way to the wrist: the lists that let the
// watch work while the phone is in another room, and the settings it honours.
//
// Plans: `.github/agents/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`
// (scenario S-003, the foods),
// `.github/agents/plans/2026-09-21-13-watch-integration-shipping.md` (Phase 3,
// scenario S-003/S-007, the routines), and
// `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md` (D-113,
// scenario S-253, the preferences).
//
// Building a message and carrying it are separate jobs, so nothing here sends
// anything: a message is built and handed back, and whoever owns the transport
// sends it. What this owns is the part that must not be got wrong twice — the
// order and the numbers the wrist will read.
//
// The order travels with the message instead of the rule travelling with it: the
// phone sorts by its own Foods I Eat rule (`foods_i_eat_order.dart`) before it
// sends, and the wrist shows what it was sent in the order it arrived. The wrist
// then does its own thing on top — what the user quick-logs moves to the front —
// which is why the two surfaces agree about where a food sits without either
// owning the other's list.

library;

import '../constants/block_types.dart';
import '../constants/metric_ids.dart';
import '../sync_protocol/phone_envelope.dart';
import '../sync_protocol/wire_timestamps.dart';
import 'food_helpers.dart';
import 'foods_i_eat_order.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

/// An exercise as `routines_down` carries it: what the wrist needs to render an
/// effort and to offer the exercise in the fallback list.
///
/// Capabilities are the one thing an [Exercise] row does not hold — they live in
/// their own table, which is why they are resolved once here and travel with the
/// name rather than being looked up again per effort row.
typedef _SyncedExercise = ({
  String id,
  String name,
  List<String> capabilities,
});

/// Resolves exercises to what the wire carries, reading each one's capabilities
/// at most once per message.
class _ExerciseResolver {
  _ExerciseResolver(this._repository);

  final WorkoutRepository _repository;
  final Map<String, String> _names = {};
  final Map<String, List<String>> _capabilities = {};

  Future<_SyncedExercise?> resolve(String? exerciseId) async {
    if (exerciseId == null) return null;

    if (_names.isEmpty) {
      for (final exercise in await _repository.getExercises()) {
        _names[exercise.id] = exercise.name;
      }
    }
    final name = _names[exerciseId];
    if (name == null) return null;

    final capabilities = _capabilities[exerciseId] ??=
        await _repository.getExerciseCapabilities(exerciseId);
    if (capabilities.isEmpty) return null;

    return (id: exerciseId, name: name, capabilities: capabilities);
  }
}

abstract final class WatchReferenceSync {
  /// The phone's routines, as the `routines_down` message the wrist reads.
  ///
  /// Assembled from storage when the wrist asks for them, not on a schedule of
  /// the phone's own: the watch is the one that knows when its user wants the
  /// routines (D-7), and a phone that pushed them on every launch would be
  /// talking to a wrist nobody asked to hear from.
  ///
  /// [generatedAt] is what makes a rebuild the same message rather than a newer
  /// one — a set of routines nobody has edited since carries the timestamp it
  /// arrived with, and a wrist holding it drops the duplicate. It is also the
  /// only thing the payload's identity rests on, which is why the message id is
  /// derived from it.
  ///
  /// Returns null when there is nothing the wrist could start: no routine, or
  /// none whose exercises the phone still holds. An empty `routines` array is
  /// not an option — the schema requires at least one — and a message the watch
  /// must reject is worse than no message at all.
  static Future<Map<String, Object?>?> buildRoutinesDown({
    required WorkoutRepository repository,
    required DateTime generatedAt,
  }) async {
    final resolver = _ExerciseResolver(repository);
    final referenced = <String, _SyncedExercise>{};

    final routines = <Map<String, Object?>>[];
    for (final template in await repository.getTemplates()) {
      final segments = await _segmentsJson(
        repository,
        template: template,
        resolve: resolver.resolve,
        referenced: referenced,
      );
      if (segments.isEmpty) continue;

      routines.add({
        'routineId': template.id,
        'name': template.name,
        'updatedAt': utcIso(
          DateTime.fromMillisecondsSinceEpoch(
            template.updatedAtMs,
            isUtc: true,
          ),
        ),
        'segments': segments,
      });
    }

    if (routines.isEmpty) return null;

    return phoneEnvelope(
      type: 'routines_down',
      messageId: 'msg-routines-${generatedAt.toUtc().millisecondsSinceEpoch}',
      sentAt: generatedAt,
      payload: {
        'generatedAt': utcIso(generatedAt),
        'routines': routines,
        'fallbackExercises': _fallbackJson(referenced),
      },
    );
  }

  /// Every exercise the routines reference, in routine order.
  ///
  /// The fallback list is what lets the wrist run a routine with the phone
  /// unreachable, so a routine this list does not cover is a routine the watch
  /// must not hold (PROTOCOL.md, "Message families").
  static List<Map<String, Object?>> _fallbackJson(
    Map<String, _SyncedExercise> referenced,
  ) => [
    for (final exercise in referenced.values)
      {
        'exerciseId': exercise.id,
        'name': exercise.name,
        'capabilities': exercise.capabilities,
      },
  ];

  /// The routine's segments, with the efforts the wrist can actually log.
  ///
  /// An effort naming no exercise, an exercise the phone no longer holds, or one
  /// carrying no capabilities is left out: the wrist renders an effort from its
  /// capabilities, and an effort it cannot render would make the whole message
  /// non-conformant. A segment left with no efforts is dropped with it, because
  /// the schema wants at least one.
  static Future<List<Map<String, Object?>>> _segmentsJson(
    WorkoutRepository repository, {
    required WorkoutTemplate template,
    required Future<_SyncedExercise?> Function(String?) resolve,
    required Map<String, _SyncedExercise> referenced,
  }) async {
    final segments = await repository.getTemplateSegments(template.id);
    final ordered = [...segments]
      ..sort((left, right) => left.orderIndex.compareTo(right.orderIndex));

    final encoded = <Map<String, Object?>>[];
    for (final segment in ordered) {
      final efforts = <Map<String, Object?>>[];
      for (final effort in await repository.getTemplateEfforts(segment.id)) {
        final exercise = await resolve(effort.exerciseId);
        if (exercise == null) continue;

        referenced[exercise.id] = exercise;
        efforts.add({
          'effortId': effort.id,
          'exerciseId': exercise.id,
          'exerciseName': exercise.name,
          'effortKind': _wireEffortKind(effort.effortKind),
          'capabilities': exercise.capabilities,
          'targets': _targetsJson(
            await repository.getTemplateTargets(effort.id),
            isHold: _isHold(effort),
          ),
        });
      }

      if (efforts.isEmpty) continue;
      encoded.add({
        'segmentId': segment.id,
        'name': segment.name ?? 'Segment',
        'efforts': efforts,
      });
    }

    return encoded;
  }

  /// The app's effort kind in the protocol's vocabulary.
  ///
  /// The two vocabularies are close but not equal, and the wire's is the
  /// smaller one: an interval is timed work, an AMRAP is rounds for time, and a
  /// freeform note carries no exercise, so it is filtered out before it gets
  /// here and the default below never sees one.
  static String _wireEffortKind(String effortKind) {
    switch (effortKind) {
      case BlockTypes.timed:
      case BlockTypes.interval:
        return BlockTypes.timed;
      case BlockTypes.amrap:
      case BlockTypes.round:
        return BlockTypes.round;
      case BlockTypes.drill:
        return BlockTypes.drill;
      default:
        return BlockTypes.set;
    }
  }

  static bool _isHold(TemplateEffort effort) =>
      effort.effortKind == BlockTypes.drill;

  /// The effort's planned values, keyed the way the protocol keys them.
  ///
  /// A routine's targets are per metric *and per set*; the wire's are per
  /// effort, so the first set is what travels — the wrist shows the plan for
  /// the set about to be done, and the phone's own screen is where the rest
  /// stay. Metrics the wire has no key for (RPE, rest, band assist) are not
  /// sent, because the schema carries no field for them.
  static Map<String, Object?> _targetsJson(
    List<TemplateTarget> targets, {
    required bool isHold,
  }) {
    if (targets.isEmpty) return const {};

    final firstSet = <String, TemplateTarget>{};
    for (final target in targets) {
      final existing = firstSet[target.metricId];
      if (existing == null ||
          (target.setIndex ?? 0) < (existing.setIndex ?? 0)) {
        firstSet[target.metricId] = target;
      }
    }

    final encoded = <String, Object?>{};
    for (final entry in firstSet.entries) {
      final wireKey = _wireTargetKey(entry.key, isHold: isHold);
      if (wireKey == null) continue;

      final value = _targetValue(entry.value, wireKey);
      if (value != null) encoded[wireKey] = value;
    }
    return encoded;
  }

  /// The wire's key for an app metric, or null when the wire has none.
  static String? _wireTargetKey(String metricId, {required bool isHold}) {
    switch (metricId) {
      case MetricIds.reps:
        return 'reps';
      case MetricIds.sets:
        return 'sets';
      case MetricIds.weight:
        return 'loadKg';
      case MetricIds.duration:
        return isHold ? 'holdMs' : 'durationMs';
      case MetricIds.roundDuration:
        return 'durationMs';
      case MetricIds.distance:
        return 'distanceMeters';
      case MetricIds.rounds:
        return 'rounds';
      default:
        return null;
    }
  }

  /// The value [target] carries, in the unit its wire key speaks.
  ///
  /// Durations are stored in seconds and travel in milliseconds; a range target
  /// travels as the low end, which is the number the wrist plans against.
  static Object? _targetValue(TemplateTarget target, String wireKey) {
    final number = target.targetInt ?? target.targetMin ?? target.targetMax;
    if (number == null) return null;

    return wireKey == 'holdMs' || wireKey == 'durationMs'
        ? (number * Duration.millisecondsPerSecond).round()
        : number;
  }

  /// The phone's settings the wrist honours, as the `preferences_down` message
  /// it reads — today, whether a session ended on the wrist asks for the
  /// session effort rating ([effortRatingPrompt]).
  ///
  /// Its own message rather than a field on `routines_down`, because
  /// [buildRoutinesDown] answers null for a phone with no routines, and a
  /// setting riding on it would then never reach the wrist (D-113).
  ///
  /// The wrist keeps the copy with the latest [generatedAt], and on a tie the
  /// one it received later. The message id follows the content for that
  /// reason: a rebuild of the same setting is the same message, while a
  /// different setting stamped in the same millisecond is a different one
  /// that must not be dropped as a redelivery.
  static Map<String, Object?> buildPreferencesDown({
    required bool effortRatingPrompt,
    required DateTime generatedAt,
  }) => phoneEnvelope(
    type: 'preferences_down',
    messageId:
        'msg-preferences-${generatedAt.toUtc().millisecondsSinceEpoch}-'
        '${effortRatingPrompt ? 'on' : 'off'}',
    sentAt: generatedAt,
    payload: {
      'generatedAt': utcIso(generatedAt),
      'effortRatingPrompt': effortRatingPrompt,
    },
  );

  /// The phone's foods, as the `foods_down` message the wrist reads.
  ///
  /// [generatedAt] is what makes a rebuild the same message rather than a newer
  /// one: a list nobody has added to since carries the timestamp it arrived
  /// with, and a wrist holding it drops the duplicate.
  static Map<String, Object?> buildFoodsDown({
    required List<Food> foods,
    required List<FoodGroup> groups,
    required DateTime generatedAt,
  }) {
    final ordered = [
      for (final section in foodsIEatSections(foods: foods, groups: groups))
        for (final food in section.foods) food,
    ];
    final categoryNames = {for (final group in groups) group.id: group.name};
    final categories = categoryNames.keys.toList()
      ..sort(
        (left, right) =>
            compareFoodNames(categoryNames[left]!, categoryNames[right]!),
      );

    return phoneEnvelope(
      type: 'foods_down',
      messageId: 'msg-foods-${generatedAt.toUtc().millisecondsSinceEpoch}',
      sentAt: generatedAt,
      payload: {
        'generatedAt': utcIso(generatedAt),
        'categories': [
          for (final id in categories)
            {'categoryId': id, 'name': categoryNames[id]!},
        ],
        'foods': [for (final food in ordered) _foodJson(food, categoryNames)],
      },
    );
  }

  /// One food, in the shape the schema pins. A food whose group the phone no
  /// longer holds has no category to name, which is a valid answer rather than
  /// a reason to drop the food.
  static Map<String, Object?> _foodJson(
    Food food,
    Map<String, String> categoryNames,
  ) {
    final groupId = food.groupId;
    final amount = food.lastAmountConsumed;
    return {
      'foodId': food.id,
      'name': food.name,
      'categoryId': groupId != null && categoryNames.containsKey(groupId)
          ? groupId
          : null,
      'referenceAmount': food.referenceAmount,
      'referenceLabel': food.referenceLabel,
      // One serving is one reference amount, so the energy per serving is the
      // energy of the macros on the food — the phone's own derivation, so the
      // wrist and the card cannot disagree about what a food costs.
      'caloriesPerServing': calculateCalories(food),
      // The portion the user last took, in servings. A food nobody has logged
      // offers one serving, which is the phone's own pre-fill rule.
      'defaultServings': amount == null || food.referenceAmount <= 0
          ? 1
          : amount / food.referenceAmount,
    };
  }
}
