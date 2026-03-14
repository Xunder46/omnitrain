import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../../core/utils/date_utils.dart';

const _uuid = Uuid();

/// A lightweight union type representing either a [TrainingSession] or a
/// [PlannedSession] for calendar display purposes.
class CalendarEntry {
  /// Epoch-ms of the day this entry belongs to (start-of-day midnight).
  final int dayMs;

  /// Modality key (may be null for Free Training).
  final String? modality;

  /// True = filled circle (completed / finished session).
  /// False = outlined circle (planned session not yet done).
  final bool isCompleted;

  /// The underlying completed [TrainingSession], if any.
  final TrainingSession? session;

  /// The underlying [PlannedSession], if any.
  final PlannedSession? plannedSession;

  CalendarEntry._({
    required this.dayMs,
    required this.modality,
    required this.isCompleted,
    this.session,
    this.plannedSession,
  });

  factory CalendarEntry.fromSession(TrainingSession s) => CalendarEntry._(
    dayMs: OmniDateUtils.startOfDayMs(OmniDateUtils.fromMs(s.startedAtMs)),
    modality: s.modality,
    isCompleted: s.endedAtMs != null,
    session: s,
  );

  factory CalendarEntry.fromPlannedSession(PlannedSession p) => CalendarEntry._(
    dayMs: OmniDateUtils.startOfDayMs(OmniDateUtils.fromMs(p.scheduledDateMs)),
    modality: p.modality,
    isCompleted: p.isCompleted,
    plannedSession: p,
  );
}

/// State holder for calendar view.
///
/// Manages the currently displayed month, loads [TrainingSession] and
/// [PlannedSession] entries within that month, groups them by day for
/// indicator rendering, and provides routing decisions for day-tap events.
class CalendarState extends ChangeNotifier {
  final WorkoutRepository _repository;

  CalendarState(this._repository);

  // ─── Current month ────────────────────────────────────────────────────────

  late int _year;
  late int _month;

  int get year => _year;
  int get month => _month;

  // ─── Entries ──────────────────────────────────────────────────────────────

  /// Entries grouped by dayMs (start-of-day).
  Map<int, List<CalendarEntry>> _entriesByDay = {};

  Map<int, List<CalendarEntry>> get entriesByDay =>
      Map.unmodifiable(_entriesByDay);

  // ─── Loading ──────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── Initialization ───────────────────────────────────────────────────────

  /// Initialize to the current local month and load entries.
  Future<void> init() async {
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    await _loadMonth();
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  Future<void> goToPreviousMonth() async {
    if (_month == 1) {
      _year -= 1;
      _month = 12;
    } else {
      _month -= 1;
    }
    await _loadMonth();
  }

  Future<void> goToNextMonth() async {
    if (_month == 12) {
      _year += 1;
      _month = 1;
    } else {
      _month += 1;
    }
    await _loadMonth();
  }

  // ─── Loading ──────────────────────────────────────────────────────────────

  Future<void> _loadMonth() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fromMs = DateTime(_year, _month, 1).millisecondsSinceEpoch;
      final lastDay = DateTime(_year, _month + 1, 0);
      final toMs = OmniDateUtils.endOfDayMs(lastDay);

      // Load both completed sessions and planned sessions in parallel.
      final results = await Future.wait([
        _repository.getSessionsByDateRange(fromMs, toMs),
        _repository.getPlannedSessionsForDateRange(fromMs, toMs),
      ]);

      final sessions = results[0] as List<TrainingSession>;
      final plannedSessions = results[1] as List<PlannedSession>;
      final completedSessions = sessions
          .where((s) => s.endedAtMs != null)
          .toList();

      final entries = <CalendarEntry>[
        ...completedSessions.map(CalendarEntry.fromSession),
        ...plannedSessions.map(CalendarEntry.fromPlannedSession),
      ];

      // Sort ascending by day.
      entries.sort((a, b) => a.dayMs.compareTo(b.dayMs));

      _entriesByDay = {};
      for (final e in entries) {
        _entriesByDay.putIfAbsent(e.dayMs, () => []).add(e);
      }

      // Load periods for calendar highlights and compute streak.
      await Future.wait([_loadPeriods(), _computeStreak()]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns entries for a specific day (by its start-of-day epoch-ms).
  List<CalendarEntry> entriesForDay(DateTime day) {
    final key = OmniDateUtils.startOfDayMs(day);
    return _entriesByDay[key] ?? [];
  }

  /// Reload the current month (e.g. after CRUD operations on planned sessions).
  Future<void> refresh() => _loadMonth();

  // ─── Planned session CRUD ─────────────────────────────────────────────────

  /// Creates a new planned session for [date] and refreshes the month view.
  Future<void> createPlannedSession({
    required DateTime date,
    String? modality,
    String? routineTemplateId,
    String? title,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = PlannedSession(
      id: _uuid.v4(),
      ownerUserId: 'user-1',
      scheduledDateMs: OmniDateUtils.startOfDayMs(date),
      modality: modality,
      routineTemplateId: routineTemplateId,
      title: title,
      note: note,
      isCompleted: false,
      createdAtMs: now,
      updatedAtMs: now,
    );
    await _repository.createPlannedSession(session);
    await _loadMonth();
  }

  /// Updates an existing planned session and refreshes the month view.
  Future<void> updatePlannedSession(PlannedSession updated) async {
    await _repository.updatePlannedSession(updated);
    await _loadMonth();
  }

  /// Deletes a planned session by ID and refreshes the month view.
  Future<void> deletePlannedSession(String id) async {
    await _repository.deletePlannedSession(id);
    await _loadMonth();
  }

  /// Marks a planned session as completed and links it to a training session.
  /// Useful when a workout session is finished and needs to be connected to
  /// its originating planned session.
  Future<void> completePlannedSession(
    String plannedSessionId,
    String linkedSessionId,
  ) async {
    // Fetch all planned sessions and find the one to update.
    // If the planned row was deleted mid-workout, treat completion linking
    // as a safe no-op and avoid recreating/throwing.
    final all = await _repository.getPlannedSessions();
    PlannedSession? ps;
    for (final session in all) {
      if (session.id == plannedSessionId) {
        ps = session;
        break;
      }
    }
    if (ps == null) {
      await _loadMonth();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = PlannedSession(
      id: ps.id,
      ownerUserId: ps.ownerUserId,
      scheduledDateMs: ps.scheduledDateMs,
      modality: ps.modality,
      routineTemplateId: ps.routineTemplateId,
      title: ps.title,
      note: ps.note,
      isCompleted: true,
      linkedSessionId: linkedSessionId,
      recurrenceRule: ps.recurrenceRule,
      createdAtMs: ps.createdAtMs,
      updatedAtMs: now,
    );
    await _repository.updatePlannedSession(updated);
    await _loadMonth();
  }

  // ─── Monthly stats (derived from _entriesByDay) ──────────────────────────

  /// Count of completed sessions for the loaded month.
  int get completedSessionCount {
    int count = 0;
    for (final entries in _entriesByDay.values) {
      for (final e in entries) {
        if (e.isCompleted) count++;
      }
    }
    return count;
  }

  /// Total training time (ms) for completed sessions in the loaded month.
  int get totalTrainingMs {
    int total = 0;
    for (final entries in _entriesByDay.values) {
      for (final e in entries) {
        if (e.isCompleted &&
            e.session != null &&
            e.session!.endedAtMs != null) {
          total += e.session!.endedAtMs! - e.session!.startedAtMs;
        }
      }
    }
    return total;
  }

  /// Count of completed sessions grouped by modality for the loaded month.
  /// Null key = Free Training.
  Map<String?, int> get modalityBreakdown {
    final result = <String?, int>{};
    for (final entries in _entriesByDay.values) {
      for (final e in entries) {
        if (e.isCompleted) {
          result[e.modality] = (result[e.modality] ?? 0) + 1;
        }
      }
    }
    return result;
  }

  // ─── Streak ───────────────────────────────────────────────────────────────

  int _streakDays = 0;
  int get streakDays => _streakDays;

  /// Computes the current consecutive-day streak of completed sessions,
  /// looking back up to 90 days from today.
  ///
  /// Rules:
  /// - If there is a session today, streak anchors on today.
  /// - Else if there is a session yesterday, streak anchors on yesterday.
  /// - Else streak is 0.
  ///
  /// Non-fatal: defaults to 0 on errors.
  Future<void> _computeStreak() async {
    try {
      final now = DateTime.now();
      final toMs = OmniDateUtils.endOfDayMs(now);
      final fromMs = OmniDateUtils.startOfDayMs(
        now.subtract(const Duration(days: 90)),
      );
      final sessions = await _repository.getSessionsByDateRange(fromMs, toMs);

      final completedDays = <int>{};
      for (final s in sessions) {
        if (s.endedAtMs != null) {
          completedDays.add(
            OmniDateUtils.startOfDayMs(OmniDateUtils.fromMs(s.startedAtMs)),
          );
        }
      }

      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final todayMs = today.millisecondsSinceEpoch;
      final yesterdayMs = yesterday.millisecondsSinceEpoch;

      DateTime? anchorDay;
      if (completedDays.contains(todayMs)) {
        anchorDay = today;
      } else if (completedDays.contains(yesterdayMs)) {
        anchorDay = yesterday;
      }

      if (anchorDay == null) {
        _streakDays = 0;
        return;
      }

      int streak = 0;
      var day = anchorDay;
      while (true) {
        final ms = day.millisecondsSinceEpoch;
        if (!completedDays.contains(ms)) break;
        streak++;
        day = day.subtract(const Duration(days: 1));
      }
      _streakDays = streak;
    } catch (_) {
      _streakDays = 0;
    }
  }

  // ─── Period highlights ───────────────────────────────────────────────────────

  List<TrainingPeriod> _periods = [];
  List<TrainingPeriod> get periods => List.unmodifiable(_periods);

  /// Load periods alongside month data so calendar can render highlights.
  Future<void> _loadPeriods() async {
    try {
      _periods = await _repository.getPeriods();
    } catch (e) {
      // Non-fatal: calendar can still work without period highlights.
    }
  }
}
