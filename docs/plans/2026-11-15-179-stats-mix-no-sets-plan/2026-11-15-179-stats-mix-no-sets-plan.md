# Plan 179 — A session with no sets no longer gives its unmeasured minutes to Resistance

Series: Stats pre-launch review group B (item 2 of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). Owner chose "share the leftover minutes by what you did" on 2026-11-15. Phone only (`lib/core`), two builder runs, then docs. Status: BUILT and verified, uncommitted.

## Goal and acceptance

The Training Mix splits a finished session's time by modality. Timed work (runs, holds, rounds) is measured; lifting sets have no timer, so the owner's rule D-8 gives Resistance "the remainder": the session's length minus the measured time (`sessionTimeByModality`, D-904). The rule never asks whether the session had any sets. Reproduced with a probe on the base code: a 40-minute session with one 30-minute run and no sets reads Cardio 75 / Resistance 25; a 60-minute yoga class with 18 minutes of holds and no sets reads Resistance 70 / Isometric 30.

After this change a session that holds no `set` effort but has measured time shares its whole duration across the measured modalities in proportion to their measured time: the run reads Cardio 100, the class Isometric 100, and the session still counts its full length, so its load (length x rating) is unchanged. A session with a set effort keeps the remainder rule exactly. Nothing else moves: rolling sessions, the "measured time exceeds the duration" fallback, and a session with no measured time (it stays all Resistance, as today).

Acceptance: S-20001..S-20011 green, the ones marked "fails without" red at the base commit; the seven existing tests named in "Readers" green after their fixtures gain a set (assertions unchanged); `flutter analyze` at the plan's baseline (181, 0 errors); full suite no new red.

## What the user sees

- Before: a run-only workout or a yoga class shows a slice of Resistance that nothing in it earned.
- After: those workouts read 100% Cardio / Isometric. Workouts with lifting sets read exactly as before. Weekly load, Sustained High Load and the calorie estimate use the same total minutes as before; only which modality the minutes belong to changes.
- Changed on purpose, owner please note: the 2026-09-24 acceptance example A2 ("Free Training, 20 min of holds, rated 3 reads Resistance 40 min / Isometric 20 min") describes a session with holds and no sets. After this change that session reads Isometric 100; the same session WITH a set reads 67/33 as before.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `sessionTimeByModality` (`lib/core/models/training_load.dart:200`) gains `required bool hasSets`. After the existing "measured exceeds the duration" branch and before the remainder, `if (!hasSets && totalMeasured > 0)` it returns each measured modality scaled to the duration: `value * durationSecs / totalMeasured` (this operand order keeps 1800 * 2400 / 1800 exactly 2400.0). | owner 2026-11-15 |
| D-2 | A session with no measured time keeps today's result whatever `hasSets` says (all Resistance for the duration). 32 reader tests build set-less sessions with no timed work; changing it was tried and made 113 of 593 reader tests red. | trial run |
| D-3 | `StatsProgressService._sessionSplit` (`stats_progress_service.dart:914`) passes `hasSets: _hasSetEffort(history, session)`. New private `_hasSetEffort` = any effort of the session with `_sectionForKind(effort.effortKind) == ExerciseSection.resistance`. One caller in production; the parameter is required so no future caller can forget it. | `_sessionSplit`, `_sectionForKind` |
| D-4 | Everything fed by the split changes with it and needs no code: `computeMixLayer`, `computeMixPeriod`, `weeklyLoads` (total load per session unchanged), `interferenceSessions` (a sports-only session's Sports load rises), `sessionTimeBySectionFor` (the Free Training calorie estimate prices the leftover as the session's measured modalities). | `_sessionSplit` callers |
| D-5 | The dominant-modality branch (D-905) and the rolling branch (D-906) are untouched and run before D-1's branch. | S-20005 |
| D-6 | No migration, no wording change in the app, no watch change. | scope |

## Scenarios

Pure scenarios call `sessionTimeByModality` and `mixSegments` directly. Numbers re-derived with a mirror of the old and new rule; the old results for S-20001 / S-20002 were also reproduced by a probe run on the base code.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20001 | `sessionTimeByModality(durationSecs: 2400, isRolling: false, measuredSecs: {cardio: 1800}, dominantSection: cardio, hasSets: false)` and `mixSegments` of the result. | `{cardio: 2400.0}`; one segment, cardio 100. | the result is `{cardio: 1800, resistance: 600}`, 75 / 25 |
| S-20002 | duration 3600, measured `{isometric: 1080}`, dominant isometric, `hasSets: false`. | `{isometric: 3600.0}`; one segment, isometric 100. | `{isometric: 1080, resistance: 2520}`, resistance 70 |
| S-20003 | duration 3000, measured `{cardio: 1800, isometric: 600}`, dominant cardio, `hasSets: false`. | `{cardio: 2250.0, isometric: 750.0}`; segments cardio 75, isometric 25; the values sum to 3000. | Resistance takes 600 and the others stay 1800 / 600 |
| S-20004 | the S-20001 fixture with `hasSets: true`. | `{cardio: 1800.0, resistance: 600.0}`, 75 / 25. | passes with and without the change on purpose: a session with sets keeps the remainder (mutation: ignore `hasSets`) |
| S-20005 | duration 1800, measured `{isometric: 2100, cardio: 600}`, dominant isometric, `hasSets: false`. | `{isometric: 1800.0}`. | passes with and without the change on purpose: the overflow branch runs before the new one (mutation: swap their order, the result becomes a scaled split) |
| S-20006 | duration 1800, measured `{}`, dominant cardio, `hasSets: false`. | `{resistance: 1800.0}`. | passes with and without the change on purpose: pins D-2 (mutation: drop the `totalMeasured > 0` test) |
| S-20007 | Service, Mock and Hive: a finished, rated-3 session 10:00-10:40 with one `timed` effort holding one finished instance of 1800 s and no set; `computeMixLayer` for the window holding it, and `sessionTimeBySectionFor(id)`. | the bar is one segment, cardio, 100%; `sessionTimeBySectionFor` is `{cardio: 2400.0}`. | the bar reads cardio 75 / resistance 25 and the time map holds resistance 600 |
| S-20008 | Service, Mock and Hive: a finished 60-minute session with one `drill` (hold) effort of three entries of 360 s, no set. | the bar is one segment, isometric, 100%. | resistance 70 |
| S-20009 | Service, Mock and Hive: a finished 60-minute session with one `set` effort holding one logged set (its rest at position + 1) and one timed 600 s cardio instance. | `sessionTimeBySectionFor` is `{resistance: 3000.0, cardio: 600.0}`. | passes with and without the change on purpose: sets keep the remainder through the real `_hasSetEffort` read (mutation: `_hasSetEffort` always false) |
| S-20010 | Service, Mock and Hive: the S-20007 session, rated 3, in a completed week; `weeklyLoads`. | that week's `loadMinutes` is 120.0 (40 x 3). | passes with and without the change on purpose: the session still counts its full length, so the load is not shrunk (mutation: leftover minutes dropped, 90.0) |
| S-20011 | Service, Mock and Hive: a finished, rated-3 60-minute session with finished rounds of 2400 s in total and no set; `interferenceSessions()`. | that session's Sports load is 180.0 (60 x 3, all Sports). | Sports load reads 120.0 (40 x 3) because a third of the session was counted as Resistance |

## Input-reality checklist

1. Writers and units: efforts of kind `set`, `timed`, `drill`, `round` are written by the logging screen, routines, the importer and the watch; durations are in seconds; `actualDurationSecs` of a finished instance is the measure.
2. Lifecycle: only ended sessions are split; a session whose last set was deleted before Finish has no set effort (plan 157a removes a set exercise left empty), so it follows the new rule; a wrist-linked session keeps its planned set efforts (157a D-11) and so keeps the remainder rule.
3. Settings: none; the saved start of week and the Effort Rating toggle do not enter the split.
4. Time: duration is `endedAtMs - startedAtMs`; the scaling needs `totalMeasured <= durationSecs`, which the overflow branch guarantees before it runs.
5. Cost: one extra walk over a session's efforts per session (about the cost of the dominant-section walk beside it); no new repository read.
6. Words: no new on-screen wording; docs in the Docs delta. The Mix card already shows shares as percentages.
7. Slot competition: the Mix layer, Sustained High Load, the Interference signal and the Free Training calorie estimate all read `_sessionSplit`; their reader tests are listed below.

## Phases

1. **P1 builder-app, scope `lib/core/models/training_load.dart`, `lib/core/services/stats_progress_service.dart`, `test/training_load_test.dart`, `test/mix_no_sets_pure_test.dart`:** (1) D-1 in `sessionTimeByModality` with its doc comment; (2) D-3 `_hasSetEffort` and the `_sessionSplit` argument; (3) `test/training_load_test.dart`: add `hasSets: true` to each existing `sessionTimeByModality(` call (twelve, mechanical, assertions untouched); (4) new `test/mix_no_sets_pure_test.dart` with S-20001..S-20006. Done: `flutter test test/training_load_test.dart test/mix_no_sets_pure_test.dart` green; no full suite.
2. **P2 builder-app, scope `test/mix_no_sets_service_test.dart`, `test/mix_layer_service_test.dart`, `test/modality_mix_period_service_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`, `test/active_energy_service_test.dart`, `test/active_energy_import_test.dart`:** (1) new `test/mix_no_sets_service_test.dart` with S-20007..S-20011 over `harnessFactories` (Mock and Hive); copy the seeding helpers from `test/mix_layer_service_test.dart` (`_seedSession`, `seedHoldEffort`) and `test/interference_sessions_service_test.dart` (`_seedSportsSession`); (2) premise fixes in the five existing files for the seven tests named in Readers: add ONE logged-set effort to each fixture (a `set` effort with one entry and its rest at position + 1, as `_seedLiftingEffort` in `mix_layer_service_test.dart` does) so the session holds sets, keeping every assertion value; a set adds no time. Report FIRST as a skeleton. Done: the six files green on both stores; no full suite.
3. **P3 crew-docs-keeper**, then the lead's full suite, mutation pass and `crew-reviewer`. The lead writes the docs-delta text below into `docs/training_load.md`'s "Time per modality" bullets.

Exact production code (P1).

`training_load.dart`, `sessionTimeByModality`: doc comment gains the paragraph `A session with no set effort ([hasSets] false) and some measured time shares its whole duration across the measured modalities in proportion to their measured time (plan 179): nothing in it is lifting, so Resistance takes none of it. A session with no measured time is unchanged.` Signature and body change:

```dart
  required ExerciseSection? dominantSection,
  required bool hasSets,
}) {
```

and between the `if (totalMeasured > durationSecs) { ... }` block and `final remainder = durationSecs - totalMeasured;` insert:

```dart
  if (!hasSets && totalMeasured > 0) {
    return {
      for (final entry in measured.entries)
        entry.key: entry.value * durationSecs / totalMeasured,
    };
  }
```

`stats_progress_service.dart`, `_sessionSplit`: in the `sessionTimeByModality(` call add `hasSets: _hasSetEffort(history, session),` after `dominantSection: dominant,`; above `_dominantSectionFor` add:

```dart
  /// Whether [session] holds any `set` effort (plan 179): only a session with
  /// sets gives its unmeasured minutes to Resistance.
  bool _hasSetEffort(_HistoryIndex history, TrainingSession session) {
    for (final segment in history.segmentsOf(session.id)) {
      for (final effort in history.effortsOf(segment.id)) {
        if (_sectionForKind(effort.effortKind) == ExerciseSection.resistance) {
          return true;
        }
      }
    }
    return false;
  }
```

This exact code was applied in a trial on the base commit and the reader files run; the trial was reverted (the tree holds no production change).

## Readers (existing tests that pin the old rule)

Trial result with D-1/D-2/D-3 applied, 593 tests in 25 reader files, base 0 red: 15 red in five files, all fixtures that are a Free Training session with timed work and no set: `test/mix_layer_service_test.dart` (S-1503 Mock and Hive, and the value-for-value parity S-1503), `test/modality_mix_period_service_test.dart` (S-1907 and S-1913, both stores), `test/modality_mix_shift_signal_screen_test.dart` (S-1909, both stores), `test/active_energy_service_test.dart` (S-13404 and S-13414, both stores), `test/active_energy_import_test.dart` (S-13419, both stores). P2 fixes their premise (a set added); a red anywhere else is reported, not edited. The other twenty reader files stayed green: `cardio_efficiency_drift_signal_screen`, `sustained_high_load_{service,signal_screen,unrated_weeks}`, `interference_{sessions_service,signal_screen,}`, `mix_layer_screen`, `stats_rated_weeks_service`, `stats_four_week_window_service`, `stats_heading_consistency_screen`, `modality_mix_shift`, `signals_layer_screen`, `watch_energy_import`, `active_energy_{lifecycle,live}`, `session_live_calories`, `fuel_vs_load`, `protein_consistency`, `nutrition_series_service`. The same run shows that giving the empty-effort session no time (rejected in D-2) breaks 113.

## Mutation list (lead)

(a) `hasSets` ignored (branch always taken when measured > 0); (b) `hasSets` inverted; (c) `totalMeasured > 0` test removed; (d) the new branch moved before the overflow branch; (e) scale by `durationSecs / totalMeasured` replaced by 1 (leftover dropped); (f) `_hasSetEffort` returns false; (g) `_hasSetEffort` returns true when any effort exists; (h) `_sessionSplit` passes `hasSets: true`; (i) the kind test in `_hasSetEffort` matches `timed` instead of `set`.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/training_load.md` | MODIFIED | A non-rolling session's Resistance time is the remainder: its own duration | A non-rolling session that holds a set effort gets its Resistance time as the | D-1, S-20009 |
| `docs/training_load.md` | ADDED | - | A session with no set effort and some measured time shares its whole duration | S-20001, S-20003, D-1 |
| `docs/training_load.md` | ADDED | - | `test/mix_no_sets_pure_test.dart` | S-20001 |
| `docs/training_load.md` | ADDED | - | `test/mix_no_sets_service_test.dart` | S-20007 |
| `docs/session_summary.md` | ADDED | - | session with timed work and no set shares its whole length across the timed | S-20007 |

Stale-term sweep run (`grep -rIn "remainder\|Sets take" docs/*.md docs/state_management docs/widget_catalog`, minus plans/history/releases and the largest-remainder hits): the rows above; `docs/training_load.md:22` ("one remainder rule") and line 83's verified-by list stay true; `calendar_periods.md:24` and `watch_sensors.md:436` are unrelated "remainder" uses.

## Open items

1. (owner) Build go-ahead, and note the A2 example change under "What the user sees". The request said plan only, so nothing is built.
2. A session with no efforts that map to a modality, or whose timed efforts have no finished instance, still reads as all Resistance for its duration (D-2). Fixing it is a separate rule decision: it breaks 113 reader tests whose fixtures are exactly such sessions.
3. The wrist-linked session keeps planned set efforts (157d), so a watch-run session with planned-but-unlogged sets still reads the remainder as Resistance until 157d.

## Predicted files

`lib/core/models/training_load.dart` (+14), `lib/core/services/stats_progress_service.dart` (+15), `test/training_load_test.dart` (12 one-line edits), new `test/mix_no_sets_pure_test.dart` and `test/mix_no_sets_service_test.dart`, five existing test files (a set added to one fixture each), two docs.

## Progress

- [x] Seeded: probe reproduced both examples on the base commit; trial run of the rule over 25 reader files
- [x] P1 build
- [x] P2 build
- [x] P3 docs (by the lead)
- [x] Lead verification, mutation pass (9/9), review (approve)
- [ ] (owner) See the Mix for a run-only and a yoga workout (Stats gallery) before releasing

## Assumption Log

- 2026-11-15: base commit `c95c4a23` on `claude_develop`; the tree holds other sessions' uncommitted watch and diagnostics work (plans 176, 177): none of it touches this plan's scopes.
- 2026-11-15: scenario ids S-20001.. chosen because every S-157xx..S-180xx range is in use by other plans (checked with grep over test, docs, lib, watch).
- 2026-11-15: option "count only the timed minutes" was offered and declined by the owner; it would have lowered those sessions' load by 25 to 70%.

## Feedback

(none yet)
