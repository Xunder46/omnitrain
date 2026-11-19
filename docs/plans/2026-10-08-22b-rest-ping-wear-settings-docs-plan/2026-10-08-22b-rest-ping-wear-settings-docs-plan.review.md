# Review — plan 22b (rest ping: Wear mirror, Settings wording, the rule and the docs)

Base commit: 06e3fe4. Reviewer: code-reviewer (Copilot CLI edition).

## Scope

Layers in scope: `lib/watch/logging/` (watch rest ping), `lib/features/settings/`, `docs/`, `test/`.
Layers skipped: `lib/data/models/`, `lib/data/repositories/`, `lib/state/` (no changes), `lib/widgets/`, `lib/core/`.

## Findings

F1 — 🟡 WARNING — `watch/watchos/Tests/WatchSessionEngineTests/WatchRestIsCountUpTests.swift:17-22` — the test's `private let rule` quotes the convention row as "no preset rest length, no rest countdown and no rest alarm anywhere, on any device" and tells the reader it "is the wording of `docs/global_conventions.md`". The changed row now reads "no preset rest length, no rest countdown and no end-of-rest alarm on any device" and adds the ping allowance, so both the quotation and the citation are false — and this string is what a future failing scan repeats to a developer. Fix: quote the row's new wording, or drop the quotation and point at the row. Guard: `watch/watchos/Tests` is not a scanner root (the roots in `test/rest_is_count_up_contract_test.dart` stop at `watch/watchos/Sources`), so no check can fail on it — add `watch/watchos/Tests` to the roots, or assert the quoted string equals the row read verbatim from `docs/global_conventions.md`. → @developer. Disclosed by the developer in the Assumption Log; not a blocker.

F2 — 💡 SUGGEST — `test/settings_sounds_test.dart:89` — S-249 sets an 800×3000 surface and never restores it, so every later widget test in the file inherits it (`:149` already leaks the same way; the new call is the added one). Fix: `addTearDown(() => tester.binding.setSurfaceSize(null))`. Guard: the teardown is the guard; the pre-existing leak at `:149` is out of this PR's scope. → @developer

F3 — 💡 SUGGEST — `lib/watch/logging/watch_rest_screen.dart:55` — the rule instance is built per `State`, so a remount mid-rest (leaving the rest surface and returning) discards `lastPinged` and replays the boundary already passed: one duplicate tap, unguarded. Fix: hold the rule where the resting row's identity lives (`WatchLoggingState`), or remember the last pinged `recordId`. Guard: a test that remounts the rest surface mid-rest and asserts `_RecordingHaptics.restPings` gains no second tap for the same boundary. The Swift half (`WatchRestPing` held by `WatchRestView`) behaves identically, so the two clients agree today and this is not a parity break. → @developer

## Diff vs Predicted Files

Conforms: 15 modified + 2 untracked files (`lib/watch/logging/watch_rest_ping.dart`, `test/watch_rest_ping_test.dart`) match the Predicted Files, plus the plan's own evidence/review/index updates. No out-of-bounds and no unfinished predicted file.

## Test run (mine)

`.github/copilot/scripts/macos/gateway.sh test test/watch_rest_ping_test.dart test/rest_is_count_up_contract_test.dart test/settings_sounds_test.dart test/watch_logging_surfaces_test.dart test/docs_indexing_contract_test.dart` → **84 passed, 0 failed** (`All tests passed!`), matching the handoff's 76 targeted claim plus the five-file set. The full suite was not re-run here per the brief (the governor's run is in flight); the handoff's pasted full-suite counts are 4179 passing / 0 failing / 1 skipped, and the governor reports lint 196/0 and swift 376/0.

Guard spot-check: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/settings_sounds_test.dart` → RED at base, `S-249 the Settings copy names the devices each row reaches` failing at `:104` with `Found 0 widgets with text "Periodic reminder during rest, on phone and watch"` — a real assertion failure, not a load error.

S-250 is a negative guard, so `prove-red` on its own file cannot prove it (the scanner is defined in that file and the new spellings were already allowed at base). The developer proved it by mutation instead — M7 (a `restPing` spelling is flagged) and M8 (blinding the scanner to `restSeconds` fails) — and disclosed that in the evidence file; the S-166 denial cases are intact and no test names were removed.

## 4a Acceptance criteria — 8/8 met

Item 1 pure-Dart `WatchRestPing`; 2 `WatchUnitPreferences.restPingSeconds` + `fromSettings`; 3 `WatchHaptics.playRestPing()` on `SystemWatchHaptics` + `_RecordingHaptics.restPings`; 4 the rest tick asks the rule through `state.units.restPingSeconds`; 5 both Settings subtitles; 6 the convention row and the four docs; 7 the scanner denial and S-250; 8 the QA index rows with the baselines untouched.

## 4b Scenarios — pass

S-241/S-242/S-243/S-244/S-245 (Dart half), S-249 and S-250 each have a passing test asserting the stated outcome, and the fixture is the enumerated one: the Dart tests walk `watch/contract/watch_rest_ping_contract.json` row by row (including the gap 200/240 and the 36/60/90 variant), not a hand-built pair. No scenario is missing a test.

## 4c Test verification — pass

Counts pasted above; the handoff's Docs section names each implicated doc as updated or unchanged. No hang, timeout or killed run.

## 4d Documentation falsification — PASS (6 implicated)

Implicated and read: `global_conventions.md:17`, `rest_tracking.md:15-20`, `theme_and_settings.md:9`, `watch_session_sync.md:604-606`, `state_management/watch_surface.md:438-442` + its scope line, `plans/2026-10-08-18-watch-qa-index.md` (22/22b rows). Swept every other doc that states the rest rule or the wrist's haptics (`state_management/services_and_utils.md:151-152`, `state_management/app_state.md:141-165`, `watch-app-setup-and-qa.md:199-202,485-490`, `modality_tracking.md`, `design_system.md`); none asserts the old absolute. The removed `watch_surface.md` sentence is genuinely duplicated at `watch_session_sync.md:588-591` (device-local, cited to S-79 in `test/watch_logging_timers_test.dart:333`) and `:608` (kilograms), so the removal loses nothing; the file stays under the contract test's 64 KiB ceiling and its 80% band (52,429 B). `docs/releases/2026-05-plan-review.md:66` ("rest ping uses lighter haptics") is a frozen snapshot with an explicit not-current scope banner, so it is not implicated. Every test and type a doc names exists: `WatchRestPingTests.testS241AnIntervalTapsAtItsMultiplesAndNowhereElse`, `WatchRestSurfaceTests.testS161…`, `WatchLoggingTimersTests.testS164ARestIsNeverOwedAnAlert`, `test/watch_rest_ping_test.dart`'s S-241 name verbatim, the scanner group and S-250.

## 4e Documentation standard — ✅ PASS

No prohibited content added: no step walkthrough or arrow chain, no visual value or hex literal, no control inventory, no restated constant (the "30, 60 and 90" figures appear inside a cited test name, which is the pointer the standard requires), no copied implementation, no roadmap or unshipped-change note. The touched sections point at named tests.

## 4f Conventions — PASS (5), N/A (4)

PASS: rest is a count-up (row updated, scanner green, denial intact); reuse the canonical owner (one rule, `WatchRestPing`, fed by the contract table — no second copy of the numbers); timestamps are source data (elapsed still derived from the persisted row); no state notification during the build phase (`initState` only starts the ticker; the ping runs from the timer callback); instrument panel, not influencer (no new chrome, restrained cue). N/A (one reason): units/canonical storage, theme tokens, card chrome, effort-kind analytics — no unit, colour, card or analytics surface changed.

## 4g Impact check — PASS (rows re-checked, 0 unlisted readers)

Re-ran the rows' greps: `WatchHaptics` conformers are still `SystemWatchHaptics`, `WatchLoggingScreen.haptics` and `test/watch_logging_surfaces_test.dart`'s `_RecordingHaptics` (the stub now implements the new member); `WatchRestScreen(` is constructed at `test/watch_rest_surface_test.dart:163` and the new S-226 site; `WatchUnitPreferences` readers are `watch_logging_state.dart:125,164`, `watch_metric_stepping.dart:46-56,93,123` and `watch_logging_debug_main.dart:130` — the added field is defaulted `const`, so every site still compiles (`WatchUnitPreferences` has no `==`/`hashCode`, so no equality behaviour changed). The unlisted-reader sweep found none: `restPingSeconds` is read only by the rest screen's ping and the phone's `WatchSyncRequestHandler`/`preferences_down` path that plan 22 already shipped.

## Assumption Log — RATIFY (6 of 7), one carried as F1

RATIFY: the Dart closure over the contract table (D-261); the Settings subtitles only, not the labels or ownership (D-262); the residue sweep and the Swift `rule` string left alone deliberately (this one is F1 — ratified as a deliberate deferral, with the guard that makes it fail instead of rot); the mutation-based proof for the negative guard S-250; the doc-size policy (below the band, deletion genuinely stale); the Dart `SystemWatchHaptics` using its existing `mediumImpact()` (D-251 sanctions it). Nothing needed REVERT or ESCALATE.

## Open questions

- The governor's full-suite result was not readable from `.work/gateway/` at review time (the run is in flight), so the only full-suite counts here are the handoff's pasted ones. The targeted set, lint and swift counts are green from two independent runs.
- `test/settings_sounds_test.dart:149` leaks a surface size too (pre-existing, not this PR). Left alone as instructed; recorded here so it is not lost.

## Verdict

APPROVE — no critical or blocking finding. F1 is a stale comment outside every scanner root; F2 and F3 are suggestions.

