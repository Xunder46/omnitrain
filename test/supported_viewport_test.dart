import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/supported_viewport.dart';
import 'helpers/supported_viewport.dart';

void main() {
  testWidgets('shared utility uses the declared supported floor', (
    tester,
  ) async {
    expect(SupportedViewport.minimumSize, const Size(360, 640));
    await pumpAtSupportedFloor(
      tester,
      Builder(
        builder: (context) {
          expect(MediaQuery.sizeOf(context), SupportedViewport.minimumSize);
          return const SizedBox.expand();
        },
      ),
    );
  });

  testWidgets('overflow is a build-breaking failure', (tester) async {
    await pumpAtSupportedFloor(
      tester,
      const MaterialApp(
        home: Row(children: [SizedBox(width: 300), SizedBox(width: 300)]),
      ),
    );
    expect(() => expectNoLayoutOverflow(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('utility renders an ordinary fixture at the exact floor', (
    tester,
  ) async {
    await pumpAtSupportedFloor(
      tester,
      Builder(
        builder: (context) {
          expect(MediaQuery.sizeOf(context), SupportedViewport.minimumSize);
          return const SizedBox.expand();
        },
      ),
    );
    expectNoLayoutOverflow(tester);
  });
}
