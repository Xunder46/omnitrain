# Feature: Stats PR 5a — the training-load definitions and the Mix layer's data

> **Status:** READY (planner) — no code yet.
> **Next handoff:** @dba (Phase 1).
> **Series:** `docs/plans/2026-10-02-05-stats-pr5-index.md` — PR 5 = pack item 7. 5a (this plan) ships the data and is invisible; 5b ships the Mix layer on the Stats screen.
> **Provenance:** owner decisions of 2026-10-02 recorded in `.work/stats-pr5/brief-plan.md`; scope from `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 7.
> **Base:** `develop`, working tree at `docs/plans/2026-09-30-04-stats-pr4-index.md` DONE (ALL TIME card + Instruments list + Fuel row + Records & Trends icon).
> **Depends on:** nothing unmerged. PR 1 (`TrainingSession.sessionFeeling`, 1–5) is in; PR 4 is in.
> **Source of scope:** pack item 7 — Copilot Prompt, Acceptance Criteria, Unit Tests Required.
> **Evidence:** `2026-10-02-05a-stats-pr5a-mix-data-plan.evidence.md` (same folder). Review findings go to `.review.md`; neither belongs in this file.
> **Binding conventions:** `docs/global_conventions.md`, plus `docs/README.md` → `docs/stats_screen.md`, `docs/modality_tracking.md`, `docs/data_models.md`, `docs/constants_reference.md`, `docs/documentation_standard.md`, `docs/rolling_sessions.md`, `docs/rest_tracking.md`. Budget: `.github/agents/pr_scope_budget.md`.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 333 (measured 2026-10-02) | 500 | 800 |
| Phases | 2 | >3 | >5 |
| Tracks | 1 (`lib/`) | >1 | — |
| Ledger decisions | 19 (D-901…D-919) | >20 | — |
| Scenarios | 17 (S-1501…S-1517) | >30 | — |
| Predicted production lines | ~330 | — | ~1,500 |

**Verdict:** under budget on every axis. 5b is the other half of PR 5 and is a separate plan; this half ships green and invisible on its own.

## What this PR does

It defines session load, the effort→modality rule, the per-session time split, the baseline and the weekly strip **once**, in code a later signal can import, and computes the Mix layer's whole payload behind one service call. It changes nothing a user can see: no widget, no screen edit, no string on a surface. 5b renders what this returns.

**Out of scope (5b, or later):** any widget; `lib/features/stats/stats_screen.dart`; `docs/stats_screen.md`'s display sections; any signal card (pack item 8); heart-rate load; interactive drill-down; a time-range selector.

## Decision Ledger — PR 5a

Immutable once written; a change is a new superseding entry. `D-901…D-919` are unused elsewhere in `docs/plans/`.

**D-901 — Session load.** `loadMinutes = sessionTimeSeconds / 60 × rating`, where `rating` is `TrainingSession.sessionFeeling` (1–5) and `sessionTimeSeconds` is D-904's session time (D-906 for rolling). A session with `sessionFeeling == null` has **zero** load and is an *unrated session*. A rating is never estimated, inferred or filled in. `sessionTimeSeconds <= 0` ⇒ load 0. Accumulate as `double`; round once, at display.

**D-902 — Effort → modality, one mapping.** An effort's modality is the section `StatsProgressService._sectionForKind` returns: `'set'`→Resistance, `'timed'`→Cardio, `'drill'`→Isometric, `'round'`→Sports, any other kind→no modality. The Mix code calls that method; it declares no second mapping and no kind-string literals of its own.

**D-903 — Measured active time.** Per effort: `'timed'` and `'drill'` contribute the sum of `actualDurationSecs` over the effort's `TimedInstance`s whose `state == TimedState.finished` (pauses are already excluded from that stored value; an unfinished instance contributes 0). `'round'` contributes the sum of `elapsedMs` over its `RoundInstance`s that are `RoundState.finished` with `startedAtMs > 0` and a non-null `finishedAtMs` — the same round predicate the Sports instrument uses. `'set'` contributes no measured time.

**D-904 — Time per modality, non-rolling session.** `measured[section]` = D-903 sums. `time[resistance] = max(0, durationSeconds − Σ measured)`, where `durationSeconds = (endedAtMs − startedAtMs) / 1000` — the figure ALL TIME uses. Session time = `durationSeconds`. When `Σ measured > durationSeconds`, D-905 replaces this whole split.

**D-905 — Dominant-modality fallback.** When a non-rolling session's `Σ measured > durationSeconds`, the session's whole time and load go to its dominant modality: the section with the most efforts of that section's kind in the session (every effort whose kind maps to a section counts, including efforts with a null `exerciseId`). A tie resolves by `ExerciseSection.values` declaration order — `resistance`, `cardio`, `isometric`, `sports`. A session with no effort that maps to a section contributes no time and no load.

**D-906 — Rolling sessions.** Duration is not used. Time per modality = D-903 measured sums only; Resistance receives nothing (its sets add no time). Session time = `Σ measured`. Load = `Σ measured / 60 × rating`. A sets-only rolling session contributes no time and no load. D-905 does not apply: a rolling session has no duration to exceed.

**D-907 — Load split.** `load[section] = loadMinutes × time[section] / sessionTimeSeconds`, over the same sections as the time split. When `sessionTimeSeconds == 0` every section's load is 0. Never round per session.

**D-908 — Which measure the layer shows.** Let `windowTimeSeconds` be the sum over the window's completed sessions (D-911 predicate) of that session's own time (D-904 / D-906), and `unratedTimeSeconds` the same sum restricted to sessions with `sessionFeeling == null`. The layer shows **load** when all of: `ratedBaselineWeeks >= kTrainingLoadMinRatedWeeks` (4), `windowTimeSeconds > 0`, and `unratedTimeSeconds / windowTimeSeconds <= kTrainingLoadMaxUnratedShare` (0.25 — the boundary is inclusive, so exactly 25% is load). Otherwise it shows **time**. The gate is never loosened per session: one unrated session does not switch the window.

**D-909 — Baseline.** **SUPERSEDED by D-934** (the baseline is no longer start-of-week aligned and no longer leaves a gap). `anchor` = the local-midnight start of the week containing `window.fromMs`, honouring the saved start-of-week (D-910). The baseline period is `[anchor − kTrainingLoadBaselineWeeks weeks, anchor)` — 12 consecutive whole weeks, so the window is never inside its own baseline. A **rated baseline week** is one of those 12 weeks containing at least one completed session with a rating, by session start. `ratedBaselineWeeks` counts them. A baseline segment's share = that modality's accumulated load over sessions starting in the baseline period ÷ the period's total load; when that total is 0 there are no baseline segments.

**D-910 — Weeks.** **NARROWED by D-935**: the setting decides only the strip's weeks, never the baseline's blocks. A week is 7 consecutive local days starting at the saved start-of-week — `'sunday'` when `SettingsState.startOfWeek == 'sunday'`, `'monday'` otherwise. Every week computation takes `now` and the setting as parameters; nothing reads the wall clock implicitly.

**D-911 — Session in the window.** `endedAtMs != null` and `startedAtMs` within `[window.fromMs.millisecondsSinceEpoch, window.toMs.millisecondsSinceEpoch]` inclusive — the Instruments list's own predicate (`StatsProgressService._sessionInWindow`, which takes `StatsWindow` whose `fromMs`/`toMs` are `DateTime`), reused rather than restated.

**D-912 — Percentages.** Only sections with a positive measure are segments. `exact = 100 × measure / total`; `percent = floor(exact)`; the remaining points (`100 − Σ percent`) go one each to the largest fractional remainders, ties broken by larger exact measure and then by `ExerciseSection.values` order. The segments of one list always sum to exactly 100. Segment **widths** use the exact proportions, never the rounded percentages.

**D-913 — Segment order.** Descending measure, ties by `ExerciseSection.values` order, in both the bar and its baseline. A window whose only work is lifting yields exactly one segment (Resistance, 100%) — never a zero-measure segment for the other three.

**D-914 — Hidden layer.** `computeMixLayer` returns `null` when `windowTimeSeconds == 0` — a window with no measurable time (for example one holding only sets logged in rolling sessions). Nothing is returned to render, so nothing draws an empty bar.

**D-915 — Unrated count.** `unratedSessionCount` = completed sessions in the window with `sessionFeeling == null`. Reported in both measures; the surface shows it only when it is above 0.

**D-916 — One measure label.** The layer's measure is named `MixMeasure.time` or `MixMeasure.load`; the surface derives one label per measure (`by time` / `by load`) and uses that same label for both the bar and the strip, so the two can never disagree (owner decision 2). The data carries the measure, never a label string.

**D-917 — Strip.** `weeks` holds exactly `kMixStripWeeks` (8) weeks, oldest first, ending with the week containing `now`; the last is `inProgress`. Each week's value is the **same measure as the bar** (D-908), accumulated over completed sessions whose local **start** falls in that week — a session crossing midnight or a week boundary belongs to the week it started in. A week with nothing is present with no segments and measure 0; weeks are never dropped. The strip does not read the window.

**D-918 — The definitions live in one home.** `lib/core/models/training_load.dart` holds the value types, the four constants and the pure arithmetic (load, time split, load split, segments). It imports no Flutter and no repository, so a later signal imports the definitions rather than restating them. `StatsProgressService.computeMixLayer` is the only place that walks history for them.

**D-919 — Reuse the cached history.** `computeMixLayer` reads `_HistoryIndex` and nothing else: no per-session repository call, no second snapshot. One service instance serves the whole screen load.

**D-934 — Baseline period (supersedes D-909).** `fromDay` = the local-midnight day of `window.fromMs` (`DateTime(y, m, d)` of that instant's local date). The baseline period is `[fromDay − kTrainingLoadBaselineWeeks × 7 days, fromDay)` — 12 consecutive blocks of 7 **calendar** days each, computed with `DateTime(y, m, d − n)` and never a `Duration`, so a DST transition cannot shift a boundary; the last block ends the instant before `fromDay`. The period therefore abuts the window with no gap and no overlap: no day belongs to neither the baseline nor the window. The window is never inside its own baseline. A **rated baseline week** is one of those 12 blocks containing at least one completed session (by session start) with a rating; `ratedBaselineWeeks` counts them. A baseline segment's share = that modality's accumulated load over sessions starting in the baseline period ÷ the period's total load; when that total is 0 there are no baseline segments. Segments are in descending measure (D-913) — the surface may reorder them for display, but this list's order never changes and no arithmetic is redone from the reordered list.

**D-935 — The start-of-week setting's scope (narrows D-910).** The saved start-of-week decides only the 8-week **strip**'s weeks (D-917). The baseline period does **not** use it: its blocks are fixed 7-calendar-day blocks anchored at `fromDay` (D-934), so changing the setting never moves a baseline boundary and never changes `ratedBaselineWeeks`. The `OmniDateUtils` week-start helper serves the strip; nothing else calls it.

### Decisions this plan consumes but does not define

| Decision | Source | What it binds here |
|---|---|---|
| Effort kinds (`set`/`timed`/`round`/`drill`) drive analytics, not modality labels | D-3, D-15; `docs/global_conventions.md` | D-902: a timed effort in a lifting session is Cardio |
| Sets take the remainder of a session's time; rolling sessions count measured time only | D-8, D-9 | D-904, D-906 |
| A rating is `sessionFeeling` (1–5); pre-redefinition answers read on the same scale | D-5, PR 1 | D-901 |
| The window chip names the resolved window and comes from one widget | D-516 | 5b only; this PR only consumes `StatsWindow` |
| No legacy section returns; no removed projection name returns | D-606, D-666 | The residue sweep, Phase 2 |

## Feature invariants that bite in this PR

- **Repository parity.** Nothing here reads the repository except through `_loadHistory`; the Mock and Hive harnesses must produce identical `computeMixLayer` output. Phase 2 runs its suite on both harnesses.
- **No schema change, no stored field.** Every figure derives from `TrainingSession`, `SessionSegment`, `SegmentEffort`, `TimedInstance` and `RoundInstance` as they are. `scripts/sqlite_schema.sql` and `lib/data/models/models.dart` are untouched, so `test/db_seed_test.dart` is untouched.
- **Nothing user-visible changes.** No widget, no screen, no string on a surface, no route. `flutter test` must show only additive change.
- **PR parity tests are read-only.** `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` are not edited.
- **Docs describe what exists.** Phase 1's doc may not name `computeMixLayer` (it does not exist yet); Phase 2 adds it.

## Requirements

1. A pure-Dart home for session load, the effort→modality rule, the per-session time split, the load split, the percentage rounding, the four constants and the baseline period's calendar blocks.
2. A week-start helper honouring the saved start-of-week, used by the strip only (D-935), and a baseline-block helper (D-934) — both usable by the service and by tests.
3. `StatsProgressService.computeMixLayer({required StatsWindow window, required DateTime now, required String startOfWeek})` returning the bar, its baseline, the unrated count, the rated-baseline-week count, the measure and 8 weeks — or `null` when the window has no measurable time.
4. Unit tests for every rule and every pack fixture value, on both repository harnesses for the service half.
5. The docs the definitions invalidate.

## Acceptance Criteria → scenarios

| # | Criterion (pack item 7) | Scenario |
|---|---|---|
| A1 | 60 min rated 4 → 240 load; unrated → no load, +1 unrated | S-1501, S-1502 |
| A2 | Free Training, 20 min holds, rated 3 → R 40 min/120, I 20 min/60 | S-1503, S-1504 |
| A3 | 75 min lifting with a 15 min timed warm-up → R 60 min, C 15 min | S-1505 |
| A4 | Measured time > duration → all to the dominant modality | S-1506, S-1507 |
| A5 | Rolling: measured time only; sets-only rolling contributes nothing | S-1508, S-1509 |
| A6 | No ratings → time measure + a baseline progress note, no usual bar | S-1510 |
| A7 | 4+ rated baseline weeks and ≤ 25% unrated → load, the usual bar | S-1510, S-1511 |
| A8 | The strip is exactly 8 weeks, empty weeks kept, current week in progress | S-1513 |
| A9 | A lifting-only window is one 100% Resistance segment | S-1515 |
| A10 | Changing the window moves the bar and leaves the strip's 8 weeks alone | S-1513 |
| A11 | A user with every modality in one session: four segments, still 100% | S-1516 |
| A12 | A session crossing midnight or a week boundary belongs to the week it started in | S-1517 |

## Scenarios

Fixtures are exact: every entity class involved is named, including the adversarial twins. All sessions are completed (`endedAtMs != null`) unless stated. `T` is a local `DateTime`; a "rated baseline" fixture is 4 sessions, one in each of 4 distinct baseline weeks, each 60 min rated 4 unless stated.

### S-1501: a 60-minute session rated 4 is 240 load
- **Fixture:** one non-rolling session, `T` → `T+60min`, `sessionFeeling = 4`, no segments. Baseline: rated-ready. Window: `[T−1d, T+1d]`.
- **Trigger:** `computeMixLayer(window: w, now: T, startOfWeek: 'monday')`.
- **Flow:** load path (D-908).
- **Expected outcome:** `measure == MixMeasure.load`; one segment, `resistance`, `measure == 240.0`, `percent == 100`; `unratedSessionCount == 0`; `baselineSegments` non-empty.
- **Edge case of:** none.

### S-1502: an unrated 60-minute session adds no load and one unrated count
- **Fixture:** S-1501's session with `sessionFeeling = null`; baseline **empty** (no sessions at all before the window).
- **Expected outcome:** `measure == MixMeasure.time`; one segment, `resistance`, `measure == 60.0`, `percent == 100`; `unratedSessionCount == 1`; `ratedBaselineWeeks == 0`; `baselineSegments` empty.
- **Edge case of:** S-1501. Twin: S-1510 fixture C (a rated baseline, a wholly unrated window) is still time — the gate is on the window, not the baseline alone.

### S-1503: Free Training, 20 minutes of holds, rated 3 → 40 min/120 R and 20 min/60 I
- **Fixture:** one non-rolling session `T` → `T+60min`, `sessionFeeling = 3`, one segment, one `drill` effort (Isometric, `exerciseId = 'ex-hold'`) with one finished `TimedInstance` whose `actualDurationSecs` is 1200 — the stored value is already net of pauses, so a live hold that was paused for 5 minutes stores 1200, not 1500. Baseline: rated-ready.
- **Expected outcome:** `measure == load`; segments in order `[resistance, isometric]`; `resistance.measure == 120.0`, `resistance.percent == 67`; `isometric.measure == 60.0`, `isometric.percent == 33`.
- **Edge case of:** S-1501.

### S-1504: the same geometry with no rating reads in minutes
- **Fixture:** S-1503 with `sessionFeeling = null` and no rated baseline.
- **Expected outcome:** `measure == time`; `resistance.measure == 40.0` (2400s), `isometric.measure == 20.0` (1200s); percentages 67/33.
- **Edge case of:** S-1503 — the pack's "40 minutes … and 20 minutes" half of criterion A2.

### S-1505: a 75-minute lifting session with a 15-minute timed warm-up
- **Fixture:** one non-rolling session `T` → `T+75min`, unrated; one segment: a `set` effort (`exerciseId = 'ex-dl'`, 3 sets) and a `timed` effort (`exerciseId = 'ex-tread'`) with one `TimedInstance{finished, 900}`.
- **Expected outcome:** `measure == time`; `resistance.measure == 60.0`, `cardio.measure == 15.0`; percentages 80/20; order `[resistance, cardio]`.
- **Edge case of:** none.

### S-1506: measured time exceeds the duration → the dominant modality takes the session
- **Fixture A:** one non-rolling session `T` → `T+30min`, `sessionFeeling = 5`; one segment with two `drill` efforts (finished instances 1200s and 900s) and one `timed` effort (finished instance 600s). `Σ measured == 2700 > 1800`.
- **Expected outcome A:** load mode; one segment, `isometric`, `measure == 150.0` (30 min × 5), `percent == 100`; no `cardio` segment — the 600s of cardio time is discarded with the rest of the split.
- **Fixture B (adversarial twin):** the same shape with one `set` effort and one `timed` effort (finished instance 900s) over a 10-minute session. Effort counts tie 1–1.
- **Expected outcome B:** the whole 10 minutes go to `resistance` — `ExerciseSection.values` order breaks the tie (D-905), not insertion order.
- **Edge case of:** S-1505.

### S-1507: a tie in the dominant-modality count resolves by declaration order
- **Fixture:** one non-rolling session `T` → `T+20min`, unrated; the `drill` effort seeded **before** the `timed` effort; finished instances 800s each. `Σ measured == 1600 > 1200`.
- **Expected outcome:** the whole 20 minutes go to `cardio` (declaration order), not `isometric` (insertion order) — one segment, `cardio`, `measure == 20.0`, `percent == 100`.
- **Edge case of:** S-1506.

### S-1508: a rolling session counts measured time only
- **Fixture:** one rolling session (`isRolling = true`) `T` → `T+3h`, `sessionFeeling = 4`; one segment: a `set` effort with 5 logged sets, and a `timed` effort with two finished instances of 900s. Baseline: rated-ready.
- **Expected outcome:** load mode; one segment, `cardio`, `measure == 120.0` (30 min × 4), `percent == 100`; **no** `resistance` segment — the 3-hour wall-clock duration is not used, so sets add neither time nor load.
- **Edge case of:** S-1501.

### S-1509: a sets-only rolling session contributes nothing
- **Fixture A:** one rolling session with only `set` efforts, alone in the window.
- **Expected outcome A:** `computeMixLayer` returns `null` (D-914).
- **Fixture B:** the same session, plus a non-rolling 30-minute lifting session in the window.
- **Expected outcome B:** one segment, `resistance`, and the rolling session contributes 0 to it — the measure is the non-rolling session's own time (30 min, or its load when rated).
- **Edge case of:** S-1508.

### S-1510: the switch, at exactly 4 rated baseline weeks and at exactly 25% unrated
- **Fixture A (exactly 4):** window = 4 sessions of 60 min, all rated 4; baseline = 4 sessions, one in each of 4 distinct baseline weeks.
- **Expected outcome A:** load mode; `ratedBaselineWeeks == 4`; `resistance.measure == 960.0`; `baselineSegments` non-empty.
- **Fixture B (3 weeks):** fixture A with one baseline session removed.
- **Expected outcome B:** time mode; `ratedBaselineWeeks == 3`; `baselineSegments` empty; the surface's note reads `Load baseline: 3 of 4 weeks rated` (5b).
- **Fixture C (exactly 25%):** baseline = 4 rated weeks; window = 4 sessions of 60 min, three rated (4, 5, 3) and one unrated. `900 / 3600 == 0.25`.
- **Expected outcome C:** load mode (the boundary is inclusive, D-908); `unratedSessionCount == 1`; `resistance.measure == 720.0`; the unrated session adds no load and no time to any segment.
- **Fixture D (33%):** window = 3 sessions of 60 min, two rated and one unrated.
- **Expected outcome D:** time mode; `unratedSessionCount == 1`; `resistance.measure == 180.0` minutes.
- **Fixture E (ratings only on old sessions):** baseline = 4 rated weeks; window = 2 sessions of 60 min, both unrated. Every rating in the store is older than the window.
- **Expected outcome E:** time mode (the window is 100% unrated); `unratedSessionCount == 2`; `ratedBaselineWeeks == 4`; `baselineSegments` empty, because the usual bar renders in the load measure only — old ratings never make an unrated window read as load.
- **Edge case of:** S-1502.

### S-1511: the baseline is the 12 calendar weeks before the window, with no gap
- **Fixture:** a hand-built `StatsWindow(fromMs: W, toMs: W+6d)` where `W` is a **Monday** at local midnight, so `fromDay == W`. Sessions at `W−1d` (rated, 60 min), `W−84d` (rated, 60 min), `W−85d` (rated, 60 min), `W+1d` (rated, 60 min, inside the window).
- **Expected outcome:** `ratedBaselineWeeks == 2` — the two sessions inside `[W−84d, W)`, the period D-934 derives from `fromDay`; the `W−84d` session counts because its day is the period's first day, the `W−85d` session is before the period, and the `W+1d` session is the window, which is not in its own baseline. No day lies between the baseline's end and the window's start. The measure is time here (2 rated blocks is below the 4 the load measure needs, D-908), so `baselineSegments` is empty; the baseline **counts**, not the baseline load, are what this fixture asserts.
- **Edge case of:** S-1510. **Start-of-week twin:** the same fixture with `startOfWeek: 'sunday'` gives the **same** `ratedBaselineWeeks` and the same baseline segments as `startOfWeek: 'monday'` — D-935: the setting moves only the strip's weeks, never a baseline boundary.
- **Fixture B (period-scoped window):** a `TrainingPeriod{startDateMs: W, endDateMs: W+13d}` that contains `now`, three sessions inside it, and the four sessions of fixture A. The window comes from `StatsProgressService.resolveWindow(periods: [period], completedSessions: [...], now: ...)`, so `isPeriodScoped` is true.
- **Expected outcome B:** the bar covers the period's sessions and the baseline ends at the local-midnight day of the window's own start (`fromDay`), not at today's week, not at a week boundary and not at the window's end; the same two baseline sessions count. The same period pulled back one day to `W−1d` leaves one rated block, which is what separates a baseline ending at the window's start from one ending at its end. `computeMixLayer` behaves identically for a period-scoped and a recency window; the flag is never read.

### S-1512: percentages always sum to 100, with deterministic tie-breaks
- **Fixture:** one non-rolling 60-minute session, unrated; one segment with a `timed` effort (1200s finished), a `drill` effort (1200s finished) and a `round` effort (one finished round, `actualDurationSecs: 1200`). Resistance remainder 0.
- **Expected outcome:** `measure == time`; three segments in order `[cardio, isometric, sports]` (equal measures, declaration order); percentages `34, 33, 33` — floors sum to 99 and the single remaining point goes to the largest remainder, the three-way tie broken by declaration order. `Σ percent == 100`.
- **Edge case of:** S-1503.

### S-1513: the strip is 8 weeks, keeps empty weeks, and ignores the window
- **Fixture:** `now` = a Wednesday. Sessions (60 min, unrated) at `now`, `now−7d`, `now−8d`, `now−30d`, `now−90d`. Window covers only the week containing `now`.
- **Expected outcome:** `weeks.length == 8`; `weeks.last.weekStart` is the Monday of `now`'s week and `weeks.last.inProgress` is true; `weeks[0].weekStart == weeks.last.weekStart − 7 weeks`; no other week is `inProgress`; `weeks[0..5]` and the week holding `now−90d`'s slot are empty (no segments, measure 0) rather than dropped; the `now`, `now−7d` and `now−8d` sessions land in the last and second-to-last weeks; the `now−30d` session lands in its own week **even though it is outside the window**; the `now−90d` session appears in no week.
- **Edge case of:** none. Sunday-start twin: `startOfWeek: 'sunday'` shifts every `weekStart` to Sunday.

### S-1514: this layer and the Instruments list put the same effort in the same modality
- **Fixture:** one non-rolling session, one segment: a `timed` effort whose exercise is named `Plank` with one finished instance of 600s, and a `set` effort whose exercise is named `Deadlift`. Window covers the session.
- **Expected outcome:** the mix puts 600s in `cardio` and the remainder in `resistance`; `computeInstrumentSections(window: w)` returns a `cardio` section containing the `Plank` row and a `resistance` section containing the `Deadlift` row — same effort, same modality, from the one mapping.
- **Edge case of:** none. This is the pack's structural parity requirement.

### S-1515: a lifting-only window is one full-width Resistance segment
- **Fixture:** a window holding three non-rolling lifting sessions (set efforts only), two rated and one unrated.
- **Expected outcome:** exactly one segment, `resistance`, `percent == 100`; no `cardio`, `isometric` or `sports` segment appears at any percent; `unratedSessionCount == 1`.
- **Edge case of:** S-1501.

### S-1516: a session holding every modality splits four ways and still sums to 100
- **Fixture:** one non-rolling 60-minute session, unrated; one segment with a `set` effort (Deadlift), a `timed` effort (one finished instance 600s), a `drill` effort (one finished instance 600s) and a `round` effort (one round, `state: finished`, `actualDurationSecs: 600`, `startedAtMs > 0`, non-null `finishedAtMs`). `Σ measured == 1800s == 30 min`, so Resistance takes the 30-minute remainder.
- **Expected outcome:** `measure == time`; four segments in order `[resistance, cardio, isometric, sports]` — Resistance 30 min, then the three 10-minute sections in declaration order; percentages `50, 17, 17, 16` (floors 50/16/16/16 sum to 98, and the two spare points go to the tied largest remainders in declaration order); `Σ percent == 100`.
- **Edge case of:** S-1512.

### S-1517: a session crossing midnight belongs to the week it started in
- **Fixture:** `startOfWeek: 'monday'`, `now` a Wednesday. One non-rolling session starting Sunday 23:30 local and ending Monday 00:30 (60 minutes), unrated, one `set` effort. Its start week is the Monday **six days before** that Sunday.
- **Expected outcome:** the session's own time is the full 60 minutes (midnight does not split a session), and it lands in the strip's second-to-last column — the week containing its start — not the last column, which holds the week containing `now`.
- **Edge case of:** S-1513. Sunday-start twin: with `startOfWeek: 'sunday'` the same session starts in the last day of its week, and the column index is the one the week-start helper yields for Sunday 23:30 — asserted against the helper rather than a literal index.


### Executor block — read before Step 0

- **Step 0a.** Read `docs/global_conventions.md`, then this plan in full, then `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 7.
- **Step 0b.** Record the baselines by running `gateway.sh lint` and `gateway.sh test` and quoting their **final lines verbatim** into the evidence file. Expected: `196 issues found.` with 0 errors, and `+3227 ~1: All tests passed!`. If yours differ, quote yours and say so.
- **Step 0c.** Red run. Write the phase's test file **before** the code it tests, run `gateway.sh test <that file>`, and paste the failure (a compile error for a missing API counts) into the evidence file. A test that has never failed proves nothing.
- **Rules.** Work on `develop`. Never commit, stage, merge, push or branch. The only shell command is `gateway.sh` (`list`, `lint`, `test [paths]`, `format <paths>`, `pub-get`, `git-status`, `git-diff`, `git-log`, `git-show`). No new dependency. `edit` needs an exact `old_str`. `flutter analyze` must stay at "none new" — never relax it. No `lib/features/` or `lib/widgets/` file in this PR: 5a is invisible, and a widget here breaks 5b's boundary. Write evidence to the `.evidence.md` file, never into this plan; log every judgement call in the Assumption Log below, at most 3 lines each.
- **Doc checklist for every phase.** Search `docs/` and `test/` for each name you add (`computeMixLayer`, `MixLayerData`, `MixSegment`, `MixWeek`, `MixMeasure`, `kMixStripWeeks`, `kTrainingLoadBaselineWeeks`, `kTrainingLoadMinRatedWeeks`, `kTrainingLoadMaxUnratedShare`, `startOfWeek`, `training_load`) and list every hit's file in the evidence file. Every behaviour sentence a doc gains must name the test that asserts it. Name constants, never restate their values. No hex, no sizes, no line numbers, no roadmap phrasing.
- **Inverse-edit mutations (all three required, all on tracked files, all reverted after).** M1: in `lib/core/services/stats_progress_service.dart`, make the Resistance remainder 0 (treat Resistance as measured) — `S-1503`/`S-1505` must fail. M2: in `lib/core/utils/date_utils.dart`, make the week-start helper ignore its `startOfWeek` argument — the strip's Sunday-start assertion (`S-1513`'s twin) must fail. M3: in `lib/core/models/training_load.dart`, make `baselineBlockStarts` step by `Duration(days: 7)` from `fromDay` instead of calendar arithmetic — the DST assertion in `S-1511`'s pure half must fail. Record all three red runs in the evidence file.

### Phase 1: the definitions, the value types and the week helper (@dba)

1. [x] Create `lib/core/models/training_load.dart` (D-918). No Flutter import, no repository import — a `library;` doc comment like `lib/core/models/stats_progress.dart`'s. It holds:
   - `const int kMixStripWeeks = 8;`, `const int kTrainingLoadBaselineWeeks = 12;`, `const int kTrainingLoadMinRatedWeeks = 4;`, `const double kTrainingLoadMaxUnratedShare = 0.25;`
   - `enum MixMeasure { time, load }`
   - `class MixSegment { final ExerciseSection section; final double measure; final int percent; }`
   - `class MixWeek { final DateTime weekStart; final List<MixSegment> segments; final double measure; final bool inProgress; }`
   - `class MixLayerData { final MixMeasure measure; final List<MixSegment> segments; final List<MixSegment> baselineSegments; final int unratedSessionCount; final int ratedBaselineWeeks; final List<MixWeek> weeks; }`
   - the pure functions: `double sessionLoadMinutes({required int sessionTimeSecs, required int? rating})` (D-901), `Map<ExerciseSection, double> sessionTimeByModality({required int durationSecs, required bool isRolling, required Map<ExerciseSection, double> measuredSecs, required ExerciseSection? dominantSection})` (D-904–D-906), `Map<ExerciseSection, double> sessionLoadByModality({required Map<ExerciseSection, double> timeByModality, required int? rating})` (D-907), and `List<MixSegment> mixSegments(Map<ExerciseSection, double> measureBySection)` (D-912, D-913).
   - `DateTime localMidnightDay(DateTime t)` and `List<DateTime> baselineBlockStarts(DateTime fromDay)` (D-934): the 12 local-midnight starts of the consecutive 7-calendar-day blocks tiling `[fromDay − kTrainingLoadBaselineWeeks × 7 days, fromDay)`, oldest first, computed with `DateTime(y, m, d − n)` and never a `Duration`.
   - Each function carries a doc comment stating the rule it implements and the D-number. The percentage rounding is the largest-remainder method with the two tie-breaks written out.
2. [x] Add the week-start helper to `lib/core/utils/date_utils.dart` as a static on `OmniDateUtils` (D-910, D-935): given a `DateTime` and the saved setting string, return the local-midnight start of the week containing it, treating any value other than `'sunday'` as `'monday'`. It serves the strip only — the baseline uses the fixed blocks of step 1 (D-934). Use calendar arithmetic (`DateTime(y, m, d − n)`), never a duration, so a DST transition cannot shift a boundary.
3. [x] Write `test/training_load_test.dart` (plain `test()`, no repository, no `testWidgets`) covering S-1501, S-1503, S-1504, S-1506, S-1507, S-1508, S-1512, S-1515, S-1516 at the function level, plus: rating 1 through 5 each give `60 × rating`; zero duration gives 0; an unrated session gives 0 and is not estimated; the week helper at every weekday for both settings; and the baseline blocks — exactly 12 blocks of 7 calendar days tiling `[fromDay − 84 days, fromDay)` with no gap, the last block ending the instant before `fromDay`, unchanged by `startOfWeek` and unshifted across a DST transition.
4. [x] Create `docs/training_load.md` with a scope block per `docs/documentation_standard.md`: what session load is, the effort→modality rule, measured active time, the remainder and fallback rules, rolling sessions, the baseline period — the 12 calendar weeks immediately before the window's start day, with no gap, split into 7-calendar-day blocks and independent of the start-of-week setting — and a rated baseline week, the strip's 8 weeks and week-start setting, and the four constants by name. Name the test that asserts each rule. It must **not** mention `computeMixLayer` (it does not exist yet) and must not describe any widget.
5. [x] Edit `docs/README.md`: one index row for `docs/training_load.md`, placed with the Stats/analysis entries.
6. [x] Edit `docs/data_models.md`: a `### The training-load value types` entry beside `### The Instruments list value types`, naming `MixLayerData`, `MixSegment`, `MixWeek`, `MixMeasure` and the file. Relationships and ownership, not field lists.
7. [x] Edit `docs/constants_reference.md`: the four constants by name, with the rule each governs.

**Done Criteria:** `gateway.sh lint` reports no new issue (compare with Step 0b); `gateway.sh test test/training_load_test.dart` passes; `gateway.sh test test/docs_indexing_contract_test.dart test/navigation_contract_enforcement_test.dart` passes; `docs/training_load.md` is under 64 KiB (`test/docs_indexing_contract_test.dart`).
**Predicted Files:** `lib/core/models/training_load.dart` (new), `lib/core/utils/date_utils.dart`, `test/training_load_test.dart` (new), `docs/training_load.md` (new), `docs/README.md`, `docs/data_models.md`, `docs/constants_reference.md`, the evidence file.
**Phase 1 verification notes (Conductor, pending):** added at verification.

### Phase 2: the service computation (@dba)

1. [x] Add `Future<MixLayerData?> computeMixLayer({required StatsWindow window, required DateTime now, required String startOfWeek})` to `lib/core/services/stats_progress_service.dart`. It reads `_loadHistory()` once and reuses `_sessionInWindow`, `_sectionForKind` and the D-918 functions. No `await` inside a session loop, no repository call beyond the cached snapshot (D-919). A private helper may collect one session's `Map<ExerciseSection, double> measuredSecs` and its dominant section from the segment/effort/instance maps; the effort→modality call is `_sectionForKind`, never a literal kind string.
2. [x] Return `null` when the window's total time is 0 (D-914). Build the bar, the baseline blocks and segments (D-934: `fromDay` = the local-midnight day of `window.fromMs`, 12 calendar blocks tiling `[fromDay − 84 days, fromDay)`, segments in the load measure only and only when the baseline's total load is above 0), `unratedSessionCount`, `ratedBaselineWeeks`, and exactly 8 weeks ending with the week containing `now` (D-917). The window's sessions use the D-911 predicate; the baseline's sessions are those starting in the D-934 blocks; the strip's sessions use the same predicate against each week's bounds, independent of the window.
3. [x] Write `test/mix_layer_service_test.dart` — plain `test()`, seeding the harness in `setUp`, never in a `testWidgets` body — covering S-1501, S-1502, S-1505, S-1509, S-1510, S-1511, S-1513, S-1514, S-1515, S-1516 and S-1517 against a real repository. Run it over **both** `harnessFactories` (Mock and Hive) with the house idiom — `for (final factory in harnessFactories) { final harness = factory(); group('${harness.name} — …', ...)` with `setUp`/`tearDown` — and assert value-for-value equality between the two harnesses for at least S-1503 and S-1513.
4. [x] **Fixture seeding — read this before writing the fixtures.** The shared `test/helpers/repository_harness.dart` seeders cannot express what these scenarios need: `seedSession` hard-codes a 60-minute non-rolling session, takes no rating, and gives a rolling session `endedAtMs == null` — which is an *unfinished* session and is excluded by D-911. So each new test file defines its own small `_seedSession(repo, {id, start, end, isRolling, rating})` helper that writes the `TrainingSession` directly with an explicit `startedAtMs`, `endedAtMs` and `sessionFeeling`. Reuse the shared `seedExercise`, `seedSetEffort`, `seedHoldEffort` (pass `effortKind: 'timed'` for a plain cardio effort), `seedRoundEffort`, `timedInstance` and `roundInstance` for the effort and instance shapes — do not restate them. Anchor every fixture on an explicit `now`/`W` computed in the test, not on `fixtureStart`, because these scenarios need exact week and baseline boundaries.
5. [x] Assert the Instruments parity in `test/mix_layer_service_test.dart` (S-1514): the timed `Plank` sits in the mix's `cardio` and in the `Cardio` section of `computeInstrumentSections(window: ...)` — the same effort, one mapping.
6. [x] Edit `docs/training_load.md`: add the `computeMixLayer` entry point — its parameters, its `null` case and the fact that it is the only history walk behind these figures — each sentence naming its test.
7. [x] Edit `docs/state_management/services_and_utils.md`: a `computeMixLayer` row in the `StatsProgressService` section, in the file's existing table shape.

**Done Criteria:** `gateway.sh lint` reports no new issue; `gateway.sh test test/training_load_test.dart test/mix_layer_service_test.dart` passes on both harnesses; `gateway.sh test` passes in full with the count grown only by the tests this PR adds; `gateway.sh git-status` shows no file outside Predicted Files.
**Predicted Files:** `lib/core/services/stats_progress_service.dart`, `test/mix_layer_service_test.dart` (new), `docs/training_load.md`, `docs/state_management/services_and_utils.md`, the evidence file.
**Phase 2 verification notes (Conductor, pending):** added at verification.

## Governor actions

**None.** This PR deletes, moves and renames nothing. It adds two files under `lib/` and `test/`, and edits five tracked files. `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/` stays — 5b is a live plan.

## Files Affected (whole PR)

| File | Change |
|---|---|
| `lib/core/models/training_load.dart` | NEW — value types, constants, the pure load/attribution/percentage/baseline-block math (the single definition home, D-918, D-934) |
| `lib/core/utils/date_utils.dart` | EDIT — the week-start helper for the strip (D-910, D-935) |
| `lib/core/services/stats_progress_service.dart` | EDIT — `computeMixLayer`, reusing `_HistoryIndex`, `_sectionInWindow`, `_sectionForKind` |
| `test/training_load_test.dart` | NEW — the pure rules and fixtures |
| `test/mix_layer_service_test.dart` | NEW — the service, both harnesses, the Instruments parity |
| `docs/training_load.md` | NEW — the definition home a later signal cites |
| `docs/README.md` | EDIT — index row |
| `docs/data_models.md` | EDIT — the value types |
| `docs/constants_reference.md` | EDIT — the four constants |
| `docs/state_management/services_and_utils.md` | EDIT — the service entry point |

## Notes

- **Dependency graph.** Phase 2 needs Phase 1's types and functions. Phase 1 alone is green, shippable and invisible — if 5b is delayed, nothing is half-built.
- **5b's contract.** 5b consumes `MixLayerData` exactly as D-916/D-917 define it: it renders the measure, the bar, the baseline and the weeks, and derives its own label from `MixMeasure`. It writes no arithmetic and no history walk. If 5b needs a field that is not here, that is a 5b plan change, not an edit to this PR's shipped shape.
- **Why `now` and `startOfWeek` are parameters.** The current week and the baseline must be deterministic under test; `resolveWindow` already takes `now`, and this follows it. The screen supplies `DateTime.now()` and `SettingsState.startOfWeek` in 5b.
- **`previousRangeFor` is not used here.** The Mix layer compares against the baseline period (D-934), not the previous window of the same length — a deliberate difference from the Instruments list's change readout, because a load baseline wants a long sample, not the preceding window.
- **Intermediate state.** After Phase 1 the model file exists with no reader in `lib/` other than its own tests. That is expected and is not dead code: 5b and pack items 8, 10–15 read it.
- **Cost.** One `_HistoryIndex` walk of the window's, the baseline's and the strip's sessions — all in memory, all from the single snapshot. No new repository read on the screen's load path.

## Open Items

- None blocking. The figures below are decided here with defaults; 5b inherits them.

## Progress

| # | Item | Result |
|---|---|---|
| 1 | Plan written (this file) | DONE |
| 2 | Plan line count measured by reading it back | DONE — planner: 333 lines; executor: 336 lines after the Assumption Log rows (+3, budget allows +150) |
| 3 | Phase 1 — definitions, types, week helper, tests, docs | **Complete** — 49 tests green; lint unchanged at `196 issues found.`; full suite `+3326 ~1` (baseline `+3277`, +49) |
| 4 | Phase 2 — `computeMixLayer`, service tests, parity, docs | **Complete** — 38 tests green on both harnesses; lint unchanged at `196 issues found.`; full suite `+3364 ~1` (Phase 1 close `+3326`, +38) |
| 5 | Evidence file baselines recorded (Step 0b) | DONE — executor re-ran both; lint matched, test count differs (see §1) |

## Assumption Log

| Phase | Decision | Options considered | Choice and why | Verdict |
|---|---|---|---|---|
| 1 | Which file M1 mutates | the plan's `stats_progress_service.dart`, or Phase 1's home of the same rule | The service computes nothing until Phase 2, so the mutation went on `training_load.dart`'s remainder; S-1503/S-1504/S-1505 failed, then the exact inverse restored the suite. | applied |
| 1 | Which claims `docs/training_load.md` may make | the planner's claim table, or only what Phase 1's tests assert | The table asserted strip and switch behaviour that has no test until Phase 2, so the doc states only Phase 1's rules; the deferred claims return in Phase 2's evidence. | applied |
| 1 | Where the four constants are cited | a compile-time pointer, or a value contract | Added a `the constants` group to `test/training_load_test.dart` so each constant is named by a test that exists. | applied |
| 2 | `baselineSegments` in the time measure | D-934's literal text (non-empty whenever baseline load > 0), or step 2's "segments in the load measure only" | Step 2 wins: segments only in the load measure and only when baseline load > 0. S-1510 B/E assert empty; S-1511's sentence about a baseline segment conflicts and is recorded in the evidence file. | applied |
| 2 | The unit of `MixSegment.measure` in the time measure | seconds (the Phase 1 doc comment), or minutes (the plan's scenario text) | Minutes: the plan's S-1502/S-1505/S-1510 D/S-1515/S-1516/S-1517 all state minutes, and the surface labels the time measure in minutes. The service converts once, at the payload boundary. | applied |
| 2 | Duration seconds from the millisecond bounds | truncate, or round | `((endedAtMs − startedAtMs) / 1000).round()`; every fixture is whole minutes, so the choice is unobservable here. | applied |

## Feedback

Findings belong in `2026-10-02-05a-stats-pr5a-mix-data-plan.review.md`; this is the fix checklist.

- [x] 1 (major) — S-1511 fixture B is exercised on both stores through `StatsProgressService.resolveWindow`, and the fixture B test now also asserts the baseline's end is the window's start day. Fixed in `test/mix_layer_service_test.dart`.
- [x] 2 (minor) — S-1511's registered expected outcome now says the measure there is time, so `baselineSegments` is empty and the baseline counts are what is asserted; the test's divergence comment points at this plan's Assumption Log entry 2.
- [x] 3 (minor) — `docs/constants_reference.md`'s four training-load rows name their verifier.
- [x] 4 (minor) — `sessionLoadMinutes`'s doc comment states the caller guarantees a rating of 1 to 5 and that out-of-range values are not clamped there. Comment only; no behaviour change.
- [x] 5 (nit) — the evidence file's S-1513 parity row records `unrated=1`.
- [x] 6 (nit) — no change requested (measured/dominant stay in the one pass over the cached snapshot, D-919).

## Open questions (defaults applied)

Every one of these changes what the user eventually sees, so each is recorded with the default this plan applies. 5b inherits all of them; none blocks Phase 1.

1. **The 25% boundary.** The pack's prompt says "at most a quarter"; its Acceptance Criteria say "fewer than 25%". *Default applied:* inclusive — exactly 25% unrated still shows load (D-908). One line to flip.
2. **Dominant-modality tie-break.** The pack says only "resolved deterministically". *Default applied:* `ExerciseSection.values` declaration order — the same rule `_sectionForLogs` already uses for the Instruments list.
3. **Efforts with no exercise in the dominant count.** *Default applied:* they count, because the pack says "the most efforts" and the mapping is by kind. *Alternative:* skip them, matching `computeSectionMetrics`' skip-null-exercise rule.
4. **Segments at 0%.** *Default applied:* a modality with a positive measure always gets a segment even when the largest-remainder rounding gives it 0%, and only zero-measure modalities are omitted (D-912/D-913). Widths use exact proportions, so nothing looks absent.
5. **Where the definitions live.** *Default applied:* `lib/core/models/training_load.dart`, a pure-Dart model file (D-918), with the definitions written up in the new `docs/training_load.md`. *Alternative:* a `lib/core/services/training_load.dart`; rejected because the constants and types would then be split across two files a widget must import.
6. **The strip's measure vs its label.** Owner decision 2 fixes the measure; the *label* wording is 5b's. This plan pins only that one label per measure is derived (D-916), so the bar and the strip cannot disagree.
