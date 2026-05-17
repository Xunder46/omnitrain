import 'package:flutter/material.dart';
import '../../core/constants/modality_config.dart';
import '../../core/utils/exercise_helpers.dart';
import '../../data/models/models.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_bottom_cta.dart';

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
  final Set<String> _selectedMuscleGroupIds = {};
  final Set<String> _legacyCapabilityIds = {};

  String? _modalityError;
  String? _nameError;
  String? _capabilityError;

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
      final muscles = await widget.workoutState.getExerciseMuscleGroups(
        widget.initialExercise!.id,
      );
      _selectedMuscleGroupIds.addAll(muscles.map((m) => m.id));
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

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
        _selectedMuscleGroupIds.clear();
      }
      _modalityError = null;
      _capabilityError = null;
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

    if (modalityError != null || nameError != null || capabilityError != null) {
      setState(() {
        _modalityError = modalityError;
        _nameError = nameError;
        _capabilityError = capabilityError;
      });
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
        muscleGroupIds: _selectedMuscleGroupIds.toList()..sort(),
      );
    } else {
      saved = await widget.workoutState.createCustomExercise(
        name: trimmedName,
        modality: _selectedModality,
        description: description.isEmpty ? null : description,
        disciplineId: _selectedDisciplineId,
        capabilities: _selectedCapabilities.toList()..sort(),
        muscleGroupIds: _selectedMuscleGroupIds.toList()..sort(),
      );
    }

    if (!mounted) return;

    if (saved == null) {
      final error = widget.workoutState.error ?? 'Failed to save exercise.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      setState(() {
        _isSaving = false;
      });
      return;
    }

    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredDisciplines = ModalityConfig.disciplinesForModality(
      _selectedModality,
      _disciplines,
    );
    final visibleLegacyCaps = _legacyCapabilityIds.toList()..sort();

    final appBar = AppBar(
      title: Text(_isEditMode ? 'Edit Exercise' : 'New Exercise'),
      backgroundColor: Colors.transparent,
      foregroundColor: theme.colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
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

    return Scaffold(
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
              Text('Modality', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _modalityOptions.map((modality) {
                  final selected = _selectedModality == modality;
                  return ChoiceChip(
                    label: Text(ModalityConfig.modalityDisplayName(modality)),
                    selected: selected,
                    onSelected: _isModalityReadOnly
                        ? null
                        : (_) => _onModalityChanged(modality),
                  );
                }).toList(),
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
                textCapitalization: TextCapitalization.words,
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Exercise name',
                  border: const OutlineInputBorder(),
                  errorText: _nameError,
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() {
                      _nameError = null;
                    });
                  }
                },
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
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _selectedDisciplineId,
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
                      child: Text(discipline.name),
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
              Text('Capabilities', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
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
                Text('Muscle groups', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _muscleGroups.map((muscle) {
                    final isSelected = _selectedMuscleGroupIds.contains(
                      muscle.id,
                    );
                    return FilterChip(
                      label: Text(muscle.name),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedMuscleGroupIds.add(muscle.id);
                          } else {
                            _selectedMuscleGroupIds.remove(muscle.id);
                          }
                        });
                      },
                    );
                  }).toList(),
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
  }
}

const List<String> _modalityOptions = [
  'cardio_endurance',
  'resistance_lifting',
  'sports',
  'isometric_stretching',
];

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
