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
/// The outer transparent Padding insets the visible circle from the AppBar's
/// left edge and the status bar, and reserves room for the shadow's blur. It
/// also guarantees a tappable hit region of at least 44×44pt, supplemented by
/// an explicit `ConstrainedBox` minimum on the gesture bounds.
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

    // Circle surface: subtle white overlay (matches the
    // `OmniTheme.colors.surfaceBorder` token value, 0x0FFFFFFF = ~6% white)
    // so the button has presence on the dark navy header without
    // introducing a new color. The 1px `surfaceBorder` ring reinforces the
    // circle edge. The 3D feel comes from `OmniTheme.softShadow` underneath.
    final tile = Container(
      width: widget.tileSize,
      height: widget.tileSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color.fromARGB(0, 0, 0, 0),
        border: Border.all(
          color: themeColors.surfaceBorder,
          width: OmniTheme.surfaceBorderWidth * 2,
        ),
        boxShadow: [OmniTheme.softShadow],
      ),
      padding: EdgeInsets.all(innerPadding),
      child: Padding(
        padding: const EdgeInsets.only(right: 1), // tweak: 1–4
        child: Center(child: artwork),
      ),
    );

    // Internal margin so the circle's soft shadow has full room to render
    // and the visible button reads with breathing room inside the AppBar.
    // The AppBar's title slot is tightly sized to the toolbar height
    // (kToolbarHeight = 56px); this padding insets the visible circle from
    // the widget's left edge (away from the screen edge) and top edge (away
    // from the status bar), and reserves room for the shadow's blur on the
    // right and bottom. The padding is transparent and does not change the
    // visible circle's shape, size, fill, or logo. The widget's bounding
    // box is 72×64 (8px horizontal × 2 + 56, 4px vertical × 2 + 56), well
    // above the 44×44pt hit-target minimum even before the ConstrainedBox
    // below guarantees it. The visible circle (56px) matches kToolbarHeight
    // exactly, so the AppBar toolbar height and the body-centered "TRAIN"
    // title do not shift.
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(1, 8, 8, 4),
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
    // already provides 72×64, but ConstrainedBox + opaque hit-test
    // behaviour make the guarantee explicit and resilient.
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
