# Per-Exercise Best-Load Defect — Investigation Finding

> **Status: investigation only.** No application code, test, or model was changed by this
> work. This document does not propose a fix or a design.
>
> **HISTORY — frozen record.** Superseded in part. The Records section this finding
> analyses has since been deleted, so the surfaces it names no longer all exist; where it
> disagrees with `lib/`, `lib/` wins. The analysis itself is unchanged.
>
> **Phase F** of `docs/plans/stats-screen-remediation-plan.md` (Decision Ledger
> **D-9**, Scenario **S-701**).
>
> **Investigated:** 2026-08-16. **Working-tree state:** Phase A–E of the remediation plan are
> applied but uncommitted; `HEAD` is `1c7c903`. Wherever this document cites deleted code it
> cites `HEAD` explicitly; unqualified `file:line` citations are the **working tree**.

Every finding below is tagged:

- **VERIFIED** — read directly out of source or git history; the citation is sufficient to
  re-check it.
- **INFERRED** — consistent with the code but not proven by it.
- **NOT DETERMINED** — the evidence available in this repository does not settle it. What
  would settle it is stated.

---

## Executive summary

1. The deleted Records section's "Heaviest load" figure was **the weight × reps product of a
   single set** — specifically the set with the greatest `metric-weight` in the exercise's
   history. It was never the weight of that set. **VERIFIED.**
2. The premise that reached this investigation — "fed by a total-volume quantity … plausible
   as accumulated session totals" — is **close but not exact**, and the difference matters.
   Nothing was accumulated. One set's tonnage was displayed under a label that named a
   weight, converted with a kg→lbs factor, and rendered with a weight unit. **VERIFIED.**
3. The exact computation that produced the wrong values is **gone and unreachable** — no
   caller, no model, no test. **VERIFIED.**
4. **But a quantity of the same kind and the same magnitude is still on screen today**, in two
   places, under the label `Volume` / `Total Volume`. Those labels name the quantity
   correctly, so this is a unit problem, not a lie. **VERIFIED.**
5. **The label/quantity mismatch that survived is a different one:** the **Recent PRs** card
   and the **session summary PR line** both show an *Epley estimated* 1RM formatted as a raw
   weight with no qualifier. The user reads "Squat — 132.0 lbs" for a weight they may never
   have lifted. **VERIFIED.** This is the finding with live user impact.
6. The uniform rep record of exactly **ten** is **not** produced by a cap or a clamp — none
   exists anywhere in `lib/`. It is produced by a **persisted default**: every set effort is
   written to the repository with `metric-reps = 10` at the moment the exercise is added to a
   session, before the user logs anything. **VERIFIED** for the mechanism; **INFERRED** that
   this is what the user's account actually hit.
7. The deleted test `S-001: heaviest-load record equals the max load × reps set` is a textbook
   instance of the pattern this feature has been finding: it asserted the wrong quantity,
   passed, and carried an in-line comment that *rationalised* the wrong quantity with a
   justification that is arithmetically false. **VERIFIED.**

---

## Section 1 — Every computation that produces a per-exercise best or heaviest load figure

There are **six**. Four are live; two are deleted.

### 1.1 `_accumulateSetForRecords` → `ExerciseRecord.heaviestLoad` — DELETED

- **Location (deleted):** `HEAD:lib/core/services/stats_progress_service.dart:1638`, assignment
  at `:1675`; consumed by `computeExerciseRecords()` at `HEAD:…:1177`, packed into the model at
  `HEAD:…:1289`.
- **What it actually computed:** the **product `weight × reps` of one single set** — the set
  with the highest `metric-weight` across the exercise's entire completed history. Selection is
  by max weight; the value carried is that set's tonnage.

  ```dart
  final existingWeight = existing?.weight ?? -1.0;
  if (existing == null ||
      weight > existingWeight ||
      (weight == existingWeight && sessionDay.isBefore(existing.date))) {
    heaviest[exId] = _HeaviestRecord(
      value: weight * reps,   // ← the stored value is the SET's tonnage
      date: sessionDay,
      weight: weight,         // ← the actual heaviest weight, never displayed
      reps: reps,
    );
  }
  ```

- **VERIFIED — how:** `git show HEAD:lib/core/services/stats_progress_service.dart` lines
  1638–1700. The model's own doc comment agrees and is explicit about the unit:
  `HEAD:lib/core/models/stats_progress.dart:356` — *"Heaviest load × reps figure (kg·reps)"*.
  The units are **kg·reps**. The screen rendered it with a **kg/lbs** label (§2.1).

- **VERIFIED — not an accumulation:** the map is *assigned*, never `+=`'d. Each `entry` from
  `ObservationGrouper.groupByEffortKind('set', …)` is exactly one set — the indexed path keys
  entries by the set index parsed out of the observation id, and the fallback path flushes one
  entry per reps+weight pair (`lib/core/utils/observation_grouper.dart:46–119`). So the figure
  is one set's tonnage, not a session total and not an all-time total.

- **VERIFIED — only one version ever shipped.** `git log -G'_accumulateSetForRecords'` returns a
  single commit, `35763b2` (2026-08-11), which is also the most recent commit to touch the file.
  `git show 35763b2:lib/core/services/stats_progress_service.dart` already contains
  `value: weight * reps` at line 1675. There is no earlier variant of this computation to
  account for the user's data — whatever the user saw, this code produced it.

  A comment inside the deleted method describes a *prior* defect in which the weight comparison
  was reconstructed as `existing.value / _recordRepsFor(...)`, freezing the record permanently.
  That helper does not exist in `HEAD` — only the comment survives. **NOT DETERMINED** whether
  that variant ever reached a user build; it is not in git history on this branch. It does not
  change the finding, because the freeze bug affected *which* set won, not *what quantity* was
  stored.

### 1.2 `_accumulateSetForRecords` → `ExerciseRecord.mostRepsAtLoad` — DELETED

- **Location (deleted):** `HEAD:lib/core/services/stats_progress_service.dart:1688`.
- **What it actually computed:** the **highest rep count in any single set**, plus the load
  (kg) of that set, plus its date. Ties broken by *earliest* date. Both bodyweight
  (`loadKg = 0.0`) and loaded sets participate.
- **VERIFIED — how:** `git show HEAD:…:1683–1694`. The label was accurate; see §4 for why the
  *values* were uniform.

### 1.3 `computeProgressData` → `LiftProgress.e1RmTrend` — LIVE

- **Location:** `lib/core/services/stats_progress_service.dart:371`, `:378`.
- **What it actually computes:** an **estimated one-rep maximum** — the maximum Epley e1RM
  across the day's sets, one point per training day. Epley is
  `weight × (1 + reps / 30)` (`:944–947`).
- **This is an estimate, not a lifted weight.** A 100 kg × 10 set yields 133.3, a number the
  lifter has never had on the bar.
- **VERIFIED — how:** direct read of `:369–382` and `:944–947`.

### 1.4 `computeProgressData` → `LiftProgress.volumeTrend` — LIVE

- **Location:** `lib/core/services/stats_progress_service.dart:374`, `:381`.
- **What it actually computes:** **Σ (weight × reps) across all of the day's sets**, one point
  per training day. This is an accumulated total across a training day, in **kg·reps**.
- **VERIFIED — how:** `totalVolume += set.weight * set.reps;` at `:374`, emitted at `:381`.
- This is the closest live relative of the deleted heaviest-load figure — same dimensional
  category (kg·reps), same order of magnitude, same downstream conversion. See §3.

### 1.5 `getAllTimeBestE1RM` / `getAllTimeBestReps` — LIVE

- **Location:** `lib/core/services/stats_progress_service.dart:972` and `:1043`.
- **What they actually compute:**
  - `getAllTimeBestE1RM` — the **highest estimated 1RM** ever logged for the exercise across
    completed sessions only. Returns `0.0`, not null, when there is no history.
  - `getAllTimeBestReps` — the **highest single-set rep count** ever logged, walking **only
    sets with `weight == 0`** (`:1071` — `if (weight != 0.0) continue;`). Loaded sets never
    contribute.
- **VERIFIED — how:** direct read of both method bodies.
- Note the asymmetry with the deleted `mostRepsAtLoad` (§1.2), which counted **all** sets
  including loaded ones. That is why the user's "rep record @ 65 lbs" / "@ 140 lbs" could only
  have come from the deleted Records section — the live reps path structurally cannot report a
  non-zero load.

### 1.6 `SessionSummaryBuilder` → `ExerciseSummary.bestWeight` / `bestE1RM` / `bestReps` — LIVE

- **Location:** `lib/state/workout/session_summary_builder.dart:62–108`, packed at `:177–182`.
- **What each actually computes, within one session only:**
  - `bestWeight` (`:77–81`) — the **genuine heaviest single set's weight**, in kg. This is the
    one computation in the codebase that really does compute a heaviest load. **It is never
    displayed** (§2.6).
  - `bestE1RM` (`:90–96`) — max Epley e1RM across the session's sets. An estimate.
  - `bestReps` (`:106–108`) — max reps among **bodyweight** sets only (`weight == 0.0`),
    mirroring §1.5.
- **VERIFIED — how:** direct read.

---

## Section 2 — Every surface that displays one of those computations

| # | Surface | Location | Fed by | Label the user sees | Label accurate? |
|---|---|---|---|---|---|
| 2.1 | Records card — "Heaviest load" | `HEAD:…/stats_screen.dart:966` | §1.1 | `Heaviest load` + `2205 lbs` | **No — deleted** |
| 2.2 | Records card — "Most reps" | `HEAD:…/stats_screen.dart:974` | §1.2 | `Most reps` + `10 reps @ 65 lbs` | Yes — deleted |
| 2.3 | Strength card — Estimated 1RM | `stats_screen.dart:320`, `:332` | §1.3 | `Estimated 1RM` | **Yes** |
| 2.4 | Strength card — Volume | `stats_screen.dart:341`, `:353` | §1.4 | `Volume` + `kg`/`lbs` | Name yes, **unit no** |
| 2.5 | Recent PRs card | `stats_screen.dart:549`, `:574` | §1.3 | `Recent PRs` + bare `132.0 lbs` | **No** |
| 2.6 | Session summary — Total Volume | `session_summary_screen.dart:878` | `SessionSummary.totalVolume` | `Total Volume` + `kg`/`lbs` | Name yes, **unit no** |
| 2.7 | Session summary — PR line | `session_summary_screen.dart:936` | §1.6 `bestE1RM` | `New best 132.0 lbs (was …)` | **No** |
| 2.8 | In-session PR toast | `widgets/session/pr_toast.dart` | §1.5 (gate only) | `Congrats! New PR` | **N/A — no number** |
| 2.9 | Exercise detail (read-only, PR 7) | `exercise_detail_view_screen.dart` | — | *no load figure at all* | N/A |
| 2.10 | Exercise library detail (PR 8) | `exercise_library_detail_screen.dart` | — | *no load figure at all* | N/A |

### 2.1 Records card — "Heaviest load" — DELETED

```dart
'Heaviest load',
'${UnitFormatter.convertWeight(record.heaviestLoad!.value, widget.settingsState).toStringAsFixed(0)} $weightLabel',
```

`HEAD:lib/features/stats/stats_screen.dart:966–967`.

**This is the defect, stated plainly.** The value is a **kg·reps** product (§1.1). It is passed
through `UnitFormatter.convertWeight`, which multiplies by `2.20462`
(`lib/core/utils/unit_formatter.dart:6, 24–28`) — a kg→lbs factor applied to a kg·reps
quantity — and then rendered next to a bare `lbs` or `kg` label under the word
**"Heaviest load"**.

**Which one is wrong — the label or the quantity?** The **quantity**. "Heaviest load" is the
right thing for a Records section to show, and the correct value was sitting unused in the very
same record: `_HeaviestRecord.weight`, populated on the line below the one that was displayed.
The label described what the user wanted; the code handed it the wrong field.

The conversion is arithmetically self-consistent, which is why the number looked plausible
enough to ship. Because `convertWeight` is linear:

> **displayed figure = (the set's weight as the user sees it) × (that set's reps), exactly.**

So a set the user entered as `220.5 lbs × 10` displays as `2205 lbs`; entered as `105 lbs × 21`
it also displays as `2205 lbs`.

**On the two reported real-data figures:**

- `2205 lbs` ⇒ stored value ≈ **1000.0 kg** (`2205 / 2.20462 = 1000.17`; `toStringAsFixed(0)`
  admits any stored value in `[999.94, 1000.40]`). This matches the reported observation that
  the storage-unit figure is exactly round. **VERIFIED** as consistent with §1.1.
- `1601 lbs` ⇒ stored value ≈ **726 kg**. **VERIFIED** as consistent with §1.1.
- **NOT DETERMINED:** the exact `weight × reps` decomposition behind either number. `1000 kg`
  admits `100 × 10`, `125 × 8`, `50 × 20`, and more; `726 kg` admits `66 × 11`, `60.5 × 12`,
  `121 × 6`. Note that `1601` is prime, so no whole-lbs × whole-reps pair produces it exactly —
  the stored weight is not a round pound value, which points toward kg-native entry, but a
  half-pound value (`145.5 × 11 = 1600.5 → "1601"`) fits equally well.
  **What would settle it:** reading the `metric-reps` and `metric-weight` observation rows for
  those two exercises out of the user's Hive box. That data is not in this repository, and no
  amount of code reading substitutes for it.
- **INFERRED (not verified):** if the `weight × reps` decomposition uses `reps = 10`, both
  figures resolve to round stored weights (`100 kg` and `160.1 lbs`), and `reps = 10` is
  exactly what §4 predicts this account is full of. This is suggestive, not proof.

### 2.2 Records card — "Most reps" — DELETED

`HEAD:lib/features/stats/stats_screen.dart:974–977`. Rendered `${reps} reps @ ${load} lbs`.
The label matched the quantity (§1.2). The load here is a genuine set weight, correctly
converted. **This surface was accurate**; §4 explains why its numbers still looked wrong.

### 2.3 Strength card — Estimated 1RM — LIVE, correct

`lib/features/stats/stats_screen.dart:320` and `:332` label the series **"Estimated 1RM"**.
Fed by §1.3. **This is the one weight-shaped figure on the Stats screen whose label tells the
truth**, and it is the model the other two should be measured against.

### 2.4 Strength card — Volume — LIVE

`lib/features/stats/stats_screen.dart:341` (chart) and `:353` (single-point card), converted at
`:284–291`. Fed by §1.4 — Σ weight×reps for the day, in kg·reps, converted with the kg→lbs
factor and labelled `kg`/`lbs`.

**Label verdict:** the *name* is right — this is volume, and the user is told so. The *unit* is
a category error: kg·reps is not kg. **This is a long-standing, deliberate, tested convention**,
not an accident — `test/data_tracking_fixes_test.dart:196–270` asserts that a 10 × 100 kg
session must format as `1000` in the volume display, and the group header documents the
intent. Gym usage ("tonnage in kg") makes it conventional. It is called out here for
completeness, not as a defect claim.

### 2.5 Recent PRs card — LIVE — **label does not match the quantity**

```dart
final displayE1Rm = UnitFormatter.convertWeight(pr.e1Rm!, widget.settingsState);
valueText = '${displayE1Rm.toStringAsFixed(1)} $weightLabel';
```

`lib/features/stats/stats_screen.dart:571–574`, under the heading `'Recent PRs'` at `:549`.

The row renders as `Squat  ·  132.0 lbs` with a trophy icon. The number is an **Epley
estimate** (§1.3) — it is not a weight the user lifted, and nothing on the card says so. The
adjacent Strength card on the *same screen* labels the identical quantity **"Estimated 1RM"**
(§2.3), so the screen contradicts itself: the same computation is qualified in one card and
presented as a bare weight in the other.

**Which is wrong — the label or the quantity?** The **label**. e1RM is the correct quantity for
a PR feed (it is what makes a rep-driven improvement at a sub-maximal weight count as a
record). The presentation is what fails: a bare weight unit with no "est." qualifier invites the
user to read it as iron on the bar.

**VERIFIED — how:** direct read of `:544–580`; cross-checked against `:317–336` for the
qualified rendering of the same series.

### 2.6 Session summary — Total Volume — LIVE

`lib/features/session/session_summary_screen.dart:878–879`, `_formatWeight` at `:1136`.
`SessionSummary.totalVolume` is Σ reps × weight over the whole session
(`session_summary_builder.dart:74`). Same verdict as §2.4: name right, unit conventional.

### 2.7 Session summary — PR line — LIVE — **label does not match the quantity**

```dart
pr.metricLabel == 'reps'
    ? '${pr.exerciseName}: New best ${pr.newBest.toInt()} reps (was ${pr.previousBest.toInt()} reps)'
    : '${pr.exerciseName}: New best ${_formatWeight(pr.newBest)} (was ${_formatWeight(pr.previousBest)})',
```

`lib/features/session/session_summary_screen.dart:934–936`.

On the weight axis `pr.newBest` is `bestE1RM` (`session_summary_service.dart:242`) — an
estimate — printed as `New best 132.0 lbs`. Same mismatch as §2.5, same axis, same formula.

**Sharpest evidence that this is unintentional:** the service already sets
`metricLabel: 'e1RM'` at `session_summary_service.dart:240`, and that string is **never
rendered**. `metricLabel` is read in exactly one place in `lib/` — line `:934` above — and only
as a branch selector (`== 'reps'`). The label that would have made the number honest is
computed, carried through the model, and dropped at the last step.

**VERIFIED — how:** `grep -rn "metricLabel" lib/` returns four hits: the model field, the two
producers, and the single branch-selector consumer. No render path.

### 2.8 In-session PR toast — LIVE, correct

`lib/features/session/workout_session_screen.dart:845–916` gates on §1.5; the toast itself
(`lib/widgets/session/pr_toast.dart`) shows a trophy and the text `Congrats! New PR` and
**displays no numeric value at all**. There is no label to mismatch. **VERIFIED.**

### 2.9 / 2.10 Read-only exercise detail surfaces — LIVE, no load figures

Both `lib/features/exercise/exercise_detail_view_screen.dart` (PR 7) and
`lib/features/exercise/exercise_library_detail_screen.dart` (PR 8, which re-renders the PR 7
body) display **only metadata**: Discipline, Tracking Methods, Movement Properties, Muscles
(`exercise_detail_view_screen.dart:252, 263, 283, 299`). Neither imports `UnitFormatter`,
neither computes or displays any per-exercise best, heaviest, volume, or rep record.
**VERIFIED — how:** `grep -rln "convertWeight\|formatWeight\|weightLabel" lib/features/` returns
seven files and neither detail screen is among them.

### 2.11 Consistency across surfaces

For the **same exercise**, Recent PRs (§2.5) and the session summary PR line (§2.7) will agree
— both print the same Epley e1RM, and `test/services_test.dart:620–693` is a real
cross-surface parity test that asserts exactly this (toast / Stats / summary produce the same
`e1Rm`). The deleted Records "Heaviest load" (§2.1) agreed with **neither**, since it was a
third, dimensionally different quantity. That disagreement is what D-7 recorded as
"displays contradictory values", and it was correctly diagnosed.

---

## Section 3 — Reachability: is the broken computation still reachable?

**The specific computation is gone. VERIFIED.**

```
grep -rn "computeExerciseRecords\|ExerciseRecord\|heaviestLoad" lib/ test/
→ no matches
```

`computeExerciseRecords()`, `_accumulateSetForRecords`, `_HeaviestRecord`, `_MostRepsRecord`,
`ExerciseRecord`, `RecordValue`, `MostRepsRecord`, `_buildRecordsSection`, `_buildRecordsCard`,
`_buildRecordRow`, and the `_exerciseRecords` state field are all absent from the working tree.
The single call site was `HEAD:lib/features/stats/stats_screen.dart:113`; it is deleted. **There
is no other consumer, and no surface can reach it.**

**But the answer to the question actually being asked — "does the wrong number reappear
somewhere worse?" — is a qualified yes, on two separate counts:**

1. **Same magnitude, honest label.** §1.4's `volumeTrend` (Stats → Strength card → `Volume`) and
   `SessionSummary.totalVolume` (session summary → `Total Volume`) are Σ weight×reps in the same
   kg·reps units, converted through the same `convertWeight` call, displayed with the same
   weight label. A user whose Records card said `Heaviest load 2205 lbs` will see numbers of the
   same and larger magnitude on the Strength card today — but under the word **Volume**, which
   is what they are. **The user is not misled here.** Removing the Records section removed the
   misleading label while leaving the quantity where it belongs.

2. **Different quantity, dishonest label — this is the live exposure.** §2.5 (Recent PRs) and
   §2.7 (session summary PR line) present an **estimated** 1RM as a bare weight. This is a
   surface the user demonstrably trusts — it carries a trophy icon and the words "PR" and "New
   best" — and the number it shows is systematically **higher than any weight the user has
   lifted** (Epley inflates by `reps/30`; a 10-rep set inflates by 33%). It is a smaller error
   than the Records defect, but it lives on a more trusted surface and it is still shipping.

**NOT DETERMINED:** whether any user has actually misread §2.5/§2.7. No telemetry, no report.
The claim here is structural — the label omits a qualifier the same screen applies elsewhere —
not observational.

---

## Section 4 — The uniform rep record of exactly ten

### 4.1 Is there a cap, clamp, or ceiling on a rep-record value?

**No. VERIFIED.**

Searched `lib/` for `clamp`, `min(`, `max(`, and every comparison involving `reps`. Every
constraint found on a rep value is a **floor**, never a ceiling:

| Location | Constraint | Direction |
|---|---|---|
| `stats_progress_service.dart:575` | `if (reps <= 0) continue;` | floor |
| `stats_progress_service.dart:945` | `if (weight <= 0 \|\| reps <= 0) return null;` | floor |
| `stats_progress_service.dart:417`, `:1073` | `if (reps > best) best = reps;` | unbounded max |
| `session_summary_builder.dart:106–107` | `if (reps > bestReps) bestReps = reps;` | unbounded max |
| `HEAD:…:1683` (deleted) | `reps > existingMostReps.reps` | unbounded max |

The only clamps in the codebase are on water volume
(`hive_workout_repository.dart:2311`, `mock_workout_repository.dart:1507`) and on the exercise
ranking score (`workout_repository.dart:289`). Neither touches reps.

`WorkoutConstants.maxEntriesPerEffort` bounds the number of **sets per effort**, not the reps
within a set. No rep ceiling exists.

### 4.2 Is a uniform ten explainable by the recorded data?

**Yes — and the mechanism is a persisted default, not a computation artifact. VERIFIED.**

`10` is the app's default rep value, and it is **written to the repository as a real
observation** at the moment an exercise is added to a session — before the user has logged
anything:

```dart
// lib/state/workout/session_core_entry.dart:58  (inside addExerciseToSession)
await addEntry(effortId);
```

```dart
// lib/state/workout/session_core_entry.dart:174–184  (inside addEntry, effortKind == 'set')
observations.add(
  EffortObservation(
    id: 'obs-$effortId-$entryIndex-reps',
    …
    valueInt: (previousValues?['reps'] as int?) ?? 10,   // ← the default
  ),
);
…
for (final obs in observations) {
  await _repository.createObservation(obs);              // ← persisted immediately
}
```

Three further `10` defaults exist, all consistent:
`lib/core/constants/effort_defaults.dart:23` and `:58` (template drafts, `MetricIds.reps: 10`),
`lib/state/workout/session_core_entry.dart:222` (non-`set` fallback branch), and
`lib/features/routine/routine_setup_screen.dart:1368` (routine editor display fallback).

**Why this produces a uniform ten across many unrelated exercises:**

1. Adding any exercise to a session persists `reps = 10, weight = 0.0` for set 1 immediately
   (`session_core_entry.dart:58` → `:174–195`).
2. **Nothing distinguishes an untouched default from logged work.** The persistence-level
   "skipped" marker is `reps == 0`; `_skippedSets` in
   `lib/features/session/workout_session_screen.dart:121` is explicitly commented "UI-only
   state" and is never persisted. `ObservationGrouper` does populate an `entry['skipped']` key
   (`observation_grouper.dart:67`), but **no computation in `lib/` ever reads it** —
   `grep -rn "'skipped'" lib/` returns only the grouper's own writes. Both the deleted
   `_accumulateSetForRecords` and the live `_processSetEffort` gate solely on `reps <= 0`.
3. A default set therefore contributes `10 reps` to the record for that exercise.
4. Users adjust **load**, not reps — the load is the thing that changes between sessions. A set
   left at the default rep count but given a real weight persists as exactly
   `10 reps @ <real weight>`, which is precisely the shape the user reported:
   `10 reps @ 65 lbs`, `10 reps @ 140 lbs` (rendered by
   `HEAD:lib/features/stats/stats_screen.dart:974–977`).
5. Manually added subsequent sets inherit the previous set's values
   (`workout_session_screen.dart:1058–1071` builds `previousValues`), so a `10` propagates
   through the whole effort rather than being corrected.

**The bundled demo routines are excluded as a cause. VERIFIED.** `lib/mock/demo_routines_seed.dart`
specifies rep targets of `5, 8, 12, 15` (lines 130, 140, 150, 189, 199, 209, 248, 258, 309,
319, 358) and **never 10**. Template targets overwrite the default via
`session_core_io.dart:258–288`, and `_calculateSetCount`
(`routine_session_service.dart:96–107`) derives set count from the max declared `setIndex`, so
every set a demo routine creates has an explicit non-10 target. A demo-sourced session cannot
produce a uniform ten. This is consistent with the report that the anomaly appeared in real,
non-seeded data.

### 4.3 Verdict

- **VERIFIED:** no cap, clamp, or ceiling on any rep-record value exists in `lib/`.
- **VERIFIED:** `10` is a persisted default written at exercise-add time, indistinguishable
  downstream from a genuine 10-rep set, and the demo routines cannot be the source.
- **VERIFIED:** the uniform ten is therefore a **data artifact** — real rows in the repository
  holding the value `10` — and **not** a computation artifact. `computeExerciseRecords` reported
  faithfully what was stored.
- **INFERRED, NOT VERIFIED:** that the specific exercises on the user's account acquired their
  `10`s through the untouched-default path rather than through the user genuinely performing
  sets of ten. Both produce byte-identical rows; **the repository cannot distinguish them, and
  neither can this investigation.**
  **What would settle it:** inspecting the user's `metric-reps` rows alongside their
  `metric-weight` siblings — a preponderance of efforts whose *every* set is exactly `10` while
  weights vary freely would confirm the default path; a natural spread of rep counts with `10`
  merely being common would refute it.

---

## Section 5 — Tests that assert a heaviest-load or rep-record value

### 5.1 `S-001: heaviest-load record equals the max load × reps set` — DELETED, was passing for the wrong reason

`HEAD:test/stats_progress_test.dart:3333–3397`.

```dart
// Heaviest load value is the kg × reps of the heaviest set
// (120 × 3 = 360), NOT the raw weight (120). This matches
// the e1RM-on-the-weight-axis convention: the record carries
// the full strength figure, not the input weight.
expect(r.heaviestLoad!.value, closeTo(360.0, 0.01));
```

This is the strongest single piece of evidence in the investigation, for three reasons:

1. **The test asserted the defect and locked it in.** `360.0` is `120 × 3` — the tonnage of one
   set. The test name says *"heaviest-load record"*. It passed, and it guaranteed the wrong
   quantity would keep being produced.
2. **Its justification is arithmetically false.** The comment claims the value "matches the
   e1RM-on-the-weight-axis convention". The Epley e1RM of `120 kg × 3` is
   `120 × (1 + 3/30) = 132.0`, not `360.0` (`stats_progress_service.dart:944–947`). `360` is not
   an e1RM under any convention in this codebase. The comment did not describe the code — it
   supplied a plausible-sounding reason to stop questioning it.
3. **The fixture contradicts its own assertion.** The seed comments read
   `// Day 1: 100 kg × 5 → load 100.` and `// Day 2: 120 kg × 3 → load 120 (the heaviest).` —
   the fixture author used "load" to mean **the weight**, matching what the UI label promised,
   then asserted `360`. The disagreement is visible inside a single 60-line test.

This is the same pattern flagged for this feature — a test whose *name and comments* claim a
behavioral guarantee its *assertions* do not deliver — but a more dangerous variant: the
assertion is not merely weak, it is precise, confident, and wrong, and it carries a false
rationale that would deflect a reviewer.

### 5.2 Other deleted record tests

The `computeExerciseRecords` group (`HEAD:test/stats_progress_test.dart:3332`, 10 references)
was removed wholesale in Phase A. Two more asserted the tonnage figure under a heaviest-load
name:

- `S-001b … heaviestLoad keeps updating after the most-reps record moves`
  (`HEAD:…:3401`), asserting `r.heaviestLoad!.value ≈ 240.0` at `:3484` — again a
  `weight × reps` product. This test *was* a genuine regression guard for the "frozen record"
  bug described in §1.1, and it discriminated correctly for **which set wins** — but on the
  **wrong quantity**.
- `S-007: a set with weight>0 always populates heaviestLoad …` (`HEAD:…:3811`), asserting
  `≈ 80.0` at `:3858`.

The `mostRepsAtLoad` assertions (`HEAD:…:3548–3550`, `:3802–3804`) asserted the **correct**
quantity — reps and the load of the max-rep set. Those tests were sound; §4 explains why the
production values looked wrong anyway. **They would not have caught the uniform-ten problem,
because there is no bug for them to catch** — the computation is right and the data is what it
is.

**Net effect of the Phase A deletion on test integrity:** it removed three tests that asserted a
wrong quantity under a right-sounding name, and two that were correct. No live test now asserts
any heaviest-load value. `grep -rn "heaviest\|Heaviest\|mostReps" test/` returns nothing.

### 5.3 Live tests that assert PR / rep-record values — checked, and sound

Read the assertions, not the names:

- `test/stats_progress_test.dart:850, 883, 923` —
  `expect(data.recentPRs.first.e1Rm, closeTo(105 * (1 + 5 / 30.0), 0.01))`. Asserts the Epley
  formula **explicitly, inline**. Cannot pass against a volume figure. **Sound.**
- `test/services_test.dart:620–693` (`S-T-001`) — a real three-surface parity test: it computes
  the toast's e1RM, the Stats screen's `recentPRs.first.e1Rm`, and the session summary's
  `newBest`, and asserts all three equal. **Sound, and genuinely discriminating.**
- `test/in_session_pr_toast_test.dart:653` —
  `expect(statsData.recentPRs.first.e1Rm, closeTo(81.6667, 0.001))` = `70 × (1 + 5/30)`.
  **Sound.**
- `test/state_test.dart:3098` — `expect(exerciseSummary.bestWeight, 60.0)` on a `5 × 60 kg`
  fixture. Asserts the genuine heaviest weight, correctly. **Sound as an assertion** — but see
  §5.4.
- `test/data_tracking_fixes_test.dart:206–270` — asserts volume is stored in kg and formatted
  through the display layer (`10 × 100 kg → "1000"`). **Sound**, and it is the authority
  establishing that §2.4/§2.6's unit convention is intentional rather than accidental.

**No live test asserts a heaviest-load quantity.** The mislabeled-assertion problem in this area
was entirely contained in the deleted Records tests.

### 5.4 A test guarding a value nothing displays

`ExerciseSummary.bestWeight` is the only computation in the codebase that correctly computes a
heaviest single-set weight (§1.6). **Nothing reads it.**
`grep -rn "bestWeight" lib/` returns three hits: the model field
(`session_summary.dart:63`), the constructor parameter (`:102`), and the producer
(`session_summary_builder.dart:78–79, 177`). `session_summary_service.dart` consumes only
`bestE1RM` and `bestReps`; no screen references it.

Its guard test (`test/state_test.dart:3098`) carries the comment
*"bestWeight remains the volume metric (raw top weight, in kg)"* — which conflates two
different things in one clause ("volume metric" and "raw top weight" are not the same
quantity), and pins a field with no consumer.

This is not a passing-for-the-wrong-reason test — the assertion is correct. It is recorded here
because it is the mirror image of §2.1: the codebase computes the right quantity and never
shows it, while the Records card showed the wrong one under the right name. **VERIFIED —
how:** exhaustive grep, cited above.

---

## What remains uncertain

Stated separately so nothing above is read as more settled than it is.

1. **The exact `weight × reps` decomposition of `2205 lbs` and `1601 lbs`.** NOT DETERMINED.
   The algebra in §2.1 is exact and verified; the specific factors are not recoverable from
   this repository. Requires the user's stored observation rows.
2. **Whether the user's `10`s came from the untouched default or from real 10-rep sets.** NOT
   DETERMINED. The two are byte-identical in storage (§4.3). Requires inspecting the
   distribution of `metric-reps` values on the account.
3. **Whether the pre-fix `_recordRepsFor` variant described in the deleted comment (§1.1) ever
   reached a user build.** NOT DETERMINED — it is not in this branch's history. Immaterial to
   the finding: it would have changed *which set* won, not *what quantity* was stored.
4. **Whether §2.5/§2.7's estimate-as-weight presentation has actually misled anyone.** NOT
   DETERMINED — no report, no telemetry. The finding is structural.
5. **`ObservationGrouper` entry-index parsing.** RESOLVED — the grouper delegates set grouping to
   `EntryRows`, which reads the number in the id, so a row with no number is in no entry.
   Verified by `test/entry_rows_test.dart` (`S-843`).

---

## Doc drift found in passing (not acted on)

`docs/stats_screen.md` still documents the deleted feature:

- `:210–212` — describes `computeExerciseRecords()` and its test group as current.
- `:216` — documents the defect as intended behavior:
  *"**Heaviest load** — max `load × reps` across the exercise's loaded …"*.
- `:549–550` — lists `ExerciseRecord`, `VolumeTrend`, `ConsistencyTrend` and the deleted
  service methods in the file-responsibility table.

Recorded per the doc-freshness rule in `CLAUDE.md` (`lib/` wins). **Not corrected — Phase F is
investigation-only.** Line `:216` is worth preserving as evidence: the mismatch between the
label "Heaviest load" and the quantity `load × reps` was written down, reviewed, and documented
as correct.
