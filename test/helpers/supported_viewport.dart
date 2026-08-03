import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/supported_viewport.dart';

/// Applies the one supported floor to a widget test and restores the binding.
Future<void> pumpAtSupportedFloor(
  WidgetTester tester,
  Widget child, {
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(SupportedViewport.minimumSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: SupportedViewport.minimumSize,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    ),
  );
  await tester.pumpAndSettle();
}

void expectNoLayoutOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull, reason: 'Supported floor must not overflow');
}
