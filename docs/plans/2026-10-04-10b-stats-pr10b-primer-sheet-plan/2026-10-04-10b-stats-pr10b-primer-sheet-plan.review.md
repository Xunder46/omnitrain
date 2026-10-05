# Review — Stats PR 10b (primer sheet)

Base commit: 01b8a0e

## Findings

1. **MAJOR — `lib/features/stats/widgets/stats_primer_sheet.dart:69`** — the sheet body is a
   non-scrollable `Column(mainAxisSize: MainAxisSize.min)` hosted with
   `showModalBottomSheet(isScrollControlled: true)`, so at large accessibility text scale on a short
   phone the column exceeds the sheet's max height and `RenderFlex` overflows. Not a regression (the
   shipped `NutritionPrimerSheet` has the identical shape), and not covered by S-2714, which asserts
   only the *empty card* at 320x568. Fix: wrap the column in a `SingleChildScrollView` and add a
   small-viewport sheet case. → @developer

2. **MINOR — `docs/stats_screen.md:38`** — the sentence "It opens the [primer sheet] and never marks
   the seen flag" cites `S-2708: the "?" and the chart icon coexist` › `the chart icon stays the only
   way into Records & Trends`, but S-2708 asserts only that the two header actions coexist and that
   the chart icon navigates; it never asserts the flag is unmarked. The claim is true and tested — by
   `S-2704` (`reopening with an unseen state leaves it unseen`) and `S-2707` (`the empty-state button
   opens the sheet without marking it seen`). Fix: cite S-2704 / S-2707 for that sentence. →
   @developer

3. **MINOR — `lib/features/stats/widgets/stats_primer_sheet.dart:41`** — the class doc comment says
   the sheet renders "inside a scrollable column", but the column is not scrollable (no
   `SingleChildScrollView`). Fix: correct the comment, or make it true per finding 1. → @developer

4. **MINOR — `lib/features/home/home_screen.dart:433`** — `_openStatsScreen` has no re-entrancy
   guard, so two simultaneous taps (multi-touch) on the 'Stats' tile can both observe
   `shouldShowPrimer == true` and push two sheets. Identical to the shipped `_openNutritionScreen`
   pair, and unreachable by ordinary sequential tapping (the modal barrier absorbs the second tap),
   so this is parity, not a new defect. Fix (optional): a `_opening` bool guard. → @developer

## Verification observed

- `gateway.sh test` (full suite): `+3873 ~1: All tests passed!` — matches the plan's recorded count.
- `gateway.sh lint`: `196 issues found.` — matches the baseline, 0 errors.
- `gateway.sh test test/docs_indexing_contract_test.dart`: `+9: All tests passed!`
- The four new test files: 21 tests, all pass.

## Answers

- **(a) Double-tap / re-entrancy:** no path shows the sheet twice, marks seen without showing, or
  pushes Stats twice under ordinary interaction. The modal barrier from `showModalBottomSheet` is
  inserted synchronously and absorbs a second tap. The only double-sheet path is simultaneous
  multi-touch, which is identical to the shipped Nutrition pair (finding 4).
- **(b) Overflow:** yes — the sheet is not scrollable and can overflow at large text scale on a short
  phone (finding 1). Matches the Nutrition precedent; not a regression.
- **(c) Shared-widget impact:** `StatsPrimerSheet` is constructed only in
  `lib/features/stats/stats_screen.dart:351` and `lib/features/home/home_screen.dart:467` (plus the
  new tests). `StatsScreen` gained only an optional `bool showPrimerHelp` defaulting `false`, so the
  18 existing construction sites are unchanged.
- **(d) DI:** `lib/main.dart` is the only non-null caller. `MyApp`, `OnboardingScreen` and
  `HomeScreen` all take an optional nullable `StatsPrimerState?`. `omni_splash_screen.dart` is
  untouched (dead code, entry point disabled). No missing construction site in `lib/`.
- **(e) Docs vs code:** all cited scenario ids and test names exist and pass; the only mismatch is
  finding 2. No prohibited content was added (docs guards 9/9 green; no hex literals, no arrow-chain
  walkthroughs, no roadmap headings, no restated numerics).

## Verdict

VERDICT: APPROVE
