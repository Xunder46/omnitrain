# Review: 2026-11-04-112-stats-sweep-fixes · mix note + wrist food day · 837a4031..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 1 · tests: not run (brief: lead ran the touched files green — mix 127+2, quick-log 46, on-day 4 — and a 12-mutant pass, all killed; full suite is the lead's)
Diff vs Predicted Files: conforms; the stat's extra files are the plan's named unrelated dirty files (`.claude/commands/crew.md`, `.github/copilot/crew-rules.md`, `lib/core/services/stats_progress_service.dart`; `test/stats_dst_day_arithmetic_test.dart` shows no diff line)
## Findings
1. [Minor] lib/state/nutrition_state.dart:361 — the `_nutritionTarget` read moved across an await: the old `logConsumedFood` captured `target` before the `getFoodGroupById` lookup, `_snapshotFor` now reads it after, so a target save completing during that await would freeze a different target than the old code did. D-18603 claims byte-identical behaviour; for any single-threaded run it is, this is only a concurrent-interleaving difference. Fix: hoist `final target = _nutritionTarget ?? NutritionTarget();` above the group lookup and pass `target: target` (2 lines). Guard: none exists; existing snapshot tests stay the proof.
## Five questions
1. `logConsumedFoodOnDay` race — no reachable half-written state: `_writeThroughLastAmount` swallows its own errors (nutrition_state.dart:619-634), so it cannot fail after the row write and return null; the lookup→create window (awaits at :545, :567, :573) exists structurally, but the only production caller chain serializes inbound frames through `_lane` (watch_transport.dart:441-442), and the pre-existing today path (`logConsumedFoodAt` → `logConsumedFood`) has the same create-without-recheck shape — no new race class.
2. `_tappedDayOrNull` — yes, every non-today path requires a parseable `loggedAt` (String + `tryParse`), not after the bridge clock, and on a local date earlier than the clock's (`parsed ≤ now` in instants forces `toLocal()` date ≤ today, so differing means earlier); a `+05:00` offset parses to the correct instant and `.toLocal()` files it on the right local day — no way to file a same-day tap on a past day. The wrist sends UTC ISO (`WatchNutritionState.swift:270` `loggedAt: clock()`, `utcIso`; schema `sync_protocol/schemas/envelope.schema.json:226` requires it).
3. `logConsumedFood` snapshot — byte-identical for every field (id, `loggedAtMs`, `dateMs`, food fields, sodium, group snapshots, four targets, `createdAtMs`, `updatedAtMs`); the only change is the target-read order of finding 1.
4. Mix note — the note block sits after the `layer.windowIsEmpty` early return (mix_layer.dart:148-160), so the empty-window state renders `_buildEmptyWindow` with no note; the ternary is exclusive, so the two sentences cannot appear together; under load `!_isLoad` is false and neither renders.
5. Docs — all three say what the code does (checked against mix_layer.dart:186-198, nutrition_state.dart:530-591, watch_nutrition_log_bridge.dart:157-166, :222-241); every cited test exists (`S-3204` groups at mix_layer_screen_test.dart:2511/:2529/:2545, group `S-18601…` in the diff, `test/nutrition_log_on_day_test.dart` S-18608/S-18609 in the diff).
## Assumption Log rulings
- Owner chose sweep items 1 and 3, deferred 2; the new sentence is the lead's default — ratify (owner decision recorded; wording is observable and pinned by S-18601).
- Scout's item 3 claim (wrist carries `loggedAt`, bridge ignored it) — ratify; confirmed in `WatchNutritionState.swift:270` and the old bridge code in the diff.
- Timing probe deleted, food reads unchanged — ratify (out of scope by the plan's own line).
## Scenario coverage
S-18601 -> test/mix_layer_screen_test.dart · group `S-18601 the baseline note when effort is hidden by unrated time` / `over the share, time keeps the note without "so far"` (fixture: 60/90 = 66% unrated with 4 rated weeks)
S-18602 -> test/mix_layer_screen_test.dart · `S-18602 the unrated share boundary is inclusive` / `exactly 25% unrated keeps load and no note` (guard: green before and after by design; kills M1/M3)
S-18603 -> test/mix_layer_screen_test.dart · existing `S-3204 the baseline note says what happens and when` (:2511) and `S-3204 the twin: no rated week at all` (:2529) pin the old sentence; the diff comments this at :2557
S-18604 -> test/watch_nutrition_quick_log_test.dart · `an event tapped the day before lands on that day, not on today` (+ one-month and one-year-later variants; bridge clock exactly +24 h, so the tapped day is past in every zone)
S-18605 -> test/watch_nutrition_quick_log_test.dart · `a re-delivered event with a new servings value updates that row`
S-18606 -> test/watch_nutrition_quick_log_test.dart · `the row freezes the targets saved for the tapped day`
S-18607 -> test/watch_nutrition_quick_log_test.dart · `a loggedAt later than the bridge clock is filed on today` / `a missing loggedAt is filed on today` / `an unreadable loggedAt is filed on today` (one test per arm, as planned; the last two judge with `validator: null` to reach the bridge's own guards past the schema)
S-18608 -> test/nutrition_log_on_day_test.dart · `S-18608 a past-day log is stored on that day and updated in place` (Mock + Hive via `harnessFactories`; also asserts `consumedToday` stays empty and a second food adds a row)
S-18609 -> test/nutrition_log_on_day_test.dart · `S-18609 a loggedAt today delegates; invalid amounts store nothing`
## Docs delta
docs/stats_screen.md MODIFIED -> applied
docs/state_management/nutrition_state.md ADDED -> applied
docs/state_management/nutrition_state.md MODIFIED -> applied
docs/state_management/watch_surface_nutrition.md MODIFIED -> applied
Doc edits outside the table: none (the three docs' diffs contain only the table's rows).
## Input-reality notes (no architect run; checked from code)
- Writer of `loggedAt`: the wrist's own engine (`WatchNutritionState.swift:270`, `loggedAt: clock()`), sent as UTC ISO; the bridge is the only reader. Unit: an instant, not a day.
- Lifecycle: a repeat delivery updates the one row (S-18605); a log with no usable time still lands today (S-18607); `consumedToday` is never touched by the past-day path (asserted in both new test files).
- Targets: per-date targets are read through `getNutritionTargetForDate(dayMs)` with a `NutritionTarget()` default (nutrition_state.dart:572-574), frozen only on create; an update keeps the row's original frozen targets (S-18606 asserts the create side).
- Existing readers of the note text: `test/stats_rated_weeks_screen_test.dart:182` asserts `contains('(2 of 4 so far)')` with 2 rated weeks — old branch, unaffected.
