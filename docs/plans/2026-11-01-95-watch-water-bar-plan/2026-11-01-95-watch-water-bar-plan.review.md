# Review — plan 95 (watch water bar, PR 94b)

Reviewer: @code-reviewer, 2026-11-01. Verdict: **REJECT on documentation only** — the code, tests and
wiring meet the plan; four docs say something untrue or prohibited, all mechanical to fix in one round.

Layers in scope: watch (Swift package `watch/watchos` sources + tests; `ios/OmniTrain Watch App/ContentView.swift`),
contract text (`watch/sync_protocol/PROTOCOL.md`), docs.
Layers skipped: Dart models, persistence, state, features, widgets, core (D-36: no Dart file is plan 95's).
Out of scope: every other uncommitted file in the shared checkout (another session's food form / nutrition /
exercise editor / workout state / tests / `design_system.md`; PR 94a's files and hunks). Not counted as
out-of-bounds; plan 95's hunks in shared files (PROTOCOL.md, the three `docs/` files) were separated by content.

## Checks run by the reviewer (observed)

| Check | Result |
|---|---|
| `swift test --package-path watch/watchos` (900 s cap) | exit 0, `Executed 1181 tests, with 0 failures (0 unexpected)` — matches the Phase 4 claim |
| `flutter test`, local time (900 s cap) | exit 1, `+6021 ~2 -1`; the one failure is A-8 (`state_test.dart` nutrition target, DST) — not a finding |
| `TZ=UTC flutter test` (900 s cap) | exit 1, `+6021 ~2 -1`; the one failure is `test/delete_focused_timer_test.dart` S-4905 (`Expected '00:45', Actual '00:46'`, a wall-clock timer) while a clean watch build ran alongside. The file re-run alone in UTC passed 3/3 (`+4`), and in local time 1/1. Load flake in a Dart workout test: not plan 95's (no Dart change), worth a look by whoever owns plan 41. |
| watch target, clean `xcodebuild build -target "OmniTrain Watch App" -sdk watchsimulator` into a fresh scratch SYMROOT/OBJROOT, `CODE_SIGNING_ALLOWED=NO` | exit 0, `** BUILD SUCCEEDED **`, 160 SwiftCompile steps incl. `WatchWater.swift`, `WatchNutritionView.swift`, `ContentView.swift`; no warning in them. No simulator booted, nothing installed. (A first run into an existing scratch dir was a no-op incremental build and is not counted.) |
| Invariant `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | empty (exit 1) |
| `ui_standards_contract_test`, `docs_indexing_contract_test` | green inside the full local run |
| 64 KiB ceiling (`find docs -name '*.md' -size +65535c` outside `docs/plans/`) | none; edited docs 51,878 / 22,641 / 38,464 / 31,038 B (first three under the 52,429 band) |

## Diff versus Predicted Files

- Every predicted file is touched; nothing predicted is left untouched.
- Out-of-bounds: `docs/state_management.md:89` (`WatchWaterState` row). Written after the evidence file (22:18:48 vs
  22:17:54), i.e. the A-8 follow-up; justified. A-8's text ("not added") is now stale.
- Plan D-38 asserted `watch_surface_wrist.md` stays true — it does not (F2).

## Findings

| # | Sev | Kind | Location | Finding | Fix | Agent |
|---|---|---|---|---|---|---|
| F1 | REJECT | mechanical (doc false) | `docs/state_management/watch_sensors.md:416-418` | "Four prunes … the store's public surface is exactly `append`, `readAll`, `pruneConfirmed`, `pruneSensorSamples`, `pruneExerciseBatches` and `pruneBests`" — there are now five (`pruneWater`). | Delete the count and the enumerated surface; point at `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule` (its allowed set is the list) and add `WatchWaterStoreTests.testS94b4APruneNamingAnAbsentRowDropsNothingAndWritesNothing` to the prune pointers. | @developer |
| F2 | REJECT | mechanical (doc false) | `docs/state_management/watch_surface_wrist.md:257-258` | Enumerates `WatchSyncProgressCopy.replyTypes` as the reference frames, batches, snapshot and `bests_down`; `water_down` now counts too. | Delete the enumeration; point at `WatchSyncProgressTests` and `WatchWaterSyncTests.testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply`. Shrinks a file in the size band. | @developer |
| F3 | REJECT | mechanical (doc false) | `docs/state_management/watch_reference_data.md:327-328` | "A glass tapped on the phone reaches the wrist at the wrist's next sync, not before" — false: the phone sends the day's count after the receipt for any wrist tap (`WatchWaterLogBridge`, same doc l.304-306), so a phone glass also arrives with the answer to the next wrist tap. Untested prose. | Delete the sentence (`docs/nutrition.md` already carries the "next sync" pointer to S-94b-17). | @developer |
| F4 | REJECT | mechanical (doc standard 3.2/3.3) | `docs/nutrition.md:431-432`; `docs/state_management/watch_surface.md:374` | "the same minus/count/plus bar under its food list" is a control inventory plus a position; "whose bar sits under the Nutrition list" is a position. | Replace with ownership + pointer, e.g. "the watch's Nutrition screen carries the water count (`WatchWaterBarSourceTests.testS94b22TheBarIsOnTheListOnlyEmptyListIncluded`)". | @developer |
| F5 | WARNING | decision (doc conflict) | `docs/state_management/watch_surface.md:757-761` vs `docs/state_management/watch_reference_data.md:325-327` | The first says what the wrist does with a receipt includes `pruneConfirmed`, "the only way the observation box gives rows back"; the second says `pruneConfirmed()` has no caller. Swift: no production caller; the Dart twin's debug surface calls it (`lib/watch/debug/watch_session_debug_surface.dart:270`). Not resolved here. | Resolve before either is trusted; the planner or owner picks the wording, then point both at `WatchWaterBarSourceTests.testS94b25TapsAreNeverPruned`. | planner → @developer |
| F6 | WARNING | design (follow-up PR) | `WatchWater.swift:181-204, 241-257`; bar body `WatchNutritionView.swift:172-227` | One bar render calls `todaysTaps` about five times (`glasses` twice, `canAdd`, `canRemove` → both). Each call filters every stored observation and parses an ISO-8601 date for every water tap ever stored. D-37 keeps taps forever, so main-thread cost per render and per tap grows linearly for the life of the install (about 3k taps a year at 8 a day). | Read one snapshot (count, canAdd, canRemove) per render; before parsing, pre-filter taps by their `nutrition-<UTC date>` session id to local today ±1 UTC day. Separately, D-37's premise "D-25/D-26 read every stored tap" overstates it: only local-today taps matter, so pruning confirmed taps older than local yesterday is safe. That is a decision for the planner. | planner → @developer |
| F7 | WARNING | mechanical (doc incomplete) | `docs/state_management.md:50` | The Watch Surface row's contents list names `WatchNutritionState` but not `WatchWaterState` (nor 94a's `WatchWaterLogBridge`). | Add both names. | @developer |
| F8 | SUGGEST | mechanical (test) | `WatchWaterSyncTests.swift:379` | S-94b-18's late arrival at t0+30 is past the 20 s cap, so it cannot fail if `noteArrival`'s guard is removed (A-5). | Move it to t0+5 (after the 4.5 s quiet end, before the cap). | @developer |
| F9 | SUGGEST | mechanical (test) | `test/watch_logging_surfaces_test.dart:975-978` | The banned-framing scan reads `WatchNutritionView.swift` but not `WatchWater.swift`, where the bar's spoken copy now lives. | Add `WatchWater.swift` to the scanned list (a Dart test edit, so in a later PR, not this one: D-36). | @developer |
| F10 | SUGGEST | pre-existing | `WatchWater.swift:242` via `WatchSessionEngine.swift:1445` | `engine.waterLog` reads the engine's unguarded `storedObservations` from the main thread while receipts rewrite it on the radio path (`WatchSessionEngine.swift:2006`). `nutritionLog` already does the same. `WatchWaterState`'s "lock-guarded" covers only the held frame. | No change in this PR; note it for an engine-threading pass. | — |

Structural guards for the remediation items:
- F1-F3: the remedy deletes the second copy of each list or claim, so the tests become the only place it is stated. If either enumeration is kept, add a docs contract test asserting that every `func prune…` in the `WatchSessionStore` protocol, and every member of `replyTypes`, appears in that doc.
- F4: no automated guard catches 3.2/3.3 (AGENTS.md); the reviewer gate is the guard.
- F6: a test that seeds about 20k historic taps and asserts that the fold parses only the candidate taps (injected counting parser).
- F8: the moved instant is itself the guard.

## Behavioural verification

- AC-1..AC-8: each is implemented and mapped to a passing test (evidence tables, re-read). No criterion is unmet.
- Fixture conformance S-94b-1..25: every scenario has a test that builds its enumerated fixture. Adversarial
  cases are all present:
  - phone unreachable (S-94b-20, `isPhoneReachable` false)
  - receipt lost and redelivered (S-94b-11, state and sync halves; byte-identical `msg-w-1`)
  - receipt arrives but the frame is lost (S-94b-12, mutant-proven)
  - both devices tapped while apart (S-94b-13; also S-94b-10)
  - minus at a shown 0 (S-94b-8, S-94b-10)
  - local midnight (S-94b-14; S-94b-15's midnight half)
  - frame for another day, yesterday and phone-ahead (S-94b-9 a/b)
  - empty foods list (S-94b-22, source scan only: the bar follows the whole if/else)
  - taps past the cap (S-94b-15, cap read from the schema)
  - relaunch with unsent taps (S-94b-16, file store)
  - unreadable frames (S-94b-6, plus seven extra shapes)
- Weak spots: S-94b-18's late arrival (F8). S-94b-10 and S-94b-19 pass on a skeleton; this was declared, and the clamp is still caught by a real-fold mutant.
- D-24..D-27 correctness: the implementation matches the decisions exactly:
  - validator, then reader, then older/unchanged/newer
  - a tie with different content applies
  - an unchanged frame advances `generatedAt` in memory only
  - the fold is by `loggedAt`, then sequence, then position
  - the frame's day is compared with zero-padded local today
  - `canRemove = canAdd && glasses > 0`
  - nothing is cached
- D-26 cap: sound under the stated one-time-zone assumption. 500 taps is unreachable in normal use, and it equals the schema `maxItems` (a test reads it). Ratified.
- Concurrency: one `WatchAsyncMutex` serialises restore, apply and press, so no double "newer" pass and no cap overrun. `NSLock` is never held across a suspension. Reads take only the lock. `onWaterChanged` is set once in the host before `restore()`. Sound (pre-existing engine race: F10).
- D-37 append-only: implemented and guarded by S-94b-25 (mutant M4 red). The rationale overstates the need (F6).
- Main-thread hops: `objectWillChange` is sent on `DispatchQueue.main` after the change. SwiftUI re-reads computed values, so this is correct; S-94b-21 pins the thread and mutant M1 is red.
- `press(.add)`/`press(.remove)` naming: correct consequence of S-004's `func remove…` ban (A-4).
- `TimelineView(.everyMinute)`: re-evaluates the computed count at each minute boundary, so midnight turns the count over on time.
- 40 mm fit: the structure is present (count `.lineLimit(1)` and `.minimumScaleFactor`, icon-only bordered buttons, flexible middle). Not verifiable without a device: owner QA step 40(e).
- Haptic and VoiceOver against A-1: `.click` only when `press` returned true. Labels are exactly D-33. The middle is one element ("Water", value "N glasses"). Matches the confirmed defaults.
- D-36: confirmed. `lib/watch` holds only 94a's `waterGlass` constant. No Dart parity test spans record kinds, `all` or the request builder. The full Dart suite is green apart from A-8.

## Documentation

- DOC FALSIFICATION: REJECT — F1 `watch_sensors.md:416`, F2 `watch_surface_wrist.md:257`, F3 `watch_reference_data.md:327`.
- DOC FALSIFICATION: CONFLICT — F5.
- DOC FALSIFICATION: WARNING — F7 `state_management.md:50`.
- DOC FALSIFICATION: PASS for these:
  - `watch_surface.md` `### WatchWaterState` and the routing sentence
  - `watch_reference_data.md` "The wrist holds one water count", except l.327-328
  - `nutrition.md` water paragraph, except F4
  - QA step 40 (a)-(f)
  - the PROTOCOL.md sentence
  - `watch-app-setup-and-qa.md` step 32
  - `navigation_and_screens.md` (phone only)
- Every cited test name exists.
- DOC STANDARD: REJECT — F4 (3.2/3.3). Otherwise PASS: no numerics (the cap is named, not restated), no roadmap and no "in PR" notes. The QA guide is exempt from 3.1 (§4).

## Conventions and impact

- PASS (6): repository/Hive invariants untouched; the watch package is platform-independent outside `#if os(watchOS)`; DI happens at the host; append-only store and S-004 updated on purpose; protocol contract unchanged (no version row needed); docs name constants.
- N/A (Flutter UI and design-system button rules): no Flutter screen changed.
- IMPACT: all 10 rows re-grepped. Line numbers drifted but the readers match. No unlisted reader of `storedObservations`, `requestRoutines`, `WatchSessionStore` conformers, `WatchNutritionView(` or the orchestrator init.

## Assumption Log rulings

- A-2: RATIFY.
- A-3: RATIFY (a corrupt frame must not read as 0).
- A-4: RATIFY. Promote: D-27's `add()`/`remove()` are `press(_:)`.
- A-5: RATIFY, with F8.
- A-6: RATIFY.
- A-7: RATIFY.
- A-8: RESOLVED; the row exists at `docs/state_management.md:89`, so the log text is stale.
- A-1: owner record.

## Scope triage (`.github/copilot/pr-scope-budget.md` §1)

There are seven substantive findings (F1-F7), and F6 is a design item that needs scenarios of its own, so split the work:
- **This PR, one round, no re-review loop:** F1-F4 and F7, all doc edits. The governor checks them with `docs_indexing_contract_test` and a re-read of the four lines. F5 also goes here once the planner or owner has picked the wording.
- **Follow-up PR plan:** F6 (render cost and the D-37 refinement), F9, and optionally F8.

