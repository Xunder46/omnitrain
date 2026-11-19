# Plan 165 — a wrist-only walk shows DURATION 0s (investigation)

Owner report, 2026-11-14: a ~40-minute outdoor walk started and run on the watch
(Cardio, "Brisk Walk"), the phone app never launched until after the watch
finished. The phone's summary read `Nov 14 at 6:06 PM`, DURATION `0s`, REST TIME
`0`, AVG HR 96, MAX 127, EFFORT 5/5, CALORIES 75, a Cardio block with ROUNDS 1
and TOTAL TIME `40m 4s`, DISTANCE `Brisk Walk 1.61 MI`. The watch app was killed
and relaunched mid-walk.

Investigation only: no product code was changed. The scratch reproduction was
deleted (see "Scratch files").

## Verdicts

| # | Question | Verdict | Evidence | Confidence |
|---|---|---|---|---|
| 1 | Which phone path created the row | The **arrival-stamped adoption path**: the phone adopted the wrist's still-`active` session when it came up, so the row's start is the phone's clock at adopt time, not the wrist's start | `_adopt` (`lib/state/watch/watch_session_adoption_bridge.dart`: `startedAtMs: atMs`, `atMs = _clock()`); `_startSessionRow` stamps the same instant for a drained `session_started`; reproduction trace: `session_snapshot delivered (drained)` → row written | high for the mechanism; medium for the exact frame on the device (see "Not determined") |
| 2 | Where DURATION comes from, why `0s` while TOTAL TIME is `40m 4s` | DURATION is the **session row's span** (`endedAtMs − startedAtMs`), not a sum of efforts; TOTAL TIME is the round effort's own duration from the observations. A span of 0 ms formats as `0s` | `lib/state/workout/session_summary_builder.dart` `buildSessionSummary` (`endedAt = session.endedAtMs ?? now; durationMs = endedAt - session.startedAtMs;` → `totalDurationMs`); `lib/features/session/session_summary_screen.dart` Duration pill (`label: 'Duration'`, `_formatDuration` renders `'${seconds}s'`), Cardio group card (`secondaryLabel = 'Total Time'` from `metrics.effortDurationMs`) | certain |
| 3 | Reproduce it | Yes. The row is created at 18:06:04 and ended at 18:06:04: `start == end`, span `0ms`. The same symptom exists at committed HEAD (prove-red), so it predates plans 154 and 160 | scratch test output and prove-red verdict below | certain |
| 4 | Smallest fix and invariant | Correct the **start**, never the end: when the wrist's own `session_end` (`followed` false) reaches a phone-held session, set that row's `started_at_ms` to `end.startedAtMs` if the wrist's start is earlier. Invariant: a row for a wrist-created session carries the wrist's own start, whatever path created the row | `lib/core/services/watch_session_importer.dart` `_mergeHeld` today applies rating + summary + entries and deliberately never touches the session's own end (`G2/D-5`); it also never corrects the start; `_createSession` already writes `startedAtMs: end.startedAtMs` | high |
| 5 | Which diagnostics settle it | On the phone: `frame_received (session_snapshot)`, `frame_received (session_lifecycle)`, `frame_received (observations_up)` with timestamps — if the snapshot arrives **before** the lifecycle and the row's start equals that timestamp, it was adoption. Plus one new line naming the adoption decision and the wrist's start | `lib/core/platform/watch_transport.dart` `frame_received` (`<type>`), `docs/state_management/watch_diagnostics.md`; there is **no** diagnostic today for "adopted", "skipped adoption" or "row written with start X" | high |

## Q1 — the phone path, step by step

A wrist-only walk with the link down queues, in this order:

1. `session_lifecycle` (`started`) and `session_snapshot` (`status: active`) at the
   wrist's start — queued (`WatchConnectivityBridge.send` → `queueNewest`).
2. `observations_up` as sets/rounds are logged — queued.
3. At the finish, a terminal `session_lifecycle`; with plan 160 in the build also
   an `observations_up` carrying the `session_end` observation.

When the phone app first launches it drains the queue and then asks for a
snapshot (`WatchSyncGraph.sync()`). The drained **active** `session_snapshot`
is delivered to `WatchIncomingRouter.receive`, which mirrors it and then calls
`WatchSessionAdoptionBridge.consider`. `consider` accepts a session whose
converged status is `active`, and `_adopt` writes:

```dart
final atMs = _clock().millisecondsSinceEpoch;
...
// A snapshot carries no start time, so the session starts when the phone
// adopts it.
startedAtMs: atMs,
createdAtMs: atMs,
updatedAtMs: atMs,
```

Drained frames land in the same instant as the phone's launch, so the row's
start is the **arrival** instant. The finish then arrives as the wrist's
terminal lifecycle, and `_routeLifecycleToHeld` ends the held row at the wrist's
own end instant (`at`, bounded by plan 164's `kFutureEndClampMs`). The span is
therefore `wrist end − phone arrival`, i.e. whatever gap there was between the
phone coming up and the wrist finishing — seconds, in the owner's case.

The second creation path, `_startSessionRow` (fed by `session_started`), stamps
the same `_clock()` instant for the same reason ("the report carries no instant
the phone trusts for a history row"). Both are arrival-stamped; the invariant
below covers both.

The import path is different and correct: `WatchSessionImporter._createSession`
writes `startedAtMs: end.startedAtMs, endedAtMs: end.endedAtMs`, i.e. both from
the wrist's own `session_end`. That is why a walk that reaches the phone only
after the end (the phone opened minutes later) shows the full span.

## Q2 — DURATION versus TOTAL TIME

`SessionSummaryBuilder.buildSessionSummary` derives the summary's headline
duration from the session row alone:

```dart
final endedAt = session.endedAtMs ?? now;
final durationMs = endedAt - session.startedAtMs;
...
totalDurationMs: session.isRolling ? 0 : durationMs,
```

The Cardio block's TOTAL TIME is a different quantity: it is the round effort's
own elapsed time accumulated from the observations (`metrics.effortDurationMs`,
`getRoundsForEffort` → `elapsedMs`). So the block can read `40m 4s` — the walk
really lasted that long — while the session line reads `0s`, because the session
row's start and end are the same instant.

`SessionSummaryScreen` renders the pill with `label: 'Duration'` through
`_formatDuration`, which floors to whole seconds and prints `'${seconds}s'`, so a
sub-second span cannot render as anything but `0s`. The date above the summary
is the session's `startedAtMs`, which is why the header says `6:06 PM` (the
arrival) instead of `5:26 PM`.

Note a second, unrelated way to get `0s`: a session whose `isRolling` is true is
reported as `0` by the same expression. The row in this investigation was not
rolling — its span itself was 0 ms — but a future report of `0s` should check
`is_rolling` on the row before assuming this cause.

## Q3 — reproduction

Scratch test `test/zz_wrist_only_start_test.dart` (created for this
investigation, then deleted): `WatchPairHarness` at `17:26:00Z`; link dropped;
wrist starts a Free workout and logs its set 30 minutes in; 10 m 4 s later the
link rises **in the second the wrist finishes**, then the wrist finishes. Output
on the working tree (plans 160 + 164):

```
wrist start 2026-11-14T17:26:00.000Z
wrist end   2026-11-14T18:06:04.000Z
phone row   start 2026-11-14 18:06:04.000Z end 2026-11-14 18:06:04.000Z span 0ms
phone holds s-w-1
trace:
31. link rises and drains the queue
   wrist→phone session_lifecycle (session 1) delivered (drained)
   wrist→phone session_snapshot (session 1) delivered (drained)
   wrist→phone observations_up (session 1) delivered (drained)
32. wrist finishes
   wrist→phone observations_up (session 1) delivered
   wrist→phone session_lifecycle (session 1) delivered
```

`startedAtMs == endedAtMs` (1794679564000 == 1794679564000), the DURATION pill
would read `0s`, and the header would read `6:06 PM` — the owner's picture. The
walk's own data (round, distance, HR summary, rating) still lands: plan 160's
`session_end` in `observations_up` merges into the held session, which is why the
summary is full of data around a zero-length session.

Does it predate plans 160 and 154? Yes. `prove-red HEAD test` on the same test:

```
phone row   start 2026-11-14 18:06:04.000Z end 2026-11-14 18:06:04.000Z span 0ms
32. wrist finishes
   wrist→phone session_lifecycle (session 1) delivered
gateway: prove-red: RED AT HEAD (exit 1).
```

At HEAD the row is created by the same arrival stamp and the span is the same
0 ms; the only difference is that HEAD also lacks the twin `session_end`, so the
walk's sets and summary never import at all (the finish emits no
`observations_up`). Plan 154 only bounds the **end** and plan 160 only adds the
wrist's `session_end`; neither touches the start. So the defect is older than
both, and plan 160 makes it *more* visible, because now a full-looking summary
sits on a zero-length session.

## Q4 — smallest fix

The phone cannot know the wrist's start at adoption time: a snapshot carries no
start (that is what the `_adopt` comment records). The start does arrive, once,
in the wrist's `session_end` (`startedAt`, emitted with plan 160). So the fix
belongs where that end is already being merged into a phone-held session:
`WatchSessionImporter._mergeHeld`, next to the rating and summary it applies.

The rule:

> For a session the wrist created (its `session_end` is not `followed`), the
> phone's row start is the wrist's `startedAt`. A row that was created before
> that end arrived takes the wrist's start when the end is merged; the row's end
> and status are untouched.

In code terms, in `_mergeHeld`, before the entries are placed:

```dart
if (end != null && !end.followed && end.startedAtMs < existing.startedAtMs) {
  await _repository.updateSession(TrainingSession.fromMap({
    ...existing.toMap(),
    'started_at_ms': end.startedAtMs,
  }));
}
```

— written through the row's own map, the way `_catchUpEnd` and `_topUpRating`
already are, so no field of the session is dropped.

Why this keeps the owner rules intact:

- **O-2 (the first ending is final)** and **O-5 (the end is the latest instant
  anyone knows)**: only `started_at_ms` moves here. The end and the status are
  not touched — the comment already in `_mergeHeld` ("The session's own end is
  never touched (G2/D-5)") continues to hold.
- **O-3 (a lagging device catches up)**: the merge is the catch-up; this only
  teaches it one more field, and it moves the start only *earlier*, only to the
  wrist's own stamp, and only for a wrist-created session.
- **O-6 (an own workout arrives)**: `followed: true` ends — a phone-started
  session the wrist merely followed — are excluded, so a phone session keeps the
  start the phone chose.
- Not a rewrite of history in the "an ended session is final" sense: an
  arrival-stamped start is a placeholder the phone stuffed in for want of a
  value, and the wrist's start is the truth it was standing in for.

Two smaller options were considered and rejected: (a) teaching the snapshot to
carry a start — a protocol change across both platforms, and plan 160 already
ships the start in the end event; (b) stamping the row from the drained
`session_started` report's own `at` — that instant is the wrist's *start*, but
only for the started-report path, it is not present on the snapshot path, and it
still would not correct a row adopted from a snapshot.

Secondary, cheap and worth having alongside: the summary could refuse to print a
zero-length session for a session that has efforts (`totalDurationMs == 0 &&
exercises.isNotEmpty` → fall back to the sum of the block durations, or hide the
pill). That hides the symptom on rows already written, and it is a product
decision — listed for the owner, not part of the fix.

## Q5 — diagnostics that settle the doubt

Already available:

- Phone: `frame_received (session_snapshot)`, `frame_received
  (session_lifecycle)`, `frame_received (observations_up)` — timestamps show
  whether an **active** snapshot arrived before the terminal lifecycle, i.e.
  whether the adoption path is the one that wrote the row. `frame_received`
  records the frame type only; it does not report the snapshot's status.
- Watch: `frame_sent` (`session_snapshot` / `session_lifecycle` /
  `observations_up`: `delivered`, `queued`, `failed: <reason>`), plus its own
  `replay_session_end` / reconnect notes.

Missing, and worth adding (one line each):

1. In `WatchSessionAdoptionBridge.consider`/`_adopt`: `adoption_decision` with
   detail `adopted <sessionId> status=<status> start=<clock>` or
   `skipped <sessionId> reason=<...>`.
2. In `_startSessionRow` and `_adopt`: `session_row_created` with
   `id`, `startedAtMs`, and which path (`snapshot` / `started`).
3. In `WatchSessionImporter._mergeHeld`: `session_start_corrected` with
   `from`, `to` once the fix lands — so a future report can be read without a
   rebuild.

With those three, the owner's next report answers Q1/Q4 from the log alone.

## Not determined

- **Which frame actually carried the adoption on the device.** The reproduction
  used the drained active snapshot; on the device a live answered snapshot would
  look identical in the resulting row (both stamp `_clock()`). `frame_received`
  timestamps against the row's `started_at_ms` would decide it; the log detail
  does not include the snapshot status today.
- **Whether the phone app was truly never in the foreground before the end.**
  The owner's account says it was first opened after the finish. The symptom is
  consistent with opening it within the same minute the walk ended (the row
  shows the same minute for start and end); it is not consistent with opening it
  appreciably later, because then the drained snapshot would be terminal and the
  import path — which uses the wrist's start — would have run instead.
- **The mid-walk watch app kill.** Nothing in the traced paths needs it to
  explain the row: the kill explains retries and re-emission, not the start
  stamp. It was not reproduced.

## Scratch files

`test/zz_wrist_only_start_test.dart` — created for this investigation, deleted
with `gateway.sh delete-scratch` before handoff. No product code, docs or tests
were changed by this run.

## Evidence — runs

| Run | Command | Result |
|---|---|---|
| Reproduction (working tree, plans 160 + 164) | `gateway.sh test test/zz_wrist_only_start_test.dart` | `+0 -1`: expected start `1794677160000`, actual `1794679564000`; `span 0ms` |
| Same test on committed HEAD | `gateway.sh prove-red HEAD test test/zz_wrist_only_start_test.dart` | `RED AT HEAD (exit 1)`, same `span 0ms`; at HEAD the finish emits no `observations_up` |
| Behaviour check before the same-second relink | earlier variant of the same scratch test (phone opened two minutes later) | row start `17:26`, end `18:06:04`, span `2404s` — the import path is correct |
| Full Flutter suite, after the scratch file was removed | `gateway.sh test` | `+7594 ~4 -5: Some tests failed.` — five reds, none in a file this run touched (no `lib/` file was changed): `logger_feedback_controls_test` S-5115, `watch_session_finish_test` S-14609, `watch_session_adoption_bridge_test` S-15403, `watch_replay_corpus_test` S-15202/S-15207 |
| Those five in isolation | `gateway.sh test test/watch_session_finish_test.dart test/watch_replay_corpus_test.dart test/logger_feedback_controls_test.dart` (one runner) | `+38 ~1: All tests passed!` — and `watch_session_adoption_bridge_test.dart` alone `+44: All tests passed!`. The full-suite reds are order/parallel flakes of the in-flight plan-160/164 tree, not this run |
| `flutter analyze` | `gateway.sh lint` | `181 issues found`, every one pre-existing in test files (deprecations, one `unnecessary_non_null_assertion`); this run added no Dart file |
| Repository invariant | `grep -rln "import .*hive_workout_repository" lib` | `lib/main.dart` only — the composition root; state, features, widgets and core stay on the interface |

## Run notes

- The brief pointed at a plan file and a plan folder for this investigation; the
  folder did not exist, so it was created by this run to hold this file alone.
  There is therefore no plan Progress table, no Scenario register and no lint
  baseline to compare against — the counts above are absolute.
- The brief's premise that the phone app was "never launched" until after the
  walk is the one assumption this investigation had to narrow: the symptom is
  only reachable if the phone came up while the wrist's session was still
  active, i.e. within the same minute the walk ended. Everything else about the
  report (data present, zero span, header at the end instant) is reproduced
  exactly.

