# Plan 216 — The first month says there is nothing to compare yet

Series: Stats pre-launch review group E (item 7, the "thin first month" half, of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). Phone only (`lib/features/stats/widgets/instrument_list.dart`), one builder run, then docs. Status: COMMITTED (built, reviewed APPROVE WITH FIXES, fixed).

## Goal and acceptance

A new user's Instruments rows all read `new` in the change column, and the caption above them says `Last 4 weeks. Change is against the 4 weeks before.` as if a comparison existed. Nothing says why every row is `new` or when that will change. After this change, while no row on the list has an earlier period to compare against, one muted line under the caption says so.

Acceptance: S-21601..S-21605 green, the ones marked "fails without" red at the base commit; the existing caption and row tests (`instrument_list_screen_test`, `stats_four_week_window_screen_test`, `stats_instruments_horizon_screen_test`, `instrument_list_service_test`) green and unchanged (the caption text itself does not change); `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- First month (no training in the 4 weeks before the window, so every row is `new`): under the caption, one more muted line: `Nothing to compare yet. Change shows once an exercise was also trained in the 4 weeks before.` (the span comes from the window, as the caption's does: `1 week`, `10 days`, ...).
- As soon as one row has a previous value (some exercise was trained in the earlier period too) the line is gone; the rows that have nothing earlier still read `new`, as today.
- To SEE it: a history whose sessions all fall in the last 4 weeks.
- Unchanged: the caption text, the `new` chips, the values, every other section.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `InstrumentList` (`instrument_list.dart`) computes `final hasComparison = widget.sections.any((s) => s.rows.any((r) => r.previousValue != null))` and, when it is false and there is at least one row, adds the note directly after the caption (still only under the first section header). A new private `_noComparisonNote(context)` builds the `Text` with `Key('instrument_no_comparison_note')`, `labelSmall`, `themeColors.textMuted` (the caption's style), and the copy above using `_span(window.dayCount)`. | `instrument_list.dart:67-79`, `:92-97`, `instrument_list.dart` `InstrumentRow.previousValue` (`lib/core/models/instrument_list.dart:25`) |
| D-2 | The caption's text, key and position are untouched, so the readers that pin it stay as they are. | `test/instrument_list_screen_test.dart:1124,1191,1281` |
| D-3 | No model, service or other screen change; the rule reads `previousValue` only, which the service already sets to null when the earlier period has no comparable value. | `stats_progress_service.dart:1280-1320` |
| D-4 | The wording is the lead's default (the owner said to proceed and explain defaults). | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21601 | `InstrumentList` pumped directly (the hand-built section of `test/instrument_list_screen_test.dart:1135-1195`) with one row whose `previousValue` is null, window `Last 4 weeks` (28 days). | `Key('instrument_no_comparison_note')` is found once with the text `Nothing to compare yet. Change shows once an exercise was also trained in the 4 weeks before.`; the caption text is unchanged; the note sits directly below the caption. | there is no note |
| S-21602 | The same list with two rows, one with a `previousValue` and one without. | no note is shown; the caption is unchanged. | passes with and without the change on purpose: it pins the note's "no row comparable" condition (mutation: the note shows whenever any row is new) |
| S-21603 | Through the real service and `StatsScreen` (Mock, one completed session in the window and none before): the note shows. Then a second case with the same exercise also trained 35 days ago (inside the previous 4 weeks): no note. (Use the history helpers of `test/stats_four_week_window_screen_test.dart`.) | note present in the first case, absent in the second. | there is no note |
| S-21604 | `InstrumentList` pumped directly with two sections (resistance, cardio), all rows new. | exactly one note (under the first header only). | passes with and without the change in the sense that the note does not exist at base, so it fails there; it kills the mutation that adds the note under every header (added after the mutation pass) |
| S-21605 | The same pump with a 10-day window (`Custom`). | the note reads `...once an exercise was also trained in the 10 days before.` | no note at base; kills the mutation that hard-codes `4 weeks` (added after the mutation pass) |

## Input-reality checklist

1. Writers and units: no stored value; `previousValue` is derived by the service from history.
2. Lifecycle: the note follows the window each load.
3. Settings: none read.
4. Time: the span is the window's own length, formatted like the caption's (`_span`), so a 10-day window reads `10 days`.
5. Cost: one `any` over the rows.
6. Words: one plain sentence in two parts; no jargon.
7. Slot competition: the note is one line under the caption, only under the first header; it never appears with the empty state (the list is not built then).

## Phases

1. **P1 builder-app, scope `lib/features/stats/widgets/instrument_list.dart`, `test/stats_no_comparison_note_test.dart` (new):** the exact production code in the brief and S-21601..S-21603 (S-21601/S-21602 pump `InstrumentList` directly, S-21603 through `StatsScreen`). Report FIRST as a skeleton. No full suite.
2. **P2 lead:** docs, mutation pass, `crew-reviewer`, full suite.

## Readers (existing tests that touch the caption area)

`test/instrument_list_screen_test.dart`, `test/stats_four_week_window_screen_test.dart`, `test/stats_instruments_horizon_screen_test.dart`, `test/instrument_list_service_test.dart`, plus any test that counts `Text` widgets or children under the first header (S-4018 "one caption, under the first header"). A first-month fixture in those files gets one more muted line; a count-based assertion that breaks is reported, not edited.

## Mutation list (lead)

(a) the note never shows; (b) the note shows whenever any row is `new` (`all` instead of none comparable); (c) the note shows under every section header; (d) the note uses the caption's span of a different window (a hard-coded `4 weeks`).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen.md` | ADDED | - | Nothing to compare yet. | S-21601, S-21602, S-21603 |
| `docs/stats_screen.md` | ADDED | - | `test/stats_no_comparison_note_test.dart` | S-21601 |
| `docs/widget_catalog.md` | ADDED | - | `instrument_no_comparison_note` | S-21601 |

Stale-term sweep (`grep -rIniE "Change is against|nothing comparable|reads .new" docs`, minus plans/history/releases): `stats_screen.md:312` (the caption paragraph the new sentence follows), `:334` (`new` when nothing comparable, still true), `widget_catalog.md:26` (the Instruments list row).

## Open items

1. The rows still each say `new`; the note explains why but does not replace the chips (a first-month screen with ten `new` chips is still busy).
2. The note can still read oddly in rare cases: when the earlier period holds only other exercises, or the same exercise on another measure (pace before, time now), no row has a comparison and the note shows (the wording talks about exercises for this reason, review major, fixed); when an earlier value is the zero fallback the chips compare against zero and the note is hidden (existing chip behaviour).
3. The totals for a thin first month still live only on Records & Trends.
4. (owner) A device check: a history with all sessions inside the last 4 weeks; read the new line.

## Predicted files

`instrument_list.dart` (+20), `test/stats_no_comparison_note_test.dart`, two docs.

## Progress

- [x] Seeded (scout of the caption, `previousValue`, the `new` chip, the readers)
- [x] P1 build (5.8 min)
- [x] Docs, mutation pass (5 mutants: 3 killed at first, S-21604/S-21605 added, 4 killed; 1 equivalent: the empty-rows guard, because a section is only built with a row)
- [x] Review: APPROVE WITH FIXES (major: the first copy overclaimed "the 4 weeks before also hold training"; reworded; minor: the note gate now looks at every section)
- [x] Full suite (+7790, 0 failures, run on the final code)

## Assumption Log

- 2026-11-16: base commit `82db7759` on `claude_develop`; other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-16: scenario ids S-216xx; grep over `test`, `docs`, `lib`, `watch` found none.
- 2026-11-16: the wording and the choice to add a line (rather than change the caption or hide the `new` chips) are the lead's defaults.

## Feedback

(none yet)
