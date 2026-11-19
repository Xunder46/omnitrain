# Plan 98 — evidence

Base commit `cafc9a61`. Probe file kept at `.work/crew/2026-11-02-98-phone-watch-live-sync-audit/probe_phone_watch_sync_test.dart`
(it is the first 458 lines of `test/watch_timer_push_test.dart` — imports, helpers, `setUp` — plus the
groups below; it is not in `test/` because it fails by design).

## Fix evidence

Code changed (plan 98 D-1, D-2, D-3):

- `lib/state/workout/timer_manager.dart` — new `closeAllOpenRestsInSessionInMemory()`; `startTimedEntry`,
  `startRound`, `_adoptRemoteTimed` and `_adoptRemoteRound` call it and persist the closed rests via
  `_persistClosedRests`. The per-effort `closeAllOpenRestsInMemory(effortId)` and `closeAllOpenRests(effortId)`
  are unchanged.
- `lib/state/watch/watch_timer_push.dart` — `_owed` (per wire kind): a start the radio did not carry is
  remembered and a clears-only pass (`flushClears`) sends it; dropped on delivery, when the phone no longer
  wants the kind, and with the ledger on a session change.
- `lib/state/watch/watch_sync_wiring.dart` — the transport's `linkChanges` stream runs
  `timerPush.flushClears()` on each `reachable: true` event; failures go to `onFailure`.

Tests added (names only; run counts are the lead's):

- `test/timer_start_closes_session_rests_test.dart` (groups `Mock`, `Hive`): `S-9921`, `S-9921b`, `S-9921c`,
  `S-9922`, `S-9923`, `S-9923b`.
- `test/watch_timer_push_test.dart`: `S-9924`, `S-9925`, `S-9926`, `S-9927a`, `S-9927b`, `S-9928`, `S-9929`,
  `S-9930`. `S-9931`, `S-9932`, `S-9933` (lead-written after a builder run was stopped) and `S-9934`
  (the clears-only pass leaves the pending window alone).
- `test/unified_rest_overlay_test.dart` `S-002b` now asserts A's rest is closed in the data layer and the
  chip does not come back when B's timer ends.

Docs updated: `docs/rest_tracking.md`, `docs/state_management/watch_surface.md`,
`docs/state_management/workout_state.md`, `docs/watch_session_sync/what_does_not_sync.md`.


## Run commands and results

```
flutter test <probe file> --plain-name "PROBE A"   → A1 FAIL, A2 FAIL
flutter test <probe file> --plain-name "PROBE A3"  → FAIL
flutter test <probe file> --plain-name "PROBE B"   → FAIL
flutter test <probe file> --plain-name "PROBE C"   → PASS
```

Printed lines: `A1 sent: [session_snapshot timers={}]`; `A3 phone intervals: [TimedState.active 0]`,
`A3 frames to wrist: []`; `B1 frames:` a rest frame, then an `elapsed` frame for `sx-bike` with no `rest`
key; `C1 sent: [session_snapshot completed]`.

The three shipped commits before the audit: `989baf13` (watch-added set exercise gets its first set;
134 tests green in the three changed files, invariants 54/54) and `cafc9a61` (gitignore).

## Probe source

```dart
  group('PROBE A: phone timer started while the wrist was out of reach', () {
    test('A1 the wrist raises and syncs: it learns the phone timer', () async {
      await wristStartsTimedSession();
      graph.timerPush.bindWorkoutState(phoneState);

      radio.unreachable = true;
      await startInterval();
      await graph.timerPush.flush();
      expect(timerFrames(), isEmpty, reason: 'fixture: nothing carried');

      // The wrist comes back in range and asks, as a raised wrist does.
      radio.unreachable = false;
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();

      final carriedTimers = [
        for (final e in radio.sent)
          if (e['type'] == 'timer_state' ||
              (e['type'] == 'session_snapshot' &&
                  _payload(e)['timers'] is Map &&
                  (_payload(e)['timers'] as Map).containsKey('elapsed')))
            e,
      ];
      // ignore: avoid_print
      print('A1 sent: ${[for (final e in radio.sent) '${e['type']} timers=${_payload(e)['timers']}']}');
      expect(
        carriedTimers,
        isNotEmpty,
        reason: 'the wrist learns the running phone timer once it asks',
      );
    });

    test('A2 reachability returns with no wrist frame: nothing re-offers it',
        () async {
      await wristStartsTimedSession();
      graph.timerPush.bindWorkoutState(phoneState);
      radio.unreachable = true;
      await startInterval();
      await graph.timerPush.flush();
      radio.unreachable = false;
      // Wait longer than the debounce; no phone state change happens.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(timerFrames(), isNotEmpty,
          reason: 'the owed start is sent when the wrist is reachable again');
    });
  });

  group('PROBE B: rest vs a work timer started on ANOTHER exercise', () {
    test('B1 phone rest on exercise A is cleared when a timer starts on B',
        () async {
      await seedExercise(
        repository,
        id: 'ex-bike',
        name: 'Bike',
        capabilities: ['time', 'distance'],
      );
      await engine.createSession(
        modality: null,
        exercises: [
          _slot(),
          {
            'sessionExerciseId': 'sx-bike',
            'exerciseId': 'ex-bike',
            'name': 'Bike',
            'effortKind': 'timed',
            'capabilities': ['time', 'distance'],
          },
        ],
      );
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      graph.timerPush.bindWorkoutState(phoneState);

      await openPhoneRest(); // rest open on sx-run
      await graph.timerPush.flush();
      expect(
        [for (final f in timerFrames()) timersOf(f).keys.toList()],
        [['rest']],
        reason: 'fixture: the rest reached the wrist',
      );

      await phoneState.startTimedEntry('sx-bike', 0);
      await graph.timerPush.flush();
      // ignore: avoid_print
      print('B1 frames: ${[for (final f in timerFrames()) timersOf(f)]}');
      final clearsRest = timerFrames().any((f) {
        final t = timersOf(f);
        return t.containsKey('rest') && t['rest'] == null;
      });
      expect(clearsRest, isTrue,
          reason: 'starting work on another exercise ends the rest');
    });
  });

  group('PROBE C: the phone finishes while the wrist is out of reach', () {
    test('C1 the wrist raises and syncs: its session ends', () async {
      await wristStartsTimedSession();
      graph.autoPush.bindWorkoutState(phoneState);

      radio.unreachable = true;
      await phoneState.endSession(writeToHealth: false);
      await graph.autoPush.flush();
      // The finish frame is queued by the OS in production; model it as not
      // arrived yet.
      radio.sent.clear();

      radio.unreachable = false;
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      // ignore: avoid_print
      print('C1 sent: ${[for (final e in radio.sent) '${e['type']} ${_payload(e)['status'] ?? _payload(e)['state']}']}');
      for (final f in radio.sent) {
        await engine.applyMessage(f);
      }
      expect(engine.session?.status, 'completed',
          reason: 'the wrist learns the phone ended the session');
    });
  });

  group('PROBE A3: the wrist starts its own timer beside the phone one', () {
    test('A3 the phone corrects the wrist to its earlier timer', () async {
      await wristStartsTimedSession();
      graph.timerAdoption.bindWorkoutState(phoneState);
      graph.timerPush.bindWorkoutState(phoneState);

      radio.unreachable = true;
      final phoneTimer = await startInterval();
      await graph.timerPush.flush();
      expect(timerFrames(), isEmpty, reason: 'fixture: wrist never told');

      radio.unreachable = false;
      final wristStart = DateTime.fromMillisecondsSinceEpoch(
        phoneTimer.startedAtMs + 20000,
        isUtc: true,
      );
      await radio.fromWrist(
        _wristTimerFrame({
          'elapsed': {
            'kind': 'elapsed',
            'state': 'running',
            'startedAt': utcIso(wristStart),
            'accumulatedPauseMs': 0,
            'sessionExerciseId': _slotId,
          },
        }),
      );
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // ignore: avoid_print
      print('A3 phone intervals: ${[for (final i in phoneState.getTimedInstancesForEffort(_slotId)) '${i.state} ${i.startedAtMs - phoneTimer.startedAtMs}']}');
      // ignore: avoid_print
      print('A3 frames to wrist: ${[for (final f in timerFrames()) timersOf(f)]}');
      expect(
        timerFrames(),
        isNotEmpty,
        reason: "the wrist's later clock is corrected to the phone's earlier one",
      );
    });
  });
```


## Lead verification (2026-11-02)

- Related suites: `watch_timer_push_test.dart` 58 tests, `timer_start_closes_session_rests_test.dart`,
  `unified_rest_overlay_test.dart`, `watch_session_auto_push_test.dart`, `live_mirroring_test.dart` — 196 passed
  together after the last change. `flutter analyze` on the touched lib and test paths: no issues.
- Mutations (each production guard line mutated alone, one test file run, restored and `cmp`ed): killed —
  clears-only sends no start (old behaviour), clears-only sends every start, failed start not owed, failed clear
  leaves start not owed, unwanted start stays owed, delivered start stays owed, reachability guard inverted and
  removed, adopt-remote-round closes one effort only, each of the four rest-close call sites, the session helper
  stopping after the first effort. Survived and accepted: `_owed.clear()` on a session change and on no session
  (timing-only: a wrist frame could send a start the push's own pass sends within 250 ms).
- A race found while reading `_flush` and proved red before the fix: a clears-only pass cancelled the pending
  phone-news window, so a reachability event inside the 250 ms of a timer start lost the start (S-9934).
- Full `flutter test`: 6016 passed, 2 skipped, 49 failed on a tree shared with a stats-screen session; the failing
  files are stats, mix layer, instrument list, protein, fuel row, nutrition and calendar-streak tests — none touch the
  watch, timers or rests; two `NutritionState` tests in `state_test.dart` fail on the base commit too (clean worktree
  run). Not a clean full-suite proof for this unit: owner/another session to re-run once the stats work is committed.
