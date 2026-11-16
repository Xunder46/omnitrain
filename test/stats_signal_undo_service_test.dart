// Plan 213, scenario S-21390 (pure): `signalDismissalsWithout` removes exactly
// the one id from the dismissal store, leaves an absent id alone, and never
// mutates its input — the undo counterpart of `signalDismissalsWith`.
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/core/models/signals.dart';

void main() {
  test('S-21390 signalDismissalsWithout removes the one id', () {
    expect(signalDismissalsWithout({'a': 1, 'b': 2}, 'a'), {'b': 2});
  });

  test('S-21390 an id that is not there changes nothing', () {
    expect(signalDismissalsWithout({'a': 1}, 'zz'), {'a': 1});
  });

  test('S-21390 the input map is not mutated and the result is a new map', () {
    final input = {'a': 1, 'b': 2};
    final result = signalDismissalsWithout(input, 'a');
    expect(input, {'a': 1, 'b': 2});
    expect(identical(result, input), isFalse);
  });
}
