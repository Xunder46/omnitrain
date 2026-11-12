# Plan 149 PR 2 — the wrist rule and rest labels

**Status**: planned by the planner run 2026-11-12; not built.
**Next handoff**: @developer (Phase 1)
**Binding conventions**: docs/global_conventions.md
**Parent plan**: `docs/plans/2026-11-12-149-planned-amount-every-effort-plan/2026-11-12-149-planned-amount-every-effort-plan.md` — its P-1..P-3, D-14901..D-14907 and PR 1's committed wire (`plannedEfforts` on the slot, `03e2433c`) bind this PR. Scenario ids S-14920..S-14928 are reserved here and are defined below; numbering is stable and never reused (S-14940.. stay with PR 3).
**Base**: branch `claude_develop` at `03e2433c`. Plans 144/145/146 and the wrist hold-Next fix are neighbours in the tree: never touch their files except where this plan names them (`WatchRestNextHoldTests.swift` is extended here, by name).

## Overview

PR 1 taught the wrist what every exercise plans (`plannedEfforts` on the slot, schema-declared, phone-projected); the wrist ignores it. PR 2 is the user-visible fix, Swift-only: `deriveRestLabels` stops treating one logged hold/interval/round as "the exercise is done" and counts each slot's **own effort kind** against its own plan. While a planned non-set slot is short of its plan, the rest line stays on it and reads `Next: Hold 2 of 3` / `Next: Interval 2 of 3` / `Next: Period 2 of 3`; when the plan is met — or the user logs past it, which always works (P-2) — the line names the next not-done exercise, and a later planned non-set slot is announced with its own `k of N` count, exactly as a planned set already is. The unbounded round stay-line (`Next: Period k+1` forever) keeps today's wording only where there is no plan; a planned round moves on like everything else. Nothing about sets changes: `plannedSets` remains the set slot's sole authority, and a set slot ignores `plannedEfforts` (the mirror of a drill slot ignoring `plannedSets`).

**No Dart twin exists** (re-checked this run: grep `deriveRestLabels|WatchRestLabelCopy|nextSlotId` over `lib/` and `test/` → zero matches). PR 2 is Swift-only; no Dart check is affected (the `flutter analyze` baseline is quoted in Done Criteria only as a no-change guard, and is not expected to move).

## Resolved Decisions (Ledger)

Carried from the parent plan, binding here (restated only where the executor needs the rule, never renumbered):

- **D-14901** (wire, PR 1): `plannedEfforts` is an integer ≥ 1 on a non-`set` slot, absent otherwise. The wrist may rely on: a slot carrying it is a non-set slot with a plan of that exact count.
- **D-14903** (the done rule, per kind): a slot with a plan is done when the entries of its **own effort kind**, logged for its `sessionExerciseId`, number at least the plan; a slot with no plan is done when anything is logged (today's rule). Own kind = declared `effortKind` mapped to its entry kind (`drill`→`hold` via `WatchEffortKind.eventKind`, `WatchLoggingState.swift:37-60`; `timed`→`timed`, `round`→`round`, `set`→`set`), keyed on `sessionExerciseId`. A set slot ignores `plannedEfforts`; `plannedSets` stays its sole authority.
- **D-14904** (stay/move wording, P-1's visible half): a planned non-set slot short of its plan stays, and the next line reads `Next: <KindWord> k of N`, k = that kind's logged count + 1, N = `max(plan, k)` — an extra reads as its own last number, so `Hold 4 of 3` never appears. `<KindWord>` mirrors the phone (`lib/features/routine/routine_setup_screen.dart:1276-1287`): `Hold` for a drill, `Interval` for a timed effort, the modality's round noun (singular of `WatchLoggingState.roundsLabel`, `WatchLoggingState.swift:652-658`) for a round. A slot without a plan keeps today's lines verbatim: a set reads `Next: Set k+1` (stays), a round reads `Next: Period k+1` (stays, unbounded), any other kind moves on after one effort. PR 3's prefixes (D-14907) wrap these lines later and are **not** in this PR.
- **A-14903** (parent, adopted): a wrist-added or ad-hoc slot travels `plannedEfforts: 1` — a plan of 1, which is today's one-effort rule in effect. No carve-out code for it.
- **D-14907 / P-3** (owner-confirmed): the `Next set:` / `Next exercise:` prefixes are PR 3, on top of this PR's lines, unchanged.

New decisions of this plan:

- **D-14910 — Slot kind resolution in `deriveRestLabels`.** `RestLabelSlot` gains a `kind`: the slot's declared `effortKind` when it carries one, else `WatchEffortKind.resolved(capabilities) ?? set` — the exact mirror of `WatchLoggingState.effortKind` (`WatchLoggingState.swift:642-650`). Both plan reads and the done rule key on this one resolved kind: the `plannedSets` count is read only when `kind == set`; `plannedEfforts` is read only when `kind != set`. This is the mirrored-ignore gate of S-14923 made structural, not per-branch.
- **D-14911 — The move line names a later planned non-set slot with its own count** (derived from D-14904 — vetoable): the not-done search's announcement for a planned non-set slot reads `Next: <name> · <KindWord> k of N`, k = that kind's logged count + 1, N = `max(plan, k)`. Options: a bare name (a planned set would then be the only announced count — inconsistent) vs the exact mirror of the set move line `\(name) · Set \(sets+1) of \(planned)` (`WatchRestLabels.swift:63-66`, chosen). A later slot with no plan keeps today's bare name.
- **D-14912 — The round stay gate sits in `WatchLoggingState`** (the parent plan's seeded placement): `restLabels` (`WatchLoggingState.swift:533-548`) passes `nextRound` only when the current round slot has **no** plan (today's unbounded line, unchanged); for a planned round it passes nil, and `deriveRestLabels` builds the stay line from its own counts and the new `roundNoun` parameter, or runs the move search when the plan is met. Contract note for the pure function: `nextRound` non-nil henceforth means "an unplanned round stays" — a caller that passes it for a planned round gets today's unbounded line, which is why the gate lives at the one production caller.
- **D-14913 — Defense in depth on the slot map.** `plannedEfforts` read as anything other than an integer ≥ 1 (0, fractional, string, missing) is treated as the key's absence. The schema already refuses such a frame (`S-14905`, PR 1); this rule only keeps a hand-built slot map from wedging the wrist.
- **D-14914 — The `now` line is untouched.** `· Set k done` stays set-only (`WatchRestLabels.swift:104-108`); every other kind's `now` is the exercise name, as today. D-14904 names only the next line.

## Feature Invariants

- **Mirrored ignore gates**: a set slot never reads `plannedEfforts`; a non-set slot never reads `plannedSets` — in `deriveRestLabels` (D-14910) and in `WatchLoggingState` alike. The two keys never both apply to one slot.
- **No plan ⇒ today's rule bit-for-bit**: for a slot with no plan, PR 2's labels equal PR 1's labels for the same entries (P-1's carve-out). Guarded by S-14926 and by every existing test in `WatchRestLabelsTests` / `WatchRestNextHoldTests` staying green.
- **A planned stay line names no slot**: `nextSlotId` is nil for it, so `leaveRest` (`WatchLoggingState.swift:493-507`) stays on the exercise — the same contract the planned-set stay line already has.
- **Never wedged, never refused (P-2)**: the wrist counts past the plan; every `k of N` in this PR uses N = `max(plan, k)`, so `4 of 3` is unprintable. The plan itself never grows on the wrist — the phone's projection grows it (D-14902, PR 1's committed half).
- **Set-value behaviour untouched**: `plannedSets` dialling, `setCaption`, the planned `initialValue` (`WatchLoggingState.swift:334, 698-707, 857`) are plan 36b's and stay byte-identical; this PR only adds a parallel read for the other kinds.
- **Swift-only**: no Dart file, no contract file, no fixture changes. The schema/fixture walkers (`SyncProtocolFixturesTests`, `test/sync_protocol_fixtures_test.dart`) must stay green untouched.

## Requirements

- R1 (P-1): Next stays on a planned non-set exercise until its own kind's logged count reaches its `plannedEfforts`, then the not-done search runs (forward, then from the top — today's order, unchanged).
- R2 (P-2): logging past the plan is accepted everywhere; the extra is labelled as its own last number wherever a `k of N` shows; the planned round wedge (a planned round never moving on) is gone.
- R3 (D-14904): the stay/move wordings per kind, exact strings pinned in the scenarios below.
- R4: docs trail code by zero phases — the pager doc's "the engine does not read it yet (plan 149's PR 2)" sentence dies in the phase that makes it false.

## Acceptance Criteria (each maps to ≥ 1 scenario)

- AC10 A planned hold stays until its 3 holds are logged, then Next names the next not-done exercise — S-14920.
- AC11 A planned round stays with `of N` and moves when met; the unbounded wedge is fixed — S-14921.
- AC12 A planned timed effort stays with `Next: Interval k of N` — S-14922.
- AC13 The mirrored ignore gates hold — S-14923.
- AC14 A fourth hold is accepted; the extra reads as its own last number — S-14924 (its visible `Hold 4 of 4` needs the logging caption, Open question 1 / Phase 4).
- AC15 Out-of-order counting keys on the slot id — S-14925.
- AC16 No planned amount keeps today's rule — S-14926.
- AC17 The same frame applied twice changes nothing — S-14927.
- AC28 A `plannedEfforts` of 1 behaves as today's one-effort rule — S-14928.

## Existing-Functionality Impact

Every place that counts efforts or "done", with the grep that found it:

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `deriveRestLabels` (`WatchRestLabels.swift:74-134`) | the change itself; `grep restLabels watch/watchos/Sources` → `WatchLoggingState.swift:533` (`restLabels`), `:494` (`leaveRest` reads `nextSlotId`), `WatchRestView.swift:70, 158` (the two label lines) | The done rule, both plan reads and the stay/move wordings become kind-aware (D-14903/D-14904/D-14910..13) | S-14920..S-14928; every existing `WatchRestLabelsTests` case (S-7601..S-7608, S-9101..S-9107) must stay green |
| `WatchLoggingState` (`WatchLoggingState.swift`) | `:334` (`setCaption`), `:493` (`leaveRest`), `:533-548` (`restLabels`, the `nextRound` construction and the `singular` noun), `:642-650` (`effortKind`), `:652-658` (`roundsLabel`), `:661-669` (`nextRoundNumber`), `:685-693` (`observations`), `:698-707` (`plannedSets` + kind gate), `:709-715` (`setsHeld`), `:857` (planned `initialValue`) | One new private `plannedEfforts` getter beside `plannedSets` (D-14910's state half), one new per-slot round count, and the `restLabels` call site gated per D-14912. Everything else stays set-only and untouched | S-14921 (state half), S-14923, S-14926, S-14927; `WatchPlannedSetsTests` (S-3623..S-3632) stays green |
| `WatchMenu.deriveMenuRows` (Swift) | `grep "WatchObservationKind.efforts"` → `WatchMenu.swift:263-267` (the "N logged" subtitle, all kinds) | None: kind-agnostic count stays | S-14925 (its per-slot reads agree with the new counting) |
| `WatchWorkoutSummary` (Swift) | same grep → `WatchWorkoutSummary.swift:76, 142` (set-block effort counts) | None | — |
| Effort-debt / rating-owed counters | same grep → `WatchSessionEngine.swift:2238`, `WatchEffortRating.swift:181`; `WatchSensorSummaries.swift:316` | None: all three count efforts kind-agnostically and read no plan | — |
| Rest ping | `grep ping` → `WatchRestPing.swift:42-55` (reads the rest timer's id/state only), `WatchRestPingScheduler.swift` (interval-driven) | None: the ping never reads labels or plans | — |
| Health surfaces | `WatchPlatformWorkout.swift` (OS workout lifecycle), `WatchWorkoutSummary.heartRateNote :94` | None: no plan counting reaches them | — |
| Pager / Next / swipe paths | `WatchLoggingPagerView` (its source contract is asserted by `WatchRestNextHoldTests.testThePagerShowsTheEnginesPageUnlessASwipeIsLanding`); `focusSlotId` `WatchLoggingState.swift:719` | None beyond label text: Next's move/stay behaviour keys on `nextSlotId`, whose stay-is-nil contract this PR preserves (Feature Invariant) | `WatchRestNextHoldTests` source assertions + S-14920/S-14926 |
| `WatchRestNextHoldTests.swift` header comment | its premise "Holds carry no planned count on the wire" is stale since PR 1 | Phase 2 item 7 amends the comment; the file's fixtures (no-plan hold ladder) stay valid — they are exactly S-14926's world | the file's own tests |
| Contract + fixtures (PR 1's, committed) | `envelope.schema.json` `$defs.sessionExercise`, `fixtures/{valid,invalid}/session_snapshot_planned_efforts*.json` | Untouched; both fixture walkers must stay green with zero diffs | `SyncProtocolFixturesTests`, `test/sync_protocol_fixtures_test.dart` in the full-package run |

Standing invariants this could break: repository parity — untouched (no repository code); layer boundaries — untouched (`lib/` never appears); the schema contract — untouched (data files committed in PR 1).

## UI Standards Impact

- `WatchRestView.swift`'s next line (`:70`, `:158`): the same text-only change class the wrist's label work has always used — no new control, no layout change, no accent change. The wrist nouns mirror the phone's own (`routine_setup_screen.dart:1276-1287`): the two ends say the same words for the same effort.
- The logging screen's caption for a planned non-set slot: a **product question** (Open question 1, owner to confirm). Today the header's status line (`WatchLoggingModel.statusLine`, `WatchLoggingModel.swift:132-138`) joins `setCaption` (nil for every non-set kind) with the sensor readout. Phase 4 is pre-planned for it and blocked on the owner's answer; its cost is stated there.

## Scenarios

Fixture naming: `slot(id, name, kind, plannedEfforts:, plannedSets:)` builds a wire slot; `entry(slot, kind, n)` builds a `WatchObservationRecord` with `payload["sessionExerciseId"] = slot` and `payload["kind"] = kind` (the helpers exist: `WatchRestLabelsTests.swift:489-519`, `WatchPlannedSetsTests.swift:448-457`; entry kinds are `WatchObservationKind`'s `set/timed/round/hold`, `WatchRecords.swift:50-86`). "k of N" strings are exact — the assertions pin them.

### S-14920: a planned hold stays until its plan, then Next names the next not-done exercise
- Fixture: ladder of three slots — A `drill` "Plank" (capabilities `["hold","time"]`, `plannedEfforts: 3`), B `drill` "Wall Sit" (`plannedEfforts: 2`), C `set` "Bench" (`plannedSets: 2 rows`). Pure-half entries: 1 `hold` for A. State-half fixture: the same two drill slots in a real engine (`createSession`), logging holds through the surface.
- Trigger: `deriveRestLabels(currentIndex: 0, effortKind: "drill", roundNoun: nil, nextRound: nil)` after each hold (state half: `restLabels` after each log).
- Flow: A's own-kind count (holds for A's slot id) is compared with 3.
- Expected outcome: after hold 1, `next` = `"Next: Hold 2 of 3"`, `nextSlotId` nil (Next stays; `leaveRest` moves nothing). After holds 2 and 3, `"Next: Hold 3 of 3"` then the move line `"Next: Wall Sit · Hold 1 of 2"`, `nextSlotId` "B" (D-14911; B is the first not-done slot forward). `now` is `"Plank"` throughout (D-14914).
- Edge case of: none (the parent behaviour).

### S-14921: a planned round stays with `of N` and moves when met; the unbounded wedge is fixed
- Fixture: A `round` "Sports Drill" (`effortKind: "round"`, `plannedEfforts: 3`, `roundDurationSecs: 180`), B `set` "Bench" (`plannedSets: 2`). Pure-half entries: 1 `round` for A, `roundNoun: "Period"`, `nextRound: nil` (the caller's gate has already withheld it — D-14912). State-half fixture: a real engine, modality `sports` (so `roundsLabel` = "Periods", `WatchLoggingState.swift:652-658`), the planned round slot first.
- Trigger: `deriveRestLabels(currentIndex: 0, effortKind: "round", roundNoun: "Period", nextRound: nil)` after each round; state half: `restLabels` after each logged round.
- Expected outcome: after round 1, `next` = `"Next: Period 2 of 3"`, `nextSlotId` nil — **not** today's unbounded `"Next: Period 2"`; after round 3, the move line names B (`"Next: Bench · Set 1 of 2"`). The state half asserts the same strings through `restLabels`, with `nextRoundNumber` (`:661-669`) feeding k through the gate — the wedge (a planned round that never moves on) is gone.
- Edge case of: S-14920.

### S-14922: a planned timed effort stays with `Next: Interval k of N`
- Fixture: A `timed` "Row Intervals" (`effortKind: "timed"`, `plannedEfforts: 3`), B `drill` "Plank" (`plannedEfforts: 1`). Entries: 1 `timed` for A.
- Trigger: `deriveRestLabels(currentIndex: 0, effortKind: "timed", roundNoun: nil, nextRound: nil)` after each interval.
- Expected outcome: `"Next: Interval 2 of 3"` then `"Next: Interval 3 of 3"` (both with nil `nextSlotId`), then `"Next: Plank · Hold 1 of 1"` — B is the first not-done slot forward, planned 1 with no entries, announced by D-14911's mirror of the set move line.
- Edge case of: S-14920.

### S-14923: the mirrored ignore gates
- Fixture (a): a `set` slot "Bench" (`plannedSets: 2 rows`, `plannedEfforts: 3` — a hand-built slot; the phone never sends both, D-14901) with 1 `set` entry. Fixture (b): a `drill` slot "Plank" (capabilities `["hold","time"]`, `effortKind: "drill"`, `plannedSets: 2 rows`, no `plannedEfforts`) with 1 `hold` entry. State half: the same two slots through the engine (`WatchPlannedSetsTests`' harness), reading `setCaption` / `restLabels`.
- Trigger: `deriveRestLabels(currentIndex: 0, effortKind: "set"/"drill", …)`.
- Expected outcome: (a) the set rule alone applies: `"Next: Set 2 of 2"` — `plannedEfforts` never becomes a hold/interval/round count for a set slot (D-14910's gate; the mirror of `testS3632AHoldSlotIgnoresTheKey`, `WatchPlannedSetsTests.swift:329`). (b) the drill is done after its one hold (no plan) and the line moves to the next not-done slot; its label never reads `Set …` — `plannedSets` is unread for a non-set slot.
- Edge case of: S-14920.

### S-14924: a fourth hold is accepted and the extra reads as its own last number
- Fixture: S-14920's slot A with 4 `hold` entries (the fourth logged through the real engine in the state half: Start, hold, Log a fourth time — never refused, never wedged).
- Trigger: the labels after the fourth hold.
- Expected outcome: A is done (4 ≥ 3) and the move line fires (`"Next: Wall Sit · Hold 1 of 2"`); nothing prints `4 of 3` anywhere — the stay-line branch never runs past the plan, and D-14904's `N = max(plan, k)` makes the extra its own last number wherever a count shows. The extra's own `Hold 4 of 4` reading needs the logging caption (Open question 1 / Phase 4); this scenario pins the acceptance and the absence of a wedge.
- Edge case of: S-14920.

### S-14925: out-of-order counting keys on the slot id
- Fixture: three `drill` slots — A "Alpha", B "Bravo", C "Charlie", each `plannedEfforts: 2`. Entries: 1 `hold` for C, 1 `hold` for A. `currentIndex: 0` (the surface sits on A).
- Trigger: `deriveRestLabels(currentIndex: 0, effortKind: "drill", …)` with A's count at 1.
- Expected outcome: `"Next: Hold 2 of 2"`, `nextSlotId` nil — C's logged hold never completes A's or B's plan (the counting filter keys on `sessionExerciseId`, `WatchRestLabels.swift:89-93`). After A's second hold: `"Next: Bravo · Hold 1 of 2"`, `nextSlotId` "B" — B's own logged count is 0, so k = 1; the per-slot counts stay per-slot in the move line too. When the search later reaches C (after B is done), it reads `"Next: Charlie · Hold 2 of 2"` — C's own entry is the count.
- Edge case of: S-14920 (the counting rule is the existing per-slot filter, `WatchRestLabels.swift:89-93`, now per kind).

### S-14926: no planned amount keeps today's rule
- Fixture: A `drill` "Plank" (no `plannedEfforts`) with 1 `hold` entry; B `set` "Squat" (no `plannedSets`) with 1 `set` entry, ladder A then B, `currentIndex: 1`, `effortKind: "set"`. Also the free-workout half: `WatchRestNextHoldTests`' existing no-plan hold ladder (its fixtures are exactly this world).
- Trigger: the labels for each.
- Expected outcome: A is done after its one hold and the line moves (`"Next: <B> · Set 2"` — the existing bare `Set k+1` stay line for the unplanned set, B, `nextSlotId` nil); the free hold ladder's existing assertions (`testNextMovesTheSessionBeforeTheRestSurfaceIsReleased` etc.) stay green unchanged. A no-plan slot's labels equal PR 1's output bit-for-bit.
- Edge case of: S-14920.

### S-14927: the same frame applied twice changes nothing
- Fixture: the S-14920 wire shape as a real snapshot frame (slot A with `plannedEfforts: 3`, one imported hold entry) through `engine.applyMessage`.
- Trigger: `applyMessage(frame)` twice, then `restLabels`.
- Expected outcome: identical labels both times, `engine.entries.count` unchanged, A's plan still 3 — the engine's frame idempotence (`S-1411`'s class) extends to the new read with no new state.
- Edge case of: S-14920.

### S-14928: a `plannedEfforts` of 1 behaves as today's one-effort rule
- Fixture: two ladders — A1 a `drill` slot with `plannedEfforts: 1`, A2 the same slot shape with no key; both with 1 `hold` entry and the same B after them.
- Trigger: the labels for each.
- Expected outcome: A1's and A2's labels are equal (`now` the name; `next` the same move line) — a plan of 1 is today's one-effort rule in effect (A-14903), so a wrist-added slot is indistinguishable from an unplanned one.
- Edge case of: S-14920.

## Iteration 1 — PR 2 (Swift watch only)

### Phase 1: the pure rule (@developer)
1. [ ] Extend `RestLabelSlot` with `kind` (D-14910's resolution: declared `effortKind`, else `WatchEffortKind.resolved(capabilities) ?? set`), per-kind counts `holds` / `timed` / `rounds` (kinds `hold` / `timed` / `round` of `WatchObservationKind`, `WatchRecords.swift:50-60`), and `plannedEfforts: Int` — `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift`, symbol `RestLabelSlot` + the slot-building loop in `deriveRestLabels` (:88-101)
2. [ ] Gate the two plan reads on the resolved kind — same loop: `planned` (the `plannedSets` count, :98) read only when `kind == WatchEffortKind.set`; `plannedEfforts` read only when `kind != WatchEffortKind.set`, as `(slot["plannedEfforts"] as? Int).flatMap { $0 >= 1 ? $0 : nil } ?? 0` (D-14913) — symbols: the `planned:` argument and the new `plannedEfforts:` argument
3. [ ] Make `isDone` kind-aware — same file, symbol `RestLabelSlot.isDone` (:62): `plannedEfforts > 0 ? ownKindCount >= plannedEfforts : (planned > 0 ? sets >= planned : efforts > 0)`, `ownKindCount` selected by `kind` (D-14903)
4. [ ] Add the kind word and the count-bearing labels — same file: a `kindWord(for:)` helper on `RestLabelSlot` (`drill`→"Hold", `timed`→"Interval", `round`→`roundNoun ?? "Round"`, else nil), `nextLabel` (:63-66) gaining the planned non-set branch `"\(name) · \(kindWord) \(count+1) of \(max(plannedEfforts, count+1))"` (D-14911), and a new `roundNoun: String? = nil` parameter on `deriveRestLabels` (:74) — the default keeps every existing call compiling
5. [ ] Rewrite the stay/move branches for the current slot — same file, the kind branches in `deriveRestLabels` (:104-124): a planned non-set slot short of its plan returns `next: "\(prefix)\(kindWord) \(k) of \(N)"`, `nextSlotId: nil` (k = own count + 1, N = max(plan, k)); a planned round ignores `nextRound` (D-14912's contract) and stays/moves by its counts; a no-plan kind falls through exactly as today — symbol: the `effortKind == WatchEffortKind.set` / `== WatchEffortKind.round` branch block
6. [ ] Red→green the pure group — `watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift`, new group `S-14920 the wrist counts each kind against its own plan`: `S-14920`, `S-14921` (pure half, `roundNoun: "Period"`), `S-14922`, `S-14923` (both gates), `S-14924`, `S-14925`, `S-14926`, `S-14928` — one test per scenario, fixtures exactly as stated, reusing the `slot(...)` / `entries(..., kind:)` helpers (:489-519); assert `nextSlotId` in every case
7. [ ] Prove the red first — `.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --filter WatchRestLabelsTests` (the new group must fail at HEAD: today a planned hold reads done after one effort); record the table in the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchRestLabelsTests` (new group green, every existing case in the file still green); then `.github/copilot/scripts/macos/gateway.sh swift-test` (full package — `WatchPlannedSetsTests`, `WatchRestNextHoldTests`, `WatchMenuTests`, the summary and fixtures suites included). `flutter analyze` is quoted against the 181-issue baseline only if a Dart file changed — none is predicted; state "not run, no Dart change" in the evidence file if none did.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift`; `watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift`; the evidence file. Nothing else.
**Phase 1 verification notes (Conductor, date):** —

### Phase 2: the state layer and the round gate (@developer)
1. [ ] Add the state-half plan read — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`: a private `plannedEfforts: Int?` getter beside `plannedSets` (:698-707), gated `effortKind != WatchEffortKind.set` and `>= 1` (D-14910's mirror, D-14913) — symbol: `plannedEfforts`
2. [ ] Add the per-slot round count — same file: a private `roundsHeld: Int` beside `setsHeld` (:709-715), `observations.filter { $0.payload["kind"] as? String == WatchObservationKind.round }.count` — symbol: `roundsHeld`
3. [ ] Gate the round stay-line — same file, `restLabels` (:533-548): pass `nextRound` only when `effortKind == WatchEffortKind.round && plannedEfforts == nil` (today's unbounded line survives verbatim for no-plan rounds; a planned round gets nil and Phase 1's count rule); pass `roundNoun: singular` (the `singular` already computed at :541-543) — symbol: `restLabels`
4. [ ] Red→green the state group — `watch/watchos/Tests/WatchSessionEngineTests/WatchRestNextHoldTests.swift`, new cases: `S-14921 a planned round moves on when its plan is met` (real engine, modality `sports`, rounds logged through the surface; the wedge string `"Next: Period 2 of 3"` then the move line), `S-14924 a fourth hold is accepted` (real engine, four logs on one planned-hold slot), `S-14925 a planned ladder counts out of order per slot` (planned-hold ladder, jump C → A → assert A stays short), `S-14926` assertion added beside the existing no-plan cases, `S-14927 the same frame twice changes nothing` (`applyMessage` twice, labels equal, entries count unchanged) — symbols: the new test methods
5. [ ] Red→green the mirrored gates at state level — `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift`: `S-14923 a set slot ignores plannedEfforts` (a slot carrying both keys; `setCaption` still `"Set 2 of 2"`, `restLabels` still the set rule) and `S-14923 a drill slot ignores plannedSets` (the existing S-3632 fixture shape now also asserted through `restLabels`) — symbols: two new test methods in the S-3631/S-3632 group
6. [ ] Re-run the neighbour suites — the full package covers it; call out in the evidence file: `WatchRestNextHoldTests`'s existing tests (the no-plan ladder is S-14926's world — all stay green), `WatchPlannedSetsTests` S-3623..S-3632 (set behaviour byte-identical), `WatchMenuTests` / summary suites (kind-agnostic counters)
7. [ ] Amend the stale header comment — `watch/watchos/Tests/WatchSessionEngineTests/WatchRestNextHoldTests.swift` (file header): "Holds carry no planned count on the wire" → the plan now travels as `plannedEfforts` (plan 149 PR 1) and PR 2 counts it; the file's no-plan fixtures remain the no-plan world — symbol: the header comment block only, no test body changes

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchRestNextHoldTests`, `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchPlannedSetsTests`, then `.github/copilot/scripts/macos/gateway.sh swift-test` (full package). No Dart change: state "not run" for `flutter analyze`.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`; `watch/watchos/Tests/WatchSessionEngineTests/WatchRestNextHoldTests.swift`; `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift`; the evidence file. Nothing else.
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: docs trail code by zero phases (@developer)
1. [ ] Kill the stale sentence — `docs/state_management/watch_surface_wrist_pager.md:59-63`: "the engine does not read it yet (plan 149's PR 2), so one logged hold makes the exercise done…" → the engine counts each kind against its own `plannedEfforts` (D-14903/D-14904), the rest line reads `Next: Hold k of N` while short and moves when met; keep the per-slot-counting sentences (still true); cite `WatchRestLabels.swift` / `WatchRestNextHoldTests.swift`
2. [ ] Extend the wrist-consumption paragraph — `docs/watch_session_sync.md` (the planned-rows paragraph, `plannedEfforts` block at :152-161): append the wrist half — the wrist counts each non-set kind against the key (D-14903), the mirrored ignore gates (D-14910), the stay/move wordings per D-14904, and the guarding tests (`WatchRestLabelsTests` S-14920.., `WatchRestNextHoldTests` S-14921/S-14924/S-14925, `WatchPlannedSetsTests` S-14923)
3. [ ] Amend the not-synced page's consumer clause — `docs/watch_session_sync/what_does_not_sync.md:24, 306-308`: the `plannedEfforts` clause gains "consumed on the wrist by `deriveRestLabels`/`WatchLoggingState` (plan 149 PR 2)" beside PR 1's phone half
4. [ ] Residue sweep — grep `does not read it yet` over `docs/` (zero live matches left; plan-file mentions are historical artefacts) and record both greps in the evidence file

**Done Criteria**: the residue greps of item 4 recorded; `.github/copilot/scripts/macos/gateway.sh swift-test` (full package, one final green run over the whole PR); no Dart change, so `flutter analyze`/`flutter test` state "not run" in the evidence file.
**Predicted Files**: `docs/state_management/watch_surface_wrist_pager.md`; `docs/watch_session_sync.md`; `docs/watch_session_sync/what_does_not_sync.md`; the evidence file. Nothing else.
**Phase 3 verification notes (Conductor, date):** —

### Phase 4: the logging caption for a planned non-set slot (@developer) — BLOCKED on Open question 1 (owner to confirm)
The owner's confusion was believing they stayed on the same exercise; P-3 (PR 3) fixes that on the rest screen. Whether the **logging** screen should also show `Hold 2 of 3` is a product question (Open question 1). Run this phase only if the owner confirms; the plan closes after Phase 3 otherwise. Cost if confirmed: one getter beside `setCaption` (`WatchLoggingState.swift:334-341`, same `k of max(N, k)` shape, D-14904's kind words), one `compactMap` part in `WatchLoggingModel.statusLine` (`WatchLoggingModel.swift:132-138` — the line already renders when either part exists, so no layout change, but on a 40 mm screen a caption can now coexist with a sensor readout: keep both parts short), tests beside the set-caption group, one doc sentence in `docs/watch_session_sync.md`'s planned-rows paragraph. Estimated production diff ~25 lines.
1. [ ] Add the non-set caption getter — `WatchLoggingState.swift`, symbol `effortCaption` (beside `setCaption`: nil unless `plannedEfforts != nil`; `"Hold 2 of 3"` / `"Interval 2 of 3"` / `"\(roundNoun-ish singular) 2 of 3"` per D-14904)
2. [ ] Join it into the header — `WatchLoggingModel.swift`, symbol `statusLine` (:132-138): `[state.setCaption ?? state.effortCaption, sensorLine]` (never both — the two are exclusive by kind)
3. [ ] Tests — `WatchPlannedSetsTests.swift`: `S-14924 the extra reads Hold 4 of 4` (the fourth hold's caption) and the short-of-plan captions per kind; `WatchRestLabelsTests` stays as the rest-line authority
4. [ ] Doc sentence — `docs/watch_session_sync.md` planned-rows paragraph: the logging header's caption per kind

**Done Criteria**: `swift-test --filter WatchPlannedSetsTests` then the full package; the caption strings asserted exactly.
**Predicted Files**: `WatchLoggingState.swift`; `WatchLoggingModel.swift`; `WatchPlannedSetsTests.swift`; `docs/watch_session_sync.md`; the evidence file. Nothing else.
**Phase 4 verification notes (Conductor, date):** —

### Phase X.Y: remediation — none open at planning time
Any defect the reviewer opens here must carry its structural guard: a permanent test making that defect class impossible to reintroduce.

## Files Affected (whole PR)

- `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift` (Phase 1)
- `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` (Phase 2; Phase 4 if confirmed)
- `watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift` (Phase 4 only)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift` (Phase 1)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchRestNextHoldTests.swift` (Phase 2)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift` (Phase 2; Phase 4 if confirmed)
- `docs/state_management/watch_surface_wrist_pager.md`; `docs/watch_session_sync.md`; `docs/watch_session_sync/what_does_not_sync.md` (Phase 3)
- Read-only dependents (re-verified, never edited): `WatchRestView.swift`, `WatchLoggingPagerView.swift`, `WatchMenu.swift`, `WatchWorkoutSummary.swift`, `WatchSessionEngine.swift`, `WatchEffortRating.swift`, `WatchRestPing.swift`/`WatchRestPingScheduler.swift`, the platform/Health surfaces, the PR 1 contract files, and everything under `lib/` (no Dart twin — grep proof in Overview).

## Notes

- Phase graph: 1 → 2 → 3; 4 is blocked on the owner and independent of 3 (it may run before or after 3 once confirmed). Phase 1 alone changes no runtime behaviour that a user can see except through `WatchLoggingState`'s call — the default `roundNoun: nil` keeps the call site compiling, so every intermediate state builds and the package stays green after each phase.
- The round gate's placement (D-14912) means Phase 1's pure tests for S-14921 pass `nextRound: nil` for planned rounds: the caller contract narrows in the same PR that uses it, so no caller can regress silently.
- The parent plan's "extended only where PR 2's plan names it" for `WatchRestNextHoldTests.swift` is honoured: Phase 2 items 4 and 7 are the named extensions; the file's existing tests are the S-14926 regression set and are not edited.
- `flutter analyze` / `flutter test` are out of this PR's loop: no Dart file is predicted to change. The evidence file records "not run, no Dart change" per phase rather than a stale number.
- The owner statement 2026-11-12 (the wrist must know the initial plan and never wedge past it) is satisfied by D-14903 + D-14904's `max(plan, k)`: the plan travels from the phone (PR 1, committed), the wrist only counts and labels.

## Progress

- [ ] PR 2 planned (this file) — planner run 2026-11-12
- [ ] Phase 1 (the pure rule) — @developer
- [ ] Phase 2 (the state layer and the round gate) — @developer
- [ ] Phase 3 (docs trail code) — @developer
- [ ] Phase 4 (the logging caption) — @developer — BLOCKED on Open question 1

## Assumption Log

Executors append here (decision, options considered, choice + why, ≤ 3 lines each); the conductor marks RATIFIED (promote to D-x) or REVERT (remediation).

- **A-14910** (planner, derived — vetoable, promoted to D-14911): the move line names a later planned non-set slot with `· <KindWord> k of N`. Options: bare name (inconsistent with the set move line) vs the set line's exact mirror (chosen). If the owner prefers bare names, a superseding entry replaces D-14911 and S-14920/S-14921/S-14922's move-line strings change.
- **A-14911** (planner, derived — vetoable): `roundNoun` nil falls back to `"Round"` (the default modality's noun) rather than crashing or omitting the word. Only a direct pure-function caller without the noun can reach it; the production caller always passes the modality's singular.
- **A-14912** (planner, derived — vetoable): PR 2 excludes the logging-screen caption pending the owner (Open question 1); the acceptance half of S-14924 is still pinned without it. If confirmed, Phase 4 runs and S-14924 gains its caption assertion.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]
