# 113 — One heading treatment on the Stats screen

> Status: Iteration 1 active. Owner answered 2026-11-04 (relayed by the main session): Q1-Q4 defaults, the D-18703 gap kept, and Q5 changed so Records & Trends headings are in scope (D-18710, D-18711)
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md`; `docs/design_system.md` ("Section / Card Headers", "Shared pieces and rules per job", "Label case", "How these rules are enforced"); `.github/copilot/pr-scope-budget.md`
> Track: phone only (`lib/`, `test/`, `docs/`). Calibration: STANDARD (several surfaces, a superseded guard, docs). Not TRIVIAL: the case change alone moves about ten test files.
> Base: HEAD `da2cde44` on `claude_develop`, tree clean at planning time.

## Overview

Owner complaint (three screenshots, 2026-11-04): the Stats headings are inconsistent and hard to read.
Verified against `lib/` while planning:

- **Font is already identical.** Every Stats heading is the shared `OmniCardHeader` (`lib/widgets/layout/omni_card_header.dart`: `labelSmall` 11 sp, `w600`, letter spacing 2.0, `textMuted`).
- **Position differs.** `TRAINING MIX` sits INSIDE its card (`lib/features/stats/widgets/mix_layer.dart` lines 148 and 163, first child of the `OmniSurface`, then a 16 dp `_blockGap`). `SIGNALS` (`signals_layer.dart` 76, 131), `Fuel` (`fuel_section.dart` 93) and `Weight` (`weight_trend_row.dart` 32) sit above their content. The four kind headings (`instrument_list.dart` 95) sit above bare rows. The widget's own doc says it renders ABOVE an outlined card, so Mix is the one deviation.
- **Gap differs.** The header's built-in bottom padding is 8 dp. `InstrumentList` adds `SizedBox(height: 8)` after every kind heading (16 dp), and `SignalsLockedSection` adds one after `SIGNALS` (16 dp). Mix uses 16 dp inside the card. Signals, Fuel and Weight use 8 dp.
- **Case differs.** `TRAINING MIX` and `SIGNALS` are uppercase. `Resistance` / `Cardio` / `Isometric` / `Sports` (from `ExerciseSection.label`, `lib/core/models/exercise_metric.dart` 17), `Fuel` and `Weight` are title case (`docs/design_system.md` "Label case").
- **Contrast is a hierarchy problem, not a legibility failure.** The heading colour measured against the page background, which is where a heading above a card sits, is 5.30:1 to 6.15:1 on all six themes (forgeEmber 5.30, crimsonDojo 6.15). `test/palette_legibility_contract_test.dart` Check 4 only checks it against the card surface. What makes the headings blend in is that the 11 sp muted title-case heading is smaller and dimmer than the 13 sp body text in the Mix card and the 16 sp white rows under the kind headings.

- **Records & Trends and Exercise Progress** (checked for the Q5 revision). Records & Trends' per-kind headings are the only title-case headings on either screen: `records_and_trends_screen.dart:241`, `OmniCardHeader(title: section.label)` gives `Resistance` / `Cardio` / `Isometric` / `Sports`. Its other headings are already uppercase: `ALL TIME` (166), `NUTRITION` (396) and `RECENT PRS` (`recent_pr_list.dart:35`). On Exercise Progress, `ALL TIME`, `TREND` and `RECENT SESSIONS` (`exercise_progress_screen.dart` 135, 141, 155) are all uppercase already, so it needs no code change.

Recommendation as planned: a **Stats-only** change. The owner's Q5 answer extends the case rule, and only the case rule, to Records & Trends' kind headings (D-18710). Move the Mix heading above its card, use one 8 dp gap, make every Stats heading uppercase, and leave the shared header untouched. Every other screen (Settings, Profile, Session Summary, Nutrition, Calendar day list, Exercise editor, Exercise Progress, the two primer sheets) keeps its exact look, and Records & Trends changes only the case of its four kind headings. A brighter or larger heading can only be done app-wide, because a Stats-only variant would be a second heading style. If the owner wants it, it is a separate follow-up PR (Q3).

## Goal and acceptance

What a user sees after this PR (with the defaults):

1. Every Stats block heading sits on the page background directly above its content: Mix, Signals (cards, quiet line or locked line), each kind list, Fuel and Weight. No heading sits inside a card. (S-18701, S-18702)
2. Every heading-to-content gap is the same. (S-18705)
3. Every Stats heading is uppercase: `TRAINING MIX`, `SIGNALS`, `RESISTANCE`, `CARDIO`, `ISOMETRIC`, `SPORTS`, `FUEL`, `WEIGHT`. (S-18703)
4. Headings keep one line and never overflow at 360 dp width and 2.0 text scale, on every theme. (S-18706, S-18707)
5. On Records & Trends the kind headings read `RESISTANCE`, `CARDIO`, `ISOMETRIC`, `SPORTS`, so every heading there is uppercase, with or without a search filter. Exercise Progress was already all uppercase and stays so. (S-18713, S-18714, S-18715, S-18716)
6. Nothing else changes. Only headings change: the Mix legend still reads `Resistance 40%`, exercise names, rows and chips keep their text, and every other screen's headings are unchanged. (S-18711, S-18712)

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-18701 | SUPERSEDED by D-18710 (kept for the record). Scope is the `StatsScreen` body only: `MixLayerSection` (both branches), `SignalsLayerSection`, `SignalsLockedSection`, `InstrumentList`, `FuelSection`, `WeightTrendRow`. `OmniCardHeader` is NOT edited (style, default padding, API). `ExerciseSection.label` is NOT edited. Records & Trends, Exercise Progress and `StatsPrimerSheet` are untouched (Q3, Q5 defaults) | `lib/features/stats/widgets/` |
| D-18702 | (Q1 default) A Stats heading never has an `OmniSurface` ancestor. The Mix block becomes `Column(crossAxisAlignment: stretch)[OmniCardHeader('TRAINING MIX'), OmniSurface(...)]` in BOTH the full and the empty-window branch. The card's first child is `mix_explainer` (full) or `mix_window_empty` (empty), and the `SizedBox(height: _blockGap)` that followed the header is deleted with it. Everything else inside the card keeps its order and gaps | `mix_layer.dart` |
| D-18703 | (derived, vetoable) Heading-to-content gap = the header's own default bottom padding (8 dp), with no extra spacer. Delete `children.add(const SizedBox(height: 8))` after the header in `InstrumentList.build` and `const SizedBox(height: 8)` after the header in `SignalsLockedSection.build`. Between-block gaps (24 dp in `stats_screen.dart`) and the 8 dp gap between kind lists are unchanged | `instrument_list.dart`, `signals_layer.dart` |
| D-18704 | (Q2 default) Every Stats heading is uppercase. `InstrumentList` passes `section.section.label.toUpperCase()`, computed at the call site so there is no uppercase literal and `ExerciseSection.label` keeps its title-case readers (Records & Trends headings, the Mix legend, the Mix bar semantics). `FuelSection` → `'FUEL'`, `WeightTrendRow` → `'WEIGHT'`. Semantics: the heading text is read as rendered (no added label) | `instrument_list.dart`, `fuel_section.dart`, `weight_trend_row.dart` |
| D-18705 | Supersedes D-606(a) (plan `2026-10-01-04c`) in part. On the Stats screen `STRENGTH`, `NUTRITION` and `Key('stats_legacy_sections')` are never findable. `CARDIO`, `ISOMETRIC` and `SPORTS` may each appear at most once, and only as an `OmniCardHeader` title that descends from `Key('instrument_list')`. D-606(b), the source scan of `stats_screen.dart`, is unchanged and still holds because of D-18704 | tests |
| D-18706 | (Q3 default) The heading style is unchanged app-wide, and the design_system rule "never louder than the card body" stands. New forward guard, palette Check 19: `textMuted` against `backgroundTop` and against `backgroundBottom` ≥ 4.5:1 (Check 4's threshold) on all six themes. Measured minimum today: 5.30:1 (forgeEmber, top stop) | `test/palette_legibility_contract_test.dart` |
| D-18707 | (Q4 default) The kind lists' rows stay on the page background, not in a card | `instrument_list.dart` |
| D-18708 | Keys (technical). `Key('mix_layer')` moves to the Mix block's root `Column`, as `fuel_section`, `weight_trend` and `signals_layer` already key their roots, and the card gets `Key('mix_layer_card')`. `InstrumentList`'s root `Column` gets `Key('instrument_list')` | `mix_layer.dart`, `instrument_list.dart` |
| D-18710 | Supersedes D-18701. Scope: the `StatsScreen` body (the six widgets D-18701 lists) PLUS the kind headings on `RecordsAndTrendsScreen`. Only one R&T change: `records_and_trends_screen.dart:241` passes `section.label.toUpperCase()`, the same call-site rule as D-18704. R&T placement, gaps, search, entries and the `ALL TIME` / `NUTRITION` / `RECENT PRS` headings are unchanged. Exercise Progress gets no code change (already all uppercase); S-18716 pins that. Still NOT edited: `OmniCardHeader`, `ExerciseSection.label`, `StatsPrimerSheet`. Headings only: no row text, exercise name, legend, chip, semantics label or search behaviour changes anywhere | `records_and_trends_screen.dart` + D-18701's files |
| D-18711 | Owner answers, 2026-11-04: Q1 header above its card (D-18702 binds). Q2 uppercase on every Stats heading (D-18704 binds). Q3 colour and size unchanged (D-18706 binds; a brighter or larger heading would be a separate app-wide PR). Q4 kind rows stay on the page (D-18707 binds). The D-18703 gap is not vetoed (binds). Q5 Records & Trends headings are in scope, headings only (D-18710) | — |
| D-18709 | New tests are render-only, so they run under the Mock harness only, in plain `testWidgets` with no Hive. Existing files keep their own harness loops. The theme is set with `OmniTheme.activeTheme = …` and restored in `tearDown` | tests |

## Feature Invariants

- `OmniCardHeader`'s typography is one style app-wide. No Stats call site may wrap, restyle or re-implement it (the "Section / card label" row in `docs/design_system.md`).
- Layer boundary: the touched widgets stay presentation-only (no repository, service or clock reads are added).

## Owner decisions (answered 2026-11-04; no open questions)

Q1 header above its card: yes. Q2 uppercase on every Stats heading: yes. Q3 colour and size unchanged: yes. Q4 kind rows stay on the page: yes. D-18703 gap: kept. Q5 Records & Trends headings: IN scope, headings only. All recorded as D-18711.

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `OmniCardHeader` | `grep -rn "OmniCardHeader(" lib` → 45 call sites in 18 files | none: not edited | D-18710, S-18711 (`git diff` on the file is empty) |
| `ExerciseSection.label` | `records_and_trends_screen.dart:241`, Mix legend and bar semantics (`mix_layer.dart` 321, 356, 420), `instrument_list.dart:95` | the enum is not edited; uppercase is applied at the two heading call sites only (Instruments, R&T), so the legend and semantics stay title case | D-18704, D-18710, S-18712 |
| R&T kind headings (`records_and_trends_screen.dart:241`) | `records_and_trends_screen_test.dart` 129-130 (empty state, ABSENCE: would pass vacuously), 250-251, 280-281, 293-294, 303-304 (search filter; 303-304 are absence finders), 313-314; `grep -rln RecordsAndTrendsScreen test` → also `screen_widget_test`, `stats_load_failure_test`, `stats_primer_screen_test`, `calendar_streak_screen_test`, `records_nutrition_entry_test`, `stats_instruments_horizon_screen_test`, none of which find a kind label (grep `find.text('Resistance'\|'Cardio'\|'Isometric'\|'Sports')` in them: hits only on Session Summary and the modality picker, `screen_widget_test.dart` 2686, 5531, 5567, 7920-7922) | presence finders fail; absence finders are rewritten to the uppercase text, never deleted | S-18713, S-18714; P1 item 6 |
| R&T other headings and Exercise Progress | `ALL TIME`, `NUTRITION`, `RECENT PRS` (`ui_standards_widget_test` S-2605a pins `RECENT PRS`), Exercise Progress `ALL TIME` / `TREND` / `RECENT SESSIONS` (`records_and_trends_screen_test`) | none: untouched | S-18713, S-18716 |
| `ui_standards_widget_test.dart:147` `find.text('Cardio')` | the modality picker | unaffected: different widget | — |
| Mix heading position, `Key('mix_layer')` | `grep -rn "Key('mix_layer')" test` → 40 hits (relative-order and `_textsUnder` checks in `mix_layer_screen_test`, `signals_layer_screen_test`, `instrument_list_screen_test`, `progression_rate_signal_screen_test`, `stats_*_screen_test`) | the key now spans header + card, so the order checks still hold. The `_textsUnder(mix_layer)` forbidden-copy checks gain the text `TRAINING MIX`, which contains none of `_kForbiddenCopy` | D-18708, full suite |
| Heading case, kind lists | `find.text('Resistance'\|'Cardio'\|'Isometric'\|'Sports')` on Stats: `instrument_list_screen_test.dart` 559-562, 794-797, 885-890, 1294-1324; `signals_layer_screen_test.dart:723`; `progression_rate_signal_screen_test.dart:378`; `stats_legacy_removal_test.dart` 63-66, 445-492 | presence finders fail. Absence finders (794-797) would pass VACUOUSLY: rewrite them to the uppercase text, never delete them | S-18703; P1 item 6 |
| Legacy-title guards (D-606(a)) | `stats_legacy_removal_test.dart:410` (`_kLegacyTitles` incl. CARDIO/ISOMETRIC/SPORTS, in states with work), `mix_layer_screen_test.dart:1966` (S-1614, every modality seeded), `instrument_list_screen_test.dart:893-901` (S-1015) | fail, because the new headings ARE `CARDIO`/`ISOMETRIC`/`SPORTS` | D-18705, S-18704 |
| Same guards in states with no Instruments list | `instrument_list_screen_test.dart:808-810`, `header_standardization_test.dart:2924`, `screen_widget_test.dart` ~3212, `signals_layer_screen_test.dart:62-64` (scoped to the Signals block) | still valid, so they stay unchanged | grep re-run by the reviewer |
| `Fuel` / `Weight` titles | `header_standardization_test.dart` 2945, 2982 (S-018 label set); `weight_trend_screen_test.dart:207` | update to `FUEL` / `WEIGHT` | S-18703 |
| Gaps (D-18703) | position assertions near `instrument_caption` / `signals_locked_line` (`instrument_list_screen_test` S-1011 caption, `signals_layer_screen_test` locked groups) | content moves up 8 dp, so order checks hold. Any exact-distance check found by the suite is updated to the new value and listed in the evidence | full suite |
| `test/interaction_flow_test.dart:191`, `test/screen_widget_test.dart:2686` | `find.text('Resistance'/'Cardio')` on the home tiles | unaffected: different screen | — |
| Theme legibility | `palette_legibility_contract_test.dart` Checks 1-18 | Check 19 is added, nothing is relaxed | D-18706, S-18708 |

## UI Standards Impact

Uses `OmniCardHeader` and `OmniSurface` exactly as `docs/design_system.md` "Shared pieces and rules per job" names them. It fixes the one Stats deviation from "rendered above an outlined card" (Mix). No new exception and no allowlist entry.

## Scenarios

**Fixtures** (every value listed. Days are relative to the test clock's today. Seed with the `test/helpers/repository_harness.dart` helpers; the mechanics are free):

- **F-A, every block.** Exercises: `ex-squat` "Back Squat" (load, reps); `ex-long` "Single-Arm Dumbbell Romanian Deadlift With Pause And Tempo Control" (load, reps; adversarial long name); `ex-run` "Treadmill Run" (time, distance); `ex-plank` "Plank" (hold); `ex-bjj` "BJJ" (rounds). Completed sessions, each with an effort rating of 6 and one effort: `ex-squat` daysAgo 1 (3×5 @ 100 kg); `ex-long` daysAgo 8 (3×8 @ 30 kg); `ex-run` daysAgo 15 (30 min, 5 km); `ex-plank` daysAgo 22 (3 holds × 60 s); `ex-bjj` daysAgo 2 (5 rounds × 5 min). The 1/8/15/22 spacing puts rated work in 4 distinct weeks, so the Signals gate is met. The test asserts `signalsGateMet` is true as a precondition so it cannot pass vacuously. Signals: the `StatsScreen(signals: [...])` seam with one positive stub card (id `p-1`, priority 10, as `signals_layer_screen_test.dart` builds it). Food: 1000 / 2000 / 2500 kcal and 50 / 100 / 125 g protein on daysAgo 1 / 2 / 3 (`fuel_row_screen_test.dart` S-1101's values). Weigh-ins: 80.8 kg on daysAgo 27 and 80.2 kg on daysAgo 0, with `showWeightTrend` on. Expected headings in document order: `TRAINING MIX`, `SIGNALS`, `RESISTANCE`, `CARDIO`, `ISOMETRIC`, `SPORTS` (the order `computeInstrumentSections` gives, ranked by days logged; the test reads the expected order from the service, not a literal), `FUEL`, `WEIGHT`.
- **F-B, break from training.** Two completed lifting sessions (`ex-squat`, 3×5 @ 100 kg, unrated) on daysAgo 35 and 60, no food, no weigh-ins. Screen shows the Mix empty-window card, `SignalsLockedSection` (0 rated weeks), no Instruments, no Fuel, no Weight. Expected headings: exactly `TRAINING MIX`, `SIGNALS`.
- **F-C, zero sessions.** An empty repository plus one food on daysAgo 1 (food alone must not produce headings).
- Viewports: 400×2400 (default, every block built), 360×2400 (`SupportedViewport.minWidth`), text scale 1.0 and 2.0. Themes: all six `AppTheme` values.

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-18701 | F-A, 400×2400, abyssalNeon | for every `OmniCardHeader` on the screen, `find.ancestor(of: header, matching: find.byType(OmniSurface))` finds nothing, and each header's bottom ≤ the top of its block's first content widget | the Mix header is a child of the Mix `OmniSurface` |
| S-18702 | F-B, 400×2400 | the `TRAINING MIX` header has no `OmniSurface` ancestor; `mix_window_empty` is a descendant of `mix_layer_card`; the `SIGNALS` header (locked section) has no `OmniSurface` ancestor | the empty-window branch also puts the header inside the card |
| S-18703 | F-A, 400×2400 | the `omniCardHeader_title` texts in document order equal the F-A expected list, and every one equals its own `toUpperCase()` | the kind headings, `Fuel` and `Weight` are title case |
| S-18704 | F-A, 400×2400 | `STRENGTH`, `NUTRITION` and `stats_legacy_sections` find nothing; `CARDIO`, `ISOMETRIC`, `SPORTS` each find exactly one widget, and it descends from both `Key('instrument_list')` and an `OmniCardHeader` | today the three uppercase texts are absent (red); mutant M6 (a stray `Text('CARDIO')` in `FuelSection`) also fails it |
| S-18705 | F-A and F-B, 400×2400 | for each block, `getBottomLeft(header).dy == getTopLeft(first content).dy`, where first content = `mix_layer_card`, first signal card, `instrument_caption` (first kind) or the first `instrument_row_*` (other kinds), the Fuel `OmniSurface`, the Weight `OmniSurface`, and `signals_locked_line` (F-B) | the Instruments and locked-Signals spacers add 8 dp, and Mix's header is inside its card |
| S-18706 | F-A at 360×2400, text scale 2.0, and again at 1.0 | `tester.takeException()` is null; for every header title the `RenderParagraph.didExceedMaxLines` is false (no ellipsis) at both scales (measured after the change: `TRAINING MIX` needs 288 of 320 dp at scale 2.0 in the test font); the `ex-long` row's name is one line, ellipsized | guard: passes today; mutant M8 (`'TRAINING MIX TRAINING MIX TRAINING MIX'` as the title) must flip it |
| S-18707 | F-A, 400×2400, once per `AppTheme` (six pumps) | every header title's colour == `OmniTheme.colorsForTheme(theme).textMuted`, the S-18701 placement holds, and no exception | guard against a Stats-local restyle; mutant M9 (a `DefaultTextStyle`/`Theme` override wrapping a Stats header) fails it |
| S-18708 | `OmniTheme.colorsForTheme(t)` for all six themes | palette Check 19: `contrastRatio(textMuted, backgroundTop)` ≥ 4.5 and `contrastRatio(textMuted, backgroundBottom)` ≥ 4.5 | guard (passes today, min 5.30); mutant M7 (forgeEmber `textMuted` set to `0xFF5A4A40`) fails it |
| S-18709 | RETIRED by the Q5 answer (it asserted that R&T stays title case); id never reused; replaced by S-18712..S-18714 | — | retired: no test is written for it |
| S-18710 | F-C, 400×2400 | `find.byType(OmniCardHeader)` finds nothing on Stats (the empty state only) | guard (as `header_standardization_test` S-004); mutant: Fuel shown without sessions |
| S-18711 | existing fixtures of `header_standardization_test.dart` (S-001, S-011, S-017), `ui_standards_widget_test.dart` (S-2605a, S-2605b), `records_and_trends_screen_test.dart`, `muscle_editor_screen_test.dart` (S-6) | all green, unchanged; `git diff --stat -- lib/widgets/layout/omni_card_header.dart lib/core/models/exercise_metric.dart` prints nothing | guard: proves other screens' headings are untouched (D-18710) |
| S-18712 | F-A, 400×2400 on Stats, then tap the `Records & Trends` icon | non-heading text keeps its case. Stats: `mix_legend` texts each start with a title-case kind (`Resistance `, `Cardio `, `Isometric `, `Sports `); the `mix_bar` semantics label contains `Resistance`; the `instrument_row_ex-long` name text is exactly `Single-Arm Dumbbell Romanian Deadlift With Pause And Tempo Control`. R&T: `records_entry_ex-long` contains that same exact name, and no `Text` outside an `OmniCardHeader` equals `RESISTANCE`/`CARDIO`/`ISOMETRIC`/`SPORTS` | guard for "headings only"; mutant M5 (uppercasing inside `ExerciseSection.label`) and mutant M10 (uppercasing the R&T entry text) each fail it |
| S-18713 | F-A, 400×2400, push `RecordsAndTrendsScreen` | the `omniCardHeader_title` texts in document order are `ALL TIME`, `NUTRITION`, then `RECENT PRS` only if `RecentPRList` renders (the test reads `find.byType(RecentPRList)` and branches, never assumes), then `RESISTANCE`, `CARDIO`, `ISOMETRIC`, `SPORTS` (R&T's enum declaration order). Every one equals its own `toUpperCase()`; `find.text('Resistance')` finds nothing on R&T | `section.label` renders title case |
| S-18714 | F-A on R&T, search field (`records_and_trends_search_field`) set to `romanian`, then to `zzzz`, then cleared | `romanian`: kind headings = exactly `RESISTANCE`, with one entry `records_entry_ex-long`. `zzzz`: no kind heading at all (only the non-kind headings remain). Cleared: all four kind headings return, uppercase | the filtered heading is title case; also guards that the filter still hides empty sections |
| S-18715 | F-A on R&T at 360×2400 with text scale 2.0, then at 1.0; and at 400×2400 once per `AppTheme` | no exception other than the known pre-existing `RecentPRList` row overflow at 360 dp / scale 2.0 (as built: `_isKnownPrListOverflow` tolerates only that); every header title has `didExceedMaxLines == false` at both scales; the `ex-long` entry stays within the width (no overflow); per theme every header colour == `OmniTheme.colorsForTheme(theme).textMuted` | guard; mutant M9 applied to the R&T heading fails it |
| S-18716 | F-A, R&T, tap `records_entry_ex-squat` to open Exercise Progress | headings are exactly `ALL TIME`, `TREND`, `RECENT SESSIONS` in order, each uppercase; `git diff` on `exercise_progress_screen.dart` is empty | guard: Exercise Progress was already compliant and must stay so (mutant: a title-case `'Trend'` fails it) |

## Phases

### Phase 1: Stats and Records & Trends headings, guards first (@developer)

1. [ ] Record baselines in the evidence file: the `flutter analyze` issue count (plan 112 measured 181) and the pass/fail counts of the Done Criteria suites.
2. [ ] Write `test/stats_heading_consistency_screen_test.dart` with S-18701..S-18707 and S-18710..S-18716 (fixtures F-A..F-C exactly as listed; one group per S-id; S-ids in the group names; S-18709 is retired, so no group). Run it against the UNCHANGED code and paste the red/green table per S-id into the evidence (expected red: 18701, 18702, 18703, 18704, 18705, 18713, 18714).
3. [ ] Mix: header out of the card, key move — `lib/features/stats/widgets/mix_layer.dart` · `MixLayerSection.build` (D-18702, D-18708).
4. [ ] Instruments: uppercase at the call site, drop the spacer, root key — `lib/features/stats/widgets/instrument_list.dart` · `_InstrumentListState.build` (D-18703, D-18704, D-18708).
5. [ ] `'FUEL'` in `lib/features/stats/widgets/fuel_section.dart` · `FuelSection.build`; `'WEIGHT'` in `lib/features/stats/widgets/weight_trend_row.dart` · `WeightTrendRow.build`; drop the spacer in `lib/features/stats/widgets/signals_layer.dart` · `SignalsLockedSection.build`; `section.label.toUpperCase()` in `lib/features/stats/records_and_trends_screen.dart` · the section loop at line 241 (D-18703, D-18704, D-18710).
6. [ ] Update the existing readers named in the Impact table. Every title-case finder becomes the uppercase text, absence finders included. The D-606(a) guards in `stats_legacy_removal_test.dart`, `mix_layer_screen_test.dart` (S-1614) and `instrument_list_screen_test.dart` (S-1015) are rewritten to D-18705. `header_standardization_test.dart` S-018's label set and loop become `{'TRAINING MIX', 'SIGNALS', 'FUEL'}`, and `weight_trend_screen_test.dart:207` becomes `WEIGHT`. In `records_and_trends_screen_test.dart` the kind finders at 129-130, 250-251, 280-281, 293-294, 303-304 and 313-314 become uppercase (absence finders included). Update the guard comments to cite D-18705.
7. [ ] Add palette Check 19 (S-18708) as its own `test(...)` in `test/palette_legibility_contract_test.dart`, named `Check 19: muted text clears 4.5:1 on the page background (every theme)`.
8. [ ] Run the Done Criteria, paste the counts, and run mutations M5-M10 (each must turn a named test red), recording them in the evidence. Update Progress and the Assumption Log.

**Done Criteria** (run until green; paste counts in the evidence):
- `bash .claude/scripts/macos/with-timeout.sh 900 flutter test test/stats_heading_consistency_screen_test.dart test/mix_layer_screen_test.dart test/signals_layer_screen_test.dart test/instrument_list_screen_test.dart test/fuel_row_screen_test.dart test/weight_trend_screen_test.dart test/header_standardization_test.dart test/stats_legacy_removal_test.dart test/progression_rate_signal_screen_test.dart test/stats_mix_horizon_screen_test.dart test/stats_instruments_horizon_screen_test.dart test/stats_four_week_window_screen_test.dart test/records_and_trends_screen_test.dart test/palette_legibility_contract_test.dart test/ui_standards_widget_test.dart test/muscle_editor_screen_test.dart`
- `bash .claude/scripts/macos/with-timeout.sh 300 flutter analyze` (issue count ≤ the item-1 baseline)
- `bash .claude/scripts/macos/with-timeout.sh 900 flutter test` (full suite; only the known flaky S-R3 may be red, by name)
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing
- `git diff --stat -- lib/widgets/layout/omni_card_header.dart lib/core/models/exercise_metric.dart lib/features/stats/stats_screen.dart lib/features/stats/exercise_progress_screen.dart lib/features/stats/widgets/recent_pr_list.dart` prints nothing
- `git diff -U0 -- lib/features/stats/records_and_trends_screen.dart | grep -c '^[-+] '` prints 2 (one line out, one line in: headings only)
- `grep -n "OmniCardHeader" lib/features/stats/widgets/mix_layer.dart` shows exactly one call. `grep -n "title: 'Fuel'\|title: 'Weight'" lib/features/stats/widgets` prints nothing

**Predicted Files**: `lib/features/stats/widgets/mix_layer.dart`, `lib/features/stats/widgets/instrument_list.dart`, `lib/features/stats/widgets/fuel_section.dart`, `lib/features/stats/widgets/weight_trend_row.dart`, `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/records_and_trends_screen.dart`, `test/stats_heading_consistency_screen_test.dart` (new), `test/palette_legibility_contract_test.dart`, `test/instrument_list_screen_test.dart`, `test/signals_layer_screen_test.dart`, `test/progression_rate_signal_screen_test.dart`, `test/stats_legacy_removal_test.dart`, `test/mix_layer_screen_test.dart`, `test/header_standardization_test.dart`, `test/weight_trend_screen_test.dart`, `test/records_and_trends_screen_test.dart`, plus the evidence file (6 lib + 10 test files). The full suite may name another reader with an exact-distance check (D-18703). If so, fix it in place and list it in the evidence as an unpredicted file with its reason.

### Phase 2: Docs and residue sweep (@developer)

1. [ ] Apply every row of the Docs delta table. Sizes now: `docs/design_system.md` 47.3 KB, `docs/stats_screen.md` 40.9 KB, `docs/widget_catalog.md` 19.8 KB, `docs/records_and_trends.md` 8.5 KB. Every edit is net under +1 KB, so all stay below the 52 KB band. Write no contrast ratio or other measurement into `design_system.md` (the docs check forbids it); refer to "palette Check 19".
2. [ ] Residue sweep. Each of these must print nothing:
   - `grep -rn "title-case\|title case" docs/design_system.md docs/stats_screen.md docs/widget_catalog.md docs/records_and_trends.md`
   - `grep -rn "find.text('Resistance')\|find.text('Cardio')\|find.text('Isometric')\|find.text('Sports')" test/instrument_list_screen_test.dart test/signals_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/stats_legacy_removal_test.dart test/records_and_trends_screen_test.dart`
   - `grep -rn "D-606(a)" test` (only lines that also cite D-18705 are allowed)
3. [ ] Run `python3 -I .claude/scripts/macos/plan-lint.py after docs/plans/2026-11-04-113-stats-heading-consistency-plan/2026-11-04-113-stats-heading-consistency-plan.md` and `flutter test test/docs_indexing_contract_test.dart`, then paste the output.

**Done Criteria**: plan-lint `after` clean; `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` green; the three sweep greps empty.
**Predicted Files**: `docs/design_system.md`, `docs/stats_screen.md`, `docs/widget_catalog.md`, `docs/records_and_trends.md`, the evidence file (4 docs).

### Phase 3: Review (@code-reviewer)

Diff against the Predicted Files. Re-run every Impact-table grep. Check per-S-id fixture conformance (F-A's values, the gate precondition, the non-vacuous absence finders). Re-run mutations M5-M10, and confirm the R&T diff is the one heading line (D-18710, headings only). Adjudicate the Assumption Log. Findings go to `2026-11-04-113-stats-heading-consistency-plan.review.md`.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/design_system.md | MODIFIED | lists on Stats and the Fuel row are title case. | Every Stats and Records & Trends heading is uppercase | D-18710 |
| docs/design_system.md | MODIFIED | the per-section list labels (`section.label`) | `NUTRITION`; the per-kind list labels in uppercase (`RESISTANCE`, `CARDIO`, `ISOMETRIC`, `SPORTS`) | S-18713 |
| docs/records_and_trends.md | MODIFIED | header per `ExerciseSection`, in the enum's declaration order (Resistance → | header per `ExerciseSection`, uppercase, in the enum's declaration order (`RESISTANCE` → | S-18713 |
| docs/design_system.md | MODIFIED | which pins the four title-case labels. | `test/stats_heading_consistency_screen_test.dart` (group `S-18703` | S-18703 |
| docs/design_system.md | MODIFIED | the Instruments list's four title-case headers | the Instruments list's four uppercase headers | S-18703 |
| docs/design_system.md | MODIFIED | `Today` (with | `TODAY` (with | S-18711 |
| docs/design_system.md | ADDED | - | a Stats heading never sits inside its card | S-18701 |
| docs/stats_screen.md | MODIFIED | The section headers are `Resistance`, `Cardio`, `Isometric` and `Sports`, and | The section headers are `RESISTANCE`, `CARDIO`, `ISOMETRIC` and `SPORTS` | S-18703 |
| docs/stats_screen.md | MODIFIED | One sentence under the card's title names the window, then says what the bars are: | One sentence at the top of the card, under the `TRAINING MIX` header above it, names the window | S-18702 |
| docs/stats_screen.md | ADDED | - | Every block's heading sits above its content | S-18701 |
| docs/widget_catalog.md | MODIFIED | an `OmniCardHeader` titled `Weight` over one | an `OmniCardHeader` titled `WEIGHT` over one | S-18703 |
| docs/widget_catalog.md | MODIFIED | is the Mix layer's body: the explainer sentence | is the Mix layer's body: the `TRAINING MIX` header above one card holding the explainer sentence | S-18702 |

(The `Today` row fixes existing drift: `nutrition_screen.dart:203` renders `TODAY`. The doc edit is cheap, and S-18711 keeps that screen unchanged.)

## Notes

- Dependency graph: P1 → P2 → P3. P1 items 3-5 are independent of each other. Item 2 must run before 3-5, because the red evidence needs the unchanged code.
- Intermediate state: after item 2 the new file is red (5 S-ids) and the rest of the suite is green. After items 3-5 the new file is green and the readers in item 6 are red. After item 6 everything is green. Never hand off between items 2 and 6.
- Owner answers are in (D-18711). A brighter or larger heading (Q3 b) stays out of this PR; if the owner asks for it after seeing this on the phone, it is a separate app-wide PR plan.
- Mutation M10 (for S-18712): uppercase the R&T entry's exercise name in `_buildEntry`.
- No persisted data, model, repository or watch surface is touched.

## Progress

- [x] P1 Stats and Records & Trends headings, guards first: red on old code (+3 -6), green after; full suite +6394 ~2, 0 failed; analyze 181 = baseline; M5-M17 all killed (evidence file)
- [x] P2 docs and residue sweep: plan-lint after clean, docs/ui contract tests +54, three sweeps empty (lead fixed 3 line-wrapped markers the keeper claimed were verified)
- [x] P3 review: APPROVE, 0 blocker / 0 major / 0 minor / 2 nits (both fixed); findings in the .review.md
- [ ] (owner) look at Stats and Records & Trends on the phone; decide whether the headings are loud enough (Q3 follow-up) and whether to fix the pre-existing Recent PRs overflow at large text

## Assumption Log

- 2026-11-04 planner: the contrast figures (5.30-6.15:1 against `backgroundTop`) were computed from the `omni_theme.dart` hex values with the WCAG formula. Check 19 re-proves them in CI.
- 2026-11-04 planner: D-18703 (one 8 dp gap) was derived; owner kept it (not vetoed), so it binds (D-18711).
- 2026-11-04 planner: owner answers relayed by the main session: Q1-Q4 defaults, Q5 changed so R&T headings are in scope. D-18701 is superseded by D-18710, and S-18709 is retired for S-18712..S-18716.
- 2026-11-04 planner: R&T scope checked in lib/. The only title-case heading on R&T or Exercise Progress is `records_and_trends_screen.dart:241`, so Exercise Progress gets no code change.

## Feedback

[empty]
