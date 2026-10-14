# S8 · Area scout · nutrition (read-only)

Area docs read: `docs/nutrition.md`, `docs/widget_catalog/nutrition_widgets.md`, nutrition parts of
`docs/navigation_and_screens.md` (lines 125–200, 247–260). Code read: all 5 screens in
`lib/features/nutrition/` and all 10 widgets in `lib/features/nutrition/widgets/`, plus the shared
primitives they call (`OmniSurface`, `OmniCardHeader`, `OmniBottomCTA`, `OmniBackHeader`,
`ConfirmationDialog`, `SelectAllOnFocus`) and `docs/global_conventions.md`,
`docs/documentation_standard.md` §3.

Names checked against `lib/`: ~45 (5 screens, 10 feature widgets + 2 private widget names the catalog
uses, 3 state owners, 12 `OmniTheme.*` tokens, 10 service/helper symbols, 3 shared primitives).
One name not found as written: `_CategoriesTab` (the class is `_GroupsTab`). Everything else exists.

---

## 1 · STALE-DOC / CONFLICT

### F1 · STALE-DOC · Target control is no longer "the small edit icon on the CalorieRingCard"
- Where the doc says it: `docs/navigation_and_screens.md:159-160` — "the small edit icon on the
  `CalorieRingCard` at the top of that screen pushes `NutritionTargetScreen`."
- Where the code does it: `lib/features/nutrition/nutrition_screen.dart:243-291` — the control is a
  labelled `OutlinedButton.icon` (key `nutrition_target_button`, label "Set target"/"Change target")
  in the `OmniCardHeader(title: 'TODAY')` actions slot, above the card. The card itself confirms the
  move: `lib/features/nutrition/widgets/calorie_ring_card.dart:225-231` — "Edit-targets control
  (labelled `OutlinedButton.icon`, key `nutrition_target_button` ...) moved to the header section
  outside the card".
- What a user would see: a bordered "Set target"/"Change target" button next to the TODAY heading,
  not an icon inside the ring card.
- Guard: `test/nutrition_target_button_test.dart` (exists; not opened this run).
- Unsure: nothing.
- NOTICED: `calorie_ring_card.dart:58,63` — `onEditTap` is still a required constructor parameter
  but is never used in the widget's build; dead parameter.

### F2 · STALE-DOC · Catalog names the third tab's widgets and controls by their old names
- Where the doc says it: `docs/widget_catalog/nutrition_widgets.md`, `_CategoriesTab` section —
  "private `_CategoriesTab`, `_GroupRow`, `_UngroupedRow`, `_DeleteGroupDialog`"; "A '+ New Group'
  `OutlinedButton.icon` (key `new_group_button`) that calls `FoodLibraryState.createFoodGroup('New
  Group')`"; `_DeleteGroupDialog`: "Title 'Delete group?'"; options "'Ungrouped' (the default,
  value `null`)".
- Where the code does it:
  - `lib/features/nutrition/add_food_screen.dart:1330` — the class is `_GroupsTab`, not
    `_CategoriesTab` (`_GroupRow`, `_UngroupedRow`, `_DeleteGroupDialog` do exist with those names).
  - `add_food_screen.dart:126-131` — the control is an `OmniBottomCTA` labelled `'+ New Category'`
    (`buttonKey: Key('new_group_button')`), not an `OutlinedButton.icon`; it calls
    `createFoodGroup('New Category')` (`add_food_screen.dart:141`).
  - `add_food_screen.dart:1690` — dialog title is `'Delete category?'`.
  - `add_food_screen.dart:1706-1709` and `food_form.dart:905-908` — the null destination is
    labelled `'Uncategorized'`, not "Ungrouped".
- What a user would see: a "+ New Category" bottom button, a "Delete category?" dialog and an
  "Uncategorized" bucket everywhere; no "Ungrouped" or "New Group" wording survives on screen.
- Guard: `test/food_library_state_delete_guard_test.dart`, `test/food_group_membership_test.dart`
  (exist; not opened this run).
- Unsure: nothing.

### F3 · STALE-DOC · Catalog claims an amount edit is never persisted until an explicit commit
- Where the doc says it: `docs/widget_catalog/nutrition_widgets.md`, `LogFoodRow` — "An unsaved
  amount edit is not a log. Typing in the amount field updates the in-memory controller only; the
  food row is written when the user explicitly commits."
- Where the code does it: `lib/features/nutrition/widgets/log_food_row.dart:63-66` — "Editing the
  amount on a logged row **auto-commits** the new amount to the day log (debounced ~250 ms) — the
  user does NOT need to re-tap the thumb"; implementation at `log_food_row.dart:236-278`
  (`_scheduleAutoCommit`, `Timer(_autoCommitDelay = 250ms, _autoCommitIfLogged)`), plus a
  focus-loss/submit fallback (`_recommitIfLogged`). The thumb tap is the explicit commit only for
  the first log of an unlogged food.
- What a user would see: type a new amount on a food already checked off today, pause a quarter
  second, and the ring/totals move without any further tap.
- Guard: none found: searched `test/` for `autoCommit`, `_autoCommitDelay` — not checked this run
  (test dir not searched for this term).
- Unsure: whether a test pins the 250 ms debounce.

### F4 · STALE-DOC · Catalog says every form field selects all on focus; name and notes do not
- Where the doc says it: `docs/widget_catalog/nutrition_widgets.md`, `FoodForm` — "every
  `TextFormField` on the form (name, reference amount, reference label, all five macros, notes) has
  a per-field `FocusNode` wired to a `_selectAllOnFocus` handler."
- Where the code does it: `lib/features/nutrition/widgets/food_form.dart:243-252` — "The free-text
  name field and the multi-line notes field are NOT wired to select-all"; `food_form.dart:383-412`
  binds only reference amount, reference label and the five macros via the shared
  `bindSelectAllOnFocus`. `_nameFocus` / `_notesFocus` exist but are never bound.
- What a user would see: tapping a pre-filled macro or reference field highlights the whole value;
  tapping the name or notes field places the cursor instead.
- Guard: `test/food_form_shipped_photo_test.dart` covers S-004..S-006 per the catalog; not opened
  this run.
- Unsure: whether a test asserts the name field's cursor behaviour.

### F5 · STALE-DOC · Catalog's blanket "host owns the bottom CTA" does not hold for EditFoodScreen
- Where the doc says it: `docs/widget_catalog/nutrition_widgets.md`, `FoodForm` — "Save CTA: the
  form does **not** render an inline save button. The host screen owns the primary bottom CTA via
  the shared `OmniBottomCTA` ... The host wires the CTA's `onPressed` to `FoodFormController.submit`".
- Where the code does it: `lib/features/nutrition/edit_food_screen.dart:96-121` — the Scaffold has
  **no** `bottomNavigationBar` at all; the trailing comment reads "Auto-save on blur - no save
  button needed for existing foods" (`autoSaveOnBlur: true, skipPopOnSave: true`). The catalog's
  own `onImageSave` row acknowledges this host has "no Save button", so the doc contradicts itself
  in one page.
- What a user would see: the Edit Food screen has no Save button anywhere; edits persist when
  focus leaves the form.
- Guard: none found: searched `lib/features/nutrition/edit_food_screen.dart` for `OmniBottomCTA` —
  absent.
- Unsure: nothing.

### F6 · STALE-DOC · nutrition.md describes AddFoodScreen as "three modes" incl. creating; it is a three-tab surface and creating is a separate pushed screen
- Where the doc says it: `docs/nutrition.md:44-46` — "The library's editor, in three modes: the
  library itself, creating a new item, and managing groups."
- Where the code does it: `lib/features/nutrition/add_food_screen.dart:171-176` — three tabs
  (`Library`, `My Foods`, `Categories`); creating a new item is a full-screen push
  (`_NewFoodFormScreen`, `add_food_screen.dart:713-733`, AppBar title 'New Food') opened from the
  My Foods tab's bottom CTA. The doc never mentions the My Foods tab, the Library tab's search
  field, or the legacy-row edit shim.
- What a user would see: three tabs named Library / My Foods / Categories; "+ New Food" opens a
  separate New Food screen rather than being a mode of the same screen.
- Guard: `test/my_foods_unification_test.dart` (exists; not opened this run).
- Unsure: nothing.

## 2 · NO-RULE / INCONSISTENT (behaviour written nowhere)

### F7 · INCONSISTENT · Empty trend renders a flat zero line while the area's own invariant says absence is never zero
- Where the doc says it: `docs/nutrition.md:17-19` — "Absence is never zero. A day with nothing
  logged is skipped rather than plotted as a zero point".
- Where the code does it: `lib/features/nutrition/widgets/nutrition_trend_card.dart:340-348` —
  "Builds an empty chart showing zero values when there's no [data]": 7 `FlSpot(i, 0)` points, a
  flat line at zero, date axis, no explanatory text.
- What a user would see: with no logged food at all, the trend card shows a flat line at zero
  instead of a "no data" message — the one empty state in the area that is a chart, not words.
- Guard: `test/nutrition_trend_screen_test.dart` (exists; not opened this run).
- Unsure: whether the empty chart is asserted anywhere.

### F8 · NO-RULE · Empty states are muted text (or icon+text), each worded locally, no shared rule
- Where the code does it:
  - `lib/features/nutrition/nutrition_screen.dart:383-393` — Foods I Eat empty: "Your Foods I Eat
    list is empty. Tap the pencil to add foods." (`textMuted`, centred).
  - `add_food_screen.dart:355-361` — Library tab, no catalog: "No catalog foods available";
    `add_food_screen.dart:431-439` — no search match: `No matches for "<query>"`.
  - `add_food_screen.dart:637-668` — My Foods empty: `Icons.restaurant_menu` 64 px + "No custom
    foods yet" + "Create your own foods to use in your nutrition tracking".
  - `nutrition_trend_card.dart:655` — single logged day: "1 day — log more to see a trend".
- What a user would see: every list explains its own emptiness in muted text; the wording, and
  whether an icon accompanies it, is decided per surface.
- Guard: none found: searched `docs/global_conventions.md` for empty-state rules — the Rules table
  has none.
- Unsure: whether `docs/design_system.md` states an empty-state rule (not read this run).

### F9 · INCONSISTENT · Destructive actions: some confirm, some do not, and two dialog patterns coexist
- Where the code does it:
  - Confirmed: deleting a user-created food — `add_food_screen.dart:979-994` uses the shared
    `ConfirmationDialog.twoChoice` (destructive, keys `food-delete-cancel`/`food-delete-confirm`).
  - Confirmed with a bespoke dialog: deleting a non-empty category — `add_food_screen.dart:1490-1500`
    opens the private `_DeleteGroupDialog` (raw `AlertDialog` + destination dropdown), not the
    shared `ConfirmationDialog`.
  - Not confirmed: removing a catalog food from the library (Library tab trash button,
    `add_food_screen.dart:1256-1276`) unlogs today's entry and removes the food immediately, no
    dialog; deleting an **empty** category is also silent (`add_food_screen.dart:1455-1470`).
  - Blocked, raw AlertDialog: deleting a bundled food shows a plain `AlertDialog` "Cannot Delete"
    (`add_food_screen.dart:959-977`), again not the shared component.
- What a user would see: tapping the trash on a My Foods row asks "Delete Food?"; tapping the trash
  on a Library row removes the food (and today's log of it) with no question; category deletion
  uses a differently-styled dialog than food deletion.
- Guard: `test/food_library_state_delete_guard_test.dart` (exists; not opened this run).
- Unsure: whether any doc outside the area prescribes which dialog to use.

### F10 · NO-RULE · Unsaved changes are never guarded; two screens auto-save, two discard silently
- Where the code does it:
  - `lib/features/nutrition/edit_food_screen.dart:100-101` — `autoSaveOnBlur: true,
    skipPopOnSave: true`: edits persist when focus leaves the form; system back just leaves.
  - `lib/features/nutrition/widgets/log_food_row.dart:63-66` — amount edits auto-commit (debounced).
  - `add_food_screen.dart:296-312` (`_NewFoodFormScreen`) and `add_food_screen.dart:243-293`
    (`_LegacyLibraryEditScreen`) plus `nutrition_target_screen.dart:96-110` — a Save `OmniBottomCTA`
    exists, but system back with half-typed values discards them; no `PopScope`/`WillPopScope` and
    no `ConfirmationDialog.showUnsavedChanges` anywhere in the area (searched
    `lib/features/nutrition` for `PopScope|WillPopScope|showUnsavedChanges|UnsavedChanges` — only
    the enum's definition file matches, none of the area files).
- What a user would see: on Edit Food, backing out keeps your edits; on New Food or the calorie
  target, backing out throws them away — with no warning in either case.
- Guard: none found: searched `lib/features/nutrition` for pop-guard symbols (above).
- Unsure: whether another area's unsaved-changes rule is meant to apply here.

### F11 · NO-RULE · Errors surface as snackbars with per-call copy; no shared rule or catalogue
- Where the code does it: ~20 `SnackBar` sites across the area, all plain-text, e.g.
  `add_food_screen.dart:1034-1035` "Could not delete <name>", `add_food_screen.dart:1526-1535` the
  bundled-food refusal with count, `food_form.dart:519-520` "Could not save food",
  `nutrition_screen.dart` has none (loads fail silently into empty UI). `EditFoodScreen.onSave`
  swallows the exception and returns `false`, which the form turns into the generic "Could not save
  food" snackbar (`food_form.dart:517-521`).
- What a user would see: every failure is a transient bottom snackbar; the wording differs per
  call site and some carry detail (counts, names) while others are generic.
- Guard: none found: searched `docs/global_conventions.md` — no error-surface rule.
- Unsure: whether `docs/design_system.md` prescribes snackbar styling.

### F12 · NO-RULE · Keyboard behaviour: decimal keyboards and select-all are per-field decisions; no dismissal affordance
- Where the code does it: numeric fields use
  `TextInputType.numberWithOptions(decimal: true)` with the `^\d*\.?\d*$` formatter
  (`food_form.dart:833-839, 786-793`; `log_food_row.dart:536-541`); the target field uses plain
  `TextInputType.number` (`nutrition_target_screen.dart:170`); select-all-on-focus via the shared
  `SelectAllOnFocus`/`bindSelectAllOnFocus` on numeric fields only (F4); the group-rename field
  commits on `onTapOutside` **and** `onEditingComplete` **and** `onSubmitted`
  (`add_food_screen.dart:1608-1611`); no `numeric_field_with_done_bar` and no explicit keyboard
  dismissal anywhere in the area (searched `lib/features/nutrition` for
  `numeric_field_with_done_bar|FocusScope.unfocus` — no matches).
- What a user would see: numbers get decimal keyboards and overwrite-on-tap; there is no Done-bar
  accessory and no tap-outside-to-dismiss-keyboard guarantee; the category name field can fire its
  rename up to three times for one commit.
- Guard: none found: searched `docs/global_conventions.md` — no keyboard rule.
- Unsure: whether the triple rename commit is guarded downstream (state layer not read).

### F13 · NO-RULE · Bottom primary actions follow the shared OmniBottomCTA where they exist, but "which screens get one" is unwritten
- Where the code does it: `OmniBottomCTA` on `AddFoodScreen` (tab-aware: '+ New Food' / '+ New
  Category' / none on Library, `add_food_screen.dart:118-136`), `_NewFoodFormScreen` ('Create'),
  `_LegacyLibraryEditScreen` ('Save'), `NutritionTargetScreen` ('Save'). `EditFoodScreen`,
  `NutritionScreen`, `NutritionTrendScreen` have none — their primary actions live in headers
  (pencil icon, "Set target" button) or nowhere.
- What a user would see: form screens end in a full-width bottom button; browse screens use header
  controls instead; nothing written says which pattern a screen type gets.
- Guard: none found: the rule exists only as a widget docstring
  (`lib/widgets/layout/omni_bottom_cta.dart:5-27`) and two plan docs it cites.
- Unsure: whether `docs/widget_catalog/layout_and_inputs.md` states the rule (not read this run).

## 3 · DOC-OFF-STANDARD

### F14 · DOC-OFF-STANDARD · nutrition_widgets.md is full of prohibited content
- Where the doc says it: `docs/widget_catalog/nutrition_widgets.md` throughout — visual values
  ("height `OmniTheme.buttonPrimaryHeight`", "square 96×96 tile", "40×40", "2 px thumb border +
  16 px corner badge", "fontSize: 9" style specs), control/gesture inventories (the FoodForm prop
  table, the field-by-field top-to-bottom list, the × overlay gating rules), step-by-step flows
  (the auto-show contract: "On dismiss, the host calls `NutritionPrimerState.markSeen()` and then
  pushes `NutritionScreen`"), and a regex literal (`^\d*\.?\d*$`).
- Standard: `docs/documentation_standard.md` §3.1–3.4 prohibits flows, visual presentation, control
  inventories, and restated numeric values.
- What a user would see: n/a (doc hygiene).
- Guard: none found: no doc-lint test located; searched `test/` glob for `documentation` — not done
  this run.
- Unsure: whether the standard's date predates this page's "Last reconciled 2026-07-26" header, i.e.
  whether the page is knowingly grandfathered.

`docs/nutrition.md` itself stays mostly within the standard (structure, invariants, test pointers);
its worst offenders are the entry-point tree (§3.1-adjacent but structural) and naming D-3/S-040
decisions, which I did not count as violations.

---

## 4 · Pattern matrix (from the code; shared components named)

| Screen | P1 top bar | P2 card header | P3 empty state | P4 locked/unavailable | P5 confirmation | P6 unsaved guard | P7 text/number entry | P8 bottom action | P9 sheets/modals | P10 theme tokens | P11 a11y | P12 charts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NutritionScreen | AppBar + `?` IconButton (`nutrition_primer_help`) | `OmniCardHeader` ('TODAY', 'Foods I Eat') | muted text "Your Foods I Eat list is empty…" | none | none | none | none on this screen | none (header pencil instead) | primer via `showModalBottomSheet` | `OmniTheme.colors.*`, `colorScheme.primary`; raw `fontSize: 13/16/22` on the target button + help icon | `Key`ed controls; `tooltip`s; no explicit text-scale handling seen | `CalorieRing` + `MacroDonutChart` (feature widgets) |
| AddFoodScreen | AppBar + `TabBar` (3 tabs) | none (tab chrome) | "No catalog foods available" / `No matches for "…"` / icon+"No custom foods yet" | bundled-food delete blocked via AlertDialog | `ConfirmationDialog.twoChoice` (food), bespoke `_DeleteGroupDialog` (category), silent (empty category, library-row remove) | none | search `TextField`; group-rename `TextField` (commit on blur+enter, triple fire) | `OmniBottomCTA` (tab-aware) | none | tokens throughout; `colorScheme.error` for destructive | `Key`s + `tooltip`s; 48dp thumb target is on NutritionScreen rows, not here | none |
| EditFoodScreen | AppBar 'Edit Food' | none | none | none | none (photo clear is instant) | none — auto-saves on blur | `FoodForm`: select-all on numeric fields, `TextCapitalization.words` on name, decimal keyboards | **none** (no CTA) | camera/gallery picker sheet (`food_form.dart:1099`) | tokens; no raw colours seen | `Key`s per field | none |
| NutritionTargetScreen | AppBar 'Daily Calorie Target' | none | empty field for unset target (hint '—') | none | none | none (back discards) | centred 36px number field via `SelectAllOnFocus`; validator | `OmniBottomCTA` 'Save' | none | tokens; raw `fontSize: 36/24/16` in the field style | `Key('calories_field')`; no semantics seen | none |
| NutritionTrendScreen | `OmniBackHeader` ('Nutrition' / 'Full history') | `OmniCardHeader` ('NUTRITION') | flat zero chart, no text (F7); 1-day inline card "1 day — log more to see a trend" | none | none | none | none | none | none | `OmniTheme.colorsForTheme(settingsState.appTheme)` — settings-reactive, not ambient | `Key`s; legend `buildLegendItem` text | `ScrollableTrendChart` + fl_chart `LineChart`, `ChartAxisHelper`, `EdgeAwareDateLabel`, dashed target line, `SegmentedButton` toggle |

Cells not checked: P4 for all screens — no locked/unavailable feature exists in the area (searched
the five screens for lock/disabled-by-permission patterns; only the water minus button disables at
0). P11 text-scale overflow: no `MediaQuery.textScaler` handling or `FittedBox` beyond the primer
CTA was seen; I did not run the app, so overflow behaviour at large text scales is unverified.
P9 for AddFoodScreen: the image-picker sheet lives in `FoodForm` (shared with EditFoodScreen), so
it is listed on both.

---

## Summary of counts

- Names checked against `lib/`: ~45; 1 stale name (`_CategoriesTab` → `_GroupsTab`).
- Findings: 6 STALE-DOC (F1–F6), 1 INCONSISTENT doc-vs-code invariant (F7), 5 NO-RULE (F8, F10–F13),
  2 INCONSISTENT behaviour (F9, and F7's kind), 1 DOC-OFF-STANDARD (F14).
- Not reported (watch surfaces, per brief): `lib/watch/`, `watch/` — untouched.
