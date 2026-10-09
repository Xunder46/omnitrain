# Plan 20b — the watch menu shows only the session: no Add exercise, one row per exercise

> Status: CLOSED — built and committed; governor-reviewed (no independent review run: small removal patch). swift 404/0, docs contract 9/9, xcodebuild OK. Follows plan 20.
> Evidence: `2026-10-09-20b-watch-menu-session-only-plan.evidence.md` beside this file. Track: Apple Watch client + docs only.

## Goal (owner, 2026-10-09)
Exercises are added on the phone. The watch menu shows only the exercises already in the session, in the session's order.
For an exercise with several sets, the wrist focuses on the current set only: logged sets and future sets are not reachable.

## Acceptance criteria
1. The menu has no **Add exercise** row and presents no picker: rows (one per session exercise, same order, count, current mark, tap to jump), then **Finish**.
2. No exercise outside the session ever appears in the menu, whatever the wrist's fallback catalog holds.
3. The menu has exactly one row per exercise, however many sets are logged or planned; no set rows, no set navigation (logging still records only the next set — nothing to change there).
4. The start screen's own exercise picker (starting a Free workout) is unchanged. Only the menu-only add-only mode is removed.

## Decision Ledger
- **D-1200** Remove `addExerciseRow`, `addExerciseLabel`, the `addingExercise` state and the nested `.sheet` from `WatchMenuView.swift`; the footer is Finish only. `WatchMenuState.paths` (used only for the nested picker) is removed from its public API if nothing else reads it (`jump(to:)` still needs it privately).
- **D-1201** Remove the add-only mode entirely rather than leave it dead: `addOnly` on `WatchExercisePickerView` (`WatchStartView.swift` ~189-219), `pickerRows(addOnly:)` and the `addOnly` parameter of `derivePickerRows` (`WatchStartPaths.swift` ~180-196, ~405-416). The `pickerRows` property returns to its original body (`derivePickerRows(sessionExercises:fallback:)`). The start screen's picker keeps its exact behaviour (acceptance 4).
- **D-1202** Delete tests `testS1105AddOnlyRowsDropTheLadder` and `testS1106PickingAnAddOnlyRowAppendsAndMoves` (their behaviour is removed on purpose) — the evidence file lists the two removed names and why. Every other existing test stays.
- **D-1203** Docs say the menu is exercises + Finish and that exercises are added on the phone: `docs/state_management/watch_surface.md:434`, `docs/watch-app-setup-and-qa.md:177`, the comments in `ios/OmniTrain Watch App/ContentView.swift:221`. Remove words, do not grow `watch_surface.md`.
- **D-1204** Plan 20's record is not rewritten; the QA index row 20 gets a note pointing to 20b.

## Scenarios
- **S-1200** Fixture A (3 slots; Squat has 2 logged efforts) with the fallback catalog populated by {Squat, Pull-up, Dip}: `WatchMenuState.rows.map(\.name) == ["Squat","Bench Press","Row"]` — no Pull-up, no Dip. Red without the change? It passes today (rows never read the catalog) — it is a **negative guard**: mutation = make `rows` append `paths.pickerRows` available entries → red.
- **S-1201** One row per exercise: Fixture A plus 3 more efforts on Row → `rows.count == 3`, Row's `loggedCount == 4`, `countLabel == "4 logged"`; the row type has no per-set field (compile-level) and no row id repeats. Negative guard; mutation: emit one row per effort → red.
- **S-1202** Source guard: `WatchMenu.swift` and `WatchMenuView.swift` contain none of `WatchExercisePickerView`, `addExercise`, `pickerRows`, `fallbackExercises`, `Add exercise`. **Red without the change**: both files name them today (`WatchMenuView.swift:34,72,115`; `WatchMenu.swift` comment `:92`). The existing S-1108 token scan stays.
- **S-1203** The start screen's picker is untouched: the existing `pickerRows` tests at `WatchConnectivityBridgeTests.swift:690`, `:762`, `:803` pass unchanged (and the file is not in the diff).

## Phase 1 (developer, one run, ≤ 6 items)
1. `WatchMenuView.swift` per D-1200; `WatchMenu.swift` per D-1200 (doc comment too).
2. `WatchStartView.swift` + `WatchStartPaths.swift` per D-1201 (remove `addOnly`).
3. `WatchMenuTests.swift`: delete S-1105/S-1106 tests, add S-1200…S-1202.
4. `ContentView.swift` comment line (~221) per D-1203 — comment only; the sheet call to `WatchMenuView` keeps the same arguments.
5. Docs per D-1203; QA index row 20 note per D-1204.
6. Evidence file: `swift-test` counts, mutation proofs for S-1200/S-1201/S-1202, removed test names.

**Done criteria:** `gateway.sh swift-test` green; `gateway.sh test test/docs_indexing_contract_test.dart` green; `gateway.sh lint` = 196 baseline; `WatchConnectivityBridgeTests.swift` not in the diff. Governor runs xcodebuild.

**Predicted files:** `WatchMenu.swift`, `WatchMenuView.swift`, `WatchStartView.swift`, `WatchStartPaths.swift`, `WatchMenuTests.swift`, `ios/OmniTrain Watch App/ContentView.swift` (comment), `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-08-18-watch-qa-index.md`, evidence file.

## Open questions
- Free-workout start still lets the wrist pick from its fallback list (start screen). Left as is; the owner said only the menu.
- The row subtitle still reads "N logged" (a count, not access to those sets). Alternative: show the current set number instead.

## Progress

| Phase | Status |
|---|---|
| 1 | Complete |

| Item | Result |
|---|---|
| 1 `WatchMenuView.swift` + `WatchMenu.swift` (D-1200) | ✅ Add exercise row, label, `addingExercise` state and nested `.sheet` gone; `paths` private; `jump(to:)` reads the slot off the session |
| 2 `WatchStartView.swift` + `WatchStartPaths.swift` (D-1201) | ✅ `addOnly` removed from the picker view, `derivePickerRows` and `pickerRows`; the start screen's rows are unchanged |
| 3 `WatchMenuTests.swift` (D-1202) | ✅ S-1105/S-1106 deleted, S-1200…S-1202 added; 15 tests, 0 failures |
| 4 `ContentView.swift` comment (D-1203) | ✅ Comment says Finish and that exercises are added on the phone; call arguments unchanged |
| 5 Docs (D-1203, D-1204) | ✅ `watch_surface.md` and `watch-app-setup-and-qa.md` reworded (4 bytes shorter), QA index row 20 notes 20b |
| 6 Evidence file | ✅ `2026-10-09-20b-watch-menu-session-only-plan.evidence.md` |

**Done criteria:** `swift-test` 404 tests / 0 failures ✓ · `test test/docs_indexing_contract_test.dart` 9/9 ✓ ·
`lint` 196 = baseline ✓ · `WatchConnectivityBridgeTests.swift` not in the diff ✓. Governor still runs xcodebuild.

## Assumption Log

- **`WatchMenuState.paths` kept, made `private`** (D-1200's "if nothing else reads it"): `jump(to:)` still routes through
  `paths.selectExercise`, so removing it would have meant reimplementing the select path. Nothing outside the class reads it.
- **`jump(to:)` no longer reads `pickerRows`** (S-1202 bans the token): it reads the slot off `engine.session.exercises`
  through a new file-private `menuSlotId(of:_:)`, the same id rule `deriveMenuRows` uses, and passes
  `.inSession(slotId:exercise:)`. S-1103/S-1104 (jump, vanished slot) stay green, so the semantics are preserved.
- **Extra doc trims in `watch_surface.md`** beyond the clause itself ("the shell's second surface" → "the second surface",
  one sentence merged into the em-dash list) so D-1203's "do not grow" holds: 8 lines replaced by 8, net 4 bytes shorter.
- **A stale clause in `WatchMenuView.rowButton`'s doc named the picker** (a banned token); reworded to state only the style
  rule.
- **`pickerRows`'s body was inlined** rather than left delegating to the deleted `pickerRows(addOnly:)`.
- **The reworded `watch_surface.md` sentence carries no new test citation**: D-1203 forbids growing the file, so instead of
  adding a citation line the clause keeps the paragraph's existing section-level references (S-1202 itself is cited in this
  plan and the evidence file). Option considered: adding `(S-1202, WatchMenuTests)` and trimming ~26 more bytes elsewhere.

