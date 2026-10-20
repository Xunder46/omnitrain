import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/muscle_selection.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/models/muscle_taxonomy.dart';
import 'package:omnitrain/widgets/exercise/muscle_picker.dart';

/// The picker over a live [MuscleSelection]: a tap cycles the tapped id, so
/// the summary and the chip states update the way the editor does.
class _PickerHost extends StatefulWidget {
  const _PickerHost({required this.groups, this.initial});

  final List<MuscleGroup> groups;
  final MuscleSelection? initial;

  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<_PickerHost> {
  late MuscleSelection _selection = widget.initial ?? MuscleSelection();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MusclePicker(
          groups: widget.groups,
          selection: _selection,
          onTap: (id) => setState(() => _selection = _selection.cycle(id)),
        ),
      ),
    ),
  );
}

/// Every taxonomy entry as a [MuscleGroup], minus [exclude].
List<MuscleGroup> _allGroups({Set<String> exclude = const {}}) => [
  for (final entry in MuscleTaxonomy.entries)
    if (!exclude.contains(entry.id))
      MuscleGroup(
        id: entry.id,
        name: entry.name,
        parentId: entry.parentId,
        createdAtMs: 0,
      ),
];

Future<void> _pumpPicker(WidgetTester tester, _PickerHost host) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  testWidgets('S-3 chest cycles main, then assists, then none', (tester) async {
    await _pumpPicker(tester, _PickerHost(groups: _allGroups()));

    expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: none');
    expect(_text(tester, MusclePicker.assistsSummaryKey), 'Assists: none');

    await tester.tap(find.byKey(MusclePicker.chipKey('muscle-chest')));
    await tester.pump();
    expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: Chest');
    expect(_text(tester, MusclePicker.assistsSummaryKey), 'Assists: none');
    expect(find.text('Chest'), findsOneWidget);

    await tester.tap(find.byKey(MusclePicker.chipKey('muscle-chest')));
    await tester.pump();
    expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: none');
    expect(_text(tester, MusclePicker.assistsSummaryKey), 'Assists: Chest');
    expect(find.text('Chest · assists'), findsOneWidget);

    await tester.tap(find.byKey(MusclePicker.chipKey('muscle-chest')));
    await tester.pump();
    expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: none');
    expect(_text(tester, MusclePicker.assistsSummaryKey), 'Assists: none');
  });

  testWidgets('S-3 the six row labels run top to bottom in plan order', (
    tester,
  ) async {
    await _pumpPicker(tester, _PickerHost(groups: _allGroups()));

    const labels = [
      'Chest and neck',
      'Back',
      'Shoulders',
      'Arms',
      'Core',
      'Legs',
    ];
    final tops = [
      for (final label in labels) tester.getTopLeft(find.text(label)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '${labels[i]} must sit below ${labels[i - 1]}',
      );
    }
  });

  testWidgets('S-3 whole legs then quadriceps leaves the legs chip covered', (
    tester,
  ) async {
    await _pumpPicker(tester, _PickerHost(groups: _allGroups()));

    await tester.tap(find.byKey(MusclePicker.chipKey('muscle-legs')));
    await tester.pump();
    expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: Legs');

    await tester.tap(find.byKey(MusclePicker.chipKey('muscle-quads')));
    await tester.pump();
    expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: Quadriceps');
    expect(_text(tester, MusclePicker.assistsSummaryKey), 'Assists: none');

    final handle = tester.ensureSemantics();
    try {
      expect(
        tester
            .getSemantics(find.byKey(MusclePicker.chipKey('muscle-legs')))
            .label,
        contains('covered by chosen muscles'),
      );
    } finally {
      handle.dispose();
    }

    await tester.tap(
      find.byKey(MusclePicker.chipKey('muscle-legs')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: Quadriceps');
    expect(_text(tester, MusclePicker.assistsSummaryKey), 'Assists: none');
  });

  testWidgets('S-3 the hint is present and the chip semantics name the role', (
    tester,
  ) async {
    await _pumpPicker(tester, _PickerHost(groups: _allGroups()));

    expect(
      _text(tester, MusclePicker.hintKey),
      'Tap once for a main muscle, twice for one that assists, '
      'a third time to clear.',
    );

    final handle = tester.ensureSemantics();
    try {
      final neck = find.byKey(MusclePicker.chipKey('muscle-neck'));
      expect(tester.getSemantics(neck).label, 'Neck, not selected');

      await tester.tap(neck);
      await tester.pump();
      expect(tester.getSemantics(neck).label, 'Neck, main muscle');

      await tester.tap(neck);
      await tester.pump();
      expect(tester.getSemantics(neck).label, 'Neck, assists');
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'S-3 every rendered chip is at least 40 dp tall',
    (tester) async {
      await _pumpPicker(tester, _PickerHost(groups: _allGroups()));

      final chips = find.byType(FilterChip);
      final count = tester.widgetList(chips).length;
      expect(count, greaterThan(0));
      for (var i = 0; i < count; i++) {
        expect(
          tester.getSize(chips.at(i)).height,
          greaterThanOrEqualTo(40.0),
          reason: 'chip #$i of $count',
        );
      }
    },
  );

  testWidgets(
    'S-12 a group id missing from groups is skipped and still named',
    (tester) async {
      await _pumpPicker(
        tester,
        _PickerHost(
          groups: _allGroups(exclude: {'muscle-obliques'}),
          initial: MuscleSelection({'muscle-obliques': MuscleRole.primary}),
        ),
      );

      expect(find.byKey(MusclePicker.chipKey('muscle-obliques')), findsNothing);
      expect(_text(tester, MusclePicker.mainSummaryKey), 'Main: Obliques');
      expect(_text(tester, MusclePicker.assistsSummaryKey), 'Assists: none');
      expect(tester.takeException(), isNull);
    },
  );
}
