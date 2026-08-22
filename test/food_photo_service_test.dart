// filepath: test/food_photo_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/food_photo_service.dart';

void main() {
  group('FoodPhotoService', () {
    test('bundledPhotoAssetPath returns correct path for food ID', () {
      const foodId = 'chicken_breast';
      final path = FoodPhotoService.bundledPhotoAssetPath(foodId);
      expect(path, 'assets/images/food_chicken_breast.webp');
    });

    test('bundledPhotoAssetPath handles various food IDs', () {
      expect(
        FoodPhotoService.bundledPhotoAssetPath('egg'),
        'assets/images/food_egg.webp',
      );
      expect(
        FoodPhotoService.bundledPhotoAssetPath('banana'),
        'assets/images/food_banana.webp',
      );
      expect(
        FoodPhotoService.bundledPhotoAssetPath('lib_custom_food_1'),
        'assets/images/food_lib_custom_food_1.webp',
      );
    });

    test('bundledPhotoAssetPath handles IDs with underscores', () {
      const foodId = 'greek_yogurt_plain';
      final path = FoodPhotoService.bundledPhotoAssetPath(foodId);
      expect(path, 'assets/images/food_greek_yogurt_plain.webp');
    });
  });
}
