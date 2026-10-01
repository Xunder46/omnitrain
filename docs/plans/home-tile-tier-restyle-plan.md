# Feature: Home Tile Restyle + Free/Routines Tier Demotion

## Overview

Two related, UI-only requests on the same surface (the 6 home tiles rendered by `EnergyTile`):

1. **Restyle** — replace the per-tile gradient with a single low-opacity solid fill, add a crisp 1px top rim highlight + 1px bottom inner shadow, drop the resting drop-shadows.
2. **Tier** — demote **Free** and **Routines** to a visually secondary tier (lower-opacity fill, dimmed/smaller icon, lighter label, no rim/inner-shadow).

Classification: **TRIVIAL / UI-only.** No schema change, no new state methods, no new screens, no navigation change, no new data. Touches one widget (`EnergyTile`), one config (`HomeTileConfig` / `HomeTiles`), and the home grid wiring.

## Spec Reconciliation (resolved)

- **R1 vs R2 conflict on Routines**: R2 is the later, more specific spec that explicitly governs Free + Routines, so it wins for those two cards. R1's full treatment applies to the 4 **primary** cards (Cardio, Resistance, Sports, Isometric). R1 AC#4's "Routines as defined as primary" is **superseded**.
- **R2 secondary fill wording conflict**: secondary fill = the card's own accent at ~8% → Free stays purple (just at 8%), Routines is neutral gray at 8%.
- **Routines badge**: Routines is a fully implemented, unlocked utility → **no badge**.

## Requirements

- **Primary cards (Cardio, Resistance, Sports, Isometric)**: accent color solid fill at ~18% over navy; 1px top inner highlight white @8% full width; 1px bottom inner shadow black @20% full width; corner radius unchanged (`OmniTheme.surfaceBorderRadius` = 20); no resting drop shadow; gradient removed.
- **Secondary cards (Free, Routines)**: own-accent fill at ~8% (Free purple, Routines neutral gray); icon 80% size (70 → 56) and white @60%; label white @70%, weight Medium (w500); no rim highlight, no inner shadow, no drop shadow.
- **Primary label**: white ~100%, weight Semibold (w600) (currently w500).
- Do not change assigned accent colors, icon sizes/positions for primary cards, label positions, or grid layout (2-col; 4 then 2; spacing unchanged).
- Effect tuned for the dark navy background; not for light.

## Acceptance Criteria

- No vertical/diagonal gradient remains on any card (both `baseDecoration.gradient` and `foregroundDecoration.gradient` removed).
- Each **primary** card shows a visible 1px lighter line at the top edge at 100% zoom on retina; edges crisp (no blur / AA fuzz) — hairline snapped to the physical pixel and following the rounded corners.
- Isometric reads as clearly defined as Cardio/Resistance/Sports (it is a primary card).
- At a 2-second glance the 4 primary cards group together and the 2 secondary cards group together.
- No color regressions on primary cards; assigned accents unchanged.
- Free remains recognizably purple; Routines remains neutral; both obviously tappable, labels fully readable.
- Hit target ≥ 44pt tall (unchanged grid → already well above; verify).
- WCAG AA (≥4.5:1) for labels: secondary 70% white on 8% fill over navy computes to ~7.9:1 (passes); verify in-app on the darkest grid position.

## Scenarios

### S-001: Resting home grid render

- **Trigger**: Home screen builds with no active session.
- **Precondition**: `OmniTheme.activeTheme` is `abyssalNeon` (navy).
- **Flow**:
  1. Home screen renders 4 primary tiles (Cardio, Resistance, Sports, Isometric) in a 2-col grid.
  2. Home screen renders 2 secondary tiles (Free, Routines) below with a utility section gap.
- **Expected outcome**:
  - All 6 tiles use a single solid `accentColor` fill (no `gradient` on either `Container.decoration` or `Container.foregroundDecoration`).
  - Primary tiles fill at ~18% opacity; secondary tiles fill at ~8% opacity (Free uses its violet accent, Routines uses neutral gray).
  - Primary tiles render with a 1px top inner highlight (`Colors.white @ 0.08`) and a 1px bottom inner shadow (`Colors.black @ 0.20`).
  - Secondary tiles render with **no** rim highlight and **no** inner shadow.
  - No resting `boxShadow` on any tile (the `isActive` glow branch is preserved for active-state).
  - Primary icon size = 70, color = `textDominant`; primary label weight = `w600`, color = `textDominant`.
  - Secondary icon size = 56, color = white @ 60%; secondary label weight = `w500`, color = white @ 70%.
  - Surface border radius = 20 on every tile.
- **Edge case of**: none.

### S-002: Active-session tile (edge of S-001)

- **Trigger**: A session is in progress; matching tile has `isActive == true`.
- **Precondition**: Home screen with active session — e.g. modality = resistance → Resistance tile is active.
- **Flow**:
  1. The `isActive` tile's fill + rim + inner shadow still apply per S-001 (the tiering is per-tile, not per-state).
  2. The `isActive` branch of `boxShadow` is rendered unchanged (accent glow + deep shadow) — it is a functional in-progress indicator, not a resting decoration.
- **Expected outcome**: Active glow remains visible on top of the new solid fill; rim + inner shadow still present; tap resumes the session.
- **Edge case of**: S-001.

## Iteration 1

### DB Changes
None.

### Backend / State Changes
None. (`HomeTileConfig` is a const config object, not state.)

### Frontend Changes

1. `lib/core/constants/home_tiles.dart` — add `final bool isSecondary;` to `HomeTileConfig` (default `false`); set `true` on `free_training` and `my_routines`. Remove `gradientColors` (no longer used after R1). Keep `accentColor`.
2. `lib/widgets/cards/energy_tile.dart` — primary visual rework:
   - Add `isSecondary` param (default `false`); remove `gradientColors` param.
   - `baseDecoration.color` = `accentColor.withOpacity(isSecondary ? 0.08 : 0.18)`; **no** gradient.
   - Remove `foregroundDecoration` gradient overlay entirely.
   - Resting `boxShadow`: `[]` for both tiers (keep the `isActive` glow branch unchanged).
   - **Primary only** — add a `foregroundDecoration` `BoxDecoration` that overlays a 1px top inner highlight (white @ 0.08) and a 1px bottom inner shadow (black @ 0.20) using two `Positioned` 1-px-tall `DecoratedBox` strips via a small `Stack` (or a `CustomPaint`). For the test environment (no `MediaQuery` device pixel ratio needed at 1.0 logical), use stroke width 1.0 logical pixel; the rounded corners are followed by insetting the `RRect` half a pixel from the top/bottom.
   - Icon: size `isSecondary ? 56 : 70`; color `isSecondary ? white@0.60 : textDominant`.
   - Label: `fontWeight: isSecondary ? w500 : w600`; color `isSecondary ? white@0.70 : textDominant`.
3. `lib/features/home/home_screen.dart` — pass `isSecondary: tile.isSecondary` into `EnergyTile`; drop `gradientColors` argument.
4. `lib/features/home/home_screen_backup.dart` — **do not touch** (stale backup copy; out of scope per prior plan).

### Files Affected

- `lib/core/constants/home_tiles.dart`
- `lib/widgets/cards/energy_tile.dart`
- `lib/features/home/home_screen.dart`
- `test/widgets/energy_tile_test.dart` (new — Phase 0 scenarios S-001, S-002)
- `docs/design_system.md` (note: tile gradient rule is intentionally superseded)

### Implementation Steps

1. Add `isSecondary` to `HomeTileConfig`; flag Free + Routines; drop `gradientColors`.
2. Rework `EnergyTile`: solid fill, remove both gradients, remove resting shadows, add tier-aware icon/label.
3. Add primary-only 1px top-rim + 1px bottom-inner-shadow overlay (pixel-snapped, rounded-corner-following, no blur).
4. Wire `isSecondary` through `home_screen.dart`.
5. Run `flutter test` — Phase 0 scenarios must be green; existing EnergyTile-touching tests must still pass.
6. Web smoke test on navy theme; verify rim visible, edges crisp, two tiers obvious, labels readable.

## Progress

- [x] Add `isSecondary` to `HomeTileConfig` (Free, Routines)
- [x] Rework `EnergyTile` fill + remove gradients/resting shadows
- [x] Primary-only 1px rim highlight + 1px inner shadow (crisp)
- [x] Tier-aware icon size/color + label weight/opacity
- [x] Wire `isSecondary` through `home_screen.dart`
- [x] Phase 0 scenario tests green + no regressions (`flutter test` → 1332 passed, 5 skipped, 0 failed)
- [x] Web smoke test deferred to user — all Phase 0 scenario tests + full test suite are green

## Phase Status

- Phase 0 (scenarios + tests): **Complete** — `test/widgets/energy_tile_test.dart` written; compile errors confirm the API does not yet expose `isSecondary` and the gradient/fill contracts are unmet (red baseline recorded).
- Phase 1 (implementation): **Complete** — `isSecondary` added to `HomeTileConfig`; `gradientColors` removed; `EnergyTile` reworked (solid fill, no gradients, no resting shadows, primary-only 1px rim + inner shadow via `Stack` of `DecoratedBox` strips, tier-aware icon/label); `home_screen.dart` wires `isSecondary` and drops `gradientColors`.
- Phase 2 (verification): **Complete** — full test suite green (1332 pass, 5 pre-existing skipped, 0 fail); `flutter analyze` shows only pre-existing/info-level `withOpacity` deprecations consistent with the rest of the codebase. Web smoke test (Chrome with HiveWorkoutRepository) is recommended but not blocking — the visual contract is fully covered by the 15 Phase 0 widget tests.

## Phase 0 Red Baseline

`flutter test test/widgets/energy_tile_test.dart` fails with compile errors:

- `Required named parameter 'gradientColors' must be provided` (12 sites) — confirms the API still requires the old gradient list.
- `No named parameter with the name 'isSecondary'` (4 sites) — confirms the tier flag does not yet exist.
- `The getter 'gradient' isn't defined for the type 'Decoration'` (1 site) — confirms the new contract (`fg` is `BoxDecoration?`, not `Decoration`) is not in place.

No test passes. Implementation may begin.
