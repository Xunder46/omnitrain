// filepath: lib/features/nutrition/widgets/food_thumbnail.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/services/food_photo_service.dart';
import '../../../core/services/image_storage_service.dart';

// Conditional import: same pattern as `ProfileAvatarImage` in
// `lib/features/profile/widgets/`. The IO variant uses
// `Image.file` to render the local photo with an `errorBuilder`
// fallback to a placeholder.
import 'food_thumbnail_stub.dart' if (dart.library.io) 'food_thumbnail_io.dart';

/// 40×40 rounded thumbnail for a food item, with a placeholder when
/// no image is set. Mirrors the contract of
/// `ProfileAvatarImage` (`features/profile/widgets/profile_avatar_image_*.dart`):
/// the image is loaded from a local file path on native and falls
/// back to a placeholder on web or when the file is missing.
///
/// Three-tier precedence (D-4):
/// 1. User-picked photo (imagePath) — always wins if set
/// 2. Bundled/shipped photo (derived via FoodPhotoService) — shown if bundled asset exists
/// 3. Placeholder icon — fallback when neither above exists
///
/// Use on the left of a food row in the food library browse view to
/// keep the row's text column from reflowing when an image is
/// added or removed (the slot is always present and the same size).
class FoodThumbnail extends StatelessWidget {
  /// Optional stored food photo reference. `null` or an empty
  /// string falls back to the placeholder. Under the
  /// post-relocation-fix contract this is a **basename** (D-1 in
  /// `docs/plans/image-persistence-relocation-fix-plan.md`),
  /// not an absolute path; the [imageStorage] service resolves it
  /// to the current managed dir on render.
  final String? imagePath;

  /// Image-storage service used to resolve [imagePath] to an
  /// absolute path under the current managed directory. Required
  /// in production (passed by the screen / form from
  /// `FoodLibraryState.imageStorage`); optional in tests that
  /// pass an already-resolved absolute path.
  final ImageStorageService? imageStorage;

  /// The food's unique ID. Used to resolve bundled photo path via convention.
  /// Optional; when null, bundled photo lookup is skipped (backward compatible).
  /// Per D-1: bundled photo for a library copy is resolved via [catalogId]
  /// if set; otherwise via this [foodId].
  final String? foodId;

  /// The catalog food ID for a library food (when copied from catalog).
  /// When set, bundled photo is resolved via this ID, not [foodId].
  /// Ensures library copies of catalog foods render the same bundled photo
  /// as the original (S-4, S-11).
  final String? catalogId;

  /// Diameter in logical pixels.
  final double size;

  /// Corner radius. Defaults to 8 — the same value used by
  /// utility buttons across the app.
  final double radius;

  /// Optional caption rendered alongside the placeholder icon
  /// when the placeholder branch is taken (no user photo AND no
  /// resolvable bundled photo). The food form opts into this
  /// caption ("Add photo") to signal interactivity on the
  /// empty-state tile; list-row consumers do NOT pass it, so a
  /// caption at thumbnail size is never introduced into dense
  /// lists. When `null`, the placeholder renders icon-only as
  /// before.
  final String? placeholderCaption;

  const FoodThumbnail({
    super.key,
    required this.imagePath,
    this.imageStorage,
    this.foodId,
    this.catalogId,
    this.size = 40,
    this.radius = 8,
    this.placeholderCaption,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final placeholder = _Placeholder(
      size: size,
      radius: radius,
      color: themeColors.textMuted,
      background: themeColors.surface,
      caption: placeholderCaption,
    );

    // Tier 1: User-picked photo (imagePath) — always wins if set
    if (imagePath != null && imagePath!.isNotEmpty) {
      if (kIsWeb) return placeholder;

      return FoodThumbnailImage(
        reference: imagePath!,
        imageStorage: imageStorage,
        size: size,
        radius: radius,
        placeholder: placeholder,
      );
    }

    // Tier 2: Bundled photo — check if asset exists for this food
    // Resolve via catalogId (for library copies) or foodId (for original foods)
    if (foodId != null || catalogId != null) {
      final resolutionKey = catalogId ?? foodId!;
      final bundledPath = FoodPhotoService.bundledPhotoAssetPath(resolutionKey);

      return _BundledPhotoImage(
        assetPath: bundledPath,
        size: size,
        radius: radius,
        placeholder: placeholder,
      );
    }

    // Tier 3: Placeholder — fallback when neither user photo nor bundled asset exists
    return placeholder;
  }
}

/// Renders a bundled food photo via Image.asset with silent missing-asset fallback.
///
/// When the asset file exists, renders the decoded image. When the file is
/// missing (the default for this tier per D-2), the errorBuilder falls through
/// to [placeholder] with no logging or error surfacing.
class _BundledPhotoImage extends StatelessWidget {
  final String assetPath;
  final double size;
  final double radius;
  final Widget placeholder;

  const _BundledPhotoImage({
    required this.assetPath,
    required this.size,
    required this.radius,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}

/// A neutral placeholder for a food thumbnail. Pairs the food icon
/// with the active theme's muted color. When a [caption] is
/// supplied (the food form opts in), the placeholder renders the
/// icon stacked above the caption inside the same square — both
/// fit by shrinking the icon to leave room for the label.
class _Placeholder extends StatelessWidget {
  final double size;
  final double radius;
  final Color color;
  final Color background;
  final String? caption;

  const _Placeholder({
    required this.size,
    required this.radius,
    required this.color,
    required this.background,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final hasCaption = caption != null && caption!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: hasCaption
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.restaurant_outlined,
                  color: color,
                  // With a caption stacked below, the icon must
                  // shrink so both fit in the square without
                  // overflowing at the form's 96×96 tile size.
                  size: size * 0.3,
                ),
                const SizedBox(height: 4),
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: size * 0.125,
                    height: 1.1,
                  ),
                ),
              ],
            )
          : Icon(Icons.restaurant_outlined, color: color, size: size * 0.5),
    );
  }
}
