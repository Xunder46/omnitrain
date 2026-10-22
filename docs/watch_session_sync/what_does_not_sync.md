# Watch Session Sync — what does not sync

Part of [Watch Session Sync](../watch_session_sync.md): the list of what stays on one device, and the reasons. Split out of that page on 2026-10-21 to keep it under the documentation size ceiling; nothing in the text changed.

---

Wrist logging is not on this list any more: a set logged on the wrist reaches
the phone's live session as a row of the effort the phone's slot already has,
filling the first row the phone reads as unlogged in place or appending when
every row is logged (`test/watch_session_merge_test.dart`, `S-9 a wrist set
reaches the live phone session`), a rest the wrist took arrives as a `rest`
observation the importer
writes into the session's history
(`test/watch_session_summary_integration_test.dart`, `S-329 the totals`), a
wrist end closes the phone's copy
(`test/watch_session_finish_test.dart`,
`S-4 the wrist ends its session, roster of logged sets first`), and a set logged
while the phone was out of reach arrives at the wrist's next sync
(`test/watch_session_merge_test.dart`, `S-19 a set logged while the phone was out
of reach`). None of these is phone→wrist any more: the sets the phone has
logged ride the frame the phone sends — its answer to a Sync, or the push a
change triggers — as `entries`, which the wrist's existing snapshot merge
stores, and a `set` slot's planned rows ride the same frame on the slot itself
as `plannedSets` (above)
(`test/watch_session_projection_test.dart`,
`S-31 the phone's own sets arrive as entries`, and the wrist adopting a session
it does not hold — `S-38 the wrist adopts a session it does not hold`). What
remains out is listed below.

- **A set the wire cannot carry is omitted.** A skipped set, or one whose stored
  reps are below 1, has no place in the protocol's `set` shape
  (`additionalProperties: false`, `reps` ≥ 1), so it is left out of the answer
  and stays on the phone, with its weight. A set the wire can carry rides its
  load as the set's one `loadKg`: on an exercise without a `load` capability that load is
  the set's extra-weight row
  (`test/watch_bodyweight_load_test.dart`,
  `S-8006 a no-load set's extra-weight rides as loadKg, a with-load set's
  weight does, 0 omits the key, and below the floor omits the entry`), while a
  hold's added weight stays `extraLoadKg`
  (`lib/core/sync_protocol/phone_entries.dart`). A set the wire *can* carry is
  carried with its sign: a
  band-assisted set reaches the wrist as a negative `loadKg`, down to the wire's
  floor (`WireLimits.minLoadKg`, D-58/D-59). The floor is one number, which the
  three schema minimums, the projection and the wrist's dial all state (D-59) —
  so a weighted row *below* it is omitted like any other the wire cannot
  carry, and a row with no load is carried without a `loadKg` key at all (D-60). A
  rejected entry would reject the whole snapshot
  (`test/watch_session_projection_test.dart`,
  `S-59 a snapshot carries the assist, and omits only the row without reps`;
  `S-60 the floor is carried, one step below it is not`;
  `test/watch_wire_limits_test.dart`,
  `S-061 the three schema loadKg floors are the one constant`).
- **All four entry kinds are carried: `set`, `timed`, `hold` and `round`.** D-39
  projected `set` entries only; D-130 completes it — a slot's kind decides which
  records it projects, so a `timed` or `hold` slot sends its `TimedInstance`s (the
  window, and the distance the effort's metric carries) and a `round` slot its
  `RoundInstance`s (its `roundNumber` and the time it spent paused), while the
  ladder still carries every slot (`test/watch_session_projection_test.dart`,
  `S-140 a phone timed entry reaches the wrist`,
  `S-141 a round and a hold carry their own fields`,
  `S-142 a wrist-logged entry of any kind is not doubled`;
  `test/watch_session_engine_test.dart`,
  `S-145 the twin applies the phone's timed, hold and round entries once each,
  with the phone's fields, and a re-statement doubles nothing`).
- **A kind's claim rule is its own.** A `timed` row claims a `timed` record and
  never a `round` record written in the same millisecond, so neither kind is
  doubled or lost (`test/watch_session_projection_test.dart`,
  `D-133 a timed row never claims a round record written at the same millisecond`).
  The push's ledger reads the same rule against the row a claim came from, so the
  deletion it announces names the row the projection left out
  (`test/watch_session_adoption_bridge_test.dart`,
  `S-144 the ledger holds the row whose stamp claimed a record, not the record's
  position in the phone's list`).
- **An instance the wire cannot express is omitted, never faked.** An instance
  that never started, and a window of no length, carry no entry at all; a
  distance of exactly 0 is left out of the fields a `timed` entry would otherwise
  carry, and so is the added weight of a hold held with nothing added
  (`test/watch_session_projection_test.dart`,
  `S-143 an unrepresentable instance is omitted, not faked`,
  `D-132 a hold held with nothing added is projected without the field`).
- **A set's load rides as its one `loadKg`, and a skipped set does not ride at
  all.** An entry's `loadKg` is the set's load, whole: on an exercise with the
  `load` capability it is the weight row, the set's own total; on one without
  it is the extra-weight row, the set's added weight
  (`test/watch_bodyweight_load_test.dart`,
  `S-8001 a wrist push-up set with loadKg 10 keeps it in the extra-weight row,
  and a bench set is unchanged`;
  `S-8006 a no-load set's extra-weight rides as loadKg, a with-load set's
  weight does, 0 omits the key, and below the floor omits the entry`).
  `extraLoadKg` stays the hold/drill path's added load
  (`lib/core/sync_protocol/phone_entries.dart`), so a set's added weight
  reaches the wrist as the set's `loadKg` and never as a second number. A set
  with no reps
  was never performed and the wire has no field to say so, so it is left out of
  `entries` — never sent as a zero — while every other set of its slot still
  rides (`test/watch_session_projection_test.dart`,
  `S-59 a snapshot carries the assist, and omits only the row without reps`).
- **An entry is asserted once, not re-asserted.** The answer's `entries` are
  byte-identical between two Syncs of an unchanged ladder, and the wrist's echo
  of that answer is not answered again — an entry-only difference is no
  difference (`test/watch_session_projection_test.dart`,
  `S-39 the projection is deterministic, and an echo is not sent`;
  `test/live_mirroring_test.dart`,
  `S-32/S-39 an entry-only difference is not re-asserted`).
- **A delete reaches the wrist, and the wrist hides the entry rather than
  dropping it.** The phone announces the deletion as a `structure_change` naming
  the entry's own id, so a set removed on the phone leaves the session the wrist
  is showing — and so does a `timed`, `hold` or `round` entry, the wrist's own
  among them (`test/watch_session_auto_push_test.dart`,
  `S-120 the push names the set the phone dropped, in a frame the wrist applies, before the snapshot that no longer carries it`;
  `S-144 a non-set entry the wrist logged leaves under the wrist's own id, and
  one the phone logged under the id the phone minted`;
  `S-144 a phone-logged record before the wrist's own does not hide the deletion
  of the wrist's row`;
  `test/watch_session_projection_test.dart`,
  `S-35 an edit reaches the wrist and a delete is announced`). The deletion is a
  **lens over the projection**: the observation row stays — the store is
  append-only — and the lens is durable, so a wrist restart does not bring the
  set back (`test/watch_session_engine_test.dart`,
  `S-124 the deleted set stays hidden across a restart`;
  `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`,
  `testS124ADeletionSurvivesAWristRelaunch`). Each deletion is announced under an
  id of its own, so a second deletion of a number the phone re-used is a new
  change rather than a repeat the wrist drops (`test/watch_session_auto_push_test.dart`,
  `F2 a number the phone re-used and dropped again is announced again, under a
  change id the wrist has not applied`), and a deletion the push could not send
  is announced by the next push under the id it was minted with rather than being
  lost — the same case whether the radio refused the frame or reported it
  `undelivered` (`test/watch_session_auto_push_test.dart`,
  `F7 the next pass announces the deletion the failed one could not, under the
  change id it was minted with`,
  S-203 a deletion frame the radio reports `undelivered` stays owed under the
  change id it was minted with`). A snapshot that carries the id
  clears its deletion, so a slot whose set was deleted and re-created under the
  reused number converges (`test/watch_session_engine_test.dart`,
  `S-125 the wrist shows the new set's own fields`, `S-125 an id the wrist never held is shown when a snapshot carries it`;
  Swift twin, `testS125AReUsedNumberShowsTheNewEntrysOwnFields`), while a
  snapshot that only repeats the row the wrist already holds leaves the deletion
  standing (`test/watch_session_projection_test.dart`,
  `S-35 a re-statement of a deleted id stays deleted`).
- **The wrist's own start is not carried, and its place and timers are its own.**
  The phone adopts a wrist session from a snapshot, never from the wrist's start
  lifecycle (`test/watch_session_adoption_bridge_test.dart`,
  `S-1 a wrist snapshot becomes the phone's in-progress session`); the answer the
  phone composes carries the place the wrist reported rather than the phone's own
  (`test/watch_session_projection_test.dart`,
  `S-76 the answer carries the position the wrist is on`) and asserts no timers,
  so the timer the wrist started is the one that stands
  (`test/watch_logging_timers_test.dart`,
  `S-79 a snapshot leaves the wrist's countdown running and stops the phone's
  own`).
- **The wrist's own start and its own adds are announced (D-90, D-91).** A
  session started on the wrist, and an exercise the wrist adds to its ladder,
  reach the phone without being asked: the start emits its lifecycle frame and
  then the session's own `session_snapshot`, and an add emits a second snapshot
  whose revision has moved, because the shape is the wrist's own (D-101). A
  change that arrived from the phone — a push, a structure change, a snapshot —
  is applied silently and never announced back. The phone still adopts a wrist
  session from a `session_snapshot`, never from the start lifecycle
  (`test/watch_session_adoption_bridge_test.dart`,
  `S-1 a wrist snapshot becomes the phone's in-progress session`). Verified by
  `test/watch_session_engine_test.dart`
  (`S-100 a wrist start sends its lifecycle, then its own snapshot`,
  `S-101 a wrist-added exercise arrives as a second snapshot with a moved
  revision` and `S-104 nothing from the phone is announced back`) and, on the
  watch target, by `WatchSessionEngineTests.testS100AWristStartSendsItsLifecycleThenItsOwnSnapshot`,
  `…testS101AWristAddedExerciseArrivesAsASecondSnapshotWithAMovedRevision`, and — for
  the three frames a change from the phone can arrive as —
  `…testS104AnExercisePushFromThePhoneIsNeverAnnouncedBack`,
  `…testS104AStructureChangeFromThePhoneIsNeverAnnouncedBack` and
  `…testS104ASnapshotFromThePhoneIsNeverAnsweredWithTheWristsOwn`. Routines,
  preferences and the food catalog still travel by their own paths. When both
  devices hold their own session, the phone's own state is preceded by the
  reset — an `abandoned` lifecycle naming the wrist's session, then the phone's
  snapshot, then one snapshot request — so the wrist ends W and holds P, and the
  wrist's answer is what moves the phone's mirror off W
  (`test/watch_session_auto_push_test.dart`,
  `S-172 the pass sends abandoned(W) then P's own state, and the wrist's answer
  is what converges the pair`, and the resume
  `S-182 the resume sends the reset before its own state, and the answer clears
  the debt`). A reset the transport cannot carry leaves the wrist on W until the
  next pass, the next reconnect's resume, or either device's next unlock or app
  focus sends it (`S-186 a session-less wrist asks, and installs the phone's
  session` is the wrist-side half of that: the wrist's own activation reaches the
  phone), and is owed by nobody once the pair agrees
  (`S-180 a reset the radio cannot carry is dropped, re-sent by the next pass, and
  owed by nobody once the pair agrees`). The wrist's own place
  is the wrist's to report and the phone follows it, so the phone's own move of
  its current exercise does not move the watch
  (`test/watch_session_projection_test.dart`,
  `S-76 the answer carries the position the wrist is on`).
- **Per-effort heart-rate summaries are attached only where the import places
  an effort** (`WatchSessionImporter._attachSetBlockSummary`, reached from
  `WatchSessionImporter._placeEffort`). A merge into a session the phone owns
  creates no effort (D-14), so it places none
  (`test/watch_session_merge_test.dart`, `S-12 a slot the session does not
  have`).
- **An end that arrives only as observations is not an end.** The finish comes
  from a `session_lifecycle` naming the held session
  (`test/watch_session_finish_test.dart`,
  `a lifecycle naming another session changes nothing`).
- **A relaunch keeps what the wrist logged, with two gaps.** The shell's store
  is an append-only file, so the session with its place in the ladder, every set
  logged, a running rest and an owed rating question come back after the app is
  closed, force-quit or the watch restarts, with no Sync in between —
  `WatchFileStoreTests.testS44ALoggedSetSurvivesTheProcess` and
  `…testS47TheOwedRatingQuestionSurvivesTheKill` in
  `watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`, and
  the rest screen counts from the restored start rather than from zero
  (`WatchRestSurfaceTests.testS161TheRestElapsedCountsUpAndSurvivesARelaunch`). A
  session still running when the app died is still running after the relaunch
  until it is ended on the wrist or the phone's Sync ends it
  (`…testS44ALoggedSetSurvivesTheProcess`, whose restored session reads active),
  and what the wrist still owes the phone is sent exactly once at the next Sync
  (`…testS45ExactlyOneDeliveryAfterARelaunch`). A kill mid-write loses only the
  row being written, never the rows already on disk
  (`…testS49ATornLastRecordCostsThatRecordOnly`), and a file written by a newer
  app is left alone rather than overwritten
  (`…testS53AVersionThisBinaryDoesNotKnowIsNeverDamaged`). A wrist that cannot
  write to its storage keeps working in memory and every row already on disk
  still reads, but the row whose write failed is not treated as stored, so what
  was logged since the writes began failing is lost if the app is killed before
  the next Sync
  (`…testF1AnAppendThatCannotBeWrittenIsNotStoredAndKeepsItsSequence`). What does
  not come back: a set the phone edited after it reached the wrist shows the
  phone's first
  value until the next Sync, because the correction lives only in memory
  (`…testD50ARestatedSetShowsItsFirstValueAfterARelaunchUntilTheNextSync`). What
  does come back is the **deletion lens** — the ids the phone has deleted ride on
  the session row itself, so a relaunch reads them back and the same sets stay
  hidden, while the watch's own corrections stay memory-only
  (`WatchSessionEngineTests.testS124ADeletionSurvivesAWristRelaunch`,
  `…testS124TheLensRidesOnTheRowsWrittenAfterIt`, and
  `WatchFileStoreTests.testS124TheLensSurvivesAStoreReopen` in
  `watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`). By
  design the wrist's record file is never trimmed — the lens is the only thing a
  deletion changes.
- **No sensor samples are collected.** The watch app wires no sensor source, so
  a session it logs carries no heart-rate or step values of its own; the
  recording layer exists and is exercised only by its own suites
  (`WatchSensorRecordingTests`, `test/watch_sensor_recording_test.dart`).
- **A rest's timer is device-local and a rest has no length; the rest itself travels (D-26, D-80's
  device-local rule, D-160, D-219/D-220).** The
  answer projects no timers, and a snapshot stops only the timer the phone
  itself wrote there: the rest the wrist started is the wrist's through a
  snapshot, while a phone-written timer loses its milestone haptic. A rest
  record carries no `plannedDurationMs`, and the wire refuses one outright
  (`test/sync_protocol_fixtures_test.dart`,
  `S-165 the wire refuses a rest length` —
  `a rest carries no planned length, a round keeps one, and a rest with one is
  refused`; Swift twin,
  `SyncProtocolValidatorTests.testS165ARestCarriesNoPlannedLengthAndStillConforms`
  and `…testS165ARestWithAPlannedLengthIsRefused`). When it ends — **Next**, or
  the next logged set — the wrist emits it as a `rest` observation, and the
  phone's importer writes it as an `EntryRest` row, so the session's totals count
  it like the phone's own rest
  (`test/watch_session_engine_test.dart`,
  `S-320 Next ends the rest and the window travels, once`; Swift twin,
  `WatchSessionEngineTests.testS320TheRestTheWristEndsTravelsAsARestEvent`;
  `test/watch_session_summary_integration_test.dart`, `S-329 the totals`).
  Verified by
  `test/watch_logging_timers_test.dart`
  (`S-79 a snapshot leaves the wrist's countdown running and stops the phone's
  own`); the phone-written case is held by the reconciliation fixture
  `timer_cleared.json`, replayed by
  `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`.
  The wrist taps at each multiple of the interval the phone sent in
  `preferences_down` (`restPingSeconds`), with no sound — a haptic tap only
  (`WatchRestPingTests.testS241AnIntervalTapsAtItsMultiplesAndNowhereElse`;
  `test/watch_rest_ping_test.dart`).
- **The wrist labels load in kilograms.** The shell hands the surfaces no unit
  preferences, so the rows read kg whatever the phone's saved unit is, while the
  payload is always kilograms on the wire, which keeps the phone's history and
  its conversions correct
  (`WatchLoggingTimersTests.testS007APoundPreferenceStepsInPoundsStoredInKilograms`).
- **A session discarded on the phone can come back from the wrist.** A discard
  deletes the row, so the phone has nothing left to recognise; a wrist that still
  holds that session — one the discard never reached — offers it again at its next
  sync and the phone adopts it as a new in-progress session. It resolves itself at
  the wrist's next unlock or app focus when the phone has a session of its own: the
  wrist's announcement is answered with the reset, so the wrist's old session is
  discarded and the phone's is shown
  (`test/watch_session_finish_test.dart`,
  `S-189 the wrist's own announcement is answered with the reset`). A wrist the
  discard did reach is told to abandon its copy instead
  (`test/watch_session_auto_push_test.dart`,
  `S-73 discarding on the phone abandons the wrist's copy, once`). Only a session
  that ended and kept a row is protected. Not handled.
- **A set the phone drops leaves the rest its fill opened.** Dropping a set
  deletes only that set's observation rows; the rest the wrist's set opened at
  its spot + 1 stays, open, until something else closes it
  (`test/watch_session_merge_test.dart`, `S-337 a rest whose after-entry is
  gone is dropped and consumed` asserts today's behaviour; a mirror delete of
  a watch-logged set instead re-keys the rests — group
  `S-4501..S-4507 a rest is keyed on the POSITION`).
- **The routine's plan travels for `set` efforts; the other kinds carry no
  planned rows.** A `set` slot's planned rows ride the slot as `plannedSets`
  and the wrist dials each set from them (above). A timed or hold slot carries
  no planned value at all, and a round slot's only one is the round length
  `roundDurationSecs`. A routine started on the wrist opens on the phone as
  that routine: the wrist's slot ids are the phone's own template effort ids
  (`sx-<effortId>`), so a ladder whose every slot names an effort of one
  template the phone holds adopts with the template's name, `intent =
  'routine'` and `routineTemplateId`, and each of its `set` efforts starts
  with the template's planned rows read from the phone's current template —
  while a ladder no template covers adopts as a free session exactly as
  before (`test/watch_routine_adoption_test.dart`,
  `S-3640 the snapshot adopts as the routine the wrist started`,
  `S-3641 the adopted effort holds the template's planned sets`,
  `S-3644a no template covers the ladder: a free session as today`,
  `S-3644c a mixed ladder: a free session as today`,
  `S-3648 a routine deleted before the snapshot: a free session`).
- **A wrist-started routine's timed, hold and round efforts get no planned
  rows, and a routine added to an already-open empty wrist session is not
  planned.** The efforts are linked to the routine but start empty, as a wrist
  free session's always have (`test/watch_routine_adoption_test.dart`,
  `S-3641 the adopted effort holds the template's planned sets` asserts the
  timed effort holds no set rows); a routine picked on the wrist while an empty
  session is already running fills that session through the wrist's absorb
  branch, which the phone sees as appended slots, not as an adoption, so those
  slots carry no planned rows. No test pins the second case.
