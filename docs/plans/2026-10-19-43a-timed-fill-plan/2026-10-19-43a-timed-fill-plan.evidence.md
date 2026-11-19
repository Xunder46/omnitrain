# Evidence — plan 43a (a watch interval fills the phone's unfinished interval)

Phase P3 (docs keeper), 2026-10-19. Every claim below was checked against the
files named this run; every test name was read from its test file this run.

## Baselines (from the lead's report, quoted in the brief)

| Check | Before | After |
| --- | --- | --- |
| `flutter analyze` | 181 | 181 (unchanged) |
| `flutter test` (full suite) | — | `+5072 ~1` after P1 (the builder ran it; the lead re-runs it at the end) |

## Test table (scenario → test → file)

`test/watch_timed_fill_test.dart` runs every scenario twice, under group
`Mock` and group `Hive`.

| Scenario | Test (group · name) | File |
| --- | --- | --- |
| S-5001 a wrist timed entry fills the unfinished interval | `Mock` / `Hive` · `S-5001 a wrist timed entry fills the unfinished interval` | `test/watch_timed_fill_test.dart` |
| S-5002 a running, then a paused, phone interval is filled (D-6) | `Mock` / `Hive` · `S-5002a a running interval is filled`, `S-5002b a paused interval is filled` | `test/watch_timed_fill_test.dart` |
| S-5003 every interval finished: the entry appends (A-51 behaviour) | `Mock` / `Hive` · `S-5003 every interval finished: the entry appends` | `test/watch_timed_fill_test.dart` |
| S-5004 two wrist entries: fill, then append | `Mock` / `Hive` · `S-5004 two wrist entries: fill, then append` | `test/watch_timed_fill_test.dart` |
| S-5005 a redelivery writes nothing | `Mock` / `Hive` · `S-5005 a redelivery writes nothing` | `test/watch_timed_fill_test.dart` |
| S-5006 a hold fills a drill effort's unfinished interval | `Mock` / `Hive` · `S-5006 a hold fills a drill effort's unfinished interval` | `test/watch_timed_fill_test.dart` |
| S-5007 a round fills the unfinished round | `Mock` / `Hive` · `S-5007 a round fills the unfinished round` | `test/watch_timed_fill_test.dart` |
| S-5007b the filled interval is the wrist's own (not sent back) | `Mock` / `Hive` · `S-5007b the filled interval is the wrist's own` | `test/watch_timed_fill_test.dart` |
| S-5010 a hole in the row numbers: the fill keeps the pairing | `Mock` / `Hive` · `S-5010 a hole in the row numbers: the fill keeps the pairing` | `test/watch_timed_fill_test.dart` |
| S-5011 a half-written earlier pass is finished in place | `Mock` / `Hive` · `S-5011 a half-written earlier pass is finished in place, never another interval` | `test/watch_timed_fill_test.dart` |
| S-5008 the open timed effort: the fill lands, the phone's running timer stops, no exception | `S-5008 a watch interval fills the open timed effort and the phone's running timer stops` | `test/watch_timed_fill_screen_test.dart` |
| S-5009 the same for a round effort | `S-5009 the same for a round effort` | `test/watch_timed_fill_screen_test.dart` |

## Proof mutations (the lead, 2026-10-19)

13 mutations applied by hand to the shipped code, each restored byte for byte
after its run. 12 made a named test red; the lead's report names these:

- the fill target skipping nothing, for timed and for round;
- the timed and the round instance not deleted;
- the half-written-pass guard (`unfinished == null`) off;
- `rowNumber` ignored;
- `rowNumber` ignored together with the row deletion;
- a history import filling too;
- the screen never dropping finished timer state;
- the drop skipping rounds.

1 mutation is an equivalent mutant kept as defence in depth: removing ONLY the
deletion of the doomed rows — `createObservation` stores by id, so the wrist's
rows at the same number overwrite them.

## Crash finding (D-5, stated plainly)

The phone crash the owner saw is NOT reproduced. The lead ran S-5008 and the
state tests with the fill disabled (the old append behaviour) on Mock and Hive:
only count mismatches — no exception, no store error. The cause is unknown; the
owner is asked to run `flutter run 2>&1 | tee ~/omnitrain-run.log` next time it
happens and send the file.

## Not in this plan (pending)

- A timer started on one device does not run on the other: plan 43b.
- Finishing on the phone does not stop a running watch timer: plan 43c.
- A-1 stands as assumed: a running or paused phone interval is filled and
  stopped by the watch's entry; 43b's owner question 3 may refine it.

## Docs changed in Phase P3

- `docs/state_management/watch_surface.md` — the held-merge interval fill and
  the screen's `_dropFinishedTimerState` added to the `WatchIncomingRouter`
  section, with test names (~1 KB added; file stays under the 52 KB band).
- `docs/watch_session_capture.md` — one sentence in "Why an import waits for
  the session end": a timed, hold or round entry in the live merge fills the
  first unfinished interval, and appends only once every interval is finished.
- `docs/watch_session_sync.md` — left alone. The brief's target sentence
  (in-progress timed/hold/round entries reaching the other device only once
  finished) does not exist in the file (greps for `only once`, `in-progress`,
  `finished`, `append` read this run); its wrist-logging sentence is about
  `set` rows and stays accurate. Net size unchanged.
- `docs/modality_based_exercise_ui.md` — left alone. It states nothing about
  what happens when the watch logs an interval (its only wrist mention is the
  Edit-Discard restore rule, unaffected by 43a).
- This evidence file, and the plan's Progress table and Status line.

## Pending

- `crew-reviewer` (the lead runs it).
- Owner checks: the two interval checks on real hardware, and the crash log if
  the phone crashes again.
