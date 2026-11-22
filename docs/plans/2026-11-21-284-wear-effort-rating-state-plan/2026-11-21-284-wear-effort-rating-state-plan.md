# Plan 284 — The Wear wrist's effort-rating state (series 283, unit b)

Series 283: 283a (committed `8cda033a`) the wrist reads the phone's settings; **283b = this plan** the effort-rating state: the engine can record and recognise a session's rating, the wrist remembers that a rating is owed across a kill, and one state class holds the prompt's logic; **283c** the prompt screen and its shell/menu wiring. Wrist only, `lib/watch/`. No wire, phone or schema change (`observations_up` already carries `effort_rating`). Nothing on screen changes in this unit: no surface reads the new state until 283c. Base commit: `.work/2026-11-21-284-wear-effort-rating-state/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

Mirror the Apple wrist's `WatchEffortRating.swift` and the engine's `hasEffortRating`/`recordEffortRating` on the Dart wrist, so that 283c is only a screen:

- The engine appends the session's effort rating once (`entryId`/`eventId` `rating-<sessionId>`), emits it to the phone, and never edits or doubles it; it knows a session already has one when the row is held, **or the phone acknowledged it and the row was pruned** (otherwise a pruned rating would be asked for again), **or the phone's snapshot carried its own** (the phone answered first).
- `WatchEffortRatingState.end()` finishes the session and, when the phone's setting asks for a rating, the session holds at least one effort entry after the phone's deletions and has no rating yet, stores a `rating_prompt` row so a kill before the answer still asks at the next launch.
- The state holds the prompt: the question, the 1 to 5 scale and its two end labels (the contract's words), nothing preselected, a pick by tap or by detents (the first step up picks the lowest number, further steps move one each and stop at the ends, stepping down never returns to nothing and from nothing picks nothing), Confirm only with a number picked, Skip closing the question without recording anything (remembered only while the app runs), most recent owed session first.

Acceptance: S-28401..S-28418 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/watch_session_engine_test.dart`, `test/watch_phone_preferences_test.dart`, `test/watch_nutrition_quick_log_test.dart`, `test/watch_session_start_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; no new red in the full suite; Docs delta applied.

## Feature invariants

- The store stays append-only: no new store method (S-004 in `test/watch_session_engine_test.dart`).
- The rating is session-scoped: it names no slot; at most one per session; the phone's own rating is final (PROTOCOL.md authority rule 4).
- Copy and scale come from `watch/contract/watch_effort_rating_contract.json`; a test holds the Dart constants to that file (as the Apple suite does).
- The Swift `WatchEffortRating.swift` and `WatchSessionEngine.swift` (`hasEffortRating`, `recordEffortRating`) are the reference.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28401 | `WatchObservationKind.effortRating = 'effort_rating'` (added to `all`, never to `efforts`) and `WatchSessionCapture.effortRatingId(sessionId) => 'rating-$sessionId'`. | `watch_records.dart` 58-100; Swift `WatchRecords.swift` 63, 102 |
| D-28402 | New record `WatchRatingPromptRecord` (`recordType` `rating_prompt`, `recordId` `prompt-<sessionId>`, `sessionId`, `recordedAt`): the wrist's own note that its End owed this session a rating. Registered in `WatchRecord.fromJson`, `WatchStoreContents.ratingPrompts` (default `const []`, in `isEmpty`), both stores' `readAll`, and the Hive `_allRows` type list, exactly as 283a did for `WatchPreferencesRecord`. | `watch_records.dart` `WatchPreferencesRecord`; the stores; Swift `WatchRatingPromptRecord` |
| D-28403 | The engine remembers acknowledged observation ids: a private `Set<String> _acknowledgedIds`, rebuilt in `restore()` from every `WatchConfirmationRecord.observationIds` in `contents.confirmations` and extended in `confirmObservations` with the ids it acknowledges. `pruneConfirmed` does not touch it. | `watch_session_engine.dart` `restore` (134-190), `confirmObservations` (2033-2068), `pruneConfirmed` (2072); Swift `acknowledgementLog` |
| D-28404 | `bool hasEffortRating(String sessionId)` = `_acknowledgedIds.contains(id) || _heldRecord(id) != null` with `id = WatchSessionCapture.effortRatingId(sessionId)`. `Future<WatchObservationRecord?> recordEffortRating(int rating, {required String sessionId})` returns null (no row, no emission) when `hasEffortRating`; else `_appendObservation({'entryId': id, 'eventId': id, 'kind': effort_rating, 'loggedAt': utcIso(_clock()), 'rating': rating}, sessionId: sessionId)`. The validator refuses a rating outside 1..5 (`WatchEmissionRejected`), as for any event. | Swift `WatchSessionEngine.swift` 2258-2288; `_appendObservation` (1693-1745), `_heldRecord` (1267) |
| D-28405 | New class `WatchEffortRatingState` in `lib/watch/logging/watch_effort_rating_state.dart` (a `ChangeNotifier`): constructor `(engine:, store:, preferences:, clock:)`; `restore()` reads `store.readAll().ratingPrompts`; `end()` (D-28406); owed-prompt getters `owedSessionIds` (rows whose session has no rating and was not skipped, newest `sequence` first), `promptSessionId`, `isPromptOwed`; `title`, `scale`, `lowestLabel`, `highestLabel` from `WatchEffortRatingCopy` constants; `selected` (null until a pick), `canConfirm`, `select(int)`, `step(int detents)`, `skipPrompt()`, `confirm()`. The crown/rotary mapping is the screen's job (283c, via `WatchRotaryTurn`): the state takes detents. | Swift `WatchEffortRating.swift` 87-309 (without the Digital Crown position bookkeeping `turnCrown`, which is watchOS-view plumbing) |
| D-28406 | `end()`: no active session returns null. Else `owed = preferences.asksForEffortRating && engine.entries.any(kind in efforts) && !engine.hasEffortRating(sessionId)` is decided BEFORE `finishSession()` (the phone's deletions are known only to this process); then `finishSession()`; when owed, append `WatchRatingPromptRecord(recordId: prompt-<id>, ...)` to the store (a second note is a store no-op) and remember it; notify; return the ended session. | Swift `end()` 141-165, `noteOwedPrompt` |
| D-28407 | `WatchEffortRatingCopy` (same file as the state): `title 'How hard was this session?'`, `lowest 1`, `highest 5`, `lowestLabel 'Very easy'`, `highestLabel 'Max effort'`, `skipLabel 'Skip'`, `promptBeforeFirstSync false`. A test reads `watch/contract/watch_effort_rating_contract.json` and holds each constant to it. | contract file; `test/watch_effort_rating_copy_parity_test.dart` (phone side) |
| D-28408 | Not in scope: any screen, the menu's End calling `end()`, the launch-time presentation, the shell wiring (283c); the Digital-Crown reading; the Swift side. | series plan |

## Input-reality checklist

1. **Writers.** The rating is written by `recordEffortRating` only (and by the phone's snapshot entry, which the engine already stores). The prompt row is written by `end()` only. Readers: `hasEffortRating`, the state's owed list.
2. **Lifecycle.** Owed at End then answered; owed then killed and relaunched (restore); owed then the phone answers first (snapshot carries `rating-<sessionId>`: the question closes); owed then the phone acknowledges the rating the wrist sent and the row is pruned (still known: `_acknowledgedIds`, restored from stored confirmations); a session with no effort entry (everything the phone deleted) owes nothing; a session already holding a rating owes nothing.
3. **Settings changing while open.** The setting is read at End only (`asksForEffortRating`); a later change does not retract a stored owed row (Swift the same).
4. **Time.** `recordedAt` and `loggedAt` use the injected clock.
5. **Load.** `entries` is rebuilt per read: `end()` reads it once; the owed getters read `hasEffortRating` per prompt row (a handful).
6. **Words.** No existing doc line names a Wear rating; `docs/wear_os_app.md` says it is missing (the Apple-hosts-more paragraph), which 283c changes; this unit adds an engine-level sentence only (Docs delta).
7. **Competition.** None (no UI).

## Scenarios

Engine, records and stores in `test/watch_effort_rating_engine_test.dart` (new, P1; plain `test()`, Mock store, Hive round trip for S-28405 and S-28407); the state in `test/watch_effort_rating_state_test.dart` (new, P2).

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28401 | an active session (one `set` slot); `recordEffortRating(4, sessionId)` | returns a row with `entryId` and `eventId` `rating-<sessionId>`, `kind` `effort_rating`, `rating` 4, `loggedAt` the clock; exactly one `observations_up` frame emitted carrying it | the method does not exist |
| S-28402 | the same call twice (second with 2) | the second returns null; one row; one frame; the held rating is still 4 | a second rating is stored or emitted |
| S-28403 | `hasEffortRating`: before any call false; after the call true; for another session id false | false / true / false | the check ignores the id |
| S-28404 | a rating of 0 and of 6 | `WatchEmissionRejected` thrown (with the engine built over the real schema validator, as `test/watch_session_engine_test.dart` builds one), nothing stored | a bad rating is stored |
| S-28405 | record a rating, `confirmObservations([ratingId])`, `pruneConfirmed()`, then `hasEffortRating` (same engine; then a NEW engine over the same store after `restore()`, Mock then Hive) | true both times, and the row is gone from `observations` | a pruned rating is forgotten and would be asked again |
| S-28406 | the phone's `session_snapshot` carrying an `effort_rating` entry with id `rating-<sessionId>` (shape: PROTOCOL.md "The phone MAY answer first"; build it as `test/watch_session_engine_test.dart` builds a snapshot with entries) | `hasEffortRating` true; `recordEffortRating` returns null and emits nothing | the phone's answer does not close the question |
| S-28407 | `WatchRatingPromptRecord` appended through each store (Mock, Hive); a new store read | `readAll().ratingPrompts` holds it with its fields; appending the same `recordId` twice leaves one row | the record is not registered in the stores or `fromJson` |
| S-28408 | `WatchObservationKind.effortRating` | equals `'effort_rating'`, is in `all` and is NOT in `efforts` | an effort rating counts as work done in a slot |
| S-28409 | state: the contract file `watch/contract/watch_effort_rating_contract.json` vs `WatchEffortRatingCopy` | title, scale min/max, the two labels and `promptBeforeFirstSync` equal the file | a constant drifts from the contract |
| S-28410 | state: preferences asking (a copy with `effortRatingPrompt: true` applied), a session holding one logged set; `end()` | the session is completed; `isPromptOwed` true; `promptSessionId` that session; one `rating_prompt` row stored | End does not record the owed prompt |
| S-28411 | the same with the setting off; a session with only a rest and no effort entry; a session that already holds a rating; a wrist that never heard from the phone | each: ended, `isPromptOwed` false, no `rating_prompt` row | the owed rule ignores one of its four conditions |
| S-28412 | the phone deleted the only effort entry before End (apply a `structure_change` delete) | no prompt owed | owed is decided from the raw rows and ignores the phone's deletions |
| S-28413 | `end()` with no active session | null; nothing stored | End without a session writes a row |
| S-28414 | owed, then a NEW state over the same store after `restore()` | `isPromptOwed` true for the same session | the owed note is held only in memory |
| S-28415 | owed for two sessions A then B (B ended later) | `owedSessionIds` is `[B, A]`; confirming B's rating makes A the prompt | the order is oldest first or the answered one stays |
| S-28416 | picks: `step(+1)` from nothing -> 1; `step(+3)` from nothing -> 3; `step(-1)` from nothing -> still null; `select(4)` then `step(+5)` -> 5 and `step(-10)` -> 1; `select(0)`, `select(6)` ignored | as stated | the pick rules differ from the Apple state |
| S-28417 | `canConfirm` false with nothing picked, true after `select(3)`; `confirm()` with nothing picked returns null and records nothing; `confirm()` after `select(3)` | records `rating-<id>` with 3 through the engine, clears `selected`, the session owes nothing more | Confirm records without a pick |
| S-28418 | owed, `select(2)`, `skipPrompt()` | `isPromptOwed` false, `selected` null, NO rating row, the `rating_prompt` row still stored; a NEW state after `restore()` asks again; a phone-side rating arriving later still closes it | Skip records a rating, or loses the owed note |

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "write the report FIRST as a skeleton". Serial.

1. **P1 — records, stores, engine** (`crew-builder-watch`; scope `lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_store.dart`, `lib/watch/session/in_memory_watch_session_store.dart`, `lib/watch/session/hive_watch_session_store.dart`, `lib/watch/session/watch_session_engine.dart`, `test/watch_effort_rating_engine_test.dart`). Items D-28401..D-28404, S-28401..S-28408. About 110 lines of production.
2. **P2 — the state** (`crew-builder-watch`; scope `lib/watch/logging/watch_effort_rating_state.dart`, `test/watch_effort_rating_state_test.dart`). Items D-28405..D-28407, S-28409..S-28418. About 200 lines.
3. **P3 — docs** (`crew-docs-keeper`, no test run).
4. **Lead:** mutation pass, full suite.

Predicted production code about 310 lines in 6 files plus one new, one track: inside the budget.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | ## The effort rating, underneath | S-28401 |
| docs/wear_os_app.md | ADDED | - | nothing on the Wear screen asks for it yet | S-28410 |

Stale-term sweep: `grep -rIn "effort-rating prompt" docs | grep -v "docs/plans\|docs/history\|docs/releases"` hits the Apple-hosts-more paragraph of `docs/wear_os_app.md` and unrelated Apple/phone pages; they stay until 283c shows the prompt.

## Assumption Log

- The Dart engine has no acknowledgement log of its own; `WatchConfirmationRecord` rows in the store carry the acknowledged ids (verified: `confirmObservations` appends one, `pruneConfirmed` deletes only observations), so D-28403 rebuilds the set from them.
- `WatchObservationKind.all` has no reader outside `watch_records.dart` (grep over `lib`); adding `effortRating` to it changes nothing at runtime.
- The `observations_up` schema already accepts `effort_rating` (`observations_up.schema.json` line 80), so the engine's `_requireConformant` validates the new event without a schema edit.
- Swift's prune also drops a `rating_prompt` row once its session is pruned; the Dart store has no session-pruning path today, so the Dart prompt rows live as long as the store (a handful of small rows).

## Progress

- [x] P1 records, stores, engine
- [x] P2 the state
- [x] P3 docs
- [x] Mutation pass, full suite
