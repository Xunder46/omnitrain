# Feature: 91 — one header "+": it always means "new item here", and it always looks the same

> Status: Iteration 1 active. Owner decisions 2026-10-29 are binding (D-91.1..D-91.8). Q1–Q4 answered by the owner 2026-10-29: all defaults (A-1).
> Next handoff: @code-reviewer (review fixes 1–6)
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md` ("Shared pieces and rules per job", "Buttons", "How these rules are enforced"), `docs/documentation_standard.md`, `.github/copilot/pr-scope-budget.md`
> Track: phone app only (`lib/`). Base: `d6ef72ab` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Hands off: `docs/plans/2026-10-28-89-fitness-workouts-follow-the-session-plan/`, and the uncommitted `docs/session_summary.md`, `lib/features/session/session_summary_screen.dart` (another unit owns them). The new contract scan reads the summary screen but must need no edit to it (it has no header "+").

## Overview

| What the user sees | Now | After 91 |
|---|---|---|
| Exercise Library header | a "+" that opens New Exercise | the same "+", now the one shared header "+": same size, colour, press shrink, and "New Exercise" read aloud |
| Manage Food Library | a wide "+ New Food" button at the bottom (Library tab) / "+ New Category" (Categories tab) | no bottom button; the header has the shared "+": "New Food" on Library, "New Category" on Categories; the list's end no longer reserves space for the old button |
| Calendar header | an outlined "+" that does not add anything: it opens the Training periods list | a calendar-span icon (no "+", no outline), read aloud as "Training periods"; same destination |
| Day list, Periodization list, My Routines | bottom "+ New …" button | unchanged (adding is those screens' main job) |
| A future screen | could add any "+" anywhere in a header | a test fails if a header builds its own "+" instead of the shared one |

## Resolved Decisions (Ledger)

- **D-91.1** A header "+" means exactly one thing: create a new item for the list on this screen. Every header "+" is `OmniHeaderAddButton`; no header builds a raw `Icons.add` or a "+"-text button. A header action that goes somewhere else uses an icon that reads as that place, never a "+". (Owner.)
- **D-91.2** Piece contract. Class `OmniHeaderAddButton`, file `lib/widgets/buttons/omni_header_add_button.dart` (the concept name is pinned: the docs contract and the scan name it). Required `String label`: used verbatim as the `IconButton` tooltip and as a wrapping `Semantics(label: label, button: true)`. Required `VoidCallback onPressed`. Optional `Key? buttonKey`, placed on the inner `IconButton` itself (so the existing `tester.widget<IconButton>(find.byKey(...))` in `test/pr8_exercise_library_test.dart` keeps working). Icon `Icons.add` at the `IconButton` default size, with no size or padding override, so every instance is the same size whatever its label. Colour `OmniTheme.colors.textDominant` (the back arrow's colour and today's Exercise Library "+"; Q1). No visible text.
- **D-91.3** Press feedback. While a pointer is down on the piece it scales to `OmniTheme.pressedScale` through `AnimatedScale` with `OmniTheme.animationDuration` and `OmniTheme.animationCurve`; it returns to 1.0 on pointer up and on cancel (finger dragged off). With `MediaQuery.disableAnimations` true the scale applies instantly without animation (same rule as `HomeLogoButton`, `lib/widgets/common/home_logo_button.dart:179-189`). The press shrink never delays or blocks `onPressed`.
- **D-91.4** Labels and keys. Exercise Library: label `New Exercise`, key `exercise_library_new_button`. Manage Food Library, Library tab: label `New Food`, key `new_food_button`. Categories tab: label `New Category`, key `new_group_button`. The Food Library label/key follows `_tabController.index`, the same index the old bottom button followed (`add_food_screen.dart:159-180`). Exactly one header "+" is on screen at any moment (never zero, never two).
- **D-91.5** Food Library actions are unchanged. `New Food` pushes the New Food form through `OmniNavigator.push` (`_openNewFoodForm`). `New Category` calls `_createGroup` (immediately creates a category named `New Category`, tracks and focuses it, shows `Could not create category` on failure). A second tap on `New Category` creates a second category with the same name, as the old button did.
- **D-91.6** Food Library bottom. `Scaffold.bottomNavigationBar` is gone (null) on both tabs; `_buildBottomCTA` is deleted. The two tab lists (`_FromCatalogTab` `ListView.separated` at `add_food_screen.dart:671-678`, `_GroupsTab` `ListView` at `:1736-1744`) replace the bottom padding `OmniTheme.formBottomCTAClearance` with `16 + MediaQuery.viewPaddingOf(context).bottom`, so the last row clears the home indicator with no empty band left for a button that no longer exists. The header "+" shows in every list state: catalog loading, empty catalog, a search with no match, zero categories.
- **D-91.7** Calendar header. One `IconButton` with `Icons.date_range`, tooltip `Training periods`, wrapped in `Semantics(label: 'Training periods', button: true)`, colour `OmniTheme.colors.textDominant` (as Stats' `Records & Trends` header icon, `lib/features/stats/stats_screen.dart:271-285`; Q2), key `calendar_training_periods_button`. No outline, no visible text, no extra right inset. Tap = the existing `_openPeriods` (pushes the Periodization list, refreshes the calendar on return). The words `Periods` / `+` never appear as visible text in the calendar header. (Owner.)
- **D-91.8** Bottom buttons stay where adding is the screen's main job: day session list `+ New Planned Session` (owner). Derived (Q4, vetoable): Periodization `+ New Period` and My Routines `+ New Routine` also stay, labels unchanged (Q3).
- **D-91.9** Contract scan (the structural guard). In every `.dart` file under `lib/` (`dartSourcesUnder(uiStandardRoots)`; `lib/watch/` is excluded by that helper), for every `constructorCalls` hit named `OmniBackHeader`, `AppBar` or `SliverAppBar`: it is a finding when (a) the call's `code` (literals and comments blanked) matches `\bIcons\.add(?:_circle|_box)?(?:_outline)?(?:_outlined|_rounded|_sharp)?\b`, or (b) a string literal in the call (comments ignored) has content exactly `+` or starting with `+ `. One finding per offending header call, reported as `<path>:<line of the call's "("> <Name> builds a raw "+" (use OmniHeaderAddButton)`. No allowlist list exists for this rule and none may be added. Known limit, stated in the design doc: actions assembled in a variable or method outside the header call's text are not seen.
- **D-91.10** Supersedes plan 78 D-3 (`docs/plans/2026-10-25-78-picker-polish-plan`, "Library CTA label `+ New Food`"): the Library's create action is the header "+" labelled `New Food`; no visible `+ New Food` text remains. Plan 78's S-13113 is amended by S-9165a below.
- **D-91.11** Out of scope: the profile measurement "+" (card body, `profile_screen.dart:513`), the exercise picker's empty-state button, session screens' Add Exercise and per-block "+", routine editor block "+", the watch. `AddFoodScreen` keeps its plain `AppBar` (it needs the `TabBar` `bottom:` that `OmniBackHeader` does not offer).

## Questions (one round; answered 2026-10-29: owner accepted all four defaults)

1. **Q1** [answered: default] Header "+" colour: the bright text colour of the back arrow (what the Exercise Library "+" uses today), or the theme's accent colour? **Default: back-arrow colour** (D-91.2). Veto before Phase 1.
2. **Q2** [answered: default] The new Training periods icon: same back-arrow colour as other header icons (Stats' Records & Trends), dropping today's accent outline? **Default: yes** (D-91.7). Veto before Phase 1.
3. **Q3** [answered: default] The Periodization list's bottom button still reads `+ New Period` and its form is titled `Create Period` / `Edit Period`. Reword to "Training period" in this PR? **Default: no, separate follow-up** (touches other screens and tests). Veto before Phase 2.
4. **Q4** [answered: default] Periodization and My Routines keep their bottom "+ New …" buttons (adding is their main job, same reasoning as the day list)? **Default: keep** (D-91.8). Veto before Phase 2.

## Feature Invariants

- One header "+" look: every header "+" is `OmniHeaderAddButton`; the scan in D-91.9 is the guard.
- Keys survive: `exercise_library_new_button`, `new_food_button`, `new_group_button` stay on the tappable `IconButton`.
- No behaviour change behind the buttons: same destinations, same created data (D-91.5, D-91.7).
- No allowlist entry, no ratchet raised (`test/helpers/ui_standards_allowlist.dart` untouched).
- Every `docs/` file stays under the 52 KB warning band (`test/docs_indexing_contract_test.dart`); the design docs name no unit value or percentage and every `Omni…` symbol they name must be declared in `lib/`.

## Requirements

- R-1 Shared header "+" piece per D-91.2/D-91.3.
- R-2 Exercise Library header uses it (D-91.4).
- R-3 Calendar header uses the Training periods icon (D-91.7).
- R-4 Contract scan per D-91.9.
- R-5 Food Library: bottom button gone, tab-aware header "+" (D-91.4..D-91.6).
- R-6 Docs follow the code in the same phase.

## Acceptance Criteria

- AC-1 (R-1) The piece looks and reads the same everywhere and shrinks on press → S-9151, S-9152, S-9153.
- AC-2 (R-2) → S-9154. AC-3 (R-3) → S-9155, S-9156, S-9157.
- AC-4 (R-4) → S-9158, S-9159.
- AC-5 (R-5) → S-9161..S-9166, S-9165a.
- AC-6 (R-6) → Phase 1 item 7–8, Phase 2 item 7–8; `test/docs_indexing_contract_test.dart` green.

## Existing-Functionality Impact

| Touched surface | Existing readers (grep) | Effect | Guarded by |
|---|---|---|---|
| key `exercise_library_new_button` | `grep -rn exercise_library_new_button lib test` → `exercise_library_screen.dart:124`; `test/pr8_exercise_library_test.dart:568,590,618,652,700` | key stays on the `IconButton`; tests unchanged | D-91.2, S-9154 |
| key `new_food_button` | `grep -rn new_food_button lib test` → `add_food_screen.dart:174`; `test/library_merge_test.dart:273,277` | moves to the header piece; key taps unchanged | D-91.4, S-9161 |
| key `new_group_button` | → `add_food_screen.dart:167`; `test/library_merge_test.dart:287`; `test/nutrition_test.dart:3865,3890,4350` | moves to the header piece; key taps unchanged | S-9163 |
| text `+ New Food` / `+ New Category` / `+ Create new food` | `grep -rn "+ New Food\|+ New Category\|Create new food" test` → `nutrition_test.dart:1946,2032,2865,4272,4406,4407,4409`; `library_merge_test.dart:274,275,288,532,537`; `picker_polish_test.dart:280,281`; `screen_widget_test.dart:9770` | visible text disappears: taps move to the key, label checks move to the tooltip, "absent" checks stay | Phase 2 items 4–5 |
| `AddFoodScreen` bottom `OmniBottomCTA` | `nutrition_test.dart` group `AddFoodScreen — shared bottom CTA (S-001 / S-002 / S-003)` (`:4220-4411`) | the group's premise is removed: rewrite as the header group (S-9161..S-9166) | D-91.6 |
| `formBottomCTAClearance` in Food Library lists | `add_food_screen.dart:676,1743`; no test reads it (`grep -rn formBottomCTAClearance test` → none) | padding shrinks | S-9166 |
| Food Library source guard | `library_merge_test.dart:511-545` (`S-12818`) asserts `label: '+ New Food',` | assertion inverted (see Phase 2 item 5) | D-91.10 |
| other `add_food_screen.dart` source guards | `library_grouping_test.dart:384` (`S-12824`), `library_row_toggle_test.dart:596` (`S-12716`), `confirmation_dialog_guard_test.dart:34` | they read untouched code (`foodsIEatSections(`, `_CatalogRowState`, dialogs): unaffected | re-run in Phase 2 |
| Calendar header `OutlinedButton('+')` | `test/header_standardization_test.dart:307-342` (`Periods (+) button is present in header actions`) | replaced by S-9155 | D-91.7 |
| `find.textContaining('+')` on the Calendar | `test/calendar_layout_responsive_test.dart:236` (`a short cell shows at least two slots and a +N badge`) | today the header "+" also satisfies it, so it cannot tell whether the `+N` badge (`calendar_screen.dart:598`) shows. After the change only the badge can: tighten the finder (S-9157) | S-9157 |
| Calendar on small screens | `test/screen_overflow_contract_test.dart:138-211` (`'Calendar': buildCalendar`) | icon is narrower than the outlined button: no new overflow | re-run in Phase 1 |
| `_openPeriods` / `PeriodListScreen` | `grep -rn "_openPeriods\|PeriodListScreen(" lib` → only `calendar_screen.dart:99,179-182` | the one entry point keeps its destination | S-9156 |
| Header calls with `Icons.add` / `'+'` | `grep -rn "Icons\.add\b" lib` (14 hits) — inside a header call only `exercise_library_screen.dart:125`; `grep -rnE "Text\('\+'\)" lib` → only `calendar_screen.dart:119` | the scan's baseline is exactly these 2 | S-9159 |
| UI standards ratchets | `test/ui_standards_contract_test.dart` S-2601/S-2606/S-2607/S-3001 | no `Colors.white/black`, sheet or dialog added; the piece's `IconButton` has a tooltip; one `OutlinedButton` (with shape) removed. No ratchet number moves | Done Criteria |
| Bottom buttons that stay | `day_session_list_screen.dart:98,685`, `period_list_screen.dart:69`, `my_routines_screen.dart:74` | untouched | D-91.8 |
| `docs/my_routines.md:258` | says the bottom-button pattern is "used by the calendar day list, food library, etc." | wording goes stale | Phase 2 item 7 |

## UI Standards Impact

New shared piece `OmniHeaderAddButton` for a new job row "Header add action" in `docs/design_system.md` "Shared pieces and rules per job". Uses existing tokens only (`OmniTheme.colors.textDominant`, `pressedScale`, `animationDuration`, `animationCurve`). Removes one `OmniBottomCTA` host (Food Library); the "Primary Bottom CTA" rule still holds for every screen that keeps one. No allowlist entry, no new exception.

## Scenarios

Ids S-9151..S-9166 (grep 2026-10-29: `S-915x`/`S-916x` unused; plan 61 uses S-9101..S-9120). All widget tests run against `MockWorkoutRepository` (each file's existing `_freshRepo()`); no Hive.

### S-9151: the piece renders one "+", reads its label, uses the header colour
- Fixture: `MaterialApp(home: Scaffold(appBar: OmniBackHeader(title: 'T', actions: [OmniHeaderAddButton(label: 'New Thing', buttonKey: Key('k'), onPressed: () => taps++)])))`, `taps = 0`.
- Trigger: pump; tap `Key('k')`.
- Expected outcome: exactly one `Icons.add` in the tree; `tester.widget<IconButton>(find.byKey(Key('k')))` has tooltip `New Thing` and colour `OmniTheme.colors.textDominant`; `find.bySemanticsLabel('New Thing')` finds at least one; no `Text` widget inside the piece; after the tap `taps == 1`.
- Edge case of: none

### S-9152: same size whatever the label
- Fixture: one `Row` holding `OmniHeaderAddButton(label: 'New', buttonKey: Key('a'), onPressed: () {})` and `OmniHeaderAddButton(label: 'New Category With A Very Long Name', buttonKey: Key('b'), onPressed: () {})`.
- Expected outcome: `tester.getSize(find.byKey(Key('a'))) == tester.getSize(find.byKey(Key('b')))`.
- Edge case of: S-9151

### S-9153: press shrink, release, cancel, reduced motion
- Fixture: S-9151's tree; a second pump of the same tree under `MediaQuery(data: MediaQueryData(disableAnimations: true), ...)`.
- Flow: (1) `startGesture` at the button centre, `pump(OmniTheme.animationDuration)` → the piece's `AnimatedScale.scale == OmniTheme.pressedScale`; `up()`, `pumpAndSettle()` → scale `1.0`, `taps == 1`. (2) `startGesture`, `moveBy(Offset(0, 200))`, `up()`, settle → scale `1.0`, `taps` still `1`. (3) reduced motion: press and hold → no `AnimatedScale` under the piece, the applied scale is `OmniTheme.pressedScale` on the first pump; release → `1.0`.
- Edge case of: S-9151

### S-9154: Exercise Library header uses the piece
- Fixture: `test/pr8_exercise_library_test.dart` `_freshRepo()` + `_buildState(repo)` (seeded exercises), `ExerciseLibraryScreen` at 800×1200; second run after typing `zzzz no match 91` in `exercise_library_search_field` and waiting past the 300 ms debounce (`pump(Duration(milliseconds: 350))`).
- Expected outcome: `find.ancestor(of: find.byKey(Key('exercise_library_new_button')), matching: find.byType(OmniHeaderAddButton))` finds one; tooltip `New Exercise`; exactly one `Icons.add` inside `OmniBackHeader`; same after the no-match search. Existing `S-4102`/`S-4103` stay green unchanged.
- Edge case of: S-9151

### S-9155: Calendar header shows the Training periods icon, no "+"
- Fixture: `test/header_standardization_test.dart` setup (400×900, `_freshRepo()`, `CalendarState(repo)..init()`, the `CalendarScreen` constructor block at `:316-327`).
- Expected outcome: inside `OmniBackHeader`: one `Icons.date_range`; zero `Icons.add`; zero `OutlinedButton`; zero `OmniHeaderAddButton`; `find.text('+')` and `find.text('Periods')` find nothing; `find.byKey(Key('calendar_training_periods_button'))` is an `IconButton` with tooltip `Training periods` and colour `OmniTheme.colors.textDominant`; `find.bySemanticsLabel('Training periods')` finds at least one.
- Edge case of: none

### S-9156: the icon still opens the Periodization list
- Fixture: S-9155's; repo with its default seed (whatever periods the Mock seeds; the assertion does not depend on the count).
- Trigger: tap `calendar_training_periods_button`, `pumpAndSettle`; then `pageBack`, `pumpAndSettle`.
- Expected outcome: `PeriodListScreen` is shown with header text `Periodization`; after back, `CalendarScreen` and its `Icons.date_range` are shown again.
- Edge case of: S-9155

### S-9157: the +N badge check can no longer be satisfied by the header
- Fixture: `test/calendar_layout_responsive_test.dart` `a short cell shows at least two slots and a +N badge` (375×667, 5 sessions on day one).
- Change: the finder becomes `find.textContaining(RegExp(r'^\+\d+$'))` (the badge text is `'+$count'`, `calendar_screen.dart:598`).
- Expected outcome: still finds the badge after Phase 1. If it fails, the badge was never showing and the old header "+" hid it: stop and report with the evidence; never relax the finder.
- Edge case of: S-9155

### S-9158: the scan flags a raw header "+" and nothing else
- Fixture: the finding function from D-91.9 called on these synthetic sources (path `lib/features/x.dart`), expected finding counts in brackets:
  - F1 `OmniBackHeader(title: 'A', actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'New', onPressed: f)])` [1]
  - F2 `AppBar(actions: [OutlinedButton(onPressed: f, child: const Text('+'))])` [1]
  - F3 `AppBar(actions: [TextButton(onPressed: f, child: Text('+ Add'))])` [1]
  - F4 `SliverAppBar(actions: [IconButton(icon: Icon(Icons.add_circle_outline), tooltip: 'x', onPressed: f)])` [1]
  - F5 `AppBar(actions: [OmniHeaderAddButton(label: 'New Food', onPressed: f)])` [0]
  - F6 `OmniBackHeader(title: 'A', actions: [IconButton(icon: Icon(Icons.add_a_photo), tooltip: 'Photo', onPressed: f)])` [0] (near-twin icon)
  - F7 `AppBar(title: Text('A'), /* Icons.add '+' */ actions: [])` [0] (comment)
  - F8 `Row(children: [IconButton(icon: Icon(Icons.add), tooltip: 'Add', onPressed: f), Text('+')])` [0] (not a header)
  - F9 `AppBar(title: Text('+$count'))` [0] (a badge, not a "+" label)
  - F10 a source with `AppBar(title: Text('ok'))` on line 1 and F1's text starting on line 3 [1], and the finding names line 3.
- Expected outcome: counts exactly as listed.
- Edge case of: none

### S-9159: the real tree has no raw header "+"
- Fixture: `lib/` as on disk.
- Expected outcome: zero findings after Phase 1. Red evidence (evidence file): with the two screen edits stashed, exactly 2 findings: `lib/features/exercise/exercise_library_screen.dart` (`OmniBackHeader(` ≈ line 117) and `lib/features/calendar/calendar_screen.dart` (≈ line 93).
- Edge case of: S-9158

### S-9161: Food Library, Library tab: header "+" and no bottom button
- Fixture: `test/nutrition_test.dart` `_freshRepo()`; `FoodLibraryState(repo)` with `loadFoodGroups()`, `loadFoods()`, `loadCatalogFoods()` awaited; `NutritionState(repo)`; `MaterialApp(home: OmniGradientBackground(child: AddFoodScreen(...)))` at 400×800.
- Expected outcome: exactly one `OmniHeaderAddButton`, inside the `AppBar`; `new_food_button` present, tooltip `New Food`; `new_group_button` absent; the `AddFoodScreen` `Scaffold.bottomNavigationBar` is null; no `OmniBottomCTA`; `find.text` of `+ New Food`, `+ New Category`, `+ Create new food` all find nothing.
- Edge case of: none

### S-9162: New Food opens the form through the app's standard route
- Fixture: `test/screen_widget_test.dart` `+ New Food bottom CTA pushes the new-food form via OmniRoute (S-N1)` (800×1800, `_RouteTypeRecorder`).
- Change: tap `find.byKey(Key('new_food_button'))` instead of the text; rename the test to say header "+".
- Expected outcome: as today: title `New Food` shown, last pushed route is `OmniRoute<void>`, not `MaterialPageRoute`.
- Edge case of: S-9161

### S-9163: Categories tab: New Category, twice
- Fixture: S-9161's repo with no user categories added (the `+ New Category adds a row…` test, `nutrition_test.dart:3868`).
- Trigger: tap tab `Categories`; tap `new_group_button`; tap it again.
- Expected outcome: before the taps `new_group_button` present with tooltip `New Category`, `new_food_button` absent, still no `OmniBottomCTA`; after one tap `TextField` count = before + 1 and `foodLib.foodGroups` has a group named `New Category`; after the second tap count = before + 2 and two groups are named `New Category`.
- Edge case of: S-9161

### S-9164: tab round trip keeps exactly one "+"
- Fixture: S-9161's.
- Flow: Library → tap `Categories` → tap `Library`; check after each settle.
- Expected outcome: always exactly one `OmniHeaderAddButton`; keys/tooltips `new_food_button`/`New Food` → `new_group_button`/`New Category` → `new_food_button`/`New Food`.
- Edge case of: S-9161

### S-9165: the "+" stays in an empty list
- Fixture: S-9161's; enter `zzzz no match 91` in `catalog_search_field`.
- Expected outcome: the `No matches for "zzzz no match 91"` empty state shows and `new_food_button` is still present; tapping it opens the New Food form.
- Edge case of: S-9161

### S-9165a: amends plan 78 S-13113 (`test/picker_polish_test.dart`)
- Fixture: that file's `_pumpCatalogTab`.
- Expected outcome: test renamed to `S-13113 / S-9165a: the Library create action is the header + labelled New Food`; asserts `new_food_button` tooltip `New Food`, and `+ New Food`, `+ Create new food` text absent.
- Edge case of: S-9161

### S-9166: the list end no longer leaves room for the old button
- Fixture: S-9161's (test view has zero bottom inset).
- Expected outcome: on Library the `ListView` under `_FromCatalogTab` has resolved bottom padding `16`; on Categories the `_GroupsTab` `ListView` has bottom padding `16`; both are below `OmniTheme.formBottomCTAClearance`.
- Edge case of: S-9161

## Iteration 1

Before any edit, each phase records in the evidence file: `flutter analyze` issue count (baseline), and the pass/fail counts of its Done Criteria suites.

### Phase 1: the shared piece, Exercise Library, Calendar, the scan (@developer)
1. [x] Create the piece per D-91.2/D-91.3 — `lib/widgets/buttons/omni_header_add_button.dart` · `OmniHeaderAddButton`
2. [x] Tests S-9151, S-9152, S-9153 — `test/omni_header_add_button_test.dart` (new) · group `S-9151..S-9153 OmniHeaderAddButton`
3. [x] Replace the header `Semantics`+`IconButton` with `OmniHeaderAddButton(label: 'New Exercise', buttonKey: Key('exercise_library_new_button'), onPressed: _openCreateExercise)`; add S-9154 beside `S-4102` — `lib/features/exercise/exercise_library_screen.dart:119-131` · `test/pr8_exercise_library_test.dart`
4. [x] Replace the `Padding`+`OutlinedButton('+')` with the Training periods icon per D-91.7 — `lib/features/calendar/calendar_screen.dart:95-122` · `_CalendarScreenState.build`
5. [x] Replace `Periods (+) button is present in header actions` with S-9155 and add S-9156 — `test/header_standardization_test.dart:307-342`; tighten the finder per S-9157 — `test/calendar_layout_responsive_test.dart:236`
6. [x] Add the D-91.9 finding function and group `S-9158 header plus` (S-9158 fixture tests + S-9159 "no header in lib/ builds a raw +"); update the file's header comment list of plans — `test/ui_standards_contract_test.dart`. Show S-9159 red (2 findings) with items 3–4 stashed; paste in evidence.
7. [x] Docs, design: `docs/design_system.md` (43,024 B now; stays under the 52 KB band) — add the job row `Header add action | OmniHeaderAddButton | lib/widgets/buttons/omni_header_add_button.dart` to the "Shared pieces and rules per job" table; add a short `### Header actions` subsection after `### Bottom actions` (a header "+" creates a new item for this screen's list and is always the shared piece; a header action that goes elsewhere uses an icon for that place, e.g. Calendar's Training periods; bottom buttons stay where adding is the main job; verified by the S-9158 group and `test/omni_header_add_button_test.dart`; the known limit from D-91.9); in "Buttons" add a `Header add` row to the variants table (no unit values) and one sentence under "Press Feedback" that the header add piece carries the press shrink; add `S-9158 header plus` to the groups list in "How these rules are enforced". Add `### OmniHeaderAddButton` to `docs/widget_catalog/layout_and_inputs.md` and its index row to `docs/widget_catalog.md`.
8. [x] Docs, screens: `docs/calendar_periods.md` (Periods section: the Training periods icon in the Calendar header opens the list, wording "Training periods", never "Periods" as a label); `docs/navigation_and_screens.md` rows `CalendarScreen` (:215, the header icon is the Training periods entry point) and `ExerciseLibraryScreen` (:194, the header "+" is the shared piece); `docs/create_new_exercise.md:31` (the header "+" is `OmniHeaderAddButton`).

**Done Criteria** (run until green): `flutter analyze` (issue count ≤ baseline, 0 errors); `flutter test test/omni_header_add_button_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart test/header_standardization_test.dart test/pr8_exercise_library_test.dart test/calendar_layout_responsive_test.dart test/screen_overflow_contract_test.dart`; S-9159 red→green pasted; full `flutter test` (900 s wrapper) counts pasted; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty.
**Predicted Files**: `lib/widgets/buttons/omni_header_add_button.dart` (new), `lib/features/exercise/exercise_library_screen.dart`, `lib/features/calendar/calendar_screen.dart`, `test/omni_header_add_button_test.dart` (new), `test/ui_standards_contract_test.dart`, `test/header_standardization_test.dart`, `test/pr8_exercise_library_test.dart`, `test/calendar_layout_responsive_test.dart`, `docs/design_system.md`, `docs/widget_catalog/layout_and_inputs.md`, `docs/widget_catalog.md`, `docs/calendar_periods.md`, `docs/navigation_and_screens.md`, `docs/create_new_exercise.md`, this plan + its evidence file.

### Phase 2: Manage Food Library moves its "+" to the header (@developer)
1. [x] Delete `_buildBottomCTA` and `bottomNavigationBar:`; put one tab-aware `OmniHeaderAddButton` in the `AppBar`'s `actions` (rebuilt on `_tabController`), labels/keys/actions per D-91.4/D-91.5 — `lib/features/nutrition/add_food_screen.dart:157-214` · `_AddFoodScreenState`
2. [x] Replace both list bottom paddings per D-91.6 — `add_food_screen.dart:672-677` (`_FromCatalogTabState.build`), `:1737-1744` (`_GroupsTab` list)
3. [x] Rewrite the stale comments: class doc (`:43` "A **+ New Food** button sits at the bottom"), the bottom-CTA block (`:100-115`), the host comment (`:209-212`), the `_GroupsTab` padding comment (`:1737-1738`) — `add_food_screen.dart`
4. [x] Rewrite group `AddFoodScreen — shared bottom CTA (S-001 / S-002 / S-003)` as `AddFoodScreen — header + (S-9161..S-9166)` covering S-9161, S-9163 (two taps), S-9164, S-9165, S-9166; switch the text taps at `:1946`, `:2032`, `:2865` to `find.byKey(Key('new_food_button'))` and fix their comments ("at the bottom") — `test/nutrition_test.dart`
5. [x] `test/library_merge_test.dart`: `S-12814` (`:267-290`) checks tooltip `New Food` instead of text `+ New Food`, keeps the key taps and the `+ New Food` absent check; `S-12818` (`:530-539`) replaces `contains("label: '+ New Food',")` with: source does not contain `'+ New Food'`, `'+ New Category'` or `_buildBottomCTA`, and contains `OmniHeaderAddButton(`. `test/picker_polish_test.dart` S-9165a (`:277-282`, and the file header comment `:3`). `test/screen_widget_test.dart` S-9162 (`:9715-9790`).
6. [x] Re-run the untouched readers: `test/library_grouping_test.dart`, `test/library_row_toggle_test.dart`, `test/confirmation_dialog_guard_test.dart`, `test/my_foods_unification_test.dart`, `test/food_group_membership_test.dart`, `test/food_photo_clear_legacy_edit_test.dart` (green, counts pasted)
7. [x] Docs: `docs/nutrition.md:108-115` (header "+", `New Food`/`New Category`, keys kept; cite S-9161/S-9163); `docs/widget_catalog/nutrition_widgets.md:253-255` (Categories tab: header "+", not a bottom button); `docs/navigation_and_screens.md:183` (`AddFoodScreen` row: "a header + for New Food / New Category"); `docs/my_routines.md:258` (drop "food library" from the list of bottom-button screens); `docs/design_system.md` `### Header actions` adds Manage Food Library to the screens using the piece
8. [x] Residue sweep, pasted in evidence: `grep -rn "_buildBottomCTA\|'+ New Food'\|'+ New Category'" lib test` → no hits; `grep -rn "new_food_button\|new_group_button" lib` → only the header call in `add_food_screen.dart`; `grep -rnE "\+ New (Food|Category)" docs --exclude-dir=plans --exclude-dir=history --exclude-dir=releases` → no hits; `grep -rnE "Text\('\+'\)" lib` → no hits

**Done Criteria** (run until green): `flutter analyze` (≤ baseline, 0 errors); `flutter test test/nutrition_test.dart test/library_merge_test.dart test/picker_polish_test.dart test/screen_widget_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` plus item 6's files; full `flutter test` (900 s wrapper) counts pasted; invariant grep empty.
**Predicted Files**: `lib/features/nutrition/add_food_screen.dart`, `test/nutrition_test.dart`, `test/library_merge_test.dart`, `test/picker_polish_test.dart`, `test/screen_widget_test.dart`, `docs/nutrition.md`, `docs/widget_catalog/nutrition_widgets.md`, `docs/navigation_and_screens.md`, `docs/my_routines.md`, `docs/design_system.md`, this plan + its evidence file.

## Files Affected

Production: `lib/widgets/buttons/omni_header_add_button.dart` (new), `lib/features/exercise/exercise_library_screen.dart`, `lib/features/calendar/calendar_screen.dart`, `lib/features/nutrition/add_food_screen.dart` (about 150 changed lines in all).
Tests changed: `test/omni_header_add_button_test.dart` (new), `test/ui_standards_contract_test.dart`, `test/header_standardization_test.dart`, `test/pr8_exercise_library_test.dart`, `test/calendar_layout_responsive_test.dart`, `test/nutrition_test.dart`, `test/library_merge_test.dart`, `test/picker_polish_test.dart`, `test/screen_widget_test.dart`.
Dependents that only read a touched surface (re-run, no edit): `test/screen_overflow_contract_test.dart`, `test/library_grouping_test.dart`, `test/library_row_toggle_test.dart`, `test/confirmation_dialog_guard_test.dart`, `test/my_foods_unification_test.dart`, `test/food_group_membership_test.dart`, `test/food_photo_clear_legacy_edit_test.dart`, `test/interaction_flow_test.dart` (Periodization list `+ New Period`, unchanged).
Docs: `docs/design_system.md`, `docs/widget_catalog/layout_and_inputs.md`, `docs/widget_catalog.md`, `docs/calendar_periods.md`, `docs/navigation_and_screens.md`, `docs/create_new_exercise.md`, `docs/nutrition.md`, `docs/widget_catalog/nutrition_widgets.md`, `docs/my_routines.md`.
Not touched: `test/helpers/ui_standards_allowlist.dart`, anything under `lib/watch/`, `watch/`, the plan-89 folder, `docs/session_summary.md`, `lib/features/session/session_summary_screen.dart`.

## Notes

- Dependency graph: Phase 2 needs Phase 1 item 1 (the piece) and item 6 (the scan, so the new header is guarded the moment it lands). No other order works without duplicating the piece.
- Intermediate state after Phase 1: Exercise Library and Calendar are done; Manage Food Library still has its bottom button and no header "+". The scan is green in that state (the Food Library `AppBar` has no actions yet), and the docs describe exactly that state.
- `testWidgets` + FakeAsync: every scenario here is Mock-only and never awaits a real delay; the Exercise Library search debounce is advanced with `pump(Duration(milliseconds: 350))`, not a real wait.
- The design docs must not name `OmniHeaderAddButton` before the class exists in `lib/` (`every Omni symbol the design docs name is declared in lib/`): items 1 and 7 of Phase 1 land together.
- No legacy handling: no persisted data changes.

## Progress

- [x] Phase 1 items 1–8 — **Complete** (2026-10-29): Done Criteria files +233 green, full suite +5868 ~2 green, analyze 180 = baseline, S-9159 red (2) → green (0); evidence file.
- [x] Phase 2 items 1–8 — **Complete** (2026-10-29): Done Criteria files +444 green, full suite +5870 ~2 green, analyze 180 = baseline, 7 reds → green; evidence file.
- [x] Review fixes 1–6 — **Complete** (2026-10-29): docs corrected, one-node semantics (red 2 nodes → green 1), refresh + inset tests added; full suite +5872 ~2 green, analyze 180; evidence "Review fixes".

## Assumption Log

- A-1 (Phase 1) Owner answered Q1–Q4 on 2026-10-29 with all defaults (relayed by the governor): header "+" in the back-arrow colour (D-91.2); Training periods icon in the back-arrow colour, no outline (D-91.7); no Periodization rewording (Q3); Periodization and My Routines keep their bottom buttons (D-91.8).
- A-2 (Phase 1) S-9159 red was shown by running the finished scan before items 3–4 were edited (2 findings, evidence file) instead of stashing them afterwards: same proof, and the shared tree holds other units' uncommitted work.
- A-3 (Phase 1) Phase 0 compiled against a stub piece (`SizedBox.shrink()`) and a stub scan (`const []`) so every red was a behaviour failure, not a missing symbol. The piece tracks the press with a `Listener` (outside the gesture arena), so the `IconButton`'s own tap and slide-off cancel are untouched.
- A-4 (Phase 2) Item 8's first grep cannot return zero in `test/`: items 4–5 require `+ New Food`/`+ New Category` absence checks. Kept them; `lib/` has no hits (evidence lists the 6 test hits).
- A-5 (review fix 5) Dropped the `Semantics` wrapper D-91.2/D-91.7 prescribed: it made a second, untappable screen-reader stop. The `IconButton` tooltip is the one node (label, button, tap); options were exclude-child-semantics or merge, rejected as more code for the same result.

## Feedback
