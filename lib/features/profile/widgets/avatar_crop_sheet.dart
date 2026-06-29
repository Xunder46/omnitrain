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

/// Avatar crop step. Push via `Navigator.push<Uint8List?>`
/// (`MaterialPageRoute(fullscreenDialog: true)`). The returned
/// future completes with the captured PNG bytes on confirm, or
/// `null` on cancel.
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
  void dispose() {
    _transformationController.dispose();
    super.dispose();
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

    return SizedBox(
      width: viewportSide,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _transformationController,
                // Pinch-in is allowed down to 1× — the viewport
                // cannot show empty borders below the natural
                // image size, so anything smaller would invite
                // black bars in the captured region.
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.memory(
                  widget.imageBytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
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