# Signals — Framework, Selection and the Dismissal Store

**Scope.** The pure Signals framework and the service that drives it:
`lib/core/models/signals.dart`, `lib/core/services/signals/signal.dart`,
`lib/core/services/signals/signal_registry.dart` and
`lib/core/services/signals_service.dart`. It does not cover the Stats screen or
any widget that draws a signal; that surface belongs to
[Stats Screen](stats_screen.md).

---

## What a signal is

A signal is a named rule that reads one Stats load and either proposes a
**card** — one observation about the training that load covers — or abstains. A
card is a proposal, not a decision: what a user is shown is decided by the gate,
the selection rule and the dismissal store below.

**Why the framework is pure.** The card, the kind, the selection, the gate and
the dismissal arithmetic live in `lib/core/models/signals.dart` as pure Dart: no
Flutter import, no repository, no service and no clock of its own — every
function that needs "now" takes it as a parameter. Selection and the day maths
are therefore testable without a widget or a store. Verified by
`test/signals_framework_test.dart`.

## The two kinds

Two kinds exist: `positive` and `caution`. Their vocabulary is `Positive` and
`Worth a look`, resolved by `signalKindLabel`. A kind is carried by the label
and the icon, never by a colour, and signals add no `OmniTheme` token. Verified
by `test/signals_framework_test.dart` (`D-1001 / D-1002 the kind vocabulary`).

## The gate

Signals are evaluated only when `signalsGateMet(mix)` is true, which reads the
load's rated-baseline weeks and `kTrainingLoadMinRatedWeeks` only — it does not
additionally require a load measure. When the gate is unmet the service
evaluates no signal at all and returns no candidates, so a user without a rated
baseline pays nothing for the framework. Verified by
`test/signals_framework_test.dart` (`D-1006 the quiet-line gate`) and
`test/signals_service_test.dart` (`S-1702 an unmet gate returns nothing and
evaluates nothing`).

## Selection and the card cap

One load yields at most `kSignalMaxCards` cards; `resolveSignals` is the single
entry point that applies the dismissal filter and this selection rule. When both kinds survive the
dismissal filter, the result is the highest-priority caution followed by the
highest-priority positive; when only one kind survives, it is the top
`kSignalMaxCards` of that kind. Within a kind, higher priority wins and an exact
tie is broken by the signal's id in ascending order, so selection is
deterministic. Priorities are comparable only within a kind — a caution and a
positive never compete. Verified by `test/signals_framework_test.dart`
(`S-1704`–`S-1708`, `D-1004 at most two cards`, `D-1005 priority order within a
kind`).

**Rationale.** The cap exists because the two kinds are different
conversations: "this is working" and "this is worth a look". A second card of a
kind adds nothing the first did not say, and the cap also bounds how much of the
Stats body a signal can displace.

**The caution order.** Within a kind, a signal's place in the order is carried
by its own `k…Priority` constant rather than by the selection rule, so the order
is a property of the signals. The only caution registered today is Modality Mix
Shift, whose priority is `kModalityMixShiftPriority`; the registered positive is
Progression Rate, whose priority is `kProgressionRatePriority`. Verified by
`test/modality_mix_shift_test.dart` (the constant contracts) for the Modality
Mix Shift entry.

## Abstention

A signal returns null when its own data-sufficiency conditions are unmet. An
abstaining signal contributes nothing — not a card, not an exception to the
quiet line — and is indistinguishable from a signal that is not registered.
Verified by `test/signals_framework_test.dart` (`S-1708 an abstaining signal is
invisible`) and `test/signals_service_test.dart` (`S-1708 an abstaining signal
adds nothing and suppresses nothing`).

## The quiet line

When the gate is met and no card qualifies, the framework reports the quiet-line
state instead of cards: `kSignalQuietLine` is the sentence and the caller draws
it without a card. A gate-unmet load reports neither cards nor the quiet line,
so a caller can tell "nothing to say" from "not yet speaking". Verified by
`test/signals_framework_test.dart` (`S-1703 gate met, nothing qualifies`).

## The dismissal store

Dismissals persist through the `WorkoutRepository` preference API under the key
`kSignalDismissalsKey`, whose value is a
JSON object mapping a signal id to the epoch-milliseconds integer at which it
was dismissed. `parseSignalDismissals` and `encodeSignalDismissals` are the
single serialization pair. A missing value, an unparseable value, a non-object
value and a non-integer entry all read as "no dismissal" and never throw, so a
corrupted preference cannot break a Stats load. Verified by
`test/signals_framework_test.dart` (`D-1009 the dismissal store parse`) and
`test/signals_service_test.dart` (`the store key is the pinned preference and
its value is a JSON object`).

Both repository implementations serve this API, so a dismissal written through
one reads back identically from the other. Verified by
`test/signals_service_test.dart` (`S-1712 Mock and Hive parity`).

**Dismissing moves the view first.** `signalDismissalsWith` is the pure write
rule: it returns the new store — the entries still hidden, plus the new
dismissal — without mutating the current map, so the caller can resolve its held
candidates against it and update the view in the tap's own frame. The write then
goes out through `persistDismissals`, which never throws, so a slow or failing
preference cannot hold a card on screen (D-1010). Verified by
`test/signals_framework_test.dart` (`D-1010 / D-1013 the dismissal write`),
`test/signals_layer_screen_test.dart` (`S-1709 dismissing removes the card at
once`) and, for the store write on both repositories,
`test/signals_service_test.dart` (`persistDismissals writes a map that reads
back value-for-value`).

## The dismissal window

`kSignalDismissalDays` hides a dismissed signal for a span of **local calendar
days**, with the dismissal day counted as day 1: hidden through
`kSignalDismissalDays` days, eligible again the day after. `isSignalDismissed`
is that single rule, and pruning uses it so the two boundaries cannot drift. The age is a whole
number of local calendar days, computed from the two dates re-read as UTC, so a
daylight-saving transition inside the window neither adds nor removes a day.
Verified by `test/signals_framework_test.dart` (`S-1710 the 14-day window`,
`S-1711 the daylight-saving boundary`).

Expired entries are pruned when a dismissal is written, so the store cannot grow
without bound; pruning never changes what is hidden. Verified by
`test/signals_service_test.dart` (`D-1013 a write prunes entries at 14 days and
keeps them at 13`).

**Rationale.** Days, not hours, because a user counts days — and because an
elapsed-hours count loses an hour across a spring-forward and expires a
dismissal a day early. The daylight-saving test is the assertion that fails when
the day count is replaced by a `Duration`-based one.

## The `Signal` contract

`buildSignalRegistry()` in `lib/core/services/signals/signal_registry.dart` is
the single registration point. The layer, the service and the screen never name
a concrete signal, so adding one is one line in one file.

`lib/core/services/signals/signal.dart` declares the contract: an id, a kind, a
priority and `evaluate`. `SignalContext` carries everything one evaluation may
read — the load's `now`, the resolved window, the resolved mix, the
`StatsProgressService` and the `WorkoutRepository` — so a signal added later
needs no change to the contract. Verified by `test/signals_service_test.dart`,
whose stub signals implement the contract and are driven through the service.

## Registered signals

`progressionRate({required samples, required now})` in
`lib/core/models/progression_rate.dart` is the Progression Rate signal's
definition. It counts **exercise-sessions**, not sessions: one exercise trained
five times inside a window contributes five counted entries, and an entry's value
is that exercise's own native metric — estimated 1RM on the weight axis, best reps
on the reps axis. Verified by `test/progression_samples_service_test.dart`
(`D-1101`).

- **The two windows.** The recent window is the `kProgressionRateWindowDays` days
  ending at `now`; the prior window is the same span immediately before it. A
  sample counts in the window its own session start falls in, so a session is
  never counted twice. Verified by `test/progression_rate_test.dart` (`D-1106`).
- **A progression** is a sample that matches or beats the exercise's previous
  sample, an exact tie included. The comparison is attributed to the later
  session, whose predecessor may sit outside both windows; each exercise's first
  sample has no predecessor and enters neither total. Verified by
  `test/progression_rate_test.dart` (`S-1806`, `D-1105`) and
  `test/progression_samples_service_test.dart` (`S-1808`).
- **The zero fallback is not a performance.** A sample whose value is not above
  zero is the native metric's fallback, so it moves neither count. Verified by
  `test/progression_rate_test.dart` (`D-1104`) and
  `test/progression_samples_service_test.dart` (`S-1810`).
- **Qualification.** The card needs `kProgressionRateMinCounted` counted
  exercise-sessions in each window, a recent rate of at least
  `kProgressionRateMinRate`, and an improvement of at least
  `kProgressionRateMinImprovement` over the prior rate. Every boundary is
  inclusive, and the rate and improvement tests are exact fractions on the counts
  rather than the two rounded percentages — a rate sitting exactly on a threshold
  still qualifies. Verified by `test/progression_rate_test.dart`
  (`S-1802`–`S-1805`, `D-1108`).
- **Kind and priority.** The kind is positive; the priority is
  `kProgressionRatePriority`, the highest among the positives the pack specifies.
  Verified by `test/progression_rate_test.dart` (`the registered signal declares
  the contract the docs describe`) and
  `test/progression_rate_signal_screen_test.dart` (`S-1801`).
- **Copy.** `progressionRateCopy` builds the card's observation from the two
  whole-number percentages and its suggestion, and `ProgressionRate.fromCounts` is
  the only place those percentages are derived, so the copy and the qualification
  test cannot disagree. Verified by `test/progression_rate_test.dart` (`D-1109`)
  and `test/progression_rate_signal_screen_test.dart` (`S-1801`).

The definition reads no clock, no repository and no service — `now` and the
samples are arguments. It becomes a card once `signal_registry.dart` lists it.
Verified by `test/progression_rate_test.dart` (`the structural guards`), which
scans both new files for a local 1RM formula and for a personal-record API call,
so the definition cannot drift back onto either.

`modalityMixShift({required measure, required recent, required baseline})` in
`lib/core/models/modality_mix_shift.dart` is the Modality Mix Shift signal's
definition, and `ModalityMixShiftSignal` in
`lib/core/services/signals/modality_mix_shift_signal.dart` is its adapter. The
signal reports a modality the user regularly trains whose share of their load
has fallen to less than half its usual share.

- **The period.** The recent period is the `kModalityMixShiftPeriodDays` local
  calendar days ending with today, built from calendar components rather than a
  `Duration` so a daylight-saving transition cannot shift a boundary. The period
  never follows the Stats window chip. Verified by
  `test/modality_mix_period_service_test.dart` (`S-1913`) and
  `test/modality_mix_shift_signal_screen_test.dart` (`S-1909 the period does not
  follow the window chip`).
- **The baseline.** The baseline is `baselineBlockStarts(localMidnightDay(fromMs))`
  — the `kTrainingLoadBaselineWeeks` consecutive 7-calendar-day blocks
  immediately before the period's start day, abutting it with no gap and no
  overlap. The signal defines no second baseline. Verified by
  `test/modality_mix_period_service_test.dart` (`S-1913`).
- **The measure gate.** The signal shows only when the period's own payload
  measures load: `ratedBaselineWeeks >= kTrainingLoadMinRatedWeeks` and the
  unrated time share at or below `kTrainingLoadMaxUnratedShare`, read exactly as
  the Mix layer reads them. Otherwise it abstains. Verified by
  `test/modality_mix_period_service_test.dart` (`S-1904a`) and
  `test/modality_mix_shift_signal_screen_test.dart` (`S-1904b`).
- **Regularly trained.** A modality is regularly trained when its baseline share
  is at least `kModalityMixShiftMinBaselineShare`, inclusive; a modality absent
  from the baseline bar is not. Verified by `test/modality_mix_shift_test.dart`
  (`S-1903`, `S-1906`).
- **Fires.** A regularly trained modality fires when its recent share is strictly
  less than half its baseline share. Exactly half does not fire, and the
  comparison is on exact fractions rather than the two rounded percentages. A
  modality absent from the recent bar reads zero and can still fire. Verified by
  `test/modality_mix_shift_test.dart` (`S-1902`, `S-1908`).
- **Which modality is reported.** Among the firing modalities the reported one
  has the largest relative drop; an exact tie resolves in `ExerciseSection`
  declaration order. Verified by `test/modality_mix_shift_test.dart` (`S-1905`,
  `S-1911`).
- **Kind and priority.** The kind is caution; the priority is
  `kModalityMixShiftPriority`, its place in the caution order above. Verified by
  `test/modality_mix_shift_test.dart` (the constant contracts) and
  `test/modality_mix_shift_signal_screen_test.dart` (`S-1909`).
- **Copy.** `modalityMixShiftCopy` builds the observation from the period's own
  rounded percentages and names the span ("over the last 4 weeks") because the
  period is fixed and not the window's. The second sentence is appended only when
  the largest recent share belongs to a modality other than the reported one.
  Every fired card also carries the suggestion `'<article> <noun> session this
  week would bring your mix back toward usual.'`, whose article and noun are the
  reported modality's, from `modalityMixShiftArticle` and
  `modalityMixShiftNoun`. Verified by `test/modality_mix_shift_test.dart`
  (`S-1901`, `S-1910`) and `test/modality_mix_shift_signal_screen_test.dart`
  (`S-1909`).

The definition reads no clock, no repository and no service — the measure and the
two segment lists are arguments. The adapter derives the period from
`context.now`, asks `StatsProgressService.computeMixPeriod` for that period's
payload and hands the payload's own segments to the rule, so it walks no history
of its own. Verified by `test/modality_mix_period_service_test.dart` (`S-1907`,
the period payload is the Mix layer's own figures).

`crossModalityInterference({required sessions, required now})` in
`lib/core/models/interference.dart` is the Cross-Modality Interference signal's
definition, and `InterferenceSignal` in
`lib/core/services/signals/interference_signal.dart` is its adapter. The signal
reports that the user's next lifting day after a hard sports session has come in
below their own usual level on the same lifts, at least
`kInterferenceMinDippedFollowUps` times in the pattern window.

- **A sports session and the load it is ranked by.** A session is a sports
  session when the shared load split attributes a positive measure to the Sports
  modality; the load it is ranked and summed by is that same Sports component in
  load minutes, never the session's whole load and never its raw duration.
  Verified by `test/interference_sessions_service_test.dart` (`S-2012`).
- **The hard window and its population.** The hard window is the exact
  `kInterferenceHardWindowDays`-day span ending at `now`, measured back from
  `now` as a duration, so a daylight-saving change can shift a boundary by at
  most an hour (D-1321). Both ends are inclusive. The population is the *rated*
  sports sessions in that window — a
  session with no rating has zero load and is never in it. Hard classification
  exists only when the population holds at least
  `kInterferenceMinRatedSportsSessions` sessions; below that the signal abstains.
  Verified by `test/interference_test.dart` (`S-2009`, `S-2015`, `fewer than 8
  rated sports sessions abstains`) and `test/interference_sessions_service_test.dart`
  (`S-2005(b)`).
- **Hard.** Sorting the population's Sports loads ascending, the threshold is
  `sorted[(kInterferenceHardPercentile × n).ceil() − 1]` — nearest-rank, so the
  share the percentile names is counted, not interpolated — and a session is
  hard when its load is at least the threshold, inclusive. Verified by
  `test/interference_test.dart` (`S-2008`).
- **The follow-up.** A hard session's follow-up is the session with the smallest
  start among those that hold at least one effort whose section maps to
  Resistance and start strictly after the hard session's end and at most
  `kInterferenceFollowUpHours` after it. A session starting exactly at the end is
  not a follow-up; one starting exactly at the bound is. Ties resolve by session
  id ascending, and the first qualifying session is the follow-up whatever it
  holds. A hard session with no such session contributes nothing. Verified by
  `test/interference_test.dart` (`S-2003`).
- **The comparable exercises and the prior average.** A follow-up's exercise is
  comparable when its best there is above zero under the shared native-value rule
  for the exercise's own axis and it has a qualifying prior session in
  `[followUpStart − kInterferenceDipWindowDays, followUpStart)` with a best above
  zero. The prior average is the mean of the exercise's per-session bests over
  those priors and excludes every follow-up this evaluation identified, so a
  follow-up never votes for its own baseline and never depresses another's.
  Verified by `test/interference_test.dart` (`S-2006`) and
  `test/interference_sessions_service_test.dart` (`S-2011`).
- **The dip.** A comparable exercise's shortfall is `(average − best) / average`.
  The follow-up dips when the *unweighted* mean of its comparable exercises'
  shortfalls is at least `kInterferenceMinDip` — one exercise, one vote, never
  weighted by volume, sets or load. The comparison tolerates floating-point
  representation error, so a shortfall that equals the threshold up to that
  error dips and one below it does not. A follow-up with no comparable exercise
  is excluded — it is not a dip and it is not counted anywhere. Verified by
  `test/interference_test.dart` (`S-2004`, `S-2006`).
- **The pattern.** The signal counts the dipped follow-up sessions whose start
  falls in `[now − kInterferencePatternWindowDays, now]`, both ends inclusive,
  and abstains unless that count reaches `kInterferenceMinDippedFollowUps`. Each
  follow-up session counts once however many hard sessions it follows. The
  reported `n` is the number of distinct follow-up sessions that are comparable
  and in the same window, so `n` is never below the count. Verified by
  `test/interference_test.dart` (`S-2002`, `S-2010`).
- **The range.** The reported range's ends are the smallest and largest of the
  counted follow-ups' mean shortfalls as whole percents; a dipped follow-up
  outside the window never widens it. Verified by `test/interference_test.dart`
  (`S-2010(b)`).
- **Kind and priority.** The kind is caution; the priority is
  `kCrossModalityInterferencePriority`, the top of the caution order. Verified by
  `test/interference_test.dart` (`the caution order holds and the registry is
  ordered by it`) and `test/interference_signal_screen_test.dart` (`S-2013`).
- **Copy.** `crossModalityInterferenceCopy` builds the observation from the
  rule's own counts and range, collapsing the range to a single number when its
  two ends are equal, and appends the second sentence only when the Sports load
  rose at least `kInterferenceSportsLoadRisePercent` over the
  `kInterferenceSportsLoadWindowDays` days ending at `now` against the span
  before it. Every fired card carries the suggestion `'A lighter or
  isometric-focused day after hard sports sessions is one option.'`. Verified by
  `test/interference_test.dart` (`S-2001`, `S-2007`) and
  `test/interference_signal_screen_test.dart` (`S-2013`).

The definition reads no clock, no repository and no service — `now` and the
session payloads are arguments. The adapter asks
`StatsProgressService.interferenceSessions` for the payloads and hands them and
`context.now` to the rule, so it walks no history of its own and calls no
personal-record API. Verified by `test/interference_test.dart` (`the adapter
walks no history and calls no PR API`) and
`test/interference_sessions_service_test.dart` (`D-1316`).

## One evaluation per load

A Stats load builds one `StatsProgressService` and one `SignalsService` over it.
`evaluateCandidates` reads the dismissal store once and evaluates each
registered signal once; a signal is never asked to walk history itself. Verified
by `test/signals_service_test.dart` (`S-1709 a dismissed id is filtered out of
the evaluated candidates`, which counts the evaluations).

---

## Related Documentation

- [Stats Screen](stats_screen.md) — the surface that renders a signal
- [Training Load & Mix](training_load.md) — `MixLayerData`, the gate's input
- [Data Models](data_models.md) — where the Signals value types sit
- [State Management & Services](state_management/services_and_utils.md) —
  `SignalsService` alongside the other services
