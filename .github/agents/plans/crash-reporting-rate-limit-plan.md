# Crash Reporting — Per-Signature Rate Limit

## Overview

OmniTrain currently forwards every error to Sentry with no ceiling. A single repeating failure recently produced ~15,000 reports from 24 users in 2 weeks, exhausting the monthly reporting budget and suppressing any genuine crash during that window. This change introduces a per-signature throttle that stops transmission past a configurable threshold and resumes after a cooldown, attaching the suppressed-occurrence count to the resumed report so high-frequency problems remain visible.

## Requirements

- Throttle applies **per failure signature** (not globally) — a noisy failure must never prevent an unrelated genuine failure from being reported.
- Threshold and cooldown are **named, configurable** values.
- Suppressed occurrences are counted **locally only** (not persisted across launches).
- After the cooldown elapses, the next transmission carries the **exact suppressed count** since the last transmission.
- Privacy contract: outgoing reports carry `appVersion`, `osVersion`, `deviceModel`, `errorContext`, plus the new `suppressedOccurrences` figure — nothing else.
- The wrapper still does no I/O / no report forwarding when `enabled: false` (debug/profile builds).
- `recordInfoSignal` is **not** throttled — those are low-severity signals explicitly excluded from the crash stream.

## Acceptance Criteria

- [x] A signature repeated beyond the threshold stops being transmitted; exactly `threshold` reports are sent.
- [x] Two distinct signatures throttle **independently**.
- [x] First report after cooldown carries a `suppressedOccurrences` count equal to the number dropped since the previous transmission.
- [x] Throttle state is reset on `resetForTests()` (does not survive a service reset).
- [x] A signature reported below the threshold is never throttled and never carries a `suppressedOccurrences` figure.
- [x] Threshold and cooldown are referenced from named configuration values; changing them changes observed behavior with no other edits.
- [x] Allow-list output: `appVersion`, `osVersion`, `deviceModel`, `errorContext`, `suppressedOccurrences` (when > 0).

## Scenarios

### S-001: Single signature stops at threshold
- Trigger: `recordError` called with the same `errorContext` N times where N > threshold
- Precondition: Bootstrap completed in release mode
- Flow: Each call invokes the rate limiter; first `threshold` calls return `(true, 0)`; subsequent calls return `(false, _)`
- Expected outcome: `reporter.capturedErrors.length == threshold`
- Edge case of: none

### S-002: Two distinct signatures throttle independently
- Trigger: `recordError` called for signature A and signature B both past threshold
- Precondition: Bootstrap completed in release mode
- Flow: Each signature has its own counter; throttling A does not affect B
- Expected outcome: Both signatures transmit `threshold` reports each; neither blocks the other
- Edge case of: none

### S-003: Cooldown resumes with suppressed count
- Trigger: Signature hits threshold, additional `K` occurrences are dropped, cooldown elapses, next occurrence arrives
- Precondition: Threshold reports already sent; K drops counted; clock advanced past cooldown
- Flow: Rate limiter returns `(true, K)` on the post-cooldown call
- Expected outcome: Transmitted report metadata includes `suppressedOccurrences == K`
- Edge case of: S-001

### S-004: Service reset clears throttle state
- Trigger: Throttle state reaches threshold; `resetForTests()` is called; same signature reported again
- Precondition: A signature has been throttled
- Flow: Reset clears internal counter map; next call starts from zero
- Expected outcome: New report is transmitted with `suppressedOccurrences` absent
- Edge case of: S-001

### S-005: Below-threshold traffic is unthrottled
- Trigger: `recordError` called fewer times than threshold
- Precondition: Bootstrap completed
- Flow: Every call returns `(true, 0)`; no `suppressedOccurrences` tag attached
- Expected outcome: All calls forwarded; no metadata key named `suppressedOccurrences` ever present
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes

1. **`lib/core/services/crash_reporting_service.dart`**
   - Add `CrashReportThrottleConfig` class with `threshold` (default `100`) and `cooldown` (default `15 minutes`). Bootstrap accepts an optional `throttleConfig` parameter.
   - Add private `_CrashReportRateLimiter` class with:
     - `consider(signature) -> ({bool shouldSend, int suppressedSinceLast})`
     - Injectable `DateTime Function() clock` for deterministic tests.
     - `reset()` method.
   - `recordError`: derive signature from `${error.runtimeType}|${errorContext ?? ''}`; consult limiter; if shouldSend, attach `suppressedOccurrences` to cleaned metadata when > 0.
   - `bootstrap`: instantiate the limiter; expose via `resetForTests()` so test reset clears throttle state too.
   - Add `'suppressedOccurrences'` to `_allowedTagKeys` so `beforeSend` keeps it.

2. **`lib/main.dart`**
   - No behavioral changes needed; default threshold/cooldown apply. (Optional: surface as `--dart-define` later.)

### Frontend Changes
None.

### Implementation Steps
1. Add TDD red tests for rate limiter scenarios.
2. Update existing `recordError allow-list` test that assumes unconditional forwarding (assert forwarding below threshold only).
3. Implement `_CrashReportRateLimiter` + `CrashReportThrottleConfig`.
4. Wire rate limiter into `recordError`; update `_allowedTagKeys`.
5. Update `resetForTests` to clear throttle state.
6. Run `flutter test` — confirm green.

## Iteration 2 (Re-verification prompt, 2026-08-03)

Re-prompted with the same Copilot prompt after the original implementation
landed in commit `d7655c6`. Re-running the pipeline as a verification pass:
no source edits required, the implementation is already in place. The
verification confirms (a) the rate-limit tests still pass, (b) `flutter
analyze` is clean, (c) all acceptance criteria are still met, and (d) the
docs under `.github/agents/docs/` describe the behaviour correctly (or,
where silent, do not assert anything false).

### DB Changes
None.

### Backend Changes
None (already implemented in `d7655c6`).

### Frontend Changes
None.

### Implementation Steps
1. Verify `lib/core/services/crash_reporting_service.dart` defines `CrashReportThrottleConfig` (threshold + cooldown, defaults `100` / `15min`).
2. Verify the private `_CrashReportRateLimiter` is wired into `recordError` with signature = `${runtimeType}|${errorContext ?? ''}`.
3. Verify `resetForTests` clears the rate limiter state.
4. Verify `'suppressedOccurrences'` is in `_allowedTagKeys`.
5. Re-run `test/crash_reporting_test.dart` rate-limit group — 5/5 pass.
6. Re-run `flutter analyze` on the three touched files — no issues.
7. Run Phase 3 code review against the implementation as it stands.

## Progress

- [x] Phase 0: Plan authored
- [x] Phase 1: Constants (in service file)
- [x] Phase 2.5: Red tests written and confirmed failing (5 compile errors)
- [x] Phase 2: Implementation
- [x] Phase 2: Green tests confirmed (16/16 crash_reporting_test; full suite: 2116 pass, 7 pre-existing failures in energy_tile_test.dart)
- [x] Phase 3: Code review
- [x] Iteration 2: Re-verification (no source changes; 5/5 rate-limit tests pass; analyze clean)

### Phase 2 Complete ✓

### Phase 3 Complete ✓

### Iteration 2 Verification Complete ✓

## Feedback

## Assumption Log

- **Signature derivation**: `${runtimeType}|${errorContext ?? ''}`. Runtime type groups same-class exceptions; errorContext groups call sites. The same exception type from different call sites yields distinct signatures — preferable since the fix surface differs.
- **Default threshold**: 100 occurrences per signature. Tuned to budget: at current Sentry plan, 100 reports × 24 users × N distinct signatures still leaves headroom.
- **Default cooldown**: 15 minutes. Short enough that the dashboard reflects regression within a quarter-hour; long enough that the budget is protected across a typical release cycle.
- **`recordInfoSignal` is not throttled** — those signals are explicitly low-severity / informational, already excluded from the crash stream.

### Phase 0 Complete ✓

---

# Iteration 3 — Pre-Release Gate Must Produce The Build It Guards

## Overview

Two defects slipped past `scripts/pre_release_check.sh`. First, the gate
verifies the build configuration text exists but never checks the
produced artifact for whether the Android notification protections
applied — leading to weeks-delayed symptom discovery. Second, the gate
inspects files rather than building them, so a configuration that could
not compile was approved. This iteration adds two checks to the
crash-reporting invariants section: one inspects the released AAB /
R8 output to verify the notification protections actually took effect;
the other attempts `flutter build appbundle --release` and fails loudly
on non-zero exit. Both share the same build invocation so the cost is
paid once.

## Requirements

- §11r (notification code protection) — after the release build runs,
  inspect the R8 output that records which `-keep` rules matched, and
  fail when the `com.dexterous.flutterlocalnotifications.**` keeps did
  not survive into the output.
- §11r (notification resource protection) — after the release build
  runs, inspect the produced AAB / APK for the raw sound resources
  `keep.xml` declares, and fail when they are absent.
- §11s (build attempt) — run `flutter build appbundle --release` (or
  `flutter build apk --release` as the local-fallback artifact), fail
  on non-zero exit, and surface the underlying error.
- Both §11r and §11s run regardless of `--fast` — they are not heavy
  by the script's definition; they are the actual gate.
- Both checks live alongside the existing crash-reporting invariants
  (§11k–§11q) and follow the same logging convention
  (`log_ok` / `log_err`).
- Each failure message names: expected condition, found condition,
  user-facing consequence.
- Missing build output → fail (per acceptance criterion: "passes by
  default when expected build output is missing entirely" is
  rejected).
- `--dart-define=SENTRY_DSN=...` is supplied to the build so the
  upload destination plumbing is exercised (matches production).

## Acceptance Criteria

- [x] Gate fails with non-zero exit when the release build output
      shows the notification `flutter_local_notifications` code
      protection did not apply.
- [x] Gate passes when the code protection did apply (post-fix state
      of `proguard-rules.pro`).
- [x] Gate fails when the `keep.xml`-declared raw resources are not
      found in the produced artifact.
- [x] Gate fails when the release build cannot be produced and
      surfaces the underlying build error rather than masking it.
- [x] Failure messages name the expected condition, the found
      condition, and the user-facing consequence.
- [x] Both checks run for release builds; they do not fire when only
      a debug / profile build exists in the output tree.
- [x] The gate fails rather than passing by default when expected
      build output is missing entirely.
- [x] Both checks live alongside §11k–§11q crash-reporting invariants
      and follow the same `log_ok` / `log_err` convention.

## Scenarios

### S-001: Notification code protection present (green)

- Trigger: Pre-release gate runs against a release build that includes
  the post-fix `proguard-rules.pro` keeping
  `com.dexterous.flutterlocalnotifications.**` classes.
- Precondition: Release build has run successfully; `seeds.txt`
  exists at `android/app/build/outputs/mapping/release/seeds.txt`.
- Flow: Gate greps seeds.txt for
  `com.dexterous.flutterlocalnotifications`; the classes are listed.
- Expected outcome: §11r reports OK; gate passes for this check.
- Edge case of: none

### S-002: Notification code protection absent (red)

- Trigger: Pre-release gate runs after a release build where
  `proguard-rules.pro` was missing the
  `com.dexterous.flutterlocalnotifications.**` keeps.
- Precondition: Release build run; seeds.txt exists.
- Flow: Gate greps seeds.txt for the kept classes; not found.
- Expected outcome: Gate fails with message naming expected classes,
  found absent, and the consequence (every notification schedule call
  throws at runtime, generating a crash-reporting flood).
- Edge case of: S-001

### S-003: Notification resource protection present (green)

- Trigger: Pre-release gate runs against a release build where
  `keep.xml` declares `@raw/boxing_bell,...` and the AAB / APK
  contains those resources.
- Precondition: Release build run; AAB exists at
  `build/app/outputs/bundle/release/app-release.aab` (or APK
  fallback).
- Flow: Gate unzips the AAB and checks for the raw resources.
- Expected outcome: §11r reports OK for resources; gate passes.
- Edge case of: none

### S-004: Notification resource protection absent (red)

- Trigger: Pre-release gate runs after a release build where the raw
  resources are absent from the AAB (e.g. `keep.xml` was stripped).
- Precondition: Release build run; AAB exists.
- Flow: Gate unzips the AAB; raw resources are absent.
- Expected outcome: Gate fails with message naming expected
  resources, found missing, and the consequence (notification
  scheduling throws `PlatformException(invalid_sound)` for every
  timer alert, in active workouts).
- Edge case of: S-003

### S-005: Build attempt succeeds (green)

- Trigger: Pre-release gate runs and invokes
  `flutter build appbundle --release`.
- Precondition: flutter on PATH; configuration compiles.
- Flow: Build exits 0.
- Expected outcome: §11s reports OK; gate continues.
- Edge case of: none

### S-006: Build attempt fails (red)

- Trigger: Pre-release gate runs and invokes
  `flutter build appbundle --release`.
- Precondition: flutter on PATH; configuration does NOT compile
  (e.g. a broken `proguard-rules.pro` line).
- Flow: Build exits non-zero; gate captures stderr.
- Expected outcome: Gate exits 1 and the underlying error text
  appears in the gate output (not masked by the wrapper).
- Edge case of: S-005

### S-007: Build output missing (red, not green)

- Trigger: Pre-release gate runs but the release build directory is
  empty / not produced.
- Precondition: §11s reported build succeeded but the artifact path is
  not present.
- Flow: §11r finds no `seeds.txt` and no AAB.
- Expected outcome: Gate fails — never silently passes because
  outputs are absent.
- Edge case of: none

### S-008: Debug-only build present

- Trigger: Only `flutter build apk --debug` was run; no release
  artifacts exist.
- Precondition: Debug build present, no release AAB/APK.
- Flow: §11s attempts release build; if it fails or output missing
  → red.
- Expected outcome: Gate fails for the same reason as S-007 — a
  debug build is not an acceptable substitute.
- Edge case of: S-007

## Iteration 1

### DB Changes
None.

### Backend Changes

1. **`scripts/pre_release_check.sh`**
   - Add §11r (notification protections verified against built
     artifact). Runs only after `flutter build appbundle --release`
     completes successfully (§11s). Inspects:
     - `android/app/build/outputs/mapping/release/seeds.txt` for the
       kept `com.dexterous.flutterlocalnotifications.**` classes.
     - The AAB / APK (whichever exists) for `@raw/<sound>` entries
       declared in `keep.xml`.
   - Add §11s (release build must succeed). Invokes
     `flutter build appbundle --release
     --dart-define=SENTRY_DSN=development` (or, when no
     `app-release.aab` would result from a missing AAB config, the
     APK fallback `flutter build apk --release
     --dart-define=SENTRY_DSN=development`). Fails on non-zero exit
     and prints the last 40 lines of the captured stderr.
   - Both checks are NOT skipped by `--fast`.
   - Both follow `log_ok` / `log_err` convention, with the failure
     message naming the expected condition, the found condition,
     and the user-facing consequence.

### Frontend Changes
None.

### Implementation Steps
1. Add a Dart test (`test/pre_release_gate_notification_and_build_test.dart`)
   mirroring `test/pre_release_gate_upload_destination_test.dart`
   patterns: copy repo into temp, run gate with `--fast` so the
   existing flutter analyze + flutter test legs are skipped (those
   are slow and irrelevant to the new invariants), but the new
   build + artifact checks run. The test injects:
     - a fake `seeds.txt` for the green case.
     - a `seeds.txt` missing the kept classes for the red case.
     - a fake APK with the raw resources for the green case.
     - a fake APK without the raw resources for the red case.
     - a build wrapper that returns 0 (green) or non-zero (red).
2. Add §11r + §11s to `scripts/pre_release_check.sh`, factoring the
   shared build invocation into a helper function so a single build
   produces output consumed by both checks.
3. Run `flutter test test/pre_release_gate_notification_and_build_test.dart`
   and confirm green.
4. Run `flutter test` (whole suite) and confirm no regression.

## Progress

- [x] Phase 0: Plan authored
- [x] Phase 1: Constants (in service file)
- [x] Phase 2.5: Red tests written and confirmed failing (5 compile errors)
- [x] Phase 2: Implementation
- [x] Phase 2: Green tests confirmed (16/16 crash_reporting_test; full suite: 2116 pass, 7 pre-existing failures in energy_tile_test.dart)
- [x] Phase 3: Code review
- [x] Iteration 2: Re-verification (no source changes; 5/5 rate-limit tests pass; analyze clean)
- [x] Iteration 3.0: Plan authored (§11r + §11s)
- [x] Iteration 3.1: Red tests written (8 tests; 7 red, 1 green-by-accident before impl)
- [x] Iteration 3.2: §11s (release build) + §11r (notification protections) implemented in pre_release_check.sh
- [x] Iteration 3.3: Tests green — 8/8 new tests pass; existing 9/9 Sentry upload-destination tests still pass; combined run 17/17; `flutter analyze` clean on the new test file
- [x] Iteration 3.4: Phase 3 code review — APPROVED; one non-blocking 🟡 WARNING on duplicated "expected build output is missing" branch between §11r (a) and (b); deliberately deferred (helper extraction would lose message clarity); dead-code helper methods removed during review

### Iteration 3 Phase 0 Complete ✓

### Iteration 3 Phase 1/2 Complete ✓

### Iteration 3 Phase 3 Complete ✓

---

## Iteration 3 Code Review — APPROVED verdict

**Layers in scope:** scripts (gate), test (gate tests). **Layers skipped:** lib/, docs, models, repositories, state, features, widgets, core.

**Acceptance criteria:** all 7 met (see table in plan file iteration block).

**Scenario coverage:** all 8 scenarios mapped 1:1 to passing tests; S-008 is implicit via S-007.

**Architecture / buttons / env-safety:** N/A — bash + Dart test, no `lib/` modified.

**Test run:** 17/17 green (8 new + 9 Sentry upload-destination). `flutter analyze`: clean.

**Files changed:**
- [scripts/pre_release_check.sh](scripts/pre_release_check.sh) — added §11r (notification protections verified against built artifact) + §11s (release build must succeed) inside the existing crash-reporting-invariants section.
- [test/pre_release_gate_notification_and_build_test.dart](test/pre_release_gate_notification_and_build_test.dart) — new test file, 8 tests, mirrors `pre_release_gate_upload_destination_test.dart` patterns, uses `PRE_RELEASE_GATE_FAKE_BUILD` test-only hook so CI does not pay the real `flutter build` cost.

**Findings:**
- `🟡 WARNING | scripts/pre_release_check.sh:574 & 588` — duplicated "expected build output is missing" branch in §11r (a) and (b). Accepted; helper extraction would lose message clarity. Re-evaluate when a third subcheck lands.

---

## Iteration 4 (Re-verification prompt, 2026-08-04)

Re-prompted with the same Copilot prompt. The implementation is already
in place from Iteration 3 (commit `d7655c6`). This pass re-runs the
verification leg only: the tests must still be green, the docs must
describe the behaviour, and nothing in the gate or its tests has
drifted since the last review.

### DB Changes
None.

### Backend Changes
None (no source edits; only a documentation completeness fix noted
under Phase 3 below).

### Frontend Changes
None.

### Implementation Steps
1. Run `flutter test test/pre_release_gate_notification_and_build_test.dart` — confirm 8/8 pass.
2. Run `flutter test test/pre_release_gate_upload_destination_test.dart` — confirm 9/9 pass (combined 17/17).
3. Run `flutter analyze` on the touched files — confirm clean.
4. Re-run Phase 3 (focused on docs falsification per Step 3.4).

## Progress

- [x] Phase 0: Plan authored
- [x] Phase 1: Constants (in service file)
- [x] Phase 2.5: Red tests written and confirmed failing (5 compile errors)
- [x] Phase 2: Implementation
- [x] Phase 2: Green tests confirmed (16/16 crash_reporting_test; full suite: 2116 pass, 7 pre-existing failures in energy_tile_test.dart)
- [x] Phase 3: Code review
- [x] Iteration 2: Re-verification (no source changes; 5/5 rate-limit tests pass; analyze clean)
- [x] Iteration 3.0: Plan authored (§11r + §11s)
- [x] Iteration 3.1: Red tests written (8 tests; 7 red, 1 green-by-accident before impl)
- [x] Iteration 3.2: §11s (release build) + §11r (notification protections) implemented in pre_release_check.sh
- [x] Iteration 3.3: Tests green — 8/8 new tests pass; existing 9/9 Sentry upload-destination tests still pass; combined run 17/17; `flutter analyze` clean on the new test file
- [x] Iteration 3.4: Phase 3 code review — APPROVED; one non-blocking 🟡 WARNING on duplicated "expected build output is missing" branch between §11r (a) and (b); deliberately deferred (helper extraction would lose message clarity); dead-code helper methods removed during review
- [x] Iteration 4.1: Tests green — re-verified 8/8 §11r/§11s + 9/9 upload-destination = 17/17
- [x] Iteration 4.2: `flutter analyze` clean on gate script, test file, and updated doc
- [x] Iteration 4.3: Phase 3 doc-falsification re-check — caught one 🟡 WARNING on services_and_utils.md (silent about §11r/§11s after the addition); fixed by extending the gate-description paragraph in Iteration 3's already-passing prose so it now names §11k–§11q + §11r/§11s and points at both test files

### Iteration 3 Phase 0 Complete ✓

### Iteration 3 Phase 1/2 Complete ✓

### Iteration 3 Phase 3 Complete ✓

### Iteration 4 Re-verification Complete ✓

---

## Iteration 4 Code Review — APPROVED verdict

**Layers in scope:** docs (`.github/agents/docs/state_management/services_and_utils.md`).
**Layers skipped:** lib/, scripts/, test/, models, repositories, state, features, widgets, core.

**Acceptance criteria:** all 7 still met (no regression).

**Scenario coverage:** 8/8 scenarios still mapped 1:1 to passing tests.

**Test run:** 17/17 green. `flutter analyze`: clean on gate script, test file, and the updated doc paragraph.

**Files changed (this iteration):**
- [`.github/agents/docs/state_management/services_and_utils.md`](.github/agents/docs/state_management/services_and_utils.md) — extended the gate-description paragraph (line 30) to name §11r / §11s and the second test file. Fixes a 🟡 WARNING from Step 3.4 doc-falsification re-check: the previous prose was accurate but silent about the §11r / §11s addition, which a future reader would have hit as a stale description.

**Findings:**
- `🟡 WARNING | .github/agents/docs/state_management/services_and_utils.md:30` (now resolved) — prose was silent about §11r / §11s after the Iteration 3 addition. Replaced with a single paragraph that names §11k–§11q + §11r / §11s and points at both test files. No remaining doc falsifications.

**PIPELINE COMPLETE — Implementation and review delivered. Ready to merge.**

**PIPELINE COMPLETE — Implementation and review delivered. Ready to merge.**

## Assumption Log

- **Notification-protection contract**: §11r verifies the two protections
  in place for `flutter_local_notifications`: (a) ProGuard `-keep` rules
  in `proguard-rules.pro` keep the plugin's classes (otherwise R8
  strips the Gson `TypeToken` generic and breaks the schedule /
  cancel hot paths — see
  `flutter_local_notifications #2014`); (b) `keep.xml` keeps the raw
  sound resources used for the rest-timer alert notification (otherwise
  `RawResourceAndroidNotificationSound(soundId)` throws
  `PlatformException(invalid_sound, …)` on every Android schedule
  call). Both protections are exercised by real users; both should fail
  the gate when missing.
- **Code-protection signal**: R8's `seeds.txt` records every class
  matched by a `-keep` rule. Its presence in
  `android/app/build/outputs/mapping/release/seeds.txt` after a
  successful release build is the canonical "rule took effect"
  signal. The file is text; greppable; produces deterministic output.
- **Resource-protection signal**: The `keep.xml`-listed `@raw/*`
  resources must survive into the produced AAB. `unzip -l <aab>` lists
  the entries; the names are stable across build configurations.
- **Build artifact**: `flutter build appbundle --release` produces
  `build/app/outputs/bundle/release/app-release.aab`. The AAB contains
  the resources. The fallback `flutter build apk --release` produces
  `build/app/outputs/flutter-apk/app-release.apk`; either is
  acceptable. §11r accepts whichever exists; both checks run after the
  same build invocation completes.
- **`--dart-define=SENTRY_DSN` for the build**: A literal string
  `development` is used so the build exercises the upload plumbing
  without needing the real secret. The DSG gate does not depend on
  this — it is purely to make the build mirror production in shape.
- **Build cost**: ~3–5 minutes on a warm cache for a first
  `appbundle`. The gate rarely runs (pre-TestFlight / pre-Play).
  That is the correct trade — the alternative is silent failure
  at user-runtime.
- **`--fast` does NOT skip §11r / §11s**: These are not metadata
  inspections; they are the actual gate. `--fast` only skips
  `flutter analyze` + `flutter test` (the long-tail code-gate legs).
- **"PASSES BY DEFAULT WHEN OUTPUT IS MISSING" is rejected**: §11r
  treats absent `seeds.txt` or absent AAB/APK as a failure (not as an
  "OK"). This is the load-bearing acceptance criterion.

### Iteration 3 Phase 0 Complete ✓

---

# Iteration 5 — Coverage Gap Investigation (no code changes)

## Overview

The per-signature rate-limit ceiling introduced in Iteration 1 lives
inside `CrashReportingService.recordError`, which is fed by the
two framework-level error sinks installed at bootstrap time
(`FlutterError.onError`, `PlatformDispatcher.instance.onError`) and
by explicit `recordError` calls from app code. The recent incident
that motivated the ceiling was a failure captured directly by the
Sentry SDK's platform-level integration (the native Android / iOS
pipeline); that failure never travelled the Dart `recordError` path.

This iteration investigates — **without changing any source code** —
whether the ceiling can see failures that arrive via the SDK's
platform-level integration, and records a definitive answer plus a
recommended standing policy for the gap (if any).

## Verdict

**CONFIRMED.** The per-signature ceiling does **NOT** cover
platform-originated failures. A failure captured by the SDK's
native-level integration (a JVM crash on Android, a native exception
on iOS, an ANR on Android) is serialised to an envelope and sent
to Sentry's server entirely inside the native SDK pipeline — it
never enters the Flutter Dart `Sentry.captureEvent` pipeline, so the
`beforeSend` callback set on `SentryFlutterOptions` is never
invoked for it, and so the rate limiter (which is consulted only
inside `CrashReportingService.recordError`) is never asked.

The doc string at `lib/core/services/crash_reporting_service.dart:377`
already acknowledges this property in passing — "every event —
including platform-originated failures that bypass recordError" —
but does not draw the rate-limit conclusion. That conclusion is
recorded here so the gap is no longer implicit.

## Files involved

- [`lib/core/services/crash_reporting_service.dart`](lib/core/services/crash_reporting_service.dart)
  - Lines 174–217: `recordError` — the only consumer of
    `_CrashReportRateLimiter.consider(...)`. The limiter cannot be
    reached without going through this function.
  - Lines 256–272: `_installErrorSinks` — installs
    `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
    Both forward into `recordError`.
  - Lines 360–366: `options.beforeSend` — applies the
    allow-list-only filter. **Does not** consult the rate limiter.
- Sentry SDK (pinned at `sentry_flutter: ^9.24.0` per
  [`pubspec.yaml:55`](pubspec.yaml)):
  - `~/.pub-cache/hosted/pub.dev/sentry_flutter-9.24.0/lib/src/sentry_flutter_options.dart:52` —
    `enableNativeCrashHandling = true` is the SDK default. The
    OmniTrain init does not override this, so native crash capture
    is **enabled**.
  - `~/.pub-cache/hosted/pub.dev/sentry_flutter-9.24.0/lib/src/native/java/android_core_worker.dart:506-515` —
    `_captureEnvelope` calls
    `native.InternalSentrySdk.captureEnvelope(...)`, which is a JNI
    call into `io.sentry.android.core.InternalSentrySdk.captureEnvelope`
    on the Java side. The envelope is processed by `sentry-android-core`
    in Java/Kotlin and dispatched directly to Sentry's server,
    bypassing the Flutter Dart `SentryClient.captureEvent` pipeline.
  - `~/.pub-cache/hosted/pub.dev/sentry_flutter-9.24.0/lib/src/native/cocoa/binding.dart:29968,71420-71422` —
    iOS analog: `SentryCocoa.captureEnvelope_(envelope)` calls into
    `sentry-cocoa`'s native Obj-C / Swift pipeline; same bypass.
- Sentry's Dart client (`~/.pub-cache/hosted/pub.dev/sentry-9.24.0/lib/src/sentry_client.dart:107-180`):
  - `captureEvent(...)` invokes `_runBeforeSend(...)` after
    event-processors run. The Flutter-side `beforeSend` is invoked
    only when an event flows through `Sentry.captureEvent` /
    `Sentry.captureMessage` / `Sentry.captureException`. Native
    envelopes skip this path entirely.

## Reasoning

1. **Where the rate limiter lives**: `_CrashReportRateLimiter` is a
   private field on `CrashReportingService._instance`. The only call
   site is inside `recordError` (`crash_reporting_service.dart:184`):
   `final decision = svc._rateLimiter.consider(signature);`.
2. **What feeds `recordError`**: only three sources — explicit
   `recordError` calls from app code, `FlutterError.onError`
   (framework errors that originate in Dart), and
   `PlatformDispatcher.instance.onError` (uncaught async Dart
   errors). All three are Dart-side.
3. **What feeds the SDK's native pipeline directly**: JVM crashes,
   native iOS exceptions, and Android ANRs. The SDK's
   `sentry-android-core` and `sentry-cocoa` libraries capture these
   natively and serialise them to Sentry envelopes; the envelopes
   are dispatched by the native SDK and do not pass through the
   Flutter Dart `SentryClient`.
4. **What `beforeSend` actually intercepts**: only events generated
   by the Dart SDK (via `Sentry.captureEvent` /
   `Sentry.captureMessage` / `Sentry.captureException`). It does not
   see native-envelope events; therefore our allow-list filter
   applies only to Dart-side events too, but at least it runs.
   The rate limiter does not run inside `beforeSend`, so even for
   the events it does see, the rate limit is enforced only at the
   `recordError` call site — i.e., never.

The architecture is correct for the SDK's design: native crashes
must be captured natively because Dart code is not running when
they occur. The ceiling's gap is a consequence of the platform
boundary, not a wiring bug in `CrashReportingService`.

## Interception — possible or not?

**Not possible from within the app**, given how the SDK routes
platform-captured reports:

- **Cannot move the limiter into `beforeSend`**. `beforeSend` is a
  Dart-side callback; the SDK only invokes it for events that flow
  through `SentryClient.captureEvent`. Native envelopes skip this
  pipeline, so `beforeSend` cannot see them.
- **Cannot disable native capture and re-capture from Dart**. A
  JVM crash or a native iOS exception is not visible to Dart code
  at all — there is no Dart error sink that fires on a native
  crash. Disabling native crash capture (`enableNativeCrashHandling
  = false`) would simply mean those failures are never reported.
- **Cannot intercept at the platform channel layer**. The native
  SDK owns its own transport; the Flutter side does not see the
  envelope until after the native side has already serialised and
  dispatched it. There is no channel-level hook that fires before
  dispatch.

The SDK does provide a way to limit server-side ingestion (project
settings → Inbound Filters → Rate Limiting), but that is a Sentry
project configuration, not an in-app change.

## Recommended standing operational response

For a future platform-side flood, the standing response is — in
priority order:

1. **Sentry project inbound rate limits** (preferred).
   Configure per-issue or per-project rate limits in the Sentry
   project's Inbound Filters. This applies server-side, sees every
   event (including native envelopes and any future integration),
   and takes effect immediately. The threshold / cooldown is set
   once in the project settings and is not subject to app release
   cadence. Practical cost: ~10 minutes of project-config work in
   Sentry's web UI; no app release required.

2. **Sentry alert + manual DSN rotation** (fallback). When the
   rate-limit approach is not enough (e.g. the budget is being
   burned before the rate-limit can be observed), rotate the
   project DSN: generate a new DSN in Sentry, ship a hotfix that
   points `--dart-define=SENTRY_DSN=<new>` at the new value, and
   let the old DSN age out. Practical cost:
   - **iOS**: App Store urgent-build review is ~24 hours (fast
     track under expedited review); users on older builds continue
     to flood until they update.
   - **Android**: Play Store urgent-build rollout can land in
     hours; users on older builds continue to flood until they
     update.
   - **Both**: until the rollout reaches >95% of the active
     user base, the flood on the old DSN continues. The old DSN
     must remain valid for that window, so the project still
     incurs the rate of events from old builds.

3. **Disable native crash capture** (last resort, NOT recommended).
   Setting `enableNativeCrashHandling = false` would silently
   stop reporting JVM / native iOS / ANR events — trading budget
   protection for visibility. This is the wrong trade for the
   current product.

## Acceptance Criteria

- [x] Verdict on whether the ceiling covers platform-originated
      failures: **CONFIRMED — does NOT cover**.
- [x] Files involved named with line refs.
- [x] Whether interception is possible from within the app stated:
      **NO** — not without disabling native crash capture entirely.
- [x] Recommended standing operational response stated, including
      its practical cost.
- [x] No source files modified.

## Unit Tests Required

**None for this item** — no code change. The Copilot prompt
explicitly states the follow-up work (a separate item) should
include a test that asserts the known gap explicitly so it is
documented in the suite rather than only in this report. The
proposed test would, at minimum:

- Confirm that `recordError` consults the rate limiter.
- Confirm that `options.beforeSend` does NOT consult the rate
  limiter (only the allow-list).
- Confirm that `enableNativeCrashHandling` remains at the SDK
  default (`true`) — any future change to `false` should fail
  the test with a message naming the visibility trade-off.

These are out of scope for this investigation but recorded here
so the follow-up item has a concrete starting shape.

## Progress

- [x] Investigation executed — verdict CONFIRMED, files named,
      interception impossibility established, operational response
      documented with practical cost.
- [x] No source files modified (`git status` clean for `lib/` and
      `test/` after this iteration).

### Iteration 5 Investigation Complete ✓

---

## Iteration 5 Summary

| Question | Answer |
|---|---|
| Does the rate-limit ceiling cover platform-originated failures? | **No — CONFIRMED** |
| Is interception possible from within the app? | **No** — not without losing native crash visibility |
| Standing operational response to a future platform-side flood | Sentry inbound rate limits (project config); DSN rotation as fallback |
| Practical cost of DSN rotation | iOS ~24h expedited review; Android hours; old builds continue to flood until rollout reaches ~95% |
| Source files modified | **None** |

**PIPELINE COMPLETE — Investigation delivered. No code change required.**
The follow-up item (test asserting the known gap) is a separate
ticket.
