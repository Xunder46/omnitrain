// Plan 239 P2 — scenario S-23901: `OmniDateUtils.daysElapsedInMonth` counts
// only days that have started.
//
// S-23902 and S-23903 (the screen's "N workout days / M rest days" totals
// line) were deleted in plan 245: the summary no longer has a month grid or
// that line. The production function stays in
// `lib/core/utils/date_utils.dart` and is tested here on its own. Pure unit
// test, no harness.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/date_utils.dart';

void main() {
  test('S-23901 daysElapsedInMonth counts only days that have started', () {
    // A past month returns its full length, even though "today" is the 18th.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 10, 1),
        DateTime(2026, 11, 18),
      ),
      31,
    );
    // The same month returns today's day number (today counts).
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 18),
      ),
      18,
    );
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 1),
      ),
      1,
    );
    // A leap February, seen from the next month.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2028, 2, 1),
        DateTime(2028, 3, 5),
      ),
      29,
    );
    // A December seen from January of the next year.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 12, 1),
        DateTime(2027, 1, 5),
      ),
      31,
    );
    // A later month returns 0.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2027, 1, 1),
        DateTime(2026, 12, 31),
      ),
      0,
    );
    // The last day of the same month.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
      ),
      30,
    );
  });
}
