import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/wrist_rest_ping_rule.dart';

void main() {
  // S-15601: true only for (connected, active, 's-1', 's-1'); false for
  // each single deviation from that shape.
  group('wristOwnsRestPings', () {
    test('true only when the link is connected and the mirror holds the phone session', () {
      expect(
        wristOwnsRestPings(
          linkConnected: true,
          mirrorActive: true,
          mirrorSessionId: 's-1',
          phoneSessionId: 's-1',
        ),
        isTrue,
      );
    });

    test('false when the link is not connected', () {
      expect(
        wristOwnsRestPings(
          linkConnected: false,
          mirrorActive: true,
          mirrorSessionId: 's-1',
          phoneSessionId: 's-1',
        ),
        isFalse,
      );
    });

    test('false when the mirror is not active', () {
      expect(
        wristOwnsRestPings(
          linkConnected: true,
          mirrorActive: false,
          mirrorSessionId: 's-1',
          phoneSessionId: 's-1',
        ),
        isFalse,
      );
    });

    test('false when the mirror names no session', () {
      expect(
        wristOwnsRestPings(
          linkConnected: true,
          mirrorActive: true,
          mirrorSessionId: null,
          phoneSessionId: 's-1',
        ),
        isFalse,
      );
    });

    test('false when the mirror holds a different session than the phone', () {
      expect(
        wristOwnsRestPings(
          linkConnected: true,
          mirrorActive: true,
          mirrorSessionId: 's-2',
          phoneSessionId: 's-1',
        ),
        isFalse,
      );
    });

    test('false when the phone has no current session', () {
      expect(
        wristOwnsRestPings(
          linkConnected: true,
          mirrorActive: true,
          mirrorSessionId: 's-1',
          phoneSessionId: null,
        ),
        isFalse,
      );
    });
  });
}
