# 108 — Stats follows Start of Week when it changes while Stats is open

Status: SEEDED by the lead 2026-11-03 (no architect run: exact production code below; test text sits in the builder briefs).
Base commit: `.work/2026-11-03-108-stats-start-of-week-reload/base.txt` (8dc98c18). Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart` (another session's DST hunks) and `test/stats_dst_day_arithmetic_test.dart`. This plan does not touch the first file at all.
Series: Stats screen analysis 2026-11-03, PR 2 of 4 (item B2). Owner: "let's continue" after PR 1; committing this unit is pre-approved when verified (`commit-ok.txt`).
Out of scope: the other analysis items (test gaps PR 3, docs D2-D4, wording W2/W3/W4).

## Goal and acceptance

What a user sees after this PR:

1. **Flip Start of Week and Stats follows.** Change `Start of Week` between Monday and Sunday in Settings while Stats is open, or while Stats sits underneath Settings: the Stats screen refreshes at once in the background. The Mix strip's eight week columns re-anchor to the new first day, and the Consistency / Training Gap week and the waiting lines use the new first day. Before this PR the calendar moved but Stats kept the old week anchors until the screen was reopened.
2. **No flash.** The refresh keeps the current content on screen and swaps it when the new numbers are ready (no spinner). The first open of Stats still shows its spinner as today.
3. **Nothing else reloads Stats.** Turning `Weight on Stats` on or off, changing the theme or any other setting does not reload Stats; setting Start of Week to the value it already has does not either.
4. **A card dismissed a moment before the flip stays dismissed** (the refresh waits for the pending dismissal write before it reads the store), and **a slow older load never overwrites a newer one**.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-18201 | `_StatsScreenState` listens to `widget.settingsState` and reloads (silently, no spinner) when `startOfWeek` differs from the value the latest load started with (`_startOfWeekInUse`). A load not yet started (value null) is left to the post-frame first load, which reads the current value. No other setting compares | `stats_screen.dart` |
| D-18202 | `_loadData({bool silent = false})` reads `startOfWeek` ONCE at its start and uses that one value for the Mix layer, `evaluateCandidates` and `waitingLines` (today the three reads happen at three different awaits and could disagree). A generation counter drops the result of any load that is not the newest | `stats_screen.dart` |
| D-18203 | Before reading the dismissal store a load awaits `_signalsWriteTail` (the chained dismissal writes, which never throw), so a reload cannot resurrect a card the user dismissed a moment earlier. At the first load the tail is an already-completed future, so nothing changes there | `stats_screen.dart` |
| D-18204 | A silent reload that fails shows the same `LoadFailureView` with its Retry as a failed first load (an honest error beats stale numbers under a new setting). Retry calls `_loadData()` with the spinner as today | `stats_screen.dart` |
| D-18207 | Review fix round 1: a successful reload sets `_loadFailed = false` itself (the silent path skips the head reset), so a screen that showed the failure view recovers when Start of Week flips and the reload succeeds | `stats_screen.dart` |
| D-18205 | Tests that flip the setting mid-test run on the Mock harness only (a Hive write started inside `testWidgets` never settles, unit 102's lesson); flipping goes through `tester.runAsync(() => settingsState.setStartOfWeek(...))` followed by `pumpAndSettle` | the two screen tests |
| D-18206 | Proof: the lead's mutation pass M1-M6; the prover is not run (the tests are new screen tests that fail at the base by construction, and mutation needs the lead anyway) | Assumption Log |

## Exact production code

### P1 — `lib/features/stats/stats_screen.dart` (one file; no other file changes)

(a) Replace the existing `initState` (current text):

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }
```

with:

```dart
  /// The Start of Week the newest load started with (plan 108, D-18201), or
  /// null until the first load has started.
  String? _startOfWeekInUse;

  /// Counts loads, so a load that is no longer the newest drops its result
  /// instead of overwriting a newer one (D-18202).
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.settingsState.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    widget.settingsState.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// Reloads in the background when Start of Week moved, because the Mix
  /// strip's week columns and the signals' week were computed with the old
  /// one. Every other setting only repaints (D-18201).
  void _onSettingsChanged() {
    final inUse = _startOfWeekInUse;
    if (inUse == null || inUse == widget.settingsState.startOfWeek) return;
    _loadData(silent: true);
  }
```

(b) `_loadData`: the current head

```dart
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loadFailed = false;
      _isLoading = true;
    });
    try {
```

becomes

```dart
  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    // One value for the whole load: the Mix layer and the signals can never
    // be computed under different weeks (D-18202).
    final startOfWeek = widget.settingsState.startOfWeek;
    _startOfWeekInUse = startOfWeek;
    if (!silent) {
      setState(() {
        _loadFailed = false;
        _isLoading = true;
      });
    }
    try {
```

(c) In `_loadData` the three lines `startOfWeek: widget.settingsState.startOfWeek,` (in `computeMixLayer`, `evaluateCandidates` and `waitingLines`) become `startOfWeek: startOfWeek,`.

(d) Directly before `final signalsDismissedAtMs = evaluateSignals` add:

```dart
      // A dismissal tapped a moment ago is written through a chain; wait for
      // it, or this load would read the old store and bring the card back
      // (D-18203). The chain never throws.
      if (evaluateSignals) await _signalsWriteTail;
```

(e) The two guards. The current `if (!mounted) return;` that sits directly before the final `setState(() { _totalSessions = totals.completedSessions; ...` becomes `if (!mounted || generation != _loadGeneration) return;`, and the `catch (_) { if (!mounted) return; ...` becomes `catch (_) { if (!mounted || generation != _loadGeneration) return; ...`.

## Scenarios

The signals screen test file already holds a stub signal that records the Start of Week it saw (`seenOnEvaluate`, `seenOnWaiting`, `evaluations`, `waitingCalls`) and a `pumpStats` helper; the Mix screen test file holds `_oldestWeekStart(String)` and the strip semantics keys. All flip scenarios are Mock-only (D-18205).
`Fails without the change` is proven by the lead's mutations (D-18206).

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-18201 | `signals_layer_screen_test.dart`, gate-met seed, one abstaining stub with a waiting line; Stats pumped on Monday; then Start of Week flipped to Sunday with the screen still mounted | after `pumpAndSettle`: `seenOnEvaluate` and `seenOnWaiting` are `sunday`, `evaluations` is 2 and `waitingCalls` is 2; no `CircularProgressIndicator` in the tree at the moment of the swap (a `pump()` right after the flip still shows the list key `signals_layer` or the locked line, not the spinner) | nothing reloads, so the stub is never asked again (M1 drops the listener; M2 drops the comparison and S-18202 sees it) |
| S-18202 | Same fixture; after the first load flip `setShowWeightTrend(false)`, then `setStartOfWeek('monday')` (the value it already has) | `evaluations` stays 1 | a reload on every settings notification (M2: the comparison removed) |
| S-18203 | A gated signal (first `evaluate` waits on a Completer; its card text is `started on <startOfWeek>`); Stats pumped on Monday so load 1 is blocked inside the signal; flip to Sunday (load 2 runs to the end); then release the gate | `started on sunday` is found once and `started on monday` is found nowhere | a slow older load overwrites the newer one (M3: the generation guard on the success path removed) |
| S-18204 | `signals_layer_screen_test.dart`, Stats pushed over by a plain route (`Navigator.push` of a `Scaffold`), flip to Sunday while it is covered, pop back | the stub saw `sunday` and `evaluations` is 2 | the held route keeps the old week (same cause as S-18201) |
| S-18205 | `mix_layer_screen_test.dart`, the existing strip fixture (`_seedEveryStripWeek`), Stats pumped on Monday, flip to Sunday | `mix_week_0_semantics` starts with `OmniDateUtils.formatShort(_oldestWeekStart('sunday'))` followed by `: ` and no longer with the Monday date | the strip keeps the Monday anchors |
| S-18207 | `signals_layer_screen_test.dart`, gate-met seed, a signal whose FIRST evaluation throws and later ones return a card; Stats pumped (first load fails), then Start of Week flipped | before the flip `Could not load your stats.` is shown; after the reload it is gone and the card is shown | a success never clears `_loadFailed` (M7: the added `_loadFailed = false;` removed) |
| S-18206 | `signals_layer_screen_test.dart`, a card dismissed by tap, then (before the store settles) Start of Week flipped | the dismissed card is not on screen after the reload | the reload reads the store before the write lands (M4: the `await _signalsWriteTail` removed) |

## Phases

| Phase | Agent | Write scope | Items | Order |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/features/stats/stats_screen.dart` | 5 (a-e) | first |
| P2a | crew-builder-app | `test/signals_layer_screen_test.dart` | S-18201..S-18204, S-18206, S-18207 | after P1, parallel with P2b |
| P2b | crew-builder-app | `test/mix_layer_screen_test.dart` | S-18205 | after P1, parallel with P2a |
| P3 | the lead | `docs/theme_and_settings.md` | the Docs delta row (one sentence) | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts; `flutter analyze` issue count not above the base count (181; 0 errors); full `flutter test` green apart from the known flaky red (`routine_save_removes_deleted_rows_test.dart` S-R3); invariant grep clean; `ui_standards_contract_test.dart` and `docs_indexing_contract_test.dart` green; `plan-lint.py after` clean.
Mutations (lead, in place, one file): M1 remove `widget.settingsState.addListener(_onSettingsChanged);`; M2 remove `inUse == widget.settingsState.startOfWeek ||`-style comparison (make `_onSettingsChanged` call `_loadData(silent: true)` unconditionally after the null check);
M3 the success-path guard `if (!mounted || generation != _loadGeneration) return;` to `if (!mounted) return;`; M4 remove `if (evaluateSignals) await _signalsWriteTail;`; M5 `silent` ignored (`if (!silent)` to `if (true)`); M6 one of the three `startOfWeek:` arguments back to `widget.settingsState.startOfWeek` is NOT killable by a stable setting and is covered by reading the diff (recorded as such).

## Docs delta

`docs/stats_screen.md` is at its size band and is NOT edited (its "one load pass" sentences stay true: a flip is one more load pass). The lead writes the one sentence.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/theme_and_settings.md | ADDED | - | changing `Start of Week` while Stats is open | S-18201 |

The sentence states: changing Start of Week while Stats is open (or underneath another screen) refreshes Stats in the background so the Mix strip's week columns and the signals' week follow, no other setting reloads it, and names the tests `S-18201` and `S-18202`.

## Progress

- [x] P1 production
- [x] P2a signals screen tests
- [x] P2b mix strip test
- [x] P3 docs sentence
- [x] P4 review
- [x] lead: verify, mutations, full suite

## Assumption Log

- 2026-11-03 lead: lead-seeded with exact code, no architect run; the prover is skipped (D-18206).
- 2026-11-03 lead: the reload is silent (no spinner) because a flash of the loading state on a settings toggle would look like a bug; a failed silent reload shows the same error view as a failed first load (D-18204). Both are visible behaviour, stated to the owner in the report.
- 2026-11-03 lead: review fix round 1 (Blocker, D-18207): the plan's exact code omitted `_loadFailed = false` on the success path of a silent reload. The lead made the one-line production fix; the guard test S-18207 is a closed builder brief.
- 2026-11-03 lead: results. Mutations M1-M5 and M7 each failed a test (M6 diff-read only; the `catch`-path generation guard and the defensive `removeListener`/`inUse == null` checks have no killing test, named in the review). Full `flutter test` after the fix round: +6326 ~2, all passed (the earlier run before the fix: +6324 ~2 -1, only the known flaky S-R3). `flutter analyze` 181 (base 181). Review: APPROVE WITH FIXES, one Blocker, fixed in round 1 (D-18207).
