// Plan 34, Phase A — the editor's muscle selection model.
//
// Scenario S-1 of
// `docs/plans/2026-10-14-34-muscle-editor-plan/2026-10-14-34-muscle-editor-plan.md`.
//
// `MuscleSelection` is the immutable value the editor taps through: off →
// main → assists → off. A region and one of its own muscles can never carry a
// role at the same time, and `toLinks` is what reaches the repository.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/muscle_selection.dart';
import 'package:omnitrain/data/models/models.dart';

ExerciseMuscleLink _link(String id, [MuscleRole role = MuscleRole.primary]) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

MuscleSelection _selection(Map<String, MuscleRole> roles) =>
    MuscleSelection(roles);

void main() {
  group('S-1 selection model', () {
    test('an empty selection cycles a muscle off → main → assists → off', () {
      var selection = MuscleSelection();
      expect(selection.isEmpty, isTrue);

      selection = selection.cycle('muscle-quads');
      expect(selection, _selection({'muscle-quads': MuscleRole.primary}));
      expect(selection.roleOf('muscle-quads'), MuscleRole.primary);

      selection = selection.cycle('muscle-quads');
      expect(selection, _selection({'muscle-quads': MuscleRole.secondary}));

      selection = selection.cycle('muscle-quads');
      expect(selection.isEmpty, isTrue);
      expect(selection.roleOf('muscle-quads'), isNull);
    });

    test('a muscle gaining a role removes its region\'s own entry', () {
      expect(
        _selection({'muscle-legs': MuscleRole.primary}).cycle('muscle-quads'),
        _selection({'muscle-quads': MuscleRole.primary}),
      );
    });

    test('a region whose muscles carry a role is covered and inert', () {
      final selection = _selection({'muscle-quads': MuscleRole.primary});
      expect(selection.isCovered('muscle-legs'), isTrue);
      expect(selection.cycle('muscle-legs'), selection);
      expect(selection, _selection({'muscle-quads': MuscleRole.primary}));
    });

    test(
      'isCovered is false for a bare region, a muscle and an unknown id',
      () {
        expect(MuscleSelection().isCovered('muscle-legs'), isFalse);
        expect(
          _selection({
            'muscle-legs': MuscleRole.primary,
          }).isCovered('muscle-legs'),
          isFalse,
        );
        expect(
          _selection({
            'muscle-chest': MuscleRole.primary,
          }).isCovered('muscle-chest'),
          isFalse,
        );
        expect(
          _selection({'muscle-quads': MuscleRole.primary}).isCovered('nope'),
          isFalse,
        );
      },
    );

    test('a secondary region gives way to a chosen muscle too', () {
      expect(
        _selection({
          'muscle-legs': MuscleRole.secondary,
        }).cycle('muscle-glutes'),
        _selection({'muscle-glutes': MuscleRole.primary}),
      );
    });

    test(
      'Chest and Neck cycle independently of each other and of a region',
      () {
        var selection = MuscleSelection();
        selection = selection
            .cycle('muscle-chest')
            .cycle('muscle-neck')
            .cycle('muscle-neck');

        expect(
          selection,
          _selection({
            'muscle-chest': MuscleRole.primary,
            'muscle-neck': MuscleRole.secondary,
          }),
        );

        selection = selection.cycle('muscle-chest').cycle('muscle-chest');
        expect(selection, _selection({'muscle-neck': MuscleRole.secondary}));
      },
    );

    test(
      'idsWith lists the chosen ids in taxonomy order, unknown ids last',
      () {
        final selection = _selection({
          'zzz-unknown': MuscleRole.primary,
          'muscle-chest': MuscleRole.primary,
          'muscle-quads': MuscleRole.primary,
          'muscle-triceps': MuscleRole.secondary,
          'muscle-forearms': MuscleRole.secondary,
        });

        expect(selection.idsWith(MuscleRole.primary), [
          'muscle-quads',
          'muscle-chest',
          'zzz-unknown',
        ]);
        expect(selection.idsWith(MuscleRole.secondary), [
          'muscle-triceps',
          'muscle-forearms',
        ]);
      },
    );

    test('fromLinks drops the region that sits next to its own muscle', () {
      expect(
        MuscleSelection.fromLinks([
          _link('muscle-legs'),
          _link('muscle-quads'),
        ]),
        _selection({'muscle-quads': MuscleRole.primary}),
      );
    });

    test('fromLinks keeps the primary of a duplicated id', () {
      expect(
        MuscleSelection.fromLinks([
          _link('muscle-triceps', MuscleRole.secondary),
          _link('muscle-triceps'),
        ]),
        _selection({'muscle-triceps': MuscleRole.primary}),
      );
      expect(
        MuscleSelection.fromLinks([
          _link('muscle-triceps'),
          _link('muscle-triceps', MuscleRole.secondary),
        ]),
        _selection({'muscle-triceps': MuscleRole.primary}),
      );
    });

    test('fromLinks round-trips a valid set through toLinks, normalised', () {
      final selection = MuscleSelection.fromLinks([
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
        _link('muscle-front-delts', MuscleRole.secondary),
      ]);

      expect(selection.toLinks(), [
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
        _link('muscle-front-delts', MuscleRole.secondary),
      ]);
    });

    test('toLinks normalises the stored order', () {
      // Insertion order (secondary first) is not the storable order: primary
      // links come first and, inside a role, taxonomy order wins.
      final selection = _selection({
        'muscle-triceps': MuscleRole.secondary,
        'muscle-chest': MuscleRole.primary,
      });

      expect(selection.toLinks(), [
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
      ]);
    });

    test('hasPrimary and hasOnlyAssists', () {
      expect(MuscleSelection().isEmpty, isTrue);
      expect(MuscleSelection().hasPrimary, isFalse);
      expect(MuscleSelection().hasOnlyAssists, isFalse);

      final assistsOnly = _selection({'muscle-triceps': MuscleRole.secondary});
      expect(assistsOnly.isEmpty, isFalse);
      expect(assistsOnly.hasOnlyAssists, isTrue);
      expect(assistsOnly.hasPrimary, isFalse);

      final withPrimary = _selection({
        'muscle-chest': MuscleRole.primary,
        'muscle-triceps': MuscleRole.secondary,
      });
      expect(withPrimary.hasPrimary, isTrue);
      expect(withPrimary.hasOnlyAssists, isFalse);
    });

    test('toLinks of an assists-only selection throws', () {
      expect(
        () => _selection({'muscle-triceps': MuscleRole.secondary}).toLinks(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('equality, hashCode and toString are by content', () {
      final a = _selection({
        'muscle-chest': MuscleRole.primary,
        'muscle-triceps': MuscleRole.secondary,
      });
      final b = _selection({
        'muscle-triceps': MuscleRole.secondary,
        'muscle-chest': MuscleRole.primary,
      });

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(MuscleSelection()));
      expect(a, isNot(_selection({'muscle-chest': MuscleRole.secondary})));
      expect(a.toString(), contains('muscle-chest'));
      expect(a.toString(), contains('muscle-triceps'));
    });

    test('the constructor copies the map it is given', () {
      final roles = <String, MuscleRole>{'muscle-chest': MuscleRole.primary};
      final selection = MuscleSelection(roles);

      roles['muscle-triceps'] = MuscleRole.secondary;

      expect(selection.roleOf('muscle-triceps'), isNull);
      expect(selection.roleOf('muscle-chest'), MuscleRole.primary);
    });
  });
}
