# 107 — One Stats load reads the session list once; the Settings words say what Start of Week does

Status: SEEDED by the lead 2026-11-03 (no architect run: exact production code below; test text sits in the builder briefs).
Base commit: `.work/2026-11-03-107-stats-load-reads/base.txt` (7e645703). Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files: `lib/core/services/stats_progress_service.dart` (another session's DST edits, hunks near `topExerciseRecencyCutoff` and the nutrition-target cursor loop) and `test/stats_dst_day_arithmetic_test.dart`.
This plan ADDS hunks to the first file (a field, two methods, one rename); it never touches, reformats or reverts the DST hunks, and the commit of this unit needs `git add -p` for that file. The test file is never touched.
Series: Stats screen analysis 2026-11-03, PR 1 of 4 (items W1, B1, D1). Owner: "Yes, plan PR1 and have your crew implement the fix". Out of scope: B2 (Start of Week while Stats is open), the test gaps (PR 3), docs D2-D4, W2/W3/W4.

## Goal and acceptance

What a user sees after this PR: only the Settings row's second line changes.

1. **Settings > Start of Week** reads `Week start in the calendar and on Stats` instead of `First day shown in the calendar`, because the setting also decides the Mix strip's week columns and the Consistency / Training Gap week.
2. Everything else looks and behaves exactly as before. Underneath, one Stats load now reads the session list once (it read it three times: the screen's shared snapshot, then once each for Consistency and Training Gap) and builds the Instruments sections once (Hold Progress rebuilt them).
3. The doc and code comments that say the signals "walk no history of their own" / "never walk history a second time" are true again, and say how.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-18101 | The Settings subtitle becomes `Week start in the calendar and on Stats`. A wording change the owner can veto; the Mix strip and the signals both live on Stats | `settings_screen.dart:701`, `interaction_flow_test.dart:1537` |
| D-18102 | `StatsProgressService.completedSessionStarts({required DateTime now})` serves the signals' session starts from the cached history snapshot (`_loadHistory()`): sessions with `endedAtMs != null` and `0 <= startedAtMs <= now`, oldest first. This is the same predicate and order as the old `getSessionsByDateRange(0, now)` read (inclusive both ends, sorted by start ascending, then filtered to ended) | `stats_progress_service.dart` |
| D-18103 | `computeInstrumentSections` is memoised per service instance, keyed by the window's two instants (`fromMs|toMs`), so Hold Progress receives the list the screen already built. Same freshness contract as the history snapshot ("callers that need fresh data construct a new service") | `stats_progress_service.dart` |
| D-18104 | `completedSessionStarts(SignalContext)` in `session_history.dart` stays as the one place the two signals call; its body is one line over D-18102. `SignalContext.repository` stays in the contract (no signal reads it after this PR, nothing is removed) | `session_history.dart` |
| D-18105 | The comment in `signal.dart` and the two docs sentences are reworded to the true claim: a signal reads history only through the service the screen already built (cached snapshot, memoised sections), never through the repository | `signal.dart`, `signals_registered.md` |
| D-18106 | Proof: the lead's mutation pass M1-M6; the prover is not run (the new service method does not exist at the base, so `prove-red` at the base proves nothing) | Assumption Log |

## Exact production code

### P1 — `lib/`

`lib/features/settings/settings_screen.dart:701`: `subtitle: 'First day shown in the calendar',` becomes `subtitle: 'Week start in the calendar and on Stats',`.

`test/interaction_flow_test.dart:1537`: `find.text('First day shown in the calendar')` becomes `find.text('Week start in the calendar and on Stats')`. Nothing else in that test changes.

`lib/core/services/stats_progress_service.dart` (additive hunks only):

(a) directly after the `_exerciseCache` field and before `_loadHistory()`, add:

```dart
  /// The Instruments sections already built by this instance, per window
  /// (plan 107, D-18103): the Stats screen builds them for the list, and the
  /// Hold Progress signal asks for the same window, so the second ask is free.
  /// Same freshness rule as [_historyIndex]: a caller that needs fresh data
  /// after a write constructs a new service.
  final Map<String, Future<List<InstrumentSectionData>>>
  _instrumentSectionsByWindow = <String, Future<List<InstrumentSectionData>>>{};
```

(b) directly after `_exerciseById(...)`, add:

```dart
  /// The start of every completed session at or before [now], oldest first
  /// (plan 107, D-18102).
  ///
  /// Served from the cached history snapshot, so the Consistency and Training
  /// Gap signals cost no repository read of their own. A session still in
  /// progress has no end and is not a session yet; one dated after [now] has
  /// not happened yet.
  Future<List<DateTime>> completedSessionStarts({required DateTime now}) async {
    final nowMs = now.millisecondsSinceEpoch;
    final startsMs = <int>[
      for (final session in (await _loadHistory()).sessions)
        if (session.endedAtMs != null &&
            session.startedAtMs >= 0 &&
            session.startedAtMs <= nowMs)
          session.startedAtMs,
    ]..sort();
    return [for (final ms in startsMs) DateTime.fromMillisecondsSinceEpoch(ms)];
  }
```

(c) `computeInstrumentSections` (currently `Future<List<InstrumentSectionData>> computeInstrumentSections({required StatsWindow window}) async {` with its body starting `final fromMs = window.fromMs.millisecondsSinceEpoch;`): keep its doc comment on the public method, add one sentence at the end of that comment ("One instance builds a window's sections once: a second call for the same window returns the first call's result."), and split it:

```dart
  Future<List<InstrumentSectionData>> computeInstrumentSections({
    required StatsWindow window,
  }) {
    final key =
        '${window.fromMs.millisecondsSinceEpoch}|'
        '${window.toMs.millisecondsSinceEpoch}';
    return _instrumentSectionsByWindow[key] ??= _buildInstrumentSections(
      window,
    );
  }

  Future<List<InstrumentSectionData>> _buildInstrumentSections(
    StatsWindow window,
  ) async {
    final fromMs = window.fromMs.millisecondsSinceEpoch;
    // ... the existing body, unchanged ...
  }
```

`lib/core/services/signals/session_history.dart` (whole file):

```dart
import 'signal.dart';

/// The start of every completed session, oldest history included (D-17803).
///
/// A session still in progress has no end and is not a session yet. The read
/// rides the service's cached history snapshot (plan 107, D-18102), so it costs
/// the screen no repository read of its own.
Future<List<DateTime>> completedSessionStarts(SignalContext context) =>
    context.progressService.completedSessionStarts(now: context.now);
```

`lib/core/services/signals/signal.dart`: the last sentence of the class doc (lines 10-11, `It reads the repository only through [SignalContext], and it never walks history a second time (D-1014).`) becomes: `It reads history only through the [StatsProgressService] in its [SignalContext] — the cached snapshot and the memoised sections the screen already built — and never from the repository itself, so a load walks history once (D-1014, D-18105).`

## Scenarios

New tests in `test/stats_load_single_read_test.dart` (plain `test()`, Mock; S-18103 on Mock AND Hive via `test/helpers/repository_harness.dart`). `S-18101` lives in the existing test.

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-18101 | The existing Settings screen test (`interaction_flow_test.dart:1537`) | `Week start in the calendar and on Stats` is found once; `First day shown in the calendar` is found nowhere | the screen still says the old words |
| S-18102 | A `MockWorkoutRepository` subclass that counts `getAllSessions` and `getSessionsByDateRange` calls; five completed sessions seeded; one `StatsProgressService`; run `computeTotals()`, then `SignalsService(...).evaluateCandidates(...)` with `buildSignalRegistry()` (gate unmet, `mix: null`) | `getSessionsByDateRange` was called 0 times; `getAllSessions` exactly 1 time | each of the two signals reads the range itself (2 calls) |
| S-18103 | Mock and Hive: `now` = Wednesday 2026-03-18 12:00; seed completed sessions at 2026-03-16 09:00, 2026-03-02 09:00 (inserted newest first), a session still open at 2026-03-17 09:00, a completed session dated 2026-03-20 09:00 (future), a completed session exactly at `now` | `completedSessionStarts(now: now)` is `[03-02 09:00, 03-16 09:00, 03-18 12:00]` in that order: oldest first, no open session, no future one, the one at `now` included | the method does not exist; the open filter (M1), the upper bound (M2: `<` vs `<=`) and the order (M3) |
| S-18104 | A service over a non-empty fixture (one completed hold session in the window): `computeInstrumentSections(window: w)` called twice; then with a window whose `toMs` differs by one day | the first two results are the same list object (`identical`) and non-empty; the third is a different list that was built for its own window (its row's `summary.sessionCount` or points differ where the fixture makes them differ — the brief names a fixture and the expected figure) | every call rebuilds a new list (M4); a key that ignores `toMs` returns the stale list (M5) |

## Phases

| Phase | Agent | Write scope | Items | Order |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/features/settings/settings_screen.dart`, `lib/core/services/stats_progress_service.dart`, `lib/core/services/signals/session_history.dart`, `lib/core/services/signals/signal.dart`, `test/interaction_flow_test.dart` | 5 | first |
| P2 | crew-builder-app | `test/stats_load_single_read_test.dart` | 1 (S-18102..S-18104) | after P1 |
| P3 | crew-docs-keeper | `docs/signals_registered.md`, `docs/state_management/services_and_utils.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts (`interaction_flow_test.dart`, the new file, `consistency_signal_test.dart`, `hold_progress_signal_test.dart`, `signals_service_test.dart`, `signals_layer_screen_test.dart`, `stats_progress_service` tests); `flutter analyze` issue count not above the base count; full `flutter test` green apart from the known flaky red (`routine_save_removes_deleted_rows_test.dart` S-R3); invariant grep clean; `ui_standards_contract_test.dart` and `docs_indexing_contract_test.dart` green; `plan-lint.py after` clean; the DST file's hunks unchanged (`git diff` of that file shows the DST hunks plus this plan's three additive hunks and nothing else). Mutations (lead): M1 drop `session.endedAtMs != null &&`; M2 `<= nowMs` to `< nowMs`; M3 drop `..sort()`; M4 make `computeInstrumentSections` call `_buildInstrumentSections` directly; M5 key built from `fromMs` only; M6 `session_history.dart` back to `context.repository.getSessionsByDateRange(0, now)`.

## Docs delta

Markers are exact one-line phrases. The keeper also searches `docs/` (excluding plans, history, releases) for `walks no history`, `walk no history`, `second walk` and reports any other hit that became false (the many `walks no history of its own` sentences of the Mix-payload signals stay true: they read the payload, not the service). `docs/stats_screen.md` is at its size band: it is NOT edited (its two `no second walk of history` lines become true as written).

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/signals_registered.md | MODIFIED | session yet — so it walks no history of its own. | the service's cached history snapshot | S-18102 |
| docs/signals_registered.md | MODIFIED | window and hands the sections to the rule, so it walks no history of its own. | the same sections the Instruments list built | S-18104 |
| docs/state_management/services_and_utils.md | ADDED | - | `completedSessionStarts({required DateTime now})` | S-18103 |
| docs/state_management/services_and_utils.md | ADDED | - | a second call for the same window returns the first call's sections | S-18104 |

The ADDED services paragraph states: what the method returns (completed sessions at or before `now`, oldest first, from the cached snapshot), that the two signals call it through `session_history.dart`, and the memo rule next to the `computeInstrumentSections` paragraph (one build per window per service instance). Each sentence names its test.

## Progress

- [x] P1 production + Settings words
- [x] P2 new tests
- [x] P3 docs
- [x] P4 review
- [x] lead: verify, mutations, full suite

## Assumption Log

- 2026-11-03 lead: the plan is lead-seeded with exact code, so no architect run. The prover is skipped (D-18106); the lead's mutations stand in.
- 2026-11-03 lead: the analysis cited `signals_registered.md:663,726`; in the current file the two sentences are at 616-618 and 714 (the page was split). The markers above are copied from the doc as it is.

- 2026-11-03 lead: results. Full `flutter test`: +6318 ~2 -1, the one red is the known flaky S-R3 (`routine_save_removes_deleted_rows_test.dart`). `flutter analyze` 181 issues (base 181). Mutations M1-M6 each failed a new test, sources restored identical. Review: APPROVE, one optional minor (S-18104's third window is identity-only; a window-ignoring build is covered by existing service tests). The keeper's wrapped marker in `services_and_utils.md` was reflowed by the lead (plan-lint after: clean).
