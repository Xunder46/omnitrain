# Stats PR 3 series — Distance source and correction (index)

> Status (2026-09-27):
> - **3a** is done: commit 4bb4afb on `develop`, which the owner may re-title.
> - **3a2** is READY; its full plan is written.
> - **3b** and **3c** are not planned yet. Plan each when its turn comes, against the code as it is then
>   (`.github/agents/pr_scope_budget.md` §3).
>
> Source: `.github/agents/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 4 and PR 2 Open
> Item O-8; the owner's answers of 2026-09-26 (Q1–Q9) and 2026-09-27 (3a D-319; 3a2 Q1–Q4).
> Why a series: as one PR, pack PR 3 would span three tracks (phone, sync contract, watch), plus two missing
> prerequisites (no distance entry on the phone, and no GPS for watch sessions).
> Next handoff: Copilot implements 3a2 (it runs locally in this checkout), then `/code-reviewer`. Plan 3b with
> conductor-v2 once 3a2 lands.

## Branch policy (owner, 2026-09-27)

- Only `develop` and `main` persist.
- Each PR gets its own branch, cut from `develop` by an explicit executor step in its plan.
- After review, the owner merges the branch into `develop` and deletes it. Executors never merge, push or
  delete branches.

## PRs in order

| PR | Scope | Depends on | Plan |
|---|---|---|---|
| **3a** (done) | Phone:<br>• each distance stores its source;<br>• the Session Summary's DISTANCE list, to enter, correct, confirm or remove a distance;<br>• "est." marking on the Summary and the Stats cardio card;<br>• pace counts only entries with a distance. | — | `2026-09-26-03a-stats-pr3a-phone-distance-plan.md` |
| **3a2** | Phone: entry identity. Every edit, delete and distance lands on the chosen entry, for sets and timed entries, live and reopened, on Hive and Mock. Also: duplicated blocks stay addressable, leftovers are ignored, and the SQL contract accepts the app's rows. Covers 3a's O-3, F-5, F-6, N-3, N-4 and O-4, and the set-path defects. | 3a | `2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md` |
| **3b** | The sync contract plus the phone import:<br>• a `distanceSource` field (`gps`/`entered`/`estimated`) on timed entries in `observations_up` and `session_snapshot`;<br>• both validators, Dart and Swift, with the timed-only rule; fixtures;<br>• the importer writes `value_source`, and a later sync never rewrites a phone-written distance.<br>Gate: `cd watch/watchos && swift test`, with a fresh baseline taken then. | 3a2 (stable entry identity) | not planned |
| **3c** | watchOS:<br>• indoor vs outdoor;<br>• GPS for outdoor wrist sessions (PR 2 O-8);<br>• the platform's distance estimate indoors, or when there is no fix;<br>• a hand-dialled distance counts as `entered`;<br>• the crown wrap on the logging dial (PR 2 O-20), in 3c or in a tiny watch PR just before it.<br>On-device checks need shipping-plan Phases 7–8. | 3b | not planned |
| then **PR 4** | The new Stats structure (pack items 5 and 6). Cadence arrives here. | 3a2; real estimates need 3c | — |

## Shared decisions (defined once in the plans named; later PRs cite them and never restate them)

- **3a D-301:** the source vocabulary (`gps`, `entered`, `estimated`); a missing source reads as `entered`.
- **3a D-302:** the phone's value is final. A sync never rewrites a phone-written distance, and the watch
  never changes one.
- **3a D-303:** the "est." marker format.
- **3a D-311:** the storage key is `value_source`, on the distance observation. 3b fills it from the wire.
- **3a D-319** (owner; supersedes D-305): an entry gets the distance row when it was tracked through Cardio,
  which is detected by the effort kind `timed`. A watch entry's kind comes from a routine-declared kind or
  from the exercise's capabilities, so 3b and 3c must keep a wire `timed` entry `timed`.
- **3a2 D-324 / D-325:** the entry rule and new-row numbering. D-324 supersedes 3a D-312, and D-325
  supersedes 3a D-313's suffix. 3b's importer changes must stay compatible, and 3b converges the importer's
  own id parser on it (3a2 O-2).
- **PR 2 D-134 and D-135, confirmed by the owner on 2026-09-27 (3a2 D-323):**
  - a watch session is imported as one session holding its exercises and entries exactly as logged, with no
    rest records;
  - it has no routine link and no modality.
- **Pack decisions still binding:**
  - D-1: watchOS only; Wear OS inherits everything through the shared format.
  - D-2: indoor vs outdoor is decided by the exercise. See open question 1.
  - Pack D-11 is superseded by 3a D-304: corrections happen on the Session Summary.

## Open questions for later planning (not decided now)

1. **3c: indoor vs outdoor.** The owner's per-exercise tracked-modality model (3a D-319) may replace pack
   D-2's exercise-based rule. The catch: the watch has no modality picker, so on the wrist an exercise-based
   list may stay the only signal. Re-ask at 3c planning.
2. **3c: the indoor list.**
   - Clear: treadmill run, stationary bike, the five rowing exercises, both elliptical exercises, both
     stair-climber exercises, ski erg, and both assault-bike exercises.
   - Unclear: incline walk, cycling sprint intervals, swimming.
3. **3c:** does dialling over an estimate on the watch make it `entered`? Does the watch's live readout show
   "est."?
4. **3b:** does the phone send a corrected distance back to the watch? The recommended answer is no, because
   the watch never changes a distance.
5. **3b:** after the phone deletes entries from an imported session, re-verify the importer's top-ups (3a2
   O-2), together with PR 2 O-17 (a late watch entry lost on an Edit Session discard).

## Series risks

- **No real "est." for a while.** Users see real "est." values only once 3c ships and the watch app is
  released (shipping-plan Phases 7–8).
- **Existing data.** Old data may already hold leftover rows. 3a2 reads them by its rule and never deletes
  them (3a2 D-322), so a leftover can't always be told apart from a real row.
- **Analyzer bar.** 242 issues with 0 errors is the bar in every PR ("none new").
- **Push state.** `develop` is 1 commit ahead of origin. Copilot runs locally, so this doesn't block; the owner
  pushes when they choose.

## Scope check (2026-09-27)

The 3a2 plan is about 460 lines, with 3 phases, one track, 12 decisions and 18 scenarios, and about 350
predicted production lines. That is no soft signal, so it is within budget.
