# Plan 310 — The Wear wrist sends the session's heart rate on `session_end` (series 310-314, the Wear-vs-Apple review of 2026-11-22)

A review of the Apple wrist against the Wear wrist (2026-11-22) found that a Wear workout reaches the phone with no heart rate. The Apple wrist's `session_end` entry carries the session's average and maximum heart rate (`avgHeartRateBpm`, `maxHeartRateBpm`) and one pair per set block (`setBlockHeartRates`); the phone already reads both for any wrist (`lib/core/services/watch_session_importer.dart`, `lib/core/sync_protocol/message_validator.dart` lines 144-148, 532-614). The Dart wrist writes only calories on that entry (`lib/watch/session/watch_session_engine.dart` `_sessionEndEvent`, plan 305). The wrist already measures and stores heart-rate samples (plan 298) and shows an Avg HR row on its own summary, so the measurement exists and is simply not sent. This plan ports the session-level half. Plan 311 does the per-effort half (timed, round and hold entries, and a round's `pausedMs`). Series: 310 session end, 311 per-effort, 312 exercise list from the phone, 313 today's planned workout, 314 modality start grid and the empty free workout. Base commit: `9e2a064c` (branch `claude_develop`). Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

A Wear workout that stored heart-rate readings ends with a `session_end` entry carrying the average and maximum heart rate over the whole session, and one average/maximum pair for each set block that has readings in its span. A workout with no readings sends neither (absence, never zero). Wrist-created and followed ends alike. Nothing on the phone changes.

Acceptance: S-31001..S-31008 green and each guard red without its change; `flutter analyze` at most 174 issues, 0 errors; the emission validator accepts every produced entry; Docs delta applied. Not provable without a real watch: owner check 25 (a real Wear workout's heart rate appears on the phone's session, with the average the wrist's own Workout done screen showed).

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-31001 | `WatchSensorSummaries.heartRate(samples, start, end)` in `lib/watch/session/watch_sensor_summaries.dart`: a port of the Apple function. Only `heartRate` kind samples with a finite value of at least 1 count; the window is inclusive at both ends, compared in whole milliseconds; the result is the arithmetic mean (clamped between the lowest and highest reading) and the highest reading; null when no reading qualifies. No pause exclusion yet (plan 311 adds it for rounds). | `WatchSensorSummaries.swift` 82-121 |
| D-31002 | A value class `WatchHeartRateSummary {averageBpm, maximumBpm}` with `fields` giving `{'avgHeartRateBpm': avg, 'maxHeartRateBpm': max}`: the two always travel together (the validator refuses one without the other, `message_validator.dart` 532-545). | `WatchSensorSummaries.swift` 30-46 |
| D-31003 | `WatchSensorSummaries.blockSpans(entries, sessionStartedAt)` and a value class `WatchSetBlockSpan {sessionExerciseId, exerciseId, startedAt, endedAt}`: a set block is every `set` entry sharing one `sessionExerciseId` and `exerciseId`; its span starts at the `loggedAt` of the latest effort entry (kinds in `WatchObservationKind.efforts`) logged strictly before the block's first set, or the session start when none, and ends at the block's last set's `loggedAt`; blocks come out in the order they began; efforts are ordered by `loggedAt` then `entryId`; an entry with no parseable `loggedAt`, a non-effort kind (a rest, a rating) or a missing slot/exercise id never makes or leads a block. | `WatchSensorSummaries.swift` 254-293, 307-330 |
| D-31004 | `_sessionEndEvent` adds, over the window `[creation.startedAt, endedAt]` normalised to wire resolution (a round trip through `utcIso`/`parseUtcIso`, as Apple's `wireInstant`): the session pair (`avgHeartRateBpm`, `maxHeartRateBpm`) when there is one, and `setBlockHeartRates` (a list of `{sessionExerciseId, exerciseId, startedAt, endedAt, avgHeartRateBpm, maxHeartRateBpm}`, instants as `utcIso`) holding only the blocks whose span has a pair; the key is absent when no block has one. Wrist-created and followed ends alike. | `WatchSessionEngine.swift` 2191-2255 |
| D-31005 | The set-block spans read the session's entries as the wrist shows them (corrections folded in, phone deletions dropped): `entries` is split into a private `_entriesFor(sessionId)` and `entries` becomes `_entriesFor(_session?.sessionId)`, because `_sessionEndEvent` runs for the session that is ending, which the public getters (filtered to the current session) cannot be relied on to name. Same behaviour for every existing reader of `entries`. | `watch_session_engine.dart` 214-218, 267-287 |
| D-31006 | Out of scope: heart rate on timed/round/hold entries and a round's `pausedMs` (plan 311); steps (the Wear wrist has no step source); the Workout done screen (it already reads the samples directly, `watch_workout_summary.dart` 133). | |

## Input-reality checklist

- **Writers/units.** One writer: `_captureSessionEnd`, once per session (the id is the session's, `_heldRecord` guard). Reads stored samples and entries only; no await between reading them and building the event. Units: beats per minute (doubles, unrounded, as Apple sends them).
- **Lifecycle.** A workout the wrist recovers after a kill keeps its stored samples, so the pair covers the whole session. A session ended by the phone (a followed end the wrist captures) uses the same samples. A sample stored after the end is never read (the end is built once). Samples pruned once the phone holds the session are gone only after the end was captured.
- **Settings changing while open.** None: the heart-rate permission only decides whether samples exist.
- **Time edges.** A reading exactly at the start or end instant counts; one a millisecond outside does not. Windows are normalised to wire resolution before comparing so the phone reading the entry's timestamps gets the same set of readings.
- **Load cost.** One pass over the session's samples and entries at the single moment of ending; a few thousand samples at most for a long workout.
- **Wording.** No user-visible words change.
- **Slot competition.** None (no screen). One wire entry grows by at most one pair plus one pair per set block; well inside the protocol's bounds (`setBlockHeartRates` is validated for uniqueness and ordering of the span, `message_validator.dart` 592-640).

## Scenarios

Fixture clock: session start `2026-01-05T10:00:00Z`, end `10:30:00Z`. Readings below are `heartRate` samples at `10:MM:SS`.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-31001 | `heartRate` over `[10:00:00, 10:30:00]`: 09:59:59 = 60, 10:00:00 = 100, 10:05:00 = 120, 10:10:00 = 140, 10:30:00 = 160, 10:30:01 = 180, 10:15:00 = 0.5, 10:16:00 = NaN, a `steps` sample at 10:20:00 = 999 | avg 130, max 160 (readings 100, 120, 140, 160 inclusive at both ends; 60, 180, 0.5, NaN and the steps sample ignored) | the function does not exist |
| S-31002 | no heart-rate sample in the window (only the 09:59:59 one); an empty list; only readings below 1 | null each time | a zero or a missing key would be sent |
| S-31003 | `blockSpans` over entries: `e1` set slotA/exA 10:02:00, `e2` set slotA/exA 10:06:00, `e3` set slotB/exB 10:12:00, `e4` timed slotC/exC 10:20:00, `e5` rest 10:13:00, `e6` set slotA/exA with an unparseable `loggedAt`, `e7` set with no `sessionExerciseId`; session start 10:00 | blocks `[A: 10:00:00 → 10:06:00, B: 10:06:00 → 10:12:00]` in that order (A leads from the session start, B from `e2`; the timed entry makes no block, the rest never leads, `e6` and `e7` make nothing) | the function does not exist |
| S-31004 | `blockSpans` with blocks interleaved (a superset), entries given out of order: A sets `a1` 10:02 and `a2` 10:08, B set `b1` 10:05, and two first sets of blocks C and D at the same instant 10:20:00 with entry ids `s-a` (C) and `s-b` (D), listed `s-b` first | `[A 10:00:00 → 10:08:00, B 10:02:00 → 10:05:00, C 10:08:00 → 10:20:00, D 10:08:00 → 10:20:00]`: A leads from the session start, B from A's first set, C and D from A's last set (the latest effort strictly before 10:20); the 10:20 tie breaks by `entryId` so C comes before D | an unsorted or id-blind version reorders blocks |
| S-31005 | engine: a wrist-created session with samples 10:01 = 100, 10:05 = 120, 10:10 = 140 and set entries `e1` slotA/exA 10:02, `e2` slotA/exA 10:06, `e3` slotB/exB 10:12, ended at 10:30 | `session_end` payload has `avgHeartRateBpm` 120, `maxHeartRateBpm` 140 and `setBlockHeartRates` `[A: 10:00:00Z → 10:06:00Z avg 110 max 120, B: 10:06:00Z → 10:12:00Z avg 140 max 140]` | `_sessionEndEvent` sends neither |
| S-31006 | the same session, no samples at all; and one whose samples fall outside every block span | no `avgHeartRateBpm`/`maxHeartRateBpm`/`setBlockHeartRates` keys; and the session pair present with `setBlockHeartRates` absent | a zero pair or an empty list would be sent |
| S-31007 | a followed session (source `phone`) with samples; and a session the phone deleted one set from (the deleted set's `entryId` in the engine's deleted ids) | the followed end carries the pair and `followed: true`; the deleted set is not a block member (block spans computed from `_entriesFor`, so a block whose only set was deleted is gone) | the followed path or the projection would be skipped |
| S-31008 | every `session_end` built in S-31005..S-31007 goes through the engine's emission validator; and a hand-built entry with `avgHeartRateBpm` above `maxHeartRateBpm` | the engine's own entries are accepted (no `WatchEmissionRejected`); the hand-built one is refused (proves the validator test is live) | an out-of-bounds pair would make the end unsendable |

Readers of the changed code (all must stay green): `test/wear_calories_test.dart` (S-30506 builds the same `session_end`), `test/watch_session_end_owed_test.dart`, `test/watch_session_capture_*` and every test that compares a `session_end` payload whole: grep `grep -rln "session_end\|sessionEnd" test` before building and run each file.

Mutation pass by the lead over every guard family (boundary inclusivity at both ends, the `>= 1` floor, finite check, kind filter, mean clamp, block lead-in rule, ordering/tie-break, strict-before lead-in, the three absent-key cases, followed path, the `_entriesFor` projection).

## Phases

| Phase | Agent | Scope | Marks |
|---|---|---|---|
| P1 | `crew-builder-watch` | `lib/watch/session/watch_sensor_summaries.dart`, `lib/watch/session/watch_session_engine.dart`, new `test/wear_heart_rate_session_end_test.dart` | serial. Exact code in the brief; the builder runs no gateway command (the gateway hangs for builders on this PC, see the progress file); the lead runs the tests |
| P2 | `crew-docs-keeper` | `docs/wear_os_app_sensors.md`, `docs/wear_os_app.md` (one owner check), plan evidence | after P1 and the mutation pass |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/wear_os_app_sensors.md` | ADDED | - | `The session end carries the heart rate` | S-31005, S-31006 |
| `docs/wear_os_app_sensors.md` | ADDED | - | `one pair for each set block` | S-31005, S-31003 |
| `docs/wear_os_app.md` | ADDED | - | `25. (owner) on a real Wear watch paired with an Android phone` | D-31004 (owner check) |

Stale-term sweep (`grep -rIn "sends none\|carries no heart\|no heart-rate" docs | grep -v "docs/plans\|docs/history\|docs/releases"`): the only Wear hits are none; `docs/watch-app-setup-and-qa.md` line 601 and `docs/watch_session_sync.md` line 418 describe the Apple wrist and stay.

## Assumption Log

- A-1: the phone's importer and validator treat the heart-rate fields identically for any wrist (read from `message_validator.dart` and the importer's grep hits; no platform branch). Not re-run against a Wear fixture until P1's S-31008.
- A-2: the lowest reading that counts is 1 bpm, the protocol's own minimum (Apple's `lowestHeartRateBpm`), not the plan 311 pause logic.
- A-3: scope guard (`pr-scope-guard`): about 40 production lines plus one test file and two doc lines; well inside the budget.

## Progress

| Item | Status |
|---|---|
| seed | Done |
| P1 build | Done |
| tests and mutation pass | Done |
| P2 docs | Done |
| commit | Open (owner's standing instruction: commit each verified PR) |
| owner check 25 | Open, needs a real Wear watch paired to a phone |
