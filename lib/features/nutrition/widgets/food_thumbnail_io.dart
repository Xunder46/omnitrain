// filepath: lib/features/nutrition/widgets/food_thumbnail_io.dart
import 'dart:io';

import 'package:flutter/material.dart';

/// Native-only image renderer for a food photo. Uses `Image.file`
/// with an `errorBuilder` that falls back to a placeholder when
/// the file is missing or unreadable. Mirrors the contract of
/// `ProfileAvatarImage` in `lib/features/profile/widgets/`.
class FoodThumbnailImage extends StatelessWidget {
  final String path;
  final double size;
  final double radius;
  final Widget placeholder;

  const FoodThumbnailImage({
    super.key,
    required this.path,
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
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}
