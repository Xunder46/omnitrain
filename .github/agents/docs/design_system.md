# OmniTrain Design System

## Core Design Philosophy: Minimum Friction

Every design decision serves one question: **does this help the athlete get to work faster?**

- If a UI element requires waiting, it should be eliminated or deferred
- If an interaction requires multiple taps, it should be reduced to one
- If information is decorative rather than functional, it must still earn its place by enhancing focus or reducing cognitive load
- The app is a tool, not a destination — beautiful, but never in the way

### The Splash Screen Litmus Test

A splash screen was added and then commented out. The reasoning: "I don't want to look at the splash logo, I am here to workout." This is the benchmark for every design decision. If it doesn't serve the workout, it doesn't belong in the critical path.

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

**Values live in `lib/core/constants/omni_theme.dart` and nowhere else.** This document names tokens and says what each is for; it does not restate what any of them equal.

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
3. **Cyan/teal accents** indicate interactivity or active state — never decorative filler
4. **White text** with opacity levels creates hierarchy without introducing new hues
5. **Home tiles** use a solid low-opacity accent fill (primary ~18%, secondary ~8%) with a 1px white top rim highlight and 1px black bottom inner shadow on primary tiles; secondary tiles (Free, Routines) have no rim or inner shadow. Tile gradients are intentionally not used — see `EnergyTile` and `HomeTileConfig.isSecondary`.
6. **Glow effects** are reserved for active/selected states and brand elements
7. **Modality accent colors** must come from `lib/core/constants/modality_colors.dart` (single source of truth) and must not be hardcoded in screens/components

## Typography

| Level | Style | Spacing |
|-------|-------|---------|
| Headers | Letter-spacing 3.0 | Wide, commanding — section titles, brand text |
| Titles | Letter-spacing 0.4 | Slightly tracked — card labels, navigation |
| Labels | Letter-spacing 2.0 | Uppercase or small-caps feel — chip labels, metadata |
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
| Letter spacing | `2.0` | The "Labels" track — uppercase or small-caps feel. |
| Color | `OmniTheme.colors.textMuted` | Quiet, secondary hierarchy; never louder than the card body. |
| Overflow | `maxLines: 1, overflow: TextOverflow.ellipsis` | Long titles (e.g. month labels, dates) truncate gracefully rather than wrap. |

### Where the canonical header is used

Every section / card header in the app routes through `OmniCardHeader`. The widget enforces the contract above; raw `Text` widgets above outlined cards are **not permitted** (see `docs/global_conventions.md`).

| Screen | Headers |
|--------|---------|
| **Settings** | `PREFERENCES`, `SOUNDS & ALERTS`, `WORKOUT`, `APPEARANCE` |
| **Session Summary** | Date (with the modality chip in actions), `SESSION NOTE` (note card), month label (with `Open Calendar` in actions) |
| **Daily Nutrition** | `Today` (with `nutrition_target_button` labelled `OutlinedButton.icon` in actions — PR 3 / S-002), `Foods I Eat` (with `food_library_manage_pencil` in actions) |
| **Profile** | One header per measurement definition (label + `+` add button in actions) |
| **Stats** | `ALL TIME`, `STRENGTH` / `CARDIO` (with the window chip in actions), `NUTRITION` |

### Intentional exceptions (D-10 — sheet / title chrome, not card headers)

The home screen's `HUB` eyebrow and body-centered `TRAIN` title are sheet / title chrome (they sit on top of the gradient or as the page's hero text), not card headers — they intentionally stay on their own typography (`letterSpacing: 3.0` for `TRAIN`, `letterSpacing: 2.0` for `HUB`). The onboarding screen's step label is similarly out of scope.

---

## Spacing & Layout

| Token | Value | Usage |
|-------|-------|-------|
| Surface Border Radius | 20.0 | Standard card rounding — generous, modern |
| Border Width | 1.0 | Subtle surface definition |
| Energy Core Size | 78.0 | Standard icon circle on tiles |
| Zen Halo Size | 160.0 | Logo/brand mark container |
| Halo Stroke Width | 7.0 | Enso arc thickness |

### Layout Rules
1. **Mobile-first, watch-aware** — design for the smallest screen, then scale up
2. Home training tiles derive artwork bounds and spacing from rendered tile height; artwork is decorative and is omitted when the height budget cannot accommodate it alongside the label. The label remains the identifying content. This contract is verified by the height-responsive artwork regression group in `test/widgets/energy_tile_test.dart`.
3. Generous padding and touch targets — minimum 48dp tap areas (gym gloves, sweaty fingers)
4. Vertical scrolling preferred — horizontal swipe only for carousel/peek patterns
5. Information density scales with screen size, never with complexity

### Large-screen content column (tablet / iPad / large unfolded foldable)

One app-wide layout rule, applied automatically by
`OmniGradientBackground` (see the [Widget Catalog](widget_catalog.md)
"OmniGradientBackground" entry). Screens do not opt in or out; the
behavior is consistent across every screen.

- **Phone-class widths** (≤ `OmniTheme.kColumnMinActivationWidth` =
  500 dp, includes every phone and a foldable in folded state): the
  centered column is **inert**. Content fills the surface edge to
  edge. Phones are byte-for-byte identical to today.
- **Tablet-class widths** (> 500 dp, includes every tablet and a
  large unfolded foldable): content sits in a horizontally centered
  column of `OmniTheme.kColumnMaxWidth` = 480 dp, with equal empty
  margins on both sides. The column is a hard cap — it does not
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

| Shadow | Properties | Usage |
|--------|-----------|-------|
| Deep Shadow | Black 55%, blur 30, offset (0, 14) | All elevated surfaces — strong vertical lift |
| Glow Shadow | Color-based, blur 24, spread 0, 35% opacity | Active states, energy cores, brand elements |
| Active Border | White @ 15%, 2px width | Selected/active tile indicator |

### Depth Rules
1. Every card/surface has `deepShadow` — no flat surfaces floating in space
2. Glow is additive — only appears on interaction or active selection
3. Shadow direction is always **downward** — consistent overhead light source
4. Never use drop shadows on text

---

## Interaction & Animation

| Token | Value | Purpose |
|-------|-------|---------|
| Press Scale | 0.96 | Tactile press feedback |
| Animation Duration | 180ms | Standard transition |
| Animation Curve | easeInOut | Smooth, natural motion |
| Splash Duration | 2800ms | Brand animation (deferred) |
| Stroke Draw | 1200ms | Enso arc reveal |
| Breathing Pulse | 3000ms | Ambient logo animation |
| Rotation | 8000ms | Slow perpetual logo rotation |

### Animation Rules
1. **Interactions are instant-feeling** — 180ms is the maximum for press/release feedback
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

| Variant | Widget | Height | Radius | Padding | Width |
|---------|--------|--------|--------|---------|-------|
| Primary | `FilledButton` | 56 dp | 12 | `symmetric(horizontal: 24)` | Full-width (`double.infinity`) |
| Row-pair | `FilledButton` / `OutlinedButton` | 56 dp | 12 | `symmetric(vertical: 16)` | `Expanded` (50/50 split) |
| Utility | `OutlinedButton.icon` | ≥48 dp | 8 | `symmetric(horizontal: 12, vertical: 8)` | Content-width |
| Icon-only | `FilledButton` + icon | 60 × 60 dp | 10 | None | 60 × 60 dp |
| Dialog | `TextButton` / `FilledButton` | Std | 8 | Default | Content-width |

### Shape Rule (MANDATORY)

Every `FilledButton`, `OutlinedButton`, or `TextButton` MUST explicitly set `shape`. Never rely on Material 3 defaults.

```dart
// ✅ Correct — shape always explicit
FilledButton(
  style: ButtonStyle(
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
      ),
    ),
  ),
  onPressed: onPressed,
  child: const Text('Finish Workout'),
)

// ❌ Wrong — Material 3 default StadiumBorder fires
FilledButton(
  style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 16)),
  onPressed: onPressed,
  child: const Text('Start Workout'),
)
```

### Press Feedback

All buttons use the same press-scale system as tiles:

```dart
GestureDetector(
  onTapDown: (_) => setState(() => _isPressed = true),
  onTapUp: (_) => setState(() => _isPressed = false),
  onTapCancel: () => setState(() => _isPressed = false),
  child: AnimatedScale(
    scale: _isPressed ? OmniTheme.pressedScale : 1.0,  // 0.96
    duration: OmniTheme.animationDuration,              // 180ms
    curve: OmniTheme.animationCurve,                   // easeInOut
    child: /* button */,
  ),
)
```

> Note: `FilledButton` / `OutlinedButton` already provide their own ink press feedback. Wrap in `AnimatedScale` only for high-prominence primary buttons where visceral feedback matters (e.g. "Finish Workout", "Start Workout"). Skip for utility and dialog buttons.

### Colour

| Variant | Fill | Border | Text/Icon |
|---------|------|--------|-----------|
| Primary / Row-pair `FilledButton` | `theme.colorScheme.primary` (neon cyan) | — | `Colors.black` (auto via `onPrimary`) |
| Row-pair `OutlinedButton` | Transparent | `theme.colorScheme.primary` | `theme.colorScheme.primary` |
| Utility `OutlinedButton.icon` | Transparent | `theme.colorScheme.primary` | `theme.colorScheme.primary` |
| Icon-only `FilledButton` | `theme.colorScheme.primary` | — | `Colors.black` |

Never hardcode button colours. Always derive from `theme.colorScheme`.

### Destructive Actions

Destructive buttons (delete, discard) use `FilledButton` with `backgroundColor: Colors.red.shade700`, same radius rules, never a different shape.

### Dialog Buttons

`TextButton` is acceptable inside `AlertDialog` for Cancel/Dismiss. It must still set `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))`. Do not use `OutlinedButton` inside dialogs.

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
  `OmniTheme.bottomCTAHorizontalPadding` (16) on each side. The
  button's left/right edges sit at exactly the same horizontal
  margin on every screen.
* **Vertical anchor rule** — `SafeArea(top: false)` (bottom on by
  default) plus `OmniTheme.bottomCTAVerticalBottomPadding` (16).
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

### Key Patterns
1. **Composable, not inherited** — primitives are combined, not subclassed
2. **State is local for UI, external for data** — `_isPressed` is local widget state; workout data comes from ChangeNotifier
3. **Deprecated widgets redirect** — old widgets are stubs pointing to canonical implementations
4. **Constants centralized** — all design tokens live in `OmniTheme`

---

## Accessibility Requirements

1. **Contrast** — text must meet WCAG AA (4.5:1 for body, 3:1 for large text) against surface colors
2. **Touch targets** — minimum 48x48 dp for all interactive elements
3. **Color is never the only differentiator** — icons and labels accompany color-coded tiles
4. **Screen reader support** — all interactive elements must have semantic labels
5. **Reduced motion** — respect `MediaQuery.disableAnimations`; skip ambient animations
6. **Readability at distance** — text sizes must be legible at arm's length in gym lighting

---


---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
