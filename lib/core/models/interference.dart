// Stats PR 7b — the Cross-Modality Interference rule and its copy.
//
// The rule reads a list of session payloads the service walked and re-derives
// nothing: the hard boundary is a nearest-rank percentile on the payloads' own
// Sports loads, the dip is a per-exercise comparison against that exercise's
// own recent bests, and the copy reads the rule's own counts. There is no
// clock here, no repository and no Flutter — the caller passes `now`.

/// The hard window, an exact duration back from `now` (D-1302, D-1321). Both
/// ends inclusive.
const int kInterferenceHardWindowDays = 90;

/// The smallest rated-sports-session population that can classify anything
/// (D-1302). Below it the signal abstains.
const int kInterferenceMinRatedSportsSessions = 8;

/// The nearest-rank percentile that separates hard sessions from the rest
/// (D-1303). The boundary is inclusive.
const double kInterferenceHardPercentile = 0.75;

/// How long after a hard session's end a follow-up may start (D-1304). The
/// upper bound is inclusive.
const int kInterferenceFollowUpHours = 36;

/// The lookback a follow-up's comparable exercises are averaged over (D-1305).
/// The lower bound is inclusive and the upper exclusive.
const int kInterferenceDipWindowDays = 28;

/// The mean shortfall at which a follow-up dips (D-1307). The boundary is
/// inclusive, with the tolerance D-1308 describes.
const double kInterferenceMinDip = 0.10;

/// The window the pattern is counted over (D-1309). Both ends inclusive.
const int kInterferencePatternWindowDays = 45;

/// How many dipped follow-ups the pattern needs (D-1309).
const int kInterferenceMinDippedFollowUps = 3;

/// The recent span the optional second sentence compares (D-1313).
const int kInterferenceSportsLoadWindowDays = 21;

/// The rise the optional second sentence needs (D-1313). The boundary is
/// inclusive.
const int kInterferenceSportsLoadRisePercent = 30;

/// The signal's priority, the highest among cautions (D-1315).
const int kCrossModalityInterferencePriority = 500;

/// One session as the rule sees it (D-1316).
///
/// [sportsLoadMinutes] is the session's Sports component in load minutes — 0
/// when the session is unrated or holds no sports work. [hasSetEffort] is true
/// when the session contains at least one effort whose section maps to
/// Resistance. [bests] holds the per-exercise bests above zero, keyed by
/// exercise id.
class InterferenceSession {
  const InterferenceSession({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.rating,
    required this.sportsLoadMinutes,
    required this.hasSetEffort,
    required this.bests,
  });

  final String id;
  final int startMs;
  final int endMs;
  final int? rating;
  final double sportsLoadMinutes;
  final bool hasSetEffort;
  final Map<String, double> bests;
}

/// The pattern the rule reports, or null when it abstains (D-1309).
///
/// [k] is the number of dipped follow-ups in the pattern window, [n] the number
/// of hard sessions whose follow-up is comparable and in the window, and [lo]
/// and [hi] the smallest and largest counted mean shortfalls as whole percents.
/// [hasSportsLoadRise] is true when the optional second sentence applies, and
/// [sportsLoadRisePercent] is the rounded rise it reports.
class Interference {
  const Interference({
    required this.k,
    required this.n,
    required this.lo,
    required this.hi,
    required this.hasSportsLoadRise,
    required this.sportsLoadRisePercent,
  });

  final int k;
  final int n;
  final int lo;
  final int hi;
  final bool hasSportsLoadRise;
  final int sportsLoadRisePercent;
}

/// The card's copy: the observation and the suggestion.
class InterferenceCopy {
  const InterferenceCopy({
    required this.observation,
    required this.suggestion,
  });

  final String observation;
  final String suggestion;
}

/// The rule's stages over a session list, exposed so follow-up detection and
/// the per-follow-up dips can be observed directly (D-1304–D-1313).
///
/// [hardSessionIds] are the hard sessions (D-1303) in session-list order.
/// [followUpIdByHardId] maps a hard session's id to its follow-up's id (D-1304);
/// a hard session with no follow-up is absent. [shortfallMeanByFollowUpId] maps
/// a follow-up's id to the unweighted mean shortfall over its comparable
/// exercises (D-1305, D-1307); a follow-up with no comparable exercise is
/// absent. [dippedFollowUpIds] are the follow-ups inside the pattern window
/// whose mean shortfall reaches [kInterferenceMinDip] within D-1308's tolerance.
/// [comparableInWindow] is D-1310's `n`. [sportsLoadRisePercent] is D-1313's
/// rounded rise, or null when the second sentence is omitted.
class InterferenceAnalysis {
  const InterferenceAnalysis({
    required this.hardSessionIds,
    required this.followUpIdByHardId,
    required this.shortfallMeanByFollowUpId,
    required this.dippedFollowUpIds,
    required this.comparableInWindow,
    required this.sportsLoadRisePercent,
  });

  final List<String> hardSessionIds;
  final Map<String, String> followUpIdByHardId;
  final Map<String, double> shortfallMeanByFollowUpId;
  final List<String> dippedFollowUpIds;
  final int comparableInWindow;
  final int? sportsLoadRisePercent;
}

/// The rule's stages over [sessions] at [now] (D-1301–D-1313).
///
/// A session is a sports session when its Sports load is above zero (D-1301).
/// The population is the rated sports sessions starting in
/// `[now − kInterferenceHardWindowDays, now]`, both ends inclusive; with fewer
/// than [kInterferenceMinRatedSportsSessions] of them nothing is hard and every
/// collection is empty with [InterferenceAnalysis.comparableInWindow] 0 and
/// [InterferenceAnalysis.sportsLoadRisePercent] null (D-1302). Sorting the
/// population's loads ascending, the threshold is
/// `sorted[(kInterferenceHardPercentile × n).ceil() − 1]` and a session is hard
/// when its load is at least the threshold (D-1303).
///
/// A hard session's follow-up is the earliest session that holds a set effort
/// and starts in `(endMs, endMs + kInterferenceFollowUpHours]`, ties by id
/// ascending (D-1304). A follow-up's exercise is comparable when its best there
/// is above zero and it has a qualifying prior session in
/// `[followUpStart − kInterferenceDipWindowDays, followUpStart)` with a best
/// above zero; the prior average excludes every follow-up this evaluation
/// identified (D-1305, D-1306). A follow-up dips when the unweighted mean of its
/// comparable shortfalls `(average − best) / average` is at least
/// [kInterferenceMinDip], within the tolerance D-1308 describes (D-1307).
InterferenceAnalysis analyseInterference({
  required List<InterferenceSession> sessions,
  required DateTime now,
}) {
  final nowMs = now.millisecondsSinceEpoch;
  final hardWindowStartMs =
      nowMs - Duration(days: kInterferenceHardWindowDays).inMilliseconds;
  final patternWindowStartMs =
      nowMs - Duration(days: kInterferencePatternWindowDays).inMilliseconds;
  final dipWindowMs =
      Duration(days: kInterferenceDipWindowDays).inMilliseconds;
  final followUpWindowMs =
      Duration(hours: kInterferenceFollowUpHours).inMilliseconds;

  // D-1302: the rated sports sessions in the hard window, both ends inclusive.
  final population = sessions
      .where(
        (s) =>
            s.rating != null &&
            s.sportsLoadMinutes > 0 &&
            s.startMs >= hardWindowStartMs &&
            s.startMs <= nowMs,
      )
      .toList();
  if (population.length < kInterferenceMinRatedSportsSessions) {
    return const InterferenceAnalysis(
      hardSessionIds: [],
      followUpIdByHardId: {},
      shortfallMeanByFollowUpId: {},
      dippedFollowUpIds: [],
      comparableInWindow: 0,
      sportsLoadRisePercent: null,
    );
  }

  // D-1303: nearest-rank threshold, inclusive.
  final sortedLoads = population.map((s) => s.sportsLoadMinutes).toList()
    ..sort();
  final rank = (kInterferenceHardPercentile * sortedLoads.length).ceil();
  final threshold = sortedLoads[rank - 1];
  final hard = population
      .where((s) => s.sportsLoadMinutes >= threshold)
      .toList();

  // D-1304: each hard session's follow-up, the earliest qualifying session.
  final followUpIdByHardId = <String, String>{};
  final followUps = <InterferenceSession>[];
  for (final session in hard) {
    final upperMs = session.endMs + followUpWindowMs;
    InterferenceSession? followUp;
    for (final candidate in sessions) {
      if (!candidate.hasSetEffort) continue;
      if (candidate.startMs <= session.endMs) continue;
      if (candidate.startMs > upperMs) continue;
      if (followUp == null ||
          candidate.startMs < followUp.startMs ||
          (candidate.startMs == followUp.startMs &&
              candidate.id.compareTo(followUp.id) < 0)) {
        followUp = candidate;
      }
    }
    if (followUp != null) {
      followUpIdByHardId[session.id] = followUp.id;
      followUps.add(followUp);
    }
  }

  // D-1306: every follow-up is excluded from every prior average.
  final followUpById = <String, InterferenceSession>{
    for (final followUp in followUps) followUp.id: followUp,
  };
  // D-1309, D-1310: a follow-up shared by two hard sessions counts once, so
  // `k` and `n` are distinct follow-up sessions, not hard sessions.
  final countedFollowUpIds = followUps.map((s) => s.id).toSet();

  // D-1305, D-1307: the comparable exercises' unweighted mean shortfall.
  final shortfallMeanByFollowUpId = <String, double>{};
  for (final followUpId in countedFollowUpIds) {
    final followUp = followUpById[followUpId]!;
    final shortfalls = <double>[];
    for (final entry in followUp.bests.entries) {
      final best = entry.value;
      if (best <= 0) continue;

      final priors = <double>[];
      for (final session in sessions) {
        if (countedFollowUpIds.contains(session.id)) continue;
        if (session.startMs < followUp.startMs - dipWindowMs) continue;
        if (session.startMs >= followUp.startMs) continue;
        final priorBest = session.bests[entry.key];
        if (priorBest == null || priorBest <= 0) continue;
        priors.add(priorBest);
      }
      if (priors.isEmpty) continue;

      final average = priors.reduce((a, b) => a + b) / priors.length;
      if (average <= 0) continue;
      shortfalls.add((average - best) / average);
    }
    if (shortfalls.isEmpty) continue;
    shortfallMeanByFollowUpId[followUpId] =
        shortfalls.reduce((a, b) => a + b) / shortfalls.length;
  }

  // D-1307, D-1308, D-1309: the pattern window, both ends inclusive, and the
  // tolerance that lets a shortfall of exactly one tenth dip.
  final dippedFollowUpIds = <String>[];
  for (final followUpId in countedFollowUpIds) {
    final followUp = followUpById[followUpId]!;
    if (followUp.startMs < patternWindowStartMs) continue;
    if (followUp.startMs > nowMs) continue;
    final mean = shortfallMeanByFollowUpId[followUpId];
    if (mean == null) continue;
    if (mean >= kInterferenceMinDip - 1e-9) {
      dippedFollowUpIds.add(followUpId);
    }
  }

  // D-1310: `n` counts every comparable follow-up in the window, dipped or not.
  final comparableInWindow = countedFollowUpIds
      .where((id) {
        final followUp = followUpById[id]!;
        return followUp.startMs >= patternWindowStartMs &&
            followUp.startMs <= nowMs &&
            shortfallMeanByFollowUpId.containsKey(id);
      })
      .length;

  return InterferenceAnalysis(
    hardSessionIds: hard.map((s) => s.id).toList(),
    followUpIdByHardId: followUpIdByHardId,
    shortfallMeanByFollowUpId: shortfallMeanByFollowUpId,
    dippedFollowUpIds: dippedFollowUpIds,
    comparableInWindow: comparableInWindow,
    sportsLoadRisePercent: _sportsLoadRise(sessions: sessions, nowMs: nowMs),
  );
}

/// The interference pattern in [sessions], or null when the rule abstains
/// (D-1301–D-1313).
///
/// [analyseInterference] carries the stages; this applies D-1309's floor and
/// builds the reported counts and range (D-1310, D-1311).
Interference? crossModalityInterference({
  required List<InterferenceSession> sessions,
  required DateTime now,
}) {
  final analysis = analyseInterference(sessions: sessions, now: now);

  // D-1309: the pattern floor.
  if (analysis.dippedFollowUpIds.length < kInterferenceMinDippedFollowUps) {
    return null;
  }

  // D-1311: the range over the counted follow-ups only.
  final percents = analysis.dippedFollowUpIds
      .map((id) => (analysis.shortfallMeanByFollowUpId[id]! * 100).round())
      .toList();
  final lo = percents.reduce((a, b) => a < b ? a : b);
  final hi = percents.reduce((a, b) => a > b ? a : b);
  final rise = analysis.sportsLoadRisePercent;

  return Interference(
    k: analysis.dippedFollowUpIds.length,
    n: analysis.comparableInWindow,
    lo: lo,
    hi: hi,
    hasSportsLoadRise: rise != null,
    sportsLoadRisePercent: rise ?? 0,
  );
}

/// The rounded rise the second sentence reports, or null when it is omitted
/// (D-1313).
int? _sportsLoadRise({
  required List<InterferenceSession> sessions,
  required int nowMs,
}) {
  final windowMs =
      Duration(days: kInterferenceSportsLoadWindowDays).inMilliseconds;
  final recentStartMs = nowMs - windowMs;
  final priorStartMs = nowMs - 2 * windowMs;

  var recent = 0.0;
  var prior = 0.0;
  for (final session in sessions) {
    if (session.startMs >= recentStartMs && session.startMs <= nowMs) {
      recent += session.sportsLoadMinutes;
    } else if (session.startMs >= priorStartMs &&
        session.startMs < recentStartMs) {
      prior += session.sportsLoadMinutes;
    }
  }

  if (prior <= 0) return null;
  if (100 * recent < (100 + kInterferenceSportsLoadRisePercent) * prior) {
    return null;
  }
  return ((recent / prior - 1) * 100).round();
}

/// The card's copy for [result] (D-1312–D-1314).
InterferenceCopy crossModalityInterferenceCopy(Interference result) {
  final range = result.lo == result.hi
      ? '${result.lo}%'
      : '${result.lo}\u2013${result.hi}%';
  final observation = StringBuffer(
    'After ${result.k} of your last ${result.n} hard sports sessions, your '
    'next lifting day came in $range below your usual on the same lifts.',
  );
  if (result.hasSportsLoadRise) {
    observation.write(
      ' Sports load is up ${result.sportsLoadRisePercent}% over the last '
      '3 weeks.',
    );
  }
  return InterferenceCopy(
    observation: observation.toString(),
    suggestion:
        'A lighter or isometric-focused day after hard sports sessions is one '
        'option.',
  );
}
