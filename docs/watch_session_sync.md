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
| The ladder the phone asserts | `WatchSessionAdoptionBridge.projectSession`, composed on demand from the bound session |
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

**D-11 — sync is manual, and the phone's answer is composed when asked.** No
part of this model sends anything on its own: the phone asserts its ladder only
inside the answer to a snapshot request, built at that moment from the session it
holds. The revision in that answer rises with the ladder and with nothing else,
which is what lets the wrist's replace-structure rule accept a real edit and stay
silent on a replay. Verified by `test/watch_session_projection_test.dart`
(`D-11 the revision rises with the ladder, and only with it`,
`S-2 a running phone session is answered with its own ladder`, and — an idle
phone sends nothing at all — `S-2 an idle phone still answers with silence`).

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

**The phone ends the session: nothing is sent, and the wrist catches up (G2,
G1).** The regular finish on the phone is `WorkoutState.endSession`; it writes
history and reports nothing to the wrist, because sync is the wrist's to start.
The wrist is still holding the session it believes is running, so its next sync
is answered with the session's own `completed` lifecycle, and that session is not
reloaded as the phone's current one — a session whose row already has an end is
never adopted back. Verified by `test/watch_session_finish_test.dart`
(`S-5 the phone's own finish is not reported, and the wrist is answered at its
next sync`, `G1 a finished session is not adopted back after a restart`,
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
- **The phone's finish is silent.** `reportLifecycle` has one production caller —
  the router's answer to a snapshot naming an ended session — and the finish path
  reaches none of it. Verified by
  `test/watch_session_finish_test.dart`
  (`S-5 the phone's own finish is not reported, and the wrist is answered at its
  next sync`), whose recorded transport stays empty through the finish.
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
of reach`). What remains out is listed below.

- **Sets logged on the phone are not carried to the wrist.** The phone answers a
  sync with its ladder and its own place, and never with an entry: the answer's
  `entries` is always empty, so a set the phone logs stays on the phone. Verified
  by `test/watch_session_projection_test.dart`
  (`S-2 a running phone session is answered with its own ladder`).
- **The wrist's own start, current exercise and timers are not carried.** The
  answer the phone composes carries its own current index and its own timers, not
  the wrist's (`test/watch_session_projection_test.dart`,
  `S-2 a running phone session is answered with its own ladder`).
- **Starting a session, changing exercises and converging two sessions still
  need a manual Sync.** The phone's ladder, its place and its timers arrive only
  in its answer to a wrist Sync (`test/watch_session_projection_test.dart`,
  `S-2 a running phone session is answered with its own ladder`), and the phone
  adopts a wrist session from the snapshot it asks for at a Sync
  (`test/watch_session_merge_test.dart`). What a settled set and the wrist's End
  do without one is listed above
  (`WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder`).
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
- **Nothing logged on the wrist survives a relaunch.** The shell's store is in
  memory, so quitting or force-quitting the watch app loses the session, its
  logged rows and any owed rating question before a sync can carry them.
- **No sensor samples are collected.** The watch app wires no sensor source, so
  a session it logs carries no heart-rate or step values of its own; the
  recording layer exists and is exercised only by its own suites
  (`WatchSensorRecordingTests`, `test/watch_sensor_recording_test.dart`).
- **A Sync stops a rest countdown running on the wrist.** The phone's answer
  projects no timers and the wrist adopts that as authoritative, so a countdown
  under a Sync loses its remaining-time line and its milestone haptic (D-26).
  Held by the reconciliation fixture `timer_cleared.json`, replayed by
  `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`.
- **The wrist labels load in kilograms.** The shell hands the surfaces no unit
  preferences, so the rows read kg whatever the phone's saved unit is, while the
  payload is always kilograms on the wire, which keeps the phone's history and
  its conversions correct
  (`WatchLoggingTimersTests.testS007APoundPreferenceStepsInPoundsStoredInKilograms`).
- **A session discarded on the phone can come back from the wrist.** A discard
  deletes the row, so the phone has nothing left to recognise; a wrist that still
  holds that session offers it again at its next sync and the phone adopts it as
  a new in-progress session. Only a session that ended and kept a row is
  protected. Not handled.

## Related

- [Watch Session Capture](watch_session_capture.md) — the import, receipts and
  tombstones.
- [The Watch Surface](state_management/watch_surface.md) — the mirror, the
  transport, the sensors.
- [Navigation & Screens](navigation_and_screens.md) — the session screen this
  session opens in.
