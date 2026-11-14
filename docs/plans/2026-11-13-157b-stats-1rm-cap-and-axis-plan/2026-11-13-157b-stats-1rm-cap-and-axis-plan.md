# Plan 157b — Est. 1RM counts at most 12 reps; one stray set never moves a lift to rep counting

Series: `docs/plans/2026-11-13-157-stats-what-counts-series.md` (second PR). Source: items 3 and 10 (first half) of the Stats pre-launch review (memory `stats-prelaunch-review-2026-11-12`); owner accepted the recommendations on 2026-11-13. Two tracks, two parallel builder phases: phone `lib/core`, and the wrist's Swift copy of the formula.

## Goal and acceptance

1. **Rep cap.** Epley (`weight x (1 + reps / 30)`) overstates a long set: 30 reps at 100 kg reads 200 kg. A set now counts at most 12 reps in the estimate (100 kg x 30 reads 140 kg). The phone has one formula (`StatsProgressService.epley1RM`, used by Stats, the Session Summary, the bests and the in-workout New PR toast) and the wrist has a Swift copy (`WatchPersonalBests.estimateOneRepMax`) that must give the same number bit for bit, so both change in this PR.
2. **Axis rule.** Today an exercise reads rep counting ("10 reps") everywhere once ANY zero-weight set exists in its history (proven 2026-11-12: Squat reads 116.7 kg Est. 1RM; a later workout adds Squat and never touches it, one stored 10 x 0 kg set, and Squat now reads "10 reps"). New rule: an exercise is on the reps axis only when its zero-weight entries (at least one rep, no load) STRICTLY OUTNUMBER its loaded entries over its whole history; a tie goes to the weight axis. One decision function, read by Stats' lift cards (`computeProgressData`), the Instruments list, the Progression Rate and the Mix of exercise values (`_repsAxisExercises`).

Acceptance: S-15801..S-15810 green; the scenarios marked "fails without" are red at the base commit; `flutter analyze` not above 181 (0 errors); full `flutter test` has no new red; `swift test --package-path watch/watchos` green with the new Swift test (and `--filter WatchSessionEngineTests` for the append-only source guard).

## What the user sees

- A set of 15 or 30 reps no longer inflates Est. 1RM, the "New PR" toast, the summary's PR line or the wrist's PR check: the figure stops growing after 12 reps (a 30-rep set reads like a 12-rep set at the same weight).
- A lift trained with weights (Squat) stays on Est. 1RM when one stray zero-weight set sits in its history. A push-up done mostly without weight stays on rep counting. An exercise with exactly as many loaded as zero-weight entries reads Est. 1RM.
- Not changed (Open item 1): the Session Summary's own PR line still uses its session-only rule "any bodyweight set in this session gives a reps verdict".

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | The cap lives in the one formula: `StatsProgressService.epley1RM` (`lib/core/services/stats_progress_service.dart:2273`) counts `min(reps, kEpleyMaxReps)` with `static const int kEpleyMaxReps = 12;` (the owner accepted "about 12"). Every caller (lines ~377, 1627, 2328, 2448, `workout_session_screen.dart:1115`, `session_summary_builder.dart:91`) gets it for free. `weight <= 0 \|\| reps <= 0` still returns null. | `epley1RM` is documented "Source of truth" |
| D-2 | The wrist copy changes in the same PR with the same operation order: `loadKg * (1 + Double(min(reps, epleyMaxReps)) / 30.0)` (`WatchPersonalBests.swift:216`). A set equal to the phone's frame value must still compare equal bit for bit. | `WatchPersonalBests.swift:213` comment |
| D-3 | The reps axis (`repsBest`) and the reps comparison are untouched by the cap. | cap is on the e1RM only |
| D-4 | `_repsAxisExercises` (`stats_progress_service.dart:1473`) becomes the single axis decision: it tallies, per requested exercise over the full history of ended sessions, the set entries with at least one rep, split into loaded (`weight > 0`) and zero-weight, and returns the ids where zero-weight strictly outnumbers loaded. `_hasBodyweightEntry` (line 1498) is deleted (its only caller is this function). Entries with zero reps (skipped sets) tally nowhere. | review item 3 |
| D-5 | `computeProgressData` stops deciding by `repsDayMap.isNotEmpty` (line ~344) and reads `repsAxis.contains(exerciseId)` from one `await _repsAxisExercises(topLiftIds.toSet())` before its loop. A reps-axis exercise always has a non-empty `repsDayMap` (it has at least one zero-weight entry), a weight-axis one ignores its stray zero-weight sets. | `computeProgressData` axis comment |
| D-6 | No migration and no data change: the rule is read-time. The wrist's stored bests frame is replaced by the next frame the phone sends, so a pre-cap frame on a wrist is stale only until then. | stats redesign has no stored user data to repair |
| D-7 | Out of scope, recorded: the Session Summary's session-level rule (`session_summary_service.dart:244-290`, "any bodyweight set this session") and `getAllTimeBestReps`/`getAllTimeBests` (they fill both axes for the wrist and read zero-weight sets by design). | Open item 1 |

## Scenarios

Phone fixtures use the harness of `test/stats_progress_test.dart` / `test/entry_delete_rests_test.dart` (`harnessFactories`, `seedSession`, `seedExercise`, `seedSetEffort`, `repo.createObservation` with `LoggedEntryRows.setObservations`) on Mock and Hive; numbers below were derived with `weight * (1 + min(reps,12)/30)`.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-15801 | `StatsProgressService.epley1RM` direct calls: (100, 1), (100, 10), (100, 12), (100, 13), (100, 30), (0, 5), (100, 0). | 103.3333, 133.3333, 140.0, 140.0, 140.0, null, null (`closeTo(..., 1e-9)`; and `epley1RM(100, 30)` equals `epley1RM(100, 12)` exactly). | (100, 13) and (100, 30) read 143.33 and 200.0 |
| S-15802 | One ended session with a set 100 kg x 30; `getAllTimeBestE1RM(exerciseId)`; and the same set through `getAllTimeBests()`. | 140.0 on both reads. | both read 200.0 |
| S-15803 | Squat: four ended sessions on four days, each with one loaded set 100 kg x 5; one more ended session with one stored entry 10 reps x 0 kg (an untouched placeholder shape). `computeProgressData`, `_repsAxisExercises` via `computeExerciseMetrics`. | Squat's lift card has a non-empty `e1RmTrend` and an EMPTY `repsTrend`; its Recent PR is an e1RM PR; `computeExerciseMetrics` reads it on the weight value. | one stray zero-weight entry puts Squat on the reps axis (reps trend only) |
| S-15804 | Push-up: three ended sessions each with one 0 kg x 12 entry, one session with one entry 10 kg x 8 (a belt). | Reps axis: non-empty `repsTrend`, empty `e1RmTrend` (assert only the axis). | passes with and without the change on purpose: it pins the other side of the rule (mutation: invert the comparison) |
| S-15805 | A tie: one 0 kg x 10 entry and one 60 kg x 8 entry, each in its own ended session. | Weight axis (non-empty `e1RmTrend`, empty `repsTrend`). | the any-zero rule puts the tie on the reps axis |
| S-15806 | An exercise whose only entries are zero-weight (plank-like pushups, 3 sessions). | Reps axis. | passes with and without the change on purpose: guards the strict comparison against an empty loaded tally (mutation d) |
| S-15807 | An exercise with 5 loaded entries and 5 skipped entries (reps 0, weight 0). | Weight axis: skipped entries tally nowhere. | passes with and without the change on purpose: guards the `reps <= 0` skip inside the new tally (mutation: remove it) |
| S-15808 | Instruments read: the S-15803 history through `computeInstrumentSections` (or the Instruments service entry the existing `test/instrument_list_service_test.dart` uses). | Squat's row reads its Est. 1RM, not a rep count. | the Instruments list also reads the any-zero rule |
| S-15809 | The in-session toast: `test/in_session_pr_toast_test.dart`'s helper path with a set 100 kg x 30 against a held best of 140.0. | No PR (equal after the cap); 100 kg x 12 against 140.0 also no PR; 101 kg x 12 is a PR. | 100 x 30 (200.0) beats 140.0, so the toast fires |
| S-15810 | Wrist (Swift, `WatchPersonalBestsTests`): a held frame whose loaded exercise has `e1rmKg` `100.0 * (1 + 12.0 / 30.0)`; the wrist logs 100 kg x 30. | `noteLogged` is false; 100 kg x 12 false; 101 kg x 12 true. | the wrist's uncapped estimate 200.0 beats 140.0 and fires a banner the phone would not |
| S-15810b | Squat: two ended sessions with 100 kg x 5; a session still running (no end) holding three 0 kg x 10 entries. `computeProgressData`. | Weight axis (`e1RmTrend` non-empty, `repsTrend` empty): an unfinished session never decides the axis. | the walk would count the running session's weightless entries and move Squat to the reps axis (mutation h) |

## Input-reality checklist

1. Writers: zero-weight sets come from `SessionCore.addEntry` placeholders (weight 0.0, untouched; 157a drops them at Finish, older data keeps them), from bodyweight exercises (no `load` capability, the weight row stays 0, `session_core_entry.dart:238-266`), from a typed 0, and from the watch importer (`loadKg` null becomes weight 0). Units: kilograms in storage. High-rep sets come from the same writers.
2. Lifecycle: ended sessions only (the walk skips `endedAtMs == null`); an edited old workout is read as stored; a skip marker is a 0-rep entry and tallies nowhere.
3. Settings: kg/lb display does not change the stored value or the axis.
4. Time: not involved (full history, no window).
5. Cost: one more cached-index pass per `computeProgressData` (it already walks history twice); `_repsAxisExercises` keeps its single walk and now counts instead of stopping at the first hit.
6. Words: docs that state the old rule or formula are in the Docs delta (found by grepping `any bodyweight`, `reps / 30`).
7. Competition: n/a.

## Phases

1. **Phone** (`crew-builder-app`, one run, parallel with phase 2): (1) `epley1RM` cap and doc comment; (2) `_repsAxisExercises` tally and delete `_hasBodyweightEntry`; (3) `computeProgressData` reads the axis from `_repsAxisExercises` and its comment is rewritten; (4) update the doc comment on `_repsAxisExercises`; (5) new `test/est_1rm_cap_and_axis_test.dart` with S-15801..S-15809 (S-15809 may live in `test/in_session_pr_toast_test.dart`'s style but in the new file). Done: the new file green (Mock and Hive); the readers (below) green; no full suite.
2. **Wrist** (`crew-builder-watch`, one run, parallel with phase 1, disjoint scope): the Swift copy and S-15810. Done: `swift test --package-path watch/watchos --filter WatchPersonalBestsTests`, then `--filter WatchSessionEngineTests` (append-only guard), then the full `swift test`.
3. **Docs** (`crew-docs-keeper`) after both; then the lead's full suite, mutation pass, review (`crew-reviewer`).

Exact production code, phone (phase 1).

`epley1RM` (replace the doc comment's first line and the body; keep the "Source of truth" paragraph):

```dart
  /// The most reps of one set the estimate counts: Epley overstates a long
  /// set (30 reps would double the bar), so a set of 13 or more reads like a
  /// set of 12 at the same weight (plan 157b D-1).
  static const int kEpleyMaxReps = 12;

  /// Epley 1-rep-max estimate: weight × (1 + min(reps, [kEpleyMaxReps]) / 30).
  /// Returns null when weight or reps is zero/negative.
  ///
  /// (keep the existing "Source of truth" paragraph here)
  static double? epley1RM(double weight, int reps) {
    if (weight <= 0 || reps <= 0) return null;
    final counted = reps > kEpleyMaxReps ? kEpleyMaxReps : reps;
    return weight * (1 + counted / 30.0);
  }
```

`_repsAxisExercises` (replace the whole method; delete `_hasBodyweightEntry`):

```dart
  /// The exercise ids among [exerciseIds] that sit on the reps axis: those whose
  /// zero-weight entries (at least one rep, no load) strictly outnumber their
  /// loaded entries across the **full** history — the one axis rule
  /// `computeProgressData` shares (plan 157b D-4). One stray zero-weight set
  /// never moves a lift off Est. 1RM, and a tie reads Est. 1RM.
  ///
  /// The walk ignores the caller's range on purpose: the axis is a property of
  /// the exercise, so a range that happens to hold only loaded sets does not
  /// move an exercise onto the weight axis, and every point of one series
  /// carries the same metric.
  Future<Set<String>> _repsAxisExercises(Set<String> exerciseIds) async {
    final history = await _loadHistory();
    final bodyweight = <String, int>{};
    final loaded = <String, int>{};
    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      for (final segment in history.segmentsOf(session.id)) {
        for (final effort in history.effortsOf(segment.id)) {
          if (effort.effortKind != 'set') continue;
          final exerciseId = effort.exerciseId;
          if (exerciseId == null || !exerciseIds.contains(exerciseId)) continue;
          for (final entry in ObservationGrouper.groupByEffortKind(
            'set',
            history.observationsOf(effort.id),
          )) {
            final reps = entry['reps'] as int? ?? 0;
            if (reps <= 0) continue;
            final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
            final tally = weight > 0 ? loaded : bodyweight;
            tally[exerciseId] = (tally[exerciseId] ?? 0) + 1;
          }
        }
      }
    }
    return {
      for (final id in bodyweight.keys)
        if (bodyweight[id]! > (loaded[id] ?? 0)) id,
    };
  }
```

`computeProgressData`: after `final fullRepsByExercise = await _buildFullRepsForExercises(completed, topLiftIds);` (line ~320) add `final repsAxis = await _repsAxisExercises(topLiftIds.toSet());`; replace the comment block and `final isRepsAxis = repsDayMap.isNotEmpty;` (lines 333-344) with:

```dart
      // ── Per-exercise axis decision (plan 157b D-4, D-5) ──
      // The axis is a property of the exercise, decided once over its whole
      // history by `_repsAxisExercises`: reps-axis only when its zero-weight
      // entries outnumber its loaded ones, so one stray zero-weight set never
      // moves a lift off Est. 1RM. A reps-axis exercise always has reps data.
      final isRepsAxis = repsAxis.contains(exerciseId);
```

Exact production code, wrist (phase 2), `WatchPersonalBests.swift` (extension near line 213): replace

```swift
    private static func estimateOneRepMax(loadKg: Double, reps: Int) -> Double {
        loadKg * (1 + Double(reps) / 30.0)
    }
```

with

```swift
    /// The most reps of one set the estimate counts: the phone's
    /// `StatsProgressService.kEpleyMaxReps` (plan 157b D-2).
    private static let epleyMaxReps = 12

    private static func estimateOneRepMax(loadKg: Double, reps: Int) -> Double {
        loadKg * (1 + Double(min(reps, epleyMaxReps)) / 30.0)
    }
```

and update its doc comment to `weight * (1 + min(reps, 12) / 30.0)`.

## Readers (tests that run the formula or the axis; builder Done lists)

Dart: `test/stats_progress_test.dart`, `test/services_test.dart`, `test/state_test.dart`, `test/in_session_pr_toast_test.dart`, `test/stats_bests_builder_test.dart`, `test/watch_sync_request_handler_test.dart`, `test/progression_samples_service_test.dart`, `test/progression_rate_test.dart`, `test/exercise_metric_service_test.dart`, `test/instrument_list_service_test.dart`, `test/instrument_list_screen_test.dart`, `test/interference_sessions_service_test.dart`, `test/records_and_trends_screen_test.dart`, `test/session_summary_effort_row_test.dart`, `test/fuel_vs_load_test.dart`. The lead ran all of them with the cap alone (probe, 609 tests) and none went red; a red after the axis change is a fixture to explain in the report, not to edit. Swift: `WatchPersonalBestsTests`, `WatchPersonalBestsStoreTests`, `WatchPersonalRecordBannerTests`, `WatchPersonalBestsWiringSourceTests`, `WatchConnectivityBridgeTests`; the wire fixtures under `watch/sync_protocol/fixtures/` carry numbers the phone computed and need no change (they are not formula tests).

## Mutation list (lead)

Phone: (a) `reps > kEpleyMaxReps ? kEpleyMaxReps : reps` to `reps`; (b) cap constant 12 to 13; (c) `bodyweight[id]! > (loaded[id] ?? 0)` to `>=`; (d) the same to `bodyweight[id]! > 0`; (e) remove `if (reps <= 0) continue;` in the tally; (f) `weight > 0 ? loaded : bodyweight` to `weight >= 0 ? loaded : bodyweight`; (g) `isRepsAxis` back to `repsDayMap.isNotEmpty`; (h) drop `if (session.endedAtMs == null) continue;`; (i) `effort.effortKind != 'set'` check removed. Swift: (j) remove `min(reps, epleyMaxReps)`; (k) cap 12 to 13; (l) change the operation order to `loadKg * (1.0 + Double(...)) / 30.0`.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/services_and_utils.md` | MODIFIED | exercise is on the reps axis when any bodyweight set appears anywhere in its | exercise is on the reps axis when its bodyweight sets outnumber its loaded sets across its | S-15803, D-4 |
| `docs/state_management/services_and_utils.md` | ADDED | - | Epley counts at most 12 reps of a set | S-15801, D-1 |
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | `loadKg * (1 + reps / 30)` | `loadKg * (1 + min(reps, 12) / 30)` | S-15810, D-2 |
| `docs/stats_best_load_investigation.md` | MODIFIED | `weight × (1 + reps / 30)` (`:944–947`). | `weight × (1 + min(reps, 12) / 30)` (`:944–947`; a set counts at most 12 reps). | S-15801, D-1 |

Stale-term sweep run (`grep -rIn "any bodyweight\|reps / 30\|Epley" docs`, minus plans/history/releases): the four hits above plus `docs/state_management/services_and_utils.md:374`, which the ADDED row extends; `stats_best_load_investigation.md` lines 359 and 537 stay true below 13 reps.

## Open items (owner)

1. The Session Summary's PR line uses its own session-only rule (any zero-weight set in that session gives a reps verdict); after 157a an untouched placeholder no longer triggers it, only a zero-weight set the user logged. Want it moved to the same majority rule? (needs counts on the per-exercise summary; not done here.)
2. `docs/stats_best_load_investigation.md` is a dated investigation page; only its formula line is updated (its source line references are stale, review minor 3).
3. The in-session New PR toast still picks its axis per set (a set with no weight is judged on reps, `workout_session_screen.dart:1134-1147`), so a weightless set logged on a lift the card reads as Est. 1RM can still fire a reps PR toast the card never shows (review minor 1). Route the toast through the same majority rule? (changes when a toast appears; not done here.)

## Predicted files

`lib/core/services/stats_progress_service.dart` (about +45/-30); new `test/est_1rm_cap_and_axis_test.dart`; `watch/watchos/Sources/WatchSessionEngine/WatchPersonalBests.swift` (about +5); `watch/watchos/Tests/WatchSessionEngineTests/WatchPersonalBestsTests.swift` (+test); three docs. Scopes: phase 1 writes only the service file and the new test; phase 2 only the two Swift files.

## Progress

- [x] Phase 1 phone: cap, tally, axis read; `est_1rm_cap_and_axis_test.dart` 19 green on Mock and Hive
- [x] Phase 2 wrist: Swift copy capped; `WatchPersonalBestsTests` 22 green, whole package 1427, 0 failures
- [x] Phase 3 docs: four rows applied plus the keeper's stale `session_summary.md` formula line; `plan-lint after` clean
- [x] Lead verification: analyze 181 (baseline, 0 errors); full suite 7566 passed, 5 skipped, 0 failed
- [x] Mutation pass: phone 10 (8 killed after two tests-only additions, 2 equivalent), Swift 3 of 3 killed
- [x] Review: APPROVE, 0 blocker, 0 major, 3 minor (recorded below)
- [ ] (owner) Device check: a 15-rep set of a lift shows the same Est. 1RM as a 12-rep set at that weight; a lift with one stray 0 kg set still shows Est. 1RM

## Assumption Log

- 2026-11-13: base commit `cd117f79`; branch `claude_develop`; 157a is uncommitted in the same tree (its files are disjoint from this plan's scopes; `docs/state_management/` pages differ).
- 2026-11-13: probe: with only the cap applied to `epley1RM`, 15 reader test files (609 tests) stay green, so no existing test encodes the uncapped formula.

## Feedback

(none yet)
- 2026-11-13: S-15808 reads the axis through `progressionSamples` (not `computeInstrumentSections`): both read it from `computeExerciseMetrics` via `_repsAxisExercises` (review minor 2). S-15810b is the unfinished-session guard added after the mutation pass; S-15807 uses six skipped sets so that tallying them would flip the axis.
- 2026-11-13: lead edits (tests/docs only): `test/exercise_metric_service_test.dart` S-904 Pull-up now holds two weightless entries and one weighted (a tie now reads Est. 1RM); two tests added to `test/est_1rm_cap_and_axis_test.dart`; `docs/session_summary.md` formula line (keeper's stale-claim report).
