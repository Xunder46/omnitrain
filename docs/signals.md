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
