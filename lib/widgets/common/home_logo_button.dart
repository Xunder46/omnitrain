import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/omni_theme.dart';

/// A small circular menu/avatar control for the home-screen AppBar that hosts
/// the brand logo. Tapping opens the Hub sheet (Calendar / Stats / Profile /
/// Nutrition / Settings).
///
/// Visually it reads as a tappable menu affordance rather than a status icon:
/// a 56×56 circle with a subtle ~6% white surface fill and a 1px
/// `surfaceBorder` outer ring, with the brand logo artwork centered inside
/// (46px in a 56px circle, 5px breathing room per side). The 3D bevel comes
/// from the existing `OmniTheme.softShadow` drop on the dark navy header —
/// no inner border, no glyph, no chevron, no label.
///
/// The outer transparent Padding insets the visible circle from the top,
/// right, and bottom edges of the AppBar and from the status bar, and
/// reserves room for the shadow's blur. It also guarantees a tappable hit
/// region of at least 44×44pt, supplemented by an explicit `ConstrainedBox`
/// minimum on the gesture bounds. The left side carries NO padding so the
/// visible 55 px circle's left edge is exactly at `titleSpacing` (16) from
/// the AppBar's content-start — the same x-coordinate the home-screen
/// training tiles start at (their outer `Padding(fromLTRB(16, 0, 16, 0))`).
/// This keeps the logo button visually aligned with the leftmost tile edge.
///
/// The press reaction (AnimatedScale to `OmniTheme.pressedScale`, light haptic
/// on non-web, reduced-motion fallback) is preserved unchanged.
class HomeLogoButton extends StatefulWidget {
  /// Callback when the logo menu button is tapped.
  final VoidCallback onTap;

  /// Size of the logo artwork inside the circle (defaults to 55). Must be
  /// less than `tileSize`; `innerPadding` is recomputed as
  /// `(tileSize - size) / 2`.
  final double size;

  /// Outer circle diameter in logical pixels. The Hub tiles are ~170px on a
  /// phone; the logo menu button is intentionally much smaller. Defaults to
  /// 56, which matches `kToolbarHeight` exactly so the AppBar toolbar height
  /// and the body-centered "TRAIN" title do not shift.
  final double tileSize;

  const HomeLogoButton({
    super.key,
    required this.onTap,
    this.size = 55,
    this.tileSize = 55,
  });

  @override
  HomeLogoButtonState createState() => HomeLogoButtonState();
}

class HomeLogoButtonState extends State<HomeLogoButton> {
  bool _isPressed = false;

  /// Public getter for testing press state.
  @visibleForTesting
  bool get isPressed => _isPressed;

  void _handleTapDown(TapDownDetails details) {
    if (mounted) setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    if (mounted) setState(() => _isPressed = false);

    // Fire haptic feedback on tap (not on cancel)
    if (!kIsWeb) {
      HapticFeedback.lightImpact();
    }
  }

  void _handleTapCancel() {
    if (mounted) setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    // Active theme tokens. The app shell keeps OmniTheme.activeTheme in sync
    // with SettingsState, so the static getter is correct here and avoids
    // threading a theme parameter through every call site.
    final themeColors = OmniTheme.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // The logo artwork, centered. Apply a subtle highlight when pressed
    // (matches the rest of the app's press feedback).
    //
    // Theme tint: the brand logo's own aqua-cyan already matches the
    // Abyssal Neon primary (`0xFF2DE2E6`), so on Abyssal Neon we render
    // the logo untouched. On every other theme we recolor the logo to that
    // theme's `primary` so the button reads as part of the active palette.
    // `BlendMode.srcATop` replaces the RGB of every opaque pixel with the
    // filter color while preserving the alpha mask, so the silhouette stays
    // crisp and we don't introduce a new color (the tint comes from an
    // existing `OmniTheme.colors.primary` token).
    Widget artwork = Image.asset(
      'assets/icon/omnitrain_logo.png',
      width: widget.size,
      height: widget.size,
    );
    if (OmniTheme.activeTheme != AppTheme.abyssalNeon) {
      artwork = ColorFiltered(
        colorFilter: ColorFilter.mode(themeColors.primary, BlendMode.srcATop),
        child: artwork,
      );
    }
    if (_isPressed) {
      artwork = ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color.fromRGBO(255, 255, 255, 0.10),
          BlendMode.modulate,
        ),
        child: artwork,
      );
    }

    // Padding so the artwork is centered inside the circle with even
    // breathing room on all sides. Defaults: tileSize=55, size=55 → 0px per
    // side. The logo artwork itself is preserved as-is and is rendered
    // centered in the circle.
    final innerPadding = (widget.tileSize - widget.size) / 2;

    // Circle edge: a single-width `surfaceBorder` ring, the same weight every
    // other surface in the app draws its border at. It was previously drawn at
    // double width, which read as heavy once the theme re-anchoring raised the
    // `surfaceBorder` token's opacity. The 3D feel comes from
    // `OmniTheme.softShadow` underneath.
    final tile = Container(
      width: widget.tileSize,
      height: widget.tileSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color.fromARGB(0, 0, 0, 0),
        border: Border.all(
          color: themeColors.surfaceBorder,
          width: OmniTheme.surfaceBorderWidth,
        ),
        boxShadow: [OmniTheme.softShadow],
      ),
      padding: EdgeInsets.all(innerPadding),
      child: Center(child: artwork),
    );

    // Internal margin so the circle's soft shadow has full room to render
    // and the visible button reads with breathing room inside the AppBar.
    // The padding is intentionally ASYMMETRIC: 0 on the left, 8 px on
    // top/right/bottom.
    //
    // The visible 55×55 circle's left edge lands at
    // `AppBar.titleSpacing` (16) from the AppBar's content-start, which
    // is the same x-coordinate the home-screen training tiles start at
    // (their outer `Padding(fromLTRB(16, 0, 16, 0))`). With 0 left
    // padding inside the logo button, the visible circle sits flush with
    // the leftmost tile edge instead of 8 px to the right of them.
    //
    // 8 px top + 8 px bottom keep the circle vertically centred and
    // reserve room for the soft shadow's blur above and below. 8 px
    // right insets the visible circle from any future AppBar trailing
    // widget. The padding is transparent and does not change the
    // visible circle's shape, size, fill, or logo. The widget's
    // bounding box becomes (55 + 8 + 8) wide × (55 + 8 + 8) tall = 63×71
    // on the horizontal — width is less than height because the left
    // padding is 0.
    //
    // The bottom padding is also what keeps the visible circle off the
    // sheet's top edge when the Hub sheet is fully expanded (the sheet
    // top lands at `padding.top + toolbarHeight`, just below the
    // AppBar's bottom edge; the 8 px bottom padding guarantees the
    // circle is fully inside the AppBar regardless of the actual
    // `toolbarHeight` configured on the host Scaffold).
    final padded = Padding(
      padding: const EdgeInsets.only(top: 8, right: 8, bottom: 8),
      child: tile,
    );

    // Press reaction: scale to OmniTheme.pressedScale, matching the Hub tile
    // family's AnimatedScale pattern. With reduced motion, the animation is
    // skipped and the scale is applied instantly.
    final scale = _isPressed ? OmniTheme.pressedScale : 1.0;
    final content = reduceMotion
        ? Transform.scale(scale: scale, child: padded)
        : AnimatedScale(
            scale: scale,
            duration: OmniTheme.animationDuration,
            curve: OmniTheme.animationCurve,
            child: padded,
          );

    // Accessibility: announce as a button with label "Open menu" (the
    // control opens the Hub sheet — a menu of calendar / stats / profile /
    // nutrition / settings — not a profile shortcut). The artwork is the
    // only foreground element; the two concentric rings are decorative and
    // are picked up by the screen reader only via the parent's label.
    final labelled = Semantics(
      button: true,
      label: 'Open menu',
      child: content,
    );

    // Hit target guarantee: ensure the gesture region is at least 44×44pt
    // even if `tileSize` is later reduced below 44. The Padding above
    // already provides 63×71 (0 left + 8 right + 8 top + 8 bottom around
    // the 55 px circle, well above the 44 pt hit target on every side
    // except the left), but ConstrainedBox + opaque hit-test behaviour
    // make the guarantee explicit and resilient.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: labelled,
      ),
    );
  }
}
