// filepath: lib/features/nutrition/widgets/food_form.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/food_draft.dart';
import '../../../core/services/image_storage_service.dart';
import '../../../core/utils/food_helpers.dart';
import '../../../core/utils/food_serving.dart';
import '../../../data/models/models.dart';
import '../../../state/food_library_state.dart';
import '../../../widgets/feedback/omni_message.dart';
import '../../../widgets/inputs/select_all_on_focus.dart';
// The form's `FoodFormImageTile` now delegates its image body
// to the shared `FoodThumbnail` widget so the editor and the
// library list render photos through the same three-tier
// precedence (user photo → shipped photo → placeholder). The
// `FoodThumbnail` import is unconditional; it pulls in the
// platform-aware `FoodThumbnailImage` (native `Image.file`
// with `errorBuilder`, web stub) via its own conditional import.
import 'food_thumbnail.dart';

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
///   * Name — with a quiet duplicate-name note underneath when the
///     trimmed name already exists in the Library (D-92c.7).
///   * Image picker tile (`FoodFormImageTile`) — directly below the
///     name (and its note), before the category dropdown. Square,
///     96×96, with a × overlay to clear (D-92c.6, D-92c.9).
///   * Category (group) dropdown
///   * Serving — "Nutrition facts are per" (100 g / 100 ml / 1 serving,
///     a package serving, or As saved), then the per-serving heading
///   * Fat (g) — macro field (blank saves 0)
///   * Carbs (g) — macro field (blank saves 0)
///   * Fiber (g) — macro field (blank saves "not recorded")
///   * Protein (g) — macro field (blank saves 0)
///   * Sodium (mg) — macro field (blank saves "not recorded")
///   * Calories — "= N cal", derived from protein/carbs/fat through
///     `caloriesFromMacros` and live as the boxes change (D-92c.1)
///   * Notes (when [showNotesField] is true)
///
/// **Primary bottom CTA**: the form no longer renders an inline
/// `Save` button. The host screen owns the bottom CTA via the
/// shared [OmniBottomCTA] (see
/// `docs/plans/primary-bottom-cta-anchor-width-plan.md`).
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

  /// Notified whenever the form-local photo changes, with the path the
  /// form now holds: the persisted managed path after a pick, `null` after
  /// the × overlay cleared it.
  ///
  /// Nothing about the photo reaches the data layer until Save (the save
  /// draft carries `imagePath`), so a host that guards unsaved work has no
  /// other way to see a pick or a clear; it compares the reported path
  /// with the one the stored food started with.
  final ValueChanged<String?>? onImageChanged;

  const FoodForm({
    super.key,
    required this.initial,
    required this.foodLibraryState,
    required this.onSave,
    this.saveLabel = 'Save',
    this.showNotesField = false,
    this.skipPopOnSave = false,
    this.controller,
    this.onImageChanged,
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

/// The segments of the form's one serving control (D-92b.5).
enum _ServingBasis { per100g, per100ml, serving, asSaved }

class _FoodFormState extends State<FoodForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _servingLabelController;
  late final TextEditingController _packageAmountController;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fiber;
  late final TextEditingController _fat;
  late final TextEditingController _sodium;
  late final TextEditingController _notes;
  // Per-field focus nodes. Numeric value fields are wired to
  // select-all on focus so the user can retype a value without
  // first clearing it (e.g. tapping into a pre-filled `4` g of fat
  // and typing `0.5` overwrites `4` rather than appending). The
  // free-text name field and the multi-line notes field are NOT
  // wired to select-all — those are free-text fields where selecting
  // everything on focus would get in the way of editing in place.
  final _nameFocus = FocusNode();
  final _proteinFocus = FocusNode();
  final _carbsFocus = FocusNode();
  final _fiberFocus = FocusNode();
  final _fatFocus = FocusNode();
  final _sodiumFocus = FocusNode();
  final _notesFocus = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  /// Detachers returned by `bindSelectAllOnFocus` for each per-field
  /// focus node. `dispose` iterates this list to remove the listeners
  /// before disposing the focus nodes themselves.
  final List<VoidCallback> _selectAllDetachers = [];

  /// Local copy of the image path. Decoupled from `widget.initial`
  /// so the user can clear the image mid-edit without losing the
  /// original on the parent widget.
  String? _imagePath;

  /// The serving choice the control is on. A new food starts on 100 g
  /// (D-92b.2); an edited food loads through `servingChoiceFrom`, so the
  /// derivation never looks at text (D-92b.3).
  ServingChoice _servingChoice = const Per100G();

  /// The stored serving an As-saved food opened with. Non-null only when the
  /// loaded triple fits none of the four choices; the fourth segment restores
  /// it verbatim (D-92b.5).
  AsSavedServing? _asSaved;

  /// The triple the edited food was opened with; null for a New Food. The
  /// D-92b.6 note compares the would-save triple against it.
  (FoodUnitType, double, String)? _openedServing;

  /// Whether the package row is open under the 100 g / 100 ml segment
  /// (D-92b.11). The typed amount survives while the row is closed.
  bool _packageOpen = false;

  /// The named servings offered as chips (D-92b.5).
  static const List<String> _servingWords = [
    'slice',
    'scoop',
    'bar',
    'piece',
    'cup',
  ];

  String? _groupId; // null = Ungrouped

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Wire the host's controller (if any) to this form's save
    // pipeline so the host's bottom CTA can trigger the form's
    // validation + save flow without exposing private state.
    widget.controller?.attach(_onSave);

    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    // The duplicate note is derived from the live name text, so the
    // note appears and disappears while typing (D-92c.11).
    _name.addListener(_onNameChanged);
    // The serving choice comes from the stored NUMERIC values, never from
    // their text: a device round-trip stores `100.0` / `1.0`, and the old
    // text comparison (`text == '100'`) silently missed them (D-92b.3).
    if (initial != null) {
      _openedServing = (
        initial.unitType,
        initial.referenceAmount,
        initial.referenceLabel,
      );
      final loaded = servingChoiceFrom(
        initial.unitType,
        initial.referenceAmount,
        initial.referenceLabel,
      );
      _servingChoice = loaded;
      if (loaded is AsSavedServing) _asSaved = loaded;
    }
    _servingLabelController = TextEditingController(
      text: switch (_servingChoice) {
        NamedServing(:final label) => label,
        _ => '',
      },
    );
    _packageAmountController = TextEditingController(
      text: switch (_servingChoice) {
        PackageServing(:final amount) => formatGrams(amount),
        _ => '',
      },
    );
    _packageOpen = _servingChoice is PackageServing;
    // A new food opens with blank boxes; an edit shows the stored value the
    // way a label prints it (`31`, not `31.0`). A never-recorded fiber or
    // sodium stays empty, so saving unchanged keeps it unrecorded
    // (D-92c.3, D-92c.4).
    final fiber = initial?.fiber;
    final sodium = initial?.sodium;
    _protein = TextEditingController(
      text: initial == null ? '' : formatGrams(initial.protein),
    );
    _carbs = TextEditingController(
      text: initial == null ? '' : formatGrams(initial.carbs),
    );
    _fiber = TextEditingController(
      text: fiber == null ? '' : formatGrams(fiber),
    );
    _fat = TextEditingController(
      text: initial == null ? '' : formatGrams(initial.fat),
    );
    _sodium = TextEditingController(
      text: sodium == null ? '' : formatGrams(sodium),
    );
    _notes = TextEditingController(text: initial?.notes ?? '');
    _groupId = initial?.groupId;
    _imagePath = initial?.imagePath;

    // Wire numeric and short-value focus nodes to select-all on
    // focus via the shared `bindSelectAllOnFocus` helper (the same
    // primitive the `SelectAllOnFocus` wrapper and
    // `SelectAllOnFocusNode` class are built on). Each binding
    // returns a `VoidCallback` that detaches the listener; we
    // collect them so `dispose` can remove the listeners before
    // the focus nodes are disposed.
    //
    // The free-text name field and the multi-line notes field are
    // intentionally NOT in this list — they keep default
    // cursor-placement behavior so the user can position the
    // cursor freely inside free-form text.
    _selectAllDetachers.addAll([
      bindSelectAllOnFocus(focusNode: _proteinFocus, controller: _protein),
      bindSelectAllOnFocus(focusNode: _carbsFocus, controller: _carbs),
      bindSelectAllOnFocus(focusNode: _fiberFocus, controller: _fiber),
      bindSelectAllOnFocus(focusNode: _fatFocus, controller: _fat),
      bindSelectAllOnFocus(focusNode: _sodiumFocus, controller: _sodium),
    ]);
  }

  @override
  void dispose() {
    widget.controller?.detach();
    for (final detach in _selectAllDetachers) {
      detach();
    }
    _selectAllDetachers.clear();
    _nameFocus.dispose();
    _proteinFocus.dispose();
    _carbsFocus.dispose();
    _fiberFocus.dispose();
    _fatFocus.dispose();
    _sodiumFocus.dispose();
    _notesFocus.dispose();
    _name.removeListener(_onNameChanged);
    _name.dispose();
    _servingLabelController.dispose();
    _packageAmountController.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fiber.dispose();
    _fat.dispose();
    _sodium.dispose();
    _notes.dispose();
    super.dispose();
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
        // user-facing message (D-5: web persistence is intentionally
        // out of scope for this iteration).
        OmniMessage.show(
          context,
          'Photo selection works on web, but food photo persistence is not '
          'supported there yet.',
        );
        return;
      }
      await handlePickedImage(picked);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Update photo: $e');
      OmniMessage.error(context, 'Could not update the photo. Try again.');
    }
  }

  /// Persist a picked [XFile] into the managed directory and update
  /// the form's local `_imagePath`.
  ///
  /// This is the single source of truth for the pick-handler
  /// post-Persistence work. `_pickImage` is the user-facing
  /// entry point that drives the OS picker and then delegates
  /// here. Tests invoke this method directly to bypass the
  /// `image_picker` platform channel.
  ///
  /// The photo stays form-local: nothing reaches the data layer
  /// until the user saves (the save draft carries `imagePath`), so
  /// the persisted path is reported through [FoodForm.onImageChanged]
  /// for the host's unsaved-work guard (D-92a.2).
  @visibleForTesting
  Future<void> handlePickedImage(XFile picked) async {
    if (kIsWeb) return;
    // D-1..D-9: copy the picked file into the managed directory.
    // The picked file lives in a temporary cache the OS may purge,
    // so we replace it with a stable app-owned path. D-6: on copy
    // failure, the service has already cleaned up any partial
    // destination; we do not mutate state.
    final persistedPath = await widget.foodLibraryState.imageStorage
        .persistPickedImage(picked);
    if (!mounted) return;
    setState(() => _imagePath = persistedPath);
    // The host's unsaved-work guard reads the pick through this
    // callback: the photo stays form-local until Save, so nothing else
    // can see it.
    widget.onImageChanged?.call(persistedPath);
  }

  /// Clear the current image.
  ///
  /// The clear is form-local: nothing reaches the data layer until the
  /// user saves, so `null` is reported through [FoodForm.onImageChanged]
  /// for the host's unsaved-work guard (D-92a.2). The save draft then
  /// carries `imagePath: null`, and the state method's
  /// `previousPath != draft.imagePath` branch deletes the managed file
  /// the clear replaced (D-7).
  ///
  /// **Production entry point**: the × (clear) overlay on
  /// [FoodFormImageTile] invokes this via the `onClear`
  /// callback. Dart's function-type variance lets the
  /// `Future<void>` return be discarded at the `VoidCallback`
  /// call site without a wrapper. Tests invoke this directly
  /// via the `@visibleForTesting` annotation, bypassing the
  /// overlay tap.
  @visibleForTesting
  Future<void> clearImage() async {
    setState(() => _imagePath = null);
    widget.onImageChanged?.call(null);
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
    final theme = Theme.of(context);
    try {
      final fiberRaw = _fiber.text.trim();
      final sodiumRaw = _sodium.text.trim();
      // Macros are stored as `double` (Food / FoodDraft) so the
      // user can enter fractional grams (e.g. `0.5` g of fat). A blank
      // Protein/Carbs/Fat means 0; a blank Fiber/Sodium means "not
      // recorded" (null). Validation has already rejected non-numeric
      // text, so `tryParse` only softens the blank case (D-92c.5).
      final (servingUnitType, servingAmount, servingLabel) =
          storedServingFrom(_currentChoice);
      final draft = FoodDraft(
        name: _name.text.trim(),
        groupId: _groupId,
        unitType: servingUnitType,
        referenceAmount: servingAmount,
        referenceLabel: servingLabel,
        protein: double.tryParse(_protein.text.trim()) ?? 0.0,
        carbs: double.tryParse(_carbs.text.trim()) ?? 0.0,
        fiber: fiberRaw.isEmpty ? null : double.tryParse(fiberRaw),
        fat: double.tryParse(_fat.text.trim()) ?? 0.0,
        sodium: sodiumRaw.isEmpty ? null : double.tryParse(sodiumRaw),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        imagePath: _imagePath,
      );
      final ok = await widget.onSave(draft);
      if (!ok) {
        OmniMessage.errorOn(messenger, theme, 'Could not save food');
        return;
      }
      // Skip pop if caller wants to handle navigation (e.g., switch tabs)
      if (widget.skipPopOnSave) return;
      if (!navigator.mounted) return;
      navigator.pop();
    } catch (_) {
      OmniMessage.errorOn(messenger, theme, 'Could not save food');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Serving control ─────────────────────────────────────────────────

  /// The segment shown for [_servingChoice]. A loaded package serving rides
  /// on the 100 g / 100 ml segment with its row open (D-92b.11).
  _ServingBasis get _basis => switch (_servingChoice) {
    Per100G() => _ServingBasis.per100g,
    Per100Ml() => _ServingBasis.per100ml,
    PackageServing(:final label) =>
      label == 'ml' ? _ServingBasis.per100ml : _ServingBasis.per100g,
    NamedServing() => _ServingBasis.serving,
    AsSavedServing() => _ServingBasis.asSaved,
  };

  /// The unit of the package row under the selected segment.
  String get _packageLabel => _basis == _ServingBasis.per100ml ? 'ml' : 'g';

  /// The choice the heading and the save read: built live from the controls
  /// so the heading follows typing (D-92b.4). An open package row with no
  /// usable amount falls back to its 100 g / 100 ml base.
  ServingChoice get _currentChoice => switch (_servingChoice) {
    Per100G() => _packageChoiceOrBase('g'),
    Per100Ml() => _packageChoiceOrBase('ml'),
    PackageServing(:final label) => _packageChoiceOrBase(label),
    NamedServing() => NamedServing(label: _servingLabelController.text.trim()),
    AsSavedServing() => _servingChoice,
  };

  ServingChoice _packageChoiceOrBase(String label) {
    if (_packageOpen) {
      final amount = double.tryParse(_packageAmountController.text.trim());
      if (amount != null && amount > 0) {
        return PackageServing(amount: amount, label: label);
      }
    }
    return label == 'ml' ? const Per100Ml() : const Per100G();
  }

  /// The D-92b.6 line, or null when the numbers still describe the serving
  /// the food was opened with or this is a New Food.
  String? get _perNote {
    final opened = _openedServing;
    if (opened == null) return null;
    final choice = _currentChoice;
    if (storedServingFrom(choice) == opened) return null;
    const prefix = 'Nutrition per ';
    final heading = servingHeading(choice);
    final per = heading.startsWith(prefix)
        ? heading.substring(prefix.length)
        : heading;
    return 'Check these numbers are per $per';
  }

  List<ButtonSegment<_ServingBasis>> _basisSegments() {
    final saved = _asSaved;
    return [
      const ButtonSegment(value: _ServingBasis.per100g, label: Text('100 g')),
      const ButtonSegment(value: _ServingBasis.per100ml, label: Text('100 ml')),
      const ButtonSegment(
        value: _ServingBasis.serving,
        label: Text('1 serving'),
      ),
      if (saved != null)
        ButtonSegment(
          value: _ServingBasis.asSaved,
          label: Text('As saved: ${formatGrams(saved.amount)} ${saved.label}'),
        ),
    ];
  }

  /// The app's segmented-control style (same tokens as the nutrition trend
  /// card's toggle): theme colours only, utility button radius.
  ButtonStyle _basisButtonStyle() {
    final colors = OmniTheme.colors;
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.primary;
        return colors.surface;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.surface;
        return colors.textSecondary;
      }),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        ),
      ),
    );
  }

  void _onBasisChanged(Set<_ServingBasis> selection) {
    if (selection.isEmpty) return;
    setState(() {
      switch (selection.first) {
        case _ServingBasis.per100g:
          _servingChoice = const Per100G();
        case _ServingBasis.per100ml:
          _servingChoice = const Per100Ml();
        case _ServingBasis.serving:
          _servingChoice = const NamedServing(label: '');
        case _ServingBasis.asSaved:
          final saved = _asSaved;
          if (saved != null) _servingChoice = saved;
      }
    });
  }

  void _fillServingLabel(String word) {
    setState(() {
      _servingLabelController.value = TextEditingValue(
        text: word,
        selection: TextSelection.collapsed(offset: word.length),
      );
    });
  }

  /// Rebuild for the derived duplicate-name note as the name changes.
  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calories = caloriesFromMacros(
      protein: _parsed(_protein),
      carbs: _parsed(_carbs),
      fat: _parsed(_fat),
    );
    return ListenableBuilder(
      listenable: widget.foodLibraryState,
      builder: (context, _) {
        final groups = _sortedGroups(widget.foodLibraryState.activeFoodGroups);
        return Form(
          key: _formKey,
          child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  key: const Key('food_form_name'),
                  controller: _name,
                  focusNode: _nameFocus,
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
                // A quiet note, never a validation: the user may still save
                // a name that already exists (D-92c.7).
                if (widget.foodLibraryState.nameExistsInLibrary(
                  _name.text.trim(),
                  excluding: widget.initial,
                )) ...[
                  const SizedBox(height: 4),
                  Text(
                    "There's already a food called "
                    '"${_name.text.trim()}" in the Library',
                    key: const Key('food_form_duplicate_note'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: OmniTheme.colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FoodFormImageTile(
                  key: const Key('food_form_image_tile'),
                  imagePath: _imagePath,
                  imageStorage: widget.foodLibraryState.imageStorageOrNull,
                  // Thread the form's initial food's id and
                  // catalogId into the tile so the bundled-photo
                  // tier can resolve a shipped photograph the
                  // same way the library list's `FoodThumbnail`
                  // does. The tier is render-only — it never
                  // writes to `Food.imagePath`; the user's
                  // imagePath stays at whatever it was when the
                  // editor opened.
                  foodId: widget.initial?.id,
                  catalogId: widget.initial?.catalogId,
                  onPickGallery: () => _pickImage(ImageSource.gallery),
                  onPickCamera: () => _pickImage(ImageSource.camera),
                  onClear: clearImage,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  key: const Key('food_form_group'),
                  initialValue: _groupId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categoryDropdownItems(groups),
                  onChanged: (v) => setState(() => _groupId = v),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nutrition facts are per',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_ServingBasis>(
                    key: const Key('food_form_basis'),
                    segments: _basisSegments(),
                    selected: {_basis},
                    showSelectedIcon: false,
                    onSelectionChanged: _onBasisChanged,
                    style: _basisButtonStyle(),
                  ),
                ),
                if (_basis == _ServingBasis.per100g ||
                    _basis == _ServingBasis.per100ml) ...[
                  TextButton(
                    key: const Key('food_form_package_link'),
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                    onPressed: () =>
                        setState(() => _packageOpen = !_packageOpen),
                    child: Text(
                      _packageOpen
                          ? 'Back to per 100 $_packageLabel'
                          : 'Enter package serving instead (e.g. 30 g)',
                    ),
                  ),
                  if (_packageOpen)
                    TextFormField(
                      key: const Key('food_form_package_amount'),
                      controller: _packageAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*$'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Serving size ($_packageLabel)',
                        hintText: '30',
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validatePositiveDouble,
                      onChanged: (_) => setState(() {}),
                    ),
                ],
                if (_basis == _ServingBasis.serving) ...[
                  TextFormField(
                    key: const Key('food_form_serving_label'),
                    controller: _servingLabelController,
                    decoration: const InputDecoration(
                      labelText: 'Called a…',
                      hintText: 'slice',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return 'Name the serving, e.g. slice';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final word in _servingWords)
                        FilterChip(
                          key: Key('food_form_serving_chip_$word'),
                          label: Text(word),
                          selected:
                              _servingLabelController.text.trim() == word,
                          onSelected: (_) => _fillServingLabel(word),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  servingHeading(_currentChoice),
                  key: const Key('food_form_per_heading'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.colors.textSecondary,
                  ),
                ),
                if (_perNote case final note?) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    key: const Key('food_form_per_note'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: OmniTheme.colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _macroField(
                  key: const Key('food_form_fat'),
                  controller: _fat,
                  focusNode: _fatFocus,
                  label: 'Fat (g)',
                ),
                const SizedBox(height: 8),
                _macroField(
                  key: const Key('food_form_carbs'),
                  controller: _carbs,
                  focusNode: _carbsFocus,
                  label: 'Carbs (g)',
                ),
                const SizedBox(height: 8),
                _macroField(
                  key: const Key('food_form_fiber'),
                  controller: _fiber,
                  focusNode: _fiberFocus,
                  label: 'Fiber (g)',
                ),
                const SizedBox(height: 8),
                _macroField(
                  key: const Key('food_form_protein'),
                  controller: _protein,
                  focusNode: _proteinFocus,
                  label: 'Protein (g)',
                ),
                const SizedBox(height: 8),
                _macroField(
                  key: const Key('food_form_sodium'),
                  controller: _sodium,
                  focusNode: _sodiumFocus,
                  label: 'Sodium (mg)',
                ),
                const SizedBox(height: 8),
                // The derived calories, live as the boxes change. One
                // formula for the form and every stored food (D-92c.1);
                // fiber and sodium never enter it.
                Text(
                  '= $calories cal',
                  key: const Key('food_form_calories'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.colors.textSecondary,
                  ),
                ),
                if (widget.showNotesField) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('food_form_notes'),
                    controller: _notes,
                    focusNode: _notesFocus,
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
        );
      },
    );
  }

  /// A blank or half-typed macro box counts as 0 for the calories line
  /// (D-92c.1).
  static double _parsed(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0.0;

  /// Macro text field with decimal input. Every box is optional: a blank
  /// Protein, Carbs or Fat saves 0, a blank Fiber or Sodium saves "not
  /// recorded" (null). Non-numeric text (a lone `.`) still surfaces
  /// `"Must be a number"`.
  ///
  /// Accepts the same `^\d*\.?\d*$` pattern as the package-size field
  /// (one optional decimal point, digits on either side).
  /// This widens the prior `digitsOnly` contract that rejected
  /// `0.5` and `1.25`, so the user can store fractional grams
  /// like `0.5` g of fat. The validator uses `double.tryParse`
  /// to accept both `12` and `0.5`, surfacing `"Must be a number"`
  /// for any other input.
  Widget _macroField({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
      ],
      // Rebuild as the box changes so readers derived from the text follow
      // typing (D-92c.10).
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        // Material hides a hint while the label sits inside the box; `always`
        // keeps the faint 0 visible without focus (D-92c.3, D-92c.14).
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final trimmed = v?.trim() ?? '';
        if (trimmed.isEmpty) return null;
        if (double.tryParse(trimmed) == null) {
          return 'Must be a number';
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

  /// Build the items list for the category dropdown (S-001 / S-002).
  ///
  /// The list is `Uncategorized` + the active groups, in alphabetical
  /// order. When the food's stored `_groupId` is **not** in the
  /// active list (it points at a deleted category, or one that was
  /// never created because the user pre-created their own), we
  /// synthesise an extra item so the dropdown's `initialValue` is
  /// satisfied and the food's original filing is visible to the
  /// user. The synthesised item is rendered with a muted
  /// [OmniTheme.colors.textMuted] style and labelled
  /// " (no longer available)" — the user can keep it (save
  /// leaves `groupId` unchanged) or pick an active group.
  ///
  /// When the food's `_groupId` IS in the **full** group cache
  /// (the `foodGroups` getter, which includes archived groups) but
  /// the group has `isArchived = true`, we render the actual
  /// archived group row labelled " (archived)" — the name is
  /// recoverable from the cache so the user sees what they filed
  /// it under. Again, muted style.
  ///
  /// Items are listed in this order: synthesised (if any) →
  /// `Uncategorized` → active groups. The synthesised item is
  /// prepended so the user sees it at the top of the menu (or as
  /// the selected value when it matches `_groupId`).
  List<DropdownMenuItem<String?>> _categoryDropdownItems(
    List<FoodGroup> activeGroups,
  ) {
    final muted = OmniTheme.colors.textMuted;
    final items = <DropdownMenuItem<String?>>[];

    // Synthesise the orphan / archived item when needed.
    final orphan = _synthesiseOrphanCategoryItem(
      mutedStyle: muted,
      activeGroups: activeGroups,
    );
    if (orphan != null) items.add(orphan);

    items.add(
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Uncategorized'),
      ),
    );
    for (final g in activeGroups) {
      items.add(DropdownMenuItem<String?>(value: g.id, child: Text(g.name)));
    }
    return items;
  }

  /// When the food's stored `_groupId` is not in the active
  /// groups list, build a selectable item so the dropdown's
  /// `initialValue` is satisfied (S-001 / S-002). The item is
  /// either:
  ///   * the actual archived group row, with a "(archived)"
  ///     suffix and muted style (resolvable from
  ///     [FoodLibraryState.foodGroups], the full cache), or
  ///   * a synthesised "(no longer available)" item carrying the
  ///     stored id but no resolvable name.
  ///
  /// Returns `null` when `_groupId` is null (Uncategorized) or when
  /// it is in the active list (no synthesis needed).
  DropdownMenuItem<String?>? _synthesiseOrphanCategoryItem({
    required Color mutedStyle,
    required List<FoodGroup> activeGroups,
  }) {
    final groupId = _groupId;
    if (groupId == null) return null;

    // If the id IS in the active list, the regular items list
    // already covers it — synthesising an extra "orphan" item
    // would create a duplicate `value`, which `DropdownButton`'s
    // "exactly one item with the value" assertion rejects. This
    // can happen transiently right after the user picks an
    // active category from the dropdown: the build re-runs with
    // the new `_groupId` set to an active id, and we must NOT
    // synthesise a second row for it.
    for (final g in activeGroups) {
      if (g.id == groupId) return null;
    }

    // Look it up in the full group cache (active + archived). The
    // active list already filtered `isArchived == false`, so a
    // hit here means either the group is archived OR there is a
    // state-cache lag — we still synthesise the item rather than
    // rely on the lag resolving.
    final allGroups = widget.foodLibraryState.foodGroups;
    FoodGroup? group;
    for (final g in allGroups) {
      if (g.id == groupId) {
        group = g;
        break;
      }
    }

    if (group != null) {
      // Resolvable: archived group row.
      final suffix = group.isArchived ? ' (archived)' : '';
      return DropdownMenuItem<String?>(
        value: groupId,
        child: Text(
          '${group.name}$suffix',
          style: TextStyle(color: mutedStyle),
        ),
      );
    }

    // Not in any cache: truly orphaned (deleted, or a default
    // we never created). Render the raw id so the user can see
    // it's there, with a "(no longer available)" hint.
    return DropdownMenuItem<String?>(
      value: groupId,
      child: Text(
        '$groupId (no longer available)',
        style: TextStyle(color: mutedStyle),
      ),
    );
  }
}

/// The image tile rendered at the very top of [FoodForm]. Square
/// 96×96 by default. Resolves the displayed photo through the
/// same three-tier precedence the library list's
/// [FoodThumbnail] uses, so a user opening the editor for a
/// bundled food sees the same photo they saw on the list they
/// tapped from:
///
///   1. **User-picked photo** ([imagePath]) — always wins if set.
///   2. **Shipped photo** — derived by
///      [FoodPhotoService.bundledPhotoAssetPath] from [foodId] or,
///      for a library copy, from [catalogId].
///   3. **Placeholder** — shown when neither source has a photo.
///
/// The bundled tier is render-only: it never writes to
/// `Food.imagePath`. The shipped photo is the food's baseline,
/// not a one-time default — clearing a user photo over a shipped
/// one returns the display to the shipped photo rather than to
/// the empty placeholder.
///
/// **Overlay chrome**:
///   * The × (clear) overlay appears **only when a user photo is
///     the displayed source** — there is nothing for the user to
///     clear when only a shipped photo is shown. A user who never
///     picked a photo must not be offered a delete affordance
///     against a photo that isn't theirs.
///   * The edit (replace) overlay appears whenever any photo is
///     displayed (user photo or shipped), so the user can pick
///     their own photo over a shipped one.
///   * Tapping the placeholder opens the same Camera / Gallery
///     picker sheet as the edit overlay.
class FoodFormImageTile extends StatelessWidget {
  /// The food's stored photo reference (user-picked photo
  /// basename under the post-relocation-fix contract, or
  /// `null`/empty when no user photo is set). Tier 1.
  final String? imagePath;

  /// The food's id (or, for a library copy, the library copy's
  /// id — the bundled tier keys off `catalogId` first if set).
  final String? foodId;

  /// The catalog food id for a library food copied from the
  /// catalog. Used by the bundled tier to resolve the shipped
  /// photo path so a library copy of a bundled food renders the
  /// same shipped photo as the original.
  final String? catalogId;

  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onClear;
  final ImageStorageService? imageStorage;
  final double size;

  const FoodFormImageTile({
    super.key,
    required this.imagePath,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onClear,
    this.foodId,
    this.catalogId,
    this.imageStorage,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    // The clear affordance only makes sense when the user has
    // actually set a photo. When the displayed source is the
    // shipped photo (no user `imagePath`), the × (clear)
    // overlay is hidden — the user cannot delete a photo that
    // isn't theirs. The edit overlay is shown whenever any photo
    // is rendered, so the user can still pick their own over
    // the shipped one.
    final hasUserImage = imagePath != null && imagePath!.isNotEmpty;
    final hasFoodIdentity = foodId != null || catalogId != null;

    // The bundled tier is reachable when the food resolves to
    // a shipped asset. We delegate the entire image body to
    // `FoodThumbnail` so the form and the library list share
    // one implementation of the three-tier precedence — the
    // only thing the form owns beyond the rendering decision is
    // its overlay chrome and the tap-to-pick gesture. The
    // body itself is wrapped in an `InkWell` so tapping
    // anywhere on the image (user photo, shipped photo, or
    // placeholder) opens the picker sheet — this matches the
    // pre-fix behaviour where tapping the placeholder opened
    // the picker and matches what users expect from a photo
    // editor (one tap to change). The overlay buttons do not
    // bubble taps up to the InkWell (they have their own
    // `Material`/`InkWell` wrappers).
    final body = FoodThumbnail(
      imagePath: imagePath,
      imageStorage: imageStorage,
      foodId: foodId,
      catalogId: catalogId,
      size: size,
      radius: 12,
      // Opt into the empty-state caption so the form's tile
      // surfaces "Add photo" when no photo is rendering.
      // List-row consumers do not pass this — only the form
      // ever does.
      placeholderCaption: 'Add photo',
    );

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showPickerSheet(context),
                  borderRadius: BorderRadius.circular(12),
                  child: body,
                ),
              ),
            ),
            // The shipped-photo / placeholder distinction is
            // surfaced through the overlay chrome: when the
            // displayed source is the shipped photo (no user
            // `imagePath`), we still want the edit overlay (the
            // user can pick their own photo over the shipped
            // one) but we hide the × clear overlay (there is
            // nothing for the user to clear). When the user
            // picks a photo, `hasUserImage` flips to true and
            // the clear overlay appears.
            if (hasUserImage)
              Positioned(
                top: 0,
                right: 0,
                child: _OverlayButton(
                  icon: Icons.close,
                  onTap: onClear,
                  tooltip: 'Remove photo',
                ),
              ),
            // Edit overlay: shown whenever any photo is displayed
            // (user photo or shipped). When the tile is purely
            // a placeholder (no photo at all and no food
            // identity to resolve a bundled photo from), the
            // placeholder's own tap-to-pick InkWell handles
            // opening the picker; the overlay is not stacked
            // on top.
            if (hasUserImage || hasFoodIdentity)
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
