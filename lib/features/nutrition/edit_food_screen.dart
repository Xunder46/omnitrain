// filepath: lib/features/nutrition/edit_food_screen.dart
import 'package:flutter/material.dart';

import '../../core/navigation/navigation.dart';
import '../../data/models/models.dart';
import '../../state/food_library_state.dart';
import 'widgets/food_form.dart';

/// Edit Food screen — opens from a row tap in the **Library** tab
/// of [AddFoodScreen]. Pre-fills the shared [FoodForm] with the
/// existing [Food]'s data and persists via
/// [FoodLibraryState.updateCatalogFood] on save.
///
/// This screen edits a **catalog** food (bundled or user-created
/// via the **+ New Item** tab on [AddFoodScreen]). The catalog is
/// the global managed library: every row in the **Library** tab
/// is a catalog food, and the row tap is the entry point to edit
/// it. Catalog foods can be added to the user's personal library
/// via the trailing **Add** button on the row; the user logs
/// against the personal-library copy (which points back to the
/// catalog row by identity). Past [ConsumedFood] snapshots remain
/// frozen (the snapshot model does not include the image, and
/// the food's `name` / macros are frozen at log time).
///
/// Pure presentation:
///   * No repository access (all writes go through
///     [FoodLibraryState]).
///   * All colors come from [OmniTheme.colors] /
///     `ThemeData.colorScheme`.
class EditFoodScreen extends StatelessWidget {
  final Food food;
  final FoodLibraryState foodLibraryState;

  const EditFoodScreen({
    super.key,
    required this.food,
    required this.foodLibraryState,
  });

  /// Push the Edit Food screen. The screen pops on successful
  /// save; the caller (the **Library** tab on [AddFoodScreen]) is
  /// refreshed via [FoodLibraryState] notifications, so the row
  /// reflects the updated food.
  static Future<void> push(
    BuildContext context, {
    required Food food,
    required FoodLibraryState foodLibraryState,
  }) {
    return OmniNavigator.push<void>(
      context,
      (context) => EditFoodScreen(
        food: food,
        foodLibraryState: foodLibraryState,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Food')),
      body: FoodForm(
        initial: food,
        foodLibraryState: foodLibraryState,
        saveLabel: 'Save',
        showNotesField: true,
        onSave: (draft) async {
          try {
            await foodLibraryState.updateCatalogFood(food, draft);
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }
}
