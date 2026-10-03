// The Signals service (Stats PR 6a, Phase 1): the gate-gated evaluation, the
// dismissal store, its pruning and its Mock/Hive parity.
//
// Scenarios S-1702, S-1708, S-1709, S-1710, S-1712 and D-1013 of
// `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/`, on plain
// `test()` so Hive's real file I/O settles. The Hive harness is opened in
// `setUp`, never inside a widget-test body.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/signals_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A signal whose evaluation is counted and whose card, when it produces one,
/// carries the signal's own id, kind and priority.
class _StubSignal implements Signal {
  _StubSignal({
    required this.id,
    required this.kind,
    required this.priority,
    this.abstains = false,
  });

  @override
  final String id;
  @override
  final SignalKind kind;
  @override
  final int priority;
  final bool abstains;

  int evaluations = 0;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    evaluations++;
    if (abstains) return null;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: 'title $id',
      observation: 'observation $id',
      suggestion: 'suggestion $id',
    );
  }
}

final StatsWindow _window = StatsWindow(
  fromMs: DateTime(2026, 3, 1),
  toMs: DateTime(2026, 3, 31),
  label: 'Test window',
  isPeriodScoped: false,
  recentDays: 30,
);

MixLayerData _mix({required int ratedBaselineWeeks}) => MixLayerData(
  measure: MixMeasure.time,
  segments: const [],
  baselineSegments: const [],
  unratedSessionCount: 0,
  ratedBaselineWeeks: ratedBaselineWeeks,
  weeks: const [],
);

MixLayerData get _mixReady =>
    _mix(ratedBaselineWeeks: kTrainingLoadMinRatedWeeks);

MixLayerData get _mixUnmet =>
    _mix(ratedBaselineWeeks: kTrainingLoadMinRatedWeeks - 1);

SignalsService _service(WorkoutRepository repo, List<Signal> signals) =>
    SignalsService(
      repository: repo,
      progressService: StatsProgressService(repo),
      signals: signals,
    );

void main() {
  group('SignalsService — the gate and evaluation', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-1702 an unmet gate returns nothing and evaluates nothing', () async {
      final positive = _StubSignal(
        id: 'p',
        kind: SignalKind.positive,
        priority: 10,
      );
      final caution = _StubSignal(
        id: 'c',
        kind: SignalKind.caution,
        priority: 20,
      );
      final service = _service(repo, [positive, caution]);
      final now = DateTime(2026, 3, 10, 12);

      expect(
        await service.evaluateCandidates(
          now: now,
          window: _window,
          mix: _mixUnmet,
        ),
        isEmpty,
      );
      expect(
        await service.evaluateCandidates(now: now, window: _window, mix: null),
        isEmpty,
      );
      expect(positive.evaluations, 0);
      expect(caution.evaluations, 0);
    });

    test('a met gate evaluates each signal once and returns its cards', () async {
      final positive = _StubSignal(
        id: 'p',
        kind: SignalKind.positive,
        priority: 10,
      );
      final caution = _StubSignal(
        id: 'c',
        kind: SignalKind.caution,
        priority: 20,
      );
      final service = _service(repo, [positive, caution]);

      final cards = await service.evaluateCandidates(
        now: DateTime(2026, 3, 10, 12),
        window: _window,
        mix: _mixReady,
      );
      expect(cards.map((card) => card.id), ['p', 'c']);
      expect(positive.evaluations, 1);
      expect(caution.evaluations, 1);
    });

    test('S-1708 an abstaining signal adds nothing and suppresses nothing', () async {
      final abstainer = _StubSignal(
        id: 'a',
        kind: SignalKind.positive,
        priority: 99,
        abstains: true,
      );
      final positive = _StubSignal(
        id: 'p',
        kind: SignalKind.positive,
        priority: 10,
      );
      final service = _service(repo, [abstainer, positive]);

      final cards = await service.evaluateCandidates(
        now: DateTime(2026, 3, 10, 12),
        window: _window,
        mix: _mixReady,
      );
      expect(cards.map((card) => card.id), ['p']);
      expect(abstainer.evaluations, 1);

      final alone = _service(repo, [abstainer]);
      expect(
        await alone.evaluateCandidates(
          now: DateTime(2026, 3, 10, 12),
          window: _window,
          mix: _mixReady,
        ),
        isEmpty,
      );
    });
  });

  group('SignalsService — dismissals', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-1709 a dismissed id is filtered out of the evaluated candidates', () async {
      final positive = _StubSignal(
        id: 'sig-positive',
        kind: SignalKind.positive,
        priority: 10,
      );
      final service = _service(repo, [positive]);
      final now = DateTime(2026, 3, 10, 12);

      final before = await service.evaluateCandidates(
        now: now,
        window: _window,
        mix: _mixReady,
      );
      expect(before.map((card) => card.id), ['sig-positive']);

      await service.dismiss('sig-positive', now);

      final after = await service.evaluateCandidates(
        now: now,
        window: _window,
        mix: _mixReady,
      );
      expect(after, isEmpty);
      expect(
        (await service.loadDismissals()).containsKey('sig-positive'),
        isTrue,
      );
      expect(positive.evaluations, 2);
    });

    test('the store key is the pinned preference and its value is a JSON object', () async {
      final service = _service(repo, const []);
      final now = DateTime(2026, 3, 10, 12);
      await service.dismiss('sig-positive', now);

      final raw = await repo.getPreferenceString(kSignalDismissalsKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['sig-positive'], now.millisecondsSinceEpoch);
    });

    test('persistDismissals writes a map that reads back value-for-value', () async {
      final service = _service(repo, const []);
      final now = DateTime(2026, 3, 10, 12);
      final stored = signalDismissalsWith(const {}, 'sig-positive', now);

      await service.persistDismissals(stored);

      expect(await service.loadDismissals(), stored);
      final raw = await repo.getPreferenceString(kSignalDismissalsKey);
      expect(jsonDecode(raw!), stored);
    });

    test('D-1013 a write prunes entries at 14 days and keeps them at 13', () async {
      final service = _service(repo, const []);
      final mar1 = DateTime(2026, 3, 1, 12);
      final mar14 = DateTime(2026, 3, 14, 12);
      final mar15 = DateTime(2026, 3, 15, 12);

      await service.dismiss('a', mar1);
      expect((await service.loadDismissals()).keys.toSet(), {'a'});

      await service.dismiss('b', mar14);
      expect((await service.loadDismissals()).keys.toSet(), {'a', 'b'});

      await service.dismiss('c', mar15);
      expect((await service.loadDismissals()).keys.toSet(), {'b', 'c'});
    });
  });

  group('S-1712 Mock and Hive parity', () {
    late RepositoryHarness mockHarness;
    late RepositoryHarness hiveHarness;
    late WorkoutRepository mockRepo;
    late WorkoutRepository hiveRepo;

    setUp(() async {
      mockHarness = MockRepositoryHarness();
      hiveHarness = HiveRepositoryHarness();
      mockRepo = await mockHarness.open();
      hiveRepo = await hiveHarness.open();
    });

    tearDown(() async {
      await mockHarness.close();
      await hiveHarness.close();
    });

    test('S-1712 a dismissal round-trips identically through both stores', () async {
      final mockService = _service(mockRepo, const []);
      final hiveService = _service(hiveRepo, const []);
      final now = DateTime(2026, 3, 1, 12);

      final mockMap = await mockService.dismiss('sig-positive', now);
      final hiveMap = await hiveService.dismiss('sig-positive', now);
      expect(mockMap, hiveMap);
      expect(await mockService.loadDismissals(), await hiveService.loadDismissals());

      final mockRaw = await mockRepo.getPreferenceString(kSignalDismissalsKey);
      final hiveRaw = await hiveRepo.getPreferenceString(kSignalDismissalsKey);
      expect(mockRaw, hiveRaw);
      final decoded = jsonDecode(hiveRaw!) as Map<String, dynamic>;
      expect(decoded['sig-positive'], isA<int>());
      expect(decoded['sig-positive'], now.millisecondsSinceEpoch);
    });
  });
}
