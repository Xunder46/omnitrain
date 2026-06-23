// filepath: lib/features/nutrition/widgets/food_thumbnail_io.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:omnitrain/core/services/image_storage_service.dart';

/// Native-only image renderer for a food photo. Uses `Image.file`
/// with an `errorBuilder` that falls back to a placeholder when
/// the file is missing or unreadable. Mirrors the contract of
/// `ProfileAvatarImage` in `lib/features/profile/widgets/`. The
/// [reference] is the stored value from `Food.imagePath` — under
/// the post-relocation-fix contract this is a **basename** (D-1
/// in
/// `.github/agents/plans/image-persistence-relocation-fix-plan.md`),
/// not an absolute path. The widget resolves the basename via
/// [imageStorage] (when provided) before `Image.file`.
class FoodThumbnailImage extends StatelessWidget {
  /// The stored photo reference (basename after the relocation
  /// fix, or a legacy absolute path during the migration window).
  final String reference;

  /// Image-storage service used to resolve [reference] to an
  /// absolute path. Required in production.
  final ImageStorageService? imageStorage;

  final double size;
  final double radius;
  final Widget placeholder;

  const FoodThumbnailImage({
    super.key,
    required this.reference,
    required this.size,
    required this.radius,
    required this.placeholder,
    this.imageStorage,
  });

  @override
  Widget build(BuildContext context) {
    final absPath = imageStorage?.resolvePathSync(reference) ?? reference;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(absPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}
