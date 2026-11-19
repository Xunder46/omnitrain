# Evidence — 43b2, a timer started on the watch runs on the phone (2026-10-20)

Record of the build and proof of this plan. Every test name below was read
from its file this run. The docs this plan wrote:
`docs/state_management/workout_state.md`,
`docs/watch_session_capture.md`, `docs/state_management/watch_surface.md`.

## Baselines

- `flutter analyze`: **181 issues before and 181 after** the work (the repo's
  pre-existing info notices; none new).
- The full `flutter test` suite is re-run by the lead as the round's closing
  step, after these docs; the docs pass itself ran
  `flutter test test/docs_indexing_contract_test.dart` (result at the bottom).

## Test table (scenario → test → file)

`test/remote_work_timer_state_test.dart` — the state layer, D-1/D-2. One
shared `_adoptionTests` body runs twice, group `Mock` and group `Hive`
(17 tests × 2 = 34):

| Scenario | Test |
|---|---|
| S-6101 a not-started interval adopts the remote start | `S-6101 a notStarted interval adopts the remote start` |
| S-6101 the effort's open rest closes and is stored | `S-6101 adopting closes the effort's open rest and stores it closed` |
| S-6101 the same for a round | `S-6101 adopting a round closes the effort's open rest and stores it closed` |
| S-6102 an earlier remote start replaces the phone's | `S-6102a an earlier remote start replaces the phone's` |
| S-6102 a later remote start changes nothing | `S-6102b a later remote start changes nothing` |
| S-6102 an equal remote start changes nothing | `S-6102c an equal remote start changes nothing` |
| S-6102 round: an equal start changes nothing | `S-6102 round: a remote start equal to the in-progress round's start changes nothing` |
| S-6103 hold pairs with a drill | `S-6103a a drill effort adopts a hold timer` |
| S-6103 round pairs with round, plan carried | `S-6103b a round effort adopts a round timer and its plan` |
| S-6103 wrong kind ignored | `S-6103c a round timer does not pair with a timed effort` |
| S-6103 unknown effort ignored | `S-6103d an unknown effort id is ignored` |
| S-6104 a paused remote adopts as paused | `S-6104a a paused remote adopts as paused` |
| S-6104 a paused remote replaces a later-started target | `S-6104b a paused remote replaces a later-started target` |
| S-6104 round adopts paused with the pause bookkeeping | `S-6104 a round adopts paused with the remote pause bookkeeping` |
| S-6105 every interval finished: ignored | `S-6105 every interval finished: ignored` |
| S-6106 the in-progress interval is the target | `S-6106 the in-progress interval is the target` |
| the adoption survives a reload | `the adopted interval survives a reload` |

`test/watch_timer_adoption_test.dart` — the adoption, D-3, over the sync
harness with the real Dart wrist engine (13 tests):

| Scenario | Test |
|---|---|
| S-6111 the wrist's timer starts the first unfinished interval, once | group `S-6111 the wrist timer starts the first unfinished interval`: `S-6111 the wrist's elapsed timer for the slot starts interval 0 on the …`, `S-6111 a paused wrist timer is adopted paused`, `S-6111 a round frame carries its length` |
| S-6112 ignored timers | group `S-6112 ignored timers`: `S-6112a a stopped timer is not applied`, `S-6112b a timer that names no slot is not applied`, `S-6112c a mirror holding another session than the phone's is not …`, `S-6112d a timer naming a slot the phone does not hold is not …`, `S-6112 a timer naming an empty slot is ignored`, `S-6112 an ended phone session adopts nothing` |
| S-6113 a timer that arrived before the session, and a new session | group `S-6113 the timer arrives before the phone holds the session`: `S-6113 the WorkoutState listener applies the timer once the phone adopts the session`, `S-6113 the same timer for a NEW session is applied again` |
| S-6114 no echo, the phone's pause still travels | group `S-6114 no echo`: `S-6114 an adopted timer is not sent back, and the phone's pause still travels` |
| S-6115 the earlier start wins, whichever device made it | group `S-6115 the earlier start wins`: `S-6115 a wrist timer earlier than the phone's own start replaces it and is not sent back` |

(Two names above are truncated with `…` where the source wraps the string
across lines; the ids are exact, the files are the record.)

`test/watch_timer_adoption_screen_test.dart` — the open screen, D-4
(`testWidgets`, Mock, live-refresh harness):

| Scenario | Test |
|---|---|
| S-6121 the wrist's elapsed timer starts the open timed interval | `S-6121 a wrist elapsed timer starts the open timed interval` |
| S-6122 the wrist's round timer runs the open countdown | `S-6122 a wrist round timer runs the open round countdown` |
| S-6122 an adopted round takes the earlier start and its length | `S-6122 a round the phone had already started with another length takes the earlier wrist start and its length` |
| S-6123 the adopted interval holds the in-progress lock | `S-6123 the adopted interval blocks starting another one` |
| S-6124 a timer for another effort leaves the open one alone | `S-6124 a wrist timer for another effort leaves the open one alone` |
| S-6125 a timer that arrived before the mount still runs (timed) | `S-6125 a wrist elapsed timer that arrives before the mount still runs` |
| S-6125 the same for a round | `S-6125 a wrist round timer that arrives before the mount still runs` — **`skip: true`**, see the S-4408 premise below |

## Mutation proof (lead, 2026-10-20)

37 mutations applied by hand. After two tests-only gap rounds (the tests were
strengthened until they could detect the change), **all 37 made a named test
red**, and every mutation was then restored byte for byte.

Three mutations stayed unproven — each is equivalent or unobservable, not
missed by the suite. (The adoption memo, `WatchTimerAdoption._applied`, was first
filed here as equivalent; the lead's reasoning corrected that: the mirror keeps
the wrist's old timer after the phone clears it, so without the memo the stale
start would overwrite the interval the phone started next. `S-6113 a stale wrist
timer is not re-applied onto the interval the phone started next` now guards both
the skip and its recording, and both mutations are red.)

1. **The empty-slot arm** (a `sessionExerciseId` that is present but names no
   held effort): an unknown slot returns false in the state layer anyway
   (`S-6103d an unknown effort id is ignored`, `S-6112d a timer naming a slot
   the phone does not hold is not …`).
2. **The live-ticker guard in `_adoptRunningTimerState`** (skip an interval
   that already has an active ticker): unobservable without a second ticker,
   which the screen forbids by the one-timer lock.
3. **The paused branch of the screen method**: the wrist has no pause control,
   so no screen test can reach it through a wrist frame.

## Design findings

- **The P3 `no_write` stop, and the re-brief as exact code.** P3 as first
  briefed stopped with `no_write`: the brief described the screen work in
  prose and the builder could not derive a write from it. The lead re-briefed
  P3 as exact code (the `_adoptRunningTimerState` body, its call site in
  `_resyncExercisesFromState`'s `apply()`), and the phase then built.
- **The stale round target cache, found by the P3b builder and fixed.** The
  screen caches a round's target length (`_effortTargetDuration`); an adopted
  round that carries the wrist's planned length left the phone's own cached
  length standing, so the ring counted from the wrong length.
  `_adoptRunningTimerState` now refreshes the cached target for an active or
  paused instance. Covered by `S-6122 a round the phone had already started
  with another length takes the earlier wrist start and its length` (the ring
  counts from the wrist's 75 s, not the phone's cached 180 s).
- **The S-4408 premise that blocked the load-path fix.** When the session
  screen is opened after the watch started a round, the load path
  (`_restoreTimerStateFromPersisted`) restores the active round as not
  running, so the ring shows the digits but does not sweep and no expiry
  fires. Starting the round's ticker from the load path would fix that — but
  it makes `S-4408: at 390x844 with the rest strip up everything is hittable`
  (`test/round_countdown_screen_test.dart`) red: that test mounts a screen on
  a running round with its rest open and expects the rest overlay chip, which
  `_shouldShowRestOverlay` hides while any effort runs. The premise — a
  running round at mount shows the rest chip — is the existing behaviour the
  test pins, so the load-path fix was dropped and the S-6125 round variant is
  `skip: true` with that reason in the file. The lead decides which premise
  moves.

## Docs check

`flutter test test/docs_indexing_contract_test.dart`: run after the docs pass;
the real count is in the crew report
(`.work/crew/2026-10-20-43b2-phone-receives/report-docs-keeper.md`).
