# Feature: 206 — the watch logging screen follows the session's modality for exercises the watch adds

> Status: SEEDED by the governor 2026-11-15; APPROVED by the owner 2026-11-15 (the modality decides how to log; a Free session's capability fallback stays as it is, no picker on the watch). Architect step skipped (A-1).
> Next handoff: crew-builder-watch
> Binding conventions: `docs/global_conventions.md`, `docs/modality_tracking.md`, `watch/sync_protocol/PROTOCOL.md` (sessionExercise `effortKind`), `.github/copilot/pr-scope-budget.md`
> Related plans: 176 (modality grid), 201 D-20105 (a pick over a started workout adds the exercise), 1412/1413 (one resolver for kind and round length), 203/204 (modality to the phone)
> Track: watch client only (Swift). No wire change, no phone change.

## Goal and acceptance

Independent review, 2026-11-15: "The logging screen still follows the exercise, not the modality. An exercise that can be sets or timed opens as sets under Cardio on the watch, while the phone would time it." Owner decision, 2026-11-15: **the watch follows the modality**, like the phone.

Finding that keeps this small: the phone already sends every slot of a phone-started session with its `effortKind` declared (`watch_session_adoption_bridge.dart` ~612: `if (_declaredKinds.contains(effort.effortKind)) 'effortKind': …`), and a slot that declares a kind is rendered with it on the wrist (`WatchLoggingState.effortKind`, `RestLabelSlot.kind`). A routine's slots declare theirs too. The only slots with no declared kind are the ones the WATCH creates under a modality: the modality button's exercise (`startModalityWorkout`) and exercises added with Add Exercise (or a pick over a started workout) to a session that has a modality. Those fall back to capabilities. This plan makes the watch declare the kind on those slots, from the modality, the way the phone's `addExerciseToSession` does (`session_core_entry.dart:24-34`).

What the owner sees (same as the phone): Cardio opens the timed screen (Start, then Log), Isometric the hold screen, Resistance sets, Sports rounds ("Periods"), for any exercise picked from the modality button or added during that workout. A Free workout (no modality) and a routine keep today's behaviour. **Accepted consequence (owner to confirm; identical on the phone):** under Resistance a time-only exercise such as a Plank logs as reps; under Cardio a reps-only exercise logs as time.

Acceptance: the scenarios fail on the old code; `swift test` whole target green with observed counts; the watch target builds (lead); no phone or wire change, because the phone already honours a declared kind when it adopts the slot (S-20606).

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-20601 | New pure `WatchEffortKind.forModality(_ modality: String?) -> String?`: `cardio_endurance` to `timed`, `resistance_lifting` to `set`, `isometric_stretching` to `drill`, `sports` to `round`, anything else (nil, an unknown key) to nil. The table is the phone's (`ModalityConfig.effortKind`, `modality_config.dart:60-176`). | `WatchLoggingState.swift` (`WatchEffortKind`, ~line 37-130) |
| D-20602 | `startModalityWorkout(_:with:)` builds the slot as `exercise.toSlot(sessionExerciseId: …, effortKind: WatchEffortKind.forModality(modality))`. `toSlot` already decides the round length from the declared kind (D-1412) and ignores a kind outside `WatchEffortKind.declared`. | `WatchStartPaths.swift` (~804) |
| D-20603 | Add Exercise and a pick over a started workout (`addExerciseToSession`, and the other `toSlot` call near line 898 if it adds to a live session) pass `effortKind: WatchEffortKind.forModality(engine.session?.modality)`. A session with no modality (a Free workout) passes nil and keeps the capability rule. A routine run with a Focus: its OWN slots keep the routine's declared kinds; an exercise ADDED to it takes the Focus's kind (the phone does the same). | `WatchStartPaths.swift` (~831-836, ~898) |
| D-20604 | **Not changed:** `WatchLoggingState.effortKind` and `RestLabelSlot.kind(of:capabilities:)` (a declared kind already wins in both: the screen and the rest labels cannot disagree); the contract's `effortKindParity` (it pins the no-declared-kind rule, still true for a Free workout); the phone (adoption honours the declared kind; `_effortKind`'s modality-blind fallback is only reached by a slot that declares nothing); the wire (`effortKind` is an existing optional slot key). | — |
| D-20606 | A modality button over a held ACTIVE session with no modality (D-20105): the added slot declares the TAPPED modality's kind (`startModalityWorkout` passes `effortKind: WatchEffortKind.forModality(modality)` to `addExerciseToSession`, which takes an optional `effortKind` parameter defaulting to the session modality's kind); the held session's own modality stays unchanged. | `WatchStartPaths.swift` |
| D-20605 | A slot's kind is fixed when the slot is created. A modality that appears later (a phone snapshot stamped on first hearing) only ever applies to the session's first creation, so no slot is re-kinded afterwards. | — |

## Input-reality checklist (answered)

1. **Writers.** The slot's `effortKind` is written only by `toSlot` (this change), by routine starts (`WatchRoutineEffort.slot`) and by the phone projection. The modality key on the session row is written by `createSession` (grid key / routine Focus) and the first-hearing stamp (all filtered to the four grid keys plus the legacy keys, scout sheet 6 Q3).
2. **Lifecycle.** An existing running session keeps its slots as stored (no migration, and a session created before this change keeps capability-resolved slots; accepted, it is a live-session edge case). A relaunch re-reads the stored slot with its declared kind. A deleted/edited exercise on the phone: the wrist slot is its own copy.
3. **Settings.** None.
4. **Time.** None.
5. **Cost.** One dictionary lookup per added slot.
6. **Words.** Docs: the Docs delta. The round noun ("Periods", "Intervals") already follows the modality (`WatchLoggingState.roundsLabel`).
7. **Competition.** Declared kind (routine or this change) beats capabilities; a routine's declared kind beats the Focus's kind for the routine's own slots (D-20603).

## Feature invariants

- A slot the watch creates under a known modality declares that modality's kind (D-20601..D-20603).
- A Free workout slot declares nothing (S-20603).
- The screen and the rest labels read the same declared kind (D-20604, S-20605).

## Existing-functionality impact

| Touched surface | What reads it (scout sheet 6, Q2/Q6) | Effect | Guarded by |
|---|---|---|---|
| Slots built by `startModalityWorkout` / `addExerciseToSession` | `WatchModalityStartTests` (S-17605 family: shape and Health kind of the slot), `WatchSessionStartPathsTests` S-002 tests (`:949`, `:1010`: exercises added to a FREE session resolve by capabilities, `effortKind == set`/`drill`; these have modality nil and stay green), `WatchPlannedSetsTests:435-463` (sessions with a modality and declared slots), `WatchEffortDistanceTests.swift:61` (cardio session, run slot built by hand with no kind: unaffected, it does not go through `toSlot` of a pick) | A slot built under a modality gains an `effortKind` key; tests that compare a whole slot dictionary are listed by the builder (`grep -rn "toSlot" watch/watchos/Tests`) | S-20601, S-20602 |
| `watch_modality_start_contract.json` | no `effortKind` key (scout: none found) | unchanged | — |
| Phone adoption | `_effortKind` honours a declared kind (`watch_session_adoption_bridge.dart:1600-1605`) | A wrist-started Cardio workout is adopted with timed efforts instead of set efforts | S-20606 (phone) |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20601 | `startModalityWorkout("cardio_endurance", with: <exercise with ["sets","reps","time"]>)`; read the slot and `WatchLoggingState.effortKind` | the slot declares `effortKind == "timed"` and the surface renders `timed` | the slot declares nothing and `sets` wins: `set` |
| S-20602 | The same with `resistance_lifting` and a hold exercise `["hold","time"]`; `isometric_stretching` and a reps exercise `["reps","sets","load"]`; `sports` and `["time","rounds"]` | `set`, `drill`, `round` respectively; the round slot carries the exercise's `roundDurationSecs` when the catalog has one | capabilities decide (`drill`, `set`, `round`: only the first two would differ) |
| S-20603 | A Free workout (`startFreeWorkout`), then Add Exercise of `["sets","time"]` | no `effortKind` key on the slot; the surface resolves `set` as today | passes today — pin |
| S-20604 | A session with modality `cardio_endurance` already running; Add Exercise of `["reps","sets","load"]` (and the D-20105 pick over a held empty session with modality set) | the added slot declares `timed` | the added slot declares nothing |
| S-20605 | The rest labels for a two-exercise modality session (S-20601's slot plus an added one): `restLabels` for a logged timed effort | "Interval 2"-style lines come from the same declared kind as the screen (`RestLabelSlot.kind == WatchLoggingState.effortKind` for every slot) | they would resolve by capabilities |
| S-20606 | Phone (Dart, real router and bridge): a wrist snapshot whose slot declares `effortKind: "timed"` for an exercise with `["sets","reps","time"]` | the adopted `SegmentEffort.effortKind == "timed"` (already true; pins that no phone change is needed) | n/a — pin |
| S-20609 | A held active session with modality nil and no exercise; `startModalityWorkout("cardio_endurance", with: <["sets","reps","time"] exercise>)` | the added slot declares `timed`; the session's `modality` is still nil | the slot declares nothing |
| S-20607 | `WatchEffortKind.forModality`: the four keys, nil, `""`, `"strength_resistance"`, `"curling"` | the four kinds; nil for the rest | no function |
| S-20608 | A routine with Focus `isometric_stretching` whose own slot declares `timed`; then Add Exercise | the routine's own slot still renders `timed`; the added one declares `drill` | n/a — pins D-20603's competition rule |

## Phases

**P1 — Swift (owner: crew-builder-watch; scope `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` (the new pure function only), `WatchStartPaths.swift`, a new `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityKindTests.swift`, any existing test file the whole-slot comparisons force (listed in the report), report).** New function name `forModality` avoids the append-only verbs. Items: D-20601..D-20603; tests S-20601..S-20605, S-20607, S-20608.

**P2 — phone pin (owner: crew-builder-app; scope `test/watch_session_wrist_modality_test.dart` is plan 203's file: use a NEW `test/watch_wrist_declared_kind_test.dart`).** S-20606 only (tests only).

**P3 — docs (owner: crew-docs-keeper).** Execute the Docs delta.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_surface_wrist.md | MODIFIED | `the slot keeps the exercise's own capabilities and Health kind` | `the exercise, and the slot declares the modality's effort kind and keeps the` | S-20601, S-20602 |
| docs/modality_tracking.md | ADDED | - | `a slot the watch creates under a modality declares that modality's kind` | S-20604, S-20608 |
| docs/watch-app-qa-wrist-logging.md | ADDED | - | `**The watch logs by the modality — (owner, plan 206).**` | S-20601 |

## Progress

- [x] Seeded by the governor 2026-11-15 (scout sheet 6 read; the phone's slot projection read in code).
- [x] P1 Swift
- [x] P2 phone pin
- [x] P3 docs
- [x] Prove, review, report

## Assumption Log

| # | Assumption | Source | Status |
|---|---|---|---|
| A-1 | The architect step is skipped: the seed names files, symbols and fixtures. | lead | open |
| A-2 | **Owner to confirm:** under Resistance a time-only exercise (Plank) logs as reps and under Cardio a reps-only exercise logs as time, exactly as on the phone. | scout sheet 6 | open |
| A-3 | A session already running when the watch app updates keeps its capability-resolved slots (no migration). | lead | open |
