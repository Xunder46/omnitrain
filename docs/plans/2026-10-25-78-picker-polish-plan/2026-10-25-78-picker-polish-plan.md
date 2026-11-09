# Feature: 78 — picker polish: first-screen order, "4 foods in your list", honest copy, tab keeps its place, typing an amount logs

> Status: seeded by the lead 2026-10-25 from the owner's follow-up list ("What I would still fix"). One track: phone app. Follows series 77 (`f0404f47`). NOT committed: the owner's commit green light covered series 77 only.
> Base: `f0404f47` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Baseline: `flutter analyze` 180 issues, 0 errors.

## Overview

| What you see | Now | After 78 |
|---|---|---|
| First category in the Library picker | Alphabetical: Condiments first, Proteins seventh | Fixed order: Proteins, Dairy, Grains & Starches, Fruits, Vegetables, Nuts Seeds & Fats, Snacks & Prepared, Drinks, Condiments; your own categories after; Uncategorized last. Foods I Eat and the wrist keep their alphabetical order |
| Library has no finish line | nothing says how many foods are in your list | a line under Search: "4 foods in your list" ("1 food…", "No foods in your list yet") |
| Library button | "+ Create new food" | "+ New Food" |
| Remove prompt | "Remove X from your library?" | "Remove X from Foods I Eat?" |
| Primer | "edit control", "check off" | "Choose foods or the pencil", "tap a food's picture to log it" |
| Empty ring with no foods in the list | "Log a food to start filling" | "Pick your foods to get started" (the old text returns once the list has a food) |
| Switch Library ↔ Categories | Library scrolls back to the top, search clears | Library keeps its place and search |
| Type an amount on an unlogged food, press Done | nothing | the food is logged with that amount (only if you changed the number) |

## Decision Ledger
- **D-1** Library heading order is a Library-only wrapper over `foodsIEatSections` (`add_food_screen.dart`): sections in the order of `_libraryHeadingOrder`; titles not in the list keep their relative (alphabetical) order after the listed ones; `Uncategorized` last. `foodsIEatSections` itself is NOT changed (Foods I Eat and the wrist share it, proven equal by `test/watch_nutrition_quick_log_test.dart` S-003).
- **D-2** Count line: key `library_count_line`, `bodySmall`, `textSecondary`, under the search field; counts non-archived library foods (`state.foods`).
- **D-3** Library CTA label `+ New Food` (key `new_food_button` unchanged).
- **D-4** Remove prompt title `Remove <name> from Foods I Eat?`.
- **D-5** Primer text per the Overview; labels `YOUR LIST, BUILT ONCE` and `TODAY AND OVER TIME` unchanged, `CHECK TO LOG, SET THE AMOUNT` → `TAP TO LOG, SET THE AMOUNT`.
- **D-6** `CalorieRingCard` gets optional `String? emptyHint` passed to `CalorieRing(emptyHint: ...)` (`CalorieRing.defaultEmptyHint` constant = `Log a food to start filling`); `NutritionScreen` passes `Pick your foods to get started` while the library is loaded and empty.
- **D-7** `_FromCatalogTabState` keeps itself alive (`AutomaticKeepAliveClientMixin`), so scroll and search survive a tab switch.
- **D-8** `LogFoodRow._recommitIfLogged` also logs an UNLOGGED food on submit/editing-complete when the typed text differs from the text the row showed when built and is valid (> 0). Unchanged text on an unlogged food logs nothing (no accidental logs).

## Scenarios (ids `S-1311x`; grep: unused) — `test/picker_polish_test.dart` (new, Mock)
- **S-13110** Real catalog, empty search: built headings start `Proteins`, `Dairy`, `Grains & Starches`, `Fruits` in that order; a created category named `Aaa 78` appears after all listed ones and before `Uncategorized`.
- **S-13111** `foodsIEatSections` still alphabetical (Foods I Eat unchanged): first section title is the alphabetically first active category.
- **S-13112** Count line: `No foods in your list yet` on an empty library; `1 food in your list` after one add; `3 foods in your list` after three; follows a removal.
- **S-13113** CTA text `+ New Food`; `+ Create new food` absent.
- **S-13114** Remove prompt reads `Remove <name> from Foods I Eat?`.
- **S-13115** Ring hint: empty library → `Pick your foods to get started` and not `Log a food to start filling`; with one food in the list → `Log a food to start filling`.
- **S-13116** Primer text: contains `Choose foods` and `TAP TO LOG, SET THE AMOUNT`; no `edit control`, no `check off`.
- **S-13117** Library keeps its place: scroll the list, switch to Categories and back: a heading far down is still built / the first built heading is not the first one; the search text survives.
- **S-13118** Typing: an unlogged row, `enterText` 250 then `testTextInput.receiveAction(TextInputAction.done)` → logged with amount 250; an unlogged row where the text is untouched and Done is pressed → not logged; an unlogged row typed to the same value as shown → not logged; typed 0 → not logged, error shown.

## The watch (owner asked: make sure the watch app gets the necessary changes)
Audited every change in series 77 and plan 78 against the watch:
- **Needs a change, done:** the wrist's empty food list said "No foods yet. Sync with your phone to get them." The phone now offers a Choose foods button, and a user with no foods cannot "sync" anything. Both wrist implementations now say "No foods yet. On your phone, open Nutrition and tap Choose foods." (`watch/watchos/Sources/WatchSessionEngine/WatchNutritionView.swift`, `lib/watch/nutrition/watch_nutrition_screen.dart`); guards S-13120 (Swift source guard, mutation-checked) and S-13121 (Dart); the old S-006 Dart test is re-pointed. `swift test` whole engine target 1023 tests, 0 failures; watch app target built with xcodebuild (BUILD SUCCEEDED).
- **No change needed, by design:** the wrist's food order stays alphabetical like Foods I Eat (the fixed Proteins-first order is Library-only; `foodsIEatSections` and the wrist-parity test are untouched); the wrist's food list is built from the user's library copies, so an edited copy (77a) reaches the wrist with the user's values on the next sync and a removed or deleted food disappears from it on the next sync; the primer, home card, sodium chip, ring hint, Library tabs, count line and amount-typing are phone-only.
- **Known gap, not changed (pre-existing):** when the user removes EVERY food, the phone sends no `foods_down` (`_foodsFrame` returns null for an empty library, to avoid wiping the wrist before the library has loaded), so the wrist keeps showing its last list until it gets a new one. Fixing it needs a protocol decision (an explicit empty list) and is not done here.
- **Not seen on the watch:** (owner) ODC-W1 Fresh install with no foods: the watch's Food screen reads the new line.

## Phases (serial): P1 `crew-builder-app` exact code (5 lib files); P2 `crew-builder-app` tests + the tests the changes move; lead: docs, mutation pass, review. Not committed (see Status).

## Assumption Log
- **A-1** (lead, owner may overrule) Fixed order is the owner's list; "most logged first" not built.
- **A-2** (lead) The finish line is the count line only; no extra Done button (the bottom button is New Food).
- **A-3** (lead, owner may overrule) Typing logs only on Done/submit and only when the number was changed.
