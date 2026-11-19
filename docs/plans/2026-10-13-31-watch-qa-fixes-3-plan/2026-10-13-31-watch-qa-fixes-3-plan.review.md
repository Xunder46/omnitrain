# Review: plan 31 (watch QA fixes, round 3) — review 1

Reviewer: code-reviewer, 2026-10-14. Base `0da2a72` + untracked `WatchExerciseListView.swift` and the plan folder.
Out of scope: `lib/`, `test/`, `docs/plans/2026-10-13-32-*` (concurrent work).

## Findings

### 1. MAJOR — duplicate scroll ids in the shared list (WatchExerciseListView.swift:100-115)

`deriveExerciseSections` (WatchMenu.swift:137-165) emits contiguous runs, so one letter key can open
**two** sections in one catalog. Reachable today: a catalog with a digit/symbol-leading name
("3x3 press" → `#` run before A, S-3105's fixture class) **and** a tilde name ("~stretch" → sorts
after Z, keys `#` — proven by existing testS3908, WatchMenuTests.swift:1388-1419) yields two
sections with letter `#`. The shared `list(_:)` puts `.id(section.letter)` on **every** header, so
one ScrollViewReader holds two views with `.id("#")` — SwiftUI requires unique ids; the `#` grid
jump may land on either run, i.e. the exact off-target-landing bug class this plan fixes. It also
breaks S-3105's pinned identity `sections.map(\.letter) == letters.map(\.letter)` for such a
catalog (the fixture avoids the combination). Same exposure in the picker
(`availablePickerExercises` preserves order, WatchStartPaths.swift:570-600).

Fix: apply `.id(section.letter)` only to the **first** section per key (track seen keys in
`list(_:)`); later runs get no scroll id. Add a test whose fixture contains both a digit-leading
and a tilde name, asserting the sections' letters are unique per scroll id (or that only the first
run carries the id). @developer

### 2. MINOR — `yieldHeartRateIfNewer` fallback `?? Date()` (HealthKitSensorFeed.swift:189, :244)

When `mostRecentQuantityDateInterval` is nil the gate compares against `Date()`, so a pull tick
3 s later re-reading the same statistics (interval still nil) yields the same bpm again as a
"newer" beat — the dedupe degenerates. Theoretical (live builders normally carry the interval);
fix by skipping the yield when the interval is nil, or falling back to the builder's start date.
@developer

### 3. MINOR — doc wording (docs/watch-app-setup-and-qa.md, step 14)

"with the session's own exercises above the letters" — in the shared view the letter **grid** is
the first row, above the in-session rows; only the letter *sections* come after. False for the
grid reading. Reword to name grid first, then in-session rows, then letter sections. @developer

## Verified good

- Heart-rate concurrency: NSLock discipline correct; check-and-set in `yieldHeartRateIfNewer`
  atomic under lock; pull Task `[weak self]`, exits on cancel/dealloc; `forgetHeartRate` nils and
  cancels under lock when continuations empty; `lastHeartRateEnd` reset on nil builder; `end()`
  clears builder first; one gate for both paths; hand-over does one immediate read (covers the
  3 s sleep before the first tick).
- ContentView: one `WatchMenuState(` construction (root `menuSheet` helper); sheet closes on
  session status != .active and on `isPromptOwed`; rest branch NavigationStack + verbatim button;
  `healthStore` declared after init keeps the S-3110 first-occurrence scan green.
- Shared list accessibility: letter buttons keep `addLetterJumpLabel`; rows are named buttons.
- One threshold site: `deriveExerciseListLetters` is the only reader of `addLetterGridThreshold`;
  menu and picker both route through it; picker sections/letters derive from the same source.
- All 16 doc-cited test names exist (grep-verified).
- Evidence file complete: prove-red verdicts + mutation tables for every guard; S-3109 GREEN at
  base is the documented D-3107 diagnostic, proven observable by an 18-failure mutation.

## Guard spot-checks (run by reviewer)

- `prove-red 0da2a72 swift-test --filter WatchSensorSourceSourceTests/testS311` → RED AT base
  (6 tests / 11 failures) — matches evidence.
- `prove-red 0da2a72 swift-test --filter testPickerRows -- WatchConnectivityBridgeTests.swift`
  → RED AT base (2 tests / 2 failures at :877/:913) — matches evidence.

## Test runs (reviewer-executed)

- `swift-test`: **573 tests / 0 failures** — matches plan claim.
- `test` (Flutter full suite): **+4519 ~1 (1 skipped), all tests passed**, exit 0.

## Known compile errors (governor-tracked, not re-listed)

`mostRecentQuantityDateInterval` needs `()` at HealthKitSensorFeed.swift ~189 and ~244 (the only
two usages in the diff); ContentView hint pinned below list. Confirmed no others in changed lines.
