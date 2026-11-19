# Review: 2026-11-04-113-stats-heading-consistency · P1+P2 · da2cde44..working tree

Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · nit 2 · tests: 6394 passed / 2 skipped / 0 failed (lead's full-suite run, pasted in the brief; not re-run per brief)
Diff vs Predicted Files: conforms — the 20 diff files are exactly the plan's 6 lib + 10 test + 4 docs; the evidence file is new/untracked so it does not appear in `git-diff` (allowed, predicted).

## Findings

1. [Nit] test/stats_heading_consistency_screen_test.dart:1-7 — the header comment says the guards are "red now" against the "UNCHANGED screen" and that "the production change lands in a later run"; the change has landed in this same tree, so the comment describes a state that no longer exists. Fix: reword to past tense ("written guards-first against the unchanged screen; the production change landed in the same PR").
2. [Nit] plan Scenarios S-18706 and S-18715 — the rows still promise `didExceedMaxLines == false` at text scale 2.0 (S-18706) and "no exception" (S-18715), but the tests assert the 1.0 scale only and tolerate the one known `RecentPRList` overflow (`_isKnownPrListOverflow`, test/stats_heading_consistency_screen_test.dart:337, 1088). Both deviations are recorded in the evidence file's "Deviations from the plan text", so this is a plan-text staleness only. Fix: annotate the two rows in the plan with the implemented assertion.

## The five questions

**1. Headings only (D-18710) — yes.**
- `mix_layer.dart`: `git-diff -w` is refused by the gateway ("git-diff option not allowed: -w"); compared the full diff manually instead. Every moved line is text-identical apart from indentation. The real change is exactly: header out of the card, the `SizedBox(height: _blockGap)` after it deleted, root `Column` (stretch) with `Key('mix_layer')`, card gets `Key('mix_layer_card')`, in BOTH branches (D-18702, D-18708). Legend texts, `mix_usual_label`, `mix_baseline_note`, `mix_strip_title`, bar and semantics untouched; no child inside the card changed order.
- `instrument_list.dart`: header line uppercased at the call site, the 8 dp spacer after it deleted, `Key('instrument_list')` added to the root Column (D-18703/04/08). Nothing else.
- `fuel_section.dart` / `weight_trend_row.dart`: one title literal each (`'FUEL'`, `'WEIGHT'`). `signals_layer.dart`: one spacer deleted. `records_and_trends_screen.dart`: exactly one line out, one in (`section.label` → `section.label.toUpperCase()`).
- No row text, legend, semantics label or key that other lib code reads changed: grep of `lib` shows no reader of `Key('mix_layer')`, `Key('instrument_list')` or `Key('mix_layer_card')` outside the touched widgets.

**2. Non-vacuous guards — yes; two skips, named.**
- `stats_legacy_removal_test.dart:414-441` (S-1208/D-18705) and `mix_layer_screen_test.dart:1971-2005` (S-1614): STRENGTH/NUTRITION stay unconditional `findsNothing`; CARDIO/ISOMETRIC/SPORTS check ≤1 match, then OmniCardHeader-title + `instrument_list`-descendant ancestors. Both contain `if (matches.evaluate().isEmpty) continue;` — named here. The skip only fires in the compliant (absent) state; if the text appeared anywhere unexpected, the at-most-once and ancestor asserts run and fail, so the guard is not vacuous. In the states with work (S-1614 seeds every modality; stats_legacy_removal's state at :479 has `mix_layer` + 2 rows + `RESISTANCE`) the full structural check executes.
- `instrument_list_screen_test.dart:794-797`: absence finders rewritten to the uppercase text in the nothing-logged state — meaningful as "no kind heading may appear when the list is empty" (a regression that rendered one would fail). Same shape as the pre-change guard, per the plan's prescription.
- `records_and_trends_screen_test.dart:129-130`: absence finders in the empty state rewritten to uppercase. With respect to the case change specifically this state cannot distinguish (no kind heading renders at all), which the plan itself flagged ("would pass vacuously") and prescribed rewrite-not-delete; the case guard lives in the presence finders at 250-251/280-281/293-294/303-304/313-314 (all rewritten, verified) and in S-18713/S-18714.
- `instrument_list_screen_test.dart:885-901` (S-1015): rewritten to unconditional `findsOneWidget` + both ancestor checks in a state where the list renders — non-vacuous.

**3. Fixture conformance — yes.**
- F-A: ex-squat "Back Squat" (load, reps) daysAgo 1, 3×5 @ 100 kg; ex-long with the adversarial name (load, reps) daysAgo 8, 3×8 @ 30 kg; ex-run "Treadmill Run" daysAgo 15, 30 min / 5 km via `seedTimedEntries`; ex-plank "Plank" (hold) daysAgo 22, 3×60 s; ex-bjj "BJJ" (rounds) daysAgo 2, 5×5 min; every session rated 6 with one effort. Food 1000/2000/2500 kcal with 50/100/125 g protein on daysAgo 1/2/3. Weigh-ins 80.8 kg @27 and 80.2 kg @0. All as the plan lists.
- Signals gate asserted as a precondition: `seedEveryBlock` expects `signalsGateMet(mix)` isTrue with a reason string, and that `sections` containsAll `ExerciseSection.values` (test/stats_heading_consistency_screen_test.dart:432-449). The stub card (id `p-1`, positive, priority 10) goes through the `StatsScreen(signals:)` seam.
- F-B: two unrated sessions daysAgo 35/60, foods and weigh-ins cleared; S-18702 asserts the titles are exactly `['TRAINING MIX', 'SIGNALS']`. F-C: cleared foods/weigh-ins plus one food on daysAgo 1; S-18710 asserts no `OmniCardHeader`.
- `showWeightTrend` is not set explicitly; the test relies on the default, which is on (`lib/state/settings/settings_state.dart:86`, and :364 only honours a saved `'false'`). If the default ever flipped, `faBlocks()` fails loudly (header-count mismatch), so the reliance is safe.
- Expected heading order is read from `computeInstrumentSections`, not a literal (S-18703, S-18713, S-18714, S-18715 all do).

**4. Scope — conforms.** `git-diff --stat` lists exactly: the 6 production files, the new `test/stats_heading_consistency_screen_test.dart`, the 9 edited test files (`header_standardization`, `instrument_list_screen`, `mix_layer_screen`, `palette_legibility_contract`, `progression_rate_signal_screen`, `records_and_trends_screen`, `signals_layer_screen`, `stats_legacy_removal`, `weight_trend_screen`) and the 4 docs. No unpredicted file. No full-suite-named extra reader appeared.

**5. Docs vs code — the sentences match the code.**
- "Every Stats and Records & Trends heading is uppercase" (design_system.md Label case): true — `instrument_list.dart:95` (call-site `toUpperCase()`), `fuel_section.dart:93` `'FUEL'`, `weight_trend_row.dart:32` `'WEIGHT'`, `records_and_trends_screen.dart:241` `toUpperCase()`; `ALL TIME`/`NUTRITION`/`RECENT PRS` were already uppercase.
- "a Stats heading never sits inside its card" (design_system.md + stats_screen.md + widget_catalog.md): true — both `mix_layer.dart` branches put the header above `OmniSurface(Key('mix_layer_card'))`.
- "The section headers are `RESISTANCE`, `CARDIO`, `ISOMETRIC` and `SPORTS`" and "the caption under the first one names the window" (stats_screen.md): true — `instrument_list.dart:95-98`.
- "One sentence at the top of the card, under the `TRAINING MIX` header above it" (stats_screen.md): true — the card's first child is `_buildExplainer` (`mix_explainer`, mix_layer.dart:234).
- widget_catalog.md `WEIGHT` over one `OmniSurface`: true. records_and_trends.md "header per `ExerciseSection`, uppercase, in the enum's declaration order": true.
- `TODAY` (design_system.md Daily Nutrition row): verified — `lib/features/nutrition/nutrition_screen.dart:203` renders `title: 'TODAY'`.
- Every cited group/test name exists: `S-18701 no Stats heading sits inside a card` (with the named test), `S-18703 every Stats heading is uppercase`, `S-18712 non-heading text keeps its case`, `S-18713 R&T headings are uppercase in the enum order` — all in the new test file; the `weight_trend_screen_test.dart` S-17705 citation now matches its `WEIGHT` assertion.
- No stale sentence seen outside the four docs.

## Docs delta

| Row | Status |
|---|---|
| design_system.md · title-case rule → "Every Stats and Records & Trends heading is uppercase" | applied |
| design_system.md · R&T row → `NUTRITION` + uppercase kind labels | applied |
| records_and_trends.md · header per ExerciseSection, uppercase, enum order | applied |
| design_system.md · pinning citation → stats_heading_consistency S-18703 | applied |
| design_system.md · Instruments four uppercase headers | applied |
| design_system.md · `Today` → `TODAY` | applied |
| design_system.md · ADDED "a Stats heading never sits inside its card" | applied |
| stats_screen.md · section headers uppercase | applied |
| stats_screen.md · explainer sentence under the `TRAINING MIX` header | applied |
| stats_screen.md · ADDED "Every block's heading sits above its content" | applied |
| widget_catalog.md · `Weight` → `WEIGHT` | applied |
| widget_catalog.md · Mix layer body: `TRAINING MIX` header above one card | applied |

Doc edits the table does not name (all benign additive verification sentences): records_and_trends.md adds the S-18713 case-pin sentence; stats_screen.md appends the S-18703 citation to the section-headers paragraph; widget_catalog.md appends the S-18703 citation to the Weight block note and the S-18701 citation to the Mix layer note.

Residue sweeps re-run by this review: `title-case|title case` in the four docs — no matches; `D-606(a)` in test — no matches; `find.text('Resistance'|'Cardio'|'Isometric'|'Sports')` in the five named test files — no matches.

## Assumption Log rulings

- Contrast figures (5.30-6.15:1) computed by the planner — **ratify**: palette Check 19 re-proves ≥ 4.5:1 in CI and is green.
- D-18703 derived, owner kept it — **ratify**: recorded in D-18711; the spacers are deleted in the diff.
- Owner answers relayed by the main session — **ratify**: D-18711 records all five; no open questions in the plan.
- R&T scope checked in lib/, Exercise Progress needs no change — **ratify**: S-18716 pins it and `exercise_progress_screen.dart` has no diff.

## Scenario coverage

S-18701 → stats_heading_consistency_screen_test · group `S-18701` · F-A placement+ancestry
S-18702 → same file · group `S-18702` · F-B empty-window branch
S-18703 → same file · group `S-18703` · document order + self-uppercase
S-18704 → same file · group `S-18704` · legacy absence + kind uniqueness/ancestry
S-18705 → same file · group `S-18705` · F-A and F-B gap == header bottom (closeTo 0.5)
S-18706 → same file · group `S-18706` · deviation: `didExceedMaxLines` asserted at scale 1.0 only (evidence-recorded)
S-18707 → same file · group `S-18707` · per-theme textMuted + placement
S-18708 → palette_legibility_contract_test · `Check 19: muted text clears 4.5:1 on the page background (every theme)`
S-18709 → retired; no group in the file (verified)
S-18710 → same file · group `S-18710` · F-C no header
S-18711 → existing suites unchanged (diff touches none of their fixtures) + empty diffs on `omni_card_header.dart`/`exercise_metric.dart`/`stats_screen.dart`/`exercise_progress_screen.dart`/`recent_pr_list.dart` (evidence invariants; confirmed absent from the diff stat)
S-18712 → same file · group `S-18712` · legend/semantics/row case on both screens + no bare uppercase kind
S-18713 → same file · group `S-18713` · R&T order + uppercase + no title-case kind
S-18714 → same file · group `S-18714` · romanian / zzzz / cleared
S-18715 → same file · group `S-18715` · deviation: tolerates exactly the known `RecentPRList` overflow (evidence-recorded)
S-18716 → same file · group `S-18716` · Exercise Progress headings

## Final counts and verdict

Blocker 0 · Major 0 · Minor 0 · Nit 2 — **APPROVE**.
