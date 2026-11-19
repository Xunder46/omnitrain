# Plan 157a — Finish keeps only the sets that were logged

Series: `docs/plans/2026-11-13-157-stats-what-counts-series.md` (first PR). Source: item 1 of the Stats pre-launch review (memory `stats-prelaunch-review-2026-11-12`), owner accepted the recommendation on 2026-11-13. Phone only (`lib/state`), one track.

## Goal and acceptance

A routine writes every planned set into the session when it starts. A set the user never logged stays stored with the planned reps and a carried weight, and Stats, the Session Summary and the bests read it as done (proven on 2026-11-12: 100 kg x 3 logged plus one untouched planned set of 10 reps reads Est. 1RM 133.3 kg; the true figure is 110.0).

After this change, when a workout the watch had no part in is finished on the phone, every `set` entry that was never logged is deleted, and a set exercise left with no entry at all is removed. A set typed in while editing an old, already finished workout still counts (edit mode never runs this). A workout the watch had a part in keeps its planned sets for now (D-11): the watch's own sets can still be on their way when the end arrives and would have nowhere to land. Pruning those is a follow-up (157d).

Acceptance: S-15701..S-15713 green on Mock and Hive where stored data is involved; the scenarios marked "fails without" are red at the base commit `cd117f79`; `flutter analyze` count not above baseline; the full suite has no new red.

## What the user sees

- Finish a routine workout where the last two planned sets were never done: the workout summary shows only the sets that were logged, volume and sets completed match, Stats and the bests no longer count the untouched ones, and an exercise never started is gone from the summary and from "last trained".
- Editing an old workout and adding a set by hand: the set stays.
- A workout the watch took part in (the wrist ran it, the wrist ended it, or its sets were sent to the phone) is NOT cleaned up yet: its planned sets still count, because the watch's own sets can arrive after the end and need those exercises to land in. That is the follow-up 157d.
- Not changed (owner call, see Open items): the Finish dialog's line "You have completed: N exercises" still counts every exercise in the session, including one with no logged set.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | The drop runs inside `SessionCore.endSession` (`lib/state/workout/session_core_lifecycle.dart:11`), first inside its `try`, before `persistActiveRounds`/`persistOpenRests`, for the phone's own Finish of a session the watch had no part in (D-11). A session that already has `endedAtMs` returns before it, so an edit-mode Save, `loadHistoricalSession` and every later reload never drop anything. | `endSession` guard `if (_currentSession!.endedAtMs != null) return;` |
| D-2 | "Logged" is the screen's own rule: a `set` entry at POSITION p (k-th group of `EntryRows.setGroups`) is logged exactly when an `EntryRest` has `entryIndex == p + 1` (`WorkoutSessionScreen._isSetLogged`, `workout_session_screen.dart:807`; `docs/rest_tracking.md` "Rests are positional"). The wrist's live merge opens its rest at the placed spot + 1 (importer D-6), so wrist-logged sets are logged by the same rule. | `watch_session_importer.dart:878` |
| D-3 | A set entry whose reps row carries the skip marker (`valueBool == true`, `markSetSkipped`) stays: it is the user's explicit act and contributes nothing (reps 0). | `session_core_entry.dart:601-647` |
| D-4 | Only `set` efforts. `timed`, `drill` and `round` entries are untouched: they carry their own state, `endSession` already persists partial timed work on purpose, and a never-started interval stores no duration (unverified in Stats, see Open items). | `endSession` calls `persistActiveTimedEntries` |
| D-5 | A `set` effort that has at least one entry dropped and none left is removed (`deleteEffort`, in-memory `_observations`, `_timerManager.removeEffort`, the `_efforts` lists), so a skipped exercise no longer earns a "last trained" date or a trend point. An effort that had no entry before is left alone. | review item 1 |
| D-6 | Quiet: the drop never calls `deleteEntry` or `removeExerciseFromSession` (each notifies listeners, and the open session screen is still mounted while Finish awaits). It deletes rows through `_repository.deleteObservation`, removes them from the in-memory list, re-keys rests with `_timerManager.rekeyEntryRestsAfterDelete`, and relies on `endSession`'s existing single `_notify()`. | `deleteEntry` quoted in the sheet |
| D-7 | Descending position order, with the set of rest positions read once before any delete: deleting position p re-keys only rests above p + 1, so every lower position's rest is unmoved and the one-time read stays valid. | `rekeyEntryRestsAfterDelete` doc |
| D-9 | The drop reads the STORE, not the session's caches: for each set effort it re-reads `getEffortObservations` and `getEntryRests` from `_repository` and refreshes `_observations` and the timer manager's rests from them before it decides anything. Found by phase 1: the watch importer writes a wrist-logged set's rest straight to the repository, and the in-memory rest cache learns of it only through a hook (`onSessionRowsChanged`), so a cache read would delete real wrist sets whenever the hook has not run yet. | S-15710, `watch_session_finish_test` S-4 |
| D-10 | Finish always finishes: the drop is shielded (`try { await _dropUnloggedSets(); } catch (_) {}`), so a failing delete leaves the placeholders in place (today's behaviour) and never turns an end into "Failed to end session". | S-15711 |
| D-11 | A session the watch had a part in keeps its planned sets. The drop is skipped when ANY of: the end is the wrist's own (`writeToHealth == false`, the adoption bridge's `endSession(writeToHealth: false, atMs:)`), the wrist is running the session (`_wristRunsSession`), or the repository holds staged wrist rows for it (`getWatchInboxEntriesForSession(sessionId)` is not empty). Found by phase 1: `test/watch_session_finish_test.dart` S-4 ("end before the logged sets" and "a set logged on the watch lands in the session the phone holds") — an end that arrives before the wrist's sets would delete the slot efforts those sets later land in, and the wrist's sets would be lost. Wrist-linked sessions keep counting their planned sets until the follow-up 157d prunes them after the wrist's rows have settled. | S-15706, S-15712, S-15713 |
| D-8 | No migration: sessions finished before this change keep their placeholders (the Stats redesign ships as one release with no stored user data to repair; the owner is the only user). | memory `stats-redesign-ships-as-one-release` |

## Scenarios

Fixtures are built the way `test/entry_delete_rests_test.dart` builds them (`harnessFactories`, `seedSession`, `seedExercise`, `loadState`, `addExerciseToSession`, `addEntry`, rests through `repo.createEntryRest` or `state.recordRestStart`). The session must be OPEN (no `endedAtMs`) when `endSession` is called. A set's rest at position p + 1 marks it logged.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-15701 | One barbell exercise, 3 sets: set 0 holds 100 kg x 3 with a rest at index 1; sets 1 and 2 are untouched placeholders (10 reps, carried weight). `endSession()`. | Repository and state hold exactly one set (100 x 3), rests `[1]`, the effort stays. | the two placeholders stay stored after Finish |
| S-15702 | 3 sets, rests at 1 and 3 (sets 0 and 2 logged, set 1 never logged; values 50 x 5, 60 x 6, 70 x 7). `endSession()`. | Two sets, values 50 x 5 then 70 x 7, rests `[1, 2]` (the re-key kept the second as logged). | three sets remain and the middle placeholder is read as done |
| S-15703 | Two exercises: X has one logged set, Y has 3 untouched placeholders. `endSession()`. | Y is gone from `repo.getSegmentEfforts`, from the state efforts and from `getEffortObservations`; X stays. | Y stays with its 3 placeholder sets |
| S-15704 | 3 sets: set 0 logged (rest at 1), set 1 skip-marked (`markSetSkipped`, no rest), set 2 untouched. `endSession()`. | Set 0 and the skipped set remain, set 2 is gone. | set 2 stays stored after Finish |
| S-15705 | Edit-mode over-reach guard: a session finished with one logged set is loaded with `loadHistoricalSession`; `addEntry` then `updateEntryValue` (reps 8, weight 40) with no rest; `endSession()`. | `endSession` is a no-op (already ended); the added set is still stored after a reload. | passes with and without the change on purpose: it fails only if the drop also ran for an ended session (mutation h) |
| S-15706 | The wrist's own end: the S-15701 fixture ended with `endSession(writeToHealth: false, atMs: <a fixed past ms>)`. | Every set is still stored (the planned ones too), the logged set's rest is intact, and `endedAtMs` equals the given instant. | a drop that ignored who ended the session would delete the placeholders the wrist's late sets land in (mutation: remove the `!writeToHealth` clause) |
| S-15707 | A `timed` exercise with one never-started interval and a `round` exercise with one not-started round; `endSession()`. | Both survive with their entries and instances. | guards D-4: a drop that ignored the kind would delete them (mutation g) |
| S-15708 | 100 kg x 3 logged plus one untouched planned set of 10 reps (carried 100 kg); `endSession()`. | The summary (`buildSessionSummary` through the state) reads 1 set, volume 300, best Est. 1RM 110.0; `StatsProgressService(repo).getAllTimeBestE1RM(exerciseId)` is 110.0 (100 x (1 + 3/30)). | they read 2 sets, volume 1300 and 133.33 (100 x (1 + 10/30)) |
| S-15709 | Screen, Mock only (the finish harness of `test/session_finish_timers_test.dart`): `WorkoutSessionScreen` over a routine-populated session with unlogged placeholders; tap Finish, confirm. | No exception, the summary screen shows, and its sets-completed figure counts only the logged set. | the summary counts the placeholders, and nothing else guards the open screen not throwing while entries vanish |
| S-15710 | A live session, 2 sets; the rest at index 1 (marking set 0 logged) is written straight to the repository with `repo.createEntryRest`, the way the importer writes it, WITHOUT touching the state's caches. `endSession()`. | Set 0 stays (its rest is read from the store), set 1 is dropped. | a cache read sees no rest and deletes the logged set 0 as well |
| S-15711 | Mock repository subclass whose `deleteObservation` throws; live session with one logged and one untouched set; `endSession()`. | The session still ends (`endedAtMs` set, no error message on the state), and both sets are still stored. | without the shield the throw is caught by `endSession`'s own handler: the end is never stored |
| S-15712 | A live session (S-15701 fixture) with one staged wrist row for it in the repository (`repo.createWatchInboxEntry` or the harness' inbox writer; read how `test/watch_session_finish_test.dart` stages one), ended with the phone's own `endSession()`. | Every set is still stored (D-11). | with only the other two clauses the staged-row case would drop the sets a late wrist entry fills (mutation: remove the inbox clause) |
| S-15713 | The S-15701 fixture on a `WorkoutState` built with `wristRunsSession: (_) => true`, ended with `endSession()`. | Every set is still stored. | the wrist-running clause is the only guard for a wrist session with nothing staged yet (mutation: remove it) |
| S-15712b | The S-15712 fixture with a staged PHONE annotation instead (`origin: originPhone`, `kind: kindPhoneRating`, `entryId: WatchInboxEntry.phoneRatingId(sessionId)`). | The phone's `endSession()` still drops the two placeholders (1 set left). | guards the `origin == originWatch` filter: without it any staged row, including the phone's own annotation, would switch the cleanup off (mutation l2) |

## Input-reality checklist

1. Writers: placeholders come from `SessionCore.addEntry` (`session_core_entry.dart:238-266`, reps 10, carried weight), reached by `populateSessionFromManifest` (`session_core_io.dart:305-375`), Add Exercise, `_addSet` and `seedFirstEntry` (watch slots). Logged marks come from `recordRestStart` (`workout_session_screen.dart:1024`, a Log Set) and the importer's `_applyRests`. Units: reps int, weight kilograms.
2. Lifecycle: an unfinished session is untouched until Finish; a rolling session ends through the same `endSession`; a wrist-only session is created by the importer (`_createSession`) with only logged rows and never passes through `endSession`; an edited old session never reaches the drop (D-1); sessions finished before this change keep their placeholders (D-8).
3. Settings: none change the answer.
4. Time: the end instant is unchanged (`atMs`, D-153).
5. Cost: one pass over the session's set efforts in memory, deletes only the unlogged rows (a few dozen at most), no history read.
6. Words: the Finish dialog line "You have completed:" (`workout_session_finish.dart:29`) is unchanged (Open item 1). Doc sentences found by sweep: see Docs delta.
7. Competition: n/a.

## Phases

1. **Production + state tests** (`crew-builder-app`, one run, no architect): (1) add `_dropUnloggedSets` to the `SessionCoreLifecycleMethods` extension; (2) call it first in `endSession`'s `try`; (3) new `test/finish_drops_unlogged_sets_test.dart` with S-15701..S-15708, then fix rounds 1b (D-9, D-10, S-15710, S-15711) and 1c (D-11, S-15706 rewritten, S-15712, S-15713). Done Criteria: that file green on Mock and Hive; the listed reader files green (below); no full suite.
2. **Screen test** (`crew-builder-app`, own run, per playbook (z)): S-15709 in `test/finish_drops_unlogged_sets_screen_test.dart`, Mock only, copying the finish harness of `test/session_finish_timers_test.dart`.
3. **Docs** (`crew-docs-keeper`) after both: the Docs delta rows.
4. Lead: full suite, scripted mutation pass (list below), review (`crew-reviewer`), fix rounds as closed briefs.

Exact production code (phase 1). In `lib/state/workout/session_core_lifecycle.dart`, inside the extension, directly after `endSession`:

```dart
  /// Plan 157a: Finish keeps only the sets that were logged (D-1..D-7).
  ///
  /// A `set` entry is logged exactly when an `EntryRest` sits at its position
  /// + 1 (the session screen's `_isSetLogged`); one carrying the skip marker is
  /// kept (it counts for nothing). Every other `set` entry is a planned set
  /// nobody did and goes, highest position first so the rests below it never
  /// move. A set exercise left with no entry is removed. Quiet: no listener is
  /// told here, `endSession` notifies once.
  Future<void> _dropUnloggedSets() async {
    for (final effortList in _efforts.values) {
      for (final effort in List<SegmentEffort>.of(effortList)) {
        if (effort.effortKind != 'set') continue;
        final rows = _observations[effort.id];
        if (rows == null) continue;

        final groups = EntryRows.setGroups(rows);
        final marked = {
          for (final rest in _timerManager.getEntryRests(effort.id))
            rest.entryIndex,
        };
        var kept = groups.length;
        var dropped = 0;
        for (var position = groups.length - 1; position >= 0; position--) {
          final group = groups[position];
          final skipped = group.rowFor(MetricIds.reps)?.valueBool ?? false;
          if (marked.contains(position + 1) || skipped) continue;

          final doomed = {for (final row in group.rows) row.id};
          for (final id in doomed) {
            await _repository.deleteObservation(id);
          }
          rows.removeWhere((row) => doomed.contains(row.id));
          await _timerManager.rekeyEntryRestsAfterDelete(effort.id, position);
          kept--;
          dropped++;
        }

        if (dropped > 0 && kept == 0) {
          await _repository.deleteEffort(effort.id);
          _observations.remove(effort.id);
          _timerManager.removeEffort(effort.id);
          effortList.removeWhere((e) => e.id == effort.id);
        }
      }
    }
  }
```

and in `endSession`, first line inside the `try {` (before `await _timerManager.persistActiveRounds();`): `await _dropUnloggedSets();`.

Note for the builder: `_efforts` values are `List<SegmentEffort>` lists mutated here, so iterate a copy of each list (done above) and do not iterate `_efforts.values` while removing from its lists beyond `removeWhere` on the current list (safe: the outer loop reads `effortList` only).

## Readers (tests that end a session and may read its sets)

Run these files in the builder's Done list (touched-tests run, never the full suite): `test/state_test.dart`, `test/data_tracking_fixes_test.dart`, `test/routine_session_modality_test.dart`, `test/session_edit_duration_test.dart`, `test/session_finish_timers_test.dart`, `test/pr4_session_controls_test.dart`, `test/watch_session_finish_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`, `test/watch_session_auto_push_test.dart`, `test/watch_session_end_owed_test.dart`, `test/session_window_never_inverted_test.dart`, `test/active_energy_lifecycle_test.dart`, `test/rating_first_answer_summary_test.dart`, `test/watch_timer_adoption_test.dart`, `test/watch_timer_push_test.dart`, `test/watch_logged_hold_stays_stopped_test.dart`. A fixture that adds sets with values, never logs them, ends the session and then reads the sets is a premise this change breaks: the fix is the fixture (log the set with `recordRestStart`), never the production rule.

## Mutation list (lead, scripted, one at a time)

(a) delete the `await _dropUnloggedSets();` line; (b) `marked.contains(position + 1)` to `marked.contains(position)`; (c) drop `|| skipped`; (d) iterate ascending; (e) remove `kept == 0` effort removal (set `dropped > 0 && false`); (f) drop `dropped > 0 &&`; (g) remove the `effortKind != 'set'` skip; (h) move the call before the `endedAtMs` early return; (i) delete the `rekeyEntryRestsAfterDelete` line; (j) remove the `!writeToHealth` clause; (k) remove the `wristSavesWorkout` clause; (l) remove the inbox clause; (m) remove the `try`/`catch` shield (D-10). Each must turn a named scenario red.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | MODIFIED | Marks session as ended: `endedAtMs` is `max(startedAtMs, now)` | Marks session as ended, after dropping every `set` entry no rest marks logged (plan 157a): `endedAtMs` is `max(startedAtMs, now)` | S-15701, D-1 |
| `docs/rest_tracking.md` | ADDED | - | Finish keeps only the sets a rest marks logged | S-15702, D-2 |
| `docs/session_summary.md` | ADDED | - | A set the user never logged is not stored at Finish | S-15708, D-1 |
| `docs/rest_tracking.md` | ADDED | - | A session the watch had a part in keeps its planned sets | S-15706, D-11 |

Stale-term sweep run (`grep -rIn "endSession\|planned set\|unlogged set" docs`, minus plans/history/releases): no other doc claims placeholders survive Finish.

## Open items (owner)

1. The Finish dialog still says "You have completed: N exercises" with N counting exercises that have no logged set. Make it count only exercises with a logged set? (changes a user-visible line; not done here).
2. A set with numbers typed but "Log Set" never tapped is dropped at Finish, like any other unlogged set (by the app's own definition of logged). No warning is shown. Want one?
3. Workouts the watch took part in keep counting their planned sets until 157d (D-11). How common is a watch-run workout for you? That decides how soon 157d should come.
4. Timed and round placeholders (D-4) are left alone; whether a never-started interval shows in any Stats figure is unchecked.

## Predicted files

`lib/state/workout/session_core_lifecycle.dart` (about +45 lines); new `test/finish_drops_unlogged_sets_test.dart`, `test/finish_drops_unlogged_sets_screen_test.dart`; three docs. Scope: one phase writes `lib/state/workout/session_core_lifecycle.dart` and `test/finish_drops_unlogged_sets_test.dart`; the screen-test phase writes only its own test file.

## Progress

- [x] Phase 1 production + state tests: built, then fix rounds 1b (read the store, shield), 1c (watch-linked sessions keep planned sets), 1d (four tests for surviving mutants); `finish_drops_unlogged_sets_test.dart` 33 green on Mock and Hive
- [x] Phase 2 screen test: S-15709 green (Mock)
- [x] Phase 3 docs: three docs applied, `plan-lint after` clean
- [x] Lead verification: analyze 181 (baseline 181, 0 errors); full suite 7547 passed, 5 skipped, 0 failed (third run; the first two had `pre_release_gate_*` failures from another session's scratch file and one yoga fixture, fixed)
- [x] Mutation pass: 25 mutants, 24 killed, 1 equivalent
- [x] Review: APPROVE WITH FIXES, 0 blocker, 0 major, 2 minor (docs sentence fixed; torn re-key recorded below)
- [ ] (owner) Device check: start a routine on the phone, log only the first set of one exercise, leave the rest untouched, Finish: the summary shows only that set and its volume; Stats shows that lift's Est. 1RM from that set alone

## Assumption Log

- 2026-11-13: base commit `cd117f79`; branch `claude_develop`; the tree also holds the other session's uncommitted plan 156 files (Swift and `ContentView.swift`), untouched here.
- 2026-11-13: the importer's wrist-only sessions are created by `_createSession` and never reach `endSession`; they hold only logged rows (scout sheet, importer lines 596-640).

## Feedback

(none yet)
- 2026-11-13: review minor 2 recorded, not fixed: if the store writes inside `rekeyEntryRestsAfterDelete` fail midway (it swallows its own failure, `timer_manager.dart:1198-1212`) a logged set above a dropped one can read unlogged after a reload. Same exposure as the existing `deleteEntry`; reached only when a repository write throws.
- 2026-11-13: fixtures edited to log their sets (assertions unchanged): `test/data_tracking_fixes_test.dart`, `test/state_test.dart`, `test/session_finish_timers_test.dart`, `test/pr4_session_controls_test.dart`, `test/watch_session_import_test.dart`, `test/health_yoga_kind_test.dart` (the last two by the lead).
