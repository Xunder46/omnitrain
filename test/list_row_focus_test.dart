// Scenario mapping:
//   S-13901 request + reveal lands a far row at the alignment; the cache
//           extent is raised only while the request is pending
//   S-13902 reveal answers false and moves nothing when there is nothing to do
//
// Plain widget tests, no timers, no repositories.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/layout/list_row_focus.dart';

const int _rowCount = 60;

double _rowHeight(int i) => 60.0 + (i % 5) * 37;

Widget _host(ListRowFocus focus, ScrollController controller, {int? skip}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        key: const Key('host-list'),
        controller: controller,
        cacheExtent: focus.cacheExtent,
        children: [
          for (var i = 0; i < _rowCount; i++)
            if (i != skip)
              focus.track(
                'c$i',
                SizedBox(
                  key: ValueKey('card-$i'),
                  height: _rowHeight(i),
                  child: Text('card $i'),
                ),
              ),
        ],
      ),
    ),
  );
}

double _landing(WidgetTester tester, int i) =>
    tester.getTopLeft(find.byKey(ValueKey('card-$i'))).dy -
    tester.getTopLeft(find.byKey(const Key('host-list'))).dy;

void main() {
  group('S-13901 reveal lands a far row', () {
    testWidgets('a row far outside the cache lands at the alignment', (
      tester,
    ) async {
      final focus = ListRowFocus();
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(focus, controller));
      expect(
        find.byKey(const ValueKey('card-30')),
        findsNothing,
        reason: 'a lazy list has not built row 30',
      );
      expect(focus.cacheExtent, isNull);

      focus.request('c30');
      expect(focus.cacheExtent, ListRowFocus.kRevealCacheExtent);
      await tester.pumpWidget(_host(focus, controller));
      expect(focus.reveal(), isTrue);
      // The owner rebuilds after reveal: the extent drops back to the default.
      await tester.pumpWidget(_host(focus, controller));
      await tester.pump();

      expect(focus.cacheExtent, isNull);
      final listHeight = tester
          .getSize(find.byKey(const Key('host-list')))
          .height;
      expect(
        _landing(tester, 30),
        closeTo(
          ListRowFocus.kRevealAlignment * (listHeight - _rowHeight(30)),
          1.0,
        ),
      );
    });

    testWidgets('the last row lands as low as the list can scroll', (
      tester,
    ) async {
      final focus = ListRowFocus();
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(focus, controller));
      focus.request('c59');
      await tester.pumpWidget(_host(focus, controller));
      expect(focus.reveal(), isTrue);
      await tester.pumpWidget(_host(focus, controller));
      await tester.pump();

      expect(controller.offset, controller.position.maxScrollExtent);
    });
  });

  group('S-13902 reveal with nothing to do', () {
    testWidgets(
      'no request, an unknown id and a removed row answer false and move nothing',
      (tester) async {
        final focus = ListRowFocus();
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_host(focus, controller));
        controller.jumpTo(300);
        await tester.pump();

        // (a) nothing requested.
        expect(focus.reveal(), isFalse);
        expect(controller.offset, 300);

        // (b) an id that was never built.
        focus.request('nope');
        await tester.pumpWidget(_host(focus, controller));
        expect(focus.reveal(), isFalse);
        expect(controller.offset, 300);
        expect(focus.cacheExtent, isNull);
        expect(focus.reveal(), isFalse, reason: 'the request was cleared');

        // (c) a row that was built, then removed from the list.
        focus.request('c10');
        await tester.pumpWidget(_host(focus, controller));
        await tester.pumpWidget(_host(focus, controller, skip: 10));
        final before = controller.offset;
        expect(focus.reveal(), isFalse);
        expect(controller.offset, before);
        expect(focus.cacheExtent, isNull);
      },
    );
  });
}
