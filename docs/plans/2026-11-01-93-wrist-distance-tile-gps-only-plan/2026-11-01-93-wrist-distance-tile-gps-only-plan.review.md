# Plan 93 — code review

Reviewer: @code-reviewer (Claude Code), 2026-11-01. Diff: `git diff 2ff372f8~2 2ff372f8` (cf50bdbe phase 1, 2ff372f8 phase 2).

Layers in scope: watch (Swift `watch/watchos` Sources + Tests), watch protocol doc, docs
Layers skipped: models, persistence, state, features, widgets, core (no `lib/` changes)

## Findings (appended as found)

- minor | `watch/watchos/Tests/WatchSessionEngineTests/WatchGpsDistanceTileTests.swift:502-506` | S-16011's trait check only requires the `.isButton` line to mention `isMeasured`, so the inverted mutant `field.isMeasured ? .isButton : []` (measured tile announced as a button, unmeasured tiles lose the trait) survives — reviewer ran it as M12c: 13 tests, 0 failures | anchor the exact ternary (measured arm `[]`, unmeasured arm `.isButton`) so M12c reddens; the strengthened assertion is the guard | @developer
- nit | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:362-363` | `isMeasuringDistance`'s doc comment ("measured for the user rather than dialled by them") predates plan 65 and still implies a wrist distance dial, which plan 93 removed | reword to "whether the location subscription is running" (comment only) | @developer
- nit | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift:335-339` | a measured tile keeps its `onTapGesture` (guarded to a no-op); D-5 holds in the model, but VoiceOver may still offer an inert activate action on the tile | optional: attach the gesture only to unmeasured tiles; confirm with VoiceOver during QA step 27 | @developer
- nit | `docs/state_management/watch_surface_wrist.md:393-394` | "covered more than 0 m" restates the source threshold (doc standard class 4, borderline: 0 is the "any movement" rule, pinned by S-16002/S-16004) | optional: "has covered any distance" | @developer

## Behavioural verification

- 4a Acceptance criteria AC-1..AC-8: all met. AC-1 S-16001..3; AC-2 S-16002..5, S-16012 + S-006; AC-3 S-16006; AC-4 S-16007; AC-5 S-16008/9; AC-6 S-16010; AC-7 S-16011, S-16013; AC-8 S-16014 (existing tests, green).
- 4b Scenarios S-16001..S-16014: each has a passing test building the scenario's fixture (F-RUN timings, stale sample at T0, sample at the Start instant, still watch with 3 samples, denied grant, rest-time movement 650 m, miles + km on one engine, sensors nil). S-16014 is covered by `SyncProtocolFixturesTests` (in the 1139) and phone `test/distance_source_import_test.dart` S-876/S-877 (green).
- Ledger D-1..D-11: D-1 `WatchLoggingState.swift:725` (filter in `metricKeys`, reaches `fields`, `adjust`, `value(of:)`, the model); D-2 `measuredValue` = window, `displayValue`/`unitLabel` reused, S-16006/S-16010; D-3 `windowPayload` GPS-only (l.1089-1096), S-16004/5/12/13; D-4 `WatchLoggingModel.swift` untouched, `armedMetricKey`/`arm` filter measured fields, S-16006 + Crown tests; D-5 `WatchLoggingView.swift:346-373` (measured row = tile alone, no button trait), S-16011 (see minor); D-6 `dialled`, the `adjust` guard, distance stepping kept, no new functions in Sources, append-only guard green; D-7 no diff under `lib/`, `test/`, `ios/`, schemas, fixtures, `watch/contract`, PROTOCOL.md sentence replaced verbatim; D-8 no Dart change; D-9 file deleted, D-9 table edits applied as listed; D-10 doc 52221 B; D-11 nothing built.
- Crown on a read-only field: `armedMetricKey` filters measured fields, `arm(_:)` refuses them, `turn`/`stepArmed` no-op without an armed key, the view's tap guard returns early; S-16006 asserts nil before/after turn, value unchanged after turn/step/adjust.
- Log payload: only `covered > 0` → `distanceMeters` + `"gps"`; `grep '"entered"' watch/watchos/Sources` empty; S-16013 scans every Source file.
- 4c Test runs (reviewer, observed): `swift test --package-path watch/watchos` (with-timeout 900) → `Executed 1139 tests, with 0 failures (0 unexpected)`, exit 0; all 13 `WatchGpsDistanceTileTests` passed. `flutter test test/distance_source_import_test.dart test/session_summary_distance_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` → `+81: All tests passed!`, exit 0. Evidence pastes real counts and red-on-base runs for every new behavioural test.
- Mutation sample (reviewer, scratch copy of `watch/`, repo source untouched): M2 killed (S-16001..4, 6, 7); M3 killed (S-16004/6/7; S-16003 green as evidence says); M5b survived (equivalent); M11 killed (S-16013); M12c (inverted trait, new) survived → minor above.
- Evidence M5b/M3 explanation: sound. `isWorkRunning` is exactly `workTimer != nil` (l.554), so a round either has no work clock (window 0, D-1 filter drops distance) or is running (`fields` returns `[]`, l.635): no reachable state shows the mutant. M3: `windowMeters` sums only samples with `recordedAt > start`; S-16003 has none after Start, so the baseline never enters the sum and S-16003 cannot redden; the plan's prediction was wrong, the evidence's correction is right.
- 4d Doc falsification: PASS (6 implicated) — `watch_surface_wrist.md` (rewritten paragraph matches code; l.351-353 "first row no sensor keeps" and l.410 single-row − / + examples still true), `watch-app-setup-and-qa.md` step 27 (matches code; phone `—` is `SessionDistanceCard.absentValue`, "est." only for `estimated`), `PROTOCOL.md` l.192-198, `watch_sensors.md` l.375-382 (accurate again), `distance_source.md` l.94-97/l.174 (true for the phone, the Dart twin and legacy events), `watch-app-qa-wrist-logging.md` step 6 (accurate again). No conflicts. Stale-reference grep (`plan 65`, `WatchHandDistanceTests`, `testS9503`, `S-950x`, `S-9510`) outside `plans/`, `history/`, `releases/`, `.build`: empty repo-wide.
- 4e Doc standard: PASS with one borderline nit; `watch-app-setup-and-qa.md` is a record outside the standard (§ "Records are outside this standard"). New paragraph points at `WatchGpsDistanceTileTests.swift` and the unique `testS006…`.
- 4f Conventions: PASS (5): units (existing `displayValue`/`metresPerUnit`), timestamps as source data (window from stored samples), reuse the canonical owner, instrument panel, rest rule untouched. N/A (6): theme tokens, OmniSurface, effort-kind analytics, initState notify, shared Flutter UI pieces, fix-what-you-touch allowlist (no Flutter UI touched).
- 4g Impact: 13 rows checked; `.fields` / `isMeasured` / `distanceSource` greps re-run match the rows (`value(of:)` is l.1171); no unlisted readers; `ios/OmniTrain Watch App` has none.
- Diff vs Predicted Files: conforms (Phase 1: 14 files, Phase 2: 6 files, all predicted).
- Outstanding (not a finding): watch app `xcodebuild` (governor); the view was type-checked for watchOS with `swiftc -typecheck` in evidence. Owner device check = QA step 27.

## Assumption Log adjudication

- A-1 RATIFY (factual count, 14 tests; arithmetic verified by the 1138/1139 runs).
- A-2 RATIFY (within D-1's stated mechanic freedom; single choke point is the better choice).
- A-3 RATIFY (both equivalences verified above).

## Verdict

APPROVED with 1 minor and 3 nits. No major. Critical: 0 | Minor: 1 | Nits: 3. The minor is a test-strength gap, not a behaviour defect; it and the nits can ride in the next watch PR or be fixed in one small pass (test + comment only).
