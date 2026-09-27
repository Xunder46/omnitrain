# PR 3a — Code review

> Plan: `2026-09-26-03a-stats-pr3a-phone-distance-plan.md` · Evidence: `…plan.evidence.md`.
> Reviewed 2026-09-27 on `feature/stats-pr3a-phone-distance` (base `develop` 2690d1b), uncommitted tree.
> Not reviewed (not Copilot's): the three untracked plan files; the header edits in the PR 1 and PR 2 plans.
> Layers in scope: models, repositories, state, core (utils, services, models), features (session, stats),
> widgets (session), schema contract, docs. Layers skipped: `watch/`, `lib/watch/`, `lib/core/sync_protocol/`,
> the watch importer (0 files changed there).

## Verdict: CHANGES REQUESTED (docs and one test; no production code)

The app does what the owner decided. Every D-319 / I-1 / Q4–Q9 behaviour in §5 is implemented and pinned by a
test that fails when the behaviour breaks: six of seven mutations went red for the right reason, and each failing
value matches the arithmetic of its defect. The blockers are documentation. The new docs claim exclusivity that
is false (F-1) and add content the documentation standard prohibits (F-2). F-3 adds one test case and F-4 adds
three index lines.

## 1. Observed runs (this review, current tree)

| Check | Result |
|---|---|
| `flutter test` (full) | exit 0, `01:19 +3051 ~1: All tests passed!`: 3000 baseline + 51 new (distance_source 18, db_seed +2, session_summary_distance 16, crown +5, stats_distance_estimate 10). Skip = `profile_navigation_test.dart:39`. No hang. |
| `flutter analyze` | `242 issues found.`, exit 1; 0 errors, 11 warnings, 231 infos = baseline. `session_summary_screen.dart` 10 (baseline 10: the same 8 `withOpacity` + 2 context infos, none on added lines); `stats_screen.dart` 1 (`_ChartSeries`, baseline); `session_core.dart` 1 (pre-existing `curly_braces…` at :161, untouched code); every other touched file 0. |
| Phase 1 command | `distance_source_test` + `db_seed_test`: exit 0, `+25: All tests passed!` |
| Phase 2 command | `session_summary_distance_test` + `crown_control_tap_to_edit_test`: exit 0, `+50` |
| Phase 3 command | `stats_distance_estimate_test` + `stats_progress_test` + `screen_widget_test`: exit 0, `+330` |
| `swift test` | Not run. Nothing under `watch/`, `lib/watch/`, `lib/core/sync_protocol/` or the importer changed. |

## 2. Mutation checks

Method: copy the file aside, break the change in place, run only the relevant test file, restore the copy, then
re-run and see green. After all runs, the sha256 of each of the five mutated files matches its pre-review value,
and the `git diff` hash is the same before and after (`4ddf410a…`).

| # | Behaviour | Mutation | Result (RED = caught) |
|---|---|---|---|
| M1 | D-319 ignores the session's modality | rule also requires modality `cardio_endurance` | RED 4. S-818a `['Easy Run · 2','3.00','KM']` (only the stored-distance row survives); S-818c `['Easy Run · 1','2.40','KM']`; S-822 `[]`; S-823 `[]`. These are exactly the Cardio-tracked entries of sessions with no modality; the Cardio-session tests stay green. |
| M5 | D-319 does not over-list | `drill` treated as Cardio-tracked | RED 4. S-818d, S-819, S-822 and S-823 gain `Plank · n` rows. |
| M2 | Q9 / D-309 pace | pace = all finished time ÷ all distance | RED 3. S-831a `600.0` (1200 s ÷ 2 km); S-831b `200.0` (600 s ÷ 3 km); S-837 `Pace: 231 s/km` not found. |
| M3 | A copy keeps the source | drop `valueSource` from Hive `cloneSessionBlock` | RED 2. Hive S-804 at `distance_source_test.dart:449`: `Expected 'estimated' Actual <null>`; the guard lists `hive_workout_repository.dart:2841`. Mock S-804 stays green (not mutated). |
| M4 | Q4: a confirm keeps the metres | Summary always stores the typed value | RED 1. S-814 `Actual <4870.0>` = 4.87 × 1000; the 3.6 m lost is the 2-decimal rounding. |
| M7 | Schema CHECK | CHECK removed from `sqlite_schema.sql` | RED 1. S-803 SQL: `Expected: not null Actual: <null>`. (The first attempt's pattern did not apply; that run was discarded.) |
| M6 | D-317: dot found by the spot's x | lookup by the painter's list index | GREEN: the mutation survives. See F-3. |

## 3. Done Criteria

| Phase | Tests | Full suite | Analyzer | Diff within Predicted Files |
|---|---|---|---|---|
| 1 | PASS (+25) | PASS (+3051 ~1) | PASS (242 issues, 0 errors; files at baseline) | DEVIATION: `lib/state/workout/session_core.dart` (legitimate) |
| 2 | PASS (+50) | PASS | PASS (`session_summary_screen.dart` 10 ≤ 10) | PASS |
| 3 | PASS (+330) | PASS | PASS (`stats_screen.dart` 1 ≤ 1) | DEVIATION: `docs/state_management/workout_state.md` (F-1, F-2) |

## 4. Predicted Files and unrequested changes

- `lib/state/workout/session_core.dart`: outside Phase 1's list; one import line. Legitimate, because
  `session_core_entry.dart` is a `part of` it.
- `.github/agents/docs/state_management/workout_state.md`: outside every list. The intent is legitimate (the
  standing doc queue after new methods), but its new rows carry F-1's false claim and describe behaviour with no
  test pointer (F-2).
- `session_distance_card.dart`, `session_summary.md`, `stats_screen.md`, `widget_catalog/session_widgets.md`:
  predicted (Phase 2 items 2 and 6, Phase 3 item 5).
- Unrequested production hunks: formatting only (N-1), plus the Stats day-distance total now counting paired rows
  only (N-3). Nothing else.
- Size: the production diff is about +723/−59 against ~550 predicted (1.3×, under the 1.5× trigger). The plan is
  531 lines against ~520 at handoff. Existing tests only gained cases (+207/−0).

## 5. Owner decisions

| Decision | Result | Evidence |
|---|---|---|
| D-319: a row for every Cardio-tracked (`timed`) entry, in any session | PASS | `session_summary_screen.dart:947`. Cardio S-811; Free Training S-818a and S-823; watch import S-818c; routine S-822. Rolling sessions use the same build path (`:715-716`) but have no dedicated test (N-5). |
| D-319: a plank tracked via Isometric gets no row | PASS | S-822, S-823; M5 |
| D-319: does not depend on the session's modality | PASS | the section never reads the modality; M1 |
| I-3: a non-timed entry with a stored distance > 0 keeps its row | PASS | S-818d; removing it hides the row (S-819) |
| I-1: entry and correction only on the Summary (post-workout and past) | PASS | Only `session_summary_screen.dart:1043-1045` calls the writes. S-820 covers post-workout; S-811 and on cover the calendar. No diff to Edit Session or the live screen, and the crown's new `distance` case has no other caller. |
| Q4: a confirm, even unchanged, marks it entered and clears "est." | PASS | S-814 (exactly 4873.6 m, `entered`); M4 |
| Q4: Cancel changes nothing | PASS | S-816: outside tap, and Ok with the text cleared |
| Q4: 0 removes the distance | PASS | S-815 (the Cardio row stays as "—"); S-819 (the legacy row disappears) |
| Q5: "est." after distance and pace; `KM EST.`/`MI EST.`; hollow points and legend; a mixed day counts as estimated | PASS | S-811/S-812, S-833, S-835, S-832. The dialog's field label stays `KM` (crown test). |
| Q6: today's Stats cardio card marks estimates | PASS | S-833, S-835 |
| Q7/I-4: a row is the name, "· n", and the distance with unit and "est." only | PASS | S-811 (no `/km`, `/mi` or `Pace` anywhere on the Summary); the card renders three texts |
| Q8: no cadence; a missing distance never shows "0 km" | PASS | no cadence in the diff; "—" in S-811 and S-818a; Stats omits the line when the value is null |
| Q9: pace uses only entries with a distance (2 × 10 min, 2 km on one → 300 s/km) | PASS | S-831a is that exact case; M2 |
| km↔mi through `UnitFormatter`; legacy distances read as "entered" | PASS | `stats_screen.dart:2049-2058`; S-836; no km/mi literal in any touched file; S-801 |
| Architecture: repository interface only; Hive = Mock; tokens only; SQL contract in step; global conventions; 64 KiB ceiling | PASS | State writes via `_repository`; S-801–S-808 run on both repositories; the card uses `OmniSurface`, `OmniCardHeader` and theme colours; db_seed checks the column, the CHECK and `toMap` keys ⊆ columns (M7); §9; the largest touched doc is 35 KB and the docs contract test is green. |

## 6. Findings (most severe first)

**F-1 — CRITICAL · MECHANICAL · doc falsification (Step 5c).**
- Where:
  - `distance_source.md:12`: "nothing else touches a distance";
  - `:34`: "`DistancePairing` is the only place that says which distance row belongs to which entry";
  - `:41`: "`SessionCore` owns the only write";
  - `:121`: "the writers and the Stats reader agree on that pairing";
  - `state_management/workout_state.md:106`: "The one write that changes a distance";
  - `distance_source.md:105`: says confirming an entry with no distance leaves a zero row. That is true only when
    a zero row already exists; with no row, a confirm creates nothing (`session_core_entry.dart:326`).
- Why it is false:
  - `updateEntryValue` still writes distance rows, pairing them by raw list order (`session_core_entry.dart:234-242`).
  - Its callers are Edit Session save (`workout_session_edit_mode.dart:207`), the live screen
    (`workout_session_screen.dart:999`) and the routine-target pre-fill (`session_core_io.dart:296`).
  - `SessionSummaryBuilder` reads distance rows by raw order (`session_summary_builder.dart:367`). The plan's own
    D-312 and O-3 say so.
- Scenario: someone planning PR 3b (a sync must never rewrite a phone-written distance, D-302) or O-3 reads "one
  write, one pairing". They guard only `setEntryDistance`, and the raw-order writers stay unguarded.
- Fix (this PR):
  - Delete the four exclusivity phrases and the no-row confirm clause.
  - Add one structural line: "`updateEntryValue` and `SessionSummaryBuilder` still pair by raw list order (plan
    O-3)."

**F-2 — CRITICAL · MECHANICAL · prohibited doc content (Step 5c-2).**
- `stats_screen.md:211-213`, class 2 (visual): the hollow dot's "series colour on the stroke, the surface on the
  fill". Keep only "marked on the chart and in the legend (S-835)".
- `widget_catalog/session_widgets.md:138-142`, class 5 (field list mirroring a class): the `rows` prop table and
  the `DistanceRowModel` field list. Keep the paragraph above them.
- `session_widgets.md:88` extends the keyboard line (class 3), and `:38` extends the `metricType` prop row
  (class 5). Revert both additions and point at `test/crown_control_tap_to_edit_test.dart`.
- `session_summary.md:52`, class 2: a new row in the section-order layout table. Remove it; the `## Distance`
  section already carries the content.
- `stats_screen.md:197-202`: the old pace formula was edited into a corrected formula, which is the anti-pattern
  Step 5c names. Replace it with a one-line contract ("a day's pace counts only finished entries that have a
  distance") and keep the S-831 pointer.
- `state_management/workout_state.md:106-107`: behaviour prose with no test pointer (standard §4.2). Name the
  methods and point at `test/distance_source_test.dart` (S-805–S-807).
- Scenario: these copies drift silently (standard §1). For example, the next change to the dot style leaves the
  stroke/fill sentence asserting a rendering that no longer exists.

**F-3 — WARNING · MECHANICAL · test gap (D-317).**
- `test/stats_distance_estimate_test.dart:343-429`: every S-835 day has both a pace and a distance, so each spot's
  list index equals its x. That is why M6 (lookup by list index) stayed green.
- Scenario: day 1 has a duration only, day 2 has 4.2 km estimated, day 3 has 4.1 km measured. With an index
  lookup, day 2 is drawn filled and day 3 hollow. The marker lands on the measured day and no test fails.
- Fix (this PR): add a day with no distance before the estimated day. Assert that on both series the hollow dot
  is at the estimated day's x.

**F-4 — WARNING · MECHANICAL · incomplete docs (Step 5c).**
- `widget_catalog.md` "Widget → Page Lookup" lacks `SessionDistanceCard`.
- `design_system.md:177` lists the Session Summary's headers without `DISTANCE`.
- `navigation_and_screens.md:185` states the Summary's purpose without mentioning distance entry.
- Scenario: an agent looking up the card, or the Summary's headers, is told they don't exist.
- Fix (this PR): one line each.

**F-5 — SUGGEST · DESIGN · pairing of a disambiguated id (follow-up with O-3).**
- `distance_source.dart:71` reads D-313's collision id (`obs-<e>-<n>-distance-<nowMs>`) as having no entry
  number. It therefore sorts after every numbered row, not at n as D-312 implies.
- Scenario: in Edit Session, delete an entry and add one (an id collision, F11). The user enters 2.00 km on the
  new entry "· 4". After a later Edit Session add, the 2.00 km shows on "· 5", "· 4" reads "—", and Stats pairs
  the distance with the new entry's time.
- The suffix also breaks the documented id convention (`data_models.md:53-57`), which `observation_grouper.dart:49`
  and `session_core_entry.dart:492` parse.
- It needs a scenario of its own, so it goes to a follow-up PR together with O-3.

**F-6 — SUGGEST · DESIGN · the entry-count rule for distance exists twice (follow-up).**
- The screen (`session_summary_screen.dart:955-958`) and the state (`session_core_entry.dart:407-415`) both compute
  "entries = the timed instances, or else the distance rows".
- Scenario: if one side changes (for example, to count only finished instances), a tap on "Easy Run · 2" writes a
  different entry's distance.
- Fix: one state method that returns the paired rows, used by both the Summary and the write. It spans feature and
  state, so it goes to the follow-up.

**NITs (optional, any PR).**
- N-1 (MECHANICAL): formatting-only hunks in untouched code: `models.dart:201-202`,
  `session_summary_screen.dart:823, 843-852, 1412`. Also a stale doc comment at `session_distance_card.dart:17`
  (`_absentValue`; the constant is `absentValue`).
- N-2 (MECHANICAL): two inaccuracies in the evidence file.
  - It cites `_buildDistanceSection(theme)`, but the method takes no argument.
  - Its S-837 note says the old figure divides 3000 s by 5.2 km. The old figure is 1800 s ÷ 5.2 km = 346 s/km.
- N-3 (no decision needed): Stats' day distance now counts paired rows only (`stats_progress_service.dart:651`).
  An orphan row, left behind when the second entry is deleted twice in Edit Session (F11), no longer counts. That
  is arguably a fix, but D-309 said the totals stay unchanged, so record it in the evidence.
- N-4 (MECHANICAL): the data-safety naming counts zero-valued rows (`session_summary_screen.dart:971`). Rows
  [0.0, 400 m] show a single row named "Plank · 2". This affects legacy data only.
- N-5: test fidelity. S-813 never reopens the Summary. S-820 never finishes the entry, and the repository already
  holds the value before Done. S-837 writes at the state layer, not through the Summary. S-834 uses 4873.6 instead
  of 5000. S-835's no-estimate case uses `isNot(surface)` and never checks the bar count. There is no
  rolling-session Summary test. `DistancePairing.entryNumberInId` (`distance_source.dart:46`) has no caller.

## 7. Budget triage ("At review")

- There are six substantive findings (F-1–F-6); nits are excluded.
- F-5 needs a scenario of its own and spans util, state and docs. F-6 spans feature and state. Both go to a
  follow-up PR planned with conductor-v2; the natural home is plan O-3 (pairing and id drift).
- Fix in this PR, in one round, with no second review: F-1, F-2, F-3, F-4. That is docs plus one test case, with
  no production code.
- The fix is done when: the full suite is green with at least one new test, the analyzer is at 242 issues with
  0 errors, and the doc guards are green.

## 8. Doc checks

- DOC FALSIFICATION: REJECT. F-1 (`distance_source.md:12, :34, :41, :105, :121`; `workout_state.md:106`).
- DOC FALSIFICATION: WARNING. F-4 (`widget_catalog.md` lookup; `design_system.md:177`;
  `navigation_and_screens.md:185`).
- DOC FALSIFICATION: CONFLICT. `data_models.md:53-57` (ids are `obs-{effort}-{index}-{metric}`) vs D-313's
  `-<nowMs>` suffix. Resolve it in the O-3 follow-up (F-5).
- DOC FALSIFICATION: PASS for every other doc in the set. Most have no scope block, so all are implicated. A grep
  of the whole set for distance, pace, units, observation fields, the Summary layout and dialog/crown claims found
  nothing else this change made false.
- DOC STANDARD: REJECT. F-2 (classes 2, 3 and 5; §4.2).
- DOC STANDARD: PASS for the `distance_source.md` structure (scope, structure, rationale, invariants with pointers,
  vocabulary) and for the `data_models.md`, `db_integration.md` and `README.md` additions.

## 9. Global conventions (Step 5d)

- PASS (7): units and canonical storage; theme tokens only; OmniSurface/OmniCardHeader; effort kind drives
  analytics; timestamps are source data; reuse the canonical owner; instrument panel.
- N/A: none. FAIL: none.

## 10. Architecture, test style, Assumption Log

- Layering: state and features use `WorkoutRepository` only. The util is pure Dart, the model has no Flutter
  import, and the lib changes use no `dart:io` or `Platform`.
- Widgets: the card reads no state, and no button was added.
- Test style:
  - State-layer tests are plain `test()` (S-801–S-808, S-821, S-831, S-832).
  - No `testWidgets` relies on a real `Future.delayed`.
  - `find.byType(LineChart).first` (S-835) is brittle, but `bars hasLength(2)` pins it.
- Assumption Log: all nine entries are RATIFIED. For entry #1, the list-based API is sound; F-5 concerns only the
  suffix regex.
