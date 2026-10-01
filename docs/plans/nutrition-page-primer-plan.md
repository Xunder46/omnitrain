# Feature: Nutrition Page — First-Tap Primer

## Overview
The Daily Nutrition page inverts the usual food-logging model and packs several
unfamiliar ideas onto one screen (curate "Foods I Eat" once, check-off with
adjustable portions, calories/macros rollup, water, sodium). New users have no
context for any of it, so the first time they tap the nutrition strip on the
Home Screen we want a single dismissible primer that explains the page in three
short blocks, plus a persistent "?" in the page header to reopen it. This task
delivers only the primer sheet, the persistence of its seen-state, and the
header entry point — it does NOT change the nutrition feature itself.

## Requirements
- One-time, dismissible primer sheet explaining the Daily Nutrition page
  model: (1) curate a "Foods I Eat" list once from the library;
  (2) check foods off daily with an adjustable portion per food;
  (3) the day's rollup: calories vs target, macros, water, sodium.
- The primer is a single self-contained sheet — no multi-step carousel,
  no pointers anchored to live page elements, no step indicators.
- Auto-shows the first time the user taps the nutrition strip from the
  Home Screen, and from no other surface.
- After dismissal, the seen state is persisted across full app
  restarts (the primer never auto-shows again on a relaunched app).
- A persistent "?" control in the Daily Nutrition page header reopens
  the same primer at any time, regardless of seen state, without
  altering the seen state.
- The primer must never block navigation; the Daily Nutrition page
  must be reachable when the primer is dismissed (and would be
  reachable even if the primer were never shown).
- All copy is terse, functional, instrument-panel tone — no
  motivational language, no exclamation points.
- Each block is a short label plus one or two plain sentences.

## Acceptance Criteria
- [ ] A new `NutritionPrimerState` exists at
      `lib/state/nutrition/nutrition_primer_state.dart` and is wired
      into `main.dart` + `MyApp` + `HomeScreen` + `NutritionScreen`
      via constructor DI, exactly like every other state class.
- [ ] The state hydrates from `repository.getPreferenceBool('primer_seen_nutrition')`
      inside an `init()` method, and `markSeen()` persists
      `setPreferenceBool('primer_seen_nutrition', true)`. The state
      fires `notifyListeners()` on every change.
- [ ] `HomeScreen._openNutritionScreen()` consults the primer
      state on the FIRST tap of the nutrition strip. When
      `shouldShowPrimer` is `true`, it shows the primer sheet first
      and pushes the nutrition page after dismissal; when `false`,
      it pushes the page directly. The "first" check is the
      in-state `shouldShowPrimer` getter (false after the user has
      ever been shown the primer on this install).
- [ ] Calling `markSeen()` on the primer state flips its persisted
      flag so the next home-screen tap does not auto-show. The
      primer still reopens via the header "?" after dismissal.
- [ ] The Daily Nutrition page header has a persistent "?" icon
      button. Tapping it opens the same primer sheet; the seen
      state is NOT mutated by this tap.
- [ ] The primer is a single modal sheet (no steps, no carousel,
      no `PageView`, no pointers tied to on-screen widgets) and
      presents exactly the three required blocks (curate, check,
      rollup). No out-of-scope content (target editing, category
      management, water stepper).
- [ ] Dismissing the primer (single "Got it" action) closes the
      sheet and records the seen state.
- [ ] All buttons in the primer use `OmniTheme.buttonBorderRadius`
      with an explicit `shape:` override (no Material 3 default
      StadiumBorder).
- [ ] All colors come from `OmniTheme.colors` / `theme.colorScheme`;
      no hardcoded colors in the primer widget.

## Scenarios

### S-001: First nutrition strip tap shows the primer
- Trigger: User taps the home nutrition summary card on the very
  first time they ever tap it (fresh install, no prior primer
  dismissal, app cold start).
- Precondition: `NutritionPrimerState.shouldShowPrimer == true`
  (preference flag is not set).
- Flow:
  1. App boots, `main.dart` instantiates `NutritionPrimerState`,
     calls `init()` which reads the unseen default.
  2. User lands on `HomeScreen`. The card renders normally.
  3. User taps the nutrition card → `_openNutritionScreen` runs.
  4. State check fires; the primer sheet opens (animated in over
     the home screen) and the navigation push to
     `NutritionScreen` is DEFERRED until the sheet is dismissed.
  5. The user reads the three blocks and taps "Got it".
- Expected outcome: Sheet closes; preference
  `primer_seen_nutrition` is `true`; `NutritionScreen` is then
  pushed (the user lands on the nutrition page behind the sheet
  by the time the sheet finishes dismissing).
- Edge case of: none.

### S-002: Dismissal persists across full app restart
- Trigger: After S-001 completes, the user force-quits and
  relaunches the app.
- Precondition: Preference `primer_seen_nutrition == true`.
- Flow:
  1. App reboots; `main.dart` constructs a fresh
     `NutritionPrimerState` and calls `init()`.
  2. The init reads the persisted preference; the state
     reports `shouldShowPrimer == false`.
  3. User returns to `HomeScreen` and taps the nutrition card.
- Expected outcome: The primer does NOT auto-show. The user is
  pushed directly to `NutritionScreen`. The persisted flag is
  asserted by the test (not inferred from in-session state).
- Edge case of: S-001 (the same user, second session).

### S-003: Header "?" reopens the primer regardless of seen state
- Trigger: User is on `NutritionScreen` and taps the "?" icon in
  the page header.
- Precondition: None — works whether the user has dismissed the
  primer (S-001 path) or never tapped the home strip (e.g.
  reached the nutrition page via the hub).
- Flow:
  1. The user is on `NutritionScreen` (after auto-show OR a
     direct hub navigation).
  2. They tap the "?" icon in the AppBar.
  3. The primer sheet opens over the nutrition page.
  4. They read the three blocks and tap "Got it".
- Expected outcome: Sheet closes. The primer's seen state is
  NOT mutated — `NutritionPrimerState.shouldShowPrimer` remains
  whatever it was before. A subsequent home-strip tap still
  auto-shows the primer IFF the seen flag is still false.
- Edge case of: none (covers both pre-dismissal and post-dismissal
  seen states).

### S-004: Primer is a single sheet with three blocks, no carousel
- Trigger: Any path that opens the primer.
- Precondition: Primer sheet is rendered.
- Flow:
  1. The sheet renders a vertical stack of three labeled blocks.
  2. The user inspects the rendered sheet widget tree.
- Expected outcome: The rendered sheet contains:
  - A title row ("DAILY NUTRITION" or similar).
  - Block 1 labeled "YOUR LIST, BUILT ONCE" with text describing
    the curated "Foods I Eat" list.
  - Block 2 labeled "CHECK TO LOG, SET THE AMOUNT" with text
    describing daily check-off + adjustable portion.
  - Block 3 labeled "YOUR DAY, AT A GLANCE" with text describing
    the rollup (calories vs target, macros, water, sodium).
  - A single primary action ("Got it").
  - NO `PageView`, `PageController`, step indicator dots, or
    Next/Back navigation.
- Edge case of: none.

### S-005: Primer never gates access
- Trigger: User taps the nutrition strip from the Home Screen
  with the primer flagged as already seen (S-002).
- Precondition: `NutritionPrimerState.shouldShowPrimer == false`.
- Flow:
  1. The user taps the nutrition card.
  2. `_openNutritionScreen` consults the state; since the
     primer is already seen, the state does not auto-show.
  3. The screen pushes directly to `NutritionScreen`.
- Expected outcome: `NutritionScreen` is reachable; the user is
  not blocked by any primer overlay; the page is fully
  interactive immediately.
- Edge case of: S-001 (S-005 is the no-primer control case).

### S-006: Wrong-pattern test guard — non-persistence assertion
- Trigger: A future contributor re-implements the seen flag
  on an in-memory `bool` (NOT persisted via the repository),
  copying the visible "before init() runs" snapshot of
  `HomeState._maintenanceHintSeen` (which is `false` by default
  before `init()` hydrates the persisted value).
- Precondition: Wrong pattern in place — `_seen = false` at
  declaration time, no repository round-trip.
- Flow:
  1. App boots; `init()` is called (or missed).
  2. A simulated app restart (build a fresh state instance) is
     constructed.
  3. The test reads the persisted value via
     `repository.getPreferenceBool('primer_seen_nutrition')` —
     NOT just the in-memory getter.
- Expected outcome: The persisted value is `true` after the
  S-001 dismissal. The test asserts on the persisted value so
  a regression that drops persistence (e.g. copying the
  HomeState hint pattern without calling `init()`) is caught.
- Edge case of: none (this is a regression guard).

## Iteration 1

### DB Changes
- No new models, no schema changes. Persistence uses the
  existing `WorkoutRepository.getPreferenceBool` /
  `setPreferenceBool` preference key surface
  (`'primer_seen_nutrition'`).
- No new repository methods; the existing preference API on
  `WorkoutRepository` already covers the storage contract.
- No `MockWorkoutRepository` changes (the existing in-memory
  `_boolPrefs` map handles the new key automatically).
- No `HiveWorkoutRepository` changes (the existing
  `_metaBox.put` path handles the new key automatically).
- No `scripts/sqlite_schema.sql` / `scripts/sqlite_seed.sql`
  changes (preferences live in the generic preference table).

### Backend / State Changes
- New `NutritionPrimerState` in
  `lib/state/nutrition/nutrition_primer_state.dart`:
  - `class NutritionPrimerState extends ChangeNotifier`
  - Constructor: `NutritionPrimerState(this._repository)` —
    repository is `WorkoutRepository` (interface only).
  - Private fields: `bool _seen = false` (defaults unseen; the
    persisted value wins once `init()` completes).
  - Getters:
    - `bool get shouldShowPrimer => !_seen;`
    - `bool get hasSeen => _seen;`
  - Methods:
    - `Future<void> init() async` — reads
      `_repository.getPreferenceBool('primer_seen_nutrition')`,
      sets `_seen`, calls `notifyListeners()`. Wraps in
      `try/catch`; on failure leaves `_seen = false` and
      still notifies (a missed read should NOT silently
      leave the seen state unknown — it should fall back to
      "show the primer", which is the safer default).
    - `Future<void> markSeen() async` — sets `_seen = true`,
      calls `notifyListeners()`, persists via
      `_repository.setPreferenceBool('primer_seen_nutrition', true)`.
      Idempotent — early-returns if already seen (same pattern
      as `HomeState.markMaintenanceHintSeen`).
- No service / domain changes; this is a pure UI-orchestration
  state.

### Frontend Changes
- `lib/main.dart`:
  - Construct `NutritionPrimerState(repository)` BEFORE
    `MyApp` is built.
  - Call `await nutritionPrimerState.init()` (mirrors the
    existing `await homeState.init()` pattern).
  - Pass `nutritionPrimerState` through `MyApp` →
    `HomeScreen` + `NutritionScreen` via constructor DI.
- `lib/app.dart`:
  - Add `final NutritionPrimerState nutritionPrimerState;` to
    `MyApp` and pass it to `HomeScreen(...)`.
- `lib/features/home/home_screen.dart`:
  - Add `final NutritionPrimerState nutritionPrimerState;` to
    `HomeScreen` constructor (required, no default).
  - Update `_openNutritionScreen()`:
    1. If `widget.nutritionPrimerState.shouldShowPrimer` is
       `true`, call
       `await widget.nutritionPrimerState.markSeen()` BEFORE
       pushing, then push `NutritionScreen` (the primer does
       not show inline on the home screen — see below).
  - **Re-evaluated decision**: per the spec, the primer MUST
    appear automatically on the first tap, not be silently
    consumed. The chosen approach is:
    1. Open the primer sheet over the home screen via
       `showModalBottomSheet` (the same mechanism used by the
       free-training start sheet and the maintenance hub
       sheet), with `isScrollControlled: true`.
    2. After the user dismisses the sheet (taps "Got it"),
       THEN push `NutritionScreen`.
    3. The primer is a one-shot gate that runs on the first
       tap, sits over the home screen, and pushes the page on
       close. On the second tap, the state is already seen,
       and the page pushes directly with no overlay.
  - The primer is a new shared widget
    `NutritionPrimerSheet` (see Widgets section).
- `lib/features/nutrition/nutrition_screen.dart`:
  - Add `final NutritionPrimerState nutritionPrimerState;` to
    `NutritionScreen` constructor (required).
  - Replace the plain `Scaffold(appBar: AppBar(title: Text('Daily Nutrition')))`
    with an `AppBar` that has an `actions: [IconButton(...)]`
    with the "?" icon (key `nutrition_primer_help`). The icon
    button opens the same `NutritionPrimerSheet` via
    `showModalBottomSheet`; it does NOT mutate the seen state.
- `lib/features/nutrition/widgets/nutrition_primer_sheet.dart`
  (new widget):
  - Public widget: `NutritionPrimerSheet` (StatelessWidget
    with a content factory `NutritionPrimerSheet.content(...)`
    so tests can render the same body without a sheet).
  - Three `NutritionPrimerBlock` widgets in a vertical
    `Column` (scrollable inside the sheet via
    `SingleChildScrollView`).
  - One "Got it" `FilledButton` at the bottom that calls
    `Navigator.of(context).pop()`.
  - Keys: `nutrition_primer_block_curate`,
    `nutrition_primer_block_check`,
    `nutrition_primer_block_rollup`, `nutrition_primer_dismiss`.
  - Button style: `shape: RoundedRectangleBorder(borderRadius:
    BorderRadius.circular(OmniTheme.buttonBorderRadius))` —
    no StadiumBorder.
  - Colors: `OmniTheme.colorsForTheme(...)` + theme
    `colorScheme.primary` for the icon button.
- Update the home test factory
  (`test/home_logo_hub_open_test.dart` →
  `buildHomeScreen`) to construct the new
  `NutritionPrimerState`, call `init()`, and pass it through
  to `HomeScreen`.
- Update the nutrition test factories (in
  `test/home_nutrition_summary_card_test.dart` and any other
  home-screen factory that constructs a `HomeScreen`) with
  the same pattern.

### Implementation Steps
- [ ] (DBA) Create `NutritionPrimerState` at
      `lib/state/nutrition/nutrition_primer_state.dart` with
      `init`, `markSeen`, `shouldShowPrimer`, `hasSeen`.
- [ ] (DBA) Wire `NutritionPrimerState` into `lib/main.dart`,
      `lib/app.dart` (via `MyApp`).
- [ ] (DBA) Pass `nutritionPrimerState` to `HomeScreen` and
      `NutritionScreen` constructors (and update all existing
      test factories that build a `HomeScreen`).
- [ ] (DBA) Add `'primer_seen_nutrition'` preference key as a
      constant on the new state class (private static
      `_preferenceKey`).
- [ ] (DBA) Update `docs/navigation_and_screens.md` with the
      new constructor dependency, the new `NutritionPrimerSheet`
      entry, and the auto-show behavior on the nutrition strip
      first tap.
- [ ] (DBA) Update `docs/state_management.md` with the new
      `NutritionPrimerState` (constructor, getters, methods,
      `init()` hydration contract).
- [ ] (DBA) Update `docs/widget_catalog.md` with the new
      `NutritionPrimerSheet` (purpose, behavior, keys,
      button-shape contract).
- [ ] (Dev) Write the new test file
      `test/nutrition_primer_test.dart` with scenarios S-001
      through S-006 (red).
- [ ] (Dev) Create the `NutritionPrimerSheet` widget at
      `lib/features/nutrition/widgets/nutrition_primer_sheet.dart`
      (3 blocks, "Got it" CTA, theme-reactive colors, explicit
      button shape).
- [ ] (Dev) Update `HomeScreen._openNutritionScreen` to show
      the primer on the first tap, then push
      `NutritionScreen` after dismissal. The primer uses
      `showModalBottomSheet` with `isScrollControlled: true`.
- [ ] (Dev) Update `NutritionScreen` AppBar with the "?"
      action that opens the same sheet without mutating seen
      state.
- [ ] (Dev) Run `flutter test` — all S-001..S-006 green; all
      pre-existing tests still pass.
- [ ] (Dev) Run `flutter analyze lib/` and `flutter analyze
      test/` — clean.
- [ ] (Reviewer) Walk the checklist; produce findings; mark
      Phase 3 complete.

## Progress
- [x] Phase 0 — plan file written
- [x] Phase 1 — `NutritionPrimerState` + DI wiring + doc updates
- [x] Phase 2 — `NutritionPrimerSheet` widget + HomeScreen tap logic + NutritionScreen "?" + TDD red→green
- [x] Phase 3 — code review

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

## Feedback
(Empty — no blockers.)
