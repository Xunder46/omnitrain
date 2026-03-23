import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/models/models.dart';

void main() {
  test(
    'ProfileState creates default profile and loads primary measurements',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      await repository.saveMeasurementEntry(
        BodyMeasurementEntry(
          id: 'weight-1',
          measurementType: 'bodyweight',
          value: 79.5,
          unitId: 'unit-kg',
          recordedAtMs: 1000,
        ),
      );
      await repository.saveMeasurementEntry(
        BodyMeasurementEntry(
          id: 'height-1',
          measurementType: 'height',
          value: 181,
          unitId: 'unit-cm',
          recordedAtMs: 2000,
        ),
      );

      final profileState = ProfileState(repository);
      await profileState.loadProfile();

      expect(profileState.profile, isNotNull);
      expect(profileState.profile!.id, 'local-user');
      expect(profileState.latestMeasurements['bodyweight']?.value, 79.5);
      expect(profileState.latestMeasurements['height']?.value, 181);
    },
  );

  test(
    'ProfileState updates latest measurement after log and delete',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final profileState = ProfileState(repository);
      await profileState.loadProfile();

      await profileState.logMeasurement(
        'bodyweight',
        82.2,
        'unit-kg',
        recordedAtMs: 1000,
      );
      await profileState.logMeasurement(
        'bodyweight',
        81.7,
        'unit-kg',
        recordedAtMs: 2000,
      );

      final history = await profileState.getMeasurementHistory('bodyweight');
      expect(history, hasLength(2));
      expect(profileState.latestMeasurements['bodyweight']?.value, 81.7);

      await profileState.deleteMeasurementEntry(history.first.id, 'bodyweight');

      expect(profileState.latestMeasurements['bodyweight']?.value, 82.2);
    },
  );

  test('ProfileState uses save time when recordedAtMs is omitted', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final profileState = ProfileState(repository);
    await profileState.loadProfile();

    final beforeLog = DateTime.now().millisecondsSinceEpoch;
    await profileState.logMeasurement('height', 182, 'unit-cm');
    final afterLog = DateTime.now().millisecondsSinceEpoch;

    final history = await profileState.getMeasurementHistory('height');

    expect(history, hasLength(1));
    expect(history.single.recordedAtMs, greaterThanOrEqualTo(beforeLog));
    expect(history.single.recordedAtMs, lessThanOrEqualTo(afterLog));
  });
}
