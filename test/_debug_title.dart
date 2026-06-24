import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';

void main() {
  testWidgets('measure titleMedium height', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(builder: (context) {
            return Text(
            'TRAIN',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              color: OmniTheme.colors.textDominant,
            ),
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.text('TRAIN'));
    debugPrint('TITLE_HEIGHT=${size.height}');
  });
}
