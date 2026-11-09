// filepath: lib/features/nutrition/edit_food_screen.dart
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../data/models/models.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition_state.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import 'widgets/delete_created_food.dart';
import 'widgets/food_form.dart';
import 'widgets/food_form_unsaved_probe.dart';
import 'widgets/save_default_as_own_food.dart';

/// Edit Food screen — opened from the pencil on a **Library** row
/// (every row offers the pencil, D-13311). Pre-fills the shared [FoodForm]
/// with the given [Food] and carries the same bottom **Save** CTA and
/// unsaved-changes guard as the New Food screen: nothing is written until
/// Save, and leaving with edits asks first.
///
/// What Save does depends on the food:
///   * a **default food** (a bundled catalog row or the user's copy of
///     one, D-13310) — an untouched form pops with nothing written;
///     anything else asks `Save as your own food?`
///     ([confirmSaveAsOwnFood]) and, on confirm, saves a food of the
///     user's own through [saveDefaultAsOwnFood] (D-13313..D-13315); the
///     default itself is never written.
///   * a **catalog row the user created** saves through
///     [FoodLibraryState.updateCatalogFood] as before.
///
/// Past [ConsumedFood] snapshots stay frozen.
///
/// A food the user created also shows a **Delete food** button (given a
/// `nutritionState`).
///
/// Pure presentation: no repository access; all colors come from
/// [OmniTheme.colors] / `ThemeData.colorScheme`.
class EditFoodScreen extends StatefulWidget {
  final Food food;
  final FoodLibraryState foodLibraryState;

  /// Needed only to offer "Delete food" for a food the user created (it
  /// unlogs today's entry first). When null the delete button is not shown.
  final NutritionState? nutritionState;

  const EditFoodScreen({
    super.key,
    required this.food,
    required this.foodLibraryState,
    this.nutritionState,
  });

  /// Push the Edit Food screen. The screen pops on successful
  /// save; the caller (the **Library** tab on [AddFoodScreen]) is
  /// refreshed via [FoodLibraryState] notifications, so the row
  /// reflects the updated food.
  static Future<void> push(
    BuildContext context, {
    required Food food,
    required FoodLibraryState foodLibraryState,
    NutritionState? nutritionState,
  }) {
    return OmniNavigator.push<void>(
      context,
      (context) => EditFoodScreen(
        food: food,
        foodLibraryState: foodLibraryState,
        nutritionState: nutritionState,
      ),
    );
  }

  @override
  State<EditFoodScreen> createState() => _EditFoodScreenState();
}

class _EditFoodScreenState extends State<EditFoodScreen> {
  final FoodFormController _formController = FoodFormController();

  /// Key on the hosted [FoodForm]; the unsaved-work probe reads the form's
  /// rendered fields through it (see [FoodFormUnsavedProbe]).
  final GlobalKey _formKey = GlobalKey();
  late final FoodFormUnsavedProbe _probe = FoodFormUnsavedProbe(
    _formKey,
    initialImagePath: widget.food.imagePath,
  );

  @override
  void initState() {
    super.initState();
    // The form's fields exist once it has laid out; that first frame is the
    // baseline the guard compares against.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _probe.record();
    });
  }

  @override
  void dispose() {
    _probe.dispose();
    _formController.detach();
    super.dispose();
  }

  /// Single exit path for the header back button and system back: leaving a
  /// form the user has not touched pops straight away, leaving one with
  /// edits asks first. Save is the only path that writes, and it pops on
  /// success without the guard.
  Future<void> _attemptExit() async {
    if (!_probe.isDirty) {
      Navigator.of(context).pop();
      return;
    }

    final discard = await ConfirmationDialog.showUnsavedChanges(
      context: context,
      title: 'Unsaved changes',
      body:
          'You have unsaved edits. Discard them to return to the '
          'food library.',
      keepEditingKey: const Key('edit-food-unsaved-keep'),
      discardKey: const Key('edit-food-unsaved-discard'),
    );
    if (!mounted || !discard) return;
    Navigator.of(context).pop();
  }

  /// Asks first when the food is a default food and the form was edited
  /// (D-13312, D-13320); the question comes from the Save button, so a
  /// Cancel never reaches the form's save and never shows its error.
  Future<void> _onSavePressed() async {
    if (widget.foodLibraryState.isDefaultFood(widget.food) &&
        _probe.isDirty) {
      final create = await confirmSaveAsOwnFood(context, food: widget.food);
      if (!create || !mounted) return;
    }
    _formController.submit();
  }

  Future<bool> _save(FoodDraft draft) async {
    final nutrition = widget.nutritionState;
    try {
      // A default food is never written in place (D-13313): an untouched
      // form just closes, anything else was confirmed on the Save button
      // and becomes a food of the user's own.
      if (widget.foodLibraryState.isDefaultFood(widget.food)) {
        if (!_probe.isDirty) return true;
        if (nutrition == null) return false;
        return await saveDefaultAsOwnFood(
          food: widget.food,
          draft: draft,
          foodLibraryState: widget.foodLibraryState,
          nutritionState: nutrition,
        );
      }
      if (widget.food.isCatalog) {
        await widget.foodLibraryState.updateCatalogFood(widget.food, draft);
      } else {
        // A non-catalog row here is a legacy library-only custom row.
        await widget.foodLibraryState.updateCustomFood(
          id: widget.food.id,
          name: draft.name,
          groupId: draft.groupId,
          unitType: draft.unitType,
          referenceAmount: draft.referenceAmount,
          referenceLabel: draft.referenceLabel,
          protein: draft.protein,
          carbs: draft.carbs,
          fiber: draft.fiber,
          fat: draft.fat,
          sodium: draft.sodium,
          notes: draft.notes,
          imagePath: draft.imagePath,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onDeleteCreated() async {
    final nutrition = widget.nutritionState;
    if (nutrition == null) return;
    final deleted = await confirmAndDeleteCreatedFood(
      context,
      food: widget.food,
      foodLibraryState: widget.foodLibraryState,
      nutritionState: nutrition,
    );
    if (!deleted || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete =
        widget.food.isCatalog &&
        widget.nutritionState != null &&
        !widget.foodLibraryState.isBundledCatalogFood(widget.food.id);
    return PopScope(
      // Always intercept: whether leaving is safe is decided fresh in
      // [_attemptExit], because the host does not rebuild as the user types
      // into the form (so a `canPop` computed at build time would go stale
      // and let the edits through).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _attemptExit();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Food')),
        body: Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollEndNotification) _probe.record();
                  return false;
                },
                child: FoodForm(
                  key: _formKey,
                  initial: widget.food,
                  foodLibraryState: widget.foodLibraryState,
                  saveLabel: 'Save',
                  showNotesField: true,
                  controller: _formController,
                  // Nothing persists the photo before Save, so the probe
                  // learns about a pick (or a clear) from the form itself.
                  onImageChanged: _probe.markImageChanged,
                  onServingChanged: _probe.markServingChanged,
                  onSave: _save,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: OmniBottomCTA(
          label: 'Save',
          buttonKey: const Key('food_form_save'),
          onPressed: _onSavePressed,
          // Only Delete sits above Save in the shared footer, so it
          // shares its height, margins and radius.
          secondaryLabel: canDelete ? 'Delete food' : null,
          secondaryButtonKey: const Key('food_delete_created'),
          onSecondaryPressed: _onDeleteCreated,
          isSecondaryDestructive: true,
        ),
      ),
    );
  }
}
