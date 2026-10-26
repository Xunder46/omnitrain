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
2. Optional radial white highlight (subtle; the opacity is defined inline in
   `lib/widgets/layout/omni_gradient_background.dart`, not as a token)
3. Optional film-grain noise overlay (`NoiseOverlayPainter`) — controlled by `OmniTheme.enableBackgroundNoise`
4. The `child`, wrapped automatically in a centered column on large screens (see below)

**Large-screen content column (built-in)**:

The `child` is wrapped in a `Center` + `ConstrainedBox(maxWidth:
OmniTheme.kColumnMaxWidth)` when the surface is at least
`OmniTheme.kColumnMinActivationWidth` wide. Below the threshold
the child passes through unchanged. This is the **only** place the
app's centered-column behavior is implemented, and every screen
reaches it for free because every screen-level route wraps its page
in `OmniGradientBackground` (per the navigation contract), and the
home / onboarding surfaces are wrapped in the gradient inside
`MaterialApp.builder` in `app.dart`.

- **Phone-class widths** (below `OmniTheme.kColumnMinActivationWidth`,
  includes every phone and a foldable in folded state): cap is fully
  inert. `child` fills the surface.
- **Tablet-class widths** (at or above `OmniTheme.kColumnMinActivationWidth`,
  includes every tablet and a large unfolded foldable): `child` sits in a
  centered column of `OmniTheme.kColumnMaxWidth`, with equal empty margins on
  both sides. The column is a hard cap — it does not grow with the
  surface.
- **Vertical sizes are unchanged at every width** — the gradient
  `Container` and the radial highlight / noise overlays continue to
  fill the full surface; only the `child`'s horizontal extent is
  capped.

Per-screen opt-outs are not supported. The cap is a single global
behavior; the design system is intentionally phone-shaped.

The activation threshold and the cap are pinned by
`test/screen_widget_test.dart` (group 'Large-screen content column':
'S-001: phone-class surface — column is inert, content fills the
width', 'S-006: threshold is exactly kColumnMinActivationWidth'); the
route wrapping that delivers every screen here is pinned by
`test/omni_route_test.dart` ('OmniRoute wraps page in
OmniGradientBackground', 'app-level OmniGradientBackground is still
present after pushing a screen').

### `OmniBackHeader`

**File**: `lib/widgets/layout/omni_back_header.dart`

Shared back-navigation header. Standard toolbar height, transparent so the route gradient shows
through. Screens supply a title and optional actions.

### `OmniCardHeader`

**File**: `lib/widgets/layout/omni_card_header.dart`

The single source of truth for section eyebrows and per-card titles.

**The widget enforces the typography contract; callers cannot override it.** This is the whole
reason it exists — before it, every screen re-declared its own header style and they drifted. Raw
`Text` widgets above outlined cards are not permitted (see
[Global Conventions](../global_conventions.md)). An optional actions slot hosts trailing controls
so callers never need to rebuild the row.

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

The shared primary bottom action. Every screen with a primary bottom action must route through it,
so the button's width and vertical anchor are identical everywhere and the user learns one
location for "the main action". Handles safe-area insets so the button clears the iOS home
indicator and Android navigation bar uniformly. Geometry comes from `OmniTheme` tokens — see
[Design System](../design_system.md) for the rule and its forbidden patterns.

Hosts that need a stable test target forward a `Key` to the rendered button; the shared geometry is
unaffected.

### `NoiseOverlayPainter`

**File**: `lib/widgets/layout/noise_overlay_painter.dart`

`CustomPainter` that renders a subtle film-grain texture over the gradient background. Creates a premium aesthetic without being distracting.

---

---

## Feedback & Empty States

### `OmniMessage`

**File**: `lib/widgets/feedback/omni_message.dart`

The one look for a small transient message at the bottom of a screen. Every
"saved" / "could not save" message in the app routes through it, so all of them
read the same: the theme's surface colour, the theme's text colour and the
corner radius the dialog actions use. Placement is Flutter's default bottom
bar, unchanged.

| Static method | Purpose |
|---|---|
| `show(context, text, {action, duration})` | Informational message. `action` and `duration` pass straight to the `SnackBar`; leaving both unset keeps Flutter's own defaults. |
| `error(context, text)` | Failed action: the same look with a leading `Icons.error_outline` in `colorScheme.error`. |
| `showOn(messenger, theme, text, {action, duration})` | `show` on a `ScaffoldMessengerState` and `ThemeData` captured **before** an `await`, for tap handlers that persist first and must not touch the `context` again afterwards. |
| `errorOn(messenger, theme, text)` | `error`'s counterpart to `showOn`. |

The copy is the caller's — `Could not … Try again.` — never an exception's
`toString()`, which the API cannot even receive.

Verified by `test/omni_message_test.dart` (group `S-2701: OmniMessage on the
${entry.key} theme`: `show paints the theme surface and text colour`, `show
uses the dialog corner radius`, `show carries no error icon`, `error adds the
error icon in the theme error colour`, `showOn paints the theme captured before
the await`, `errorOn adds the error icon captured theme error colour`; and the
top-level tests `showOn passes an action and a duration through`, `show passes
an action and a duration through`). The scans that hold every other call site
to this look are `test/ui_standards_contract_test.dart` (group `S-2702 one
message look`: `no file outside the two that own a look builds a message bar`;
group `S-2703 no exception text in a message`: `no message in lib/
interpolates an exception`).

**Exception**: `PRToast` keeps its own celebration `SnackBar` by design — see
[Session, Picker & Presentation](session_widgets.md).

### `OmniEmptyState`

**File**: `lib/widgets/common/omni_empty_state.dart`

The shared "nothing here yet" composition: a muted icon, a short title and one
line saying what to do next. Every screen or list with nothing to show routes
through this widget, so the same message reads the same everywhere. All
colours come from `Theme.of(context).colorScheme.onSurface` at three alphas, so
the composition follows the active theme without per-screen tokens.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | The headline, kept verbatim per screen |
| `hint` | `String?` | `null` | One line saying what to do next |
| `icon` | `IconData` | `Icons.inbox_outlined` | The muted glyph above the title |
| `action` | `Widget?` | `null` | Optional content below the hint — a CTA or a short explanation |
| `compact` | `bool` | `false` | Shrinks the icon and drops the scroll wrapper, for use inside a card |

The default variant centres itself in the space it is given and scrolls when
that space is shorter than the content, so it never overflows on a small phone
(320x568). `compact: true` is for a card that already supplies its own padding
and sits in a scrolling body.

Verified by `test/omni_empty_state_test.dart` (group `S-2801 OmniEmptyState`:
`light: the icon, title and hint render on a 320x568 phone without an
overflow`, `the icon, title and hint carry the muted onSurface alphas`, `the
compact variant uses the smaller icon and keeps the title and hint`, `the
action renders below the hint`, `a hint is optional and a long title still
fits, rather than overflowing`). The scan that holds every empty screen to
this one composition is `test/ui_standards_contract_test.dart` (group `S-2804
one empty-state composition`: `only one empty-state class is declared in
lib/`).

### `LoadFailureView`

**File**: `lib/features/stats/widgets/load_failure_view.dart`

The centred "could not load" surface the Stats-area screens render when their
one load read throws. It is deliberately **not** an empty state: the screen
says the load failed and offers the retry, instead of reading as "no data".

| Prop | Type | Description |
|------|------|-------------|
| `message` | `String` | The plain-language failure line, e.g. `Could not load your stats.` Never an exception's text. |
| `onRetry` | `VoidCallback` | Re-runs the host screen's own load method. |

The retry is a full-width `FilledButton` (`Try again`, key
`load_failure_retry`) at the primary button height and `buttonBorderRadius`,
copying the startup failure screen's Retry look.

It is feature-scoped rather than `lib/widgets/` material, but it is
presentation-only and theme-reactive in the same sense as the catalogued
widgets. Its hosts are the Stats screen, Records & Trends and Exercise
Progress. Verified by `test/stats_load_failure_test.dart` (group `S-2704: a
failed load is not an empty state`: `Stats: the failure text and Try again
replace the empty state`, `Records & Trends: the failure text and Try again
replace the empty state`, `Exercise Progress: the failure text and Try again
replace the empty state`).

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

> **Doc freshness** — Last reconciled against source: 2026-10-13. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
