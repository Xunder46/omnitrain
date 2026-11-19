# Evidence — plan 177 (Diagnostics entry points hidden in release builds)

Baselines at HEAD `62480d10` unless stated otherwise. Every count below is
pasted from a gateway run; nothing here is an estimate.

## Phase 0 — RED first

Register verified against `## Scenarios` before writing any test: all seven
S-ids name their fixture (the constants file, `main.dart`, the Settings
surface, `ContentView.swift`, `project.pbxproj`, `WatchStartView.swift`).

`gateway.sh prove-red HEAD test test/diagnostics_entry_test.dart test/diagnostics_wiring_source_test.dart test/settings_diagnostics_test.dart`

```
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an
assertion fails for the reason the test guards; a compile or load error means
the test could not run there (use a mutation instead).
```

What failed, and why:

| S-id | At HEAD | Verdict |
|---|---|---|
| S-17702 | real assertion: `main.dart does not contain 'diagnostics: kDiagnosticsEntryVisible ? diagnostics : null,'` | red for the reason it guards — proves the guard |
| S-17701 | compile error (`diagnosticsEntryVisibleFor` does not exist — new symbol) | needs a mutation proof (M1/M2) |
| S-17703 | compile error (`diagnosticsEntryVisibleFor`, `kDiagnosticsEntryVisible` new) | needs a mutation proof (M1/M2) |
| S-17706 | compile error (imports the new constants file) | needs a mutation proof (M1/M2) |
| S-17704 | Swift: `DiagnosticsEntryPoint.swift` absent (`NSCocoaErrorDomain 260`) | needs a mutation proof (M3) |
| S-17705 | Swift: Profile configuration has no `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | needs a mutation proof (M4) |
| S-17707 | green at HEAD by design — it asserts recording is untouched | guard against regression, mutation-proved by M3 |

## Phase 1 — phone gate (green)

`gateway.sh test test/diagnostics_entry_test.dart test/diagnostics_wiring_source_test.dart test/settings_diagnostics_test.dart`

```
14 passed, 0 failed
```

Mutation proofs (original line recorded, changed, seen red, restored exactly,
re-run green):

| # | File | Original line | Mutation | Test that went red |
|---|---|---|---|---|
| M1 | `lib/core/constants/diagnostics_entry.dart` | `}) => debugBuild || profileBuild || override;` | `}) => profileBuild || override;` | S-17701 `a debug build shows the entry point` — Expected `true`, Actual `false`; S-17703 flag-on — 0 `Diagnostics` widgets found |
| M2 | same file | same | `}) => true;` | S-17701 `a release build with no override hides the entry point`; S-17703 `the release fixture has no row` — Expected `null` |

## Phase 2 — watch app-target gate (green)

`gateway.sh swift-test --filter WatchDiagnosticsSourceTests` before GREEN:

```
Executed 10 tests, with 3 failures (0 unexpected)
```

Failures: `testS14213TheStartScreenOpensTheDiagnosticsSurface` (line 124, the
old ungated closure), `testS17704TheEntryPointIsGatedThroughTheAppTargetGate`
(gate file missing), `testS17705TheWatchBuildConfigurationsCarryTheRightConditions`
(Profile condition missing). `testS17707` was green — by design.

After GREEN:

```
Executed 10 tests, with 0 failures (0 unexpected) in 0.016 (0.017) seconds
```

| # | File | Original line | Mutation | Test that went red |
|---|---|---|---|---|
| M3 | `ios/OmniTrain Watch App/DiagnosticsEntryPoint.swift` | `#if DEBUG || PROFILE || OMNITRAIN_DIAGNOSTICS` | `#if DEBUG || OMNITRAIN_DIAGNOSTICS` | S-17704 — `debug, profile and the owner override are the three ways in` (line 168) |
| M4 | `ios/Runner.xcodeproj/project.pbxproj` (Profile config) | `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "PROFILE $(inherited)";` | line removed | S-17705 — `the Profile configuration carries PROFILE` (line 218) |

Both restored exactly; the file was green again on the next run
(`Executed 10 tests, with 0 failures`).

## Phase 3 — docs (green)

`gateway.sh test test/docs_indexing_contract_test.dart`

```
00:00 +13: All tests passed!
```

## Final verification (whole feature)

`gateway.sh test` (full suite, run while a concurrent plan-176 run was building
in the same tree):

```
06:53 +7672 ~4 -1: Some tests failed.
```

The one failure is `test/pre_release_gate_ios_artifact_test.dart`, group
`pre-release gate — combined crash-reporting section fails when any single
invariant fails`, test `happy path — gate does not fire the new iOS artifact
checks against the post-fix repo`:

```
TimeoutException after 0:00:30.000000: Test timed out after 30 seconds.
```

That test copies the repository into a temp directory and runs the gate script
(it takes ~20 s per case on an idle machine). Re-run on its own:

```
04:48 +12: All tests passed!
```

so it is a load timeout, not a regression: no file it inspects was changed by
this plan beyond the single Profile-condition line.

`gateway.sh test` (full suite) re-run after the load cleared:

```
05:52 +7673 ~4: All tests passed!
```

7673 passed, 4 skipped, 0 failed.

`gateway.sh test test/diagnostics_entry_test.dart test/diagnostics_wiring_source_test.dart test/settings_diagnostics_test.dart test/navigation_contract_enforcement_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`

```
00:03 +69: All tests passed!
```

`gateway.sh lint`:

```
181 issues found. (ran in 4.7s)
```

181 is the plan's baseline; this change adds no notice, and the files it touched
carry none (the notices are `deprecated_member_use` in other test files).

`gateway.sh swift-test` (full package):

```
Executed 1495 tests, with 0 failures (0 unexpected) in 40.251 (40.352) seconds
Test Suite 'All tests' passed
```

## Residue sweep (item 4)

`grep Diagnostics|diagnostics` across `lib/`, `ios/OmniTrain Watch App/`,
`watch/watchos/Sources/`:

- Entry-point constructions, the only two, both gated:
  - `ios/OmniTrain Watch App/ContentView.swift`:
    `onOpenDiagnostics: DiagnosticsEntryPoint.isVisible ? { showingDiagnostics = true } : nil`
  - `lib/main.dart`: `diagnostics: kDiagnosticsEntryVisible ? diagnostics : null,`
- Readers that already treat null as "no entry", unchanged:
  `lib/features/settings/settings_screen.dart` (`if (widget.diagnostics != null)`,
  the `_DiagnosticsRow` and its `Diagnostics` row only render then),
  `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`
  (`if let onOpenDiagnostics { Button(Self.diagnosticsLabel, …) }`).
- Recording sites, intentionally untouched (D-17701): `lib/main.dart`
  (`DiagnosticsLog(...)`, `noteLaunch()`, the lifecycle observer,
  `createWatchSync(... diagnostics: diagnostics ...)`),
  `ios/OmniTrain Watch App/ContentView.swift` (`diagnostics.noteLaunch()`,
  `host.diagnostics.note("scene"`, the `WatchDiagnosticsView` sheet and
  `sendDiagnostics`), `ios/OmniTrain Watch App/OmniTrainApp.swift`
  (`recovery_relaunch`), `watch/watchos/Sources/WatchSessionEngine/` (the log,
  the summary, the view, the bridges).
- No other construction of the two representations exists; no reader of a
  gated representation was left ungated.

`grep -rln "import .*hive_workout_repository" lib/` → `lib/main.dart` only (the
composition root; `lib/state/`, `lib/features/`, `lib/widgets/` and `lib/core/`
are clean).

## Generated-bundle note

`ios/Runner.xcodeproj/project.pbxproj` in the working tree carries a large
project-file rewrite that this run did not make (`objectVersion` 54 → 70,
reordered `PBXBuildFile`/`PBXFileReference` entries, a collapsed
`PBXFileSystemSynchronizedRootGroup`, the local package reference named
`"../watch/watchos"`, empty `inputPaths`/`outputPaths`, reordered
`SUPPORTED_PLATFORMS`). This run's only change in that file is the single line
`SWIFT_ACTIVE_COMPILATION_CONDITIONS = "PROFILE $(inherited)";` in the watch app
target's Profile configuration `46AC7A243061FCC100924AC9`. A concurrent run was
building in this tree at the time, so the governor should restore the file from
HEAD and re-apply that one line rather than review the rewrite.

## Governor-only checks

- `xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -sdk watchsimulator -configuration Release` — the gated `#else` branch compiles.
- Same command with `-configuration Profile` — the `PROFILE` branch compiles.
- Owner QA on device: the Phase 3 how-to in `docs/watch-app-setup-and-qa.md` step 38 (release override) and the phone `--dart-define=OMNITRAIN_DIAGNOSTICS=true`.
