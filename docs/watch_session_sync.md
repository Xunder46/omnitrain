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
| The ladder the phone asserts, and the entries it logged | `WatchSessionAdoptionBridge.projectSession`, composed on demand from the bound session — the ladder, plus the phone's own logged sets (a set is logged exactly when a rest sits at its index + 1), timed, hold and round entries in the answer's `entries` (D-31, D-33, D-130); a `set` slot's planned rows ride the slot itself as `plannedSets`, not as entries (D-2, `S-3621 a set slot carries every planned row, in set order`) |
| Turning the phone's logged rows into wire entries | `PhoneEntries.project` / `PhoneEntries.ordered` in `lib/core/sync_protocol/phone_entries.dart` — pure, no repository and no clock |
| Which phone record a wrist row already claimed | `WatchSessionAdoptionBridge`'s per-kind claim read over the session's live inbox rows (D-34) — `S-142 a wrist-logged entry of any kind is not doubled` |
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
`S-3 an empty wrist session is adopted but reads "not yet active"`. A wrist
free session stays free — no routine title, intent or link — while an adopted
ladder that is a run of one of the phone's own routines links to it and its
`set` efforts start with the routine's planned rows
(`test/watch_session_adoption_bridge_test.dart`,
`S-1 a wrist snapshot becomes the phone's in-progress session` — its slots
carry no `sx-` prefix, so it stays the free-session guard;
`test/watch_routine_adoption_test.dart`,
`S-3640 the snapshot adopts as the routine the wrist started`,
`S-3641 the adopted effort holds the template's planned sets`,
`S-3644a no template covers the ladder: a free session as today`).

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

**D-31/D-33/D-34 — the answer carries the entries the phone logged, as its
own.** `projectSession` reads each slot's own records through the repository —
a `set` slot's row groups, and a `timed`, `hold` or `round` slot's instances
(D-130) — and emits one entry per record the phone logged, named
`entry-<slotId>-<n>` with `eventId` equal to `entryId` (D-33). A `set` record
counts as logged exactly when a rest sits at its index + 1
(`EntryRows.loggedSetNumbersOf(groups, rests)`, which maps each rest's
position to the set number the wire uses — the rule the session screen reads),
so a
routine's planned rows, and the default row a new exercise gets, are planned
values and are sent as nothing in `entries` — the wrist's menu shows no
"N logged" for them (`test/watch_session_projection_test.dart`,
`S-3601 a session of planned rows sends no entry`,
`S-3602 only the set a rest follows is sent`,
`S-3603 a logged set with no reps is still no entry`). The planned rows are
not dropped with the entries: they ride the slot itself as `plannedSets`
(below). A record a live wrist
row already produced is *claimed* by that row, per kind, and not sent back
(D-34), so the wrist never re-receives its own work. Nothing is written while
composing, and no value comes from a clock or a counter. Verified by
`test/watch_session_projection_test.dart`
(`S-31 the phone's own sets arrive as entries`,
`S-33 the wrist's own set is not sent back to it`,
`S-34 one live row claims one ladder group`,
`S-39 the projection is deterministic, and an echo is not sent`,
`S-40 two sessions do not share entries`,
`S-140 a phone timed entry reaches the wrist`,
`S-141 a round and a hold carry their own fields`,
`S-142 a wrist-logged entry of any kind is not doubled`) and, at the mirror
level,
`test/live_mirroring_test.dart`
(`S-31 a ladder the phone disagrees with is answered with its sets`).

**The planned rows travel on the slot as `plannedSets`, and the wrist dials
each set from them (plan 36b, D-2).** A `set` slot of the answer carries
`plannedSets`: one item per set row the exercise holds, in set order (the row
at index k is set k+1, the numbering of `entry-<slot>-<k>`), logged rows
included, with `reps` omitted for a row with fewer than 1 rep and `loadKg`
omitted at 0 or below the wire's floor — a value the wire cannot carry is left
out, never clamped, exactly as an entry's is. A slot with no rows and a
non-`set` slot carry no key, and a change to a planned value is a changed
ladder that raises the projected revision. Verified by
`test/watch_session_projection_test.dart` (group
`S-3621 the phone sends the planned sets`:
`S-3621 a set slot carries every planned row, in set order`,
`S-3621 a logged set is a planned set too`,
`S-3621 a row with no reps carries only its load`,
`S-3621 a bodyweight row carries only its reps`,
`S-3621 a load below the wire's floor is omitted, never clamped`,
`S-3621 a timed slot carries no key, whatever rows it holds`,
`S-3621 an effort with no rows carries no key`) and by
`test/watch_session_adoption_bridge_test.dart`
(`S-3622 a planned-value edit moves the revision`). The wrist reads the key
for a `set` effort only: its next set starts from `plannedSets[setsHeld]` —
reps and load — while fewer sets are held than planned, `setsHeld` counting
the slot's `set` entries the wrist holds, its own unconfirmed ones included;
past the planned rows, or for a row that carries no `reps`, the old chain
(last logged, else the kind default) stands, while a row that carries no
`loadKg` is a planned load of 0 — never the last logged load — and the logging
header reads
"Set k of N", N the larger of the planned count and k. The planned load rides
in kilograms and is shown through the wrist's saved unit. Verified by
`watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift`
(`testS3623TheWristStartsEachSetFromItsPlannedValues`,
`testS3624APhoneLoggedSetCountsTowardsK`,
`testS3625ASlotWithNoPlannedSetsHasNoCaption`,
`testS3625ATimedSlotCarryingTheKeyIgnoresIt`,
`testS3625APlannedRowWithoutALoadShowsZero`,
`testS3625APlannedRowWithoutRepsFallsBackToTheOldChain`,
`testS3626APlannedLoadShowsThroughTheSavedUnit`,
`testS3627AFullyLoggedSlotReadsSetFourOfFour`,
`testS3628AWristLoggedSetCountsBeforeThePhoneConfirms`,
`testS3631ASlotThatDeclaresAnotherKindIgnoresTheKey`,
`testS3632AHoldSlotIgnoresTheKey`).

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
(`S-35 an edit reaches the wrist and a delete is announced`,
`S-35 a re-statement is append-only and doubles nothing`,
`S-35 a second edit wins over the first`), by the two stacks' agreement in
`test/watch_reconciliation_cross_stack_test.dart`
(`S-35 a held id the phone edited is re-stated on the wrist, not resaved`), and on
the native watchOS client by `WatchPhoneEntriesTests`
(`testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow`,
`testASecondEditWinsOverTheFirst`) in
`watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`.

**D-10 — a conflict resolves to the phone's session (D-170).** A phone already
running a session refuses to adopt another, and a wrist session the phone is not
in is left where it is — but the pair does not stay split: a phone that still
knows the wrist's session sends its own state preceded by a `session_lifecycle`
naming that session `abandoned`, so the wrist ends it and then holds the phone's.
A phone that has not sent the reset — one whose mirror holds the placeholder
rather than a session (D-173) — sends no lifecycle at all: there is nothing on
the wrist to abandon, and no frame anywhere may name the placeholder
(`test/watch_session_auto_push_test.dart`, group `S-172 the phone resets the
wrist's live session, then asserts its own`, test `S-181 case B a phone holding
its own session over a wrist that holds nothing sends no lifecycle and never
names the placeholder`). A refusal is the rule
working, not an error: it is reported once per
(held, offered) pair through the bridge's own `onSkipped` callback — one plain
`debugPrint` line by default, carrying no stack — and never through the failure
hook, which stays for a snapshot that cannot be written at all. The phone's half
of the reset is verified by `test/watch_session_auto_push_test.dart`
(`S-172 the pass sends abandoned(W) then P's own state, and the wrist's answer
is what converges the pair`, and the retry
`S-180 a reset the radio cannot carry is dropped, re-sent by the next pass, and
owed by nobody once the pair agrees`), the wrist's half by
`test/watch_session_projection_test.dart`
(`S-183 case A the abandoned frame the reset carries ends the wrist's session
and takes nothing else`), and the adoption half the reset leaves standing by
`test/watch_session_adoption_bridge_test.dart`
(`S-6 the phone keeps the session it is already running`, which asserts the skip
arrives once and the failure list stays empty, `S-6 counter-case an empty phone
session does not block adoption`, and `an adoption that cannot be written is
reported as a failure` for the hook itself), by `test/watch_session_finish_test.dart`
(`G1 counter-case a running session is not answered with an end`) and by
`test/watch_session_projection_test.dart`
(`S-6 a wrist session this phone is not in is left alone`).

**A snapshot of the session the phone holds grows that session, add-only
(D-92/D-93).** Whenever a wrist snapshot for the session the phone has already
adopted arrives, the phone appends the slots it has not already taken, in the
snapshot's order, after the slots it holds, and changes nothing else: no
deletion, no reorder, no rename, no move of the position or the status, and no
rest or timed timer cleared. The append is one notification, and a ladder that
adds nothing writes nothing and notifies nothing. (Known limit, and no test
claims it: the slot ids this rule remembers live in memory only and are forgotten
as soon as the phone holds another session, so leaving the session and coming
back — or relaunching the app — re-opens the window in which a stale wrist
snapshot can bring back a slot the phone removed.) Verified by
`test/watch_session_adoption_bridge_test.dart`
(`S-102 a slot the wrist added to the held session is appended`,
`S-104 a snapshot with no new slot changes nothing`,
`S-105 a phone-side rename is not undone by a wrist snapshot`,
`S-106 the phone's own session is not taken away`), by
`test/watch_session_adoption_build_notify_test.dart`
(`S-103 the same snapshot twice, and a stale copy after a removal` and
`S-111 an append while the phone is on another screen`) and by
`test/watch_session_rest_timer_append_test.dart`
(`S-110 a running rest survives the append`).

## The two directions of ending

**The wrist ends the session: the phone's copy ends too (D-5).** A wrist
`session_lifecycle` says `completed` or `abandoned` about the session it names.
When it names the session the phone holds, `completed` runs the ordinary finish —
one history entry, and the rating the wrist recorded is read from the session row
first so the finish cannot write a stale copy over it (D-8); `abandoned` runs the
ordinary discard, which clears the phone's copy and deletes the row. A lifecycle
naming any other session changes nothing. An end pressed while the phone is
apart is not lost: the wrist re-announces it at its next catch-up, from its own
stored end row and in the live frame's own identity, and the phone's copy ends
then, its session screen leaving for one summary carrying the wrist's rating.
While the wrist still holds a finished session, every catch-up re-announces that
end, and the phone reads the repeat as the end it already holds. Verified by
`test/watch_session_finish_test.dart` (`S-4 the wrist ends its session, roster of
logged sets first`, the same scenario with `S-4 the wrist ends its session, end
before the logged sets`, `a wrist abandoned lifecycle discards the phone's copy`,
and `a lifecycle naming another session changes nothing`), by
`test/watch_session_engine_test.dart` (group `S-212 the replay is the live end
frame, not a new event`, `S-212 the replay repeats the live frame field for
field`, `S-214 a session still running replays nothing`), by
`test/live_mirroring_test.dart` (group `S-216 the catch-up re-announces the
wrist's end behind what it owes`, `S-216 the replay is gated on reachability: an
apart sync re-announces nothing, and the later one does`,
`S-215 every catch-up repeats the same frame, and the phone stays still`) and by
`test/pr4_session_controls_test.dart` (`S-213 the end the wrist re-announces at
its next catch-up leaves the screen for one summary carrying the wrist's
rating`).

**The wrist's rating reaches the open Summary (D-1).** Written only if the
row has none (D-138), it closes the open prompt: first answer wins
(`S-4301`, `S-4303`: `test/rating_first_answer_*_test.dart`).

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
`S-86 the push ends the wrist's session as a deliberate reset and never as an
end the phone was told about`,
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

## Catching up by itself

**The wrist catches up when the phone comes back in reach and whenever its app
wakes (D-96, D-183).** A reachability edge or the wrist's own activation runs the
same catch-up the Sync button runs, once and without the user pressing anything:
the routines, the messages the wrist owes, and then the session state — a wrist
holding a session hands that session over, and a wrist holding none asks the
phone for its workout instead of doing nothing, so the session the wrist should
be in appears after its own was discarded, at the price of re-asking for the
routines on every wake. A trigger that arrives while one is already running is
dropped: never queued, never cancelling the running one. Verified by
`test/live_mirroring_test.dart` (`the wrist catches up at its next activation`:
`S-186 a session-less wrist asks, and installs the phone's session`,
`S-187 an unreachable activation is a no-op, and the reachability edge does the
work`, `S-188 an activation burst is dropped, and the later trigger runs`) and by
`WatchConnectivityBridgeTests.testS186AWristWithNoSessionAsksAtItsNextActivation`,
`testS187AnUnreachableActivationIsANoOpAndTheEdgeDoesTheWork` and
`testS188AnActivationBurstIsDroppedAndTheLaterTriggerRuns`, with
`WatchConnectivityBridgeTests.testS107TheWristCatchesUpOnAReachabilityEdgeOnce`
still covering the edge and the drop of a trigger that arrives in flight, in
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`.

**The phone catches up when the app resumes, once (D-96).** Resuming the app asks
for one sync: the phone asserts its own session and then asks the wrist for its
own, so a change the wrist made while the app was backgrounded lands without the
user pressing Sync. The trigger is the app lifecycle alone — no timer, no polling —
and a phone with no watch mounts no observer at all. Verified by
`test/watch_resume_sync_test.dart`
(`S-109 a resume asks for one sync, no other lifecycle state asks for any, and an
unmounted observer asks for none`, `S-109 every reported resume asks
for exactly one sync, and no other lifecycle state asks for any`) and by
`test/watch_session_projection_test.dart`
(`S-109 case A one resume is one catch-up: the phone's OWN session and then the
request for the wrist's, once per resume`,
`S-109 case B a phone holding no session sends no snapshot at all`,
`S-109 case C the phone asserts its own session, never the wrist's copy`).

**A wedged send cannot silence either device (D-98).** Each frame a device chains
is bounded: a send that does not complete within its bound is reported through the
device's failure hook and the chain moves on to the next frame — nothing is
retried and nothing is queued, because the row the frame came from is still owed
and the next sync re-sends it from storage. A frame the radio could not carry is
not marked sent either: the push's baseline, a pending end and an owed deletion
advance only on a delivered one, so what is owed is offered again at the next
trigger — a WorkoutState pass, a resume, a frame applied from the wrist, or the
answer to a wrist announcement. Delivery means the frame was handed to the radio
while the counterpart was reachable, never that it was applied. A wrist whose app
is not in the foreground is out of the phone's reach, so it hears from the phone
at its next wake, when it asks. Verified on the phone by
`test/watch_session_auto_push_test.dart`
(`S-112 a send that never completes is abandoned and reported, and the change made
while it hung still leaves the phone`, group `S-200 a frame the radio did not
carry stays owed`, `S-200 the baseline does not advance on an undelivered send,
so the same state is offered again when the radio comes back`, `S-200 a resume
whose own snapshot the radio refused stays owed, and the push offers it again
(D-191 site 4, D-198)`, group `S-205 a frame from the wrist re-offers what is
owed, never itself`, `S-205 (S-209) the wrist's own set arrives while a deletion
is owed: it is applied, never echoed, and the deletion leaves after it`) and on
the wrist by
`WatchEmitForwarderTests.testS112AHungSendCannotWedgeTheQueue` in
`watch/watchos/Tests/WatchSessionEngineTests/WatchEmitForwarderTests.swift`.

**What the Sync button is still for.** Sync is what is not automatic: the first
fetch on a fresh watch (routines, preferences and the food catalog) and a manual
retry. A session's own changes travel by themselves in both directions (D-90,
D-91, D-96).

**A phone session now takes over the wrist's running one (D-102, D-170).** A
snapshot the phone sends for a different session is still refused whole and
silently while the wrist holds an active session **with a non-empty ladder**, but
it no longer arrives alone: the reset in front of it is an `abandoned` lifecycle
naming that very session, so the wrist ends it and the snapshot that follows is
the phone's session taking its place. The alternative — leaving the wrist's work
standing and the two devices on two sessions — is the defect D-170 fixes.
Pinned, for the phone's half, by
`test/watch_session_auto_push_test.dart`
(`S-172 the pass sends abandoned(W) then P's own state, and the wrist's answer
is what converges the pair`) and, for the wrist's half, by
`test/watch_session_projection_test.dart`
(`S-183 case A the abandoned frame the reset carries ends the wrist's session
and takes nothing else`, `S-183 case B a lifecycle naming a session the wrist is
not holding is a no-op`); the refusal the reset works around stays pinned by
`WatchSessionEngineTests.testS77AForeignSnapshotChangesNothingAndSaysNothing`,
with the empty-ladder counter-case
`WatchSessionEngineTests.testS77AWristWithAnEmptyLadderReservesNothing`, in
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`.

**A start on the wrist never opens a second session there (D-171, D-177).** A
free start while the wrist holds a session hands that session back and emits
nothing; a routine start over a session that has exercises is refused the same
way, with the ladder untouched; a routine over an active *empty* session fills it
in place, resending the structure as a snapshot and no new started lifecycle
(`test/watch_session_start_test.dart`,
`S-177 startFreeWorkout on a live session returns it and emits nothing`,
`S-170 startFromRoutine on a session with exercises is refused too`,
`S-178 a routine fills an active empty session in place`; on the watch target by
`WatchSessionStartPathsTests.testS177StartFreeWorkoutOnALiveSessionReturnsItAndEmitsNothing`,
`…testS170StartFromRoutineOnASessionWithExercisesIsRefusedToo` and
`…testS178ARoutineFillsAnActiveEmptySessionInPlace`, in
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`).

## Invariants

- **One session id, one row.** A wrist pass over a session the phone owns writes
  no second `TrainingSession` for that id and does not materialise the wrist's
  entries under derived ids: each staged wrist effort row becomes a row of the
  effort the session already has, under the row id the phone gave that slot
  (D-14), and is receipted. Verified by `test/watch_session_finish_test.dart`
  (`a set logged on the watch lands in the session the phone holds`) and
  `test/watch_session_merge_test.dart` (`S-9 a wrist set reaches the live phone
  session`, `S-12 a slot the session does not have`).
- **A wrist set fills the phone's next unlogged planned row, in the held merge
  only.** While the phone holds the session, a wrist `set` fills the first row
  the phone reads as unlogged — no rest at its position + 1, which differs from
  the row's number once the phone has deleted a middle set — replacing that
  row's values and stamping them with the wrist's `loggedAt`, so the row count
  does not change; when every row is logged it appends after the last row, and
  a history import always appends after the last row
  (`test/watch_session_import_test.dart`,
  `A-51 a late wrist set is placed after the user’s own set`; and, for the live
  merge, `test/watch_session_merge_test.dart`,
  `S-3604 a wrist set fills the planned row and opens its rest`,
  `S-3605 a second wrist set fills the next planned row`,
  `S-3606 a fourth set appends once the planned rows are filled`,
  `S-3607 the phone's own logged set is never filled`,
  `S-3616 a skipped planned row is not logged, so the wrist fills it`,
  `S-11 the phone's own rows are the user's`). The fill opens the rest at that
  set's position + 1, run from the wrist's `loggedAt`, and ends the phone's
  older open
  rest — one rest runs at a time; the wrist's own `rest` report later closes
  that same rest in place with the wrist's window, and a rest the phone already
  finished stands
  (`S-3608 the wrist's rest closes the rest the fill opened`,
  `S-3618 the wrist's set ends the phone's older open rest`).
  Every rest the importer writes is keyed on that position + 1, and a mirror
  delete of a watch-logged set re-keys the effort's rests by the same rule
  (`EntryRows.restsAfterDelete`, shared with
  `TimerManager.rekeyEntryRestsAfterDelete`;
  `test/watch_session_merge_test.dart`, group
  `S-4501..S-4507 a rest is keyed on the POSITION`, under Mock and Hive;
  `test/entry_rows_test.dart`, group `S-4508 restsAfterDelete`).
  On the screen the
  filled row reads LOGGED at once and is offered no second log
  (`test/watch_live_refresh_screen_test.dart`,
  `S-3514 a wrist merge fills the planned row in place`,
  `S-3515 the set the wrist logged is offered no second log`,
  `S-3610 a wrist set fills the row the screen is on`), and the filled row is
  not echoed back to the wrist — its stamp claims it
  (`test/watch_routine_round_trip_test.dart`,
  `S-3609 the set the wrist logged is never echoed back to it`).
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
  `S-86 the push ends the wrist's session as a deliberate reset and never as an
  end the phone was told about`,
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

The list of what stays on one device, and why, is its own page: [What does not sync](watch_session_sync/what_does_not_sync.md).

## Related

- [Watch Session Capture](watch_session_capture.md) — the import, receipts and
  tombstones.
- [The Watch Surface](state_management/watch_surface.md) — the mirror, the
  transport, the sensors.
- [Navigation & Screens](navigation_and_screens.md) — the session screen this
  session opens in.
