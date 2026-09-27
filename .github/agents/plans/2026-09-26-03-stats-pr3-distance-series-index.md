# Stats PR 3 series — Distance source and correction (index)

> Status: 3a READY; its full plan is written. 3b and 3c are not planned yet. Plan each when its turn
> comes, against the code as it is then (`.github/agents/pr_scope_budget.md` §3).
> Source: `.github/agents/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 4, plus PR 2
> Open Item O-8; the owner's answers of 2026-09-26 (Q1–Q9); the owner's Q3 decision of 2026-09-27
> (3a D-319).
> Why a series: as one PR, pack PR 3 spans three tracks (phone, sync contract, watch). Planning also
> found two missing prerequisites: the phone has no way to enter a distance, and the watch never starts
> GPS for its own sessions. Both are over budget.
> Next handoff: Copilot implements 3a, then `/code-reviewer`. Plan 3b with conductor-v2 once 3a lands.

## PRs in order

| PR | Scope | Depends on | Plan |
|---|---|---|---|
| **3a** | Phone only, no wire or watch change. Each distance stores its source (`value_source`). The Session Summary gets a DISTANCE list to enter, correct, confirm or remove a distance. "est." is marked on the Summary and on the Stats cardio card. Pace counts only entries that have a distance. | — | `2026-09-26-03a-stats-pr3a-phone-distance-plan.md` |
| **3b** | The sync contract plus the phone import. A `distanceSource` field (`gps`/`entered`/`estimated`) on timed entries in `observations_up` and `session_snapshot`. Both validators, Dart and Swift, get the timed-only rule; fixtures and the manifest are updated. The importer writes `value_source`, and a later sync never rewrites a phone-written distance. Gate: `cd watch/watchos && swift test` (baseline 242). | 3a's field | not planned |
| **3c** | watchOS only:<br>• indoor vs outdoor;<br>• GPS for outdoor wrist sessions (PR 2 O-8: wrist sessions carry no modality, so GPS never starts);<br>• the platform's distance estimate for indoor efforts and for outdoor efforts that never get a fix;<br>• a hand-dialled distance counts as `entered`.<br>Unit-tested in 3c; on-device checks wait for shipping-plan Phases 7–8 (pack O-2). | 3b's wire field | not planned |
| then **PR 4** | The new Stats structure (pack items 5 and 6). Cadence arrives here (3a D-310). | 3a's marking; real estimates need 3c | — |

## Shared decisions

These are defined once, in the 3a ledger, and bind every PR in the series. Later PRs cite them and never
restate them.

- **D-301:** the source vocabulary (`gps`, `entered`, `estimated`); a missing source reads as `entered`.
- **D-302:** the phone's value is final. In 3b, a sync never rewrites a phone-written distance's value
  or source. The watch never changes a distance (pack item 4).
- **D-303:** the "est." marker format.
- **D-319** (owner decision; supersedes D-305): an entry gets the phone's distance row when it was
  tracked through Cardio, in any kind of session. It is detected by the effort kind `timed`. For a watch
  entry, the kind comes from a routine-declared kind or from the exercise's capabilities, so 3b and 3c
  must keep a wire `timed` entry `timed`. D-319's data-safety clause is still flagged I-3.
- **D-311:** the storage key is `value_source`, on the distance observation. 3b fills it from the wire.
- **D-312:** how distance rows are paired with timed entries.
- **Pack decisions still binding:**
  - D-1: watchOS only; Wear OS inherits everything through the shared format.
  - D-2: indoor vs outdoor is decided by the exercise, with a fallback when there is no GPS fix. See
    open question 1.
- **Superseded:** pack D-11 ("distance correction uses the edit-session flow") is superseded by 3a D-304
  (the Session Summary), following the owner's Q2 answer.

## Open questions for later planning (not decided now)

1. **3c: indoor vs outdoor.** The owner's model is that each exercise carries the modality the user
   tracks it through (3a D-319). That may replace the pack's D-2, which decides indoor vs outdoor by
   the exercise.
   - One option is the tracked modality plus a per-exercise or per-session indoor choice.
   - A catch: the watch has no modality picker today. It resolves the kind from the exercise's
     capabilities, so D-2's exercise-based list may still be the only signal on the wrist.
   - Re-ask at 3c planning.
2. **3c:** the exact indoor list.
   - Clear catalog candidates: treadmill run, stationary bike, the five rowing exercises (steady-state,
     intervals, 2k test, long, sprints), both elliptical exercises, both stair-climber exercises, ski
     erg, and both assault-bike exercises.
   - Unclear: incline walk, cycling sprint intervals, swimming.
3. **3c:** does dialling over an estimate on the watch make it `entered`? Does the watch's live readout
   show "est."?
4. **3b:** does the phone send a corrected distance back to the watch? The recommended answer is no,
   because the watch never changes a distance.

## Series risks

- **BLOCKER (process): `develop` is unpushed.** It is 17 commits ahead of origin (`origin/develop` =
  f1f9aaa). Push it before any GitHub-hosted Copilot handoff.
- **Pre-existing pairing and id drift (3a O-3).** Deleting a timed entry leaves its companion-row ids
  unchanged, and a later add can reuse one. Candidate small PR between 3a and 3b.
- **Unconfirmed PR 2 decisions.** D-134 (the shape of imported rows) and D-135 (wrist sessions carry no
  modality) are still marked "owner to confirm". They bear on 3b and 3c.
- **No real "est." for a while.** Users see real "est." values only once 3c ships and the watch app is
  released (shipping-plan Phases 7–8).
- **Analyzer bar.** The analyzer baseline is 242 issues with 0 errors. "None new" is the bar in every PR.

## Scope check (2026-09-27)

The 3a plan is about 520 lines, with 3 phases, one track, 19 decisions and 28 scenarios, and about 550
predicted production lines. That is one soft signal (over 500 lines), so it is within budget.
