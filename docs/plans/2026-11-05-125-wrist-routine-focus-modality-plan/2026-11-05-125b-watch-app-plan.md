# Feature: 125b — the wrist starts a routine with the routine's Focus; the phone starts sending it

> Status: SEEDED, revision 2 after owner feedback (the held-empty-session branch is now a marked, cuttable EDGE; the phone-started-routine gap is a separate follow-up, 125d). Ready for build (NOT started). Parent: `2026-11-05-125-wrist-routine-focus-modality-plan.md` (INDEX: evidence, Q1-Q3, owner checks). Built on 125a (committed, `19006457`): the schema, both validators, the Dart wrist copy of `WatchRoutine.focusModality` and the phone importer already exist.
> Track: watch (Swift package + its Dart copy) + one phone line. No contract file, schema, fixture or View changes. Base commit: `19006457`.
> Next handoff: crew-builder-watch (phases A and B), crew-builder-app (phase C), all parallel; then docs (phase D).
> Evidence → `…125b-watch-app-plan.evidence.md`; review → `…125b-watch-app-plan.review.md` (beside this file, created by the build).
> Owner already accepted: Q1 (phone sends only together with this watch update), Q2 (Cardio focus = Running, Sports focus = Other; reuse the watch's table), Q3 (Cardio/Sports focus turn GPS on and say "Intervals"/"Periods"). Not re-asked.
> **OWNER DECISION 2026-11-06: the relaunch EDGE is CUT** (D-12561's cut line taken). Built: the plain version only. NOT built: `carryFocus`, the `modality` parameter of `transitionTo`, the `session_end` first-row fix (D-12562, D-12569), the held-empty-session branch work, scenarios S-12563, S-12564, S-12566, S-12567 (S-12565 stays retired), docs rows 3 and 5, owner check 3. Everything below marked CUT is kept only so ids are never reused. `WatchSessionEngine.swift` is not touched by 125b.
> Another session (plan 129, wrist planned button) has UNCOMMITTED hunks in six files this plan also edits: see "Shared files". 125b edits only its own lines there.

## Goal and acceptance

A routine with a Focus (say Stretching), started from the routine list on the Apple Watch, runs as a Stretching workout on the wrist and arrives that way on the phone:
- Apple Health on the watch records it as Flexibility (not "Other"); Cardio focus = Running, Sports focus = Other (Q2).
- A Cardio or Sports Focus routine turns the wrist's location on from the start and calls rounds "Intervals" / "Periods" (Q3).
- EDGE (cuttable, see D-12561): the one way a person reaches a routine pick over an EMPTY wrist session is after the watch app was relaunched while the Free workout list was open (the empty workout is restored and the Start screen shows the routines again). That pick fills the empty workout and gives it the routine's Focus, like the phone, where a routine pick silently replaces an empty session.
- NOT in this plan: a routine started on the PHONE and followed by the wrist (see "Gap found: routines started on the phone", follow-up 125d).
- The session the phone receives (`session_end`) carries that modality, so the calendar shows the Focus colour and name (125a already links the routine and falls back to the template Focus).
- The phone sends `focusModality` in `routines_down` for every routine that has one, and omits it for a routine that has none. A Focus-only edit on the phone reaches the wrist on its next sync.
- A routine with no Focus, an unknown Focus, or a phone that predates the field: the wrist behaves exactly as today. The wrist's own modality survives a phone snapshot. No screen changes.

## Findings from the code (read, not run; the INDEX outline is amended by these)

| # | Finding | Consequence |
|---|---|---|
| F-1 | **Focus-only edit does bump the stamp.** `RoutineState.updateRoutineFocusModality` sets `updatedAtMs` to now (`lib/state/routine/routine_state.dart:213-227`) and the autosave persists that copy via `createTemplate` (an upsert, `_persistDraft`). Independently, the phone's `since` gate compares the SERIALISED text of the preferences + routines + foods frames, not only `updatedAt` (`watch_sync_request_handler.dart:_sendRoutines`, the `held.referenceText == referenceText` test), and the Hive revision listener moves on any `_templatesBox` write (`hive_workout_repository.dart:_listenForReferenceWrites`). | **No fix needed.** Pin it with a test (S-12576, S-12577). The first request after the phone update also re-sends (a relaunched phone has no `held`, so the stamp is new; existing S-9212). |
| F-2 | **`session_end` reads the modality from the session's FIRST row.** `captureSessionEnd` → `sessionEndEvent(origin…)` uses `creationRow(sessionId)` = lowest `sequence` (`WatchSessionEngine.swift:1771-1775, 1701`). A modality stamped on a LATER row (only the EDGE does that) would never reach the phone. | **Matters only for the EDGE.** The plain path creates the session with its modality on the first row. D-12562 belongs to the EDGE and is cut with it. |
| F-3 | **The shipped watch app builds its engine with no validator** (`ios/OmniTrain Watch App/ContentView.swift:165`, `WatchSessionEngine(store:onEmit:)`, `validator` defaults nil; `SyncProtocolValidator.incomingRejections(nil, …)` returns `[]`). | Q1's premise ("an old watch rejects the whole list") holds only for a build that injects a validator (tests, tools). The shipped old watch would ignore the unknown key. The owner's Q1 default stays (single install, phone gate = this PR), the risk is lower than the INDEX says. Recorded; no new question. |
| F-4 | **The stored routine catalog is re-serialised through `WatchRoutine.toJson()`** (`WatchRoutinesDown.toRecord` → `routines.map { $0.toJson() }`, restored by `init(catalog:)`). | `toJson` must carry `focusModality` or a watch relaunch forgets the Focus (S-12569). |
| F-5 | A phone `session_snapshot` already keeps the wrist's modality (`modality: existing?.modality`, `WatchSessionEngine.swift:601`; Dart `watch_session_engine.dart:557`). | S-12505 holds today; pin it so the new `carryFocus` stamp is not undone (S-12568). |
| F-6 | The Dart wrist engine has no `session_end` (only the Swift one does). | Dart copy needs parse + start + stamp only. |
| F-7 | 125b's emit gate is the whole safety story for Q1: the sender and the readers must land in one commit. | D-12566. |
| F-8 | **Reachability of the held-empty branch (owner question 1).** The watch's Start screen is shown whenever there is no active session WITH an exercise (`ios/OmniTrain Watch App/ContentView.swift:496-499`: logging only when `status == active && !exercises.isEmpty`). Tapping "Free workout" opens the picker as a modal sheet over the routines (`WatchStartView.swift:272-275, 242-247`), so the routines cannot be tapped while it is open, and closing it without a pick abandons the empty workout (`cancelIfNothingPicked`, `:308`, `cancelEmptyFreeWorkout`). The only other `createSession` caller is `startFromRoutine` itself, and both pass `modality: nil` (`WatchStartPaths.swift:713, 725`); the wrist has no tile or other start. **By hand it is reachable only if the app is relaunched or evicted while the Free workout list is open:** `restore()` keeps the empty active row (`WatchSessionEngine.swift:143-166`, no empty check) and the Start screen then shows with the routines enabled; plan 129's planned-start button reaches the same branch deliberately (`startPlanned`'s `filledInPlace`, `WatchStartPaths.swift:529-546`). | Reachable, but only by that relaunch edge. Kept as a small EDGE with a cut line (D-12561). My earlier "Sports tile" fixture was wrong: no such wrist start exists (S-12565 retired). |
| F-9 | **A routine started on the PHONE after an empty Free workout on the watch.** The wrist's empty session does not protect itself: a snapshot naming another session is refused only while the wrist holds an active session WITH exercises (`WatchSessionEngine.swift:571-579`), so the phone's new routine session is applied and becomes the wrist's current session. `session_snapshot` carries NO modality: the validator lists `modality` only for `session_end` (`message_validator.dart:149`) and the snapshot row copies `existing?.modality`, which is nil for a different session (`WatchSessionEngine.swift:601`). The wrist therefore follows the routine's exercises but not its Focus: Health type is the majority of the exercises' own types (`forSession` falls back to `forExercises`), GPS follows the current exercise, rounds say "Rounds". The phone's own calendar entry is right (plan 122 stamps the Focus; a followed session's end is HR-only, `followed:true`). | **A real gap, not fixed by 125b.** It is the common case (phone-started routine, wrist watching). Smallest fix = follow-up 125d (below), a separate PR. |

## Decision Ledger

| ID | Decision | Cites |
|---|---|---|
| D-12560 | **Reading the field.** Swift `WatchRoutine` gains `focusModality: String?` (tolerant parse: only a non-empty `String` is kept; a number, null, array or `""` is nil and NEVER throws, so a malformed Focus cannot make the whole list unreadable) and a computed `startModality: String?` = the Focus only when it is a key of `WatchActivityTypes.byModality`, else nil. `toJson()` emits the key only when set. The memberwise `init` gains `focusModality: String? = nil` so existing callers compile. The Dart copy already parses and round-trips (125a); it gains the same `startModality` getter. The INDEX said "dropped silently when unknown"; storing the raw key and filtering at use has the same observable result and keeps `toJson` faithful. | `WatchRoutineRecords.swift:282-335`, `lib/watch/start/watch_routine_catalog.dart:186-250`, `WatchPlatformWorkout.swift:62`, `lib/watch/sensors/watch_platform_workout.dart:67` |
| D-12561 | **CUT LINE TAKEN (owner, 2026-11-06): only the PLAIN half is built; the EDGE text below is history.** **`startFromRoutine` carries the Focus.** PLAIN (core): new session `createSession(modality: routine.startModality, exercises: …)`. EDGE (cuttable, F-8): in the held, active, EMPTY branch, if the held session has no modality and the routine has a `startModality`, call the new engine method `carryFocus(_:)` BEFORE the slots are inserted, then insert the slots as today (no `started` lifecycle, no snapshot for the stamp, `moveTo: false`; S-178 unchanged); a routine without a usable Focus leaves the held session exactly as today. **Cut line:** if the owner would rather not carry this edge, delete `carryFocus`, the `modality` parameter of `transitionTo`, the F-2 fix (D-12562), the held half of `startFromRoutine`, scenarios S-12563, S-12564, S-12566, S-12567 and the Docs delta rows 3 and 5; the plain version is complete without them (~25 fewer production lines). Mirrored in `lib/watch/start/watch_session_start_paths.dart` and `lib/watch/session/watch_session_engine.dart`. | `WatchStartPaths.swift:685-722` (current), `watch_session_start_paths.dart:176-200` |
| D-12562 | **CUT (not built).** **EDGE only: `session_end` carries the newest row's modality** (Swift only, F-2). `captureSessionEnd` passes `newest?.modality ?? origin.modality` (newest = highest `sequence` row of the session) into `sessionEndEvent`, which keeps its `if let modality, !modality.isEmpty` rule. Rows a phone snapshot writes copy the wrist's modality (F-5), so the newest row always holds it; a session the phone started and the wrist followed has none either way. | `WatchSessionEngine.swift:1651-1702, 1771` |
| D-12563 | **No change to the Health table, GPS policy or round words** (Q2, Q3 accepted): they read `session.modality`, so they follow. Known and accepted consequences, written in the docs: a Cardio-focus routine of squats registers as Running with GPS on; a Sports-focus routine registers as "Other" with GPS on. | `WatchPlatformWorkout.swift:62-98, 182, 222-240`, `WatchLoggingState.swift:608-615, 886` |
| D-12564 | **The phone emits it.** `buildRoutinesDown` adds `'focusModality': focus` to a routine map when `template.focusModality` is non-null AND non-empty, verbatim (no enum on the wire; the wrist filters). `''` is omitted: the schema's `minLength:1` would otherwise make a validating wrist refuse the list. Never `null`. The key goes between `updatedAt` and `segments`. | `lib/core/utils/watch_reference_sync.dart:136-146`, schema `routines_down.schema.json` (`focusModality`, 125a) |
| D-12565 | **Contract files untouched** (schema, fixtures, manifest, envelope, `watch_start_paths_contract.json`, validators): 125a did all of it and this PR adds no wire shape. One `PROTOCOL.md` history-row sentence changes (the row says the phone does not emit yet). Cross-client parity for the Focus table is carried by the same four-row table in the Swift and Dart tests (below) instead of a new section in the shared contract file, which keeps 129's file free of a second plan's hunks. | `PROTOCOL.md:854` |
| D-12566 | **Emit gate = one commit.** Phases A, B and C land in the same commit; the lead does not commit C without A. If A or B is not green, C is dropped and the phone keeps not sending (Q1). | INDEX Q1 |
| D-12567 | **No view, no string, no layout.** No `*View.swift` or Screen file gains a line from 125b (S-12582 is a lead check). The wrist shows no Focus label (INDEX scope). | INDEX S-12506 |
| D-12568 | **New code avoids the append-only verbs** in `watch/watchos/Sources` (`update`, `delete`, `remove`, `replace`, `edit`, `overwrite`, `write`, `clear`, `purge`, `wipe`, `reset`, `drop`, `truncate`, `erase`, `forget`, `modify`, `mutate`, `destroy`, `set`): names used are `carryFocus`, `startModality`, `focusKey`. | crew playbook (r), (ac) |
| D-12569 | **CUT (not built; `carryFocus` does not exist).** **Concurrency.** `carryFocus` goes through the engine's `mutex.exclusive` like every transition, and "first modality wins" is decided INSIDE the exclusive section (`session.modality ?? modality`), so a second stamp, an `exercise_push` insert or a snapshot interleaved with the start cannot overwrite it. | `WatchSessionEngine.swift:1244-1300` |

## Scenarios

Table columns: ID · fixture (exact) · expected · why it fails without the change. Swift tests: new file `watch/watchos/Tests/WatchSessionEngineTests/WatchRoutineFocusTests.swift` (copy the private `TokenHarness` block from `WatchSlotTokenTests.swift` as the harness; it builds the engine + start paths and syncs a `routines_down`). Dart wrist tests: new file `test/watch_routine_focus_start_test.dart` (copy the `_Harness` block from `test/watch_session_start_test.dart`). Phone tests: new file `test/watch_routine_focus_send_test.dart`, plus the one flipped test in `test/watch_routine_link_import_test.dart`. Existing files that Plan 129 also modifies are NOT edited by 125b.

Focus table used by S-12560/S-12561 on BOTH wrist clients (same four rows + legacy): `isometric_stretching` → Health `flexibility`, GPS off, word "Rounds"; `resistance_lifting` → `traditionalStrengthTraining`, GPS off, "Rounds"; `cardio_endurance` → `running`, GPS on, "Intervals"; `sports` → `other`, GPS on, "Periods"; `conditioning_mixed` (legacy key) → `crossTraining`, GPS off, "Rounds".

| ID | Fixture | Expected | Fails without the change because |
|---|---|---|---|
| S-12560 | Wrist holds routine R (2 efforts) with `focusModality` = each row of the table; no live session; `startFromRoutine(R)` | `session.modality` = the key; the lifecycle `session_started` frame is unchanged; Health type, `WatchGpsPolicy.isRequired(session)` and `roundsLabel` equal the table row | `startFromRoutine` passes `modality: nil`, so every row reads "other", GPS off, "Rounds" |
| S-12561 | Dart wrist: same table, same routine | same expectations through `WatchActivityTypes.forModality(session.modality)` and `ModalityDisplay.getRoundsLabel` | the Dart copy passes `modality: null` |
| S-12562 | Routine with Focus `isometric_stretching`; start (new-session branch), log one hold, End | the emitted `session_end` observation has `modality == "isometric_stretching"` | needs S-12560's fix |
| S-12563 | CUT (owner, not built). EDGE. Free workout started (`modality` nil, 0 exercises, active), then the engine and start paths RELAUNCHED on the same store (`restore()`; this is how a person reaches it, F-8); `startFromRoutine(R)` with Focus `isometric_stretching` | `session.modality == "isometric_stretching"`; the routine's slots are in template order with the user still on index 0; NO new `session_started` lifecycle frame and no extra snapshot for the stamp (only the snapshot the slot inserts already send); the Health lifecycle action for that session is `.start` with type `flexibility` (it was "waits" while empty) | held branch fills slots only; modality stays nil and the workout waits for the majority rule |
| S-12564 | CUT (owner, not built). EDGE. Same held empty Free workout; routine with NO Focus | `modality` stays nil; slots fill as today (S-178 result identical) | guards that the stamp is conditional on the routine having a Focus |
| S-12565 | RETIRED: it assumed a tile-started empty session, which the wrist cannot do (F-8) | none; the first-modality-wins rule is the engine's concurrency guard, proved by S-12566 | nothing: the state it guarded cannot be reached on the wrist; the id is kept so it is never reused |
| S-12566 | CUT (owner, not built). EDGE. `carryFocus` called twice on one empty session with two different keys, the second inside an interleaved `insertExercise` (same task group) | the first key stays; the second call returns the held row unchanged; exactly one new session row for the first call | arm 2 of the first-wins guard (a stamp that checks outside the mutex lets the second land) |
| S-12567 | CUT (owner, not built). EDGE. Held-branch session (S-12563 fixture) is ended by the wrist (End) | `session_end` carries `modality == "isometric_stretching"` (the stamped, NOT the creation row's nil) | F-2: `sessionEndEvent` reads the creation row, which has no modality |
| S-12568 | (Built after S-12560 only; the S-12563 half is CUT.) After S-12560, the phone sends a `session_snapshot` for the same `sessionId` (phone echo, no modality key; `status: active`) | the wrist session row's `modality` is unchanged; a later End still emits the Focus (Swift); Dart: `session.modality` unchanged | pins F-5/S-12505 against any later change of the snapshot path |
| S-12569 | Routine with Focus applied, engine + start paths relaunched on the same store (`restore()` ×2) | `routines[0].focusModality` is the key (both clients); the live session's modality is still the key | F-4: a `toJson` without the key loses it on relaunch |
| S-12570 | Adversarial parse, one routine per case in one `routines_down`: `focusModality` = `""`, `"Stretching"` (display name), `"ISOMETRIC_STRETCHING"` (case), `" cardio_endurance"` (leading space), `12` (number), `null`, `["sports"]`, `{}` | list applied (`applied == true`); every routine's `startModality` is nil; `""`/number/null/array/object give `focusModality == nil`; the three string cases keep the raw string (nil `startModality`); a session started from each has `modality == nil` and Health "other" by the existing majority rule; no throw | a parser that throws on a non-string (`requiredString`-style) drops the WHOLE list; a `startModality` that trusts the raw string types the session with an unknown key |
| S-12571 | Cardio-focus routine whose only efforts are squats (`reps,sets,load`) | `modality == "cardio_endurance"`, Health `running`, GPS required, "Intervals" (Q2/Q3, documented consequence, not a defect) | proves the accepted behaviour is the Focus table's, not the exercises' |
| S-12572 | Old phone → new watch: `routines_down` with NO `focusModality` anywhere (the existing `routines_down.json` fixture) | `focusModality == nil`, session as today (`modality == nil`) | INDEX S-12502 (regression guard for the default path) |
| S-12573 | Phone: template with Focus for each of `cardio_endurance`, `resistance_lifting`, `sports`, `isometric_stretching`; `buildRoutinesDown` | each routine map has `focusModality` equal to the template's, key order irrelevant, `updatedAt`/`segments` untouched | flips 125a's S-12514 (`buildRoutinesDown carries NO focusModality key`): today there is no key |
| S-12574 | Phone: template with `focusModality: null` | the map has NO `focusModality` key (`containsKey` false), not null | an `if (…!=null)`-less emit would send `null` and a validating wrist refuses the list |
| S-12575 | Phone: three templates in one build: Focus `sports`, Focus `''` (old data), Focus null; plus a fourth with an unknown key `legacy_unknown` | `sports` emitted; `''` omitted; null omitted; `legacy_unknown` emitted verbatim | `''` emitted would break `minLength:1`; an emit that filters on the wrist's table would drop the unknown key the phone should pass through |
| S-12576 | Request handler with a wrist whose `since` = the stamp of the first answer; then `RoutineState.updateRoutineFocusModality('sports')` on that template and its autosave runs; second request with the same `since` | a `routines_down` frame is sent again, stamped later than `since`, carrying `focusModality: 'sports'` (Mock repo AND a revision-moving repo from `test/helpers/revisioned_repository.dart`) | covers F-1 end to end; guards against a future "stamp from `updatedAt` only" optimisation |
| S-12577 | Same, but the edit is "Mixed / Not set" (`updateRoutineFocusModality(null)`) on a routine that had a Focus | `routines_down` re-sent, the routine has no `focusModality` key | `clearFocusModality` path of F-1 |
| S-12578 | `RoutineState.updateRoutineFocusModality(x)` on a template whose `updatedAtMs` is 1000 | `currentTemplate.updatedAtMs > 1000` (and equals the clock within the autosave), for a set and for a clear | direct pin of the F-1 stamp rule |
| S-12579 | `buildRoutinesDown` output for S-12573's four templates validated with the Dart `SyncProtocolValidator` (helper in `test/helpers/sync_protocol_harness.dart`) | zero rejections | proves the sender's real output conforms (schema from 125a), not only that the key exists |
| S-12580 | Relaunched phone (fresh handler, no `held`), wrist `since` older than now, templates with Focus | routines frame sent with the Focus (the existing wrist that holds the old list gets the Focus on its first request after the update) | without the emit the new field never reaches an already-synced wrist |
| S-12581 | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | empty | invariant |
| S-12582 | `git diff -U0 -- 'watch/watchos/Sources/WatchSessionEngine/*View*.swift' 'ios/OmniTrain Watch App'` compared with the pre-run snapshot | no 125b hunk (129's `WatchStartView.swift` hunks are the only ones) | a builder that adds a label or view line for the Focus would show here (D-12567); this is a lead check, not a test |

Stale-Focus case S-12507 (Focus changed on the phone after the wrist synced) is documented behaviour: the wrist keeps the old Focus until its next sync; S-12576 proves the sync happens. A session already running keeps its stamped modality (stamp at start, like the phone's 122 rule).

## Phases

All three build phases are disjoint in scope and independent (no phase needs another's output); they can run in parallel if the runner's writer cap allows, else A, then B, then C. At most one of them runs a full suite (none should: lead runs the suites). Every builder brief opens with "Never run the full `flutter test`" and the 6+ item briefs say "write the report FIRST as a skeleton".

### Phase A — Swift wrist (crew-builder-watch)
Items (3, after the owner's cut; items 2 and 3 of the old list are CUT and `WatchSessionEngine.swift` is not touched):
1. `WatchRoutineRecords.swift` `WatchRoutine`: `focusModality` (tolerant `focusKey`), `startModality`, `toJson`, memberwise default (D-12560).
2. `WatchStartPaths.swift` `startFromRoutine`: new-session branch passes `routine.startModality`; the held branch is left exactly as it is; refresh the doc comment that says "The session carries no modality" (D-12561).
3. New test file `WatchRoutineFocusTests.swift` for S-12560, 12562, 12568 (after S-12560), 12569-12572 (Swift halves).

Exact production code (checked against the current text):
```swift
// WatchRoutine
public let focusModality: String?
public init(routineId: String, name: String, updatedAt: Date, segments: [WatchRoutineSegment], focusModality: String? = nil)
// init(json:) → focusModality: Self.focusKey(json["focusModality"])
private static func focusKey(_ value: Any?) -> String? {
    guard let key = value as? String, !key.isEmpty else { return nil }
    return key
}
public var startModality: String? {
    guard let focusModality, WatchActivityTypes.byModality[focusModality] != nil else { return nil }
    return focusModality
}
// toJson(): build the dictionary in a var; `if let focusModality { json["focusModality"] = focusModality }`

// startFromRoutine: held branch UNCHANGED (the carryFocus half of this block was CUT by the owner)
// new-session branch: `modality: routine.startModality,`
```
`WatchActivityTypes` (an enum, `WatchPlatformWorkout.swift:53`) owns `byModality`; the value struct is `WatchActivityType`.

Predicted files (after the cut): `WatchRoutineRecords.swift` (+~20), `WatchStartPaths.swift` (+~4/-4), new `WatchRoutineFocusTests.swift` (~220). Scope (quoted globs): `"watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift"`, `"watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift"`, `"watch/watchos/Tests/WatchSessionEngineTests/WatchRoutineFocusTests.swift"`. The lead creates the empty test file first.
Done criteria (runnable, in the order a builder runs them):
- `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchRoutineFocusTests` → all green, count pasted.
- `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchSessionEngineTests` → green (the append-only guard lives here; filtered runs never select it otherwise).
- `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchSessionStartPathsTests` and `--filter WatchSlotTokenTests` → green (existing S-170/S-177/S-178/S-15003 untouched).
- `.github/copilot/scripts/macos/gateway.sh git-diff --stat -- <the four files>` → within Predicted Files; lead compares against the pre-run snapshot for 129's hunks.
Lead afterwards: full `swift test --package-path watch/watchos` (900 s timeout) and the scripted mutation pass (mutants: drop `startModality` filter; `focusModality` not in `toJson`; stamp in the held branch removed; `??` removed (overwrite); newest-row rule reverted to `origin.modality`; held-branch check `held.modality == nil` removed; `moveTo` flipped), run in an isolated copy of `watch/` (another session shares the tree).

### Phase B — Dart wrist copy (crew-builder-watch)
Items (3, after the owner's cut; the engine file is NOT touched): (1) `lib/watch/start/watch_routine_catalog.dart`: `startModality` getter (import `../sensors/watch_platform_workout.dart`); (2) `lib/watch/start/watch_session_start_paths.dart` `startFromRoutine` new-session branch passes `routine.startModality` + its doc comment (held branch unchanged); (3) new test file `test/watch_routine_focus_start_test.dart` (S-12561, 12568, 12569-12572 Dart halves).
Predicted files: the two lib files (+~10), the new test (~200). Scope: those four paths. The Swift package is not touched, so A and B may run in parallel.
Done criteria: `.github/copilot/scripts/macos/gateway.sh test -- test/watch_routine_focus_start_test.dart` green; `… test -- test/watch_session_start_test.dart test/watch_routine_focus_modality_test.dart test/watch_health_activity_test.dart` green (existing S-002/S-177/S-178 and 125a's round trip); `gateway.sh lint` issue count not above the plan baseline; invariant grep (S-12581) empty. Builders use `gateway.sh test -- <file>`, never `--plain-name`.

### Phase C — phone emits it (crew-builder-app)
Items (4): (1) `lib/core/utils/watch_reference_sync.dart` `buildRoutinesDown`: `if (focus != null && focus.isNotEmpty) 'focusModality': focus` (D-12564) and any doc comment that says the phone does not send it; (2) flip the S-12514 test in `test/watch_routine_link_import_test.dart` (it now asserts the key IS present for a Focus routine; rename to `S-12573 …`; the file is committed, not 129's); (3) new `test/watch_routine_focus_send_test.dart` with S-12573..S-12580 (copy the request-handler harness block from `test/watch_sync_changed_only_test.dart`: `_firstStamp`, the recording transport and the clock; do NOT edit that file, it is 129-modified); (4) the revision-moving arm of S-12576 uses `test/helpers/revisioned_repository.dart`.
Predicted files: `watch_reference_sync.dart` (+~3), `watch_routine_link_import_test.dart` (±15), new test (~260). Scope: those three paths.
Done criteria: `gateway.sh test -- test/watch_routine_focus_send_test.dart test/watch_routine_link_import_test.dart` green; `gateway.sh test -- test/watch_reference_sync_test.dart test/watch_sync_request_handler_test.dart test/watch_sync_changed_only_test.dart test/watch_sync_idle_reads_test.dart test/watch_transport_test.dart` unchanged (all were checked: every existing fixture builds templates with `focusModality: null`, so no exact-payload assertion sees a new key — verified by grep); `gateway.sh lint`; invariant grep.
Mutants (lead): drop the `isNotEmpty` check; emit null; emit only for `sports`; swap `updatedAt`/`focusModality` keys is not a mutant (order irrelevant).

### Phase D — docs (after A, B, C green; serial)
`crew-docs-keeper` executes the Docs delta rows 1-5 (docs/**), told "run no test", the QA list is `docs/watch-app-setup-and-qa.md`'s numbered owner steps (the keeper adds none unless this plan's owner checks are not there: name the list in its brief; do not let it pick). `crew-builder-watch` makes the one docs-only edit to `watch/sync_protocol/PROTOCOL.md` (row 6; the keeper's ceiling is `docs/**`). Then `plan-lint after`, reviewer (5 narrow questions), lead mutation pass, `pr-scope-guard`.

## Shared files with Plan 129 (uncommitted; read today with `git diff -U0` against HEAD `19006457`; line numbers are the working-tree lines)

125b's builds edit ONLY the lines named under "125b". Nobody runs `git checkout`, `git stash` or a formatter on these files. Before each run the lead saves `git diff -- <file>` to `.work/2026-11-05-125b/pre-<phase>-<name>.diff`; after it, the diff minus 125b's hunks must equal the snapshot.

| File | 129's hunks (do not touch) | 125b's lines |
|---|---|---|
| `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` | +85-92 (`WatchStartSurfaceCopy`), +310-313, +404-410, +416-452, +484-557 (planned-start path), +895-899 (`StoredWatchRecord` extension) | `startFromRoutine` and its doc comment, currently ~685-722 (between hunks +484-557 and +895); nothing else |
| `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` | +1355-1391 (`emitSessionStarted`) | **none after the owner's cut** (the file is not edited) |
| `lib/core/utils/watch_reference_sync.dart` | +36 (import), +162-251 (`buildPlannedDown`, after `buildRoutinesDown` ends at 157) | `buildRoutinesDown` routine map, ~136-146 |
| `watch/sync_protocol/PROTOCOL.md` | 129's `planned_down` / `session_started` table rows, two notes bullets, one history row (2026-11-06) | ONE sentence inside the committed 125a history row (~line 854): "so the phone does not emit the field yet — a later release turns the sender on…" |
| `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`, `WatchStartView.swift`, `WatchSessionStore.swift`, `FileWatchSessionStore.swift`, `SyncProtocolValidator.swift`, `WatchConnectivityBridge.swift`, `WatchSyncOrchestrator.swift` | all 129's (ten one-line `StoredWatchRecord` hunks in `WatchRecords.swift`, six view hunks in `WatchStartView.swift`, …) | **none** (125b needs no row type, no view, no validator change) |
| `watch/contract/watch_start_paths_contract.json`, `watch/sync_protocol/schemas/envelope.schema.json`, `fixtures/manifest.json`, `lib/core/sync_protocol/message_validator.dart`, `lib/state/watch/*`, `test/watch_reference_sync_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`, `WatchSessionStartPathsTests.swift`, `WatchSessionEngineTests.swift` | 129's (and the earlier 121a/127/128 leftovers shown by `git status`) | **none**: 125b adds new test files only |

At commit time the lead stages these four files with `git add -p` (they mix 129 and 125b hunks): `WatchStartPaths.swift`, `WatchSessionEngine.swift`, `watch_reference_sync.dart`, `PROTOCOL.md`. 125b lists no new file that 129 also creates.

## Docs delta

Rows 3 (`watch_session_sync.md` ADDED) and 5 (`watch_sensors.md` MODIFIED) are EDGE rows: DROPPED (the owner took the cut line in D-12561); they are removed from the table below.

Stale-term sweep (`grep -rIn "does not send it yet\|NO focusModality\|not emit the field\|has no field for one" docs watch lib test`, excluding plans/history/releases): hits are rows 1-3 and 6 below plus two code comments (`WatchStartPaths.swift:687`, `watch_session_start_paths.dart:173`, fixed by phases A/B) and the test name in `test/watch_routine_link_import_test.dart:181` (phase C).

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/watch_session_sync.md` | MODIFIED | `but the phone does not send it yet` | `the phone sends it whenever the routine has one` | D-12564 |
| `docs/watch_session_sync.md` | REMOVED | `S-12514 buildRoutinesDown carries NO focusModality key` | - | S-12573 |
| `docs/state_management/watch_reference_data.md` | MODIFIED | `and the phone does not send it yet.` | `and the phone sends it whenever the routine has one` | S-12573 |
| `docs/state_management/watch_sensors.md` | MODIFIED | `and a session with no modality — every Free workout —` | `every Free workout and` | S-12560 |
| `docs/my_routines.md` | ADDED | - | `a routine started on the watch carries the same Focus` | S-12560 |
| `watch/sync_protocol/PROTOCOL.md` | MODIFIED | `so the phone does not emit the field yet` | `the phone emits the field from the release that teaches the watch to read it` | D-12564 |

Each ADDED/MODIFIED sentence names its test (exact group/test name) as `crew-rules.md` requires. Docs touched are far below the 52,428-byte band (`watch_session_sync.md` 38,481; `watch_sensors.md` 31,751; `my_routines.md` 29,467; `watch_reference_data.md` 23,332).

## Input-reality checklist (answers)

- **Writers and units:** one writer (phone template → `routines_down`), one reader per client; the value is a modality KEY, not a unit. Display names, case variants and padded strings are not keys (S-12570).
- **Lifecycle:** the Focus is read at the moment of the start and stamped (like 122 on the phone); an edit after the wrist synced shows at the next sync (S-12507, S-12576); a running session keeps its stamp; a routine deleted on the phone is simply absent from the next list (125a S-12504 covers the end).
- **Settings changing while open:** none; no setting involved.
- **Time edges:** `updatedAtMs` is epoch ms; a Focus edit within the same millisecond as the previous edit would not change `updatedAt`, but the serialised text still changes (F-1), so the stamp moves.
- **Load cost:** one short string per routine in a message that is only sent when the stamp moved; no extra repository read.
- **Wording:** no UI string is added; docs say "Focus". The round words "Intervals"/"Periods" appear on the wrist exactly as on the phone for that modality (the wrist has no tile start of its own).
- **Slot competition:** a held empty session can receive a phone `exercise_push`, a second routine pick or a snapshot while `carryFocus` runs: all go through the engine mutex; first modality wins inside it (D-12569, S-12565, S-12566). The Health workout starts once (lifecycle `.start` on first known type); nothing re-registers mid-session (plan 40 D-4803 intact: S-12563 asserts the type is fixed at the stamp).
- **Waiting readers (rule "as"):** the phone still sends the same frames; only a key is added. No spinner, timeout or "no answer" line reads the routines frame differently.
- **Exact-payload readers:** nine test files build templates and `buildRoutinesDown` output (`watch_health_activity_test`, `watch_reference_sync_test`, `watch_routine_adoption_test`, `watch_session_adoption_bridge_test`, `watch_session_queue_test`, `watch_sync_changed_only_test`, `watch_sync_idle_reads_test`, `watch_transport_test`, `watch_routine_link_import_test`). Eight use `focusModality: null` (no new key); `watch_routine_adoption_test` seeds Focus templates for the ADOPTION path (it does not read the routines frame); the ninth is the S-12514 test this plan flips. Swift: `WatchSyncNoAnswerTests`, `WatchConnectivityBridgeTests`, `WatchPhoneProblemWiringSourceTests`, `WatchSlotTokenTests` and `WatchGpsByExerciseTests` call `startFromRoutine`/`createSession`; none builds a routine with a Focus, so none changes (confirm by the Done runs).

## Progress

- 2026-11-06: owner cut the relaunch EDGE (see the header). Plan edited to match what is built: phases A and B shrink to the plain version, the engine file is untouched, docs rows 3 and 5 and owner check 3 are gone.
- [x] Phase A — Swift wrist (built 2026-11-06 by crew-builder-watch; `WatchRoutineFocusTests` 7/0, `WatchSessionEngineTests` 1231/0, `WatchSessionStartPathsTests` 73/0, `WatchSlotTokenTests` 7/0, re-run by the lead)
- [x] Phase B — Dart wrist copy (built; `watch_routine_focus_start_test` 10/0; with `watch_session_start_test`, `watch_routine_focus_modality_test`, `watch_health_activity_test`, `sync_protocol_fixtures_test` 238/0, re-run by the lead)
- [x] Phase C — phone emits (built; `watch_routine_focus_send_test` + `watch_routine_link_import_test` + `watch_reference_sync_test` 54/0; `flutter analyze` on the touched files: no issues)
- [x] Phase D — docs (crew-docs-keeper; `plan-lint after` clean; `docs_indexing_contract` + `ui_standards_contract` + `sync_protocol_fixtures` + `watch_reference_sync` 253/0), PROTOCOL.md sentence (lead, one sentence), lead mutation pass 14/14 killed in an isolated copy; NO reviewer run (owner is watching token spend; the lead read every diff) and NO commit (governor commits by hunk)
- Deviations: (1) the PROTOCOL.md sentence was edited by the lead, not a builder run (one sentence, avoids a run); (2) the QA owner check is step 42 in `docs/watch-app-qa-wrist-logging.md` (the setup doc's pointer says new steps go there); `docs/watch-app-setup-and-qa.md` untouched; (3) a `watch_sensors.md` row was kept in the Docs delta (two sentences became false for a Focus routine start even in the plain version); (4) the brief's `gateway.sh swift-test -- --filter X` spelling does not work, the form is `swift-test --filter X`.
- Scope check (`pr-scope-guard`, at handoff): 223 lines, 4 phases, 10 decisions, 23 scenarios, ~110 predicted production lines, tracks watch + phone (no contract change). Only one soft signal (two tracks): within budget, no split. Revision 2 (owner feedback) removed one scenario (S-12565), marked five as EDGE, added no phase and no production code. `plan-lint before`: clean.
- Preflight for the build run: branch `claude_develop` (the owner's rule "always develop" is overridden by the checkout actually in use; never switch), `git rev-parse HEAD` → `.work/2026-11-05-125b/base.txt` (expected `19006457`), unrelated uncommitted files = Plan 129's and the 121a-128 leftovers listed in `git status`; `grep -rln "(owner)" docs/plans` for pending owner checks.

## Assumption Log

| # | Assumption | Basis | If wrong |
|---|---|---|---|
| A-1 | No crew agent was run for this plan: no scout, no architect. The seed carries exact code and pointers (as in plans 56/57/58-60), and a run costs tokens the owner is watching. | read the code and the committed 125a plan/evidence/review myself | add a scout for the one claim a reader doubts (F-2) |
| A-2 | The held-empty branch is a rare edge (relaunch with the Free workout list open, or plan 129's planned start), not the normal Free-workout-then-routine path, which the Start screen does not offer. Kept small and cuttable (D-12561). Owner to confirm keep or cut; building the core does not depend on it. | F-8; `ContentView.swift:496-499`, `WatchStartView.swift:242-308`, `WatchSessionEngine.swift:143-166` | Cut line in D-12561 |
| A-3 | The shipped watch has no validator (F-3), so an old watch ignores the key; the Q1 gate (one commit) is kept anyway. | `ContentView.swift:165`; `SyncProtocolValidator.incomingRejections` | none needed |
| A-4 | `WatchActivityTypes.byModality` is the right "known modality" set on both clients (it lists the four current keys plus the six legacy ones); the owning Swift type is the enum `WatchActivityTypes` (the INDEX wrote `WatchActivityType.byModality`; `WatchActivityType` is the value struct). | `WatchPlatformWorkout.swift:53-62`, `lib/watch/sensors/watch_platform_workout.dart:58-67` | compile error in phase A, caught at the first run |
| A-5 | The checkout in use is `claude_develop`, not `develop`. | `git status` header | n/a |
| A-6 | Writer cap allows A, B, C in parallel; otherwise they run in the order A, B, C. | `crew.env` | serial |

## Owner device checks (plain language; after 125b; add to the QA list in phase D)

1. Give a routine a Focus of Stretching, sync the watch, start that routine on the watch, log one hold, end it. Apple Health shows the workout as Flexibility, not Other.
2. Open the OmniTrain calendar: that day shows the Stretching colour and name and the routine's name (with the phone away or closed during the workout: same, via the import path).
3. CUT by the owner (the relaunch edge is not built; the id is kept so numbering stays stable).
4. Phone-started routine (NOT fixed here, see 125d): start the Stretching routine on the phone with the watch app open, note the watch's Health workout type: it follows the exercises, not the Focus, until 125d.
5. A routine with no Focus: still "Free Training" on the calendar and Other in Health. A routine of only squats with a Cardio Focus: the watch asks for location, says "Intervals" and Health shows Running (accepted, Q2/Q3).
6. Change a routine's Focus on the phone (or choose "Mixed / Not set"), wait for the watch to sync, start it: the new Focus applies.
7. Look at the 40 mm watch: nothing should look different.

## Gap found: routines started on the PHONE (follow-up 125d, NOT part of 125b)

What a person sees today: start a routine with a Focus on the phone while the watch app is open (even after an empty Free workout on the watch, which the phone's new session silently supersedes): the watch follows the exercises but not the Focus. Health on the watch is typed from the exercises, location follows the current exercise, rounds say "Rounds". The phone's calendar entry is correct.
Cause (F-9): `session_snapshot` has no `modality`; the wrist copies `existing?.modality`, nil for a new session.
Smallest fix, outlined only (plan it when 125b has landed): (1) contract: optional `modality` (string, minLength 1) on the `session_snapshot` payload, additive, fixtures + PROTOCOL row (`watch/sync_protocol/`); (2) phone: the snapshot projection in `lib/state/watch/live_session_mirror_state.dart` / the session projection adds the phone session's `modality` when set; (3) wrist: `applySnapshotExclusive` writes `existing?.modality ?? payload["modality"]` (Swift and the Dart copy). About 40 production lines on three tracks, so it is its own PR and its own plan under the budget (contract may ride with its first consumer). It reuses 125b's Health/GPS/round-word behaviour unchanged. Order: after 125b; it does not depend on the EDGE.

## Noticed, not in scope

- The wrist shows no Focus anywhere (INDEX: not in scope).
- A phone-started routine followed on the wrist still has no Focus on the wrist (a snapshot carries none).
- `crew` plan 125c (shared routine matcher) stays optional; 125a already extracted the matcher.
