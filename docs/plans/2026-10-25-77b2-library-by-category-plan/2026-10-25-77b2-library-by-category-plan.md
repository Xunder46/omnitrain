# Feature: 77b2 — Library grouped by category

> Status: seeded by the lead 2026-10-25 (owner away). One track: phone app. Follows 77b (`1d055fb8`). Series: `docs/plans/2026-10-25-77-nutrition-setup-path-series.md`.
> Base: `1d055fb8` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Baseline: `flutter analyze` 180 issues, 0 errors.

## Overview

| What you do | Now | After 77b2 |
|---|---|---|
| Open the Library tab | One flat alphabetical wall of ~170 foods | Foods under category headings (Dairy, Fruits, Proteins, …), headings alphabetical, "Uncategorized" last, foods alphabetical inside each |
| Search in Library | Flat filtered list | Unchanged: while text is typed the list is flat (no headings) |

## Decision Ledger

- **D-1** Grouping reuses the phone's own rule `foodsIEatSections({foods, groups})` (`lib/core/utils/foods_i_eat_order.dart`), the same function Foods I Eat uses: active categories alphabetically, foods missing from the active set under "Uncategorized" last. No new ordering logic.
- **D-2** Only when the search box is empty. A non-empty query shows the flat list exactly as today (assumption A-1).
- **D-3** A row sits under its CATALOG food's category (the shipped or created category), even when the user changed the category on their own copy (assumption A-2).
- **D-4** (revised by the lead after the first build) The Library tab does NOT load categories itself: a reload with the default flags replaced the cache that `NutritionScreen` loads (`includeArchived: true`) and broke 12 Categories-tab tests. It reads the already-loaded `activeFoodGroups` (the manage screen is only reached from the nutrition page, which loads them). With nothing loaded every food falls under Uncategorized.
- **D-5** The heading is a private `_LibrarySectionHeader` (key `library_section_<title>`): `titleSmall`, `FontWeight.w600`, `OmniTheme.titleLetterSpacing`, `OmniTheme.colors.textDominant`, padding left/right 16, top 16, bottom 4. No divider next to a heading.

## Scenarios (ids `S-1282x`; grep: unused)

`test/library_grouping_test.dart` (new, Mock):
- **S-12820** With the real catalog and an empty search, the heading keys built at the top of the list are in alphabetical order of the active category names that have foods, and each heading is above its foods (`getTopLeft().dy`).
- **S-12821** Typing a query removes every `library_section_*` heading (flat list); clearing it brings them back.
- **S-12822** A created food with `groupId: null` and a legacy custom sit under `library_section_Uncategorized`, which is the last heading (scroll to it with `scrollUntilVisible`).
- **S-12823** A food whose category was archived lands under Uncategorized (archive a category that holds a created food, reload).
- **S-12824** Source guard: `add_food_screen.dart` contains `foodsIEatSections(` with `groups: state.activeFoodGroups`, and does NOT call `loadFoodGroups(`.

## Phases

- **P1** `crew-builder-app`: exact code in `lib/features/nutrition/add_food_screen.dart` (lead gives it).
- **P2** `crew-builder-app`: `test/library_grouping_test.dart`, and fix any existing test the headings break (run the ten related nutrition files).
- Then docs (lead), mutation pass, `crew-reviewer`, commit.

## Owner device check
- (owner) ODC-1 Manage Food Library: the list has category headings; typing in Search flattens it.

## Assumption Log
- **A-1** (lead, owner may overrule) Headings only while the search box is empty.
- **A-2** (lead, owner may overrule) A row stays under its catalog category even if the user re-categorised their copy.
