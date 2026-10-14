import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants/modality_config.dart';
import '../../core/utils/exercise_helpers.dart';
import '../../core/utils/muscle_selection.dart';
import '../../data/models/models.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/exercise/muscle_picker.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';
import '../../widgets/feedback/omni_message.dart';

class ExerciseEditorScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final Exercise? initialExercise;
  final String? contextModality;

  const ExerciseEditorScreen({
    super.key,
    required this.workoutState,
    this.initialExercise,
    this.contextModality,
  });

  @override
  State<ExerciseEditorScreen> createState() => _ExerciseEditorScreenState();
}

class _ExerciseEditorScreenState extends State<ExerciseEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  bool _isLoading = true;
  bool _isSaving = false;

  List<Discipline> _disciplines = [];
  List<MuscleGroup> _muscleGroups = [];

  String? _selectedModality;
  String? _selectedDisciplineId;
  final Set<String> _selectedCapabilities = {};
  MuscleSelection _muscleSelection = MuscleSelection();
  final Set<String> _legacyCapabilityIds = {};

  String? _modalityError;
  String? _nameError;
  String? _capabilityError;
  String? _muscleError;

  final GlobalKey _modalityKey = GlobalKey();
  final GlobalKey _nameKey = GlobalKey();
  final GlobalKey _capabilitiesKey = GlobalKey();
  final GlobalKey _musclesKey = GlobalKey();

  String _initialName = '';
  String _initialDescription = '';
  String? _initialModality;
  String? _initialDisciplineId;
  Set<String> _initialCapabilities = const {};
  MuscleSelection _initialMuscleSelection = MuscleSelection();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialExercise?.name ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.initialExercise?.description ?? '',
    );

    _selectedModality =
        widget.initialExercise?.modality ?? widget.contextModality;
    _selectedDisciplineId = widget.initialExercise?.disciplineId;
    _selectedCapabilities.addAll(
      widget.initialExercise?.capabilities ?? const [],
    );

    if (widget.initialExercise != null) {
      _legacyCapabilityIds.addAll(
        ModalityConfig.legacyCapabilitiesForEdit(
          widget.initialExercise!.modality,
          widget.initialExercise!.capabilities,
        ),
      );
    }

    _loadReferenceData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    if (widget.workoutState.disciplines.isEmpty) {
      await widget.workoutState.loadDisciplines();
    }
    if (widget.workoutState.muscleGroups.isEmpty) {
      await widget.workoutState.loadMuscleGroups();
    }

    _disciplines = widget.workoutState.disciplines;
    _muscleGroups = widget.workoutState.muscleGroups;

    _selectedDisciplineId = _resolvedDisciplineId(
      modality: _selectedModality,
      selectedDisciplineId: _selectedDisciplineId,
    );

    if (widget.initialExercise != null) {
      final links = await widget.workoutState.getExerciseMuscleLinks(
        widget.initialExercise!.id,
      );
      if (links == null) {
        // A failed read must not open the form on an empty picker: a save
        // would then wipe the stored links.
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          OmniMessage.error(
            context,
            'Could not load this exercise. Try again.',
          );
          Navigator.of(context).pop();
        });
        return;
      }
      _muscleSelection = MuscleSelection.fromLinks(links);
    }

    _captureInitialState();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// The state the form opened with, for the unsaved guard (D-8).
  void _captureInitialState() {
    _initialName = _nameController.text;
    _initialDescription = _descriptionController.text;
    _initialModality = _selectedModality;
    _initialDisciplineId = _selectedDisciplineId;
    _initialCapabilities = {..._selectedCapabilities};
    _initialMuscleSelection = _muscleSelection;
  }

  /// True when any field differs from the state the form opened with.
  bool get _isDirty =>
      !_isLoading &&
      (_nameController.text != _initialName ||
          _descriptionController.text != _initialDescription ||
          _selectedModality != _initialModality ||
          _selectedDisciplineId != _initialDisciplineId ||
          !setEquals(_selectedCapabilities, _initialCapabilities) ||
          _muscleSelection != _initialMuscleSelection);

  bool get _isEditMode => widget.initialExercise != null;

  bool get _isModalityReadOnly {
    if (!_isEditMode) return false;
    return widget.initialExercise!.modality != null;
  }

  bool get _showMuscleGroups {
    return ModalityConfig.forModality(
          _selectedModality,
        )?.showMuscleGroupsInForm ==
        true;
  }

  List<String> get _allowedCapabilities {
    return ModalityConfig.forModality(_selectedModality)?.formCapabilities ??
        const [];
  }

  void _onModalityChanged(String modality) {
    if (_isModalityReadOnly) return;

    final allowedCaps =
        ModalityConfig.forModality(modality)?.formCapabilities ?? const [];
    final allowedSet = allowedCaps.toSet();

    setState(() {
      _selectedModality = modality;
      _selectedCapabilities.removeWhere((cap) => !allowedSet.contains(cap));
      _selectedDisciplineId = null;
      if (ModalityConfig.forModality(modality)?.showMuscleGroupsInForm !=
          true) {
        _muscleSelection = MuscleSelection();
      }
      _modalityError = null;
      _capabilityError = null;
      _muscleError = null;
    });
  }

  String? _resolvedDisciplineId({
    required String? modality,
    required String? selectedDisciplineId,
  }) {
    if (selectedDisciplineId == null) return null;
    final scoped = ModalityConfig.disciplinesForModality(
      modality,
      _disciplines,
    );
    final exists = scoped.any((d) => d.id == selectedDisciplineId);
    return exists ? selectedDisciplineId : null;
  }

  Future<void> _validateAndSave() async {
    if (_isSaving) return;

    final trimmedName = _nameController.text.trim();
    final requiredCaps =
        ModalityConfig.forModality(
          _selectedModality,
        )?.formRequiredCapabilities ??
        const [];
    final hasRequiredCapability = requiredCaps.any(
      _selectedCapabilities.contains,
    );

    String? modalityError;
    String? nameError;
    String? capabilityError;
    String? muscleError;

    if (_selectedModality == null) {
      modalityError = 'Select a modality.';
    }
    if (trimmedName.isEmpty) {
      nameError = 'Exercise name required.';
    }
    if (_selectedModality != null && !hasRequiredCapability) {
      capabilityError = ModalityConfig.formRequiredCapabilitiesLabel(
        _selectedModality,
      );
    }
    if (_showMuscleGroups && _muscleSelection.hasOnlyAssists) {
      muscleError = 'Pick at least one main muscle.';
    }

    if (modalityError != null ||
        nameError != null ||
        capabilityError != null ||
        muscleError != null) {
      setState(() {
        _modalityError = modalityError;
        _nameError = nameError;
        _capabilityError = capabilityError;
        _muscleError = muscleError;
      });
      _scrollToFirstError(
        modalityError: modalityError,
        nameError: nameError,
        capabilityError: capabilityError,
        muscleError: muscleError,
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final description = _descriptionController.text.trim();

    Exercise? saved;
    if (_isEditMode) {
      final current = widget.initialExercise!;
      saved = await widget.workoutState.updateCustomExercise(
        exercise: current.copyWith(
          name: trimmedName,
          description: description.isEmpty ? null : description,
          disciplineId: _selectedDisciplineId,
          modality: _selectedModality,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        capabilities: _selectedCapabilities.toList()..sort(),
        muscleLinks: _muscleSelection.toLinks(),
      );
    } else {
      saved = await widget.workoutState.createCustomExercise(
        name: trimmedName,
        modality: _selectedModality,
        description: description.isEmpty ? null : description,
        disciplineId: _selectedDisciplineId,
        capabilities: _selectedCapabilities.toList()..sort(),
        muscleLinks: _muscleSelection.toLinks(),
      );
    }

    if (!mounted) return;

    if (saved == null) {
      // D-27.2: the state's error text carries the exception
      // (`Failed to create exercise: …`); log it and show plain copy.
      debugPrint('Save exercise: ${widget.workoutState.error}');
      OmniMessage.error(context, 'Could not save the exercise. Try again.');
      setState(() {
        _isSaving = false;
      });
      return;
    }

    Navigator.of(context).pop(saved);
  }

  /// Brings the first field in error into view, in the order the form reads
  /// its sections: modality, name, capabilities, muscles (D-7).
  void _scrollToFirstError({
    required String? modalityError,
    required String? nameError,
    required String? capabilityError,
    required String? muscleError,
  }) {
    GlobalKey? targetKey;
    if (modalityError != null) {
      targetKey = _modalityKey;
    } else if (nameError != null) {
      targetKey = _nameKey;
    } else if (capabilityError != null) {
      targetKey = _capabilitiesKey;
    } else if (muscleError != null) {
      targetKey = _musclesKey;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = targetKey?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      );
    });
  }

  /// Single exit path for header back, system back and the dialog's own
  /// Discard: an untouched form pops straight away, a form with edits asks
  /// first. Save runs the normal save path, which pops only when the exercise
  /// was written.
  ///
  /// A save already in flight owns the exit: the dialog's Discard would pop
  /// while the write still completes, so both the header back and the system
  /// back leave the form alone until the save resolves.
  Future<void> _attemptExit() async {
    if (_isSaving) return;

    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }

    final action = await ConfirmationDialog.showUnsavedChanges(
      context: context,
      title: 'Unsaved changes',
      body: 'You have unsaved edits. Save them or discard to return.',
      keepEditingKey: const Key('exercise_editor_unsaved_keep'),
      discardKey: const Key('exercise_editor_unsaved_discard'),
      saveKey: const Key('exercise_editor_unsaved_save'),
    );
    if (!mounted) return;

    switch (action) {
      case UnsavedChangesAction.discard:
        Navigator.of(context).pop();
      case UnsavedChangesAction.save:
        await _validateAndSave();
      case UnsavedChangesAction.keepEditing:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredDisciplines = ModalityConfig.disciplinesForModality(
      _selectedModality,
      _disciplines,
    );
    final visibleLegacyCaps = _legacyCapabilityIds.toList()..sort();

    final appBar = OmniBackHeader(
      title: _isEditMode ? 'Edit Exercise' : 'New Exercise',
      onBack: () => _attemptExit(),
    );

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: appBar,
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final editor = Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                key: _modalityKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const OmniCardHeader(title: 'MODALITY'),
                  // Two tiles per row, each half the padded row less the 8 dp
                  // gap (D-6). A `_ModalityTile` is a plain `Material` +
                  // `InkWell`, so `Expanded` really hands it half the row
                  // (a Material `ChoiceChip` wraps itself in a centring
                  // tap-target layout that loosens that width), and it sets no
                  // `maxLines`, so a long label wraps instead of being clipped
                  // (a chip's label area clips at its own height).
                  for (var i = 0; i < _modalityRows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    // `IntrinsicHeight` + `stretch` keep the two tiles of a
                    // row level when one label wraps and the other does not.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final modality in _modalityRows[i]) ...[
                            if (modality != _modalityRows[i].first)
                              const SizedBox(width: 8),
                            Expanded(
                              child: _ModalityTile(
                                key: Key('modality_tile_$modality'),
                                label: ModalityConfig.modalityDisplayName(
                                  modality,
                                ),
                                selected: _selectedModality == modality,
                                onTap: _isModalityReadOnly
                                    ? null
                                    : () => _onModalityChanged(modality),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (_modalityError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _modalityError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: _nameKey,
                textCapitalization: TextCapitalization.words,
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Exercise name',
                  border: const OutlineInputBorder(),
                  errorText: _nameError,
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {
                  _nameError = null;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _selectedDisciplineId,
                // Long discipline names are laid out for every item, selected
                // or not; without a bounded width the row overflows on narrow
                // phones (320 dp) and at larger text scales.
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Discipline',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None'),
                  ),
                  ...filteredDisciplines.map(
                    (discipline) => DropdownMenuItem<String?>(
                      value: discipline.id,
                      child: Text(
                        discipline.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: _selectedModality == null
                    ? null
                    : (value) {
                        setState(() {
                          _selectedDisciplineId = value;
                        });
                      },
              ),
              const SizedBox(height: 20),
              Column(
                key: _capabilitiesKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const OmniCardHeader(title: 'CAPABILITIES'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allowedCapabilities.map((capabilityId) {
                      final isSelected = _selectedCapabilities.contains(
                        capabilityId,
                      );
                      return FilterChip(
                        label: Text(_capabilityLabel(capabilityId)),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedCapabilities.add(capabilityId);
                            } else {
                              _selectedCapabilities.remove(capabilityId);
                            }
                            _capabilityError = null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              if (visibleLegacyCaps.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: visibleLegacyCaps.map((capabilityId) {
                    final isSelected = _selectedCapabilities.contains(
                      capabilityId,
                    );
                    return FilterChip(
                      label: Text('${_capabilityLabel(capabilityId)} (Legacy)'),
                      selected: isSelected,
                      disabledColor: theme.colorScheme.surfaceContainerHighest,
                      onSelected: isSelected
                          ? (_) {
                              setState(() {
                                _selectedCapabilities.remove(capabilityId);
                                _capabilityError = null;
                              });
                            }
                          : null,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Legacy capability',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (_capabilityError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _capabilityError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (_showMuscleGroups) ...[
                const SizedBox(height: 20),
                Column(
                  key: _musclesKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const OmniCardHeader(title: 'MUSCLES'),
                    MusclePicker(
                      groups: _muscleGroups,
                      selection: _muscleSelection,
                      onTap: (id) => setState(() {
                        _muscleSelection = _muscleSelection.cycle(id);
                        _muscleError = null;
                      }),
                    ),
                    if (_muscleError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _muscleError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: OmniBottomCTA(
        label: 'Save exercise',
        onPressed: _isSaving ? null : _validateAndSave,
      ),
    );

    return PopScope(
      canPop: !_isDirty && !_isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _attemptExit();
      },
      child: editor,
    );
  }
}

const List<String> _modalityOptions = [
  'cardio_endurance',
  'resistance_lifting',
  'sports',
  'isometric_stretching',
];

/// The modality grid: two `_modalityOptions` per row, in that order (D-6).
final List<List<String>> _modalityRows = [
  for (var i = 0; i < _modalityOptions.length; i += 2)
    _modalityOptions.sublist(i, i + 2),
];

/// One modality choice, filling whatever cell its `Expanded` gives it.
///
/// A plain `Material` + `InkWell` rather than a `ChoiceChip`: a chip is an
/// intrinsically-sized widget inside a centring tap-target layout, so a tight
/// half-row width comes out loose (a short label's cell is left half empty)
/// and its `maxLines` clips a long label. This tile has a `minHeight`, never a
/// fixed height, and lets its label wrap.
class _ModalityTile extends StatelessWidget {
  const _ModalityTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// Null in edit mode for a stored modality: the tile reads as disabled.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surface,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[
                      Icon(
                        Icons.check,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: onTap == null
                            ? TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _capabilityLabel(String capabilityId) {
  switch (capabilityId) {
    case 'time':
      return 'Time';
    case 'distance':
      return 'Distance';
    case 'rounds':
      return 'Rounds';
    case 'reps':
      return 'Reps';
    case 'sets':
      return 'Sets';
    case 'load':
      return 'Load';
    case 'hold':
      return 'Hold';
    default:
      return capabilityId;
  }
}
