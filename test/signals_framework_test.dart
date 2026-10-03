// The pure Signals framework (Stats PR 6a, Phase 1): the gate, the selection,
// the quiet line, the dismissal day maths and the store parse.
//
// Scenarios S-1703 … S-1711 of
// `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/`, asserted
// against synthetic candidate lists. Nothing here needs a repository, a widget
// or a clock: `now` is a parameter everywhere it is read (D-1017).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/training_load.dart';

SignalCard _card(
  String id,
  SignalKind kind,
  int priority, {
  String? suggestion,
}) => SignalCard(
  id: id,
  kind: kind,
  priority: priority,
  title: 'title $id',
  observation: 'observation $id',
  suggestion: suggestion,
);

SignalCard _positive(String id, int priority) =>
    _card(id, SignalKind.positive, priority);

SignalCard _caution(String id, int priority) =>
    _card(id, SignalKind.caution, priority);

MixLayerData _mix({required int ratedBaselineWeeks, MixMeasure? measure}) =>
    MixLayerData(
      measure: measure ?? MixMeasure.time,
      segments: const [],
      baselineSegments: const [],
      unratedSessionCount: 0,
      ratedBaselineWeeks: ratedBaselineWeeks,
      weeks: const [],
    );

/// The dismissal every day-maths case uses: 2026-03-01 at local noon.
final int _dismissedAtMs = DateTime(2026, 3, 1, 12).millisecondsSinceEpoch;

void main() {
  group('D-1006 the quiet-line gate', () {
    test('signalsGateMet is false for a null mix', () {
      expect(signalsGateMet(null), isFalse);
    });

    test('signalsGateMet is false one rated week below the minimum', () {
      expect(
        signalsGateMet(
          _mix(ratedBaselineWeeks: kTrainingLoadMinRatedWeeks - 1),
        ),
        isFalse,
      );
    });

    test('signalsGateMet is true at the minimum rated weeks', () {
      expect(
        signalsGateMet(_mix(ratedBaselineWeeks: kTrainingLoadMinRatedWeeks)),
        isTrue,
      );
    });

    test('signalsGateMet reads rated weeks only, never the measure', () {
      expect(
        signalsGateMet(
          _mix(
            ratedBaselineWeeks: kTrainingLoadMinRatedWeeks,
            measure: MixMeasure.time,
          ),
        ),
        isTrue,
      );
    });
  });

  group('S-1703 gate met, nothing qualifies', () {
    test('the quiet line is the pinned sentence', () {
      expect(
        kSignalQuietLine,
        'No signals — nothing outside your usual range.',
      );
    });

    test('an empty candidate list yields no cards and the quiet line', () {
      final data = resolveSignals(
        candidates: const [],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards, isEmpty);
      expect(data.showQuietLine, isTrue);
    });

    test('an unmet gate yields no cards and no quiet line', () {
      final data = resolveSignals(
        candidates: [_positive('p', 1)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: false,
      );
      expect(data.cards, isEmpty);
      expect(data.showQuietLine, isFalse);
    });
  });

  group('S-1704 one qualifying card', () {
    test('S-1704 a single positive is the only card', () {
      final data = resolveSignals(
        candidates: [_positive('p', 10)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards.map((c) => c.id), ['p']);
      expect(data.cards.single.kind, SignalKind.positive);
      expect(data.showQuietLine, isFalse);
    });
  });

  group('S-1705 both kinds qualify', () {
    test('S-1705 the top caution sits above the top positive', () {
      // Candidates are given in ascending priority, so a selection that keeps
      // the input order cannot pass.
      final data = resolveSignals(
        candidates: [
          _caution('c10', 10),
          _caution('c20', 20),
          _positive('p10', 10),
          _positive('p20', 20),
        ],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards.map((c) => c.id), ['c20', 'p20']);
      expect(data.cards.map((c) => c.kind), [
        SignalKind.caution,
        SignalKind.positive,
      ]);
    });
  });

  group('S-1706 three cautions, no positive', () {
    test('S-1706 the two highest-priority cautions, in order', () {
      final data = resolveSignals(
        candidates: [_caution('c10', 10), _caution('c30', 30), _caution('c20', 20)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards.map((c) => c.id), ['c30', 'c20']);
    });
  });

  group('S-1707 three positives, no caution', () {
    test('S-1707 the two highest-priority positives, in order', () {
      final data = resolveSignals(
        candidates: [
          _positive('p10', 10),
          _positive('p30', 30),
          _positive('p20', 20),
        ],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards.map((c) => c.id), ['p30', 'p20']);
    });
  });

  group('D-1004 at most two cards', () {
    test('a ten-candidate list resolves to the top two', () {
      final data = resolveSignals(
        candidates: [for (var i = 1; i <= 10; i++) _positive('p$i', i)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards.length, kSignalMaxCards);
      expect(data.cards.map((c) => c.id), ['p10', 'p9']);
    });
  });

  group('D-1005 priority order within a kind', () {
    test('an exact priority tie breaks by id ascending', () {
      final data = resolveSignals(
        candidates: [_positive('b', 5), _positive('a', 5)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards.map((c) => c.id), ['a', 'b']);
    });
  });

  group('S-1708 an abstaining signal is invisible', () {
    test('S-1708 an abstainer contributes no card and suppresses nothing', () {
      // The abstainer itself never reaches `resolveSignals` — the service drops
      // a null evaluation — so the pure rule is that the other cards resolve
      // unchanged and an otherwise-empty list still shows the quiet line.
      final others = resolveSignals(
        candidates: [_positive('p', 10)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(others.cards.map((c) => c.id), ['p']);

      final alone = resolveSignals(
        candidates: const [],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(alone.cards, isEmpty);
      expect(alone.showQuietLine, isTrue);
    });
  });

  group('S-1710 the 14-day window', () {
    test('S-1710 hidden on day 14, eligible on day 15', () {
      expect(
        isSignalDismissed(
          dismissedAtMs: _dismissedAtMs,
          now: DateTime(2026, 3, 14),
        ),
        isTrue,
      );
      expect(
        isSignalDismissed(
          dismissedAtMs: _dismissedAtMs,
          now: DateTime(2026, 3, 15),
        ),
        isFalse,
      );
    });

    test('a dismissed candidate is hidden; an expired one is not', () {
      final hidden = resolveSignals(
        candidates: [_positive('p', 10)],
        dismissedAtMs: {'p': _dismissedAtMs},
        now: DateTime(2026, 3, 14),
        gateMet: true,
      );
      expect(hidden.cards, isEmpty);
      expect(hidden.showQuietLine, isTrue);

      final shown = resolveSignals(
        candidates: [_positive('p', 10)],
        dismissedAtMs: {'p': _dismissedAtMs},
        now: DateTime(2026, 3, 15),
        gateMet: true,
      );
      expect(shown.cards.map((c) => c.id), ['p']);
    });
  });

  group('S-1711 the daylight-saving boundary', () {
    test('S-1711 the spring-forward does not shorten the window', () {
      // Dismissed 2026-03-01; the window contains the 2026-03-08 US
      // spring-forward. Calendar days say day 14 is hidden and day 15 is
      // eligible; an elapsed-hours count loses the hour and hides day 15.
      expect(
        isSignalDismissed(
          dismissedAtMs: _dismissedAtMs,
          now: DateTime(2026, 3, 14),
        ),
        isTrue,
      );
      expect(
        isSignalDismissed(
          dismissedAtMs: _dismissedAtMs,
          now: DateTime(2026, 3, 15),
        ),
        isFalse,
      );
    });
  });

  group('D-1010 / D-1013 the dismissal write', () {
    test('adds the id at `now`', () {
      final next = signalDismissalsWith(
        const {},
        'p',
        DateTime(2026, 3, 10, 12),
      );
      expect(next, {'p': DateTime(2026, 3, 10, 12).millisecondsSinceEpoch});
    });

    test('keeps an entry that is still hidden', () {
      final next = signalDismissalsWith(
        {'old': _dismissedAtMs},
        'p',
        DateTime(2026, 3, 10, 12),
      );
      expect(next.keys.toSet(), {'old', 'p'});
      expect(next['old'], _dismissedAtMs);
    });

    test('drops an entry at 14 days', () {
      final next = signalDismissalsWith(
        {'old': _dismissedAtMs},
        'p',
        DateTime(2026, 3, 15, 12),
      );
      expect(next.containsKey('old'), isFalse);
      expect(next.containsKey('p'), isTrue);
    });

    test('does not mutate its input', () {
      final current = {'old': _dismissedAtMs};
      final next = signalDismissalsWith(
        current,
        'p',
        DateTime(2026, 3, 15, 12),
      );
      expect(current, {'old': _dismissedAtMs});
      expect(identical(next, current), isFalse);
    });
  });

  group('D-1009 the dismissal store parse', () {
    test('a missing value reads as no dismissal', () {
      expect(parseSignalDismissals(null), isEmpty);
    });

    test('an unparseable value reads as no dismissal', () {
      expect(parseSignalDismissals('not json'), isEmpty);
    });

    test('a non-object value reads as no dismissal', () {
      expect(parseSignalDismissals('[1, 2]'), isEmpty);
    });

    test('a non-integer entry reads as no dismissal', () {
      expect(parseSignalDismissals('{"a": 1.5, "b": true}'), isEmpty);
    });

    test('an empty object reads as no dismissal', () {
      expect(parseSignalDismissals('{}'), isEmpty);
    });

    test('a well-formed map round-trips through the encoder', () {
      const stored = {'sig-a': 1772366400000};
      expect(parseSignalDismissals(encodeSignalDismissals(stored)), stored);
    });
  });

  group('D-1001 / D-1002 the kind vocabulary', () {
    test('the two kinds carry the pinned labels', () {
      expect(signalKindLabel(SignalKind.positive), 'Positive');
      expect(signalKindLabel(SignalKind.caution), 'Worth a look');
    });
  });

  // ─── Structural guards (Phase 3) ──────────────────────────────────────────
  //
  // Each guard names the defect it makes impossible and the edit that breaks
  // it. They are permanent: a change that reintroduces the defect fails here,
  // not in review.

  group('Structural guard — the gate precedes every signal', () {
    test('a card proposed while the gate is unmet is never rendered', () {
      // Breaks if `resolveSignals` stops returning early on `!gateMet`: a
      // signal that returns a card would then reach the layer with the gate
      // unmet (D-1006).
      final data = resolveSignals(
        candidates: [_positive('p', 10), _caution('c', 20)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: false,
      );
      expect(data.cards, isEmpty);
      expect(data.showQuietLine, isFalse);
    });
  });

  group('Structural guard — the layer never renders three cards', () {
    test('a ten-candidate list is capped at the pinned two', () {
      // Breaks if `kSignalMaxCards` is raised: the cap is a product rule
      // (D-1004), not a tunable.
      expect(kSignalMaxCards, 2);
      final data = resolveSignals(
        candidates: [for (var i = 1; i <= 10; i++) _positive('p$i', i)],
        dismissedAtMs: const {},
        now: DateTime(2026, 3, 10),
        gateMet: true,
      );
      expect(data.cards.length, lessThanOrEqualTo(2));
      expect(data.cards.length, kSignalMaxCards);
    });
  });

  group('Structural guard — a dismissal hides for the whole window', () {
    test('every day 1…14 is hidden and day 15 is eligible', () {
      // Breaks if `isSignalDismissed` shortens the window (e.g. hides for 13
      // days): day 14 would become eligible (D-1011).
      for (var day = 1; day <= kSignalDismissalDays; day++) {
        expect(
          isSignalDismissed(
            dismissedAtMs: _dismissedAtMs,
            now: DateTime(2026, 3, day),
          ),
          isTrue,
          reason: 'day $day of the window must be hidden',
        );
      }
      expect(
        isSignalDismissed(
          dismissedAtMs: _dismissedAtMs,
          now: DateTime(2026, 3, kSignalDismissalDays + 1),
        ),
        isFalse,
        reason: 'the day after the window must be eligible',
      );
    });
  });
}
