# Stats Screen — Signals Layer

**Scope.** The Signals layer of the Stats screen: where it sits, the gate, the cards, the quiet line, the waiting lines, dismissal and how it loads with the rest of the screen.
The signal framework is in [Signals](../signals.md) and the individual signals' definitions are in [Registered Signals](../signals_registered.md).

> Part of [Stats Screen](../stats_screen.md). Return to the [Signals layer](../stats_screen.md#signals-layer) entry for the rest of the screen.

---

The Signals layer is the second block in the body, directly under the Mix layer
and above the Instruments list, and there is exactly one of it.
The signals that need no ratings render from the first session; the signals
that read the load measure or the ratings wait for the gate —
`signalsGateMet(mix)`, the Mix layer's `ratedWeeks` —
how many of the last 12 seven-day weeks, today's included, hold a rated
session — against `kTrainingLoadMinRatedWeeks`. When the gate is
unmet but a card speaks, the layer shows the hint line
`More signals unlock after 4 weeks of rating your workouts — N of 4 so far.`
under the cards, N being the payload's rated weeks. When the gate is unmet and
no card speaks, the screen shows the locked Signals section in the layer's
slot instead: the `SIGNALS` header and one line,
`Unlocks after 4 weeks of rating your workouts — N of 4 so far.`, where N is
that count and no load-reading signal is evaluated. Verified by
`test/signals_layer_screen_test.dart` (group `S-17505 a signal that needs no
ratings speaks while the gate is unmet` › `S-17505 its card shows with the
hint under it and the load-reading signal is not evaluated`, `S-1702`,
`S-4002`, `S-4013`), `test/signals_service_test.dart` (`S-17501 an unmet gate
evaluates only the signals that need no rated weeks`) and
`test/stats_rated_weeks_screen_test.dart`
(group `S-17107 current weeks count` › `two rated weeks drive the locked line
and the Mix note`).

**The cards.** A load shows at most `kSignalMaxCards` cards: one caution above
one positive when both kinds qualify, otherwise the top cards of the surviving
kind. A card is a neutral surface carrying its kind's label and icon, the
observation and, when the signal supplies one, a suggestion. Kind is carried by
the label and the icon, never by a colour, and the layer adds no theme token.
Verified by `test/signals_layer_screen_test.dart` (`S-1704`–`S-1708`) and
`test/signals_framework_test.dart` (`D-1004 at most two cards`,
`D-1005 priority order within a kind`).

**The quiet line.** When the gate is met and no card qualifies, the layer shows
its header and `kSignalQuietLine` (`kSignalQuietLineWithWaiting` above waiting
lines; see [Signals](../signals.md#the-waiting-lines)). The layer is never hidden
once the gate is met, because "nothing to say" is a state the user can see.
Verified by `test/signals_layer_screen_test.dart` (`S-1703`, `S-1708`) and,
for the waiting lines' place under the quiet line, group `S-17605 the waiting
lines sit under whatever the block shows` › `the quiet line shortens and
the line follows it`.

**The waiting lines.** Under whatever the block shows — the cards and the hint,
the quiet line or the locked line — the screen draws up to
`kSignalMaxWaitingLines` (3) lines, one per signal still
short of something the user can supply, each keyed `signals_waiting_N`, under
everything else in the block. The
screen computes them whenever there is at least one completed session, the same
condition that evaluates the signals; with no completed session the empty state
shows alone and no line is computed. Two exist today:
`Protein Consistency: log food on N more days of the last 14.`
(`1 more day` for one) when food was logged on 1 to 9 of the last 14 days, and
`Cardio Efficiency: needs heart rate from the watch on at least 3 workouts of
the same kind in each of two periods.` when 1 to 5 cardio workouts carry a
measured distance and an average heart rate. Verified by
`test/signals_layer_screen_test.dart` (group `S-17605 the waiting lines sit
under whatever the block shows`) and `test/signals_waiting_test.dart` (groups
`S-17601 proteinConsistencyWaitingLine`, `S-17602 cardioEfficiencyWaitingLine`,
`S-17603 SignalsService.waitingLines`); the empty state by group
`the empty-state branch` › `a profile with no sessions shows the empty state
and no layer, even with stubs registered`.

**Dismissing a card.** A card's dismiss control removes the card in the frame of
the tap: the screen resolves the held candidates against the new store with
`signalDismissalsWith`, updates the view, and only then writes the store through
`persistDismissals`, with no reload and no second walk of history. Verified by
`test/signals_layer_screen_test.dart` (`S-1709`) and, for the store write on
both repositories, `test/signals_service_test.dart` (`S-1712 Mock and Hive
parity`).

**The dismissal window.** A dismissal hides its signal for
`kSignalDismissalDays` **local calendar days**, with the dismissal day counted
as day 1; the signal is eligible again the day after the window. Verified by
`test/signals_framework_test.dart` (`S-1710 the 14-day window`, `S-1711 the
daylight-saving boundary`) and `test/signals_layer_screen_test.dart` (`S-1710`,
`S-1711`).

**Not coaching.** A signal is a rule-based observation against the user's own
history, never a rest, deload or recovery instruction, and every observation
carries its own time span. An earlier revision of this document recorded "no
rest / deload / recovery suggestion" as a deliberate non-feature; this section
deliberately replaces that, limited to these signal rules, rather than leaving
it as a gap. Verified by `test/signals_layer_screen_test.dart` (`S-1716`) and
`test/stats_legacy_removal_test.dart` (`S-1210`, no chart primitive).

**The registered signals.** `buildSignalRegistry()` lists ten, described here in the order they shipped rather than in registry order (the registry order is in [Signals](../signals.md#selection-and-the-card-cap)). The first is the
Progression Rate: it compares each exercise's own metric across two adjacent
windows and proposes a positive card only when the recent window improves on the
prior one. Its rules — the two windows, what a sample is, the zero fallback, the
three thresholds, the kind and the priority — live in
[Signals](../signals.md#registered-signals) and are not restated here. The card's
copy and its suggestion are built by `progressionRateCopy`
(`lib/core/models/progression_rate.dart`) so that the copy and the qualification
test cannot disagree. Verified by `test/progression_rate_signal_screen_test.dart`
(`S-1801` the card end to end, `S-1812` its disappearance when the condition
clears, `S-1813` its dismissal) and, for the definition itself,
`test/progression_rate_test.dart`.

The second is the Modality Mix Shift: it reports a modality the user regularly
trains whose share of their load has fallen to less than half its usual share
over its own `kModalityMixShiftPeriodDays`-day period, and proposes a caution
card. Its rules — the period, the
baseline, the measure gate, the two thresholds, the two sentences and the
suggestion — live in [Signals](../signals.md#registered-signals) and are not
restated here. The card's copy is built by `modalityMixShiftCopy`
(`lib/core/models/modality_mix_shift.dart`) so that the copy and the fire test
cannot disagree. Verified by `test/modality_mix_shift_signal_screen_test.dart`
(`S-1909` the card on the layer and its dismissal, `S-1904b` its absence while
the period measures time) and, for the definition itself,
`test/modality_mix_shift_test.dart`.

The third is the Cross-Modality Interference: it reports that the user's next
lifting day after a hard sports session has come in below their own usual level
on the same lifts, at least `kInterferenceMinDippedFollowUps` times in the
pattern window, and proposes a caution card. Its rules — the hard window and its rated population, the follow-up, the
per-exercise dip against its own average, the pattern window and the optional
second sentence — live in [Signals](../signals.md#registered-signals) and are not
restated here. The card's copy is built by `crossModalityInterferenceCopy`
(`lib/core/models/interference.dart`) so that the copy and the fire test cannot
disagree. Verified by `test/interference_signal_screen_test.dart` (`S-2013` the
card on the layer and its dismissal) and, for the definition itself,
`test/interference_test.dart`.

The fourth is the Fuel vs Load: it reports that the user's training load rose
over the last three weeks while their average daily intake did not rise with it,
and proposes a caution card. Its rules — the two periods, the six-block
consistency gate, the measure gate, the two thresholds, the copy and the
suggestion — live in [Signals](../signals.md#registered-signals) and are not
restated here. The card's copy is built by `fuelVsLoadCopy`
(`lib/core/models/fuel_vs_load.dart`) so that the copy and the fire test cannot
disagree. Verified by `test/fuel_vs_load_signal_screen_test.dart` (`S-2113` the
card on the layer and its dismissal, and the abstention when the repository
holds no food) and, for the definition itself, `test/fuel_vs_load_test.dart`.

The fifth is the Protein Consistency: it reports that the user's protein has
averaged short of the level they usually manage, or short of their own daily
target, over its own `kProteinConsistencyWindowDays`-day window, and proposes a
caution card. Its rules — the window, the logged-days and resistance gates, the
two comparison modes, the per-day target mean, the baseline's consistent weeks,
the threshold, the copy and the priority — live in
[Signals](../signals.md#registered-signals) and are not restated here. The card's
copy is built by `proteinConsistencyCopy`
(`lib/core/models/protein_consistency.dart`) so that the copy and the fire test
cannot disagree. Verified by `test/protein_consistency_signal_screen_test.dart`
(`S-2216 the card on the layer the caution card shows with S-2201's copy, the
caution label and its key, below the Mix layer`, `S-2216 the card is dismissible
one tap removes the card in the tap frame, the store holds the id, and the next
open is still quiet`, `S-2207 with no bodyweight drops the g/kg figure and
renders no second line at all`) and, for the definition itself,
`test/protein_consistency_test.dart`.

The sixth is the Sustained High Load: it reports that the user's completed weeks
ran above their usual load with no easier week in the run, and proposes a caution
card. Its rules — the weeks, the twelve-week baseline, the rated-history floor,
the higher-load line, the streak, the measure gate, the history fact, the copy
and the priority — live in [Signals](../signals.md#registered-signals) and are not
restated here. The card's copy is built by `sustainedHighLoadCopy`
(`lib/core/models/sustained_high_load.dart`) so that the copy and the fire test
cannot disagree. Verified by `test/sustained_high_load_signal_screen_test.dart`
(`S-2412 the card on the layer` › `the caution card shows with S-2401's copy, the
caution label and its key, below the Mix layer`, `S-2412 the card is dismissible`
› `one tap removes the card in the tap frame, the store holds the id, and the
next open is still quiet`) and, for the definition itself,
`test/sustained_high_load_test.dart`.

The seventh is the Cardio Efficiency Drift: it reports that one cardio exercise's
measured pace at the same average heart rate is worse than it was four to six
weeks ago, over efforts of comparable duration, and proposes a caution card. Its
rules — the two windows, the eligible effort, the duration grouping, the drift
test, the one-card selection, the lifting sentence, the copy and the priority —
live in [Signals](../signals.md#registered-signals) and are not restated here. The
card's copy is built by `cardioEfficiencyDriftCopy`
(`lib/core/models/cardio_efficiency_drift.dart`) so that the copy and the fire
test cannot disagree. Verified by
`test/cardio_efficiency_drift_signal_screen_test.dart` (`S-2501 the card on the
layer` › `the caution card shows with S-2501's copy, the caution label and its
key, below the Mix layer`, `S-2511 the card is dismissible` › `one tap removes
the card in the tap frame, the store holds the id, and the next open is still
quiet`) and, for the definition itself,
`test/cardio_efficiency_drift_test.dart`.

The eighth to tenth are the Consistency, the Training Gap and the Hold Progress
(a positive, a caution and a positive card): their rules live in
[Registered Signals](../signals_registered.md). Verified by
`test/consistency_test.dart` (groups `S-17801 consistency, a Monday week`,
`S-17807 the training gap`) and `test/hold_progress_test.dart` (group
`S-17901 a hold that improved`).
