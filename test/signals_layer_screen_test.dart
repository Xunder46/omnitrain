// The Signals layer (Stats PR 6a, Phase 2) — the screen half of the framework.
//
// Scenarios S-1701…S-1713, S-1715 and S-1716's copy checks of
// `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/`, on both
// repository implementations.
//
// Every card this file asserts on comes from a stub the file defines and
// injects through the screen's `signals:` seam (`StatsScreen(signals: […])`,
// D-1016). Each stub records how many times it was evaluated, which is how the
// gate's "no work when the gate is unmet" claim (D-1006) is checked rather than
// assumed.
//
// The gate is the load baseline: Fixture U carries no ratings and renders no
// layer at all, Fixture R carries four rated weeks and renders one. Both are
// built in the shape `test/mix_layer_screen_test.dart` already uses.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. S-1712 is the one exception — it restarts
// the repository *after* a pump, inside `tester.runAsync`.

import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/chart/scrollable_trend_chart.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block the scenarios address is laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// S-1715's viewport: the narrowest width and the largest text scale the suite
/// uses, so a card that overflows at that combination fails here.
const Size _kNarrowViewport = Size(375, 667);
const double _kNarrowTextScale = 1.3;

/// The strings no card on the layer may carry (S-1716): nothing here is
/// estimated, nothing counts calories or heart rate, and nothing names a legacy
/// surface or coaches.
const List<String> _kForbiddenCopy = <String>[
  'est.',
  'should',
  'calories',
  'heart',
  'bpm',
  'STRENGTH',
  'CARDIO',
  'ISOMETRIC',
  'SPORTS',
  'NUTRITION',
  'rest',
  'deload',
  'recover',
];

/// The dismissal store each implementation read back in S-1712, so the two can
/// be compared value-for-value once both groups have run.
final Map<String, int> _preservedDismissalMs = <String, int>{};

/// The layer the structural guard is about, and the theme whose token set it
/// may not exceed (D-1002).
const String _kLayerPath = 'lib/features/stats/widgets/signals_layer.dart';
const String _kThemePath = 'lib/core/constants/omni_theme.dart';

/// The field names of the `OmniThemeColors` record typedef, read from source so
/// a token added to the theme is a name this guard knows about.
Set<String> _omniThemeColorFields() {
  final source = File(_kThemePath).readAsStringSync();
  final start = source.indexOf('typedef OmniThemeColors = (');
  final end = source.indexOf('});', start);
  final body = source.substring(start, end);
  return RegExp(
    r'^\s*\w[\w<>, ]*\s+(\w+),',
    multiLine: true,
  ).allMatches(body).map((match) => match.group(1)!).toSet();
}

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

/// Every card key on screen, in document order.
List<String> _cardKeys() {
  final keys = <String>[];
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'signal_card_',
                ),
          )
          .evaluate()) {
    keys.add((element.widget.key! as ValueKey<String>).value);
  }
  return keys;
}

/// The accessibility labels of every `Semantics` under [scope].
List<String> _semanticLabelsUnder(Finder scope) {
  final labels = <String>[];
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(Semantics))
          .evaluate()) {
    final label = (element.widget as Semantics).properties.label;
    if (label != null) labels.add(label);
  }
  return labels;
}

// ─── stubs ──────────────────────────────────────────────────────────────────

/// A registered signal whose card is fixed by the fixture (D-1008, D-1015).
///
/// [abstains] makes `evaluate` return null, [flag] lets a fixture clear the
/// condition between two loads (S-1713), and [evaluations] counts the calls so
/// the gate's "nothing is evaluated" claim is observed, not inferred.
class _StubSignal implements Signal {
  @override
  final String id;

  @override
  final SignalKind kind;

  @override
  int priority;

  final bool abstains;
  bool flag = true;

  final String observation;
  final String? suggestion;

  int evaluations = 0;

  _StubSignal({
    required this.id,
    required this.kind,
    this.priority = 10,
    this.abstains = false,
    String? observation,
    this.suggestion,
  }) : observation = observation ?? 'observation $id';

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    evaluations++;
    if (abstains || !flag) return null;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: 'title $id',
      observation: observation,
      suggestion: suggestion,
    );
  }
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

/// A local wall-clock instant [daysAgo] days back, in epoch ms — the shape a
/// dismissal is stored in.
int _dismissedAtMs(int daysAgo, {int hour = 0, int minute = 0}) {
  final day = _day(daysAgo);
  return DateTime(
    day.year,
    day.month,
    day.day,
    hour,
    minute,
  ).millisecondsSinceEpoch;
}

/// One completed session with one segment. Written directly because the shared
/// `seedSession` cannot express a rating.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  int? rating,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      sessionFeeling: rating,
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
/// resistance remainder, so it needs no effort to be measured.
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

/// A `set` effort on [sessionId] — the resistance row the Instruments list
/// shows.
Future<void> _seedSetEffort(
  WorkoutRepository repo, {
  required String sessionId,
}) async {
  final exerciseId = 'ex-squat-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-set',
    exerciseId: exerciseId,
    entryCount: 3,
    hasExtraWeight: false,
    weightFactor: 100.0,
    repsBase: 5,
  );
}

/// A training period from [daysAgo] to the end of today, named [name].
///
/// `resolveWindow` prefers it over the recency fallback, which is how the
/// gate-met fixture keeps its rated sessions outside the window.
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

/// Rated baseline sessions [daysAgo] days back from the window's start day —
/// the weeks the gate needs before the layer renders at all (D-1006).
Future<void> _seedRatedBaseline(
  WorkoutRepository repo, {
  required int fromDay,
  List<int> offsets = const [80, 60, 40, 20],
  int minutes = 60,
  int rating = 4,
}) async {
  for (final offset in offsets) {
    await _seedLifting(
      repo,
      sessionId: 's-baseline-$offset',
      daysAgo: fromDay + offset,
      minutes: minutes,
      rating: rating,
    );
  }
}

/// The repository's food log, emptied: the Mock harness opens with
/// `SeedData.sampleConsumedFoods()` already written, the Hive harness empty.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One logged `ConsumedFood` on the local day [daysAgo] days back, so the Fuel
/// row renders below the Instruments list.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
}) async {
  final dateMs = _day(daysAgo).millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: id,
      name: id,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: 100,
      carbs: 400,
      fiber: 0,
      fat: 0,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 0,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

/// Fixture U (gate unmet): three completed unrated sessions, no period, so
/// `ratedBaselineWeeks` is below `kTrainingLoadMinRatedWeeks` and the layer must
/// not exist (S-1702). The Instruments list and the Fuel row are seeded anyway,
/// so their presence is asserted on the same load.
Future<void> _seedGateUnmet(WorkoutRepository repo) async {
  await _seedLifting(repo, sessionId: 's-u1', daysAgo: 1);
  await _seedLifting(repo, sessionId: 's-u2', daysAgo: 2);
  await _seedLifting(repo, sessionId: 's-u3', daysAgo: 3, minutes: 45);
  await _seedSetEffort(repo, sessionId: 's-u1');
  await _clearConsumedFoods(repo);
  await _seedFood(repo, id: 'food-u1', daysAgo: 1);
  await _seedFood(repo, id: 'food-u2', daysAgo: 2);
}

/// Fixture R (gate met): a period-scoped window holding one rated 60-minute
/// lifting session, four rated weeks of baseline, and two logged food days.
Future<void> _seedGateMet(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10);
  await _seedLifting(
    repo,
    sessionId: 's-window',
    daysAgo: 3,
    minutes: 60,
    rating: 4,
  );
  await _seedSetEffort(repo, sessionId: 's-window');
  await _clearConsumedFoods(repo);
  await _seedFood(repo, id: 'food-1', daysAgo: 1);
  await _seedFood(repo, id: 'food-2', daysAgo: 2);
}

/// Writes the dismissal store the load will read (D-1009).
Future<void> _seedDismissals(WorkoutRepository repo, Map<String, int> store) =>
    repo.setPreferenceString(kSignalDismissalsKey, jsonEncode(store));

/// The store as the repository reads it back.
Future<Map<String, int>> _readDismissals(WorkoutRepository repo) async =>
    parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey));

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  // ─── Structural guard (Phase 3) ───────────────────────────────────────────
  //
  // The layer's source may name only the theme tokens that already exist and
  // no colour literal. Breaks if the layer adds a hex colour or a token outside
  // the existing set (D-1002). Source-level because a token is not a widget.
  group('Structural guard — the layer adds no colour and no new token', () {
    test('the layer source names only declared OmniThemeColors fields and no '
        'colour literal', () {
      final source = File(_kLayerPath).readAsStringSync();
      expect(source.contains('Color(0x'), isFalse);
      expect(RegExp(r'\bColors\.').hasMatch(source), isFalse);

      final declared = _omniThemeColorFields();
      expect(declared, isNotEmpty);
      final referenced = RegExp(r'themeColors\.(\w+)')
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();
      expect(referenced, isNotEmpty);
      for (final name in referenced) {
        expect(
          declared,
          contains(name),
          reason:
              '`themeColors.$name` is not a declared OmniThemeColors field '
              '(D-1002)',
        );
      }
    });
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('Signals layer — ${harness.name}', () {
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
        List<Signal> signals = const <Signal>[],
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
                signals: signals,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      /// Rebuilds the screen from scratch, so a second load really happens.
      Future<void> reopen(
        WidgetTester tester, {
        List<Signal> signals = const <Signal>[],
      }) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await pumpStats(tester, signals: signals);
      }

      /// Gives a repository write started inside a test body a real
      /// event-loop turn.
      ///
      /// The Hive harness writes to disk: a write's future only resumes when
      /// the real event loop gets a turn, and whatever it schedules after that
      /// only runs when the fake clock is pumped. Without both, Hive's write
      /// queue is still holding a future when `tearDown` closes the box —
      /// which hangs the test.
      Future<void> settleStore(WidgetTester tester) async {
        for (var round = 0; round < 3; round++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      // ─── S-1701 ────────────────────────────────────────────────────────────

      group('S-1701 the layer is the second block', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('the layer sits below the Mix layer and above ALL TIME, '
            'with no quiet line', (tester) async {
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
          );
          await pumpStats(tester, signals: [positive]);

          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          expect(find.text('SIGNALS'), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);

          final signalsTop = tester
              .getTopLeft(find.byKey(const Key('signals_layer')))
              .dy;
          final mixTop = tester
              .getTopLeft(find.byKey(const Key('mix_layer')))
              .dy;
          final allTimeTop = tester.getTopLeft(find.text('ALL TIME')).dy;

          expect(signalsTop, greaterThan(mixTop));
          expect(signalsTop, lessThan(allTimeTop));
          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1702 ────────────────────────────────────────────────────────────

      group('S-1702 gate unmet renders nothing', () {
        setUp(() => _seedGateUnmet(repo));

        testWidgets('no layer, no card, no quiet line, no SIGNALS text, and no '
            'signal is evaluated', (tester) async {
          final caution = _StubSignal(
            id: 'c-1',
            kind: SignalKind.caution,
            priority: 10,
          );
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
          );
          await pumpStats(tester, signals: [caution, positive]);

          expect(find.byKey(const Key('signals_layer')), findsNothing);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text('SIGNALS'), findsNothing);
          expect(_cardKeys(), isEmpty);

          // The rest of the screen is unchanged and unmoved.
          expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          expect(find.text('ALL TIME'), findsOneWidget);
          expect(find.byKey(const Key('all_time_card')), findsOneWidget);
          expect(find.text('Resistance'), findsOneWidget);
          expect(find.byKey(const Key('fuel_section')), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(const Key('mix_layer'))).dy,
            lessThan(tester.getTopLeft(find.text('ALL TIME')).dy),
          );

          expect(caution.evaluations, 0);
          expect(positive.evaluations, 0);
        });
      });

      // ─── S-1703 ────────────────────────────────────────────────────────────

      group('S-1703 gate met, nothing qualifies', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('an abstaining stub leaves the header and the quiet line, '
            'and no card', (tester) async {
          final abstain = _StubSignal(
            id: 'a-1',
            kind: SignalKind.caution,
            priority: 99,
            abstains: true,
          );
          await pumpStats(tester, signals: [abstain]);

          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          expect(find.text('SIGNALS'), findsOneWidget);
          expect(
            tester
                .widget<Text>(find.byKey(const Key('signals_quiet_line')))
                .data,
            kSignalQuietLine,
          );
          expect(_cardKeys(), isEmpty);
          expect(
            find.descendant(
              of: find.byKey(const Key('signals_layer')),
              matching: find.byType(IconButton),
            ),
            findsNothing,
          );
          expect(find.byKey(const Key('all_time_card')), findsOneWidget);
          expect(abstain.evaluations, 1);
        });

        testWidgets('an empty registry leaves the header and the quiet line, '
            'and no card', (tester) async {
          await pumpStats(tester, signals: const <Signal>[]);

          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          expect(find.text('SIGNALS'), findsOneWidget);
          expect(
            tester
                .widget<Text>(find.byKey(const Key('signals_quiet_line')))
                .data,
            kSignalQuietLine,
          );
          expect(_cardKeys(), isEmpty);
          expect(find.byKey(const Key('all_time_card')), findsOneWidget);
        });
      });

      // ─── S-1704 ────────────────────────────────────────────────────────────

      group('S-1704 one qualifying card', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('exactly one card, keyed, with the Positive label, the '
            'observation and the suggestion', (tester) async {
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
            observation: 'Up 8% over the last 6 sessions',
            suggestion: 'Keep the current weekly rhythm for 2 weeks',
          );
          await pumpStats(tester, signals: [positive]);

          expect(_cardKeys(), ['signal_card_p-1']);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);

          final texts = _textsUnder(find.byKey(const Key('signal_card_p-1')));
          expect(texts, contains('Positive'));
          expect(texts, contains('Up 8% over the last 6 sessions'));
          expect(texts, contains('Keep the current weekly rhythm for 2 weeks'));
          // A card's title names it; it is never rendered (D-1001).
          expect(texts, isNot(contains('title p-1')));
          expect(find.byIcon(Icons.trending_up), findsOneWidget);
        });

        testWidgets('a card without a suggestion renders no suggestion line', (
          tester,
        ) async {
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
            observation: 'Up 8% over the last 6 sessions',
          );
          await pumpStats(tester, signals: [positive]);

          final texts = _textsUnder(find.byKey(const Key('signal_card_p-1')));
          expect(texts, contains('Positive'));
          expect(texts, contains('Up 8% over the last 6 sessions'));
          expect(texts.length, 2);
        });
      });

      // ─── S-1705 ────────────────────────────────────────────────────────────

      group('S-1705 both kinds qualify', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('the priority-20 caution sits above the priority-20 '
            'positive, and the priority-10 pair is absent', (tester) async {
          final signals = <Signal>[
            _StubSignal(id: 'c-10', kind: SignalKind.caution, priority: 10),
            _StubSignal(id: 'c-20', kind: SignalKind.caution, priority: 20),
            _StubSignal(id: 'p-10', kind: SignalKind.positive, priority: 10),
            _StubSignal(id: 'p-20', kind: SignalKind.positive, priority: 20),
          ];
          await pumpStats(tester, signals: signals);

          expect(_cardKeys(), ['signal_card_c-20', 'signal_card_p-20']);
          expect(
            tester.getTopLeft(find.byKey(const Key('signal_card_c-20'))).dy,
            lessThan(
              tester.getTopLeft(find.byKey(const Key('signal_card_p-20'))).dy,
            ),
          );
          expect(
            _textsUnder(find.byKey(const Key('signal_card_c-20'))),
            contains('Worth a look'),
          );
          expect(
            _textsUnder(find.byKey(const Key('signal_card_p-20'))),
            contains('Positive'),
          );
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
        });
      });

      // ─── S-1706 ────────────────────────────────────────────────────────────

      group('S-1706 three cautions, no positive', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('the top two cautions render, in priority order, and '
            'nothing else', (tester) async {
          final signals = <Signal>[
            _StubSignal(id: 'c-10', kind: SignalKind.caution, priority: 10),
            _StubSignal(id: 'c-20', kind: SignalKind.caution, priority: 20),
            _StubSignal(id: 'c-30', kind: SignalKind.caution, priority: 30),
          ];
          await pumpStats(tester, signals: signals);

          expect(_cardKeys(), ['signal_card_c-30', 'signal_card_c-20']);
          expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
          expect(find.byIcon(Icons.trending_up), findsNothing);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
        });
      });

      // ─── S-1707 ────────────────────────────────────────────────────────────

      group('S-1707 three positives, no caution', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('the top two positives render, in priority order, and '
            'nothing else', (tester) async {
          final signals = <Signal>[
            _StubSignal(id: 'p-10', kind: SignalKind.positive, priority: 10),
            _StubSignal(id: 'p-20', kind: SignalKind.positive, priority: 20),
            _StubSignal(id: 'p-30', kind: SignalKind.positive, priority: 30),
          ];
          await pumpStats(tester, signals: signals);

          expect(_cardKeys(), ['signal_card_p-30', 'signal_card_p-20']);
          expect(find.byIcon(Icons.trending_up), findsNWidgets(2));
          expect(find.byIcon(Icons.visibility_outlined), findsNothing);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
        });
      });

      // ─── S-1708 ────────────────────────────────────────────────────────────

      group('S-1708 an abstaining signal is invisible', () {
        setUp(() => _seedGateMet(repo));

        testWidgets(
          'an abstaining stub at the top priority neither renders nor '
          'suppresses the others',
          (tester) async {
            final signals = <Signal>[
              _StubSignal(
                id: 'a-1',
                kind: SignalKind.positive,
                priority: 99,
                abstains: true,
              ),
              _StubSignal(id: 'c-1', kind: SignalKind.caution, priority: 10),
              _StubSignal(id: 'p-1', kind: SignalKind.positive, priority: 10),
            ];
            await pumpStats(tester, signals: signals);

            expect(_cardKeys(), ['signal_card_c-1', 'signal_card_p-1']);
            expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
            final texts = _textsUnder(find.byKey(const Key('signals_layer')));
            expect(texts, isNot(contains('unavailable')));
            expect(texts, isNot(contains('observation a-1')));
          },
        );

        testWidgets(
          'an abstaining stub alone does not suppress the quiet line',
          (tester) async {
            final signals = <Signal>[
              _StubSignal(
                id: 'a-1',
                kind: SignalKind.positive,
                priority: 99,
                abstains: true,
              ),
            ];
            await pumpStats(tester, signals: signals);

            expect(_cardKeys(), isEmpty);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          },
        );
      });

      // ─── S-1709 ────────────────────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write is covered on Hive by the service-level round
      // trip (S-1712 in `test/signals_service_test.dart`: `persistDismissals` /
      // `dismiss` on both repositories), and the screen-level behaviour
      // asserted here — the card gone in the frame after the tap, siblings
      // kept, no re-evaluation — is store-independent.
      if (harness.name == 'Mock') {
        group('S-1709 dismissing removes the card at once', () {
          setUp(() async {
            await _seedGateMet(repo);
            // The caution is already dismissed (yesterday), so only the
            // positive renders and the dismiss control has one target.
            await _seedDismissals(repo, {'c-1': _dismissedAtMs(1)});
          });

          testWidgets('one tap removes that card, keeps the other, writes the '
              'store and re-evaluates nothing', (tester) async {
            final caution = _StubSignal(
              id: 'c-1',
              kind: SignalKind.caution,
              priority: 10,
            );
            final positive = _StubSignal(
              id: 'p-1',
              kind: SignalKind.positive,
              priority: 10,
            );
            await pumpStats(tester, signals: [caution, positive]);

            expect(_cardKeys(), ['signal_card_p-1']);

            // The dismiss control: keyed, labelled, and a 48 dp target.
            final dismiss = find.byKey(const Key('signal_dismiss_p-1'));
            expect(dismiss, findsOneWidget);
            expect(
              tester.widget<IconButton>(dismiss).tooltip,
              'Dismiss signal',
            );
            expect(
              _semanticLabelsUnder(find.byKey(const Key('signal_card_p-1'))),
              contains('Dismiss signal'),
            );
            expect(tester.getSize(dismiss).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(dismiss).height, greaterThanOrEqualTo(48));

            final evaluationsBefore = positive.evaluations;

            await tester.tap(dismiss);

            // The view moves in the tap's own frame: the card is gone and the
            // quiet line is up on the very next pump, before the store write
            // has settled (D-1010).
            await tester.pump();

            expect(find.byKey(const Key('signal_card_p-1')), findsNothing);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key('signals_layer')), findsOneWidget);

            // A dismissal re-resolves the held candidates; it never
            // re-evaluates.
            expect(positive.evaluations, evaluationsBefore);
            expect(caution.evaluations, 1);

            // The write is fired and forgotten, so it needs a real event-loop
            // turn and a pump before the store can be read back.
            await settleStore(tester);
            final store = await _readDismissals(repo);
            expect(store.containsKey('p-1'), isTrue);
            expect(store['c-1'], _dismissedAtMs(1));
          });
        });

        // S-1709's concurrency half: two dismissals in one frame must both be
        // remembered. The writes are serialised on a single in-flight tail, so
        // the second cannot overtake the first and neither is lost. Mock-only
        // for the same reason as the group above.
        group('S-1709 two rapid dismissals', () {
          setUp(() => _seedGateMet(repo));

          testWidgets('two taps before any settle persist both ids', (
            tester,
          ) async {
            final caution = _StubSignal(
              id: 'c-1',
              kind: SignalKind.caution,
              priority: 20,
            );
            final positive = _StubSignal(
              id: 'p-1',
              kind: SignalKind.positive,
              priority: 10,
            );
            await pumpStats(tester, signals: [caution, positive]);

            expect(_cardKeys(), ['signal_card_c-1', 'signal_card_p-1']);

            final dismissCaution = find.byKey(
              const Key('signal_dismiss_c-1'),
            );
            final dismissPositive = find.byKey(
              const Key('signal_dismiss_p-1'),
            );
            expect(dismissCaution, findsOneWidget);
            expect(dismissPositive, findsOneWidget);

            // Two taps in the same frame: no settle between them, so both
            // writes are queued before either store read.
            await tester.tap(dismissCaution);
            await tester.tap(dismissPositive);
            await tester.pump();

            expect(_cardKeys(), isEmpty);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);

            await settleStore(tester);
            final store = await _readDismissals(repo);
            expect(store.containsKey('c-1'), isTrue);
            expect(store.containsKey('p-1'), isTrue);
          });
        });
      }

      // ─── S-1710 ────────────────────────────────────────────────────────────

      group('S-1710 the 14-day window', () {
        group('day 13', () {
          setUp(() async {
            await _seedGateMet(repo);
            await _seedDismissals(repo, {'p-1': _dismissedAtMs(13)});
          });

          testWidgets('day 13 is hidden and shows the quiet line', (
            tester,
          ) async {
            final positive = _StubSignal(
              id: 'p-1',
              kind: SignalKind.positive,
              priority: 10,
            );
            await pumpStats(tester, signals: [positive]);

            expect(_cardKeys(), isEmpty);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
          });
        });

        group('day 14', () {
          setUp(() async {
            await _seedGateMet(repo);
            await _seedDismissals(repo, {'p-1': _dismissedAtMs(14)});
          });

          testWidgets('day 14 is eligible again', (tester) async {
            final positive = _StubSignal(
              id: 'p-1',
              kind: SignalKind.positive,
              priority: 10,
            );
            await pumpStats(tester, signals: [positive]);

            expect(_cardKeys(), ['signal_card_p-1']);
            expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          });
        });
      });

      // ─── S-1711 ────────────────────────────────────────────────────────────

      group('S-1711 the age is calendar days, not elapsed hours', () {
        setUp(() async {
          await _seedGateMet(repo);
          // Calendar age 14 → eligible. An elapsed-hours count would read
          // 13 days and hide it (D-1012). The literal 2026-03-08
          // spring-forward pair is pinned by `test/signals_framework_test.dart`.
          await _seedDismissals(repo, {
            'p-1': _dismissedAtMs(14, hour: 23, minute: 59),
          });
        });

        testWidgets('a dismissal 13 days and 23 h 59 m old is still on its '
            '14th calendar day and is eligible', (tester) async {
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
          );
          await pumpStats(tester, signals: [positive]);

          expect(_cardKeys(), ['signal_card_p-1']);
        });
      });

      // ─── S-1712 ────────────────────────────────────────────────────────────

      group('S-1712 a dismissal survives a restart', () {
        setUp(() async {
          await _seedGateMet(repo);
          await _seedDismissals(repo, {'old-1': _dismissedAtMs(1)});
        });

        testWidgets('the card is absent on the second open and the store reads '
            'back identically in both repositories', (tester) async {
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
          );
          await pumpStats(tester, signals: [positive]);
          expect(_cardKeys(), ['signal_card_p-1']);

          if (harness.name == 'Mock') {
            // Tap-driven, and Mock-only for the same reason as S-1709: a Hive
            // write started by a tap inside a widget test's fake-async zone
            // cannot drain, so the restart below would never close the box. The
            // Hive variant records the dismissal through the repository
            // instead, which is what the tap does in production.
            await tester.tap(find.byKey(const Key('signal_dismiss_p-1')));
            await settleStore(tester);
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('signal_card_p-1')), findsNothing);
          }

          // A restart is real file I/O, so it runs outside the fake clock.
          await tester.runAsync(() async {
            if (harness.name != 'Mock') {
              await _seedDismissals(repo, {
                'old-1': _dismissedAtMs(1),
                'p-1': _dismissedAtMs(0),
              });
            }
            repo = await harness.restart();
            workoutState = WorkoutState(repo);
            settingsState = SettingsState(repo, fakePreferencesService());
            await settingsState.initialize();
          });

          await reopen(
            tester,
            signals: [
              _StubSignal(id: 'p-1', kind: SignalKind.positive, priority: 10),
            ],
          );

          expect(_cardKeys(), isEmpty);
          expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);

          final raw = await repo.getPreferenceString(kSignalDismissalsKey);
          final decoded = jsonDecode(raw!) as Map<String, dynamic>;
          expect(decoded['p-1'], isA<int>());
          expect(decoded['old-1'], _dismissedAtMs(1));

          _preservedDismissalMs[harness.name] = decoded['old-1'] as int;
          for (final entry in _preservedDismissalMs.entries) {
            if (entry.key == harness.name) continue;
            expect(
              decoded['old-1'],
              entry.value,
              reason: 'Mock and Hive must read the store back identically',
            );
          }
        });
      });

      // ─── S-1713 ────────────────────────────────────────────────────────────

      group('S-1713 a cleared condition disappears', () {
        setUp(() => _seedGateMet(repo));

        testWidgets(
          'the card shows while the flag is set and is gone, with the '
          'quiet line, once it clears',
          (tester) async {
            final positive = _StubSignal(
              id: 'p-1',
              kind: SignalKind.positive,
              priority: 10,
            );
            await pumpStats(tester, signals: [positive]);
            expect(_cardKeys(), ['signal_card_p-1']);

            positive.flag = false;
            await reopen(tester, signals: [positive]);

            expect(_cardKeys(), isEmpty);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
          },
        );
      });

      // ─── S-1715 ────────────────────────────────────────────────────────────

      group('S-1715 overflow safety', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('long copy at the narrowest viewport and the largest text '
            'scale neither overflows nor blocks the body', (tester) async {
          final caution = _StubSignal(
            id: 'c-long',
            kind: SignalKind.caution,
            priority: 10,
            observation:
                'Your resistance share has drifted ${'higher' * 8} over the '
                'last 4 weeks',
            suggestion:
                'Worth checking whether ${'volume' * 10} matches the block you '
                'planned',
          );
          final positive = _StubSignal(
            id: 'p-long',
            kind: SignalKind.positive,
            priority: 10,
            observation: 'Up 8% over the last 6 sessions',
            suggestion: 'Keep the current weekly rhythm for 2 weeks',
          );
          await pumpStats(
            tester,
            size: _kNarrowViewport,
            textScale: _kNarrowTextScale,
            signals: [caution, positive],
          );

          expect(tester.takeException(), isNull);
          expect(_cardKeys(), ['signal_card_c-long', 'signal_card_p-long']);

          // Both dismiss controls are reachable and hit-testable.
          for (final id in ['c-long', 'p-long']) {
            final dismiss = find.byKey(Key('signal_dismiss_$id'));
            await tester.ensureVisible(dismiss);
            await tester.pumpAndSettle();
            expect(dismiss.hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);

          // The body still scrolls to the Fuel row below everything else.
          await tester.scrollUntilVisible(
            find.byKey(const Key('fuel_row')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.byKey(const Key('fuel_row')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1716 ────────────────────────────────────────────────────────────

      group('S-1716 no chart, no legacy name, no coaching', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('the layer draws no chart primitive, carries no forbidden '
            'copy and states its own span', (tester) async {
          final caution = _StubSignal(
            id: 'c-1',
            kind: SignalKind.caution,
            priority: 10,
            observation: 'Up 12% over the last 4 weeks',
            suggestion: 'Hold the current block for 2 more weeks',
          );
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
            observation: 'Up 8% over the last 6 sessions',
            suggestion: 'Keep the current weekly rhythm for 2 weeks',
          );
          await pumpStats(tester, signals: [caution, positive]);

          final layer = find.byKey(const Key('signals_layer'));
          expect(layer, findsOneWidget);
          expect(
            find.descendant(of: layer, matching: find.byType(LineChart)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: layer,
              matching: find.byType(ScrollableTrendChart),
            ),
            findsNothing,
          );

          final texts = _textsUnder(layer);
          for (final forbidden in _kForbiddenCopy) {
            for (final text in texts) {
              expect(
                text.toLowerCase().contains(forbidden.toLowerCase()),
                isFalse,
                reason: '"$text" must not carry "$forbidden" (D-1019)',
              );
            }
          }

          // Every observation states the span it is about.
          final observations = texts.where((text) => text.startsWith('Up '));
          expect(observations, hasLength(2));
          for (final observation in observations) {
            expect(
              RegExp(
                r'over the last \d+ (weeks|sessions)',
              ).hasMatch(observation),
              isTrue,
              reason: '"$observation" must name its own span (D-1019)',
            );
          }
        });
      });

      // ─── the empty-state sibling of S-1702 ─────────────────────────────────

      group('the empty-state branch', () {
        testWidgets('a profile with no sessions shows the empty state and no '
            'layer, even with stubs registered', (tester) async {
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
          );
          await pumpStats(tester, signals: [positive]);

          expect(find.text('No sessions yet'), findsOneWidget);
          expect(find.byKey(const Key('signals_layer')), findsNothing);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text('SIGNALS'), findsNothing);
          expect(_cardKeys(), isEmpty);
          expect(find.text('ALL TIME'), findsNothing);
          expect(positive.evaluations, 0);
        });
      });

      // ─── Structural guards (Phase 3) ──────────────────────────────────────
      //
      // Each guard names the defect it makes impossible and the edit that
      // breaks it. They are permanent: a change that reintroduces the defect
      // fails here, not in review.

      group('Structural guard — a gate-unmet screen renders no SIGNALS and '
          'evaluates nothing', () {
        setUp(() => _seedGateUnmet(repo));

        testWidgets('a signal that would return a card is never asked', (
          tester,
        ) async {
          // Breaks if `_loadData()` stops gating the signals: the stub would
          // be evaluated and its card would render (D-1006).
          final positive = _StubSignal(
            id: 'p-1',
            kind: SignalKind.positive,
            priority: 10,
          );
          await pumpStats(tester, signals: [positive]);

          expect(find.text('SIGNALS'), findsNothing);
          expect(find.byKey(const Key('signals_layer')), findsNothing);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(_cardKeys(), isEmpty);
          expect(positive.evaluations, 0);
        });
      });

      group('Structural guard — the layer draws no chart', () {
        setUp(() => _seedGateMet(repo));

        testWidgets('no chart primitive in the layer subtree', (tester) async {
          // Breaks if a chart is added to the layer (D-1019).
          await pumpStats(
            tester,
            signals: [
              _StubSignal(id: 'p-1', kind: SignalKind.positive, priority: 10),
            ],
          );
          final layer = find.byKey(const Key('signals_layer'));
          expect(layer, findsOneWidget);
          expect(
            find.descendant(of: layer, matching: find.byType(LineChart)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: layer,
              matching: find.byType(ScrollableTrendChart),
            ),
            findsNothing,
          );
        });
      });
    });
  }
}
