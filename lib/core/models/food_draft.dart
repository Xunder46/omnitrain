// filepath: lib/core/models/food_draft.dart
import '../../data/models/models.dart';

/// Editable payload returned by `FoodForm` (in
/// `lib/features/nutrition/widgets/food_form.dart`) on a successful
/// save.
///
/// The form owns the validation, the image picker, and the
/// translation from controllers to a typed [FoodDraft]. The caller
/// hands the draft to [FoodLibraryState.createCustomFood] (create)
/// / [FoodLibraryState.createCatalogFood] (catalog create) or
/// [FoodLibraryState.updateCustomFood] (library edit) /
/// [FoodLibraryState.updateCatalogFood] (catalog edit) — never to
/// the repository directly.
///
/// Lives in `core/` (not in the feature tree) so state classes
/// that depend on it do not have to reach into the nutrition
/// feature to import it.
class FoodDraft {
  final String name;
  final String? groupId;
  final FoodUnitType unitType;
  final double referenceAmount;
  final String referenceLabel;
  final double protein;
  final double carbs;
  final double? fiber;
  final double fat;
  final double? sodium;
  final String? notes;
  final String? imagePath;

  const FoodDraft({
    required this.name,
    required this.groupId,
    required this.unitType,
    required this.referenceAmount,
    required this.referenceLabel,
    required this.protein,
    required this.carbs,
    required this.fiber,
    required this.fat,
    required this.sodium,
    required this.notes,
    required this.imagePath,
  });
}
