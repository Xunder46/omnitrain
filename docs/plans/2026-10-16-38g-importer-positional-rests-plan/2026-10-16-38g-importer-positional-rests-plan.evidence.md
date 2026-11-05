# Evidence — plan 38g (the watch importer reads and writes rests by position)

Docs-keeper record of the scenario → test mapping. No pass counts here: the
lead adds them. Every test name below was read from its test file on
2026-10-16.

## Scenario → test

| Scenario | Test file › name | What it proves |
|---|---|---|
| S-4501 | `test/watch_session_merge_test.dart` › group `S-4501..S-4507 a rest is keyed on the POSITION` · `S-4501 after the phone deleted a middle set the wrist's set opens its rest at its POSITION + 1, not the row number + 1` | Hole, a wrist set appends: the arrival rest sits at the appended set's position + 1 (`rest-sl-1-3`, open from the wrist's `loggedAt`), not at the row number + 1. |
| S-4502a | same group · `S-4502a the wrist's late rest report closes the rest the appended set opened` | Hole, the wrist's rest report in a later message closes the rest the arrival opened, in place (stamps from the report, no second rest). |
| S-4502b | same group · `S-4502b the same, with the set and its report in one message` | The same, with the set and its report in one message — the same-pass `_placed` write carries the position. |
| S-4503 | same group · `S-4503 a wrist set after the phone's delete fills the first unlogged POSITION and opens its rest there` | Hole, a wrist set fills a planned set after the hole (the first unlogged position) and its rest sits at the filled position + 1; the row past it stays planned. |
| S-4504 | same group · `S-4504 a fill below an open rest leaves that rest running` | An open rest of a later set is not closed by a wrist set that fills an earlier planned set; the arrival rest opens between them. |
| S-4505 | same group · `S-4505 the phone's delete of a wrist set re-keys the rests the merge wrote` | A middle wrist set deleted through the live mirror: its rows go, its rest goes, the later rest moves one down keeping its stamps and open state. |
| S-4506 | same group · `S-4506 the delete re-keys by position where the numbers and the positions disagree` | Positions 0 logged / 1 unlogged / 2 logged, wrist set 0 deleted: the re-key follows positions, so `EntryRows.loggedSetNumbersOf` reads position 0 unlogged and position 1 logged. |
| S-4507 | same group · `S-4507 the delete of the only wrist set takes its rest with it, once per change` | The only wrist set deleted: its rest goes with it; a redelivered delete changes nothing and raises no failure. |
| S-4508 | `test/entry_rows_test.dart` › group `S-4508 restsAfterDelete` | The pure rule: the rest at `deletedIndex + 1` is dropped, every higher rest re-keys one down (id `rest-<effortId>-<newIndex>`, stamps and open/paused state kept), rests below stay, null when no rest sits at the mark or above, empty list when the mark was the only rest. |
| S-4509 | same group · `S-4509 a retry of the pass that wrote the appended set opens no second rest, and leaves the one it left closed` | A pass that stopped before marking the row applied leaves the set's rows (number 3) and a closed rest at 3; the retry re-places at the same spot and opens no second rest. |
| S-4510 | same group · `S-4510 the delete of a wrist set appended after a hole re-keys the effort's rests by POSITION` | Deleting a wrist set whose number (3) differs from its position (2): the rest at 3 goes, the phone's own rests 1 and 2 are untouched. |
| S-4511 | same group · `S-4511 two wrist sets in one message fill two POSITIONS, not the same one twice` | After a hole, two wrist sets in one message fill the two planned sets after it; rest 2 closes at the second set's time, rest 3 opens. |
| S-4512 | `test/entry_rows_test.dart` › `S-4508 restsAfterDelete` · `the kept rests come back in entry-index order` | Unsorted input comes back sorted by index. |

The merge group runs every scenario twice — `main` wraps the same fixtures in
`group('Mock', …)` and `group('Hive', …)` — so each row above is asserted under
both repositories.

The same rule serves the phone's own delete: `TimerManager.rekeyEntryRestsAfterDelete`
calls `EntryRows.restsAfterDelete` (`lib/state/workout/timer_manager.dart`),
and `test/entry_delete_rests_test.dart` (group
`${harness.name} — deleteEntry takes the rest with the entry`,
S-4301..S-4304) is unchanged by this plan.

## Not changed

- Timed, hold and round wrist deletions: the importer does not re-key their
  instances or rests (plan D-4); nothing there turns row numbers into
  positions.
- No scheduled-ping cancel on a mirror delete: the importer has no notification
  service, so the live mirror's delete of a watch-logged set cancels no rest
  ping; a running rest of the deleted set simply disappears from the store.
