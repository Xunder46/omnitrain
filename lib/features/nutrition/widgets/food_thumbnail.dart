// filepath: lib/features/nutrition/widgets/food_thumbnail.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/services/image_storage_service.dart';

// Conditional import: same pattern as `ProfileAvatarImage` in
// `lib/features/profile/widgets/`. The IO variant uses
// `Image.file` to render the local photo with an `errorBuilder`
// fallback to a placeholder.
import 'food_thumbnail_stub.dart'
    if (dart.library.io) 'food_thumbnail_io.dart';

/// 40×40 rounded thumbnail for a food item, with a placeholder when
/// no image is set. Mirrors the contract of
/// `ProfileAvatarImage` (`features/profile/widgets/profile_avatar_image_*.dart`):
/// the image is loaded from a local file path on native and falls
/// back to a placeholder on web or when the file is missing.
///
/// Use on the left of a food row in the food library browse view to
/// keep the row's text column from reflowing when an image is
/// added or removed (the slot is always present and the same size).
class FoodThumbnail extends StatelessWidget {
  /// Optional stored food photo reference. `null` or an empty
  /// string falls back to the placeholder. Under the
  /// post-relocation-fix contract this is a **basename** (D-1 in
  /// `.github/agents/plans/image-persistence-relocation-fix-plan.md`),
  /// not an absolute path; the [imageStorage] service resolves it
  /// to the current managed dir on render.
  final String? imagePath;

  /// Image-storage service used to resolve [imagePath] to an
  /// absolute path under the current managed directory. Required
  /// in production (passed by the screen / form from
  /// `FoodLibraryState.imageStorage`); optional in tests that
  /// pass an already-resolved absolute path.
  final ImageStorageService? imageStorage;

  /// Diameter in logical pixels.
  final double size;

  /// Corner radius. Defaults to 8 — the same value used by
  /// utility buttons across the app.
  final double radius;

  const FoodThumbnail({
    super.key,
    required this.imagePath,
    this.imageStorage,
    this.size = 40,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final placeholder = _Placeholder(
      size: size,
      radius: radius,
      color: themeColors.textMuted,
      background: themeColors.surface,
    );

    if (imagePath == null || imagePath!.isEmpty) return placeholder;
    if (kIsWeb) return placeholder;

    return FoodThumbnailImage(
      reference: imagePath!,
      imageStorage: imageStorage,
      size: size,
      radius: radius,
      placeholder: placeholder,
    );
  }
}

/// A neutral placeholder for a food thumbnail. Pairs the food icon
/// with the active theme's muted color.
class _Placeholder extends StatelessWidget {
  final double size;
  final double radius;
  final Color color;
  final Color background;

  const _Placeholder({
    required this.size,
    required this.radius,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Icon(Icons.restaurant_outlined, color: color, size: size * 0.5),
    );
  }
}
