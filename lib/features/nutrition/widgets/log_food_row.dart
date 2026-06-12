// filepath: lib/features/nutrition/widgets/log_food_row.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/utils/food_helpers.dart';
import '../../../data/models/models.dart';
import '../../../state/food_library_state.dart';
import '../../../state/nutrition_state.dart';

/// A single food-library row that doubles as the "log a food as consumed"
/// affordance on the nutrition page.
///
/// Layout (left to right):
///
///   ```
///   [ ☑/☐ checkbox ]   [ food name (1 line) ]           [ amount ] [label]
///                       ┌──────────────┐                  [ textbox ] [g/ml]
///                       │ 31P    0C    │   ← 2×2 macro grid          ┌──┴──┐
///                       │ 3F    151cal│     (cal/P top, C/F bottom) │     │
///                       └──────────────┘                            └──┬──┘
///   ```
///
/// The amount field behavior depends on the food's [FoodUnitType]:
///   - For `grams` (weight-based foods): the typed value is the **actual
///     amount** in the food's unit (e.g., reference 100g, user enters 50
///     → 50g consumed, not 50×100g).
///   - For `count` (discrete items): the typed value is a **multiplier**
///     against the reference (e.g., reference 1 egg, user enters 0.5
///     → 0.5 eggs consumed).
///
/// The checkbox is the primary "mark consumed" toggle; tapping it
/// logs the food at the current amount. Editing the amount on a
/// logged row **auto-commits** the new amount to the day log
/// (debounced ~250 ms) — the user does NOT need to re-tap the
/// checkbox; the ring and totals update live.
///
/// The per-row "remove from library" trashcan has been removed (a
/// redesigned deletion UX is a follow-up). The hard-delete API on
/// [FoodLibraryState] remains available; it is just not surfaced in
/// this row.
///
/// Validation: the amount must be `> 0`. While the input is
/// invalid (empty, zero, or non-numeric), the checkbox tap is a
/// no-op and an inline error renders. Both count and grams foods
/// accept any positive number (whole numbers and decimals).
///
/// Pure presentation:
///   - No repository access (state is injected via constructor).
///   - All colors come from [OmniTheme.colors] / `ThemeData.colorScheme`.
class LogFoodRow extends StatefulWidget {
  /// The library food to render and toggle.
  final Food food;

  /// State holder for the day-log and its derived totals.
  final NutritionState nutritionState;

  /// State holder for the food library. Currently only needed to keep
  /// the constructor signature symmetric with other row widgets; no
  /// mutations are performed through it from this row.
  final FoodLibraryState foodLibraryState;

  const LogFoodRow({
    super.key,
    required this.food,
    required this.nutritionState,
    required this.foodLibraryState,
  });

  @override
  State<LogFoodRow> createState() => _LogFoodRowState();
}

class _LogFoodRowState extends State<LogFoodRow> {
  late final TextEditingController _amountController;
  String? _amountError;

  /// Debounce timer for the auto-commit on amount edit. When the
  /// user types in the amount input on an already-logged row, the
  /// row is re-committed to the day log after this timer elapses
  /// with no further keystrokes. Keeps the repository quiet while
  /// the user is still typing.
  Timer? _autoCommitDebounce;

  /// How long to wait after the last keystroke before
  /// auto-committing. 250 ms is short enough to feel live but long
  /// enough to coalesce multi-keystroke edits.
  static const Duration _autoCommitDelay = Duration(milliseconds: 250);

  /// Default amount for grams-type foods (actual amount, not multiplier).
  /// For count-type foods, we use a multiplier of 1 (defaultMultiplier).
  double get _defaultAmount {
    if (widget.food.unitType == FoodUnitType.grams) {
      return widget.food.referenceAmount;
    }
    return 1.0; // count type uses multiplier
  }

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _formatAmount(_defaultAmount),
    );
    // If the food is already logged today, pre-fill the amount
    // input with the existing consumed amount.
    // For grams: show the actual amount consumed.
    // For count: show the multiplier (amountConsumed / referenceAmount).
    final existing =
        widget.nutritionState.findLoggedTodayForFood(widget.food.id);
    if (existing != null) {
      final displayValue = widget.food.unitType == FoodUnitType.grams
          ? existing.amountConsumed
          : existing.amountConsumed / widget.food.referenceAmount;
      _amountController.text = _formatAmount(displayValue);
    }
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void didUpdateWidget(covariant LogFoodRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the food's reference changes (e.g. the library row is
    // replaced with a new food of a different reference), reset
    // the controller to the default. This is rare but cheap to guard.
    if (oldWidget.food.id != widget.food.id ||
        oldWidget.food.referenceAmount != widget.food.referenceAmount ||
        oldWidget.food.unitType != widget.food.unitType) {
      _amountController.text = _formatAmount(_defaultAmount);
    }
  }

  @override
  void dispose() {
    _autoCommitDebounce?.cancel();
    _autoCommitDebounce = null;
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  /// Format the amount for display. Integers render without a
  /// decimal point (e.g. "1" not "1.0"); decimals are preserved
  /// as-is.
  static String _formatAmount(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// Parse the current input. Returns `null` for empty / invalid
  /// input. Returns the parsed value (>= 0) otherwise; the
  /// caller validates the > 0 constraint.
  double? _parseAmount() {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  /// Validate the current input. Updates [_amountError] and returns
  /// the parsed value, or `null` if invalid.
  ///
  /// The amount must be positive. For grams, it's the actual amount;
  /// for count, it's a multiplier. Any positive value is acceptable.
  /// The only invalid inputs are empty, non-numeric, zero, and negative.
  double? _validateAmount() {
    final raw = _parseAmount();
    if (raw == null) {
      _amountError = 'Enter a number';
      return null;
    }
    if (raw <= 0) {
      _amountError = 'Amount must be greater than 0';
      return null;
    }
    _amountError = null;
    return raw;
  }

  /// Convert the typed value into the food's own-unit amount
  /// for persistence. Returns `null` if the input is invalid.
  ///
  /// For grams: the typed value is the actual amount (not multiplied).
  /// For count: the typed value is multiplied by referenceAmount.
  double? _amountInOwnUnit() {
    final value = _validateAmount();
    if (value == null) return null;
    // For count type, treat as multiplier; for grams, use as-is.
    if (widget.food.unitType == FoodUnitType.count) {
      return value * widget.food.referenceAmount;
    }
    return value; // grams: use the typed value directly
  }

  void _onAmountChanged() {
    // Re-validate on every keystroke so the inline error appears
    // immediately. Then restart the auto-commit debounce so the
    // new amount is written to the day log after the user
    // stops typing (only when the food is already logged today;
    // otherwise the checkbox is the explicit commit affordance).
    setState(() {
      _validateAmount();
    });
    _scheduleAutoCommit();
  }

  /// Restart the auto-commit debounce. When the timer fires, if
  /// the food is already logged today and the current input is
  /// valid, call [NutritionState.logConsumedFoodAt] (translating
  /// the multiplier to the food's own-unit amount) to update the
  /// existing row in place. A no-op if the food is not logged
  /// today or the input is invalid.
  void _scheduleAutoCommit() {
    _autoCommitDebounce?.cancel();
    _autoCommitDebounce = Timer(_autoCommitDelay, _autoCommitIfLogged);
  }

  /// Auto-commit the current multiplier to the day log if the food
  /// is already logged today and the input is valid. Fires from
  /// the debounce timer (see [_scheduleAutoCommit]).
  Future<void> _autoCommitIfLogged() async {
    if (!mounted) return;
    if (!widget.nutritionState.isFoodLoggedToday(widget.food.id)) return;
    final amount = _amountInOwnUnit();
    if (amount == null) return;
    await widget.nutritionState.logConsumedFoodAt(widget.food, amount);
  }

  /// Toggle the food's log state. Called from the checkbox
  /// `onChanged`. Validates the multiplier first; if invalid, the
  /// toggle is a no-op and the inline error is surfaced.
  Future<void> _toggle(bool? value) async {
    final isLogged =
        widget.nutritionState.isFoodLoggedToday(widget.food.id);
    if (value == true && !isLogged) {
      // Log on. Translate multiplier to food's own-unit amount
      // before handing off to the state.
      final amount = _amountInOwnUnit();
      if (amount == null) {
        setState(() {}); // surface the validation error
        return;
      }
      await widget.nutritionState.logConsumedFoodAt(widget.food, amount);
    } else if (value == false && isLogged) {
      // Unlog.
      await widget.nutritionState.unlogFoodToday(widget.food.id);
    }
    // value == current logged state → no-op.
  }

  /// Re-commit the current multiplier for an already-logged food.
  /// Called from the `onSubmitted` / `onEditingComplete` callbacks
  /// (i.e. when the user submits the field with the keyboard
  /// "done" key or moves focus away). The typical typing flow is
  /// covered by the debounce timer in [_scheduleAutoCommit]; this
  /// is the focus-loss / submit fallback.
  Future<void> _recommitIfLogged() async {
    if (!widget.nutritionState.isFoodLoggedToday(widget.food.id)) return;
    final amount = _amountInOwnUnit();
    if (amount == null) {
      setState(() {});
      return;
    }
    await widget.nutritionState.logConsumedFoodAt(widget.food, amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colors;
    final food = widget.food;
    final cal = calculateCalories(food);

    return ListenableBuilder(
      listenable: widget.nutritionState,
      builder: (context, _) {
        final isLogged = widget.nutritionState.isFoodLoggedToday(food.id);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Checkbox: primary log/unlog affordance ────────────
              Checkbox(
                key: Key('log_food_checkbox_${food.id}'),
                value: isLogged,
                onChanged: _toggle,
              ),
              // ── Food name + macros (takes remaining space) ────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Food name (1 line, ellipsis on overflow).
                    Text(
                      food.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: themeColors.textDominant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 2×2 macro grid: P/C top, F/cal bottom. Each
                    // cell is its own Text widget (no separator
                    // strings) so the cells can lay out in a
                    // responsive grid.
                    _MacroGrid(
                      calories: cal,
                      protein: food.protein,
                      carbs: food.carbs,
                      fat: food.fat,
                    ),
                  ],
                ),
              ),
              // ── Amount textbox + unit label (right-aligned) ──────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 73,
                    child: TextField(
                      key: Key('log_food_amount_${food.id}'),
                      controller: _amountController,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      inputFormatters: [_AmountInputFormatter()],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: themeColors.textDominant,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonUtilityRadius,
                          ),
                        ),
                        errorText: _amountError,
                        errorMaxLines: 2,
                      ),
                      onSubmitted: (_) => _recommitIfLogged(),
                      onEditingComplete: _recommitIfLogged,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Unit label beneath the textbox (e.g. "g", "ml", "units")
                  Text(
                    _unitLabel(food),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Render the unit label for display beneath the amount textbox.
  /// For grams: returns the reference label (e.g., "g", "ml").
  /// For count: returns "units" as the label.
  static String _unitLabel(Food food) {
    if (food.unitType == FoodUnitType.count) {
      return 'units';
    }
    // For grams, extract just the unit (e.g., "g", "ml") from the reference label
    final raw = food.referenceLabel.trim();
    // Strip "per " prefix if present
    String label = raw;
    if (label.toLowerCase().startsWith('per ')) {
      label = label.substring(4).trim();
    }
    // If it starts with a number, just return the unit part (e.g., "100 g" -> "g")
    final parts = label.split(' ');
    if (parts.length >= 2) {
      // Check if first part is a number
      final numPart = double.tryParse(parts[0]);
      if (numPart != null) {
        return parts.sublist(1).join(' ');
      }
    }
    return label;
  }
}

/// 2×2 macro grid: calories + protein on the top row, carbs + fat
/// on the bottom row. Each cell is its own Text widget so the grid
/// lays out in the parent Row's available space.
///
/// Format (matches the test contract):
///   - macro cells are compact: `21P`, `22C`, `50F` (no space between
///     the number and the unit letter)
///   - the calorie cell is spaced: `622 cal` (a space between the
///     number and the word "cal")
///
/// Zero-macro values still render their `0` cell — a food with
/// `protein = 0` renders `0P`, not an empty cell. This keeps the
/// grid visually consistent and lets the test suite assert on the
/// macro values directly.
class _MacroGrid extends StatelessWidget {
  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  const _MacroGrid({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colors;
    final cellStyle = theme.textTheme.bodySmall?.copyWith(
      color: themeColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top row: cal · P
        Row(
          children: [
            SizedBox(
              width: 73,
              child: Text('$calories cal', style: cellStyle),
            ),
            const SizedBox(width: 8),
            Text('${protein}P', style: cellStyle),
          ],
        ),
        // Bottom row: C · F
        Row(
          children: [
            SizedBox(
              width: 73,
              child: Text('${carbs}C', style: cellStyle),
            ),
            const SizedBox(width: 8),
            Text('${fat}F', style: cellStyle),
          ],
        ),
      ],
    );
  }
}

/// `TextInputFormatter` for the multiplier input on a food row.
///
/// Accepts digits and at most one dot, with up to 3 fractional
/// digits. Intermediate states are allowed (e.g. a trailing dot, a
/// leading dot) so the user can type freely on any keyboard. The
/// validation in [_LogFoodRowState._validateMultiplier] rejects the
/// final value if it's empty, non-numeric, zero, or negative.
class _AmountInputFormatter extends TextInputFormatter {
  static final RegExp _disallowed = RegExp(r'[^\d.]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    if (_disallowed.hasMatch(text)) return oldValue;
    if (text.indexOf('.') != text.lastIndexOf('.')) {
      return oldValue;
    }

    final dotIdx = text.indexOf('.');
    if (dotIdx >= 0) {
      final fractional = text.substring(dotIdx + 1);
      if (fractional.length > 3) return oldValue;
    }

    return newValue;
  }
}
