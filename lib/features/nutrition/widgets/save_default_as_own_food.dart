// filepath: lib/features/nutrition/widgets/save_default_as_own_food.dart
import 'package:flutter/material.dart';

import '../../../core/models/food_draft.dart';
import '../../../data/models/models.dart';
import '../../../state/food_library_state.dart';
import '../../../state/nutrition_state.dart';
import '../../../widgets/dialogs/confirmation_dialog.dart';

/// Asks before a **default food** (a bundled catalog food or the user's
/// copy of one) is saved as a food of the user's own (plan 133 D-13312).
/// Returns true when the user chose **Create copy**; false on Cancel, the
/// barrier or back. The body names the default's own name.
Future<bool> confirmSaveAsOwnFood(BuildContext context, {required Food food}) {
  return ConfirmationDialog.showTwoChoice(
    context: context,
    title: 'Save as your own food?',
    body: Text(
      '${food.name} is a default food and stays as it is. Saving '
      'creates a new food of your own, with its photo copied.',
    ),
    dismissLabel: 'Cancel',
    confirmLabel: 'Create copy',
    dismissKey: const Key('food-copy-cancel'),
    confirmKey: const Key('food-copy-confirm'),
    isDestructive: false,
  );
}

/// Saves [draft] as a food of the user's own from the default [food]
/// (plan 133 D-13313..D-13315, D-13321). No dialog and no snackbar: the
/// caller asks first ([confirmSaveAsOwnFood]) and the food form reports a
/// false return.
///
/// The bundled catalog row and its seed marker are never written. When the
/// default is in the user's list, today's log moves to the new food: the
/// amount is read first, unlogged, the swap runs, then the amount is logged
/// on the new library row. If any step fails, the amount is put back on
/// whichever row is in the list (the old copy if it is still there, else
/// the new food) so a storage error cannot lose today's log.
Future<bool> saveDefaultAsOwnFood({
  required Food food,
  required FoodDraft draft,
  required FoodLibraryState foodLibraryState,
  required NutritionState nutritionState,
}) async {
  final oldLibraryId = foodLibraryState.libraryIdFor(food.catalogId ?? food.id);
  final amount = oldLibraryId == null
      ? null
      : nutritionState.findLoggedTodayForFood(oldLibraryId)?.amountConsumed;
  var unlogged = false;
  String? newId;
  try {
    if (oldLibraryId != null && amount != null) {
      unlogged = await nutritionState.unlogFoodToday(oldLibraryId);
    }
    newId = await foodLibraryState.createOwnCopyOfDefault(
      food,
      draft,
      addToList: oldLibraryId != null,
    );
    if (unlogged) {
      final newLibraryFood = foodLibraryState.foods.firstWhere(
        (f) => f.id == newId,
      );
      await nutritionState.logConsumedFoodAt(newLibraryFood, amount!);
    }
    return true;
  } catch (_) {
    if (unlogged) {
      final inList = foodLibraryState.foods.where(
        (f) => f.id == oldLibraryId || f.id == newId,
      );
      if (inList.isNotEmpty) {
        try {
          await nutritionState.logConsumedFoodAt(inList.first, amount!);
        } catch (_) {
          // Best effort: the original failure is the one reported.
        }
      }
    }
    return false;
  }
}
