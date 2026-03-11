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

### Color Usage Rules
1. **Background** is always the cosmic gradient — never flat
2. **Surfaces** float above the background with depth (shadow + border)
3. **Cyan/teal accents** indicate interactivity or active state — never decorative filler
4. **White text** with opacity levels creates hierarchy without introducing new hues
5. **Gradient colors** on tiles are functional — they differentiate workout categories
6. **Glow effects** are reserved for active/selected states and brand elements

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
OmniTheme.buttonBorderRadius        // 12.0 — primary, row-pair
OmniTheme.buttonUtilityRadius       // 8.0  — utility, dialog
OmniTheme.buttonIconRadius          // 10.0 — icon-only square
OmniTheme.buttonPrimaryHeight       // 56.0 — full-width and row-pair height
OmniTheme.buttonIconSize            // 60.0 — icon-only button size
```

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
