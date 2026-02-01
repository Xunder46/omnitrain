import 'package:flutter/material.dart';
import 'models.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout Tracker',
      theme: ThemeData.dark(),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final _uuid = const Uuid();
  List<Exercise> exercises = [];
  Map<String, List<SetRow>> sets = {};

  @override
  void initState() {
    super.initState();
    // For MVP, we start empty
  }

  void addExercise(String name) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ex = Exercise(
      id: _uuid.v4(),
      ownerUserId: null,
      disciplineId: null,
      name: name,
      createdAtMs: now,
      updatedAtMs: now,
    );
    final initialSet = SetRow(
      id: _uuid.v4(),
      exerciseId: ex.id,
      reps: 10,
      weight: 0.0,
      duration: 0,
      timestamp: now,
    );
    setState(() {
      exercises.add(ex);
      sets[ex.id] = [initialSet];
    });
  }

  void addSet(String exerciseId) {
    final set = SetRow(
      id: _uuid.v4(),
      exerciseId: exerciseId,
      reps: 10,
      weight: 0.0,
      duration: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      sets[exerciseId] ??= [];
      sets[exerciseId]!.add(set);
    });
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Tracker')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ...exercises.map((ex) => Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ex.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...sets[ex.id]!.map((s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: s.reps.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Reps'),
                                onChanged: (v) {
                                  final val = int.tryParse(v) ?? s.reps;
                                  setState(() => s.reps = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: s.weight.toString(),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Weight'),
                                onChanged: (v) {
                                  final val = double.tryParse(v) ?? s.weight;
                                  setState(() => s.weight = val);
                                },
                              ),
                            ),
                          ],
                        ),
                      )),
                  TextButton(
                    onPressed: () => addSet(ex.id),
                    child: const Text('Add Set'),
                  ),
                ],
              ),
            ),
          )),
          TextButton(
            onPressed: () async {
              final nameController = TextEditingController();
              final result = await showDialog<String?>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('New Exercise'),
                  content: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Exercise name',
                      hintText: 'e.g. Squats',
                    ),
                    autofocus: true,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(nameController.text.trim()),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              );
              if (result != null && result.isNotEmpty) {
                addExercise(result);
              }
            },
            child: const Text('Add Exercise'),
          ),
        ],
      ),
    );
  }
}
