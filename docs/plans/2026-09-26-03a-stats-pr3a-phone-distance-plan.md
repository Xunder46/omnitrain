# Feature: Stats PR 3a — Distance entry on the Session Summary, distance source, "est." marking

> Status: CLOSED — implemented by Copilot, reviewed (fix round F-1–F-4 done), committed as 4bb4afb on `develop`
> (2026-09-27). F-5, F-6 and O-3 moved to PR 3a2: `2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`.
> Series: PR 3a of 3. Index: `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.
> Binding conventions: `docs/global_conventions.md`; `CLAUDE.md` ("Verification is observed
> output"); `docs/documentation_standard.md` (every doc edit); `.github/agents/pr_scope_budget.md`.
> Read first: `docs/session_summary.md`, `docs/stats_screen.md` (CARDIO),
> `docs/data_models.md`, and `docs/watch_session_capture.md` (why imported rows
> keep their `createdAtMs`).
> Evidence: `2026-09-26-03a-stats-pr3a-phone-distance-plan.evidence.md`. It holds the baselines and the code
> facts F1–F19, and executors append to it. Review findings go in `…plan.review.md`, which the reviewer creates.
> Branch: `feature/stats-pr3a-phone-distance` (fast-forwarded into `develop` and deleted, 2026-09-27).
> Source of scope: `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 4 (its
> phone half); the owner's answers of 2026-09-26 (Q1–Q9); the owner's Q3 decision of 2026-09-27 (D-319).
> Scope check (2026-09-27): about 520 lines (one soft signal: over 500), 3 phases, one track (the phone),
> 19 decisions, 28 scenarios, about 550 predicted production lines, no missing prerequisite. Within
> budget: two soft signals are needed to split.

## Interpretations for the owner to confirm

Q3 is now the owner's own decision: D-319, which supersedes D-305 and retires I-2. The three items
below are still applied as written until the owner confirms them; a veto becomes a superseding ledger
entry.

- **I-1 (D-304, Q2 "session summary").** The Session Summary is the only place on the phone to type or
  fix a distance. That covers the Summary right after a workout and a past session's Summary opened from
  the calendar. **Edit Session and the live session screen get no distance field in this PR.**
- **I-3 (D-319's data-safety clause).** Every entry tracked through Cardio already gets the field, so this
  clause only covers an entry **not** tracked through Cardio that still holds a stored distance. Today's
  app never writes such a row (F4, F18), so it protects legacy data, such as the retired `interval` kind.
  That distance is always shown and can be corrected or removed; removing it hides the row at once.
- **I-4 (D-306, Q7 reconciled with Q2).** The Summary gains only the DISTANCE list. Each row shows the
  exercise name, the entry number when there are several, and the distance with its unit and "est.".
  There is no pace, total, change indicator or duration.

## Overview

Nobody can record a distance on the phone today (F5). The pack's distance-source feature starts here, on
the phone, with no protocol or watch change:
- every stored distance records whether it came from GPS, was entered by a person, or was estimated;
  existing distances read as entered;
- the Session Summary lists each qualifying entry's distance, and a tap enters, corrects, confirms or
  removes it;
- the Stats cardio card marks estimates, and a day's pace counts only the entries that have a distance.

No estimated value exists until PR 3b/3c. The marking is built and tested now, with fixtures.

## Resolved Decisions (Ledger)

Immutable. Changes are made by superseding entries. D-301–D-303 bind the whole PR 3 series.

| ID | Decision | Source |
|---|---|---|
| **D-301** | **Distance source vocabulary.** Every stored distance has one source: `gps` (measured by the watch's GPS), `entered` (typed or dialled by a person) or `estimated` (the watch platform's estimate). Only `estimated` is marked. A row with no source reads as `entered`. That covers every row written before this PR and every row the phone or the watch import writes in 3a, because every distance stored today was typed or dialled (F6). | Pack item 4; Claude |
| **D-302** | **The phone's value is final.** Once a distance exists, only a phone write changes its value or its source. In 3a the Summary field is the only such writer, and it writes `entered`. Copies of a row keep its source: the edit-session restore, a block clone, and re-saving the same value. PR 3b must not let a later sync rewrite a phone-written distance. | Pack item 4; Claude |
| **D-303** | **The estimate marker (Q5: agreed).** In text, append ` est.` after the unit, in lowercase: `4.87 km est.`, `369 s/km est.`. An uppercase unit label becomes `KM EST.` / `MI EST.`. On a chart, an estimated day's point is hollow and the legend gains an `est.` item. A day that mixes estimated and other distances counts as estimated. The marker is text and shape only; there is no new colour. | Owner, 2026-09-26 |
| **D-304** | Owner answer Q2 "session summary" → **interpretation:** the Session Summary, both post-workout and past, is the only phone surface that enters or corrects a distance. Edit Session and the live session screen are unchanged. *Flagged I-1.* | Owner → Claude |
| **D-305** | **Superseded by D-319; do not build.** Owner answer Q3 "tied to the cardio modality tracked, not an exercise" → **interpretation:** the Summary shows a distance row for every **timed** entry of a session whose modality is `cardio_endurance`, whatever the exercise, with no capability or list check. A Cardio session contains only timed entries (F3); any other kind found there, from legacy data, gets no row. **Data-safety rule:** in any session, a timed entry whose stored distance is greater than 0 always gets a row. Consequences are listed in I-2. *Flagged I-2 and I-3.* | Owner → Claude |
| **D-306** | Owner answer Q7 "agreed", reconciled with Q2 → **interpretation:** the Summary gains one DISTANCE section. Each row carries only its name, the entry number when needed, and the distance with its unit label. There is no pace, total, delta, duration or other new readout anywhere on the Summary. *Flagged I-4.* | Owner → Claude |
| **D-307** | **Editing rules (Q4: agreed).** Ok in the dialog always records.<br>• Confirming the pre-filled value unchanged keeps the stored metres exactly and sets the source to `entered`.<br>• Any other value v > 0 stores v × `metresPerUnit` with source `entered`.<br>• v = 0 removes the distance: value 0.0, source null. The row then reads `—`, or disappears outside a Cardio session (D-305).<br>• Tapping outside the dialog, or Ok with empty or unparseable text, changes nothing. | Owner, 2026-09-26 |
| **D-308** | **Stats marks estimates now (Q6: agreed).** Today's Stats cardio card marks estimated distances and paces per D-303, on the single-point card text and on the chart points. | Owner, 2026-09-26 |
| **D-309** | **Pace counts only entries with a distance (Q9: agreed).** A day's pace = the sum of `actualDurationSecs` over finished timed entries whose paired distance is greater than 0, divided by the sum of those paired distances in km. The day's duration total and distance total are unchanged. If no entry qualifies, the pace is null. | Owner, 2026-09-26 |
| **D-310** | **Order and cadence (Q1, Q8: agreed).** The series runs 3a → 3b → 3c, then Stats PR 4. There is no cadence anywhere in 3a; it arrives with PR 4's cardio rows. | Owner, 2026-09-26 |
| **D-311** | **Storage.** `EffortObservation` gains a nullable `valueSource`, stored under the key `value_source`.<br>• It may be non-null only on a `metric-distance` row, and only with `gps`, `entered` or `estimated`. Otherwise the constructor throws `ArgumentError`, as `SensorSummary` does for a writer defect.<br>• No migration is needed: an absent key reads as null (F15).<br>• `scripts/sqlite_schema.sql` gets the column and a CHECK that mirrors the rule.<br>• Every field-by-field copy forwards the field (F9). | Claude |
| **D-312** | **Pairing.** An effort's distance rows are paired with its timed entries by relative order.<br>• Entries are ordered by `entryIndex`.<br>• `metric-distance` rows are ordered by the entry number in the id `obs-<effortId>-<n>-distance` (numeric), then by `createdAtMs`, then by id.<br>• One pure helper does this. The Summary field, the state write and the Stats pace all use it (F10).<br>• `SessionSummaryBuilder` and `updateEntryValue` keep their raw-order pairing (O-3). The two orders agree in a live session. | Claude |
| **D-313** | **Writes.** The state write keeps the row's id and `createdAtMs` (the watch import tells its own rows apart by `createdAtMs`) and sets `updatedAtMs` to now. If the edited entry has no paired row, it first creates zero-valued rows with no source for every unpaired entry up to and including it. Their ids are `obs-<effortId>-<i>-distance`, with `-<nowMs>` appended when that id is taken. | Claude |
| **D-314** | **Units and precision.**<br>• Display: metres ÷ `UnitFormatter.metresPerUnit(preferredDistanceUnit)`, to 2 decimals.<br>• Storage: the entered display value × `metresPerUnit`, unrounded.<br>• Pace display: `paceSecPerKm × metresPerUnit ÷ 1000`, to 0 decimals, as today.<br>• The dialog clamps to 0–999.99 display units and rounds to 2 decimals.<br>• No km↔mi constant may appear in any touched file. | Claude |
| **D-315** | **Summary section.**<br>• Header `DISTANCE` through `OmniCardHeader`, card through `OmniSurface`, placed after the modality group cards and before `SESSION NOTE`. Hidden when it has no rows.<br>• Rows follow the effort order of `getExercisesWithEntries()`, then entry order.<br>• Name: `<exercise name>`, or `<exercise name> · <n>` (n = 1-based entry position) when the effort has two or more timed entries.<br>• Value: the distance to 2 decimals, or `—` when there is none.<br>• Unit label: `KM`/`MI`, or `KM EST.`/`MI EST.` for an estimate.<br>• Tapping the row opens the dialog. | Claude |
| **D-316** | **Dialog.** Reuse `showMetricEditPopup` with the metric type `distance`.<br>• Title: `Edit Distance`.<br>• Field label: `KM`/`MI`, never `EST.`, because Ok makes the value entered.<br>• Keyboard: decimal, unsigned.<br>• Pre-fill: 2 decimals, or `0.00` when there is no distance. | Claude |
| **D-317** | **Stats estimated day.**<br>• One flag per exercise per day: true when any distance greater than 0 counted in that day's total has source `estimated`. It marks both that day's distance and its pace.<br>• An estimated point is drawn with `FlDotCirclePainter(radius: 3, color: themeColors.surface, strokeWidth: 1.5, strokeColor: <series colour>)`; other points are unchanged.<br>• Look the flag up by the spot's `x` (its trend index), not by the painter's list index.<br>• The `est.` legend item, with a hollow swatch, appears only when the card has at least one estimated point. | Claude |
| **D-318** | **Docs.** A new feature doc, `docs/distance_source.md`, indexed in `README.md` and written to `documentation_standard.md`: structure, rationale, invariants with test pointers, vocabulary. No flows, visuals or numbers. | Claude |
| **D-319** | **Supersedes D-305. Owner decision, 2026-09-27:** "every exercise in a free session or routine is assigned a modality to track through by the user, it acts similar to if a user started a cardio session. If a plank was tracked via cardio - it will get a distance field."<br>• **Rule:** an entry gets the Summary's distance row when it was tracked through Cardio, in any session — a Cardio session, a routine, Free Training, a rolling session or a watch-started session — whatever the exercise.<br>• **Detection (Claude):** effort kind `timed`. Each tracking modality maps to exactly one effort kind, and only Cardio yields `timed` (F17). The picked modality is never stored, so `timed` is the only stored record of Cardio tracking (F18). The result for each kind of session is in Notes.<br>• **Data-safety clause (Claude; flagged I-3):** a non-timed entry whose stored distance is greater than 0 also gets a row. There is one row per such distance row, in D-312 row order, named `<exercise name>`, or `<exercise name> · <n>` (n = the row's position) when the effort holds two or more. Setting 0 removes that row.<br>• This replaces D-307's "disappears outside a Cardio session (D-305)": a timed entry's row always stays, reading `—`. | Owner, 2026-09-27; Claude |

## Feature Invariants

- **Repository parity.** Hive and Mock store and return `valueSource` identically, including across a
  restart and in block clones (S-802, S-804, S-808).
- **No estimate without its marker**, on the Summary field or the Stats cardio card (S-811, S-812, S-833,
  S-835).
- **Absence is never zero.** A missing distance shows `—`, never `0.00`. A day without a paired distance
  has no pace (S-811, S-831).
- **A write keeps the row's id and `createdAtMs`** (S-805). This protects the import's ownership rule in
  `watch_session_capture.md`.
- **Only the Summary field's write changes a source.** Every copy keeps it (S-804, S-821).
- **Unchanged:** the PR definition and detection, the effort rating, the calendar, Edit Session, the live
  screen and all watch code. No file under `watch/`, `lib/watch/`, `lib/core/sync_protocol/` or
  `lib/core/services/watch_session_importer.dart` changes.

## Requirements

- **R-1:** store each distance's source, with legacy rows read as entered (D-301, D-311). **R-2:** the
  Summary's DISTANCE section (D-319, D-315). **R-3:** enter, correct, confirm and remove (D-307, D-316).
- **R-4:** mark estimates on the Summary and on Stats (D-303, D-308, D-317). **R-5:** pace counts only
  entries with a distance (D-309). **R-6:** the schema contract and the docs (D-311, D-318).

## Acceptance Criteria

- **AC-1:** every distance's source is stored, round-trips on Hive and Mock, and reads as entered for
  legacy rows; bad writes are refused. (S-801, S-802, S-803, S-808)
- **AC-2:** copies and an Edit Session discard keep the source. (S-804, S-821)
- **AC-3:** the Summary lists exactly the entries D-319 names. (S-811, S-812, S-818, S-819, S-822, S-823)
- **AC-4:** enter, correct, confirm, remove and cancel all behave per D-307. (S-805–S-807, S-813–S-817,
  S-820)
- **AC-5:** estimates are marked and measured values are not. (S-811, S-812, S-832–S-835)
- **AC-6:** pace counts only entries with a distance. (S-831)
- **AC-7:** a Summary correction reaches Stats. (S-837)
- **AC-8:** nothing else on the Summary changes, and every unit conversion goes through
  `UnitFormatter`. (S-811, S-836)

## Scenarios

**FX-CARDIO**, the shared fixture:
- **Repository and exercises:** Mock repository; exercises `ex-treadmill` "Treadmill Run" and
  `ex-easy-run` "Easy Run".
- **Session `s-cardio`:** modality `cardio_endurance`, 09:00–10:00 on a past day, no rating, one segment.
- **Effort `e-tread`** (orderIndex 0, timed, ex-treadmill): instances entryIndex 0 (1200 s, finished) and
  1 (600 s, finished); rows `obs-e-tread-0-distance` 4873.6 with source `estimated`, and
  `obs-e-tread-1-distance` 0.0 with no source.
- **Effort `e-easy`** (orderIndex 1, timed, ex-easy-run): instance 0 (1800 s, finished); row
  `obs-e-easy-0-distance` 5000.0, **stored from a map with no `value_source` key**.
- **Setup:** distance unit km unless stated; effort-rating prompt off. Load it with
  `workoutState.loadHistoricalSession('s-cardio')` and pump the Summary with `openedFromCalendar: true`
  (harness F16). In Phase 3, the same fixture is dated 1 day before now.

### Scenarios for Phase 1: stored source (state and data; Mock and Hive)

#### S-801: A legacy distance reads as entered
- Fixture: row `obs-e-easy-0-distance` (metric-distance, 5000.0), stored from a map with no `value_source`.
- Trigger: read it back through each repository.
- Expected: `valueSource` is null; it resolves to `entered`; it is not estimated; `toMap()` carries
  `value_source: null`.

#### S-802: Each source round-trips across a restart
- Fixture: effort `e-1` with distance rows -0- `gps` 1000.0, -1- `entered` 2000.0 and -2- `estimated`
  3000.0, plus one reps row with no source.
- Trigger: create them; restart Hive (close and reopen, harness F16); read everything back.
- Expected: on both repositories, the sources read back as `gps`, `entered`, `estimated` and null.

#### S-803: Writer defects are refused
- Fixture: (a) a `metric-reps` row with source `entered`; (b) a `metric-distance` row with source
  `manual`; (c) a `metric-distance` row with source `estimated` and value_real 3000.0.
- Trigger: construct each; insert each into `test/db_seed_test.dart`'s in-memory schema as a raw SQL row
  with only `value_real` set (F14).
- Expected: (a) and (b) throw `ArgumentError` and the CHECK refuses them; (c) constructs and inserts.

#### S-804: Copies keep the source
- Fixture: a rolling session (no modality) with a block holding timed effort `e-blk`: one instance, row -0-
  4873.6 `estimated`.
- Trigger: (a) `updateEntryValue('e-blk', 0, 'distance', 4873.6)`; (b) `cloneSessionBlock` of that block,
  on Hive and on Mock; (c) the source guard (Phase 1, item 6).
- Expected: (a) the row keeps `estimated`; (b) the clone's distance row is 4873.6 `estimated` on both
  repositories; (c) no `EffortObservation(` call in `lib/` passes `rpeRating:` without `valueSource:`.

#### S-805: Setting a distance
- Fixture: FX-CARDIO, state layer only, on Mock and on Hive.
- Trigger: set `e-tread` entry 1 to 1500.0 m; set `e-easy` entry 0 to 0.
- Expected: `obs-e-tread-1-distance` = 1500.0 `entered`; `obs-e-easy-0-distance` = 0.0 with no source.
  Both keep their id and `createdAtMs`, and `updatedAtMs` changes. Listeners are notified. After a Hive
  restart the values are the same.

#### S-806: Confirming unchanged keeps the number
- Fixture: FX-CARDIO, state layer.
- Trigger: confirm `e-tread` entry 0; confirm `e-tread` entry 1, which holds 0.0.
- Expected: entry 0 is exactly 4873.6, source `entered`; entry 1 stays 0.0 with no source.
- Edge of: S-805.

#### S-807: Missing rows are filled in position
- Fixture: timed effort `e-gap` with instances entryIndex 0, 1 and 2, and only one row,
  `obs-e-gap-0-distance` 0.0.
- Trigger: set entry 2 to 1500.0 m.
- Expected: row -1- is created at 0.0 with no source, and row -2- at 1500.0 `entered`; the paired
  distances are [0.0, 0.0, 1500.0].
- Edge of: S-805.

#### S-808: Pairing survives Hive key order
- Fixture: timed effort `e-12` with 12 instances (entryIndex 0–11) and rows `obs-e-12-<n>-distance` =
  (n+1) × 100.0 m, on Hive (which reads them back as -0-, -1-, -10-, -11-, -2-, …) and on Mock.
- Trigger: reload; pair them with the D-312 helper.
- Expected: entry k pairs with (k+1) × 100.0 m for every k, on both repositories.

### Scenarios for Phase 2: the Summary's DISTANCE section

#### S-811: A Cardio session lists every entry, since all are tracked through Cardio
- Fixture: FX-CARDIO, km. Trigger: open its Summary from the calendar.
- Expected: a `DISTANCE` header sits below the last group card and above `SESSION NOTE`. The rows, in
  order: `Treadmill Run · 1` | `4.87` | `KM EST.`; `Treadmill Run · 2` | `—` | `KM`; `Easy Run` | `5.00` |
  `KM`. No text on the Summary contains `/km`, `/mi` or `Pace`.

#### S-812: Miles
- Fixture: FX-CARDIO with the unit set to `mi`.
- Expected: `3.03` `MI EST.`; `—` `MI`; `3.11` `MI`.
- Edge of: S-811.

#### S-813: Correcting an estimate
- Fixture: FX-CARDIO.
- Trigger: tap `Treadmill Run · 1`. The dialog is titled `Edit Distance`, with field label `KM`
  pre-filled `4.87`. Enter `5.2`; Ok.
- Expected: the row shows `5.20` `KM`; 5200.0 m is stored as `entered`; reopening the Summary shows the
  same.

#### S-814: Confirming unchanged removes the marker
- Fixture: FX-CARDIO. Trigger: tap `Treadmill Run · 1`; Ok without editing.
- Expected: `4.87` `KM`; the stored value is exactly 4873.6 m, source `entered`.
- Edge of: S-813.

#### S-815: Entering 0 in a Cardio session
- Fixture: FX-CARDIO. Trigger: tap `Easy Run`; enter `0`; Ok.
- Expected: the row stays and shows `—` `KM`; 0.0 is stored with no source.

#### S-816: Cancelling changes nothing
- Fixture: FX-CARDIO.
- Trigger: (a) open `Treadmill Run · 1` and tap outside the dialog; (b) open it, clear the text, Ok.
- Expected: the row is still `4.87` `KM EST.`; the stored value is still 4873.6 m `estimated`.

#### S-817: Adding a distance to an empty entry
- Fixture: FX-CARDIO. Trigger: tap `Treadmill Run · 2`, which is pre-filled `0.00`; enter `1.5`; Ok.
- Expected: `1.50` `KM`; 1500.0 m is stored as `entered`.

#### S-818: Cardio tracking decides, in every kind of session
- Fixture: four completed sessions, each opened from the calendar:
  - (a) Free Training (no modality), with `Easy Run` added as Cardio (timed; entries -0- 0.0 and -1-
    3000.0, no source) and `Brisk Walk` added as Cardio (timed, 0.0);
  - (b) a `resistance_lifting` session with one set effort;
  - (c) a session with no modality, as a watch import creates, holding timed `Easy Run` entries at 2400.0
    and 0.0;
  - (d) an `isometric_stretching` session whose drill `Plank` (two holds) holds one legacy distance row,
    `obs-<effortId>-0-distance` at 400.0, written straight to the repository.
- Expected: (a) rows `Easy Run · 1` | `—` | `KM`, `Easy Run · 2` | `3.00` | `KM` and `Brisk Walk` | `—` |
  `KM`; (b) no `DISTANCE` header; (c) rows `Easy Run · 1` | `2.40` | `KM` and `Easy Run · 2` | `—` | `KM`;
  (d) exactly one row, `Plank` | `0.40` | `KM`, from D-319's data-safety clause.

#### S-819: Removing a legacy distance hides its row
- Fixture: S-818 (d). Trigger: tap `Plank`; enter `0`; Ok.
- Expected: 0.0 is stored with no source; the row and the `DISTANCE` header disappear at once.
- Edge of: S-818.

#### S-820: The post-workout Summary
- Fixture: a `WorkoutState` on Mock: `createNewSession(modality: 'cardio_endurance')`, then
  `addExerciseToSession` for Easy Run, whose one timed entry is finished at 1800 s. The Summary is pushed
  with `openedFromCalendar: false`, rating prompt off.
- Trigger: tap `Easy Run`; enter `4.2`; Ok; tap `Done`.
- Expected: before Done the row shows `4.20` `KM`; after Done the repository holds 4200.0 m `entered`
  for that entry.

#### S-821: An Edit Session discard keeps the Summary's value
- Fixture: FX-CARDIO after S-813 (entry 0 = 5200.0 `entered`), state layer.
- Trigger: `snapshotSessionState()`; `addEntry('e-tread')`; `restoreSessionSnapshot(snapshot)`; reopen
  the Summary.
- Expected: `e-tread` has two entries again; entry 0 is 5200.0 m `entered`; the rows read
  `Treadmill Run · 1` `5.20` `KM` and `Treadmill Run · 2` `—` `KM`.

#### S-822: A routine with a Cardio-tracked run and an Isometric-tracked plank
- Fixture: a completed routine session (no modality, intent `routine`) holding the routine's two efforts:
  `Easy Run`, assigned Cardio (timed; one entry, 1800 s, finished, distance row 0.0), and `ex-plank`
  "Plank", assigned Isometric (drill; two finished 60 s holds, no distance rows).
- Trigger: open its Summary from the calendar.
- Expected: exactly one row, `Easy Run` | `—` | `KM`; nothing for `Plank`.

#### S-823: A plank tracked through Cardio gets the field
- Fixture: a `WorkoutState` on Mock, with exercise `ex-plank` "Plank". `createNewSession()` (Free
  Training); `addExerciseToSession(plank, effortKindOverride: ModalityConfig.forModality(Modality.cardioEndurance)!.effortKind)`,
  then the same call with `Modality.isometricStretching`, which is the mapping the modality picker
  applies (F17). Each effort has one finished 60 s entry. The Summary is pushed post-workout, rating
  prompt off.
- Trigger: tap the `Plank` row; enter `0.4`; Ok.
- Expected: before the edit, exactly one row, `Plank` | `—` | `KM`, for the Cardio-tracked effort. After
  it, the row reads `0.40` `KM`, and the timed effort stores 400.0 m `entered`.

### Scenarios for Phase 3: Stats (Mock; sessions dated within the last 14 days)

#### S-831: Pace counts only entries with a distance
- Fixture: exercise `Treadmill Run`, one session 1 day ago with one timed effort. (a) Instances 0 and 1,
  both finished at 600 s; rows -0- 2000.0 and -1- 0.0. (b) In a fresh repository: instance 0 finished at
  600 s with row 2000.0; instance 1 notStarted (0 s) with row 1000.0.
- Expected: (a) durationSecs 1200, distanceM 2000.0, paceSecPerKm 300.0 (today it is 600.0);
  (b) durationSecs 600, distanceM 3000.0, paceSecPerKm 300.0 (today it is 200.0).

#### S-832: The estimated flag per day
- Fixture: exercise `Run`. Day −3: 1800 s, 4873.6 `estimated`. Day −2: 1800 s, 5000.0 with no source.
  Day −1: two efforts in one session, 5000.0 `gps` and 1000.0 `estimated`.
- Expected: `distanceEstimated` is true, false, true.

#### S-833: The single-point card marks an estimate
- Fixture: one day, 1800 s, 4873.6 `estimated`.
- Expected: km: the card contains `Distance: 4.87 km est.` and `Pace: 369 s/km est.`. mi: it contains
  `Distance: 3.03 mi est.` and `Pace: 594 s/mi est.`.

#### S-834: A measured point carries no marker
- Fixture: one day, 1800 s, 5000.0 with no source.
- Expected: `Distance: 5.00 km` and `Pace: 360 s/km`, with no `est.` anywhere in the card. The existing
  test `cardio single-day pace respects miles preference` passes without modification.

#### S-835: Chart points and legend
- Fixture 1: days −3, −2 and −1 at 1200 s / 4000.0 (no source), 1080 s / 4200.0 `estimated`, and
  1150 s / 4100.0 (no source). Fixture 2: the same days, none estimated.
- Expected with fixture 1: on the pace series, the dot painter returns fill `surface` and stroke
  `secondary` at x = 1, and fill `secondary` and stroke `surface` at x = 0 and 2. The distance series
  does the same with `primary`. The legend holds `Pace (s/km)`, `Distance (km)` and `est.`.
- Expected with fixture 2: no `est.` legend item, and every dot is filled.

#### S-836: Conversions go through UnitFormatter
- Fixture: `lib/features/stats/stats_screen.dart`.
- Expected: it contains none of `0.621371`, `1.609344` or `1609.3` (guard test), and S-833's miles values
  still hold.

#### S-837: A Summary correction reaches Stats
- Fixture: FX-CARDIO, dated 1 day ago.
- Trigger: correct `Treadmill Run · 1` to 5.2 on the Summary; open Stats.
- Expected: the `Treadmill Run` card reads `Distance: 5.20 km` and `Pace: 231 s/km`, with no `est.`.
  (1200 s ÷ 5.2 km; entry 2 has no distance, so D-309 leaves it out of the pace.)

## Iteration 1

**Executor rules (every phase).**
- **Scope and runs:** work one phase at a time and stop when its Done Criteria are green. Redirect suite
  output to a log and read only its tail; a run that hangs for 10 minutes is a failure.
- **Red before green:** show each new test red on unfixed code: copy the changed source file aside, revert
  the change in place, run, restore the copy, run again; record both results in the evidence file. Never
  `git stash` here (this checkout holds older stashes; a pop after an empty push applies one of them).
- **Existing tests:** never loosen an existing assertion. If one must change, record the old assertion,
  the new one and the reason in the evidence file.
- **Ambiguity and test style:** decide, then log it in the Assumption Log (3 lines at most; detail goes in
  the evidence file). Use plain `test()` for state-layer tests.
- **Conventions:** theme tokens only; `OmniCardHeader` and `OmniSurface` for headers and cards; any
  button you add sets `shape` from an `OmniTheme` radius token; state and features use the
  `WorkoutRepository` interface only.
- **Out of bounds:** nothing listed under "Unchanged" in Feature Invariants.

### Phase 1: Stored distance source (Copilot)

1. [ ] `lib/data/models/models.dart`: add `valueSource` to `EffortObservation` per D-311: constants for
   the three values, the constructor check, and `fromMap`/`toMap` under `value_source`. A `copyWith` is
   optional.
2. [ ] Forward `valueSource` in every field-by-field copy: `lib/state/workout/session_core_entry.dart`
   (`updateEntryValue`, `markSetSkipped`), and `cloneSessionBlock` in
   `lib/data/repositories/hive_workout_repository.dart` and `lib/data/repositories/mock_workout_repository.dart`.
3. [ ] New `lib/core/utils/distance_source.dart`, pure Dart: the D-312 pairing (one paired row or none
   per entry), and source resolution (null reads as `entered`) with `isEstimated`.
4. [ ] The state write, implemented in `session_core_entry.dart` and delegated from
   `lib/state/workout/workout_state.dart`. Suggested names: `setEntryDistance(effortId, entryIndex,
   metres)` and `confirmEntryDistance(effortId, entryIndex)`. It must apply the D-307 value rules, the
   D-312 pairing, and D-313's stamps and row filling; persist through `WorkoutRepository` and update the
   in-memory list; and notify listeners, reporting errors through the existing error channel.
5. [ ] `scripts/sqlite_schema.sql`: add `value_source TEXT` to `app_effort_observation`, plus
   `CHECK (value_source IS NULL OR (metric_id = 'metric-distance' AND value_source IN ('gps','entered',
   'estimated')))`. Add S-803's raw-insert cases to `test/db_seed_test.dart`.
6. [ ] New `test/distance_source_test.dart`: S-801, S-802 and S-804–S-808, on Mock and Hive (Hive harness
   F16). Add **the source guard:** scan every `lib/**/*.dart` for `EffortObservation(` calls; any whose
   argument list contains `rpeRating:` must also contain `valueSource:`. The failure message lists
   `path:line`.
7. [ ] Docs: create `docs/distance_source.md` with scope, structure (field, pairing helper,
   state write), rationale (why null reads as entered, why a confirm flips the source), invariants
   pointing at S-801–S-808, and vocabulary. Link it from `docs/README.md` and
   `docs/data_models.md`, and add the column to `docs/db_integration.md`.

**Red → green.**
- With item 1 alone, the guard fails listing 4 offenders: `session_core_entry.dart` ~245 and ~302,
  `hive_workout_repository.dart` ~2841 and `mock_workout_repository.dart` ~2029. S-804 (a) and (b) fail
  with `Expected: 'estimated' Actual: <null>`. Item 2 turns them green.
- S-803's SQL cases fail until item 5, and S-805–S-808 fail until items 3 and 4.

**Done Criteria** (run until green):
- `flutter test test/distance_source_test.dart test/db_seed_test.dart > /tmp/pr3a_p1.log 2>&1; echo
  "exit $?"; tail -2 /tmp/pr3a_p1.log` → exit 0 and `All tests passed!`.
- `flutter test > /tmp/pr3a_full.log 2>&1; echo "exit $?"; tail -2 /tmp/pr3a_full.log` → exit 0 and
  `+N ~1: All tests passed!`, where N is 3000 plus the new tests. The skip count stays 1.
- `flutter analyze > /tmp/pr3a_analyze.log 2>&1; tail -1 /tmp/pr3a_analyze.log; grep -c "^ *error •"
  /tmp/pr3a_analyze.log` → at most 242 issues and 0 errors, with every predicted file at or below its
  count in evidence §1.
- `git diff --name-only` stays within the Predicted Files, and nothing under `watch/` changes.

**Predicted Files:** `lib/data/models/models.dart`; `lib/core/utils/distance_source.dart` (new);
`lib/state/workout/session_core_entry.dart`; `lib/state/workout/workout_state.dart`;
`lib/data/repositories/hive_workout_repository.dart`; `lib/data/repositories/mock_workout_repository.dart`;
`scripts/sqlite_schema.sql`; `test/db_seed_test.dart`; `test/distance_source_test.dart` (new);
`docs/distance_source.md` (new), `README.md`, `data_models.md`, `db_integration.md`; the
evidence file.

### Phase 2: The Summary's DISTANCE section (Copilot)

1. [ ] `lib/widgets/session/metric_crown_widget.dart`: add the metric type `distance` to
   `MetricStepCalc.parseAndClamp` (clamp 0–999.99, 2 decimals), `_titleForMetric` (`Distance`),
   `_formatCurrentValue` (2 decimals) and the keyboard (`decimal: true`, `signed: false`).
2. [ ] New `lib/widgets/session/session_distance_card.dart`: renders the D-315 rows from row models
   (name, value text, unit label, onTap). It reads no state.
3. [ ] `lib/features/session/session_summary_screen.dart`:
   - build the rows:
     - D-319 visibility: every effort whose kind is `timed`, from `getExercisesWithEntries()`, with
       `observationsMap` and the D-312 helper; plus the data-safety rows for non-timed efforts. The
       session's modality plays no part.
     - D-303/D-314 formatting;
   - insert `OmniCardHeader(title: 'DISTANCE')` and the card between the group cards and `SESSION NOTE`;
   - on tap, open the D-316 dialog;
   - on Ok, apply D-307 through the Phase 1 write. Compare the returned value with the pre-filled
     2-decimal value to choose between confirm and set. Call `setState` after the write.
4. [ ] `test/crown_control_tap_to_edit_test.dart`, group `MetricStepCalc`: `distance` parses `5.2` → 5.2,
   `-3` → 0.0, `1500` → 999.99 and `4.876` → 4.88; the dialog title is `Edit Distance`.
5. [ ] New `test/session_summary_distance_test.dart`: S-811–S-820, S-822 and S-823 as widget tests
   (harness F16), and S-821 as a plain `test()`.
6. [ ] Docs: `docs/session_summary.md` (what the DISTANCE section lists, and the D-319 and
   D-307 rules as contracts with test pointers); `distance_source.md` (the Summary is the one phone
   writer); `docs/widget_catalog/session_widgets.md` (the new widget).

**Red → green.**
- S-811, S-818 (a, c, d), S-822 and S-823 fail on current code, finding 0 matches for `DISTANCE`.
- The title case fails, reading `Edit distance` from the fall-through branch, and `1500` returns 1500.0
  instead of 999.99.
- S-813–S-820 and S-823's edit fail until item 3.
- S-818 (b), S-822's `Plank` absence and S-823's single row pass before and after the change. They guard
  against over-listing: any rule that lists an entry not tracked through Cardio turns one of them red.
  A rule based on the session's modality fails S-818 (a, c) and S-822 instead.

**Done Criteria:**
- `flutter test test/session_summary_distance_test.dart test/crown_control_tap_to_edit_test.dart >
  /tmp/pr3a_p2.log 2>&1` → exit 0 and `All tests passed!`.
- The full suite and the analyzer run as in Phase 1; `session_summary_screen.dart` stays at 10 issues or
  fewer.
- The diff stays within the Predicted Files.

**Predicted Files:** `lib/widgets/session/metric_crown_widget.dart`;
`lib/widgets/session/session_distance_card.dart` (new); `lib/features/session/session_summary_screen.dart`;
`test/crown_control_tap_to_edit_test.dart`; `test/session_summary_distance_test.dart` (new);
`docs/session_summary.md`, `distance_source.md`, `widget_catalog/session_widgets.md`; the
evidence file.

### Phase 3: Stats marks estimates; pace counts only entries with a distance (Copilot)

1. [ ] `lib/core/models/stats_progress.dart`: add `CardioTrendPoint.distanceEstimated` (bool, default
   false).
2. [ ] `lib/core/services/stats_progress_service.dart` (`_processTimedEffort`, `_CardioDay`, the
   `CardioProgress` build): D-312 pairing, D-309 pace inputs, and the D-317 flag. The duration and
   distance totals stay unchanged.
3. [ ] `lib/features/stats/stats_screen.dart`: the single-point card suffixes (D-303); the estimated dots
   and the `est.` legend item (D-317); and all km↔mi math through `UnitFormatter.metresPerUnit` (D-314)
   in `_buildSingleCardioPointCard`, `_paceForDisplay` and `_distanceForDisplay`.
4. [ ] New `test/stats_distance_estimate_test.dart`: S-831 and S-832 as plain `test()`s; S-833–S-835 and
   S-837 as widget tests, with seed helpers modelled on `test/screen_widget_test.dart:2589-2690`; S-836 as
   a text guard.
5. [ ] Docs: `docs/stats_screen.md`, CARDIO section (the D-309 pace rule, and that
   estimates are marked, with test pointers); `distance_source.md` (Stats as a reader).

**Red → green.**
- S-831 fails on current code: (a) `Expected: 300.0 Actual: 600.0`; (b) `Expected: 300.0 Actual: 200.0`.
- S-833 fails because no `est.` text is found.
- S-836 fails listing three literals, in `stats_screen.dart` at ~1901, ~2011 and ~2018.
- S-834 and the existing miles test stay green both before and after. They guard against over-marking.

**Done Criteria:**
- `flutter test test/stats_distance_estimate_test.dart test/stats_progress_test.dart
  test/screen_widget_test.dart > /tmp/pr3a_p3.log 2>&1` → exit 0.
- The full suite and the analyzer run as in Phase 1; `stats_screen.dart` stays at 1 issue or fewer.
- The diff stays within the Predicted Files.

**Predicted Files:** `lib/core/models/stats_progress.dart`; `lib/core/services/stats_progress_service.dart`;
`lib/features/stats/stats_screen.dart`; `test/stats_distance_estimate_test.dart` (new);
`docs/stats_screen.md`, `distance_source.md`; the evidence file.

## Files Affected (whole feature)

The union of the three Predicted Files lists. Existing tests change only by gaining cases
(`test/db_seed_test.dart`, `test/crown_control_tap_to_edit_test.dart`); see "Unchanged" for what never changes.

## Notes

- **Which entries get a row (D-319, per F17–F19):**
  - A **Cardio session** (tile, or a planned Cardio session): every entry. **Resistance, Isometric,
    Sports sessions:** none.
  - A **routine:** the exercises assigned Cardio, picked per exercise or inherited from a Cardio focus.
    **Free Training and rolling sessions:** the exercises added as Cardio, including through the Cardio
    tile. "Track by Time" or "Track by Distance" in the Summary's Save-as-Routine sheet also makes a timed
    entry.
  - A **watch-started session:** the entries the watch logged as timed, taking the routine-declared
    kind, or else the kind from the exercise's capabilities. A run is timed; a plank is a hold.
  - **Any session:** a non-timed entry with a stored distance, under the data-safety clause.
- **Dependency graph:** 1 → 2 → 3. Phase 3 needs Phase 1's field and helper, and its S-837 needs Phase 2.
  Phase 3 can run straight after Phase 1 if the Summary work is delayed; S-837 then waits for Phase 2.
- **Intermediate states:** after Phase 1, nothing visible changes; after Phase 2, the Summary shows
  DISTANCE; after Phase 3, Stats marks estimates, and the pace changes only on days that mix entries with
  and without a distance.
- **Legacy data:** no migration. An absent key reads as null, which reads as `entered`. Real `estimated`
  and `gps` rows arrive with PR 3b/3c; until then only the fixtures hold them.
- **Non-goals:** a distance field in Edit Session or on the live screen (D-304); pace, totals or deltas
  on the Summary (D-306); cadence (D-310); the watch, the protocol and the import (PR 3b/3c); the stale
  Stats doc sections (O-5).

## Open Items

- **O-1 — BLOCKER (process): `develop` is unpushed.** It is 17 commits ahead of origin
  (`origin/develop` = f1f9aaa). A GitHub-hosted Copilot agent branches from origin, so push before the
  handoff. A local Copilot session is unaffected.
- **O-2 — Owner confirmation of I-1, I-3 and I-4** (D-304, D-319's data-safety clause, D-306). Q3 is
  settled (D-319). A veto becomes a superseding D-3xx before
  Phase 2 starts.
- **O-3 — Pre-existing pairing and id drift (F10, F11).** The builder and `updateEntryValue` pair in raw
  order. Deleting a timed entry deletes rows by the current index's id prefix. Adding an entry can reuse
  a row id after a deletion, which can overwrite a Summary-entered distance after an Edit Session delete
  followed by an add. This needs its own design and structural guard; it is a candidate small PR after 3a.
  - **F-5 (review):** `DistancePairing` reads D-313's collision id (`-<nowMs>` suffix) as having no entry
    number, so such a row sorts last instead of at *n*, and the suffix breaks the id convention
    `data_models.md` documents and two parsers read.
  - **F-6 (review):** the "entries = timed instances, else distance rows" rule exists twice, in the
    Summary and in `SessionCore`; one state method returning the paired rows should own it.
- **O-4 — Pre-existing schema drift (F14).** `toMap` writes `value_bool: 0` where the CHECK allows only
  one value column. Not fixed here.
- **O-5 — Stale Stats doc sections.** RECORDS, VOLUME TRENDS and CONSISTENCY (pack D-13) are left for
  PR 4.

## Progress

Baselines (evidence §1): 3000 passed, 1 skipped; analyzer 242 issues, 0 errors; Swift 242 (untouched).

- [x] Phase 1: stored distance source — complete (evidence §3; suite `+3020 ~1`, analyzer 242/0 errors)
- [x] Phase 2: the Summary's DISTANCE section — complete (evidence §3; suite `+3041 ~1`, analyzer 242/0 errors)
- [x] Phase 3: Stats estimates and pace — complete (evidence §3; suite `+3051 ~1`, analyzer 242/0 errors)
- [x] Review: `/code-reviewer` — CHANGES REQUESTED, then F-1–F-4 fixed in this PR (evidence §3, review round); F-5, F-6 carried into O-3

## Assumption Log

<!-- Executors append here: decision, options considered, choice and why. At most 3 lines each; detail
     goes in the evidence file. The reviewer marks each entry RATIFIED (promoted to a D-3xx) or REVERT. -->

- **Phase 1 — pairing takes a row list, not an effort id.** `DistancePairing.forEntries` reads the entry number from the `-<n>-distance` suffix, since one effort's rows share the `obs-<effortId>-` prefix; `entryNumberInId` keeps the scoped check for callers holding the id. Detail: evidence §3.
- **Phase 1 — the write reports through `_setError`, not a return value.** Both new methods are `Future<void>` like every other `SessionCore` write; the in-memory list is updated after each repository call and listeners are notified. Detail: evidence §3.
- **Phase 1 — confirming an entry with no paired row does nothing.** A pre-filled `0.00` is not a value the user supplied, so a confirm would store a number nobody chose. Detail: evidence §3.
- **Phase 2 — the estimate marker is a suffix of the unit label**, not a row flag: the card renders `KM EST.` and carries no `isEstimated`. Detail: evidence §3.
- **Phase 2 — confirm is chosen by comparing the answer with the pre-filled value at 2 decimals.** Comparing unrounded units would treat `4.87` against a stored `4873.6` as a change and overwrite the metres. Detail: evidence §3.
- **Phase 2 — rows are built from `getExercisesWithEntries()`**, so the Summary's own effort order is the only source of row order. Detail: evidence §3.
- **Phase 3 — `_CardioDay` carries the pace's two sums, not a paced day.** A day merges several efforts, so its pace is a ratio of the merged sums; keeping the inputs makes the merge exact. Detail: evidence §3.
- **Phase 3 — the estimate flag merges with OR across the day.** Pace and distance share a point, so one estimated distance marks both rather than one series. Detail: evidence §3.
- **Phase 3 — an unfinished entry contributes its distance to the day's total but no pace time.** The total is "distance recorded that day"; the entry's seconds are a target, not a measurement. Detail: evidence §3.

## Feedback

Review 2026-09-27: CHANGES REQUESTED. Findings, evidence and mutation results: `2026-09-26-03a-stats-pr3a-phone-distance-plan.review.md`.
Fix in this PR in one round (docs + one test, no production code); F-5 and F-6 go to a follow-up PR with O-3.

- [x] F-1: delete the false "only / nothing else" claims in `distance_source.md` (:12, :34, :41, :105, :121) and `workout_state.md:106`; name the raw-order paths (O-3) — done
- [x] F-2: remove prohibited doc content: `stats_screen.md:211-213` and :197-202, `session_widgets.md:38, 88, 138-142`, `session_summary.md:52`, `workout_state.md:106-107` → test pointers — done
- [x] F-3: extend S-835 with a day that has no distance, so the estimate dot is checked by its x, not list position — done (red at `+8 -1`, green at `+11` on the file)
- [x] F-4: add `SessionDistanceCard` to `widget_catalog.md` lookup, `DISTANCE` to `design_system.md:177`, distance entry to `navigation_and_screens.md:185` — done
