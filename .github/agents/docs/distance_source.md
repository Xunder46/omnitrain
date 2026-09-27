# Distance Source and Pairing

**Scope.** What a stored distance means. Covers the source a distance records
(`EffortObservation.valueSource` in `lib/data/models/models.dart` and the
`value_source` column of `app_effort_observation` in
`scripts/sqlite_schema.sql`), which entry a distance row belongs to
(`DistancePairing` in `lib/core/utils/distance_source.dart`), what the stored
source resolves to (`DistanceSource`, same file), and the write that changes a
distance (`SessionCore.setEntryDistance` / `confirmEntryDistance` in
`lib/state/workout/session_core_entry.dart`, delegated from `WorkoutState`).
The Session Summary's DISTANCE section writes through these rules and
`StatsProgressService` reads through them.

This document does not cover how a distance is measured. The watch's own
recording and the phone's import of it are described in
[Watch Session Capture](watch_session_capture.md).

---

## Structure

A distance is an `EffortObservation` whose `metricId` is `metric-distance`,
with the value in metres. It carries an optional `valueSource`, and no other
observation may carry one. The model refuses a violation at construction and
the schema refuses it at insert; both mirrors of the same rule are listed under
Invariants below.

`DistanceSource` is the only place that says what a stored source means:
`resolve` maps a missing source to `entered`, and `isEstimated` answers whether
a value is an estimate. `StatsProgressService` marks a training day as
estimated when any distance counted in that day's total is one, and the Stats
card renders that mark.

`DistancePairing` is how the source-aware code decides which distance row
belongs to which entry. Nothing in storage links the two, so it pairs the
effort's `metric-distance` rows with the effort's entries by relative order,
sorting the rows by the entry number in the row id
(`obs-<effortId>-<n>-distance`), then `createdAtMs`, then id. The Session
Summary's rows, the state write and the Stats pace all read through it.
`updateEntryValue` (Edit Session, the live screen, routine pre-fill) and
`SessionSummaryBuilder` still pair a distance with its entry by raw list order,
so the two rules can disagree (plan O-3).

`SessionCore` owns the write that records a source: `setEntryDistance` stores a
value, and `confirmEntryDistance` re-records the value an entry already holds.
Both keep an existing row's id and `createdAtMs` and stamp a new `updatedAtMs`.
When the edited entry has no row of its own, the write first fills every
earlier unpaired entry with a zero-valued row so that the pairing the next
write reads stays positional. On an effort that is not timed, the entries are
the distance rows
themselves — the rows a stored distance keeps visible, which have no timed
instance behind them.

The Session Summary's DISTANCE section is the one phone surface that calls
that write: the live screen and Edit Session have no distance field. What the
section lists is [Session Summary](session_summary.md)'s to describe; what a
stored distance means is this document's.

## Rationale

**Why a missing source reads as `entered`.** Every distance stored before the
field existed was typed or dialled by a person, and so is every distance the
phone and the watch import write today. Treating absence as `entered` avoids a
data migration and keeps legacy rows honest at once. Absence is not a fourth
source: it is the same fact, recorded by an older writer.

**Why confirming flips the source.** A stored `estimated` or `gps` value is
something a machine produced. The moment a person looks at that number and
accepts it, it is their number — so a confirmation records the same metres
under `entered` rather than leaving the value claiming a provenance it no
longer has. The metres themselves do not move: a confirm is not a conversion,
and re-deriving the stored value from a rounded display value would quietly
change it.

**Why pairing is computed and not stored.** A distance row and its entry are
written by different code paths, and an entry's duration lives on its
`TimedInstance` rather than on the row. An explicit link (an `entryIndex`
column, or the timed instance's id on the row) would be a second place that can
disagree with the id convention the rest of the app already reads indices out
of. Ordering by the number already in the id, with the same tie-breakers the
repository ordering contract uses, resolves the same pairing from any list of
rows — including the key-sorted order Hive returns, which is not entry order.

**Why the write fills earlier gaps.** Pairing is positional, so a row created
for entry 3 while entries 0-2 have none would be read as entry 0's. Writing the
missing rows as zero-valued, source-less rows keeps the positions stable and
costs nothing visible: a zero distance is absence, not a value.

## Invariants

- A source appears only on a `metric-distance` row, and only from the three
  values the model defines. A writer defect throws `ArgumentError` at
  construction and is refused by the schema's CHECK. Verified by
  `test/distance_source_test.dart` (`S-803 writer defects are refused`) and
  `test/db_seed_test.dart` (`Distance source schema contract (D-301 / D-311)`).
- `toMap` and the schema agree: every key the model writes is a column.
  Verified by `test/db_seed_test.dart` (same group).
- A row stored without the key reads back as null, resolves to `entered`, is
  not estimated, and round-trips through both repositories — including across a
  Hive restart. Verified by `test/distance_source_test.dart` (`S-801`,
  `S-802`).
- Every field-by-field copy of an observation forwards the source, so a copy
  never turns an estimate into an entered value or the reverse. Verified by
  `test/distance_source_test.dart` (`S-804 copies keep the source`, and the
  source guard in `S-804 (c) source guard`).
- A write keeps the row's id and `createdAtMs` and updates `updatedAtMs`.
  Verified by `test/distance_source_test.dart` (`S-805`).
- Confirming keeps the stored metres exactly and changes only the source; a
  zero-valued row stays zero and source-less. Verified by
  `test/distance_source_test.dart` (`S-806`).
- Pairing is order-independent and pairs entry *k* with its own row for every
  entry. Verified by `test/distance_source_test.dart` (`S-808`).
- Entries with no row of their own are filled in position before the edited
  entry is written. Verified by `test/distance_source_test.dart` (`S-807`).
- Only the Summary's write changes a source; every copy keeps it, including
  across a repository restart and through an Edit Session snapshot and restore.
  Verified by `test/distance_source_test.dart` (`S-802`, `S-805`) and
  `test/session_summary_distance_test.dart` (`S-821`).
- A reader of a distance resolves its source through `DistanceSource` rather
  than testing the stored string, so a legacy row marks nothing and a reader
  cannot invent a fourth meaning. Stats' estimate marking is
  `test/stats_distance_estimate_test.dart` (`S-832`–`S-835`).
- A distance row belongs to the entry its position implies, in any order a
  store returns rows in, and the Summary's write and the Stats reader agree on
  that pairing. Verified by `test/distance_source_test.dart` (`S-808`) and
  `test/stats_distance_estimate_test.dart` (`S-831`).

## Vocabulary

- **Distance source** — where a stored distance's value came from. One of
  `gps` (the watch's GPS measured it), `entered` (a person typed or dialled it)
  or `estimated` (the watch platform estimated it). Only `estimated` is marked
  where a distance is displayed.
- **Legacy distance** — a stored distance with no source key at all. It reads
  as `entered`.
- **Paired row** — the distance row an entry owns, as `DistancePairing`
  computes it. An entry with no distance has no paired row and reads as
  absence, never as zero.
- **Entry index** — an entry's position among the effort's entries: its timed
  instances, or its distance rows on an effort that is not timed. It is the
  index the rest of the app encodes in observation ids and the index the
  distance write takes.
