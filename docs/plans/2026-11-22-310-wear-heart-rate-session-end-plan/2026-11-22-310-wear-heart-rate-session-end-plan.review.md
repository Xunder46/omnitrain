# Review: plan 310 (the Wear wrist's session-end heart rate) · P1+P2 · 9e2a064c..4dc74259

Verdict: APPROVE
Counts (the lead's run, pasted from the evidence file — the brief forbids gateway commands on this PC, so not re-run here): `flutter analyze` 174 issues, 0 errors (baseline 174); `test/wear_heart_rate_session_end_test.dart` 16 passed; reader files 1620 passed, 821 failed — every failure re-produced on a clean `9e2a064c` (Windows baseline), none new.

## 1. Wire bounds — OK

`_sessionEndEvent` cannot produce an entry the validator refuses, constraint by constraint:

- **avg above max** — impossible: `heartRate` clamps the mean into `[lowest, highest]` of the same qualifying set (`lib/watch/session/watch_sensor_summaries.dart:105-116`), so average ≤ maximum always; the equal-readings float-noise case is pinned by S-31009 `equal readings average to exactly their value` (test line 655).
- **one without the other** — impossible: `WatchHeartRateSummary.fields` always emits both (`watch_sensor_summaries.dart:26-30`); a block is added only when its pair is non-null (`watch_session_engine.dart:773-785`), and the session pair is spread only when non-null (787).
- **repeated (slot, exercise) block** — impossible: `blockSpans` groups by `blockKey` and emits one span per key (`watch_sensor_summaries.dart:157-176`); the validator's uniqueness check (`message_validator.dart:592-620`) can never fire on the output.
- **block `startedAt` after its `endedAt`** — impossible whenever the block survives: the lead-in is strictly before the first set (`watch_sensor_summaries.dart:180-183`), so only the session-start fallback could invert a span, and a window with start > end admits no reading (`at < first || at > last` holds for every sample, 99-100), so the pair is null and the block is dropped (engine 776-777).
- **schema-forbidden values** — none producible: readings are filtered to finite and ≥ 1 (`watch_sensor_summaries.dart:94-96`), so both fields meet the schema's `heartRateBpm` minimum 1 (`watch/sync_protocol/schemas/envelope.schema.json:392-395`); each block carries exactly the six required fields (`additionalProperties: false`, required six, timestamp refs — envelope.schema.json:407-441); `sessionExerciseId`/`exerciseId` are non-null strings by `blockKey`'s construction; `startedAt`/`endedAt` are `utcIso` output; `minItems: 1` is met by omitting the key when no block has a pair (engine 786-787).

Constraints the validator has that the plan did not list:

- the per-kind field table `_captureFieldKinds` (`message_validator.dart:141-157`): `avgHeartRateBpm`/`maxHeartRateBpm` only on `timed/round/hold/session_end`, `setBlockHeartRates` only on `session_end` — the plan gestures at bounds but never names the kind table;
- the block item schema's required-six / `additionalProperties: false` / `minItems: 1` / per-value `minimum: 1` / timestamp format (envelope.schema.json:379-441), none named individually;
- the plan's Input-reality checklist overstates the validator: "`setBlockHeartRates` is validated for uniqueness **and ordering of the span**" — no check rejects a span out of order or outside the session window (`_blockHeartRateRejections` checks duplicates and pairs only). Harmless, because as shown above the producer cannot emit one, but the claim is not the validator's. [Minor, plan text only]

Guard: S-31008 `a session_end the engine builds passes its own validator` (line 580) and `a hand-built pair above its maximum is refused` (line 621), the latter against the real schemas directory.

## 2. Ordering and pruning — OK

Every removal site and every capture site:

- samples: one `_sensorSamples.removeWhere` only, in `pruneSettledSensorSamples` (`watch_session_engine.dart:2330`), gated on the newest row being non-active AND no observation of the session awaiting a receipt (2318-2325, 2333-2336).
- observations: `pruneConfirmed` (2275-2278) and `pruneWaterTaps` (2295-2298). `pruneConfirmed`'s only caller under `lib/` is the debug surface (`lib/watch/debug/watch_session_debug_surface.dart:270`); `pruneWaterTaps` drops water taps only.
- `_captureSessionEnd` call sites: 658 (snapshot), 1006 (phone lifecycle end), 1623 (`_transitionTo`). All three capture BEFORE the terminal row is appended (D-16002).

So before a session's first end capture its newest row is still active — `pruneSettledSensorSamples` cannot yet have dropped its samples — and no production path drops its entries. After capture, the deterministic `sessionEndId` plus the `_heldRecord` guard (engine 823-825, 1335-1342) blocks any re-capture, so a later prune cannot be outrun. Residual hole, debug-only: after `pruneConfirmed` drops a confirmed end, a re-delivered terminal snapshot re-captures an end whose samples may already be settled-pruned — the same exposure the Apple original has (its `knowsObservation` guard reads the same live ledger), and unreachable in production. A session whose rows are gone from `_observations` reaches `_sessionEndEvent` only through that same debug path.

## 3. Behaviour preserved — OK

The old body (quoted in `.work/2026-11-22-310-wear-heart-rate-session-end/brief-builder-p1.md` item 2a: iterate the `observations` getter, filter `!_deletedEntryIds.contains(observation.entryId)`, keep the switch/sort/return "exactly as it is") vs the new `_entriesFor(_session?.sessionId)` (`watch_session_engine.dart:267-291`): the `observations` getter's predicate `observation.sessionId == _session?.sessionId` (215-219) is the same predicate `_entriesFor` applies with `sessionId = _session?.sessionId`; the deletions filter, the D-113.3 correction switch and the `_byLoggedAtThenEntryId` sort moved verbatim. Same rows, same projection, same order for every existing reader of `entries` — confirmed by the reader re-run in the evidence (no new failure). The only new caller, `_sessionEndEvent`, reads `_entriesFor(sessionId)` for the session that is ending, which is the point of D-31005 and the only behavioural addition.

## 4. Apple parity — OK

- `heartRate` (Dart 78-116 vs `WatchSensorSummaries.swift:88-121`): kind filter, `isFinite`, `>= lowestHeartRateBpm` (= 1 on both sides), inclusive window compared in whole milliseconds, mean clamped into `[lowest, highest]`, maximum = highest — rule for rule. The dropped `excluding pauses` parameter is plan 311's declared out-of-scope.
- `blockSpans` (Dart 136-189 vs Swift 254-293): sort by (ms, entryId); set-kind only; both-or-nothing slot/exercise key; lead-in = latest effort strictly before the first set (Dart's last-match loop equals Swift's `last(where:)` on the same sorted array); session-start fallback; endedAt = last set; spans in first-appearance order. No rule dropped or changed.
- `wireInstant`: identical shape (Swift 296-298).
- One structural difference with no behavioural effect: Swift writes the event's `startedAt`/`endedAt` from the normalised instants (`WatchSessionEngine.swift:2200-2201`); Dart writes them raw from `creation.startedAt`/`endedAt` (`watch_session_engine.dart:798-799`). In Dart `wireInstant` is an identity round trip (`utcIso` → `toIso8601String` keeps the instant, `parseUtcIso` parses it back — `lib/core/sync_protocol/wire_timestamps.dart:11-17`; the evidence's M20 EQUIVALENT), so the strings are the same; in Swift the normalisation is not identity because `wholeMilliseconds` rounds.

## 5. Docs honesty — OK

The new paragraph (`docs/wear_os_app_sensors.md:25-49`), sentence by sentence:

| Sentence | True of code | Test with that exact name |
|---|---|---|
| window = stored readings start→end, both ends included, < 1 bpm and not-a-number ignored | `watch_sensor_summaries.dart:92-101` | S-31001 `the window keeps the readings at both ends and ignores the rest` (149) and `each non-qualifying reading alone gives null` (171) ✓ |
| set block = one slot's sets; spans last-effort-before-first-set (or session start) → last set | `watch_sensor_summaries.dart:136-189` | S-31003 `blocks come out in the order they began, each over its span` (226); S-31004 `the tie at 10:20 breaks by entryId, and each block leads from its own effort` (293) ✓ |
| block with no reading in its span left out; session with no readings sends none of it, never zero | engine 776-787, `heartRate` null | S-31006 `a session with no heart-rate samples sends none of the keys` (423) and `readings outside every block span keep the session pair only` (446) ✓ |
| wrist-created and phone-ended alike | all three `_captureSessionEnd` sites share `_sessionEndEvent` | S-31007 `a followed session carries the pair and followed: true` (484) ✓ — nuance: the test ends a `source: 'phone'` session from the wrist; no test in the file drives a phone-sent lifecycle end with samples. The code path is the shared one, so the sentence is true; the tie runs through the followed end. [Minor] |
| phone already reads the fields for any watch, nothing changes there | `lib/core/services/watch_session_importer.dart:2423-2424, 2503, 2549-2550` | reader tests exist (`watch_session_import_test.dart`, `watch_followed_end_import_test.dart`) ✓ |
| validator's acceptance | engine validates its own emissions | S-31008 `a session_end the engine builds passes its own validator` (580) and `a hand-built pair above its maximum is refused` (621) ✓ |
| pair's bounds and the session's isolation | clamp; per-session sample/entry filters | S-31009 `equal readings average to exactly their value` (655) and `an earlier session's sets and a skewed reading never reach the next session's end` (674) ✓ |
| "Not sent yet": per-effort heart rate and pausedMs (plan 311), steps | no such code in the diff | n/a — forward-looking ✓ |

`docs/wear_os_app.md:578` carries check 25 as the Docs delta describes.

## Overall

APPROVE — no blocker, no major; two Minor notes (the plan's "ordering of the span" validator claim, and the followed-vs-phone-ended nuance in the docs tie), neither needing a code change.
