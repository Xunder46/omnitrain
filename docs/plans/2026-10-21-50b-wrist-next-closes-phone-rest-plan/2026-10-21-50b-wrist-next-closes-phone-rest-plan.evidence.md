# Evidence — plan 50b (Next on the watch ends the phone's rest)

Proof date: 2026-10-21 (lead: unit tests, mutation pass). Docs and evidence: docs keeper, 2026-10-21.

## Test table (scenario → test → file)

| Scenario | Test | File |
|---|---|---|
| S-7401 the phone logged set 0 on effort E (rest open from T); a wrist `rest` event `afterEntryId: 'entry-E-0'`, window T..T+90 s closes the phone's rest, still one row | `S-7401 a wrist rest after a phone-logged set closes the phone's running rest` | `test/watch_session_rest_phone_entries_test.dart` |
| S-7402 the same for a timed instance entry and a round instance | `S-7402 the same for an entry on a timed effort`, `S-7402 the same for an entry on a round effort` | same file |
| S-7403 an unknown effort (`entry-nope-0`) or an index beyond the entries (`entry-E-9`) is dropped, nothing written | `S-7403 a rest naming an unknown effort or an index beyond the entries is dropped` | same file |
| S-7404 a finished phone rest stands (the wrist's later report does not rewrite it) | `S-7404 a finished phone rest stands` | same file |
| S-7405 redelivery of the same event writes nothing the second time | `S-7405 a redelivered rest event writes nothing the second time` | same file |

Count: 6 tests (S-7402 is two tests).

## Verified

- The tests above green (lead, 2026-10-21), Mock harness.
- Governor mutation pass over the series: 12 of 12 mutants red.
- `WatchSessionImporter._applyRests` resolves an unplaced `afterEntryId` through `_phoneEntry` (seen in `lib/core/services/watch_session_importer.dart` this run, working tree).

## Not verified

- The two devices live: the Simulator could not be driven. Owner checks: Next on the watch ending the phone's rest chip for a set logged on the phone.

## Docs

- `docs/state_management/watch_surface_wrist.md`: the new paragraph names the importer resolving a phone-logged `afterEntryId`, citing S-7401..S-7405.
- `docs/rest_tracking.md`, "The Wrist's Rest": Next on the watch closes the phone's open rest whichever device logged the set, citing S-7401..S-7405.
