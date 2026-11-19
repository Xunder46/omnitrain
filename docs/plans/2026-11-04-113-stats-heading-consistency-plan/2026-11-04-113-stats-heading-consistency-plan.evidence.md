# Evidence — plan 113, Stats heading consistency

Written by the lead (governor) from output the lead observed. Base commit `da2cde44` on `claude_develop`.

## Baselines (before any change)

- `flutter analyze`: 181 issues found (all pre-existing info/warning notices).

## Phase 1 — red on the unchanged code (guards written first)

`flutter test test/stats_heading_consistency_screen_test.dart` against the unchanged `lib/`: `00:01 +3 -6: Some tests failed.`

| S-id | Result on unchanged code | Reason |
|---|---|---|
| S-18701 | red | Mix header is a child of `OmniSurface-[<'mix_layer'>]` |
| S-18702 | red | same, empty-window branch (F-B) |
| S-18703 | red | titles are title case (`Resistance`, `Fuel`, `Weight`) |
| S-18704 | red | `Found 0 widgets with text "CARDIO"` |
| S-18705 (F-A, F-B) | red | gap differs by 16.0 dp |
| S-18706, S-18707, S-18710 | green | guards that must also pass today |

(S-18712..S-18716 were written after the production change, so they have no red-on-old-code run; their proof is the mutation table below.)

## Phase 1 — green after the change

- `flutter test test/stats_heading_consistency_screen_test.dart`: `00:01 +15: All tests passed!` (builder-reported; the same 15 tests ran inside the lead's full-suite and mutation runs, which showed `+14 -1` with one mutant active, i.e. 15 tests).
- Full suite (lead, `with-timeout.sh 900 flutter test`): `04:30 +6394 ~2: All tests passed!` — 0 failures, 2 skipped.
- `flutter analyze`: 181 issues, equal to the baseline.
- Invariants: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing; `git diff --stat` on `omni_card_header.dart`, `exercise_metric.dart`, `stats_screen.dart`, `exercise_progress_screen.dart`, `recent_pr_list.dart` prints nothing; the Records & Trends diff is exactly 2 lines (one out, one in); `mix_layer.dart` has two `OmniCardHeader` calls (one per branch, both `TRAINING MIX`); no `title: 'Fuel'` / `title: 'Weight'` left.
- Production diff: 6 files, 81 insertions, 77 deletions (the Mix block re-indent accounts for 147 of the changed lines with whitespace; `git diff -w` shows the real change).

## Mutations (lead, applied by script, each restored and `cmp`-identical)

| Id | Mutant | Guard that went red |
|---|---|---|
| M5 | `ExerciseSection.label` resistance returns `RESISTANCE` | S-18712 |
| M6 | stray `Text('CARDIO')` in `FuelSection` | S-18704 (and S-18705, S-18712) |
| M7 | forgeEmber `textMuted` set to `0xFF5A4A40` | palette Check 19 (and Checks 1-17 group) |
| M8 | Mix title `TRAINING MIX TRAINING MIX TRAINING MIX` | S-18706 (and S-18701, 18703, 18705, 18707) |
| M9 | Fuel heading replaced by a red `Text` with the title key | S-18707 (and S-18701, 18705, 18706). A `DefaultTextStyle`/`Theme` wrapper cannot change the colour because `OmniCardHeader` sets it explicitly, so the restyle mutant replaces the widget instead |
| M10 | R&T entry name uppercased | S-18712 |
| M11 | R&T heading `.toUpperCase()` removed | S-18713, S-18714, S-18715 and two `records_and_trends_screen_test` S-912 cases |
| M12 | Exercise Progress `'TREND'` → `'Trend'` | S-18716 |
| M13 | 8 dp spacer back under the Instruments heading | S-18705 (F-A) |
| M14 | 8 dp spacer back under the locked SIGNALS heading | S-18705 (F-B) |
| M15 | Instruments `.toUpperCase()` removed | S-18703, S-18704, instrument_list S-1001, S-1015, S-4018 |
| M16 | `'WEIGHT'` → `'Weight'` | S-18703, weight_trend S-17705 |
| M17 | empty-window Mix heading back inside the card | S-18702 |

## Deviations from the plan text (found while building)

- S-18706 (CORRECTED after the owner's question): the builder first reported that `TRAINING MIX` ellipsizes at 360 dp / text scale 2.0 and the test asserted "no ellipsis" at scale 1.0 only. That was true only while the heading sat INSIDE the card (32 dp narrower). The lead measured the final layout with a throwaway probe: at scale 2.0 `TRAINING MIX` needs 288 of 320 dp available and `didExceedMaxLines` is false for every Stats heading (test font Roboto/Ahem-width glyphs, wider than the phone's real font). The tests (S-18706 and S-18715) now assert "no ellipsis" at both scales, as the plan first said.
- S-18715: `RecentPRList` (`lib/features/stats/widgets/recent_pr_list.dart:63`, not touched by this plan) overflows its row by 197/219 px at 360 dp with text scale 2.0, which already happened before this change. The test tolerates exactly that one exception and fails on any other. Follow-up: fix the overflow, then remove `_isKnownPrListOverflow`.
- S-18707: each theme is mounted with a keyed `MaterialApp`, because `const OmniCardHeader` instances in a retained tree are not rebuilt between pumps.
