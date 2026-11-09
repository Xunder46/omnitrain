import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/macro_targets.dart';
import '../../state/nutrition_state.dart';
import '../../data/models/models.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';
import '../../widgets/inputs/select_all_on_focus.dart';
import '../../widgets/layout/omni_bottom_cta.dart';

/// Screen for setting today's daily targets: calories, then protein, carbs
/// and fat in grams.
///
/// Calories is the headline. Typing it fills the three macro boxes with the
/// default split (`defaultMacroTargets`); typing in a macro box sets calories
/// to what the macros add up to (`impliedCalories`). A macro box the user
/// typed in, or loaded from a stored target, is "manual": a later calories
/// edit leaves it alone. Every macro box is optional (empty = no target), and
/// a mismatch between calories and the macros never blocks Save. The carbs
/// target is TOTAL carbs.
///
/// The primary bottom **Save** action uses the shared [OmniBottomCTA] (see
/// `docs/plans/primary-bottom-cta-anchor-width-plan.md`).
class NutritionTargetScreen extends StatefulWidget {
  final NutritionState nutritionState;

  const NutritionTargetScreen({super.key, required this.nutritionState});

  @override
  State<NutritionTargetScreen> createState() => _NutritionTargetScreenState();
}

class _NutritionTargetScreenState extends State<NutritionTargetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  bool _isLoading = true;

  /// The macro boxes the user typed in, or loaded from a stored target.
  /// A calories edit never refills these.
  final Set<TextEditingController> _manual = {};

  /// The four boxes' text on entry (after the load-time prefill); a
  /// difference means dirty.
  String _initialSnapshot = '';

  @override
  void initState() {
    super.initState();
    _caloriesController = TextEditingController();
    _proteinController = TextEditingController();
    _carbsController = TextEditingController();
    _fatController = TextEditingController();
    _loadTodayTarget();
  }

  String get _snapshot => [
    _caloriesController.text,
    _proteinController.text,
    _carbsController.text,
    _fatController.text,
  ].join('|');

  /// Grams in a box, or null when it is empty or not a number.
  static double? _valueOf(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  static String _gramsText(double grams) =>
      grams > 0 ? grams.round().toString() : '';

  Future<void> _loadTodayTarget() async {
    final target = await widget.nutritionState.getTodayTarget();
    if (!mounted) return;
    setState(() {
      if (target != null && target.calories > 0) {
        _caloriesController.text = target.calories.toInt().toString();
      }
      final hasMacros =
          target != null &&
          (target.protein > 0 || target.carbs > 0 || target.fat > 0);
      if (hasMacros) {
        _proteinController.text = _gramsText(target.protein);
        _carbsController.text = _gramsText(target.carbs);
        _fatController.text = _gramsText(target.fat);
        _manual.addAll([_proteinController, _carbsController, _fatController]);
      } else {
        _prefillFromCalories();
      }
      _initialSnapshot = _snapshot;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  /// True when any of the parsed values is Infinity or NaN.
  static bool _hasNonFinite(double? a, double? b, double? c) =>
      !(a?.isFinite ?? true) ||
      !(b?.isFinite ?? true) ||
      !(c?.isFinite ?? true);

  /// Fills every macro box the user has not typed in with the default split
  /// of the calories box (empty when calories is empty or 0).
  void _prefillFromCalories() {
    final calories = _valueOf(_caloriesController);
    final defaults = (calories != null && calories.isFinite && calories > 0)
        ? defaultMacroTargets(calories)
        : null;
    void fill(TextEditingController controller, int? grams) {
      if (_manual.contains(controller)) return;
      controller.text = (grams == null || grams <= 0) ? '' : grams.toString();
    }

    fill(_proteinController, defaults?.protein);
    fill(_carbsController, defaults?.carbs);
    fill(_fatController, defaults?.fat);
  }

  /// Calories = what the three macro boxes add up to. Left alone when all
  /// three are empty.
  void _syncCaloriesFromMacros() {
    final protein = _valueOf(_proteinController);
    final carbs = _valueOf(_carbsController);
    final fat = _valueOf(_fatController);
    if (protein == null && carbs == null && fat == null) return;
    // Infinity/NaN (e.g. `1e400`, `NaN`): the validator rejects them at
    // Save; the sync must not round them (impliedCalories would throw).
    if (_hasNonFinite(protein, carbs, fat)) return;
    final implied = impliedCalories(
      protein: protein ?? 0,
      carbs: carbs ?? 0,
      fat: fat ?? 0,
    );
    _caloriesController.text = implied > 0 ? implied.toString() : '';
  }

  /// The calories the macro boxes add up to, or null when none has a value.
  int? get _impliedFromBoxes {
    final protein = _valueOf(_proteinController) ?? 0;
    final carbs = _valueOf(_carbsController) ?? 0;
    final fat = _valueOf(_fatController) ?? 0;
    if (_hasNonFinite(protein, carbs, fat)) return null;
    final implied = impliedCalories(protein: protein, carbs: carbs, fat: fat);
    return implied > 0 ? implied : null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final protein = _valueOf(_proteinController) ?? 0.0;
    final carbs = _valueOf(_carbsController) ?? 0.0;
    final fat = _valueOf(_fatController) ?? 0.0;
    var calories = _valueOf(_caloriesController) ?? 0.0;
    if (calories <= 0) {
      // Calories left empty: the macros define the target.
      calories = impliedCalories(
        protein: protein,
        carbs: carbs,
        fat: fat,
      ).toDouble();
    }

    await widget.nutritionState.saveNutritionTarget(
      NutritionTarget(
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// True when any box differs from the text it held on entry.
  bool get _isDirty => _snapshot != _initialSnapshot;

  /// Single exit path for header back, system back and the dialog's own
  /// Discard: leaving without edits pops straight away, leaving with edits
  /// asks first. Save runs the normal save path, which pops only when the
  /// target was written.
  Future<void> _attemptExit() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }

    final discard = await ConfirmationDialog.showUnsavedChanges(
      context: context,
      title: 'Unsaved changes',
      body:
          'You have unsaved edits. Discard them to return to the previous screen.',
      keepEditingKey: const Key('nutrition-target-unsaved-keep'),
      discardKey: const Key('nutrition-target-unsaved-discard'),
    );
    if (!mounted || !discard) return;
    Navigator.of(context).pop();
  }

  static String? _validateGrams(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) {
      return 'Please enter a valid number';
    }
    if (parsed < 0) return 'Please enter a non-negative number';
    return null;
  }

  InputDecoration _decoration(String label, {required bool large}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return InputDecoration(
      labelText: label,
      hintText: '—',
      labelStyle: TextStyle(
        fontSize: large ? 16 : 14,
        color: OmniTheme.colors.textMuted,
      ),
      hintStyle: TextStyle(
        fontSize: large ? 24 : 20,
        fontWeight: FontWeight.bold,
        color: OmniTheme.colors.textMuted,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: large ? 24 : 8,
        vertical: large ? 24 : 16,
      ),
      border: border,
      enabledBorder: border.copyWith(
        borderSide: BorderSide(color: OmniTheme.colors.surfaceBorder, width: 2),
      ),
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: OmniTheme.colors.primary, width: 2),
      ),
    );
  }

  Widget _numberField({
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required bool large,
    required VoidCallback onEdited,
  }) {
    return SelectAllOnFocus(
      controller: controller,
      builder: (context, focusNode) => TextFormField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: large ? 36 : 22,
          fontWeight: FontWeight.bold,
        ),
        decoration: _decoration(label, large: large),
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(onEdited),
        validator: _validateGrams,
      ),
    );
  }

  Widget _macroField(
    String keyName,
    TextEditingController controller,
    String label,
  ) {
    return Expanded(
      child: _numberField(
        fieldKey: Key(keyName),
        controller: controller,
        label: label,
        large: false,
        onEdited: () {
          _manual.add(controller);
          _syncCaloriesFromMacros();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Daily Targets')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final implied = _impliedFromBoxes;
    final mutedBody = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: OmniTheme.colors.textMuted,
    );

    final content = Scaffold(
      appBar: AppBar(title: const Text('Daily Targets')),
      // The Save button is the screen's primary bottom action. It
      // uses the shared `OmniBottomCTA` so it inherits the
      // app-wide width, height, corner radius, and safe-area
      // vertical anchor (see `OmniTheme.bottomCTA*` tokens).
      bottomNavigationBar: OmniBottomCTA(label: 'Save', onPressed: _save),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          OmniTheme.formBottomCTAClearance,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _numberField(
                  fieldKey: const Key('calories_field'),
                  controller: _caloriesController,
                  label: 'Calories',
                  large: true,
                  onEdited: _prefillFromCalories,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _macroField(
                    'protein_field',
                    _proteinController,
                    'Protein (g)',
                  ),
                  const SizedBox(width: 8),
                  _macroField('carbs_field', _carbsController, 'Carbs (g)'),
                  const SizedBox(width: 8),
                  _macroField('fat_field', _fatController, 'Fat (g)'),
                ],
              ),
              const SizedBox(height: 8),
              if (implied != null)
                Center(
                  child: Text(
                    'Macros add up to $implied Cal',
                    key: const Key('implied_calories_readout'),
                    style: mutedBody,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Set calories and the macros fill in with a default split. '
                'Change a macro and calories follows. Carbs are total '
                'carbs, fiber included. Leave a macro empty for no target.',
                style: mutedBody,
              ),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _attemptExit();
      },
      child: content,
    );
  }
}
