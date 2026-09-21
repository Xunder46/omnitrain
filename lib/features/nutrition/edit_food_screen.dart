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
/// **Primary bottom CTA**: the **Save** action uses the shared
/// [OmniBottomCTA] (see
/// `.github/agents/plans/primary-bottom-cta-anchor-width-plan.md`),
/// wired to a [FoodFormController] that triggers the form's
/// validation + save pipeline. The `Key('food_form_save')` is
/// preserved on the bottom CTA for backward compatibility with
/// existing test contracts.
///
/// Pure presentation:
///   * No repository access (all writes go through
///     [FoodLibraryState]).
///   * All colors come from [OmniTheme.colors] /
///     `ThemeData.colorScheme`.
class EditFoodScreen extends StatefulWidget {
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
      (context) =>
          EditFoodScreen(food: food, foodLibraryState: foodLibraryState),
    );
  }

  @override
  State<EditFoodScreen> createState() => _EditFoodScreenState();
}

class _EditFoodScreenState extends State<EditFoodScreen> {
  final FoodFormController _formController = FoodFormController();

  @override
  void dispose() {
    _formController.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Food')),
      body: FoodForm(
        initial: widget.food,
        foodLibraryState: widget.foodLibraryState,
        saveLabel: 'Save',
        showNotesField: true,
        controller: _formController,
        autoSaveOnBlur: true,
        skipPopOnSave: true,
        onSave: (draft) async {
          try {
            await widget.foodLibraryState.updateCatalogFood(widget.food, draft);
            return true;
          } catch (_) {
            return false;
          }
        },
        // "Save on upload": the form has no Save button (the user
        // explicitly removed it — see the user's Phase 3.X bug
        // report), so the photo pick handler must persist the new
        // imagePath to the data layer immediately. The partial
        // draft is built from `widget.food` with only `imagePath`
        // changed, so concurrent edits to the form's text
        // controllers (a half-typed name, say) are preserved.
        onImageSave: (draft) async {
          try {
            await widget.foodLibraryState.updateCatalogFood(widget.food, draft);
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
      // Auto-save on blur - no save button needed for existing foods.
    );
  }
}
