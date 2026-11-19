# 102 — Signals that never needed ratings speak from the first session

Status: SEEDED by the lead 2026-11-03 (no architect run: the seed carries exact production code; exact test text sits in the
builder briefs). Base commit: `.work/2026-11-03-102-signals-gate/base.txt`.
Track: phone only (`lib/`, `test/`, `docs/`). Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart`,
`test/stats_dst_day_arithmetic_test.dart` (another session's DST work).
Series: Stats Signals, group 3 of the owner's review items 9-12. Unit 1 of 5 (102 gate, 103 quiet-line waiting list, 104 weight
line, 105 Consistency signal, 106 hold and cardio trend). Owner 2026-11-03: "Yes to all" (commits pre-approved, take the defaults,
report at the end); weeks end on Sunday or Saturday by the Start of Week setting (matters from unit 105).
Independent review (a read-only session with no lead context) and the lead agree on the facts below; both are quoted in the
Assumption Log.

## Goal and acceptance

What a user sees after this PR:

1. **Three signals no longer wait for four rated weeks.** Progression Rate (positive), Protein Consistency and Cardio Efficiency
   Drift (cautions) read no ratings and no load measure, so they speak as soon as their own data rules are met. Before, the whole
   Signals block sat behind one gate (`signalsGateMet`: 4 of the last 12 weeks with a rated session).
2. **The four load-reading signals still wait.** Fuel vs Load, Sustained High Load, Modality Mix Shift and Cross-Modality
   Interference read the load measure or the ratings; their rules do not change and they stay silent while the gate is unmet.
3. **With the gate unmet and an unlocked signal speaking**, the Signals block shows that card and under it one line,
   `More signals unlock after 4 weeks of rating your workouts — N of 4 so far.` (N clamped 0..4). With the gate unmet and nothing
   speaking, the block is exactly what it is today: the locked line `Unlocks after 4 weeks of rating your workouts — N of 4 so far.`
   and no quiet line. With the gate met nothing changes.
4. **Dismissing the only visible card at an unmet gate** returns the block to the locked line (no quiet line, no hint).
5. **No completed session**: unchanged, the empty state alone and no signal evaluated.

Not in this PR: Modality Mix Shift on time (its rule and copy are load-only; a time version needs a new baseline: separate, not
planned); the waiting-for list in the quiet line (unit 103: it replaces both the locked line and the new hint line); new signals.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17501 | `Signal` gains an abstract `bool get needsRatedWeeks`: true when the signal reads the load measure or ratings (silent until the gate is met), false when it reads neither. Abstract on purpose: a new signal must decide. Values: `fuel-vs-load` true, `sustained-high-load` true, `modality-mix-shift` true, `cross-modality-interference` true, `progression-rate` false, `protein-consistency` false, `cardio-efficiency-drift` false | `signals/signal.dart`, the seven signal files |
| D-17502 | `SignalsService.evaluateCandidates` has no early return on an unmet gate. It computes `signalsGateMet(mix)` once and skips a signal whose `needsRatedWeeks` is true while the gate is unmet; everything else (dismissal read, dismissal filter, registry order) is unchanged | `signals_service.dart:36-63` |
| D-17503 | `resolveSignals` loses its early return on `!gateMet`. The candidates are already filtered by the service, so it ranks whatever it is given; `gateMet` now only decides whether the quiet line may show: `showQuietLine: cards.isEmpty && gateMet` | `signals.dart:164-196` |
| D-17504 | `SignalsLayerSection` gets an optional `int? lockedRatedWeeks` (default null). When non-null and the data has cards, a line `signalsMoreLine(lockedRatedWeeks)` (key `signals_locked_hint`) renders under the cards. The copy is a new function `signalsMoreLine(int ratedWeeks)` in `signals.dart`, clamped like `signalsLockedLine` and built from `kTrainingLoadMinRatedWeeks`. `signalsLockedLine` and `SignalsLockedSection` are untouched | `signals.dart`, `signals_layer.dart` |
| D-17505 | `StatsScreen._load` evaluates and resolves signals whenever `totals.completedSessions > 0` (gate met or not) and passes `gateMet: signalsGateMet(mixLayer)` to `resolveSignals`. Render rule: the layer when `_signalsData != null && (cards.isNotEmpty \|\| gate met)` with `lockedRatedWeeks: gate met ? null : (_mixLayer?.ratedWeeks ?? 0)`; else, when the gate is unmet and the Mix layer exists, the locked section exactly as today | `stats_screen.dart:132-159,295-309` |
| D-17506 | The two test stubs named `_StubSignal` (in `signals_service_test.dart` and `signals_layer_screen_test.dart`) get a constructor argument `needsRatedWeeks` defaulting to true, so every existing test keeps its meaning (a default stub is a load-reading signal: unevaluated while the gate is unmet) | the two test files, stub classes only |
| D-17507 | Cardio Efficiency Drift's optional "lifting load rose" sentence already drops to the time measure when load is unavailable (`liftMeasure: mix?.measure ?? MixMeasure.time`), so it needs no gate; nothing in its rule changes | `cardio_efficiency_drift_signal.dart:54-68` |
| D-17508 | Copy decision (product, default taken): the hint under a card reads `More signals unlock after 4 weeks of rating your workouts — N of 4 so far.` | `signals.dart` |
| D-17509 | Proof: the lead's mutation pass (M1-M7) is the proof; `prove-red` at the base fails by compile (stub argument), which proves nothing about behaviour | Assumption Log |

## Exact production code (P1)

`lib/core/services/signals/signal.dart`, inside `abstract class Signal` after `int get priority;`:

```dart
  /// True when this signal reads the load measure or the effort ratings, so it
  /// stays silent until `signalsGateMet` is true; false when it reads neither
  /// and may speak from the first session (D-17501).
  bool get needsRatedWeeks;
```

In each of the seven signal classes, directly after the `priority` getter, add (value per D-17501):

```dart
  @override
  bool get needsRatedWeeks => true; // false for progression-rate, protein-consistency, cardio-efficiency-drift
```

(write `true` or `false` literally, no comment about the others).

`lib/core/services/signals_service.dart`, replace the doc comment and first lines of `evaluateCandidates`:

```dart
  /// The candidates of one load, in registry order (D-1014).
  ///
  /// While the gate is unmet only the signals that need no rated weeks are
  /// evaluated (D-17502); once it is met every registered signal is evaluated
  /// once. The cards of currently dismissed signals are dropped (D-1011).
  ///
  /// [dismissedAtMs] lets a caller that already read the store pass that map
  /// in, so one load reads the store once; when it is omitted the store is
  /// read here, which is what the service-level tests and `dismiss` rely on.
  Future<List<SignalCard>> evaluateCandidates({
    required DateTime now,
    required StatsWindow window,
    required MixLayerData? mix,
    Map<String, int>? dismissedAtMs,
  }) async {
    final gateMet = signalsGateMet(mix);
    final dismissed = dismissedAtMs ?? await loadDismissals();
    final context = SignalContext(
      now: now,
      window: window,
      mix: mix,
      progressService: _progressService,
      repository: _repository,
    );
    final cards = <SignalCard>[];
    for (final signal in _signals) {
      if (signal.needsRatedWeeks && !gateMet) continue;
      final card = await signal.evaluate(context);
```

(the rest of the loop is unchanged).

`lib/core/models/signals.dart`: the doc of `signalsGateMet` becomes `/// Whether the signals that read the load measure or the ratings may speak (D-1006, D-17501).` (body unchanged). Add after `signalsLockedLine`:

```dart
/// The line under the cards while the gate is unmet but a signal that needs no
/// ratings is speaking (D-17504, D-17508).
///
/// The count is clamped like [signalsLockedLine], and the number in the copy is
/// always [kTrainingLoadMinRatedWeeks].
String signalsMoreLine(int ratedWeeks) =>
    'More signals unlock after $kTrainingLoadMinRatedWeeks weeks of rating '
    'your workouts — ${ratedWeeks.clamp(0, kTrainingLoadMinRatedWeeks)} of '
    '$kTrainingLoadMinRatedWeeks so far.';
```

In `resolveSignals`: delete the `if (!gateMet) { return const SignalsData(cards: [], showQuietLine: false); }` block; the last line becomes
`return SignalsData(cards: cards, showQuietLine: cards.isEmpty && gateMet);`; the doc comment gains: "[gateMet] decides only whether the quiet line may show; the candidates are already filtered by the service, so an unmet gate still ranks the cards of the signals that need no ratings (D-17503)." Also update the `SignalsData` doc ("an empty [cards] with [showQuietLine] false means the gate is unmet and nothing speaks: the layer renders the locked line").

`lib/features/stats/widgets/signals_layer.dart`: `SignalsLayerSection` gets

```dart
  /// When non-null the gate is unmet and a card that needs no ratings is
  /// showing: the line under the cards says how far the other signals are
  /// (D-17504). Null once the gate is met.
  final int? lockedRatedWeeks;
```

as an optional constructor argument (`this.lockedRatedWeeks,`), and in `build`, after the `for` that draws the cards (inside the `else` branch, so only when `cards` is non-empty):

```dart
          if (lockedRatedWeeks != null) ...[
            const SizedBox(height: _kCardGap),
            Text(
              signalsMoreLine(lockedRatedWeeks!),
              key: const Key('signals_locked_hint'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: themeColors.textSecondary,
              ),
            ),
          ],
```

`lib/features/stats/stats_screen.dart` `_load` (replace lines 140-159):

```dart
      final evaluateSignals = totals.completedSessions > 0;
      final gateMet = signalsGateMet(mixLayer);
      final signalsDismissedAtMs = evaluateSignals
          ? await signalsService.loadDismissals()
          : const <String, int>{};
      final signalsCandidates = evaluateSignals
          ? await signalsService.evaluateCandidates(
              now: now,
              window: window,
              mix: mixLayer,
              dismissedAtMs: signalsDismissedAtMs,
            )
          : const <SignalCard>[];
      final signalsData = evaluateSignals
          ? resolveSignals(
              candidates: signalsCandidates,
              dismissedAtMs: signalsDismissedAtMs,
              now: now,
              gateMet: gateMet,
            )
          : null;
```

(update the comment above it: "While the gate is unmet only the signals that need no ratings are evaluated (D-17502)"). Build (lines 295-309):

```dart
                            if (_signalsData != null &&
                                (_signalsData!.cards.isNotEmpty ||
                                    signalsGateMet(_mixLayer))) ...[
                              SignalsLayerSection(
                                data: _signalsData!,
                                themeColors: themeColors,
                                onDismiss: _dismissSignal,
                                lockedRatedWeeks: signalsGateMet(_mixLayer)
                                    ? null
                                    : (_mixLayer?.ratedWeeks ?? 0),
                              ),
                              const SizedBox(height: 24),
                            ] else if (_mixLayer != null &&
                                !signalsGateMet(_mixLayer)) ...[
                              SignalsLockedSection(
                                ratedWeeks: _mixLayer!.ratedWeeks,
                                themeColors: themeColors,
                              ),
                              const SizedBox(height: 24),
                            ],
```

`_dismissSignal` is unchanged (it already passes `gateMet: signalsGateMet(_mixLayer)`).

The two `_StubSignal` classes (D-17506): add `this.needsRatedWeeks = true,` to the constructor and
`@override final bool needsRatedWeeks;` (in `signals_layer_screen_test.dart` the constructor is the non-const one at line 162).

## Scenarios

`Fails without the change` is proven by the lead's mutations (D-17509). Fixtures reuse the helpers of the file each test lands in.

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17501 | Service test: stubs `u` (positive, `needsRatedWeeks: false`) and `l` (caution, default true); `mix` unmet, and again `mix: null` | `evaluateCandidates` returns exactly the card of `u`; `u.evaluations` is 1 per call and `l.evaluations` is 0 | the old early return gave `[]` and evaluated nothing (mutation M1) |
| S-17502 | Service test: the same stubs, `mix` ready | both evaluated once, both cards returned in registry order | twin: existing test `a met gate evaluates each signal once and returns its cards` stays green (guards the gate-met path) |
| S-17503 | `buildSignalRegistry()`: map id to `needsRatedWeeks` | `progression-rate`, `protein-consistency`, `cardio-efficiency-drift` false; `fuel-vs-load`, `sustained-high-load`, `modality-mix-shift`, `cross-modality-interference` true; seven entries | a flipped flag unlocks a load-reading signal or locks an unrated one (mutations M2, M3) |
| S-17504 | Framework test (pure `resolveSignals`): (a) one positive candidate, `gateMet: false`; (b) no candidates, `gateMet: false`; (c) no candidates, `gateMet: true` | (a) the card is returned and `showQuietLine` false; (b) no cards and `showQuietLine` false; (c) no cards and `showQuietLine` true | (a) the early return dropped the card; mutation M4 (drop `&& gateMet`) fails (b) |
| S-17505 | Screen test, fixture U (gate unmet: 3 unrated sessions, 0 rated weeks), stubs `p-open` (positive, unlocked) and `c-locked` (caution, locked) | the card `signal_card_p-open` shows; `signal_card_c-locked` does not; `signals_locked_hint` reads `signalsMoreLine(0)`; `signals_locked` and `signals_quiet_line` are absent; `p-open.evaluations` 1, `c-locked.evaluations` 0 | the gate showed the locked section and evaluated nothing (M1, M5, M6) |
| S-17506 | The existing screen test `S-1702 gate unmet locks the signals` (default stubs are load-reading) | stays green untouched: locked section, no card, no quiet line, 0 evaluations | guards the no-card branch (M5) |
| S-17507 | Screen test, fixture U and the S-17505 stubs, tap `signal_dismiss_p-open` | the card is gone; `signals_locked` and `signals_locked_line` show; `signals_locked_hint` and `signals_quiet_line` are absent | the card never existed at an unmet gate, so there was nothing to dismiss (M1, M5); the quiet-line rule (M4) is killed at framework level by S-17504 (b) |
| S-17508 | Screen test, fixture U with the Mix layer present and only locked stubs, plus the existing S-1703 gate-met quiet-line tests | gate met nothing speaks: quiet line; gate unmet nothing speaks: locked section | existing; guards the render rule (M5) |
| S-17509 | Progression Rate end to end: copy the fixture of an existing card test in `progression_rate_signal_screen_test.dart` and remove every rating so `ratedWeeks` is below the gate | the real `ProgressionRateSignal` card shows with the `signals_locked_hint` line under it | the gate hid the card (M1, M3) |
| S-17510 | Empty history (no completed session) with a stub in the registry | the existing empty-state sibling test stays green: empty state alone, 0 evaluations | guards `evaluateSignals` (M7) |

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/core/services/signals/*.dart`, `lib/core/services/signals_service.dart`, `lib/core/models/signals.dart`, `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/stats_screen.dart`, the two stub classes | the exact edits above | first |
| P2a | crew-builder-app | `test/signals_service_test.dart`, `test/signals_framework_test.dart` | S-17501, S-17502 (existing), S-17503, S-17504, and the two framework tests that pinned the early return | after P1; parallel with P2b |
| P2b | crew-builder-app | `test/signals_layer_screen_test.dart` | S-17505, S-17507 | after P1; parallel |
| P2c | crew-builder-app | `test/progression_rate_signal_screen_test.dart` | S-17509 | after P2b |
| P3 | crew-docs-keeper | `docs/signals.md`, `docs/stats_screen.md`, `docs/widget_catalog.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts (Mock only); `flutter analyze` issue count not above the base count
(0 errors); full `flutter test` green apart from the known reds; invariant grep clean; `ui_standards_contract_test.dart` and
`docs_indexing_contract_test.dart` green; `plan-lint.py after` clean. Mutations: M1 delete the `if (signal.needsRatedWeeks &&
!gateMet) continue;` line; M2 `fuel-vs-load` flag to false; M3 `progression-rate` flag to true; M4 `showQuietLine: cards.isEmpty`;
M5 the screen render condition without `|| signalsGateMet(_mixLayer)` (the layer renders for every non-null data); M6 the screen
passes `lockedRatedWeeks: null`; M7 `evaluateSignals` forced true.

## Docs delta

Markers are exact one-line phrases. `-` = none. Docs not listed are checked by the keeper's search for `evaluates nothing`,
`Unlocks after`, `gate is unmet`, `gate-unmet`, `signalsGateMet` outside `docs/plans`, `docs/history`, `docs/releases`.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/signals.md | MODIFIED | evaluates no signal at all and returns no candidates, so a user without enough | evaluates only the signals that need no rated weeks | S-17501 |
| docs/signals.md | ADDED | - | A signal declares whether it needs rated weeks | S-17503 |
| docs/signals.md | MODIFIED | it without a card. A gate-unmet load reports neither cards nor the quiet line — | A gate-unmet load reports the cards of the unlocked signals but never the quiet line | S-17504 |
| docs/stats_screen.md | MODIFIED | and above the Instruments list, and there is exactly one of it. It renders only | The signals that need no ratings render from the first session | S-17505 |
| docs/stats_screen.md | MODIFIED | that count and no signal is evaluated at all. Verified by | no load-reading signal is evaluated | S-17501 |
| docs/stats_screen.md | ADDED | - | More signals unlock after 4 weeks of rating your workouts | S-17505 |
| docs/stats_screen.md | MODIFIED | evaluates nothing and shows the locked line instead. The screen holds the | evaluates only the signals that need no ratings | S-17501 |
| docs/stats_screen.md | MODIFIED | [Signals layer](#signals-layer) when its gate is met — or, when the gate is | [Signals layer](#signals-layer) whenever a signal speaks or its gate is met | S-17505 |
| docs/widget_catalog.md | MODIFIED | A gate-unmet screen instead renders the sibling | A gate-unmet screen with no unlocked card instead renders the sibling | S-17506 |

## Progress

- [x] P1 production
- [x] P2a service and framework tests (+42 with the framework file)
- [x] P2b screen tests (stopped at 28 min on a Hive-only hang in the dismissal test; the lead made S-17507 Mock-only like S-1709; file +56)
- [x] P2c Progression Rate end to end (+7, both harnesses)
- [x] Lead mutation pass M1-M7 (M7 first survived: the empty-state test's stub was load-reading, so the unmet gate skipped it anyway; its stub is now `needsRatedWeeks: false`; all 7 killed)
- [x] P3 docs
- [x] `plan-lint after` (clean, 9 of 9 rows)
- [x] P4 review (APPROVE, 0 blocker, 0 major, 1 minor: the S-17507 rationale above, fixed)
- [x] Full suite `+6182 ~2 -1` (the one red, `routine_save_removes_deleted_rows_test.dart` S-R3, is red at the base), analyze 181 (baseline 181), invariant grep clean, UI standards and docs contract tests green (+54)
- [x] Commit (own files only)

## Assumption Log

- Independent read-only review (2026-11-03): Progression Rate reads no ratings (`progressionSamples` walks `set` efforts); Protein
  Consistency reads food logs, lifting-session counts and bodyweight; Cardio Efficiency Drift needs heart rate and distance, its
  lifting sentence degrades to time. Lead spot-checks: `modality_mix_shift.dart:79` returns null unless the measure is load (so the
  proposal's "Mix Shift on time" is a new rule, out of scope); the only gate is `signalsGateMet` at `signals_service.dart:42` and
  `stats_screen.dart:140`.
- Default taken: the hint copy (D-17508). The owner may prefer other wording; unit 103 replaces it with the waiting list anyway.
- Fuel vs Load and Interference are kept behind the gate on the reviewer's reading of their rules (load measure and rated sports
  sessions); not re-derived by the lead.
- Lead-written parts (D-17509): the S-17507 test moved into its own Mock-only group after the P2b builder stalled on the Hive variant (the existing S-1709 test is Mock-only for the same reason), and the empty-state test's stub switched to `needsRatedWeeks: false` after M7 survived.
- Not run on a device or simulator: a test cannot show how the hint line sits under a card at a real phone width; the simulator look is off by default.
