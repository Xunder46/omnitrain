/// Service for deriving bundled food photo asset paths by convention.
///
/// The bundled photo path for any food (catalog or library) is determined
/// solely by the food's ID via a standard naming convention. The actual
/// `.webp` files live in `assets/images/` and are declared in `pubspec.yaml`
/// so `Image.asset` resolves them at runtime.
///
/// Example:
/// - Catalog food with id="chicken_breast" → "assets/images/food_chicken_breast.webp"
/// - Library copy (id="lib_xyz") with catalogId="chicken_breast" → resolve via catalogId → "assets/images/food_chicken_breast.webp"
class FoodPhotoService {
  /// Derives the bundled photo asset path for a given food ID.
  ///
  /// The convention is: `assets/images/food_${foodId}.webp`
  ///
  /// This path is **not verified** to exist at runtime—the caller is
  /// responsible for handling Image.asset failures via errorBuilder.
  ///
  /// Args:
  ///   foodId: The food's ID (from either Food.id or Food.catalogId)
  ///
  /// Returns:
  ///   The asset path string, e.g. "assets/images/food_chicken_breast.webp"
  static String bundledPhotoAssetPath(String foodId) {
    return 'assets/images/food_$foodId.webp';
  }
}
