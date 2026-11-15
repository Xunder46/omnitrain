# Evidence — plan 163: kill cases in the randomized convergence sweep

Run: 2026-11-14, @developer, branch `claude_develop`, tree at `c664f215` + the edits below.
Shell: `.github/copilot/scripts/macos/gateway.sh` only.

## Files changed in this run

- `test/helpers/watch_pair_harness.dart` — Phases 1-2 + the relaunch fidelity fix (F-163-1).
- `test/watch_convergence_random_test.dart` — Phase 1 (seam) + Phase 2 (shipping space).
- `docs/plans/2026-11-14-163-kill-cases-in-the-sweep-plan/*` (this file + Progress).

No file under `lib/` or `watch/` was touched (D-16307).

## Phase 1 — the action, the relaunch, the seam (S-16301)

| # | Item | Result |
| --- | --- | --- |
| 1-2 | `PhoneKilledAndRelaunched` class + `phoneKilledAndRelaunched()` mint | done |
| 3 | `phone`/`graph` → backing fields + getters; `build()` → `_launchPhone()` + `_launchWrist()` | done |
| 4 | `relaunchPhone()` beside `relaunchWrist()` | done |
| 5 | `perform` case → `relaunchPhone()`; phone kill records no replay event (D-16303) | done |
| 6 | `kNoSessionActions` member + comment at `recordReplayKill` | done |
| 7 | Seam test extension (S-16301) | done |

### Red → green

| Check | Before Phase 2 (action not drawn) | After Phase 2 (option added) |
| --- | --- | --- |
| `test ... --plain-name "the allowed-actions seam"` | RED — `Expected: non-empty / Actual: Set:[]` at `test/watch_convergence_random_test.dart:98:7` (the seeds drew no phone kill) | `+1: All tests passed!` |
| `test ... --plain-name "S-14502"` | green (the seeded draw stream is unchanged by the refactor) | green |

RED AT: `test/watch_convergence_random_test.dart:98:7` — exactly the assertion S-16301
adds (the generator must be able to draw the phone kill), not an import or typo failure.

## F-163-1 — a harness fidelity fault the sealed sweep found (Phase 1.Y / 2.Y)

**What the first measurement showed.** With the kill in the space, the 200-seed sweep
went red at 43 shipping divergences (budget 8), all in the known `status` class
(`by class {status: 54, heal: 3}`).

**Why.** `seed=5` went `phone starts a session` → `phone killed` → `phone starts a
session` again: `_phoneStartsSession` guarded on `phone.currentSession`, which a fresh
`WorkoutState` does not have, so the harness started a SECOND session beside an open
phone row. The shipping app cannot do that: `HomeScreen` restores a dangling session on
its first frame (`checkForInProgressSession()` then `loadHistoricalSession()`,
`lib/features/home/home_screen.dart`) and plan 145's A-145-19 records that Home offers
Resume — a start while a session is open is a no-op. The relaunch therefore persisted
LESS phone state than the app, which let the sweep perform a trace the app never
performs: a fidelity violation of D-16302's own rule, and the source of most of the new
divergences.

**Fix** (`_launchPhone()`, after the graph is built, mirroring production's order):
`checkForInProgressSession()` then `loadHistoricalSession(id)` when a dangling row
exists.

**Mutation check (recorded, then restored exactly):**

| Harness state | 200-seed shipping divergences | by class |
| --- | --- | --- |
| kill option removed (pre-change baseline; only the refactor + fix in the tree) | 3 — `[94, 162, 169]` | `{heal: 4, status: 5}` — test GREEN |
| kill option present, restore lines REMOVED | 43 — `[1, 5, 9, 22, 26, …]` | `{status: 54, heal: 3}` |
| kill option present, restore lines present (final) | 14 — `[32, 34, 46, 50, 65, 102, 105, 113, 127, 149, 152, 153, 178, 200]` | `{status: 12, heal: 3, absorbing: 2}` |

The mutation (removing the two restore lines) turns the run from 14 to 43, and restoring
them returns it to 14 — the guard is load-bearing.

## Phase 2 — the 200-seed re-measurement (S-16308, S-16310)

Two full 200-seed runs at the final code (`kSeedCount` defaults to 200):

| Run | Contract line | by class | Verdict |
| --- | --- | --- | --- |
| `--plain-name "every random seed converges"` (filtered) | 183 converge; 14 shipping `[32, 34, 46, 50, 65, 102, 105, 113, 127, 149, 152, 153, 178, 200]`; 3 heal-only `[70, 148, 169]`; 0 re-assert-only | `{status: 12, heal: 3, absorbing: 2}` | RED: `Expected: <= 8, Actual: 14` (`test/watch_convergence_random_test.dart:315:7`) |
| whole file (`test/watch_convergence_random_test.dart`) | 182 converge; the SAME 14 shipping seeds; 2 heal-only `[83, 155]`; 2 re-assert-only `[70, 131]` | `{status: 13, heal: 2, absorbing: 3}` | RED on the same assert; `+14 -1`, every other test green |

Logs: `.work/gateway/test-20261114-184732-17109.log` (43), `.work/gateway/test-20261114-185132-17814.log` (14, filtered),
`.work/gateway/test-20261114-185250-19590.log` (baseline 3), `.work/gateway/test-20261114-185349-19927.log` (14, whole file).

Both diverging classes, `status` and `absorbing`, are already named in `knownClasses`
(plan 161's A-161-05 residue and plan 146's O-2 class), so **no new class entered the
register** and the plan's `unknown` expect stayed green in every run. The total,
however, moved from 3 to 14, above the standing `shippingRatchet` of 8.

### Residue R-163-1 — the phone kill widens the known `status` class (12-13 of 14)

Not a new class: `seed=32` (listed first in both runs) carries no kill at all and still
diverges, so the class is reachable without the new action; the kills only change the
draw stream and add their own instances of it. Representative trace (`seed=32`,
abridged to the actions):

```
phone starts a rest timer / wrist logs a set / phone starts a session /
wrist starts a Free workout / phone starts a rest timer / link drops /
time advances 9s / phone logs a set / link drops x3 / phone starts a rest timer /
wrist starts a Free workout / time advances 8s / phone finishes / phone logs a set /
link drops / wrist discards / wrist logs a set / phone starts a rest timer /
wrist starts a rest timer x2
check: DIVERGED — session 1: phone abandoned vs wrist completed
```

### Residue R-163-2 — the phone kill exposes `absorbing` (2-3 occurrences)

`absorbing` (a finished workout re-reported active, plan 146's check 2) does not appear
in the pre-change baseline at all and appears only with kills in the space. The
contract print aggregates classes, so the individual seeds were not isolated in this
run — the follow-up needs a per-seed class dump.

### The ratchet conflict (why Phase 2 cannot close)

D-16306b allows the total to move only through a NEW class's own measured line, and
forbids raising the standing 8 to absorb what the kills expose. Both classes here are
already in `knownClasses`, so the plan provides no mechanism to reach green from 14:
lowering the constant is impossible, raising it is forbidden, and fixing the divergence
is Phase-out-of-scope (D-16307: no production change). Phase 2 is marked **Blocked
(scope)** for the owner's decision — options in the plan's `## Open Items`.

## Verification status and tree state (important for the reviewer)

All the runs above executed against a compiling tree (18:47-18:54). At 18:57 a
concurrent run's in-flight edits to `lib/watch/sensors/watch_platform_workout.dart`
landed in this shared worktree and the tree no longer compiles
(`lib/watch/sensors/watch_platform_workout.dart:270:32: Method not found: 'forModality'`;
`gateway.sh lint` → 224 issues, of which every error is in that run's files —
`lib/watch/sensors/*`, `test/watch_sensor_recording_test.dart`,
`test/watch_routine_focus_start_test.dart`, `test/watch_snapshot_focus_wrist_test.dart` —
and none in the two files this plan touches).

Consequences, stated plainly:

- The full `gateway.sh test` suite **could not be run** at the end of this run: the
  compile error above fails every file that reaches `lib/watch/sensors`. Not a finding
  of this change; not something this run may fix (D-16307 and the standing rule).
- Lint is 224 vs the plan's 181 baseline. Baseline 181 - the 43 extra are the concurrent
  run's compile errors; the two files this plan touches contribute zero issues.
- The harness blast-radius files (`watch_convergence_harness_test.dart`,
  `watch_ended_session_not_current_test.dart`, `watch_replay_corpus_test.dart`) are
  therefore unverified in this run; `watch_convergence_random_test.dart` — the file that
  exercises the harness hardest (14 green, 1 red: the ratchet) — ran green except the
  ratchet assert while the tree still compiled.
- `test/watch_replay_corpus_test.dart` is expected to be red on S-15207 freshness once
  it can compile: the new `_options` entry changes every `seed-*` draw stream (D-16304),
  which is why Phase 4 regenerates the corpus.



| Sweep | Result |
| --- | --- |
| `PhoneKilled\b` over the tree | plan docs only (152's D-15210/S-15211, this plan); zero code hits |
| `watch_pair_harness\|PairAction\|kShippingActions` under `lib/` | zero files |
| `hive_workout_repository\|watch_pair_harness` under `lib/` | `lib/main.dart` only (the composition root; not `lib/state`, `lib/features`, `lib/widgets`, `lib/core`) |
| `kShippingActions` | contains `WristKilled` and `PhoneKilledAndRelaunched` |

## Not done in this run

Phases 3, 4 and 5 (scripted kill semantics, the corpus `trace-kills` step/source and
regeneration, the 2000-seed soak, the docs delta) are untouched. Phase 4's regeneration
is a write under `--dart-define=REPLAY_CORPUS_WRITE=true` which this run must not
execute; the plan's Phase 2 decision gates Phases 4-5 anyway (the corpus must be
re-recorded with the FINAL option space).

---

# Resumed run — 2026-11-14, plan 169's one-clock baseline (`ef9d7636`, `dfbf2ab7` beneath)

The parked `.work/plan163-wip.patch` was re-applied BY HAND (it no longer applies: plan
169 changed the same constructor and warm-up). Tree at `ef9d7636`, which compiles and
lints at the 181 baseline (the compile errors the earlier run recorded are gone).

## Re-application delta against the parked patch (all in the two predicted files)

| Hunk | Why it differs |
| --- | --- |
| `build()` now pins the phone: `_phoneClock = _gridClock(clock)` before `_launchPhone()` | plan 169 D-16905/D-16907: the phone's own stamps ride the injected grid clock, and the relaunch must reuse the SAME pin |
| `WorkoutState(repository, clock: _phoneClock)` inside `_launchPhone()` | ditto; the patch had `WorkoutState(repository)` |
| `_launchPhone()` ends with `checkForInProgressSession()` + `loadHistoricalSession(dangling.id)` | F-163-1 (HomeScreen's first-frame restore, A-145-19) |
| seam test gained the S-16301 kill-space pass over seeds 1..5 | the original attempt |

## Red → green

| Check | Red | Green |
| --- | --- | --- |
| `test test/watch_convergence_random_test.dart --plain-name "the allowed-actions seam"` | RED at `test/watch_convergence_random_test.dart:98:7`, `Expected: non-empty / Actual: <Set:{}>` — the seeds drew no phone kill | `+1: All tests passed!` after `_ActionOption(PhoneKilledAndRelaunched, 3, …)` |
| `test … --plain-name "S-14502"` | (pre-existing green) | `+1: All tests passed!` |
| `test test/watch_convergence_harness_test.dart` (blast radius) | — | `+36: All tests passed!` |
| `lint` | — | `181 issues found` = the plan's baseline; both touched files contribute zero issues (`grep` of the lint log: no match) |

## Phase 2 re-measurement — two 200-seed sweeps

| Run | Contract line | by class | Verdict |
| --- | --- | --- | --- |
| 1 (`.work/gateway/test-20261114-202419-84793.log`) | 189 converge; 8 shipping `[46, 60, 76, 105, 113, 127, 145, 153]`; 1 heal-only `[70]`; 2 re-assert-only `[4, 152]` | `{status: 6, entries: 1, heal: 1, absorbing: 3}` | RED: `Expected: <= 6, Actual: 8` (`test/watch_convergence_random_test.dart:320:7`) |
| 2 (`.work/gateway/test-20261114-202438-84906.log`) | 191 converge; 7 shipping `[46, 60, 105, 113, 127, 145, 153]`; 1 heal-only `[70]`; 1 re-assert-only `[152]` | `{status: 4, entries: 1, heal: 1, absorbing: 3}` | RED: `Expected: <= 6, Actual: 7` |

`kSeedCount` 200, `shippingRatchet = (200 * 6 / 200).ceil() = 6` (A-169-04). Per-seed
kinds, run 1: 46 status, 60 entries, 70 heal, 76 status, 105 status, 113 status,
127 absorbing, 145 status, 153 absorbing. Kill coverage is real: 11 traces in run 1
contain "phone app killed and relaunched".

**No new class.** `status`, `entries`, `absorbing` and `heal` are all already in
`knownClasses`, so the `unknown` expect was green in both runs and item 4 (classify) is
satisfied. The total is nevertheless above the standing 6, and D-16306b/D-16307 give no
mechanism to close it from here: the constant may not rise, and no production fix is in
scope. Phase 2 is **Blocked (scope)**.

## Largest class (`status`) — shrunk traces

`ConvergenceRun.runSeed(seed)` + `Shrinker.shrink`, run from a temporary probe test that
was removed afterwards (`TEMP-PROBE-163`; the file ends at its original F-7 as before).

| Seed | Replay result | Shrunk trace |
| --- | --- | --- |
| 46 | no mismatch on replay | — |
| 76 | no mismatch on replay | — |
| 105 | no mismatch on replay | — |
| 152 | no mismatch on replay | — |
| 113 | `session 1: phone abandoned vs wrist completed` | 5 actions: phone starts a session / link drops / wrist finishes / time advances 73s / phone discards |
| 145 | `session 2: phone completed vs wrist abandoned` | 7 actions: phone starts a session / a live frame from the phone refused / phone finishes / link drops / time advances 22s / wrist discards / time advances 78s |

**Finding (the sweep is not replay-closed).** Seeds 46, 76, 105 and 152 diverge in the
seed sweep but not when their drawn actions are replayed, because the sweep's draws
depend on harness state that `replayActions` reconstructs differently. A
`replayActions`-only shrinker therefore under-reports this class; seed 113 (an abandoned
vs completed end across a dropped link) and seed 145 (a refused live frame before the
phone's own end) are what it can see. Recorded in the plan's Open Items.

## Mutation proofs

| # | Mutation (harness line) | Result | Restored |
| --- | --- | --- | --- |
| A | `WorkoutState(repository, clock: _phoneClock)` → `WorkoutState(repository)` | `--plain-name "S-14502"` stayed GREEN — that test does not pin the clock; the pin is exercised by the sweep's `status` counts, not by a unit test | yes, exact line |
| B | the two restore lines → `if (dangling == null) await phone.checkForInProgressSession();` | 200-seed sweep went from 8/7 shipping divergers to **34** `[1, 5, 9, 22, 27, 33, 43, 46, 48, 51, 58, 60, 63, 68, 71, 96, 99, 102, 103, 105, 113, 117, 118, 124, 132, 137, 139, 145, 156, 167, 169, 183, 184, 193]`, `{status: 42, absorbing: 3, entries: 1, heal: 1}` (`.work/gateway/test-20261114-202730-85530.log`) | yes, exact lines; seam test re-run green (`+1`) |

Mutation A is an honest negative: the read/write clock pin is a fidelity property, and
the guard that measures it is the sweep, not a single seed. Mutation B is the positive
proof that F-163-1's restore is load-bearing.

## Tree state at the end of this run

`git-status`: modified `test/helpers/watch_pair_harness.dart`,
`test/watch_convergence_random_test.dart`,
`docs/plans/…-163-…-plan.md`; untracked `…-163-…-plan.evidence.md` (this file) and
`test/stats_gallery_render_test.dart` (not this run's). No file under `lib/`,
`watch/`, `ios/` or `.claude/`. Fabricated files: none; the probe test was removed.

Not run this run, and why: the 2000-seed soak and the docs delta (Phases 4-5 not started),
`swift-test` (no `.swift` file changed).

Full suite run once, at the end: `.github/copilot/scripts/macos/gateway.sh test` →
**`+7625 ~4 -2`**, `.work/gateway/test-20261114-203052-86555.log`. Both failures are the
ones this plan predicts, and 7625 + 2 equals the plan's +7627 baseline, so nothing else
moved:

| Failing test | Why |
| --- | --- |
| `S-14509 every random seed converges, or diverges inside a class the plan names` (`test/watch_convergence_random_test.dart:320`) | `Expected: a value less than or equal to <6> / Actual: <8>` — the unraised ratchet |
| `S-15207 the corpus is fresh: every file matches a fresh recording` (`test/watch_replay_corpus_test.dart`) | the staleness Phase 4's `REPLAY_CORPUS_WRITE=true` regeneration fixes; every other corpus test (S-15202, S-15204) is green |

Also green: `test/watch_convergence_harness_test.dart` `+36`, `test/ui_standards_contract_test.dart`
`+41`, `test/docs_indexing_contract_test.dart` `+13`, `lint` `181 issues` (= baseline, zero in
the touched files), and the project invariant `import .*hive_workout_repository` under
`lib/state|features|widgets|core` — no hits (`lib/main.dart` is the composition root).
Residue sweeps: `PhoneKilled\b` in `*.dart` — no matches (plan 152's superseded name
never reached code); `kShippingActions` carries both `WristKilled` and
`PhoneKilledAndRelaunched`.

## Governor action needed — corpus regeneration

```
.github/copilot/scripts/macos/gateway.sh test test/watch_replay_corpus_test.dart --dart-define=REPLAY_CORPUS_WRITE=true
.github/copilot/scripts/macos/gateway.sh swift-test
```

`REPLAY_CORPUS_WRITE=true` is forbidden in this mode. That note was written when the
phone kill sat inside `kShippingActions`; the 163c split (below) put the standing space
back to its pre-plan 15 members, so the `seed-*` recordings are fresh again and only
`trace-kills.json` is new — confirmed by S-15207 naming exactly one stale file.

---

# Run 2026-11-14, brief `163c` — Phases 2-5 (@developer)

The governor's brief resolved Phase 2's ratchet conflict and asked for Phases 3-5.

## The decision (P-9): split the space, raise nothing

| Space | Members | Ratchet / 200 seeds | Measured |
| --- | --- | --- | --- |
| `kShippingActions` | the pre-plan-163 15 | 6 (unchanged) | 4 — `[94, 123, 145, 167]`, `{status: 3, entries: 2, heal: 1}` |
| `kShippingActionsWithPhoneKill` | those 15 + `PhoneKilledAndRelaunched` | 10 (new) | 8 then 7 |
| `kEveryAction` | `kShippingActionsWithPhoneKill` + `PhoneReassertsLive` | — | the second chance for both sweeps |

Because the standing space is byte-identical to its pre-plan self, the seeded draw stream
is the pre-plan stream: `S-14502` (same seed twice) and the corpus `seed-*` recordings
stay valid without regeneration.

## Phase 3 — scripted kill tests (`test/watch_convergence_kill_test.dart`, new)

| Test | S-id | First run | Final |
| --- | --- | --- | --- |
| `S-16302 the owed end survives a phone kill` | S-16302 | green | green |
| `S-16303 the first ending survives a phone kill` | S-16303 | green | green |
| `S-16304 staged inbox rows survive the phone's death` | S-16304 | RED | green |
| `S-16305 a kill on an idle pair is a no-op` | S-16305 | green | green |
| `S-16306 a phone kill while the link is down` | S-16306 | green | green |
| `S-16307 double kill is idempotent` | S-16307 | green | green |
| `S-16302 the relaunched phone's stamps stay on the pair clock` | S-16302/P-6 | green | green |

- RED run: `.work/gateway/test-20261114-204632-94818.log` — `+6 -1`.
- GREEN run: `.work/gateway/test-20261114-204714-95113.log` — `+7: All tests passed!`.
- S-16304's first assertion (`stagedAfterHeal` empty) was wrong, not the code: inbox rows
  are put-if-absent and `clearWatchInboxApplied` only stamps `applied_at_ms`, so applied
  rows remain as tombstones. The test now asserts no row with `appliedAtMs == null`,
  `getWatchSessionIdsWithUnappliedEnd()` excludes the session, and its `endedAtMs` is
  non-null. `TrainingSession` has no `status` field / `TrainingSessionStatus` enum, so the
  terminal state is read from `endedAtMs`.

### Mutation proofs (this file cannot compile at HEAD, so no `prove-red`)

| # | Mutation | Result | Restored |
| --- | --- | --- | --- |
| A | `WorkoutState(repository, clock: _phoneClock)` → `WorkoutState(repository)` in `relaunchPhone()` | the pair-clock guard goes RED: `Expected: a value less than or equal to <100> / Actual: <406052699>` — 406 s of skew (`.work/gateway/test-20261114-204731-95242.log`) | exact line; re-run `+7` |
| B | the `checkForInProgressSession()`/`loadHistoricalSession(dangling.id)` restore commented out | S-16304 and the clock guard go RED (`Expected: not null / Actual: <null>`), S-16304's trace reading `check: DIVERGED` (`.work/gateway/test-20261114-204742-95374.log`) | exact lines; re-run `+7` |
| C | the S-16310 floor `greaterThan(kSeedCount ~/ 4)` → `greaterThan(kSeedCount * 2)` (the "never kills the phone" shape) | S-16310 goes RED: `Expected: a value greater than <400> / Actual: <95>` with the reason `the phone-kill sweep must actually kill the phone` (`.work/gateway/test-20261114-210544-2593.log`) | exact line; re-run `+8` (`.work/gateway/test-20261114-210605-2718.log`) |

Mutation C is the proof that the kill-trace floor is load-bearing: without it a sweep whose
option silently stopped being drawn would still pass on its diverger count alone.

A dead `expect(killedTraces, isNonNegative, ...)` that duplicated the floor (a count is
never negative, so it could not fail) was removed in the same pass; the floor keeps the
guard and the printed line keeps the measurement.

## Phase 4 — the corpus source

`_Step.run` gained `case 'phoneKill'`; `trace-kills` (steps `wristStart, drop, wristLog,
phoneKill, rise, wristFinish, wristKill, rise`, tags `['kill', 'phone-kill']`) joined
`kCorpusSources`; `'phone-kill'` joined `kRunOnlyTags` and the S-15204 floor list.

Red exactly as predicted, and only those three (`.work/gateway/test-20261114-205432-96174.log`):

| Test | Failure |
| --- | --- |
| S-15202 | `the corpus is missing trace-kills.json — regenerate with flutter test --dart-define=REPLAY_CORPUS_WRITE=true` |
| S-15204 | the manifest lists 16 sources, the declaration has 17 |
| S-15207 | `stale recordings: ['trace-kills.json']` — no `seed-*` file moved |

## Phase 5 — soak, docs, residue

- Soak, `--dart-define=CONVERGENCE_SEEDS=2000`, 5m43s:
  `.work/gateway/test-20261114-204832-95696.log` → `+16: All tests passed!`.
  - standing sweep: 1933 converge, 31 shipping divergers (ratchet 60), 13 heal-only, 23 synthetic-only.
  - kill sweep: 1894 converge, 76 shipping divergers (ratchet 100), 11 heal-only, 19 synthetic-only, 1086 traces carrying a kill, by class `{status: 53, entries: 5, heal: 13, absorbing: 36}`.
- Both constants therefore have ≥ 3/200 of headroom at 2000 seeds and can only go down.
- 200-seed kill sweep, three runs: `.work/gateway/test-20261114-204257-94121.log` (8, `[46, 60, 76, 105, 113, 127, 145, 153]`, `{status: 5, entries: 1, heal: 1, absorbing: 3}`, synthetic-only `[152]`), `.work/gateway/test-20261114-204334-94265.log` (7, same minus 76, `{status: 4, ...}`) and `.work/gateway/test-20261114-210605-2718.log` (8 again, same list as run 1). The diverger list is stable; the flake is in the two side buckets — seed 76 moves in and out of the diverger list, and seed 4 joins `syntheticOnly` in run 3 (`.work/gateway/test-20261114-210544-2593.log`, `[4, 152]`). The ratchet bounds the diverger total only, deliberately.
- Docs: `docs/state_management/watch_surface_transport.md`, "Convergence testing" — the
  "a phone app killed and relaunched is not modelled either" paragraph is replaced by two
  naming both kill actions, D-16302's keep/lose list, the `_gridClock` pin, the six
  scripted tests, the parametric option list, the separate ratchet and the `trace-kills` /
  `phone-kill` corpus coverage.
- Residue: `PhoneKilled\b` — no match in code; `kShippingActions` carries `WristKilled` and
  the new space carries `PhoneKilledAndRelaunched`.
- Invariant: `import .*hive_workout_repository` under `lib/` — only `lib/main.dart`.

## Red → green, whole change

| Check | Result |
| --- | --- |
| `gateway.sh lint` | `181 issues` = baseline, zero in the files touched (`.work/gateway/lint-20261114-210040-1549.log`); the one issue introduced (an unused import in the kill test) was removed |
| `gateway.sh test test/ui_standards_contract_test.dart` | `+41: All tests passed!` |
| `gateway.sh test test/docs_indexing_contract_test.dart` | `+13: All tests passed!` |
| `gateway.sh test test/watch_convergence_kill_test.dart` | `+7: All tests passed!` |
| `gateway.sh test test/watch_convergence_random_test.dart --dart-define=CONVERGENCE_SEEDS=2000` | `+16: All tests passed!` |
| `gateway.sh test` (full) | `+7632 ~4 -3` twice — `.work/gateway/test-20261114-205432-96174.log` and the final `.work/gateway/test-20261114-210625-2839.log` (5m31s). `7632 + 3` = the `+7627` baseline plus this plan's 8 new tests; the three reds are exactly the corpus tests above |

## Tree state

`git-diff --stat`: `test/helpers/watch_pair_harness.dart` (154), `test/watch_convergence_random_test.dart`
(190), `test/watch_replay_corpus_test.dart` (25), `docs/state_management/watch_surface_transport.md`
(32), `…-163-…-plan.md`; untracked `test/watch_convergence_kill_test.dart` and this evidence
file. Nothing under `lib/`, `watch/` or `ios/` (D-16307). No scratch or probe files created
in this run.

