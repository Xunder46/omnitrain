import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';

Widget _host(TargetPlatform platform, int actions) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: Scaffold(
    appBar: OmniBackHeader(
      title: 'Stats',
      actions: [
        for (var i = 0; i < actions; i++)
          IconButton(icon: const Icon(Icons.show_chart), onPressed: () {}),
      ],
    ),
  ),
);

void main() {
  for (final actions in [0, 1, 2, 3]) {
    testWidgets('iOS title stays centred with $actions action(s)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(TargetPlatform.iOS, actions));
      final centre = tester.getCenter(find.text('Stats')).dx;
      final screen = tester.getSize(find.byType(Scaffold)).width / 2;
      expect(centre, closeTo(screen, 0.5));
    });
  }

  testWidgets('Android keeps its left-aligned title', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android, 2));
    final centre = tester.getCenter(find.text('Stats')).dx;
    final screen = tester.getSize(find.byType(Scaffold)).width / 2;
    expect(centre, lessThan(screen - 20));
  });
}
