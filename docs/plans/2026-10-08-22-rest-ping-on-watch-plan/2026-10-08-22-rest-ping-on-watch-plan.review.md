# Code Review — plan 22 (rest ping on the watch: contract + phone + Apple Watch)

Base commit: 53f3f2be2e00f8ef8facc1c068ac5626bdfcb46e. Work uncommitted on the tree.
Scope: Phases 1–2 only. Phase 3 shipped as plan 22b — its absence is not a finding.

## Scope (step 0)

Layers in scope: sync contract (`watch/sync_protocol/`), state (`lib/state/watch/`), core utils
(`lib/core/utils/watch_reference_sync.dart`), watch client (`watch/watchos/`), app target
(`ios/OmniTrain Watch App/ContentView.swift`), tests.
Layers skipped: models, persistence (both `WorkoutRepository` impls untouched), components.

## Findings

Severity is the plan's vocabulary (blocker / major / minor) with the pipeline's word in brackets.

1. **blocker / major [CRITICAL]** — `docs/theme_and_settings.md:9` — the bullet says "the wrist owes no
   alert for a rest at all", which the shipped wrist ping falsifies: the wrist now taps at each multiple of
   the interval while its own rest is open. A false claim about the current product is a rejection (4d),
   and it lands on `main` when this PR merges, not when 22b merges. **Fix:** delete the "wrist owes no
   alert at all" clause in this PR — do not reword it into a corrected sentence — and leave the wrist
   half to 22b's D-263, which will add the pointer to
   `watch/watchos/Tests/WatchSessionEngineTests/WatchRestPingTests.swift` (the failing test for a rest
   length, countdown or alarm is `test/rest_is_count_up_contract_test.dart`). If the governor prefers one
   fewer round, advance 22b Phase 1 item 6's `theme_and_settings.md` half into this PR instead. → @developer
2. **minor [WARNING]** — `docs/rest_tracking.md:12` — the rule paragraph and the ping sentence are true but
   silent on the wrist's half of the ping, which now exists. Incomplete, not false → no action here; 22b
   D-263 owns the reword.
3. **minor [WARNING]** — `docs/global_conventions.md:17` — the "Rest rule: rest is a count-up" row still
   reads "no rest alarm anywhere, on any device" without naming the rest ping as the one allowed cue, so a
   reader cannot tell whether the shipped wrist tap is permitted. Defensible under the project's meaning of
   "alarm" and scheduled by D-240/D-263 → no action here; 22b owns it.
4. **minor [WARNING]** — `docs/state_management/watch_surface.md:436-437` — the rest-surface paragraph
   ("a rest with no length, which the rest screen counts up") is still true but says nothing about the ping
   the screen now fires. Incomplete → 22b Phase 1 item 7 owns it (remove before adding).
5. **minor [WARNING]** — `docs/state_management/watch_surface.md:3` — the scope block lists
   `lib/state/watch/` and `lib/core/sync_protocol/` but not `lib/core/utils/`, yet the document owns
   `WatchReferenceSync` (`lib/core/utils/watch_reference_sync.dart`, documented at `:263`, changed by this
   PR). An under-claiming scope block hides a document from 4d's mapping → add
   `lib/core/utils/watch_reference_sync.dart` to the scope line (fold into 22b's edit of this file, which is
   already open for its size trim). → @developer
6. **minor [WARNING]** — `docs/plans/2026-10-08-22-rest-ping-on-watch-plan/...-plan.md` §Existing-Functionality
   Impact row 1 — the reader list omits two contract files that also carry the field:
   `watch/contract/watch_effort_rating_contract.json` (`preferencesField: effortRatingPrompt`) and
   `watch/contract/watch_capture_contract.json` (four `preferences` ops). No surface is unguarded — the
   tests that read both (`WatchCaptureContractTests.swift`, `test/watch_capture_contract_conformance_test.dart`,
   both listed) are green — so this is a stale list, not an unlisted reader. → @developer (one-line row fix)
7. **minor [WARNING]** — `test/rest_ping_contract_test.dart:12-17` — the header says "two of its rows are not
   the phone's to judge — S-243's gap and S-222", but four rows are never driven through
   `shouldFireRestPing`: S-242 (Off) and S-244 (mid-rest lowering) are phone-compatible and simply not
   asserted. Restating the count is the cheap fix; driving S-242 and S-244 through `_phoneTaps` (both match
   the table today) turns the parity claim into a guard. → @developer
8. **minor [SUGGEST]** — `watch/watchos/Sources/WatchSessionEngine/WatchPhonePreferences.swift` ·
   `wholeSeconds()` — a JSON `90.0` is refused on the wrist while the schema's `integer` type and the Dart
   validator accept it (JSON Schema counts a zero fraction as an integer). Fails closed and unreachable from
   this phone, which sends an `int` — but the two validators now disagree on a payload no fixture pins.
   **Fix:** one clause in the `PROTOCOL.md` bullet ("the wrist refuses a fractional value") or a fixture
   both stacks refuse. → @developer

### Verified, no finding

- `boundary > 0` is an equivalent mutant (`lastPinged` starts at 0), correctly recorded as such in the
  evidence rather than claimed as a proved guard; the live clause `boundary > lastPinged` is what the S-243
  and S-244 tests pin.
- The Dart contract test cannot be red at the base commit by assertion (the named parameter does not exist),
  which the evidence states and covers with the mutation table instead. The fixture guard *was* proved red at
  base by real assertion failures.
- `WatchTimerHaptics.poll` and `testS164ARestIsNeverOwedAnAlert` are untouched; `rest_is_count_up_contract_test.dart`
  is green; no stored rest length, planned rest or countdown was added anywhere.

## Behavioral verification

**4a Acceptance criteria** — 1 (one setting, `SettingsState.restPingInterval`, no watch-side setting:
`WatchRestView` gained no control), 2 (schema + both validators + fixtures + the wrist's store, newest copy
wins), 3 (taps at multiples, never closed, never Off/unknown, once per poll after a gap), 6 (baselines) all
met. 4 and 5 are 22b's by the plan's split.

**4b Scenario register** — S-241 (2 tests), S-242 (2), S-243, S-244 (2), S-245, S-221, S-222 (both table
rows), S-223, S-224, S-225, S-247 (3) in `WatchRestPingTests.swift`; S-246 and S-248 in
`test/rest_ping_contract_test.dart`. Each asserts the scenario's stated outcome from the contract table
itself (`RestPingTable.load`/`drive`), so the fixture is the one the scenario enumerates — including the
`beforeFirstSync` Off ticks in front of S-222's first poll. No scenario without a conformant test.

**4c Test run** — `.github/copilot/scripts/macos/gateway.sh test` (7 files: `rest_ping_contract_test`,
`watch_reference_sync_test`, `watch_transport_test`, `sync_protocol_fixtures_test`,
`watch_capture_contract_conformance_test`, `rest_is_count_up_contract_test`,
`docs_indexing_contract_test`) → **175 passed, 0 failed**. Governor's full run, pasted from the brief:
flutter test `+4163 ~1` all passed; `swift-test` 376 / 0; `flutter analyze` 196 issues (baseline);
`xcodebuild "OmniTrain Watch App"` BUILD SUCCEEDED. The full suite was not re-run, per the brief.

**4d Documentation falsification** — implicated docs derived from the changed files:
`theme_and_settings.md` (❌ false, finding 1), `rest_tracking.md`, `global_conventions.md`,
`state_management/watch_surface.md`, `watch_session_sync.md` (checked: its "the first fetch on a fresh watch
(routines, preferences and the food catalog)" names message families, not fields → still true), and
`watch/sync_protocol/PROTOCOL.md` (updated in step with the schema). `watch-app-setup-and-qa.md`'s rest
steps and citations (`testS161…`, `testS162…`, `testS164A…`) were re-checked and still exist. Cited tests
looked up by exact group and name: `testS161TheRestElapsedCountsUpAndSurvivesARelaunch`,
`testS162NextEndsTheRestAtTheTapInstant`, `testS164ARestIsNeverOwedAnAlert` — all present.

**4e Documentation standard** — the only documentation prose added is the `PROTOCOL.md` bullet. It states a
wire field's requiredness and semantic (`0` for Off) and points at the contract table and the test, matching
its neighbours, which are the protocol's own vocabulary rather than the four permitted categories of a
`docs/` page. No visual values, no control inventory, no copied code, no roadmap, no numeric default copied
from a constant (`0` is the wire's Off, not a settings value). PASS.

**4g Impact check** — all five rows re-grepped. Row 1's grep reproduces; its reader list misses the two
contract JSONs (finding 6). Row 2's manifest walk reproduces (the three new invalid fixtures each carry
`expectedCode` + `expectedReasonContains`). Row 3's `restPingInterval` readers are unchanged, with the
handler added alongside them. Row 4's `WatchHaptics` conformers: `WristHaptics`, `RecordingHaptics` moved in
Phase 2; the three Dart ones are 22b's, and the Dart interface is a separate type so nothing breaks. Row 5's
`WatchRestView(` has exactly one construction site, `ContentView.swift:186`, and it passes the interval as a
closure. No unlisted reader of a touched surface was found.

## Answer to the brief's side-effect question

`let _ = pingIfOwed()` inside the `TimelineView` closure is safe. `WatchRestPing` is a `final class` held in
`@State`, so the tick mutates it in place without writing view state, and the rule is idempotent per
boundary — a repeated body evaluation sees `boundary == lastPinged` and returns false, so it cannot tap
twice per boundary. A tick that never ran (screen off, no re-render) is caught up by the boundary form on
the next evaluation, so it cannot silently skip a boundary either. The one residual is a *fresh*
`@State` mid-rest (a view-identity change, or a relaunch of a session whose rest is still open): it re-taps
the current boundary once. That fails open, matches the catch-up rule, and is not worth code.

## Conventions (`docs/global_conventions.md`)

PASS (7 rules): units + canonical storage (seconds both sides, no unit label, no conversion); theme tokens
only (no styling added); timestamps are source data (the ping derives from the persisted row's elapsed, not
a counter); reuse the canonical owner (the interval comes from `SettingsState`, the rule from one place per
platform over one shared table, and the wrist keeps no setting of its own); instrument panel (a single
light tap, restrained); no state notification during the build phase (no Dart widget touched —
`initstate_notify_contract_test.dart` scans `lib/features`); rest rule: rest is a count-up
(`rest_is_count_up_contract_test.dart` green, no length/countdown/alarm added).
N/A (2 rules): card chrome via `OmniSurface`/`OmniCardHeader` and effort-kind drives analytics — no card and
no analytics code touched.
FAIL (0).

## Assumption Log adjudication

- **RATIFY** (A1, D-250): the formula governs a boundary that fell before the interval arrived. The two
  S-222 rows encode both readings and `testS222TheIntervalArrivingMidRestTapsFromItsNextBoundary` drives
  both — no silent guess, and the reading is now pinned by the table. Promote is already done.
- **RATIFY** (A2, D-253): `restPingSeconds` does not trip `_restLengthSpelling`; the scanner is green over
  the changed roots.
- **RATIFY** (A3): Phase 1 shipped the field wire-only; Phase 2 then read it, and the Notes' intermediate
  state was shippable. The plan's Progress records both.
- **RATIFY** (A4): the phone is held to the table only where a row polls every multiple of its interval.
  Consistent with plan item 7 and D-250; see finding 7 for the wording of the header, not the choice.
- **RATIFY** (A5): `boundary > 0` is an equivalent mutant. Recording it instead of claiming a guard is the
  right call; do not "simplify" the clause, D-250 states it.
- **RATIFY** (A6): the float payload has no fixture, so the refusal is asserted inline on the wrist. See
  finding 8 for the residual divergence.
  No unrecorded guess found — every choice this phase made is in the log.

## Scope triage (`.github/copilot/pr-scope-budget.md` §1)

Eight substantive findings, but six are one-line fixes inside files 22b already opens, one is a header
sentence and one is a one-clause doc line — a single bounded round, no design finding spans layers, and no
second review round is needed. **Do not add anything: fix findings 1, 5, 6, 7 and 8 in this PR (or mirror
them into 22b's phase items as this review's Feedback pointer says) and land it.** The plan's own split is
correct and must not be re-expanded.
