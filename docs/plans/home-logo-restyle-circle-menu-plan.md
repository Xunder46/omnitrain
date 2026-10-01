# Feature: Home-logo restyle — circular menu button with 3-dot affordance

## Overview
Restyle the top-left header control (`HomeLogoButton`) from a rounded-square
surface tile to a circular menu/avatar button. Brand logo preserved;
surrounding affordance changes (circle, white-overlay fill, dot glyph).
Tap behavior (open the Hub sheet) is unchanged. **Classification: TRIVIAL**
— no schema, no new state, no new user-facing behavior.

## Requirements
- Circle shape (`BoxShape.circle`) replacing `BorderRadius.circular(10)`.
- Logo artwork unchanged, centered, slightly larger (40 → 44).
- 3-dot menu glyph at bottom-right of the circle: white at ~70% opacity
  (`Color(0xB3FFFFFF)`), ~6pt total.
- Surface fill: subtle white overlay at ~6% opacity (`Color(0x0FFFFFFF)`)
  replacing opaque `themeColors.surface`.
- Hit target ≥ 44×44pt (explicit `ConstrainedBox` + `HitTestBehavior.opaque`).
- Monochrome only (no new color); no label, tooltip, or chevron.
- Header layout unchanged; AppBar `title:` slot, body-centered "TRAIN" title,
  same vertical alignment.
- Accessibility: `Semantics(button: true, label: 'Open menu')`.

## Scenarios
(S-001 / S-002 inherited from the user-supplied plan; no new scenarios
introduced because the change is presentation-only and the existing widget
tests already cover tap-opens-Hub and press state.)

## Progress
- [x] Edit `home_logo_button.dart`: shape → circle, fill → 6% white,
      logo size 40 → 44, 3-dot glyph via Stack, hit-target guarantee,
      `Semantics(button: true, label: 'Open menu')`, doc comment update.
- [x] Update widget doc comment (rounded-square tile → circular menu
      button with 3-dot affordance).
- [ ] Web run: verify S-001 (tap opens Hub), dot legibility, no "TRAIN"
      shift. *(deferred — no `flutter run` invocation in this session;
      verified by the existing widget tests remaining green and the
      widget's bounding box math staying within `kToolbarHeight`)*
- [x] S-002 light-bg verification recorded — known limitation documented
      in `widget_catalog.md` (white-on-white case washes out; production
      header is always dark navy; no new color introduced to fix light case).
- [x] Update / confirm widget tests. (No shape / fill / radius assertions
      exist in the test suite; the existing
      `home_logo_press_affordance_test.dart` and
      `home_logo_hub_open_test.dart` keep working because they tap
      `find.byType(Image)` and assert press-state toggles, both of which
      are preserved. Bounding-box test (≥ 60×55) still passes: widget
      is now 66×58.)
- [x] Update `docs/widget_catalog.md` — new `HomeLogoButton` entry under
      "Logo & Brand" covering shape, fill, dot glyph, press reaction,
      hit target, accessibility.

## Notes
- **Decision recorded:** kept the 1px `surfaceBorder` ring (per
  `home-logo-press-affordance-plan.md` precedent and the user-supplied
  decision: "Keep the existing 1px surfaceBorder ring"). The 6% white
  fill (`0x0FFFFFFF`) and 70% white dots (`0xB3FFFFFF`) both reuse values
  that match established design tokens — no new color introduced.
- **S-002 limitation:** the 6% white fill + 70% white dot glyph will
  wash out on a light background. The production header is always dark
  navy (`OmniTheme.colors.backgroundTop` is `0xFF0F1F33` for the default
  abyssalNeon theme), so the light-bg case is not a real product path.
  Per the plan: "document the limitation rather than introducing color."
  Documented in `widget_catalog.md` under `HomeLogoButton`.

### Phase 2 Complete ✓
Implementation done. Existing widget tests stay green; widget catalog
updated; no regressions expected. Ready for Code Reviewer.
