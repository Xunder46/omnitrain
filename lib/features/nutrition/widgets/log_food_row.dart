// filepath: lib/features/nutrition/widgets/log_food_row.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/services/image_storage_service.dart';
import '../../../core/utils/food_helpers.dart';
import '../../../data/models/models.dart';
import '../../../state/food_library_state.dart';
import '../../../state/nutrition_state.dart';
import 'food_thumbnail.dart';

/// A single food-library row that doubles as the "log a food as consumed"
/// affordance on the nutrition page.
///
/// Layout (left to right):
///
///   ```
///   [ thumb ]    [ food name (1 line) ]           [ amount ] [label]
///   [ toggle ]   [ <cal> cal · <P>P · <C>C · <F>F ]   [ textbox ] [g/ml]
///       (40×40)  ▲                                   ▲
///       (tappable                                     │
///       ≥48dp)                                        │
///   ```
///
/// **Iteration 1** replaces the leading `Checkbox` with a tappable
/// [FoodThumbnail] that IS the log/unlog toggle (S-001). Foods
/// without an image render the muted placeholder thumb (S-002 — the
/// common case on web, where the image picker is a no-op). The
/// thumb's tap target is padded to **≥ 48 dp** in both dimensions
/// (design-system gym-glove rule). The unchecked + checked states
/// mirror each other in shape (2 px thumb border + 16 px corner
/// badge) so the toggle is always visually obvious, and animate
/// via `AnimatedContainer` at
/// `OmniTheme.animationDuration` / `OmniTheme.animationCurve`:
///   - Logged: 2 px `primary` border + filled `primary` corner
///     disc with a surface-colored check glyph.
///   - Unlogged: 2 px `textMuted` border + hollow `textMuted`
///     corner ring (surface fill, no glyph).
/// The thumb wraps a `Semantics(checked: ...)` node so screen
/// readers + tests see a toggle (S-005). Iteration 1 also
/// condenses the 2×2 macro grid to a single
/// `"<cal> cal · <P>P · <C>C · <F>F"` line (S-007) for format
/// parity with `AddFoodScreen` rows.
///
/// The amount field behavior depends on the food's [FoodUnitType]:
///   - For `grams` (weight-based foods): the typed value is the **actual
///     amount** in the food's unit (e.g., reference 100g, user enters 50
///     → 50g consumed, not 50×100g).
///   - For `count` (discrete items): the typed value is a **multiplier**
///     against the reference (e.g., reference 1 egg, user enters 0.5
///     → 0.5 eggs consumed).
///
/// The thumb toggle is the primary "mark consumed" affordance.
/// Tapping it logs the food at the current amount. Editing the
/// amount on a logged row **auto-commits** the new amount to the
/// day log (debounced ~250 ms) — the user does NOT need to re-tap
/// the thumb; the ring and totals update live.
///
/// The per-row "remove from library" trashcan has been removed (a
/// redesigned deletion UX is a follow-up). The hard-delete API on
/// [FoodLibraryState] remains available; it is just not surfaced in
/// this row.
///
/// Validation: the amount must be `> 0`. While the input is
/// invalid (empty, zero, or non-numeric), the thumb tap is a
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
    final existing = widget.nutritionState.findLoggedTodayForFood(
      widget.food.id,
    );
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
    // otherwise the thumb is the explicit commit affordance).
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

  /// Toggle the food's log state. Called from the thumb
  /// `onTap`. `nextState` is `true` to log, `false` to unlog.
  /// Validates the amount first; if invalid (e.g. the user
  /// cleared the amount field before tapping), the toggle is a
  /// no-op and the inline error is surfaced.
  Future<void> _toggle(bool nextState) async {
    final isLogged = widget.nutritionState.isFoodLoggedToday(widget.food.id);
    if (nextState == true && !isLogged) {
      // Log on. Translate the typed value to the food's
      // own-unit amount before handing off to the state.
      final amount = _amountInOwnUnit();
      if (amount == null) {
        setState(() {}); // surface the validation error
        return;
      }
      await widget.nutritionState.logConsumedFoodAt(widget.food, amount);
    } else if (nextState == false && isLogged) {
      // Unlog.
      await widget.nutritionState.unlogFoodToday(widget.food.id);
    }
    // `nextState == isLogged` is a no-op (the user tapped a
    // thumb that was already in the target state — e.g. tapped
    // the checked thumb when it was already checked; the thumb
    // widget does not fire onTap in that case anyway, but the
    // guard is kept defensively).
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
        // Single-line macro string (S-007). Format parity with
        // `AddFoodScreen`'s catalog rows.
        final macroText =
            '$cal cal · ${food.protein}P · ${food.carbs}C · ${food.fat}F';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Thumb toggle: primary log/unlog affordance ───────
              _ThumbToggle(
                food: food,
                isLogged: isLogged,
                imageStorage: widget.foodLibraryState.imageStorageOrNull,
                onTap: () => _toggle(isLogged ? false : true),
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
                    // Single-line macros (S-007) — format parity
                    // with `AddFoodScreen` rows.
                    Text(
                      macroText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: themeColors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                        fontFeatures: const [FontFeature.tabularFigures()],
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
  /// Shows "{referenceAmount} {referenceLabel}" (e.g., "100 g", "1 unit").
  /// Handles legacy labels like "per 100g" by extracting just the unit part.
  static String _unitLabel(Food food) {
    final amount = food.referenceAmount.toInt();
    var label = food.referenceLabel.trim();

    // Handle legacy labels that contain "per" (e.g., "per 100g", "per 100 g")
    if (label.toLowerCase().startsWith('per ')) {
      label = label.substring(4).trim();
      // If it still starts with a number, extract just the unit part
      final parts = label.split(' ');
      if (parts.isNotEmpty) {
        final firstPart = parts[0];
        if (double.tryParse(firstPart) != null) {
          // First part is a number, take the rest
          label = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        }
      }
    }

    return '$amount $label';
  }
}

/// Tappable food thumbnail that IS the log/unlog toggle on a
/// [LogFoodRow] (S-001..S-005).
///
/// Composition:
///   - 48×48 tappable area (the design-system gym-glove minimum)
///     padding the 40×40 [FoodThumbnail] to a comfortable tap
///     target.
///   - The 40×40 thumbnail is rendered with an `AnimatedContainer`
///     border that animates between the unchecked and checked
///     states at [OmniTheme.animationDuration] /
///     [OmniTheme.animationCurve]. The unchecked state uses the
///     same 2 px outline as the checked state (so the toggle
///     shape is always visible) but in a muted/grey color
///     (`textMuted`); the checked state uses `primary`. This
///     makes the affordance obvious at a glance — every thumb
///     reads as a paired state of the same control.
///   - The top-right corner carries a 16×16 circular badge in
///     both states. Unchecked: a hollow ring (surface fill,
///     muted border, no glyph) so it reads as "empty / not yet
///     selected." Checked: a filled `primary` disc with a
///     surface-colored check glyph. The badge's color, fill,
///     and border all animate through `AnimatedContainer`.
///   - The whole thing is wrapped in a `Semantics(checked: ...)`
///     node so screen readers + tests see a toggle (S-005).
///   - The `Key('log_food_thumb_<food.id>')` is mounted on the
///     `Semantics` wrapper (not the [GestureDetector]) so test
///     semantics lookups find the correct node — `tester.getSemantics`
///     on the key returns the Semantics node carrying the
///     `checked` / `label` properties.
class _ThumbToggle extends StatefulWidget {
  final Food food;
  final bool isLogged;
  final ImageStorageService? imageStorage;
  final VoidCallback onTap;

  /// Diameter of the visible thumbnail (also the badge's parent
  /// box width). Matches `FoodThumbnail`'s default.
  static const double _thumbSize = 40.0;

  /// Tap-target dimension. The design-system gym-glove rule
  /// requires ≥ 48 dp.
  static const double _tapTargetSize = 48.0;

  /// Diameter of the corner badge (always rendered; fills /
  /// borders change between states).
  static const double _badgeSize = 16.0;

  /// Width of the thumb border. Same in both states so the
  /// outline always reads as a continuous ring around the
  /// thumbnail.
  static const double _thumbBorderWidth = 2.0;

  /// Width of the corner badge's border. Same in both states.
  static const double _badgeBorderWidth = 1.5;

  const _ThumbToggle({
    required this.food,
    required this.isLogged,
    required this.imageStorage,
    required this.onTap,
  });

  @override
  State<_ThumbToggle> createState() => _ThumbToggleState();
}

class _ThumbToggleState extends State<_ThumbToggle> {
  /// Whether the user is currently pressing the thumb. Drives
  /// the 0.96× press scale (S-003 / S-004 feedback).
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final isLogged = widget.isLogged;
    // Unchecked uses the same 2 px outline as the checked state,
    // but in `textMuted` (the muted/grey tone) so the toggle
    // shape is always visible. The badge mirrors the same
    // shape/color split (hollow ring vs. filled disc with a
    // check) — see the comment block on [_ThumbToggle].
    final borderColor =
        isLogged ? themeColors.primary : themeColors.textMuted;
    final badgeFill =
        isLogged ? themeColors.primary : themeColors.surface;
    final badgeBorderColor =
        isLogged ? themeColors.surface : themeColors.textMuted;

    final thumb = AnimatedContainer(
      duration: OmniTheme.animationDuration,
      curve: OmniTheme.animationCurve,
      width: _ThumbToggle._thumbSize,
      height: _ThumbToggle._thumbSize,
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor,
          width: _ThumbToggle._thumbBorderWidth,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: FoodThumbnail(
          imagePath: widget.food.imagePath,
          imageStorage: widget.imageStorage,
          size: _ThumbToggle._thumbSize,
          // The thumbnail widget paints its own border for the
          // placeholder (0.2-alpha muted outline) and none when an
          // image is present. We render OUR border on the
          // AnimatedContainer so the two don't double up.
        ),
      ),
    );

    return Semantics(
      key: Key('log_food_thumb_${widget.food.id}'),
      container: true,
      checked: isLogged,
      label: isLogged ? 'Unlog ${widget.food.name}' : 'Log ${widget.food.name}',
      button: true,
      enabled: true,
      onTap: widget.onTap,
      excludeSemantics: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: _ThumbToggle._tapTargetSize,
          height: _ThumbToggle._tapTargetSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // The thumb itself, centered in the 48×48 tap target.
              // AnimatedScale provides the 0.96× press feedback
              // (the standard pressed scale is too aggressive for
              // a small inline thumb; 0.96 is the same ratio the
              // CrownControl chip uses elsewhere, so a touch on the
              // thumb feels consistent with the rest of the app's
              // interactive surfaces).
              AnimatedScale(
                scale: _pressed ? 0.96 : 1.0,
                duration: OmniTheme.animationDuration,
                curve: OmniTheme.animationCurve,
                child: thumb,
              ),
              // Corner badge — top-right, always present so the
              // toggle affordance reads as a paired state. The
              // fill + border + glyph cross-fade through
              // AnimatedContainer; the unchecked state is a
              // hollow ring (surface fill, muted border, no
              // glyph) and the checked state is a filled
              // primary disc with a surface-colored check.
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedContainer(
                  duration: OmniTheme.animationDuration,
                  curve: OmniTheme.animationCurve,
                  width: _ThumbToggle._badgeSize,
                  height: _ThumbToggle._badgeSize,
                  decoration: BoxDecoration(
                    color: badgeFill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: badgeBorderColor,
                      width: _ThumbToggle._badgeBorderWidth,
                    ),
                  ),
                  child: isLogged
                      ? Icon(
                          Icons.check,
                          size: 12,
                          color: themeColors.surface,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
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
