# Review — plan 20, the watch menu

Base commit reviewed: 433eace (Phase 2 uncommitted working tree) + untracked `WatchMenuView.swift`.
Brief: `.work/watch-20/brief-review-1.md`.

## Scope

Layers in scope: watch/watchos Swift package sources + tests, `ios/OmniTrain Watch App/ContentView.swift`, watch docs.
Layers skipped: Flutter `lib/data/`, `lib/state/`, `lib/features/`, `lib/widgets/`, `lib/core/` (untouched by this change).

## Acceptance criteria

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | One toolbar control, the menu button | ✅ PASS | `ContentView.swift:234-241` — only `.topBarTrailing`; the `.topBarLeading` End item is gone |
| 2 | One row per exercise, order, count, current marked | ✅ PASS | `WatchMenu.swift:56-80`; `WatchMenuView.swift:110-124` (`.borderedProminent` on the current row) |
| 3 | A row jumps and closes; nothing edits/deletes/reorders | ✅ PASS | `WatchMenuView.swift:96-100` → `WatchMenu.swift:117-122` (`paths.selectExercise`) |
| 4 | Add exercise (add-only) + Finish == End | ✅ PASS | `WatchMenuView.swift:72-79` (nested add-only picker, both dismissals), `:128-137` → `WatchMenu.swift:126-128` (`rating.end()`) |
| 5 | Reachable only from the logging surface; no rest control | ✅ PASS (code) / 🟡 guard gap below | `ContentView.swift:243`; `WatchMenu.swift:118` has no rest/edit/delete token |
| 6 | Suites and builds green | ✅ PASS | `swift-test` 403/0; docs contract 9/9; governor's watch build succeeded |

## Findings

1. **major** — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift:508-516` — S-1108's source scan reads only `WatchMenu.swift`, so a rest, edit or delete control planted in `WatchMenuView.swift` (the file that renders the menu, and the only place such a control could appear) would leave acceptance criterion 5 and D-1106 unguarded. Fix: read `WatchMenuView.swift` through the same `Fixtures.sourcesRoot` walk and assert the same four tokens against it (a text read — no compile required, so the `#if os(watchOS)` gate does not block it; all four tokens are absent from the file today). @developer
2. **minor** — `docs/plans/2026-10-08-18-watch-qa-index.md:22` — row 20 still reads `planned — @developer Phase 1` while `## Progress` says Phase 2 complete and the governor's build succeeded; the plan (P2.5) makes the flip conditional on that build. Fix: set row 20's status to the landing state (governor step). @governor
3. **minor** — `docs/plans/2026-10-08-18-watch-qa-index.md:22` / plan file — the plan's own record is inconsistent: line 3 still reads "Next handoff: @developer (Phase 1)" and Phase 2's items (lines 269-306) are unchecked `[ ]` while `## Progress` says "2 | Complete". Fix: tick Phase 2's items and update the Next-handoff line. @developer
4. **minor** — `docs/watch-app-setup-and-qa.md:399,401,528,543,577` and `docs/watch_session_capture.md:227,233,246,252,254,273,279,315` — the live docs still call the wrist's end "End" (e.g. walkthrough heading "**End and answer once**") while the only control that ends the session is now labelled **Finish**; a reader who follows the heading looks for a control that no longer exists. Fix: one naming pass ("the wrist's own end (Finish)") or, better, a pointer to `WatchMenuTests.testS1107FinishEndsAndOwesTheRating`. @developer
5. **minor** — `docs/watch_session_capture.md:3` — the scope declaration claims the doc "describes the phone half", yet the changed row (`:229`) and the surrounding prose (`:227-315`) document the wrist's rating state and its `WatchEffortRatingState`. Under-claiming declaration (4d rule 5): verified in full anyway; widen the declaration when the doc is next touched. @developer
6. **minor** — `docs/plans/2026-09-21-13-watch-integration-shipping.md:764` — the archived shipping checklist still names `WatchEndSessionView`, which no longer exists. Archived plan; fix only if archive plans are kept honest. @governor
7. **suggest** — `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:404-419` — the `pickerRows` property and `pickerRows(addOnly:)` are two copies of the same derivation; the property could delegate to `pickerRows(addOnly: false)`, keeping the "exact signature and behaviour" the plan asked for. @developer
8. **suggest** — acceptance criterion 4's "closes everything" (the nested-sheet dismissal) and criterion 1's single control have no automated guard — they are view-only and the plan routes them to the governor's build plus walkthrough step 3. No action required; recorded so the gap is explicit rather than implied by a green suite. @governor

## Change-specific checks

- **Diff vs Predicted Files** — conforms. Every Phase 1 and Phase 2 predicted file is present; `docs/plans/2026-10-08-18-watch-qa-index.md` and `WatchMenuView.swift` (untracked) are the only names outside a per-phase list, and both are planned.
- **Test run** — `swift-test` → **403 passed, 0 failures** (14 of them `WatchMenuTests`); `test/docs_indexing_contract_test.dart` → **9/9**. Both pasted, not claimed.
- **prove-red** — `prove-red 433eace swift-test -- …/WatchMenuTests.swift` → **RED AT 433eace (exit 1)**, but by *compile* error (`cannot find type 'WatchMenuState'`, `cannot find 'deriveMenuRows'`), so it proves the file is new, not that any single guard is discriminating. Per-guard evidence is the evidence file's mutation table (`2026-10-09-20-watch-menu-plan.evidence.md:56-70`); its seven rows name the failing assertion, the file:line and the exact mismatch, and each is consistent with the code as written. Spot-checked by reading: S-1110 (the `WatchObservationKind.efforts` filter), S-1111 (ladder index vs derived position), S-1112 (no caching), S-1109 (`engine.entries` vs `observations`) all have a discriminating mechanism in `WatchMenu.swift`.
- **No test asserts the removed behaviour** — `grep WatchEndSessionView` leaves zero test hits; `pickingExercise` survives only in `WatchStartView`'s own start-screen sheet (intended).
- **Impact rows (4g)** — one stale row: the `WatchExercisePickerView.init` row names `ios/OmniTrain Watch App/ContentView.swift:245` as a reader, but Phase 2 replaced that mount with the menu; the reader is now `WatchMenuView.swift:72` (`addOnly: true`). All other rows' greps still match; no unlisted reader of `selectExercise`, `rating.end()` or `derivePickerRows` was found.
- **Menu writes** — `WatchMenu.swift` touches no store: the jump is `paths.selectExercise`, the add is the picker's `selectExercise`, Finish is `rating.end()` → `engine.finishSession()`. No id minting, no `insertExercise`, no appended observation (D-1107).

DOC FALSIFICATION: 🟡 WARNING (2 implicated) — `docs/state_management/watch_surface.md` (no false claim found: the second-surface clause now names list button → rows, Add exercise, Finish; its scope declaration covers `watch/watchos/Sources/WatchSessionEngine/`, so it is correctly implicated) · `docs/watch-app-setup-and-qa.md` (no false claim found; scope line, so implicated by every change) · 🟡 SCOPE — `docs/watch_session_capture.md:3` under-claims (see finding 5) · ⚠️ archived plans under `docs/plans/` still name `WatchEndSessionView` (`2026-09-21-13-watch-integration-shipping.md:764`, `2026-10-05-15c-…:107,309`, `2026-09-25-02-…:2021`); recorded as records, not corrected (finding 6).
DOC STANDARD: ✅ PASS — the doc diff adds no walkthrough narration, no restated numeric, no copied code and no roadmap note; it deletes prose rather than adding it, and `docs_indexing_contract_test` is green.
IMPACT: 2 of 9 rows stale-or-narrower (`WatchExercisePickerView.init` reader moved; `derivePickerRows/pickerRows` row now also feeds `WatchMenu.swift` and `WatchStartView.swift:219`); 0 unlisted readers found.

**Verdict:** no blockers. One major (finding 1) is a cheap single-test widening; findings 2-3 are record hygiene; 4-6 are documentation naming. `swift-test` 403/0 and the docs contract 9/9 are pasted above.

**Governor actions requested:** flip `docs/plans/2026-10-08-18-watch-qa-index.md` row 20's status (finding 2); delete nothing — no scratch files were created by this review.
