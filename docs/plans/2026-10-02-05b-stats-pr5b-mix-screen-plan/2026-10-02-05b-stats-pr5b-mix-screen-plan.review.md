# Review — Stats PR 5b (Mix layer on the Stats screen, incl. the shared `OmniCardHeader` change)

Reviewed against `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/2026-10-02-05b-stats-pr5b-mix-screen-plan.md`
(revised: D-936 stacked strip, D-937 usual bar), its `.evidence.md`, `docs/global_conventions.md`,
and the brief `.work/stats-pr5/brief-review-5b.md`. Base commit `8be0918`, uncommitted on `develop`.
5a's `MixLayerData` contract (`lib/core/models/training_load.dart`) treated as given.

**Layers in scope:** `lib/features/stats/` (new widget + screen wiring), `lib/widgets/layout/` (shared header),
`test/` (new + re-stabilised), `docs/`.
**Layers skipped:** `lib/data/models/`, `lib/data/repositories/`, `lib/state/`, `lib/core/` — 5b touches none of them
(the Mix data layer and service are 5a's, already reviewed).

## Findings — the fix set

1. **major** — `lib/widgets/layout/omni_card_header.dart:70-86` — the actions cluster became a *flex sibling* of
   the title: the title is `Expanded` (flex 1, tight) and the cluster is now `Flexible` (flex 1, loose), so
   `RenderFlex` splits the header's free space **50/50 whenever actions exist**, and the title's budget drops from
   `width − actions` to `width / 2`. On 320–390 dp headers whose titles approach that half this truncates text that
   previously fit — Session Summary's date-time title (`session_summary_screen.dart:763`) and the month-label /
   `Open Calendar` pair (`:888`) are the closest cases, and the `Open Calendar` button itself is now capped at half
   the header (at 1.3× it exceeds that cap and its label wraps). The new test covers only a raw `Text` action, so
   nothing asserts the title side or any real action widget. Fix: bound the cluster without making it a flex sibling
   — e.g. `LayoutBuilder` + `ConstrainedBox(maxWidth: constraints.maxWidth * 0.5)` around the actions `Row`, leaving
   the title `Expanded` (it then keeps `width − actions`, which is ≥ half) — or, if the 50 % cap is intended, add a
   title-side assertion to `test/header_standardization_test.dart` `S-001c` and state the cap in
   `docs/design_system.md`. Side note: the widget also now asserts if ever used under a horizontally unbounded
   parent (all six current hosts are bounded). → @developer

2. **minor** — `docs/stats_screen.md:33-35` — "Otherwise it is four blocks in a fixed order: the Mix layer, the
   ALL TIME card, …" gives the Mix layer no condition while the other three carry one ("when the window holds work",
   "when recent food exists"), yet `S-1610-B` renders ALL TIME with no Mix layer. Fix: qualify it (the Mix layer when
   the window holds measurable time), or point the sentence at `S-1610` for the hidden state. → @developer

3. **minor** — `docs/stats_screen.md:80-83` — the note/unrated bullet cites `S-1610`, which asserts the *layer's
   absence* (no `mix_layer` key), not the note or the unrated line. Fix: drop `S-1610` from that bullet and cite it
   against the layer's hidden state instead. → @developer

4. **nit** — `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/2026-10-02-05b-stats-pr5b-mix-screen-plan.md:241`
   — Phase 2's Predicted Files line omits `test/header_standardization_test.dart`, which Phase 2 changed (+65 lines;
   the file is named in that phase's Done Criteria at `:226` and its step 5 at `:286`, and the evidence §11.6/§12
   says it was added to Predicted Files). Fix: add it to the line. → @developer

5. **nit** — `docs/design_system.md:170-173` — the new `actions`-cluster sentence is true but silent on the title cap
   the same change introduces, so a reader cannot tell that a header with actions gives its title half the width.
   If the implementation stays, say so here. → @developer

6. **nit** — `test/mix_layer_screen_test.dart` `S-1615` — it asserts *horizontal* overflow at 375×667/1.3×, the
   exact case `test/screen_overflow_contract_test.dart:36-44` declares fictional under the test font and
   deliberately refuses to assert on ("adding horizontal assertions would make this suite cry wolf"). The
   sub-widget-width assertions carry the real signal; consider dropping the horizontal `overflowed` check. Also
   `S-1616` seeds inside `tester.runAsync` after a pump rather than in `setUp` — documented, and I judge it safe,
   but it is the one place the file's seeding rule bends. → @developer

## Carried (read, not in the fix set)

- `docs/stats_screen.md:120` — an unrelated blank line was deleted, merging two paragraphs; looks accidental.
- `docs/design_system.md:186` — the Profile row still claims "label + `+` add button in actions"; the header is
  title-only per A16 and the add button lives in the card body. Pre-existing drift, adjacent to this diff.
- `docs/stats_screen.md:45-47` — "it computes nothing itself" is loose: the widget computes the segment flex and the
  strip's max week locally from the data's measures (D-924/D-936 require it). Intent is clear.
- `lib/features/stats/widgets/mix_layer.dart:73` — `'min'` is now a third literal for the same unit
  (`native_value_format.dart:39`, `:138`); no shared duration-unit owner exists, so this is acceptable.
- D-933 says long strings ellipsize rather than wrap; the measure label, the baseline note and the unrated line have
  no `maxLines`/`ellipsis` and wrap at large text scale. No overflow observed; judged fine for short sentences.

## Verified — the brief's nine items

1. **Owner decisions — PASS.** Mix is the first body block above ALL TIME (`stats_screen.dart`, guarded by
   `if (_mixLayer != null && window != null)`); one measure label rendered above both the bar and the strip from
   `MixMeasure` (D-923, `findsNWidgets(2)` asserted); the strip stacks each week by modality with the current column
   marked by a `textMuted` border plus `' (in progress)'` in semantics (D-936/D-930); the baseline is a thin `usual`
   bar under the main bar in the load measure only (D-937); the chip is the same `StatsWindowChip`, so the screen
   carries exactly two (D-922).
2. **Pack acceptance — PASS.** Lifting-only → one full-width Resistance segment (`S-1611`); no ratings → `by time`,
   the `Load baseline: n of 4 weeks rated` note, no usual bar; 4+ rated weeks and ≤25 % unrated → `by load`, usual
   bar, no note and no `by time` (both asserted as `findsNWidgets(2)`/`findsNothing` pairs); unrated count in words;
   8 columns with the in-progress one marked; layer hidden on a fresh profile and on a set-only rolling window with
   the empty state / ALL TIME unchanged (`S-1610-A/B`); percentages are the data's rounded ones and widths are the
   exact proportions (`_flex`, never `percent`).
3. **Purity, wiring, colours, guards — PASS.** `MixLayerSection` reads only `MixLayerData` + `window` + `themeColors`:
   no repository/service/`Future`/`setState`, no `fl_chart`/`ScrollableTrendChart`/`CustomPaint`. The screen computes
   it once inside the existing `_loadData()` on the same `service` and the same `progressData.window`, passing
   `now` and `settingsState.startOfWeek`. Colours are `ModalityColors`/`themeColors` only — no hex, no new token.
   No bare modality name is rendered (`'<label> <pct>%'`), and `test/stats_legacy_removal_test.dart` is untouched and
   still meaningful (`find.text('Resistance') findsOneWidget` plus the source-fragment guard on `stats_screen.dart`).
4. **Layout and accessibility — PASS.** `S-1615` (375×667@1.3, 440×956@1.0) is green and asserts every sub-widget is
   no wider than the card; the semantics labels exist for the bar, the usual bar and every column, match the legend's
   rounded percentages, and the legend is `ExcludeSemantics`-wrapped so nothing is read twice;
   `test/palette_legibility_contract_test.dart` is green on every theme.
5. **Shared header — see finding 1.** Answers to the brief's sub-questions: tap targets are unchanged (an `IconButton`
   keeps its 48 dp intrinsic under a loose `Flexible`, and every current cluster holds one action, so each gets half a
   header ≥ 160 dp at the narrowest real width); right-edge alignment is unchanged; a `Flexible` wrapping an
   intrinsic-width button is safe *because* the outer `Row` is bounded in all six hosts. The new behaviour **is**
   covered by a genuine red/green test: `S-001c` fails against the old header, and the pre-existing
   `fuel_row_screen_test.dart` narrow/large-text tests (`S-1259`–`S-1261`) were red before the fix
   (`overflowed by 27 pixels on the right` at 320×568, `210` at 390×844@2.0) and are green after. The gap is the
   title side and real (non-`Text`) actions. The brief's list of affected screens is partly stale: Profile's header is
   title-only and the Calendar screen has no `OmniCardHeader`, so the live hosts are Nutrition ×2, Session Summary ×2,
   the Instruments list and the Mix layer.
6. **Re-stabilised tests — PASS.** The four edited files changed heights (400×900/400×1200 → 400×1600), one locator
   (`find.byType(OmniSurface).first` → `find.byKey(const Key('all_time_card'))`, the same card), and chip counts
   (`findsOneWidget` → `findsNWidgets(2)` plus the ancestor-header title set `{'TRAINING MIX', 'Resistance'}`).
   No assertion was weakened or removed; the fuel-row-has-no-chip assertion is kept and the chip test is strengthened
   (both chips must read `'· Block A'`). For the governor's name-level diff: that fuel-row test was **renamed**, not
   deleted — its contract is intact.
7. **Layer tests — PASS.** `S-1601`–`S-1616` are present on both harnesses with Hive seeded in `setUp`; the assertions
   are plain and rule-shaped; the four Phase-2 structural guards are present (one section→colour mapping, no bare
   modality name, no chart primitive or new colour, strip stacks by modality). The two reported mutations are real —
   M1 (Mix block moved below ALL TIME) reddens `S-1601` on both harnesses, and M2′ (swapping the `_sectionColors`
   bindings in `mix_layer.dart`) reddens 12 tests. M2 as literally written (swapping the `ModalityColors` initialisers)
   is neutral because widget and guard read the same constants; the evidence reports that honestly rather than
   claiming a red it did not get. See nit 6 for `S-1615`/`S-1616`.
8. **Docs — findings 2, 3, 5 plus the carried items.** `widget_catalog.md`'s new note bullet matches its neighbours'
   shape and names the right file and test; `navigation_and_screens.md`'s `StatsScreen` row now leads with the Mix
   layer and stays true of the code; the `stats_screen.md` additions are otherwise accurate (window table, chips
   section, constants table, file table, version bump). A search of `docs/` (outside `plans/`, `history/`,
   `releases/`) found nothing else still describing the Stats body as ALL TIME / Instruments / Fuel only, or counting
   one chip; the "three blocks" at `docs/widget_catalog/nutrition_widgets.md:28` is about nutrition, not Stats.
9. **Scope — PASS.** `git-status` lists exactly the brief's files; the extras (`omni_card_header.dart`,
   `records_and_trends_screen_test.dart`, `header_standardization_test.dart`, `design_system.md`,
   `navigation_and_screens.md`) are recorded in the evidence (§11.2, §11.3, §11.6) and in the plan's Phase 1
   Predicted Files (`:227`) — except `header_standardization_test.dart`, which is finding 4. No scratch, probe or
   debug files; no `print`; no unrelated reformatting beyond the carried blank line.

## Global conventions

`PASS (7 rules):` units + canonical storage (the layer renders no converted value and `'min'` appears in semantics
only, per D-932; no preference-backed unit is involved), theme tokens only (colours from `ModalityColors` /
`themeColors`, palette contract green), card chrome via `OmniSurface` + `OmniCardHeader` (the layer is one
`OmniSurface` opening with an `OmniCardHeader`; no raw `Text` above a card), effort-kind drives analytics (the layer
classifies nothing — every figure comes from `MixLayerData`), timestamps are source data (no logging flow touched),
reuse the canonical owner (one `StatsWindowChip`, one service instance, one resolved window), instrument panel not
influencer (no chart primitive, no estimating or coaching copy).

## Open questions

- The 50/50 split in finding 1 is reasoned from `RenderFlex`'s flex algorithm, not observed in a run: this review
  could not add a probe test (review-only, gateway-only shell). The mechanism is certain; the *specific* titles that
  now truncate are estimated from glyph metrics, so finding 1 asks for the cap to be removed or documented/tested
  rather than for a named pixel value.
- Whether the title should be capped at half the header, or the actions bounded locally, is a design call. Finding 1
  gives both branches; the smaller alternative (bound the cluster, keep `Expanded` title) is behaviour-neutral for
  every header that has short actions today.

VERDICT: CHANGES_REQUESTED
