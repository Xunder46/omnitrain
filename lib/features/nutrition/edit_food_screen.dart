// filepath: lib/features/nutrition/edit_food_screen.dart
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../data/models/models.dart';
import '../../state/food_library_state.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';
import 'widgets/food_form.dart';

/// Edit Food screen — opened from the pencil on an in-list row of the
/// **Library** tab of [AddFoodScreen]. Pre-fills the shared [FoodForm] with
/// the given [Food] and saves on blur (no Save button).
///
/// Which food is edited decides where the edit lands:
///   * a **library row** (`isCatalog == false`, the user's own copy of a
///     bundled food) saves through [FoodLibraryState.editLibraryFood]; the
///     shipped catalog entry is never altered. When the copy differs from
///     its shipped original a **Reset to original** button is shown.
///   * a **catalog row the user created** (`isCatalog == true`) has no
///     shipped original, so it saves through
///     [FoodLibraryState.updateCatalogFood] as before (no Reset).
///
/// Past [ConsumedFood] snapshots stay frozen.
///
/// Pure presentation: no repository access; all colors come from
/// [OmniTheme.colors] / `ThemeData.colorScheme`.
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

  Future<bool> _save(FoodDraft draft) async {
    try {
      if (widget.food.isCatalog) {
        await widget.foodLibraryState.updateCatalogFood(widget.food, draft);
      } else {
        await widget.foodLibraryState.editLibraryFood(widget.food, draft);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onReset() async {
    final confirmed = await ConfirmationDialog.showTwoChoice(
      context: context,
      title: 'Reset to original?',
      body: Text('${widget.food.name} goes back to the values it came with.'),
      dismissLabel: 'Cancel',
      confirmLabel: 'Reset',
      dismissKey: const Key('food-reset-cancel'),
      confirmKey: const Key('food-reset-confirm'),
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await widget.foodLibraryState.resetLibraryFood(widget.food.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canReset =
        !widget.food.isCatalog &&
        widget.foodLibraryState.canResetLibraryFood(widget.food);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Food')),
      body: Column(
        children: [
          Expanded(
            child: FoodForm(
              initial: widget.food,
              foodLibraryState: widget.foodLibraryState,
              saveLabel: 'Save',
              showNotesField: true,
              controller: _formController,
              autoSaveOnBlur: true,
              skipPopOnSave: true,
              onSave: _save,
              // "Save on upload": the form has no Save button, so the
              // photo pick handler persists the new imagePath at once.
              // The partial draft keeps concurrent half-typed edits.
              onImageSave: _save,
            ),
          ),
          if (canReset)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  OmniTheme.bottomCTAHorizontalPadding,
                  8,
                  OmniTheme.bottomCTAHorizontalPadding,
                  OmniTheme.bottomCTAVerticalBottomPadding,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const Key('food_reset_original'),
                    onPressed: _onReset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(color: theme.colorScheme.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonBorderRadius,
                        ),
                      ),
                    ),
                    child: const Text('Reset to original'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
