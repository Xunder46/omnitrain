# Watch Session Sync — one session on two devices

**Scope.** One session at a time, shared between the phone and the wrist: which
device's session becomes the phone's own, what each direction of *ending* does,
what a conflict resolves to, and what does not sync. The phone half lives in
`lib/state/watch/` (`watch_session_adoption_bridge.dart`,
`watch_incoming_router.dart`, `watch_sync_wiring.dart`,
`watch_session_inbox.dart`) with the answer a wrist snapshot gets from
`lib/state/watch/live_session_mirror_state.dart`; the wire contract is
`watch/sync_protocol/PROTOCOL.md`. Turning a finished wrist session into history
is [Watch Session Capture](watch_session_capture.md)'s; the mirror, the
transport and the sensors are in
[The Watch Surface](state_management/watch_surface.md).

---

## Structure

| Concern | Owner |
|---|---|
| The session the wrist is running becoming the phone's own in-progress session | `WatchSessionAdoptionBridge.consider`, called by `WatchIncomingRouter` after the mirror has applied a snapshot |
| Telling the wrist when its session is already history | `WatchIncomingRouter`'s answer to that snapshot: the mirror's `reportLifecycle` |
| Ending the phone's copy when the wrist ends its own | `WatchSessionAdoptionBridge.onLifecycle` → the ordinary finish or the ordinary discard |
| The ladder the phone asserts, and the sets it logged | `WatchSessionAdoptionBridge.projectSession`, composed on demand from the bound session — the ladder, plus the phone's own logged sets in the answer's `entries` (D-31, D-33) |
| Turning the phone's logged rows into wire entries | `PhoneEntries.project` / `PhoneEntries.ordered` in `lib/core/sync_protocol/phone_entries.dart` — pure, no repository and no clock |
| Which ladder group a wrist row already claimed | `WatchSessionAdoptionBridge._wristRowStamps`, read from the session's live inbox rows (D-34) |
| Handing the rating the wrist recorded to the finish that writes the row | `WatchSessionAdoptionBridge.onLifecycle`'s read of the session row before it ends the session |
| Merging a wrist's set into the session the phone holds | `WatchSessionImporter.apply`'s `phoneOwnsSession` branch — the held merge — told by `WatchSessionInbox` |
| Which session the phone holds | `WatchSessionAdoptionBridge.holdsSession`, read by the inbox |

## Decisions this model rests on

**D-2 — the wrist's session is where a wrist session belongs.** A snapshot the
mirror applied is projected into `WorkoutState`, so a session started on the
wrist is the session the phone logs into: one ladder, one set of efforts, and
the ordinary session screen. Protocol ids are reused as row ids (D-3), so a slot
id *is* its effort's row id and a restart resolves the same ids. Verified by
`test/watch_session_adoption_bridge_test.dart`
(`S-1 a wrist snapshot becomes the phone's in-progress session`,
`S-1 a restart resolves the same session and slot ids`, and `S-1 Mock and Hive
adopt the same rows`). An empty wrist session is adopted but reads as not yet
active (D-6), verified by that file's
`S-3 an empty wrist session is adopted but reads "not yet active"`.

**D-11 — the answer is composed on demand, and a change to the phone's own
session is pushed (D-75).** The phone asserts its ladder inside the answer to a
snapshot request, built at that moment from the session it holds, and a change to
that session is also sent unasked: `WatchSessionAutoPush` binds the same
`WorkoutState`, coalesces a burst of notifications into one frame, and sends a
frame only when its composed payload differs from the last one it sent. A phone
with no session of its own has nothing to assert and sends nothing. The revision
in the answer rises with the ladder and with nothing else, which is what lets the
wrist's replace-structure rule accept a real edit and stay silent on a replay.
Verified by `test/watch_session_projection_test.dart`
(`D-11 the revision rises with the ladder, and only with it`,
`S-2 a running phone session is answered with its own ladder`, and — an idle
phone sends nothing at all — `S-2 an idle phone still answers with silence`) and
by `test/watch_session_auto_push_test.dart`
(`S-70 the phone's own set is pushed as one snapshot, and the wrist's own set is
not sent back`, `S-74 five notifications without a change push nothing`,
`S-75 three changes inside the window are one frame`).

**D-31/D-33/D-34 — the answer carries the sets the phone logged, as its own.**
`projectSession` reads each `set` slot's row groups through the repository and
emits one `set` entry per row: id `entry-<slotId>-<n>` with `eventId` equal to
`entryId` (D-33), `loggedAt` the row's own instant, and the ladder's
`sessionExerciseId`/`exerciseId` beside the row's reps and load. A group a live
wrist row already produced is *claimed* by that row and not sent back (D-34), so
the wrist never re-receives its own set. Nothing is written while composing, and
no value comes from a clock or a counter. Verified by
`test/watch_session_projection_test.dart`
(`S-31 the phone's own sets arrive as entries`,
`S-33 the wrist's own set is not sent back to it`,
`S-34 one live row claims one ladder group`,
`S-39 the projection is deterministic, and an echo is not sent`,
`S-40 two sessions do not share entries`) and, at the mirror level,
`test/live_mirroring_test.dart`
(`S-31 a ladder the phone disagrees with is answered with its sets`).

**D-35 — a set edited on the phone is re-stated on the wrist at the next push or
Sync.** A set edited on the phone shows its new value on the watch at the next
push or Sync, still
as one set: an `entryId` the wrist already holds is *re-stated* from the answer —
the wrist shows the phone's corrected values, stores no second row, and leaves the
row it already holds unrewritten. Only the watch re-states: for an id it already
holds it takes the values the answer carries. A phone that receives a watch
snapshot keeps the values it already holds for an id — the watch does not edit
existing records (authority rule 1), so the phone's model does not re-state — and
the answer carries the watch's own values for the watch's own entries, so a
re-statement of one is a no-op. Verified by `test/watch_session_projection_test.dart`
(`S-35 an edit reaches the wrist and a delete is not sent`,
`S-35 a re-statement is append-only and doubles nothing`,
`S-35 a second edit wins over the first`), by the two stacks' agreement in
`test/watch_reconciliation_cross_stack_test.dart`
(`S-35 a held id the phone edited is re-stated on the wrist, not resaved`), and on
the native watchOS client by `WatchPhoneEntriesTests`
(`testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow`,
`testASecondEditWinsOverTheFirst`) in
`watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`.

**D-10 — a conflict resolves to "each keeps its own".** A phone already running a
session refuses to adopt another, and a wrist session the phone is not in is left
alone. A refusal is the rule working, not an error: it is reported once per
(held, offered) pair through the bridge's own `onSkipped` callback — one plain
`debugPrint` line by default, carrying no stack — and never through the failure
hook, which stays for a snapshot that cannot be written at all. Verified by
`test/watch_session_adoption_bridge_test.dart`
(`S-6 the phone keeps the session it is already running`, which asserts the skip
arrives once and the failure list stays empty, `S-6 counter-case an empty phone
session does not block adoption`, and `an adoption that cannot be written is
reported as a failure` for the hook itself), by `test/watch_session_finish_test.dart`
(`G1 counter-case a running session is not answered with an end`) and by
`test/watch_session_projection_test.dart`
(`S-6 a wrist session this phone is not in is left alone`).

## The two directions of ending

**The wrist ends the session: the phone's copy ends too (D-5).** A wrist
`session_lifecycle` says `completed` or `abandoned` about the session it names.
When it names the session the phone holds, `completed` runs the ordinary finish —
one history entry, and the rating the wrist recorded is read from the session row
first so the finish cannot write a stale copy over it (D-8); `abandoned` runs the
ordinary discard, which clears the phone's copy and deletes the row. A lifecycle
naming any other session changes nothing. Verified by
`test/watch_session_finish_test.dart` (`S-4 the wrist ends its session, roster of
logged sets first`, the same scenario with `S-4 the wrist ends its session, end
before the logged sets`, `a wrist abandoned lifecycle discards the phone's copy`,
and `a lifecycle naming another session changes nothing`).

**The phone ends the session: the wrist is told (D-81).** The regular finish on
the phone is `WorkoutState.endSession`; it writes history, and the push that
follows reports the session's own `completed` lifecycle, read from the session's
stored row, so the wrist ends its copy rather than holding a session the phone has
closed — and a session whose row already has an end is never adopted back. What
is announced is the session the phone itself composed, never
whichever session the mirror happens to be showing: a second session ended in the
same run is announced for itself, a session the phone never held is not
announced at all (S-85, S-86), and an end still pending when a frame from the
wrist re-baselines the push onto a newer session is not lost to that frame
(S-87), nor is a pending end lost when the user browses a past session and
finishes the live one afterwards (S-88). Verified by `test/watch_session_auto_push_test.dart`
(`S-72 finishing on the phone ends the wrist's copy, once`,
`S-85 two finishes and a discard are announced once each, under each session's
own id`, `S-85 the end the wrist itself caused is not announced back at it`,
`S-86 the phone's own push does not end the wrist's live session`,
`S-87 a frame the wrist sends inside the window does not lose the finish it
landed in`, `S-87 a frame the wrist sends inside the window does not lose the
discard it landed in`,
`S-88 browsing a past session and then finishing the live one inside one window
still announces the finish`) and
`test/watch_session_finish_test.dart`
(`S-5 the phone's own finish is reported, and the wrist is answered at its next
sync`, `G1 a finished session is not adopted back after a restart`,
`G1 counter-case a running session is not answered with an end`). The wrist's own
half — it ends its session on receiving that lifecycle — is
`WatchSessionEngineTests.testThePhonesLifecycleEndsAWristSessionAtTheMomentItNames`
in `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`.

## Invariants

- **One session id, one row.** A wrist pass over a session the phone owns writes
  no second `TrainingSession` for that id and does not materialise the wrist's
  entries under derived ids: each staged wrist effort row becomes a row of the
  effort the session already has, under the row id the phone gave that slot
  (D-14), and is receipted. Verified by `test/watch_session_finish_test.dart`
  (`a set logged on the watch lands in the session the phone holds`) and
  `test/watch_session_merge_test.dart` (`S-9 a wrist set reaches the live phone
  session`, `S-12 a slot the session does not have`).
- **The phone's finish and discard are announced (D-81).** The session announced
  is one the phone itself composed; that session's own stored row decides: an
  ended row reports its `completed` lifecycle and a row that is gone reports
  `abandoned` — never the phone's current-session pointer, which browsing a past
  session repoints, and never a session the mirror shows but the phone refused.
  The id is forgotten once announced, so a second session ended in the same run is
  announced for itself, and a session whose end is still pending when a frame from
  the wrist re-baselines the push is announced for itself too (S-87), and one that
  is still running when the user browses a past session keeps its pending end until
  it is finished (S-88). Verified by
  `test/watch_session_auto_push_test.dart`
  (`S-72 finishing on the phone ends the wrist's copy, once`,
  `S-73 discarding on the phone abandons the wrist's copy, once`,
  `S-84 opening a past session pushes nothing for the live one`,
  `S-85 two finishes and a discard are announced once each, under each session's
  own id`, `S-85 the end the wrist itself caused is not announced back at it`,
  `S-86 the phone's own push does not end the wrist's live session`,
  `S-87 a frame the wrist sends inside the window does not lose the finish it
  landed in`, `S-87 a frame the wrist sends inside the window does not lose the
  discard it landed in`,
  `S-88 browsing a past session and then finishing the live one inside one window
  still announces the finish`) and by
  `test/watch_session_finish_test.dart`
  (`S-5 the phone's own finish is reported, and the wrist is answered at its next
  sync`).
- **A flush that cannot read the session leaves nothing behind.** A `getSession`
  that throws an `Exception` is swallowed: no frame is sent, no async error
  escapes, and the session's end is announced by the next flush. Two flushes that
  overlap run one after the other, so the end is announced once. An `Error` is not
  swallowed — it is a programming fault, and it reaches the caller. Verified by
  `test/watch_session_auto_push_test.dart`
  (`F4 a throwing getSession leaks no async error and the next flush announces the
  end`, `F4 two overlapping flushes announce the end once`,
  `G2 an Error from the session read is not swallowed`).
- **A finished session is never resurrected.** Verified by
  `test/watch_session_finish_test.dart`
  (`G1 a finished session is not adopted back after a restart`: the next sync
  leaves one history entry and sends exactly one lifecycle).
- **No state reader knows the storage engine.** Everything here talks to
  `WorkoutRepository` through `WorkoutState`; nothing under `lib/state`,
  `lib/features`, `lib/widgets` or `lib/core` imports a concrete repository.

## What does not sync

Wrist logging is not on this list any more: a set logged on the wrist reaches
the phone's live session as a row of the effort the phone's slot already has
(`test/watch_session_merge_test.dart`, `S-9 a wrist set reaches the live phone
session`), a wrist end closes the phone's copy
(`test/watch_session_finish_test.dart`,
`S-4 the wrist ends its session, roster of logged sets first`), and a set logged
while the phone was out of reach arrives at the wrist's next sync
(`test/watch_session_merge_test.dart`, `S-19 a set logged while the phone was out
of reach`). Neither is phone→wrist any more: the sets the phone logs itself ride
the frame the phone sends — its answer to a Sync, or the push a change triggers —
as `entries`, which the wrist's existing snapshot merge stores
(`test/watch_session_projection_test.dart`,
`S-31 the phone's own sets arrive as entries`, and the wrist adopting a session
it does not hold — `S-38 the wrist adopts a session it does not hold`). What
remains out is listed below.

- **A set the wire cannot carry is omitted.** A skipped set, or one whose stored
  reps are below 1, has no place in the protocol's `set` shape
  (`additionalProperties: false`, `reps` ≥ 1), so it is left out of the answer
  and stays on the phone — and a set's added weight goes with it, `extraLoadKg`
  being a hold's load. A set the wire *can* carry is carried with its sign: a
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
- **Only sets are carried.** D-39 projects `set` entries only: a `timed`, `hold`
  or `round` effort contributes nothing to `entries`, while the ladder still
  carries its slot (`test/watch_session_projection_test.dart`,
  `S-2 a running phone session is answered with its own ladder`).
- **An entry is asserted once, not re-asserted.** The answer's `entries` are
  byte-identical between two Syncs of an unchanged ladder, and the wrist's echo
  of that answer is not answered again — an entry-only difference is no
  difference (`test/watch_session_projection_test.dart`,
  `S-39 the projection is deterministic, and an echo is not sent`;
  `test/live_mirroring_test.dart`,
  `S-32/S-39 an entry-only difference is not re-asserted`).
- **A delete does not reach the wrist.** A set deleted on the phone stays on the
  wrist until the wrist's own session is replaced
  (`test/watch_session_projection_test.dart`,
  `S-35 an edit reaches the wrist and a delete is not sent`).
- **The wrist's own start is not carried, and its place and timers are its own.**
  The phone adopts a wrist session from a snapshot, never from the wrist's start
  lifecycle (`test/watch_session_adoption_bridge_test.dart`,
  `S-1 a wrist snapshot becomes the phone's in-progress session`); the answer the
  phone composes carries the place the wrist reported rather than the phone's own
  (`test/watch_session_projection_test.dart`,
  `S-76 the answer carries the position the wrist is on`) and asserts no timers,
  so a countdown the wrist started is the one that stands
  (`test/watch_logging_timers_test.dart`,
  `S-79 a snapshot leaves the wrist's countdown running and stops the phone's
  own`).
- **A few things still need the Sync button.** A session started on the wrist,
  and an exercise added on the wrist, reach the phone only at the wrist's own
  Sync: the phone adopts a wrist session from a `session_snapshot`
  (`test/watch_session_adoption_bridge_test.dart`,
  `S-1 a wrist snapshot becomes the phone's in-progress session`), and the wrist
  sends its snapshot only inside `WatchSyncOrchestrator`, the Sync action — its
  start emits only a lifecycle frame. A device that was out of reach catches up
  the same way, and routines, preferences and the food catalog always do. When
  both devices hold their own session, each keeps its own and is told nothing
  (`test/watch_session_engine_test.dart`,
  `S-77 the wrist refuses a foreign snapshot, silently`). The wrist's own place
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
  logged, a running rest countdown and an owed rating question come back after
  the app is closed, force-quit or the watch restarts, with no Sync in between —
  `WatchFileStoreTests.testS44ALoggedSetSurvivesTheProcess`,
  `…testS46ACountdownThatWasRunningIsStillRight` and
  `…testS47TheOwedRatingQuestionSurvivesTheKill` in
  `watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`. A
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
  (`…testD50ARestatedSetShowsItsFirstValueAfterARelaunchUntilTheNextSync`); and,
  by design, the wrist's record file is never trimmed — nothing is ever deleted
  from it.
- **No sensor samples are collected.** The watch app wires no sensor source, so
  a session it logs carries no heart-rate or step values of its own; the
  recording layer exists and is exercised only by its own suites
  (`WatchSensorRecordingTests`, `test/watch_sensor_recording_test.dart`).
- **The phone's rest timer is not carried; each device keeps its own
  countdown (D-26, D-80).** The answer projects no timers, and a snapshot stops
  only the countdown the phone itself wrote there: a countdown the wrist started
  keeps its remaining-time line through a snapshot, while a phone-written one
  loses it and its milestone haptic. Verified by
  `test/watch_logging_timers_test.dart`
  (`S-79 a snapshot leaves the wrist's countdown running and stops the phone's
  own`); the phone-written case is held by the reconciliation fixture
  `timer_cleared.json`, replayed by
  `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`.
- **The wrist labels load in kilograms.** The shell hands the surfaces no unit
  preferences, so the rows read kg whatever the phone's saved unit is, while the
  payload is always kilograms on the wire, which keeps the phone's history and
  its conversions correct
  (`WatchLoggingTimersTests.testS007APoundPreferenceStepsInPoundsStoredInKilograms`).
- **A session discarded on the phone can come back from the wrist.** A discard
  deletes the row, so the phone has nothing left to recognise; a wrist that still
  holds that session — one the discard never reached — offers it again at its next
  sync and the phone adopts it as a new in-progress session. A wrist the discard
  did reach is told to abandon its copy instead
  (`test/watch_session_auto_push_test.dart`,
  `S-73 discarding on the phone abandons the wrist's copy, once`). Only a session
  that ended and kept a row is protected. Not handled.

## Related

- [Watch Session Capture](watch_session_capture.md) — the import, receipts and
  tombstones.
- [The Watch Surface](state_management/watch_surface.md) — the mirror, the
  transport, the sensors.
- [Navigation & Screens](navigation_and_screens.md) — the session screen this
  session opens in.
