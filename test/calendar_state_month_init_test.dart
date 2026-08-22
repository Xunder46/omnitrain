import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';

/// Regression: `CalendarState.year` / `.month` used to be `late` fields that
/// were only assigned inside the async `init()`. Screens build before that
/// future completes (CalendarScreen kicks `init()` off in a post-frame
/// callback), so the first build threw
/// `LateInitializationError: Field '_year' has not been initialized`.
void main() {
  test('year and month are readable before init() runs', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();

    final state = CalendarState(repo);

    final now = DateTime.now();
    expect(state.year, now.year);
    expect(state.month, now.month);
  });

  test('init() keeps the displayed month on the current month', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();

    final state = CalendarState(repo);
    await state.init();

    final now = DateTime.now();
    expect(state.year, now.year);
    expect(state.month, now.month);
  });

  test('month navigation still works from the constructor-set month', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();

    final state = CalendarState(repo);
    final startYear = state.year;
    final startMonth = state.month;

    await state.goToPreviousMonth();

    if (startMonth == 1) {
      expect(state.year, startYear - 1);
      expect(state.month, 12);
    } else {
      expect(state.year, startYear);
      expect(state.month, startMonth - 1);
    }

    await state.goToNextMonth();
    expect(state.year, startYear);
    expect(state.month, startMonth);
  });
}
