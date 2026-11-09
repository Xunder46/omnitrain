import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/start/watch_routine_catalog.dart';

void main() {
  final segments = [
    {
      'segmentId': 'seg-1',
      'name': 'Segment',
      'efforts': [
        {
          'effortId': 'ef-1',
          'exerciseId': 'ex-1',
          'exerciseName': 'Exercise',
          'effortKind': 'timed',
          'capabilities': ['time'],
          'targets': {'durationMs': 600000},
        },
      ],
    },
  ];

  Map<String, Object?> json(String? focusModality) => {
    'routineId': 'routine-1',
    'name': 'Routine',
    'updatedAt': '2026-11-05T17:00:00Z',
    'segments': segments,
    'focusModality': ?focusModality,
  };

  test(
    'S-12510 a routine that carries a focus modality parses and keeps it',
    () {
      final routine = WatchRoutine.fromJson(json('isometric_stretching'));
      expect(routine.focusModality, 'isometric_stretching');
    },
  );

  test('S-12510 a routine that carries none parses to null', () {
    final routine = WatchRoutine.fromJson(json(null));
    expect(routine.focusModality, isNull);
  });

  test(
    'S-12510 toJson omits the key when the routine has no focus modality',
    () {
      final routine = WatchRoutine.fromJson(json(null));
      expect(routine.toJson().containsKey('focusModality'), isFalse);
    },
  );

  test('S-12510 toJson round-trips a set focus modality', () {
    final routine = WatchRoutine.fromJson(json('isometric_stretching'));
    final back = WatchRoutine.fromJson(routine.toJson());
    expect(back.focusModality, 'isometric_stretching');
  });

  test('S-12510 an empty focus modality parses to null, keeping none', () {
    final routine = WatchRoutine.fromJson(json(''));
    expect(routine.focusModality, isNull);
  });
}
