# Stats PR 3 series — Distance source and correction (index)

> Status (2026-09-27):
> - **3a** is done: commit 4bb4afb on `develop`, which the owner may re-title.
> - **3a2** is implemented and reviewed; the owner commits and merges it.
> - **3b** is READY, with its full plan written.
> - **3a3**, the **O-17 PR** and **3c** are not planned yet. Plan each when its turn comes, against the code as
>   it is then (`.github/agents/pr_scope_budget.md` §3).
>
> Source: `.github/agents/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 4 and PR 2 Open
> Item O-8; the owner's answers of 2026-09-26 and 2026-09-27.
> Implementer: Copilot with DeepSeek V4.1 Flash, running locally in this checkout. Plans are written for a small
> model: numbered one-concern steps, exact strings, commands and greps, and rules inline.
> Next handoff: Copilot implements 3b after 3a2 lands, then `/code-reviewer`.

## Branch policy (owner, 2026-09-27)

- Only `develop` and `main` persist.
- All work happens directly on `develop`. Plans must never create, switch or delete branches.
- Executors never commit, merge or push; the owner does.

## PRs in order

| PR | Scope | Depends on | Plan |
|---|---|---|---|
| **3a** (done) | Phone: each distance stores its source; the Session Summary's DISTANCE list; "est." marking on the Summary and the Stats cardio card; pace counts only entries with a distance. | — | `2026-09-26-03a-stats-pr3a-phone-distance-plan.md` |
| **3a2** | Phone: entry identity. Every edit, delete and distance lands on the chosen entry, live and reopened, on Hive and Mock. | 3a | `2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md` |
| **3b** | Phone plus the sync contract:<br>• the `distanceSource` wire field, on timed entries only and only with a distance, on both validators;<br>• the import stores the source (absent means `entered`);<br>• a sync never rewrites a phone-written distance;<br>• the row guard closes 3a2's F-6 and F-7;<br>• the import uses the shared id parser;<br>• instance ids are unique. | 3a2 | `2026-09-27-03b-stats-pr3b-distance-source-import-plan.md` |
| **3a3** | Phone cleanup, with no visible change. Removes the old-data handling made dead by the owner's single-release decision and proven dead by 3b's guard:<br>• the missing-source-reads-`entered` rule;<br>• non-timed distance rows (3a I-3);<br>• 3a-style suffixed ids, including the 3a2 review's F-8;<br>• the sequential grouping fallback;<br>• missing-row filling;<br>• "leftover" wording.<br>It also fixes the save-as-routine defaults, which read the first raw row (3a2 O-7). | 3b | not planned |
| **O-17 PR** | Phone: a late watch entry that arrives while its session is open in Edit Session is no longer lost when the user discards (PR 2 O-17; the owner's Q1: fix before release). | 3b | not planned |
| **3c** | watchOS:<br>• the watch sends `distanceSource` (GPS, dialled or estimated) and the field becomes required, removing 3b's "absent means `entered`" rule;<br>• GPS for outdoor wrist sessions (PR 2 O-8);<br>• the platform estimate indoors, or when there is no fix;<br>• the crown wrap on the logging dial (PR 2 O-20).<br>On-device checks need shipping-plan Phases 7–8. | 3b | not planned |
| then **PR 4** | The new Stats structure (pack items 5 and 6). Cadence arrives here. | 3a3 | — |

## Shared decisions (defined once in the plans named; later PRs cite them and never restate them)

- **3b D-332 (owner): single release.** The whole Stats redesign ships at once, and no user data exists for
  any of it. So nothing needs old-data handling, migration or backward compatibility. That includes the
  watch↔phone protocol: both apps ship together, and the version stays 1.
- **3b D-333 (owner): the phone never sends a corrected distance to the watch.**
- **3a D-301 / D-302 / D-303 / D-311:**
  - the source vocabulary (`gps`, `entered`, `estimated`);
  - the phone's value is final (3b D-336 enforces it for sync);
  - the "est." marker;
  - the storage key `value_source`.
- **3a D-319 (owner):** an entry gets the distance row when it was tracked through Cardio, which is detected
  by the effort kind `timed`. 3b and 3c keep a wire `timed` entry `timed`.
- **3a2 D-324 / D-325:** the entry rule and new-row numbering. 3b's import reads ids through the same parser.
- **PR 2 D-134 and D-135, confirmed by the owner on 2026-09-27:** a watch session is imported as logged, with
  no rest records, no routine link and no modality.
- **Pack decisions still binding:**
  - D-1: watchOS only; Wear OS inherits everything through the shared format.
  - D-2: indoor vs outdoor is decided by the exercise. See question 1.
  - Pack D-11 is superseded by 3a D-304: corrections happen on the Session Summary.

## Open questions for later planning

1. **3c: indoor vs outdoor.** The owner's per-exercise tracked-modality model (3a D-319) may replace pack
   D-2. The catch: the watch has no modality picker, so on the wrist an exercise list may stay the only
   signal.
2. **3c: the indoor list.**
   - Clear: treadmill run, stationary bike, the five rowing exercises, both elliptical exercises, both
     stair-climber exercises, ski erg, and both assault-bike exercises.
   - Unclear: incline walk, cycling sprint intervals, swimming.
3. **3c:** does dialling over an estimate make it `entered`? Does the watch's live readout show "est."?
4. **3c:** do GPS distances the watch records on phone-started Cardio sessions reach history at all? This
   is unverified.

The earlier question 4 ("send a corrected distance back to the watch?") is closed: no (3b D-333).

## Series risks

- **No real "est." until 3c ships.** 3b's fixtures exercise every source, but the watch sends none yet.
- **The analyzer bar is "none new":** 241 issues with 0 errors on the 3a2 tree.
- **Small-model implementer.** Every plan must keep its rules inline and its steps mechanical. The last two
  reviews each found CRITICAL doc issues.

## Scope check (2026-09-27)

The 3b plan is 498 lines, with 3 phases. Its tracks are the phone plus the contract (one soft signal). It has
10 decisions, 14 scenarios and about 200 predicted production lines. That is within budget.
