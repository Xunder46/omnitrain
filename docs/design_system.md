# OmniTrain Design System

**Scope.** This document governs the Flutter app's visual system: the tokens in
`lib/core/constants/omni_theme.dart`, and every surface under `lib/widgets/` and
`lib/features/`. It also governs the values the watch clients **mirror** from
those tokens — button shapes, radii, and heights reused by
`lib/watch/widgets/watch_controls.dart`, `lib/watch/logging/`,
`lib/watch/nutrition/`, `lib/watch/start/`, and
`watch/watchos/Sources/WatchSessionEngine/`.

**Not in scope: wrist-only layout geometry.** Spacing and screen-level
composition on a wrist are sized for a ~40 mm display, not a phone. The watch
surfaces carry their own inset and height values (`WatchLoggingScreen.surfaceInset`,
`WatchStartScreen.surfaceInset`) rather than scaling a phone token down, and
rules written for a full-width phone screen — the `OmniBottomCTA` width and
vertical-anchor rule in particular — do not apply to them.

## Core Design Philosophy: Minimum Friction

Every design decision serves one question: **does this help the athlete get to work faster?**

- If a UI element requires waiting, it should be eliminated or deferred
- If an interaction requires multiple taps, it should be reduced to one
- If information is decorative rather than functional, it must still earn its place by enhancing focus or reducing cognitive load
- The app is a tool, not a destination — beautiful, but never in the way

### The Splash Screen Litmus Test

If it doesn't serve the workout, it doesn't belong in the critical path. This is the benchmark for every design decision.

---

## Visual Identity: Spacecraft Interior

The aesthetic is **spacecraft interior** — not cosmic/outer-space, but the controlled, purposeful environment *inside* the ship. Think: precision instrumentation, ambient lighting, surfaces that communicate status without demanding attention.

### Mood Keywords
- Zen — calm, focused, undistracted
- Tranquil — nothing screams for attention
- Aura / Halo — subtle light emanation, not explosion
- Precision — engineered, intentional, not decorative
- Premium — feels crafted, not templated

### What We Are NOT
- Cosmic/galaxy wallpaper aesthetic
- Generic 3-color Material theme
- Apple Fitness sterile minimalism
- Neon-overload gaming UI
- Average fitness app with stock photography

---

## Color System

### Theme Roster

Six themes ship: Abyssal Neon, Forge & Ember, Obsidian Volt, Void Pulse, Crimson Dojo, and Malachite Core. Each is a distinct character rather than a hue swap — Abyssal Neon is deep and high-contrast, Forge & Ember is industrial warmth, Obsidian Volt is controlled amber, Void Pulse is cosmic and meditative, Crimson Dojo is martial, and Malachite Core is grounded and mineral (the only green in the permanent roster, deliberately clear of the teal boundary so it never reads as a second Abyssal Neon).

**Values live in `lib/core/constants/omni_theme.dart` and nowhere else** — except the per-theme Material `ColorScheme` role mapping, which lives in `lib/app.dart`. The theme contract tests gate both locations. This document names tokens and says what each is for; it does not restate what any of them equal.

### Adding or changing a theme

Theme compliance is enforced by the toolchain, not by reviewer memory. Two gates
catch a new or edited theme, in this order:

**1. The compiler.** `AppTheme` is matched by exhaustive `switch` statements, so adding an
enum value fails the build until every one is handled. Today that forces you to supply the
full palette, the Material `ColorScheme` role mapping, and the on-primary / on-secondary
label colours. You cannot ship a theme that silently inherits another theme's values or
falls through to a framework default — the build stops first.

**2. The palette legibility contract** (`test/palette_legibility_contract_test.dart`).
It iterates `AppTheme.values`, so once the code compiles, every rule applies to the new
theme automatically with **no test edits**. It covers background lightness, surface lift,
muted and secondary text, borders, dividers, accent contrast, the on-primary/on-secondary
labels, the interactive vs decorative outline split, the elevated container tier, the home
tile fills at both tiers, the modality accents against the surface, and the effort-rating
intensity ramp (below). A failure names the theme, the check, the measured value and the
threshold.

**Derived tokens — the effort-rating intensity ramp.** `OmniThemeColors.intensityRamp`
(`step1`…`step5`) is not hand-picked per theme; `OmniTheme.intensityRampFor` derives it from
each theme's `primary` and `surface`, cached per `(primary, surface)` pair so an edited palette
can never be served a stale ramp, and a new theme gets a ramp for free. Each step is `primary`
alpha-composited over `surface`: step 5 is `primary` itself, step 1 is the lowest alpha whose
composite clears the same floor contract check 6 holds `surfaceBorder` to, and steps 2–4 space
the contrast against `surface` evenly between them. It colors the effort-rating tiles, the
Session Summary EFFORT marker and the calendar day-list tint through
`feelingColor(rating, themeColors)`; the selected tile's number uses `effortTileTextColor(...)`.
Enforced by contract checks 18a (every step clears the border floor), 18b (contrast strictly
increases from step 1 to 5) and 18c (the tile number clears the text floor on every step) in
`test/palette_legibility_contract_test.dart`, and by `test/utils_test.dart` (group
`Intensity ramp spacing (T-1)`: step 1 is the lowest qualifying alpha, even spacing, cache
keying). The ramp reads as "more", never as good/bad — don't reintroduce a traffic-light
palette for ratings. It is a fill, never a text color: the low steps sit below the text floor,
so a rating shown as text uses the normal text tokens with a ramp-filled mark beside it.

Related gates that also iterate the roster: `emphasis_tier_contract_test.dart` (accent stays
chromatically distinct from the text tiers) and `switch_consistency_contract_test.dart`
(no control opts out of theme-driven styling).

**What is NOT gated.** Be deliberate about these, because nothing will stop you:

- The macro chart and nutrition strip palettes have no contrast check.
- Glow and brand colours are exempt by design — the brand mark stays constant across themes.
- `textDisabled` has no floor.
- The startup failure surface renders in the canonical theme regardless of the saved one,
  because it runs before persisted settings are readable.

**Tuning an existing value.** Change it and run the suite. If a check fails, the value is
wrong or the threshold needs an explicit, recorded decision — never quietly relax the
assertion. Thresholds are approved product decisions; a test edited to accommodate a value
is how the original legibility defects reached users in the first place.

### Emphasis Tiers

OmniTrain’s shared text hierarchy is expressed through `OmniTheme.colors`:

| Token | Role |
|-------|------|
| `textDominant` | Hero headings, primary back arrows, selected/active emphasis |
| `textSecondary` | Supporting text, secondary icons, subdued labels |
| `textMuted` | Tertiary metadata, chrome, status labels |
| `textDisabled` | Disabled controls and unavailable states |

`primary` remains the primary-action accent used for CTAs and active indicators.

### Macro Chart Palette

`OmniTheme.colors.macroChart` is a five-slot palette for the daily nutrition macro-distribution donut: `protein`, `netCarbs`, `fiber`, and `fat` map to the four arc sections, and `chartLabelDark` is the label colour used on light section backgrounds (the light counterpart is the theme’s `textDominant`). The palette lives on `OmniTheme` so the "theme tokens only" rule is honoured and themes can override slots without touching the chart.

### Color Usage Rules
1. **Background** is always the cosmic gradient — never flat
2. **Surfaces** float above the background with depth (shadow + border)
3. **The active theme's primary accent** indicates interactivity or an active state — never decorative filler
4. **White text** with opacity levels creates hierarchy without introducing new hues
5. **Home tiles** use a solid low-opacity accent fill (primary tier and a quieter secondary tier; the opacities live in `lib/widgets/cards/energy_tile.dart`) with a top rim highlight and a bottom inner shadow on primary tiles; secondary tiles (Free, Routines) have no rim or inner shadow. Tile gradients are intentionally not used — see `EnergyTile` and `HomeTileConfig.isSecondary`.
6. **Glow effects** are reserved for active/selected states and brand elements
7. **Modality accent colors** must come from `lib/core/constants/modality_colors.dart` (single source of truth) and must not be hardcoded in screens/components

## Typography

| Level | Tracking | Character |
|-------|----------|-----------|
| Headers | Wide (`OmniTheme.headerLetterSpacing`) | Commanding — section titles, brand text |
| Titles | Slightly tracked (`OmniTheme.titleLetterSpacing`) | Card labels, navigation |
| Labels | Wide, uppercase or small-caps feel | Chip labels, metadata |
| Body | Default | Clean and readable — descriptions, notes |

### Typography Rules
1. Favor **system fonts** — speed over custom font loading
2. **Wide letter-spacing** for headers communicates premium without a custom typeface
3. Body text must be immediately readable at arm's length (gym context)
4. Never use more than 3 type weights on a single screen

---

## Section / Card Headers

Every section eyebrow and per-card title in the app uses the **canonical D-1 typography** — there is one and only one style for these elements. The contract is enforced by the `OmniCardHeader` widget (see `docs/widget_catalog.md`); callers cannot override the style.

| Property | Value | Rationale |
|----------|-------|-----------|
| Size | `theme.textTheme.labelSmall` | Small enough to read as a section eyebrow, not a hero title. |
| Weight | `FontWeight.w600` | Same emphasis tier as the surrounding card content (no louder than the card body). |
| Letter spacing | The "Labels" tracking (see [Typography](#typography)) | Uppercase or small-caps feel. |
| Color | `OmniTheme.colors.textMuted` | Quiet, secondary hierarchy; never louder than the card body. |
| Overflow | Single line, ellipsized | Long titles (e.g. month labels, dates) truncate gracefully rather than wrap. |

The `actions` cluster takes at most half the header's width: a long action
label ellipsizes instead of overflowing the header row at a narrow width, a
short action keeps its natural size, and the title keeps the rest — at least
the other half. Verified by `test/header_standardization_test.dart` (`S-001c`
and its title-side and real-action cases).

### Where the canonical header is used

Every section / card header in the app routes through `OmniCardHeader`. The widget enforces the contract above; raw `Text` widgets above outlined cards are **not permitted** (see `docs/global_conventions.md`).

| Screen | Headers |
|--------|---------|
| **Settings** | `PREFERENCES`, `SOUNDS & ALERTS`, `WORKOUT`, `APPEARANCE` |
| **Session Summary** | Date (with the modality chip in actions), `DISTANCE`, `SESSION NOTE` (note card), month label (with `Open Calendar` in actions) |
| **Daily Nutrition** | `Today` (with `nutrition_target_button` labelled `OutlinedButton.icon` in actions), `Foods I Eat` (with `food_library_manage_pencil` in actions) |
| **Records & Trends** | `ALL TIME`; `RECENT PRS` (via `RecentPRList`); the per-section list labels (`section.label`). Verified by `test/records_and_trends_screen_test.dart` (group `Records & Trends / Exercise Progress — ${harness.name}`) and `test/ui_standards_widget_test.dart` (group `Mock S-2605a RecentPRList`). |
| **Exercise Progress** | `ALL TIME`, `TREND`, `RECENT SESSIONS`. Verified by `test/records_and_trends_screen_test.dart` (group `Records & Trends / Exercise Progress — ${harness.name}`). |
| **Day session list (calendar)** | `COMPLETED`, `PLANNED`, `IN PROGRESS` group labels. Verified by `test/ui_standards_widget_test.dart` (group `Mock S-2605b DaySessionListScreen headers`). |
| **Profile** | One title-only header per measurement definition; the `+` add button lives in the card body. Verified by `test/header_standardization_test.dart` (`S-011`). |
| **Stats** | `TRAINING MIX` (carrying the window chip in actions); `SIGNALS`; `ALL TIME`; the Instruments list's four title-case headers, `Resistance`, `Cardio`, `Isometric`, `Sports`, the first of them carrying the window chip in actions; and the Fuel row's `Fuel`. Verified by `test/mix_layer_screen_test.dart` (`S-1601`, `S-1612`), `test/signals_layer_screen_test.dart` (`S-1701`), `test/instrument_list_screen_test.dart` (`S-1001`, `S-1011`, `S-1015`) and `test/fuel_row_screen_test.dart`. |

### Intentional exceptions (D-10 — sheet / title chrome, not card headers)

The home screen's `HUB` eyebrow and body-centered `TRAIN` title are sheet / title chrome (they sit on top of the gradient or as the page's hero text), not card headers — they intentionally stay on their own typography (the wide Headers tracking for `TRAIN`, the Labels tracking for `HUB`). The onboarding screen's step label is similarly out of scope.

---

## Spacing & Layout

| Token | Usage |
|-------|-------|
| `OmniTheme.surfaceBorderRadius` | Standard card rounding — generous, modern |
| `OmniTheme.surfaceBorderWidth` | Subtle surface definition |
| `OmniTheme.energyCoreSize` | Standard icon circle on tiles |
| `OmniTheme.zenHaloSize` | Logo/brand mark container |
| `OmniTheme.zenHaloStrokeWidth` | Enso arc thickness |

### Layout Rules
1. **Mobile-first, watch-aware** — design for the smallest screen, then scale up
2. Home training tiles derive artwork bounds and spacing from rendered tile height; artwork is decorative and is omitted when the height budget cannot accommodate it alongside the label. The label remains the identifying content. This contract is verified by the height-responsive artwork regression group in `test/widgets/energy_tile_test.dart`.
3. Generous padding and touch targets — tap areas meet the platform minimum (`kMinInteractiveDimension`; gym gloves, sweaty fingers)
4. Vertical scrolling preferred — horizontal swipe only for carousel/peek patterns
5. Information density scales with screen size, never with complexity

### Large-screen content column (tablet / iPad / large unfolded foldable)

One app-wide layout rule, applied automatically by
`OmniGradientBackground` (see the [Widget Catalog](widget_catalog.md)
"OmniGradientBackground" entry). Screens do not opt in or out; the
behavior is consistent across every screen.

- **Phone-class widths** (≤ `OmniTheme.kColumnMinActivationWidth`, includes
  every phone and a foldable in folded state): the centered column is
  **inert**. Content fills the surface edge to edge. Phones are
  byte-for-byte identical to today.
- **Tablet-class widths** (> `OmniTheme.kColumnMinActivationWidth`, includes
  every tablet and a large unfolded foldable): content sits in a
  horizontally centered column of `OmniTheme.kColumnMaxWidth`, with equal
  empty margins on both sides. The column is a hard cap — it does not
  grow with the surface.
- **Vertical sizes are unchanged at every width.** The gradient,
  the radial highlight, and the noise overlay continue to fill the
  full surface. Only the `child`'s horizontal extent is capped.
- **No split layouts, no text-scaling changes, no orientation
  handling, no user-facing toggle.** The only behavior is one
  centered column.
- Implementation lives in a single place
  (`lib/widgets/layout/omni_gradient_background.dart`); every
  screen-level route wraps its page in `OmniGradientBackground` per
  the navigation contract, so the cap reaches every screen with no
  per-screen logic.

---

## Depth & Shadow System

| Shadow | Token | Usage |
|--------|-------|-------|
| Deep Shadow | `OmniTheme.deepShadow` | All elevated surfaces — strong vertical lift |
| Glow Shadow | `OmniTheme.glowShadow(color)` | Active states, energy cores, brand elements |

### Depth Rules
1. Every card/surface has `deepShadow` — no flat surfaces floating in space
2. Glow is additive — only appears on interaction or active selection
3. Shadow direction is always **downward** — consistent overhead light source
4. Never use drop shadows on text

---

## Interaction & Animation

| Token | Purpose |
|-------|---------|
| `OmniTheme.pressedScale` | Tactile press feedback |
| `OmniTheme.animationDuration` | Standard transition |
| `OmniTheme.animationCurve` | Smooth, natural motion |
| `OmniTheme.splashDuration` | Brand animation |
| `OmniTheme.strokeDrawDuration` | Enso arc reveal |
| `OmniTheme.breathingDuration` | Ambient logo animation |
| `OmniTheme.rotationDuration` | Slow perpetual logo rotation |

### Animation Rules
1. **Interactions are instant-feeling** — the standard animation duration is the maximum for press/release feedback
2. **No animations in the critical path** — never make the user wait for an animation to complete before they can act
3. **Ambient animations** (breathing, rotation) are for idle/brand moments only
4. **Press-scale** is the universal interaction feedback — every tappable element uses it
5. Transitions between screens should be fast, not cinematic
6. No bouncing, no elastic overshoots — smooth and controlled, like spacecraft instrument panels

---

## Buttons

Buttons use a **slightly-rounded rectangle**, never a pill (StadiumBorder). Material 3 default `StadiumBorder` must always be overridden. The aesthetic reads as precision instrument controls — weighted, tactile, a scalpel handle, not a bubble.

### Reference Buttons
- **Primary**: "Finish Workout" — full-width, bottom of screen
- **Utility**: "+ Add Exercise" — inline in a row beside other controls

### Button Variants

| Variant | Widget | Shape token | Width |
|---------|--------|-------------|-------|
| Primary | `FilledButton` | `OmniTheme.buttonBorderRadius` | Full-width (`double.infinity`) |
| Row-pair | `FilledButton` / `OutlinedButton` | `OmniTheme.buttonBorderRadius` | `Expanded` (50/50 split) |
| Utility | `OutlinedButton.icon` | `OmniTheme.buttonUtilityRadius` | Content-width |
| Icon-only | `FilledButton` + icon | `OmniTheme.buttonIconRadius` | Square (`OmniTheme.buttonIconSize`) |
| Dialog | `TextButton` / `FilledButton` | `OmniTheme.buttonUtilityRadius` | Content-width |

### Shape Rule (MANDATORY)

Every `FilledButton`, `OutlinedButton`, or `TextButton` MUST explicitly set `shape`. Never rely on Material 3 defaults. The correct pattern is a `ButtonStyle` whose `shape` is a `WidgetStateProperty` carrying a `RoundedRectangleBorder` with the variant's radius token (see the table above); the wrong pattern is any button style that omits `shape` and lets the Material 3 default `StadiumBorder` fire. For the canonical worked example see `lib/widgets/dialogs/confirmation_dialog.dart`, which sets an explicit shape on every action button.

### Press Feedback

All buttons use the same press-scale system as tiles: track press state and wrap the button in an `AnimatedScale` that applies `OmniTheme.pressedScale` with `OmniTheme.animationDuration` and `OmniTheme.animationCurve` while pressed.

> Note: `FilledButton` / `OutlinedButton` already provide their own ink press feedback. Wrap in `AnimatedScale` only for high-prominence primary buttons where visceral feedback matters (e.g. "Finish Workout", "Start Workout"). Skip for utility and dialog buttons.

### Colour

| Variant | Fill | Border | Text/Icon |
|---------|------|--------|-----------|
| Primary / Row-pair `FilledButton` | `theme.colorScheme.primary` | — | per-theme dark label (from `onPrimary`) |
| Row-pair `OutlinedButton` | Transparent | `theme.colorScheme.primary` | `theme.colorScheme.primary` |
| Utility `OutlinedButton.icon` | Transparent | `theme.colorScheme.primary` | `theme.colorScheme.primary` |
| Icon-only `FilledButton` | `theme.colorScheme.primary` | — | per-theme dark label (from `onPrimary`) |

Never hardcode button colours. Always derive from `theme.colorScheme`.

### Destructive vs Routine Confirmation Dialogs

The app implements a two-tier classification for confirmation dialogs, enforced by the shared `ConfirmationDialog` component in `lib/widgets/dialogs/confirmation_dialog.dart`:

**Destructive** confirmations (delete, discard, remove) render the confirming action as a `FilledButton` filled with `theme.colorScheme.error` (not hardcoded colors) and foreground `theme.colorScheme.onError`. Examples: delete session, delete exercise, discard unsaved edits.

**Routine** confirmations render the confirming action as a `FilledButton` in standard primary styling (`theme.colorScheme.primary`). Examples: finish workout, enable notifications.

**Ordering rule**: dismissal action first (left or top), confirming action last (right or bottom) on every confirmation. Both use `OmniTheme.buttonUtilityRadius` — never framework default shapes.

**Barrier dismissal**: `barrierDismissible: true` on all confirmations. Tapping the barrier produces the same outcome as tapping the dismissal button and mutates no state.

**Three-choice (unsaved changes) parity**: the three-choice unsaved-changes dialog (`showUnsavedChanges`) shares the two-choice look: a title without a close icon, a plain `TextButton` dismissal action first ("Keep editing"), a destructive red-filled Discard, and a primary Save, in that order. Because three content-width buttons may not fit one action row, they may stack vertically on phone widths (dismissal top, confirming bottom); the ordering rule above still holds. Both dialog shapes build every action button from one shared style helper in `confirmation_dialog.dart`, so the destructive fill and the button shape cannot drift between them.

Verified by `test/widgets/confirmation_dialog_alignment_test.dart` (group `Mock ConfirmationDialog - unsaved-changes alignment`: `three-choice drops the X and orders Keep editing / Discard / Save`, `PARITY: Discard matches a destructive confirm, Keep editing matches Cancel`, `PARITY: the destructive fill is not the primary fill`, `every action stays tappable without overflow at 280x700` and `…at 320x568`, `barrier tap coalesces to keepEditing`).

The two-tier classification serves the UX goal of drawing the eye to potentially destructive actions while normalizing routine confirmations. Styling is machine-enforced by the component; individual screens do not vary the treatment.

### Dialog Buttons

`TextButton` is acceptable inside `AlertDialog` for Cancel/Dismiss. It must still set `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))`. Do not use `OutlinedButton` inside dialogs. Both `ConfirmationDialog` shapes build their action buttons from one shared style helper in `confirmation_dialog.dart`; a new dialog shape must reuse that helper rather than hand-rolling its own `ButtonStyle`.

### OmniTheme Tokens

Button geometry is tokenised on `OmniTheme`: `buttonBorderRadius` (primary and row-pair), `buttonUtilityRadius` (utility and dialog), `buttonIconRadius` (icon-only square), `buttonPrimaryHeight`, `buttonIconSize`, and the shared bottom-CTA insets `bottomCTAHorizontalPadding`, `bottomCTAVerticalTopPadding`, `bottomCTAVerticalBottomPadding`, and `formBottomCTAClearance`. Reference the token; never restate or hardcode its value.

### Primary Bottom CTA — shared width and vertical anchor (MANDATORY)

Every screen that exposes a primary bottom action **must** use
[`OmniBottomCTA`](widget_catalog.md#omnibottomcta) as the
`Scaffold.bottomNavigationBar` (or, for screens with a custom
`Stack`, as a `Positioned(left: 0, right: 0, bottom: 0, child: OmniBottomCTA(...))`).

The shared widget enforces the same width and the same vertical
anchor on every screen:

* **Width rule** — `width: double.infinity` inset by
  `OmniTheme.bottomCTAHorizontalPadding` on each side. The
  button's left/right edges sit at exactly the same horizontal
  margin on every screen.
* **Vertical anchor rule** — `SafeArea(top: false)` (bottom on by
  default) plus `OmniTheme.bottomCTAVerticalBottomPadding`.
  The button clears the iOS home indicator and Android navigation
  bar uniformly. The user learns one location for "the main
  action" everywhere.

**Forbidden patterns** — do not bypass the shared widget at the
bottom of a screen:

* ❌ `Spacer() + SizedBox(width: double.infinity, height: buttonPrimaryHeight, child: FilledButton(...))`
* ❌ `Positioned(... bottom: 0, child: FilledButton(...))` (use `OmniBottomCTA` instead so the width rule + safe-area handling are inherited)
* ❌ Any inline `FilledButton` whose width is hard-coded or whose
  vertical anchor is derived from the body content (it moves with
  the scroll position).

**Per-screen hosts** that need a stable test target (e.g. the
food library `Key('food_form_save')`) use the `buttonKey` prop on
`OmniBottomCTA` to forward a `Key` to the rendered `FilledButton`.
The width, height, and vertical anchor remain shared; only the
test surface key is custom.

---

## Surface Boundaries: Decorative vs Interactive

The Material ColorScheme provides two outline roles to distinguish boundary purposes:

| Role | Intent | Construction | Usage |
|------|--------|-------------|-------|
| `outline` | **Interactive** — control strokes, focus rings | The stronger of the two boundary tints | Form control borders, button outlines, interactive element boundaries |
| `outlineVariant` | **Decorative** — subtle dividers, surface separation | The same subtle tint as the surface border token | Dividers between sections, card borders, passive structural separation |

Both roles are uniform across all six themes. `test/palette_legibility_contract_test.dart` enforces each role's legibility against every theme surface — `outline` strongly enough that interactive controls remain visibly bounded, `outlineVariant` quietly enough to separate without shouting.

**Where to apply**:
- Interactive control borders (switches, radio buttons, checkboxes in focused state) → `outline`
- Card/surface division borders (exercise lists, section dividers) → `outlineVariant`
- Form field focus rings → `outline`
- Passive tile / card separation → `outlineVariant`

Never hardcode these values. Always derive from `theme.colorScheme.outline` and `theme.colorScheme.outlineVariant`.

---

## Component Patterns

### Naming Conventions
| Prefix | Domain | Examples |
|--------|--------|---------|
| `Omni` | Foundational layout primitives | `OmniSurface`, `OmniGradientBackground` |
| `Energy` | Interactive card-level components | `EnergyTile`, `EnergyCore` |
| `Zen` | Brand/logo elements | `ZenHaloPainter`, `AnimatedZenHalo` |

### Surface Composition
```
OmniGradientBackground          ← Full-screen cosmic backdrop
  └── OmniSurface               ← Dark navy card with border + deep shadow
       └── Content               ← Text, icons, interactive elements
```

### Interactive Tile Pattern
```
GestureDetector (press tracking)
  └── AnimatedScale (press feedback)
       └── Container (gradient surface + shadows)
            └── EnergyCore (icon) + Label
```

### Signal Card Pattern
```
OmniSurface (neutral — one surface for both kinds)
  ├── kind row: kind icon + kind label, both textSecondary
  ├── observation (textDominant)
  ├── suggestion (textSecondary, only when the signal supplies one)
  └── dismiss control (accessibility touch-target minimum, semantic label "Dismiss signal")
```

A signal card is read, not tapped: the surface carries no tap callback and only the
dismiss control is interactive. Kind is carried by the label and the icon, never by a
colour, so both kinds draw on the same neutral `OmniSurface` and the pattern adds no
theme token. The dismiss control meets the touch-target minimum in
[Accessibility Requirements](#accessibility-requirements). Verified by
`test/signals_layer_screen_test.dart` (`S-1704`, `S-1716`).

### Key Patterns
1. **Composable, not inherited** — primitives are combined, not subclassed
2. **State is local for UI, external for data** — `_isPressed` is local widget state; workout data comes from ChangeNotifier
3. **Constants centralized** — all design tokens live in `OmniTheme`

---

## Accessibility Requirements

1. **Contrast** — text must meet WCAG AA against surface colors; the thresholds are enforced by `test/palette_legibility_contract_test.dart`
2. **Touch targets** — all interactive elements meet the platform minimum (`kMinInteractiveDimension`)
3. **Color is never the only differentiator** — icons and labels accompany color-coded tiles
4. **Screen reader support** — all interactive elements must have semantic labels
5. **Reduced motion** — respect `MediaQuery.disableAnimations`; skip ambient animations
6. **Readability at distance** — text sizes must be legible at arm's length in gym lighting

---

## Shared pieces and rules per job

**Scope of this section.** The phone app's screens under `lib/features/` and the
shared widgets under `lib/widgets/`. `lib/watch/` is out of scope — the wrist
surface has its own component set.

One job, one shared piece. A screen that needs one of the jobs below uses the
named piece rather than building its own copy: two ways to do one job drift
apart, and each drift is a place where the app teaches the user a different
pattern.

| Job | Shared piece | Where |
|---|---|---|
| Card surface | `OmniSurface` | `lib/widgets/layout/omni_surface.dart` |
| Section / card label | `OmniCardHeader` | `lib/widgets/layout/omni_card_header.dart` |
| Screen header | `OmniBackHeader` | `lib/widgets/layout/omni_back_header.dart` |
| Primary bottom action | `OmniBottomCTA` | `lib/widgets/layout/omni_bottom_cta.dart` |
| Confirmation | `ConfirmationDialog` | `lib/widgets/dialogs/confirmation_dialog.dart` |
| Small bottom message | `OmniMessage` | `lib/widgets/feedback/omni_message.dart` |
| Empty state | `OmniEmptyState` | `lib/widgets/common/omni_empty_state.dart` |
| Trend chart | `ScrollableTrendChart` | `lib/widgets/chart/scrollable_trend_chart.dart` |
| Text-entry dialog | none yet — hand-built `AlertDialog`s | — |
| Bottom sheet | none yet — hand-built | — |

A new use of a "none yet" job must not grow the number of hand-built copies.
Both hand-built populations are ratcheted: `test/ui_standards_contract_test.dart`
(group `S-3001 hand-built sheet ratchet` · "no more hand-built sheets than the
ratchet allows" counts every `showModalBottomSheet` call outside the owner
files; group `S-3001 hand-built dialog ratchet` · "no more hand-built dialogs
than the ratchet allows" counts every raw `AlertDialog` outside
`lib/widgets/dialogs` and `lib/widgets/pickers`). The maxima live in
`test/helpers/ui_standards_allowlist.dart` (`handBuiltSheetRatchet`,
`handBuiltDialogRatchet`) and may fall, never rise.

### Messages

Every small bottom message goes through `OmniMessage`. A failure message is
plain, says what failed and what to do, and never carries exception text. When
the load of a screen's data fails, the screen says so and offers a retry
instead of reading as empty — this holds for Stats, Records & Trends and
Exercise Progress. The PR celebration toast is the one exception: it keeps its
own celebration look.

Verified by `test/ui_standards_contract_test.dart` (group `S-2702 one message
look` · "no file outside the two that own a look builds a message bar"; group
`S-2703 no exception text in a message` · "no message in lib/ interpolates an
exception"), `test/omni_message_test.dart` (group `S-2701: OmniMessage on the
${entry.key} theme`) and `test/stats_load_failure_test.dart` (group `S-2704: a
failed load is not an empty state`).

### Failure copy

A failure shown to the user is plain words — in a message, on a screen or in a
dialog — and says what to do next; the exception text goes to the console
(`debugPrint`), never to the UI.

Verified by `test/profile_screen_test.dart` (group `D-27.2: a failed profile
load says so in plain words` · "the screen shows the plain line and the
exception text is nowhere on it"), by `test/session_screen_build_phase_notify_test.dart`
("D-27.2 a failed session load says so in plain words and hides the
exception") and by `test/interaction_flow_test.dart` (group
`ExerciseEditorScreen interactions` · "a failed save shows plain copy, never
the exception text"). For messages the rule is scanned across all of `lib/` by
`test/ui_standards_contract_test.dart` (group `S-2703 no exception text in a
message` · "no message in lib/ interpolates an exception").

### Empty states

Every screen or list with nothing to show uses `OmniEmptyState`: a muted icon,
a title, and an optional one-line hint saying what to do next. The compact form
is for use inside a card. A trend with no data says so and never draws a zero
line. Two exceptions stay outside the widget: tiny inline notes inside a
populated card, and action surfaces — the live session list's empty case is a
call to act, not a message.

Verified by `test/ui_standards_contract_test.dart` (group `S-2804 one
empty-state composition` · "only one empty-state class is declared in lib/"),
`test/omni_empty_state_test.dart` (group `S-2801 OmniEmptyState`), the
per-screen empty cases in `test/screen_widget_test.dart` and
`test/pr8_exercise_library_test.dart` ("empty … renders the shared
OmniEmptyState (S-2802)"), and `test/nutrition_trend_screen_test.dart` (group
`no food logged` · "shows the empty state, never an all-zero chart").

### Unsaved work

Any screen with a Save action warns before discarding typed or changed work,
through `ConfirmationDialog.showUnsavedChanges`. Named exceptions: the screens
that auto-save (Edit Food) and the live session, where nothing is unsaved by
design.

Verified by `test/screen_widget_test.dart` (group `CreatePeriodScreen unsaved
changes guard (S-2901)`) and `test/nutrition_test.dart` (groups
`NutritionTargetScreen — unsaved changes guard (S-2902)`, `AddFoodScreen — New
Food form unsaved guard (S-2902)`, `AddFoodScreen — legacy edit shim unsaved
guard (S-2902)`). The every-screen generalisation is *unguarded* — no scan
covers it.

### Deleting

Every delete or remove of the user's data confirms first, through the shared
destructive dialog (`ConfirmationDialog` with `isDestructive`). Exceptions: the
category delete that needs a destination picker keeps its bespoke dialog with
the standard button shape, and info-only dialogs are not confirmations.

Verified by `test/nutrition_test.dart` (group `ManageFoodLibrary – add/remove
toggle` · "tapping Remove asks first, and Cancel keeps the food in the library
(S-2903)"; group `AddFoodScreen — Groups tab` · "trash on an empty category
asks first, and Cancel keeps it (S-2904)" and "confirming the delete archives
an empty category (S-2904)"). The every-screen generalisation is *unguarded*.

### Destructive and fixed colours

Destructive icons and buttons use the theme's error role, never a hardcoded
red. A fixed colour is allowed only where the colour *is* the thing — a scrim,
a shadow, a user-chosen colour — and each such site is listed with its reason
in `test/helpers/ui_standards_allowlist.dart`.

Verified by `test/ui_standards_contract_test.dart` (group `S-2604 no raw
colours` · "every raw colour in lib/ is a fixed site or an allowlisted one";
group `allowlist self-check` · "every allowlist entry still matches a line in
its file" and "every ratchet entry still names a file that uses the name";
group `S-2607 colour ratchet` · "no file uses Colors.white or Colors.black
above its ratchet").

### Label case

Case is part of the `OmniCardHeader` title string, not a style the widget
applies. Screen-level section labels are uppercase; the per-exercise-kind
lists on Stats and the Fuel row are title case.

*Unguarded*, except `test/instrument_list_screen_test.dart` (group `S-1001` ·
"four sections render in the order Resistance, Cardio, Isometric, Sports"),
which pins the four title-case labels.

### Bottom actions

A screen's primary bottom action is one of three cases: the shared
`OmniBottomCTA`; the Cancel + Save pair in the routine editor (a named
exception — the pair is the screen's content, not a single anchored action);
or an inline button on a first-run or startup screen, where there is no screen
to anchor to.

*Unguarded.*

### Accessibility and shape

Every `IconButton` carries a tooltip; every button sets its `shape` explicitly;
no screen builds a raw Material `Card`.

Verified by `test/ui_standards_contract_test.dart` (group `S-2606 IconButton
tooltip` · "every IconButton in lib/ carries a tooltip"; group `S-2601 button
shape` · "every button constructor in lib/ sets a shape"; group `S-2603 no raw
Card` · "no feature or widget file builds a raw Card"). Text size is
*unguarded* (the text-scale audit was never finished).

## How these rules are enforced

**Source scans.** `test/ui_standards_contract_test.dart` reads `lib/` as text,
so a rule about how a constructor is called holds at every call site, not only
where a test renders. Its groups: `S-2601 button shape`, `S-2603 no raw Card`,
`S-2604 no raw colours`, `S-2606 IconButton tooltip`, `S-2607 colour ratchet`,
`S-2702 one message look`, `S-2703 no exception text in a message`,
`S-2804 one empty-state composition`, `S-3001 hand-built sheet ratchet`,
`S-3001 hand-built dialog ratchet`, and `allowlist self-check`.

**The allowlist.** `test/helpers/ui_standards_allowlist.dart` is the one place
a scan may excuse a site. Entries are only ever removed: a fixed violation
makes the self-check fail until its entry is gone. Adding an entry needs an
owner-approved reason in a plan, and the reason must say what makes the site
different from every other call site.

**Ratchets.** Three populations may fall, never rise: the `Colors.white` /
`Colors.black` per-file counts (S-2607), the hand-built bottom sheets
(`handBuiltSheetRatchet`) and the raw `AlertDialog`s outside the dialog and
picker folders (`handBuiltDialogRatchet`). The maxima live in
`test/helpers/ui_standards_allowlist.dart`; a file the colour map does not
list may not use the name at all.

**Docs checks.** `test/docs_indexing_contract_test.dart` (group `Docs indexing
contract`) keeps the docs honest: the per-file size ceiling, no hexadecimal
colour literals, no step-by-step flow walkthroughs, no scheduling or roadmap
annotations, every relative link resolving and reachable, every `Omni…` symbol
the design docs name declared in `lib/` ("every Omni symbol the design docs
name is declared in lib/"), and no measurement value or percentage in a design
doc ("no design doc carries a unit value or a percentage").

**Fix what you touch.** A change that edits a file carrying a listed deviation
fixes it in the same change, or records why not. The reviewer treats a new
allowlist entry or a raised ratchet as a blocker. *Unguarded* — this is a
process rule, not a test.

---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
