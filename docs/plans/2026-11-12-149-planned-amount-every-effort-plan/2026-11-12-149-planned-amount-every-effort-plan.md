# Plan — 149: every exercise type carries its planned amount to the wrist

**Status**: seeded by the lead 2026-11-12; planned in detail by the planner run — this file is now the **PR series index plus PR 1's full plan**; not built.
**Next handoff**: @dba (PR 1, Phase 1)
**Binding conventions**: docs/global_conventions.md
**Base**: branch `claude_develop`. Plans 144 (diagnostics), 145 (convergence tests), 146 (ended is final, being built) and a wrist hold-Next fix (`watch/watchos`, `WatchRestNextHoldTests.swift`) are uncommitted in the same tree: never touch their files except where this plan names them.

## Overview

On the watch, the rest screen's one **Next** button keeps you on the same exercise only for sets: the phone sends `plannedSets` rows for `set` slots and nothing for holds, timed work, rounds or intervals, so after ONE hold/round/interval the watch treats the exercise as done and Next moves to the next exercise (owner confirmed on a real holds workout 2026-11-11; the owner thought Next stayed). The routines on the phone already hold the right preset amount (for example 3 holds); the watch just is not told.

Owner decisions 2026-11-12:
- **P-1** Every exercise from any routine holds its planned amount (sets, holds, rounds, intervals) on the watch while logging; Next stays on the exercise until the planned amount is logged, then moves to the next not-done exercise.
- **P-2** Going beyond the plan is normal (an extra round: the user goes back to the first exercise on the watch). The watch must keep the initial plan, allow logging past it, and never refuse or mislabel it (for example "Hold 4 of 3" reads as an extra, not an error; the planner proposes the wording).
- **P-3** (CONFIRMED by the owner 2026-11-12) make it obvious when Next changes exercise: the rest screen says "Next set: Hold 2 of 3" when it stays and "Next exercise: <name>" when it moves.
- Free workouts and exercises with no planned amount keep today's behaviour (one effort counts as done).

## What the planner must establish by reading code (cite file:line)

1. Where the phone builds `plannedSets` and the slot payload (`lib/` projection for the watch: search `plannedSets`), and what the phone's routine/exercise model holds for holds, timed, round and drill efforts (routine item sets/rounds/duration fields): is the planned amount already stored for every effort kind? Which field per kind?
2. The contract: `watch/sync_protocol/PROTOCOL.md` (~line 324 and the 2026-10-15 amendment, ~line 858: `plannedSets` is sent only for a `set` effort; the slot object is closed), the JSON schema and validators (Dart `lib/watch/` + Swift `SyncProtocolValidator.swift`), the fixtures. The cheapest additive wire shape for a planned count of non-set efforts (for example `plannedEfforts: <int>` or generalised rows), and the compatibility statement (older wrist + newer phone is unsupported, both ship together: owner: pre-release).
3. The watch: `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift` (`deriveRestLabels`: only `effortKind == set` stays; `isDone`), `WatchLoggingState.swift` (`plannedSets`, `setsHeld`), `WatchRestView.swift`, `WatchPagerModel`/list "done" markers, and the Dart twin under `lib/watch/`. Which places count "done" or "sets" and must count the exercise's own effort kind.
4. The phone mirror/adoption side that reads wrist entries back (`WatchSessionAdoptionBridge.projectSession`) in case it keys on `plannedSets`.
5. Tracks touched (contract, phone, Swift, Dart twin) are more than one PR: apply `.github/copilot/pr-scope-budget.md`; write an index plus the first PR's plan. Suggested order: (1) contract + phone sends the amount + Dart twin, (2) Swift rule and rest labels, (3) the wording/clarity change P-3.

## Scenarios the plan must cover (fixture + expected each)

A hold exercise planned 3: after hold 1 Next says "Next set: Hold 2 of 3" and stays; after hold 3 Next names the next not-done exercise; a fourth hold on the same exercise is accepted and labelled as an extra; rounds and intervals likewise; an exercise with no planned amount keeps today's rule; going out of order (jump to exercise C, log, jump back to A) counts per exercise by slot id; a free workout is unchanged; a routine exercise whose planned amount is 0/missing is treated as "no plan".

## Notes

- Do not touch plan 144/145/146 files or the Swift hold-Next change's tests except to extend them; coordinate through the plan: this plan builds on that change (Next moves the exercise first, rest ends second).
- No existing user data to migrate (owner: pre-release).

---

# Planner sections (appended 2026-11-11 by the planner run; seeded text above is unchanged)

## Planner answers to the seed's five questions (file:line)

1. **Where the phone builds `plannedSets`, and what each kind's planned amount is.** `WatchSessionAdoptionBridge.projectSession` (`lib/state/watch/watch_session_adoption_bridge.dart:272-291`): after `_slotFor` (:546-575), only when `_wireKind(slot) == PhoneEntries.setKind` (:416) it reads the slot's set rows (`EntryRows.setGroups(await _repository.getEffortObservations(effort.id))`) and sets `slot['plannedSets']`. The planned amount **is already stored for every effort kind**, as the phone's planned rows, one row per planned effort:
   - `set` → `EffortObservation` set rows (reps/weight/extra-weight), seeded by `populateSessionFromManifest` (`lib/state/workout/session_core_io.dart:291-377`, `entry.setCount` rows at :359-361) and, per set, by `addEntry` (`lib/state/workout/session_core_entry.dart:259-279`).
   - `timed`/`drill` (hold) → `TimedInstance` rows (`lib/data/models/models.dart:1310`, `targetDurationSecs`), one per planned interval, seeded by `addEntry`'s timed/drill branch (`session_core_entry.dart:200-226` via `_timerManager.addTimedEntry`), read with `WorkoutState.getTimedInstancesForEffort` (`lib/state/workout/workout_state.dart:140`).
   - `round` → `RoundInstance` rows (`models.dart:1110`, `plannedDurationSecs`), one per planned period, seeded by `addEntry`'s round branch (`session_core_entry.dart:182-195`), read with `WorkoutState.getRoundsForEffort` (`workout_state.dart:138`).
   - The routine template holds the amounts as `TemplateTarget` rows keyed by `setIndex` (`models.dart:855-905`); the count is the highest `setIndex` + 1 (`lib/core/services/routine_session_service.dart:88-99`, the same rule the routine editor uses, `lib/features/routine/routine_setup_screen.dart:1230-1238`).
   - **Gap found**: the wrist-started (adopted) session seeds planned rows ONLY for `set` efforts — `_createPlannedRows` is gated `_effortKind(slot) == BlockTypes.set` (`watch_session_adoption_bridge.dart:1110`; the seeder at :1174-1196, `_plannedValue` :1199, `_plannedSetCount` :1247). An adopted hold slot holds no `TimedInstance` until the wrist logs one, so a row-count source alone would still lose the plan there. PR 1 Phase 3 extends the adoption seeding to the non-set kinds, for I-6 parity with the phone's own routine start.
2. **The contract.** `watch/sync_protocol/PROTOCOL.md:324-331` states `plannedSets` is sent only for a `set` effort; `$defs.sessionExercise` is closed (`watch/sync_protocol/schemas/envelope.schema.json:106-160`, `additionalProperties: false` at :113), so an undeclared key is refused `unexpected_field` and the field must be declared. The 2026-10-15 amendment row (`PROTOCOL.md:858`) is the pattern to copy: additive, no version change, an older wrist and a newer phone are not a supported pair (both clients ship from this repository in one release — owner: pre-release). Both validators are schema-driven (Swift loads the same schema documents from the repo, `SyncProtocolValidator.swift:8-26`; Dart reads `additionalProperties` at `lib/core/sync_protocol/message_validator.dart:965`), so **no validator code changes** — the schema plus fixtures carry the change. Cheapest additive wire shape: a new optional integer `plannedEfforts` on `sessionExercise`, sent only for non-set slots (symmetric with `plannedSets` only for set slots); generalising `plannedSets` into rows per kind would add per-row shapes no consumer needs — the wrist only counts.
3. **The watch.** `WatchRestLabels.deriveRestLabels` (`watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift:74-134`): a slot is done when `planned > 0 ? sets >= planned : efforts > 0` (:62), `planned` read from `plannedSets` only (:98) — so holds/timed/rounds are "done" after one effort and Next moves on; rounds escape via the `nextRound` line ("`\Period k+1`", `WatchLoggingState.swift:536-548`, `nextRoundNumber` :661-669), which is unbounded — a planned round exercise never moves on. `WatchLoggingState` counts `setsHeld` (kind `set` only, :703-708) and gates `plannedSets`/`setCaption`/the planned `initialValue` on `effortKind == .set` (:335, :698-707, :857) — those stay set-only and unchanged. `WatchMenu.deriveMenuRows` counts all effort kinds per slot for its "N logged" subtitle (`WatchMenu.swift:263-267`) — kind-agnostic, unchanged; `WatchWorkoutSummary.swift:142` counts efforts for set blocks, unchanged. **No Dart twin of `deriveRestLabels` exists** (grep `deriveRestLabels|WatchRestLabelCopy|nextSlotId` over `lib/` and `test/`: zero matches) — the rest-label rule is watchOS-only, so the seed's suggested "Dart twin" item has no target; PR 2 is Swift-only.
4. **The phone's read-back side.** `grep plannedSets lib/state/watch/` finds the writer (:286), the ladder identity (:657) and a comment (:615) — nothing on the phone *reads* `plannedSets` back; `heldWristEntryIds` (:432-476) claims by entry kind, not by the key. The new key has no phone-side reader either (projection is write-only for both keys).
5. **Tracks.** Contract, phone and Swift watch — three PRs per `.github/copilot/pr-scope-budget.md`; the series below follows the seed's suggested order, with the Dart-twin item resolved as "none exists" above.

## PR series (index)

| PR | Scope | Track(s) | Depends on | Decisions it shares |
|----|-------|----------|------------|---------------------|
| **PR 1** (planned below, Phases 1–3) | The wire: `sessionExercise` MAY carry `plannedEfforts` (schema, fixtures, manifest, PROTOCOL.md row); the phone projects the planned count for non-set slots and seeds the planned non-set rows on adoption | contract + phone | — | D-14901, D-14902, D-14903 (phone half), D-14905, D-14906, D-14907 (wording is PR 3's) |
| **PR 2** | The wrist rule and rest labels: `deriveRestLabels` counts each slot's own effort kind against its plan; the stay/move lines gain kind-aware "k of N" wordings; the round stay-line respects the plan; `WatchRestNextHoldTests.swift` extended only where PR 2's plan names it | Swift watch (`watch/watchos`) | PR 1 (the wrist ignores the key until then — safe intermediate state, see Notes) | D-14903 (wrist half), D-14904; scenarios S-14920..S-14928 (planned then) |
| **PR 3** (P-3, CONFIRMED by the owner) | Rest-screen clarity: the next line reads "Next set: …" when it stays and "Next exercise: <name>" when it moves | Swift watch | PR 2 | D-14907; scenarios S-14940.. (planned then) |

Order rationale: the contract and the sender must exist before any receiver can read the field; PR 2 is the user-visible fix; PR 3 is a wording change on top, matching the seed's suggested order.

## Resolved Decisions (Ledger)

The seed's P-1..P-3 above are binding owner decisions; D-14901.. below pin the rules that implement them. Entries are immutable: changes are new superseding entries.

- **D-14901 — Wire.** A `sessionExercise` MAY carry `plannedEfforts`: an integer of at least 1, the planned number of efforts the slot holds, sent only for a non-`set` slot whose planned rows number at least 1 — a hold (drill), a timed effort or a round. A set slot, a slot with no planned rows, and a phone that predates the field omit it. The slot object stays closed (`$defs.sessionExercise` keeps `additionalProperties: false`): the field is refused until the schema declares it, an older wrist and a newer phone are not a supported pair, both clients ship from this repository in one release (owner: pre-release). No new message family, no new rejection code, no version change — additive for the same reason as the 2026-10-15 `plannedSets` amendment (`PROTOCOL.md:858`), and no existing fixture changed. `plannedSets` and `plannedEfforts` are never sent on the same slot by the phone.
- **D-14902 — Planned-count source.** The count is the phone's planned rows for the slot, read per kind at projection time: `set` → its set rows (already sent as `plannedSets`), `drill`/`timed` → `WorkoutState.getTimedInstancesForEffort(effort.id).length`, `round` → `WorkoutState.getRoundsForEffort(effort.id).length`. The count is self-extending exactly like `plannedSets` (logged rows included: the importer writes a new row when the wrist logs past the plan, `lib/core/services/watch_session_importer.dart:1422-1500`), so an extra effort reads as its own last number and the user is never wedged or refused (P-2). No existing user data migrates (owner: pre-release).
- **D-14903 — The done rule, per kind.** A slot with a plan is done when the entries of its own effort kind, logged for its slot id, number at least the plan; a slot with no plan is done when anything is logged (today's rule). The slot's own kind is its declared `effortKind` mapped to its entry kind (`drill`→`hold` via `WatchEffortKind.eventKind`, `WatchLoggingState.swift:37-60`; `timed`→`timed`, `round`→`round`, `set`→`set`), and counting keys on `sessionExerciseId` — so going out of order counts per exercise (seed scenario, S-14925). For a set slot `plannedSets` remains the sole authority: the wrist ignores `plannedEfforts` on a set slot, the mirror of `testS3632AHoldSlotIgnoresTheKey` (`WatchPlannedSetsTests.swift:329`).
- **D-14904 — Stay/move wording for planned non-set slots (P-1's visible half).** When a planned non-set slot still holds efforts short of its plan, the rest line stays on it and reads `Next: <KindWord> k of N`, k = that kind's logged count + 1, N = `max(plan, k)` — an extra reads as its own last number, so the seed's "Hold 4 of 3" never appears (P-2). `<KindWord>` mirrors the phone's own wording (`lib/features/routine/routine_setup_screen.dart:1276-1287`): `Hold` for a drill, `Interval` for a timed effort, the modality's round noun (singular of `WatchLoggingState.roundsLabel`, :652-658) for a round. A slot without a plan keeps today's lines: a set reads `Next: Set k+1` (stays), a round reads `Next: Period k+1` (stays, unbounded as today), any other kind moves on after one effort. PR 3's prefixes then wrap these same lines (D-14907).
- **D-14905 — Revision.** `plannedEfforts` joins the ladder identity: `_ladderOf` (`watch_session_adoption_bridge.dart:650-658`) appends the slot's `plannedEfforts` beside `plannedSets`, so a plan change is a changed ladder that states a newer revision (the same principle plan 36b's D-3 pinned for `plannedSets`).
- **D-14906 — Adoption seeds the non-set plan (I-6).** `_createPlannedRows` (`watch_session_adoption_bridge.dart:1110-1196`) is extended from set-only to every declared kind: a planned hold or interval becomes a `TimedInstance` whose `targetDurationSecs` is the template's `duration` target for that index, else 0; a planned period becomes a `RoundInstance` whose `plannedDurationSecs` is the template's `round-duration` target for that index, else the exercise's default (the phone's own start, `session_core_entry.dart:182-195`, is the mirror). The count rule (`_plannedSetCount`, :1247 — highest `setIndex` + 1, one when no targets) is reused unchanged.
- **D-14907 — Stay/move prefixes (P-3, confirmed).** The rest screen's next line reads `Next set: <line>` when Next stays on the exercise and `Next exercise: <name>` when it moves. This wraps D-14904's lines without changing them; it ships in PR 3, after the rule itself is correct.

## Feature Invariants

- Every implementation of `WorkoutRepository` — `HiveWorkoutRepository` and `MockWorkoutRepository` — produces the same observable output for the same inputs (docs/global_conventions.md). The bridge reads through `WorkoutState`/repository interfaces only; PR 1 adds no repository method, so parity is untouched — the S-14908 tests run Mock-first per the repo's test rules.
- A free workout, a wrist-added slot and an exercise with no planned amount keep today's rest behaviour: one effort counts as done (P-1's carve-out). A wrist-added slot's single seeded row (`seedFirstEntry`, `session_core_entry.dart:129-152`) yields `plannedEfforts: 1` — a plan of 1, which is today's rule in effect (A-14903).
- The phone never sends `plannedSets` and `plannedEfforts` on the same slot; the wrist never applies `plannedEfforts` to a set slot (D-14903).
- `plannedEfforts` is never below 1 on the wire; a count of 0 is the key's absence (D-14901, S-14904).
- Nothing on the phone reads `plannedSets` or `plannedEfforts` back (grep proof in answer 4): the projection is write-only for both keys.
- The wrist's set-value behaviour (`plannedSets` dialling, `setCaption`, the planned `initialValue`) is untouched: plan 36b owns it; this plan only adds a parallel key for the other kinds.

## Requirements

- R1 (P-1, wire): the phone projects the planned count of every non-set slot it sends (Phase 2), and holds the planned rows for them on adopted routine sessions (Phase 3).
- R2 (P-1, wrist): PR 2 — Next stays on a planned non-set exercise until its plan is logged, then moves to the next not-done exercise.
- R3 (P-2): logging past the plan is accepted everywhere, labelled as the extra it is (k of max(N, k)), never refused and never a wedge; PR 2.
- R4 (contract): PROTOCOL.md states the field, the version history gains the 2026-11-12 row, and the fixtures + manifest pin the shape (Phase 1).
- R5 (P-3, confirmed): PR 3 — the stay/move distinction in the rest line's prefix.

## Acceptance Criteria (each maps to ≥ 1 scenario)

- AC1 A hold exercise planned 3 reaches the wrist with `plannedEfforts: 3` — S-14901.
- AC2 Round and timed plans travel likewise, with the round's `roundDurationSecs` intact — S-14902.
- AC3 A set slot carries `plannedSets` and never `plannedEfforts` — S-14903.
- AC4 A slot with no planned rows carries neither key and still projects — S-14904.
- AC5 The wire refuses a non-conforming count — S-14905.
- AC6 A plan change states a newer revision — S-14906.
- AC7 An effort logged past the plan grows the projected count by exactly 1 — S-14907.
- AC8 An adopted routine session holds its planned holds/periods on the phone, with the template's own values — S-14908.
- AC9 A template with no per-index targets still seeds the count (one per kind, phone defaults) — S-14909.
- AC10–AC17 (PR 2, planned then): stay-until-planned per kind, the extra-effort label, the no-plan carve-out, out-of-order counting, set-slot ignoring, idempotent re-apply, the round wedge fix — S-14920..S-14928.
- AC18 (PR 3): the stay/move prefixes — S-14940...

## Existing-Functionality Impact

Every place that counts "sets" or "done", with the grep that found it:

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchRestLabels.deriveRestLabels` (Swift) | `grep plannedSets watch/watchos/Sources` → `WatchRestLabels.swift:98` (planned), `:62` (isDone), `:47-54` (nextLabel); `grep "done" watch/watchos/Sources` → no other done-marker | PR 2 changes the done rule per kind and the two labels; PR 1 changes nothing here — after Phase 1 the Swift *validator* accepts the declared key and the engine ignores it, exactly as a drill slot ignores `plannedSets` (`WatchPlannedSetsTests.swift:329`) | S-14903, S-14920.. |
| `WatchLoggingState` (Swift) | `WatchLoggingState.swift:335` (setCaption), `:698-707` (plannedSets getter + kind gate), `:703-708` (setsHeld), `:857` (initialValue planned branch), `:536-548` (restLabels call, nextRound), `:661-669` (nextRoundNumber) | All stay set-only and untouched; the round stay-line's plan gate is PR 2 (D-14904) | S-14926 (round wedge fix), S-14921 |
| `WatchMenu` rows (Swift) | `grep "efforts" WatchMenu.swift` → `WatchMenu.swift:263-267` (loggedCount, all effort kinds) | None: "N logged" is kind-agnostic and stays | S-14925 (out-of-order counting reads the same entries) |
| `WatchWorkoutSummary` (Swift) | `WatchWorkoutSummary.swift:142` (efforts count for set blocks) | None | — |
| `WatchSessionAdoptionBridge.projectSession` (phone) | `grep plannedSets lib/` → writer `:286`, ladder `:657`; nothing reads it back | Phase 2 adds the parallel `plannedEfforts` writer and ladder segment; whole-slot map tests that pin non-set slots will see the new key | S-14901..S-14907, S-1411 regression |
| `_createPlannedRows` (phone adoption) | `watch_session_adoption_bridge.dart:1110` (set-only gate), `:1174-1196` (seeder), `_plannedSetCount` `:1247` | Phase 3 widens the gate to all declared kinds; set-row behaviour byte-identical | S-14908, S-14909, existing adoption tests |
| Importer row growth | `watch_session_importer.dart:1422-1500` (`_createEntry` writes a row per logged past-plan effort, every kind) | None — it is what makes D-14902's self-extension true | S-14907 |
| Validators (both stacks) | `SyncProtocolValidator.swift:8-26` (schema-driven), `message_validator.dart:965` (`additionalProperties`) | None: declaring the field in the schema is the whole change | S-14905 |
| Whole-slot fixtures on the wire | `grep "plannedSets" test/` → `watch_session_adoption_bridge_test.dart` (S-1411 `:1519` pins a whole slot), `watch_session_projection_test.dart` (S-2 `:670`), the Swift slot helpers (`WatchRestLabelsTests.swift:524-533`, `WatchPlannedSetsTests.swift:448-457`, `WatchBodyweightLoadTests.swift:23-31`, `WatchPersonalRecordBannerTests.swift:68-77`) | Phone-side pins may see `plannedEfforts` on non-set slots (re-run named suites); the Swift helpers add no key and are untouched | S-14903, S-14901 |
| `docs/watch_session_sync.md` | `grep plannedSets docs/` → `:24, 110, 128-148`; `docs/watch_session_sync/what_does_not_sync.md:24, 306`; `docs/state_management/watch_surface_wrist_pager.md:59` ("A hold or timed effort carries no planned count on the wire" — false after Phase 1) | Phase 1 item 7 amends them; docs trail code by zero phases | S-14901 |

Standing invariants this could break: implementation parity (no new repository method — unaffected, stated above); layer boundaries (`lib/features/` untouched); the schema contract (envelope.schema.json is exercised by both fixture walkers — S-14905 is the guard).

## UI Standards Impact

- Wrist rest screen (`WatchRestView.swift`, the `labels.now`/`labels.next` lines, :57-59, :75-80): the next line's wording gains kind-aware "k of N" counts (D-14904) — the same text-only change class as the wrist's existing label work; no new control, no layout change, no accent change. The wrist nouns mirror the phone's own (`routine_setup_screen.dart:1276-1287`) — the two ends say the same words for the same effort.
- Phone UI: none. The routine editor already shows the amount for every kind — `Hold 2 of 3` / `Interval i of n` / round noun (`routine_setup_screen.dart:1276-1287`) and the card's count chip (`:1164`). One pre-existing nit, out of scope: the card chip reads "N sets" for every kind (`:1164`).
- P-3's prefix change (D-14907) is the same text-only class, in PR 3.
- No section is added to any doc in `docs/` — all doc edits are amendments to existing sections (watch_session_sync.md's planned-rows paragraph; the pager doc's one stale sentence), so the 64 KiB band is not approached.

## Scenarios

The seed's minimum list (verbatim above) is covered: the stay-until-planned behaviour by S-14920..S-14922 (PR 2, on top of the wire counts proven in PR 1), the extra-effort acceptance by S-14924 (PR 2) and its wire half by S-14907 (PR 1), the no-plan carve-out by S-14926 (PR 2) and S-14904 (PR 1), out-of-order counting by S-14925 (PR 2), free workouts by S-14926, and "planned amount 0/missing treated as no plan" by S-14904/S-14909 + the schema's minimum-1 refusal (S-14905).

Numbering is stable and never reused; PR 1 owns S-14901..S-14909, PR 2 reserves S-14920..S-14928, PR 3 owns S-14940...

### S-14901: a hold slot carries its planned count
- Fixture: one active phone session (modality none), one segment, one `drill` effort `effort-h` on "Plank" (capabilities `hold`,`time`); `TimerManager` holds exactly 3 `TimedInstance`s (`entryIndex` 0..2, `targetDurationSecs` 45, `startedAtMs` 0 — planned, unstarted); no entries of any kind.
- Trigger: `projectSession(null)`.
- Flow: the projection loop reaches the effort; `_wireKind` → `hold` ≠ `set`; the instance count is read.
- Expected outcome: the slot carries `effortKind: "drill"` and `plannedEfforts: 3`; `plannedSets` absent; nothing else on the slot changes (capabilities, name, id verbatim).
- Edge case of: none (the parent behaviour).

### S-14902: round and timed slots carry theirs
- Fixture: as S-14901, three efforts on one segment: a `round` effort with 4 `RoundInstance`s (`plannedDurationSecs` 180) and a `roundDurationSecs` target, a `timed` effort with 2 `TimedInstance`s (`targetDurationSecs` 0), a `set` effort with 3 set rows.
- Trigger: `projectSession(null)`.
- Expected outcome: the round slot carries `effortKind: "round"`, `roundDurationSecs: 180` (unchanged) and `plannedEfforts: 4`; the timed slot `plannedEfforts: 2`; the set slot `plannedSets` with 3 items and no `plannedEfforts` (S-14903's assertion in the same frame).
- Edge case of: S-14901.

### S-14903: a set slot never carries the key
- Fixture: as S-14902's set effort.
- Trigger: `projectSession(null)`.
- Expected outcome: `plannedSets` present, `plannedEfforts` absent — the keys never share a slot from the phone (D-14901).
- Edge case of: S-14902.

### S-14904: a slot with no planned rows carries no key
- Fixture: a `drill` effort whose `TimedInstance`s have all been deleted (adversarial empty set: 0 instances, 0 entries) — a legacy or fully-deleted slot.
- Trigger: `projectSession(null)`.
- Expected outcome: the slot projects (id, name, capabilities verbatim) with neither `plannedEfforts` nor `plannedSets`; the wrist treats it as "no plan" (today's rule).
- Edge case of: S-14901.

### S-14905: the wire refuses a non-conforming count
- Fixture: `fixtures/invalid/session_snapshot_planned_efforts_zero.json` (`plannedEfforts: 0`), `..._fractional.json` (2.5), `..._string.json` ("3"); the valid carrier is `fixtures/valid/session_snapshot_planned_efforts.json` (drill 3 + round 4 + a set slot with `plannedSets` only).
- Trigger: the manifest walk (`S-001 fixtures`) in both stacks.
- Expected outcome: 0 → `constraint_violation` (minimum 1); 2.5 and "3" → `invalid_type`; the valid frame conforms on both stacks; a slot carrying both keys is NOT a fixture (the phone never sends it, and the wrist's ignoring rule is behavioural — S-14923, PR 2).
- Edge case of: S-14901.

### S-14906: a plan change states a newer revision
- Fixture: S-14901's session, projected once; then a 4th `TimedInstance` is added on the phone (`addEntry`), projected again.
- Trigger: two consecutive `projectSession(null)` calls.
- Expected outcome: the second projection's `revision` is strictly greater; the ladder string contains the slot's `plannedEfforts` (D-14905).
- Edge case of: S-14901.

### S-14907: logging past the plan grows the count by one
- Fixture: S-14901's session; the wrist's hold-4 entry has been imported (the importer wrote a 4th `TimedInstance` for it, `watch_session_importer.dart:1478`).
- Trigger: `projectSession(null)`.
- Expected outcome: `plannedEfforts: 4` — the plan self-extends exactly like `plannedSets`, never refusing or wedging the extra (P-2, phone half).
- Edge case of: S-14901.

### S-14908: an adopted routine session seeds its planned holds and periods
- Fixture: the wrist started a session from a routine the phone holds; the ladder's slot ids are the template's effort ids; the template plans 3 holds of 45 s and 4 periods of 180 s; the exercise library holds both exercises.
- Trigger: the adoption creates the phone's efforts and seeds planned rows.
- Expected outcome: the hold effort holds 3 `TimedInstance`s (`targetDurationSecs` 45, from the template's `duration` target per index) and the round effort 4 `RoundInstance`s (`plannedDurationSecs` 180, from the `round-duration` target); the next projection carries `plannedEfforts: 3` / `: 4` (D-14906, I-6 parity with `populateSessionFromManifest`).
- Edge case of: none (the adoption half).

### S-14909: a template with no per-index targets still seeds the count
- Fixture: as S-14908, but the hold effort's template holds no `duration` targets at all and the round effort's holds no `round-duration` targets.
- Trigger: the adoption seeding.
- Expected outcome: 1 `TimedInstance` with `targetDurationSecs` 0 and 1 `RoundInstance` with the exercise's default round length — the count rule (highest `setIndex` + 1, one when no targets) and the phone's own defaults (`session_core_entry.dart:182-195`), never a crash and never zero rows for a planned effort.
- Edge case of: S-14908.

### S-14920..S-14928 (PR 2, planned then — ids reserved)
The wrist rule: S-14920 after hold 1 of 3 the line stays and reads "Next: Hold 2 of 3", after hold 3 it names the next not-done exercise; S-14921 rounds likewise ("Next: Period 2 of 3") and the unbounded round wedge is gone; S-14922 timed intervals likewise ("Next: Interval 2 of 3"); S-14923 a set slot ignores `plannedEfforts` and a drill slot ignores `plannedSets` (both gates, mirrored); S-14924 a fourth hold is accepted and the extra reads "Hold 4 of 4"; S-14925 out-of-order counting per slot id (jump to C, log, back to A: A's plan counts A's entries only); S-14926 no planned amount keeps today's rule (free hold moves after one, free set stays); S-14927 the same frame twice changes nothing (idempotent); S-14928 a `plannedEfforts` of 1 on a wrist-added slot behaves as today's one-effort rule.

### S-14940.. (PR 3)
The P-3 prefixes (D-14907): after hold 1 of 3 the line reads "Next set: Hold 2 of 3" (the seed scenario's exact wording); when the plan is met it reads "Next exercise: <name>".

## Iteration 1 — PR 1 (contract + phone)

### Phase 1: the contract (@dba)
1. [ ] Declare `plannedEfforts` on `$defs.sessionExercise` — `watch/sync_protocol/schemas/envelope.schema.json` (properties block, after `plannedSets` at :146-160): `{"type": "integer", "minimum": 1, "description": "The planned number of efforts the slot holds, sent only for a non-set effort (a hold, a timed effort, a round), counted the way plannedSets counts a set's rows. Omitted for a set slot, a slot with no planned rows, and an older phone."}` — symbol: `$defs.sessionExercise.properties`
2. [ ] Create the valid carrier — `watch/sync_protocol/fixtures/valid/session_snapshot_planned_efforts.json`: one snapshot, three slots — a drill slot (`effortKind: "drill"`, `plannedEfforts: 3`), a round slot (`effortKind: "round"`, `roundDurationSecs: 180`, `plannedEfforts: 4`), a set slot (`plannedSets: [{reps:10,loadKg:60},{reps:8}]`, no `plannedEfforts`) (S-14901/02/03's wire shapes)
3. [ ] Create the refusals — `watch/sync_protocol/fixtures/invalid/session_snapshot_planned_efforts_zero.json` (0), `session_snapshot_planned_efforts_fractional.json` (2.5), `session_snapshot_planned_efforts_string.json` ("3") (S-14905)
4. [ ] Add the manifest rows — `watch/sync_protocol/fixtures/manifest.json`: one `valid` entry (`scenario: "S-14901"`, note per the register's style) and three `invalid` entries (`scenario: "S-14905"`) — symbol: the `valid` and `invalid` arrays
5. [ ] State the field in the spec — `watch/sync_protocol/PROTOCOL.md`: insert one paragraph after the `plannedSets` paragraph (:324-331), before `## Timer state (normative)` (:333), in the 2026-10-15 row's pattern (D-14901's text, plus: a receiver that predates the field refuses the whole snapshot as it refuses anything it cannot read; both clients ship together; the consumer is `WatchSessionAdoptionBridge.projectSession` on the phone and `WatchRestLabels`/`WatchLoggingState` on the wrist from PR 2)
6. [ ] Add the version-history row — `watch/sync_protocol/PROTOCOL.md` (Version history table, after the 2026-11-09 row at :876): a row dated `2026-11-12`, amendment `1 (amended)`, in the 2026-10-15 row's shape: `plannedEfforts` — an integer of at least 1, the planned number of efforts (holds, timed efforts, rounds) the slot holds, counted like `plannedSets` counts a set's rows, self-extending when an effort is logged past the plan; sent only for a non-set slot with at least one planned row, `plannedSets` untouched, the two keys never share a slot from the phone; the slot object stays closed so the field is refused until the schema declares it — an older wrist and a newer phone are not a supported pair, both clients shipping from this repository in one release; no new message family, no new rejection code, no version change, additive for the same reason as the 2026-10-15 amendment, no existing fixture changed; names the four fixtures and both walkers (`test/sync_protocol_fixtures_test.dart` / `SyncProtocolFixturesTests.swift`), the phone consumer (`WatchSessionAdoptionBridge.projectSession`, pinned by `test/watch_session_projection_test.dart` S-14901..S-14909) and this plan's path.
7. [ ] Amend the three stale wire docs — `docs/watch_session_sync.md` (the planned-rows paragraph :128-149: add the `plannedEfforts` sentence beside the `plannedSets` one) and `docs/state_management/watch_surface_wrist_pager.md:59` ("A hold or timed effort carries no planned count on the wire" → a count MAY travel as `plannedEfforts`); `docs/watch_session_sync/what_does_not_sync.md:24,306` gains the same clause

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (compare with the 181-issue baseline — no new issues); `.github/copilot/scripts/macos/gateway.sh test` on the named suites `test/sync_protocol_fixtures_test.dart`, `test/watch_session_projection_test.dart` (projection stays green — no consumer yet); and `swift test` in `watch/watchos` (the manifest the Swift walker reads changed: `SyncProtocolFixturesTests.testEveryValidFixtureConforms` / `testEveryInvalidFixtureIsRejectedAsStated` must accept the new fixtures).
**Predicted Files**: `watch/sync_protocol/schemas/envelope.schema.json`; `watch/sync_protocol/fixtures/valid/session_snapshot_planned_efforts.json`; `watch/sync_protocol/fixtures/invalid/session_snapshot_planned_efforts_{zero,fractional,string}.json`; `watch/sync_protocol/fixtures/manifest.json`; `watch/sync_protocol/PROTOCOL.md`; `docs/watch_session_sync.md`; `docs/watch_session_sync/what_does_not_sync.md`; `docs/state_management/watch_surface_wrist_pager.md`. Nothing else.
**Phase 1 verification notes (Conductor, date):** —

### Phase 2: the phone sends the amount (@developer)
1. [ ] Add the `plannedEfforts` writer — `lib/state/watch/watch_session_adoption_bridge.dart`, `projectSession` (loop :272-291): after the existing `plannedSets` block, when `_wireKind(slot) != PhoneEntries.setKind`, read the count (`_wireKind(slot) == PhoneEntries.roundKind` → `target.getRoundsForEffort(effort.id).length`, else → `target.getTimedInstancesForEffort(effort.id).length`) and set `slot['plannedEfforts'] = count` when `count >= 1` — symbol: `projectSession`
2. [ ] Join the ladder identity — same file, `_ladderOf` (:650-658): append the slot's `plannedEfforts` after the `plannedSets` segment — symbol: `_ladderOf`
3. [ ] Red→green the projection group — `test/watch_session_projection_test.dart`, new group `S-149 the phone sends the planned efforts`: `S-14901 a hold slot carries its planned count`, `S-14902 round and timed slots carry theirs`, `S-14903 a set slot never carries the key`, `S-14904 a slot with no planned rows carries no key` (fixtures exactly as the scenarios state; Mock-first per the repo's test rules)
4. [ ] Pin the revision — same group: `S-14906 a plan change states a newer revision` (extend the `S-3622 a planned-value edit moves the revision` pattern in `test/watch_session_adoption_bridge_test.dart`'s sibling)
5. [ ] Pin the self-extension — same group: `S-14907 logging past the plan grows the count by one` (seed the 4th instance directly, as the importer's `_createEntry` would — the importer's own growth is already covered by its tests)
6. [ ] Re-run the whole-slot regressions — `test/watch_session_adoption_bridge_test.dart` (`S-1411 the same number twice is the same bytes`, `:1519`) and `test/watch_session_auto_push_test.dart`: any pin that held a whole non-set slot map now sees the key, and is updated to expect it (a changed pin is a finding to log in the Assumption Log, not a silent edit)

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint` (no new issues vs the 181 baseline); `.github/copilot/scripts/macos/gateway.sh test` on `test/watch_session_projection_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_auto_push_test.dart`, `test/sync_protocol_fixtures_test.dart`; the red→green table filled in the evidence file.
**Predicted Files**: `lib/state/watch/watch_session_adoption_bridge.dart`; `test/watch_session_projection_test.dart`; `test/watch_session_adoption_bridge_test.dart` (pins only); the evidence file. Nothing else.
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: the adoption seeds the non-set plan (@developer)
1. [ ] Widen the seeding gate — `lib/state/watch/watch_session_adoption_bridge.dart:1110`: `_effortKind(slot) == BlockTypes.set` → the slot carries a declared kind (`_declaredKinds.contains(_effortKind(slot))`), passing the kind into `_createPlannedRows` — symbol: the adoption loop's `_createPlannedRows` call site
2. [ ] Seed the non-set rows — same file, `_createPlannedRows` (:1174-1196): per kind — `set` exactly as today; `drill`/`timed` → `_repository.createTimedInstance` per planned index with `entryIndex` = index and `targetDurationSecs` = `_plannedValue(targets, MetricIds.duration, index)?.toInt() ?? 0`; `round` → `_repository.createRoundInstance` per planned index with `roundIndex` = index and `plannedDurationSecs` = `_plannedValue(targets, MetricIds.roundDuration, index)?.toInt() ?? exercise.defaultRoundDurationSecs ?? WorkoutConstants.defaultRoundDurationSecs` — symbols: `_createPlannedRows`; repository method names as the importer uses them (`watch_session_importer.dart:1511/1552`)
3. [ ] Red→green the adoption group — `test/watch_session_adoption_bridge_test.dart`, new cases in the adoption group: `S-14908 an adopted routine session seeds its planned holds and periods` (assert the phone's rows AND the projection's `plannedEfforts`), `S-14909 a template with no per-index targets still seeds the count` (defaults, adversarial: template holds no duration/round-duration targets)
4. [ ] Regression sweep — the same file's set-row adoption tests (the D-3 group) and the whole-slot pins stay green byte-for-byte for set slots; re-grep `'sessionExerciseId'` next to `'capabilities'` in `test/watch_session_*` for any other whole-slot pin and re-run it
5. [ ] Update the adoption docs — `docs/watch_session_sync.md:46` ("`set` efforts start with the routine's planned rows" → every declared kind does) and `:104-110` (the planned-rows sentence), zero-phase trail

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint` (no new issues vs the 181 baseline); `.github/copilot/scripts/macos/gateway.sh test` on `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_session_auto_push_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`; a residue grep recorded in the evidence file proving no set-only seeding claim remains (`grep "set efforts start with the routine's planned rows" docs/` → only the amended text).
**Predicted Files**: `lib/state/watch/watch_session_adoption_bridge.dart`; `test/watch_session_adoption_bridge_test.dart`; `docs/watch_session_sync.md`; the evidence file. Nothing else.
**Phase 3 verification notes (Conductor, date):** —

### Phase X.Y: remediation — none open at planning time
Any defect the reviewer opens here must carry its structural guard: a permanent test making that defect class impossible to reintroduce.

## Files Affected (whole feature)

- **PR 1** (this plan): `watch/sync_protocol/schemas/envelope.schema.json`; `watch/sync_protocol/fixtures/valid/session_snapshot_planned_efforts.json`; `watch/sync_protocol/fixtures/invalid/session_snapshot_planned_efforts_{zero,fractional,string}.json`; `watch/sync_protocol/fixtures/manifest.json`; `watch/sync_protocol/PROTOCOL.md`; `lib/state/watch/watch_session_adoption_bridge.dart`; `test/watch_session_projection_test.dart`; `test/watch_session_adoption_bridge_test.dart`; `docs/watch_session_sync.md`; `docs/watch_session_sync/what_does_not_sync.md`; `docs/state_management/watch_surface_wrist_pager.md`; the evidence file.
- **PR 2** (planned then): `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift`; `WatchLoggingState.swift` (the round stay-line's plan gate, `restLabels` :536-548); `watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift`; `WatchPlannedSetsTests.swift` (the mirrored ignore gate); `WatchRestNextHoldTests.swift` (extended only where PR 2's plan names it); the wrist docs.
- **PR 3**: `WatchRestLabels.swift` copy + its tests + the rest-surface docs.
- Read-only dependents (touched surface, readers only): `WatchMenu.swift`, `WatchWorkoutSummary.swift`, `WatchRestView.swift`, `lib/core/sync_protocol/phone_entries.dart`, the importer — none change; each is re-verified by the named suites.

## Notes (planner additions; the seed's Notes above stay verbatim)

- Phase graph: 1 → 2 → 3 inside PR 1; PR 2 depends on all three (the wrist reads the key only once the phone sends it and the schema declares it); PR 3 depends on PR 2. Phase 3 could run before Phase 2 (the seeding is independent of the projection) — running it second keeps every intermediate state shippable and the projection testable as soon as the contract lands, which is worth the strict order.
- Intermediate states: after Phase 1 both validators accept the declared key and every client ignores it (schema-driven, `additionalProperties: false` lifts only when the field is declared); after Phase 2 the wrist receives counts it does not yet read — no behaviour change anywhere until PR 2. Nothing is half-live.
- The importer's past-plan row growth (`_createEntry`, every kind) is what makes D-14902's self-extension true on every kind; it is already tested (its own suites) and is named, not changed.
- The seed's "Dart twin" item resolved: no Dart twin of the rest-label rule exists (answer 3's grep); nothing to build there.

## Progress

- [x] PR 1 Phase 1 (contract) — @dba — schema + 4 fixtures + 4 manifest rows + PROTOCOL.md bullet & version row; Dart fixtures 182 passed, Swift fixtures 6/6; `prove-red` GREEN AT HEAD (data-only fixtures), mutation proof recorded
- [x] PR 1 Phase 2 (phone sends the amount) — @developer — `projectSession` writer + `_ladderOf` segment; group `S-14901 the phone sends the planned efforts` 5/5, RED AT HEAD before it
- [x] PR 1 Phase 3 (adoption seeds the non-set plan) — @developer — seeding gate widened, `_createPlannedRows` per kind; S-14908/S-14909 2/2, RED AT HEAD before it; docs amended; sweep 232/232
- [ ] PR 2 planned (wrist rule + labels)
- [ ] PR 3 planned (P-3 prefixes)

## Assumption Log

Executors append here (decision, options considered, choice + why, ≤ 3 lines each); the conductor marks RATIFIED (promote to D-x) or REVERT (remediation).

- **A-14901** (planner, derived — vetoable): the planned count is the phone's row count per kind (self-extending), not a static template number. Options: template `max(setIndex)+1` (the literal "initial plan") vs row counts. Chose rows: parity with `plannedSets` (whose rows the wrist already treats as the plan, logged rows included), one source rule for every kind, and the importer's row growth makes the "initial plan" hold in effect until an extra effort is actually logged. If the owner wants a static plan, a superseding entry replaces D-14902 and S-14907/S-14924 change meaning.
- **A-14902** (planner, derived — vetoable): the adoption seeding must widen to non-set kinds (Phase 3) or P-1 fails for wrist-started routine sessions (the adopted hold slot holds no rows, the count reads 0/1). Options: seed rows (chosen — I-6 parity, the phone's own screens gain the same rows) vs read the template in `projectSession` per projection (a per-call template lookup the bridge's I-2 rule already forbids caching; more reads, no phone-side rows).
- **A-14903** (planner, derived — vetoable): a wrist-added or ad-hoc slot travels with `plannedEfforts: 1` (its seeded row), which is today's one-effort rule in effect. Options: suppress the key for non-routine slots (needs an "is this routine?" flag the slot does not carry) vs send the count (chosen: one rule, no new flag, behaviour identical).
- **A-14904** (planner, derived — vetoable): "no plan" means zero planned rows (all deleted / legacy), i.e. the key's absence — the seed's "planned amount is 0/missing" has no separate wire state, because a count of 0 is refused by the schema (S-14905) and omission IS the zero.
- **A-14905** (implementer, Phase 2): the group's tests are named for the fixtures the register states, not the step list's paraphrase — `S-14901 a drill slot carries how many holds it plans`, `S-14902 a round and a timed slot carry their own counts`, `S-14906/S-14907 a fourth effort moves the count and the revision`. Options: adopt the step list's "hold slot" wording (the register's fixture is a `drill` slot, so the name would misdescribe it) vs the fixture's own words (chosen). The docs cite the actual names.
- **A-14906** (implementer, Phase 1): `prove-red` reports GREEN AT HEAD for the schema-and-fixture guards because the schema, the fixtures and the manifest are data already on disk at HEAD. Options: accept the GREEN AT (proves nothing) vs a mutation — `plannedEfforts` `minimum: 1` → `0`, the walker then fails `invalid/session_snapshot_planned_efforts_zero.json is rejected as constraint_violation` (`Expected: non-empty`, `Actual: []`), original restored and 182 passed (chosen).
- **A-14907** (implementer, Phase 3): `test/watch_session_adoption_bridge_test.dart` has no file-scope slot helper (`_slot()` there takes named `declaredKind`), so the new group carries a local `slotIn(...)`. Options: widen `_slot()` for every existing caller (touches 40+ call sites for no gain) vs a local helper (chosen).
- **A-14908** (implementer, Phase 3): a `timed`/`hold` template effort with no `duration` targets now seeds exactly one `TimedInstance` (`targetDurationSecs` 0), and a `round` one seeds one round at the exercise's default length. This is the count rule's "one when no targets" and `addEntry`'s own default, and no existing pin contradicts it: the routine-adoption suite's timed effort already held no set rows (still true) and the 232-test sweep passes unchanged.

## Open questions

1. **Wrist nouns** (D-14904): `Hold` / `Interval` / the modality's round noun, mirroring the phone (`routine_setup_screen.dart:1276-1287`). Default: as stated. Owner may prefer different wrist wording.
2. **Round stay-line** (D-14904): a planned round's stay-line gains "of N" ("Period 2 of 3"); an unplanned round keeps today's unbounded "Period 2". Default: as stated.
3. **Ad-hoc slots travel `plannedEfforts: 1`** (A-14903). Default: send it (one rule, no new flag); alternative: suppress the key outside routine sessions.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]
