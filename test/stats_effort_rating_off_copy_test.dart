// Plan 214, S-21401: the off copy of the signal lines, pure (no repository).
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';

void main() {
  test('S-21401 the off lines', () {
    expect(
      signalsLockedLine(2, ratingOff: true),
      'Effort Rating is off in Settings, so signals that need it stay '
      'locked — 2 of 4 weeks rated so far.',
    );
    expect(
      signalsMoreLine(2, ratingOff: true),
      'Effort Rating is off in Settings, so more signals stay locked — '
      '2 of 4 weeks rated so far.',
    );
  });

  test('S-21401 the count is clamped', () {
    expect(
      signalsLockedLine(9, ratingOff: true),
      contains('4 of 4 weeks rated so far.'),
    );
    expect(signalsLockedLine(-3, ratingOff: true), contains('0 of 4 weeks'));
    expect(
      signalsMoreLine(9, ratingOff: true),
      contains('4 of 4 weeks rated so far.'),
    );
    expect(signalsMoreLine(-3, ratingOff: true), contains('0 of 4 weeks'));
  });

  test('S-21401 the default lines are unchanged', () {
    expect(
      signalsLockedLine(2),
      'Unlocks after 4 weeks of rating your workouts — 2 of 4 so far.',
    );
    expect(
      signalsMoreLine(2),
      'More signals unlock after 4 weeks of rating your workouts — '
      '2 of 4 so far.',
    );
    expect(signalsLockedLine(2, ratingOff: false), signalsLockedLine(2));
    expect(signalsMoreLine(2, ratingOff: false), signalsMoreLine(2));
  });
}
