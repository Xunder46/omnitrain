# Feature: The Diagnostics entry points are hidden in release builds (plan 177)

> Status: Iteration 1 active
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md
> Related plans: 142 (`docs/plans/2026-11-10-142-diagnostics-log-plan/`, D-14210 the Start-screen button and the sheet),
> 143 (`docs/plans/2026-11-10-143-phone-diagnostics-log-plan/`, D-14305/D-14306 the Settings row),
> 144 (`docs/plans/2026-11-10-144-watch-log-to-phone-plan/`, D-14403 the radio and `sendDiagnostics`),
> 174 (`docs/plans/2026-11-14-174-phone-adoption-diagnostics-plan/`, the phone's decision kinds).

## Overview

The Diagnostics surfaces are debugging tools, not user features: the wrist's
"Diagnostics" button (bottom of the Start screen, `WatchStartView`) and the
phone's "Diagnostics" row in Settings' APPLE WATCH section. **Owner decision
2026-11-15:** neither ships to users.

This plan hides the two **entry points only**. The logs themselves keep
recording in every build — they are how the owner debugs real walks — and
nothing ever leaves the device unless the user copies it (plan 142 D-14211,
plan 143 D-14307 privacy rules are untouched).

- **Phone.** `SettingsScreen.diagnostics: DiagnosticsLog?` (settings_screen.dart:43) is
  already the seam: null hides the row (settings_screen.dart:161). The gate lives in
  `lib/main.dart` where `MyApp` is built (main.dart:486).
- **Watch.** `WatchStartView.onOpenDiagnostics: (() -> Void)?` (WatchStartView.swift:92)
  is already the seam: nil leaves the button off (WatchStartView.swift:248). The
  gate lives in the app target's `ContentView.swift` where the closure is passed
  (ContentView.swift:558).

No new screen, no new state, no persisted field, no route change.

## Resolved Decisions (Ledger)

| Id | Decision | Ground truth |
|----|----------|--------------|
| D-17701 | Only the two ENTRY POINTS are gated; the log itself records in every build. On the phone `lib/main.dart` keeps building `DiagnosticsLog` once and passing it to `createWatchSync(diagnostics:)` (main.dart:400, pinned by `test/diagnostics_wiring_source_test.dart` "S-14316"); on the watch `WatchAppHost` keeps `diagnostics` (ContentView.swift:161, 353) and keeps noting `scene`/`launch` (ContentView.swift:162, 589). No `note`, no `DiagnosticsLog`/`WatchDiagnosticsLog` construction, and no `sendDiagnostics` wiring changes. | ContentView.swift:158-215; lib/main.dart:363-366 |
| D-17702 | Visibility rule: **debug ∪ profile ∪ explicit owner override**; release with no override is hidden. Phone: one file, `lib/core/constants/diagnostics_entry.dart`, holds (a) `const bool kOmnitrainDiagnosticsOverride = bool.fromEnvironment('OMNITRAIN_DIAGNOSTICS')` — set with `--dart-define=OMNITRAIN_DIAGNOSTICS=true`; (b) a pure injectable predicate `bool diagnosticsEntryVisibleFor({required bool debugBuild, required bool profileBuild, required bool override})` returning `debugBuild || profileBuild || override`; (c) `const bool kDiagnosticsEntryVisible = bool.fromEnvironment('OMNITRAIN_DIAGNOSTICS') || kDebugMode || kProfileMode;` used by main.dart. The constant is named ONCE, here; no other file writes `OMNITRAIN_DIAGNOSTICS`. | lib/core/constants/ has no diagnostics file yet (glob); `kDebugMode`/`kProfileMode` are const in Flutter |
| D-17703 | Watch gating is compile-time, in the APP TARGET (the package cannot see the app's conditions; the closure is passed in from ContentView). New app-target file `ios/OmniTrain Watch App/DiagnosticsEntryPoint.swift`: `enum DiagnosticsEntryPoint { static var isVisible: Bool { #if DEBUG \|\| PROFILE \|\| OMNITRAIN_DIAGNOSTICS; return true; #else; return ProcessInfo.processInfo.environment["OMNITRAIN_DIAGNOSTICS"] == "1"; #endif } }`. `ContentView.swift:558` becomes `onOpenDiagnostics: DiagnosticsEntryPoint.isVisible ? { showingDiagnostics = true } : nil`. The `WatchStartView` package contract (nil → no button, WatchStartView.swift:248) is unchanged. | WatchStartView.swift:90-92, 248-250; package Tests scan app sources via `appSource("ContentView.swift")` (WatchDiagnosticsSourceTests.swift:122) |
| D-17704 | Build configurations: the watch target's Debug config already sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"` (project.pbxproj, config named Debug, ~line 686); the Release config `46AC7A233061FCC100924AC9` (~732) and Profile config `46AC7A243061FCC100924AC9` (~782) set none. The plan adds `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "PROFILE $(inherited)"` to the watch target's **Profile** config so `#if PROFILE` compiles true there. The **Release** config is left clean — the owner adds `OMNITRAIN_DIAGNOSTICS` to it temporarily when debugging a release build (D-17706), so a normal release never carries the button. | project.pbxproj read 2026-11-15 |
| D-17705 | Hidden means unreachable. Verified by grep: there is no deep link / URL scheme / named route to either surface — `lib/` has no `go_router`, no `pushNamed`, no `onOpenURL` (grep 2026-11-15, zero hits); `lib/core/navigation/` mentions no diagnostics (grep, zero hits); `docs/navigation_contract.md`'s rule (test `test/navigation_contract_enforcement_test.dart`) only forbids raw `MaterialPageRoute`/`PageRouteBuilder` outside `lib/core/navigation/` and needs NO change. The sheet on the watch root (ContentView.swift:580-582) and the Settings row are the ONLY constructions of the diagnostics surfaces; both are gated by D-17702/D-17703. There is no settings search. | greps of lib/, lib/core/navigation/, test/navigation_contract_enforcement_test.dart |
| D-17706 | Owner override, Release/TestFlight: (a) watch — add `OMNITRAIN_DIAGNOSTICS` to the watch app target's Active Compilation Conditions for Release (Xcode: target "OmniTrain Watch App" → Build Settings → Swift Compiler - Custom Flags → Active Compilation Conditions, Release) and rebuild; the button returns; remove it before archiving a user build. (b) watch, Release run from Xcode without a rebuild-config change — set the environment variable `OMNITRAIN_DIAGNOSTICS=1` in the scheme's run action (the ProcessInfo fallback in D-17703 reads it). (c) TestFlight — no env vars: (a) is the only path. (d) phone — build with `--dart-define=OMNITRAIN_DIAGNOSTICS=true`. The owner's normal workflow — an Xcode Debug run on both devices — is UNCHANGED: Debug sets DEBUG (pbxproj ~686) and `kDebugMode` is true, so both entries show as today. | D-17702, D-17703, D-17704 |
| D-17707 | (derived, vetoable) main.dart gates the `MyApp` argument to `diagnostics: kDiagnosticsEntryVisible ? diagnostics : null` rather than passing the flag down as a second parameter: `SettingsScreen` already treats null as "no row" (plan 143 D-14306, settings_screen.dart:161) and the log object stays alive for recording (D-17701), so a second parameter would add a seam without changing any user-visible result. | settings_screen.dart:41-43, 161 |
| D-17708 | The watch entry test is a source scan, not a render test: the package has no SwiftUI view-inspection harness (its Tests are pure-logic plus `#if canImport(SwiftUI)` interpolation checks — WatchDiagnosticsSourceTests.swift:20, 154). The structural proof that nil hides the row is the existing `if let onOpenDiagnostics {` (WatchStartView.swift:248, asserted by testS14213TheStartScreenOpensTheDiagnosticsSurface:133); plan 177 adds scans pinning the app-target gate and the gated closure instead of introducing a render harness. | WatchDiagnosticsSourceTests.swift:120-146 |

## Feature Invariants

- **The log always records.** Whether or not an entry point is visible, both
  logs record in every build and every test suite that asserts recording
  keeps passing unchanged (`test/diagnostics_log_test.dart`,
  `test/diagnostics_wiring_source_test.dart`, `WatchDiagnosticsLogTests`).
- **One constant, one place.** `OMNITRAIN_DIAGNOSTICS` is written exactly
  once per track: `lib/core/constants/diagnostics_entry.dart` (phone) and
  `DiagnosticsEntryPoint.swift` + the Release build condition the owner sets
  (watch). No other file reads `kDebugMode` to gate diagnostics.
- **The seams are the existing optionals.** `SettingsScreen.diagnostics` and
  `WatchStartView.onOpenDiagnostics` do not gain a second flag parameter; the
  callers pass null/nil when hidden.

## Requirements

1. Release phone build: Settings has no Diagnostics row; nothing reaches the
   log screen.
2. Release watch build: the Start screen's last button is not "Diagnostics".
3. Debug and profile builds on both tracks: unchanged from today (button and
   row visible).
4. Owner override (D-17706) brings the entries back in a release build on
   either track.
5. Both logs keep recording in all builds (D-17701).
6. Docs state the rule and the override how-to.

## Acceptance Criteria (each maps to ≥1 scenario)

- AC-1 → S-17701, S-17702, S-17703: phone, flag off, no row; flag on, row; the
  wiring is the gated constant, not an ad-hoc `kDebugMode` check.
- AC-2 → S-17704, S-17705: watch, release config, no button; the closure is
  gated through the app-target gate; the Profile config defines PROFILE.
- AC-3 → S-17703, S-17704: debug/profile fixtures show the entries.
- AC-4 → S-17706: override paths are pinned by the predicate truth table and
  the gate file's `#if` conditions.
- AC-5 → S-17707: the recording wiring is untouched (source scan).
- AC-6 → Phase 3 docs; `test/docs_indexing_contract_test.dart` stays green.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `lib/main.dart` `MyApp(diagnostics:)` (main.dart:486) | `test/settings_diagnostics_test.dart`, `test/settings_diagnostics_watch_log_test.dart` (pump SettingsScreen with the injected log — they own the seam and are unaffected); `test/diagnostics_wiring_source_test.dart` S-14316 (scans the `createWatchSync` call at main.dart:400, NOT the MyApp argument — no conflict) | The argument becomes flag-conditional | S-17702, S-17707 |
| `lib/features/settings/settings_screen.dart:161` `if (widget.diagnostics != null)` | `test/settings_diagnostics_test.dart` (S-14315 row/copy/position), `test/settings_diagnostics_watch_log_test.dart` | NO CODE CHANGE: null already hides the row | S-17703 |
| `ios/OmniTrain Watch App/ContentView.swift:558` closure, `:580-582` sheet | `watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSourceTests.swift:120-146` asserts `onOpenDiagnostics: { showingDiagnostics = true }` VERBATIM — goes RED, updated in Phase 2 | Closure becomes gated; sheet stays | S-17704 |
| `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift:92, 248` | testS14213TheStartScreenOpensTheDiagnosticsSurface:133-145 (init keeps closure, `if let`, label constant) | NO CODE CHANGE: the injected-optional contract already means nil → no button | S-17704, D-17708 |
| Watch Profile/Release build configs | `WatchDiagnosticsLogTests` etc. run via `swift test` (Debug) — unaffected | Profile config gains PROFILE condition | S-17705 |
| Phone diagnostics recording wiring (main.dart:363-366, :400; watch_sync_wiring.dart) | `test/diagnostics_log_test.dart`, `test/diagnostics_lifecycle_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`, `test/diagnostics_wiring_source_test.dart` | NONE — grep proves the gate touches only the MyApp argument; the `createWatchSync` wiring statement is a different line (main.dart:400) | S-17707 |

## UI Standards Impact

None. No new surface, no styling, no copy change; the Start screen simply has
one fewer button in release and Settings one fewer row. `docs/design_system.md`
pieces are not touched. The Start screen's layout tests in the package are
source scans, unaffected.

## Scenarios

### S-17701: the phone visibility predicate's truth table
- Fixture: none (pure function). Input triples `(debugBuild, profileBuild, override)`.
- Trigger: call `diagnosticsEntryVisibleFor(debugBuild:profileBuild:override:)`.
- Flow: evaluate the pure predicate in `lib/core/constants/diagnostics_entry.dart`.
- Expected outcome: `(true, false, false) → true`, `(false, true, false) → true`,
  `(false, false, false) → false`, `(false, false, true) → true`,
  `(true, false, true) → true` (override never turns it off). Pinned by
  `test/diagnostics_entry_test.dart`.
- Edge case of: none.

### S-17702: phone release wiring passes null to Settings
- Fixture: source of `lib/main.dart` (read as text, like S-14316's scans).
- Trigger: run the new scan in `test/diagnostics_wiring_source_test.dart`.
- Flow: assert the `MyApp(` constructor block contains
  `diagnostics: kDiagnosticsEntryVisible ? diagnostics : null,` and that
  `lib/main.dart` contains no other `kDebugMode`-based diagnostics gate and no
  second literal `OMNITRAIN_DIAGNOSTICS` (only the import of the constants
  file uses it).
- Expected outcome: scan green; a build that inlines `kDebugMode` at the MyApp
  call or drops the gate fails the scan.
- Edge case of: none.

### S-17703: Settings hides the row when the entry flag is off, shows it when on
- Fixture: `MockWorkoutRepository` (initialized), `SettingsState` over it
  (initialized), `WatchLinkState` with a connected `_Source` (`WatchLinkInfo(paired: true, appInstalled: true, reachable: true)`),
  `DiagnosticsLog` with 2 `launch` events over `InMemoryDiagnosticsStorage`,
  clock `DateTime.utc(2026, 1, 1, 12)` — the exact helpers of
  `test/settings_diagnostics_test.dart` (`_makeSettings`, `_makeWatchLink`, `_logOfEvents`).
- Trigger: pump `SettingsScreen` with the diagnostics seam computed by the SAME
  pure predicate main.dart uses:
  `diagnostics: diagnosticsEntryVisibleFor(debugBuild: false, profileBuild: false, override: false) ? log : null`
  (flag-off fixture), and again with `debugBuild: true` (flag-on fixture).
- Flow: `testWidgets` in `test/settings_diagnostics_test.dart`, Mock-first
  (no Hive in the harness), pump-and-settle.
- Expected outcome: flag off — `find.text('Diagnostics')` finds nothing while
  `find.text('Apple Watch')` still finds the status row; flag on — the row
  reads `Diagnostics` / `2 events` / `Copy` as S-14315 pins today.
- Edge case of: none (S-14315 covers the row's own behavior).

### S-17704: the watch closure is gated through the app-target gate
- Fixture: sources `ios/OmniTrain Watch App/ContentView.swift`,
  `ios/OmniTrain Watch App/DiagnosticsEntryPoint.swift`, and
  `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` (the package
  tests' `appSource`/`packageSource` readers).
- Trigger: the updated `testS14213TheStartScreenOpensTheDiagnosticsSurface`
  and the new scan in `WatchDiagnosticsSourceTests.swift`.
- Flow: assert (a) ContentView contains
  `onOpenDiagnostics: DiagnosticsEntryPoint.isVisible ? { showingDiagnostics = true } : nil`;
  (b) ContentView still contains
  `WatchDiagnosticsView(log: host.diagnostics, onSend: { url in host.sendDiagnostics(url) })`
  (the sheet, and with it Send-to-phone, live only behind the entry);
  (c) the gate file names exactly `#if DEBUG || PROFILE || OMNITRAIN_DIAGNOSTICS`
  and the ProcessInfo fallback
  `ProcessInfo.processInfo.environment["OMNITRAIN_DIAGNOSTICS"] == "1"`;
  (d) `WatchStartView.swift` still contains `if let onOpenDiagnostics {` and
  `Button(Self.diagnosticsLabel, action: onOpenDiagnostics)` unchanged.
- Expected outcome: green; a release configuration compiles the `#else` branch
  and passes nil, so `WatchStartView.swift:248` renders no button.
- Edge case of: S-14213 (the old scan, superseded in its ContentView line only).

### S-17705: the build configurations carry the right conditions
- Fixture: `ios/Runner.xcodeproj/project.pbxproj` source.
- Trigger: source scan in `WatchDiagnosticsSourceTests.swift` (reads via the
  repo-relative path, same pattern as `appSource`).
- Flow: assert the watch app target's Debug config sets
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"`; the Profile
  config `46AC7A243061FCC100924AC9` sets
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "PROFILE $(inherited)"`; no
  build configuration in the file sets `OMNITRAIN_DIAGNOSTICS` (the owner adds
  it temporarily, per D-17706 — a committed override would ship the button).
- Expected outcome: green; a Release build with no owner override compiles the
  hidden branch; a Profile build compiles the visible branch.
- Edge case of: none.

### S-17706: the owner override reaches a release build
- Fixture: the predicate (phone) and the gate file (watch).
- Trigger: phone — `diagnosticsEntryVisibleFor(debugBuild: false, profileBuild: false, override: true)`
  is true (S-17701's table); the constant
  `kOmnitrainDiagnosticsOverride = bool.fromEnvironment('OMNITRAIN_DIAGNOSTICS')`
  is scanned to appear verbatim in `diagnostics_entry.dart` (a test asserts the
  string, since a const environment read cannot be flipped at runtime — D-17702's
  "inject through a seam" rule). Watch — S-17704c pins the two override spellings
  in `DiagnosticsEntryPoint.swift`.
- Flow: unit + source scans only; the device-level override is the owner's QA
  step (docs, Phase 3; `owner to confirm` on device).
- Expected outcome: the release override is reachable without touching any
  production source beyond the one constant file.
- Edge case of: S-17701, S-17704.

### S-17707: hiding the entry never stops the recording
- Fixture: source of `lib/main.dart`, `lib/state/watch/watch_sync_wiring.dart`,
  `ios/OmniTrain Watch App/ContentView.swift`.
- Trigger: the existing scans keep running unchanged —
  `test/diagnostics_wiring_source_test.dart` S-14316 (log built once,
  `noteLaunch()`, lifecycle observer, `diagnostics: diagnostics` inside
  `createWatchSync(`) and the plan-174 adoption/inbox scan — plus one new
  assertion that `ContentView.swift` still contains
  `host.diagnostics.note("scene"` and `diagnostics.noteLaunch()`.
- Expected outcome: every recording assertion green with zero edits to
  recording code; the gate's only effect is the MyApp argument and the closure.
- Edge case of: D-17701's invariant.

## Iteration 1

### Phase 1: Phone entry gate (@developer)
1. [ ] RED — add the truth-table unit test for the predicate (S-17701) — `test/diagnostics_entry_test.dart` · `main()` tests `diagnosticsEntryVisibleFor` `(true,false,false)→true` etc.
2. [ ] RED — add the MyApp-argument wiring scan (S-17702) — `test/diagnostics_wiring_source_test.dart` · new test `S-17702 main.dart gates the Settings diagnostics argument` asserting `diagnostics: kDiagnosticsEntryVisible ? diagnostics : null,` inside the `MyApp(` block and no second `OMNITRAIN_DIAGNOSTICS` literal in `lib/`.
3. [ ] RED — add the flag-off/flag-on widget test using the shared predicate through the seam (S-17703) — `test/settings_diagnostics_test.dart` · new `testWidgets('S-17703 the entry flag hides the Diagnostics row in a release build and shows it in debug')` built on `_pumpSettings`/`_logOfEvents`.
4. [ ] GREEN — create the constants file — `lib/core/constants/diagnostics_entry.dart` · `kOmnitrainDiagnosticsOverride`, `diagnosticsEntryVisibleFor`, `kDiagnosticsEntryVisible` (exact spellings per D-17702).
5. [ ] GREEN — gate the MyApp argument — `lib/main.dart` · the `diagnostics:` argument of the `MyApp(` constructor call (:486) becomes `diagnostics: kDiagnosticsEntryVisible ? diagnostics : null,`; the `createWatchSync` call at :400 and the log construction at :363-366 stay untouched (D-17701, S-17707).
6. [ ] Verify the navigation contract needs no change (D-17705) — `test/navigation_contract_enforcement_test.dart` · unchanged, runs green as-is.
7. [ ] Update docs touched by the phone gate (Phase 3 items 1-2 cover the copy; this phase only leaves the code green).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/diagnostics_entry_test.dart test/diagnostics_wiring_source_test.dart test/settings_diagnostics_test.dart test/navigation_contract_enforcement_test.dart test/docs_indexing_contract_test.dart`; then `.github/copilot/scripts/macos/gateway.sh lint` (compare info-notice count with the pre-existing baseline — non-zero exit is expected while the repo carries notices; only NEW notices count as failures); paste pass/fail counts into `<plan-name>.evidence.md`.
**Predicted Files**: `lib/core/constants/diagnostics_entry.dart` (new), `lib/main.dart`, `test/diagnostics_entry_test.dart` (new), `test/diagnostics_wiring_source_test.dart`, `test/settings_diagnostics_test.dart`. Nothing else.
**Phase 1 verification notes (Conductor, date):** —
### Phase 1.Y: remediation — BLOCKS Phase 1 closure
(open — only if a scan or the widget test reveals a second diagnostics entry in `lib/`, e.g. a screen deep-linking to Settings; then gate it at its construction and add a scan pinning that).

### Phase 2: Watch app-target gate (@developer)
1. [ ] RED — update the superseded assertion and add the gated-closure + gate-file scan (S-17704) — `watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSourceTests.swift` · `testS14213TheStartScreenOpensTheDiagnosticsSurface` (:120-146) expects the gated closure string; new test `testS17704TheEntryPointIsGatedThroughTheAppTargetGate`.
2. [ ] RED — add the build-configuration scan (S-17705) — same file · new test `testS17705TheWatchBuildConfigurationsCarryTheRightConditions` reading `ios/Runner.xcodeproj/project.pbxproj`.
3. [ ] GREEN — create the gate — `ios/OmniTrain Watch App/DiagnosticsEntryPoint.swift` · `enum DiagnosticsEntryPoint { static var isVisible }` per D-17703.
4. [ ] GREEN — gate the closure — `ios/OmniTrain Watch App/ContentView.swift` · :558 becomes `onOpenDiagnostics: DiagnosticsEntryPoint.isVisible ? { showingDiagnostics = true } : nil`; the `showingDiagnostics` state (:508) and the sheet (:580-582) stay.
5. [ ] GREEN — add the Profile condition — `ios/Runner.xcodeproj/project.pbxproj` · in the watch app target's Profile configuration `46AC7A243061FCC100924AC9 /* Profile */` add `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "PROFILE $(inherited)";` beside `SWIFT_VERSION` (the Release config stays WITHOUT any condition, D-17704).
6. [ ] Add the recording-untouched scan (S-17707) — `watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSourceTests.swift` · new test `testS17707HidingTheEntryNeverStopsTheRecording` asserting `diagnostics.noteLaunch()` and `host.diagnostics.note("scene"` remain in ContentView.
7. [ ] Docs for the watch rule + owner Release how-to are Phase 3's; this phase leaves the package green.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (full package — Tests changed); paste counts into the evidence file. GOVERNOR-ONLY compile check (plan cannot run it): `xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -sdk watchsimulator -configuration Release` builds clean (the hidden branch compiles), and the same command with `-configuration Profile` (PROFILE branch compiles). 
**Predicted Files**: `ios/OmniTrain Watch App/DiagnosticsEntryPoint.swift` (new), `ios/OmniTrain Watch App/ContentView.swift`, `ios/Runner.xcodeproj/project.pbxproj`, `watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSourceTests.swift`. Nothing else.
**Phase 2 verification notes (Conductor, date):** —
### Phase 2.Y: remediation — BLOCKS Phase 2 closure
(open — if the Release xcodebuild fails to compile the `#else` branch, fix the gate file and re-run once; a second failure stops the phase and reports).

### Phase 3: Docs (@developer)
1. [ ] Document the entry-point rule and the owner override — `docs/state_management/watch_diagnostics.md` · new section "Entry point visibility" (~15 lines, after "The screen." / "Send to phone"): debug ∪ profile ∪ override; the two seams; the log always records (D-17701); the override spellings (D-17706). Doc is <20 KB today (read in full, no truncation) — safe under the 52 KB band.
2. [ ] Update the Settings description — `docs/theme_and_settings.md` · the Diagnostics-row paragraph (:124-128) gains one sentence: the row shows only when the entry flag is on (debug/profile, or the owner override), citing `lib/core/constants/diagnostics_entry.dart` and the new plan. Doc is <20 KB — safe.
3. [ ] Update the QA/setup doc — `docs/watch-app-setup-and-qa.md` · in step 38's area add ≤10 lines: how to see the Diagnostics button in a Release watch build (D-17706 a/b/c) and the phone `--dart-define` (d). **CAUTION: the doc is 52.7 KB today — already past the ~52 KB split band and 11 KB from the 64 KiB hard limit (`test/docs_indexing_contract_test.dart`).** Keep the delta minimal; a split into part pages is a separate, governor-owned task (see Open questions).
4. [ ] Residue sweep — grep `Diagnostics` across `lib/`, `ios/OmniTrain Watch App/`, `watch/watchos/Sources/` and paste the hit list into the evidence file: the only entry-point constructions are `ContentView.swift:558` (gated) and `settings_screen.dart:161` (null-gated); zero other readers of the gated representations remain; the recording sites (:162, :589, main.dart:363-366, :400) are listed as intentionally untouched.
5. [ ] Update the doc freshness lines of both edited docs to the reconciliation date and confirm `test/docs_indexing_contract_test.dart` stays green (no new doc, no index change in `docs/README.md`).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/settings_diagnostics_test.dart`; grep sweep pasted into `<plan-name>.evidence.md`.
**Predicted Files**: `docs/state_management/watch_diagnostics.md`, `docs/theme_and_settings.md`, `docs/watch-app-setup-and-qa.md`, `<plan-name>.evidence.md`. Nothing else.
**Phase 3 verification notes (Conductor, date):** —

## Files Affected (whole feature)

- `lib/core/constants/diagnostics_entry.dart` (NEW — the one phone constant, D-17702)
- `lib/main.dart` (one argument, :486)
- `test/diagnostics_entry_test.dart` (NEW), `test/diagnostics_wiring_source_test.dart`, `test/settings_diagnostics_test.dart`
- `ios/OmniTrain Watch App/DiagnosticsEntryPoint.swift` (NEW — the one watch gate, D-17703)
- `ios/OmniTrain Watch App/ContentView.swift` (:558)
- `ios/Runner.xcodeproj/project.pbxproj` (Profile config condition, D-17704)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSourceTests.swift` (S-14213 line update + new scans)
- `docs/state_management/watch_diagnostics.md`, `docs/theme_and_settings.md`, `docs/watch-app-setup-and-qa.md`

Readers that need NO change (verified by grep): `lib/features/settings/settings_screen.dart` (null already hides, :161), `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` (nil already hides, :248), `lib/core/navigation/` (no diagnostics route), `test/navigation_contract_enforcement_test.dart`, the recording suites (`test/diagnostics_log_test.dart`, `test/diagnostics_lifecycle_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`, `test/settings_diagnostics_watch_log_test.dart`), and the package's log/hook/store tests.

## Notes

- **Phase dependency graph:** Phase 1 (phone) and Phase 2 (watch) are
  independent; either may run first. Phase 3 needs both (it documents the
  finished rule). Phase 2's Done Criteria needs the governor for the two
  `xcodebuild` configuration checks; the implementer runs `swift-test` itself
  and asks the governor for the compile checks before claiming closure.
- **Predicted intermediate states:** after Phase 1 a release phone build hides
  the row while a debug build is unchanged; after Phase 2 a release watch build
  hides the button while Debug/Profile are unchanged; the old S-14213 assertion
  is RED between Phase 2 items 1 and 4 — that is the red-first state, and the
  package suite must NOT be left red overnight (items 1-6 land as one run).
- **Legacy handling:** none. No persisted field, no migration, no seed change.
- **What the owner's normal workflow sees:** an Xcode Debug run on both
  devices is unchanged (Debug defines DEBUG, `kDebugMode` true — both entries
  visible, both logs recording, both override paths dormant).

## Progress

- [x] Phase 1 (phone entry gate) — @developer — `test/diagnostics_entry_test.dart`,
      `test/diagnostics_wiring_source_test.dart` S-17702 and
      `test/settings_diagnostics_test.dart` S-17703 RED at HEAD, then green (14 passed);
      `lib/core/constants/diagnostics_entry.dart` created, `lib/main.dart` gated (M1/M2 mutations).
- [x] Phase 2 (watch app-target gate) — @developer — S-14213 updated + S-17704/S-17705/S-17707 added
      (10 tests, 3 red before GREEN); `DiagnosticsEntryPoint.swift`, the gated `ContentView` closure and
      the Profile condition in place (M3/M4 mutations); `swift-test` 1495 passed, 0 failed.
      The two `xcodebuild` configuration builds are the governor's (see evidence).
- [x] Phase 3 (docs) — @developer — "Entry point visibility" in
      `docs/state_management/watch_diagnostics.md`, the Settings sentence + freshness date in
      `docs/theme_and_settings.md`, 9 lines in `docs/watch-app-setup-and-qa.md` step 38;
      `test/docs_indexing_contract_test.dart` 13 passed; residue sweep in the evidence file.
- [ ] Review (evidence table, S-conformance, xcodebuild configs) — @code-reviewer

## Assumption Log

- A-17701 (Phase 2): chose `ProcessInfo` environment fallback in the gate's
  `#else` branch so the owner can reveal the button in a Release run from Xcode
  without editing `project.pbxproj`; options: build-setting-only override
  (rejected: needs a rebuild config edit every time) / runtime UserDefaults
  (rejected: a user could discover it). Conductor to RATIFY at review.
- A-17702 (Phase 3): `docs/watch-app-setup-and-qa.md` is 52.7 KB, past the
  ~52 KB split band; the plan keeps its delta ≤10 lines and defers the split to
  a separate task (Open questions). Conductor to RATIFY at review.
- A-17703 (Phase 1): `kDiagnosticsEntryVisible` is built from the testable
  predicate's inputs inline (`kOmnitrainDiagnosticsOverride || kDebugMode ||
  kProfileMode`) rather than calling `diagnosticsEntryVisibleFor`, because
  `kDebugMode`/`kProfileMode` are const and the call would not be. Option
  considered: one non-const `final` constant calling the predicate — rejected
  (the plan pins `const bool kDiagnosticsEntryVisible`, D-17702). Both read the
  same rule; S-17701 pins the predicate, S-17706 pins the constant.
- A-17704 (Phase 1): S-17706's verbatim scan matches the override line through
  a whitespace-collapsed `RegExp` (`const bool kOmnitrainDiagnosticsOverride =`
  followed by `bool.fromEnvironment(` and `'OMNITRAIN_DIAGNOSTICS'`) instead of
  one literal string, because the formatter wraps the declaration. The scan
  still fails if the environment key or the `fromEnvironment` read changes.

## Feedback

[empty]
