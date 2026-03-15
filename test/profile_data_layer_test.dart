import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

void main() {
  test('MockWorkoutRepository stores and sorts profile measurements', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final profile = UserProfile(
      id: 'local-user',
      displayName: 'Alex',
      avatarPath: null,
      createdAtMs: 1000,
    );

    await repository.saveProfile(profile);

    expect(await repository.getProfile(), isNotNull);
    expect((await repository.getProfile())!.displayName, 'Alex');

    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'entry-1',
        measurementType: 'bodyweight',
        value: 80.0,
        unitId: 'unit-kg',
        recordedAtMs: 1000,
      ),
    );

    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'entry-2',
        measurementType: 'bodyweight',
        value: 81.5,
        unitId: 'unit-kg',
        recordedAtMs: 3000,
      ),
    );

    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'entry-3',
        measurementType: 'height',
        value: 182.0,
        unitId: 'unit-cm',
        recordedAtMs: 2000,
      ),
    );

    final bodyweightHistory = await repository.getMeasurementHistory(
      'bodyweight',
    );

    expect(bodyweightHistory, hasLength(2));
    expect(bodyweightHistory.first.id, 'entry-2');
    expect(bodyweightHistory.last.id, 'entry-1');

    final latestBodyweight = await repository.getLatestMeasurement(
      'bodyweight',
    );
    expect(latestBodyweight, isNotNull);
    expect(latestBodyweight!.value, 81.5);

    await repository.deleteMeasurementEntry('entry-2');

    final refreshedLatest = await repository.getLatestMeasurement('bodyweight');
    expect(refreshedLatest, isNotNull);
    expect(refreshedLatest!.id, 'entry-1');
  });
}
