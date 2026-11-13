# Plan 151 — evidence

## Baselines

| Check | Baseline |
|---|---|
| `flutter test` (full) | green at HEAD before this change |
| `flutter analyze` | 181 issues (repo-wide, pre-existing info notices) |
| `swift test` (`watch/watchos`) | 1404 tests, green |
| 200-seed sweep | 12 shipping divergers: `[29,43,94,95,111,117,124,134,149,152,161,193]` |
| 2000-seed soak | 125 diverge / 1801 converge; classes `{status:137, absorbing:22, heal:34, entries:14, timers:2}` |

## Red then green — Dart

Command: `.github/copilot/scripts/macos/gateway.sh test test/watch_ended_session_not_current_test.dart`

Red (before the engine change):

```
00:00 +0 -1: S-15101 ... the wrist holds another ended session ... [E]
  Expected: <4>  Actual: <5>   a session that has ended takes no new row
00:00 +0 -2: S-15101 ... a live session with an empty ladder ... [E]
  Expected: <3>  Actual: <4>
00:00 +1 -2: S-15101 ... a live session of its own (D-78 unchanged)   <- green guard
00:00 +1 -3: S-15101 ... stays out of the current session ... [E]
  Expected: 's-2'  Actual: 's-1'
00:00 +1 -4: S-15101 the Phase 4 four-action trace ... [E]
  Expected: empty
    Actual: ['session 1 was completed on the wrist and reports active again']
00:00 +1 ~1 -4: Some tests failed.
```

Green (after D-15101/D-15102, with the engine's own suite):

```
00:00 +79 ~1: All tests passed!        (test/watch_ended_session_not_current_test.dart + test/watch_session_engine_test.dart)
```

## Red then green — Swift

Command: `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchEndedSessionNotCurrentTests`

Red (before the engine change):

```
WatchEndedSessionNotCurrentTests.swift:133: XCTAssertEqual failed: ("3") is not equal to ("2") - an ended session takes no new row
WatchEndedSessionNotCurrentTests.swift:134: XCTAssertEqual failed: ("Optional("active")") is not equal to (Optional("completed"))
WatchEndedSessionNotCurrentTests.swift:135: XCTAssertEqual failed: (ladder)
WatchEndedSessionNotCurrentTests.swift:137: XCTAssertNotEqual failed: ("Optional("s-watch-1")")
WatchEndedSessionNotCurrentTests.swift:162: XCTAssertEqual failed: ("Optional("active")") ...
WatchEndedSessionNotCurrentTests.swift:105/108: the A1 shape — current became s-watch-1, status active
Executed 4 tests, with 8 failures (0 unexpected)
```

Green (after the change):

```
Executed 4 tests, with 0 failures (0 unexpected) in 0.010 seconds
```

## Notes

- The per-session newest-snapshot marker (D-15103, S-15102) is **not** implemented: an existing Swift
  test asserts the device-wide refusal and a source guard asserts its literal line. Recorded as
  Blocked (scope) in the plan.
- The shared reconciliation fixture was not added; see Open Items 2 in the plan.

## 200-seed sweep, after the change

```
S-14509 contract: 200 seeds; 184 converge on every trace; 10 diverge on a trace the shipping app can
perform [29, 43, 94, 95, 117, 124, 134, 149, 161, 193]; 2 on a heal stall alone [86, 114]; 4 only after
the harness-only re-assert [33, 89, 138, 142]
```

Baseline was 1777/2000 seeds and 12 shipping divergers `[29,43,94,95,111,117,124,134,149,152,161,193]`.
Seeds **111** (the A1 trace above) and **152** are gone; the A1 class — "session N was completed on the
wrist and reports active again" — no longer appears on any trace in the sample. 184 of 200 converge
everywhere, up from 182 (12 → 10 on the shipping-trace measure).

The ratchet in `test/watch_convergence_random_test.dart` (`(kSeedCount * 14 / 200).ceil()`) was **not**
lowered: seed membership is not process-stable (A-145-02), and 10 < 14 leaves the headroom the
ratchet exists for.

## The one existing test that went red — `S-14509 a drain-only heal`

```
S-14509 drain-only heal: red seeds [] of 1..200; drain-only runs that diverge at all:
[17, 29, 43, 46, 94, 95, 102, 115, 117, 124, 134, 137, 149, 161, 193, 199]
Expected: non-empty   Actual: []
```

That test is a *measurement*: it asserts that at least one seed converges with the full heal and fails
on the drain-only heal, i.e. that the re-offer round is load-bearing. After D-15101 no seed in the 200
sample is in that class — every drain-only diverger also fails the full heal, because the resurrection
the re-offer used to repair is now prevented at the point the frame is applied. This is the "finding
has moved" case the test's own reason anticipates; the fix is a decision about the measurement (its
seed sample or its statement), not a code change, and the test was **not** edited.


## Lead note: S-14509 re-based (2026-11-13)
After the fix the "drain-only heal" measurement (S-14509) went red (`red seeds []`): no seed needs the heal's re-offer any more, because the resurrection it used to repair is prevented at apply time. Its own reason text anticipated "the finding has moved". Re-based, not weakened: both runs now use a wrist that ignores `completed` lifecycles (`_MutationWrist`), so only a heal that re-offers snapshots repairs it; red on 21 of 200 seeds (52, 55, 56, 57, 77, 78, 82, 84, 88, 99, 112, 129-132, 136, 159, 167, 168, 174, 180). Same pattern as S-14508 earlier.
Lead-verified: focused Flutter set 498 passed (2 skipped: S-15102 and the older F-skip); Swift full 1408 passed; the new tests fail on the old engines (Dart 4 failures, Swift 7 assertion failures); analyze 181.
Blocked and recorded by the developer run: per-session newest-snapshot marker (A2, seed 857; needs a plan 63 amendment: `testS9312...` and S-9315 pin the device-wide rule) and the shared fixture (walkers compare only the current session).
