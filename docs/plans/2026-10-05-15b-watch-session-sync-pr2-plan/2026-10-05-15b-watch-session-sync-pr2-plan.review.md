# Code Review — watch-session-sync PR 2a

Plan: `2026-10-05-15b-watch-session-sync-pr2-plan.md`
Base commit: bac93ee. Reviewer: @code-reviewer (Copilot CLI).

Layers in scope: core (`lib/core/services/`), state (`lib/state/watch/`, `lib/state/workout/`), docs (`docs/`).
Layers skipped: models, persistence (no changes), features, widgets (no changes).

Scope statement derived from `git-status`:
- Modified: `docs/plans/2026-10-05-15-watch-session-sync-index.md`,
  `docs/plans/2026-10-05-15b-...-plan.md`, `docs/state_management/watch_surface.md`,
  `docs/state_management/workout_state.md`, `docs/watch_session_sync.md`,
  `lib/core/services/watch_session_importer.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`,
  `lib/state/watch/watch_session_inbox.dart`, `lib/state/watch/watch_sync_wiring.dart`,
  `lib/state/workout/session_core_io.dart`, `lib/state/workout/workout_state.dart`,
  `test/watch_session_finish_test.dart`
- Untracked: `test/watch_session_merge_test.dart`, plan `.evidence.md`

## Diff vs Predicted Files

Conforms. Every predicted file is touched; the two extras are documented deviations
(`docs/state_management/workout_state.md` per A-34, the series index; S-17 landed in the merge test per
Phase 2 item 5 / A-33, so `test/watch_session_import_test.dart` is correctly untouched).
`watch/sync_protocol/` and `watch/watchos/` are untouched — D-20 holds.

## Test run (4c)

`.github/copilot/scripts/macos/gateway.sh test` → exit 0, `01:49 +3909 ~1: All tests passed!`
(log `.work/gateway/test-20261005-202134-4244.log`).
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_merge_test.dart` → `+24: All tests passed!`
(12 Mock + 12 Hive). `.github/copilot/scripts/macos/gateway.sh lint` → 196 issues, 0 errors (the plan's
baseline). The handoff pastes counts, not claims.

## Findings

🟡 WARNING | `lib/core/services/watch_session_importer.dart:282` | the merge's `_attachSessionSummary()` — a new write of the wrist's session summary into the phone's **live** session — has no test: S-15's stated outcome "the session's summary is attached" is unasserted anywhere, and the merge test's only summary assertion is S-17's, which is the *not-held* import path | add S-15's summary clause to the finish test's merge case (its `_end` helper needs `avgHeartRateBpm`/`maxHeartRateBpm`, which S-15's fixture names) or to a merge-test case, asserting `getSensorSummariesForSession('s-w1')` | @developer
🟡 WARNING | `docs/plans/...-pr2-plan.md:487` (A-32) | the claim that Phase 1's override put the finish test's merge case "onto S-15's exact fixture — set, end with heart rate, rating 4" is false on two counts: that fixture is `reps: 8` with `avgHeartRateBpm: 140`/`maxHeartRateBpm: 165`, while `test/watch_session_finish_test.dart:211,222` builds `reps: 5, loadKg: 80` and an end with **no** heart rate, and it asserts nothing about a summary | correct A-32 to what the case actually covers, or make the case S-15's fixture (the same edit the finding above needs) | @developer
🟡 WARNING | `docs/plans/...-pr2-plan.md:466` (A-27) | the parity claim is false: `run` carries no `status == completed` condition (`lib/core/services/watch_session_importer.dart:439` attaches for an existing session whenever the end row is unapplied — an abandoned session is diverted before `run`), so an abandoned wrist end that carries heart rate attaches a summary in the merge and none in the import; A-27 states the divergence and the agreement in the same entry | record the divergence as a numbered decision (or add `status == completed` to the merge's guard for parity) and drop the "the merge and the import agree" clause | @developer
💡 SUGGEST | `lib/core/services/watch_session_importer.dart:282` | the branch tests `endRow != null` but calls `pass._attachSessionSummary()`, which dereferences `end!`; a staged `session_end` that fails `_End.parse` throws instead of being skipped | guard on `end != null` (the import's `run` reaches it only after its own parse succeeded) | @developer

### Checked and found correct (no finding)

- The deletion path I first suspected of orphaning a merged row is sound: a fresh `phone_deletion` lands in
  `deleted` but not in `deletedEarlier`, so the entry stays in `before` and leaves `live`, the slot survives
  into `slots`, and `_placeAroundUserRows` deletes its own rows. Verified by reading
  `_mergeHeld` (233-363) against `_placeAroundUserRows` (735-860).
- `existing == null` → `_consume(unapplied)` is D-136's deleted-session rule, and consuming all unapplied
  rows for a session that no longer exists is the only consistent reading.
- `_topUpRating`/`_attachSessionSummary` run before the per-group loop, so the `_Pass.writes` counter (A-26)
  is correct; `changedEffortIds` cannot be polluted by the rating write.
- `refreshEfforts` notifies once, outside any build; `holdsSession`/`refreshHeldEfforts` re-check the
  predicate; `_placeAroundUserRows` never moves, edits or deletes user rows; Mock and Hive run the same code.
- Manual-sync-only scope: the merge fires on a wrist sync, the protocol and the wrist are untouched, and
  nothing syncs on its own.

## Test gaps

🧪 MISSING: `test/watch_session_finish_test.dart` (merge case) — the held session's sensor summary after the
wrist's end (S-15's fourth clause; the only uncovered new line in the change).

## 4a / 4b — acceptance criteria and scenarios

AC1-AC11 each located in code and tests, with one exception: **AC7 is partially verified** — the rating, the
ended session, the applied/receipted rows and "no second entry" are asserted, the summary clause is not.
S-9, S-10, S-11, S-12, S-13, S-14, S-16, S-17, S-19 have passing, fixture-conformant tests; **S-15 is not
fully covered** (see the first WARNING). S-18 is a sweep, not a test, by design. AC9 names
`watch_session_import_test.dart` but the regression landed in the merge test — permitted by Phase 2 item 5
and recorded in A-33; note only.

## 4d — Documentation falsification

DOC FALSIFICATION: 🟡 WARNING (5 implicated) — `docs/watch_session_sync.md`, `docs/watch_session_capture.md`,
`docs/state_management/watch_surface.md`, `docs/state_management/workout_state.md`, `docs/session_summary.md`
🟡 WARNING — `docs/watch_session_capture.md:64-67` — incomplete: "Why an import waits for the session end …
Rows staged before it wait" is silent about the exception this PR adds (a held session's wrist effort rows
merge on arrival); the document's own scope names `watch_session_importer.dart`, so its reader meets the
merge here → add one clause naming the held merge and point at `test/watch_session_merge_test.dart` (`S-9`)
Everything else is true post-change: every `Verified by` test name in the changed docs exists, the rewritten
"One session id, one row" invariant and the three rewritten "What does not sync" bullets match the code, no
document still names `G3 the wrist's entries…` or the staged-only rule, and the symbols the docs cite
(`_attachSetBlockSummary`, `_placeEffort`, `holdsSession`, `refreshEfforts`) all exist. No conflict between
documents. `docs/session_summary.md` has no scope declaration (rule 4) and was read: its watch claims
(`:30`, `:31`) still hold.

## 4e — Documentation standard

DOC STANDARD: ✅ PASS — no prohibited content added. The changed lines add test pointers
(`watch_session_sync.md`'s invariants and "What does not sync"), replace a stale test name
(`watch_surface.md:455`), and add a method-table row in the file's established form
(`workout_state.md:89`) — no walkthrough, no visual value, no restated number, no copied code, no roadmap.

## 4f — Conventions

PASS (4 rules): Units + canonical storage (values go through `LoggedEntryRows` and stored `loadKg`; no new
conversion or unit label); Effort-kind drives analytics (the merge keys on `SegmentEffort.effortKind`);
Timestamps are source data (row values and stamps come from the staged `loggedAt`, never the phone's clock at
merge time); Reuse the canonical owner (`LoggedEntryRows`, `_EffortRows` and `WorkoutState.refreshEfforts`
are reused, not rebuilt).
N/A (3 rules): Theme tokens only, Card chrome via `OmniSurface`, Instrument panel — no UI file changed.

## 4g — Impact Check

IMPACT: ✅ PASS (6 rows re-grepped, 0 unlisted readers). `phoneOwnsSession`, `markWatchInboxEntriesApplied`,
`historyChanged|onHistoryChanged`, `loadSessionData`, `refreshEfforts` and the wrist's `pendingObservations`
readers all still match their rows; the one residue, the mirror's own `sessionScopedKinds`
(`live_session_mirror_state.dart:129`), is the documented out-of-scope constant (A-25/A-35).

## Assumption Log adjudication

RATIFY: A-21…A-26, A-28…A-31, A-33…A-38 — each consistent with the recorded decisions; A-26's write-count
correction is the one that keeps D-17 honest and carries a red→green proof.
REVERT: **A-32** (the fixture and the assertions it claims do not exist) and **A-27** (the parity claim; see
the WARNINGs above). A-38's "checked and needed no change" is narrowed, not reverted: the capture doc needs
one clause.
ESCALATE: none — no entry is ambiguous enough to need the planner.

## Scope triage

3 substantive findings, 1 suggestion — under the §1 threshold (6), no split, and no second review round:
both remediations are one test case plus two plan sentences, in one bounded pass. Nothing else in this PR
needs to change.

## Remediation and guards

1. Assert the held session's summary after the wrist's end. **Guard:** the merge case asserts
   `getSensorSummariesForSession` for the held session — a regression in `_mergeHeld`'s summary attach fails
   the suite from then on.
2. Correct A-27 and A-32 (or make the case S-15's fixture, which satisfies 1 as well). **Guard:** the
   assumption entries then name an assertion that exists.

→ @developer: one test case plus the two assumption corrections. No code defect found; nothing else blocks.

