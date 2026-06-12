import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../state/nutrition_state.dart';
import '../../data/models/models.dart';

/// Screen for setting today's daily calorie target.
///
/// Per D-3 / S-040 the daily target is **calories only**. The macro
/// fields on the persisted [NutritionTarget] (protein / carbs / fat)
/// are kept on the model for backwards compatibility and are written
/// as 0; they are not user-editable. Macro ratios are informational
/// only — derived from consumed amounts — and never from macro
/// targets. The "implied calories from macros" helper is removed in
/// line with the new contract; the form is a single field.
///
/// `NutritionTargetScreen` was previously a four-field form. The
/// protein / carbs / fat inputs and the live macro-implied read-out
/// have been removed; only the calories field remains.
class NutritionTargetScreen extends StatefulWidget {
  final NutritionState nutritionState;

  const NutritionTargetScreen({
    super.key,
    required this.nutritionState,
  });

  @override
  State<NutritionTargetScreen> createState() => _NutritionTargetScreenState();
}

class _NutritionTargetScreenState extends State<NutritionTargetScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _caloriesController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _caloriesController = TextEditingController();
    _loadTodayTarget();
  }

  Future<void> _loadTodayTarget() async {
    final target = await widget.nutritionState.getTodayTarget();
    if (mounted) {
      setState(() {
        // Treat a stored calories value of 0 (or negative) as
        // "unset" — the form shows an empty field in that case.
        // Stored protein/carbs/fat are ignored here: the user
        // cannot edit them (D-3) and the value they hold has no
        // effect on the ring or strip.
        if (target != null && target.calories > 0) {
          _caloriesController.text = target.calories.toInt().toString();
        } else {
          _caloriesController.text = '';
        }
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Parse the (single) calories field. Empty or non-numeric is
    // rejected by the validator; reaching here means a valid integer.
    final raw = _caloriesController.text.trim();
    final calories = double.tryParse(raw) ?? 0.0;

    // D-3 / S-040: build a macros-0 target. The persisted
    // NutritionTarget keeps its protein/carbs/fat fields for
    // schema/back-compat; they go forward as 0 from this form.
    final newTarget = NutritionTarget(
      calories: calories,
      protein: 0.0,
      carbs: 0.0,
      fat: 0.0,
    );

    await widget.nutritionState.saveNutritionTarget(newTarget);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Daily Calorie Target'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Calorie Target'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('calories_field'),
                controller: _caloriesController,
                decoration: const InputDecoration(
                  labelText: 'Calories',
                  hintText: 'Leave empty for no goal',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  final parsed = double.tryParse(value);
                  if (parsed == null) {
                    return 'Please enter a valid number';
                  }
                  if (parsed < 0) {
                    return 'Please enter a non-negative number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              // D-3 framing copy: the daily target is a single
              // calories value. Macros are not editable here.
              Text(
                'Your daily target is a single calorie value. Macro '
                'ratios are informational and derived from what you '
                'log, not from target values.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: OmniTheme.colors.textMuted,
                    ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: OmniTheme.buttonPrimaryHeight,
                child: FilledButton(
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonBorderRadius,
                        ),
                      ),
                    ),
                  ),
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
