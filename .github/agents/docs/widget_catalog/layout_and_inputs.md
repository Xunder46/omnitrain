# Layout & Input Primitives

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.

---

## Layout Primitives

### `OmniGradientBackground`

**File**: `lib/widgets/layout/omni_gradient_background.dart`

Full-screen cosmic gradient backdrop used on every screen. **Also the
single source of truth for the app-wide large-screen content column
cap** — see the [Design System](../design_system.md) "Large-screen
content column" rule.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content to overlay |
| `showRadialHighlight` | `bool` | `true` | White radial glow at top-center |

**Layers** (bottom to top):
1. Vertical linear gradient (`backgroundGradientTop` → `backgroundGradientBottom`)
2. Optional radial white highlight (10% opacity)
3. Optional film-grain noise overlay (`NoiseOverlayPainter`) — controlled by `OmniTheme.enableBackgroundNoise`
4. The `child`, wrapped automatically in a centered column on large screens (see below)

**Large-screen content column (built-in)**:

The `child` is wrapped in a `Center` + `ConstrainedBox(maxWidth:
OmniTheme.kColumnMaxWidth)` when the surface is at least
`OmniTheme.kColumnMinActivationWidth` dp wide. Below the threshold
the child passes through unchanged. This is the **only** place the
app's centered-column behavior is implemented, and every screen
reaches it for free because every screen-level route wraps its page
in `OmniGradientBackground` (per the navigation contract), and the
home / onboarding surfaces are wrapped in the gradient inside
`MaterialApp.builder` in `app.dart`.

- **Phone-class widths** (≤ 500 dp, includes every phone and a
  foldable in folded state): cap is fully inert. `child` fills the
  surface.
- **Tablet-class widths** (> 500 dp, includes every tablet and a
  large unfolded foldable): `child` sits in a centered column of
  `OmniTheme.kColumnMaxWidth` (480) dp, with equal empty margins on
  both sides. The column is a hard cap — it does not grow with the
  surface.
- **Vertical sizes are unchanged at every width** — the gradient
  `Container` and the radial highlight / noise overlays continue to
  fill the full surface; only the `child`'s horizontal extent is
  capped.

Per-screen opt-outs are not supported. The cap is a single global
behavior; the design system is intentionally phone-shaped.

### `OmniBackHeader`

**File**: `lib/widgets/layout/omni_back_header.dart`

Standardized back-and-title header used by all secondary screens. Implements `PreferredSizeWidget` so it slots directly into `Scaffold.appBar`. **Screen-level chrome** — lives above the body and is distinct from `OmniCardHeader` (per-card title, see below).

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Primary header text |
| `subtitle` | `String?` | `null` | Optional second line below the title in `bodySmall` + `OmniTheme.colors.textSecondary` |
| `onBack` | `VoidCallback?` | `null` | Called on back arrow tap; defaults to `Navigator.of(context).pop()` |
| `actions` | `List<Widget>?` | `null` | Trailing widgets forwarded to `AppBar.actions` |

**Behavior**:
- `preferredSize` is always `Size.fromHeight(kToolbarHeight)` (56 px)
- `backgroundColor` and `surfaceTintColor` are `Colors.transparent`, `elevation: 0` — gradient background shows through
- Back arrow color: `OmniTheme.colors.textDominant` (never inherits from theme's `foregroundColor`)
- `titleTextStyle`: `titleLarge` + `FontWeight.w600` + `OmniTheme.titleLetterSpacing` (0.4) + `OmniTheme.colors.textDominant`
- Screens must set `extendBodyBehindAppBar: true` on their `Scaffold` for the gradient to render behind the transparent header

**Usage notes**:
- Calendar uses `actions: [FilledButton('+')]` for the Periods shortcut
- `SessionSummaryScreen` uses `actions: [PopupMenuButton]` for the Edit/Save/Discard overflow
- `SessionOverviewScreen` and `RoutineSetupScreen` use `subtitle` for contextual secondary text
- `RoutineSetupScreen` (PR 6) uses `actions: [IconButton(Icons.delete_outline)]`
  (key `routine-delete-action`) for the destructive delete action; the
  underlying dialog is rendered via `showDeleteRoutineDialog` from
  `my_routines_screen.dart`.

### `OmniCardHeader`

**File**: `lib/widgets/layout/omni_card_header.dart`

Canonical per-card header rendered above an outlined card. Single source of truth for section/card header typography across the app. **Card-level chrome** — distinct from `OmniBackHeader` (screen-level, above the body).

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Header title (left-aligned) |
| `actions` | `List<Widget>?` | `null` | Trailing widgets (icon buttons, controls) rendered in a right-aligned cluster. `null` or empty list renders no cluster. |
| `padding` | `EdgeInsetsGeometry?` | `EdgeInsets.fromLTRB(0, 0, 0, 8)` | Padding around the row. The default leaves an 8 dp gap below the row so the header sits cleanly above the card beneath it. |

**Behavior**:
- Title typography is the canonical D-1 quartet: `theme.textTheme.labelSmall` + `FontWeight.w600` + `letterSpacing: 2.0` + `color: OmniTheme.colors.textMuted`. The widget enforces this — callers cannot override the style.
- Title has `maxLines: 1, overflow: TextOverflow.ellipsis` (Phase 2.2 / A8) so long titles truncate gracefully rather than wrap.
- Layout: `Row(MainAxisAlignment.spaceBetween)` with the title inside `Expanded` (so it shrinks/truncates when actions take space) and the actions cluster as a `Row(mainAxisSize: MainAxisSize.min, children: actions)`. Keys: `Key('omniCardHeader_title')` on the title `Text`; `Key('omniCardHeader_actions')` on the actions cluster `Row`.
- Presentation-only: no repository or service access, no business logic.
- Use cases (every section/card header in the app routes through this widget):
  - **Settings screen** (Phase 1): `PREFERENCES`, `SOUNDS & ALERTS`, `WORKOUT`, `APPEARANCE`.
  - **Session Summary screen** (Phase 2 / 2.1 / 2.2): the date header above the combined session info card (with the modality chip in actions), the `SESSION NOTE` header above the note card, and the month label header above the calendar card (with the `Open Calendar` button in actions).
  - **Daily Nutrition screen** (Phase 3): `Today` header (with the `nutrition_target_button` `OutlinedButton.icon` in actions — PR 3 / S-002), `Foods I Eat` header (with the `food_library_manage_pencil` `IconButton` in actions).
  - **Profile screen** (Phase 4): one `OmniCardHeader` per measurement definition (label + the `+` add `OutlinedButton` in actions).
  - **Stats screen** (Phase 5): `ALL TIME`, `STRENGTH` / `CARDIO` (with the window chip in actions), `NUTRITION`.

**Forbidden**:
- Raw `Text` widgets above outlined cards are **not permitted** for section/card headers. Any pre-existing per-screen `_SectionHeader` / `_SectionLabel` / in-card `Text(definition.label)` widget has been migrated to this primitive (see `.github/agents/plans/unified-card-and-header-plan.md`).
- Hard-coded overrides of the title style — the typography is canonical and enforced by the widget.

### `OmniSurface`

**File**: `lib/widgets/layout/omni_surface.dart`

Base container for all cards and panels. Dark navy with border + shadow. **Single source of truth for outlined card chrome** — every outlined card in the app routes through this widget.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content |
| `padding` | `EdgeInsets?` | `null` | Optional inner padding |
| `showShadow` | `bool` | `true` | Deep shadow toggle |

**Behavior**:
- Uses `OmniTheme.colors.surface`, `surfaceBorderRadius`, `OmniTheme.colors.surfaceBorder`, `surfaceBorderWidth`, `deepShadow`. The widget is the only authority for outlined card chrome across the app.
- No call-site may re-declare border, radius, or shadow for an outlined card. Pre-existing per-screen `_SummaryCard` (Session Summary), raw Flutter `Card()` (Foods I Eat on the Daily Nutrition screen, Phase 3) and the calorie ring card's internal `Card()` (Daily Nutrition "Today" card, A20) have been migrated to this primitive.

### `OmniBottomCTA`

**File**: `lib/widgets/layout/omni_bottom_cta.dart`

Shared full-width bottom call-to-action used by screens with a single persistent footer action. **Single source of truth for primary bottom CTA placement and width** — see `.github/agents/plans/primary-bottom-cta-anchor-width-plan.md`.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `String` | required | Button text; a leading `+` triggers the shared add affordance |
| `onPressed` | `VoidCallback?` | required | Tap handler; `null` disables the CTA |
| `isDestructive` | `bool` | `false` | Uses the active theme’s destructive/error colors |
| `buttonKey` | `Key?` | `null` | Optional `Key` forwarded to the rendered `FilledButton`. Used by host screens that need a stable test target (e.g. the `food_form_save` key on the food library host screens) |

**Behavior**:
- **Height**: `OmniTheme.buttonPrimaryHeight` (56 dp).
- **Width**: `double.infinity` inset by `OmniTheme.bottomCTAHorizontalPadding` (16) on each side. The button's left/right edges sit at exactly the same horizontal margin on every screen.
- **Corner radius**: `OmniTheme.buttonBorderRadius` (12 dp).
- **Vertical anchor**: `SafeArea(top: false)` (bottom on by default) plus `OmniTheme.bottomCTAVerticalBottomPadding` (16). The button clears the device home indicator (iOS) and gesture / 3-button nav bar (Android) uniformly.
- **Top padding**: `OmniTheme.bottomCTAVerticalTopPadding` (24) — the gap between content above and the CTA so the gradient fade reads as a deliberate break.
- **Footer treatment**: theme-reactive fade gradient using `colorScheme.surface` so the CTA lifts above scrollable content.
- Prevents per-screen CTA styling drift by centralizing footer layout, colors, and safe-area handling.

**Call-site contract**:
- All primary bottom CTAs use this widget. Inline `Spacer() + SizedBox + FilledButton` is **not** permitted at the bottom of a screen — that pattern has been removed in favour of `Scaffold.bottomNavigationBar: OmniBottomCTA(...)`.
- Form bodies that need clearance for the bottom CTA use `OmniTheme.formBottomCTAClearance` (112) as the scroll view's bottom padding.

### `NoiseOverlayPainter`

**File**: `lib/widgets/layout/noise_overlay_painter.dart`

`CustomPainter` that renders a subtle film-grain texture over the gradient background. Creates a premium aesthetic without being distracting.

---

---

## Input Primitives

### `SelectAllOnFocus`

**File**: `lib/widgets/inputs/select_all_on_focus.dart`

Widget wrapper that selects the entire current contents of a `TextEditingController` whenever the wrapped field gains focus. The user can still tap to place the cursor manually after the initial focus — select-all is a one-shot focus event, not a permanent override, so any subsequent tap inside the field moves the cursor to the tapped position via Flutter's standard selection model.

Use this for **value-entry fields** (weight, reps, durations, logged amounts, body measurements, height, calories target) where the user's intent on focus is to overwrite the existing value in one tap. Do NOT use this for multi-line or free-text fields (notes, names, descriptions, search) — selecting everything on focus would be a nuisance and would break the user's ability to position the cursor freely.

| Prop | Type | Description |
|---|---|---|
| `controller` | `TextEditingController` | required — the controller whose text gets selected on focus |
| `builder` | `Widget Function(BuildContext, FocusNode)` | required — builds the wrapped field, receiving the focus node the wrapper has wired up |
| `focusNode` | `FocusNode?` | optional — external focus node to use instead of the wrapper's internal one. Pass when the caller already owns a `FocusNode` (e.g. a form with multiple named nodes). |

**Companion exports** (in the same file):
- `SelectAllOnFocusNode` — a `FocusNode` subclass that selects the full text of an associated `TextEditingController` on every focus gain. Drop-in replacement for `FocusNode` for callers that already own a `FocusNode` (e.g. the `FoodForm` state's 10 named focus nodes). Detaches its listener on `dispose`.
- `bindSelectAllOnFocus` — function form for callers that want to attach the listener manually (e.g. when the focus node is created internally inside a larger widget). Returns a `VoidCallback` that detaches the listener.

**Behavior**:
- Selection is set in a post-frame callback after focus is gained, so Flutter's focus machinery has time to settle before the selection is overridden. The post-frame callback re-checks both `focusNode.hasFocus` and the current controller text length to handle the case where the text was mutated between the focus event and the frame boundary (e.g. by a programmatic assignment or `tester.enterText`).
- The selection is re-applied on every focus gain, not just the first one — so re-focusing a field after blur still highlights the value.
- Empty values are a no-op (Flutter's selection model tolerates an empty range, but skipping the assignment keeps cursor behavior predictable for empty fields).
- Internal `FocusNode` is disposed in `dispose`; the listener is detached in `dispose` (for the wrapper) or in the `SelectAllOnFocusNode.dispose` override.

### `NumericFieldWithDoneBar`

**File**: `lib/widgets/inputs/numeric_field_with_done_bar.dart`

`TextField` wrapper that displays a themed "Done" accessory bar above the numeric keyboard, dismisses the keyboard on Done tap, and (by default) selects the full current contents on focus. The Done bar does not appear on web.

| Prop | Type | Default | Description |
|---|---|---|---|
| `controller` | `TextEditingController?` | `null` | The field's controller |
| `focusNode` | `FocusNode?` | `null` | The field's focus node. When `null`, the wrapper creates an internal `SelectAllOnFocusNode` (if `selectAllOnFocus: true` and a `controller` is provided) or a plain `FocusNode` (if either is missing). |
| `keyboardType` | `TextInputType` | `TextInputType.number` | Forwarded to `TextField` |
| `decoration` | `InputDecoration?` | `null` | Forwarded to `TextField` |
| `textAlign` | `TextAlign` | `TextAlign.start` | Forwarded to `TextField` |
| `selectAllOnFocus` | `bool` | `true` | When `true` and the wrapper owns the focus node, the wrapper selects the full contents of `controller` on focus gain. Set to `false` to disable per instance — the caller is then responsible for the field's selection behavior. |

All other `TextField` properties (`onChanged`, `onEditingComplete`, `onSubmitted`, `obscureText`, `textInputAction`, `maxLines`, `minLines`, `enabled`, `textCapitalization`) are forwarded unchanged.

**Use sites** (every value-entry field with a numeric keyboard routes through this wrapper):
- `lib/widgets/session/metric_crown_widget.dart` — set logging (weight, reps, time, distance)
- `lib/widgets/session/duration_entry_dialog.dart` — h/m/s duration entry
- `lib/features/profile/profile_screen.dart` — body measurement values + height (cm mode + ft/in mode)
- `lib/features/routine/routine_setup_screen.dart` — round/timed targets (via the shared `showDurationEntryDialog`)

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
