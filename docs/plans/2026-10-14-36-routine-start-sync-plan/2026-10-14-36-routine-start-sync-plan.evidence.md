# Plan 36 — routine start sync: evidence

Phases A, B, B-fix-1 and C are done and green. Sources:
`.work/crew/2026-10-14-36-routine-start-sync/report-A.md`, `report-B-fix-1.md`,
`report-C.md` (builder-B's own report is not on disk; its fixture changes are
recorded below from the tests as they now stand, read this run).

## Baselines

| Check | Before | After |
| --- | --- | --- |
| `flutter analyze` | 182 issues (lead, base `4b7a002`) | 182 (`report-B-fix-1`, `report-C`; report A saw 183 mid-run — one transient `undefined_method` error in `watch_session_importer.dart` while Phase B was mid-edit, gone by B-fix-1) |
| Full suite | `+4640 ~1` | `+4697 ~1: All tests passed!` (exit 0), `03:01`, log `.work/gateway/test-20261015-001649-77978.log` (report C) |

## Red before green (as the reports quote them)

- **Phase A, S-3601…S-3603** (production code unchanged, `+0 -3`):
  ```
  +0 -1: … S-3601 a session of planned rows sends no entry [E]
    Expected: empty
      Actual: [ { 'entryId': 'entry-sl-1-0', … }, … ]
  +0 -2: … S-3602 only the set a rest follows is sent [E]
    Expected: ['entry-sl-1-0']
      Actual: ['entry-sl-1-0', 'entry-sl-1-1', 'entry-sl-1-2']
  +0 -3: … S-3603 a logged set with no reps is still no entry [E]
    Expected: empty
      Actual: [ { 'entryId': 'entry-sl-1-1', … }, … ]
  ```
  After items 1–3 of Phase A: `+3: All tests passed!` for the same selection.
  En route, the expected fixture migrations went red first: projection S-2 and
  S-31 (`+27 -2`) before the fixture rests, auto_push 41 of 54 red
  ("expected N frames, got []") before `logSet`/`markLastSetLogged`.
- **Phase B-fix-1, S-3618** (before the closing loop, Mock + Hive, 2 failures):
  ```
  00:00 +0 -1: Mock ... S-3618 ... [E]
    Expected: ... 'rest_end_ms': 1791195000000, ...
    Actual:   ... 'rest_end_ms': null, ...
   Which: at location [0]['rest_end_ms'] is <null> instead of <1791195000000>
  00:00 +0 -2: Hive ... S-3618 ... [E]  (same failure)
  ```
- **Phase C**: no red-before-green — test-only migrations; S-3610 needed no
  production change, so the stop-and-report rule never fired.

## Fixtures whose meaning changed

- **A — `test/watch_session_projection_test.dart` `add()`**: the default row of
  a new exercise is now a logged set (the fixture writes a rest behind it),
  preserving the pre-change behaviour where that row rode the answer; the row's
  other assertions are untouched. `seedSets` writes a rest for every set,
  including `skipped: true` rows — behaviourally identical, a skipped row has
  `reps: 0` and the wire rule omits it either way.
- **B/B-fix — `test/watch_session_merge_test.dart`**:
  - `S-11 the phone's own rows are the user's`: the fixture gained closed rests
    at 1 and 2, so the phone's two rows read logged and the wrist's set still
    appends after the last row (S-3611, plan open question 1).
  - `S-16 the live screen shows the merged set and keeps a running rest`: the
    phone's own rest at index 0 is now closed where the wrist's set landed; the
    expectation was rewritten — same record keeps id, `restStartMs` and
    `entryIndex`, `restEndMs == max(start, t1)`, not paused; the fill's rest at
    index 1 is the one open rest.
  - `S-320 a late rest tops up the set the phone already merged`: a set
    arriving alone now opens its own rest (D-6); the late rest closes that row
    in place rather than writing a second one.
  - `S-325 the phone's own rest at that spot wins`: the fixture now counts the
    phone's own closed rest at index 1, so row 0 reads logged; the wrist's set
    is recognised by its stamp as the phone's own row and the phone's rest
    record stands (D-216).
  - `S-337 a rest whose after-entry is gone is dropped and consumed`: asserts
    today's known limit — dropping the set deletes only its observation rows,
    so the rest its arrival opened stays, open.
  - `S-338 a rest after the last set takes the next index`: two rests now exist
    (one per set's arrival); selection moved from `restEndMs` singleWhere to by
    id — `rest-sl-1-2` keeps the wrist's window, `rest-sl-1-1` is closed at t2
    by the second set (A4, one rest at a time).
  - `S-3605 a second wrist set fills the next planned row`: was
    `restEndMs == [null, null]`; now `[_msOf(_t2), null]` — the second set ends
    the rest the first one opened.
- **C — `test/watch_live_refresh_screen_test.dart`**:
  - `S-3514 a wrist merge fills the planned row in place` (renamed from "leaves
    the open entry and its rest alone"): the wrist's set FILLS row 1 — three
    entries, row values checked, `Set 2 of 3` and not `of 4`, LOGGED with no
    Log Set (position unmoved, S-3617), two rests with exactly one open at
    index 2.
  - `S-3515 the set the wrist logged is offered no second log`: one entry
    carrying the wrist's reps and load, one rest with the wrist's window; the
    old control's premise (a wrist set with no rest behind it) is unreachable
    under the fill rule — every imported wrist set opens a rest — so the
    control was rebuilt on a phone-planned, never-logged row of the next effort.

## Doc claim → test

| Claim (docs/watch_session_sync.md) | Test (file · exact name) |
| --- | --- |
| A planned row is sent as nothing; the wrist's menu shows no "N logged" for it | `test/watch_session_projection_test.dart` · `S-3601 a session of planned rows sends no entry` |
| A set is logged exactly when a rest sits at its index + 1; only that set rides | `test/watch_session_projection_test.dart` · `S-3602 only the set a rest follows is sent` |
| The `reps < 1` wire rule still omits a logged set with no reps | `test/watch_session_projection_test.dart` · `S-3603 a logged set with no reps is still no entry` |
| A wrist set fills the first unlogged planned row in place and opens its rest | `test/watch_session_merge_test.dart` · `S-3604 a wrist set fills the planned row and opens its rest` |
| A second wrist set fills the next planned row, not a new one | `test/watch_session_merge_test.dart` · `S-3605 a second wrist set fills the next planned row` |
| A fourth set appends once every planned row is logged | `test/watch_session_merge_test.dart` · `S-3606 a fourth set appends once the planned rows are filled` |
| The phone's own logged set is never filled | `test/watch_session_merge_test.dart` · `S-3607 the phone's own logged set is never filled` |
| The wrist's `rest` closes the fill's rest in place; a finished rest stands | `test/watch_session_merge_test.dart` · `S-3608 the wrist's rest closes the rest the fill opened` |
| A skipped planned row is not logged, so the wrist fills it | `test/watch_session_merge_test.dart` · `S-3616 a skipped planned row is not logged, so the wrist fills it` |
| The wrist's set ends the phone's older open rest — one rest at a time | `test/watch_session_merge_test.dart` · `S-3618 the wrist's set ends the phone's older open rest` |
| A history import still appends after the user's rows | `test/watch_session_merge_test.dart` · `S-11 the phone's own rows are the user's` |
| The filled row reads LOGGED on the screen, no second log, rest strip runs | `test/watch_live_refresh_screen_test.dart` · `S-3514 a wrist merge fills the planned row in place`, `S-3515 the set the wrist logged is offered no second log`, `S-3610 a wrist set fills the row the screen is on` |
| The filled row is not echoed back to the wrist (its stamp claims it) | `test/watch_routine_round_trip_test.dart` · `S-3609 the set the wrist logged is never echoed back to it` |
| Dropping a set leaves the rest its fill opened (known limit) | `test/watch_session_merge_test.dart` · `S-337 a rest whose after-entry is gone is dropped and consumed` |