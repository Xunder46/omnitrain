# Plan 157c — Sustained High Load stops counting unrated weeks as zero load

Series: `docs/plans/2026-11-13-157-stats-what-counts-series.md` (third PR). Source: item 10, second half, of the Stats pre-launch review (memory `stats-prelaunch-review-2026-11-12`); owner accepted the recommendation on 2026-11-13. Phone only (`lib/core`), one track, one builder run.

## Goal and acceptance

The "Sustained high load" caution compares each recent week with the user's usual, the twelve weeks before it. A session's load needs an effort rating: an unrated session has load 0 (`_sessionSplit`: "zero throughout when the session is unrated"). So a week in which the user trained but did not rate the workouts reads as a week of zero load, and the usual is the twelve weeks' sum divided by twelve. A user who starts rating more of their workouts therefore sees their usual jump up from a baseline that was understated, and the card can fire although nothing about their training changed (review item 10; read in code, not run).

After this change a week that held sessions but no rated one is an UNRATED week: its load is unknown, not zero. It is left out of the baseline (the usual divides by twelve less the unrated weeks) and is not counted as an easier week in the history fact. A week with no session at all still counts as zero (D-1705: a rest week is real information). The streak itself is unchanged: an unrated week has load 0 and so cannot be part of a higher-load run.

Acceptance: S-15901..S-15906 green, the ones marked "fails without" red at the base commit; the existing Sustained High Load and training-load tests stay green unedited; `flutter analyze` not above 181 (0 errors); full suite no new red.

## What the user sees

- Before: rate only your recent workouts, keep training exactly as before, and "You've had 5 consecutive weeks above your usual training load" can appear because your earlier, unrated weeks counted as nothing.
- After: the earlier unrated weeks are left out of your usual, so the same steady training no longer reads as an increase. Weeks you really skipped still count as easy weeks.
- Not changed: the 8-of-12 rated-weeks floor, the 110% / 80% thresholds, the five-week streak, the card's wording.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `WeeklyLoad` (`lib/core/models/training_load.dart:76`) gains `final bool hasSessions` (constructor `this.hasSessions = false`, so every existing construction keeps meaning "a week with no session") and `bool get isUnrated => hasSessions && !hasRatedSession`. | review item 10 |
| D-2 | `StatsProgressService.weeklyLoads` (`stats_progress_service.dart:603`) sets `hasSessions` for every week a completed session starts in, beside the existing `ratedWeekStartsMs` set. Empty weeks stay `hasSessions: false`. | `weeklyLoads` loop |
| D-3 | `sustainedHighLoadBaseline` (`lib/core/models/sustained_high_load.dart:112`) divides the pooled load by `kTrainingLoadBaselineWeeks` minus the number of `isUnrated` weeks in the window (an all-unrated window, divisor 0, yields usual 0.0; the 8-rated-weeks floor rejects it anyway). `ratedWeeks` is counted as before. | D-1705 (empty week counts zero) kept |
| D-4 | `sustainedHighLoadEasierGapWeeks` (same file, line ~203) skips an `isUnrated` week: unknown is not easier. An empty week is still an easier week. | doc "an empty week is an easier week" |
| D-5 | The streak test (`sustainedHighLoadHigherWeek`) is untouched: an unrated week has load 0, is never higher, and so breaks any run it sits in (conservative: unknown never fires the card). | S-15905 |
| D-6 | No migration, no change to the Mix layer, `computeMixPeriod`, the rated-weeks floor of the Mix measure, or any other signal. | scope |

## Scenarios

Pure-Dart scenarios use a week helper `_week(i, load, {rated, sessions})` (week i starts `DateTime(2026, 1, 5 + 7 * i)`); numbers were re-derived with a mirror script of the old and new rule.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-15901 | Twelve baseline weeks: 8 rated weeks at load 100, 2 unrated weeks that held sessions (load 0), 2 empty weeks (load 0); `sustainedHighLoadBaseline(weeks, beforeIndex: 12)` over a 13-week list. | `usualLoadMinutes` is 80.0 (800 / (12 - 2)) and `ratedWeeks` is 8. | the usual reads 66.67 (800 / 12) |
| S-15902 | Twelve weeks: 10 rated at 100 and 2 empty weeks (no sessions). | `usualLoadMinutes` is 83.333... (1000 / 12): empty weeks still count as zero. | passes with and without the change on purpose: guards the empty week against being treated as unrated (mutation: `isUnrated` ignores `hasSessions`) |
| S-15903 | The user starts rating late: 17 weeks, weeks 0-3 unrated with sessions (load 0), weeks 4-11 rated at 100, weeks 12-16 rated at 100 (the same training throughout). `sustainedHighLoad(weeks: ..., mixShowsLoad: true)`. | null (no streak: usual 100 against a 110% bar). | the old usual is 66.67, five weeks of 100 qualify, the card fires |
| S-15904 | 20 rated weeks at 100 except weeks 2, 5 and 8 which held only unrated sessions; `sustainedHighLoadEasierGapWeeks(weeks, beforeIndex: 12, usual: 100)`. | null: unrated weeks are not easier weeks. | they read as easier weeks 3 apart and the fact reports a 3-week habit |
| S-15905 | 12 rated weeks at 100, then five weeks at 200 where the third is unrated with sessions (load 0). `sustainedHighLoadStreak` and `sustainedHighLoad(... mixShowsLoad: true)`. | `weekCount` is at most 2 and the rule returns null. | passes with and without the change on purpose: pins D-5, an unrated week breaks a run (mutation: skip unrated weeks inside the streak test) |
| S-15906 | Service, Mock and Hive (harness): ended sessions in three consecutive weeks: week A one rated session, week B one unrated session, week C none, then a fourth week holding a rated session so C lies between; `StatsProgressService(repo).weeklyLoads(now: <a day after the fourth week>)`. | A: `hasSessions` true, `hasRatedSession` true; B: `hasSessions` true, `hasRatedSession` false, `isUnrated` true; C: both false, `isUnrated` false. | `hasSessions` does not exist (the field is always false: B reads as an empty week) |
| S-15902b | Twelve unrated weeks (sessions, no rating) and a thirteenth; `sustainedHighLoadBaseline(beforeIndex: 12)`. | `usualLoadMinutes` is 0.0 (not NaN) and `ratedWeeks` is 0. | passes with and without the divisor change by arithmetic; added after the mutation pass so a divisor guard cannot be dropped (mutation h) |

## Input-reality checklist

1. Writers: `session.sessionFeeling` is written by the post-workout rating sheet, the Session Summary's EFFORT row and the watch (rating first answer wins); it is null for a workout never rated, or when the Effort Rating prompt is switched off (`docs/theme_and_settings.md`). Weeks are bucketed by the session's own start in the saved start-of-week setting (`OmniDateUtils.startOfWeek`).
2. Lifecycle: only ended sessions count; a session the user rates later turns its week from unrated to rated and the usual updates on the next load; a rolling or imported session counts like any ended one.
3. Settings: the Effort Rating toggle off means every week is unrated, no baseline reaches 8 rated weeks and the card never shows (unchanged: this change only affects users who have both rated and unrated weeks). The start-of-week setting moves week boundaries and the unrated classification with them.
4. Time: the week containing `now` is never returned (unchanged); a week is decided by its sessions' start times, not their end.
5. Cost: `weeklyLoads` already walks every ended session once; one more `Set<int>` add per session.
6. Words: the docs that state the old divisor are in the Docs delta; the card's wording does not change.
7. Competition: this signal's eligibility is unchanged.

## Phases

1. **One builder run** (`crew-builder-app`, no architect): (1) `WeeklyLoad` gains `hasSessions` and `isUnrated` (doc comment updated); (2) `weeklyLoads` sets `hasSessions`; (3) `sustainedHighLoadBaseline` divisor and its doc comment; (4) `sustainedHighLoadEasierGapWeeks` skip and its doc comment; (5) new `test/sustained_high_load_unrated_weeks_test.dart` with S-15901..S-15906. Done: the new file green (service group on Mock and Hive); the readers below green; no full suite.
2. **Docs** (`crew-docs-keeper`), then the lead's full suite, mutation pass and `crew-reviewer`.

Exact production code.

`training_load.dart`, replace the `WeeklyLoad` doc comment's last sentence and the class:

```dart
/// One completed calendar week's load (D-1702).
///
/// [weekStart] is the local-midnight first day of the week. [loadMinutes] is
/// the week's summed [sessionLoadMinutes] — the same load definition the Mix
/// layer uses, so the weekly figure is shared and never re-derived. A session
/// counts in the week its own start falls in. [hasRatedSession] is true when a
/// completed rated session starts in the week. [hasSessions] is true when any
/// completed session starts in the week (plan 157c). A week with no work is
/// present with `loadMinutes: 0`, `hasRatedSession: false` and
/// `hasSessions: false`, never dropped; a week that held sessions but no rated
/// one is [isUnrated]: its load is zero because load needs a rating, not
/// because the user rested.
class WeeklyLoad {
  final DateTime weekStart;
  final double loadMinutes;
  final bool hasRatedSession;
  final bool hasSessions;

  const WeeklyLoad({
    required this.weekStart,
    required this.loadMinutes,
    required this.hasRatedSession,
    this.hasSessions = false,
  });

  /// A week that held sessions but no rated one: its load is unknown, not zero.
  bool get isUnrated => hasSessions && !hasRatedSession;
}
```

`weeklyLoads` in `stats_progress_service.dart`: next to `final ratedWeekStartsMs = <int>{};` add `final sessionWeekStartsMs = <int>{};`; in the session loop, next to `if (session.sessionFeeling != null) ratedWeekStartsMs.add(weekStartMs);` add `sessionWeekStartsMs.add(weekStartMs);`; in the `WeeklyLoad(` construction add `hasSessions: sessionWeekStartsMs.contains(weekStartMs),` after `hasRatedSession: ...`.

`sustained_high_load.dart`: baseline (replace the function body and its doc comment's second paragraph):

```dart
/// One candidate's baseline: the [kTrainingLoadBaselineWeeks] weeks immediately
/// before [beforeIndex], pooled (D-1705).
///
/// The baseline lies strictly before the candidate, so a run can never inflate
/// its own baseline. The usual is the pooled load divided by the twelve weeks
/// less the unrated ones (plan 157c): an empty week counts as zero, never the
/// mean of the rated weeks only, but a week that held sessions and no rating
/// has an unknown load and is left out of the divisor. Returns null when fewer
/// than twelve weeks precede [beforeIndex].
SustainedHighLoadBaseline? sustainedHighLoadBaseline({
  required List<WeeklyLoad> weeks,
  required int beforeIndex,
}) {
  if (beforeIndex < kTrainingLoadBaselineWeeks) return null;
  var total = 0.0;
  var rated = 0;
  var unrated = 0;
  for (var i = beforeIndex - kTrainingLoadBaselineWeeks; i < beforeIndex; i++) {
    total += weeks[i].loadMinutes;
    if (weeks[i].hasRatedSession) rated++;
    if (weeks[i].isUnrated) unrated++;
  }
  final counted = kTrainingLoadBaselineWeeks - unrated;
  return SustainedHighLoadBaseline(
    usualLoadMinutes: counted > 0 ? total / counted : 0.0,
    ratedWeeks: rated,
  );
}
```

and the `SustainedHighLoadBaseline.usualLoadMinutes` doc comment becomes `The baseline's usual: its summed load ÷ the twelve weeks less the unrated ones, an empty week counting as zero.` In `sustainedHighLoadEasierGapWeeks`, first statement of the loop body: `if (weeks[i].isUnrated) continue;`; its doc comment gains `A week that held only unrated sessions is neither easier nor harder: it is skipped.`

## Readers (existing tests that must stay green unedited)

`test/sustained_high_load_test.dart` (its `_weeks` helper builds weeks without `hasSessions`, so every one is an empty-or-rated week: unchanged by the default), `test/sustained_high_load_service_test.dart`, `test/sustained_high_load_signal_screen_test.dart`, `test/training_load_test.dart`, `test/signals_service_test.dart` and any test naming `sustained-high-load` (`grep -rln "sustained-high-load\|SustainedHighLoad" test`). A red there is reported, not edited.

## Mutation list (lead)

(a) `counted` divisor replaced by `kTrainingLoadBaselineWeeks`; (b) `if (weeks[i].isUnrated) unrated++;` removed; (c) `isUnrated` returns `!hasRatedSession` (empty weeks count as unrated); (d) `isUnrated` returns `hasSessions`; (e) the easier-gap skip removed; (f) `hasSessions: sessionWeekStartsMs.contains(weekStartMs)` replaced by `hasSessions: false`; (g) `sessionWeekStartsMs.add(weekStartMs)` removed; (h) divisor guard `counted > 0` removed (an all-unrated window must not throw or return NaN); (i) streak test changed to skip unrated weeks.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/training_load.md` | MODIFIED | the twelve weeks, an empty week counting as zero. | the twelve weeks less any week that held only unrated sessions, an empty week counting as zero. | S-15901, D-3 |
| `docs/signals_registered.md` | MODIFIED | summed load divided by the twelve weeks — an empty week counts as zero, never | summed load divided by the twelve weeks less the weeks that held only unrated sessions — an empty week counts as zero. | S-15901, D-3 |
| `docs/signals_registered.md` | MODIFIED | counts as an easier week. The fact reports the median gap between the easier | counts as an easier week, while a week that held only unrated sessions is neither. The fact reports the median gap between the easier | S-15904, D-4 |
| `docs/state_management/services_and_utils.md` | ADDED | - | Each entry also says whether the week held any session | S-15906, D-2 |

Stale-term sweep run (`grep -rIn "empty week\|÷ twelve\|counting as zero\|counts as zero" docs`, minus plans/history/releases): the hits above; `docs/training_load.md:174` and `services_and_utils.md:531` describe the series and stay true.

## Open items

1. A week with both rated and unrated sessions still counts as a rated week whose unrated sessions add zero load, so a user who rates only half of each week's sessions still gets a low-biased usual (review minor 2; whole-week scope was deliberate, D-6). Planned as a follow-up only if the owner wants it.

No other owner question. Recorded: with the Effort Rating prompt off nothing changes (no rated weeks, the card cannot show). `docs/signals_registered.md` is at 49,674 bytes (the 80% band starts at 52,428): this unit adds under 400 bytes there; split it before a unit that adds more.

## Predicted files

`lib/core/models/training_load.dart` (+14), `lib/core/models/sustained_high_load.dart` (+12), `lib/core/services/stats_progress_service.dart` (+4), new `test/sustained_high_load_unrated_weeks_test.dart`, three docs.

## Progress

- [x] Phase 1 build: 9 tests (S-15906 on Mock and Hive) green
- [x] Phase 2 docs: four rows applied, `plan-lint after` clean
- [x] Lead verification: analyze 181 (baseline, 0 errors); full suite 7574 passed, 5 skipped, 0 failed
- [x] Mutation pass: 9 of 9 killed (two after tests-only additions)
- [x] Review: APPROVE WITH FIXES, 0 blocker, 1 major (a stale contrast clause in a code comment and one doc, fixed), 1 minor (recorded in Open items)
- [ ] (owner) Device check: needs weeks of history; see it with the Stats gallery (`test/stats_gallery_render_test.dart`) rather than waiting

## Assumption Log

- 2026-11-14: base commit `cd117f79`; branch `claude_develop`; 157a and 157b are uncommitted in the same tree; this plan's scopes are disjoint from theirs except `lib/core/services/stats_progress_service.dart`, which 157b also edits (different method: `weeklyLoads`).
- 2026-11-14: fixtures derived with a mirror script of the old and new rule: S-15903 streak old 5 / new 0; S-15901 usual 66.67 / 80.0; S-15904 gap old 3 / new null; S-15905 streak 2 under both.

## Feedback

(none yet)
- 2026-11-14: lead edit (tests only): `test/cardio_efficiency_drift_signal_screen_test.dart` `_seedFTwo` (S-2511) seeds a rated zero-minute session in F-9A's two quiet weeks, because its unrated cardio sessions can land in them and would now make those weeks unrated (usual 200 becomes 218 or 240 and the 230-load streak no longer clears 110%). Same assertions; all weekday variants green.
