# Evidence — the rest ping: Wear mirror, Settings copy, the rule and the docs (22b)

Companion to `2026-10-08-22b-rest-ping-wear-settings-docs-plan.md`. Implementers write the suite output and
the red→green tables here; the plan keeps one line per item and Assumption Log entries of at most 3 lines.
Suite output, not claims: paste the pass/fail counts.

This PR is plan 22's Phase 3, moved here whole by the governor's scope check on 2026-10-08. The phone and
Apple Watch halves of the same scenarios stay in
`docs/plans/2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.evidence.md`; this
file records the Dart, Settings, rule and docs halves only.

## Baselines (recorded by the governor before the first phase)

| Check | Baseline |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` (flutter, full) | 4152 passing, ~1 failing (pre-existing) |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 359 passing, 0 failing |
| `.github/copilot/scripts/macos/gateway.sh lint` (`flutter analyze`) | 196 issues, 0 errors (pre-existing infos) |

Record the same three numbers at the end of the phase and state the delta. A phase that moves one of them
without saying why is a finding. `test/docs_indexing_contract_test.dart` hard-fails above 64 KiB per doc and
warns above 80% (≈51.2 KiB).

## Red → green

The red column is the failure observed at the base commit for that scenario; the green column is the passing
run after the phase. Red for the *new* rule type is the first run of `test/watch_rest_ping_test.dart` at the
base commit: with `WatchRestPing` absent the file does not compile — record that run's output, not a later
one. S-226's red is `WatchHaptics` having no `playRestPing()` (the stub cannot conform and the assertions do
not compile).

| Scenario | Phase | Red (observed) | Green (suite output) | Test file · test name |
|---|---|---|---|---|
| S-241 the table, one-second polls (Dart) | 1 | not compiling at the base commit: `watch_rest_ping_test.dart:27:8: Error: Error when reading 'lib/watch/logging/watch_rest_ping.dart': No such file or directory`, then `Method not found: 'WatchRestPing'` ×5 and `The getter 'restPingSeconds' isn't defined for the type 'WatchUnitPreferences'` — re-run at HEAD by `prove-red` (.work/gateway/test-20261008-164026-23770.log) | 13/13 `watch_rest_ping_test.dart`; 76/76 the brief's targeted suite; full suite 4179 passing, 0 failing, 1 skipped | `test/watch_rest_ping_test.dart` · `the table, walked by the Dart rule S-241 an interval of 30 polled every second from 0 to 100 taps at 30, 60 and 90 and nowhere else` |
| S-242 interval 0 / Off via `fromSettings` (Dart) | 1 | same compile red; guard witnessed by mutation M3 (`fromSettings` → `restPingSeconds: 0`): `Expected: <45> Actual: <0>` in this row, "the wrist carries the interval the phone holds" | 13/13 | `test/watch_rest_ping_test.dart` · `S-242 Off and unknown S-242 an interval of 0 polled every second to 600 taps nowhere`, `… S-242 the interval reaches the rule from Settings, and Off is its never-set default` |
| S-243 gap catch-up fires once (Dart) | 1 | same compile red; mutation M1 dropped the novelty clause: `Expected: [200, 240] Actual: [200, 201, 240]` | 13/13 | `test/watch_rest_ping_test.dart` · `S-243 a gap taps once S-243 an interval of 60 polled at 0, 59, 200, 201 and 240 taps at 200 and 240, not once per skipped multiple` |
| S-244 interval change mid-rest (Dart) | 1 | same compile red; mutation M1: `Expected: [60, 90] Actual: [60, 70, 70, 90]` and `Expected: [60] Actual: [60, 61, … 70]` | 13/13 | `test/watch_rest_ping_test.dart` · `S-244 the interval changes mid-rest S-244 the table row taps only the boundaries still to come`, `… S-244 lowering the interval past a boundary already pinged does not ping it again` |
| S-245 a rest ends, the next starts clean (Dart) | 1 | same compile red; mutation M2 removed the per-row reset: `Expected: [30] Actual: []`, "a new rest row starts from nothing, not from rest A's last boundary" | 13/13 | `test/watch_rest_ping_test.dart` · `S-245 a rest ends, the next starts clean S-245 the next rest row taps at its own first boundary, and a closed rest is never evaluated` |
| S-221 same second pinged once (Dart) | 1 | same compile red; mutation M1: `Expected: [30] Actual: [30, 30, 30]` | 13/13 | `test/watch_rest_ping_test.dart` · `S-221 the same second polled three times S-221 an interval of 30 with the same second polled three times taps once` |
| S-222 interval lands mid-rest (Dart) | 1 | same compile red; mutation M1 on both rows: `Expected: [30, 60, 90]` / `Expected: [36, 60, 90]` against one tap per poll | 13/13 | `test/watch_rest_ping_test.dart` · `S-222 the interval arrives mid-rest S-222 arriving at elapsed 20, the formula governs: 30, 60 and 90`, `… S-222 arriving at elapsed 35 taps once on the next poll, then the multiples after it` |
| S-223 large interval (180) (Dart) | 1 | same compile red; mutation M1: `Expected: [180] Actual: [180, 181, … 200]` | 13/13 | `test/watch_rest_ping_test.dart` · `S-223 a large interval S-223 an interval of 180 over 0 to 200 taps once, at 180` |
| S-224 a closed rest is never evaluated (Dart) | 1 | same compile red (the rule cannot be constructed at base), passing on the first green run | 13/13 | `test/watch_rest_ping_test.dart` · `S-224 a closed rest is never evaluated S-224 a rest closed before its next boundary taps nothing afterwards` |
| S-226 the Dart mirror's ping is its own tap | 1 | the edited stub and the new assertions do not load at base: `watch_logging_surfaces_test.dart:883:43: Error: No named parameter with the name 'restPingSeconds'`, `:893:13: … 'haptics'` (prove-red run above) | 76/76 targeted (S-226 included); full suite 4179 passing | `test/watch_logging_surfaces_test.dart` · `The surface the user taps S-226 the rest surface pings through its own entry point, never a milestone` |
| S-249 the Settings copy names the devices | 1 | assertion failure at the base commit, `prove-red HEAD test test/settings_sounds_test.dart`: `Expected: exactly one matching candidate · Actual: _TextWidgetFinder:<Found 0 widgets with text "Periodic reminder during rest, on phone and watch">` at `test/settings_sounds_test.dart:101`, "the test description was: S-249 the Settings copy names the devices each row reaches"; gateway verdict "RED AT HEAD (exit 1)" (.work/gateway/ log 20261008-1650*, brief's prove-red) | 84/84 the part-B targeted suite, S-249 included; 1/1 on its own (`--plain-name S-249`) | `test/settings_sounds_test.dart` · `SOUNDS & ALERTS section S-249 the Settings copy names the devices each row reaches` |
| S-250 the rule still bites | 1 | negative guard, so `prove-red` on its own file proves nothing (the scanner is defined in it): proved by mutation instead — M7 flags a ping spelling, M8 blinds the scanner to `restSeconds`; both fail the assertions this scenario adds | 10/10 `rest_is_count_up_contract_test.dart`, S-250 included | `test/rest_is_count_up_contract_test.dart` · `restIsCountUpContract S-250 the rest ping is allowed and the rule still bites` |

S-250 is a *negative* guard: its red is the reworded prose plus the new identifiers being *absent* from the
allowance, so the scanner flags `const restPingSeconds = 30;` — a later run in which the same red case
(countdown, stored rest length, planned rest) still fails is required evidence, not a substitute.

## Phase evidence

### Phase 1 — Wear mirror, Settings copy, rule and docs (@developer)

Part A of this phase (items 1.1–1.4, the Dart mirror) ran on 2026-10-08; part B (1.5–1.8, the Settings copy,
the docs and the scanner) ran in a second developer run the same day and is recorded under "Part B — items
1.5–1.8" below, so the bullets in *this* subsection cover items 1–4 only.

- `.github/copilot/scripts/macos/gateway.sh lint` (baseline 196 issues / 0 errors): **196 issues, 0 errors**
  — no delta; none of the 196 names a file this part touched
  (`.work/gateway/lint-20261008-164210-24968.log`, grep for the five paths: no match).
- `.github/copilot/scripts/macos/gateway.sh test test/watch_rest_ping_test.dart
  test/watch_rest_surface_test.dart test/watch_logging_surfaces_test.dart
  test/watch_logging_stepping_test.dart` (the brief's list minus the two part-B files
  `test/settings_sounds_test.dart` and `test/docs_indexing_contract_test.dart`): **76 passed, 0 failed**;
  `test/rest_is_count_up_contract_test.dart` added to the same run (it scans `lib/watch`): **still green**.
- `.github/copilot/scripts/macos/gateway.sh test` (full suite, 900 s): **4179 passing, 0 failing, 1 skipped**
  (`~1`), "All tests passed!" — against the 4152-passing baseline, +27 (13 rule tests, 1 S-226 test, and the
  rest of the delta is other phases' committed work, not this one).
- `.github/copilot/scripts/macos/gateway.sh swift-test` (expected unchanged; no Swift in this PR): **not run
  — no `.swift` file changed in this part**, per the run brief ("run the full `swift-test` once at the end,
  and only if this run changed a `.swift` file"). Nothing on the Swift side reads the Dart rule.
- `docs/state_management/watch_surface.md` size before → after (band: 51.2 KB warn, 64 KiB hard fail):
  **not touched in part A** — item 7 is part B. The file still needs its remove-before-adding pass there.
- Residue sweep, part A (the `lib/watch` half): `grep -n` for `restSeconds|restDuration|plannedRest|restLength|restRemaining` under `lib/watch` → **no matches**, so no reader of a rest *length* appeared; the
  doc-side sweep in item 8 is still open.
- Diff versus Predicted Files: `git-status` lists exactly the six files items 1–4 predict —
  `lib/watch/logging/watch_rest_ping.dart` (new), `test/watch_rest_ping_test.dart` (new),
  `lib/watch/logging/watch_logging_screen.dart`, `lib/watch/logging/watch_metric_stepping.dart`,
  `lib/watch/logging/watch_rest_screen.dart`, `test/watch_logging_surfaces_test.dart`. `git-diff --stat`:
  4 files changed, 113 insertions(+), 3 deletions(-) (the two new files are untracked). **No out-of-bounds
  file; no predicted file untouched.**
- Assumption Log entries added: three (see the plan): the record id is read through the screen's own
  `state.timerFor(WatchTimerKind.rest)`, the new import in `watch_rest_screen.dart` is required by that read,
  and this run covers items 1–4 only.

#### Guards proved by mutation

The new rule and the new protocol member do not exist at the base commit, so `prove-red` can only reach them
as a compile error (the run above; the gateway's own verdict: "RED AT HEAD (exit 1). It proves the guard only
if an assertion fails for the reason the test guards; a compile or load error means the test could not run
there (use a mutation instead)"). Each guard below was therefore proved by mutating the implementation,
observing the named test fail for the reason it guards, restoring the exact line and re-running green.

| Mutation | Original line | Test red | Observed |
|---|---|---|---|
| M1 (S-241, S-243, S-244, S-221, S-222, S-223) | `if (boundary <= 0 \|\| boundary <= _lastPinged) return false;` → `if (boundary <= 0) return false;` | 10 of 13 | `+2 -10: Some tests failed`; `Expected: [30, 60, 90] Actual: [30, 31, …]`, `Expected: [200, 240] Actual: [200, 201, 240]`, `Expected: [60] Actual: [60, 61, … 70]`, `Expected: [30] Actual: [30, 30, 30]`, `Expected: [180] Actual: [180, 181, … 200]` |
| M2 (S-245) | the `_lastPinged = 0;` line inside `if (_pingingRestId != restId)` → removed | 1 of 13 | `+12 -1`; `Expected: [30] Actual: []` — "a new rest row starts from nothing, not from rest A's last boundary" |
| M3 (S-242 `fromSettings`) | `restPingSeconds: settings.restPingInterval,` → `restPingSeconds: 0,` | 1 of 13 | `+12 -1`; `Expected: <45> Actual: <0>` — "the wrist carries the interval the phone holds"; the surfaces file stayed green there, because S-226 builds its `WatchUnitPreferences` explicitly |
| M4 (S-226, the count comes from the rule) | `if (owed) widget.haptics.playRestPing();` → the same line plus an unconditional `widget.haptics.playRestPing();` | S-226 | `Expected: <3> Actual: <93>` — "one tap at each multiple of the interval" |
| M5 (S-226, never a milestone) | the ping line → `widget.haptics.play(WatchTimerMilestone(kind: WatchTimerKind.rest, at: DateTime.now()));` before it | S-226 | `Expected: empty Actual: [WatchTimerMilestone(rest at …) ×3]` — "the ping is its own entry point, not a milestone" |
| M6 (item 6, the docs prose guard) | `docs/watch_session_sync.md:602` `  The wrist taps at each multiple of the interval the phone sent in` → `  A rest countdown ticks on the wrist: the interval the phone sent in` | S-166 whole-tree scan | `Expected: empty Actual: ['docs/watch_session_sync.md:604 counts a rest down: a rest is a count-up, never a remaining time']` — `+0 -1`, so the scan reads the lines item 6 added, and they are safe only because each names a denial |
| M7 (S-250, the allowance stays narrow) | `_restLengthSpelling` first alternative `r'rest_?seconds\|…'` → `r'rest_?ping\|rest_?seconds\|…'` | S-250 | `Expected: empty Actual: ['lib/watch/logging/example.dart:1 names 'restPing': a stored rest length is a preset rest length']` — "the rest ping is the one allowed cue, never a rest length"; a scanner that flags a ping identifier fails here |
| M8 (S-250, the rule still bites) | `_restLengthSpelling` first alternative → `r'rest_?seconds_never\|…'` (blinds the scanner to `restSeconds`) | S-250 | `Expected: an object with length of <1> Actual: []` — "a stored rest length is still the preset value the rule forbids"; the allowance did not widen |

After M1–M5 every original line was restored (M4's and M5's mutation was the ping line and, for M5, the
temporary `import 'watch_timer_haptics.dart';`, both removed) and the suite re-run: **76 passed, 0 failed**;
`git-status` shows the same six files and no extra import. M6–M8 were restored the same way (the docs line
character-for-character, the regex alternative character-for-character) and re-run green: **10 passed, 0
failed** for the contract file and **84 passed, 0 failed** for the part-B targeted suite.

#### Part B — items 1.5–1.8 (@developer, second run)

- `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/settings_sounds_test.dart` — **RED AT
  HEAD (exit 1)**, an assertion failure naming the new subtitle (the row above), so S-249 is red at the base
  commit for the reason it guards.
- `.github/copilot/scripts/macos/gateway.sh test test/settings_sounds_test.dart
  test/rest_is_count_up_contract_test.dart test/docs_indexing_contract_test.dart
  test/watch_rest_ping_test.dart test/watch_logging_surfaces_test.dart` (the brief's part-B list) — **84
  passed, 0 failed** ("All tests passed!", exit 0). The first of those runs was red: S-249's tap missed the
  Rest Ping row (below the default 600 px fold), fixed by the file's own `setSurfaceSize` pattern.
- `.github/copilot/scripts/macos/gateway.sh lint` (baseline 196 issues / 0 errors) — **196 issues, 0 errors**
  (`196 issues found.`), no delta. The three entries naming `lib/features/settings/settings_screen.dart` are
  pre-existing (`:190`, `:200`, `:310`); nothing names a line this part touched, and no other touched file
  appears (.work/gateway/lint-20261008-165424-36467.log).
- `.github/copilot/scripts/macos/gateway.sh swift-test` (the brief's list; no `.swift` file changed here) —
  **376 passed, 0 failed** (`Executed 376 tests, with 0 failures`), matching plan 22 Phase 2's committed 376;
  the 359 baseline predates it.
- Full `.github/copilot/scripts/macos/gateway.sh test` — **not run: the governor runs it**, per the brief.
- `docs/state_management/watch_surface.md` size before → after (band: 52,429 B ≈ 51.2 KiB warn,
  64 KiB hard fail): **50,892 → 50,843 B** (−49 B), measured by a `test/zz_doc_size_test.dart` probe
  (`File(...).lengthSync()`) that was deleted with `gateway.sh delete-scratch` before lint ran. The brief's
  "ceiling 51 200" is the 51.2 KiB band written in bytes; the contract test's own threshold is
  `round(65536 * 0.80)` = 52,429 B, and `test/docs_indexing_contract_test.dart` is green in the run above.
  What was removed: the sentence "Two smaller gaps: the wrist labels load in kilograms whatever the phone's
  unit preference says, and a countdown the phone wrote stops when a Sync arrives while one the wrist started
  keeps running, because the phone's answer carries no timers (D-26, D-80; on the Dart twin,
  `test/watch_logging_timers_test.dart`'s `S-79 …`)" — both facts are stated with their own citations in
  `docs/watch_session_sync.md` (the "wrist labels load in kilograms" bullet and the "A rest is device-local,
  and it has no length" bullet, which cites the same S-79 test), so nothing current was lost and the
  pointer to the detail doc stays. What was added: the 4-line ping paragraph (`restPingSeconds`, one setting,
  silent) and `lib/core/utils/watch_reference_sync.dart` on the scope line.
- Residue sweep — `grep` for `restSeconds|rest seconds|plannedDurationMs` under `lib/watch`: every hit is a
  round/hold timer field or the wire's `kind != 'rest'` refusal, so **no wrist reader of a rest *length***
  exists (part A's sweep repeated on the part-B tree). `grep` for `no rest alarm anywhere` across `docs/`,
  `lib/`, `test/` and `watch/`: the four item-6 documents and the scanner now say "no end-of-rest alarm" or
  name the allowance; what still quotes the retired wording is history (`docs/plans/**`, including 18b's
  review and plan 22's plan) plus one live file outside this brief's scope —
  `watch/watchos/Tests/WatchSessionEngineTests/WatchRestIsCountUpTests.swift:22`, the `rule` string a failing
  scan repeats, which still reads "no rest alarm anywhere, on any device" and claims to be the wording of
  `docs/global_conventions.md`. Reported, not fixed (item 6 names four docs; the brief calls the sweep
  report-only). See the plan's Assumption Log.
- Diff versus Predicted Files, part B: `git-diff --stat` lists exactly the eight files items 5–8 predict —
  `lib/features/settings/settings_screen.dart` (4 lines), `test/settings_sounds_test.dart` (+43),
  `docs/global_conventions.md` (2), `docs/rest_tracking.md` (8), `docs/theme_and_settings.md` (2),
  `docs/watch_session_sync.md` (+4), `docs/state_management/watch_surface.md` (15),
  `test/rest_is_count_up_contract_test.dart` (+61), plus `docs/plans/2026-10-08-18-watch-qa-index.md` (+2,
  the two rows). Each edit is the size it should be; part A's six files are untouched by this run. **No
  out-of-bounds file; no predicted file untouched.**
- Project invariant: `grep` for `import .*hive_workout_repository` under `lib/state`, `lib/features`,
  `lib/widgets`, `lib/core` — **no matches**.
- Assumption Log entries added: four (see the plan): `swift-test` run anyway, S-249's surface size, the
  index's two rows, and the Swift residue above.

## Fix round 1 — review findings F1, F2 (base 06e3fe4; F3 deliberately left)

Both fixes are wording/hygiene only; F3 (the Wear client is unbuilt) is out of scope by the brief.

- **F1 — the Swift `rule` message now quotes the current row.** `WatchRestIsCountUpTests.swift`'s
  `private let rule` (was lines 17–26) said "no rest alarm anywhere, on any device" while claiming to be the
  wording of `docs/global_conventions.md`. It now reads "There is no preset rest length, no rest countdown
  and no end-of-rest alarm on any device. The one allowed rest cue is the rest ping." — the row's own
  wording at `docs/global_conventions.md:17` — with the pointers
  (`docs/global_conventions.md, "Rest rule: rest is a count-up"`,
  `docs/plans/2026-10-08-18b-watch-rest-count-up-plan, D-160 and D-164`) and the closing "Do not add a
  preset rest length or a rest countdown; if you think the product needs one, ask the owner." unchanged.
  Diff: 3 lines → 4 inside the string literal; nothing else in the file.
  - Stale-wording sweep: `grep "alarm anywhere"` under `watch/watchos/Tests` — **one hit, the definition
    itself** (`WatchRestIsCountUpTests.swift:23` before the edit); no test asserts the old wording, so none
    needed updating. `grep "alarm anywhere|no rest alarm anywhere"` repo-wide: the remaining hits are
    history under `docs/plans/**` (18b's plan/review, 22's plan) plus the four item-6 documents and the
    scanner, which already say "no end-of-rest alarm" or name the allowance.
  - `swift-test` (full, the only Swift suite, run because a `.swift` file changed): **376 tests,
    0 failures** — the brief's 376 / 0, unchanged. Log `.work/gateway/swift-test-20261008-170317-46920.log`.
  - No new guard was added: the review's optional suggestion (add `watch/watchos/Tests` to the scanner roots,
    or assert the quotation equals the row verbatim) is outside this brief's F1 goal, which is the message
    wording. Logged as an Assumption Log entry.
- **F2 — S-249 restores the surface it resizes.** `test/settings_sounds_test.dart`, inside `S-249 the
  Settings copy names the devices each row reaches`, immediately after
  `await tester.binding.setSurfaceSize(const Size(800, 3000));`:
  `addTearDown(() => tester.binding.setSurfaceSize(null));` — the idiom 124 other call sites in `test/` use.
  One added line; the test's own body is untouched.
- `gateway test test/settings_sounds_test.dart test/rest_is_count_up_contract_test.dart`: **30 passed,
  0 failed** (`settings_sounds_test.dart` 20, `rest_is_count_up_contract_test.dart` 10) — `All tests passed!`
- `gateway lint`: **196 issues, 0 errors** — the plan's baseline, exit code 1 is the pre-existing info
  notices. Log `.work/gateway/lint-20261008-170330-47177.log`. Neither touched file contributes a notice.
- Full `gateway test` after both fixes (the standing end-of-run rule; F2 is cross-test hygiene, so the whole
  suite is the honest check): **4181 passed, 1 skipped, 0 failed** — `01:49 +4181 ~1: All tests passed!`,
  log `.work/gateway/test-20261008-170428-47462.log`.
- Project invariant: `grep` for `import .*hive_workout_repository` under `lib/state`, `lib/features`,
  `lib/widgets`, `lib/core` — **no matches**.
- Files changed by this round (2): `watch/watchos/Tests/WatchSessionEngineTests/WatchRestIsCountUpTests.swift`,
  `test/settings_sounds_test.dart`. No governor actions were needed.

