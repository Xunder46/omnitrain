import 'package:flutter/material.dart';

import '../../../data/models/models.dart';
import '../../../state/food_library_state.dart';
import '../../../state/nutrition_state.dart';
import '../../../widgets/dialogs/confirmation_dialog.dart';
import '../../../widgets/feedback/omni_message.dart';

/// Asks, then deletes a food the user created (a non-bundled catalog row).
///
/// Order matters: today's log entry is unlogged first so the ring drops with
/// the row, then the library copy is removed, then the catalog row is
/// hard-deleted. Past [ConsumedFood] snapshots are untouched (frozen at log
/// time). Returns true when the food is gone, false on Cancel or an error
/// (an error shows a snackbar).
Future<bool> confirmAndDeleteCreatedFood(
  BuildContext context, {
  required Food food,
  required FoodLibraryState foodLibraryState,
  required NutritionState nutritionState,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final confirmed = await ConfirmationDialog.showTwoChoice(
    context: context,
    title: 'Delete ${food.name}?',
    body: const Text('Your past nutrition logs will remain unchanged.'),
    dismissLabel: 'Cancel',
    confirmLabel: 'Delete',
    dismissKey: const Key('food-delete-cancel'),
    confirmKey: const Key('food-delete-confirm'),
    isDestructive: true,
  );
  if (!confirmed) return false;
  try {
    final libraryId = foodLibraryState.libraryIdFor(food.id);
    if (libraryId != null && nutritionState.isFoodLoggedToday(libraryId)) {
      await nutritionState.unlogFoodToday(libraryId);
    }
    if (libraryId != null) {
      await foodLibraryState.removeFood(libraryId);
    }
    await foodLibraryState.deleteCatalogFood(food.id);
    return true;
  } catch (_) {
    OmniMessage.errorOn(messenger, theme, 'Could not delete ${food.name}');
    return false;
  }
}
