//
// Plan 214 — S-21402..S-21405: with Effort Rating off in Settings and the
// rated-week gate unmet, the Stats screen says the setting is the reason —
// on the locked Signals line, on the line under a card that needs no
// ratings, and on the Mix baseline note — and flipping the setting while the
// screen is open updates the lines without a second load.
//
// Plan: `docs/plans/2026-11-16-214-stats-says-when-effort-rating-is-off-plan/`.
//
// Mock-only: a widget test body runs under `FakeAsync`, where a Hive read
// never settles, so the store under test is the in-memory
// `MockWorkoutRepository`, opened and seeded in `setUp`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the Signals block and the Mix note are both laid out, so
/// an assertion on a widget's absence is never just an off-screen miss.
const Size _kViewport = Size(400, 2400);

/// The off copy the three slots show while the gate is unmet (0 rated weeks).
const String _kLockedOffCopy =
    'Effort Rating is off in Settings, so signals that need it stay '
    'locked — 0 of 4 weeks rated so far.';
const String _kMoreOffCopy =
    'Effort Rating is off in Settings, so more signals stay locked — '
    '0 of 4 weeks rated so far.';
const String _kMixNoteOffCopy =
    'Showing time for now. Effort Rating is off in Settings (0 of 4 weeks '
    'rated).';
const String _kMixNoteDefaultCopy =
    'Showing time for now. Effort appears once 4 weeks are rated '
    '(0 of 4 so far).';

/// A Mock repository that counts the history reads, so S-21405 can assert the
/// setting flip did not start a second load.
class _CountingRepository extends MockWorkoutRepository {
  int sessionsReads = 0;

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    sessionsReads++;
    return super.getAllSessions();
  }
}

/// A registered signal that needs no ratings and always shows a card, so the
/// hint under it is the line under test (S-21403's shape, minimal).
class _OpenSignal implements Signal {
  @override
  final String id = 'open-1';

  @override
  final SignalKind kind = SignalKind.positive;

  @override
  final int priority = 10;

  @override
  final bool needsRatedWeeks = false;

  int evaluations = 0;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    evaluations++;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: 'title $id',
      observation: 'observation $id',
    );
  }

  @override
  Future<String?> waitingFor(SignalContext context) async => null;
}

void main() {
  late _CountingRepository repo;
  late WorkoutState workoutState;
  late SettingsState settingsState;

  setUp(() async {
    repo = _CountingRepository();
    await repo.initialize();
    // One completed session with no rating and one set effort: the gate is
    // unmet (0 rated weeks) and the Mix strip is on the time measure.
    await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
    await seedExercise(repo, id: 'ex-row', name: 'Row', capabilities: ['load']);
    await seedSetEffort(
      repo,
      segmentId: 'seg-sess-1',
      effortId: 'eff-1',
      exerciseId: 'ex-row',
      entryCount: 2,
      hasExtraWeight: false,
    );
    workoutState = WorkoutState(repo);
    settingsState = SettingsState(repo, fakePreferencesService());
    await settingsState.initialize();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Signal> signals = const <Signal>[],
  }) async {
    await tester.binding.setSurfaceSize(_kViewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: StatsScreen(
          workoutState: workoutState,
          settingsState: settingsState,
          signals: signals,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String lockedLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('signals_locked_line'))).data!;

  String lockedHint(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('signals_locked_hint'))).data!;

  String mixNote(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('mix_baseline_note'))).data!;

  group('Effort Rating off', () {
    setUp(() async {
      await settingsState.setShowFeelingSurvey(false);
    });

    group('S-21402 the locked line names the setting', () {
      testWidgets('the locked line is the off copy with 0 of 4', (
        tester,
      ) async {
        await pump(tester);

        expect(find.byKey(const Key('signals_locked_line')), findsOneWidget);
        expect(lockedLine(tester), _kLockedOffCopy);
      });
    });

    group('S-21403 the hint under a card that needs no ratings names the '
        'setting', () {
      testWidgets('the hint is the off copy with 0 of 4', (tester) async {
        final open = _OpenSignal();
        await pump(tester, signals: [open]);

        expect(find.byKey(const Key('signals_locked_hint')), findsOneWidget);
        expect(lockedHint(tester), _kMoreOffCopy);
        expect(open.evaluations, 1);
      });
    });

    group('S-21404 the Mix baseline note names the setting', () {
      testWidgets('the note is the off copy with 0 of 4', (tester) async {
        await pump(tester);

        expect(find.byKey(const Key('mix_baseline_note')), findsOneWidget);
        expect(mixNote(tester), _kMixNoteOffCopy);
      });
    });

    group('S-21405 the flip while the screen is open', () {
      testWidgets('turning Effort Rating on restores both lines with no '
          'second load', (tester) async {
        await pump(tester);
        expect(lockedLine(tester), _kLockedOffCopy);
        expect(mixNote(tester), _kMixNoteOffCopy);

        final readsBefore = repo.sessionsReads;
        await tester.runAsync(() => settingsState.setShowFeelingSurvey(true));
        await tester.pumpAndSettle();

        expect(lockedLine(tester), signalsLockedLine(0));
        expect(mixNote(tester), _kMixNoteDefaultCopy);
        expect(repo.sessionsReads, readsBefore);
      });
    });
  });

  group('control: Effort Rating on (the default)', () {
    testWidgets('S-21402 the locked line is the existing wait copy', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byKey(const Key('signals_locked_line')), findsOneWidget);
      expect(lockedLine(tester), signalsLockedLine(0));
    });

    testWidgets('S-21403 the hint is the existing more-signals copy', (
      tester,
    ) async {
      final open = _OpenSignal();
      await pump(tester, signals: [open]);

      expect(find.byKey(const Key('signals_locked_hint')), findsOneWidget);
      expect(lockedHint(tester), signalsMoreLine(0));
    });

    testWidgets('S-21404 the Mix note is the existing appears-once copy', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byKey(const Key('mix_baseline_note')), findsOneWidget);
      expect(mixNote(tester), _kMixNoteDefaultCopy);
    });
  });
}
