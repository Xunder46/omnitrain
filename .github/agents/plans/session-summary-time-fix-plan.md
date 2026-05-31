# Feature: Session Summary Time Statistics Fix

## Overview
The Session Summary screen shows two distinct time bugs for non-rolling sessions:
1. **Rest Time shows `0`** — the last rest period (opened after the final set) is never
   closed before `computeSessionRestTimeMs` runs, so it is skipped.
2. **Rest Time exceeds session Duration** — when the user alternates between multiple
   exercises, rest periods for different efforts overlap in wall-clock time. Because
   `computeSessionRestTimeMs` sums every effort's rests independently, concurrent
   rest windows are counted multiple times, inflating the total beyond the actual
   session clock.

Rolling sessions are correctly excluded from the stats card — no change needed there.

---

## Root Cause Analysis

### Bug 1 — Last rest is always open at finish time

`_finishSession()` in `workout_session_finish.dart` calls, in order:
1. `_freezeAllLocalTimers()` — cancels UI tickers
2. `cancelRestNotifications()` / `cancelEffortTimerNotification()`
3. `_persistActiveEffortTimers()` — closes active rounds + timed entries
4. `workoutState.endSession()` → `persistActiveRounds()` + `persistActiveTimedEntries()`
   → then stamps `endedAtMs`

**Nothing in this chain closes open `EntryRest` records.** The rest that opened after
the last logged set has `restEndMs = null`. `computeSessionRestTimeMs` correctly skips
null-end rests, so it contributes zero to the total.

For `round / timed / drill` efforts, `recordRestStart` is called with `unawaited`
(fire-and-forget). If the user taps "Finish" quickly, the rest may not even be
persisted to the repository before `computeSessionRestTimeMs` runs.

### Bug 2 — Overlapping rest intervals counted twice

`computeSessionRestTimeMs` traverses segments → efforts → `getEntryRests(effortId)`
and sums all closed durations **independently per effort**. It does not account for
simultaneous rests across multiple exercises.

Concrete example:
```
Exercise A rest:  T=60s → T=120s  (60 s)
Exercise B rest:  T=80s → T=140s  (60 s)
Sum of both:                      120 s
Session duration:                 100 s   ← rest > duration
Correct merged rest:    T=60s → T=140s = 80 s
```

When a user supersets or alternates exercises, both exercises have open rests at the
same wall-clock time. Both intervals are fully closed and both are counted — giving a
total that can exceed the session duration.

---

## Requirements
- Rest Time must never be zero unless the user genuinely did not rest between any sets.
- Rest Time must never exceed the session Duration.
- Rest Time must represent actual wall-clock rest (no double-counting of overlapping
  rest windows from different exercises).
- No schema changes; no new repository interface methods; no new public API on
  `WorkoutState`.

---

## Acceptance Criteria
- [x] A session where the user finishes while a rest is active shows a non-zero
      Rest Time on the summary screen (the last rest is captured at session end time).
- [x] A session where the user alternates between two exercises with overlapping
      rest windows reports Rest Time ≤ Duration.
- [x] A session with no logged sets (rest records) still shows Rest Time `0`.
- [x] Rolling sessions continue to hide the stats card entirely (no regression).
- [x] Existing services_test `computeSessionRestTimeMs` passes unchanged.
- [x] New tests cover: (a) open-rest closure at finish, (b) overlap merging,
      (c) session-window clipping.

---

## Scenarios
- User logs 3 sets on Bench Press then taps Finish Workout while rest timer is running.
  Summary shows rest time ≈ time between last set log and finish confirmation.
- User supersets Squat and Bench Press, 30 s apart. Summary rest ≤ total session time.
- User finishes an empty free-training session. Rest Time = `0`.

---

## Iteration 1

### DB Changes
None.

### Backend Changes

#### 1. `TimerManager` — add `persistOpenRests(int closeAtMs)`

**File**: `lib/state/workout/timer_manager.dart`

Add one new method alongside `closeAllOpenRests`:

```dart
/// Closes every open [EntryRest] across **all** efforts at [closeAtMs].
/// Called from [endSession] so the last rest window is captured
/// rather than discarded.
Future<void> persistOpenRests(int closeAtMs) async {
  for (final effortId in List<String>.from(_entryRests.keys)) {
    final list = _entryRests[effortId];
    if (list == null) continue;
    for (var i = 0; i < list.length; i++) {
      final rest = list[i];
      if (rest.restEndMs != null) continue;
      final closed = rest.copyWith(restEndMs: closeAtMs, updatedAtMs: closeAtMs);
      try {
        await _repository.updateEntryRest(closed);
      } catch (_) {
        // best-effort; do not block session end
      }
      list[i] = closed;
    }
  }
}
```

#### 2. `session_core_lifecycle.dart` — call `persistOpenRests` in `endSession()`

**File**: `lib/state/workout/session_core_lifecycle.dart`

In `endSession()`, after `persistActiveTimedEntries()` and before `final now = …`:

```dart
await _timerManager.persistActiveRounds();
await _timerManager.persistActiveTimedEntries();
final now = DateTime.now().millisecondsSinceEpoch;  // existing line
await _timerManager.persistOpenRests(now);           // ← add this
```

This stamps every still-open rest with the same `now` used as `endedAtMs`, so
rest intervals are always capped at session end.

#### 3. `SessionSummaryService.computeSessionRestTimeMs` — clip + merge intervals

**File**: `lib/core/services/session_summary_service.dart`

Replace the current naïve sum with a three-step pipeline:

```dart
Future<int> computeSessionRestTimeMs(String sessionId) async {
  // Step 1 — fetch session window for clipping
  final session = await _repository.getSession(sessionId);
  if (session == null) return 0;
  final windowStart = session.startedAtMs;
  final windowEnd   = session.endedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  // Step 2 — collect closed intervals from all efforts, clipped to session window
  final intervals = <(int, int)>[];
  final segments = await _repository.getSessionSegments(sessionId);
  for (final segment in segments) {
    final efforts = await _repository.getSegmentEfforts(segment.id);
    for (final effort in efforts) {
      final rests = await _repository.getEntryRests(effort.id);
      for (final rest in rests) {
        final endMs = rest.restEndMs;
        if (endMs == null) continue;
        final start = rest.restStartMs.clamp(windowStart, windowEnd);
        final end   = endMs.clamp(windowStart, windowEnd);
        if (end > start) intervals.add((start, end));
      }
    }
  }

  if (intervals.isEmpty) return 0;

  // Step 3 — merge overlapping intervals, then sum
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  var mergedStart = intervals.first.$1;
  var mergedEnd   = intervals.first.$2;
  var totalMs = 0;
  for (final iv in intervals.skip(1)) {
    if (iv.$1 <= mergedEnd) {
      // overlapping or adjacent — extend current merged window
      if (iv.$2 > mergedEnd) mergedEnd = iv.$2;
    } else {
      totalMs += mergedEnd - mergedStart;
      mergedStart = iv.$1;
      mergedEnd   = iv.$2;
    }
  }
  totalMs += mergedEnd - mergedStart;
  return totalMs;
}
```

`_repository.getSession` is already on the `WorkoutRepository` interface and
used by `loadHistoricalSession`. No new interface method is needed.

### Frontend Changes
None — `session_summary_screen.dart` already displays whatever value
`computeSessionRestTimeMs` returns. The `_formatDurationOrZero` helper already
shows `0` correctly when the computed value is zero.

### Implementation Steps
1. [x] Add `persistOpenRests(int closeAtMs)` to `TimerManager`
2. [x] Call `await _timerManager.persistOpenRests(now)` in `endSession()` (after
       `persistActiveTimedEntries`, before the repository write)
3. [x] Rewrite `computeSessionRestTimeMs` with session-window clipping + interval merge
4. [x] Add unit test in `services_test.dart`:
       - "overlapping rests from two efforts are merged and not double-counted"
       - "rest intervals are clipped to session window"
5. [x] Add widget/integration test in `session_finish_timers_test.dart`:
       - "finishing session closes the active open rest record"
       - "rest time shown on summary is non-zero after a single set with rest"
6. [x] Run full test suite; confirm no regressions

---

## Progress
- [x] `TimerManager.persistOpenRests` added
- [x] `endSession()` calls `persistOpenRests`
- [x] `computeSessionRestTimeMs` rewritten with clipping + merge
- [x] New tests added
- [x] Full suite green
- [x] Empty-session (`no rest records`) test added
- [x] Session summary/rest tracking/state management docs updated

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
