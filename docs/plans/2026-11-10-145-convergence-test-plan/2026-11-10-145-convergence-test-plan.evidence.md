# Evidence — plan 145: a randomized convergence test for the phone and the wrist

Baselines, suite outputs and red/green tables live here; the plan keeps one line
per item.

## Baselines

| When | Command | Result |
|---|---|---|
| 2026-11-11, before any code | `gateway.sh lint` (`flutter analyze`) | **181 issues** (repo's pre-existing info notices; log `.work/gateway/lint-20261111-080510-43563.log`) |
| 2026-11-11, before any code | `gateway.sh git-status` | `M .claude/crew.md`, `?? docs/plans/2026-11-10-145-convergence-test-plan/` only — the plan 144 tree is committed (`fc93d226`) |

## Phase A, part 1 (items 1–3 and the S-14501 smoke test)

Delivered: `test/helpers/watch_pair_harness.dart` (items 1–3) and
`test/watch_convergence_harness_test.dart` (S-14501 smoke only). Test-only: no
`lib/` or `watch/` file changed.

### Run results

| When | Command | Result |
|---|---|---|
| 2026-11-11 | `gateway.sh test test/watch_convergence_harness_test.dart` (mutation applied) | **RED AT** `expect(harness.wristEngine.session?.sessionId, phoneSessionId)` — `Expected: 'session-<ms>' / Actual: <null>`, test file line 31 (`0 passed, 1 failed`) |
| 2026-11-11 | `gateway.sh test test/watch_convergence_harness_test.dart` (original restored, after `dart format`) | **+1, all tests passed** |
| 2026-11-11 | `gateway.sh lint` | **181 issues** — unchanged from baseline; no finding names either new file (log `.work/gateway/lint-20261111-080710-44438.log`) |
| 2026-11-11 | `gateway.sh format test/helpers/watch_pair_harness.dart test/watch_convergence_harness_test.dart` | `Formatted 2 files (1 changed)` |
| 2026-11-11 | `gateway.sh test` (full suite) | **7374 passed, 2 skipped, 0 failed** (`All tests passed!`, log `.work/gateway/test-20261111-080733-44888.log`) |
| 2026-11-11 | `gateway.sh test test/ui_standards_contract_test.dart` | **41 passed** (`All tests passed!`) |
| 2026-11-11 | invariant grep `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` | no matches |
| 2026-11-11 | residue sweep `grep -n _QRadio test/` | 4 hits, all in `test/watch_session_end_owed_test.dart` (plan 128's own) — the harness copies the radio instead of importing it (D-14502) |
| 2026-11-11 | `gateway.sh git-diff --stat` | `.claude/crew.md \| 2 ++` only (pre-existing before this run); the two new test files and the plan folder are untracked — no `lib/`, `watch/` or existing test file changed |

### The mutation that proves the smoke test

The scenario is new code, so the smoke test cannot be prove-red'd against
`HEAD`; it is proved by mutation instead.

- Original line (in `WatchPairHarness._receiveOnWrist`):
  `      await _orchestrator.receive(frame);`
- Mutated to: `      // mutation: the wrist ignores the phone's message.`
- Result: red at the wrist session assertion (verdicts above), i.e. the guard
  fails for exactly the reason it exists.
- Restored to the byte-identical original, re-run green before the format run.

### What the harness exposes for the next run (items 4–8)

- `WatchPairHarness.build({start, exerciseId, exerciseName, capabilities})`
  builds the phone (Mock repository, `WorkoutState`, `SettingsState`, the
  `createWatchSync` graph) and the wrist (`WatchSessionEngine`, paths,
  `WatchSyncOrchestrator`) over one `PairRadio` and one `TestClock`.
- `PairRadio`: `frames` trace, `framesOfType`/`ofType`, `phoneQueue` /
  `wristQueue`, `refuseWhen(lane, frame)`, `setReachable`, `drainQueues`,
  `linkInfo`, `heard`.
- `HarnessRunner.perform(action)` for all 15 seeded actions plus
  `phoneReassertsLive()`; factories mint serials from one counter.
- `relaunchWrist()`, `slot()`, `phoneEfforts`, `settle()`, `nextMessageId()`,
  `nextWristEntryId()`.

## Phase A, part 2 (Part 0's withdraw fix, items 4–8)

Delivered: the same two test files. Test-only: no `lib/` or `watch/` file
changed (see `git-diff --stat` below).

### Red → green, one row per guard

| Guard | Proving mutation (restored byte-identically, green afterwards) | Verdict |
|---|---|---|
| D-14512 — a live frame withdraws the queued copy it replaces | `cross()`'s `_withdrawAfterSend(lane, frame);` line removed (Part 0's whole fix) | **RED AT** `test/watch_convergence_harness_test.dart:46` — `expect(...queued older copy..., isFalse)` → `Expected: false / Actual: <true>`, `+0 -1` |
| S-14501 — the pair converges with three entries on each side | `HarnessRunner.healRoundLimit` `10` → `1` (the heal stops one round before the fixed point) | **RED AT** `:121` — `expect(heal.converged, isTrue)` → `Expected: true / Actual: <false>`, trace ends `check: DIVERGED`; `+1 -2` (D-14512 green, S-14501 and S-14505 red) |
| S-14505 — a wrist killed after the phone finished still hears the end | the same `healRoundLimit = 1` mutation (one mutation, two guards) | **RED AT** `:219` — `expect(heal.converged, isTrue)` → `Expected: true / Actual: <false>`, `check: DIVERGED` |
| S-14502 — the same actions twice give the same trace and result | `WatchPairHarness.labelFor` returns the raw `sessionId` instead of "session N" | **RED AT** `:168` — `expect(second, first, reason: 'the trace is the same twice')` differing at `session-…1010` vs `session-…1117`, `+0 -1` |
| S-14503 — a finished workout is never reopened by a queued `started` | none: the test is `skip: 'plan 146: a finished workout is final'` because the defect it measures (`_applyLifecycle` maps `started` → `active` with no held-status check, `lib/watch/session/watch_session_engine.dart:646`) is fixed only in plan 146 | **RED AT** `:194` with the skip removed — `expect(harness.wristEngine.session?.status, WatchSessionStatus.completed)` → `Expected: 'completed' / Actual: 'active'` (`Differ at offset 0`), `+0 -1`; the earlier queue assertion at `:186` passed, so the queued `started` did drain and reopen the finished session. Skip restored. |

### Finding F-1 (recorded, not fixed here)

S-14503's red run is F-1: a `started` lifecycle that arrives after the wrist
reported `completed` reopens the session (`active`), instead of changing
nothing. The trace: wrist starts → link drops → the phone re-asserts `started`
(queued) → the wrist finishes (`completed`) → link up → the queued `started`
lands → the wrist is `active` again. Fixed in plan 146 (`_applyLifecycle`), never
here: `lib/` is not this plan's to change.

Run order for each mutation: mutate → `gateway.sh test
test/watch_convergence_harness_test.dart [--plain-name <name>]` → restore →
re-run. The restore is verified by the final green run below, not by reading the
diff back.

The line numbers above are the ones flutter reported in those red runs; the final
`dart format` pass (both files, two changed) moved them — S-14501 `:121` → `:124`,
S-14505 `:219` → `:227`, S-14502 `:168` → `:173`, S-14503 `:194` → `:203`,
D-14512 `:46` → `:51`. The assertions are unchanged.

### The defects each guard would catch

- **S-14501** catches a pair that cannot finish the same workout: a session
  status that stays `active` on one side after the heal, an entry that reaches
  only one side (the union mismatch that surfaced while building it — a phone
  set the projection left out because no rest sat below it, A-145-07), a
  duplicate id within a side, or an absorbing-end violation.
- **S-14502** catches a harness whose trace or report carries anything from the
  wall clock (A-145-06), i.e. a runner that cannot be compared run-to-run — the
  precondition for every seeded run in Phase B.
- **S-14505** catches the lost-end defect: a wrist killed after the phone
  finished, relaunched from its store, must still hear the end through the heal;
  the guard fails on an extra session id, a wrist left `active`, or an entry
  the relaunch dropped.

### Run results

| When | Command | Result |
|---|---|---|
| 2026-11-11 | `gateway.sh test test/watch_convergence_harness_test.dart` | **+4 ~1, all tests passed** (D-14512, S-14501, S-14502, S-14505; S-14503 skipped) |
| 2026-11-11 | `gateway.sh format test/helpers/watch_pair_harness.dart test/watch_convergence_harness_test.dart` | `Formatted 2 files (2 changed)` |
| 2026-11-11 | `gateway.sh test test/watch_convergence_harness_test.dart` (after the format pass) | **+4 ~1, all tests passed** (D-14512, S-14501, S-14502, S-14505; S-14503 skipped) |
| 2026-11-11 | `gateway.sh lint` | **181 issues** — unchanged from baseline; no finding names either file (logs `.work/gateway/lint-20261111-082614-59508.log`, re-run after the format pass `.work/gateway/lint-20261111-083202-66109.log`, both 181) |
| 2026-11-11 | `gateway.sh test` (full suite) | **7377 passed, 3 skipped, 0 failed** (`All tests passed!`, log `.work/gateway/test-20261111-082550-59177.log`); the baseline 7374 passed / 2 skipped plus this run's four tests and one skip |
| 2026-11-11 | `gateway.sh test test/ui_standards_contract_test.dart` | **41 passed** (`All tests passed!`) |
| 2026-11-11 | invariant grep `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` | no matches |
| 2026-11-11 | `gateway.sh git-diff --stat` / `git-status` | `.claude/crew.md` (pre-existing, not this run's) plus the two new untracked test files and the plan folder — no `lib/`, `watch/` or existing test file changed |

## Phase B, part 1 (items 1, 2, 5, 6 — the seeded runner, the seams, the shrinker, S-14510)

`ConvergenceRun` sits in `test/helpers/watch_pair_harness.dart` (A-145-09), so both
test files import the helper. The runner is a weighted mint over the sixteen
actions of D-14505/D-14513, one `Random(seed)` for everything (D-14503), trace
length 8–40 (D-14510); `runSeed(seed, allowedActions:, length:)` is the
fixture-space seam (A-145-11), `replayActions(actions)` repeats a given trace.

### The three harness defects the sweep found (all fixed in this run)

| Id | Symptom | Diagnosis | Fix |
|---|---|---|---|
| F-lane | 12 seeds each took 10 011 ms, then the 200-seed run hung | `PairRadio.cross` awaited the phone's inbound handler for a wrist→phone frame; a push pass mid-`send` deadlocked against the `flush()` its own delivery triggered. Only production's 10 s `sendTimeout` broke it — a cycle production cannot have, because the phone reads the wrist's frame in another process | `unawaited(_deliver(...))` for the wrist→phone lane only (A-145-12). Those 12 seeds went from 20 s to under 1 s |
| F-drain | The 100-seed run hung inside seed 46's `LinkRises`, no progress and no output | `drainQueues()` used unbounded `while (queue.isNotEmpty)`; with the link up, every delivery a `refuseWhen` re-queued kept the queue non-empty | Each lane is bounded by its queue length at drain start (A-145-13); a frame enqueued during a drain stays owed for the next trigger |
| F-budget | The 200-seed run hung 900 s and the test's own 5-minute `Timeout` never fired | A pair whose every delivery provokes another never yields the event loop, and Dart runs pending microtasks before timers — so no timer, not even the test's, can end the run | A 20 000-delivery budget sets `radio.runaway` and delivers nothing after it (A-145-14); the sweep reports the seeds |

### F-seam (the `drainOnlyHeal` premise, item 8's seam)

The plan's premise — that a drain-only heal leaves an owed end undelivered — does
not hold, and the guard was written to what the seam actually guarantees, not
weakened: an end travels as a durable `session_lifecycle` that the OS queue alone
carries, so the drain-only heal still ends the session. What the full heal adds is
exactly the re-offer triggers (reconnect sync, resume, wrist `energy_live`), all
three of which appear in its rounds. `test/watch_convergence_harness_test.dart`:
`B1 drainOnlyHeal makes the heal one drain and nothing else` asserts the drain-only
heal is one round carrying only previously-queued frames, no `energy_live`, no
`request:*`, while the full heal carries both, and that both reach `completed`.

### S-14510 — red first, then green

Mutation (A-145-10): `Shrinker.shrink`'s `while (removedSomething) {` replaced by
`while (false && removedSomething) {`, run
`gateway.sh test test/watch_convergence_random_test.dart --plain-name "S-14510"`:

```
00:00 +0 -1: S-14510 the shrinker reduces S-14503 padded with 20 unrelated actions [E]
  Expected: a value less than or equal to <6>
    Actual: <25>
```

Restored byte-identically (`while (removedSomething) {`), the same filter run is
green inside the file-wide run below. `prove-red HEAD` cannot be used here: the
harness is new code, so the test cannot compile against `HEAD` (A-145-04's pattern).

### Run results

| When | Command | Result |
|---|---|---|
| 2026-11-11 | `gateway.sh test test/watch_convergence_random_test.dart` | **+4 ~1, all tests passed in 18–33 s** (seam, S-14502, the 200-seed sweep, S-14510; the convergence assertion is skipped for plan 146) — logs `.work/gateway/test-20261111-124009-95330.log`, `…-124101-95758.log` |
| 2026-11-11 | `gateway.sh test test/watch_convergence_harness_test.dart` | **+6 ~1, all tests passed** — the four Phase A tests plus the two B1 seams (output printed inline, not logged) |
| 2026-11-11 | `gateway.sh format` (each file by path) | three files formatted, `1 changed` each; re-run green after every pass |
| 2026-11-11 | `gateway.sh lint` | **181 issues** = baseline; the new file's six `avoid_print` notices were removed with one `// ignore_for_file: avoid_print` line (the sweep's report is its product), and no notice names any of the three files |
| 2026-11-11 | `gateway.sh test` (full suite) | **7383 passed, 4 skipped, 0 failed** (`All tests passed!`, log `.work/gateway/test-20261111-124148-96623.log`): the Phase A 7377/3 plus six tests and one skip |
| 2026-11-11 | `gateway.sh test test/ui_standards_contract_test.dart` | **41 passed** (`All tests passed!`) — no UI touched |
| 2026-11-11 | invariant grep `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` | no matches |
| 2026-11-11 | `git-status` | only the three untracked test files, the plan folder and `.claude/crew.md` (not this run's); nothing under `lib/` or `watch/` |

### What the 200-seed sweep measured (a finding set for plan 146, not an assertion)

Three consecutive runs of the same sweep, printed by the test:

```
convergence sweep: 56 of 200 seeds converge, 144 diverge
  (status=126, timers=15, entries=104, heal=8, absorbing=6, duplicates=3, rejected=6)
convergence sweep: heal never settles on seeds [10, 67, 112, 113, 180, 186]
convergence sweep: the pair never stopped answering itself on seeds [116, 130, 183]
  (refusals there: 13330, 10000, 13320)
convergence sweep: 36670 non-conformant frames refused on seeds
  [116, 120, 130, 175, 179, 183]; first: refusing to apply a non-conformant message:
  rejected: semantic_violation at $.payload.exercises: every sessionExerciseId MUST
  be unique within a session; repeated effort-…-0, effort-…-1
```

- **The seed-level results are not identical across processes.** Divergence counts
  moved by one or two seeds, and the heal-stall and runaway seed lists changed
  between runs (run 1: stalls `[10, 67, 71, 112, 113, 180, 186]`, runaways
  `[42, 44, 46, 54, 183]`; run 3: the lists above). Same-process determinism holds
  — S-14502 passes twice over — so the drift is either the phone's real-clock
  session id (A-145-02) or the per-process string-hash iteration order of a
  `Set`/`Map` the phone or the graph walks. Plan 146 needs one of those pinned
  before a finding can cite a seed as reproducible across runs.
- **The one repetitive finding: a payload the wrist refuses as non-conformant and
  the phone keeps emitting.** 36 670–89 988 refusals across 6–8 seeds, all
  `semantic_violation at $.payload.exercises: every sessionExerciseId MUST be
  unique within a session`, thrown by
  `WatchSessionEngine._requireConformingIncoming` (`lib/watch/session/watch_session_engine.dart:1849`).
  On the three runaway seeds the refusal repeats until the delivery budget stops
  the run, so "the pair never stopped answering itself" and "a repeated
  `sessionExerciseId`" are the same defect seen twice: the phone's projection
  duplicates an exercise id, the wrist refuses it, and the phone re-offers it
  forever.
- **Divergence kinds** are D-14507's checks as counted: status (126 seeds), entries
  (104), timers (15), heal rounds that never settle (8), absorbing ends (6),
  duplicate entry ids (3). Per D-14508 these are shipped as data — the sweep
  asserts only that no seed makes the pair throw — and the assertion that every
  seed converges is present and skipped for plan 146.

## Phase B, part 1b (harness faults H1–H4, re-triage, 2026-11-11)

Test-only run: the diff is the harness and the two convergence test files; nothing
under `lib/` or `watch/`.

### The four faults, test first, each proved by a mutation

`prove-red HEAD` is not usable (the harness is new code, so the tests cannot compile
against `HEAD` — A-145-04's pattern). Each fix was proved by mutating the fix in
place, running the test, restoring the exact original line, and re-running green.

| Fault | Test (plain `test()`) | Mutation applied | Verdict |
|---|---|---|---|
| H1 phone-side discard | `H1 a wrist discard ends the phone side too (S-14514 abandon trace) — A-14516` | `_phoneStatusOf`: dropped `\|\| _phoneHeld.contains(sessionId)` | **RED AT** `Expected: empty / Actual: ['session 1: phone active vs wrist abandoned']`; restored → green |
| H2 heal fixed point | `H2 the heal settles on unchanged state, not on silence — A-14517` | `if (round > 1 && state == previous)` → `state != previous` | **RED AT** `Expected: true / Actual: <false>`, trace shows heal rounds 1…10; restored → green |
| H3 phone inbox | `H3 an entry the phone received counts as held after the wrist moves on — A-14518` | inbox rows replaced by `const <String>[]` in `_sampleEntries` | **RED AT** `Expected: contains 'w-entry-1' / Actual: <null>` (phone set); restored → green |
| H4 double start | `H4 a second phone Start while a session is open keeps the session — A-14519` | guard removed: `if (phone.currentSession != null && false)` | **RED AT** `Expected: 'session-…920' / Actual: 'session-…939'` (a second id); restored → green |

`H4 a second wrist Start while a workout runs keeps it — A-14519` is green with and
without the harness guard, because `WatchSessionEngine.createSession` already keeps an
`active` session ("kept …, did not adopt") — it is a regression guard, kept
deliberately (A-145-19). A `H4 a double Start never exposes an entry twice` case was
written, found to pass under the mutation (`_addEntries` unions into a `Set`, so an
entry id cannot repeat there and the second snapshot carried no entries), and removed
rather than kept as a test that proves nothing.

### Red before the fix

The four tests and the four fixes landed in one pass (the tests do not compile without
the new harness fields), so "red first" is carried by the mutations above: each test
was observed failing for the reason it guards, with the fix removed, and green with it
restored. Completed-file runs:

| Command | Result |
|---|---|
| `gateway.sh test test/watch_convergence_harness_test.dart` (after the fixes) | **+11 ~1, all tests passed** (12 tests: the 7 Phase A/B1 cases and 5 new ones; S-14503 skipped for plan 146) |
| `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` | **+15 ~2, all tests passed** (log `.work/gateway/test-20261111-134625-12460.log`) |

### Re-triage of the 200-seed sweep (measured, printed by S-14509's healthy-harness test)

| | before (triage 1) | after H1–H4 |
|---|---|---|
| seeds converged | 42 / 200 | **87 / 200** |
| seeds diverged | 144 | **113** |
| kinds | status 126, entries 104, timers 15, heal 8, absorbing 6, duplicates 3, refused 6 | **status 94, timers 22, entries 22, heal 5, absorbing 10** |
| heal never settles | 6 seeds | **3 seeds `[10, 184, 187]`** |
| runaway / refused frames | 3 seeds, 36 670 refusals | **none (0 refusals, no runaway)** |

Read: the `duplicates` and `refused`/runaway families were H4's double start (a second
`createNewSession` made the phone re-offer a duplicated `sessionExerciseId`, which the
wrist refused until the delivery budget stopped the run), and most of the `heal`
family was H2. Both are gone.

The surviving `status` bucket has one dominant shape, visible in the log's last trace:

```
session 2: phone not held vs wrist completed
session 1: phone abandoned vs wrist not held
```

The first line is the next harness reading fault, not yet fixed: `_phoneStatusOf`
returns `null` for a phone row that **exists, is not ended and is not the current
session** — a session the phone holds but has moved on from — so it reads "not held"
against the wrist's `completed`. That ranks with H1 (A-145-20) and needs its own
test-first change.

### Not done in this run (next brief)

- Per-signature shrinking and classification of the remaining 113 seeds (`heal`,
  `timers`, `entries`, `absorbing` and the `status` remainder), each labelled harness
  fault or real finding with a code line.
- The cross-process determinism check: two separate `flutter test` processes diffing
  per-seed signatures for seeds 1–200. The sweep still reorders one or two seeds
  between runs (Phase B part 1's note), so no finding cites a seed as reproducible
  until this lands.

## Phase B, part 1c (developer B1c, 2026-11-11) — H5, A-145-21, re-triage, determinism

### H5 — the un-ended, off-screen row

`HarnessRunner._phoneStatusOf` returned `null` for a phone row that exists and is not
ended but is not `currentSession`: the phone answered "not held" for a session it
holds. It now records the id in `_phoneHeld` and answers `active`; `null` is reserved
for an id the phone has never had a row for. Guard:

| test | fixture | red (mutation) | green |
|---|---|---|---|
| `H5 a session the phone holds but has moved on from reads active, not missing — A-14520` | the wrist starts a workout the phone adopts (row opened), then the phone starts its own session, which replaces the session on screen and leaves the adopted row un-ended | `_phoneStatusOf`'s last two lines restored to `return null;` → `Expected: 'active' / Actual: <null>`, `check: DIVERGED` | `+1`, restored exact original |

The fixture is worth noting: with H4's guard in place a *second Start* cannot reach
`createNewSession`, and the adoption bridge refuses a wrist session while the phone
holds one ("kept session-…, did not adopt s-w-1"), so it creates no placeholder row.
The only reachable way to an un-ended, off-screen row is `loadHistoricalSession` — an
adoption or a history open that replaces the session on screen. The guard drives that
with `harness.phone.createNewSession()` (the state method; the harness's action wrapper
is what guards H4).

### A-145-21 — a session only one side ever held

`checkConvergence` sorts session ids by label (the raw ids carry the phone's clock),
splits each into shared / phone-only / wrist-only, keeps a solo id out of check 1's
status comparison and out of check 3's entry comparison, and reports the counts in
`ConvergenceReport.unsharedSummary`. Guard: `A-14521 a session only one side ever held
is counted, not a disagreement` (fixture: link down, the wrist starts and logs a set,
the phone starts its own session, check — the phone's row for the wrist id is absent).
Red by mutation: `final shared = phoneHeld && wristHeld;` → `final shared = true;`
gives `Expected: contains 'session 1' / Actual: []` on `phoneOnlySessions`; restored.

The item's product question for the owner: a wrist workout the phone never adopts is
now counted, never asserted — should the phone adopt it, or must the wrist workout
yield? Recorded as the tail of A-145-21.

### Re-triage, seeds 1–200, same action set as part 1b

```
convergence sweep: 117 of 200 seeds converge, 83 diverge
  (status=51, timers=22, heal=7, absorbing=10, entries=13)
convergence sweep: heal never settles on seeds [10, 71, 184]
convergence sweep: the pair never stopped answering itself on seeds []
convergence sweep: 0 non-conformant frames refused on seeds []
```

| metric | part 1b | part 1c |
|---|---|---|
| converge | 87 of 200 | **117 of 200** |
| kinds | status 94, timers 22, entries 22, heal 5, absorbing 10 | **status 51, timers 22, entries 13, heal 7, absorbing 10** |
| heal stalls | `[10, 184, 187]` | `[10, 71, 184]` |

The `status` bucket lost 43 seeds and `entries` 9. The entries drop is A-145-21 doing
its job (a solo session's entries are no longer compared against an empty set); the
status drop is mostly A-145-21 too — the distant-run lines such as `session 1: phone
not held vs wrist completed` are overwhelmingly *wrist-only* sessions, not the H5
row. Two read-only code facts were confirmed for that class:

- `session_started` is not in `_queueable` (`lib/core/platform/watch_transport.dart`),
  so a wrist start reaches the phone only while the link is up;
- `consider` refuses another session's snapshot while the phone holds an active one
  (`refusedConflict`), and `hasActiveSession` is `currentSession` un-ended **with at
  least one effort** (`lib/state/workout/session_core.dart`).

So a wrist workout started while the phone holds its own is never adopted — a gap
`_phoneStatusOf` cannot close, which is why the check counts it.

### Determinism across two processes

Two separate `flutter test test/watch_convergence_random_test.dart
--dart-define=CONVERGENCE_VERBOSE=true` processes, identical summaries, identical
861-line output, 200 `seed=N kinds=` lines each, and the sampled window
(seeds 46–66) is line-for-line identical in both logs:

- `.work/gateway/test-20261111-141113-26275.log`
- `.work/gateway/test-20261111-141127-26447.log`

The only differing lines are the phone's clock-derived session ids inside the pair's
own `Watch session sync: kept session-…` notices; the report is comparable because
ids are labelled (`labelFor`) and both the id list and the entry lists are sorted. A
seed no longer reorders between runs.

### Not done in this run

- Per-signature shrinking and classification of the remaining 83 diverging seeds. The
  kinds above are the four product-level groups the sweep reports; no minimal trace
  was produced and no seed is labelled REAL FINDING / HARNESS FAULT here.
  `.work/2026-11-10-145-convergence-test/triage_scratch_test.dart.txt` was never
  copied to `test/zz_triage_scratch_test.dart`, so nothing was left behind to delete.
- The two brief-named code leads were read but not exercised end to end: a rest timer
  surviving on an abandoned session (the sweep's `timers` kind still reports it:
  `session 1: a rest timer runs on the wrist although the session is abandoned`), and
  a stale phone `active` snapshot re-adopting a row the phone discarded.

## Triage 1c (lead, 2026-11-11): what the surviving divergences are

The part-1c developer run stopped before classifying; the lead shrank one representative per signature (greedy shrinker, `allowedActions` excluding the synthetic re-assert, so every action is shipping-reachable). After the two last harness faults (A-145-22, A-145-23) the sweep reads **141 of 200 converge, 59 diverge** (timers 25, status 23, absorbing 12, heal 5, entries 6; the earlier 144 → 112 → 82 → 54 steps came from H1-H5, A-145-21, H6, H7). Scratch outputs: `.work/2026-11-10-145-convergence-test/triage-1-output.txt`. Raw minimal traces below are the ones the shrinker printed.

| Signature | Minimal trace | Classification | Why |
|---|---|---|---|
| timers (seeds 30, 46, 1…) | 1. phone starts a session. 2. phone starts a rest timer. 3. phone discards. (no faults) | **REAL FINDING** (plan 146, low severity) | Both sides still report a running rest timer on an abandoned workout. A rest timer is not cleared by an end/discard on either side's observable state. UI impact not confirmed (the screen leaves the workout); the data is wrong. Wrist twin: `abandonSession`/`finishSession` and `_applyTimerState` (`watch_session_engine.dart`). |
| absorbing (seed 50) | 1. wrist starts a Free workout. 2. link drops. 3. wrist finishes. 4. phone starts a rest timer. 5. link rises. | **REAL FINDING F-2** (plan 146) | The phone, unaware of the end, sends a NEWER active snapshot (by `sentAt`) after the wrist finished; the wrist reports `active` again. "Ignore older by sentAt" cannot catch it because the phone's frame really is newer. Only "ended is final" (status beats time) fixes it. This is S-14504's shape; the seeded prediction (green) was wrong. |
| status (seed 14) | 1. wrist starts a Free workout. 2. phone discards. 3. wrist finishes (the wrist already heard `abandoned`). 4. phone starts a session. | **REAL FINDING** (engine level, plan 146); UI reachability unconfirmed | The wrist engine turns an `abandoned` session into `completed` when `finishSession` is called on it; the end is not final inside the engine. The wrist UI leaves an abandoned workout, so a user rarely reaches this, but the rule "ended is final" must reach the engine. |
| status (seed 77) | 1. phone starts a session. 2. link drops. 3. phone discards. 4. phone starts a session. 5. phone starts a rest timer. 6. phone finishes. | **REAL FINDING** (plan 146) | The wrist keeps the discarded workout `active` while apart (the discard lifecycle is queued) and the timer line repeats the ended-session timer finding. The status line is the S-14512 family: two devices hold different ends until the link returns. Re-check after the heal: the heal brought it to `phone abandoned vs wrist active`, so the abandon is still not reaching an active wrist session at the end of the heal. Needs its own look in plan 146. |
| entries (seeds 29, 68) | 1. wrist starts a Free workout. 2. link drops. 3. phone logs a set. 4. wrist finishes (or discards). 5. wrist starts a Free workout. | **REAL FINDING / DESIGN QUESTION** | The phone's set for workout 1 never reaches a wrist that already ended it and moved on; the wrist holds one session at a time, so the set exists on the phone only. Data is not lost (it is on the phone) but check 3 (same entry set on both sides) cannot hold after the wrist moves on. Owner/plan 146 decides whether check 3 applies after the wrist has ended and left a workout. |
| heal only (seeds 86, 142, 10, 184) | three phone actions, or 19-36 actions | **HARNESS FLAKE, unresolved** | The same 3-action trace converges in 16 of 16 standalone replays, but the seed stalls inside the 200-seed sweep: state leaks between runs inside one process (the sweep reuses the isolate), or a real async race the `pumpEventQueue` settle does not cover. Seeds listed vary slightly between processes. Needs its own unit (run each seed in isolation, or find the leak). Until then a heal that "never settles" is counted, never cited as a finding.

## Phase B, part 2 (developer B2part, 2026-11-11) — S-14504/06/07, the runner seam, S-14508 and S-14509

Test-only: `test/helpers/watch_pair_harness.dart`, `test/watch_convergence_harness_test.dart`
and `test/watch_convergence_random_test.dart`. Nothing under `lib/` or `watch/` changed.

### The runner seam (Phase B item 4 — S-14508's and S-14509's prerequisite)

`ConvergenceRun.runSeed(seed, {allowedActions, length, engineFactory, drainOnlyHeal = false})`
and `ConvergenceRun.replayActions(actions, {seed = -1, engineFactory, drainOnlyHeal = false})`
now pass `engineFactory` to `WatchPairHarness.build` and set `pair.drainOnlyHeal`, so both
mutations are reachable through the runner and no test needs a second harness path. Guards:
`B2 runSeed takes the wrist engine factory and the drain-only heal` and `B2 replayActions takes
the wrist engine factory and the drain-only heal` — each asserts `pair.wristEngine` is
`same(injected)`, `pair.drainOnlyHeal` is true, and `run.heal.rounds` has length 1 (the
positive evidence that the heal really was one drain and not a request/answer exchange);
`replayActions` also asserts `injected!.applied > 0`, so the injected engine is the one that
served the run.

### The three scripted measurements — all green unskipped

No `skip: 'plan 146: …'` was written for any of the three: each run reproduced the outcome the
scenario register predicted.

| Scenario | Test | Outcome (`+18 ~1` file, green) |
|---|---|---|
| S-14504 | `S-14504 a wrist finish while apart is final against the phone's later set` | both sides read `completed`, the phone's set is on both sides, checks 2–4 clean |
| S-14506 | `S-14506 a phone discard is final against the wrist's later set` | both sides read `abandoned`, four checks clean, the wrist's later set still in the wrist's own record |
| S-14507 | `S-14507 both sides start a rest within the same second: the tally is measured, not asserted` | tally **0 disagreements**; both sides `{rest: {kind: rest, state: running, startedAt: …T19:37:14.170Z, accumulatedPauseMs: 0}}` |

S-14507 prints the tally and both timer maps and asserts only `isNonNegative` plus both sides
live — D-14508's "measured, never asserted" for this class.

S-14504 needed a change of shape mid-item (A-145-28). Its trace shows the phone's queued
`session_snapshot` (status active) draining to the wrist *before* the phone's own `completed`
announcement inside the same "link rises" action, so the reopen is corrected within one action
and check 2's per-action sampling can never see it. The test therefore also asserts the fixture
— `harness.radio.phoneQueue` holds the phone's active snapshot while the link is apart, i.e. the
F-2 shape is really exercised — plus the per-action outcomes above. The `print`s used to read
those two traces were removed before the final run.

### S-14508 — the wrist that ignores a completed lifecycle

`_MutationWrist extends WatchSessionEngine` refuses every `session_lifecycle` frame whose
`state` is `completed` (the private `_applyLifecycle` cannot be overridden from another library,
so the intercept is `applyMessage`) and counts `ignoredCompleted` and `applied`. Seeds 1..60,
`kShippingActions` (the sweep's action space minus `PhoneReassertsLive`, so every action a
shipping app can produce):

```
S-14508 mutation red on seeds [7] of 1..60 (173 completed lifecycles ignored; 44 converging seeds never depended on one)
S-14508 seed=7 minimal trace under the mutation:
1. wrist starts a Free workout
2. phone finishes
3. link drops
4. wrist discards
5. link rises and drains the queue
6. wrist starts a Free workout
```

The test asserts `redSeeds` `isNotEmpty` (with the checks that must fire named in the reason),
`ignoredCompleted > 0` (the mutation was actually reached), and that the shrunk trace is red
under the mutation after being green without it. A converging seed that never depends on the
wrist hearing the end is counted (`44`) instead of failing, so a future silent "no red" is
visible rather than a pass (A-145-25).

### S-14509 — the drain-only heal

`HarnessRunner.heal()` with `drainOnlyHeal` on returns one `HealReport` built from
`radio.drainQueues()` alone: no `orchestrator.sync(reconnect: true)`, no phone resume trigger
`graph.sync()`, no wrist frame. 200 seeds, `kShippingActions`:

```
S-14509 drain-only heal: red seeds [9, 37, 61, 69, 96, 125, 128, 141, 160, 170, 194] of 1..200; drain-only runs that diverge at all: [1, 9, 14, 18, 22, 27, 29, 30, 31, 37, 39, 44, 46, 47, 50, 53, 58, 61, 63, 68] … (65)
```

11 seeds converge with the full heal and fail check 1 or 2 on the drain alone, so the heal's
re-offer triggers carry the owed end and are not a redundant extra round (A-145-26). The item
allowed a no-red outcome as evidence too; the measurement rejected it, so the assertion is
`isNotEmpty` with the count and the meaning of a reversal in its reason.

Two notes on that print. The red seed list was identical in both runs; the trailing total of
drain-only runs that diverge *at all* read 64 in the run before the lint fix and 65 in the final
one, and the first-20 sample starts `[1, 9, 14, 18, …]` — those are seeds diverging for their own
unrelated reasons, which is why the red list (full-heal-green, drain-red) and not the total is
the finding. And per the triage above, one of the 11 could in principle be the unresolved
heal-only flake; the list is stable across two processes, which is the evidence it is not.

### The mutation proofs

`prove-red HEAD test <files>` cannot carry these files: `test/helpers/watch_pair_harness.dart`
and both convergence test files are untracked in this branch, so the tests do not compile
against `HEAD` (A-145-04's pattern, A-145-24). Every new guard was proved by mutating the line
it protects, running only the affected file, restoring the exact original line, and re-running
green.

| Guard | Mutation applied | Verdict | After restore |
|---|---|---|---|
| `B2 runSeed takes the wrist engine factory and the drain-only heal` | `runSeed`: `WatchPairHarness.build(engineFactory: engineFactory)` → `build()`, and `pair.drainOnlyHeal = drainOnlyHeal` → `= false` | **RED** — fired on `expect(run.pair.wristEngine, same(injected), reason: 'the seed run built its wrist from the injected factory')` | green |
| `S-14509 a drain-only heal …` (same mutation, same run) | as above | **RED** — fired on `expect(redSeeds, isNotEmpty)`: with the flag off a drain-only run equals its full run, so the red list empties | green |
| `B2 replayActions takes the wrist engine factory and the drain-only heal` | the same two substitutions in `replayActions` | **RED** — fired on `expect(run.pair.wristEngine, same(injected))` | green |
| `S-14508 …` | no-op mutation: `_MutationWrist.applyMessage`'s ignore branch made to `return super.applyMessage(message)` | **RED** — fired on `expect(redSeeds, isNotEmpty)`: the red list empties, so the test cannot pass on a mutation that carries nothing | green |

Incidental measurement from the same base: a `_MutationWrist` that refuses `abandoned` instead
of `completed` puts seeds **4, 42, 43, 49** in the red list — the pair depends on both ends
being heard (A-145-27).

### Runs

| Command | Result |
|---|---|
| `gateway.sh test test/watch_convergence_harness_test.dart` | **+18 ~1, all tests passed** (19 registered: 18 passed, S-14503 skipped for plan 146) |
| `gateway.sh test test/watch_convergence_random_test.dart` | **+8 ~1, all tests passed** (9 registered) |
| `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` | **+26 ~2, all tests passed**, 16 s of test time (`All tests passed!`; log `.work/gateway/test-20261111-143927-37221.log`) |
| `gateway.sh lint` | **181 issues = the baseline**, none in the three files touched. One new `unnecessary_brace_in_string_interps` notice appeared at `test/watch_convergence_random_test.dart:314` (182) and was fixed before the final run, so the count returned to 181 |
| `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart test/ui_standards_contract_test.dart` (final, after the lint fix) | **+67 ~2, All tests passed!**, 17 s of test time — the 26 convergence tests plus 41 `ui_standards_contract_test` cases, so the source scans are clean with the new test code in the tree (log `.work/gateway/test-20261111-144309-38675.log`) |
 |

Not a harness fault, not asserted: a workout the wrist ran while the phone held its own is never adopted by the phone (`wrist-only` sessions, A-145-21). Product question for the owner: should the phone adopt it, or must the wrist workout yield?

Cross-process determinism: part 1c reports 200 byte-identical seed lines across two processes; the heal-flake above is the one exception and is outside what that comparison saw.

### S-14507 re-measured by the lead (A-145-30)

The developer's version started both rests at one instant (tally 0, which proves nothing). The test now measures gaps of 0 ms, 700 ms and 20 s between the phone's and the wrist's rest starts: **tally 0 on all three**, both sides end holding one `rest` with the same `startedAt`. So in this model two rests started while apart do not stay disagreeing: one start wins after the heal. Not measured: which side wins, and whether the winning start is the right one for the user. For the timer-owner decision this says a separate "timer owner" rule is not needed to make the two sides agree; it does not say the surviving start time is the one the user expects. The `startedAt` values are real-clock (the phone's `recordRestStart` uses `DateTime.now()`), another real-clock leak next to A-145-02.

### S-14504 note (lead)

The developer's S-14504 passes: with the phone logging a SET while apart, the phone's own `completed` announcement drains in the same "link rises" action and corrects the wrist before the next sample. The F-2 revival the lead found (triage seed 50) needs a different trigger: the phone starts a REST while apart, so the phone sends a newer active snapshot and no end. The F-2 replay test is Phase C's job (one skipped replay per finding); S-14504 as written stays a guard.

## Phase B2 (developer B2, 2026-11-11) — S-14511 … S-14517 scripted, five guards proved

Scope of this run: the two convergence test files only (the brief's rule); `lib/` and `watch/` are unchanged apart from mutations that were restored, and `git-status` shows no `lib/` modification.

### What was written

- `test/helpers/watch_pair_harness.dart` — `kNoSessionActions` moved here from the random test, above `_WristTransport` (A-145-31). Nothing else in the file changed; the five mutation points used below were all restored exactly.
- `test/watch_convergence_harness_test.dart` — `_b2Tests()` with the seven tests, plus four top-level helpers (`_wristEnergyFrame`, `_payloadOf`, `_completedEndsSince`, `_isRunning`) and two imports (`watch_delivery.dart`, `message_validator.dart`). It registers **25 tests** (`+25 ~1`).
- `test/watch_convergence_random_test.dart` — only the `kNoSessionActions` deletion; still `+8 ~1`.

### Outcome per scenario

| S-id | Kind | Outcome as measured |
|---|---|---|
| S-14511 | guard | Green. The queued `observations_up` is delivered after the relaunch, the phone stages the entry, one session id exists, both sides end `completed`, the entry id is in both unions, and nothing reports `active` again |
| S-14512 | measurement | Both sides end **`completed`**; check 1 clean (0 mismatches, 0 entry mismatches), check 2 silent. Not a finding, so no `skip:` (A-145-33) |
| S-14513 | measurement | W1's owed end is confirmed after W2 started, W2 is `active` on both sides, W1 never reports `active` again, check 1 holds per session id. Not a finding, no `skip:` |
| S-14514 | guard | Exactly one owed end re-offered in each 30 s window, unions match, no id twice, check 2 silent (per-window counting, A-145-34) |
| S-14515 | guard | Zero sessions reported, four checks clean, no crash over the empty-fixture action space |
| S-14516 | guard | The refused durable `session_snapshot` is `queued`, the heal delivers it, check 3 passes |
| S-14517 | guard | The refused `timer_state` is `undelivered`, nothing is queued for it, unions match, check 4 holds, timer tally **0** (A-145-35) |

The two measurements printed their evidence on green:
- `phone completed wrist completed, 0 mismatch(es), 0 entry mismatch(es)` (S-14512)
- `timer tally 0: phone timers {rest: running …}, wrist timers {rest: running …}` (S-14517)

### Deliberate breaks — one per guard, each restored exactly

`prove-red HEAD` cannot prove these: all three test files of this plan are untracked in this branch, so there is no committed code to run them against. Every guard was therefore proved by a mutation of the code it pins.

| Scenario | Mutation (original → mutated) | Red verdict (verbatim) | Restored |
|---|---|---|---|
| S-14511 | `WristKilled` case: `harness.radio.wristQueue.clear();` added **and** `relaunchWrist()` launched on a fresh `InMemoryWatchSessionStore()` instead of the surviving store | `session 1 was completed on the wrist and reports active again` ×4, `absorbingViolations`, `test/watch_convergence_harness_test.dart 759` | yes |
| S-14514 | `watch_incoming_router.dart`, `_reofferOwedEnd`: `if (owed != null) {` → `if (owed != null && false) {` | `Expected: an object with length of <1>` / `Actual: []` — "one owed end re-offered for the first window", line 940 | yes |
| S-14515 | `_mint`: the `allowedActions == null ? options : [...]` filter → `final allowed = options;` | `Expected: empty` / `Actual: [` (the report carried failures), line 989 | yes |
| S-14516 | `PairRadio._enqueue`, phone lane: `if (!WatchConnectivityTransport.isDurable(frame)) return false;` → `if (frame['type'] == 'session_snapshot') return false;` | `Expected: WatchDelivery:<WatchDelivery.queued>` / `Actual: WatchDelivery:<WatchDelivery.undelivered>`, line 1033 | yes |
| S-14517 | `PairRadio.isWristQueueable`: added `'timer_state' => true,` | `Expected: WatchDelivery:<WatchDelivery.undelivered>` / `Actual: WatchDelivery:<WatchDelivery.queued>`, line 1095 | yes |

Two S-14511 attempts are recorded because they stayed green and are the reason A-145-32 exists: clearing only `wristQueue`, and skipping only `restore()` in `relaunchWrist`. Each stays green because the heal's reconnect snapshot re-offers both the observation and the session.

### Runs

| Command | Result |
|---|---|
| `gateway.sh test test/watch_convergence_harness_test.dart` | **+25 ~1, all tests passed** (26 registered: 25 passed, S-14503 skipped for plan 146) |
| `gateway.sh test test/watch_convergence_random_test.dart` | **+8 ~1, all tests passed**, ~17 s |
| `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` (final, after every mutation was restored) | **+33 ~2, All tests passed!**, 17 s of test time (log `.work/gateway/test-20261111-155902-49712.log`) |
| `gateway.sh lint` | **181 issues = the baseline**, and no notice names `test/watch_convergence_harness_test.dart`, `test/watch_convergence_random_test.dart` or `test/helpers/watch_pair_harness.dart` (log `.work/gateway/lint-20261111-155924-49889.log`) |
| `gateway.sh test test/ui_standards_contract_test.dart` | **+41, All tests passed!** |
| invariant grep (`import .*hive_workout_repository` under `lib/`) | only `lib/main.dart` (the composition root); nothing in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` |
| `gateway.sh git-diff --stat` | `.claude/crew.md` only — not this plan's; no `lib/`, no `watch/`, no tracked test file |

The full `flutter test` suite was not run in this phase: the brief scoped the run to the two convergence files. Phase C item 5 owns the consolidated full-suite run.

Red-run logs kept: `.work/gateway/test-20261111-155829-49116.log` (S-14515). The S-14514, S-14516 and S-14517 red runs and the S-14511 red run were read from the gateway's inline output.

## Phase C — the 200-seed sweep, the 2000-seed soak, and one replay per finding

### Findings (each one is now a skipped replay test)

| id | check | seed | shrunk trace (action count of the seed's) | message today |
|---|---|---|---|---|
| F-1 | status/absorbing | S-14503 | five actions, in `test/watch_convergence_harness_test.dart` | a finished workout is reopened by a queued `started` — already skipped, not duplicated here |
| F-2 | absorbing | 50 (triage), 40 (sweep) | 1. wrist starts a Free workout. 2. link drops. 3. wrist finishes. 4. phone starts a rest timer. 5. link rises. (shipping-reachable; the sweep's seed-40 shape needed the harness-only re-assert) | `session 1 was completed on the wrist and reports active again` |
| F-3 | timers | 2 | 1. phone starts a session. 2. phone starts a rest timer. 3. phone discards. (3 of 23) | `session 1: a rest timer runs on the phone/wrist although the session is abandoned` |
| F-4 | status | 4 | 1. phone starts a session. 2. wrist discards. 3. link drops. 4. phone starts a session. 5. wrist finishes. (5 of 38) | `session 2: phone abandoned vs wrist completed` |
| F-5 | status | 104 | 1. wrist starts a Free workout. 2. link drops. 3. phone discards. 4. phone starts a session. (shrunk 25 → 4 by the lead) | `session 1: phone abandoned vs wrist active` |
| F-6 | entries | 14 | 1. phone starts a session. 2. link drops. 3. wrist discards. 4. wrist starts a Free workout. 5. phone logs a set. (5 of 35) | `session 1: the wrist never held entry-…-0-2, entry-…-0-3` |
| F-7 | duplicates (soak-only) | 408 | 1. wrist starts a Free workout. 2. link drops. 3. phone discards. 4. phone starts a session. 5. wrist discards. 6. wrist starts a Free workout. 7. a live frame from the wrist refused. 8. phone logs a set. (shrunk 24 → 8 by the lead) | `session 2: the wrist exposed the set twice` |

`F-2` and `F-4` are the same rule in two places — an ended session is not final — so
unit 146 "ended is final" is the fix for both. `F-6` is the open product question
(does check 3 apply once the wrist has ended that workout and moved on):
the set is not lost, it is on the phone only, and the wrist holds one session at a
time. `F-2`'s shrunk trace needs the harness-only re-assert (no build can send
it); the shipping flavour of the same hole was seed 50 of the earlier triage:
the phone sends a *newer* active snapshot after the wrist finished, so
"ignore older by `sentAt`" cannot catch it.

### The 200-seed sweep (verbose)

`gateway.sh test test/watch_convergence_random_test.dart --plain-name "S-14509 the random seeds" --dart-define=CONVERGENCE_VERBOSE=true`
→ **142 of 200 seeds converge, 58 diverge** (timers=25, status=23, absorbing=12,
entries=6, heal=4, duplicates=0); heal never settles on `[10]`; the pair never
stopped answering itself on `[]`; 0 non-conformant frames refused; 00:04,
`+1: All tests passed!`. Every diverging seed's `seed=N kinds=…` line and the
full traces are in `.work/gateway/test-20261111-182941-61845.log`.

| check | seeds (of 200) |
|---|---|
| timers | 2, 10, 11, 18, 42, 57, 62, 68, 70, 81, 84, 89, 109, 115, 117, 118, 125, 135, 145, 146, 150, 152, 156, 160, 198 |
| status | 4, 6, 15, 29, 33, 41, 53, 67, 71, 72, 73, 82, 97, 104, 110, 114, 138, 141, 142, 145, 170, 175, 180 |
| absorbing | 10, 40, 65, 70, 72, 83, 88, 111, 141, 150, 182, 198 |
| entries | 14, 104, 110, 113, 127, 165 |
| heal | 10, 84, 89, 183 |
| duplicates | none |

Seeds per check sum to more than 58 because a seed can fail several.

### The 2000-seed soak (43 s, inside the 5-minute budget)

| run | result |
|---|---|
| `--dart-define=CONVERGENCE_SEEDS=2000` | **1349 of 2000 converge, 651 diverge** (timers=293, status=234, absorbing=161, heal=66, entries=56, **duplicates=2**); heal never settles on 34 seeds `[10, 316, 500, 540, 633, 660, 671, 672, 701, 708, 776, 844, 960, 961, 1001, 1016, 1058, 1076, 1080, 1321, 1385, 1430, 1487, 1496, 1556, 1561, 1569, 1580, 1632, 1648, 1683, 1697, 1885, 1887, 1950]`; runaways `[]`; 0 refusals; 00:43, `+1` passed (`.work/gateway/test-20261111-183221-63246.log`) |
| the same with `--dart-define=CONVERGENCE_VERBOSE=true` | **1345 of 2000 converge, 655 diverge** (timers=293, status=234, absorbing=161, heal=69, entries=58, duplicates=2) — the duplicate seeds are 408 and 660; 00:43, `+1` passed (`.work/gateway/test-20261111-183319-63648.log`) |

The soak's `duplicates` kind is the one the 200-seed sweep never produced, so it
gets a replay of its own (F-7, above).

**The two soak processes disagree by four seeds** (heal 66 vs 69, entries 56 vs
58). A seed reads the same twice *within* a process (S-14502), so this is not a
missing seed; something in the run depends on process state — wall-clock ids are
visible in the traces (`session-1794440…`). Recorded for unit 146 / the harness
owner: a cross-process diff of `seed=N kinds=…` lines is only meaningful for the
action sequences, not for the verdict. It is also why the heal replay was
dropped, below.

### Red runs (each F-test proves it is not decoration)

Run once with the `skip` removed, then restored — the failure is the invariant
the test guards:

| test | failing assertion (verbatim) | log |
|---|---|---|
| F-3 | `Expected: empty` / `Actual: ['session 1: a rest timer runs on the phone although the session is abandoned', 'session 1: a rest timer runs on the wrist although the session is abandoned']` | `test-20261111-183154-62966.log` |
| F-2 | `Expected: empty` / `Actual: ['session 2 was completed on the wrist and reports active again', 'session 2 was completed on the wrist and reports active again']` | same |
| F-4 | `Expected: empty` / `Actual: ['session 2: phone abandoned vs wrist completed']` | same |
| F-5 | `Expected: empty` / `Actual: ['session 1: phone abandoned vs wrist active']` | same |
| F-6 | `Expected: empty` / `Actual: ['session 1: the wrist never held entry-effort-1794439916141-0-2, entry-effort-1794439916141-0-3']` | same |
| F-7 | `Expected: empty` / `Actual: ['session 3: the wrist exposed entry-effort-1794440060582-0-1 twice']` | `test-20261111-183418-64030.log` |

That run reported `+1 -5`: the six F-tests became five red and one green.

### Dropped: the heal finding as a replay

Seed 183 reported `kinds=heal` ("the heal did not reach its fixed point") in the
first probe and shrank to three plain actions (1. phone starts a session. 2.
phone logs a set. 3. phone logs a set), but the same seed **passed** with the
`skip` removed in the F-run (`+1 -5`, the `+1` is F-7-as-heal). Given the
cross-process variance above, a heal that never settles is real — 34 of 2000
seeds in one process, 69 in another — but it is not reproducible by seed, so it
stays a soak measurement and does not become a skipped replay. Unit 146 should
fix the heal's fixed point first and then decide whether to freeze one seed.

### Residue sweep (item 5)

`grep -rn "_QRadio" test/` → four hits, all in
`test/watch_session_end_owed_test.dart` (the file the sweep excludes): clean.

### Docs

`docs/state_management/watch_surface_transport.md`: 142 → 188 lines
(`git-diff --stat` → `46 insertions(+)`, no line removed) with a new
`### Convergence testing` section (harness, replay, the two defines, reading a
numbered trace, findings as skipped replays, the phone-app kill that is not
modelled). Byte sizes could not be measured (no shell for `wc`); the file is
well under the 64 KiB cap and `test/docs_indexing_contract_test.dart` is green.

### Runs

| Command | Result |
|---|---|
| `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` | **+33 ~8, All tests passed!**, 16 s (`.work/gateway/test-20261111-183425-64152.log`); the 8 skips are S-14503, the every-seed test, and F-2 to F-7 |
| `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` | **+54, All tests passed!**, 1 s |
| `gateway.sh test test/docs_indexing_contract_test.dart` (re-run after the plan and evidence edits) | **+13, All tests passed!** — the plan folder is still inside the indexing ceiling and its links resolve |
| `gateway.sh lint` | **181 issues = baseline**; exit 1 on the repo's pre-existing notices; no notice names either convergence test file or the doc (`grep` over `.work/gateway/lint-20261111-183447-64333.log` → no match) |
| invariant grep (`import .*hive_workout_repository` under `lib/state lib/features lib/widgets lib/core`) | nothing |
| `git-status` / `git-diff --stat` | only `docs/state_management/watch_surface_transport.md` modified (+46/-0); the plan folder and the three test files are untracked; `.claude/crew.md` was already modified before this run and is not touched |

Nothing under `lib/` or `watch/` was changed: this phase is test-only plus docs.




### Lead fix-up after the Phase C run (2026-11-11)

The developer's F-tests replayed whole seeds, F-2 used the harness-only `PhoneReassertsLive`, and F-5/F-7 were never shrunk. The lead rewrote F-2..F-7 as explicit shipping-reachable action lists (the traces in the findings table above), shrunk F-5 (25 → 4 actions) and F-7 (24 → 8) with the `Shrinker`, and re-proved all six red with the `skip` removed (`+0 -6`; one first-line assertion each: F-2 `session 1 was completed on the wrist and reports active again`, F-3 two rest-timer lines, F-4 `phone abandoned vs wrist completed`, F-5 `phone abandoned vs wrist active`, F-6 `the wrist never held entry-…`, F-7 `the wrist exposed entry-… twice`), then restored the skips. A first F-2 draft without the final `link rises` passed (the heal does not raise the link by itself), so the trace has five steps. Lead's full run, 900 s timeout: `flutter test` → `+7406 ~10: All tests passed!` in 05:03 (plan item 5); residue grep for `_QRadio` clean; docs page 8,993 → 11,878 bytes (+46 lines).