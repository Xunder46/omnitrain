import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../state/workout/workout_state.dart';

class ExerciseEditorScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final Exercise? initialExercise;

  const ExerciseEditorScreen({
    super.key,
    required this.workoutState,
    this.initialExercise,
  });

  @override
  State<ExerciseEditorScreen> createState() => _ExerciseEditorScreenState();
}

class _ExerciseEditorScreenState extends State<ExerciseEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  bool _isLoading = true;
  bool _isSaving = false;

  List<Discipline> _disciplines = [];
  List<MuscleGroup> _muscleGroups = [];

  String? _selectedDisciplineId;
  final Set<String> _selectedCapabilities = {};
  final Set<String> _selectedMuscleGroupIds = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialExercise?.name ?? '');
    _descriptionController = TextEditingController(text: widget.initialExercise?.description ?? '');
    _selectedDisciplineId = widget.initialExercise?.disciplineId;
    _selectedCapabilities.addAll(widget.initialExercise?.capabilities ?? const []);
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

    if (widget.initialExercise != null) {
      final muscles = await widget.workoutState
          .getExerciseMuscleGroups(widget.initialExercise!.id);
      _selectedMuscleGroupIds.addAll(muscles.map((m) => m.id));
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    final created = await widget.workoutState.createCustomExercise(
      name: name,
      description: description.isEmpty ? null : description,
      disciplineId: _selectedDisciplineId,
      capabilities: _selectedCapabilities.toList()..sort(),
      muscleGroupIds: _selectedMuscleGroupIds.toList()..sort(),
    );

    if (!mounted) return;

    if (created == null) {
      final error = widget.workoutState.error ?? 'Failed to create exercise.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      setState(() {
        _isSaving = false;
      });
      return;
    }

    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('New Exercise'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Exercise'),
        actions: [],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Exercise name',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  value: _selectedDisciplineId,
                  decoration: const InputDecoration(
                    labelText: 'Discipline',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None'),
                    ),
                    ..._disciplines.map(
                      (discipline) => DropdownMenuItem<String?>(
                        value: discipline.id,
                        child: Text(discipline.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedDisciplineId = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Capabilities',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _capabilityOptions.map((option) {
                    final isSelected = _selectedCapabilities.contains(option.id);
                    return FilterChip(
                      label: Text(option.label),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCapabilities.add(option.id);
                          } else {
                            _selectedCapabilities.remove(option.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text(
                  'Muscle groups',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _muscleGroups.map((muscle) {
                    final isSelected = _selectedMuscleGroupIds.contains(muscle.id);
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
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              style: ButtonStyle(
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                backgroundColor: MaterialStateProperty.all(theme.colorScheme.primary.withOpacity(0.8)),
              ),
              child: const Text('Save exercise'),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilityOption {
  final String id;
  final String label;

  const _CapabilityOption(this.id, this.label);
}

const List<_CapabilityOption> _capabilityOptions = [
  _CapabilityOption('time', 'Time'),
  _CapabilityOption('distance', 'Distance'),
  _CapabilityOption('rounds', 'Rounds'),
  _CapabilityOption('reps', 'Reps'),
  _CapabilityOption('sets', 'Sets'),
  _CapabilityOption('load', 'Load'),
  _CapabilityOption('hold', 'Hold'),
];
