# Review: 216 — the first month says there is nothing to compare yet · P1 build + docs · 82db7759..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not run (brief forbids; builder's run: new file 6 green, sixteen related files green, 4/5 mutants killed, 1 equivalent, plan-lint clean, lint at baseline 181)
Diff vs Predicted Files: conforms (exactly the 4 predicted files; no other file in the stat)
## Findings
1. [Major] `instrument_list.dart:97` — the note's copy overclaims in three reachable non-first-month cases where every row still has `previousValue == null` (`stats_progress_service.dart:1306-1309`: `comparable` needs a previous summary for the same exerciseId AND `best.metric` equality):
   (a) the previous range holds only other exercises — a user who ran last month and lifts this month sees `Nothing to compare yet. Change shows once the 4 weeks before also hold training.` although the 4 weeks before DID hold training (of other exercises);
   (b) the same exercise is trained in the previous range but its best metric changed between windows (e.g. reps-only sessions before, weighted now) — the note claims no earlier training for an exercise that was trained;
   (c) the previous window's value is the zero fallback (`stats_progress_service.dart:1143-1144`, `_zeroValueFor`) with the same metric — `previousValue` is a non-null zero, so the note is hidden and every chip shows a change against zero; the note does not cover that first-month-like case (pre-existing chip behaviour, but the note inherits the gap).
   The behaviour matches D-1/D-3 exactly; the wording (D-4, the lead's default) is what overclaims. Fix: smallest copy change that names the rows rather than the period, e.g. "Nothing to compare for these yet." or drop the second sentence's trigger claim — owner's call. Guard: a case-(a) service fixture asserting what the note says once the wording is decided.
2. [Minor] `instrument_list.dart:114` — the note gate is `section.rows.isNotEmpty` on the FIRST section while `hasComparison` scans all sections: a caller whose first section is empty and second all-new shows no note. Unreachable through the service (a section exists only with a row) and only the hand-built fixtures could hit it, but the consistent gate is `widget.sections.any((s) => s.rows.isNotEmpty)`. Fix: one-line change; guard: none needed beyond S-21601 (behaviour unchanged for service data).
## Assumption Log rulings
- base commit `82db7759` on `claude_develop`: ratify (diff stat matches the predicted file set).
- scenario ids S-216xx unique: ratify (new test file only).
- wording and add-a-line choice are the lead's defaults: ratify as process, but finding 1 escalates the wording itself to the owner.
## Scenario coverage
S-21601 -> test/stats_no_comparison_note_test.dart · `a row with nothing earlier sits under the caption with the note` (text, position between caption and first row, no exception)
S-21602 -> test/stats_no_comparison_note_test.dart · `one row with a previous value means no note` (pins the condition; kills mutation b; would pass at base by design, disclosed in the plan)
S-21603 -> test/stats_no_comparison_note_test.dart · two tests through `StatsScreen` + real service: `one session in the window and none before shows the note` / `the same exercise trained 35 days ago hides the note`
S-21604 -> test/stats_no_comparison_note_test.dart · `S-21604 two sections, all new: exactly one note` (kills mutation c)
S-21605 -> test/stats_no_comparison_note_test.dart · `S-21605 a ten-day window names the ten days before it` (kills mutation d)
No MISSING scenario.
## Question answers (brief)
1. Condition — see finding 1. "No row has a previous value" is not exactly the first-month case; cases (a)/(b) are reachable with earlier training, (c) hides the note while chips compare against zero.
2. Placement — OK. The note renders under the first header for any window shape (`previousRangeFor` at `stats_progress_service.dart:1367-1385` is the same-length range before `fromMs`, so a period-scoped window or a range before the first session behaves like the default case); `hasComparison` scans the uncapped `section.rows` (`instrument_list.dart:108-109`), so a comparable row past the 5-row cap still hides the note. Layout: the note is a plain wrapping `Text`, no fixed width or Row, so 320 dp and large text scale wrap rather than overflow; S-21601 pumps a 400×1600 viewport and asserts `takeException` null.
3. Other readers — OK. `InstrumentList` is built only from `stats_screen.dart:440-443`, gated on `_instrumentSections.isNotEmpty`, so the note never coexists with the empty state. S-4018 (`instrument_list_screen_test.dart:1288-1330`) seeds a day-40 squat session (flagship fixture, `:383-389`), so no note renders there, and even if one did it filters texts containing `Change is against` (the note reads `Change shows once`) and checks header descendants, not Column siblings — unaffected.
4. Docs — OK. The new `stats_screen.md` paragraph (333-338) and `widget_catalog.md:26` sentence say only what the code does and name real anchors (`instrument_no_comparison_note`, `test/stats_no_comparison_note_test.dart`, both exist). Stale-term sweep over `docs/*.md` outside plans/history/releases: `stats_screen.md:312,342,352,355` are the caption/chip statements, still true; nothing stale. No doc edit outside the table's rows.
## Docs delta
`docs/stats_screen.md` ADDED "Nothing to compare yet." -> applied
`docs/stats_screen.md` ADDED `test/stats_no_comparison_note_test.dart` -> applied
`docs/widget_catalog.md` ADDED `instrument_no_comparison_note` -> applied
