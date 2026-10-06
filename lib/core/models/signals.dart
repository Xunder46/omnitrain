import 'dart:convert';

import 'training_load.dart';

/// The two kinds of signal a card can carry (D-1002).
enum SignalKind { positive, caution }

/// The kind label for a positive card (D-1001).
const String kSignalPositiveLabel = 'Positive';

/// The kind label for a caution card (D-1001).
const String kSignalCautionLabel = 'Worth a look';

/// The most cards the layer ever shows at once (D-1004).
const int kSignalMaxCards = 2;

/// How many local calendar days a dismissal hides its signal (D-1011).
const int kSignalDismissalDays = 14;

/// The repository preference key holding the dismissal store (D-1009).
const String kSignalDismissalsKey = 'signal_dismissals';

/// The line shown when the gate is met and no card qualifies (D-1007).
const String kSignalQuietLine = 'No signals — nothing outside your usual range.';

/// The label a card of [kind] carries. Kind is carried by the label and the
/// icon, never by a colour (D-1002).
String signalKindLabel(SignalKind kind) => switch (kind) {
  SignalKind.positive => kSignalPositiveLabel,
  SignalKind.caution => kSignalCautionLabel,
};

/// One signal's proposal for a card, before the framework selects and orders
/// what is actually shown (D-1001).
///
/// [title] is not rendered: it names the card for its key, its semantic label
/// and the dismissal store. [suggestion] is rendered only when non-null.
class SignalCard {
  final String id;
  final SignalKind kind;
  final int priority;
  final String title;
  final String observation;
  final String? suggestion;

  const SignalCard({
    required this.id,
    required this.kind,
    required this.priority,
    required this.title,
    required this.observation,
    this.suggestion,
  });
}

/// What the layer renders for one load (D-1003, D-1007).
///
/// An empty [cards] with [showQuietLine] true is the "nothing to say" state;
/// an empty [cards] with [showQuietLine] false means the gate is unmet and the
/// layer renders nothing at all.
class SignalsData {
  final List<SignalCard> cards;
  final bool showQuietLine;

  const SignalsData({required this.cards, required this.showQuietLine});
}

/// Whether signals render at all (D-1006).
///
/// The gate reads `ratedBaselineWeeks` only — it does not additionally require
/// a load measure.
bool signalsGateMet(MixLayerData? mix) =>
    mix != null && mix.ratedBaselineWeeks >= kTrainingLoadMinRatedWeeks;

/// Whether the signal dismissed at [dismissedAtMs] is still hidden at [now]
/// (D-1011, D-1012).
///
/// The dismissal day is day 1: hidden on days 1–14, eligible again on day 15.
/// The age is a whole number of local calendar days, computed on the dates
/// re-read as UTC so a daylight-saving transition inside the window neither
/// adds nor removes a day — the same arithmetic
/// `StatsProgressService.previousRangeFor` uses.
bool isSignalDismissed({required int dismissedAtMs, required DateTime now}) {
  final dismissedDay = localMidnightDay(
    DateTime.fromMillisecondsSinceEpoch(dismissedAtMs),
  );
  final today = localMidnightDay(now);
  final ageDays =
      DateTime.utc(
        today.year,
        today.month,
        today.day,
      ).difference(
        DateTime.utc(dismissedDay.year, dismissedDay.month, dismissedDay.day),
      ).inDays;
  return ageDays >= 0 && ageDays < kSignalDismissalDays;
}

/// The store after dismissing [id] at [now] (D-1010, D-1013).
///
/// Returns a NEW map holding the entries of [current] that [isSignalDismissed]
/// still reports hidden at [now], plus `id -> now` — the exact pruning rule a
/// write applies, kept pure so the screen can move its view before the write.
/// [current] is never mutated.
Map<String, int> signalDismissalsWith(
  Map<String, int> current,
  String id,
  DateTime now,
) {
  final next = <String, int>{};
  current.forEach((key, dismissedAtMs) {
    if (isSignalDismissed(dismissedAtMs: dismissedAtMs, now: now)) {
      next[key] = dismissedAtMs;
    }
  });
  next[id] = now.millisecondsSinceEpoch;
  return next;
}

/// Reads the dismissal store out of its stored JSON (D-1009).
///
/// A missing value, an unparseable value, a non-object value and a non-integer
/// entry all read as "no dismissal"; this never throws.
Map<String, int> parseSignalDismissals(String? raw) {
  if (raw == null || raw.isEmpty) return <String, int>{};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return <String, int>{};
  }
  if (decoded is! Map) return <String, int>{};
  final out = <String, int>{};
  decoded.forEach((key, value) {
    if (key is String && value is int) out[key] = value;
  });
  return out;
}

/// Serialises the dismissal store for the preference API (D-1009).
String encodeSignalDismissals(Map<String, int> dismissals) =>
    jsonEncode(dismissals);

/// Resolves the candidates of one load into what the layer shows (D-1004,
/// D-1005, D-1007, D-1008).
///
/// Dismissed candidates are dropped. When both kinds survive, the answer is the
/// highest-priority caution followed by the highest-priority positive; when
/// only one kind survives, it is the top [kSignalMaxCards] of that kind.
/// Within a kind, higher priority wins and an exact tie is broken by id
/// ascending, so selection is deterministic.
SignalsData resolveSignals({
  required List<SignalCard> candidates,
  required Map<String, int> dismissedAtMs,
  required DateTime now,
  required bool gateMet,
}) {
  if (!gateMet) {
    return const SignalsData(cards: [], showQuietLine: false);
  }
  final live = candidates.where((card) {
    final dismissedAt = dismissedAtMs[card.id];
    return dismissedAt == null ||
        !isSignalDismissed(dismissedAtMs: dismissedAt, now: now);
  });

  List<SignalCard> rankedOf(SignalKind kind) =>
      live.where((card) => card.kind == kind).toList()
        ..sort((a, b) {
          final byPriority = b.priority.compareTo(a.priority);
          return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
        });

  final cautions = rankedOf(SignalKind.caution);
  final positives = rankedOf(SignalKind.positive);
  final List<SignalCard> cards;
  if (cautions.isNotEmpty && positives.isNotEmpty) {
    cards = [cautions.first, positives.first];
  } else {
    final surviving = cautions.isNotEmpty ? cautions : positives;
    cards = surviving.take(kSignalMaxCards).toList(growable: false);
  }
  return SignalsData(cards: cards, showQuietLine: cards.isEmpty);
}
