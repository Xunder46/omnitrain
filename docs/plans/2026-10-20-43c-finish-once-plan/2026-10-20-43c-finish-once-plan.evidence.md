# Evidence — 43c, finishing an interval on either device logs it once (2026-10-20)

Record of the build and proof of this plan. Every test name below was read
from its file this run. The docs this plan wrote:
`docs/watch_session_capture.md` (one paragraph, "Why finishing on either logs
once", plus in-place corrections to the two timer paragraphs).

## Baselines

- Base: commit `80afbcdd` plus the uncommitted work of plans 42 and 43
  (43a, 43b1, 43b2, 43b3) on `claude_develop`.
- `flutter analyze`: **181 issues, the baseline 181** (the repo's pre-existing
  info notices; none new).
- Full `flutter test` after the fix round: `+5225 ~2: All tests passed!` (was
  +5174; +51 = 40 importer tests, 11 new push tests). The run before the fix
  round read `+5217 ~2`.
- Full `swift test` (`watch/watchos`): **633 tests, 0 failures** (was 628; +5,
  the S-6331 tests below). No Swift production change, so no `xcodebuild` of
  the watch app target.

## Test table (scenario → test → file)

`test/watch_finish_once_test.dart` — the live merge in
`lib/core/services/watch_session_importer.dart`, D-1 and D-2. One shared
`_finishOnceTests` body runs twice, group `Mock` and group `Hive`
(20 tests × 2 = 40):

| Scenario | Test |
|---|---|
| S-6301 the entry fills the interval whose start is its own | `S-6301 the entry fills the interval whose start is its own` |
| S-6302 a paused interval is as good a target | `S-6302 a paused interval is as good a target` |
| S-6302b a paused round is in progress | `S-6302b a paused round is in progress` |
| S-6303 the same for a hold (drill) and a round | `S-6303a a hold fills the drill interval with its start`, `S-6303b a round fills the round with its start` |
| S-6304 no start match: the in-progress one wins | `S-6304 without a start match the in-progress one wins` |
| S-6305 two in progress, then neither matches | `S-6305a of two in-progress intervals the shared start is filled`, `S-6305b matching neither start, the first in-progress wins` |
| S-6306 the 1000 ms tolerance | `S-6306a a start 400 ms from the phone's is the same start`, `S-6306b a start 5 s from the phone's is not the same start` |
| S-6307 nothing in progress: 43a's rule intact | `S-6307a nothing in progress: the first not-finished is filled`, `S-6307b every interval finished: the entry appends` |
| S-6311 a duplicate is ignored, redelivery included | `S-6311 a second report of an interval the phone logged is ignored` |
| S-6312 a duplicate hold and round | `S-6312a a second report of a hold is ignored`, `S-6312b a second report of a round is ignored` |
| S-6313 a start outside the tolerance is not a duplicate | `S-6313 a start outside the tolerance is not a duplicate` |
| S-6314 the tolerance on the duplicate rule | `S-6314a a phone start 400 ms away makes the entry a duplicate`, `S-6314b a phone start 5 s away is no duplicate` |
| S-6315 an entry's own half-written instance is not a duplicate of itself | `S-6315 an entry's own half-written instance is not a duplicate of itself` |
| S-6316 a rest following a duplicate lands on the phone's interval | `S-6316 a rest after a duplicate lands on the phone's interval` |

`test/watch_timer_push_test.dart` — the clear of an adopted timer in
`lib/state/watch/watch_timer_push.dart`, D-3, over the shipping graph (fake
radio, real Dart wrist engine). The file holds 25 tests: the 14 the 43b3 plan
wrote (groups `S-6211` to `S-6217`) and these 11 new ones:

| Scenario | Test |
|---|---|
| S-6321 finishing an adopted interval clears the wrist clock | `S-6321 the phone finishing the interval the wrist started sends one cleared elapsed timer, and the wrist stops counting` |
| S-6322 the wrist logged first, so nothing is cleared | `S-6322 when the wrist has already logged the interval the phone finishes, nothing is sent` |
| S-6323 the mirror holds a different start for the slot | `S-6323 when the wrist has begun the slot's next interval, the phone finishing the old one does not stop the new clock` |
| S-6324 the mirror holds the same start for another slot | `S-6324 when the mirror holds another slot at the same instant, the phone finishing its interval does not clear the wrist's clock` |
| S-6325 an undelivered clear is re-offered | `S-6325 the clear the radio could not carry is offered again at the next pass and then stops` |
| S-6326 the cleared mirror copy does not block the next interval | `S-6326 after the clear the mirror still holds the old timer, and the phone's next interval is sent and run on the wrist` |
| S-6327 the clear and the next interval in one pass | `S-6327 finishing the adopted interval and starting another before a pass sends the clear first and then the new timer` |
| S-6328 a second pass while the adopted interval still runs | `S-6328 further passes send nothing until the phone pauses the interval, and the pause travels with the wrist's own start` |
| S-6329 after a clear, the wrist's next interval still wins | `S-6329 the wrist's next start is not mistaken for the copy this push cleared, so the phone's later interval is not sent` |
| S-6330 a stopped wrist timer does not block the phone | `S-6330 the wrist stopped its own timer, so the phone's later start is sent` |
| S-6341 the wrist logs after the phone logged (end to end) | `S-6341 one interval, no duplicate: the wrist entry lands on the interval the phone already finished` |

watchOS `WatchTimedWorkTests`
(`watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift`) —
the wrist half of the clear, D-6, test only (5 new tests):

| Scenario | Test |
|---|---|
| S-6331 a phone clear of the elapsed timer makes the wrist offer Start | `testS6331APhoneClearOfTheElapsedTimerMakesTheWristOfferStart` |
| S-6331 the same clear stops a clock the wrist started itself | `testS6331BTheSameClearStopsAClockTheWristStartedItself` |
| S-6331 a clear of another kind leaves the clock running | `testS6331CAClearOfAnotherKindLeavesTheClockRunning` |
| S-6331 a hold effort offers Start after the clear | `testS6331DAHoldEffortOffersStartAfterTheClear` |
| S-6331 a round effort offers Start after the clear | `testS6331EARoundEffortOffersStartAfterTheClear` |

## Mutation proof (lead, 2026-10-20)

Importer: 15 mutations. The first pass left 4 green — the round-paused arm,
the own-instance exemption (×2), and two redundant guards. A tests-only round
added `S-6302b a paused round is in progress` and `S-6315 an entry's own
half-written instance is not a duplicate of itself` and made the first two
red. Timer push: 17 mutations. The first pass left 6 green — P2
earlier-recorded, `sameInterval` always-false, the `sameInterval` slot arm,
the stale start arm, retired-in-condition redundant, adopted drop. A round
added S-6328, S-6329, S-6330 and S-6341 and made `sameInterval`-always-false,
the stale start arm and the stopped arm red; the retired-in-condition term was
removed as redundant. The end-to-end S-6341 goes red when the duplicate rule
is switched off. Swift: removing the null branch of `adoptTimers`
(`timers.keys.contains(kind)`) makes `testS6331A`, `B` and `D` red. Every
mutation was restored byte for byte.

Equivalent-by-construction defensive guards the mutations left green —
recorded here, not in the capture doc:

- the `phoneStartMs > 0` and `startMs <= 0` guards of `_sameStart` /
  `_loggedIntervalIndex` (a zero start can never be within 1000 ms of a real
  one);
- the round branch's own-instance exemption (a round writes no rows, so
  `unfinishedPlaceOf` answers for it unless two instances share an index);
- `_adopted.remove` when the mirror no longer holds the timer (hygiene);
- the slot arm of the retire check (two slots cannot share a start instant);
- the dup check's `fillPlanned` / `unfinished == null` conditions.

## Crew runs

2 scouts, 3 build runs (parallel: importer, push, Swift), 2 fix runs
(parallel).

## Owner checks

The plan's "Owner checks" section already carried the four checks, the
aeroplane-mode edge included ("(owner, edge) Turn the watch's radio off
(aeroplane mode), log on the phone, then log on the watch, then turn it on:
the phone keeps one interval; the watch may list it twice (known limit
D-5)"); nothing to add.

## Docs check

`flutter test test/docs_indexing_contract_test.dart` (via
`.github/copilot/scripts/macos/gateway.sh test`), after the docs pass and
again after the final trim of `docs/watch_session_capture.md`:
`00:00 +13: All tests passed!` (13 tests, exit 0). Sizes after the pass:
`docs/watch_session_capture.md` 31.9 KiB (was 29.1 KiB before the pass; the
addition is ≈2.9 KB, under the 3 KB budget), evidence file ≈8.5 KB; the plan
files are far under the ceiling.
