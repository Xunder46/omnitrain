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

| Theme | Enum | Primary | Character |
|-------|------|---------|-----------|
| Abyssal Neon | `abyssalNeon` | `#2DE2E6` Neon cyan | Deep cosmic, high-contrast blue-teal |
| Forge & Ember | `forgeEmber` | `#FF7B45` Ember orange | Hot molten steel, industrial warm |
| Obsidian Volt | `obsidianVolt` | `#E8B420` Amber volt | Dark electric, controlled amber |
| Void Pulse | `voidPulse` | `#A478FF` Deep violet | Cosmic meditative, purple-galaxy |
| Crimson Dojo | `crimsonDojo` | `#FF4C47` Crimson red | Martial aggression, deep red |
| Malachite Core | `malachiteCore` | `#24B85A` Deep emerald | Industrial, geological, mineral-veined rock face |

---

### Theme: Abyssal Neon Dark

| Token | Hex | Role |
|-------|-----|------|
| Background Top | `#0F1F33` | Deep navy gradient start |
| Background Bottom | `#060B14` | Near-black gradient end |
| Surface | `#0E223A` | Card/panel background |
| Surface Border | `#FFFFFF` @ 6% | Subtle boundary definition |
| Primary (Neon Cyan) | `#2DE2E6` | Interactive elements, accents |
| Secondary (Muted Teal) | `#1B9AAA` | Supporting accents |
| Zen Core Glow | `#00CFFF` | Logo/brand element glow |
| Text Primary | `#FFFFFF` @ 90% | Main content text |
| Text Secondary | `#FFFFFF` @ 70% | Supporting text, labels |
| Material Background | `#0B0F14` | Material theme scaffold |
| Material Surface | `#121826` | Material component surfaces |
| Text Muted | `#9BA4B5` | Tertiary text |
| Divider | `#1F2937` | Separators |

### Theme: Malachite Core

Character: deep emerald, geological, industrial — a mineral-veined rock face under tungsten light. Closest mood sibling to Void Pulse but grounded and earthy rather than cosmic. Primary hue ≈ 147° HSL, unambiguously green (well clear of the teal boundary at ~170°). Sole green theme in the permanent roster.

| Token | Hex | Role |
|-------|-----|------|
| Background Top | `#0D1F10` | Dark warm green-black gradient start |
| Background Bottom | `#060C08` | Near-black gradient end, slightly warmer |
| Surface | `#122214` | Warm dark green-black card surface |
| Surface Border | `#FFFFFF` @ 5% | Subtle boundary (matches Forge & Ember weight) |
| Primary (Deep Emerald) | `#24B85A` | Bright emerald accent — CTAs, active states |
| Secondary (Forest Emerald) | `#128A40` | Supporting accent, clears 3:1 on surface |
| Text Muted | `#7FAA7F` | Darker metadata green for stronger emphasis-tier separation |
| Divider | `#172A18` | Warm dark green separator |

### Color Usage Rules
1. **Background** is always the cosmic gradient — never flat
2. **Surfaces** float above the background with depth (shadow + border)
3. **Cyan/teal accents** indicate interactivity or active state — never decorative filler
4. **White text** with opacity levels creates hierarchy without introducing new hues
5. **Home tiles** use a solid low-opacity accent fill (primary ~18%, secondary ~8%) with a 1px white top rim highlight and 1px black bottom inner shadow on primary tiles; secondary tiles (Free, Routines) have no rim or inner shadow. Tile gradients are intentionally not used — see `EnergyTile` and `HomeTileConfig.isSecondary`.
6. **Glow effects** are reserved for active/selected states and brand elements
7. **Modality accent colors** must come from `lib/core/constants/modality_colors.dart` (single source of truth) and must not be hardcoded in screens/components

### Emphasis Tiers

OmniTrain’s shared text hierarchy is expressed through `OmniTheme.colors`:

| Token | Role |
|-------|------|
| `textDominant` | Hero headings, primary back arrows, selected/active emphasis |
| `textSecondary` | Supporting text, secondary icons, subdued labels |
| `textMuted` | Tertiary metadata, chrome, status labels |
| `textDisabled` | Disabled controls and unavailable states |

`primary` remains the primary-action accent used for CTAs and active indicators.

### Phase 1B Tier Values

| Theme | `textDominant` | `textSecondary` | `textMuted` | `textDisabled` | `primary` |
|-------|----------------|-----------------|-------------|----------------|-----------|
| Abyssal Neon | `#FFFFFF` @ 95% (`0xF2FFFFFF`) | `#FFFFFF` @ 60% (`0x99FFFFFF`) | `#7A8899` | `#FFFFFF` @ 30% (`0x4DFFFFFF`) | `#2DE2E6` |
| Forge & Ember | `#FFF5EA` @ 94% (`0xF0FFF5EA`) | `#FFFFFF` @ 60% (`0x99FFFFFF`) | `#8A5C4E` | `#FFFFFF` @ 30% (`0x4DFFFFFF`) | `#FF7B45` |
| Obsidian Volt | `#FFFFFF` @ 95% (`0xF2FFFFFF`) | `#FFFFFF` @ 60% (`0x99FFFFFF`) | `#6E6240` | `#FFFFFF` @ 30% (`0x4DFFFFFF`) | `#E8B420` |
| Void Pulse | `#FFFFFF` @ 95% (`0xF2FFFFFF`) | `#FFFFFF` @ 60% (`0x99FFFFFF`) | `#6B5B8A` | `#FFFFFF` @ 30% (`0x4DFFFFFF`) | `#A478FF` |
| Crimson Dojo | `#FFFFFF` @ 95% (`0xF2FFFFFF`) | `#FFFFFF` @ 60% (`0x99FFFFFF`) | `#A07060` | `#FFFFFF` @ 30% (`0x4DFFFFFF`) | `#FF4C47` |
| Malachite Core | `#FFFFFF` @ 95% (`0xF2FFFFFF`) | `#FFFFFF` @ 60% (`0x99FFFFFF`) | `#7FAA7F` | `#FFFFFF` @ 30% (`0x4DFFFFFF`) | `#24B85A` |

### Macro Chart Palette

`OmniTheme.colors.macroChart` is a five-slot palette for the daily
nutrition macro-distribution donut (`MacroDonutChart`). The first
four slots map 1:1 to the four arc sections drawn by the chart;
the fifth slot, `chartLabelDark`, is the dark text color used for
in-band labels on **light** section backgrounds (the light
counterpart is the theme's existing `textDominant` token, used
for labels on dark section backgrounds). Each theme defines a
value tuned for contrast on its background:

| Slot | Role | Abyssal Neon | Forge & Ember | Obsidian Volt | Void Pulse | Crimson Dojo | Malachite Core |
|------|------|--------------|---------------|---------------|------------|--------------|----------------|
| `protein` | Protein slice | `#EDEDED` | `#EDE3D2` | `#EDEDED` | `#EDEAFA` | `#EDE3DE` | `#EDEDE7` |
| `netCarbs` | Net Carbs slice (`carbs − fiber`) | `#4F8DF7` | `#5BA8F2` | `#4F8DF7` | `#6E94F2` | `#5BA8F2` | `#4F8DF7` |
| `fiber` | Fiber slice | `#3FBF67` | `#54C97A` | `#3FBF67` | `#5BC982` | `#54C97A` | `#3FBF67` |
| `fat` | Fat slice | `#E8B420` | `#F2C84B` | `#E8B420` | `#E8B420` | `#F2C84B` | `#E8B420` |
| `chartLabelDark` | In-band label color on light section backgrounds | `#0B1424` | `#1A0B05` | `#0B0B0B` | `#0A071A` | `#1A0606` | `#0C0F0A` |

The palette lives on `OmniTheme` so the "theme tokens only" rule is
honoured; themes can override slots later without touching the chart.

> **Iteration 2 (`.github/agents/plans/daily-nutrition-macro-chart-plan.md`):**
> The donut's external labels were removed. The same four palette slots
> are now applied as the **band's arc colors**; the per-macro label
> content (name + grams + %) was moved into the calorie ring's center
> on tap. See `MacroDonutChart` and `MacroFocusContent` in
> `docs/widget_catalog.md`.
>
> **Iteration 3 (`.github/agents/plans/daily-nutrition-macro-chart-plan.md`):**
> The donut now also draws **in-band labels** (`"<initial> <N>g"`,
> e.g. `"N 22g"`) at each section's mid-angle, upright on the band's
> mid-radius. A luminance check via
> `ThemeData.estimateBrightnessForColor` picks the label color per
> section: light section colors (protein, fat) get
> `macroChart.chartLabelDark`; dark section colors (net carbs,
> fiber) get `textDominant`. The new `chartLabelDark` slot is the
> only addition to the palette in this iteration. A section's
> label is hidden when the painted text width exceeds the section's
> arc length at mid-radius minus an 8 px pad, and the label's alpha
> inherits the section's focus opacity (so an unfocused 0.4 section
> also has a 0.4-alpha label). The Iteration 3 polish also fixed
> the 12 o'clock seam notch — every inter-section gap (including
> the wrap-around seam) is now exactly `gapDegrees` wide. See
> `MacroDonutChart` in `docs/widget_catalog.md`.

---

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
| **Daily Nutrition** | `Today` (with `edit_targets_icon` in actions), `Foods I Eat` (with `food_library_manage_pencil` in actions) |
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
2. Tiles use `LayoutBuilder` to adapt — labels hide below 100px width
3. Generous padding and touch targets — minimum 48dp tap areas (gym gloves, sweaty fingers)
4. Vertical scrolling preferred — horizontal swipe only for carousel/peek patterns
5. Information density scales with screen size, never with complexity

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

```dart
OmniTheme.buttonBorderRadius                // 12.0 — primary, row-pair
OmniTheme.buttonUtilityRadius               // 8.0  — utility, dialog
OmniTheme.buttonIconRadius                  // 10.0 — icon-only square
OmniTheme.buttonPrimaryHeight               // 56.0 — full-width and row-pair height
OmniTheme.buttonIconSize                    // 60.0 — icon-only button size
OmniTheme.bottomCTAHorizontalPadding        // 16.0 — left/right inset for the shared bottom CTA
OmniTheme.bottomCTAVerticalTopPadding       // 24.0 — top inset inside the shared bottom CTA footer
OmniTheme.bottomCTAVerticalBottomPadding    // 16.0 — bottom inset above the device safe area
OmniTheme.formBottomCTAClearance            // 112.0 — scroll view bottom padding to clear the shared bottom CTA
```

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

## Known Inconsistencies (To Resolve)

1. **Dual color definitions** — `OmniTheme` surface/text colors diverge slightly from Material `buildTheme()` values. Custom widgets use `OmniTheme` directly; Material components use the theme. These should be unified.
2. **Hardcoded icon sizes** — 70px tile icon, 40% core percentage. Should become `OmniTheme` tokens.
