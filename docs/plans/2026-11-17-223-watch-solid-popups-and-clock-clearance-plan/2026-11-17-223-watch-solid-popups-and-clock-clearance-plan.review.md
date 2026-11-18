# Review: 2026-11-17-223-watch-solid-popups-and-clock-clearance-plan · P1+P2+P3 · 964dc4c7..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 3 · tests: swift test whole target 1591 tests, 0 failures (lead observed, per brief — not re-run; the brief forbids the full flutter test)
Diff vs Predicted Files: conforms except `watch/watchos/Tests/WatchSessionEngineTests/WatchTimerCueTests.swift` (finding 1); every other changed entry in the diff stat belongs to other runs' work (stats screens, their tests/docs, `.claude/`, `.github/`), not to this plan and not reviewed.

## Findings
1. [Major] `watch/watchos/Tests/WatchSessionEngineTests/WatchTimerCueTests.swift:189` — `testS15107TheMenuFinishesWithTheTapAndNeverOnCancel` pinned the system alert's empty Cancel line (`"Button(WatchMenuCopy.confirmCancel, role: .cancel) {}"`) and had to be edited when the `.alert` was removed, but the file is in neither P1's nor P2's Predicted Files and is absent from the plan's "Existing tests that pin what changes" table and from P1 item 6's rewrite list. A maintainer running the next scope check reads this file as outside the plan's budget. Fix: add `WatchTimerCueTests.swift` to P1's Predicted Files and to the touched-surfaces table with the one-line reason. Guard: none needed — the edit is a pin update, already green.
2. [Minor] `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift:1799` — the rewritten guard's name still reads `testS17102TheViewDiscardsOnlyFromTheAlertsDiscardButton`, but the alert no longer exists (S-22302 forbids it); a maintainer grepping `alert` to find the alert era lands on a name describing removed UI. Fix: rename to a question wording (e.g. `…FromTheQuestionsDiscardButton`) and update any references.
3. [Minor] `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift:312,323,325` — `WatchMenuConfirmationView` hardcodes `4.0`/`10.0` where the rest of the file names `surfaceInset`/`sectionGap` (D-22313 ties 10 pt to the separators' constant). If the menu's gap token changes, the question's layout silently diverges from it. Fix: hoist the two constants (file-private, like `sectionGap`) or pass them in.
4. [Minor] `docs/plans/2026-11-17-223-…plan.md` Progress table — P1/P2/P3 still say "not started" while the work is in the tree; a maintainer reading the plan believes nothing was built. Fix: lead/governor updates the three rows (plan file not in the diff; owner action).

## Questions
1. **No behaviour lost or added.** Old Finish alert: Cancel `role: .cancel {}` (system cleared the flag), Finish `{ haptics.playFinished(); await state.finish(); onFinish() }`. New: Cancel flips `confirmingFinish = false` (same effect), Finish's Task is the same three calls in the same order. Discard: old `role: .destructive { Task { state.discard(); onDiscard() } }`, no haptic; new identical. The empty-End branch survives verbatim in `finishRow` (`if state.hasWorkToSave { confirmingFinish = true } else { confirmingDiscard = true }`, seen in the file). The one presentation difference — the menu is replaced instead of overlaid — is exactly D-22309/D-22314.
2. **D-22302 holds.** The title `Text` carries `.accessibilityAddTraits(.isHeader)` (WatchMenuView.swift:314), the message is its own `Text`, both buttons read from their words and roles; the file has no `.accessibilityLabel` anywhere (asserted by `testS17112TheDiscardRowAndItsConfirmationSpeak`). No invented label.
3. **The wrap changed nothing else.** Every child, gap and modifier kept its order; `.padding(Self.surfaceInset)` stayed on the inner `VStack`; `.onChange(of: revision)` and both `.sheet`s moved one level out (now on the `NavigationStack`, previously on the `ScrollView`) with the exact same lines — the `git-diff -w` view shows only re-indentation.
4. **Docs: every changed sentence names an existing test, exact names verified by grep**: `testS22309TheTileLabelsKeepTheirSides` (WatchPlannedSurfaceSourceTests.swift:397), `testS22301EverySheetWearsTheSolidBackdropOnce` (WatchSheetSoliditySourceTests.swift:26), `testS22305TheStartScreenSitsInATitlelessStack` (:355), `testS22307EachListRowIsOneShape` (WatchMenuTests.swift:998), `testS22308ThePickerSitsInATitlelessStack` (:1038), `testS22302NoMenuQuestionIsASystemAlert` (WatchSheetSoliditySourceTests.swift:112), `testS22310TheEndingsStandASectionGapApart` (WatchMenuTests.swift:1105), `testS20106TheMenuRowsWearTheirColours` (:2216), `testS3401TheMenuCopyIsTheOwnersWords` (:899). The answer orders the docs now state match the code: Finish then Cancel (logging :14, QA step 7), Discard then Cancel (logging :38, QA step 44). No sentence says something the code does not do.
5. **No banned verb.** New names in `watch/watchos/Sources`: `solidSheetBackground()`, `WatchSolidSheetBackground`, `WatchMenuConfirmationView`, `finishQuestion`, `discardQuestion`, `menu`, `labelSideInset` — none starts with update/delete/remove/replace/edit/overwrite/write/clear/purge/wipe/reset/drop/truncate/erase/forget/modify/mutate/destroy/set.

## Prove-red
The brief carries no per-guard prove-red verdicts ("unproven" by the letter of the rule). By construction each new guard asserts source text absent at base 964dc4c7 (`.solidSheetBackground()`, the question builders, the `VStack` wrap, `labelSideInset`), so red-at-base is trivially true; the lead's mutation pass (24/24 killed) is the falsifiability evidence.

## Assumption Log rulings
- A-1 ratify — the QA edits are sentence changes to existing steps, no new QA step.
- A-3 ratify — all three reworded New markers applied; each Old marker is gone from its doc (checked on disk).
- A-2 ratify — `S-223xx` vs the contract's literal `S-223`; no collision seen in the new test names.

## Scenario coverage
S-22301 -> WatchSheetSoliditySourceTests.testS22301EverySheetWearsTheSolidBackdropOnce
S-22302 -> WatchSheetSoliditySourceTests.testS22302NoMenuQuestionIsASystemAlert
S-22303 -> WatchSheetSoliditySourceTests.testS22303TheAccentStillWrapsTheSheets
S-22304 -> WatchSheetSoliditySourceTests.testS22304TheFinishQuestionRunsTheEndInOrder (+ testS15107, testS17102, testS17109)
S-22305 -> WatchPlannedSurfaceSourceTests.testS22305TheStartScreenSitsInATitlelessStack
S-22306 -> WatchSheetSoliditySourceTests.testS22306TheQuestionLivesInsideTheMenuSheet
S-22307 -> WatchMenuTests.testS22307EachListRowIsOneShape
S-22308 -> WatchMenuTests.testS22308ThePickerSitsInATitlelessStack
S-22309 -> WatchPlannedSurfaceSourceTests.testS22309TheTileLabelsKeepTheirSides
S-22310 -> WatchMenuTests.testS22310TheEndingsStandASectionGapApart
S-22311 -> covered by testS22306 (sheet-internal question + both shell closes asserted)
S-22312 -> WatchSheetSoliditySourceTests.testS22312OneQuestionAtATime
S-22313 -> testS22301 (backdrop) + existing testS8965ThePlanPickerSheetAndItsStateExist (title pin, untouched)
No scenario MISSING.

## Docs delta
`docs/state_management/watch_surface_wrist_logging.md` "Finish Workout?" sentence -> applied
`docs/state_management/watch_surface_wrist_logging.md` "Discard session?" sentence -> applied
`docs/state_management/watch_surface_wrist.md` 44 pt grid sentence -> applied
`docs/state_management/watch_surface_wrist.md` ADDED "every sheet on the wrist is solid black" -> applied
`docs/state_management/watch_surface_wrist.md` ADDED "each row is one shape" -> applied
`docs/watch-app-qa-wrist-logging.md` step 7 -> applied
`docs/watch-app-qa-wrist-logging.md` step 44 -> applied
`docs/watch-app-qa-wrist-logging.md` step 45 -> applied
Doc edit the table does not name: the ADDED wrist paragraph also carries a second sentence — "The Start screen sits in a titleless navigation stack, so nothing scrolls under the clock (`testS22305…`)" (watch_surface_wrist.md, the new solid-sheets paragraph). True, names an existing test; the table has no row for it (D-22303/D-22310 have no docs-delta row). Informational, listed for the keeper.
Stale-term sweep over the three docs: no `alert`, `44 pt` or see-through wording remains; the two `capsule` hits (watch_surface_wrist_logging.md:138, :160) are the logging step buttons, out of scope (D-22307). QA :596/:599 "Finish Workout?"/"Discard session?" remain true. The doc sizes could not be measured this run (shell restricted to the gateway script, which has no size check); the P3 keeper's size measurement is on record as the owner of that check.

## UI standards
The diff adds no allowlist entry, raises no ratchet count, and touches no Flutter widget file. The changed watch screens are `#if os(watchOS)` views no test can render — the look is the plan's (owner) checks.