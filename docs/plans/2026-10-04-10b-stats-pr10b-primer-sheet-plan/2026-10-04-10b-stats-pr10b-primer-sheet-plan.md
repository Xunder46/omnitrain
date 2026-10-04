# Feature: Stats PR 10b — a "?" explanation sheet and a friendlier first-use screen

> Status: DRAFT — the auto-open is hosted by `HomeScreen`, the Nutrition way, not by `StatsScreen`,
> and the seen flag is marked when the sheet closes by any means (D-2022). Copy is pinned below and
> marked **owner to confirm** (see Open questions). Not started. Next handoff: **@dba (Phase 1)**.
> Plan folder: `docs/plans/2026-10-04-10b-stats-pr10b-primer-sheet-plan/` — this file,
> `2026-10-04-10b-stats-pr10b-primer-sheet-plan.evidence.md` (executors),
> `2026-10-04-10b-stats-pr10b-primer-sheet-plan.review.md` (reviewer).
> Binding conventions: [`docs/global_conventions.md`](../../global_conventions.md);
> [`docs/design_system.md`](../../design_system.md) (the explicit-`shape` rule for every button,
> "Adding or changing a theme"); [`docs/widget_catalog.md`](../../widget_catalog.md) (feature-scoped
> "Notes" pattern); [`docs/widget_catalog/nutrition_widgets.md`](../../widget_catalog/nutrition_widgets.md)
> → `NutritionPrimerSheet`; [`docs/state_management/nutrition_state.md`](../../state_management/nutrition_state.md)
> → `NutritionPrimerState`. Budget: [`.github/agents/pr_scope_budget.md`](../../../.github/agents/pr_scope_budget.md).

## Overview

A first-time user opening Stats sees one card, `No sessions yet`, and nothing else. Nothing on the
screen explains what will appear once they train, and nothing explains the Signals cards or the chart
icon. This PR adds the explanation surface the owner approved:

1. A **"?" control in the Stats header, next to the chart icon**, opening a three-block explanation
   sheet. The sheet auto-opens once on the **first Stats tap from Home**, is marked seen when it
   closes **by any means**, and is reopenable from the "?" at any time **without** marking anything.
   It is hosted by `HomeScreen` exactly as the Nutrition primer is, with one deliberate difference
   noted in D-2022.
2. A **richer first-use card**: the existing title and body kept verbatim, plus three short lines
   about what will appear, plus a `How Stats works` text button that opens the same sheet.

No inline notes anywhere else on the screen (owner decision), and never the wording "still building"
or anything else that reads as unfinished work.

## Scope

**In:** `StatsPrimerState` (the `primer_seen_stats` flag over the repository preference API, hydrated
before `runApp`, with its own Mock + Hive tests); `StatsPrimerSheet` (one `OmniSurface` column, eyebrow,
title, three keyed blocks, one `Got it` CTA); the Stats header "?" beside the existing chart icon; the
one-shot auto-open on the **first Stats tap from Home**, hosted by `HomeScreen`, with the seen flag
marked when the sheet closes by any means; the richer first-use card and its `How Stats works` button;
the DI thread `main.dart → MyApp → HomeScreen` (and `MyApp → OnboardingScreen → HomeScreen`,
forward-only), with `StatsScreen` receiving only `bool showPrimerHelp`; structural guards, a residue
sweep and the docs.

**Out:** the Nutrition primer, its sheet, its state and its tests; any inline note, banner, tooltip or
helper line on the Stats body explaining Signals or Fuel; the duplicated empty state in
`lib/features/stats/records_and_trends_screen.dart`; any new colour, token, theme value, animation or
route; `docs/signals.md`; the Stats data pipeline, the signals registry, the dismissal store and the
Fuel row.

## Findings (research, 2026-10-04)

| # | Finding | Where |
|---|---|---|
| F-1 | The Nutrition primer is a clean template: the sheet is pure presentation and takes `onDismiss`; the host decides what dismissal means. The state persists one flag and never mutates on reopen. | `lib/features/nutrition/widgets/nutrition_primer_sheet.dart`, `lib/state/nutrition/nutrition_primer_state.dart` |
| F-2 | The Nutrition header "?" is `IconButton(key: Key('nutrition_primer_help'), icon: Icons.help_outline, tooltip: 'About Daily Nutrition', onPressed: _reopenPrimer)`; `_reopenPrimer` hosts the sheet with `onDismiss: null`. | `lib/features/nutrition/nutrition_screen.dart` ~107–154 |
| F-4 | The Stats header already has exactly one action: a `Semantics(label: 'Records & Trends', button: true)` wrapping an `IconButton(Icons.show_chart, tooltip: 'Records & Trends', color: OmniTheme.colors.textDominant)`. | `lib/features/stats/stats_screen.dart` ~236–252 |
| F-5 | The Stats empty state is an `OmniSurface` column: 48px `Icons.bar_chart_outlined` at `textMuted` α0.5, title `No sessions yet` (`titleMedium`, `textDominant`), body `Complete your first session to see stats here.` (`bodySmall`, `textMuted`, centred). | `lib/features/stats/stats_screen.dart` ~366–392 |
| F-6 | The **same two strings** are also rendered by Records & Trends. They are two independent copies; the owner's change is about the Stats screen only. | `lib/features/stats/records_and_trends_screen.dart` ~355/362; asserted at `test/records_and_trends_screen_test.dart` 121/123 |
| F-7 | Eight test files assert the two empty-state strings. Six of them do so for **other** screens or for Stats **with `showPrimerHelp` omitted**, so none needs editing (see Phase 2A step 6). | `mix_layer_screen_test.dart:1133`, `header_standardization_test.dart:2842`, `nutrition_trend_screen_test.dart:283`, `signals_layer_screen_test.dart:1248`, `screen_widget_test.dart:2707/2709/2957`, `stats_legacy_removal_test.dart:487`, `fuel_row_screen_test.dart` (S-1107), `records_and_trends_screen_test.dart:121/123` |
| F-8 | 18 test files construct `StatsScreen(`; every one of them passes only `workoutState` and `settingsState` (plus the optional `signals:`). A `bool showPrimerHelp` that defaults to `false` leaves all 18 trees byte-for-byte unchanged. | `grep -l "StatsScreen(" test` |
| F-9 | `test/records_and_trends_screen_test.dart` S-913 finds the chart entry point by `find.byTooltip('Records & Trends')` and taps it; a separate static scan asserts `lib/features/stats/stats_screen.dart` is the **only** `RecordsAndTrendsScreen(` construction site in `lib/`. A second header action with a different tooltip and key breaks neither. | `test/records_and_trends_screen_test.dart` ~383–445, 692–705 |
| F-10 | `test/header_standardization_test.dart` pumps `StatsScreen` without a primer state and asserts the header title, the back icon and the empty state — never an action count. | `test/header_standardization_test.dart` ~571–583, 2794–2845 |
| F-11 | The repository preference surface is `getPreferenceBool` / `setPreferenceBool`, implemented by both `HiveWorkoutRepository` and `MockWorkoutRepository`. | `lib/data/repositories/workout_repository.dart` ~423–427; Hive ~971–980; Mock ~1710–1720 |
| F-12 | Widget tests run under `FakeAsync`, where a Hive write never drains — persistence is asserted in plain `test()` bodies over `test/helpers/repository_harness.dart` (`harnessFactories`, `HiveRepositoryHarness.restart()`), the pattern `test/entry_identity_test.dart` uses. | `test/helpers/repository_harness.dart`, `test/entry_identity_test.dart` |
| F-13 | `test/screen_overflow_contract_test.dart` builds Stats **with seeded sessions**; there is no small-viewport case for the empty card, so the taller card needs its own overflow assertion. | `test/screen_overflow_contract_test.dart` |
| F-14 | `docs/stats_screen.md` documents the header entry point (chart icon only) and mentions the empty state in passing; `docs/state_management.md` has a class→page lookup table; `docs/README.md` has a source-tree block listing `lib/state/` subdirectories. There is no Stats state page and no `lib/state/stats/` directory yet. | `docs/stats_screen.md` 13–27, 343; `docs/state_management.md` 41/63; `docs/README.md` ~140 |
| F-15 | `docs/signals.md` is 47 KB — the only doc near the 64 KiB ceiling. It is not touched. | brief; `test/docs_indexing_contract_test.dart` |
| F-16 | `lib/features/splash/omni_splash_screen.dart` still declares and forwards `nutritionPrimerState`, but its entry point in `app.dart` is disabled (the README calls it "disabled"). It is dead code and is left untouched. | `lib/features/splash/omni_splash_screen.dart`; `docs/README.md` ~131 |
| F-17 | The shipped Nutrition primer's auto-open is hosted by the **home screen**, not the nutrition page: `_openNutritionScreen` awaits `_showNutritionPrimer()` (a `showModalBottomSheet` with `onDismiss: () => unawaited(markSeen())`) and only then pushes `NutritionScreen`; the page's `_reopenPrimer` passes `onDismiss: null`. Copying that pattern for Stats means hosting the auto-open in `HomeScreen`. | `lib/features/home/home_screen.dart` ~378–421; `lib/features/nutrition/nutrition_screen.dart` ~111–127 |
| F-18 | The only `StatsScreen(` construction in `lib/` is the 'Stats' `_MaintenanceItem` in `HomeScreen._buildMaintenanceGrid`. The hub is an in-Home draggable sheet, not a modal, so a modal primer sheet over Home behaves exactly as it does for Nutrition. | `lib/features/home/home_screen.dart` ~1171; `grep -rn "StatsScreen(" lib/` |
| F-19 | `HomeScreen` declares `nutritionPrimerState` as **required** (so its nine constructing test files already pass one), and exposes the hub via a logo tap (`find.byType(Image)`) whose tiles are `MaintenanceTile` with a `.title`; the Stats tile is the second. A HomeScreen-level primer test opens the hub, taps the Stats tile and asserts the sheet, mirroring `test/nutrition_primer_test.dart`. | `lib/features/home/home_screen.dart` ~91/119; `test/home_logo_hub_open_test.dart` ~338–365 |
| F-20 | The Signals copy in the pinned block matches the shipped gates: the baseline gate is `>= kTrainingLoadMinRatedWeeks` (= 4) rated weeks via `signalsGateMet`, and a dismissal hides a signal for `kSignalDismissalDays` (= 14). One signal (Cardio Efficiency Drift) needs average heart-rate data, which is why the copy says "a watch". | `lib/core/models/signals.dart` 18/72; `lib/core/models/training_load.dart` 23 |
| F-21 | `test/helpers/test_nutrition_primer_state.dart` is a two-line `buildNutritionPrimerState(repo)` helper; a sibling `buildStatsPrimerState(repo)` fits the same shape. The 18 `StatsScreen`-pumping files and the nine `HomeScreen`-constructing files need no edit because `statsPrimerState` stays nullable-optional and `showPrimerHelp` defaults off. | `test/helpers/test_nutrition_primer_state.dart`; F-8, F-19 |

## Decision Ledger

Decisions are contracts. Immutable once written: a change is a new superseding entry.

- **D-2001 — Sibling classes, not an extraction.** A new `StatsPrimerSheet` and a new
  `StatsPrimerState` mirror the Nutrition pair. The Nutrition primer files are **not** edited, so
  `test/nutrition_primer_test.dart` stays green with zero edits. Reason: a shared extraction would
  refactor a shipped, tested feature to serve one new caller, and the duplicated surface is a
  presentation column plus a one-flag notifier.
- **D-2002 — The flag key is exactly `primer_seen_stats`**, exposed as
  `StatsPrimerState.preferenceKey`. It is distinct from `primer_seen_nutrition`; the two flags must be
  readable and writable independently (S-2706).
- **D-2003 — New files live at `lib/state/stats/stats_primer_state.dart` and
  `lib/features/stats/widgets/stats_primer_sheet.dart`.** `lib/state/nutrition/` is the precedent for a
  feature-scoped state directory.
- **D-2004 — SUPERSEDED by D-2019** (the injection seam moved off `StatsScreen`).
- **D-2005 — SUPERSEDED by D-2020** (the DI chain no longer reaches `StatsScreen`).
- **D-2006 — SUPERSEDED by D-2021** (the auto-open moved to the Home tap handler).
- **D-2007 — SUPERSEDED by D-2021** (there is no route transition to wait for).
- **D-2008 — SUPERSEDED by D-2022** (the flag is marked when the sheet's future completes, not by an
  `onDismiss` callback that only the `Got it` button fires).
- **D-2009 — The "?" is the first entry of `OmniBackHeader.actions`, so the chart icon stays
  rightmost.** It is `Semantics(label: 'About Stats', button: true)` wrapping
  `IconButton(key: Key('stats_primer_help'), icon: Icon(Icons.help_outline), color: OmniTheme.colors.textDominant, tooltip: 'About Stats')`.
  The icon colour follows the sibling chart action in the **same** header (`textDominant`), not the
  Nutrition header's `colorScheme.primary`.
- **D-2010 — The sheet is one `OmniSurface` column:** padding `fromLTRB(20, 20, 20, 20)`, eyebrow
  `STATS`, title `A quick orientation`, exactly three blocks keyed
  `stats_primer_block_page`, `stats_primer_block_signals`, `stats_primer_block_records` (each a
  `OmniCardHeader` label over one `bodyMedium` sentence), and one full-width `FilledButton` keyed
  `stats_primer_dismiss` labelled `Got it` with
  `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius))`
  at `OmniTheme.buttonPrimaryHeight`. No carousel, no step indicator, no anchored pointers, no
  `PageView`. The sheet is presentation-only: it imports no state class and reads no repository.
- **D-2011 — The copy is pinned verbatim in the "Pinned copy" section below** and is marked **owner to
  confirm**. Sentence case, no exclamation, no coaching, no causal claim, no medical language, and
  none of: `still building`, `coming soon`, `gate`, `window`, `load baseline`, `unfinished`. Drafting
  language is the planner's; changing it is the owner's.
- **D-2012 — The empty-state contract.** The title `No sessions yet` and the body
  `Complete your first session to see stats here.` are kept **verbatim** (so the eight existing
  assertions in F-7 stay green untouched). Below the body, three short centred `bodySmall` /
  `textMuted` lines are added, then a `TextButton` keyed `stats_primer_empty_cta` labelled
  `How Stats works`, rendered **only** when `showPrimerHelp` is true (D-2019). No new colour, no
  new token, no new surface, no icon, no animation.
- **D-2013 — The Records & Trends empty state is not changed.** Its copy stays as-is; this PR's
  first-use change is the Stats screen's card only (F-6).
- **D-2014 — The empty-state button uses the in-Stats utility pattern:** `Align(alignment: Alignment.centerLeft)`
  wrapping a `TextButton` whose `style` sets `shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius)))`
  — the same shape `instrument_show_all_*` uses. Every button in this PR sets `shape` explicitly
  (design-system rule).
- **D-2015 — Hydration failure is conservative.** If `getPreferenceBool` throws, `init()` leaves the
  state unseen (the primer shows at least once) and still notifies once; `init()` is idempotent
  (S-2711).
- **D-2016 — The sheet is the only explanation surface.** No inline note, banner, tooltip or helper
  line is added to the Stats body for Signals or Fuel, in any state (owner decision).
- **D-2017 — Persistence is proved in plain `test()` bodies, not widget tests.** Any widget-level
  assertion about the flag reads the Mock repository only; the Hive round trip lives in
  `test/stats_primer_state_test.dart` over `harnessFactories` (F-12).
- **D-2018 — Docs ship with the behaviour.** Each doc sentence about this feature names an existing
  test by its exact name. `docs/signals.md` is not touched (F-15).
- **D-2019 — `StatsScreen` takes one optional `final bool showPrimerHelp;` that defaults to `false`;
  it does NOT take the primer state.** When `false` the rendered tree is byte-for-byte today's (no
  "?", no empty-card button). `HomeScreen` passes `showPrimerHelp: widget.statsPrimerState != null`.
  The "?" and the empty-card button host `StatsPrimerSheet` with `onDismiss: null`, so the screen has
  no reference through which it could mark the flag — "reopen never marks" is structural, not a code
  path. Wherever the ledger says the feature is active "when the primer state is injected" (D-2012,
  D-2014), read "when `showPrimerHelp` is true". **Supersedes D-2004.** (F-8, F-21)
- **D-2020 — The state is constructed and `await init()`-ed in `lib/main.dart` before `runApp`, then
  threaded `MyApp → HomeScreen` and `MyApp → OnboardingScreen → HomeScreen` (forward-only).** The
  parameter is nullable-optional at **every** hop (`MyApp`, `OnboardingScreen`, `HomeScreen`); with a
  null state the 'Stats' tile pushes `StatsScreen` directly with `showPrimerHelp: false`, exactly as
  today. `main.dart` is the only non-null caller. `StatsScreen` is **not** in the chain (D-2019).
  `lib/features/splash/omni_splash_screen.dart` is not touched (F-16). **Supersedes D-2005.**
- **D-2021 — The auto-open is hosted by `HomeScreen`, mirroring the shipped Nutrition primer's
  hosting shape (the sheet is shown over Home, then the page is pushed).** New private
  `_openStatsScreen()` / `_showStatsPrimer()` in `home_screen.dart`: if
  `widget.statsPrimerState?.shouldShowPrimer == true`, `await _showStatsPrimer()`, then
  `if (!mounted) return;`, then `OmniNavigator.push(... StatsScreen(showPrimerHelp:
  widget.statsPrimerState != null) ...)`. `_showStatsPrimer()` hosts `StatsPrimerSheet` in
  `showModalBottomSheet` with `onDismiss: null` and marks seen after the awaited future completes
  (D-2022). The 'Stats' `_MaintenanceItem` `onTap` calls `_openStatsScreen`. There is no post-frame
  callback, no `_primerAutoShown` flag and no route-settle listener: the auto-open runs once per tap
  by construction, and a second tap (flag now seen) pushes Stats directly (S-2716). **Supersedes
  D-2006 and D-2007.** (F-17, F-18, F-19)
- **D-2022 — The seen flag is marked when the sheet's `showModalBottomSheet` future completes, by any
  means; this is the one place Stats deliberately differs from the Nutrition primer.**
  `_showStatsPrimer()` is `await showModalBottomSheet<void>(...)` (building the sheet with no
  `onDismiss`) followed by `unawaited(widget.statsPrimerState!.markSeen())`. The future completes when
  the sheet is popped — by the `Got it` CTA, by a swipe-down, or by a tap on the modal barrier — so a
  close of any kind counts as seen. `StatsPrimerSheet` still accepts an optional `onDismiss` (parity
  with `NutritionPrimerSheet`), but every Stats host passes `null`, so the sheet itself never marks;
  the "?" and the empty-card button hosts pass `null` too and never mark. Product behaviour: once the
  sheet has been shown and closed in any way it will not open by itself again; the user can always
  reopen it from the "?". This supersedes D-2008's mechanism. Verified in the shipped Nutrition code:
  `NutritionPrimerSheet` fires `onDismiss` only from its `Got it` button
  (`nutrition_primer_sheet.dart` ~line 142), so a swipe-away or outside tap does **not** mark seen
  there — the comment in `home_screen.dart` `_showNutritionPrimer` overclaims. Nutrition is not
  touched.

## Pinned copy (owner to confirm)

The strings below are final drafts (the planner's); the host moved, not the copy. Block 2's "a watch"
was checked against the shipped gates: the Signals baseline is `>= kTrainingLoadMinRatedWeeks` (= 4)
rated weeks via `signalsGateMet`, a dismissal hides a signal for `kSignalDismissalDays` (= 14), and
one signal (Cardio Efficiency Drift) needs average heart-rate data, so "a watch" is accurate (F-20).
The planner kept the wording; changing it is the owner's (O-2).

Sheet — `lib/features/stats/widgets/stats_primer_sheet.dart`:

| Slot | Key | Exact string |
|---|---|---|
| Eyebrow | — | `STATS` |
| Title | — | `A quick orientation` |
| Block 1 label | `stats_primer_block_page` | `WHAT THIS PAGE SHOWS` |
| Block 1 body | `stats_primer_block_page` | `Your training mix by kind of work, the exercises you have trained and how they changed since last time, all-time totals, and your Fuel row once you log food.` |
| Block 2 label | `stats_primer_block_signals` | `SIGNALS` |
| Block 2 body | `stats_primer_block_signals` | `Short notes about your own patterns, compared only with your own history. They start after about four weeks of rating how hard each workout felt, and a few need food logging or a watch. Dismiss any card and it stays hidden for 14 days.` |
| Block 3 label | `stats_primer_block_records` | `THE CHART ICON` |
| Block 3 body | `stats_primer_block_records` | `Opens Records & Trends: your personal records and the full history of each exercise. Tap an exercise there to see its progress.` |
| CTA | `stats_primer_dismiss` | `Got it` |

Empty card — `lib/features/stats/stats_screen.dart`, below the existing body line, in order:

| Slot | Key | Exact string |
|---|---|---|
| Existing title (kept) | — | `No sessions yet` |
| Existing body (kept) | — | `Complete your first session to see stats here.` |
| New line 1 | — | `Your training mix, by kind of work.` |
| New line 2 | — | `Your records, and how each exercise changes over time.` |
| New line 3 | — | `How your eating lines up with your training, once you log food.` |
| Button | `stats_primer_empty_cta` | `How Stats works` |

Tooltip / semantics label for the header control: `About Stats`.

## Feature Invariants

Only the invariants this feature can break:

- **Repository parity.** `getPreferenceBool` / `setPreferenceBool` behave identically on
  `HiveWorkoutRepository` and `MockWorkoutRepository`; `primer_seen_stats` round-trips on both, and
  the two primer flags are independent (S-2705, S-2706).
- **Zero-touch compatibility.** With `showPrimerHelp` omitted (every existing `StatsScreen` consumer)
  the Stats tree is unchanged: no extra action, no extra text, no extra button (S-2703). With a null
  `statsPrimerState` (every existing `HomeScreen` consumer) the 'Stats' tile pushes Stats directly
  (S-2717).
- **No silent seen-marking.** `markSeen()` is called from exactly one place — `HomeScreen._showStatsPrimer()`,
  after the awaited sheet future completes (D-2022). Reopening from the "?" or the empty-card button
  never marks (S-2704, S-2707, S-2718). `StatsScreen` holds no reference to the state, so it cannot mark.
- **The sheet never gates access.** It is a modal sheet over a fully usable screen; dismissing it
  leaves the screen as it was, and no state is required to reach Stats or Records & Trends.
- **Design-system compliance.** Every new button sets `shape` explicitly; no new colour, token or
  theme value is introduced.
- **No unfinished-feature language.** The banned word list in D-2011 appears nowhere in `lib/`.

## Requirements

| # | Requirement | Scenario |
|---|---|---|
| R-1 | The Stats header carries a "?" control next to the chart icon, with the key, icon, tooltip and semantics label in D-2009. | S-2708 |
| R-2 | The sheet auto-opens once on the first Stats tap from Home when Home holds a primer state and the flag is unset. | S-2701 |
| R-3 | A second Stats tap from Home after the primer is seen pushes Stats directly with no sheet. | S-2716 |
| R-4 | With no primer state on Home the tap pushes Stats directly and the Stats tree has no "?". | S-2717 |
| R-5 | Closing the auto-shown sheet marks the flag seen, once, by any means (the `Got it` CTA, a swipe-down, or a barrier tap). | S-2701, S-2710, S-2718 |
| R-6 | The "?" reopens the sheet at any time and never marks the flag. | S-2704 |
| R-7 | The flag persists across an app restart and hydrates before the first frame. | S-2705 |
| R-8 | The Stats and Nutrition primer flags are independent. | S-2706 |
| R-9 | A hydration failure leaves the primer unseen. | S-2711 |
| R-10 | With no primer state on Home (or `showPrimerHelp` omitted) the feature is entirely absent from the tree. | S-2703, S-2717 |
| R-11 | The first-use card keeps its title and body verbatim, adds three short lines and a `How Stats works` button. | S-2707 |
| R-12 | The first-use card's button opens the same sheet and never marks the flag. | S-2707 |
| R-13 | The taller first-use card does not overflow a small phone viewport. | S-2714 |
| R-14 | A seen flag suppresses the auto-open on later Stats taps in the same run. | S-2716 |
| R-15 | No inline note explains Signals or Fuel anywhere on the screen. | S-2703, S-2715 |
| R-16 | Docs describe only shipped behaviour and name existing tests. | S-2715 |

## Scenarios

Fixtures are enumerated. "Injected" means a `StatsPrimerState` built over a **Mock**
`WorkoutRepository` (widget tests) or over a harness repository (plain tests).

### S-2701: the first Stats tap from Home shows the primer once
- **Fixture:** one `MockWorkoutRepository`, initialised, **no** completed sessions, **no**
  `primer_seen_stats` row. One `StatsPrimerState` over it with `await init()` done (so
  `shouldShowPrimer == true`). `HomeScreen(... statsPrimerState: state)` pumped under `MaterialApp`.
- **Trigger:** open the hub (tap the logo) and tap the 'Stats' `MaintenanceTile`.
- **Flow:** the tile's `onTap` awaits `_showStatsPrimer()` → sheet shown; tap `stats_primer_dismiss`.
  The host marks seen when the sheet's future completes (D-2022), not while it is open.
- **Expected outcome:** `StatsPrimerSheet` is on screen with exactly the three block keys and the
  `Got it` CTA, and `state.hasSeen` is still `false` while it is up; after the tap the sheet is gone,
  `StatsScreen` is pushed, and `state.hasSeen == true` with `state.shouldShowPrimer == false`.
- **Edge case of:** none

### S-2703: with `showPrimerHelp` omitted the Stats primer feature is off
- **Fixture:** `MockWorkoutRepository` with no completed sessions; `StatsScreen(workoutState:,
  settingsState:)` constructed with `showPrimerHelp` **omitted** (the default `false` — exactly what
  all 18 existing files do).
- **Trigger:** pump and settle.
- **Flow:** none.
- **Expected outcome:** `find.byKey(Key('stats_primer_help'))` is empty,
  `find.byType(StatsPrimerSheet)` is empty, `find.byKey(Key('stats_primer_empty_cta'))` is empty, and
  the chart action (`find.byTooltip('Records & Trends')`) is still present exactly once.
- **Edge case of:** none — this is the compatibility contract for the 18 existing files (F-8).

### S-2704: the header "?" reopens the primer and never marks it
- **Fixture:** `MockWorkoutRepository` with no completed sessions;
  `StatsScreen(workoutState:, settingsState:, showPrimerHelp: true)` pumped under `MaterialApp`. The
  state is **not** passed to the screen (D-2019). Two cases: (a) the test holds an unseen
  `StatsPrimerState`; (b) the test holds a seen one.
- **Trigger:** tap `stats_primer_help` in each case.
- **Flow:** sheet shows; tap `Got it`.
- **Expected outcome:** in both cases the sheet is shown and then gone; the held state is
  **unchanged** — (a) `hasSeen` stays `false` / `shouldShowPrimer` stays `true`, (b) `hasSeen` stays
  `true`. The screen cannot mark because it holds no reference; the Phase 3A guard
  `the Stats screen holds no StatsPrimerState` makes that structural (S-2715).
- **Edge case of:** S-2701

### S-2705: the seen flag survives a restart
- **Fixture:** a harness repository from `harnessFactories` (Mock and Hive), one
  `StatsPrimerState` over it. Plain `test()`, no widget, no `FakeAsync`.
- **Trigger:** `markSeen()`; then `restart()` the harness; construct a **fresh**
  `StatsPrimerState` over the restarted repository and `await init()`.
- **Flow:** write → restart → hydrate.
- **Expected outcome:** the fresh state reports `hasSeen == true` and `shouldShowPrimer == false`.
- **Edge case of:** none

### S-2706: the two primer keys are independent
- **Fixture:** one harness repository, one `StatsPrimerState` and one `NutritionPrimerState` over the
  same repository. Plain `test()`.
- **Trigger:** `statsPrimer.markSeen()` only.
- **Flow:** read both persisted flags.
- **Expected outcome:** `getPreferenceBool('primer_seen_stats') == true` and
  `getPreferenceBool('primer_seen_nutrition') == false`; then marking the Nutrition primer seen
  leaves the Stats flag unchanged.
- **Edge case of:** S-2705

### S-2707: the first-use card explains what will appear
- **Fixture:** `MockWorkoutRepository` with no completed sessions; `StatsScreen(workoutState:,
  settingsState:, showPrimerHelp: true)` pumped under `MaterialApp`, Mock only. The held state is
  unseen so the assertion "after dismissal `hasSeen` is still `false`" is meaningful.
- **Trigger:** pump and settle; tap `stats_primer_empty_cta`.
- **Flow:** read the card, open the sheet from the button, dismiss it.
- **Expected outcome:** the card shows `No sessions yet` and
  `Complete your first session to see stats here.` exactly once each, plus the three new lines in
  order, plus a `TextButton` labelled `How Stats works`; tapping it shows the sheet with the three
  block keys; after dismissal the held state's `hasSeen` is still `false`.
- **Edge case of:** S-2701

### S-2708: the "?" and the chart icon coexist
- **Fixture:** `StatsScreen(workoutState:, settingsState:, showPrimerHelp: true)` over a Mock
  repository with **no** sessions.
- **Trigger:** read the header; tap the chart icon.
- **Flow:** assert both actions, then navigate.
- **Expected outcome:** `find.byKey(Key('stats_primer_help'))` and
  `find.byTooltip('Records & Trends')` are each present once;
  `find.byTooltip('About Stats')` is present once; tapping the chart icon lands on
  `RecordsAndTrendsScreen`. `test/records_and_trends_screen_test.dart`'s static scan still reports
  `lib/features/stats/stats_screen.dart` as the only construction site.
- **Edge case of:** none

### S-2710: markSeen is idempotent
- **Fixture:** a recording repository stub that counts `setPreferenceBool` calls and
  `notifyListeners` via a listener counter. Plain `test()`.
- **Trigger:** `markSeen()` twice.
- **Flow:** none.
- **Expected outcome:** exactly one `setPreferenceBool(preferenceKey, true)` call and exactly one
  notification.
- **Edge case of:** S-2705

### S-2711: a hydration failure falls back to unseen
- **Fixture:** a stub repository whose `getPreferenceBool` throws. Plain `test()`.
- **Trigger:** `await init()`.
- **Flow:** none.
- **Expected outcome:** `init()` does not throw; `shouldShowPrimer == true`; a second `init()` is a
  safe no-op.
- **Edge case of:** S-2705

### S-2714: the taller first-use card fits a small viewport
- **Fixture:** S-2701's fixture at a `Size(320, 568)` surface.
- **Trigger:** pump and settle with the auto-shown sheet dismissed.
- **Flow:** none.
- **Expected outcome:** the card, its three lines and its button are all laid out with no
  `RenderFlex overflowed` exception and no off-screen clip.
- **Edge case of:** S-2707

### S-2715: no unfinished-feature wording, no inline notes, and the compatibility seams hold
- **Fixture:** a static source scan over `lib/` (the guards in Phase 3A).
- **Trigger:** read the files.
- **Flow:** none.
- **Expected outcome:** `primer_seen_stats` appears in exactly one `lib/` file
  (`lib/state/stats/stats_primer_state.dart`); `lib/features/home/home_screen.dart` declares
  `StatsPrimerState? statsPrimerState`; `lib/features/stats/stats_screen.dart` declares
  `bool showPrimerHelp` and contains no `StatsPrimerState` reference; and no file under
  `lib/features/stats/` contains any string from the D-2011 banned list.
- **Edge case of:** none

### S-2716: a second Stats tap pushes Stats directly
- **Fixture:** one Mock repository with `primer_seen_stats` already `true`; one `StatsPrimerState`
  over it with `await init()` done (`shouldShowPrimer == false`); `HomeScreen(... statsPrimerState:
  state)` pumped under `MaterialApp`.
- **Trigger:** open the hub and tap the 'Stats' tile.
- **Flow:** none.
- **Expected outcome:** no `StatsPrimerSheet` is shown; `StatsScreen` is pushed directly, with the
  "?" present (`showPrimerHelp` is true because the state is injected).
- **Edge case of:** S-2701 — replaces the dropped S-2712 and covers R-3/R-14.

### S-2717: a Home with no state pushes Stats directly and Stats has no "?"
- **Fixture:** `HomeScreen` constructed with **no** `statsPrimerState` (what the nine existing
  HomeScreen-constructing test files do); a Mock repository with no sessions.
- **Trigger:** open the hub and tap the 'Stats' tile.
- **Flow:** none.
- **Expected outcome:** no `StatsPrimerSheet` is shown and `StatsScreen` is pushed with
  `showPrimerHelp: false`, so `find.byKey(Key('stats_primer_help'))` is empty on the pushed screen.
- **Edge case of:** S-2703 — the Home-level compatibility contract (F-19, F-21).

### S-2718: dismissing the auto-shown sheet by an outside tap still marks it seen
- **Fixture:** S-2701's fixture (unseen, injected, Mock only).
- **Trigger:** open the hub and tap the 'Stats' tile; while the sheet is showing, assert
  `state.hasSeen == false`; then tap the modal barrier (e.g. `tester.tapAt(const Offset(10, 10))`)
  and settle.
- **Flow:** show (not marked) → barrier-tap dismiss (marked) → Stats pushed.
- **Expected outcome:** the flag is `false` while the sheet is up and `true` after the barrier tap,
  and `StatsScreen` is pushed — the mark-on-close contract (D-2022). This is the one place Stats
  differs from the Nutrition primer, whose outside tap does **not** mark seen
  (`nutrition_primer_sheet.dart` fires `onDismiss` only from its `Got it` button).
- **Edge case of:** S-2701

### Dropped scenarios

Superseded by the pre-approval revision; ids are retired and never reused.

- **S-2702** — the sheet does not re-open on a rebuild or a data reload. Dropped: the auto-open is a plain `if (shouldShowPrimer)` in the Home tap handler (D-2021); S-2716 covers non-repetition.
- **S-2709** — the auto-open waits for the route to settle. Dropped: no in-screen auto-open, no route transition (D-2021); `test/nutrition_primer_test.dart` covers the modal-over-Home shape.
- **S-2712** — the seen state is shared across visits. Dropped: the auto-open no longer lives on `StatsScreen`; S-2716 asserts the same behaviour at the Home level.
- **S-2713** — the auto-open does not depend on the screen being empty. Dropped: the sheet opens on the first Stats tap from Home regardless of session count; the plain-words statement is O-6.

## Executor block (applies to every phase)

- **Shell.** Only `.github/copilot/scripts/macos/gateway.sh`, spelled in full, never piped:
  `list`, `lint`, `test [paths] [--plain-name …]`, `format <new file paths>`, `pub-get`,
  `delete-scratch test/zz_*.dart`, `git-status`, `git-diff`, `git-log`, `git-show`.
  A denied command is never retried. A test command over 3 minutes is a hang: stop and report.
- **Formatting.** The gateway refuses `format` on any tracked file. Format **only** files this PR
  creates; edit existing files with minimal `edit` calls and check `git-diff`.
- **No scratch files.** No `test/zz_*.dart` left behind; if one is used, delete it with the gateway
  before the phase ends.
- **Evidence.** Write baselines, suite output lines, red→green tables and mutation records into
  `2026-10-04-10b-stats-pr10b-primer-sheet-plan.evidence.md`. Never into this plan. Review findings go
  in `…plan.review.md`.
- **Steps.** One concern per numbered step, at most ~10 per run. Exact paths, exact pinned strings.
- **Red first.** Before writing a phase's production code, run its new test file and record the red
  output. A test that has never been observed failing is not evidence.
- **Mutations.** Each run names its mutations and, for every one, the seed or stub that turns it red.
  An inverse-edit mutation on an existing file is required in every run that edits one (2A, 2B, 3A).
- **Baselines.** `flutter analyze` = `196 issues found.`, 0 errors; `flutter test` =
  `+3852 ~1: All tests passed!`. PR 10a (test-only) may land first and change the count: **re-measure
  before relying on either number**. One pre-existing timing-sensitive test may fail once in a full
  run: re-run once and record **both** summary lines.
- **Tests.** Widget tests are Mock-first. No real-clock thresholds; drive the frame clock explicitly.
  Prefer plain `test()` outside the widget layer. Never `await Future.delayed` inside `testWidgets`.
- **Ambiguity.** Do not stop. Pick the option most consistent with this Ledger, append an entry to
  `## Assumption Log` (decision, options considered, rationale) and continue.
- **Docs.** A phase that changes behaviour updates the docs it invalidated in the same phase. Every
  behaviour sentence names an existing test by its exact name.

## Phases

Five runs, each ending with the **full suite**: **Phase 1 → Phase 2A → Phase 2B → Phase 3A → Phase 3B.**

Phase 2A (the sheet, the `showPrimerHelp` flag, the "?" and the first-use card) does **not** import
`StatsPrimerState`, so it is independent of Phase 1 and may run first if the visible win is wanted
sooner — at the cost of landing the state a run later. Phase 2B needs both 1 and 2A; Phase 3A guards
what 2B shipped; Phase 3B documents it. There is no useful re-ordering beyond that.

### Phase 1: the seen state and its tests (@dba)

1. [ ] Create `lib/state/stats/stats_primer_state.dart` as a sibling of
   `lib/state/nutrition/nutrition_primer_state.dart` with exactly this public surface:
   `static const String preferenceKey = 'primer_seen_stats';`
   `StatsPrimerState(this._repository)` over a `WorkoutRepository`;
   `bool get shouldShowPrimer => !_seen;` `bool get hasSeen => _seen;`
   `Future<void> init()` (try/catch around `getPreferenceBool(preferenceKey)`; on throw leave
   `_seen = false`; `notifyListeners()` exactly once; idempotent);
   `Future<void> markSeen()` (early-return when `_seen`; set it; `notifyListeners()`; then
   `await _repository.setPreferenceBool(preferenceKey, true)`).
   The class doc states the hydration contract (construct in `lib/main.dart`, `await init()` before
   `runApp`, idempotent) and the reopen contract (the header "?" never mutates the flag). The file's
   header comment references **this** plan's path, not the nutrition plan's.
2. [ ] Create `test/stats_primer_state_test.dart` — **plain `test()` bodies only, no `testWidgets`** —
   driven by `harnessFactories` from `test/helpers/repository_harness.dart` (F-12), with exactly these
   groups and test names:
   - `S-2705: the seen flag survives a restart` ›
     `a marked-seen Stats primer is seen again after a Hive restart` (S-2705)
   - `S-2706: the two primer keys are independent` ›
     `marking the Stats primer seen leaves the Nutrition primer unseen` (S-2706)
   - `S-2710: markSeen is idempotent` ›
     `two markSeen calls write the flag once and notify once` (S-2710)
   - `S-2711: a hydration failure falls back to unseen` ›
     `a throwing getPreferenceBool leaves the primer unseen` (S-2711)
   The S-2706 case imports `NutritionPrimerState` and writes through the same repository; the S-2710
   and S-2711 cases use local stub repositories defined in the test file.
3. [ ] **Red run first:** before step 1's file exists, run
   `.github/copilot/scripts/macos/gateway.sh test test/stats_primer_state_test.dart` and record the
   compile failure. Then run it again after step 1 and record the green line.
4. [ ] Mutation pair A: change `preferenceKey` to `'primer_seen_nutrition'` → the S-2706 case must go
   red. Restore and re-run.
5. [ ] Mutation pair B: delete the `await _repository.setPreferenceBool(...)` line in `markSeen` → the
   S-2705 case must go red. Restore and re-run.
6. [ ] `.github/copilot/scripts/macos/gateway.sh format` on the two new files only, then
   `gateway.sh lint` (expect `196 issues found.`, 0 errors — re-measure per the Executor block).

**Done Criteria** (run until green):
`.github/copilot/scripts/macos/gateway.sh test test/stats_primer_state_test.dart`;
`.github/copilot/scripts/macos/gateway.sh lint`.
**Predicted Files:** `lib/state/stats/stats_primer_state.dart` (new),
`test/stats_primer_state_test.dart` (new). Nothing else.

### Phase 2A: the sheet, the `showPrimerHelp` flag, the "?" and the first-use card (@developer)

1. [ ] Create `lib/features/stats/widgets/stats_primer_sheet.dart` mirroring
   `lib/features/nutrition/widgets/nutrition_primer_sheet.dart` per D-2010, with the "Pinned copy"
   strings verbatim and the keys `stats_primer_block_page`, `stats_primer_block_signals`,
   `stats_primer_block_records`, `stats_primer_dismiss`. Pure presentation: no state import, no
   repository, no preference key. The `Got it` CTA pops first, then calls `onDismiss?.call()`.
2. [ ] In `lib/features/stats/stats_screen.dart`: add `final bool showPrimerHelp;` with the
   constructor parameter defaulting to `false` (D-2019) and the `StatsPrimerSheet` import. Do **not**
   add a `StatsPrimerState` import or field — the screen must not hold the state.
3. [ ] In the same file, insert the "?" as the **first** entry of `OmniBackHeader.actions` behind
   `if (widget.showPrimerHelp)`, exactly as D-2009 pins it, leaving the chart action unchanged and
   last. Host the sheet with `onDismiss: null` (D-2019) so the reopen can never mark seen.
4. [ ] In the same file's `_buildEmptyState`, keep the existing title and body strings verbatim and
   add, below the body, the three new lines from "Pinned copy" (each its own centred `Text`,
   `bodySmall` / `textMuted`, `SizedBox(height: 4)` between them) followed by the `How Stats works`
   `TextButton` per D-2012 / D-2014, rendered only when `widget.showPrimerHelp`. Host the sheet with
   `onDismiss: null`. No new colour, no new token, no new surface.
5. [ ] Create `test/stats_primer_screen_test.dart` (Mock-first, `testWidgets`, `showPrimerHelp`
   omitted unless a case needs it) with exactly these groups and test names:
   - `S-2703: with showPrimerHelp omitted the Stats primer feature is off` ›
     `no help action, no empty-state button and the chart action still renders`
   - `S-2704: the header "?" reopens the primer and never marks it` ›
     `reopening with an unseen state leaves it unseen` and
     `reopening with a seen state still opens the sheet`
   - `S-2707: the first-use card explains what will appear` ›
     `the empty state keeps its title and body and adds the explanation and the button` and
     `the empty-state button opens the sheet without marking it seen`
   - `S-2708: the "?" and the chart icon coexist` ›
     `the chart icon stays the only way into Records & Trends`
   - `S-2714: the taller first-use card fits a small viewport` ›
     `the card lays out at 320x568 without an overflow`
6. [ ] **State, in the evidence file, which existing tests need editing and why.** Expected: **none.**
   Name each file and the reason it is unaffected: `test/header_standardization_test.dart` (pumps
   Stats with `showPrimerHelp` omitted; F-10), `test/records_and_trends_screen_test.dart` (S-913 keys
   off `find.byTooltip('Records & Trends')`; F-9), `test/stats_legacy_removal_test.dart`,
   `test/screen_widget_test.dart`, `test/fuel_row_screen_test.dart` (S-1107),
   `test/screen_overflow_contract_test.dart`, `test/nutrition_trend_screen_test.dart`,
   `test/mix_layer_screen_test.dart`, `test/signals_layer_screen_test.dart`, and the remaining
   `StatsScreen`-pumping files (F-7, F-8). If any file **does** need an edit, stop and log it as an
   Assumption Log entry naming the file and the assertion.
7. [ ] **Red run first:** run
   `.github/copilot/scripts/macos/gateway.sh test test/stats_primer_screen_test.dart` before step 1
   exists and record the compile failure; then after steps 1–4 and record the green line.
8. [ ] Mutation pair A (inverse edit on an existing file): in `lib/features/stats/stats_screen.dart`,
   change the `showPrimerHelp` constructor default from `false` to `true` → the S-2703 case
   (`showPrimerHelp` omitted) must go red. Restore and re-run. (The "reopen never marks" half of
   S-2704 / S-2707 cannot go red here because the screen holds no state; it is held by the structural
   guard in Phase 3A, and its cross-phase mutation is 2B step 8.)

**Done Criteria** (run until green):
`.github/copilot/scripts/macos/gateway.sh test test/stats_primer_screen_test.dart test/stats_primer_state_test.dart`;
`.github/copilot/scripts/macos/gateway.sh test` (full suite, count recorded);
`.github/copilot/scripts/macos/gateway.sh lint`.
**Predicted Files:** `lib/features/stats/widgets/stats_primer_sheet.dart` (new),
`lib/features/stats/stats_screen.dart` (edit), `test/stats_primer_screen_test.dart` (new). Nothing
else — in particular `lib/features/stats/records_and_trends_screen.dart` and `docs/signals.md` are
untouched.

### Phase 2B: HomeScreen hosting, DI threading and the Home test (@developer)

1. [ ] In `lib/features/home/home_screen.dart`: add the `StatsPrimerState` / `StatsPrimerSheet`
   imports and `final StatsPrimerState? statsPrimerState;` with an **optional, nullable** constructor
   parameter (D-2020). Add `_openStatsScreen()` and `_showStatsPrimer()` mirroring
   `_openNutritionScreen` / `_showNutritionPrimer` (D-2021): if
   `widget.statsPrimerState?.shouldShowPrimer == true`, `await _showStatsPrimer()`, then
   `if (!mounted) return;`, then push
   `StatsScreen(workoutState: …, settingsState: …, showPrimerHelp: widget.statsPrimerState != null)`
   through `OmniNavigator`. `_showStatsPrimer()` is
   `await showModalBottomSheet<void>(...)` building `const StatsPrimerSheet()` (no `onDismiss`),
   followed by `unawaited(widget.statsPrimerState!.markSeen())` — so a close of any kind marks seen
   (D-2022).
2. [ ] In the same file, point the `'Stats'` `_MaintenanceItem`'s `onTap` at `_openStatsScreen` (the
   `StatsScreen(...)` construction moves into `_openStatsScreen`). The tile's `title` stays `'Stats'`.
3. [ ] Thread the state (D-2020): `lib/main.dart` — construct `StatsPrimerState(repository)` next to
   `NutritionPrimerState` and `await statsPrimerState.init();`, then pass it to `MyApp`;
   `lib/app.dart` — add the optional nullable field, the constructor parameter and the argument to
   **both** `OnboardingScreen` and `HomeScreen`; `lib/features/onboarding/onboarding_screen.dart` —
   add the optional nullable field and forward it to `HomeScreen`. Do **not** touch
   `lib/features/splash/omni_splash_screen.dart` and do **not** add the state to `StatsScreen`.
4. [ ] Create `test/helpers/test_stats_primer_state.dart` mirroring
   `test/helpers/test_nutrition_primer_state.dart`: `Future<StatsPrimerState>
   buildStatsPrimerState(WorkoutRepository repo)` (construct + `await init()`).
5. [ ] Create `test/stats_primer_home_test.dart` reusing the `HomeScreen` harness pattern of
   `test/nutrition_primer_test.dart` (open the hub by tapping the logo `Image`, then tap the
   `MaintenanceTile` whose `title` is `'Stats'`; F-19) with exactly these groups and test names:
   - `S-2701: the first Stats tap from Home shows the primer once` ›
     `an unseen state shows the sheet on the first tap and marks it seen when the sheet closes`
   - `S-2716: a second Stats tap pushes Stats directly` ›
     `a seen state pushes Stats with no sheet`
   - `S-2717: a Home with no state pushes Stats directly and Stats has no "?"` ›
     `a null state pushes Stats with showPrimerHelp false`
   - `S-2718: dismissing the auto-shown sheet by an outside tap still marks it seen` ›
     `the flag is false while the sheet shows and true after an outside tap`
6. [ ] **Red run first:** run
   `.github/copilot/scripts/macos/gateway.sh test test/stats_primer_home_test.dart` before steps 1–4
   exist and record the compile failure; then after them and record the green line.
7. [ ] Mutation pair A (inverse edit on an existing file): in `_openStatsScreen`, delete the
   `shouldShowPrimer` condition so the sheet shows on every tap → the S-2716 case must go red (seed:
   a Mock repository with `primer_seen_stats` already `true`). Restore and re-run.
8. [ ] Mutation pair B (inverse edit on an existing file): delete the
   `unawaited(widget.statsPrimerState!.markSeen());` line after the awaited sheet in
   `_showStatsPrimer()` → the S-2718 and S-2701 cases must go red (the flag never becomes `true`).
   Restore and re-run.

**Done Criteria** (run until green):
`.github/copilot/scripts/macos/gateway.sh test test/stats_primer_home_test.dart test/stats_primer_screen_test.dart test/stats_primer_state_test.dart test/nutrition_primer_test.dart test/header_standardization_test.dart test/records_and_trends_screen_test.dart`;
`.github/copilot/scripts/macos/gateway.sh test` (full suite, count recorded);
`.github/copilot/scripts/macos/gateway.sh lint`.
**Predicted Files:** `lib/features/home/home_screen.dart` (edit), `lib/main.dart` (edit),
`lib/app.dart` (edit), `lib/features/onboarding/onboarding_screen.dart` (edit),
`test/helpers/test_stats_primer_state.dart` (new), `test/stats_primer_home_test.dart` (new). Nothing
else.

### Phase 3A: structural guards and residue sweep (@developer)

1. [ ] Create `test/stats_primer_contract_test.dart` with exactly four static-source guards, all
   mapping to S-2715:
   - `the Stats primer key is written in exactly one file` — scan every `.dart` under `lib/` for
     `primer_seen_stats`, expect exactly `['lib/state/stats/stats_primer_state.dart']`.
   - `the Home screen's primer state stays optional and nullable` — assert
     `lib/features/home/home_screen.dart` contains `StatsPrimerState? statsPrimerState`.
   - `the Stats screen holds no StatsPrimerState` — assert `lib/features/stats/stats_screen.dart`
     contains `bool showPrimerHelp` and does **not** contain `StatsPrimerState`.
   - `no unfinished-feature wording reaches the Stats feature` — scan every `.dart` under
     `lib/features/stats/` and `lib/state/stats/` for the D-2011 banned strings, expect none.
2. [ ] Mutation pair A (inverse edit on an existing file): drop the `?` from
   `StatsPrimerState? statsPrimerState` in `lib/features/home/home_screen.dart` → the
   `stays optional and nullable` guard must go red. Restore and re-run.
3. [ ] Mutation pair B (inverse edit on an existing file): add a temporary
   `final StatsPrimerState? statsPrimerState;` field (and import) to
   `lib/features/stats/stats_screen.dart` → the `the Stats screen holds no StatsPrimerState` guard
   must go red. Restore and re-run.
4. [ ] Residue sweep — record the raw output of each in the evidence file:
   (a) `primer_seen_stats` appears in no file other than `lib/state/stats/stats_primer_state.dart`;
   (b) `StatsPrimerSheet(` is constructed only in `lib/features/stats/stats_screen.dart` and
   `lib/features/home/home_screen.dart`;
   (c) `lib/features/stats/records_and_trends_screen.dart` still contains
   `Complete your first session to see stats here.` exactly once and is otherwise unmodified;
   (d) no `TODO`, `UnimplementedError` or placeholder text in either new file;
   (e) no new colour literal, `Color(0x` or token value in either new file;
   (f) no reference to `_primerAutoShown`, `AnimationStatusListener` or a post-frame auto-open remains
   in `lib/features/stats/`.

**Done Criteria** (run until green):
`.github/copilot/scripts/macos/gateway.sh test test/stats_primer_contract_test.dart test/stats_primer_screen_test.dart test/stats_primer_home_test.dart test/stats_primer_state_test.dart`;
`.github/copilot/scripts/macos/gateway.sh test` (full suite, count recorded);
`.github/copilot/scripts/macos/gateway.sh lint`.
**Predicted Files:** `test/stats_primer_contract_test.dart` (new). Nothing else.

### Phase 3B: docs (@developer)

1. [ ] `docs/stats_screen.md`: in the navigation/entry-point section, document the two header actions
   (the "?" with tooltip `About Stats` first, the chart icon last and still the only way into
   Records & Trends); add a `## First-Use Empty State` section describing the kept title and body, the
   three new lines and the `How Stats works` button; add a `## Primer Sheet` section describing the
   three blocks, the **HomeScreen-hosted** once-per-install auto-open on the first Stats tap (the
   Nutrition pattern: sheet over Home, seen marked when the sheet closes by any means, then Stats
   pushed), the
   `primer_seen_stats` flag and the reopen-without-marking rule; add both new files to the core-files
   table and a pointer under Related Documentation to the widget-catalog note from step 2. Every
   behaviour sentence names one of the Phase 1 / 2 test names above.
2. [ ] `docs/widget_catalog.md`: add a `Note on the Stats screen's primer sheet` in the same
   feature-scoped form as the existing Mix / Signals / Fuel notes — `StatsPrimerSheet` is
   presentation only, its host owns the seen flag, keys `stats_primer_block_page` /
   `stats_primer_block_signals` / `stats_primer_block_records` / `stats_primer_dismiss`, and the
   explicit-`shape` rule. Do **not** add a lookup-table row.
3. [ ] `docs/state_management.md`: add the row `StatsPrimerState` → Stats screen to the class → page
   lookup table. Do not create a new state page.
4. [ ] `docs/navigation_and_screens.md`: extend the injection graph with `StatsPrimerState(repository)`
   → `MyApp` → `HomeScreen` / `OnboardingScreen` → `HomeScreen`, state that the parameter is
   optional-nullable so only `lib/main.dart` passes it, and that `StatsScreen` receives only
   `showPrimerHelp`. Add the Stats primer to the same paragraph that describes the Nutrition primer.
5. [ ] `docs/README.md`: add the `lib/state/stats/` line to the `state/` block of the source tree,
   matching the `nutrition/` line's form, and add `StatsPrimerSheet` to the `features/stats/` tree
   comment. Do not change the Stats row of the docs index.
6. [ ] Run the docs guards and the full suite:
   `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`
   (plus any other `test/docs_*_test.dart` file the gateway `list` shows), then the full
   `.github/copilot/scripts/macos/gateway.sh test` and record the exact `+N ~M:` line against the
   re-measured baseline, then `.github/copilot/scripts/macos/gateway.sh lint`, then
   `gateway.sh git-status` and `git-diff` to confirm the diff is exactly the Predicted Files.

**Done Criteria** (run until green): the docs guard in step 6; the full suite (count recorded);
`gateway.sh lint`.
**Predicted Files:** `docs/stats_screen.md` (edit), `docs/widget_catalog.md` (edit),
`docs/state_management.md` (edit), `docs/navigation_and_screens.md` (edit), `docs/README.md` (edit).
Nothing else — in particular `docs/signals.md` is untouched.

## Governor actions

- Run the `pr-scope-guard` skill **now** (plan written), **after each run**, and **after the code
  review**. The governor measures; the planner and the executors do not.
- This plan is written to a hard budget of one PR: one track (phone app), 5 runs (Phase 1, 2A, 2B,
  3A, 3B), 22 decisions (5 of them superseded, so 17 live), 14 live scenarios
  (S-2702 / S-2709 / S-2712 / S-2713 dropped), and a production surface of two new `lib/` files plus
  five small edits. If the governor reports over budget, the split is by phase boundary and this plan
  stays the plan for the later half:
  - **Split A** — Phase 1 alone (a state class with no caller is inert), then 2A + 2B + 3A + 3B.
  - **Split B** — Phase 1 + 2A (both are inert: `showPrimerHelp` defaults to `false` and nothing
    passes `true` yet, so the feature is off in the app), then 2B + 3A + 3B.
- Never grow this plan to absorb review feedback. Take it to a stopping point where every item is done
  or not started and the suites are green, then plan the remainder as a separate PR with conductor-v2.
- Evidence goes in `2026-10-04-10b-stats-pr10b-primer-sheet-plan.evidence.md`; review findings go in
  `2026-10-04-10b-stats-pr10b-primer-sheet-plan.review.md`. Neither goes in this plan.

## Files Affected (whole feature)

| File | Kind | Phase |
|---|---|---|
| `lib/state/stats/stats_primer_state.dart` | new | 1 |
| `test/stats_primer_state_test.dart` | new | 1 |
| `lib/features/stats/widgets/stats_primer_sheet.dart` | new | 2A |
| `lib/features/stats/stats_screen.dart` | edit | 2A |
| `test/stats_primer_screen_test.dart` | new | 2A |
| `lib/features/home/home_screen.dart` | edit | 2B |
| `lib/main.dart` | edit | 2B |
| `lib/app.dart` | edit | 2B |
| `lib/features/onboarding/onboarding_screen.dart` | edit | 2B |
| `test/helpers/test_stats_primer_state.dart` | new | 2B |
| `test/stats_primer_home_test.dart` | new | 2B |
| `test/stats_primer_contract_test.dart` | new | 3A |
| `docs/stats_screen.md` | edit | 3B |
| `docs/widget_catalog.md` | edit | 3B |
| `docs/state_management.md` | edit | 3B |
| `docs/navigation_and_screens.md` | edit | 3B |
| `docs/README.md` | edit | 3B |

**Files to delete:** none.

Explicitly **not** touched: `lib/features/nutrition/**`, `lib/state/nutrition/**`,
`test/nutrition_primer_test.dart`, `test/helpers/test_nutrition_primer_state.dart`,
`lib/features/stats/records_and_trends_screen.dart`, `lib/features/splash/omni_splash_screen.dart`,
`docs/signals.md`, the 18 `StatsScreen`-pumping test files and the 9 `HomeScreen`-constructing test
files.

## Notes

- **No useful split inside 2B.** The DI threading and the Home tap handler ship together, or the flag
  never reaches the sheet.
- **Intermediate states.** After Phase 1 the new state is inert: nothing constructs it. After 2A the
  sheet and the flag exist but the feature is **off in the app** — `showPrimerHelp` defaults to
  `false` and no caller passes `true` yet — so the only suite effect is the new files themselves.
  After 2B the feature is live but undocumented; docs catch up in 3B with no behaviour change.
- **The empty card grows by three lines and a button.** The overflow assertion (S-2714) exists because
  `test/screen_overflow_contract_test.dart` only builds the seeded, non-empty screen (F-13).

## Progress

| Item | Status | Evidence |
|---|---|---|
| Plan written | **Complete** | this file |
| Phase 1 — `StatsPrimerState` + tests (@dba) | **Complete** | `.evidence.md` §2 → red compile failure, `+6` green (S-2705/2706 on Mock+Hive, S-2710, S-2711), mutations A/B red→restore→green, lint `196 issues`, full suite `+3858 ~1` |
| Phase 2A — sheet + `showPrimerHelp` + "?" + first-use card (@developer) | not started | `.evidence.md` → red run, the seven screen cases, mutation A, the unaffected-files table, lint line |
| Phase 2B — HomeScreen hosting + DI + home test (@developer) | not started | `.evidence.md` → red run, the four home cases, mutations A/B, lint line |
| Phase 3A — guards + residue sweep (@developer) | not started | `.evidence.md` → the four guards, the two mutations, the six-point residue sweep, lint line |
| Phase 3B — docs (@developer) | not started | `.evidence.md` → docs-guard line, full-suite line, lint line |

## Assumption Log

_Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED (promoted to a D-x) or REVERT (remediation)._

- **A-1 (planner) —** The brief says the plan folder exists; it exists and is empty. The plan and the
  evidence stub are created in it; nothing else there is touched.
- **A-2 (planner) —** Scenario ids start at S-2701, continuing the 10a block (S-1801…S-2511) with a
  gap. No id is reused and none is renumbered by later phases.
- **A-3 (planner) —** The screen tests go in a new `test/stats_primer_screen_test.dart` rather than
  appended to `test/nutrition_primer_test.dart` or `test/header_standardization_test.dart`: the feature
  is the Stats screen's, the file is then reviewable in isolation, and no existing file has to be
  re-read by a reviewer diffing against Predicted Files.
- **A-4 (planner) —** `StatsPrimerState` is documented in `docs/stats_screen.md` plus one lookup row
  in `docs/state_management.md`, rather than in a new `docs/state_management/stats_state.md` page:
  one class does not justify a page, and the lookup table is already the index of record.
- **A-5 (planner) —** The brief moves the auto-open to `HomeScreen` but does not say what `StatsScreen`
  should receive. Chosen: one optional `bool showPrimerHelp` defaulting to `false` (D-2019), so the
  screen never holds the state and the 18 existing `StatsScreen` test files stay untouched. The
  alternative — passing `StatsPrimerState?` to the screen and reading `shouldShowPrimer` there — would
  put the state back in the screen and re-open the "reopen marks seen" hole. Vetoable.
- **A-6 (planner) —** The brief does not say whether the sheet should appear over Home (Nutrition's
  behaviour) or over an already-pushed Stats screen. Chosen: over Home, because the brief says to copy
  the Nutrition pattern and that is what it does (F-17). Recorded as O-7 for the owner.
- **A-7 (planner) —** The brief does not say whether the Home test needs its own helper. Chosen: yes —
  `test/helpers/test_stats_primer_state.dart` mirroring the Nutrition helper, so the Home test and any
  later test build the state the same way. Vetoable.
- **A-8 (planner) —** The brief says the seen flag must be marked when the sheet closes by any means,
  but the shipped Nutrition sheet only marks from its `Got it` button. Chosen: the Home host awaits the
  `showModalBottomSheet` future and marks seen after it completes, with every host passing
  `onDismiss: null` (D-2022), rather than copying Nutrition's callback. This is the one deliberate
  behavioural divergence, and it is what makes a barrier tap or a swipe-away count. Vetoable.
- **A-9 (Phase 1 executor) —** `lib/state/stats/` did not exist, and the gateway's fixed menu has no
  way to create a directory (`mkdir` is refused; the `create` tool needs the parent to exist). Options
  considered: (a) put the class at `lib/state/stats_primer_state.dart` — rejected, D-2003 pins the
  path and the Phase 3A guard asserts it; (b) leave the phase blocked — rejected, the work is
  otherwise complete. Chosen: a throwaway `test/zz_mkdir_stats.dart` probe run through the allowed
  `gateway.sh test`, which created the directory, then removed with `gateway.sh delete-scratch`. No
  scratch file remains and no tracked file was touched.
- **A-10 (Phase 1 executor) —** S-2705 and S-2706 must run on Mock and Hive (the evidence table fills
  both columns), so the file iterates `harnessFactories` and the group name is prefixed `Mock — ` /
  `Hive — `, the convention in `test/entry_identity_test.dart` and
  `test/protein_consistency_service_test.dart`. The pinned scenario name and test name are kept
  verbatim after the prefix; the alternatives (duplicate identical group names, or Mock-only) were
  rejected as either confusing or non-conforming to the evidence table. Vetoable.

## Feedback

[empty — the Conductor folds non-empty entries into the plan and clears this one]

## Open questions

| # | Item | Owner | Status |
|---|---|---|---|
| O-1 | The existing empty-state body line `Complete your first session to see stats here.` is **kept** verbatim under the new three lines, because eight existing assertions match that exact string (F-7) and keeping it is the smaller change. If the owner prefers it replaced by the new lines, every one of those eight assertions must be updated in the same PR — name them and the change becomes a Phase 2 sub-item | Owner | Defaulted — owner may confirm |
| O-2 | Every string in "Pinned copy" is the planner's draft: the sheet's eyebrow/title/three blocks and the card's three new lines and `How Stats works` label. The wording is the owner's to change; the keys and structure are not | Owner | Defaulted — owner may confirm |
| O-3 | `StatsPrimerState` is documented in `docs/stats_screen.md` with one lookup row in `docs/state_management.md` (A-4). A dedicated `docs/state_management/stats_state.md` page is the alternative if the owner expects one page per feature-scoped state | Owner | Defaulted — owner may confirm |
| O-4 | The `How Stats works` button renders **only** when `showPrimerHelp` is true (D-2019), which is what keeps the 18 existing `StatsScreen` test files untouched. The alternative — always rendering it and updating those files — is more faithful to "every user sees it" but costs edits across the 18 files and their assertions | Owner | Defaulted — owner may confirm |
| O-5 | The "?" uses `OmniTheme.colors.textDominant` to match the sibling chart icon in the same header, rather than the Nutrition header's `colorScheme.primary` (D-2009). Visual, not structural | Owner | Defaulted — owner may confirm |
| O-6 | The auto-open fires on the first Stats tap from Home **whether or not** the user has sessions, so someone who trains first and opens Stats later still gets the orientation. The alternative — empty screens only — would leave the Signals and chart-icon explanations unshown to exactly the users who need them | Owner | Defaulted — owner may confirm |
| O-7 | The sheet appears **over Home**, and Stats is pushed when the user dismisses it — the shipped Nutrition behaviour (F-17) — rather than appearing on top of an already-pushed Stats screen. The user-visible difference is that the first Stats tap lands on Home with a sheet, then on Stats; the alternative is one place to change (the tap handler in `home_screen.dart`), but it reintroduces route-settle timing work | Owner | Defaulted — owner may confirm |
| O-8 | Closing the auto-shown sheet **any** way — the `Got it` CTA, a swipe-down, or a tap outside on the barrier — counts as seen, and the sheet will not open by itself again (D-2022). This is the one place Stats deliberately differs from the shipped Nutrition primer, whose `onDismiss` fires only from its `Got it` button, so a Nutrition swipe-away shows it again next time. If the owner wants the two primers to behave identically, the alternative is to mark seen only from `Got it` and accept that a swipe-away re-shows it | Owner | Defaulted — owner may confirm |
