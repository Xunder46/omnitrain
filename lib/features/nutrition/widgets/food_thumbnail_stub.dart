// filepath: lib/features/nutrition/widgets/food_thumbnail_stub.dart
import 'package:flutter/material.dart';

/// Web/stub fallback for [FoodThumbnailImage]. On web, the parent
/// [FoodThumbnail] already short-circuits to the placeholder when
/// `kIsWeb` is true, but this stub exists to keep the import
/// contract the same on every platform (so the public
/// [FoodThumbnail] widget can do a single conditional import).
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
  Widget build(BuildContext context) => placeholder;
}
