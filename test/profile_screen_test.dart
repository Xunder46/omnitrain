import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/state/profile/profile_state.dart';

void main() {
  testWidgets('all measurement log sheets hide note input and date input', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final profileState = ProfileState(repository);

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(profileState: profileState)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('Log Body Weight'), findsOneWidget);
    expect(find.text('DATE'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);

    Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Log Height'), findsOneWidget);
    expect(find.text('DATE'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);

    Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
    await tester.pumpAndSettle();

    expect(find.text('More measurements'), findsNothing);
    expect(find.text('ADDITIONAL'), findsNothing);

    await tester.tap(find.byIcon(Icons.add).at(2));
    await tester.pumpAndSettle();

    expect(find.textContaining('Log '), findsOneWidget);
    expect(find.text('DATE'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);
  });

  testWidgets('measurement history loads without note UI', (tester) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'history-entry',
        measurementType: 'bodyweight',
        value: 80,
        unitId: 'unit-kg',
        recordedAtMs: 123456,
      ),
    );

    final profileState = ProfileState(repository);

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(profileState: profileState)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Body Weight'));
    await tester.pumpAndSettle();

    expect(find.textContaining('History'), findsOneWidget);
    expect(find.text('Note (optional)'), findsNothing);
  });
}
