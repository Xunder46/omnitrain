// filepath: lib/features/profile/widgets/avatar_crop_sheet.dart
//
// Full-screen avatar crop step. Pushed between the photo picker
// and the avatar save so the user can frame their subject before
// committing. The picked photo is rendered into a square
// `RepaintBoundary` with an `InteractiveViewer` overlay — pinch
// and drag freely pan / zoom the image. A circular dim scrim
// above the viewport shows what the avatar will look like inside
// the circle (the avatar display path uses `ClipOval`, so the
// framed square region is clipped to a circle when shown).
//
// **The square is always full of photo.** The pannable child is
// sized so the image's *shorter* side covers the viewport (a
// cover fit) and the longer side overflows for the user to pan
// through, with `minScale: 1.0` as the cover scale. A
// `BoxFit.contain` layout would letterbox a non-square photo and
// bake the empty bands into the saved avatar, which is exactly
// the bug this arrangement prevents.
//
// **The scrim is preview chrome, never pixels.** The dim ring and
// its hairline are painted OUTSIDE the `RepaintBoundary`, so they
// frame the crop on screen without being captured into the PNG.
//
// **Output shape**. The stored avatar is a **square PNG**, NOT
// the clipped circle. The circular scrim is a preview aid only;
// the persisted file matches the full viewport. This matches the
// existing `UserProfile.avatarPath` shape (square, `ClipOval`-ed
// at display time) and avoids introducing a transparent-margin
// avatar format that the rest of the app does not render.
//
// **Capture pipeline**:
//   1. On "Use Photo", the viewport's `RenderRepaintBoundary` is
//      rendered to a `ui.Image` via `toImage(pixelRatio: 3.0)`
//      — a 3× scale produces a ~1000+ px output from a 360 dp
//      viewport, plenty for an avatar shown at any reasonable
//      size on a phone-class display.
//   2. The image is re-encoded as PNG via
//      `image.toByteData(format: ui.ImageByteFormat.png)` — the
//      `ImageByteFormat` codecs are built into Flutter, so no new
//      image-encoding dependency is added.
//   3. The PNG bytes are passed back to the caller via
//      `Navigator.pop(context, bytes)`. The caller (the
//      `ProfileScreen` `_pickAvatar` flow) persists them via
//      `ImageStorageService.persistImageBytes` and writes the new
//      basename through `state.updateAvatarPath(...)`.
//
// **Cancel** pops with `null` — the caller treats this as "do
// nothing"; the picked file is never copied into the managed dir
// and the existing avatar is untouched.
//
// **No new dependencies**. The crop step is built from
// `InteractiveViewer`, `RepaintBoundary`, and `Image.memory` — all
// in Flutter's core widget set. No plugin channel, no platform
// code. The trade-off is no fancy rotation / aspect-ratio picker;
// per the feature spec, those are explicitly out of scope.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../widgets/layout/omni_back_header.dart';

/// Avatar crop step. Pushed via `OmniNavigator.push<Uint8List?>(
///   context, (_) => AvatarCropSheet(...),
///   fullscreenDialog: true,
/// )` — the navigation contract requires every screen-level push
/// to go through `OmniNavigator` so the route is wrapped in
/// `OmniRoute` (`opaque = true` + `OmniGradientBackground`) and
/// the underlying `ProfileScreen` does not bleed through during
/// the slide-up transition. A raw `Navigator.push` + raw route
/// would leave the `Scaffold`'s transparent background exposed.
/// See `docs/navigation_and_screens.md` ("Navigation Contract")
/// and `docs/navigation_contract.md` for the full rationale.
///
/// The returned future completes with the captured PNG bytes on
/// confirm, or `null` on cancel.
class AvatarCropSheet extends StatefulWidget {
  /// Encoded image bytes (JPEG, PNG, HEIC — anything `Image.memory`
  /// decodes). Read once at construction; the widget does not
  /// re-read the source.
  final Uint8List imageBytes;

  const AvatarCropSheet({super.key, required this.imageBytes});

  @override
  State<AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<AvatarCropSheet> {
  /// Key to the viewport's `RepaintBoundary`. `findRenderObject()`
  /// on this key's `BuildContext` returns the `RenderRepaintBoundary`
  /// used to capture the framed region.
  final GlobalKey _boundaryKey = GlobalKey();

  /// Natural pixel size of the source image. `null` until the
  /// async decode finishes; the viewport falls back to a
  /// `BoxFit.cover` render (fills the square, not pannable) in
  /// that window so a capture during it is still bar-free.
  Size? _imageSize;

  /// Viewport side the current centering transform was computed
  /// for. Guards the post-frame centering so it runs once per
  /// (image, viewport) pair instead of on every build.
  double? _centeredForSide;

  /// Drives the `InteractiveViewer`. Tests set this directly to
  /// simulate a deliberate pan / zoom crop; the production UI
  /// lets the user's gestures drive it.
  final TransformationController _transformationController =
      TransformationController();

  /// True while a capture is in flight. Disables the Use Photo
  /// button so a fast double-tap cannot enqueue two captures.
  bool _isSaving = false;

  /// Exposed for tests so they can drive a non-identity
  /// transformation (a "deliberately off-center, zoomed" crop).
  /// The production UI never reads this getter.
  @visibleForTesting
  TransformationController get transformationControllerForTesting =>
      _transformationController;

  @override
  void initState() {
    super.initState();
    _decodeImageSize();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  /// Read the source image's natural pixel dimensions. The crop
  /// viewport needs them to size the pannable child so its
  /// **shorter** side matches the square viewport (a cover fit) —
  /// without them a non-square photo can only be laid out with
  /// `BoxFit.contain`, which letterboxes the square and bakes
  /// empty bars into the captured avatar.
  Future<void> _decodeImageSize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      try {
        final frame = await codec.getNextFrame();
        final size = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        frame.image.dispose();
        if (!mounted || size.shortestSide <= 0) return;
        setState(() => _imageSize = size);
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // A source the codec cannot read also cannot be rendered by
      // `Image.memory`; the viewport's cover fallback handles the
      // display and the capture path stays intact.
    }
  }

  /// Size of the pannable child for [imageSize] inside a square
  /// viewport of [side]: the image scaled so its shorter side
  /// exactly covers the viewport. The longer side overflows and
  /// is what the user pans through.
  static Size _coverChildSize(Size imageSize, double side) {
    final scale = side / imageSize.shortestSide;
    return Size(imageSize.width * scale, imageSize.height * scale);
  }

  /// Transform that parks the viewport over the centre of the
  /// cover-sized child, so the crop opens on the middle of the
  /// photo rather than its top-left corner.
  static Matrix4 _centeredMatrix(Size imageSize, double side) {
    final child = _coverChildSize(imageSize, side);
    return Matrix4.identity()
      ..translateByDouble(
        -(child.width - side) / 2,
        -(child.height - side) / 2,
        0,
        1,
      );
  }

  Future<void> _onConfirm() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final renderObject = _boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError(
          'Avatar crop viewport is not a RenderRepaintBoundary — '
          'capture cannot proceed.',
        );
      }
      final image = await renderObject.toImage(pixelRatio: _capturePixelRatio);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw StateError('Avatar crop capture produced no byte data.');
        }
        final bytes = byteData.buffer.asUint8List();
        if (!mounted) return;
        Navigator.of(context).pop(bytes);
      } finally {
        // Always dispose the decoded `ui.Image` — Flutter logs a
        // memory leak warning otherwise.
        image.dispose();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture crop: $e')),
      );
    }
  }

  /// Pixel ratio applied when capturing the viewport. 3× matches
  /// the `MediaQuery` device pixel ratio on most modern phones and
  /// produces a sharp output without ballooning the file size —
  /// a 360 dp viewport renders to 1080×1080 px, plenty for an
  /// avatar shown at any reasonable size.
  static const double _capturePixelRatio = 3.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: const OmniBackHeader(title: 'Crop Photo'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildViewport(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Pinch & drag to position',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.colors.textSecondary,
                      letterSpacing: 0.4,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  /// Square crop viewport. Renders the picked image inside an
  /// `InteractiveViewer` (free pan / zoom inside the square), with
  /// a circular dim scrim above showing the displayed-avatar
  /// shape. The whole viewport is wrapped in a
  /// `RepaintBoundary` so we can capture the rendered region as a
  /// single image on confirm.
  Widget _buildViewport(BuildContext context) {
    // Cap the viewport to `min(screenW - 32, 360)` so the square
    // is comfortably visible on every phone class without
    // requiring the user to scroll to see it.
    final screenWidth = MediaQuery.of(context).size.width;
    final viewportSide = math.min(screenWidth - 32, 360.0);

    final imageSize = _imageSize;
    if (imageSize != null && _centeredForSide != viewportSide) {
      // Centre the crop on the photo the first time both the
      // decoded size and the laid-out viewport are known (and
      // again if the viewport side changes, e.g. on rotation).
      // Assigning the controller notifies the `InteractiveViewer`,
      // so it has to happen after this frame, not during build.
      _centeredForSide = viewportSide;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _transformationController.value =
            _centeredMatrix(imageSize, viewportSide);
      });
    }

    return SizedBox(
      width: viewportSide,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Only the image layer sits inside the
            // `RepaintBoundary`. The scrim below is deliberately
            // OUTSIDE it: anything inside is baked into the
            // captured PNG, and a dimmed frame + hairline ring
            // are preview chrome, not part of the avatar.
            RepaintBoundary(
              key: _boundaryKey,
              child: ClipRect(
                child: _buildImageLayer(viewportSide, imageSize),
              ),
            ),
            // The circular dim overlay is a preview aid — the
            // persisted image is the full square viewport. The
            // overlay is `IgnorePointer`d so it never blocks the
            // `InteractiveViewer`'s gesture detector underneath.
            const IgnorePointer(
              child: CustomPaint(
                painter: _CircularCropOverlayPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The pan / zoom image layer.
  ///
  /// Once the source dimensions are known the child is sized to
  /// **cover** the square viewport (shorter side == viewport side)
  /// and handed to an unconstrained `InteractiveViewer`, which
  /// clamps panning to the child's bounds. The square is therefore
  /// filled with photo at every scale ≥ 1 — the user pans along
  /// the overflowing axis to choose the framing, and no empty
  /// letterbox band can ever end up in the capture.
  ///
  /// Before the decode lands, `BoxFit.cover` fills the same square
  /// (not pannable for that one frame), so a capture during the
  /// decode window is bar-free too.
  Widget _buildImageLayer(double viewportSide, Size? imageSize) {
    if (imageSize == null) {
      return Image.memory(
        widget.imageBytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }

    final childSize = _coverChildSize(imageSize, viewportSide);
    return InteractiveViewer(
      transformationController: _transformationController,
      // The child is larger than the viewport on its long axis,
      // so it must be laid out unconstrained; `constrained: true`
      // would squeeze it back to the viewport and reintroduce the
      // letterbox.
      constrained: false,
      // Pinch-in is allowed down to 1× — that is the cover fit,
      // the smallest scale at which the square is still fully
      // covered by photo.
      minScale: 1.0,
      maxScale: 4.0,
      child: SizedBox(
        width: childSize.width,
        height: childSize.height,
        child: Image.memory(
          widget.imageBytes,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }

  /// Bottom action row: Cancel (outlined) and Use Photo
  /// (filled). Both buttons set `shape:` explicitly using the
  /// `OmniTheme.buttonBorderRadius` token. The row uses the same
  /// vertical anchor the rest of the app uses for primary
  /// bottom CTAs (16 dp side, 24/16 vertical).
  Widget _buildBottomBar() {
    final shape = WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniTheme.bottomCTAHorizontalPadding,
        OmniTheme.bottomCTAVerticalTopPadding,
        OmniTheme.bottomCTAHorizontalPadding,
        OmniTheme.bottomCTAVerticalBottomPadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: OmniTheme.buttonPrimaryHeight,
              child: OutlinedButton(
                key: const Key('avatar_crop_cancel'),
                style: ButtonStyle(
                  shape: shape,
                  side: WidgetStateProperty.all(
                    BorderSide(color: Theme.of(context).colorScheme.primary),
                  ),
                  foregroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                onPressed:
                    _isSaving ? null : () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: OmniTheme.buttonPrimaryHeight,
              child: FilledButton(
                key: const Key('avatar_crop_use_photo'),
                style: ButtonStyle(shape: shape),
                onPressed: _isSaving ? null : _onConfirm,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Use Photo'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a dim scrim outside the central circle, leaving the
/// circle itself transparent so the image underneath shows
/// through. A 1.5 dp hairline strokes the circle edge for a
/// crisp visual frame.
///
/// The shape is built with `Path.fillType = evenOdd` so the
/// scrim's fill skips the circle's interior. The hairline is
/// drawn separately on top.
class _CircularCropOverlayPainter extends CustomPainter {
  const _CircularCropOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final radius = side / 2;
    final center = Offset(size.width / 2, size.height / 2);

    // Scrim path: outer rectangle minus the central circle,
    // using even-odd fill so the circle interior is left
    // untouched (the image shows through).
    final scrimPath = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // Hairline outline so the circle boundary reads against any
    // image content.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.6)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}