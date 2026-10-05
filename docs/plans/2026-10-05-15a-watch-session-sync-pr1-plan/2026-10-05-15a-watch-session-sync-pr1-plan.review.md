# Review — watch-session-sync PR 1 (phone side)

Reviewer: code-reviewer (Copilot CLI edition). Base: HEAD 8e41207 + untracked new files.
Plan: `2026-10-05-15a-watch-session-sync-pr1-plan.md`; series: `2026-10-05-15-watch-session-sync-index.md`.

## Scope

Layers in scope: `lib/state/watch/`, `lib/core/services/watch_session_importer.dart`,
`lib/state/workout/` (read-only, for the adoption path), `lib/features/` (removals + home/picker),
`lib/main.dart`, `lib/app.dart`, `test/`, `docs/`.
Layers skipped: `lib/data/models/`, `lib/data/repositories/` (untouched — verified by
`git-status`), `lib/widgets/` (only the entry-point deletion), `watch/`, `watch/sync_protocol/`
(untouched), Swift.

Governor-verified and not re-run here: full suite `+3871 ~1 -2` (the 2 failures pre-existing, see
finding F0), analyze 196 / 0 errors, protocol/reconciler/Swift untouched, and mutation checks on
the D-10 guard, running-status check, revision rules, G1 never-resurrect guard, G3 importer
predicate. This review targets what those do not prove: data safety, the manual-sync-only
invariant, no-watch behaviour, layering/scope, residue, and doc truth.

Diff vs Predicted Files: conforms. Every touched path is inside the plan's Predicted Files or is one of
the deviations the plan records (A10 the debug harness, A26/A28 the wiring/router adjustments, A29 the
`docs/` set). Nothing outside the predicted set was touched.

## 4c — Test run (this reviewer, observed)

```
.github/copilot/scripts/macos/gateway.sh test test/watch_session_finish_test.dart \
  test/watch_session_projection_test.dart test/watch_session_adoption_bridge_test.dart
→ 00:00 +24: All tests passed!   (exit 0)
```

The full suite was not re-run here: the governor's `+3871 ~1 -2` stands, and the 2 failures are the
pre-existing ones in `test/cardio_efficiency_drift_signal_screen_test.dart` recorded in `## Feedback`.
Both counts are real; the handoff summary pastes them, so 4c's first box passes.

## 4a — Acceptance criteria

- AC1 PASS — reproduced: `grep -rln "live_session_screen|live_session_entry_point|LiveSessionScreen|
  LiveSessionEntryPoint|liveSessionBlock|liveSessionEntryGap|watchSessionRatings" lib/ test/` → nothing;
  those names survive only in plan/history docs.
- AC2 PASS — S-1 (adoption bridge), including Mock/Hive row parity and the restart id check.
- AC3 PASS — S-2 (projection), including the idle-phone silence case.
- AC4 PASS — S-4 ×2 and S-5 (finish); one history entry asserted in each.
- AC5 PASS — S-3 (adoption bridge).

## 4b — Scenario register cross-check

| Scenario | Test | Fixture as enumerated |
|---|---|---|
| S-1 | `test/watch_session_adoption_bridge_test.dart` (3 tests: adopt, Mock+Hive parity, restart ids) | yes — 2 slots, catalog seeded, revision 3 |
| S-2 | `test/watch_session_projection_test.dart` (`S-2 a running phone session is answered with its own ladder`, `S-2 an idle phone still answers with silence`) | yes |
| S-3 | adoption bridge (`S-3 an empty wrist session is adopted but reads "not yet active"`) | yes |
| S-4 | `test/watch_session_finish_test.dart` (`S-4 …roster of logged sets first`, `S-4 …end before the logged sets`) | yes |
| S-5 | finish (`S-5 the phone's own finish is not reported, and the wrist is answered at its next sync`) | yes |
| S-6 | adoption bridge (`S-6 the phone keeps the session it is already running`, counter-case) + projection (`S-6 a wrist session this phone is not in is left alone`) | yes — both halves |
| S-7 | the residue sweep above (AC1); the scenario states its outcome as that grep | n/a |
| S-8 | projection (`S-8 case A …added…`, `S-8 case B …removed…`) | yes |

Every scenario has a passing, fixture-conformant test. D-11's revision rule, G1 and its counter-case,
and G3 each have their own test in the same files.

## Findings

🔴 CRITICAL | `docs/state_management/watch_surface.md:63-66` | Claims `effortEntries`/`effortEntriesOf`
"are what a surface lists and counts as logged work" and cites `test/live_session_capture_entries_test.dart`
(`S-254`) — that surface was deleted here, and neither member is referenced anywhere in `lib/` or `test/`
| Delete both the claim and the citation; if the log list needs a behavioural statement, point at the
ordinary session screen's test | @developer
🔴 CRITICAL | `docs/watch_session_capture.md:187` | "Only the device that ended a live-mirrored session
asks how hard it was" is still true, but "live-mirrored session" names the deleted screen and the claim is
"verified by" the deleted `test/live_session_effort_rating_test.dart` (`S-281`–`S-284`, `A-62`) | Repoint to
`test/watch_session_finish_test.dart` (`S-4`, `S-5`) and `test/watch_session_import_test.dart` (`the phone's
own rating (D-138, D-139 state half)`); drop the "live-mirrored" framing | @developer
🟡 WARNING | `docs/state_management/watch_surface.md:96-101` | "They exist so no screen has to know a
`structure_change` from an `exercise_push`" — no phone screen reaches the mirror at all now; the push family
is reached only from tests | Fix in the same pass as the first finding: describe them as the mirror's
protocol API, exercised by the harness and the tests | @developer
🟡 WARNING | `docs/watch-app-setup-and-qa.md:57` and `:441` | Both describe the phone-side wiring as
"`main.dart` → `liveSession`"; `liveSession` no longer appears anywhere in `lib/` | The plan assigns this doc
to the owner's step — reword to the one-session wiring (`createWatchSync`) so the QA instruction stays
followable | @developer (owner-facing)
🟡 WARNING | plan `S-5` (Flow) vs `G2` | S-5's Flow still says the phone "reports `session_lifecycle`
`completed` to the wrist"; G2, the shipped behaviour, is that the phone's finish sends nothing and the wrist
catches up at its next sync — the S-5 test asserts G2 | Rewrite S-5's Flow and Expected outcome to name G2
and the test | @developer
🟡 WARNING | `lib/state/watch/live_session_mirror_state.dart:137`, `:140`, `:351` | `effortEntries`,
`effortEntriesOf` and `mintSlotId` now have no reference in `lib/` or `test/`; `pushExercise`, `swapExercise`,
`correctEntry`, `deleteEntry` and `completeSession` are reached only from tests | Confirm these are retained
on purpose for the successor unit (and record it) or delete them — guard: the first successor change that
uses one must arrive with a test that exercises it | @developer
🟡 WARNING | `lib/state/watch/watch_sync_wiring.dart:63` | `WatchSyncGraph.ratings` is constructed and never
read in `lib/` (its reader, the screen's `watchSessionRatings`, was removed here), and
`WatchSessionInbox.recordPhoneRating` is called only from tests — the phone's rating now travels the ordinary
finish | Same decision as above; a guard test or a recorded decision, not silence | @developer
🟡 WARNING | `lib/state/workout/workout_state.dart:403` (4g unlisted reader) | `checkForInProgressSession`
deletes every in-progress row but the newest, and this change can leave two (the S-6 counter-case keeps the
wrist's adopted row beside an empty phone row). Verified safe — Hive and Mock both sort newest-first
(`hive_workout_repository.dart:3068`, `mock_workout_repository.dart:378`) and the adopted row's `startedAtMs`
is the adoption instant, so it is the survivor — but no test pins that ordering | Add a guard test: adopt,
let the empty phone row stand, restart → the adopted session and its slot ids survive and the empty row is
gone; note the accepted same-millisecond tie | @developer
💡 SUGGEST | `docs/watch_session_sync.md` ("What does not sync", first bullet) | Names the successor unit as
where the staged entries go — standard class 7 territory | Optional: state the current limitation without
naming forthcoming work | @developer

## Data safety, manual sync, no-watch (the brief's focus areas)

- **Data safety PASS.** Adoption writes a new `TrainingSession` plus one segment and one effort per slot
  with protocol ids reused as row ids; a second snapshot of the held session rewrites nothing; an ended
  wrist session is never adopted back; a lifecycle naming another session changes nothing. Removal paths:
  nothing in this change deletes a row that the wrist's copy still needs (the wrist's entries stay staged
  and unreceipted). The one ordering assumption above is reasoned and now needs its guard.
- **Manual sync only PASS.** The only production send that is not an answer is the router's
  `reportLifecycle(completed)` for a snapshot naming an ended session; the mirror's re-assertion inside
  `receive` and `WatchSyncRequestHandler`'s snapshot are answers. The ordinary finish sends nothing (S-5).
  Nothing on a timer, nothing on a state change.
- **No-watch behaviour PASS.** `createWatchSync` still returns null where no watch exists, and the
  projection returns null when unbound; an unbound bridge writes nothing (test observed).

## 4d — Documentation falsification

DOC FALSIFICATION: ❌ REJECT — `docs/state_management/watch_surface.md:63-66` — claims a surface lists and
counts logged work through `effortEntries`/`effortEntriesOf`, citing a deleted test → delete the prose, point
at the surviving test
DOC FALSIFICATION: ❌ REJECT — `docs/watch_session_capture.md:187` — "live-mirrored session" plus a citation
of a deleted test → repoint to `test/watch_session_finish_test.dart` and `test/watch_session_import_test.dart`
DOC FALSIFICATION: 🟡 WARNING — `docs/state_management/watch_surface.md:96-101` — incomplete/false purpose
claim for the push family
DOC FALSIFICATION: 🟡 WARNING — `docs/watch-app-setup-and-qa.md:57`, `:441` — claims wiring that no longer
exists
DOC FALSIFICATION: ✅ PASS (all other implicated docs) — `watch_session_sync.md` (new), `watch_session_capture.md`
elsewhere, `navigation_and_screens.md`, `state_management.md`, `watch-app-setup-and-qa.md` elsewhere: every
cited test file, group and test name was looked up and exists; the Swift half names
`testThePhonesLifecycleEndsAWristSessionAtTheMomentItNames`, which exists.

## 4e — Documentation standard

DOC STANDARD: ✅ PASS — no prohibited content added; the new doc carries a scope declaration, no hex
literals, no arrow-chain walkthrough, no restated constants, and its "Structure" table names owners rather
than fields. The mechanical guard (`test/docs_indexing_contract_test.dart`) is green at the governor's
baseline. The one borderline item is the SUGGEST above.

## 4f — Conventions

PASS (7 rules): repository interface only — `grep hive_workout_repository` in `lib/state lib/features
lib/widgets lib/core` returns nothing; state depends on `WorkoutRepository` by injection; screens take state
through the constructor and hold no business logic; no platform branch added to shared code; constants and
tokens untouched and unre-defined; new tests are plain `test()` (no `testWidgets` FakeAsync hazard); no
formatter run over a directory.
N/A (3 rules): the Swift/watch package rules, the design-token rules and the widget purity rules — no
widget, theme or Swift file was changed.
FAIL: none.

## 4g — Impact conformance

Each row's grep was re-run: the readers named are still the readers (`screen_widget_test.dart` and the two
deleted test files are gone with their surfaces; `watch_sync_wiring.dart`, `watch_incoming_router.dart`,
`live_mirroring_test.dart`, `phone_manage_bridge_test.dart` still read the mirror; `docs/navigation_and_screens.md`
no longer lists the three surfaces). One unlisted reader found: `WorkoutState.checkForInProgressSession` via
the home screen's resume check — reported above with its reasoning and its guard. No other unlisted reader.

## Counts

Critical: 2 | Warnings: 6 | Suggestions: 1 | Test gaps: 2 (the ordering guard and the dead-seam decision both
need a permanent guard)

→ @developer: one bounded fix pass — the two doc REJECTs (delete false prose, repoint citations), the three
adjacent doc corrections (push-family purpose, QA wiring, plan S-5), and the two structural guards (the
in-progress ordering test; a recorded decision plus a test for the retained rating/push seams). No product
behaviour changes: every finding is documentation truth, dead-seam bookkeeping, or a missing test. Nothing
in this list requires a design decision, so this is a single round — do not open a second review.

---
⏸️ **PIPELINE PAUSED** — waiting for your decision.


