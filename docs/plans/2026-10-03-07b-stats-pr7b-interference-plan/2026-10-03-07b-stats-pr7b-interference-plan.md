# Feature: Cross-Modality Interference After Hard Sports Sessions (Stats PR 7b — pack item 11)

> **Status:** READY (planner) — not started.
> **Next handoff:** @dba (Phase 1)
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 11
> ("Cross-Modality Interference After Hard Sports Sessions (Caution)"), and the series seam in
> `docs/plans/2026-10-03-07-stats-pr7-index.md`.
> **Base:** `develop`, Stats PR 6 DONE (`docs/plans/2026-10-03-06-stats-pr6-index.md`); PR 7a DONE
> (`docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/`), which owns the caution order this plan's
> priority is the top of.
> **Binding conventions:** `docs/global_conventions.md`. `docs/README.md` entries this plan depends on,
> read before Phase 1: `docs/signals.md`, `docs/training_load.md`,
> `docs/state_management/services_and_utils.md`, `docs/state_management.md`, `docs/stats_screen.md`,
> `docs/constants_reference.md`, `docs/data_models.md`, `docs/modality_tracking.md`,
> `docs/documentation_standard.md`, `docs/design_system.md`. Budget:
> `.github/agents/pr_scope_budget.md`.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 652 | 500 | 800 |
| Phases | 3 | >3 | >5 |
| Tracks | 1 (`lib/`, `test/`, `docs/`) | >1 | — |
| Ledger decisions | 20 (D-1301…D-1320) | >20 | — |
| Scenarios | 15 (S-2001…S-2015) | >30 | — |
| Predicted production lines | ~360 | — | ~1,500 |

**Verdict:** one soft signal (plan length), zero hard — 20 decisions sit exactly on the soft boundary,
not over it. The split rule is "split if two or more soft signals", so this stays one PR. 7a
(`2026-10-03-07a-stats-pr7a-mix-shift-plan/`) is the other half and must land first, because this
plan's priority is defined relative to 7a's.

## What this PR does

One new caution signal: after the user's hard sports sessions, their next lifting day has come in
below their own usual level on the same lifts, three times in the last 45 days. It needs a new
session-level walk on `StatsProgressService` (per-session Sports load and per-exercise bests), the
pure rule and copy, and the one registry line that puts the card on the layer.

## Out of scope

- Recommending specific sports-to-lifting gaps or schedules (pack's out-of-scope).
- Classifying hard sessions by heart rate (pack's out-of-scope).
- Any calendar or planning action (pack's out-of-scope).
- Any change to the Mix layer's rendered figures, the Signals framework, the Stats window chips, the
  PR rules, `lib/data/` or `watch/`.
- Modality Mix Shift — that is 7a.

## Resolved Decisions (Ledger)

**D-1301 — A sports session, and the load it is ranked by.** A session is a sports session when the
shared load split attributes a positive measure to the Sports modality:
`sessionLoadByModality(...)[ExerciseSection.sports] > 0`. The load a sports session is ranked and
summed by is that same Sports component, in load minutes — never the session's whole load and never
its raw duration. *(Derived from the pack's "a sports session whose load is in the user's top 25% of
rated sports sessions" — owner to confirm; see Open questions.)*

**D-1302 — The hard window and its population.** The hard window is the 90 local calendar days ending
at `now`: a session counts when `startMs >= now − kInterferenceHardWindowDays && startMs <= now`, both
ends inclusive, computed with calendar components. The population is the *rated* sports sessions in
that window — a session with no rating has zero load and is never in it (D-1305). Hard classification
exists only when the population holds at least `kInterferenceMinRatedSportsSessions` (8) sessions;
with 7 or fewer, nothing is hard and the signal abstains.

**D-1303 — Hard.** Sort the population's Sports loads ascending. With `n` = the population size,
`threshold = sorted[(kInterferenceHardPercentile × n).ceil() − 1]` (nearest-rank, so the top 25% is
counted, not interpolated). A session is hard when `sportsLoad >= threshold` — inclusive, so the
session sitting exactly on the threshold is hard.

**D-1304 — The follow-up.** A hard session's follow-up is the session with the smallest `startMs`
among those that (a) contain at least one effort whose section maps to Resistance (through the shared
kind→section rule, never a literal comparison) and (b) start strictly after the hard session's end and
at most `kInterferenceFollowUpHours` (36) hours after it: `endMs < startMs <= endMs + 36 h`. A session
starting exactly at the end is not a follow-up; one starting exactly 36 hours later is. Ties on
`startMs` resolve by session id ascending. A hard session with no such session has no follow-up and
contributes nothing. The first qualifying session is the follow-up whatever it holds — a later session
is never substituted for it.

**D-1305 — The comparable exercises.** A follow-up's exercise is comparable when (a) the exercise's
best in the follow-up is above zero under the shared native-value rule for the exercise's own axis
(the rule's zero fallback is not a value), and (b) the exercise has at least one qualifying prior
session — a session starting in `[followUpStart − kInterferenceDipWindowDays, followUpStart)`, the
lower bound inclusive and the upper exclusive — in which its best is also above zero. An exercise with
no qualifying prior session is not comparable.

**D-1306 — The prior average excludes every follow-up.** The prior average is the mean of the
exercise's per-session bests over its qualifying prior sessions, and it excludes every follow-up this
evaluation identified: the follow-up being measured and the follow-ups of other hard sessions alike. A
follow-up never votes for its own baseline and never depresses another's.

**D-1307 — The shortfall, the dip and the exclusion.** A comparable exercise's shortfall is
`(average − best) / average` — positive when the follow-up is below the user's own recent level. The
follow-up dips when the *unweighted* mean of its comparable exercises' shortfalls is at least
`kInterferenceMinDip` (1/10): one exercise, one vote, never weighted by volume, sets or load. A
follow-up with no comparable exercise is excluded — it is not a dip and it is not counted anywhere.

**D-1308 — The 10% boundary's arithmetic.** The dip test is
`meanShortfall >= kInterferenceMinDip − 1e-9`. The tolerance exists because `1 − 0.9` is
`0.09999999999999998` in binary floating point: without it a shortfall of exactly one tenth would not
dip. `1e-9` is seven orders of magnitude below the smallest difference the measure can carry (a tenth
of a percent) and above the representation error, so exactly 10% dips and 9% does not.

**D-1309 — The pattern.** `k` is the number of dipped follow-ups whose `startMs` falls in
`[now − kInterferencePatternWindowDays (45 days), now]`, both ends inclusive. The signal abstains
unless `k >= kInterferenceMinDippedFollowUps` (3).

**D-1310 — `n`.** `n` is the number of hard sessions (D-1302, D-1303) whose follow-up (D-1304) has at
least one comparable exercise (D-1305) and starts in `[now − 45 days, now]`. A hard session with no
follow-up, a follow-up outside the window, or a follow-up with no comparable exercise is not in `n`.
`n >= k` always.

**D-1311 — The dip range.** `lo` and `hi` are the smallest and largest of the counted follow-ups' mean
shortfalls multiplied by 100 and rounded to whole numbers. Only the follow-ups `k` counts contribute —
a dipped follow-up outside the 45-day window never widens the range.

**D-1312 — Observation.** Sentence one is
`'After $k of your last $n hard sports sessions, your next lifting day came in $lo–$hi% below your usual on the same lifts.'`
— an en dash (U+2013) between the two numbers and one `%` after the second. When `lo == hi` the range
collapses to a single number: `'… came in $lo% below your usual on the same lifts.'` *(Derived; owner
to confirm — see Open questions.)*

**D-1313 — The optional second sentence.** Appended to the same observation string as
`' Sports load is up $p% over the last 3 weeks.'` only when the Sports load over
`[now − kInterferenceSportsLoadWindowDays, now]` is at least `kInterferenceSportsLoadRisePercent` (30)
per cent higher than over `[now − 2 × kInterferenceSportsLoadWindowDays, now − kInterferenceSportsLoadWindowDays)`
and the earlier span's Sports load is above zero: `prior > 0 && 10 × recent >= 13 × prior`. `p` is
`((recent / prior) − 1) × 100`, rounded to a whole number. The sentence is omitted in every other case,
including when the earlier span is zero — there is never a division by zero and never an infinite rise.

**D-1314 — Suggestion.** `'A lighter or isometric-focused day after hard sports sessions is one option.'`
— verbatim from the pack.

**D-1315 — Kind, priority, id and title.** Kind caution. Priority
`kCrossModalityInterferencePriority = 500`, the highest among cautions, above 7a's Mix Shift (400).
The order, written once in `docs/signals.md` by 7a: Interference 500 > Mix Shift 400 > Fuel vs Load
300 > Protein Consistency 200 > Sustained High Load 100 > Cardio Efficiency Drift 50. The id is
`cross-modality-interference` — the dismissal key, the widget key and the semantic label. The title is
`Interference after hard sports sessions` and is never rendered (the layer renders the kind's label).

**D-1316 — The walk's payload and ordering.** `StatsProgressService.interferenceSessions()` returns one
`InterferenceSession` per completed session in the cached history, ordered by `startMs` ascending with
ties by session id ascending, carrying the session id, `startMs`, `endMs`, the rating, the Sports load
in load minutes (0 when unrated or when the session has no sports work), whether the session contains
at least one Resistance effort, and the per-exercise bests above zero. One walk over the cached history
index, no second repository read.

**D-1317 — One split, two readers.** The per-session time and load splits that `computeMixLayer`
computes become a private helper both the Mix walk and `interferenceSessions` call, so a session's
Sports load cannot differ between the Mix layer and the signal. `computeMixLayer`'s rendered figures do
not change: same measure, same segments, same percents, same counts, same strip.

**D-1318 — Plug-in only.** The signal is one class implementing `Signal` in
`lib/core/services/signals/interference_signal.dart` plus one line in `buildSignalRegistry()`. No file
in `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart` or
`lib/features/stats/widgets/signals_layer.dart` changes, and `SignalContext` gains no member.

**D-1319 — No PR rule.** The dip measure shares no rule with the personal-record measure: it never
calls a PR API, never reads an all-time best, and never compares two exercises with each other. Every
comparison is an exercise against its own recent history.

**D-1320 — Dismissal is the framework's.** The signal adds no dismissal rule and no preference key;
the framework's 14-local-day window applies unchanged.

## Feature Invariants

Only the invariants that bite here; project-wide rules stay in `docs/global_conventions.md`.

- **The Mix layer's rendered figures do not change.** D-1317's extraction is behaviour-preserving.
  Proven by the existing Mix suites, read-only in this PR.
- **A signal never walks history itself.** The signal calls the service; the service rides its cached
  history index. One repository read per screen evaluation.
- **One signal = one class + one registry line.** No framework file names a concrete signal.
- **No new colour, token, widget or `OmniTheme` value.** The card uses the layer's existing caution
  styling.
- **The PR path is untouched** and the PR rules are not reused (D-1319).
- **Repository parity.** The walk's per-session values are identical on `HiveWorkoutRepository` and
  `MockWorkoutRepository`, because both sit behind the same repository interface and the walk reads
  only what the interface returns.

## Requirements

- **R1** A user with a run of hard sports sessions followed by sub-par lifting days sees one caution
  card, with the counts and the dip range.
- **R2** A single bad day, or two, is never enough.
- **R3** The comparison is per exercise against that exercise's own recent level, never against another
  exercise and never against a raw-volume total.
- **R4** A user without 8 rated sports sessions in 90 days never sees the card.
- **R5** The card is dismissible and stays dismissed for the framework's window.
- **R6** No existing Stats figure changes.

## Acceptance Criteria (each maps to ≥1 scenario)

| # | Criterion (from the pack) | Scenarios |
|---|---|---|
| AC-1 | 3 dipped follow-ups in the last 45 days and ≥8 rated sports sessions in 90 days shows the card with the actual count and dip range | S-2001 |
| AC-2 | 2 dipped follow-ups in 45 days shows no card | S-2002 |
| AC-3 | A resistance session starting 37 hours after a hard sports session is not a follow-up | S-2003 |
| AC-4 | A follow-up whose exercises average 9% below their own recent level is not a dip | S-2004 |
| AC-5 | 7 rated sports sessions in 90 days never shows the card | S-2005 |
| AC-6 | A follow-up containing only exercises never trained before is excluded, not counted as a dip | S-2006 |
| AC-7 | The second sentence appears only when sports load rose at least 30% over the last 21 days | S-2007 |
| AC-8 | The top-25% hard boundary, inclusive | S-2008 |
| AC-9 | Unrated sports sessions are never hard | S-2009 |
| AC-10 | Exactly 3 in 45 days fires; a case outside the window does not count | S-2010 |
| AC-11 | The dip is per exercise against its own average, excluding other follow-ups | S-2011 |
| AC-12 | The walk's Sports load is the Mix layer's own figure, on both repositories | S-2012 |
| AC-13 | The card renders on the layer, dismisses, and leaves every other block alone | S-2013 |
| AC-14 | The framework and the PR path are untouched | S-2014 |
| AC-15 | The 90-day hard window's bounds are exact | S-2015 |

## Scenarios

Fixtures name every entity class involved. `day(n)` means local midnight `n` days before today; all
sessions start at 09:00 local and all times are local. The pure scenarios build
`InterferenceSession` lists directly; the service scenarios seed the repository through
`test/helpers/repository_harness.dart` (never edited — both plans need a local rated-session seeder,
because the harness's `seedSession` writes a fixed one-hour end and no rating).

### S-2001: the pack's own example fires
- **Fixture (F-2001, pure):** all sessions `hasSetEffort: false` unless stated.
  - 12 rated sports sessions at days 88, 80, 70, 60, 55, 50, 44, 40, 34, 28, 18, 8 with Sports loads
    4, 8, 12, 20, 24, 28, 30, 41, 50, 50, 55, 83 (rating 4 throughout except the day-8 session, rating
    5), each with no set effort.
  - 7 prior lifting sessions at days 58, 52, 46, 42, 38, 36, 30, each `hasSetEffort: true` with
    `{ex-lift: 100.0}`.
  - 4 follow-up lifting sessions at days 33 (`{ex-lift: 84.0}`), 27 (`{ex-lift: 100.0}`), 17
    (`{ex-lift: 89.0}`), 7 (`{ex-lift: 88.0}`), each `hasSetEffort: true`.
  - Ends: the day-34 session runs 750 s (end 09:12:30), day 28 runs 750 s, day 18 runs 825 s, day 8
    runs 996 s (end 09:16:36).
- **Trigger:** `crossModalityInterference(sessions: sessions, now: now)`.
- **Flow:** D-1302/D-1303 → 12 rated sports sessions, sorted loads
  `4, 8, 12, 20, 24, 28, 30, 41, 50, 50, 55, 83`, `ceil(0.75 × 12) = 9`, `threshold = sorted[8] = 50`,
  hard = days 34 (50), 28 (50), 18 (55), 8 (83). D-1304 → follow-ups at days 33, 27, 17, 7 (each is
  the earliest set-effort session after its hard session's end and within 36 h; no prior session falls
  inside any hard session's 36-hour interval). D-1305/D-1306 → each follow-up's 28-day lookback holds
  only 100.0 priors (FU1: days 58, 52, 46, 42, 38, 36; FU2: 52, 46, 42, 38, 36, 30; FU3: 42, 38, 36,
  30; FU4: 30) — FU1's, FU2's and FU3's lookbacks also contain the earlier follow-ups, which D-1306
  excludes. D-1307 → shortfalls 16%, 0%, 11%, 12% → the first, third and fourth dip. D-1309/D-1310 →
  `k = 3`, `n = 4`. D-1311 → `lo = 11`, `hi = 16`. D-1313 → Sports load in `[day 21, now]` is
  55 + 83 = 138, in `[day 42, day 21)` is 50 + 50 = 100, `10 × 138 = 1380 >= 13 × 100 = 1300` → `p = 38`.
- **Expected outcome:** fires. Observation exactly `'After 3 of your last 4 hard sports sessions, your
  next lifting day came in 11–16% below your usual on the same lifts. Sports load is up 38% over the
  last 3 weeks.'` (en dash); suggestion exactly `'A lighter or isometric-focused day after hard sports
  sessions is one option.'`
- **Edge case of:** none.

### S-2002: two dips are not a pattern
- **Fixture:** F-2001 with the day-17 follow-up at `{ex-lift: 100.0}` and the day-7 follow-up at
  `{ex-lift: 100.0}`.
- **Trigger:** one call.
- **Flow:** D-1309's floor.
- **Expected outcome:** null. Only the day-33 follow-up dips (16%) → `k = 1 < 3`.
- **Edge case of:** S-2001.

### S-2003: the follow-up boundary, on both sides, and the first session only
- **Fixture:** one hard sports session H (rated, load 100, `endMs = E`) plus the rated population
  needed for the 8-floor — 7 rated sports sessions with loads 1–7 placed at days 88, 84, 80, 76, 72,
  68, 64 (all far from any lifting session, so none of them has a follow-up). Five sub-cases, each
  adding lifting sessions to a copy of that base list:
  - (a) a lifting session starting exactly at `E`;
  - (b) a lifting session starting exactly at `E + 36 h`;
  - (c) a lifting session starting exactly at `E + 37 h`, with (b) absent;
  - (d) a session with no set effort (a cardio/timed session) starting at `E + 1 h` and a lifting
    session at `E + 2 h`;
  - (e) lifting sessions at `E + 1 h` and `E + 2 h`.
- **Trigger:** one call per sub-case.
- **Flow:** D-1304.
- **Expected outcome:** (a) H has no follow-up (`startMs > endMs` is strict) → null; (b) the `E + 36 h`
  session is the follow-up (the upper bound is inclusive); (c) the `E + 37 h` session is not → H has no
  follow-up → null; (d) the follow-up is the `E + 2 h` session, not the `E + 1 h` one; (e) the
  follow-up is the `E + 1 h` session.
- **Edge case of:** S-2001. (The 36-hour upper bound is mutation (a) in Phase 1.)

### S-2004: the 10% boundary
- **Fixture:** a hard sports session H with a lifting follow-up F, plus prior lifting sessions so that
  F's lookback average is exactly 100.0. Sub-cases:
  - (a) F's best 90.0 → shortfall `1 − 0.9 = 0.09999999999999998`;
  - (b) F's best 91.0 → shortfall 0.09;
  - (c) F has two comparable exercises, shortfalls 0.19 and 0.01 → mean exactly 0.10;
  - (d) F has two comparable exercises, shortfalls 0.19 and −0.01 → mean 0.09.
- **Trigger:** one call per sub-case.
- **Flow:** D-1307, D-1308.
- **Expected outcome:** (a) dips (the tolerance is what makes it dip — mutation (b) in Phase 1 removes
  it and this sub-case fails); (b) does not dip; (c) dips (the unweighted mean, exactly 10%); (d) does
  not dip.
- **Edge case of:** S-2001.

### S-2005: seven rated sports sessions never classify
- **Fixture (F-INT, service):** seeded on the repository through the harness. 8 rated sports sessions
  at days 88, 80, 70, 60, 44, 30, 20, 10, each a non-rolling session whose single finished round
  effort is its whole duration, so the session's time and load are Sports only:
  | daysAgo | rating | round seconds | Sports load |
  |---|---|---|---|
  | 88 | 4 | 60 | 4 |
  | 80 | 4 | 120 | 8 |
  | 70 | 4 | 180 | 12 |
  | 60 | 4 | 300 | 20 |
  | 44 | 4 | 360 | 24 |
  | 30 | 5 | 600 | 50 |
  | 20 | 4 | 420 | 28 |
  | 10 | 5 | 492 | 41 |
  Plus 10 rated lifting sessions at days 62, 55, 50, 40, 33, 26, 22, 12, 6, 2, each one exercise
  `ex-lift` (capabilities `load`, `reps`), one set, 1 rep, 100 kg; and 3 follow-up lifting sessions at
  days 29, 19, 9, each `ex-lift`, one set, 1 rep, at 84 kg, 90 kg and 89 kg.
- **Trigger:** (a) `crossModalityInterference(sessions: await service.interferenceSessions(), now: now)`
  on F-INT; (b) the same with the day-88 sports session removed.
- **Flow:** D-1302's floor.
- **Expected outcome:** (a) fires — sorted loads `4, 8, 12, 20, 24, 28, 41, 50`, `ceil(0.75 × 8) = 6`,
  `threshold = sorted[5] = 28`, so days 30, 20 and 10 are hard (day 20 sits exactly on the threshold
  and is hard; day 44 at 24 is not) and the follow-ups at days 29, 19, 9 dip by
  `1 − 84/100 = 16%`, `1 − 90/100 = 0.09999999999999998` and `1 − 89/100 = 11%` → `k = 3`, `n = 3`,
  `lo = 10`, `hi = 16`; (b) null — 7 rated sports sessions < 8.
- **Edge case of:** S-2001 (the same rule, hand-built rather than walked).

### S-2006: a follow-up with nothing to compare is excluded, not a dip
- **Fixture:** a hard sports session H; a follow-up F1 containing only `ex-new`, which has no session
  anywhere before it; a follow-up F2 (after a second hard session) containing `ex-new` and `ex-known`,
  where `ex-known`'s prior average is 100.0 and its best in F2 is 90.0.
- **Trigger:** one call.
- **Flow:** D-1305, D-1307.
- **Expected outcome:** F1 is excluded — not a dip and not in `n`; F2's mean is over `ex-known` only
  (0.09999999999999998) → F2 dips. With only these two hard sessions `k = 1 < 3` → null, and the
  assertion is on the result's own counts: `n = 1`, `k = 1`.
- **Edge case of:** S-2001.

### S-2007: the second sentence's boundary
- **Fixture:** F-2001's session list with the Sports loads in the two 21-day spans set directly.
  Sub-cases: (a) prior 100, recent 130; (b) prior 100, recent 129; (c) prior 0, recent 500.
- **Trigger:** one call per sub-case.
- **Flow:** D-1313.
- **Expected outcome:** (a) the sentence is included with `p = 30` —
  `'… Sports load is up 30% over the last 3 weeks.'`; (b) omitted; (c) omitted (no division by zero,
  no infinite rise).
- **Edge case of:** S-2001.

### S-2008: the top-25% boundary is inclusive
- **Fixture:** F-2001's population (12 sessions, threshold 50) and a 9-session variant with loads
  1–9.
- **Trigger:** one call per variant.
- **Flow:** D-1303.
- **Expected outcome:** 12 sessions → the day-34 and day-28 sessions at exactly 50 are hard, the
  day-40 session at 41 is not, and the hard set has 4 members; 9 sessions → `ceil(6.75) = 7`,
  `threshold = sorted[6] = 7`, so loads 7, 8 and 9 are hard (3 of 9).
- **Edge case of:** S-2001.

### S-2009: unrated sports sessions are never hard and never counted
- **Fixture (pure):** F-2001's population plus three unrated sports sessions carrying the largest raw
  work in the list (3600-second round efforts, no rating) at days 86, 84 and 82, each with
  `sportsLoadMinutes: 0`. **Service:** F-INT plus one unrated sports session at day 5 with a
  3600-second round effort.
- **Trigger:** one call each; the service case goes through `interferenceSessions()`.
- **Flow:** D-1302, D-1305.
- **Expected outcome:** the unrated sessions are not in the population, do not move the threshold, are
  never hard, and the card is unchanged (same `k`, `n`, `lo`, `hi`, and the same 38% sentence). The
  service walk reports their Sports load as 0.
- **Edge case of:** S-2001, S-2005.

### S-2010: the 45-day pattern window
- **Fixture:** F-2001's list with the follow-up days moved. Sub-cases:
  - (a) dipped follow-ups at days 45, 44, 43 (the lower bound is inclusive) → fires;
  - (b) dipped follow-ups at days 44, 43, 42 plus one dipped at `day(45) 00:00 − 1 ms` → the last one
    is outside the window and does not count → `k = 3` still fires, and the out-of-window dip does not
    appear in `lo`/`hi`.
- **Trigger:** one call per sub-case.
- **Flow:** D-1309, D-1311.
- **Expected outcome:** (a) fires with `k = 3`; (b) fires with `k = 3`, `n` unchanged, and the range
  computed only from the three counted follow-ups.
- **Edge case of:** S-2001, S-2002.

### S-2011: the prior average excludes other follow-ups (service)
- **Fixture:** F-INT (S-2005).
- **Trigger:** `crossModalityInterference(sessions: await service.interferenceSessions(), now: now)`.
- **Flow:** D-1306.
- **Expected outcome:** the day-19 follow-up's shortfall is exactly one tenth and the day-9
  follow-up's is 11%, which only holds when the day-29 follow-up is excluded from the day-19
  lookback and the day-29 and day-19 follow-ups are excluded from the day-9 lookback. The
  counterfactual is the point: including the day-29 follow-up (86.8 on the 103.3333 average) would
  give `1 − 93/100.0267 = 7.0%` → no dip at day 19 → `k = 2` → no card.
- **Edge case of:** S-2001.

### S-2012: the walk's Sports load is the Mix layer's own figure
- **Fixture:** F-INT seeded on the repository, run on both harness factories.
- **Trigger:** `interferenceSessions()` and `computeMixLayer(window: periodScoped(day(89), todayEnd), now: now, startOfWeek: 'monday')`.
- **Flow:** D-1316, D-1317.
- **Expected outcome:** the Sports segment's exact measure equals the sum of the walk's per-session
  Sports loads over the same window (`4 + 8 + 12 + 20 + 24 + 28 + 41 + 50 = 187` in load mode), and
  every per-session value is identical on `HiveWorkoutRepository` and `MockWorkoutRepository`.
- **Edge case of:** S-2005.

### S-2013: the card on the layer, and its dismissal
- **Fixture:** F-INT on the Mock repository, the Stats window scoped so the Mix layer renders above the
  Signals layer, and no other signal qualifying.
- **Trigger:** open the Stats screen; read the layer; then tap the card's dismiss control.
- **Flow:** one evaluation; then the framework's dismissal write.
- **Expected outcome:** the layer shows the caution card with S-2005's exact observation and
  suggestion, the `Worth a look` kind label, the widget key `signal_card_cross-modality-interference`,
  and no quiet line; it sits below the Mix layer; the ALL TIME, Instruments and Fuel blocks are
  unchanged. After one tap the card is gone in the next frame, the quiet line appears, and the
  dismissal store holds `cross-modality-interference` with an integer timestamp; a fresh screen build
  keeps it hidden.
- **Edge case of:** none. **Mock only for the tap** — a Hive write inside `FakeAsync` never drains.

### S-2014: the framework and the PR path are untouched
- **Fixture:** the repository at the Phase 3 tip.
- **Trigger:** `git diff --name-only` against the PR base, and the full suite.
- **Flow:** the residue sweep in Phase 3.
- **Expected outcome:** `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart`,
  `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/widgets/signals/*`,
  `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` show no diff;
  `test/signals_framework_test.dart`, `test/signals_service_test.dart`,
  `test/signals_layer_screen_test.dart`, `test/in_session_pr_toast_test.dart` and
  `test/pr_toast_test.dart` pass unmodified.
- **Edge case of:** none.

### S-2015: the 90-day hard window's bounds
- **Fixture:** F-2001's list with the 8th sports session moved to exactly `now − 90 days`; then the
  same list with that session moved to `now − 90 days − 1 ms`.
- **Trigger:** one call per variant.
- **Flow:** D-1302's inclusive bounds.
- **Expected outcome:** at exactly `now − 90 days` the session is in the population (8 rated sessions)
  and the card fires; 1 ms earlier it is out (7 rated sessions) → null.
- **Edge case of:** S-2005.

## Iteration 1

### Executor block (applies to every phase in this plan)

- **Branch:** work on `develop`. Never create a branch, never commit — the owner commits.
- **Shell:** every command goes through the gateway, spelled in full:
  `.github/copilot/scripts/macos/gateway.sh <list|lint|test [paths]|format <paths>|pub-get|build|codegen|git-status|git-diff|git-log|git-show>`.
  The bare form is denied. No `git`, `grep`, `sed`, `awk` or `wc` in a shell — use the gateway's
  `git-*` verbs and your file tools. A denied command is never retried.
- **Red first:** every phase writes its tests before the code they test, runs them, and records the
  failing output in `<this plan>.evidence.md`. A test that has never failed proves nothing.
- **Mutations:** at least two inverse edits per plan, on files that already exist at that point. Apply
  one, run the named test, record the failure, restore the file, re-run to confirm green, and *never
  end a step with a mutation applied*.
- **Step budget:** at most 8–10 steps per run. Read at most ~100 lines of a large file at a time —
  `lib/core/services/stats_progress_service.dart` is 2,247 lines; find a region by searching for its
  symbol, then read that region.
- **Evidence:** baselines, suite summaries, red→green tables and the mutation pairs go to
  `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.evidence.md`.
  Never into this plan. Findings go to `...review.md`.
- **Ambiguity:** never stop. Pick the option most consistent with the Ledger and the Feature
  Invariants, log it in the Assumption Log (decision, options considered, rationale) and continue.
- **Docs trail code by zero phases:** each phase updates the docs it invalidated.
- **Baseline for this plan (measured on `develop`):** `flutter analyze` → `196 issues found.` with 0
  errors; `flutter test` → `+3548 ~1: All tests passed!`. Re-measure at Phase 1 and use your own
  numbers if 7a has landed since.

### Phase 1: the pure rule and the copy (@dba)

1. [ ] Write `test/interference_test.dart` (plain `test()`, no widget, no repository): S-2003, S-2004,
   S-2006, S-2007, S-2008, S-2009's pure half, S-2010, S-2015, plus the abstention cases (no sessions;
   fewer than 8 rated sports sessions; no hard session; a hard session with no follow-up; a hard
   session whose follow-up starts outside the 45-day window). Build S-2001's and F-2001's session lists
   as shared helpers in the file. Run it and record the failure.
2. [ ] Create `lib/core/models/interference.dart` (D-1301…D-1314): the constants
   `kInterferenceHardWindowDays = 90`, `kInterferenceMinRatedSportsSessions = 8`,
   `kInterferenceHardPercentile = 0.75`, `kInterferenceFollowUpHours = 36`,
   `kInterferenceDipWindowDays = 28`, `kInterferenceMinDip = 0.10`,
   `kInterferencePatternWindowDays = 45`, `kInterferenceMinDippedFollowUps = 3`,
   `kInterferenceSportsLoadWindowDays = 21`, `kInterferenceSportsLoadRisePercent = 30`,
   `kCrossModalityInterferencePriority = 500`; `InterferenceSession`; the result type carrying `k`,
   `n`, `lo`, `hi` and whether the second sentence applies; the rule; the copy builder. No Flutter, no
   repository, no clock, no service.
3. [ ] Re-run step 1's suite to green, including S-2001's exact observation string.
4. [ ] Mutations, one at a time, each restored: **(a)** D-1304's `<= endMs + 36 h` → `< endMs + 36 h` —
   S-2003(b) must fail; **(b)** D-1308's `>= kInterferenceMinDip − 1e-9` → `> kInterferenceMinDip` —
   S-2004(a) must fail. Record both red→green pairs in the evidence file.
5. [ ] Docs: add the `interference` constant group to `docs/constants_reference.md` (names and values
   only, no restatement of the rule); confirm `docs/signals.md` carries the caution order from 7a's
   D-1214 and add it only if 7a has not landed. Every behaviour sentence names its test.

**Done Criteria** (run until green):
`flutter analyze` (expect `196 issues found.`, 0 errors);
`flutter test test/interference_test.dart`;
full `flutter test` with its summary line pasted into the evidence file.

**Predicted Files:** `lib/core/models/interference.dart` (NEW); `test/interference_test.dart` (NEW);
`docs/constants_reference.md` (EDIT); `docs/signals.md` (EDIT — only if 7a has not landed).

**Phase 1 verification notes (Conductor, date):** _(added at verification)_

### Phase 2: the walk and the shared split (@dba)

1. [ ] Write `test/interference_sessions_service_test.dart` (plain `test()`) against
   `test/helpers/repository_harness.dart` on both factories, with a local rated-session seeder:
   F-INT's per-session payloads, S-2012's parity sum, S-2009's service half (an unrated sports session
   reports zero Sports load), S-2005(b)'s 7-session population, S-2011's 10% and 11% shortfalls, and
   the walk's ordering (by `startMs`, ties by id). Run it and record the failure.
2. [ ] In `lib/core/services/stats_progress_service.dart`, find `computeMixLayer` by searching for
   `Future<MixLayerData?> computeMixLayer`, read that region, and lift its per-session time and load
   split into a private helper both the Mix walk and the new walk call (D-1317). Nothing about the
   layer's measure, segments, percents, counts or strip changes.
3. [ ] Add `interferenceSessions()` (D-1316) to the same file: one pass over the cached history index,
   the existing native-value rule and axis classification for the per-exercise bests, the shared split
   for the Sports load, and the set-effort flag through the shared kind→section rule.
4. [ ] Re-run step 1's suite to green, then the Mix suites:
   `flutter test test/mix_layer_service_test.dart test/mix_layer_screen_test.dart`.
5. [ ] Mutation: replace the Sports component of the shared split with the session's whole load —
   S-2012's parity assertion must fail. Restore and re-run.
6. [ ] Docs: add `interferenceSessions` to `docs/state_management/services_and_utils.md`'s
   `StatsProgressService` entry, and note the shared split in `docs/training_load.md`'s entry-point
   section. Every behaviour sentence names its test.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/interference_sessions_service_test.dart test/mix_layer_service_test.dart test/mix_layer_screen_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/stats_progress_service.dart` (EDIT — the split extraction and
the new method, nothing else); `test/interference_sessions_service_test.dart` (NEW);
`docs/state_management/services_and_utils.md`, `docs/training_load.md` (EDIT).

**Phase 2 verification notes (Conductor, date):** _(added at verification)_

### Phase 3: the signal, the card, the guards and the close (@developer)

1. [ ] Write `test/interference_signal_screen_test.dart` first, asserting the exact observation and
   suggestion strings, the `Worth a look` label, the widget key and the position of S-2013, and the
   dismissal. Run it and record the failure (the card is absent — the registry has no such signal yet).
2. [ ] Create `lib/core/services/signals/interference_signal.dart` (D-1315, D-1318, D-1320): id
   `cross-modality-interference`, kind caution, priority `kCrossModalityInterferencePriority`;
   `evaluate` asks `context.progressService.interferenceSessions()`, hands the list and `context.now`
   to the rule, and returns the card or null. It reads no repository, walks no history and calls no PR
   API.
3. [ ] Add one line to `buildSignalRegistry()` so the registry holds Progression Rate, Modality Mix
   Shift and Interference. Nothing else in the framework changes.
4. [ ] Re-run the new suite to green, then the framework and surface suites:
   `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/modality_mix_shift_signal_screen_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/screen_widget_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart`.
   A failure in `test/mix_layer_screen_test.dart`, `test/progression_rate_signal_screen_test.dart` or
   `test/modality_mix_shift_signal_screen_test.dart` is a surface-height re-stabilisation; a failure
   anywhere else is a real finding.
5. [ ] Confirm the PR path is untouched:
   `flutter test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` — with no edit to those
   files.
6. [ ] Guards, each a permanent test: (a) the caution order holds and the registry's caution
   priorities are distinct — `kCrossModalityInterferencePriority > kModalityMixShiftPriority`; (b) the
   hard rule counts no unrated session (S-2009's fixture); (c) the dip test tolerates representation
   error and nothing more (S-2004's fixture); (d) the signal walks no history and calls no PR API; (e)
   the framework files are unchanged (S-2014).
7. [ ] Residue sweep: search `lib/`, `test/` and `docs/` for every name this PR introduces —
   `InterferenceSignal`, `cross-modality-interference`, `interferenceSessions`, `InterferenceSession`,
   `crossModalityInterference`, every `kInterference*` constant, `kCrossModalityInterferencePriority`,
   and the observation's opening words. List every hit's file in the evidence file; confirm the
   framework files and `watch/` are absent. Confirm the untouched files show no diff.
8. [ ] Docs: add Interference to `docs/stats_screen.md`'s Signals section; add its paragraph to
   `docs/signals.md`'s registered-signals section — the hard rule and its 8-session floor, the 36-hour
   follow-up, the per-exercise dip and its 28-day average, the 45-day pattern, the optional sentence
   and the copy — with every behaviour sentence naming a test.
9. [ ] Full `flutter test`; paste the summary line and compare it with Phase 2's, explaining every
   delta. Re-read both docs against the shipped code and correct any claim that no longer matches;
   confirm the shipped copy and the documented copy match character for character, and that both files
   are under the 64 KiB ceiling. Close the Progress table and the Assumption Log and fill the evidence
   file's final table.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/interference_test.dart test/interference_sessions_service_test.dart test/interference_signal_screen_test.dart test/signals_framework_test.dart test/docs_indexing_contract_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/signals/interference_signal.dart` (NEW);
`lib/core/services/signals/signal_registry.dart` (EDIT — one line);
`test/interference_signal_screen_test.dart` (NEW); `test/interference_test.dart`,
`test/interference_sessions_service_test.dart` (EDIT — the guards); `docs/signals.md`,
`docs/stats_screen.md` (EDIT);
`test/mix_layer_screen_test.dart`, `test/progression_rate_signal_screen_test.dart`,
`test/modality_mix_shift_signal_screen_test.dart` (EDIT — surface heights only, if step 4 needs it).

**Phase 3 verification notes (Conductor, date):** _(added at verification)_

## Governor actions

- **@dba owns Phases 1–2.** The pure model, the copy, the shared split and the walk.
- **@developer owns Phase 3.** The signal, the registry line, the card's tests, the guards and the
  close.
- If Phase 2's extraction changes any existing Mix test's expected value, stop: D-1317 is a
  behaviour-preserving extraction, so a changed expectation is a defect in the extraction, not a test
  to update.
- If Phase 3 needs a `SignalContext` member or a framework file edit, stop: D-1318 says the seam is
  wrong.
- The owner commits. No agent commits, branches or pushes.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/interference.dart` | NEW — constants, `InterferenceSession`, rule, copy |
| `lib/core/services/stats_progress_service.dart` | EDIT — the shared split, `interferenceSessions()` |
| `lib/core/services/signals/interference_signal.dart` | NEW — the signal |
| `lib/core/services/signals/signal_registry.dart` | EDIT — one registry line |
| `test/interference_test.dart` | NEW — the pure rule, the copy, the guards |
| `test/interference_sessions_service_test.dart` | NEW — the walk, the parity, the exclusion |
| `test/interference_signal_screen_test.dart` | NEW — the card and the dismissal |
| `test/mix_layer_screen_test.dart`, `test/progression_rate_signal_screen_test.dart`, `test/modality_mix_shift_signal_screen_test.dart` | EDIT — surface heights only, if needed |
| `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/training_load.md`, `docs/state_management/services_and_utils.md` | EDIT — the new rule, walk and constants |

Nothing in `lib/data/`, `scripts/`, `watch/` or `lib/features/` outside the Stats screen's existing
Signals layer.

## Notes

- **Dependency graph:** Phase 1 → Phase 2 → Phase 3, strictly. Phase 2's walk needs Phase 1's
  `InterferenceSession` type; Phase 3's signal needs both. There is no useful reordering, and Phase 2
  cannot start before Phase 1 because the test file it red-runs constructs `InterferenceSession`
  values.
- **Cross-PR dependency:** 7a must land first. This plan's priority constant is defined *relative to*
  7a's (`500 > 400`), and 7a owns the caution-order paragraph in `docs/signals.md` that Phase 3 step 8
  extends.
- **Predicted intermediate states:** after Phase 1 the repository has a rule, a copy builder and a
  session value type that nothing produces; the Stats screen is unchanged and the full suite is green.
  After Phase 2 the service can hand out sessions but no signal reads them; still green. After Phase 3
  the card can appear; the only pre-existing suites that may need a height adjustment are the three
  screen suites named in Phase 3 step 4.
- **Legacy handling:** none. No field, schema or stored value changes; a dismissal rides the existing
  preference API, which both repository implementations already implement.
- **Fixture reuse:** F-2001 is Phase 1's pure list and is reused by S-2001, S-2002, S-2007, S-2008,
  S-2009 and S-2010; F-INT is Phase 2's seeded fixture and is reused by S-2005, S-2009, S-2011, S-2012
  and S-2013.
- **Two fixtures, one rule:** the pure fixtures carry hand-picked native values (100.0, 84.0) so the
  boundary cases are exact; F-INT carries real `weight × (1 + reps/30)` arithmetic (103.3333…) so the
  service path is exercised by the same rule. Both must agree on the same rule, not on the same
  numbers.

## Open questions

| # | Item | Owner | Status |
|---|---|---|---|
| O-1 | D-1301's definition of a sports session and the load it is ranked by (the Sports component of the split, not the whole session load) | Owner | Defaulted — **owner to confirm**; vetoable |
| O-2 | D-1312's single-number collapse when `lo == hi` | Owner | Defaulted — **owner to confirm**; vetoable |
| O-3 | D-1313's second sentence carries no explicit span on its own — the enclosing period is the 21-day comparison | Owner | Defaulted — **owner to confirm**; vetoable |
| O-4 | D-1315's priority 500 as the top of the caution order | Owner | Defaulted — **owner to confirm**; matches 7a's D-1214 |

## Progress

| Item | Status | Evidence |
|---|---|---|
| Plan lines re-measured | pending | — |
| Phase 1 | not started | — |
| Phase 2 | not started | — |
| Phase 3 | not started | — |

## Assumption Log

_Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED (promoted to a D-x) or REVERT (remediation)._

## Feedback

[empty — the Conductor folds non-empty entries into a new Iteration block and clears this one]
