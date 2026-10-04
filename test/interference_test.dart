// Stats PR 7b, Phase 1 — the Cross-Modality Interference rule and its copy.
//
// The rule is pure Dart: `now` is a parameter, and there is no clock, no
// repository and no Flutter. Scenarios S-2001, S-2003, S-2004, S-2006, S-2007,
// S-2008, S-2009's pure half, S-2010 and S-2015 of
// `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/interference.dart';
import 'package:omnitrain/core/models/modality_mix_shift.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/signal_registry.dart';

/// [path] with its comments stripped, so a guard fires on code and not on a
/// comment that merely names what the code must not do.
String _strippedSource(String path) {
  final source = File(
    path,
  ).readAsStringSync().replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return source
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i < 0 ? line : line.substring(0, i);
      })
      .join('\n');
}

/// Local midnight [daysAgo] days before [now].
DateTime _day(DateTime now, int daysAgo) {
  final d = now.subtract(Duration(days: daysAgo));
  return DateTime(d.year, d.month, d.day);
}

/// A session starting at 09:00 local on [daysAgo], running [seconds].
InterferenceSession _session({
  required DateTime now,
  required int daysAgo,
  required String id,
  double sportsLoadMinutes = 0,
  int? rating,
  bool hasSetEffort = false,
  Map<String, double> bests = const {},
  int seconds = 3600,
}) {
  final start = _day(now, daysAgo).add(const Duration(hours: 9));
  return InterferenceSession(
    id: id,
    startMs: start.millisecondsSinceEpoch,
    endMs: start.add(Duration(seconds: seconds)).millisecondsSinceEpoch,
    rating: rating,
    sportsLoadMinutes: sportsLoadMinutes,
    hasSetEffort: hasSetEffort,
    bests: bests,
  );
}

/// A session starting at the absolute [startMs], running [seconds].
InterferenceSession _at({
  required int startMs,
  required String id,
  double sportsLoadMinutes = 0,
  int? rating,
  bool hasSetEffort = false,
  Map<String, double> bests = const {},
  int seconds = 3600,
}) => InterferenceSession(
  id: id,
  startMs: startMs,
  endMs: startMs + seconds * 1000,
  rating: rating,
  sportsLoadMinutes: sportsLoadMinutes,
  hasSetEffort: hasSetEffort,
  bests: bests,
);

/// [s] with its Sports load replaced by [load].
InterferenceSession _withLoad(InterferenceSession s, double load) =>
    InterferenceSession(
      id: s.id,
      startMs: s.startMs,
      endMs: s.endMs,
      rating: s.rating,
      sportsLoadMinutes: load,
      hasSetEffort: s.hasSetEffort,
      bests: s.bests,
    );

/// F-2001: the pack's own example, hand-built (S-2001).
///
/// 12 rated sports sessions, 7 prior lifting sessions and 4 follow-up lifting
/// sessions. The four hard sessions are days 34, 28, 18 and 8; their follow-ups
/// are days 33, 27, 17 and 7. Each follow-up's 28-day lookback (D-1305) reaches
/// the day-58 … day-30 priors alone.
///
/// The 41-load session sits at day 46, outside the prior 21-day span: D-1313's
/// prior span is then the day-34 and day-28 sessions alone (50 + 50 = 100), and
/// the recent span is 55 + 83 = 138 → 38%. At day 40 the same session would add
/// its 41 to the prior span (141) and the rise would not hold.
List<InterferenceSession> _f2001(DateTime now) {
  const sportsDays = [88, 80, 70, 60, 55, 50, 46, 44, 34, 28, 18, 8];
  const sportsLoads = [4.0, 8.0, 12.0, 20.0, 24.0, 28.0, 41.0, 30.0, 50.0, 50.0, 55.0, 83.0];
  const sportsSeconds = [3600, 3600, 3600, 3600, 3600, 3600, 3600, 3600, 750, 750, 825, 996];

  final sessions = <InterferenceSession>[];
  for (var i = 0; i < sportsDays.length; i++) {
    sessions.add(
      _session(
        now: now,
        daysAgo: sportsDays[i],
        id: 'sports-${sportsDays[i]}',
        sportsLoadMinutes: sportsLoads[i],
        rating: sportsDays[i] == 8 ? 5 : 4,
        seconds: sportsSeconds[i],
      ),
    );
  }

  for (final daysAgo in const [58, 52, 46, 42, 38, 36, 30]) {
    sessions.add(
      _session(
        now: now,
        daysAgo: daysAgo,
        id: 'prior-$daysAgo',
        rating: 4,
        hasSetEffort: true,
        bests: const {'ex-lift': 100.0},
      ),
    );
  }

  const followUps = {33: 84.0, 27: 100.0, 17: 89.0, 7: 88.0};
  for (final entry in followUps.entries) {
    sessions.add(
      _session(
        now: now,
        daysAgo: entry.key,
        id: 'follow-${entry.key}',
        rating: 4,
        hasSetEffort: true,
        bests: {'ex-lift': entry.value},
      ),
    );
  }

  return sessions;
}

/// F-2001 with the day-17 and day-7 follow-ups back at 100.0 (S-2002).
List<InterferenceSession> _f2001TwoDips(DateTime now) => _f2001(now)
    .map(
      (s) => s.id == 'follow-17' || s.id == 'follow-7'
          ? InterferenceSession(
              id: s.id,
              startMs: s.startMs,
              endMs: s.endMs,
              rating: s.rating,
              sportsLoadMinutes: s.sportsLoadMinutes,
              hasSetEffort: s.hasSetEffort,
              bests: const {'ex-lift': 100.0},
            )
          : s,
    )
    .toList();

/// S-2003's base: one hard sports session H plus the 7-session floor.
///
/// H is rated with load 100 and ends at `E`; the seven fillers sit at days 88,
/// 84, 80, 76, 72, 68 and 64 with loads 1–7, far from any lifting session.
List<InterferenceSession> _s2003Base(DateTime now) {
  final sessions = <InterferenceSession>[
    _session(
      now: now,
      daysAgo: 10,
      id: 'hard',
      sportsLoadMinutes: 100,
      rating: 5,
      seconds: 3600,
    ),
  ];
  const fillerDays = [88, 84, 80, 76, 72, 68, 64];
  for (var i = 0; i < fillerDays.length; i++) {
    sessions.add(
      _session(
        now: now,
        daysAgo: fillerDays[i],
        id: 'filler-${fillerDays[i]}',
        sportsLoadMinutes: (i + 1).toDouble(),
        rating: 4,
      ),
    );
  }
  return sessions;
}

/// A lifting session starting [hours] after [base]'s hard session ends.
InterferenceSession _afterHard(
  DateTime now,
  InterferenceSession hard, {
  required String id,
  required double hours,
  bool hasSetEffort = true,
  Map<String, double> bests = const {'ex-lift': 100.0},
}) {
  final startMs = hard.endMs + (hours * 3600000).round();
  return InterferenceSession(
    id: id,
    startMs: startMs,
    endMs: startMs + 3600000,
    rating: 4,
    sportsLoadMinutes: 0,
    hasSetEffort: hasSetEffort,
    bests: bests,
  );
}

/// S-2003's base plus a prior lifting session inside the follow-up's 28-day
/// lookback, so a follow-up that exists is also comparable (D-1305).
List<InterferenceSession> _s2003WithPrior(DateTime now) => [
  ..._s2003Base(now),
  _session(
    now: now,
    daysAgo: 20,
    id: 'prior-20',
    rating: 4,
    hasSetEffort: true,
    bests: const {'ex-lift': 100.0},
  ),
];

/// S-2004's base: a hard sports session H, a lifting follow-up F and priors so
/// F's lookback average is exactly 100.0.
List<InterferenceSession> _s2004Base(DateTime now) {
  final sessions = <InterferenceSession>[
    _session(
      now: now,
      daysAgo: 10,
      id: 'hard',
      sportsLoadMinutes: 100,
      rating: 5,
      seconds: 3600,
    ),
  ];
  const fillerDays = [88, 84, 80, 76, 72, 68, 64];
  for (var i = 0; i < fillerDays.length; i++) {
    sessions.add(
      _session(
        now: now,
        daysAgo: fillerDays[i],
        id: 'filler-${fillerDays[i]}',
        sportsLoadMinutes: (i + 1).toDouble(),
        rating: 4,
      ),
    );
  }
  for (final daysAgo in const [20, 18, 16]) {
    sessions.add(
      _session(
        now: now,
        daysAgo: daysAgo,
        id: 'prior-$daysAgo',
        rating: 4,
        hasSetEffort: true,
        bests: const {'ex-lift': 100.0, 'ex-other': 100.0},
      ),
    );
  }
  return sessions;
}

/// S-2004's follow-up at day 9 with [bests].
InterferenceSession _s2004FollowUp(
  DateTime now, {
  required Map<String, double> bests,
}) => _session(
  now: now,
  daysAgo: 9,
  id: 'follow',
  rating: 4,
  hasSetEffort: true,
  bests: bests,
);

/// F-2001 with the two 21-day spans' Sports loads set directly (S-2007): the
/// day-34 and day-28 sessions carry [prior] between them, the day-18 and day-8
/// sessions [recent].
List<InterferenceSession> _f2007(
  DateTime now, {
  required double prior,
  required double recent,
}) => _f2001(now)
    .map(
      (s) => switch (s.id) {
        'sports-34' || 'sports-28' => _withLoad(s, prior / 2),
        'sports-18' || 'sports-8' => _withLoad(s, recent / 2),
        _ => s,
      },
    )
    .toList();

/// One follow-up of S-2010's fixture: its id, its absolute start and its best.
class _FollowUp {
  const _FollowUp(this.id, this.startMs, [this.best = 84.0]);

  final String id;
  final int startMs;
  final double best;
}

/// S-2010's fixture: 5 filler sports sessions (loads 1–5) and 3 prior lifting
/// sessions (best 100.0), plus a hard sports session ending 24 h before each
/// follow-up — inside the 36-hour bound but after every other follow-up, so no
/// hard session shadows another's follow-up (D-1304).
List<InterferenceSession> _s2010(DateTime now, List<_FollowUp> followUps) {
  final sessions = <InterferenceSession>[];
  const fillerDays = [88, 84, 80, 76, 72];
  for (var i = 0; i < fillerDays.length; i++) {
    sessions.add(
      _session(
        now: now,
        daysAgo: fillerDays[i],
        id: 'filler-${fillerDays[i]}',
        sportsLoadMinutes: (i + 1).toDouble(),
        rating: 4,
      ),
    );
  }
  for (final daysAgo in const [60, 58, 56]) {
    sessions.add(
      _session(
        now: now,
        daysAgo: daysAgo,
        id: 'prior-$daysAgo',
        rating: 4,
        hasSetEffort: true,
        bests: const {'ex-lift': 100.0},
      ),
    );
  }
  for (final followUp in followUps) {
    sessions.add(
      _at(
        startMs: followUp.startMs - const Duration(hours: 25).inMilliseconds,
        id: 'hard-${followUp.id}',
        sportsLoadMinutes: 100,
        rating: 5,
      ),
    );
    sessions.add(
      _at(
        startMs: followUp.startMs,
        id: followUp.id,
        rating: 4,
        hasSetEffort: true,
        bests: {'ex-lift': followUp.best},
      ),
    );
  }
  return sessions;
}

/// S-2015's fixture: exactly 8 rated sports sessions, one of them at the
/// absolute [earliestStartMs]. Loads 1–8 put the threshold at 6 (D-1303), so
/// days 25, 20 and 15 are hard and days 24, 19 and 14 dip by 16%.
List<InterferenceSession> _s2015(
  DateTime now, {
  required int earliestStartMs,
}) {
  final sessions = <InterferenceSession>[
    _at(startMs: earliestStartMs, id: 'sports-90', sportsLoadMinutes: 1, rating: 4),
  ];
  const sportsDays = [60, 50, 40, 30, 25, 20, 15];
  for (var i = 0; i < sportsDays.length; i++) {
    sessions.add(
      _session(
        now: now,
        daysAgo: sportsDays[i],
        id: 'sports-${sportsDays[i]}',
        sportsLoadMinutes: (i + 2).toDouble(),
        rating: 4,
      ),
    );
  }
  for (final daysAgo in const [35, 34, 33]) {
    sessions.add(
      _session(
        now: now,
        daysAgo: daysAgo,
        id: 'prior-$daysAgo',
        rating: 4,
        hasSetEffort: true,
        bests: const {'ex-lift': 100.0},
      ),
    );
  }
  for (final daysAgo in const [24, 19, 14]) {
    sessions.add(
      _session(
        now: now,
        daysAgo: daysAgo,
        id: 'follow-$daysAgo',
        rating: 4,
        hasSetEffort: true,
        bests: const {'ex-lift': 84.0},
      ),
    );
  }
  return sessions;
}

/// S-2008's 9-session variant: loads 1–9, so nearest-rank
/// `ceil(kInterferenceHardPercentile × 9) = 7` puts the threshold on the seventh
/// smallest load, 7, and loads 7, 8 and 9 are hard (D-1303).
List<InterferenceSession> _s2008Nine(DateTime now) => [
  for (var i = 1; i <= 9; i++)
    _session(
      now: now,
      daysAgo: 90 - i * 9,
      id: 'nine-$i',
      sportsLoadMinutes: i.toDouble(),
      rating: 4,
    ),
];

/// A fixture where two hard sports sessions share one follow-up — the
/// distinct-count guard for D-1309/D-1310.
///
/// Five filler sports sessions carry loads 1–5; the hard sessions all carry 7,
/// so they sit on the threshold. `hard-1` and `hard-2` both name
/// `follow-shared` (it starts 19 h after the first's end and 6 h after the
/// second's, D-1304); `hard-3` names `follow-b` and, when [withThird], `hard-4`
/// names `follow-c`. Every follow-up's 28-day lookback (D-1305) holds only
/// priors at best 100.0, so each dips by 16%.
List<InterferenceSession> _sharedFollowUp(
  DateTime now, {
  required bool withThird,
}) {
  final nowMs = now.millisecondsSinceEpoch;
  const hour = 3600000;
  const day = 86400000;
  return [
    for (var i = 0; i < 5; i++)
      _session(
        now: now,
        daysAgo: 88 - i * 4,
        id: 'filler-$i',
        sportsLoadMinutes: (i + 1).toDouble(),
        rating: 4,
      ),
    _at(
      startMs: nowMs - 30 * day,
      id: 'hard-1',
      sportsLoadMinutes: 7,
      rating: 4,
    ),
    _at(
      startMs: nowMs - 30 * day + 13 * hour,
      id: 'hard-2',
      sportsLoadMinutes: 7,
      rating: 4,
    ),
    _at(
      startMs: nowMs - 20 * day,
      id: 'hard-3',
      sportsLoadMinutes: 7,
      rating: 4,
    ),
    if (withThird)
      _at(
        startMs: nowMs - 10 * day,
        id: 'hard-4',
        sportsLoadMinutes: 7,
        rating: 4,
      ),
    _at(
      startMs: nowMs - 30 * day + 20 * hour,
      id: 'follow-shared',
      rating: 4,
      hasSetEffort: true,
      bests: const {'ex-lift': 84.0},
    ),
    _at(
      startMs: nowMs - 20 * day + 5 * hour,
      id: 'follow-b',
      rating: 4,
      hasSetEffort: true,
      bests: const {'ex-lift': 84.0},
    ),
    if (withThird)
      _at(
        startMs: nowMs - 10 * day + 5 * hour,
        id: 'follow-c',
        rating: 4,
        hasSetEffort: true,
        bests: const {'ex-lift': 84.0},
      ),
    _session(
      now: now,
      daysAgo: 40,
      id: 'prior-40',
      rating: 4,
      hasSetEffort: true,
      bests: const {'ex-lift': 100.0},
    ),
    _session(
      now: now,
      daysAgo: 25,
      id: 'prior-25',
      rating: 4,
      hasSetEffort: true,
      bests: const {'ex-lift': 100.0},
    ),
  ];
}

void main() {
  final now = DateTime(2026, 10, 3, 20);

  group('crossModalityInterference', () {
    test('S-2001 the pack example fires with its exact copy', () {
      final result = crossModalityInterference(
        sessions: _f2001(now),
        now: now,
      );

      expect(result, isNotNull);
      expect(result!.k, 3);
      expect(result.n, 4);
      expect(result.lo, 11);
      expect(result.hi, 16);
      expect(result.hasSportsLoadRise, isTrue);

      final copy = crossModalityInterferenceCopy(result);
      expect(
        copy.observation,
        'After 3 of your last 4 hard sports sessions, your next lifting day '
        'came in 11\u201316% below your usual on the same lifts. Sports load '
        'is up 38% over the last 3 weeks.',
      );
      expect(
        copy.suggestion,
        'A lighter or isometric-focused day after hard sports sessions is one '
        'option.',
      );
    });

    test('S-2002 two dips are not a pattern', () {
      final result = crossModalityInterference(
        sessions: _f2001TwoDips(now),
        now: now,
      );

      expect(result, isNull);
    });

    test('S-2003(a) a session starting exactly at the end is not a follow-up',
        () {
      final base = _s2003WithPrior(now);
      final hard = base.first;
      final analysis = analyseInterference(
        sessions: [...base, _afterHard(now, hard, id: 'at-end', hours: 0)],
        now: now,
      );

      expect(analysis.followUpIdByHardId, isNot(contains('hard')));
    });

    test('S-2003(b) a session starting exactly 36 hours later is the follow-up',
        () {
      final base = _s2003WithPrior(now);
      final hard = base.first;
      final analysis = analyseInterference(
        sessions: [...base, _afterHard(now, hard, id: 'at-36h', hours: 36)],
        now: now,
      );

      expect(analysis.followUpIdByHardId['hard'], 'at-36h');
    });

    test('S-2003(c) a session starting 37 hours later is not a follow-up', () {
      final base = _s2003WithPrior(now);
      final hard = base.first;
      final analysis = analyseInterference(
        sessions: [...base, _afterHard(now, hard, id: 'at-37h', hours: 37)],
        now: now,
      );

      expect(analysis.followUpIdByHardId, isNot(contains('hard')));
    });

    test('S-2003(d) a session with no set effort is skipped for the next one',
        () {
      final base = _s2003WithPrior(now);
      final hard = base.first;
      final analysis = analyseInterference(
        sessions: [
          ...base,
          _afterHard(
            now,
            hard,
            id: 'cardio-1h',
            hours: 1,
            hasSetEffort: false,
            bests: const {},
          ),
          _afterHard(now, hard, id: 'lift-2h', hours: 2),
        ],
        now: now,
      );

      expect(analysis.followUpIdByHardId['hard'], 'lift-2h');
    });

    test('S-2003(e) the earliest qualifying session is the follow-up', () {
      final base = _s2003WithPrior(now);
      final hard = base.first;
      final analysis = analyseInterference(
        sessions: [
          ...base,
          _afterHard(now, hard, id: 'lift-1h', hours: 1),
          _afterHard(now, hard, id: 'lift-2h', hours: 2),
        ],
        now: now,
      );

      expect(analysis.followUpIdByHardId['hard'], 'lift-1h');
    });

    test('S-2004(a) exactly one tenth below dips', () {
      final analysis = analyseInterference(
        sessions: [
          ..._s2004Base(now),
          _s2004FollowUp(now, bests: const {'ex-lift': 90.0}),
        ],
        now: now,
      );

      expect(analysis.dippedFollowUpIds, contains('follow'));
      expect(analysis.shortfallMeanByFollowUpId['follow'], closeTo(0.1, 1e-9));
    });

    test('S-2004(b) nine per cent below does not dip', () {
      final analysis = analyseInterference(
        sessions: [
          ..._s2004Base(now),
          _s2004FollowUp(now, bests: const {'ex-lift': 91.0}),
        ],
        now: now,
      );

      expect(analysis.dippedFollowUpIds, isNot(contains('follow')));
      expect(analysis.shortfallMeanByFollowUpId['follow'], closeTo(0.09, 1e-9));
    });

    test('S-2004(c) an unweighted mean of exactly one tenth dips', () {
      final analysis = analyseInterference(
        sessions: [
          ..._s2004Base(now),
          _s2004FollowUp(
            now,
            bests: const {'ex-lift': 81.0, 'ex-other': 99.0},
          ),
        ],
        now: now,
      );

      expect(analysis.dippedFollowUpIds, contains('follow'));
      expect(analysis.shortfallMeanByFollowUpId['follow'], closeTo(0.1, 1e-9));
    });

    test('S-2004(d) an unweighted mean of nine per cent does not dip', () {
      final analysis = analyseInterference(
        sessions: [
          ..._s2004Base(now),
          _s2004FollowUp(
            now,
            bests: const {'ex-lift': 81.0, 'ex-other': 101.0},
          ),
        ],
        now: now,
      );

      expect(analysis.dippedFollowUpIds, isNot(contains('follow')));
      expect(analysis.shortfallMeanByFollowUpId['follow'], closeTo(0.09, 1e-9));
    });

    test('S-2006 a follow-up with nothing to compare is excluded', () {
      final sessions = <InterferenceSession>[
        _session(
          now: now,
          daysAgo: 30,
          id: 'hard-1',
          sportsLoadMinutes: 100,
          rating: 5,
        ),
        _session(
          now: now,
          daysAgo: 20,
          id: 'hard-2',
          sportsLoadMinutes: 90,
          rating: 5,
        ),
        _session(
          now: now,
          daysAgo: 29,
          id: 'follow-1',
          rating: 4,
          hasSetEffort: true,
          bests: const {'ex-new': 50.0},
        ),
        _session(
          now: now,
          daysAgo: 19,
          id: 'follow-2',
          rating: 4,
          hasSetEffort: true,
          bests: const {'ex-new': 50.0, 'ex-known': 90.0},
        ),
        _session(
          now: now,
          daysAgo: 25,
          id: 'prior-known',
          rating: 4,
          hasSetEffort: true,
          bests: const {'ex-known': 100.0},
        ),
      ];
      for (var i = 0; i < 6; i++) {
        sessions.add(
          _session(
            now: now,
            daysAgo: 88 - i * 4,
            id: 'filler-$i',
            sportsLoadMinutes: (i + 1).toDouble(),
            rating: 4,
          ),
        );
      }

      final analysis = analyseInterference(sessions: sessions, now: now);

      expect(analysis.shortfallMeanByFollowUpId, isNot(contains('follow-1')));
      expect(analysis.dippedFollowUpIds, isNot(contains('follow-1')));
      expect(analysis.dippedFollowUpIds, contains('follow-2'));
      expect(analysis.dippedFollowUpIds, hasLength(1));
      expect(analysis.comparableInWindow, 1);
      expect(crossModalityInterference(sessions: sessions, now: now), isNull);
    });

    test('S-2007(a) a 30% rise includes the second sentence', () {
      final analysis = analyseInterference(
        sessions: _f2007(now, prior: 100, recent: 130),
        now: now,
      );

      expect(analysis.sportsLoadRisePercent, 30);

      final result = crossModalityInterference(
        sessions: _f2007(now, prior: 100, recent: 130),
        now: now,
      );

      expect(result, isNotNull);
      expect(result!.hasSportsLoadRise, isTrue);
      expect(
        crossModalityInterferenceCopy(result).observation,
        endsWith('Sports load is up 30% over the last 3 weeks.'),
      );
    });

    test('S-2007(b) a 29% rise omits the second sentence', () {
      final analysis = analyseInterference(
        sessions: _f2007(now, prior: 100, recent: 129),
        now: now,
      );

      expect(analysis.sportsLoadRisePercent, isNull);

      final result = crossModalityInterference(
        sessions: _f2007(now, prior: 100, recent: 129),
        now: now,
      );

      expect(result, isNotNull);
      expect(result!.hasSportsLoadRise, isFalse);
      expect(
        crossModalityInterferenceCopy(result).observation,
        isNot(contains('Sports load is up')),
      );
    });

    test('S-2007(c) a zero prior span omits the second sentence', () {
      final analysis = analyseInterference(
        sessions: _f2007(now, prior: 0, recent: 500),
        now: now,
      );

      expect(analysis.sportsLoadRisePercent, isNull);
    });

    test('S-2008 the top-25% boundary is inclusive', () {
      final analysis = analyseInterference(sessions: _f2001(now), now: now);

      expect(
        analysis.hardSessionIds,
        containsAll(const ['sports-34', 'sports-28', 'sports-18', 'sports-8']),
      );
      expect(analysis.hardSessionIds, hasLength(4));
      expect(analysis.hardSessionIds, isNot(contains('sports-46')));

      final result = crossModalityInterference(
        sessions: _f2001(now),
        now: now,
      );

      expect(result, isNotNull);
      expect(result!.n, 4);
    });

    test('S-2008 nine sessions put the threshold on the seventh smallest', () {
      final analysis = analyseInterference(
        sessions: _s2008Nine(now),
        now: now,
      );

      expect(analysis.hardSessionIds, const ['nine-7', 'nine-8', 'nine-9']);
      expect(
        crossModalityInterference(sessions: _s2008Nine(now), now: now),
        isNull,
      );
    });

    test('a follow-up shared by two hard sessions counts once', () {
      final twoDistinct = analyseInterference(
        sessions: _sharedFollowUp(now, withThird: false),
        now: now,
      );

      expect(twoDistinct.followUpIdByHardId['hard-1'], 'follow-shared');
      expect(twoDistinct.followUpIdByHardId['hard-2'], 'follow-shared');
      expect(twoDistinct.followUpIdByHardId, hasLength(3));
      expect(twoDistinct.dippedFollowUpIds, hasLength(2));
      expect(twoDistinct.comparableInWindow, 2);
      expect(
        crossModalityInterference(
          sessions: _sharedFollowUp(now, withThird: false),
          now: now,
        ),
        isNull,
      );

      final threeDistinct = analyseInterference(
        sessions: _sharedFollowUp(now, withThird: true),
        now: now,
      );

      expect(threeDistinct.followUpIdByHardId, hasLength(4));
      expect(threeDistinct.dippedFollowUpIds, hasLength(3));
      expect(threeDistinct.comparableInWindow, 3);

      final result = crossModalityInterference(
        sessions: _sharedFollowUp(now, withThird: true),
        now: now,
      );

      expect(result, isNotNull);
      expect(result!.k, 3);
      expect(result.n, 3);
    });

    test('S-2009 unrated sports sessions are never hard and never counted', () {
      final sessions = [
        ..._f2001(now),
        _session(
          now: now,
          daysAgo: 86,
          id: 'unrated-86',
          sportsLoadMinutes: 0,
          seconds: 3600,
        ),
        _session(
          now: now,
          daysAgo: 84,
          id: 'unrated-84',
          sportsLoadMinutes: 0,
          seconds: 3600,
        ),
        _session(
          now: now,
          daysAgo: 82,
          id: 'unrated-82',
          sportsLoadMinutes: 0,
          seconds: 3600,
        ),
      ];

      final result = crossModalityInterference(sessions: sessions, now: now);

      expect(result, isNotNull);
      expect(result!.k, 3);
      expect(result.n, 4);
      expect(result.lo, 11);
      expect(result.hi, 16);
      expect(result.hasSportsLoadRise, isTrue);
    });

    test('S-2010(a) the 45-day lower bound is inclusive', () {
      final nowMs = now.millisecondsSinceEpoch;
      const day = 86400000;
      final sessions = _s2010(now, [
        _FollowUp('follow-45', nowMs - 45 * day),
        _FollowUp('follow-44', nowMs - 44 * day),
        _FollowUp('follow-43', nowMs - 43 * day),
      ]);

      final result = crossModalityInterference(sessions: sessions, now: now);

      expect(result, isNotNull);
      expect(result!.k, 3);
      expect(result.n, 3);
      expect(result.lo, 16);
      expect(result.hi, 16);
    });

    test('S-2010(b) a dip outside the window does not count', () {
      final nowMs = now.millisecondsSinceEpoch;
      const day = 86400000;
      final sessions = _s2010(now, [
        // `day(45) 00:00 − 1 ms`, ~20 h before the window's lower bound.
        _FollowUp('follow-out', _day(now, 45).millisecondsSinceEpoch - 1, 50.0),
        _FollowUp('follow-44', nowMs - 44 * day),
        _FollowUp('follow-43', nowMs - 43 * day),
        _FollowUp('follow-42', nowMs - 42 * day),
      ]);

      final analysis = analyseInterference(sessions: sessions, now: now);

      expect(analysis.shortfallMeanByFollowUpId, contains('follow-out'));
      expect(analysis.dippedFollowUpIds, isNot(contains('follow-out')));
      expect(analysis.dippedFollowUpIds, hasLength(3));
      expect(analysis.comparableInWindow, 3);

      final result = crossModalityInterference(sessions: sessions, now: now);

      expect(result, isNotNull);
      expect(result!.k, 3);
      expect(result.n, 3);
      expect(result.lo, 16);
      expect(result.hi, 16);
    });

    test('S-2015 the 90-day window bounds are exact', () {
      final nowMs = now.millisecondsSinceEpoch;
      final boundMs = nowMs - const Duration(days: 90).inMilliseconds;

      expect(
        crossModalityInterference(
          sessions: _s2015(now, earliestStartMs: boundMs),
          now: now,
        ),
        isNotNull,
      );

      final outside = _s2015(now, earliestStartMs: boundMs - 1);

      expect(
        analyseInterference(sessions: outside, now: now).hardSessionIds,
        isEmpty,
      );
      expect(
        crossModalityInterference(sessions: outside, now: now),
        isNull,
      );
    });

    test('no sessions abstains', () {
      expect(
        crossModalityInterference(sessions: const [], now: now),
        isNull,
      );
    });

    test('fewer than 8 rated sports sessions abstains', () {
      const removed = {
        'sports-88',
        'sports-80',
        'sports-70',
        'sports-60',
        'sports-55',
      };
      final sessions = _f2001(now)
          .where((s) => !removed.contains(s.id))
          .toList();

      expect(
        crossModalityInterference(sessions: sessions, now: now),
        isNull,
      );
    });

    test('no hard session abstains', () {
      final sessions = _f2001(now)
          .map(
            (s) => s.sportsLoadMinutes > 0
                ? InterferenceSession(
                    id: s.id,
                    startMs: s.startMs,
                    endMs: s.endMs,
                    rating: s.rating,
                    sportsLoadMinutes: 0,
                    hasSetEffort: s.hasSetEffort,
                    bests: s.bests,
                  )
                : s,
          )
          .toList();

      expect(
        crossModalityInterference(sessions: sessions, now: now),
        isNull,
      );
    });

    test('a hard session with no follow-up abstains', () {
      final sessions = _f2001(now)
          .where((s) => !s.id.startsWith('follow-'))
          .toList();

      expect(
        crossModalityInterference(sessions: sessions, now: now),
        isNull,
      );
    });

    test('a follow-up outside the 45-day window abstains', () {
      final sessions = _f2001(now)
          .map(
            (s) => s.id.startsWith('follow-')
                ? InterferenceSession(
                    id: s.id,
                    startMs: s.startMs - const Duration(days: 60).inMilliseconds,
                    endMs: s.endMs - const Duration(days: 60).inMilliseconds,
                    rating: s.rating,
                    sportsLoadMinutes: s.sportsLoadMinutes,
                    hasSetEffort: s.hasSetEffort,
                    bests: s.bests,
                  )
                : s,
          )
          .toList();

      expect(
        crossModalityInterference(sessions: sessions, now: now),
        isNull,
      );
    });
  });

  group('the constant contracts', () {
    test('the constants the docs name', () {
      expect(kInterferenceHardWindowDays, 90);
      expect(kInterferenceMinRatedSportsSessions, 8);
      expect(kInterferenceHardPercentile, 0.75);
      expect(kInterferenceFollowUpHours, 36);
      expect(kInterferenceDipWindowDays, 28);
      expect(kInterferenceMinDip, 0.10);
      expect(kInterferencePatternWindowDays, 45);
      expect(kInterferenceMinDippedFollowUps, 3);
      expect(kInterferenceSportsLoadWindowDays, 21);
      expect(kInterferenceSportsLoadRisePercent, 30);
      expect(kCrossModalityInterferencePriority, 500);
    });
  });

  group('the structural guards', () {
    test('the caution order holds and the registry is ordered by it', () {
      // The card's place is the top of the caution order (D-1315). A priority
      // at or below the Mix Shift's would put the two cautions in the wrong
      // order on the layer, and the registry's own order would stop matching
      // the priorities it is built from.
      expect(
        kCrossModalityInterferencePriority,
        greaterThan(kModalityMixShiftPriority),
      );

      final registry = buildSignalRegistry();
      final cautions = registry
          .where((s) => s.kind == SignalKind.caution)
          .toList();
      expect(cautions.map((s) => s.id), [
        'cardio-efficiency-drift',
        'sustained-high-load',
        'protein-consistency',
        'fuel-vs-load',
        'modality-mix-shift',
        'cross-modality-interference',
      ]);
      for (var i = 1; i < cautions.length; i++) {
        expect(
          cautions[i - 1].priority,
          lessThan(cautions[i].priority),
          reason: 'the registry lists cautions in ascending priority',
        );
      }
    });

    test('the hard rule counts no unrated session', () {
      // S-2009's fixture: three unrated sports sessions carrying the largest
      // raw work in the list. A rule that classified on raw work rather than
      // the rated population would make them hard and move the threshold.
      final sessions = [
        ..._f2001(now),
        for (final daysAgo in const [86, 84, 82])
          _session(
            now: now,
            daysAgo: daysAgo,
            id: 'unrated-$daysAgo',
            sportsLoadMinutes: 200,
            seconds: 3600,
          ),
      ];

      final analysis = analyseInterference(sessions: sessions, now: now);
      expect(analysis.hardSessionIds, [
        'sports-34',
        'sports-28',
        'sports-18',
        'sports-8',
      ]);
      for (final id in analysis.hardSessionIds) {
        expect(id.startsWith('unrated-'), isFalse);
      }

      final result = crossModalityInterference(sessions: sessions, now: now);
      expect(result, isNotNull);
      expect(result!.k, 3);
      expect(result.n, 4);
      expect(result.lo, 11);
      expect(result.hi, 16);
    });

    test('the dip test tolerates representation error and nothing more', () {
      // S-2004's fixture: a shortfall of exactly one tenth is
      // `1 - 0.9 = 0.09999999999999998` in binary floating point, so the
      // tolerance is what makes it dip. A wider tolerance would dip a
      // shortfall that is genuinely below the floor.
      final sessions = [
        ..._s2004Base(now),
        _s2004FollowUp(now, bests: const {'ex-lift': 90.0}),
      ];

      final analysis = analyseInterference(sessions: sessions, now: now);
      final mean = analysis.shortfallMeanByFollowUpId['follow'];
      expect(mean, isNotNull);
      expect(mean!, lessThanOrEqualTo(kInterferenceMinDip));
      expect(mean, greaterThan(kInterferenceMinDip - 1e-9));
      expect(analysis.dippedFollowUpIds, ['follow']);
    });

    test('the adapter walks no history and calls no PR API', () {
      // The signal is a thin adapter: it asks `StatsProgressService` for the
      // session payloads and hands them to the rule. A repository read, a
      // window-scoped walk or a personal-record call would be a second source
      // of the figures the Mix layer shows (D-1316, D-1319).
      const forbidden = <String>[
        'context.repository',
        'computeMixLayer',
        'computeMixPeriod',
        'computeTotals',
        'computeProgressData',
        'getAllSessions',
        'getSessionsByDateRange',
        'getSegmentsBySession',
        'getEffortsBySegment',
        'personalRecord',
        'PersonalRecord',
        'estimatedOneRepMax',
      ];
      final source = _strippedSource(
        'lib/core/services/signals/interference_signal.dart',
      );
      for (final identifier in forbidden) {
        expect(
          source.contains(identifier),
          isFalse,
          reason: 'the adapter must not walk history itself ("$identifier"); '
              'it calls interferenceSessions and nothing else (D-1316)',
        );
      }
      expect(source.contains('interferenceSessions'), isTrue);
    });

    test('the rule derives no percentage of its own', () {
      // The dip range and the rise are the rule's own rounded whole percents
      // (D-1311, D-1313); a second derivation in the adapter would be a second
      // definition of the same figure.
      final source = _strippedSource(
        'lib/core/services/signals/interference_signal.dart',
      );
      for (final identifier in const ['* 100', 'round(', 'toStringAsFixed']) {
        expect(
          source.contains(identifier),
          isFalse,
          reason: 'the adapter must not derive a percentage of its own '
              '("$identifier"); the rule reports them (D-1311)',
        );
      }
    });

    test('the rule reads no clock, no repository and no Flutter', () {
      final source = _strippedSource('lib/core/models/interference.dart');
      for (final identifier in const [
        'DateTime.now',
        'package:flutter',
        'WorkoutRepository',
      ]) {
        expect(
          source.contains(identifier),
          isFalse,
          reason: 'the rule is pure Dart ("$identifier"); `now` is a '
              'parameter (D-1301)',
        );
      }
    });

    test('the sports-load window is derived from its constant', () {
      // S-2301: the second sentence's span is `kInterferenceSportsLoadWindowDays`
      // alone (D-1601). A `3 weeks` literal is a second definition of the same
      // window and would keep rendering 3 weeks if the constant moved.
      final source = _strippedSource('lib/core/models/interference.dart');
      expect(
        source.contains('3 weeks'),
        isFalse,
        reason: 'the sports-load span must be derived from '
            'kInterferenceSportsLoadWindowDays, not written as a literal',
      );
      expect(
        source.contains('kInterferenceSportsLoadWindowDays ~/ 7'),
        isTrue,
        reason: 'the observation must interpolate the owning constant',
      );

      final result = crossModalityInterference(
        sessions: _f2007(now, prior: 100, recent: 130),
        now: now,
      );
      expect(result, isNotNull);
      expect(
        crossModalityInterferenceCopy(result!).observation,
        contains('over the last 3 weeks.'),
      );
    });
  });
}
