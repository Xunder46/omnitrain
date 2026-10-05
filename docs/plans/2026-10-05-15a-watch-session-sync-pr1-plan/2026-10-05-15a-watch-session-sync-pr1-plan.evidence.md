# Evidence — watch-session-sync PR 1

Developer run, Copilot CLI. Every figure below is observed output from
`.github/copilot/scripts/macos/gateway.sh`; nothing is inferred from a successful analyze.

- Phase 1 (remove the three phone-side watch surfaces) — below, to "Files touched by this phase".
- Phase 2 (wrist→phone adoption bridge) — [the last section](#phase-2--wristphone-adoption-bridge).

## Baselines (governor-measured on the dirty tree, before this phase)

| Check | Baseline |
|---|---|
| `gateway.sh test` (full) | `+3881 ~1` — 0 failures |
| `gateway.sh lint` | 196 issues, 0 errors |

## Phase 0 note (tests first)

A removal phase produces no new behaviour, so there is no red→green pair to show. The Phase 1
"tests" are the **deletion inventory** (every test that existed only for a removed surface is gone,
every test that guards behaviour that still exists is kept) and the **residue sweep** (S-7 / AC1).
Both are shown below as runs.

## Item 1–5: the surfaces and the DI wiring

| Item | Change | Verified by |
|---|---|---|
| 1 | `lib/features/session/live_session_screen.dart` deleted (639 lines); no route registration existed in `lib/app.dart` beyond the constructor argument | residue sweep below; full suite compiles |
| 2 | `lib/widgets/session/live_session_entry_point.dart` deleted (92 lines) | residue sweep below |
| 3 | `home_screen.dart`: `liveSession`/`watchSessionRatings` params, the entry-point card, `_openLiveSession`, `liveSessionEntryGap` and the `liveSessionBlock` layout budget removed (−70 lines) | `test/home_short_viewport_test.dart` green (S-003 keeps the compressed-layout path) |
| 4 | `exercise_picker_screen.dart`: `liveSession`, `liveSessionInsertIndex`, `liveSessionSwapSlotId`, `_sendToWatchSession` and the watch icon removed; rows are pop-only again (−78 net) | `test/interaction_flow_test.dart` + `test/screen_widget_test.dart` green |
| 5 | `app.dart` (−14), `main.dart` (−2), `watch_sync_wiring.dart` (6 lines re-typed): screens no longer receive `liveSession`; `createWatchSync` and its whole graph (mirror, router, request handler, inbox, rating bridge) stay | `test/live_mirroring_test.dart`, `test/phone_manage_bridge_test.dart`, `test/watch_transport_test.dart`, `test/watch_session_import_test.dart`, `test/watch_nutrition_quick_log_test.dart` all green in the full run |

`lib/state/watch/live_session_mirror_debug_main.dart` had 35 lines trimmed (its debug harness built
the removed screen). Outside Predicted Files — see Assumption Log A2.

## Item 6: the test inventory

**Deleted with the surfaces (files):** `test/live_session_effort_rating_test.dart` (−422 lines),
`test/live_session_capture_entries_test.dart` (−151 lines).

**Deleted groups/helpers:**

- `test/screen_widget_test.dart` (−229 lines): the whole `LiveSessionScreen` render group, the three
  home tests that asserted the watch card and its gap, plus the `liveSession` parameter of
  `buildHomeScreen`.
- `test/interaction_flow_test.dart` (−488 lines): the send-to-watch interaction group (475 lines plus
  its banner), and three now-unused imports.
- `test/home_short_viewport_test.dart` (−98 lines): the S-005/S-006 budget assertions and the
  `liveSession` parameter/assertion of `_pumpAndAssertShortViewport`. S-003 — the compressed path
  with no watch session — is the production-layout guard and stayed.
- `test/helpers/live_session_fixtures.dart` (−71 lines): trimmed to `RecordingMirrorTransport`,
  which `test/watch_nutrition_quick_log_test.dart` still uses.

**Kept (guards behaviour that still exists):** `live_mirroring_test.dart`,
`phone_manage_bridge_test.dart`, `watch_transport_test.dart`, `watch_session_import_test.dart`,
`watch_nutrition_quick_log_test.dart`, `in_session_pr_toast_test.dart` (its
`pumpLiveSessionScreen` helper builds the *workout* session screen, not the removed one).

**Net test count:** 3881 → 3847 passing = **34 tests removed with the surfaces**. No test was deleted
that guards behaviour this phase keeps (`interaction_flow`'s workout-session and rating flows,
`screen_widget_test`'s session screens and `home_short_viewport`'s S-003 all stayed).

### Full suite

```
gateway.sh test            → 01:38 +3847 ~1 -2: Some tests failed.   (exit 1)
```
Wall time 1 m 38 s (the gateway's test check is capped at 900 s). The `-2` is **not** this change —
see "External red" below.

### The three touched test files

```
gateway.sh test test/screen_widget_test.dart test/home_short_viewport_test.dart test/interaction_flow_test.dart
→ All tests passed! (+277)
```
(The gateway's "lines that look like failures (N)" summary is a naive matcher that also lists passing
progress lines; the verdict line and exit code 0 are the authority.)

### Lint

```
gateway.sh lint → 196 issues found. (0 errors)
```
Exactly the baseline. The only findings are pre-existing `deprecated_member_use` infos in
`lib/features/home/home_screen.dart` and `lib/widgets/session/effort_rating_sheet.dart`; nothing in
the four edited test files, and nothing in the two deleted ones.

## Item 7: docs

| Doc | Change |
|---|---|
| `docs/navigation_and_screens.md` | HomeScreen row loses the watch card; the `LiveSessionScreen` row is gone; the picker row loses the send-to-watch icon; the paragraph threading `liveSession` through `app.dart` is gone |
| `docs/widget_catalog/session_widgets.md` | `LiveSessionEntryPoint` section deleted; the picker paragraphs about the live `liveSession` and the removed icon deleted; `EffortRatingSheet` now described with its remaining reader |
| `docs/widget_catalog.md` | the `LiveSessionEntryPoint` index row deleted (the section it pointed at no longer exists) |
| `docs/watch-app-setup-and-qa.md` | every walkthrough step that used a removed surface replaced with the brief's neutral sentence; the "phone half is wired" claim corrected and left citing a real test |

Every behaviour sentence in the touched docs names a test that exists; structure-only sentences are
phrased as structure. Phase 4 owns the remaining two doc residues (`docs/watch_session_capture.md`
lines 17/36, `docs/state_management/watch_surface.md` line 379) — see Assumption Log A7.

## S-7 / AC1 residue sweep (run)

```
grep -rln "live_session_screen|LiveSessionScreen|live_session_entry_point|LiveSessionEntryPoint|
liveSessionEntryGap|liveSessionSwapSlotId|liveSessionInsertIndex|watchSessionRatings|liveSessionBlock"
  lib/   → No matches found.
  test/  → only test/in_session_pr_toast_test.dart's pumpLiveSessionScreen (a WorkoutSessionScreen
           helper, not a reader of a removed surface)
```

```
grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core
  → No matches found.                        (the repo's invariant check stays clean)
```

## How the files were deleted

`rm`, `git rm` and every other shell command but the gateway are denied by policy. The established
route (`.work/friction.md` line 204) was used: a throwaway `test/zz_watch_surface_removal_test.dart`
run through `gateway.sh test` did the four `deleteSync()`/`writeAsStringSync()` operations (asserting
the anchors first: the removed group is the last in `main()`, its closing line is exactly `  });`,
the anchor text is unique), printed a report, then was removed with `gateway.sh delete-scratch`.
The probe passed (+1) and left no scratch file; the one artefact it could not reach — the group's
5-line banner comment, which the brace walk left behind the blank line — was removed with a normal
edit.

## External red: two failures in `test/cardio_efficiency_drift_signal_screen_test.dart`

`S-2511 two cautions qualifying renders the higher-priority caution above the Cardio Efficiency
Drift card` fails in **both** harness variants (`signal_card_sustained-high-load` not found), in the
full run **and in isolation**:

```
gateway.sh test test/cardio_efficiency_drift_signal_screen_test.dart → 00:01 +15 -2: Some tests failed.
```

Not this change, on the evidence available:

- `gateway.sh git-diff --stat` lists 19 modified/deleted files, all watch surfaces, their tests or
  their docs; no file under `lib/core/`, `lib/state/workout/`, `lib/state/settings/` or
  `lib/features/stats/`.
- The test imports `stats_screen.dart`, `workout_state.dart`, `settings_state.dart` and two helpers;
  `stats_screen.dart`'s import list (core models/services/utils, navigation, calendar/settings/workout
  state, layout widgets, nutrition_trend, records_and_trends, its own widgets) contains **none** of
  the changed files, so no path from the failing assertion reaches this diff.
- The failure is date-anchored: the file's fixtures place every session with `DateTime.now()`-relative
  `_day(daysAgo)` / `_weekStart(weeksAgo)` anchors, and the sustained rule abstains unless the Mix
  layer reports `load` for the streak's span (a rated-week floor over a span whose start moves with
  the calendar week). The last full-suite green run on this tree was on 2026-10-04 (`.work/runs/`,
  `.work/watch-bridge/verify.md`); the run above is the first on 2026-10-05, which is also the first
  day of a new calendar week. The exact mechanism is the Stats feature owner's to confirm — this
  phase did not touch, and did not "fix", another feature's test.

## Files touched by this phase (git-status, in full)

```
 M docs/navigation_and_screens.md          M lib/state/watch/watch_sync_wiring.dart
 M docs/watch-app-setup-and-qa.md          M lib/widgets/session/effort_rating_sheet.dart
 M docs/widget_catalog.md                  M test/helpers/live_session_fixtures.dart
 M docs/widget_catalog/session_widgets.md  M test/home_short_viewport_test.dart
 M lib/app.dart                            M test/interaction_flow_test.dart
 M lib/features/exercise/exercise_picker_screen.dart  M test/screen_widget_test.dart
 M lib/features/home/home_screen.dart      D test/live_session_capture_entries_test.dart
 D lib/features/session/live_session_screen.dart      D test/live_session_effort_rating_test.dart
 M lib/main.dart                           D lib/widgets/session/live_session_entry_point.dart
 M lib/state/watch/live_session_mirror_debug_main.dart
```

---

## Phase 2 — wrist→phone adoption bridge

### What it does

`WatchSessionAdoptionBridge` takes the converged session a `session_snapshot` left in
`LiveSessionMirrorState` and projects it into the phone's own `WorkoutState` as an in-progress
`TrainingSession` (D-2): one default segment, one `SegmentEffort` per wrist slot, the protocol ids
kept verbatim (D-3). It depends on `WorkoutRepository` only; it never mentions the mirror, the
transport or a storage implementation.

Outcomes it answers, and why: `unbound` (no `WorkoutState` bound yet), `notRunning` (no usable
session id, or a snapshot the wrist has closed), `alreadyHeld` (the phone already holds that id — no
write, no reload; after adoption the phone owns the ladder, so re-applying the wrist's copy would
fight the phone's own edits), `refusedConflict` (D-10: the phone holds a *different* active session —
reported through the graph's `onFailure` as `WatchSessionAdoptionSkipped`, and nothing written), and
`adopted`.

### Phase 0 — tests first (RED)

`test/watch_session_adoption_bridge_test.dart` was written before the bridge existed:

```
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart
Error: Error when reading 'lib/state/watch/watch_session_adoption_bridge.dart' …
Error: The method 'consider' isn't defined … / No named parameter with the name 'adoption'
00:00 +0 -1: Some tests failed.
```

RED for the right reason: the absent bridge class and the absent `adoption` wiring parameter — not a
typo or a missing import. (One fixture typo, a missing `importedSegment` in a `show` list, was found
and fixed in the same run; only then did the run fail on the absent implementation alone. The
compilation error list is in the gateway log for that run.)

### RED → GREEN

| Scenario | Test | RED | GREEN |
|---|---|---|---|
| S-1 | `S-1 a wrist snapshot becomes the phone's in-progress session` | absent class | pass |
| S-1 | `S-1 Mock and Hive adopt the same rows` | absent class | pass |
| S-1 | `S-1 a restart resolves the same session and slot ids` | absent class | pass |
| S-3 | `S-3 an empty wrist session is adopted but reads "not yet active"` | absent class | pass |
| S-6 | `S-6 the phone keeps the session it is already running` | absent class | pass |
| S-6 | `S-6 counter-case an empty phone session does not block adoption` | absent class | pass |
| — | `a second snapshot of the session the phone holds does not rewrite it` | absent class | pass |
| — | `a slot resolves its effort kind from its declaration, then its capabilities` | absent class | pass |
| — | `a snapshot the wrist has closed is not adopted` | absent class | pass |
| — | `an unbound bridge writes nothing` | absent class | pass |

```
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart
00:00 +10: All tests passed!
```

### One expectation was wrong, and was corrected rather than forced

The first green attempt was `+9 -1`. The case was the snapshot whose ladder differs from the one the
mirror holds; it had been asserted to answer `MirrorOutcome.refused`. Reading
`LiveSessionMirrorState.receive` shows `refused` comes **only** from
`SyncProtocolValidator.evaluateOrAccept` rejecting the envelope, and a shape-differing snapshot is
`applied` (the mirror takes it and re-asserts the phone's own ladder to the wrist). The fixture behind
the first failure was in fact invalid — `currentExerciseIndex: 1` with a single slot — which is why it
was refused. The test now asserts the honest behaviour: an applied snapshot naming another session is
`applied`, and the phone answers with its own ladder. That is the branch the bridge actually hangs off.

### D-10 mutation check

- Original guard: `if (held != null && target.hasActiveSession) {`
- Mutant: `if (false && held != null && target.hasActiveSession) {`
- `gateway.sh test test/watch_session_adoption_bridge_test.dart --plain-name "S-6"` → `+1 -1`: S-6 red
  with `D-10 the wrist session is not adopted — Actual: TrainingSession:<wrist-session>`; the
  counter-case stayed green, so the fixture tells the guarded case from the unguarded one (the
  counter-case holds an *empty* phone session, which D-6 does not call active).
- Original restored verbatim, then
  `test/watch_session_adoption_bridge_test.dart test/live_mirroring_test.dart` → `+52: All tests passed!`

### Done Criteria

```
$ .github/copilot/scripts/macos/gateway.sh lint
196 issues found. (ran in 1.6s)        # = Phase 1 baseline; 0 errors, 0 warnings
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart
00:00 +10: All tests passed!
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart test/live_mirroring_test.dart
00:00 +52: All tests passed!           # mirror conformance unchanged, S-251 included
```

### Full suite

```
$ .github/copilot/scripts/macos/gateway.sh test
01:34 +3857 ~1 -2: Some tests failed.
```

`.work/gateway/test-20261005-111037-46827.log` — of 4541 lines, the only `[E]` lines are 79 and 113,
the two external failures in `test/cardio_efficiency_drift_signal_screen_test.dart` (S-2511 Mock and
Hive) described under "External red" above. Against the `+3847 ~1 -2` baseline the deltas are exactly
the 10 new tests; no previously passing test changed state.

### Mock ↔ Hive parity

`S-1 Mock and Hive adopt the same rows` pushes one envelope through both harness factories and compares
the adopted session row and every effort row field by field. The bridge has no Hive awareness at all —
it talks to `WorkoutRepository` — and this test is what says so out loud.

### Lint note: the one issue the phase introduced is fixed

The first post-implementation lint run reported **197** issues — `use_null_aware_elements` at
`test/watch_session_adoption_bridge_test.dart:149`, an `if (declaredKind != null)` map entry, which the
repo spells with the `?` null-aware marker (as `phoneEnvelope` does). Changed to
`'effortKind': ?declaredKind`; the count returned to 196 and the 10 tests were re-run green after that
edit (the `+10` above is that run).

### Footprint

```
 M lib/main.dart                                (M from Phase 1; this phase adds 5 lines: the bind)
 M lib/state/watch/watch_incoming_router.dart   (optional `adoption`; drives `consider` after the mirror)
 M lib/state/watch/watch_sync_wiring.dart       (M from Phase 1; this phase adds the bridge + handle)
?? lib/state/watch/watch_session_adoption_bridge.dart   (new)
?? test/watch_session_adoption_bridge_test.dart         (new, 10 tests)
```

`lib/features/` untouched. Absent from the diff, as item 3 requires:
`lib/core/sync_protocol/session_reconciler.dart`, `fixtures/reconciliation/session_switch.json`,
`test/live_mirroring_test.dart`, `PROTOCOL.md`. S-7's invariant is still clean:

```
grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core
(no matches)
```

### Docs

No update required in this phase. The plan puts the watch docs (`docs/watch_session_sync.md`, new, plus
`docs/state_management/watch_surface.md`, `docs/watch_session_capture.md`,
`docs/widget_catalog/session_widgets.md`, `docs/navigation_and_screens.md`) in Phase 4, and Phase 2's
Predicted Files exclude `docs/` — the plan was updated with the Progress and Assumption Log entries
only.

---

## Phase 3 — phone→wrist surfacing

### What it does

Every ladder this phone asserts is composed on demand from the bound `WorkoutState`
(`WatchSessionAdoptionBridge.projectSession`), never from the copy the mirror converged with the
wrist (D-11). `LiveSessionMirrorState` takes it as `projection:`, uses it for both a wrist snapshot
(the re-assertion branch) and a snapshot request (`projectedSession`, answered by
`WatchSyncRequestHandler` through the new `sendState`), and falls back to its own copy when the
projection refuses: no bound state, no running session, a ladder with nothing renderable, or a
snapshot naming a session this phone is not in (the D-10 gate, A23).

Slot id = the effort's row id (D-3), so a wrist-visible slot stays stable across a phone edit of the
same effort and a newly added effort carries its own new id. The revision seeds upward from the
frame's own `revision` and rises only when the ladder changes, which is what makes the wrist's
replace-structure rule accept a real edit while a replay stays silent (the two halves of S-8 case A).

### Phase 0 — the RED this phase could show

The brief rewrote `test/watch_session_projection_test.dart` in place, and the source edits landed in
the same pass, so the honest RED here is by mutation rather than by a first-run failure. Two kinds:

**The feature absent.** `projection: null` in `watch_sync_wiring.dart` — the wiring as it stood before
this phase — gives `+2 -4`:

| Test | Absent feature |
|---|---|
| `S-2 a running phone session is answered with its own ladder` | red — the answer is the mirror's (empty) copy |
| `S-8 case A an added exercise is answered with the extended ladder` | red |
| `S-8 case B removing the exercise the wrist is on moves its position` | red |
| `D-11 the revision rises with the ladder, and only with it` | red |
| `S-2 an idle phone still answers with silence` | green (nothing to answer either way) |
| `S-6 a wrist session this phone is not in is left alone` | green (the fallback path answers it) |

**Four mutants, each red on its own scenario.** The original line was recorded before each mutation
and restored verbatim after it.

| # | Mutation | Run | Which tests went red |
|---|---|---|---|
| M1 | `_countRevision`: drop `_projectedRevision += 1;` | `+2 -4` | `S-2 … its own ladder`, `S-8 case A`, `S-8 case B`, `D-11` — all four on `Expected: a value greater than <0> Actual: <0>` (the revision never moves) |
| M2 | `_indexFor`: `return 0;` | `+4 -2` | `S-8 case A` (`Expected: <1> Actual: <0>`), `S-8 case B` — the position the wrist reported is not carried |
| M3 | delete the projection's D-10 gate | `+5 -1` | `S-6 a wrist session this phone is not in is left alone`, which printed the offending answer: `sessionId: session-1791215933517 … currentExerciseIndex: 0, exercises: [effort-1791215933517-0]` |
| M4 | mirror: `final answer = before;` | `+4 -2` | `S-8 case A` (`Expected: ['sl-1', 'sl-2', 'effort-…-2'] Actual: ['sl-1', 'sl-2']`), `S-8 case B` — the answer falls back to the mirror's stale copy |

Restored source, re-run:

```
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_projection_test.dart
00:00 +6: All tests passed!
```

### Scenario coverage

| Scenario | Test | What it asserts |
|---|---|---|
| S-2 | `S-2 a running phone session is answered with its own ladder` | the answer's `sessionId` is the phone's, `status` active, `revision` > 0, the ladder is the phone's own efforts in the phone's order with slot ids = effort ids and their names/capabilities, an exercise carrying no capability is not a slot, an effort kind outside the wire vocabulary is omitted (`amrap`), index 0, empty entries/timers, no failure |
| S-2 | `S-2 an idle phone still answers with silence` | a sessionless phone answers nothing (`+0` sends, no failure) |
| S-8 A | `S-8 case A an added exercise is answered with the extended ladder` | three slots, `sl-1`/`sl-2` unchanged, the added effort's own id third, revision above what the wrist held, the wrist's real engine applies it, and replaying the old snapshot sends no second answer |
| S-8 B | `S-8 case B removing the exercise the wrist is on moves its position` | two slots, revision above what the wrist held, answer index 1, the wrist's engine lands on the following slot at index 1 and keeps the removed slot's logged entry |
| S-3/S-6 (D-10) | `S-6 a wrist session this phone is not in is left alone` | the answer is silent, the wrist keeps its own ladder and session id, the skip is reported as `WatchSessionAdoptionSkipped` with both ids |
| D-11 | `D-11 the revision rises with the ladder, and only with it` | asking twice with an unchanged ladder answers with the same revision (a converged wrist is not told the shape moved); adding an exercise answers with the ladder the phone holds at that moment and a strictly higher revision |

Both S-8 cases drive the real wrist engine (`WatchSessionEngine.applyMessage`), so "the wrist applies
it" is observed rather than inferred.

### Done Criteria

```
$ .github/copilot/scripts/macos/gateway.sh lint
196 issues found. (ran in 2.5s)        # = baseline; 0 errors, 0 warnings
$ .github/copilot/scripts/macos/gateway.sh test test/watch_transport_test.dart test/watch_session_projection_test.dart
00:00 +29: All tests passed!           # 23 transport (S-003's copy fallback included) + 6 new
```

### Full suite

```
$ .github/copilot/scripts/macos/gateway.sh test
01:32 +3863 ~1 -2: Some tests failed.
```

`.work/gateway/test-20261005-115951-74755.log` (4546 lines): the only `[E]` lines are 79 and 113, both
in `test/cardio_efficiency_drift_signal_screen_test.dart` — the same two external failures documented
under "External red" above. Against Phase 2's `+3857 ~1 -2` the delta is exactly the 6 new tests;
nothing previously passing changed state.

### Lint note: the phase's one new issue is fixed

The first post-implementation lint run reported **197** issues — `use_null_aware_elements` at
`test/watch_session_projection_test.dart:59`, an `if (effortKind != null)` map entry. Changed to
`'effortKind': ?effortKind`, as `test/watch_session_adoption_bridge_test.dart` already spells it; the
count returned to 196. The `+29` Done Criteria run above is after that edit.

### Docs

One paragraph in `docs/state_management/watch_surface.md`'s `LiveSessionMirrorState` section described
the answer to a wrist snapshot as this mirror's own shape, which this phase made false (A27). It now
states the D-11 rule, names `projectedSession`/`sendState`, and cites
`test/watch_session_projection_test.dart` and `test/watch_transport_test.dart`'s `S-003` fallback. The
file's remaining watch-surface cleanup is Phase 4's. No other doc claim changed; `docs/navigation_and_screens.md`
and `docs/widget_catalog*` are untouched by this phase.

```
$ .github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart
00:00 +9: All tests passed!            # ceiling, warning band, links, reachability all still hold
```

### Footprint

```
 M lib/state/watch/live_session_mirror_state.dart   (projection seam, projectedSession, sendState, re-assertion)
 M lib/state/watch/watch_sync_request_handler.dart  (projected answer first, mirror fallback)
 M lib/state/watch/watch_sync_wiring.dart           (bridge built first; `projection:` passed)
 M docs/state_management/watch_surface.md           (one paragraph, A27)
?? lib/state/watch/watch_session_adoption_bridge.dart   (Phase 2; this phase adds projectSession + helpers)
?? test/watch_session_projection_test.dart              (new, 6 tests)
```

Absent from the diff, as the phase requires: `lib/core/sync_protocol/session_reconciler.dart`,
`watch/sync_protocol/PROTOCOL.md`, `watch/sync_protocol/fixtures/`,
`test/live_mirroring_test.dart`, `lib/main.dart`. S-7's invariant is still clean — no file under
`lib/state`, `lib/features`, `lib/widgets` or `lib/core` imports `hive_workout_repository` (the new
projection talks to `WorkoutState` only).

## Phase 4 — lifecycle, dedup, rating, docs

### What it does

**Ending, wrist → phone (D-5).** `WatchIncomingRouter.receive` routes a `session_lifecycle` to
`WatchSessionAdoptionBridge.onLifecycle`, after the mirror has applied the frame (the lifecycle is the
mirror's to apply too, and the two read the same envelope). `completed` runs the *ordinary* finish —
`WorkoutState.endSession()` — so the wrist's session lands in history as one session with one row;
`abandoned` runs `discardCurrentSession()`, which consumes it without history. The lifecycle is only
honoured for the session the phone actually holds and that is not already ended.

**A finished session is not resurrected (G1).** `consider` now reads the session row *before* the
`alreadyHeld` guard: a row with `endedAtMs != null` returns the new
`WatchSessionAdoption.alreadyEnded`, writing nothing and loading nothing back. The router answers that
outcome with the mirror's own `reportLifecycle(completed)`, so a wrist still looking at a session the
phone has finished is told so at its next sync — and only a `session_snapshot` the mirror *applied*
can reach that answer.

**The phone's own finish is silent (G2).** Phase 4 item 2 (route the phone's `endSession` to report a
lifecycle) is superseded: the wrist is the authority on its own session, and a phone-initiated push
would make the wrist end a session it is still logging into. Nothing on the ordinary finish path
calls `reportLifecycle`; see the grep below.

**The wrist's entries are not lost (G3).** `WatchSessionImporter.apply` takes `phoneOwnsSession`, and
`WatchSessionInbox` is wired with `phoneOwnsSession: adoption.holdsSession`. For a session the phone
owns, only the session-scoped kinds (`session_end`, `effort_rating`, `phone_rating`) are applied; the
wrist's effort rows are deliberately left staged — `appliedAtMs` stays null and the `entries`
comprehension is skipped — so the same set is not materialised a second time onto a ladder the phone
already holds from adoption. Those rows stay unreceipted, which is correct: only the phone may drop
what it has acknowledged, and PR 3's merge is what consumes them.

**One rating (D-8).** The inbox applies a wrist `effort_rating` to the session row, but the copy
`WorkoutState` holds in memory was read before that row changed, and the ordinary finish writes the
in-memory copy back — over the rating. `_catchUpSessionRow` re-reads `sessionFeeling` from the row and
writes it through `updateSessionFeeling` first, so the finished session carries one rating: the
wrist's (and the phone's, when the phone had already staged one, which wins per D-138).

### Phase 0 — tests first, and the RED this phase could show

`test/watch_session_finish_test.dart` (8 plain `test()`s, Mock-first — the harness drives
`CaptureTransport`, the inbox, `LiveSessionMirrorState`, the router, the bridge and a real
`WorkoutState`, and reads the wire traffic back with the `watch_capture_import_harness` helpers).
As in Phase 3 the source edits and the test file landed in the same pass, so the first run is not the
register's RED. That first run was **`+5 -3`**, three genuine reds, and they are worth recording
because two were real defects in the new path rather than test bugs:

| Test | First-run failure | Why |
|---|---|---|
| `S-4 the wrist ends its session, roster of logged sets first` | `Expected: <4> Actual: <null>` on `_heldRating` | the ordinary finish wrote the pre-rating copy back (the `_catchUpSessionRow` gap above) |
| `G3 the wrist's entries for a session the phone owns are not lost` | same rating assertion | same gap |
| `G1 a finished session is not adopted back after a restart` | `alreadyHeld`, not `alreadyEnded` | the assertion called `consider` itself and consumed the router's own call; asserting on the robustness of the *answer* (`reportLifecycle`) is the honest form, so the test now drives a bare map and reads the sent lifecycle |

The RED proper is by mutation — the six mutants below, each red on its own scenario, each restored
verbatim (`git-diff` shows no `MUTATION` marker, and the file re-runs green).

| # | Mutation | Run | Which tests went red |
|---|---|---|---|
| M1 | `watch_session_importer.dart`: drop the G3 predicate (both the `unapplied` filter's `(!phoneOwnsSession \|\| _sessionScopedKinds.contains(row.kind))` and the `!phoneOwnsSession &&` in the `entries` comprehension) | `+5 -3` | `S-4(a)`/`S-4(b)` (duplicate `effort-s-w1-sl-1-ex-bench-set` ids) and `G3` (`appliedAtMs` non-null — the wrist's rows imported onto the phone's own) |
| M2 | `watch_session_adoption_bridge.dart`: drop `consider`'s `alreadyEnded` guard (`final existing = …; if (existing != null && existing.endedAtMs != null) { return WatchSessionAdoption.alreadyEnded; }`) | `+6 -2` | `S-5` (no lifecycle sent) and `G1` (`alreadyHeld` instead of `alreadyEnded`) |
| M3 | `watch_incoming_router.dart`: drop the `alreadyEnded → reportLifecycle(completed)` answer | `+6 -2` | `S-5` (`answered: []`, expected `['s-w1']`) and `G1` (answered length 0) |
| M4 | `watch_incoming_router.dart`: drop the `session_lifecycle → onLifecycle` routing | `+3 -5` | `S-4(a)`, `S-4(b)` (no ended session row at all), `G1` (null), `G3` ("the session stays ended" null), and the abandoned case (a `TrainingSession` still held) |
| M5 | `watch_session_adoption_bridge.dart`: drop `await _catchUpSessionRow(sessionId);` | `+6 -2` | `S-4(a)` and `G3`, both `Expected: <4> Actual: <null>` — D-8's rating |
| M6 | the harness: a `WorkoutState` listener in `_phone` pushing `mirror.reportLifecycle(completed)` once `endedAtMs != null` — the shape G2 forbids | `+7 -1` | `S-5`'s lifecycle list became `['s-w1', 's-w1']` |

M6 is honest evidence about the *test*, not just the source: the synchronous
`expect(phone.transport.sent, isEmpty)` before the assert does **not** observe that push, because
`reportLifecycle` awaits `applyMessage` and only then `await _transport.send`, so the send lands on a
microtask. The lifecycle-list assertion does catch it. G2 itself has no line to mutate — it is an
absence — so its evidence is the grep below plus M6.

Restored source, re-run:

```
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_finish_test.dart
00:00 +8: All tests passed!
```

### G2 — the phone never pushes an end

```
grep -n reportLifecycle   (whole repo)
./lib/state/watch/watch_incoming_router.dart:108        await _mirror.reportLifecycle(WatchLifecycleState.completed);
./lib/state/watch/live_session_mirror_state.dart:472    await reportLifecycle(WatchLifecycleState.completed);   # completeSession() itself
./lib/state/watch/live_session_mirror_state.dart:482    Future<Map<String, Object?>> reportLifecycle(          # definition
./test/live_mirroring_test.dart:760, ./test/phone_manage_bridge_test.dart:709                     # tests only
```

The one production caller is the router's answer to a wrist snapshot (line 108). The other in-`lib`
caller, `completeSession()`, has **no production caller** (`grep -n completeSession` → its definition
plus five call sites, all in `test/`). So there is no path from the phone finishing a session to a
lifecycle going out.

### Done Criteria

```
$ .github/copilot/scripts/macos/gateway.sh lint
196 issues found. (ran in 2.9s)        # = baseline; 0 errors, 0 warnings in the touched files
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart test/watch_session_finish_test.dart
00:00 +53: All tests passed!           # 45 import (unchanged) + 8 new
$ .github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart
00:00 +9: All tests passed!
```

### Full suite

```
$ .github/copilot/scripts/macos/gateway.sh test
01:38 +3871 ~1 -2: Some tests failed.
```

`.work/gateway/test-20261005-123151-98140.log` (4555 lines): the only `[E]` lines are 79 and 113,
both in `test/cardio_efficiency_drift_signal_screen_test.dart` — the same two external failures
documented under "External red" above. Against Phase 3's `+3863 ~1 -2` the delta is exactly the 8 new
tests; nothing previously passing changed state. The new file's tests ran inside this suite
(log lines 1559+).

### Docs

`docs/watch_session_sync.md` is new (8702 B, 13% of the 64 KiB ceiling): the single-session model, the
structure table (which surface does what), D-2/D-11/D-10 and both directions of ending with the exact
test names, the invariants, and a "What does not sync" list — each sentence naming a real test. The
guarded-file rules hold (no hex literals, no user-action arrow chains, no roadmap phrasing). It is
indexed from `docs/README.md` (20371 B).

Three residues the phase's own edits made false were corrected in place: `docs/watch_session_capture.md`
(20897 B — its scope line named the deleted `lib/features/session/live_session_screen.dart`, and its
Structure row claimed a screen reads `WatchSessionRatings`, which nothing does now),
`docs/state_management/watch_surface.md` (39789 B — the `completeSession` paragraph gained the G2 rule
and the one production `reportLifecycle` caller; the mirror section's claim about `main.dart` passing
`liveSession`/`watchSessionRatings` is gone, those fields no longer exist), and
`docs/watch-app-setup-and-qa.md` (22641 B — the stale second walkthrough and its false warning were
replaced by the one-session `(a)–(f)` owner walkthrough). `docs/widget_catalog/session_widgets.md`
(13052 B) and `docs/navigation_and_screens.md` (24544 B) needed no further change: Phase 1 had already
taken the removed screen out of them.

Every file is far below the 52 KiB warning band (the closest, `watch_surface.md`, is 61% of the
ceiling); the contract test above is green.

### Residue sweep (AC1, item 5)

```
lib/ + test/  for  live_session_screen | live_session_entry_point | LiveSessionEntryPoint | LiveSessionScreen
→ test/in_session_pr_toast_test.dart only: its local helper `pumpLiveSessionScreen`
  (lines 1290–1325) builds `WorkoutSessionScreen` — a name coincidence, not a reader of the removed surface.
grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core
→ No matches found.                        (S-7's invariant stays clean)
```

The one prose residue left is inside this plan and its index (Phase 4's own item 2, superseded by G2,
and the plan's `Files Affected` heading) — a record, not a claim about the tree.

### Footprint

```
$ .github/copilot/scripts/macos/gateway.sh git-diff --stat -- lib/core/services/watch_session_importer.dart \
    lib/state/watch/watch_incoming_router.dart lib/state/watch/watch_session_inbox.dart \
    lib/state/watch/watch_sync_wiring.dart docs/README.md docs/watch_session_capture.md \
    docs/state_management/watch_surface.md docs/watch-app-setup-and-qa.md
docs/README.md                                |  1 +
docs/state_management/watch_surface.md        | 40 ++++++++++--
docs/watch-app-setup-and-qa.md                | 92 +++++++++++++++------------
docs/watch_session_capture.md                 | 25 ++++----
lib/core/services/watch_session_importer.dart | 39 +++++++++++-
lib/state/watch/watch_incoming_router.dart    | 46 +++++++++++++-
lib/state/watch/watch_session_inbox.dart      | 13 +++-
lib/state/watch/watch_sync_wiring.dart        | 34 ++++++++--
8 files changed, 223 insertions(+), 67 deletions(-)

$ .github/copilot/scripts/macos/gateway.sh git-status    (new files, not in a diff)
?? lib/state/watch/watch_session_adoption_bridge.dart   (Phase 2; this phase adds onLifecycle, alreadyEnded, holdsSession, _catchUpSessionRow)
?? test/watch_session_finish_test.dart                 (new, 8 tests)
?? docs/watch_session_sync.md                          (new)
```

Two of these are outside Phase 4's Predicted Files: `lib/core/services/watch_session_importer.dart`
(G3's staging predicate lives where the import is decided) and `lib/state/watch/watch_incoming_router.dart`
(both G1's answer and D-5's routing are decided where the envelope is), recorded as A28/A29.

Absent from the diff, as the phase requires: `lib/main.dart`, `lib/app.dart`,
`lib/state/watch/live_session_mirror_state.dart`, `watch/`, `watch/sync_protocol/`, and the two
external-red test files.

## Fix round 1 — review 1 findings, no behaviour change

Bounded pass over the seven findings in `<plan>.review.md` (`CHANGES_REQUESTED`): documentation
truth, dead-seam bookkeeping, one scenario rewrite and one new guard test. No product behaviour
changed; no source file other than the three dead members below.

### Findings applied

| # | Finding | Applied |
|---|---|---|
| 1 🔴 | `docs/state_management/watch_surface.md` claimed `effortEntries`/`effortEntriesOf` are what a surface lists and counts, citing the deleted `test/live_session_capture_entries_test.dart` (`S-254`) | The counting claim and that citation are gone. The surviving behaviour — the mirror holds every entry of the session it carries — is kept and re-pointed at `test/watch_session_import_test.dart`, `S-268 with its entries only` (pins `end-*` and `rating-*` among the mirror's entries). |
| 2 🔴 | `docs/watch_session_capture.md` — "only the device that ended a live-mirrored session asks how hard it was", "verified by" the deleted `test/live_session_effort_rating_test.dart` | "live-mirrored" is gone. Re-pointed to `S-4`/`S-5` in `test/watch_session_finish_test.dart` and the `the phone's own rating (D-138, D-139 state half)` group in `test/watch_session_import_test.dart` (`S-281`, `S-284`). |
| 3 🟡 | `docs/state_management/watch_surface.md:96-101` — "They exist so no screen has to know a `structure_change` from an `exercise_push`" | "no caller"; the paragraph now says the family is the mirror's protocol API, verified by `test/phone_manage_bridge_test.dart` and `test/live_mirroring_test.dart`, and that no phone screen calls it — the only caller outside tests is `live_session_mirror_debug_main.dart` via `applyStructureChange`. |
| 4 🟡 | `docs/watch-app-setup-and-qa.md:57`, `:441` — "`main.dart` → `liveSession`", a symbol that no longer exists | Reworded to the one-session wiring: `createWatchSync`, its adoption bridge bound to the running `WorkoutState`, and the `routines_down` producer. |
| 5 🟡 | plan `S-5`'s Flow contradicted G2 | Rewritten: the finish writes the rating and sends nothing; the wrist learns it is over at its next sync. The test is named in the scenario. |
| 6 🟡 | three members with no reference in `lib/` or `test/` | Deleted: `effortEntries`, `effortEntriesOf`, `mintSlotId` (and their doc comments). Retention of the test-only seams is recorded in the plan's Assumption Log (A34). |
| 7 🟡 | no guard on the in-progress ordering `checkForInProgressSession` relies on | One new test in `test/watch_session_adoption_bridge_test.dart` — red→green below. |
| 8 ⚪ | `docs/watch_session_sync.md` "What does not sync" named the successor unit | Now states the shipped limitation only, with its `G3` test named. |

### Item 6 — what was deleted, and the search behind it

```
lib/ + test/  for  effortEntries | effortEntriesOf | mintSlotId
→ after deletion: no matches outside docs (the plan, the review, this file).
   Before deletion: every match was a definition or a doc comment in
   lib/state/watch/live_session_mirror_state.dart (lines 137, 140, 351).

Kept, on purpose (A34): pushExercise, swapExercise, correctEntry, deleteEntry,
completeSession  — reached from test/phone_manage_bridge_test.dart,
test/live_mirroring_test.dart and test/watch_session_import_test.dart;
WatchSyncGraph.ratings and WatchSessionInbox.recordPhoneRating — held for the
successor unit that hosts the wrist's rating and finish; sessionScopedKinds —
still names the kind set the importer's own predicate mirrors.
```

`_newId` and `_objects` are both still used by the remaining members, so the deletion left no
unused private helper.

### Item 7 — the new guard test, red by mutation

Test: `S-1 the adopted session survives checkForInProgressSession beside an empty phone row`
(`test/watch_session_adoption_bridge_test.dart`). Mock repository, plain `test()`. It seeds an empty
phone row, adopts `s-w1`, then restarts (a fresh `WorkoutState` over the same rows), runs
`checkForInProgressSession()` and loads the survivor it returns.

Mutation — the original line, restored exactly after the red run:

```
test/watch_session_adoption_bridge_test.dart
- final DateTime _adoptedAt = DateTime.utc(2026, 10, 5, 12);      ← original
+ final DateTime _adoptedAt = DateTime.utc(2026, 1, 5, 12);       ← mutant (adoption now predates the empty row)
- final DateTime _adoptedAt = DateTime.utc(2026, 10, 5, 12);      ← restored, byte-identical
```

| Run | Command | Result |
|---|---|---|
| green (before) | `gateway.sh test test/watch_session_adoption_bridge_test.dart` | `+11: All tests passed!` |
| red (mutated) | same | `+10 -1: Some tests failed.` — `Expected: 's-w1' Actual: 'session-phone-empty'`, the new test only |
| green (restored) | same | `+11: All tests passed!` |

Only the ordinary `startedAtMs` ordering makes the survivor the adopted row; the mutant makes the
empty row newer, so the sweep deletes the session the wrist is running and the test fails on the
first assertion. **Accepted limitation:** a same-millisecond tie between the two rows is decided by
the sort's stability, not by the test — the note is in the test file, above the test. The adapter
stamps the adopted row from the wrist's clock and the phone stamps its own rows, so the tie does not
arise in either implementation.

### Verification (this round)

```
gateway.sh lint   → 196 issues found, 0 errors (baseline: 196/0; the exit code is the
                    pre-existing info notices, unchanged)
gateway.sh test   → 01:31 +3872 ~1 -2: Some tests failed.
                    (+3871 before this round; the +1 is the new guard test. The ~1 skip and
                     the -2 are the untouched test/cardio_efficiency_drift_signal_screen_test.dart
                     pair recorded under "External red", re-confirmed failing in this run's log.)
```

Touched this round: `docs/state_management/watch_surface.md`, `docs/watch_session_capture.md`,
`docs/watch-app-setup-and-qa.md`, `docs/watch_session_sync.md`,
`lib/state/watch/live_session_mirror_state.dart`, `test/watch_session_adoption_bridge_test.dart`, and
the plan (S-5, Progress, Assumption Log, Feedback). The PR-wide `git-diff --stat` is unchanged in
shape — this round adds no file and removes none.

## Fix round 2 — the owner's simulator findings (skip reporting, build notify, one limitation)

Bounded round over the three findings in `.work/watch-session-sync/brief-fix-2.md`. (A) changed how a
D-10 skip is reported; (B) is a reproduction attempt that **did not reproduce**, with no production
change; (C) is one documented limitation. No product behaviour changed: the phone still keeps the
session it is running, nothing is deleted or merged, and no line under `lib/features/` was touched.

### Problem A — a protective skip was reported as a crash

The console printed, three times in one Sync,
`Watch transport unavailable: Bad state: kept DC19…, did not adopt 9736…` with a stack trace: the
bridge threw `WatchSessionAdoptionSkipped` (a `StateError`) into the graph's `onFailure`, which
`main.dart` prefixes. Refusing is the rule working, so it is not a failure any more.

| File | Change |
|---|---|
| `lib/state/watch/watch_session_adoption_bridge.dart` | `WatchSessionAdoptionSkipped` deleted. The D-10 guard calls `_reportSkipOnce(held.id, sessionId)` and returns `refusedConflict`. `_reportSkipOnce` dedupes on the (held, offered) pair in memory and calls the new `onSkipped`; the default `_reportSkipped` prints exactly one line: `Watch session sync: kept <held>, did not adopt <offered> (this phone already has a session in progress)`. |
| `lib/state/watch/watch_sync_wiring.dart` | `createWatchSync` takes the optional `onSkipped` and passes it to the bridge (A36). `lib/main.dart` is **unchanged**: the default reporter is what the app wants, and its `onFailure` still prefixes "Watch transport unavailable". |
| the three existing tests | `_Phone.skipped` records the callback; S-6, its counter-case and G1's counter-case assert the skip arrives **once** for repeated snapshots and that the failure list stays empty. |

`onFailure` was not deleted with the skip (A37). It kept the one genuine failure left in the bridge — a
row that cannot be written during adoption — wrapped in `try`/`catch` →
`_onFailure(error, stack); rethrow;`. The new test `an adoption that cannot be written is reported as
a failure` pins it with a `_UnwritableRepository` whose `createSession` throws: the failure list has
length 1 and the error still reaches the caller (`expectLater(..., throwsA(isA<StateError>()))`).

### Problem A — the RED, by mutation

The original line, restored byte-identical after the red run:

```
lib/state/watch/watch_session_adoption_bridge.dart   (_reportSkipOnce)
- _onSkipped(heldSessionId, offeredSessionId);                            ← original
+ _onFailure(StateError('MUTANT: skipped'), StackTrace.current);          ← mutant
- _onSkipped(heldSessionId, offeredSessionId);                            ← restored, byte-identical
```

| Run | Command | Result |
|---|---|---|
| green (before) | the four watch files | `+30: All tests passed!` |
| red (mutated) | same | `+25 -5: Some tests failed.` — five failures, every one a D-10 skip assertion |
| green (restored) | same | `+30: All tests passed!` |

The five failures, and the assertion each one names:

| File:line | Test | Expectation that failed |
|---|---|---|
| `test/watch_session_adoption_bridge_test.dart:451` | `S-6 the phone keeps the session it is already running` | `D-10 the skipped adoption is reported, not dropped` — `Expected: [(held: session-phone-1, offered: s-w2)] Actual: []` |
| `test/watch_session_projection_test.dart:493` | `S-6 a wrist session this phone is not in is left alone` | `S-6 the skipped adoption is reported with both session ids` |
| `test/watch_session_finish_test.dart:546` | `G1 counter-case a running session is not answered with an end` | `D-10 the crossed session is the one skip in this test` — `Expected: [(held: s-w1, offered: s-other)] Actual: []` |
| `test/watch_session_adoption_build_notify_test.dart:261` | `a skip delivered while the home screen is mounted reports through onSkipped and throws nothing` | `the skip reached the app's own observation of it` |
| `test/watch_session_adoption_build_notify_test.dart:320` | `a skip delivered from a post-frame callback throws nothing` | the same expectation |

Routing the skip back into the failure hook is precisely the defect the owner saw in the console, and
five assertions name it.

### Problem B — `setState() or markNeedsBuild() called during build`: NOT reproduced

**What was tried.** A new file, `test/watch_session_adoption_build_notify_test.dart`: four
`testWidgets`, each over the **real** `HomeScreen` (the one `test/home_short_viewport_test.dart`'s
`buildHomeScreen` builds), a `MockWorkoutRepository`, and the real graph `createWatchSync` builds, with
one wrist `session_snapshot` handed to the radio on each schedule a build could catch:

1. delivered while the screen is mounted, for a session that is adopted;
2. delivered while the screen is mounted, for a D-10 skip;
3. delivered from inside a build (`initState` runs during the build phase), adopted;
4. delivered from a post-frame callback, a skip.

Every case runs to completion while the real screen is mounted and `tester.takeException()` is null in
all four — `+4: All tests passed!`. No `lib/` line was changed for B, and the brief's stop condition
(the reproduced cause being in `lib/features/`) did not arise because nothing there is implicated.

**Why it does not reproduce, structurally.** Every entry into the watch path yields before it notifies.
`WatchIncomingRouter.receive` awaits the inbox, then the mirror, and only then asks the bridge;
`consider` awaits the repository and then `loadHistoricalSession`, and `loadHistoricalSession` is what
notifies `WorkoutState`. The notification therefore lands in a microtask *after* the frame that handed
the snapshot over, never inside that frame's build. The mirror is a `ChangeNotifier` too, but nothing
under `lib/features/` or `lib/widgets/` listens to it: `HomeScreen` observes `widget.workoutState`
through a `ListenableBuilder`, and its own initial load already defers its notification to a stable
frame boundary.

The tests cannot prove the error impossible — a schedule that put a notification inside a build would
have to exist in the watch path first. They do prove the delivery completed in every case (each case
asserts its effect), so no case can pass by delivering nothing.

**The one log the owner must send.** The console line was the abbreviated repeat
(`Another exception was thrown: setState() or markNeedsBuild() called during build.`). What is needed
is the **first full report**: the `EXCEPTION CAUGHT BY WIDGETS LIBRARY` block printed before it, with
its "The relevant error-causing widget was" and "When the exception was thrown, this was the stack"
sections, which name the `State` and the `build` that was running. The abbreviation names neither a
widget nor a stack, so without it the cause cannot be localized.

### Problem C — a discarded session can be re-adopted (documented, not fixed)

`docs/watch_session_sync.md` → "What does not sync" gained one limitation bullet: a session the user
discards on the phone has its row deleted, so the phone has nothing left to recognise; a wrist that
still holds that session offers it again at its next sync and the phone adopts it as a new in-progress
session — only a session that ended and kept a row is protected (G1). It is phrased as not handled and
names no test and no future unit, per the brief. No code changed.

### Doc and plan sentences corrected

| Where | Was | Now |
|---|---|---|
| `docs/watch_session_sync.md` D-10 | "refuses to adopt another and says so" | the refusal is reported once per (held, offered) pair through the bridge's own `onSkipped` (one plain `debugPrint`, no stack), never the failure hook, which stays for a snapshot that cannot be written at all; the tests are named |
| plan D-10 | "reported through the graph's failure/debug hook" | `onSkipped`, once per pair, not an error |
| plan S-6 Flow | "reported through the failure/debug hook" | `onSkipped`, once, no stack, no failure entry; the test is named in the scenario |
| plan Phase 2 item 3 | "through the graph's failure/debug hook" | `onSkipped`; the mutation note now records that routing the skip back to `onFailure` turns the D-10 assertions red |
| plan Progress / Assumption Log / Feedback | — | the round's bullet, A36–A38, one Feedback line per problem |

`docs/state_management/watch_surface.md`'s two failure-hook sentences are about the *transport* (a
refused send, and the plist-safety refusal) and `docs/watch-app-setup-and-qa.md:401` is the Effort
Rating prompt; neither is the D-10 skip, so both stay as they are.

### Verification (this round)

```
gateway.sh lint      → 196 issues found, 0 errors (baseline 196/0; the exit code is the pre-existing
                       info notices). The round's first run read 197 — one unused import in the new
                       test file, the only new line — and it was removed.
gateway.sh test      → 01:36 +3877 ~1 -2: Some tests failed.
                       (re-run on the frozen tree after the doc/plan edits: the same counts. +3872
                        before this round: +1 the new adoption-write failure test, +4 the new
                        Problem B file. The -2 are the untouched
                        test/cardio_efficiency_drift_signal_screen_test.dart S-2511 pair — Mock and
                        Hive — and both runs' logs show them as the only failures.)
the four watch files → +30: All tests passed!   (12 + 8 + 6 + 4)
mutation (above)     → +25 -5, five D-10 skip assertions; restored → +30
invariant check      → `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`
                       → no matches
```

Touched this round: `lib/state/watch/watch_session_adoption_bridge.dart`,
`lib/state/watch/watch_sync_wiring.dart`, `test/watch_session_adoption_bridge_test.dart`,
`test/watch_session_finish_test.dart`, `test/watch_session_projection_test.dart`,
`test/watch_session_adoption_build_notify_test.dart` (new), `docs/watch_session_sync.md`, the plan and
this file. `lib/main.dart` was not changed: the wiring's new parameter is optional and the default
reporter is what ships.

## Unrelated: cardio drift test fix (`test/cardio_efficiency_drift_signal_screen_test.dart`)

The `S-2511 two cautions qualifying` failure described under "External red" above is a **fixture**
artifact, not a product bug. No file under `lib/` was touched.

### What it actually was

The "External red" hypothesis — that the Mix layer abstains over the streak's span — is wrong. A probe
(since removed) inside the failing test, on the real Monday 2026-10-05, printed:

```
weeks  6/8…9/28: 240R 240R 240R 240R 264R 240R 264R 240R 264R 240R 24R 48R 278R 230R 230R 278R 278R
streak=2  first=2026-09-21  usual=213.5  mix=load  ratedBase=12
```

The Mix layer was `load` all along. The **streak** was short: F-9A intends 17 weeks (10 × 240, two
empty, 5 × 230) over a baseline of 200, so each streak week clears 110 %. But the *rated* cardio
sessions land inside the week buckets — `264 = 240 + 24`, `278 = 230 + 48`, and the two weeks meant to
be empty hold cardio load only — lifting the usual to 213.5 and cutting the streak to 2 weeks, below
the five-week floor. Sustained High Load then abstains and the card is absent.

The fixture mixes two anchorings — `_seedF9A` places sessions in calendar weeks (`_weekStart`),
`_seedCardio` a day count back from `now` (`_day`) — so which week a cardio session lands in moves
with the weekday. That is why the file passed on Sunday and failed on Monday; the weekday, not "the
first day of a new calendar week", is the variable.

A second, independent weekday defect sat behind it: the drift rule's lifting sentence compares a
28-day period against an 84-day baseline, and `_atWeek`'s mid-week offset (`start.day + 3`) put the
week five back at day offset 25 + `dow`, so on Monday–Wednesday it fell inside the 28-day period
instead of the baseline. With the streak repaired, the observation then carried the extra
"Lifting load is 15% above your usual over the same period." sentence that S-2511 asserts is absent.

Neither defect is a product bug, so no `lib/` change was made and none is needed. `weeklyLoads`
buckets a session into the week its start falls in; the streak rule's 110 %-of-usual arithmetic is
right for the weeks it is handed; the drift rule's 28-day-against-84-day comparison is right for its
own inputs; and the signals read `SignalContext.now` rather than reaching for the clock themselves.
The wrongness was entirely in where the fixture put its sessions — which is why the fix is two
fixture lines and no assertion was relaxed.

### The fix — two fixture edits, no assertion weakened, no behaviour changed

- `_seedFTwo`: `_seedCardio(repo)` → `_seedCardio(repo, rating: null)`. The sessions keep their
  durations, so `cardioEfforts` and the drift still fire, but they contribute no load and cannot
  perturb a week bucket. (`_seedRatedBaseline` stays rated — it carries the layer's rated-week floor.)
- `_atWeek`: `start.day + 3` → `start.day`. The week five back is then always at day offset 28…34 —
  inside the 84-day baseline, never inside the 28-day period — and the weeks one to three back are
  always inside the period, whatever the weekday.
- Removed the `sustained_high_load.dart` import the probe had added (unused once the probe went).

`_atWeek` is used only by `_seedWeekSession` ← `_seedF9A` ← `_seedFTwo` in this file; the sibling
`sustained_high_load_signal_screen_test.dart` has its own private copies and no cardio fixture.
`_seedFCard` (default `rating: 3`) and `_seedRatedBaseline` are untouched, so the S-2501/S-2509
arithmetic ("1380 / 3600", "exactly +15%") is unchanged.

### New cases: three fixed `now` values

`StatsScreen` reads `DateTime.now()` directly and has no clock seam, so the widget case can only ever
exercise the weekday the suite happens to run on. The file now carries a test-local anchor
(`_fixtureNow` / `_now()`, null = real clock) used by `_day`, `_weekStart` and `_seedPeriod`, and a
new group **`S-2511 the two cautions hold on every weekday`** builds the F-TWO fixture around a fixed
Monday, Wednesday and Sunday (2026-10-05 / 10-07 / 10-11, 20:00) and reads both signals at it —
Mock and Hive, 6 cases. It asserts the Sustained High Load card exists with its five-week copy and
that the drift observation is `_kObservation` with no lifting sentence.

### Red → green, by mutation

| State | Loop group result |
|---|---|
| Both edits reverted (as reported) | `+2 -4` — Monday and Wednesday: `Expected: not null / Actual: <null>`; Sunday passes |
| M1 only: rated cardio restored (`rating: 3`) | `+2 -4` — the same two anchors, same sustained failure |
| M2 only: `_atWeek` back to `start.day + 3` | `+2 -4` — the same two anchors, drift observation carries the extra "Lifting load is 15% …" sentence |
| Both edits in place | `+6: All tests passed!` |

Each mutation was restored to the exact original line and re-run green. Sunday is green in every
state — the signal that the failure was weekday-dependent, and the reason the loop asserts all three.

### Verification on the final tree

```
gateway.sh test test/cardio_efficiency_drift_signal_screen_test.dart → 00:01 +23: All tests passed!
gateway.sh test                                                    → 01:49 +3885 ~1: All tests passed!
gateway.sh lint                                                    → 196 issues found, 0 errors (baseline 196/0)
invariant check                                                    → no matches
```

Baseline was `+3877 ~1 -2`, the two failures being the Mock and Hive variants of this test; the final
count is 3877 + 2 repaired + 6 new = **3885**, and the suite now exits 0. Only
`test/cardio_efficiency_drift_signal_screen_test.dart` changed (`git-diff --stat`: 93 insertions,
10 deletions — the probe's removal offsets part of the new group). The plan file was not touched.


