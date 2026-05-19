# Feature: Typography & Text Scale Audit

## Overview

A TestFlight session on an iPhone 16 Pro with iOS Dynamic Type at default-middle revealed widespread
UI breakage: oversized fonts, clipped button labels, rows that don't fit their containers, and
layouts that look broken. Lowering Dynamic Type to minimum restores the intended look, confirming
the issue is typography misuse and the total absence of a text-scale clamp — not a device or layout
bug.

This effort runs after the centralized route system & transition bleed-through fix has merged. The
`lib/core/navigation/` module is already present and confirmed clean (no typography issues).

Two coordinated tracks:
1. **Code audit** — exhaustive sweep of `lib/features/` and `lib/widgets/` for typography
   antipatterns; fix all of them in place.
2. **Global text scale clamp** — one clamp at `MaterialApp` root; not re-implemented per screen.

## Acceptance Criteria

- [ ] A single global text scale clamp (0.9–1.3) is applied at `MaterialApp` root; the bounds are
      defined in exactly one place (`OmniTheme`)
- [ ] No `TextStyle(fontSize: <literal>)` remains in `lib/features/` or `lib/widgets/` except where
      an inline comment explicitly justifies the exception (e.g., chart axis labels)
- [ ] Every text element inside a fixed-size container has an explicit overflow strategy:
      `maxLines` + `TextOverflow.ellipsis`, or `FittedBox`, or `softWrap: true` with a flexible parent
- [ ] Every button label that sits inside a `OmniTheme.buttonPrimaryHeight` (56 dp) container uses
      `FittedBox(fit: BoxFit.scaleDown)` so labels shrink rather than clip
- [ ] All horizontal `Row` widgets containing `Text` children have the text side wrapped in
      `Expanded` or `Flexible`
- [ ] All six themes verified at minimum, default, and upper-clamp text scale on iOS and Android;
      screenshots committed to the audit report
- [ ] Active session logger, settings, calendar, profile, stats, onboarding, exercise editor,
      routine setup, splash, free-training sheet all visually verified across the clamp range
- [ ] Audit report committed at `.github/agents/docs/typography-audit-report.md`
- [ ] New tests: dense-screen overflow at clamp range, global clamp boundary behaviour, button
      label fit (all four button variants), bottom-sheet overflow at upper-clamp scale
- [ ] All existing widget tests pass after the audit; any test asserting on text-scale-dependent
      positioning is flagged in the audit report
- [ ] `.github/agents/docs/design_system.md` updated with the exhaustive typography rule set
- [ ] `.github/agents/docs/widget_catalog.md` updated where component typography behaviour changed
- [ ] `.github/agents/docs/typography_contract.md` created explaining the clamp, its bounds, and
      the single-point-of-configuration rule
- [ ] Default-scale rendering is visually unchanged — this is not a redesign

---

## Pre-Audit Inventory

### Hardcoded `fontSize` literal violations — full file × line inventory

The grep was run against the post-centralized-route-refactor source tree.

| File | Lines | Literal values |
|------|-------|----------------|
| `lib/app.dart` | 54, 59 | 18, 18 — custom textTheme `labelSmall`/`labelLarge` overrides |
| `lib/features/home/home_screen.dart` | 176, 502, 644 | 18, 20, 12 |
| `lib/features/onboarding/onboarding_screen.dart` | 179, 190, 245, 254, 287, 296, 340, 463, 478, 523 | 40, 18, 26, 14, 26, 14, 16, 15, 13, 15 |
| `lib/features/calendar/calendar_screen.dart` | 262, 297, 432, 486, 568, 586, 658, 668 | 17, 11, 12, 11, 13, 13, 13, 30 |
| `lib/features/calendar/day_session_list_screen.dart` | 418, 436, 538, 547, 554, 744, 762 | 15, 13, 14, 12, 12, 16, 12 |
| `lib/features/session/session_summary_screen.dart` | 1170, 1194, 1202, 1242 | 13, 11, 11, 22 |
| `lib/features/session/workout_session_global_timer.dart` | 193, 484, 672, 690 | 11, 11, 12, 12 |
| `lib/features/period/create_period_screen.dart` | 147, 157, 168, 186, 208, 405 | 12, 12, 13, 12, 13, 14 |
| `lib/features/period/period_list_screen.dart` | 57, 199, 215, 230, 252 | 15, 14, 11, 12, 10 |
| `lib/features/profile/profile_screen.dart` | 208 | 12 |
| `lib/features/profile/widgets/measurement_history_chart_sheet.dart` | 455 | 10 — chart axis |
| `lib/features/routine/my_routines_screen.dart` | 101, 113, 144, 152 | 24, 16, 16, 12 |
| `lib/features/splash/omni_splash_screen.dart` | 118 | 24 |
| `lib/features/home/maintenance_placeholder_screen.dart` | 56, 74 | 24, 16 |
| `lib/features/settings/settings_screen.dart` | 153, 196, 214, 228, 555, 637, 677, 687, 773, 815 | 12, 13, 13, 13, 10, 11, 15, 12, 13, 14 |
| `lib/features/stats/stats_screen.dart` | 205, 293, 339, 363, 474, 513, 545, 590, 627 | 11, 11, 10★, 9★, 11, 10★, 9★, 11, 13 |
| `lib/widgets/cards/energy_tile.dart` | 143 | 16 |
| `lib/widgets/cards/maintenance_tile.dart` | 74 | 15 |
| `lib/widgets/pickers/modality_picker_dialog.dart` | 34, 114, 123 | 18, 14, 12 |

★ Stats chart axis labels at 9–10 dp are the only justified exceptions. They remain as literals
with an inline comment: `// chart axis label — exempt from textTheme rule; scaling would
// destroy chart readability at any text scale within the clamped range.`

### Sizing tokens that need `FittedBox` on their labels

The following widgets use `OmniTheme.buttonPrimaryHeight` (56 dp) as a fixed height. Every text
label inside must be wrapped in `FittedBox(fit: BoxFit.scaleDown)`:

| File | Context |
|------|---------|
| `lib/widgets/layout/omni_bottom_cta.dart` | Full-width CTA button |
| `lib/features/home/home_screen.dart` line 521 | Free Training start button |
| `lib/features/session/workout_session_list_view.dart` line 287 | Session action button |
| `lib/features/onboarding/onboarding_screen.dart` line 319 | Continue/Start button |
| `lib/features/profile/profile_screen.dart` line 594 | Profile CTA |
| `lib/features/profile/widgets/measurement_history_chart_sheet.dart` line 200 | Sheet CTA |
| `lib/features/calendar/day_session_list_screen.dart` lines 455, 1002 | Day actions |
| `lib/features/routine/routine_setup_screen.dart` lines 545, 566 | Routine action pair |
| `lib/widgets/pickers/exercise_picker_dialog.dart` line 206 | Dialog CTA |

---

## Proposed `textTheme` Role Mapping

The `buildTheme` function in `lib/app.dart` currently defines only `labelSmall` and `labelLarge`.
It must be extended to cover every role referenced in the app so literals can be replaced. The
following mapping drives Phase 1:

| M3 Role | Suggested size (dp) | Current literal(s) it replaces |
|---------|--------------------|---------------------------------|
| `displayLarge` | 40 | Onboarding hero heading |
| `displayMedium` | 30–32 | Calendar month stat large number |
| `headlineLarge` | 26 | Onboarding feature page title |
| `headlineMedium` | 24 | Splash, routine empty-state header, maintenance placeholder |
| `headlineSmall` | 22 | Session summary PR value |
| `titleLarge` | 20 | Free Training sheet title |
| `titleMedium` | 18 | Home greeting, onboarding sub-title, modality picker title |
| `titleSmall` | 16 | Home screen action labels, routine tile labels, energy tile |
| `bodyLarge` | 15 | Period list name, maintenance tile, settings section header |
| `bodyMedium` | 14 | Onboarding copy, exercise list items, settings row value |
| `bodySmall` | 13 | Muted supporting labels across calendar, session summary, settings |
| `labelMedium` | 12 | Dense inline labels, calendar date numbers, session timer fine print |
| `labelSmall` | 11 | Instrumentation-density labels (session timer, stats summary) |

Chart axis labels (9–10 dp) are **not** mapped to textTheme roles and remain as literal constants
with a justification comment.

---

## Iteration 1

### Phase 1: Typography Token Foundation (@developer)

**Goal**: Give feature code a single correct path — `theme.textTheme.<role>?.copyWith(...)` —
before touching the call sites.

1. [ ] Add `kTextScaleMin` and `kTextScaleMax` constants to `lib/core/constants/omni_theme.dart`
       (values: 0.9 and 1.3)
2. [ ] Extract `buildTextTheme()` static method (or standalone function) into
       `lib/core/constants/omni_theme.dart` that returns a complete `TextTheme` covering all 13
       roles in the mapping table above. The function is called by `buildTheme` in `lib/app.dart`
       so the textTheme is assembled in one place.
3. [ ] Update `buildTheme` in `lib/app.dart` to call `buildTextTheme()` instead of the inline
       partial override that currently sets only `labelSmall` and `labelLarge`.
4. [ ] Remove the inline `textTheme` override from `MyApp.build` (`app.dart` lines 50–62); the
       `buildTheme` call now owns the full textTheme.
5. [ ] Verify `flutter analyze` passes and `flutter test` is green before moving to Phase 2.

**Files touched:**
- `lib/core/constants/omni_theme.dart`
- `lib/app.dart`

---

### Phase 2: Global Text Scale Clamp (@developer)

**Goal**: One `MediaQuery` wrapper in `MaterialApp.builder` clamps every descendant's
`textScaler`. Nothing else in the app changes.

1. [ ] Update `MaterialApp.builder` in `lib/app.dart` to:
   ```dart
   builder: (context, child) {
     final mq = MediaQuery.of(context);
     final rawScale = mq.textScaler.scale(1.0);
     final clamped = rawScale.clamp(OmniTheme.kTextScaleMin, OmniTheme.kTextScaleMax);
     return MediaQuery(
       data: mq.copyWith(textScaler: TextScaler.linear(clamped)),
       child: GestureDetector(
         behavior: HitTestBehavior.translucent,
         onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
         child: OmniGradientBackground(child: child ?? const SizedBox.shrink()),
       ),
     );
   },
   ```
2. [ ] Confirm the clamp is **not** duplicated anywhere else in `lib/` — grep for `textScaler`
       and `textScaleFactor` and confirm zero usages outside `app.dart`.
3. [ ] Run `flutter test` to confirm all tests still pass with the clamp in place.

**Files touched:**
- `lib/app.dart`

---

### Phase 3: Feature & Widget Audit (@developer)

Work through each file in the inventory. For each file, apply all applicable fix categories in a
single pass so the file is fully compliant after one edit.

**Antipattern categories:**

- **A** — `TextStyle(fontSize: N)` → `theme.textTheme.<role>?.copyWith(...)`. Obtain `theme` via
  `Theme.of(context)` if not already in scope.
- **B** — Text in fixed-size container with no overflow strategy → add
  `maxLines: 1, overflow: TextOverflow.ellipsis` (or `maxLines: 2` where wrapping is appropriate),
  or wrap in `FittedBox(fit: BoxFit.scaleDown)`.
- **C** — Button label without fit strategy inside a `OmniTheme.buttonPrimaryHeight` container →
  wrap the `Text` child in `FittedBox(fit: BoxFit.scaleDown)`.
- **D** — `Row` with a `Text` child that has no width budget → wrap the `Text` in
  `Expanded` or `Flexible(child: Text(...))`.
- **E** — Chart axis label at 9–10 dp → keep literal, add inline justification comment.

#### 3.1 — `lib/app.dart`
- [A] Lines 54, 59: Remove the inline `textTheme` override (done in Phase 1, step 4).

#### 3.2 — `lib/features/home/home_screen.dart`
- [A] Line 176 (18) → `titleMedium`
- [A] Line 502 (20) → `titleLarge`
- [A] Line 644 (12) → `labelMedium`
- [C] Line 521 button label → `FittedBox`
- [D] Audit all `Row` children containing `Text` for missing `Expanded`/`Flexible`

#### 3.3 — `lib/features/onboarding/onboarding_screen.dart`
- [A] Line 179 (40) → `displayLarge`
- [A] Line 190 (18) → `titleMedium`
- [A] Line 245 (26) → `headlineLarge`
- [A] Line 254 (14) → `bodyMedium`
- [A] Line 287 (26) → `headlineLarge`
- [A] Line 296 (14) → `bodyMedium`
- [A] Line 340 (16) → `titleSmall`
- [A] Line 463 (15) → `bodyLarge`
- [A] Line 478 (13) → `bodySmall`
- [A] Line 523 (15) → `bodyLarge`
- [B] Large heading text (was 40dp) in top card area — ensure `softWrap: true` and parent is
  scrollable or has a flexible height, not a hard `SizedBox`.
- [C] Line 319 button label → `FittedBox`

#### 3.4 — `lib/features/calendar/calendar_screen.dart`
- [A] Line 262 (17) → `titleMedium`
- [A] Lines 297, 432, 486 (11, 12, 11) → `labelSmall` / `labelMedium`
- [A] Lines 568, 586, 658 (13) → `bodySmall`
- [A] Line 668 (30) → `displayMedium`
- [B] All text in fixed calendar cell containers (cells have a fixed `width`/`height`) →
  `maxLines: 1, overflow: TextOverflow.ellipsis`

#### 3.5 — `lib/features/calendar/day_session_list_screen.dart`
- [A] Line 418 (15) → `bodyLarge`
- [A] Line 436 (13) → `bodySmall`
- [A] Line 538 (14) → `bodyMedium`
- [A] Lines 547, 554 (12) → `labelMedium`
- [A] Line 744 (16) → `titleSmall`
- [A] Line 762 (12) → `labelMedium`
- [C] Lines 455, 1002 button labels → `FittedBox`
- [D] Audit session-row `Row` children for `Expanded`/`Flexible` wrapping

#### 3.6 — `lib/features/session/session_summary_screen.dart`
- [A] Line 1170 (13) → `bodySmall`
- [A] Lines 1194, 1202 (11) → `labelSmall`
- [A] Line 1242 (22) → `headlineSmall`

#### 3.7 — `lib/features/session/workout_session_global_timer.dart` ★ (densest screen)
- [A] Lines 193, 484 (11) → `labelSmall`
- [A] Lines 672, 690 (12) → `labelMedium`
- [B] All text in the fixed-height timer rows → `maxLines: 1, overflow: TextOverflow.ellipsis`
  (the timer screen has hard height budgets; text must truncate rather than push layout)
- Note: Do NOT add `FittedBox` to timer digit text — `FittedBox` would resize the digit display,
  disrupting the instrument-panel rhythm. Use `labelSmall` / `labelMedium` + ellipsis for
  surrounding labels; the digit itself already uses `theme.textTheme.displayMedium`.

#### 3.8 — `lib/features/period/create_period_screen.dart`
- [A] Lines 147, 157, 186 (12) → `labelMedium`
- [A] Lines 168, 208 (13) → `bodySmall`
- [A] Line 405 (14) → `bodyMedium`

#### 3.9 — `lib/features/period/period_list_screen.dart`
- [A] Line 57 (15) → `bodyLarge`
- [A] Line 199 (14) → `bodyMedium`
- [A] Line 215 (11) → `labelSmall`
- [A] Line 230 (12) → `labelMedium`
- [A] Line 252 (10) → `labelSmall` (accept the 1dp rounding — the textTheme role is correct)

#### 3.10 — `lib/features/profile/profile_screen.dart`
- [A] Line 208 (12) → `labelMedium`
- [C] Line 594 button label → `FittedBox`

#### 3.11 — `lib/features/profile/widgets/measurement_history_chart_sheet.dart`
- [A/E] Line 455 (10): chart axis — add justification comment, keep as literal
- [C] Line 200 button label → `FittedBox`

#### 3.12 — `lib/features/routine/my_routines_screen.dart`
- [A] Line 101 (24) → `headlineMedium`
- [A] Lines 113, 144 (16) → `titleSmall`
- [A] Line 152 (12) → `labelMedium`

#### 3.13 — `lib/features/routine/routine_setup_screen.dart`
- No literal fontSize violations (confirmed clean in grep)
- [C] Lines 545, 566 button labels → `FittedBox`

#### 3.14 — `lib/features/splash/omni_splash_screen.dart`
- [A] Line 118 (24) → `headlineMedium`

#### 3.15 — `lib/features/home/maintenance_placeholder_screen.dart`
- [A] Line 56 (24) → `headlineMedium`
- [A] Line 74 (16) → `titleSmall`

#### 3.16 — `lib/features/settings/settings_screen.dart`
- [A] Line 153 (12) → `labelMedium`
- [A] Lines 196, 214, 228 (13) → `bodySmall`
- [A/E] Line 555 (10) → `labelSmall` (if settings preview chip — otherwise confirm and map)
- [A] Line 637 (11) → `labelSmall`
- [A] Line 677 (15) → `bodyLarge`
- [A] Line 687 (12) → `labelMedium`
- [A] Line 773 (13) → `bodySmall`
- [A] Line 815 (14) → `bodyMedium`
- [B] Theme-chip and preview-row text areas — confirm each has `maxLines: 1, overflow: ellipsis`

#### 3.17 — `lib/features/stats/stats_screen.dart`
- [A] Lines 205, 293, 474, 590 (11) → `labelSmall`
- [A] Line 627 (13) → `bodySmall`
- [E] Lines 339, 363, 513, 545 (10, 9, 10, 9) → chart axis labels — keep literals, add
  justification comment on each

#### 3.18 — `lib/widgets/cards/energy_tile.dart`
- [A] Line 143 (16) → `titleSmall`
- Confirm existing `Flexible` wrapping (line 135) is preserved

#### 3.19 — `lib/widgets/cards/maintenance_tile.dart`
- [A] Line 74 (15) → `bodyLarge`

#### 3.20 — `lib/widgets/pickers/modality_picker_dialog.dart`
- [A] Line 34 (18) → `titleMedium`
- [A] Line 114 (14) → `bodyMedium`
- [A] Line 123 (12) → `labelMedium`

#### 3.21 — `lib/widgets/layout/omni_bottom_cta.dart`
- No literal fontSize violations
- [C] Line 51 (`OmniTheme.buttonPrimaryHeight`) — button label → `FittedBox`

#### 3.22 — `lib/widgets/pickers/exercise_picker_dialog.dart`
- No literal fontSize violations (already uses `theme.textTheme.*`)
- [C] Line 206 button label → `FittedBox`

#### 3.23 — `lib/core/navigation/omni_route.dart` and `omni_navigator.dart`
- Confirmed clean. No typography changes required.

---

### Phase 4: Tests (@developer)

#### New test file: `test/typography_scale_test.dart`

1. [ ] **Dense screen overflow test**: Pump `WorkoutSessionScreen` (the active session logger) at
       `textScaleFactor` 0.9, 1.0, 1.15, and 1.3. Assert that no `RenderBox` is overflowing its
       parent at any of these scales. Use `tester.binding.window.textScaleFactorTestValue` or
       `MediaQuery` override.

2. [ ] **Global clamp boundary test**: Pump `MyApp` with a mock `MediaQueryData` that sets
       `textScaler: TextScaler.linear(0.5)` and separately `TextScaler.linear(2.0)`. For each,
       read back the `MediaQuery.textScalerOf(context)` effective scale from a descendant widget
       and assert it equals 0.9 and 1.3 respectively (the clamp bounds).

3. [ ] **Button label fit test**: Pump each button variant (primary CTA via `OmniBottomCta`,
       row-pair button in `WorkoutSessionListView`, utility outlined button, icon-only square
       button) at text scale 1.3 and assert no `Text` overflow (no `RenderFlex` overflow errors).

4. [ ] **Bottom sheet overflow test**: Pump the Free Training start sheet (accessible from
       `HomeScreen` or extracted directly) and `MeasurementHistoryChartSheet` at text scale 1.3
       and assert sheet titles and action buttons render without clipping or overflow.

#### Existing test review

5. [ ] Re-run all tests under `test/` after Phase 3 completes. Any test that previously passed by
       asserting a specific pixel offset for text (which would shift under a different textScaler)
       should be flagged in the audit report with the decision: update the assertion to be
       scale-independent, or remove the fragile assertion.

6. [ ] Tests of specific interest (known to pump screens with text):
   - `test/screen_widget_test.dart`
   - `test/session_blocks_repository_test.dart`
   - `test/session_edit_duration_test.dart`
   - `test/session_finish_timers_test.dart`
   - `test/session_toolbar_rework_test.dart`
   - `test/settings_sounds_test.dart`
   - `test/settings_state_test.dart`
   - `test/numeric_done_bar_test.dart`
   - `test/interaction_flow_test.dart`
   - `test/widget_test.dart`

---

### Phase 5: Documentation (@developer)

1. [ ] **`.github/agents/docs/design_system.md` — Typography section rewrite**

   Replace the current sparse table with an exhaustive rule set:
   - Rule 1: Never declare `TextStyle(fontSize: N)` directly in feature or widget code. Use
     `Theme.of(context).textTheme.<role>?.copyWith(...)` — or `theme.textTheme.<role>` if
     `theme` is already in scope.
   - Rule 2: Every `Text` widget in a fixed-size container (fixed `width`, `height`, or inside a
     `SizedBox` with explicit dimensions) must declare an overflow strategy:
     `maxLines: 1, overflow: TextOverflow.ellipsis` as a minimum; `FittedBox` where shrink-to-fit
     is preferred over truncation.
   - Rule 3: Button labels inside `OmniTheme.buttonPrimaryHeight` containers are wrapped in
     `FittedBox(fit: BoxFit.scaleDown)` so they shrink at high text scale rather than overflow.
   - Rule 4: Horizontal `Row` widgets that contain a `Text` child give that child a defined width
     budget via `Expanded` or `Flexible`.
   - Rule 5: Chart axis labels are the only justified exception to Rule 1. They must carry an
     inline comment: `// chart axis label — exempt from textTheme rule; see typography_contract.md`
   - Rule 6: The global text scale clamp lives in one place (`MaterialApp.builder` in
     `lib/app.dart`). It must not be re-implemented per screen.
   - Include the `textTheme` role → design intent table from the mapping section above.

2. [ ] **`.github/agents/docs/widget_catalog.md` — Button label behaviour**

   Update the `OmniBottomCta` entry (and any in-progress button component entries) to document:
   - The label `Text` is wrapped in `FittedBox(fit: BoxFit.scaleDown)`.
   - The button height is fixed at `OmniTheme.buttonPrimaryHeight`; the label shrinks to fit.
   - This is the expected pattern for all primary CTA surfaces.

3. [ ] **Create `.github/agents/docs/typography_contract.md`**

   New short document (≈ 100 lines) covering:
   - The global clamp: its purpose, its bounds (0.9–1.3), and where it is configured (single
     location in `app.dart`; the constants live in `OmniTheme`).
   - Why the lazy hard-clamp to 1.0 was rejected: user-hostile; the gym demographic includes users
     with vision concerns; Android users routinely run scale at 1.15–1.30.
   - The accepted tradeoff: above 1.3 the active session logger and calendar will feel tighter —
     that is the correct tradeoff between aesthetics and accessibility.
   - The two categories of exempt text: chart axis labels (9–10 dp, structural to chart geometry)
     and `OmniGradientBackground` (pure decorative).
   - The review gate: any PR introducing a raw `TextStyle(fontSize: N)` in `lib/features/` or
     `lib/widgets/` without an inline justification comment is a review blocker.
   - The test gate: `typography_scale_test.dart` must pass before merging any typography change.

4. [ ] **Create `.github/agents/docs/typography-audit-report.md`**

   To be populated by the developer as they work through Phase 3. Structure:
   - Summary table: every file touched, antipattern category (A/B/C/D/E), count of fixes.
   - Theme × text-scale verification matrix: 6 themes × 3 scale points (0.9, 1.0, 1.3) on iOS
     and Android → "pass" / "note" / "fail" for each screen listed in acceptance criteria.
   - Screenshots (or simulator captures) for: active session logger, settings, calendar, profile,
     stats, onboarding, exercise editor, routine setup, splash, and the free-training sheet — at
     minimum and upper-clamp text scale on at least one iOS device and one Android emulator.
   - Existing test flags: any test updated or flagged due to text-scale-dependent assertions.

---

## Files Affected — Full List

### Modified
- `lib/core/constants/omni_theme.dart` — `kTextScaleMin`, `kTextScaleMax`, `buildTextTheme()`
- `lib/app.dart` — clamp in `builder:`, call `buildTextTheme()`, remove inline textTheme override
- `lib/features/home/home_screen.dart` — 3× [A], 1× [C], [D] review
- `lib/features/onboarding/onboarding_screen.dart` — 10× [A], [B], 1× [C]
- `lib/features/calendar/calendar_screen.dart` — 8× [A], [B]
- `lib/features/calendar/day_session_list_screen.dart` — 7× [A], [B], 2× [C], [D]
- `lib/features/session/session_summary_screen.dart` — 4× [A]
- `lib/features/session/workout_session_global_timer.dart` — 4× [A], [B]
- `lib/features/period/create_period_screen.dart` — 6× [A]
- `lib/features/period/period_list_screen.dart` — 5× [A]
- `lib/features/profile/profile_screen.dart` — 1× [A], 1× [C]
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` — 1× [E], 1× [C]
- `lib/features/routine/my_routines_screen.dart` — 4× [A]
- `lib/features/routine/routine_setup_screen.dart` — 2× [C]
- `lib/features/splash/omni_splash_screen.dart` — 1× [A]
- `lib/features/home/maintenance_placeholder_screen.dart` — 2× [A]
- `lib/features/settings/settings_screen.dart` — 9× [A], [B]
- `lib/features/stats/stats_screen.dart` — 5× [A], 4× [E]
- `lib/widgets/cards/energy_tile.dart` — 1× [A]
- `lib/widgets/cards/maintenance_tile.dart` — 1× [A]
- `lib/widgets/pickers/modality_picker_dialog.dart` — 3× [A]
- `lib/widgets/layout/omni_bottom_cta.dart` — 1× [C]
- `lib/widgets/pickers/exercise_picker_dialog.dart` — 1× [C]

### New
- `test/typography_scale_test.dart`
- `.github/agents/docs/typography_contract.md`
- `.github/agents/docs/typography-audit-report.md` (shell created; screenshots added during
  device testing)

### Updated docs
- `.github/agents/docs/design_system.md`
- `.github/agents/docs/widget_catalog.md`

---

## Implementation Notes

### `buildTextTheme()` placement
The function belongs in `omni_theme.dart` because it is the single source of truth for all design
tokens. It should return a `TextTheme` and call `merge` against `ThemeData.dark().textTheme` so
unspecified roles fall back to Material 3 defaults. This avoids over-specifying the theme.

### Instrument-panel screens
`workout_session_global_timer.dart` is the densest screen. Fixes there must be conservative:
- Timer digit text (`displayMedium`) is already correct — leave it.
- Label text at 11–12 dp → map to `labelSmall`/`labelMedium` + `maxLines: 1, overflow: ellipsis`.
- Do **not** use `FittedBox` on timer digits — it would rescale the digit display mid-workout.

### Stats chart axis labels
Stats lines 339, 363, 513, 545 (values 9 and 10 dp) are structural to the chart geometry and
cannot be scaled without destroying the chart. Keep as literals with a standard justification
comment. All other stats text must be migrated to textTheme roles.

### `OmniBottomCta` button label pattern
After adding `FittedBox`, the label tree inside the button is:
```dart
FittedBox(
  fit: BoxFit.scaleDown,
  child: Text(label, style: theme.textTheme.titleMedium?.copyWith(...)),
)
```
`BoxFit.scaleDown` only scales down, never up, so at default scale the visual is unchanged.

### Theme verification strategy
Verify all six themes at scale 0.9, 1.0, and 1.3 on a physical iPhone (or iOS Simulator with
Dynamic Type) and an Android emulator (System > Accessibility > Font size). Capture screenshots
and commit to the audit report. The six themes have different `textMuted` and `primary` colours;
the fix must not introduce any hard-coded `Color` values — all text colour derives from
`theme.colorScheme` or `OmniTheme.colorsForTheme(activeTheme)`.

---

## Progress

- [x] Phase 1: Typography token foundation (OmniTheme + buildTextTheme)
- [x] Phase 2: Global text scale clamp in MaterialApp.builder
- [x] Phase 3.1: lib/app.dart inline textTheme override removal
- [x] Phase 3.2: home_screen.dart
- [x] Phase 3.3: onboarding_screen.dart
- [x] Phase 3.4: calendar_screen.dart
- [x] Phase 3.5: day_session_list_screen.dart
- [x] Phase 3.6: session_summary_screen.dart
- [x] Phase 3.7: workout_session_global_timer.dart ★
- [x] Phase 3.8: create_period_screen.dart
- [x] Phase 3.9: period_list_screen.dart
- [x] Phase 3.10: profile_screen.dart
- [x] Phase 3.11: measurement_history_chart_sheet.dart ([E] axis label kept at 10dp with comment)
- [x] Phase 3.12: my_routines_screen.dart
- [x] Phase 3.13: routine_setup_screen.dart
- [x] Phase 3.14: omni_splash_screen.dart
- [x] Phase 3.15: maintenance_placeholder_screen.dart
- [x] Phase 3.16: settings_screen.dart
- [x] Phase 3.17: stats_screen.dart ([E] chart axis labels 9–10dp kept with comments)
- [x] Phase 3.18: energy_tile.dart
- [x] Phase 3.19: maintenance_tile.dart
- [x] Phase 3.20: modality_picker_dialog.dart
- [x] Phase 3.21: omni_bottom_cta.dart
- [x] Phase 3.22: exercise_picker_dialog.dart — **Phase 3 Complete**
- [ ] Phase 4: New typography scale tests + existing test review
- [ ] Phase 5: Design system doc update, widget catalog update, typography_contract.md, audit report shell

## Feedback

