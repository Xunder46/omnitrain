# Plan 36b — planned sets and presets (review)

# Review: plan 36b planned sets · Phases A1/A2/B/D · 295dd71..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 2 · minor 2 · tests: flutter `+4708 ~1`, `swift test` 591, analyze 182 (run by the lead per the brief; not re-run)
Diff vs Predicted Files: conforms — exactly the 13 files of Phases A1 (6), A2 (3), B (3) and D (`docs/watch_session_sync.md`); the plan/evidence/review files are plan artifacts. Nothing outside.

## Findings

1. [Blocker] docs/watch_session_sync.md:117-118 — the sentence "past the planned rows, or in a row that carries no value for a metric, the old chain (last logged, else the kind default) stands" is false for load: a planned row without `loadKg` yields a planned zero (WatchLoggingState.swift:612 `return (row["loadKg"] as? NSNumber)?.doubleValue ?? 0`), never the chain — with a last-logged load of 40 the chain would give 40, the code gives 0. The same false claim sits in the code comment at WatchLoggingState.swift:604, and the doc's own cited test (`testS3625APlannedRowWithoutALoadShowsZero`) pins 0, contradicting the sentence. A maintainer reading the doc would expect a loadKg-less row to inherit the last logged load. Fix: split the sentence (and the comment) — "a row without `reps` falls to the old chain; a row without `loadKg` is a planned zero load (0), not the chain". Guard: the distinguishing state is exactly what finding 2's test should assert.
2. [Major] watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift:170 `testS3625APlannedRowWithoutALoadShowsZero` — vacuous: the slot has no entries and no history, so without the planned branch weight is `lastLogged ?? target` = nil ?? 0 = 0 (targetsByKind, WatchLoggingState.swift:210-211), the same 0 the branch returns. The test cannot detect a regression where the weight case falls through to the chain, so the scenario "a row without loadKg is a planned zero load" is unpinned in the state that distinguishes it. Fix: give the snapshot one phone entry with `loadKg: 40` (the `setEntry` helper) so lastLogged(weight) is 40, keep the planned row `["reps": 10]`, and assert weight 0 — that fails without the branch and passes with it. (Mutation W1's 14 failures come from the other tests; this one survives it.)
3. [Major] S-3630 (the user adds a set on the phone mid-session → four plannedSets items, revision rises) has no test. The plan's stated guard was "S-3621's list assertion extended + S-3622", but no test in the diff adds a fourth row to an already-projected session: the S-3621 group seeds 1–3 rows once, and S-3622 edits reps without adding a row. The list-follows-rows mechanism is covered, but the add-a-set flow the scenario names is not. Fix: one test in the S-3621 group — seed P's three rows, project, append a fourth (`LoggedEntryRows.setObservations`, entryIndex 3), project again, assert four items in order (the revision rise is S-3622's to carry).
4. [Minor] watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift:189 `testS3625APlannedRowWithoutRepsFallsBackToTheOldChain` — the reps half asserts 10, which equals the kind default (targetsByKind[set][reps] = 10), so only the "else the kind default" half of the old chain is pinned for a reps-less row; the "last logged" half is not. The weight half (30) does guard the branch. Fix: add a phone entry with reps 7 before the planned row and assert the reps-less planned row shows 7.
5. [Minor] watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift:329 `testS3632AHoldSlotIgnoresTheKey` — the slot declares `effortKind: "hold"`, which is not a wire `effortKind` value (envelope.schema.json:66 enum `set|timed|round|drill`), so the test exercises the wrist-started shape (via `createSession`), not what a phone snapshot carries for a hold slot (`effortKind: "drill"`). The gate is shared (`effortKind == .set`, WatchLoggingState.swift:502) so the behaviour holds on both paths, and the phone never sends the key for a drill slot — but the wire form is untested. Fix: one more case applying a wire snapshot whose slot declares `effortKind: "drill"` with `plannedSets`, asserting caption nil and the extraWeight row only.

## Assumption Log rulings

- Open question 1 (D-3's reason wording): RATIFY the proposed rewording — `applySnapshot` (WatchSessionEngine.swift:487-532) compares no revision; its gates are the schema gate and the foreign-session refusal (:502-506). The plan file is outside this review's write scope; the lead applies the wording.
- Open question 2: resolved by the lead; nothing to rule.
- Open question 3 (dead `parity` assignments, test/watch_session_projection_test.dart:2479/:2613): RATIFY leaving them — pre-existing, untouched by this diff.
- Open question 4 (docs/watch-app-setup-and-qa.md:213 drift): ESCALATE to the docs keeper's next pass, as flagged; outside this plan's surface.
- A-1, A-2: RATIFY — A-2's substance re-checked this run (no view test; the caption is tested through `setCaption` only).

## Scenario coverage

- S-3620 → test/sync_protocol_fixtures_test.dart (three generated S-001 tests, +3 per the evidence) and SyncProtocolFixturesTests.swift walkers | covered (walkers read; individual generated names not read)
- S-3621 → test/watch_session_projection_test.dart, 7 tests, group `S-3621 the phone sends the planned sets` | covered
- S-3622 → test/watch_session_adoption_bridge_test.dart `S-3622 a planned-value edit moves the revision` | covered
- S-3623 → `testS3623TheWristStartsEachSetFromItsPlannedValues` | covered
- S-3624 → `testS3624APhoneLoggedSetCountsTowardsK` | covered
- S-3625 → four testS3625… tests | covered, two weak (findings 2, 4)
- S-3626 → `testS3626APlannedLoadShowsThroughTheSavedUnit` | covered
- S-3627 → `testS3627AFullyLoggedSlotReadsSetFourOfFour` | covered
- S-3628 → `testS3628AWristLoggedSetCountsBeforeThePhoneConfirms` | covered
- S-3629 → no new test (existing behaviour per the plan); cited guard `testS81AReDeliveredSnapshotLeavesTheStoreAsItWas` not read this run — not checked
- S-3630 → MISSING (finding 3)
- S-3631 → `testS3631ASlotThatDeclaresAnotherKindIgnoresTheKey` | covered
- S-3632 → `testS3632AHoldSlotIgnoresTheKey` | covered, fixture caveat (finding 5)

## What the tests cannot show — checked, no finding

- Double-count: a wrist-logged set is claimed stamp-exactly (`PhoneEntries.resolveClaims`, phone_entries.dart:269-286: `stampOf(group) != stamp` skips), the live merge fills the claimed planned row in place (watch_session_importer.dart:820-836 deletes the planned rows and re-keys the wrist's rows `obs-<effortId>-<n>-<metricKey>`), so the group count does not grow and no index shifts; the phone never echoes the claimed set. Where the phone logged the same set number itself, the stamps differ, the phone's own entry is echoed, and the wrist counts two held sets — two physical sets, consistent with I-4.
- Deletion: `engine.entries` drops `deletedEntryIds` (WatchSessionEngine.swift:203), and `setsHeld` reads that projection, so a phone-deleted set stops counting; the importer keeps the wrist's own entryId, so a deletion of a wrist-logged set names the id the wrist holds.
- Mid-dial snapshot: `field(for:)` reads `dialled[metricKey] ?? initialValue(for:)` (WatchLoggingState.swift:529-531) and nothing in `applySnapshot` clears `dialled`, so a snapshot arriving mid-dial never resets the user's dialled value; a logged set clears it (`log(now:)`).
- Below-floor load: `_plannedSetOf` omits it (`weightKg >= WireLimits.minLoadKg`, wire_limits.dart:20), matching the entry rule; the wrist then shows 0 for that set — documented in both docs, accepted by D-58/D-60.
- Push size/determinism: `setGroups` sorts by number (entry_rows.dart:158-168) and `_ladderOf`'s appended `jsonEncode` is deterministic; no key-order or list-order hazard.
- Older-wrist refusal: PROTOCOL.md states it plainly in both the normative paragraph and the changelog row; the watch app ships from this repository, so no shipped wrist build predates the field.
