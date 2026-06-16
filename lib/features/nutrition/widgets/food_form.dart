// filepath: lib/features/nutrition/widgets/food_form.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/food_draft.dart';
import '../../../data/models/models.dart';
import '../../../state/food_library_state.dart';
// Conditional import: reuses the platform-aware image renderer
// from the `FoodThumbnail` widget.
import 'food_thumbnail_stub.dart'
    if (dart.library.io) 'food_thumbnail_io.dart';

export '../../../core/models/food_draft.dart' show FoodDraft;

/// Shared form widget used by both the **+ New Item** flow on
/// [AddFoodScreen] and the **Edit Food** screen.
///
/// The form is parameterized by an optional [initial] [Food] and a
/// required [onSave] callback. When [initial] is `null`, the form
/// starts blank (create mode); when non-null, the form is
/// pre-populated with the food's values (edit mode).
///
/// Form fields (top to bottom):
///   * Image picker tile (`FoodFormImageTile`) — the very top of
///     the form, before the name field. Square, 96×96, with a
///     × overlay to clear.
///   * Name
///   * Category (group) dropdown
///   * Unit type (count vs grams)
///   * Reference amount + Reference label
///   * Protein (g) — macro field
///   * Carbs (g) — macro field
///   * Fiber (g) — macro field (optional, blank = unset)
///   * Fat (g) — macro field
///   * Sodium (mg) — macro field (optional, blank = unset)
///   * Notes (when [showNotesField] is true)
///
/// **Primary bottom CTA**: the form no longer renders an inline
/// `Save` button. The host screen owns the bottom CTA via the
/// shared [OmniBottomCTA] (see
/// `.github/agents/plans/primary-bottom-cta-anchor-width-plan.md`).
/// The host wires the CTA's `onPressed` to
/// [FoodFormController.submit] so the form's validation + save
/// pipeline still runs in one place. See
/// `EditFoodScreen` / `_NewFoodFormScreen` /
/// `_LegacyLibraryEditScreen` for the standard wiring.
///
/// Fiber is exposed alongside carbs in the macro list, matching
/// the [Food.fiber] field on the model. The existing
/// `calculateNetCarbs(food)` helper handles the net-carb math.
///
/// The form is presentation-only:
///   * No repository access (saves route through [FoodLibraryState]).
///   * All colors come from [OmniTheme.colors] /
///     `ThemeData.colorScheme`.
///   * All buttons use the explicit `shape:` +
///     [OmniTheme.button*Radius] contract.
class FoodForm extends StatefulWidget {
  /// When non-null, the form is pre-populated with the food's
  /// values (edit mode). When null, the form starts blank (create
  /// mode).
  final Food? initial;

  /// Source for the categories dropdown. The form listens to
  /// [FoodLibraryState] and re-reads the active groups whenever
  /// they change.
  final FoodLibraryState foodLibraryState;

  /// Save callback. Receives a [FoodDraft] and returns a `Future`
  /// resolving to `true` on success, `false` on failure. The form
  /// pops only on `true` (unless [skipPopOnSave] is true). The form
  /// is responsible for the [GlobalKey<FormState>] validation; the
  /// callback is responsible for any persistence-side work.
  final Future<bool> Function(FoodDraft draft) onSave;

  /// Label rendered on the primary CTA. Defaults to "Save".
  final String saveLabel;

  /// When true, a "Notes" field is rendered below the macros.
  final bool showNotesField;

  /// When true, the form will not pop after successful save.
  /// Caller is responsible for navigation in this case.
  final bool skipPopOnSave;

  /// Host-provided controller. The host's bottom CTA calls
  /// [FoodFormController.submit] which routes through the form's
  /// `_onSave` pipeline (validation + save callback). Required
  /// when the host renders the CTA outside the form (the standard
  /// case after the shared-CTA migration).
  final FoodFormController? controller;

  /// When true, the form auto-saves on blur (tap outside any field)
  /// instead of requiring a save button press.
  final bool autoSaveOnBlur;

  const FoodForm({
    super.key,
    required this.initial,
    required this.foodLibraryState,
    required this.onSave,
    this.saveLabel = 'Save',
    this.showNotesField = false,
    this.skipPopOnSave = false,
    this.controller,
    this.autoSaveOnBlur = false,
  });

  @override
  State<FoodForm> createState() => _FoodFormState();
}

/// Public controller that lets a host's bottom CTA trigger the
/// [FoodForm]'s save pipeline without exposing the form's private
/// state.
///
/// The host instantiates one of these, passes it to
/// [FoodForm.controller], and calls [submit] from the
/// [OmniBottomCTA.onPressed] handler. The form's internal
/// `_onSave()` (validate + `widget.onSave(draft)`) runs exactly
/// the same way it did when the save button was inline.
///
/// The form's `initState` calls [attach] with its internal save
/// handler; the form's `dispose` calls [detach] to clear the
/// reference. The host should dispose the controller in its own
/// `dispose` as a safety net (in case the form is rebuilt without
/// reattaching).
class FoodFormController {
  VoidCallback? _onSubmit;

  /// Register the form's internal save handler. Called by the
  /// [FoodForm] in its `initState`. Public because Dart's
  /// privacy is library-scoped, not class-scoped, so a separate
  /// file like [EditFoodScreen] cannot call a private method
  /// on this controller.
  void attach(VoidCallback onSubmit) {
    _onSubmit = onSubmit;
  }

  /// Clear the form's save handler. Called by the [FoodForm] in
  /// its `dispose`, and by the host as a safety net.
  void detach() {
    _onSubmit = null;
  }

  /// Triggers the form's save pipeline. No-op if the controller
  /// is not yet attached to a form (e.g. during navigation
  /// transitions).
  void submit() {
    _onSubmit?.call();
  }
}

class _FoodFormState extends State<FoodForm> {
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  late final TextEditingController _name;
  late final TextEditingController _referenceAmount;
  late final TextEditingController _referenceLabel;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fiber;
  late final TextEditingController _fat;
  late final TextEditingController _sodium;
  late final TextEditingController _notes;
  final ImagePicker _imagePicker = ImagePicker();

  /// Local copy of the image path. Decoupled from `widget.initial`
  /// so the user can clear the image mid-edit without losing the
  /// original on the parent widget.
  String? _imagePath;

  FoodUnitType _unitType = FoodUnitType.grams;
  String? _groupId; // null = Ungrouped

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Wire the host's controller (if any) to this form's save
    // pipeline so the host's bottom CTA can trigger the form's
    // validation + save flow without exposing private state.
    widget.controller?.attach(_onSave);

    // Set up focus listener for auto-save on blur
    if (widget.autoSaveOnBlur) {
      _focusNode.addListener(_onFocusChange);
    }

    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _referenceAmount = TextEditingController(
      text: (initial?.referenceAmount ?? 100).toString(),
    );
    _referenceLabel = TextEditingController(
      text: initial?.referenceLabel ?? 'g',
    );
    _protein = TextEditingController(text: (initial?.protein ?? 0).toString());
    _carbs = TextEditingController(text: (initial?.carbs ?? 0).toString());
    _fiber = TextEditingController(
      text: (initial?.fiber ?? 0).toString(),
    );
    _fat = TextEditingController(text: (initial?.fat ?? 0).toString());
    _sodium = TextEditingController(
      text: (initial?.sodium ?? 0).toString(),
    );
    _notes = TextEditingController(text: initial?.notes ?? '');
    _unitType = initial?.unitType ?? FoodUnitType.grams;
    _groupId = initial?.groupId;
    _imagePath = initial?.imagePath;
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _name.dispose();
    _referenceAmount.dispose();
    _referenceLabel.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fiber.dispose();
    _fat.dispose();
    _sodium.dispose();
    _notes.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  // ─── Focus handler for auto-save ────────────────────────────────────

  void _onFocusChange() {
    // When focus leaves the form (blur), auto-save
    if (widget.autoSaveOnBlur && !_focusNode.hasFocus) {
      _onSave();
    }
  }

  // ─── Image picker ────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (picked == null) return;
      if (kIsWeb) {
        if (!mounted) return;
        // Web has no persistent file API; mirror the avatar flow's
        // user-facing message.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo selection works on web, but food photo persistence is not supported there yet.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _imagePath = picked.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update photo: $e')),
      );
    }
  }

  void _clearImage() {
    setState(() => _imagePath = null);
  }

  // ─── Save ────────────────────────────────────────────────────────────

  Future<void> _onSave() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fiberRaw = _fiber.text.trim();
      final sodiumRaw = _sodium.text.trim();
      final draft = FoodDraft(
        name: _name.text.trim(),
        groupId: _groupId,
        unitType: _unitType,
        referenceAmount: double.parse(_referenceAmount.text.trim()),
        referenceLabel: _referenceLabel.text.trim(),
        protein: int.parse(_protein.text.trim()),
        carbs: int.parse(_carbs.text.trim()),
        fiber: fiberRaw.isEmpty ? null : int.parse(fiberRaw),
        fat: int.parse(_fat.text.trim()),
        sodium: sodiumRaw.isEmpty ? null : int.parse(sodiumRaw),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        imagePath: _imagePath,
      );
      final ok = await widget.onSave(draft);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not save food')),
        );
        return;
      }
      // Skip pop if caller wants to handle navigation (e.g., switch tabs)
      if (widget.skipPopOnSave) return;
      if (!navigator.mounted) return;
      navigator.pop();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save food')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.foodLibraryState,
      builder: (context, _) {
        final groups = _sortedGroups(widget.foodLibraryState.activeFoodGroups);
        return Form(
          key: _formKey,
          child: Focus(
            focusNode: _focusNode,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
              FoodFormImageTile(
                key: const Key('food_form_image_tile'),
                imagePath: _imagePath,
                onPickGallery: () => _pickImage(ImageSource.gallery),
                onPickCamera: () => _pickImage(ImageSource.camera),
                onClear: _clearImage,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('food_form_name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('food_form_group'),
                value: _groupId,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Ungrouped'),
                  ),
                  for (final g in groups)
                    DropdownMenuItem<String?>(
                      value: g.id,
                      child: Text(g.name),
                    ),
                ],
                onChanged: (v) => setState(() => _groupId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FoodUnitType>(
                key: const Key('food_form_unit_type'),
                value: _unitType,
                decoration: const InputDecoration(
                  labelText: 'Unit type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: FoodUnitType.count,
                    child: Text('Count (1 unit)'),
                  ),
                  DropdownMenuItem(
                    value: FoodUnitType.grams,
                    child: Text('Grams (100 g)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _unitType = v;
                    if (v == FoodUnitType.grams) {
                      if (_referenceAmount.text == '1') {
                        _referenceAmount.text = '100';
                        _referenceLabel.text = 'g';
                      }
                    } else {
                      if (_referenceAmount.text == '100') {
                        _referenceAmount.text = '1';
                        _referenceLabel.text = 'unit';
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('food_form_reference_amount'),
                      controller: _referenceAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*$'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Reference amount',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validatePositiveDouble,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: const Key('food_form_reference_label'),
                      controller: _referenceLabel,
                      decoration: const InputDecoration(
                        labelText: 'Reference label',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Macros (the reference above)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: OmniTheme.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _macroField(
                key: const Key('food_form_protein'),
                controller: _protein,
                label: 'Protein (g)',
                required: true,
              ),
              const SizedBox(height: 8),
              _macroField(
                key: const Key('food_form_carbs'),
                controller: _carbs,
                label: 'Carbs (g)',
                required: true,
              ),
              const SizedBox(height: 8),
              _macroField(
                key: const Key('food_form_fiber'),
                controller: _fiber,
                label: 'Fiber (g)',
                required: false,
              ),
              const SizedBox(height: 8),
              _macroField(
                key: const Key('food_form_fat'),
                controller: _fat,
                label: 'Fat (g)',
                required: true,
              ),
              const SizedBox(height: 8),
              _macroField(
                key: const Key('food_form_sodium'),
                controller: _sodium,
                label: 'Sodium (mg)',
                required: false,
              ),
              if (widget.showNotesField) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('food_form_notes'),
                  controller: _notes,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              // The form no longer renders an inline save button.
              // The host screen owns the primary bottom CTA via
              // the shared `OmniBottomCTA`. The host wires the
              // CTA's `onPressed` to `FoodFormController.submit`,
              // which calls into the form's `_onSave` pipeline
              // (validation + `widget.onSave(draft)`) — the same
              // pipeline the inline button used to trigger.
            ],
          ),
        ),
        );
      },
    );
  }

  /// Macro text field with integer-only input. Required fields
  /// reject empty input; optional fields allow empty (treated as
  /// "unset", persisted as `null` on the model).
  Widget _macroField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required bool required,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final trimmed = v?.trim() ?? '';
        if (trimmed.isEmpty) {
          return required ? 'Required' : null;
        }
        if (int.tryParse(trimmed) == null) {
          return 'Must be a whole number';
        }
        return null;
      },
    );
  }

  /// Validates a positive double. Empty / 0 are not allowed for
  /// reference amount because the macros are expressed "per" it.
  String? _validatePositiveDouble(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(v.trim());
    if (parsed == null) return 'Must be a number';
    if (parsed <= 0) return 'Must be greater than 0';
    return null;
  }

  /// Case-insensitive alphabetical sort for the category dropdown.
  static List<FoodGroup> _sortedGroups(List<FoodGroup> groups) {
    final copy = [...groups];
    copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return copy;
  }
}

/// The image tile rendered at the very top of [FoodForm]. Square
/// 96×96 by default. When an image is set, renders the photo with
/// small × (clear) and edit (change) overlays; when no image is
/// set, renders a dashed placeholder with an "Add photo"
/// affordance.
class FoodFormImageTile extends StatelessWidget {
  final String? imagePath;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onClear;
  final double size;

  const FoodFormImageTile({
    super.key,
    required this.imagePath,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onClear,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: hasImage
                  ? _ImageBody(path: imagePath!, size: size)
                  : _PlaceholderBody(
                      size: size,
                      onTap: () => _showPickerSheet(context),
                    ),
            ),
            if (hasImage) ...[
              Positioned(
                top: 0,
                right: 0,
                child: _OverlayButton(
                  icon: Icons.close,
                  onTap: onClear,
                  tooltip: 'Remove photo',
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: _OverlayButton(
                  icon: Icons.edit,
                  onTap: () => _showPickerSheet(context),
                  tooltip: 'Change photo',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Show a bottom sheet with Camera / Gallery choices. Mirrors the
  /// avatar flow on the profile screen.
  Future<void> _showPickerSheet(BuildContext context) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('food_form_image_camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onPickCamera();
                },
              ),
              ListTile(
                key: const Key('food_form_image_gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onPickGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Image body. Uses the platform-aware [FoodThumbnailImage] (native
/// `Image.file` with `errorBuilder`, web stub) — reuses the
/// conditional import at the top of the file.
class _ImageBody extends StatelessWidget {
  final String path;
  final double size;

  const _ImageBody({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: FoodThumbnailImage(
          path: path,
          size: size,
          radius: 12,
          placeholder: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Placeholder body (no image). Shows a dashed border, a camera
/// icon, and an "Add photo" label.
class _PlaceholderBody extends StatelessWidget {
  final double size;
  final VoidCallback onTap;

  const _PlaceholderBody({required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    return Material(
      color: themeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: themeColors.textMuted.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: size,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_a_photo_outlined,
                color: themeColors.textSecondary,
                size: size * 0.32,
              ),
              const SizedBox(height: 4),
              Text(
                'Add photo',
                style: TextStyle(
                  color: themeColors.textSecondary,
                  fontSize: size * 0.12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small circular overlay button used for the × (clear) and edit
/// (change) affordances on top of the image.
class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _OverlayButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 16, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
