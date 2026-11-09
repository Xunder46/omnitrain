import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/routine/routine_state.dart';

import 'helpers/repository_harness.dart';

// Plan 123: choosing "Mixed / Not set" on a routine that has a Focus Modality
// must remove the Focus (S-12301..S-12308), on the Mock and on Hive.

const _resistance = 'resistance_lifting';
const _cardio = 'cardio_endurance';

Future<RoutineState> _editor(
  WorkoutRepository repo, [
  String? templateId,
]) async {
  final state = RoutineState(repo);
  state.setAutosaveEnabled(false);
  if (templateId != null) await state.loadRoutineForEditing(templateId);
  return state;
}

/// A routine saved with [focus]; returns its id.
Future<String> _saved(
  WorkoutRepository repo,
  String? focus, {
  bool withExercise = false,
}) async {
  final state = await _editor(repo);
  await state.createNewRoutine('Routine');
  if (focus != null) await state.updateRoutineFocusModality(focus);
  if (withExercise) {
    final exercises = await repo.getExercises();
    await state.addExerciseToRoutine(exercises.first, 'set');
  }
  await state.saveRoutine();
  return state.currentTemplate!.id;
}

Future<String?> _storedFocus(WorkoutRepository repo, String id) async =>
    (await repo.getTemplateById(id))!.focusModality;

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();
    group('Routine focus on ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => harness.close());

      test('S-12301: Focus -> Mixed, save, reopen shows Mixed', () async {
        final id = await _saved(repo, _resistance);
        final editing = await _editor(repo, id);
        expect(editing.currentTemplate!.focusModality, _resistance);
        await editing.updateRoutineFocusModality(null);
        expect(editing.currentTemplate!.focusModality, isNull);
        await editing.saveRoutine();

        final again = await _editor(await harness.restart(), id);
        expect(again.currentTemplate!.focusModality, isNull);
      });

      test('S-12302: Mixed -> Focus is saved', () async {
        final id = await _saved(repo, null);
        final editing = await _editor(repo, id);
        await editing.updateRoutineFocusModality(_cardio);
        await editing.saveRoutine();
        expect(await _storedFocus(await harness.restart(), id), _cardio);
      });

      test('S-12303: Focus -> other Focus is saved', () async {
        final id = await _saved(repo, _resistance);
        final editing = await _editor(repo, id);
        await editing.updateRoutineFocusModality(_cardio);
        await editing.saveRoutine();
        expect(await _storedFocus(await harness.restart(), id), _cardio);
      });

      test('S-12304: unchanged Focus stays; unchanged Mixed stays', () async {
        final withFocus = await _saved(repo, _resistance);
        final mixed = await _saved(repo, null);
        for (final id in [withFocus, mixed]) {
          final editing = await _editor(repo, id);
          await editing.updateRoutineDescription('touched');
          await editing.saveRoutine();
        }
        final r = await harness.restart();
        expect(await _storedFocus(r, withFocus), _resistance);
        expect(await _storedFocus(r, mixed), isNull);
      });

      test(
        'S-12305: Focus -> Mixed with exercises keeps the exercises',
        () async {
          final id = await _saved(repo, _resistance, withExercise: true);
          final editing = await _editor(repo, id);
          final before = editing.currentEfforts.map((e) => e.id).toList();
          expect(before, isNotEmpty);
          await editing.updateRoutineFocusModality(null);
          await editing.saveRoutine();

          final again = await _editor(await harness.restart(), id);
          expect(again.currentTemplate!.focusModality, isNull);
          expect(again.currentEfforts.map((e) => e.id), before);
        },
      );

      test(
        'S-12306: a seeded/imported routine with a Focus can be cleared',
        () async {
          final now = DateTime.now().millisecondsSinceEpoch;
          await repo.createTemplate(
            WorkoutTemplate(
              id: 'imported-1',
              name: 'Imported',
              focusModality: _resistance,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          await repo.createTemplateSegment(
            TemplateSegment(
              id: 'imported-1-seg',
              templateId: 'imported-1',
              orderIndex: 0,
              segmentType: 'mixed',
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          final editing = await _editor(repo, 'imported-1');
          await editing.updateRoutineFocusModality(null);
          await editing.saveRoutine();
          expect(
            await _storedFocus(await harness.restart(), 'imported-1'),
            isNull,
          );
        },
      );

      test(
        'S-12307: an unsaved Mixed pick, discarded, leaves the Focus',
        () async {
          final id = await _saved(repo, _resistance);
          final editing = await _editor(repo, id);
          await editing.updateRoutineFocusModality(null);
          editing.discardCurrentRoutine();

          final reopened = await harness.restart();
          expect(await _storedFocus(reopened, id), _resistance);
          final again = await _editor(reopened, id);
          expect(again.currentTemplate!.focusModality, _resistance);
        },
      );

      test('S-12308: Focus -> Mixed counts as an unsaved change', () async {
        final id = await _saved(repo, _resistance);
        final editing = await _editor(repo, id);
        expect(editing.hasUnsavedChanges, isFalse);
        await editing.updateRoutineFocusModality(null);
        expect(editing.hasUnsavedChanges, isTrue);
        await editing.updateRoutineFocusModality(_resistance);
        expect(editing.hasUnsavedChanges, isFalse);
      });
    });
  }
}
