# Feature: 50b — Next on the watch ends the phone's rest

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (reviewed with 50a: no finding of its own beyond the unnecessary await, fixed). Swift 688/0, Flutter +5411 (one unrelated flaky test, S-5115, fails in some full runs and passes alone), analyze 180 (baseline). Series: `docs/plans/2026-10-21-49-watch-food-and-rest-series.md`. Scout: `.work/crew/2026-10-21-49/scout-rest-phone.md` Q3.

## Goal and acceptance

When you tap Next on the watch's rest screen, the phone's rest chip stops, whichever device logged the set. Today it stops when the set was logged on the watch (the importer places the wrist's own entry) but NOT when the set was logged on the phone: the wrist's `rest` event names a phone-logged entry (`entry-<slot>-<n>`) that the importer does not know, so the event is dropped and the phone's rest keeps counting.

## Decision Ledger
- D-1 `WatchSessionImporter._applyRests` (`lib/core/services/watch_session_importer.dart:~1187`): when `_placed[afterEntryId]` is null, resolve a phone entry id of the form `entry-<effortId>-<n>` (the ids `PhoneEntries` mints: `'entry-$sessionExerciseId-$entryIndex'`, `phone_entries.dart:375`) to `(effortId, position n)` provided `<effortId>` is one of the session's efforts and an entry with index `n` exists on it (a logged set row, a timed/round instance: read how the other phone-entry readers decide existence). The rest's `entryIndex` is then `n + 1` exactly as for a placed wrist entry, and the existing branches apply unchanged: a finished phone rest stands (D-216); a running one takes the wrist's window and closes in place (D-7).
- D-2 A row whose `afterEntryId` matches neither a placed wrist entry nor an existing phone entry is dropped as today (S-323, S-328, S-337).
- D-3 Not in scope: sending the phone's rest (50a), pausing, any wire change.

## Scenarios (ids S-7401.. checked free) in `test/watch_session_rest_timer_append_test.dart` (its Mock/Hive openers) and the importer tests it already uses
- S-7401 the phone logged set 0 on effort E (rest `rest-E-1` open, `restStartMs = T`); a wrist `rest` event `afterEntryId: 'entry-E-0'`, window T..T+90 s arrives: the phone's rest is closed with `restEndMs = T+90 s` and still one row.
- S-7402 the same for a timed instance entry and a round instance (one test each: `entry-E-0` on a timed effort, `entry-E-0` on a round effort).
- S-7403 an unknown effort (`entry-nope-0`) or an index beyond the entries (`entry-E-9`) is dropped, nothing written.
- S-7404 a finished phone rest stands (the wrist's later report does not rewrite it) for a phone-logged entry.
- S-7405 redelivery of the same event writes nothing the second time.
- Run both Mock and Hive (stored-data rule).
Mutation list: fallback dropped, `n + 1` -> `n`, effort-membership check dropped, existence check dropped.

## Phases
P1 (crew-builder-app, 4 items): tests first, importer change. Scope: `lib/core/services/watch_session_importer.dart`, `test/watch_session_rest_timer_append_test.dart`, `test/watch_session_rest_phone_entries_test.dart` (new if the existing file's harness is private).
