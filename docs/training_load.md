# Training Load & Mix Definitions — Feature Documentation

**Scope.** The pure Dart definitions behind the training-load figures:
`lib/core/models/training_load.dart` — the session-load rule, the per-modality
time split, the load split, the segment rounding, the value types and the four
constants — the week-start helper `OmniDateUtils.startOfWeek` in
`lib/core/utils/date_utils.dart`, and the one history walk that assembles them,
`StatsProgressService.computeMixLayer` in
`lib/core/services/stats_progress_service.dart`. This document covers those
definitions and that entry point only. It does not cover any screen or any
widget.

---

## Why the definitions live in one file

Session load compares a hard short session with an easy long one on a single
number, so a bar, its baseline and a weekly strip can be read against each
other. Every arithmetic rule behind those figures sits in
`lib/core/models/training_load.dart`, which imports neither Flutter nor the
repository. A caller imports the definitions rather than restating them, so
there is exactly one effort-to-modality mapping, one remainder rule and one
rounding rule in the codebase.

Nothing here is persisted: no box, schema file or seed file holds any of these
types. They are derived and discarded with the read that built them.

Verified by `test/training_load_test.dart`.

---

## Session load

A session's **load** is its time in minutes multiplied by its rating. The rating
is `sessionFeeling` (1–5). A session with no rating has zero load and is never
estimated or filled in, and a session with no positive time has zero load. The
figure is accumulated unrounded and rounded once, where it is displayed.

Verified by `test/training_load_test.dart` (`sessionLoadMinutes (D-901)`,
including `S-1501`, `S-1502`, and the case pinning each rating 1–5 to
`60 × rating`).

---

## The effort-to-modality rule

An effort's modality comes from its **kind**, never from the session's modality:
a timed effort inside a lifting session is Cardio. That invariant is owned by
[Global Conventions](global_conventions.md). The definitions take an
`ExerciseSection` and never a kind string, so the mapping has one home and
cannot be restated. Where two modalities tie, the order is `ExerciseSection`'s
declaration order — Resistance, then Cardio, then Isometric, then Sports. That
order is the tie-break for both the dominant modality and the segment order, so
a tie always resolves the same way.

Verified by `test/training_load_test.dart` (`S-1506 B`, `S-1512`).

---

## Time per modality

The split takes a per-modality map of **measured active time** in seconds; it
never derives that map itself and never reads a stored instance. A caller that
produces the sums is the only place that touches the stored instances.

- A non-rolling session's Resistance time is the remainder: its own duration
  minus the measured sums, never below zero. Its duration is the same figure
  the all-time totals use.
- When the measured sums exceed the duration, the whole session's time goes to
  its **dominant** modality instead — the modality with the most efforts of
  that modality's kind. A session with no effort that maps to a modality
  contributes nothing at all.
- A **rolling** session has no duration to use, so its time is the measured
  sums only; its sets add no time. A sets-only rolling session contributes
  nothing.

A session's **load** splits across those same modalities in proportion to their
time, and every modality's load is zero when the session's time is zero or the
session is unrated. The split is never rounded per session.

Verified by `test/training_load_test.dart` (`sessionTimeByModality (D-904–D-906)`
— `S-1503`, `S-1504`, `S-1505`, `S-1506 A`, `S-1507`, `S-1508`, `S-1509 A`,
`S-1515`, `S-1516`, and the cases for a non-negative remainder and a session
with no mapping effort — and `sessionLoadByModality (D-907)`).

---

## Segments and percentages

Only modalities with a positive measure become segments, so a window whose only
work is lifting yields one Resistance segment rather than a full list with three
empty ones. Segments are ordered by descending measure, ties resolving in
`ExerciseSection` declaration order.

Percentages use the largest-remainder method: each segment's exact share is
floored, and the points left over go one each to the largest fractional
remainders, ties broken first by the larger exact share and then by
`ExerciseSection` declaration order. The percentages of one list always sum to
exactly 100, and a modality with a positive measure always receives a segment
even when its rounded share is zero. Segment **widths** use the exact
proportions, never the rounded percentages, so a small modality is never drawn
as absent.

Verified by `test/training_load_test.dart` (`mixSegments (D-912, D-913)` —
`S-1501`, `S-1503`, `S-1512`, `S-1515`, `S-1516`, and the cases for a
zero-measure modality, an empty measure, and a positive measure at 0%).

---

## The baseline period

The baseline is the stretch of history a window is compared against. It is
`kTrainingLoadBaselineWeeks` consecutive blocks of 7 **calendar** days each,
anchored at the local-midnight day of the window's start, oldest block first.
The blocks tile the period immediately before that day, so the last block ends
the instant before it: no gap, no overlap, and the window is never inside its
own baseline.

The blocks are computed from calendar components rather than a `Duration`, so a
daylight-saving transition cannot shift a boundary. They are also independent of
the saved start-of-week setting — changing that setting never moves a baseline
boundary. A **rated baseline week** is one of the blocks containing at least one
completed session with a rating.

Verified by `test/training_load_test.dart` (`baselineBlockStarts (D-934)`,
including the block count, the no-gap case, the last-block boundary, the
anchoring case and the DST case).

---

## The weekly strip

A strip holds `kMixStripWeeks` weeks and a week's start comes from
`OmniDateUtils.startOfWeek`, which honours the saved start-of-week setting and
treats any value other than `'sunday'` as `'monday'`. The helper is built from
calendar components, so a daylight-saving transition cannot shift a week
boundary. It serves the strip only; the baseline does not use it.

`MixWeek` carries a week's start, its segments, its measure and whether it is
the current week. `MixLayerData` carries the measure the figures are in, the
window's segments and its baseline's segments, the two counts the surface
reports, and the strip.

Verified by `test/training_load_test.dart` (`OmniDateUtils.startOfWeek (D-910,
D-935)` — every weekday under both settings, an unrecognised setting, and the
local-midnight result — and the constant contract for `kMixStripWeeks`).

---

## The four constants

| Constant | Rule it governs |
|----------|-----------------|
| `kMixStripWeeks` | How many weeks a weekly strip holds |
| `kTrainingLoadBaselineWeeks` | How many 7-calendar-day blocks the baseline spans |
| `kTrainingLoadMinRatedWeeks` | How many rated baseline weeks the load measure needs before it is shown |
| `kTrainingLoadMaxUnratedShare` | The largest share of a window's time that may be unrated for the load measure to be shown; the boundary is inclusive |

Verified by `test/training_load_test.dart` (the constant contracts).

---

## The entry point

`StatsProgressService.computeMixLayer` is the only history walk behind these
figures. It takes the window, the current instant and the saved start-of-week
setting, and returns the whole payload — the measure, the window's bar, the
baseline's segments, the two counts and the strip — or `null` when the window
holds no time at all, because there is nothing to split.

It reads the service's cached history snapshot once and serves the window, the
baseline and the strip from that single pass, so the surface pays for no extra
repository read. The window's sessions are selected by the same predicate the
other stats reads use; the baseline's are those starting inside the baseline
blocks; the strip's are selected against each week's own bounds and never
against the window, so changing the window moves the bar and leaves the strip
alone.

The measure is load only when the baseline is rated enough and the window is
rated enough; otherwise it is time. The baseline's segments are built in the
load measure only, and only when the baseline's total load is above zero. The
strip's weeks are the `kMixStripWeeks` weeks ending with the week containing
the current instant, oldest first, with the last week marked in progress; an
empty week is present with a zero measure rather than dropped, and a session
belongs to the week it started in.

Verified by `test/mix_layer_service_test.dart` (`S-1501`, `S-1502`, `S-1503`,
`S-1505`, `S-1509`, `S-1510 A`–`E`, `S-1511` and its start-of-week twin,
`S-1513` and its Sunday-start twin, `S-1514`, `S-1515`, `S-1516`, `S-1517`,
and the Mock/Hive value-for-value parity group).

`StatsProgressService.computeMixPeriod` is the second entry point over the same
walk. It takes a period's two instants instead of a `StatsWindow` and returns
the same payload shape, so a rule that compares an arbitrary period against its
baseline reads the same measure, bar and baseline the Mix layer does. It
carries no weekly strip, because a period is not anchored to a week; its
baseline is the same `kTrainingLoadBaselineWeeks` calendar blocks before the
period's start day, and the measure gate is the same one.

Verified by `test/modality_mix_period_service_test.dart` (`S-1904a`, `S-1907`,
`S-1913`, over both repository implementations).

---

## Related Documentation

- [Stats Screen](stats_screen.md) — the surface the mix figures are read on
- [Modality Tracking](modality_tracking.md) — effort kinds and what they imply
- [Constants & Configuration](constants_reference.md)
- [Data Models](data_models.md)

---

**Document Version**: 1.0
**Last Updated**: October 3, 2026
