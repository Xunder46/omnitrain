# Signals — Framework, Selection and the Dismissal Store

**Scope.** The pure Signals framework, the service that drives it, and the
registered signals' definitions and adapters:
`lib/core/models/signals.dart`, `lib/core/services/signals/signal.dart`,
`lib/core/services/signals/signal_registry.dart`,
`lib/core/services/signals_service.dart`, the signal definitions
`lib/core/models/progression_rate.dart`,
`lib/core/models/modality_mix_shift.dart`, `lib/core/models/interference.dart`,
`lib/core/models/fuel_vs_load.dart`,
`lib/core/models/protein_consistency.dart`,
`lib/core/models/sustained_high_load.dart`,
`lib/core/models/cardio_efficiency_drift.dart`,
`lib/core/models/consistency.dart`,
`lib/core/models/hold_progress.dart`, and the adapters under
`lib/core/services/signals/`. It does not cover the Stats screen or
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

A signal declares whether it needs rated weeks: true when it reads the load
measure or the effort ratings, false when it reads neither and may speak from
the first session. Verified by `test/signals_service_test.dart` (group
`S-17503 which registered signals need rated weeks` › `only Progression Rate,
Protein Consistency and Cardio Efficiency Drift speak before the gate`).
`signalsGateMet(mix)` reads the load's rated weeks — how many of the last 12
seven-day weeks, current ones included, hold at least one completed session
with a rating — and `kTrainingLoadMinRatedWeeks` only — it does not
additionally require a load measure. When the gate is unmet the service
evaluates only the signals that need no rated weeks, so a user without enough
rated weeks pays nothing for the load-reading signals; when no card speaks and
the Mix layer exists the
Stats screen shows the locked Signals line in the layer's slot instead,
reading `Unlocks after 4 weeks of rating your workouts — N of 4 so far.` from
the payload's rated weeks alone. Verified by
`test/signals_service_test.dart` (`S-17501 an unmet gate evaluates only the
signals that need no rated weeks`),
`test/signals_layer_screen_test.dart` (`S-4002 the locked line counts rated
weeks`, `S-4013 the locked section takes the layer slot`, group `S-17507
dismissing the only card at an unmet gate` › `S-17507 returns the block to
the locked line`) and, for the count's rule,
`test/stats_rated_weeks_service_test.dart` (`S-17106 ratedWeekBlockStarts
tiles the 12 weeks at local midnight`).

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
is a property of the signals. Seven cautions are registered today, in ascending
priority: Training Gap (`kTrainingGapPriority`), Cardio Efficiency Drift
(`kCardioEfficiencyDriftPriority`), Sustained High Load
(`kSustainedHighLoadPriority`), Protein Consistency
(`kProteinConsistencyPriority`), Fuel vs Load (`kFuelVsLoadPriority`), Modality
Mix Shift (`kModalityMixShiftPriority`) and Cross-Modality Interference
(`kCrossModalityInterferencePriority`). The registered positives are Progression
Rate (`kProgressionRatePriority`), Consistency (`kConsistencyPriority`) and
Hold Progress (`kHoldProgressPriority`). The list is the priority
order, not the render order: when two cautions qualify together the framework
draws the higher priority first, so Protein Consistency renders above Sustained
High Load, and Sustained High Load renders above Cardio Efficiency Drift.
Verified by `test/interference_test.dart` (`the caution order holds
and the registry is ordered by it`), which asserts the registry lists the
cautions in ascending priority with Training Gap first; by
`test/signals_service_test.dart` (group `S-17503 which registered signals need
rated weeks`), which pins the ten registered ids; by
`test/consistency_signal_test.dart` (group `S-17809 the signals on real
sessions — Mock` › `Consistency proposes its card from fixture A, Monday
weeks`) for the Consistency entry's kind and priority; by
`test/hold_progress_test.dart` (`the constants the rule is built from are the
ones the plan names`) and `test/modality_mix_shift_signal_screen_test.dart`
(group `the registry` › `lists exactly the ten shipped signals, in order`) for
the Hold Progress entry's priority and registration; by
`test/sustained_high_load_test.dart` (`the
registry lists the cautions in strictly ascending priority`); by
`test/sustained_high_load_signal_screen_test.dart` (`S-2412 two cautions
qualifying` › `renders the higher-priority caution above the Sustained High Load
card`); by `test/cardio_efficiency_drift_signal_screen_test.dart` (`S-2511 two
cautions qualifying` › `renders the higher-priority caution above the Cardio
Efficiency Drift card`); and by `test/modality_mix_shift_test.dart` (the
constant contracts) for the Modality Mix Shift entry.

## Abstention

A signal returns null when its own data-sufficiency conditions are unmet. An
abstaining signal contributes nothing — not a card, not an exception to the
quiet line — and is indistinguishable from a signal that is not registered.
Verified by `test/signals_framework_test.dart` (`S-1708 an abstaining signal is
invisible`) and `test/signals_service_test.dart` (`S-1708 an abstaining signal
adds nothing and suppresses nothing`).

## The quiet line

When the gate is met and no card qualifies, the framework reports the quiet-line
state instead of cards: `kSignalQuietLine` is the sentence the caller draws
without a card, or `kSignalQuietLineWithWaiting` (`No signals right now.`) when
waiting lines sit under it, because "nothing outside your usual range" would
read as "nothing here" above lines about what is still missing. Verified by
`test/signals_layer_screen_test.dart` (`the quiet line shortens and the line
follows it`, `S-18401 with no waiting line the quiet line keeps its full copy`)
and `test/signals_framework_test.dart` (`S-18402 the quiet line with waiting
lines under it is the pinned shorter sentence`).
A gate-unmet load reports the cards of the unlocked signals but never the quiet line,
so a caller can tell "nothing to say" from "not yet speaking". Verified by
`test/signals_framework_test.dart` (`S-1703 gate met, nothing qualifies` ›
`S-17504 an unmet gate keeps the cards it is given and shows no quiet line`,
`S-17504 an unmet gate with nothing to show yields no cards and no quiet
line`, group `Structural guard — the quiet line needs the gate` › `an unmet
gate with no candidates is never the quiet line`).

## The waiting lines

Each signal can say what it is waiting for
— one sentence on what the user can supply to wake it, or null when it is not
short of anything the user can supply. `SignalsService.waitingLines` asks every
registered signal in registry order, drops the nulls, skips a signal whose
answer cannot be read and returns at most `kSignalMaxWaitingLines` (3) lines;
it does not read the gate. Verified by `test/signals_waiting_test.dart` (group
`S-17603 SignalsService.waitingLines`).

Two signals answer today. `proteinConsistencyWaitingLine` in
`lib/core/models/protein_consistency.dart` returns
`Protein Consistency: log food on N more days of the last 14.` — `1 more day`
for one — for 1 to 9 logged days in the 14 local days ending today, and null
with none (a user who does not log food is not nagged) and from 10, when the
signal can speak. Verified by `test/signals_waiting_test.dart` (group
`S-17601 proteinConsistencyWaitingLine`) and, for the count the adapter feeds
it, groups `S-17604 the Protein Consistency count — Mock` and `S-17604 the
Protein Consistency count — Hive`.

`cardioEfficiencyWaitingLine` in `lib/core/models/cardio_efficiency_drift.dart`
returns `Cardio Efficiency: needs heart rate from the watch on at least 3
workouts of the same kind in each of two periods.` for 1 to 5 eligible efforts
— cardio workouts that already carry a measured distance and an average heart
rate — and null with none (no watch, nothing to do) and from 6. Verified by
`test/signals_waiting_test.dart` (group `S-17602 cardioEfficiencyWaitingLine`).

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
priority, `needsRatedWeeks`, `evaluate` and `waitingFor`. `waitingFor` answers
what it is waiting for
— one sentence on what the user can supply to wake the signal, or null when it
is not short of anything the user can supply. `SignalContext` carries
everything one evaluation may
read — the load's `now`, the resolved window, the resolved mix, the
`StatsProgressService` and the `WorkoutRepository` — plus the `startOfWeek`
Start of Week setting (`monday` or `sunday`), which `evaluateCandidates` and
`waitingLines` pass through and the Stats screen supplies from the setting — so
a signal added later needs no change to the contract. Verified by
`test/signals_service_test.dart` (group `S-17811 the start of week reaches the
signals`) and `test/signals_layer_screen_test.dart` (group `S-17812 the Start
of Week setting reaches the signals`). The contract itself is verified by
`test/signals_service_test.dart`,
whose stub signals implement the contract and are driven through the service,
and by `test/signals_waiting_test.dart` (group `S-17603
SignalsService.waitingLines`).

## Registered signals

The ten registered signals — Training Gap, Progression Rate, Consistency,
Hold Progress, Modality Mix Shift, Cross-Modality Interference, Fuel vs Load,
Protein Consistency, Sustained High Load and Cardio Efficiency Drift — are
described in
[Registered Signals](signals_registered.md): each one's definition, adapter,
gate, copy and the tests that pin them. This page keeps the framework.

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
- [Nutrition](nutrition.md) — the food log, the daily target and the
  consistency foundation the nutrition signals read
- [Data Models](data_models.md) — where the Signals value types sit
- [State Management & Services](state_management/services_and_utils.md) —
  `SignalsService` alongside the other services
