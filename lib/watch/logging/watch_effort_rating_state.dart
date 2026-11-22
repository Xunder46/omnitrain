/// The effort-rating prompt's logic on the Wear wrist: the End that may owe a
/// rating, the question, and the single answer it records (plan 284, series
/// 283 unit b). Mirrors the Apple client's `WatchEffortRating.swift`.
///
/// Everything here is state; the prompt screen (283c) only binds to it. The
/// rotary mapping is the screen's job: it hands this class whole detents.
///
/// Once owed, the prompt has two ways out: an answer, or Skip, which records
/// nothing. Nothing here puts it off in any other way.
library;

import 'package:flutter/foundation.dart';

import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_session_store.dart';
import '../start/watch_phone_preferences.dart';

/// The question, its scale and the words at its two ends, as
/// `watch/contract/watch_effort_rating_contract.json` states them. A test holds
/// these values to the contract file.
abstract final class WatchEffortRatingCopy {
  static const String title = 'How hard was this session?';
  static const int lowest = 1;
  static const int highest = 5;
  static const String lowestLabel = 'Very easy';
  static const String highestLabel = 'Max effort';

  /// Wrist-only copy for closing the question without an answer. Not in the
  /// contract file: the phone's sheet does not offer it.
  static const String skipLabel = 'Skip';

  /// A wrist that has never received the phone's preferences does not ask.
  static const bool promptBeforeFirstSync = false;
}

/// The End control and the effort-rating prompt, as state a screen binds to.
class WatchEffortRatingState extends ChangeNotifier {
  WatchEffortRatingState({
    required this.engine,
    required WatchSessionStore store,
    required WatchPhonePreferences preferences,
    DateTime Function()? clock,
  }) : _store = store,
       _preferences = preferences,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final WatchSessionEngine engine;
  final WatchSessionStore _store;
  final WatchPhonePreferences _preferences;
  final DateTime Function() _clock;

  /// The prompts the wrist's End has owed, oldest first.
  final List<WatchRatingPromptRecord> _prompts = [];

  /// The owed sessions the user closed without an answer. Nothing is recorded
  /// for them; remembered only while the app runs.
  final Set<String> _declinedSessionIds = {};

  int? _selected;

  /// The number the user has picked, or null while nothing is: nothing is
  /// preselected.
  int? get selected => _selected;

  /// Reads the owed prompts back out of storage. Call on launch, after the
  /// engine has restored.
  Future<void> restore() async {
    final contents = await _store.readAll();
    _prompts
      ..clear()
      ..addAll(contents.ratingPrompts);
    notifyListeners();
  }

  // The End control ----------------------------------------------------------

  /// The wrist's own End: finishes the session and, when a rating is owed,
  /// records that it is. Null when there is no active session to finish.
  ///
  /// Owed means the phone's setting, as last synced, asks for it; the session
  /// holds at least one effort entry after the phone's deletions; and it has no
  /// rating yet. That is decided before the session ends, because the phone's
  /// deletions are known only to this process, which is also why the answer is
  /// stored rather than recomputed at the next launch.
  Future<WatchSessionRecord?> end() async {
    final session = engine.session;
    if (session == null || session.status != WatchSessionStatus.active) {
      return null;
    }
    final owed = _isRatingOwed(session.sessionId);

    final ended = await engine.finishSession();
    if (owed) await _noteOwedPrompt(session.sessionId);
    notifyListeners();
    return ended;
  }

  bool _isRatingOwed(String sessionId) =>
      _preferences.asksForEffortRating &&
      engine.entries.any(
        (entry) => WatchObservationKind.efforts.contains(entry.kind),
      ) &&
      !engine.hasEffortRating(sessionId);

  Future<void> _noteOwedPrompt(String sessionId) async {
    final stored = await _store.append(
      WatchRatingPromptRecord(
        recordId: WatchRatingPromptRecord.recordIdFor(sessionId),
        sessionId: sessionId,
        recordedAt: _clock(),
      ),
    );
    if (!_prompts.any((prompt) => prompt.recordId == stored.recordId)) {
      _prompts.add(stored);
    }
  }

  // The prompt ---------------------------------------------------------------

  /// The sessions that owe an answer, most recent first: every owed prompt whose
  /// session has no rating yet (kept, acknowledged, or carried by the phone) and
  /// was not skipped.
  List<String> get owedSessionIds {
    final owed = [
      for (final prompt in _prompts)
        if (!engine.hasEffortRating(prompt.sessionId) &&
            !_declinedSessionIds.contains(prompt.sessionId))
          prompt,
    ]..sort((a, b) => b.sequence.compareTo(a.sequence));
    return [for (final prompt in owed) prompt.sessionId];
  }

  /// The session the prompt is asking about, or null when nothing is owed.
  String? get promptSessionId {
    final owed = owedSessionIds;
    return owed.isEmpty ? null : owed.first;
  }

  bool get isPromptOwed => promptSessionId != null;

  String get title => WatchEffortRatingCopy.title;

  List<int> get scale => [
    for (
      var value = WatchEffortRatingCopy.lowest;
      value <= WatchEffortRatingCopy.highest;
      value++
    )
      value,
  ];

  String get lowestLabel => WatchEffortRatingCopy.lowestLabel;

  String get highestLabel => WatchEffortRatingCopy.highestLabel;

  /// Confirm is enabled only once a number is picked, and only while a prompt is
  /// owed.
  bool get canConfirm => isPromptOwed && _selected != null;

  /// [detents] rotary steps. From nothing picked, the first step up picks the
  /// lowest number; further steps move one number each and stop at either end.
  /// Stepping down never returns to nothing picked, and from nothing picked it
  /// picks nothing.
  void step(int detents) {
    if (detents == 0) return;
    const lowest = WatchEffortRatingCopy.lowest;
    const highest = WatchEffortRatingCopy.highest;

    final current = _selected;
    if (current != null) {
      _selected = (current + detents).clamp(lowest, highest).toInt();
    } else if (detents > 0) {
      _selected = (lowest + detents - 1).clamp(lowest, highest).toInt();
    } else {
      return;
    }
    notifyListeners();
  }

  /// A tap on a number of the scale; a number outside it changes nothing.
  void select(int value) {
    if (value < WatchEffortRatingCopy.lowest ||
        value > WatchEffortRatingCopy.highest) {
      return;
    }
    _selected = value;
    notifyListeners();
  }

  /// Closes the owed question without an answer. Nothing is recorded: the
  /// session stays unrated, so the phone's own question and the first real
  /// answer are untouched. Remembered only while the app runs.
  void skipPrompt() {
    final sessionId = promptSessionId;
    if (sessionId == null) return;
    _declinedSessionIds.add(sessionId);
    _selected = null;
    notifyListeners();
  }

  /// Records the picked number as the owed session's effort rating, through the
  /// engine's append path, and returns it; or null, recording nothing, when
  /// nothing is picked or nothing is owed. The session then owes nothing more:
  /// a rating is never edited and never added twice.
  Future<WatchObservationRecord?> confirm() async {
    final sessionId = promptSessionId;
    final rating = _selected;
    if (sessionId == null || rating == null) return null;

    final recorded = await engine.recordEffortRating(
      rating,
      sessionId: sessionId,
    );
    _selected = null;
    notifyListeners();
    return recorded;
  }
}
