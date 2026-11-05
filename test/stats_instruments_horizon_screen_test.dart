// The Instruments caption, the `new` change chip, and ALL TIME leaving Stats
// — Stats 100 P2c. Scenarios S-17304, S-17305, S-17306, S-17307, S-17308 and
// S-17313 of
// `docs/plans/2026-11-02-100-stats-block-horizons-plan/`.
//
// The window is named in words by the Instruments caption, never by a chip;
// a row with nothing comparable behind it reads `new`; and the all-time
// figures live on Records & Trends alone.
//
// Every screen scenario runs on both repository implementations. The harness
// is opened and seeded in `setUp` and never inside a `testWidgets` body: a
// widget test body runs under `FakeAsync`, where Hive's real file I/O never
// settles and the test hangs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/instrument_list.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block the scenarios address is laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

// ─── readers ────────────────────────────────────────────────────────────────

/// Every `Text` under [scope], in document order.
List<String> _textsUnder(Finder scope) {
  final texts = <String>[];
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(Text), matchRoot: true)
          .evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

/// The single `Text` a keyed widget carries, failing if there is not exactly
/// one.
String _textAtKey(WidgetTester tester, String key) {
  final texts = _textsUnder(find.byKey(Key(key)));
  expect(texts, hasLength(1), reason: 'expected one text under $key');
  return texts.single;
}

// ─── fixtures ───────────────────────────────────────────────────────────────

/// Local midnight of the day [daysAgo] days back.
DateTime _day(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo);
}

/// [daysAgo]'s day at [hour] o'clock, in epoch ms.
int _at(int daysAgo, int hour) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch;
}

/// One completed session with one segment. Written directly because the shared
/// `seedSession` cannot express a rating and marks a rolling session
/// unfinished.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  int? rating,
  bool isRolling = false,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      sessionFeeling: rating,
      isRolling: isRolling,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
}

/// A lifting-only session of [minutes]: every second of it is the session's
/// resistance remainder, so it needs no effort to be measured (D-905).
Future<void> _seedLifting(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  int minutes = 60,
  int? rating,
  int hour = 9,
}) async {
  final start = _at(daysAgo, hour);
  await _seedSession(
    repo,
    sessionId: sessionId,
    startedAtMs: start,
    endedAtMs: start + minutes * 60000,
    rating: rating,
  );
}

/// A `timed` effort measuring [seconds] of cardio on [sessionId].
Future<void> _seedCardioEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required int seconds,
}) async {
  final exerciseId = 'ex-cardio-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Easy Run',
    capabilities: const ['time', 'distance'],
  );
  await seedHoldEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-cardio',
    exerciseId: exerciseId,
    entryCount: 1,
    secondsPerEntry: seconds,
    effortKind: 'timed',
  );
}

/// A training period from [daysAgo] to the end of today, named [name].
///
/// The four-week window ignores it; the fixture exists to prove that.
Future<void> _seedPeriod(
  WorkoutRepository repo, {
  required String name,
  required int daysAgo,
}) async {
  final start = _day(daysAgo);
  final now = DateTime.now();
  await repo.createPeriod(
    TrainingPeriod(
      id: 'period-1',
      ownerUserId: 'user-1',
      name: name,
      startDateMs: start.millisecondsSinceEpoch,
      endDateMs: DateTime(
        now.year,
        now.month,
        now.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch,
      focusModalities: const [],
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: start.millisecondsSinceEpoch,
    ),
  );
}

/// S-17304's and S-17307's fixture: a period named "Holds" covering today, a
/// 20-minute cardio session inside it, and three 60-minute lifting sessions
/// before the period starts — all four inside the 28-day window.
Future<void> _seedPeriodAndMixedWindow(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Holds', daysAgo: 3);

  final cardioStart = _at(0, 9);
  await _seedSession(
    repo,
    sessionId: 's-cardio-today',
    startedAtMs: cardioStart,
    endedAtMs: cardioStart + 20 * 60000,
  );
  await _seedCardioEffort(repo, sessionId: 's-cardio-today', seconds: 1200);

  await _seedLifting(repo, sessionId: 's-lift-8', daysAgo: 8);
  await _seedLifting(repo, sessionId: 's-lift-12', daysAgo: 12);
  await _seedLifting(repo, sessionId: 's-lift-20', daysAgo: 20);
}

// ─── hand-built list pieces ─────────────────────────────────────────────────

/// One resistance row worth `140` on the estimated 1RM, with [previous] as the
/// value the previous window of the same length holds (null when the exercise
/// is new).
InstrumentRow _row(String exerciseId, {NativeValue? previous}) {
  return InstrumentRow(
    summary: ExerciseMetricSummary(
      exerciseId: exerciseId,
      name: 'Back Squat',
      section: ExerciseSection.resistance,
      best: const NativeValue(
        metric: NativeMetric.estimatedOneRepMax,
        value: 140,
      ),
      points: const [],
      lastTrainedMs: DateTime(2026, 4, 20).millisecondsSinceEpoch,
      sessionCount: 1,
    ),
    previousValue: previous,
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Instruments horizon — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
        workoutState = WorkoutState(repo);
        settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
      });

      tearDown(() async {
        await harness.close();
      });

      Future<void> pumpStats(
        WidgetTester tester, {
        Size size = _kTallViewport,
        double textScale = 1.0,
      }) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MaterialApp(
              home: StatsScreen(
                workoutState: workoutState,
                settingsState: settingsState,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      /// Pumps [sections] through `InstrumentList` directly, the way
      /// `instrument_list_screen_test.dart` drives a hand-built window.
      Future<void> pumpList(
        WidgetTester tester, {
        required StatsWindow window,
        required List<InstrumentSectionData> sections,
      }) async {
        await tester.binding.setSurfaceSize(_kTallViewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InstrumentList(
                  sections: sections,
                  window: window,
                  themeColors: OmniTheme.colorsForTheme(
                    settingsState.appTheme,
                  ),
                  workoutState: workoutState,
                  settingsState: settingsState,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // ─── S-17304 ─────────────────────────────────────────────────────────

      group('S-17304 the caption is one plain line', () {
        setUp(() => _seedPeriodAndMixedWindow(repo));

        testWidgets('the caption names the window and its previous span, and '
            'no chip names it', (tester) async {
          await pumpStats(tester);

          final caption = find.byKey(const Key('instrument_caption'));
          expect(caption, findsOneWidget);
          expect(
            _textsUnder(caption),
            ['Last 4 weeks. Change is against the 4 weeks before.'],
          );

          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17305 ─────────────────────────────────────────────────────────

      group('S-17305 a row with nothing to compare against reads new', () {
        testWidgets('the three rows read new, the dash, and an arrow figure',
            (tester) async {
          await pumpList(
            tester,
            window: StatsWindow(
              fromMs: DateTime(2026, 4, 14),
              toMs: DateTime(2026, 4, 20, 23, 59, 59, 999),
              label: 'Custom',
              isPeriodScoped: false,
            ),
            sections: [
              InstrumentSectionData(
                section: ExerciseSection.resistance,
                trainingDayCount: 3,
                rows: [
                  // No previous window value at all.
                  _row('ex-new'),
                  // A previous value equal to the window's: no change.
                  _row(
                    'ex-same',
                    previous: const NativeValue(
                      metric: NativeMetric.estimatedOneRepMax,
                      value: 140,
                    ),
                  ),
                  // A previous value the window has moved past.
                  _row(
                    'ex-up',
                    previous: const NativeValue(
                      metric: NativeMetric.estimatedOneRepMax,
                      value: 120,
                    ),
                  ),
                ],
              ),
            ],
          );

          expect(_textAtKey(tester, 'instrument_change_ex-new'), 'new');
          expect(_textAtKey(tester, 'instrument_change_ex-same'), '—');
          expect(
            _textAtKey(tester, 'instrument_change_ex-up'),
            startsWith('↑ +'),
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17306 ─────────────────────────────────────────────────────────

      group('S-17306 the caption counts the window\'s own span', () {
        Future<void> expectCaption(
          WidgetTester tester, {
          required DateTime from,
          required DateTime to,
          required String expected,
        }) async {
          await pumpList(
            tester,
            window: StatsWindow(
              fromMs: from,
              toMs: to,
              label: 'Custom',
              isPeriodScoped: false,
            ),
            sections: [
              InstrumentSectionData(
                section: ExerciseSection.resistance,
                trainingDayCount: 1,
                rows: [_row('ex-one')],
              ),
            ],
          );

          expect(
            _textsUnder(find.byKey(const Key('instrument_caption'))),
            [expected],
          );
          expect(tester.takeException(), isNull);
        }

        testWidgets('a ten-day window reads the ten days before it',
            (tester) async {
          await expectCaption(
            tester,
            from: DateTime(2026, 4, 11),
            to: DateTime(2026, 4, 20, 23, 59, 59, 999),
            expected: 'Custom. Change is against the 10 days before.',
          );
        });

        testWidgets('a seven-day window reads the one week before it',
            (tester) async {
          await expectCaption(
            tester,
            from: DateTime(2026, 4, 14),
            to: DateTime(2026, 4, 20, 23, 59, 59, 999),
            expected: 'Custom. Change is against the 1 week before.',
          );
        });

        testWidgets('a one-day window reads the one day before it',
            (tester) async {
          await expectCaption(
            tester,
            from: DateTime(2026, 4, 20),
            to: DateTime(2026, 4, 20, 23, 59, 59, 999),
            expected: 'Custom. Change is against the 1 day before.',
          );
        });
      });

      // ─── S-17307 ─────────────────────────────────────────────────────────

      group('S-17307 ALL TIME is on Records & Trends only', () {
        setUp(() => _seedPeriodAndMixedWindow(repo));

        testWidgets('Stats shows no all-time block, and its blocks keep their '
            'order', (tester) async {
          await pumpStats(tester);

          expect(find.text('ALL TIME'), findsNothing);
          expect(find.byKey(const Key('all_time_card')), findsNothing);
          expect(find.text('Streak'), findsNothing);
          expect(find.text('STREAK'), findsNothing);

          // The blocks appear in order: Mix, then the signals layer (or its
          // locked line when the gate is unmet), then the Instruments list.
          final mixTop = tester
              .getTopLeft(find.byKey(const Key('mix_layer')))
              .dy;

          const signalsFinder = Key('signals_layer');
          const lockedFinder = Key('signals_locked');
          final double signalsTop;
          if (find.byKey(signalsFinder).evaluate().isNotEmpty) {
            signalsTop = tester.getTopLeft(find.byKey(signalsFinder)).dy;
          } else {
            expect(find.byKey(lockedFinder), findsOneWidget);
            signalsTop = tester.getTopLeft(find.byKey(lockedFinder)).dy;
          }

          final captionTop = tester
              .getTopLeft(find.byKey(const Key('instrument_caption')))
              .dy;

          expect(mixTop, lessThan(signalsTop));
          expect(signalsTop, lessThan(captionTop));
          expect(tester.takeException(), isNull);
        });

        testWidgets('S-17307 twin: Records & Trends keeps ALL TIME',
            (tester) async {
          await tester.binding.setSurfaceSize(_kTallViewport);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              home: RecordsAndTrendsScreen(
                workoutState: workoutState,
                settingsState: settingsState,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('ALL TIME'), findsOneWidget);
          final texts = _textsUnder(find.byType(MaterialApp));
          expect(texts, contains('SESSIONS'));
          expect(texts, contains('TIME'));
          expect(texts, contains('STREAK'));
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17308 ─────────────────────────────────────────────────────────

      group('S-17308 twin: no session at all', () {
        testWidgets('the empty state stands alone, with no all-time block',
            (tester) async {
          await pumpStats(tester);

          expect(find.text('No sessions yet'), findsOneWidget);
          expect(find.text('ALL TIME'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });
    });
  }

  // ─── S-17313 ─────────────────────────────────────────────────────────────

  test('S-17313 the chip is gone from the source', () {
    expect(
      File('lib/features/stats/widgets/window_chip.dart').existsSync(),
      isFalse,
    );

    final offenders = <String>[];
    for (final entity
        in Directory('lib/features/stats').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final source = entity.readAsStringSync();
        if (source.contains('StatsWindowChip') ||
            source.contains('stats_window_chip')) {
          offenders.add(entity.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
