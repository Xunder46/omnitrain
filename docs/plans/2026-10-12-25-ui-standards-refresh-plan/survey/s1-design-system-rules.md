# S1 — Rule-by-rule audit: docs/design_system.md + UI rules in docs/global_conventions.md

Scout sheet, 2026-10-12. Read-only. Method: every rule sentence in `docs/design_system.md`
and the UI rules in `docs/global_conventions.md` ("Theme tokens only", "Card chrome via
OmniSurface; card headers via OmniCardHeader"); each rule checked against `lib/` and `test/`.
Phone app only; `lib/watch/`, `watch/` excluded per common.md.

---

## BREAKS-RULE

### F1 · BREAKS-RULE · Shape rule: four TextButtons set no style at all (no explicit shape)
- Where the doc says it: `docs/design_system.md:293` "Every `FilledButton`, `OutlinedButton`, or `TextButton` MUST explicitly set `shape`. Never rely on Material 3 defaults." and `docs/design_system.md:383` "It must still set `shape: RoundedRectangleBorder(...)`" for dialog TextButtons.
- Where the code does it:
  - `lib/features/nutrition/add_food_screen.dart:968` — `TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('OK'))` — no `style:` at all (inside an AlertDialog for a non-deletable catalog food).
  - `lib/features/nutrition/add_food_screen.dart:1732` — `TextButton(onPressed: () => Navigator.of(context).pop(_cancelledSentinel), child: const Text('Cancel'))` — no `style:` (delete-group dialog).
  - `lib/widgets/pickers/metric_chooser_dialog.dart:44` — `TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))` — no `style:`.
  - `lib/widgets/pickers/metric_chooser_dialog.dart:109` — `TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))` — no `style:`.
- What a user would see: those four dialog buttons render with the Material 3 default pill (StadiumBorder) while every other dialog button in the app is a slightly-rounded rectangle.
- Guard: none found: searched `test/` for `StadiumBorder`, `shape.*explicit`, `buttonShape` — no matches.
- Unsure: whether Material 3 `TextButton` default in this app's `ThemeData` is overridden app-wide (checked `lib/app.dart` theme build only for ColorScheme; did not audit `buttonTheme`/`dialogTheme` overrides).

### F2 · BREAKS-RULE · "Do not use OutlinedButton inside dialogs" — modality picker does
- Where the doc says it: `docs/design_system.md:385` "Do not use `OutlinedButton` inside dialogs."
- Where the code does it: `lib/widgets/pickers/modality_picker_dialog.dart:18` returns a `Dialog(...)` whose only action is an `OutlinedButton` at line 40 (`child: const Text('Cancel')`).
- What a user would see: the modality picker's Cancel button is an outlined button inside a dialog, the one variant the doc forbids there.
- Guard: none found: searched `test/` for `modality_picker` dialog shape/action assertions — no test file named for it; searched `test/` for `OutlinedButton` dialog rules — none.
- Unsure: whether any test pins this dialog's button type (searched `test/` for `ModalityPickerDialog` — no matches).

### F3 · BREAKS-RULE · Raw `Card(` widgets bypass OmniSurface (3 sites)
- Where the doc says it: `docs/global_conventions.md` "Card chrome via `OmniSurface`" row: "Every outlined card in the app must route through `OmniSurface` ... Raw Flutter `Card(...)` widgets and raw `Text` widgets above outlined cards are not permitted."
- Where the code does it:
  - `lib/features/session/workout_session_list_view.dart:161` — `return Card(color: tileColors.surface.withOpacity(0.7), elevation: 2, ..., shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), ...)`
  - `lib/features/routine/routine_setup_screen.dart:354` — same pattern, radius 12, elevation 2.
  - `lib/features/routine/routine_setup_screen.dart:1113` — same pattern, radius 12, elevation 2, with an InkWell.
- What a user would see: routine/session block cards with a 12-dp rounding and Material elevation instead of the app's 20-dp surface radius + deep-shadow chrome; two card systems coexist.
- Guard: none found: searched `test/` for raw-`Card(` bans (`Card(`, `OmniSurface` contract) — `test/` has no card-chrome contract test; `switch_consistency_contract_test.dart` covers switches only.
- Unsure: whether these three `Card(` sites are intentionally exempted somewhere (no exemption passage found in `docs/design_system.md` or `docs/global_conventions.md`).

### F4 · BREAKS-RULE · `_SectionHeader` raw-Text section headers survive in DaySessionListScreen
- Where the doc says it: `docs/design_system.md:159` "Every section / card header in the app routes through `OmniCardHeader` ... raw `Text` widgets above outlined cards are **not permitted**"; `docs/global_conventions.md` "Per-screen `_SectionHeader` / `_SectionLabel` / `_SummaryCard` / `_MeasurementRow` style widgets have been migrated to these primitives."
- Where the code does it: `lib/features/calendar/day_session_list_screen.dart:406-421` — `class _SectionHeader extends StatelessWidget { ... Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: OmniTheme.colors.textSecondary, letterSpacing: 0.5)) }`, used at lines 130, 147, 173 (`'Completed'`, `'Planned'`, `'In Progress'`).
- What a user would see: the day session list's section labels are bolder, tighter-tracked and brighter than every other section eyebrow in the app, which uses the quiet `OmniCardHeader` style.
- Guard: `test/header_standardization_test.dart` covers this screen only for `OmniBackHeader` presence (group `OmniBackHeader presence – DaySessionListScreen`, line 345); no test pins `_SectionHeader` typography — the D-1 contract test does not reach it.
- Unsure: whether `_SectionHeader` here is counted as "sheet/title chrome" (the D-10 exception covers only the home HUB/TRAIN and onboarding step label — not this screen).

### F5 · BREAKS-RULE · Hardcoded colours outside the token files (6 sites)
- Where the doc says it: `docs/design_system.md:190` "Modality accent colors must come from `lib/core/constants/modality_colors.dart` (single source of truth) and must not be hardcoded in screens/components"; `docs/global_conventions.md` "Theme tokens only ... Never hardcode colors"; `docs/design_system.md:66` "Values live in `lib/core/constants/omni_theme.dart` and nowhere else."
- Where the code does it (raw `Color(0x…)` outside `omni_theme.dart`/`modality_colors.dart`/`app.dart`'s ColorScheme role mapping):
  - `lib/features/session/workout_session_global_timer.dart:694` and `:744` — `Container(color: const Color(0xBF000000))` (scrim)
  - `lib/features/session/workout_session_global_timer.dart:808` — `color: const Color(0xFF1A1A2E)`
  - `lib/features/onboarding/onboarding_screen.dart:327` — `const Color(0xFF060B14)` as the Get-Started button's foreground
  - `lib/features/calendar/calendar_screen.dart:483` — `return Color(0xFF000000 | value).withOpacity(0.14);`
  - `lib/widgets/cards/energy_tile.dart:340` — `color: Color(0x4D000000), // black @ 30%` (live-dot shadow)
  - `lib/widgets/pickers/modality_picker_dialog.dart:22` — `color: Color(0xFF1a1a1a)` (dialog background)
  - `lib/core/constants/home_tiles.dart:102` — `accentColor: Color(0xFF9E9E9E)` (Routines tile grey; the other five tiles use `ModalityColors.*`)
- What a user would see: those surfaces keep fixed colours that do not follow the selected theme (most visible in the modality picker's near-black dialog on a light-leaning theme, and the Routines tile grey).
- Guard: `test/switch_consistency_contract_test.dart` group `Switch consistency contract`, test `no switch call site hardcodes its colours` (line 88) — switches only; no guard for these sites. `test/palette_legibility_contract_test.dart` iterates themes, not call sites.
- Unsure: whether `app.dart`'s ~104 per-theme `ColorScheme` hex literals count as violations of "omni_theme.dart and nowhere else" — they are the Material role mapping the doc's own "Adding or changing a theme" section requires, but the file is `lib/app.dart`, not `omni_theme.dart` (filed separately as F14).

### F6 · BREAKS-RULE · Routine-setup bottom row-pair bypasses OmniBottomCTA's shared insets
- Where the doc says it: `docs/design_system.md:345-352` "Every screen that exposes a primary bottom action **must** use `OmniBottomCTA` ... Forbidden patterns — ❌ `Positioned(... bottom: 0, child: FilledButton(...))`".
- Where the code does it: `lib/features/routine/routine_setup_screen.dart:532-534` — `Widget _buildBottomActions(...) { return Positioned(left: 0, right: 0, bottom: 0, child: DecoratedBox(... child: SafeArea(top: false, minimum: const EdgeInsets.fromLTRB(16, 24, 16, 16), child: Row(...OutlinedButton 'Cancel' + FilledButton 'Save'...))))` (buttons at lines 556/580).
- What a user would see: the routine editor's Save/Cancel pair sits at hand-rolled insets (a `minimum` LTRB, not `bottomCTAHorizontalPadding`/`bottomCTAVerticalBottomPadding`), so its bottom anchor is not guaranteed to match `OmniBottomCTA` screens.
- Guard: none found: searched `test/` for `OmniBottomCTA` contract/forbidden-pattern tests — no test file named for it; `navigation_contract_enforcement_test.dart` covers routing, not CTA hosting.
- Unsure: whether a Cancel+Save row-pair counts as "a primary bottom action" under the rule (the doc's variant table legitimises row-pairs but the MANDATORY CTA rule names no row-pair exemption; `OmniBottomCTA` itself has no two-button API — checked its constructor, `label`/`onPressed`/`isDestructive`/`buttonKey` only).

---

## INCONSISTENT

### F7 · INCONSISTENT · Two dialog-button idioms for the same job
- Where the code does it: `lib/widgets/dialogs/confirmation_dialog.dart:155-186` sets explicit `shape` on every action button; `lib/features/nutrition/add_food_screen.dart:968,1732` and `lib/widgets/pickers/metric_chooser_dialog.dart:44,109` set no style at all (see F1).
- What a user would see: dialog buttons are rounded rectangles in some dialogs and pills in others.
- Guard: `test/confirmation_dialog_guard_test.dart` pins the shared component; nothing pins the ad-hoc dialogs.
- Unsure: nothing further.

---

## CONFLICT

### F8 · CONFLICT · "Cyan/teal accents indicate interactivity" vs the six-theme roster
- Where the doc says it: `docs/design_system.md:191` "3. **Cyan/teal accents** indicate interactivity or active state — never decorative filler" — while the same doc's Theme Roster (line 63) ships Forge & Ember ("controlled amber"), Malachite Core ("grounded and mineral ... green"), Crimson Dojo (martial red) whose `primary` is not cyan/teal and is the CTA/active accent per the Emphasis Tiers table ("`primary` remains the primary-action accent used for CTAs and active indicators", line 105).
- What a user would see: nothing broken in-app; the written rule describes only the cyan-era palette and contradicts the roster it sits under.
- Guard: n/a (doc-internal).
- Unsure: nothing further.

### F9 · CONFLICT · design_system.md header table vs the D-1 contract it declares
- Where the doc says it: `docs/design_system.md:159` "Every section / card header in the app routes through `OmniCardHeader`" vs the same doc's own per-screen table (lines 176-184) listing Stats headers "the Instruments list's four title-case headers, `Resistance`, `Cardio`, `Isometric`, `Sports`" — title-case, while the D-1 contract and `OmniCardHeader` render uppercase-feel `labelSmall` eyebrows (checked `lib/widgets/layout/omni_card_header.dart:73-79`: `labelSmall` + `letterSpacing: 2.0` + `w600` + `textMuted`; no uppercasing in the widget — title text is used as given).
- What a user would see: if the Stats headers are passed title-case strings, they render title-case in the same style slot that carries uppercase labels elsewhere — two visual dialects of "section header".
- Guard: `test/instrument_list_screen_test.dart` groups `S-1001`/`S-1011`/`S-1015` pin the four headers' presence; did not check whether they pin the exact casing.
- Unsure: the actual title strings passed by `lib/features/stats/widgets/instrument_list.dart` (not viewed).

---

## STALE-DOC

### F10 · STALE-DOC · Press Scale 0.96 — token is 0.9
- Where the doc says it: `docs/design_system.md:250` "| Press Scale | 0.96 |" and the code sample at line 310 `scale: _isPressed ? OmniTheme.pressedScale : 1.0,  // 0.96`.
- Where the code does it: `lib/core/constants/omni_theme.dart:488` `static const double pressedScale = 0.9;` (used by `lib/widgets/cards/energy_tile.dart:112`, `lib/widgets/cards/maintenance_tile.dart:35`, `lib/widgets/common/home_logo_button.dart:181`).
- What a user would see: tiles press in to 90% scale, slightly deeper than the documented 96%.
- Guard: none found: searched `test/` for `pressedScale` — no matches.
- Unsure: nothing further.

### F11 · STALE-DOC · "Active Border — White @ 15%, 2px" shadow token does not exist
- Where the doc says it: `docs/design_system.md:243` "| Active Border | White @ 15%, 2px width | Selected/active tile indicator |".
- Where the code does it: active tiles draw `OmniTheme.colors.surfaceBorder` at `OmniTheme.surfaceBorderWidth` (1.0) — `lib/widgets/cards/energy_tile.dart:140-143`; searched `lib/` for `activeBorder`, `0x26FFFFFF`, `white.*0.15`, `width: 2` — no white 15% 2-px active border anywhere (the four `width: 2` hits are an empty-state circle, a number field border and similar, none white-on-tile).
- What a user would see: nothing — the documented selected-tile border treatment is not in the code.
- Guard: none found: searched `test/` for active-border assertions — none.
- Unsure: whether another widget (not `EnergyTile`) implements it; searched all of `lib/` for the value pattern.

### F12 · STALE-DOC · "Values live in omni_theme.dart and nowhere else" — app.dart holds ~104 theme hex literals
- Where the doc says it: `docs/design_system.md:66` "**Values live in `lib/core/constants/omni_theme.dart` and nowhere else.**"; `docs/theme_and_settings.md` ("Available Themes"): "the values themselves live only in `lib/core/constants/omni_theme.dart`".
- Where the code does it: `lib/app.dart:204-374` — a per-theme `ColorScheme` role mapping with ~104 `Color(0x…)` literals (`primaryContainer`, `tertiary`, `surfaceContainer*`, `inverseSurface`, `errorContainer`, …) plus `outlineGround = Color(0x66FFFFFF)` at line 204.
- What a user would see: nothing directly; a reader tuning "the palette" from the doc's pointer would miss a whole second value file.
- Guard: `test/palette_legibility_contract_test.dart` and `test/color_scheme_contrast_test.dart` gate the values themselves, not their location.
- Unsure: whether `docs/theme_and_settings.md`'s own "Flagged, not owned here" block intends to cover this (it flags only the copied enum/token table in that doc, not app.dart).

### F13 · STALE-DOC · "Deprecated widgets redirect — old widgets are stubs" — no widget stubs found
- Where the doc says it: `docs/design_system.md:415` "3. **Deprecated widgets redirect** — old widgets are stubs pointing to canonical implementations".
- Where the code does it: not found for widgets: searched `lib/` for `@Deprecated|Deprecated:|deprecated` — hits are only data-model fields (`lib/data/models/models.dart:1948,1951`), state methods (`lib/state/food_library_state.dart:1069,1086,1139`) and two deprecated `OmniTheme` constants (`lib/core/constants/omni_theme.dart:637,649`, both rest-timer offsets). No widget stub class found.
- What a user would see: n/a.
- Guard: n/a.
- Unsure: whether a stub widget exists under a name not containing "deprecated"; searched only the deprecation markers.

---

## NO-RULE

### F14 · NO-RULE · Per-theme ColorScheme role mapping lives in lib/app.dart with no doc pointer
- Where the code does it: `lib/app.dart:196-374` — `switch (theme)` supplying the full Material role set per theme, commented "Iteration 2: D-8 through D-12".
- What a user would see: n/a (structure).
- Guard: `test/color_scheme_contrast_test.dart` exists (file seen in `test/` listing; groups not read).
- Unsure: whether any doc names `lib/app.dart` as this mapping's home — searched `docs/design_system.md` and `docs/theme_and_settings.md` for "app.dart" as the mapping location: not found.

---

## NO-GUARD

### F15 · NO-GUARD · Shape rule (MANDATORY) has no test
- Where the doc says it: `docs/design_system.md:293` "Every `FilledButton`, `OutlinedButton`, or `TextButton` MUST explicitly set `shape`."
- Guard: none found: searched `test/` for `StadiumBorder`, `shape.*explicit`, `buttonShape` — no matches. The rule holds today except for F1's four sites; nothing would fail if a new pill button shipped.
- Unsure: nothing further.

### F16 · NO-GUARD · 48-dp touch-target minimum is asserted in prose, tested only once
- Where the doc says it: `docs/design_system.md:222` "Generous padding and touch targets — minimum 48dp tap areas"; `docs/design_system.md:432` "Touch targets — minimum 48x48 dp for all interactive elements".
- Guard: only `test/pr6_routine_session_entry_navigation_test.dart:824` ("play glyph touch target meets the platform accessibility minimum") — one control, one screen. No app-wide contract test found: searched `test/` for `tapTargetSize|48.*tap|touch target|kMinInteractiveDimension`.
- Unsure: nothing further.

### F17 · NO-GUARD · "Never use drop shadows on text" / "No animations in the critical path" / "No bouncing, no elastic overshoots"
- Where the doc says it: `docs/design_system.md:236-238, 262-266`.
- Guard: none found: searched `test/` for shadow-on-text, critical-path animation and curve assertions (`Curves` contract, `easeOutBack`/`elastic` bans) — no matches.
- Unsure: nothing further.

---

## DOC-OFF-STANDARD (design_system.md vs documentation_standard.md §6.1 — values, change-log, to-dos)

§6.1 exempts design_system.md from §3.2 (visual rules) but explicitly NOT from §3.4: "No sizes, spacings, radii, durations, or opacities. Name the token and say what it is for; never state what it equals. No change-log narratives and no open to-do lists."

### F18 · DOC-OFF-STANDARD · Spacing & Layout table restates five token values
- Where the doc says it: `docs/design_system.md:196-202` — "| Surface Border Radius | 20.0 |", "| Border Width | 1.0 |", "| Energy Core Size | 78.0 |", "| Zen Halo Size | 160.0 |", "| Halo Stroke Width | 7.0 |".
- Code owners: `lib/core/constants/omni_theme.dart:471-472` (`surfaceBorderRadius`, `energyCoreSize`, `surfaceBorderWidth`), `:525-527` (`zenHaloStrokeWidth`, `zenHaloSize`).
- Guard: n/a (doc-standard finding).

### F19 · DOC-OFF-STANDARD · Depth & Shadow table restates alphas, blurs, offsets
- Where the doc says it: `docs/design_system.md:231-235` — "Black 55%, blur 30, offset (0, 14)", "blur 24, spread 0, 35% opacity", "White @ 15%, 2px width".
- Code owners: `lib/core/constants/omni_theme.dart:441-468` (`deepShadow`, `glowShadow`). (The Active Border row is separately stale — F11.)

### F20 · DOC-OFF-STANDARD · Interaction & Animation table restates six durations/scales
- Where the doc says it: `docs/design_system.md:249-255` — "0.96", "180ms", "easeInOut", "2800ms", "1200ms", "3000ms", "8000ms".
- Code owners: `lib/core/constants/omni_theme.dart:486-488, 512-521` (`animationDuration`, `animationCurve`, `pressedScale`, `splashDuration`, `strokeDrawDuration`, `breathingDuration`, `rotationDuration`). (0.96 is also wrong — F10.)

### F21 · DOC-OFF-STANDARD · Button tables restate geometry and paddings
- Where the doc says it: `docs/design_system.md:277-283` — "56 dp", "12", "8", "≥48 dp", "60 × 60 dp", "`symmetric(horizontal: 24)`", "`symmetric(vertical: 16)`", "`symmetric(horizontal: 12, vertical: 8)`"; `docs/design_system.md:377` "Both use `OmniTheme.buttonUtilityRadius` (8.0)"; `docs/design_system.md:352-355` "inset by `OmniTheme.bottomCTAHorizontalPadding` (16)" and "`OmniTheme.bottomCTAVerticalBottomPadding` (16)"; code sample at 296-305 hardcodes `BorderRadius.circular(OmniTheme.buttonBorderRadius)` inside a literal example (copied implementation content, §3.5).
- Code owners: `lib/core/constants/omni_theme.dart:542-599` (button tokens, bottom-CTA tokens).

### F22 · DOC-OFF-STANDARD · Large-screen column restates the two width constants
- Where the doc says it: `docs/design_system.md:210-216` — "`OmniTheme.kColumnMinActivationWidth` = 500 dp", "`OmniTheme.kColumnMaxWidth` = 480 dp".
- Code owners: `lib/core/constants/omni_theme.dart:671,684`.

### F23 · DOC-OFF-STANDARD · Outline-role section restates alphas and contrast ratios
- Where the doc says it: `docs/design_system.md:398-401` — "`outline` (40% white) achieves ≥3:1", "`outlineVariant` (19% white) achieves ≥1.8:1".
- Code owners: `lib/app.dart:204-205,213-215` (`outlineGround` 0x66, `outlineVariantGround` 0x30, with D-8/D-9 comments); thresholds live in `test/palette_legibility_contract_test.dart`.

### F24 · DOC-OFF-STANDARD · Home-tile colour rule restates opacities and pixel widths
- Where the doc says it: `docs/design_system.md:192` — "primary ~30%, secondary ~15%", "1px white top rim highlight and 1px black bottom inner shadow".
- Code owners: `lib/widgets/cards/energy_tile.dart:20` (`secondaryFillOpacity = 0.15`), `:296-318` (rim/shadow `Positioned` heights and opacities).

### F25 · DOC-OFF-STANDARD · Typography tables restate letter-spacing values
- Where the doc says it: `docs/design_system.md:135-140` — "Letter-spacing 3.0", "0.4", "2.0"; `docs/design_system.md:170` header-contract table "Letter spacing | `2.0`".
- Code owners: `lib/core/constants/omni_theme.dart:477-478` (`titleLetterSpacing`, `headerLetterSpacing`); `lib/widgets/layout/omni_card_header.dart:77` (`letterSpacing: 2.0`).

### F26 · DOC-OFF-STANDARD · Accessibility section restates WCAG ratios and dp sizes
- Where the doc says it: `docs/design_system.md:429-434` — "4.5:1 for body, 3:1 for large text", "48x48 dp".
- Code owners: thresholds in `test/palette_legibility_contract_test.dart`; touch-target floor is platform (`kMinInteractiveDimension`).

### F27 · DOC-OFF-STANDARD · Change-log narrative and PR annotations
- Where the doc says it:
  - `docs/design_system.md:47-49` — "A splash screen was added and then commented out. The reasoning: 'I don't want to look at the splash logo...'" (change-log narrative; the code state itself is `lib/app.dart:128-129` "Splash screen temporarily disabled - showing home screen directly").
  - `docs/design_system.md:184` — "labelled `OutlinedButton.icon` in actions — PR 3 / S-002" (delivery annotation; same narrative also in `lib/features/nutrition/widgets/calorie_ring_card.dart:193` comment).
  - `docs/design_system.md:264` — "| Splash Duration | 2800ms | Brand animation (deferred) |" ("deferred" = scheduled-change/roadmap annotation, §3.7/§3.6 flavour).
  - `docs/design_system.md:359-363` — "Destructive confirmations (delete, discard, remove — 20 sites)", "Routine confirmations (2 sites)", "on all 22 sites" (site counts copied from a survey; drift-prone numeric claims with no owner).
- Guard: n/a.

### F28 · DOC-OFF-STANDARD · Header-contract table restates style values
- Where the doc says it: `docs/design_system.md:166-175` — "`theme.textTheme.labelSmall`", "`FontWeight.w600`", "`2.0`", "`maxLines: 1, overflow: TextOverflow.ellipsis`" (a field list mirroring `OmniCardHeader`'s implementation, §3.5 flavour).
- Code owner: `lib/widgets/layout/omni_card_header.dart:73-79`.

---

## Guards verified to exist (named in the doc, confirmed on disk this run)

- `test/palette_legibility_contract_test.dart` — checks 18a/18b/18c comments at lines 255-295; iterates themes.
- `test/utils_test.dart:1357` — group `Intensity ramp spacing (T-1)`.
- `test/emphasis_tier_contract_test.dart`, `test/switch_consistency_contract_test.dart`, `test/screen_overflow_contract_test.dart`, `test/navigation_contract_enforcement_test.dart`, `test/header_standardization_test.dart` (S-001c at 925/1014/1051, S-011 at 1848), `test/mix_layer_screen_test.dart` (S-1601 at 816, S-1612 at 1674), `test/signals_layer_screen_test.dart` (S-1701 at 552, S-1704 at 784, S-1716 at 1302), `test/instrument_list_screen_test.dart` (S-1001 at 534, S-1011 at 697, S-1015 at 878), `test/fuel_row_screen_test.dart`, `test/widgets/energy_tile_test.dart`, `test/confirmation_dialog_guard_test.dart`, `test/nutrition_target_button_test.dart` — all present in the `test/` listing.
- `lib/` symbols named by the doc, all found: `OmniBottomCTA` (`lib/widgets/layout/omni_bottom_cta.dart`), `OmniCardHeader` (`lib/widgets/layout/omni_card_header.dart`), `OmniSurface` (`lib/widgets/layout/omni_surface.dart`), `OmniGradientBackground` (`lib/widgets/layout/omni_gradient_background.dart`), `ConfirmationDialog` (`lib/widgets/dialogs/confirmation_dialog.dart`), `EnergyTile`/`EnergyCore` (`lib/widgets/cards/`), `ZenHaloPainter`/`AnimatedZenHalo` (`lib/widgets/logo/`), `HomeTileConfig.isSecondary` (`lib/core/constants/home_tiles.dart:30`), `OmniTheme.intensityRampFor` (`omni_theme.dart:105`), `macroChart` palette with `protein/fiber/chartLabelDark` slots (`omni_theme.dart:25-29`), `feelingColor`/`effortTileTextColor` (`lib/core/utils/session_feeling_utils.dart:17,45`), `kColumnMinActivationWidth`/`kColumnMaxWidth` (`omni_theme.dart:671,684`), `Key('nutrition_target_button')` (`lib/features/nutrition/nutrition_screen.dart:204`), `ModalityColors` (`lib/core/constants/modality_colors.dart` — the five modality hexes appear nowhere else in `lib/`, searched `0xFF43A047|0xFF5B9BD5|0xFFE63946|0xFFFFA726|0xFF885ED1`).
- Reduced-motion rule ("respect `MediaQuery.disableAnimations`"): implemented in `lib/widgets/common/home_logo_button.dart:85` and `lib/widgets/common/interactive_logo.dart:45,53,61,70`; no test found that pins it (searched `test/` for `disableAnimations` — no matches) → the rule is also NO-GUARD (folded here to keep the sheet short).
- ConfirmationDialog two-tier matches the doc: error fill when `isDestructive` (`confirmation_dialog.dart:180-186`), dismissal-first ordering (comment "Dismissal action first", line 154), `barrierDismissible: true` (lines 66, 96).

## Not covered / notes

- `docs/global_conventions.md` non-visual rules (units, effort-kind keying, timestamps, reuse-the-owner, initState-notify, rest count-up) were skipped as out of the brief's "UI rules" scope; their named guards (`initstate_notify_contract_test.dart`, `rest_is_count_up_contract_test.dart`, …) were seen in the `test/` listing but not opened.
- No hex literals exist in `docs/design_system.md` itself (searched `#[0-9a-fA-F]{3,8}` — no matches); the §6.1 breaches are numeric values, not hex.
- `StadiumBorder` appears in `lib/` only inside comments (`nutrition_primer_sheet.dart:29,123`, `stats_primer_sheet.dart:24,121`) — no code use.
