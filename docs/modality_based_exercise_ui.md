# Modality-Based Exercise Details Screen — UX/UI Technical Documentation

## Overview

The **modality-based exercise details screen** (`WorkoutSessionScreen`) is the core workout tracking interface that dynamically adapts its UI and interaction patterns based on the training modality selected by the user. This document describes the UX/UI architecture, design patterns, and implementation details of this adaptive exercise tracking system.

## Business Context

### Problem
Traditional workout apps force a single tracking paradigm (typically reps/sets/weight for strength training), making them poorly suited for other training types. Athletes across different sports need different tracking methods:
- **Runners** track continuous time and distance
- **Powerlifters** track sets, reps, and weight
- **Martial artists** track timed rounds
- **Yogis** track static hold durations

### Solution
A **context-aware UI** that automatically configures its tracking controls, metric inputs, progress indicators, and terminology based on the workout modality. The same screen adapts to display:
- Rep/weight editors for resistance training
- Duration timers for cardio work
- Round counters for martial arts
- Hold timers with extra weight tracking for isometric work

### Key Benefits
1. **Zero Configuration**: Users never manually select tracking modes; the UI adapts automatically
2. **Consistent Experience**: Same screen layout, different context-appropriate controls
3. **Universal Compatibility**: Single implementation supports all training types
4. **Cognitive Ergonomics**: Terminology and controls match the user's mental model of their activity

---

## Architecture Overview

### Component Hierarchy
```
WorkoutSessionScreen (StatefulWidget)
├── State Management (_WorkoutSessionScreenState)
│   ├── with WorkoutSessionTimerMixin (workout_session_timer_mixin.dart)
│   │   ├── Per-effort timer state maps
│   │   └── Timer lifecycle methods (toggle, tick, pause, freeze, persist)
│   ├── Exercise list state
│   ├── Current exercise/set tracking
│   ├── Rest count-up state
│   └── View mode state (list vs detail)
├── UI Modes (split across part files)
│   ├── List View builders → workout_session_list_view.dart
│   └── Detail View builders → workout_session_detail_view.dart
└── Reusable Widgets
    ├── InlineMetricEditor (scrollable value adjustment)
    ├── ValueStepperRow (reps / weight rows with − and +, boxed)
    ├── Header (navigation + one-line exercise counter)
    ├── SetSegmentBar (one tappable segment per set / interval / round / hold, with per-set captions)
    ├── SetCountStepper (boxed add / remove entry control)
    └── Control Buttons
```

### Key Design Principles

1. **Single Responsibility per View Mode**
   - List View: Exercise overview, navigation, add exercises
   - Detail View: Exercise execution, metric tracking, set logging

2. **State-Driven UI Rendering**
   - `effortKind` determines which metrics to display
   - ModalityConfig provides terminology (rounds vs periods vs intervals)
   - Timer states control start/pause/resume behavior

3. **Progressive Disclosure**
   - Start in list view (see all exercises)
   - Tap to drill into detail view (focus on one exercise)
   - Back returns to list view (overview)

4. **Haptic + Visual Feedback**
   - Light haptic on successful log (non-web)
   - The rest count-up appears after logging a set
   - Timer state conveyed by the ticking digits and the centre button label — `timed` and `drill` have no status row (`test/timed_emphasis_redesign_test.dart`, group `Timed emphasis redesign` · `free-session timed and drill running states keep dominant digits and show no status chrome across all themes`)
   - Logged segments of the set bar fill in (`SetSegmentBar`)

---

## Modality-Based UI Adaptation

### Effort Kinds (UI Rendering Modes)

The `effortKind` field on each `SegmentEffort` drives UI rendering. Determined by modality during exercise addition. The four kinds are `set`, `timed`, `round`, and `drill`; see [Constants Reference](constants_reference.md) for their definitions and [Modality Tracking](modality_tracking.md) for how a modality resolves to one.

**Terminology Adaptation**: `round` efforts render as "ROUND" for martial arts and "PERIOD" for the sports modality.

---

## Core UX Patterns

### 1. InlineMetricEditor (Scrollable Value Adjustment)

**Purpose**: Touch-optimized value input without keyboard, ideal for workout environments (gym, outdoors).

**Implementation Details**:
```dart
class InlineMetricEditor extends StatefulWidget {
  final String metricType;        // 'reps', 'weight', 'duration', 'rpe', 'extra-weight'
  final dynamic currentValue;     // Current value to display
  final String unitLabel;         // 'REPS', 'LBS', 'TIME', 'EXTRA WEIGHT'
  final Function(dynamic) onValueChanged; // Immediate callback
}
```

**Visual Design**:
- Value changes by tapping the number and using the popup/dialog; the editor is tap-only (no drag path exists in `lib/widgets/session/inline_metric_editor.dart`)

**Set efforts render stepper rows**: for an effort of kind `set` (resistance
and free training) the reps and weight values render as two `ValueStepperRow`
rows, reps then weight — `−` on the left, the number in the middle, `+` on the
right, each row boxed in the shared `OmniSurface` with no shadow. Tapping the
number still opens the popup; one tap on a button steps the value, holding a
button repeats it.

Verified by `test/reps_screen_test.dart` (group `Reps screen — stepper rows —
resistance (S-4250..S-4256)` · `S-4250: the two rows step reps and weight and
store both`, `S-4254: tapping the weight number still opens Edit Weight`,
`S-4253: holding plus stores the stepped value once, on lift`) and
`test/logger_shell_screen_test.dart` (group `Logger polish — header, captions,
boxes, layout (S-4311..S-4317, S-4322..S-4324)` · `S-4316: the reps and weight
rows sit in an OmniSurface`).

**Count-up efforts render plain digits**: the two count-up kinds — `timed`
(cardio interval) and `drill` (isometric hold) — show the elapsed time as
plain large digits with no ring, no status row (no play/pause glyph, no
`STOPPED` / `RUNNING` / `PAUSED` text) and no time stepper before Start; a
caption sits under the digits — `ELAPSED` while the entry is unfinished,
`COMPLETED` once it is finished (owner O-13 restored what 38c had removed);
running is conveyed by the digits ticking and the centre button label
(`Start`, then `Log Interval` / `Log Hold`). The only way to produce a value is Start → run → log, which
locks the elapsed time; there is no Pause control, and an entry restored from
storage in the paused state shows `Resume` in the centre slot. The live
digits render at the `MetricEmphasisTier.hero` emphasis — the size constant
`kCountUpDigitsFontSize` in `lib/widgets/session/inline_metric_editor.dart` —
inside a scale-down `FittedBox`, so a count past an hour still fits; the
digits read `mm:ss` below an hour and `h:mm:ss` from it
(`OmniDateUtils.formatTimerDigits` in `lib/core/utils/date_utils.dart`).
Both kinds show one full-width `ValueStepperRow` weight row under the
digits, always visible (the old collapsible `Weight adjustment` button is
gone; plan 39 D-5 gave the interval its row back, superseding the O-11 rule
for the interval — a hold's row is unchanged): it steps 2.5 kg or 5 lb
(`MetricStepping.weightStepFor`), stores the `extra-weight` metric, tapping
the number opens the existing `Edit Weight` popup (limits −200..999 in the
shown unit, and the number carries no `+` sign), and the row is editable
before Start and while the effort runs; once the effort is logged in a live
session its buttons dim and do nothing, and it is never locked in the session
editor. The row's key is per set, so moving to another set discards an effort
in progress. In the session editor a count-up keeps its duration editor
(dialog `Edit Interval Duration` / `Edit Hold Duration`) plus the weight row.

The stepper rows and the session-editor duration editors share the
`InlineMetricEditor` anatomy: the unit label sits directly under the number,
centred, and when the editor is editable a `tap to type` hint (key
`tap-hint`) sits under the label; a read-only editor shows no hint. On the
sports screen the body is tightened: the `SetSegmentBar` cell is
`kSetBarCaptionedHeight` tall with captions and `kSetBarPlainHeight` without
(constants in `lib/widgets/session/set_segment_bar.dart`), and the scroll
area's top padding is smaller, so the ring starts within a dozen dp of the
bar.

Verified by `test/count_up_screen_test.dart` (group `Count-up — timed
intervals (S-4260..S-4263)` · `S-4260: an interval with no load shows digits
and no chrome`, `S-4260: a stored extra weight shows again on an interval
(plan 39, D-5)`, `S-4260: an exercise that carries load shows the interval
weight row too (plan 39, was O-11)`, `S-4261: Start leaves the digits plain
and the button logs`, `S-4262: the interval editor keeps its duration dialog
and gains the weight row (S-4709)`, `S-4263: logging an interval leaves its
data untouched`, `S-4277: a live interval's digits open nothing on a tap`;
group `Cardio weight — live (S-4708)` · `S-4708: an interval carries a 0.0 KG
row under its digits`, `S-4708: + steps the interval 2.5 kg and stores
kilograms`, `S-4708: a pounds interval steps 5 lb and stores 2.27 kg`,
`S-4708: logging the interval locks its weight row`, `S-4708: the logged
interval caption stays the time only`, `S-4708: a hold still shows its weight
row`; group `Cardio weight — editor (S-4709)` · `S-4709: the session editor
keeps a finished interval editable and Save stores the kilograms`;
group `Count-up — holds (S-4264..S-4270)` ·
`S-4264: a hold shows digits plus one weight row`, `S-4265: the hold weight
steps 2.5 kg at a time`, `S-4265: a pounds preference steps 5 lb and stores
kg`, `S-4266: a weight step does not stop a running hold`, `S-4267: a logged
hold locks both weight buttons`, `S-4267: a logged hold stays editable in the
editor`, `S-4268: the hold weight number opens Edit Weight`, `S-4269: a
stored 10.0 reads as 10.0, with no sign`, `S-4269: a stored -10.0 reads as
-10.0 and plus gives -7.5`, `S-4270: a long press survives the one-second
rebuilds`, `S-4276: a hold dies with its set when the arrows move focus`,
`S-4278: a live hold's digits open nothing on a tap`, `S-4279: the hold
editor keeps its duration dialog`; group `Count-up — restored paused entries
(S-4273, S-4274)` · `S-4273: a paused interval shows its elapsed and Resume`,
`S-4274: a paused hold keeps its elapsed, weight and Resume`; group `Count-up
— a running hold survives a weight step (S-4275)` · `S-4275: the reload keeps
the elapsed time and the timer`; group `Count-up — layout guard (S-4271)` ·
`S-4271: with the rest strip up the hold's controls are reachable`; group
`Count-up — a finished entry reads COMPLETED (S-4402)` · `S-4402: a finished
interval swaps ELAPSED for COMPLETED`, `S-4402: a finished hold swaps ELAPSED
for COMPLETED`),
`test/exercise_detail_emphasis_tier_test.dart` (`S-106 hold effort weight row
renders dominant tier`, `S-106b interval effort renders a weight editor`),
`test/count_up_hero_layout_test.dart` (group `S-4710 hero count-up digits` ·
`the live interval digits are 112 sp inside a scaleDown FittedBox, captioned
ELAPSED`, `the live hold digits are 112 sp inside a scaleDown FittedBox,
captioned ELAPSED`, `an interval past an hour reads 1:15:35`, `the sports
ring digits are 48 sp inside the ring chord`; group `S-4711 tightened body` ·
`the set bar cell is 34 dp with captions on a 3-period sports screen`,
`the set bar cell is 18 dp without captions on a 6-period sports screen`,
`the ring starts within 12 dp of the set bar`; group `plan 39 constants` ·
`the digit and set bar sizes are pinned at the plan 39 values`),
`test/cardio_interval_weight_storage_test.dart` (groups `Mock` and `Hive` ·
`S-4708 a logged interval weight is stored as kilograms`, `S-4708 a pounds
step is stored as its kilogram value`, `S-4709 the editor Save rewrites the
interval row in place`),
`test/value_stepper_row_test.dart` (group `S-4707 anatomy` · `a reps row
centres its label and hint under the number`, `a weight row centres its label
and hint under the number`, `a duration row centres its label and hint under
the number`, `a locked row hides the hint and keeps the label under the
number`),
`test/timed_emphasis_redesign_test.dart` (group `Timed emphasis redesign` ·
`free-session timed and drill stopped states show dominant digits only: no
status chrome, one weight row on an interval and on a hold, across all
themes`, `free-session timed and drill running states keep dominant digits
and show no status chrome across all themes`, `routine setup shows one weight
row for a timed effort and a drill effort across all themes`,
`routine-backed timed and drill
session details show dominant digits with no status chrome across all
themes`), `test/logger_shell_screen_test.dart` (group `Logger shell — logged
sets are locked live (S-4216/S-4217)` · `S-4217: a logged hold's weight is
read-only live`, `S-4217: edit mode keeps a logged hold's weight editable`)
and `test/session_toolbar_rework_test.dart` (`S-009: tapping Start button
starts the timer (centre button becomes Log Interval)`, `S-010: centre button
reads Start before the timer runs`, `S-011: centre button reads Log Interval
while running`, `S-013: jumping to another set leaves the timer running`).

### 2. Timer State Management

**Challenge**: Multiple exercises with multiple sets, each potentially with independent timers.

**Solution**: All effort timers are **wall-clock derived from persisted records**; the only `Stopwatch` / `Timer.periodic` in the session screen is a 1-Hz UI repaint driver. There is no `Stopwatch`-based elapsed counter in the active source.

> **Note on prior implementations:** Earlier drafts of this file described "Stopwatch-Based Timers (set / timed / drill efforts)" with a `_effortStopwatches` field. That implementation no longer exists in the source. The current `set` effort has no timer at all (reps + weight are stepper-row inputs persisted on every `updateEntryValue`); `timed` and `drill` elapsed time is derived from `TimedInstance` wall-clock records; `round` elapsed time is derived from `RoundInstance` wall-clock records. A single `_ticker = Timer.periodic(1 s)` drives UI repaints; it never computes elapsed time itself.

#### Effort kinds and their timer model

| Effort kind | Has a running timer? | Source of truth for elapsed time | Persisted record |
|---|---|---|---|
| `set` | No — reps + weight are stepper-row inputs | n/a (no clock) | `EffortObservation` rows written on every `updateEntryValue` |
| `timed` | Yes (started from the centre button; `Resume` only for an entry restored from storage in the paused state) | Wall-clock derived from `TimedInstance.startedAtMs` − `pausedAtMs` − `totalPausedDurationMs` | `TimedInstance` row |
| `drill` | Yes (same timer model as `timed`) | Wall-clock derived from `TimedInstance` (same formula as `timed`) | `TimedInstance` row |
| `round` | Yes (start / pause / resume from the timer display) | Wall-clock derived from `RoundInstance` timestamps via the `elapsedMs` getter | `RoundInstance` row |

#### Per-tick UI state (timer mixin)

The session-screen timer mixin (`WorkoutSessionTimerMixin` in
`lib/features/session/workout_session_timer_mixin.dart`) owns the per-effort UI state, all keyed by `effortId-entryIndex`:

```dart
final Map<String, Timer?> _effortTimers = {};          // Active periodic ticks (UI repaint drivers)
final Map<String, bool> _effortRunning = {};           // Running state flags
final Map<String, int> _effortElapsed = {};            // Elapsed seconds (UI display cache)
final Map<String, bool> _effortAlerted = {};           // Expiry alert already fired
final Map<String, int> _effortTargetDuration = {};     // Countdown / expiry check
```

`_effortElapsed` is **derived on each tick** by reading the relevant persisted record (`TimedInstance.elapsedMs` or `RoundInstance.elapsedMs`) — it is a display cache, not a source of truth. The mixin never holds a `Stopwatch`.

#### Wall-Clock Timer Lifecycle (`timed` / `drill` / `round`)

1. **Start**: persist `startedAtMs = now` (or resume from `pausedAtMs` / `totalPausedDurationMs`); start a `Timer.periodic(1 s)` to drive UI repaints; set `_effortRunning[key] = true`.
2. **Pause**: persist `pausedAtMs = now`; cancel the periodic tick; clear `_effortRunning[key]`.
3. **Resume**: fold `pausedAtMs` into `totalPausedDurationMs`; clear `pausedAtMs`; restart the periodic tick.
4. **Log / Finish**: persist the final value; cancel the tick; clear `_effortRunning[key]`. The persisted timestamps stay so the final elapsed is reproducible on reload.
5. **Round specifics**: `completeRound` (natural countdown) vs `endRoundEarly` (user-ended) both write `finishedAtMs`; `elapsedMs` returns `actualDurationSecs * 1000` for the `finished` state.

The 1-Hz `_ticker` reads the persisted record on each tick and repaints; it never owns elapsed time. App suspension, foreground return, and reload all derive the same elapsed from the persisted timestamps.

**Round State Machine**:
Round lifecycle is enforced by `RoundState` enum in `RoundInstance`:
- `notStarted` → `active` (via `WorkoutState.startRound`)
- `active` → `paused` (via `WorkoutState.pauseRound`)
- `paused` → `active` (via `WorkoutState.resumeRound`; folds pause into `totalPausedDurationMs`)
- `active` / `paused` → `finished` (via `completeRound` / `endRoundEarly`)
- `finished` is terminal — no further transitions allowed

Transitions are validated by `_isValidRoundTransition()` in `WorkoutState`. Rapid-tap protection is provided by the `_pendingRoundTransitions` set in `WorkoutSessionScreen`, which blocks duplicate dispatches while a write is in-flight.

**Round Countdown Display** (live `round` effort):
- The hero is a `TimerRing` (`lib/widgets/session/timer_ring.dart`) with the
  remaining-time digits centred inside it. The ring and the digits derive from
  the same pair — the timer mixin's per-tick `_effortElapsed` cache and
  `_getEffortTargetDuration` — as `effectiveTarget - elapsed`, clamped to
  `[0, effectiveTarget]`; the display never reads
  `RoundInstance.remainingMs`, which re-derives from `DateTime.now()` at
  build time and can disagree with the digits between ticks. Verified by
  `test/round_countdown_screen_test.dart` (group `Round countdown — ring
  (S-4401)` · `S-4401: a fresh 180 s round draws a full ring`, `S-4401: an
  active round 45 s in shows a 0.75 ring`).
- Ring states: full before Start; following the digits while running (a
  falling progress sweeps linearly over one second between the 1 Hz ticks);
  frozen at its fraction for a round restored paused; empty once the round is
  finished, by expiry or by logging early. Verified by `test/timer_ring_test.dart`
  (group `S-4408 sweep` · `a falling progress sweeps while running`, `a
  stopped ring applies the new value at once`, `a growing progress while
  running is applied at once`) and `test/round_countdown_screen_test.dart`
  (group `Round countdown — restored instances (S-4410, S-4411)` · `S-4410: a
  paused round 45 s in reads 02:15, frozen at 0.75`, `S-4411: a round logged
  early reads 01:00 + COMPLETED, ring empty`).
- Captions: `REMAINING` under the digits while the round is unfinished,
  `COMPLETED` once it is finished. The old chrome is gone: no `ROUND n` /
  `PERIOD n` heading, no `DURATION` / `RUNNING` / `STOPPED` / `PAUSED`
  labels, no play/pause status row. Verified by
  `test/round_countdown_screen_test.dart` (group `Round countdown — digits
  and caption (S-4402)` · `S-4402: martial arts reads 03:00 + REMAINING with
  no old chrome`, `S-4402: sports reads 03:00 + REMAINING with no old chrome`)
  and `test/sports_emphasis_redesign_test.dart` (group `Sports effort emphasis
  redesign` · `S-001 free session stopped hierarchy is correct`, `S-002 free
  session running hierarchy is correct`).
- Round-length row under the ring: a `ValueStepperRow` in its duration mode
  with the inline label `ROUND LENGTH` — one step is 15 s, the row is floored
  at 15 s and ceilinged by `MetricStepCalc`, tapping the number opens
  `showDurationEntryDialog` (`Edit Round Duration`, `Edit Period Duration` in sports), and the row is read-only
  while the round runs, mid-round or finished. Verified by
  `test/round_countdown_screen_test.dart` (group `Round countdown — length
  row (S-4403, S-4413)` · `S-4403: + adds 15 s to the round length (03:15)`,
  `S-4403: − removes 15 s from the round length (02:45)`, `S-4413: − at 00:15
  stays at 00:15`, `S-4413: + at 60:00 stays at 60:00`, `S-4403: the row
  number opens the duration dialog`, `S-4403: the row is read-only while the
  round runs`) and `test/value_stepper_row_test.dart` (group `S-4413 duration
  mode`).
- A live length change applies to the round at the edited index (unless it is
  finished) and to every later round that has not started; running and
  finished rounds keep their own length. The single writer is
  `TimerManager.updatePlannedDurationFrom`
  (`lib/state/workout/timer_manager.dart`), exposed by `WorkoutState` and
  called by the screen's `round-duration` path. Verified by
  `test/state_test.dart` (`round: updatePlannedDurationFrom reaches the later
  unstarted rounds`, `round: updatePlannedDurationFrom keeps the running
  round its length`) and `test/round_planned_duration_parity_test.dart`
  (groups `Mock` and `Hive` · `S-4412 a finished round keeps its length, the
  later ones follow`, `S-4412 a running round keeps the length it started
  with`).
- Session editor (`editMode`): the same `ValueStepperRow` length row without
  the ring. Verified by `test/round_countdown_screen_test.dart` (group
  `Round countdown — layout and edit mode (S-4408, S-4409)` · `S-4409: edit
  mode shows the length row and no ring`).
- Actual duration capped at `plannedDurationSecs * WorkoutConstants.roundActualDurationCapFactor` on persist

### 5. Rest Count-Up Overlay

**Purpose**: Passive rest tracking between sets without requiring user action. Rest is a count-up
from the moment a set is logged to the moment the next set starts, with no preset length and no
countdown ([Global Conventions](global_conventions.md), "Rest rule: rest is a count-up";
`test/rest_is_count_up_contract_test.dart`).

**Architecture**: Rest intervals are backed by `EntryRest` repository records — **not** a Stopwatch. The old `_restTimer`, `_restStopwatch`, and `_restElapsedSeconds` fields have been removed. See [rest_tracking.md](rest_tracking.md) for the full data layer documentation.

**Behavior**:
- Appears automatically after logging a set (a new `EntryRest` record is written via `workoutState.recordRestStart(effortId, entryIndex)`)
- Overlay visibility is gated on `workoutState.hasRestRecord(effortId, entryIndex)` — no record, no overlay
- Elapsed time is read from `workoutState.getRestElapsedSeconds(effortId, entryIndex)` on each `_ticker` tick (wall-clock derived from `EntryRest.startedAtMs`)
- Displays elapsed rest time (MM:SS format)
- Positioned in lower screen area (above controls, non-intrusive)
- **Hides immediately when a timed/round/drill timer starts**: When `_toggleEffortTimer` is called to start a timed, round, or drill timer, all open rest records for that effort are closed **synchronously in-memory** before the timer UI begins rendering. This ensures `hasRestRecord()` returns `false` and `getRestElapsedSeconds()` returns `0` immediately, even if the async repository persist is still in-flight. Without this synchronous close, a race condition could occur where the rest overlay displays stale elapsed time (rest time + new timer time) in the millisecond window before the async persist completes. See [Rest Record Lifecycle — Synchronous Close on Effort Start](rest_tracking.md#rest-record-lifecycle--synchronous-close-on-effort-start) for details.
- Independent of effort timers — rest records are keyed per effortId+entryIndex, not globally

### 6. Set Navigation and Control

The detail view's header is one line under the exercise name:
`Exercise N / M · <section name>` — just `Exercise N / M` when the section has
no name (key `session-detail-header`).

Directly under the header, pinned outside the scroll, sits the set bar block:
one tappable segment per set / interval / round / hold (`SetSegmentBar`) with
one caption per segment under it — the logged value (`reps×weight` for a set,
`m:ss` for an interval, hold or round), blank for an unlogged set, shown only
when the exercise has 5 sets or fewer. The entry stepper (`SetCountStepper`)
sits in the scroll body below the exercise's controls, away from the primary
row: a boxed full-width control with `−` on the left, the count text in the
middle (`Set 2 of 3`, `Interval 2 of 3`, `Round`/`Period 2 of 3`, `Hold 2 of 3`)
and `+` on the right.

Verified by `test/logger_shell_screen_test.dart` (group `Logger shell — set bar
and logged line (S-4210..S-4214)` · `S-4210: logging through the button fills
the bar and line`, `S-4214: nothing logged keeps the line empty at its height`;
group `Logger shell — layout (S-4221/S-4223)` · `S-4221: the bar sits above the
controls, the stepper below`; group `Logger polish — header, captions, boxes,
layout (S-4311..S-4317, S-4322..S-4324)` · `S-4311: the counter and the section
name are one text`, `S-4312: every logged set carries its own caption`,
`S-4315: the sets control boxes the count text`, `S-4317: at 390 x 844 the bar
hugs the header and the sets control stays reachable`,
`S-4322: an empty section name leaves the counter alone`) and
`test/set_shell_widgets_test.dart` (group `Mock S-4201 SetSegmentBar` ·
`one segment per set, 48 dp tall, tap reports its index`; group
`Mock S-4325 SetSegmentBar captions` · `one caption per set, in its cell,
under a top-aligned bar`).

**Timer Control Rule**:

- timed, round, and drill entries are started from the action-row centre button (`Start`); the timer display itself is read-only
- there is no separate play button in the action row
- navigating to another set or exercise leaves a running timer running — elapsed time is wall-clock derived, so it keeps advancing and still expires on schedule while the user is elsewhere
- a paused entry (only reachable from a session persisted mid-pause) shows `Resume` in the same centre slot

**Lock Rule (live sessions)**:

- in a live session a logged set cannot be edited: its reps and weight render
  as `ValueStepperRow` rows whose buttons are dimmed and do nothing, a hold's
  weight row dims the same way once the hold is logged, and the centre control
  keeps showing `LOGGED`
- in the session editor (`editMode`) nothing is locked; its controls stay
  navigation-only with a screen-level Save

Verified by `test/logger_shell_screen_test.dart` (group `Logger shell — logged
sets are locked live (S-4216/S-4217)` · `S-4216: a logged set is read-only and
shows LOGGED`, `S-4216: edit mode leaves a logged set editable`, `S-4217: a
logged hold's weight is read-only live`, `S-4217: edit mode keeps a logged
hold's weight editable`). The dimmed button icons of the locked rows are
asserted by `test/value_stepper_row_test.dart` (group `S-4246 read-only` · `a
locked row dims its buttons`); that the locked rows do nothing is
`test/reps_screen_test.dart` (group `Reps screen — stepper rows — resistance
(S-4250..S-4256)` · `S-4252: live, a logged set is locked and an unlogged one
steps`).

**Auto-Advance Rule**:

- after a log, focus moves to the first unlogged set after the focused one; if
  every later set is logged it moves to the next exercise; on the last exercise
  it stays

Verified by `test/logger_shell_screen_test.dart` (group `Logger shell —
auto-advance (S-4215)` · `S-4215: logging set 1 moves focus to set 2`,
`S-4215: a logged set ahead is skipped`, `S-4215: the last set moves to the
next exercise`).

**Stepper Remove Rule** (rewritten by plan 41, which reversed the plan-38a
remove rule):

- the stepper's `−` deletes the set the user is looking at (the focused set);
  `+` adds a set up to the 12-entry cap
- an unlogged set that was never started is deleted at once, without a dialog
- a set that was started but not logged — a timer, interval or round still
  running or paused — asks first (`Delete running <Set|Interval|Round|Hold>?`;
  deleting it loses that progress)
- a logged set asks `Delete logged <label>?`; when the effort has only one set
  left, `−` asks `Remove Exercise?` because it deletes the whole exercise from
  the session
- after a delete the focus stays on the same position (the set that slid up) or
  clamps to the new last set; a running timer on another set of the same
  exercise keeps running and keeps its own time
- in Edit Session, edits not yet saved on later sets move with their sets, so
  Save writes each edit onto the set it was made on (`S-4909`)

Verified by `test/delete_focused_set_test.dart` (group `Delete the focused set
(plan 41)` · `S-4901: − deletes the focused unlogged set, not the last one`,
`S-4902: − on a logged focused set asks, cancel keeps it, delete removes it and
re-keys the rests`, `S-4907: an open rest of a later set keeps its own set
after a middle delete`) and `test/delete_focused_timer_test.dart` (group
`Delete the focused set — timers (plan 41)` · `S-4904: deleting a running
interval asks first; cancel keeps it running; delete drops it and its timer;
the next set is idle`, `S-4905: a running later interval keeps running and
keeps its own time after a middle delete`, `S-4906: deleting a running round
asks first`, `S-4908: the only interval, started, asks to remove the
exercise`); the all-logged and one-set confirmations are also covered by
`test/logger_shell_screen_test.dart` (group `Logger shell — sets stepper
(S-4220/S-4230/S-4231)` · `S-4220: − on an all-logged effort asks to delete a
logged set`, `S-4220: − on an all-logged effort drops the last set`,
`S-4231: one logged set left asks to remove the exercise`, `S-4230: at the
12-set cap + is disabled`).

### 7. List View vs Detail View Toggle

**List View**:
- Shows all exercises in session
- Ordering behavior:
  - Non-rolling sessions: detail navigation follows the exact same sequence as the rendered list.
  - With blocks present, block anchors define group placement in the list and detail traversal.
  - Within a block, exercises are ordered by `createdAtMs`, then `executionOrder`, then id.
  - Standalone (no-block) exercises are ordered by `createdAtMs`, then `executionOrder`, then id.
  - Rolling sessions: exercises render grouped by session block order.
- Summary stats per exercise:
  - **set**: "3 sets"
  - **timed**: "05:30 total"
  - **round**: "5 rounds"
  - **drill**: "3 holds"
- Tap exercise to enter detail view
- Inline add-exercise-and-block bar at the end of the list (centred in the empty state); there is no FAB
- Non-rolling list view does not render modality group headers.

**Detail View**:
- Single exercise focus
- Full metric editors
- Set-by-set tracking
- Back button returns to list view

**State Management**:
```dart
bool _showListView = true;  // Default to list view
```

**Navigation Flow**:
```
HomeScreen → Select Modality
  → WorkoutSessionScreen (list view)
    → Tap exercise → Detail view
      → Back → List view
        → Back → HomeScreen

HomeScreen → My Routines tile
  → MyRoutinesScreen → Tap routine
    → WorkoutSessionScreen (list view, pre-populated from routine)
      → (same flow as above)
```

---

## State Persistence Strategy

### Immediate Persistence
All metric changes persist immediately via `updateEntryValue()`.

**Why Immediate**:
- No data loss if app crashes mid-workout
- No "unsaved changes" warnings needed
- User can leave app and return without losing progress

### Logging vs Persisting
- **Persist**: Save value to repository (happens on every metric change)
- **Log**: Mark set complete, advance to next set (explicit user action)

### Timer Value Persistence
- **timed/drill efforts**: Save `_effortElapsed[key]` (seconds) on pause/log via `updateEntryValue`
- **round efforts**: Write a `RoundInstance` record — never raw observations. Fields persisted:
  - `state` — `RoundState` enum (`notStarted` | `active` | `paused` | `finished`); `finished` is terminal
  - `startedAtMs` — wall-clock epoch ms when timer started (0 when `notStarted`)
  - `pausedAtMs` — epoch ms when most recent pause occurred (`null` when not paused)
  - `totalPausedDurationMs` — cumulative pause time folded in on each `resumeRound` call
  - `finishedAtMs` — epoch ms when round ended (0 when not yet finished)
  - `actualDurationSecs` — clamped to `plannedDurationSecs * WorkoutConstants.roundActualDurationCapFactor`
  - `completed` — `true` only when round ends via natural countdown (`completeRound`); `false` otherwise
  - `plannedDurationSecs` — target round length (default: `WorkoutConstants.defaultRoundDurationSecs = 180`)

---

## Edge Cases and Error Handling

### Empty State
**Condition**: No exercises or blocks in the session.

### Loading State
**Condition**: Fetching exercises from repository
**UI**: Centered CircularProgressIndicator
**Trigger**: Initial load, after adding/deleting exercises

### Error State
**Condition**: Repository error during load
**UI**: 
- Error icon in the theme's error colour
- "Error Loading Session" title
- The plain line `Could not load your workout. Try again.` — never the exception text
- "Retry" button
**Recovery**: Retry button calls `_loadExercises()` again

Verified by `test/session_screen_build_phase_notify_test.dart`
("D-27.2 a failed session load says so in plain words and hides the
exception").

### Set Skip vs Delete
- **Skip Set**: Advance without logging via forward navigation (the segment stays unlogged)
- **Remove Entry**: The stepper's `−` deletes the set the user is looking at (the focused set; the rule since plan 41). An unlogged set that was never started goes at once; a started-but-unlogged set asks `Delete running <label>?` first; a logged set asks `Delete logged <label>?`. When the effort has **only one set**, the `−` icon is a trash-can (`Icons.delete_outline`) — confirming removes the entire exercise from the session. Tooltip text also switches from "Remove set" to "Remove exercise".
- **A deleted logged set takes its rest with it**: the rest that marked the set logged is removed and every later rest moves down one, so a set added afterwards is a new unlogged set (pre-filled from the previous set as the carry-forward does). The rest history of the deleted set disappears with it.
- Use case: Skip = "I'm moving on without logging this effort", Remove = "This entry should not exist"

Verified by `test/logger_shell_screen_test.dart` (group `Logger shell — skipped
log (S-4233)` · `S-4233: a zero-rep log leaves the segment unlogged`; group
`Logger shell — sets stepper (S-4220/S-4230/S-4231)` · `S-4231: one logged set
left asks to remove the exercise`; group `Logger polish — deleting a logged set
(S-4310, S-4319..S-4321)` · `S-4310: the set added after a delete reads
unlogged and logs cleanly`, `S-4320: deleting the set whose rest is open hides
the chip and cancels the pings`, `S-4321: removing the exercise cascades its
logged set and rest away`) and `test/set_shell_widgets_test.dart`
(group `Mock S-4204 SetCountStepper` · `a one-set exercise offers Remove
exercise with a trash icon`). The state-layer rule is
`test/entry_delete_rests_test.dart` (group
`<harness> — deleteEntry takes the rest with the entry` · `S-4301 deleting the
last set takes its rest, so a new set reads unlogged`, `S-4302 deleting the
first set moves every rest down with the sets it keeps`, `S-4303 deleting a
middle set drops its own rest and moves the rest above it down`). The
focused-set rule itself is verified in **Stepper Remove Rule** above.

### Modality Change Warning
**Trigger**: User taps different modality tile while session active
**UI**: Alert dialog
```
"Start New Session?"
"Changing modality will start a new session. Current session will not be saved."
[Cancel] [Start New]
```
**Behavior**: Confirm → End current session, create new session, navigate to new session

---

## Performance Optimizations

### State Locality
- Timer state stored in maps (O(1) lookup by key)
- No unnecessary rebuilds (setState scoped to affected widgets)

### Lazy Loading
- Exercises loaded once on screen mount
- Reload only after mutations (add, delete, update)
- No polling or background refresh

---

## Session Finalization

### Finish Workout Flow

Finishing a workout runs a deterministic shutdown sequence: local UI timers are frozen, every active or paused timer-based entry is persisted, the session is ended (idempotently), and the summary replaces the workout screen on the back-stack so Back cannot return to an active-timer view. A `_isFinishingSession` flag prevents double-tap races, and tick callbacks guard against ghost updates by checking `session.endedAtMs != null`.

Verified by `test/session_finish_timers_test.dart`.

### Edit Mode — Session Duration Editing

In edit mode (`editMode: true`) the session duration becomes editable.

- Pending duration is stored in `_pendingDurationSecs`; `_originalDurationSecs` holds the value at edit entry.
- `_hasDurationChanged()` returns `true` if the two differ — this feeds into the **Unsaved Changes** guard.
- On **Save**: `workoutState.updateSessionEndTime(_pendingDurationSecs!)` stores the end clamped to the start (D-153). Verified by `test/session_window_never_inverted_test.dart` (`S-155 writer table — every phone-owned writer leaves an ordered window`).
- On **Discard**: `_pendingDurationSecs` is reset to `_originalDurationSecs`; no repository write occurs.

Discard throws away the user's own edits but never a wrist entry that arrived
while the screen was open: the restore un-marks exactly the entries applied
after the snapshot's watermark and runs one import pass, so a set the user
logged on the wrist is still in the session after Discard. Verified by
`test/watch_session_edit_restore_late_entry_test.dart` (`S-1401` to `S-1410`).

### Unsaved Changes Dialog

Leaving edit mode with pending changes must prompt before discarding them. Pending state covers inline metric edits, structural changes (add/remove exercise or set), and a session duration edit.

Verified by `test/unsaved_changes_dialog_test.dart`.

---

## Developer Notes

### Common Pitfalls
1. **Timer Keys**: Always use `effortId-entryIndex` format (not just effortId)
   - Reason: Same exercise can have multiple timers (one per set)

2. **setState Scope**: Wrap only affected variables in setState
   - Anti-pattern: `setState(() { /* entire method */ })`
   - Better: Call method, then `setState(() { _localVar = newValue })`

3. **Timer Cleanup**: Always cancel timers in `dispose()`
   - Memory leak risk if timers survive widget lifecycle

4. **Round Persistence**: Round efforts use `RoundInstance` records, not observations
   - Never call `updateEntryValue` for round metrics — use `WorkoutState.startRound`, `pauseRound`, `resumeRound`, `endRoundEarly`, `completeRound`
   - Elapsed is always derived at read time via `RoundInstance.elapsedMs` getter — never stored as a raw counter
   - The display value comes from `_getRoundInstance(...).elapsedMs`, not from dedicated round UI maps
   - State transitions are strictly enforced by `_isValidRoundTransition()` in `WorkoutState`; `finished` is terminal
   - Rapid-tap protection: `_pendingRoundTransitions` set in `WorkoutSessionScreen` prevents concurrent duplicate transitions
   - See `WorkoutConstants.roundActualDurationCapFactor` for the safety cap on `actualDurationSecs`

### Code Organization
```
lib/features/session/
  workout_session_screen.dart
    ├── State (_WorkoutSessionScreenState)
    ├── Lifecycle (initState, dispose, _loadExercises)
    ├── Actions (_logSet, _addSet, _deleteSetAt)
    ├── Timer Management (_toggleEffortTimer, _rekeyTimerStateAfterDelete — in workout_session_timer_mixin.dart)
    ├── UI Builders (_buildHeader, _buildListView, _buildMetricWidget, _buildSetControls)
    └── Helpers (_jumpToSet, _switchExercise)

lib/widgets/session/
  inline_metric_editor.dart
    ├── State (_InlineMetricEditorState)
    ├── Value Formatting (_formatValue)
    ├── Gesture Handling (_onNumberTap)
    └── UI (tap-to-edit number display)
```

---

## Conclusion

The modality-based exercise details screen represents a **context-aware, adaptive UI pattern** that eliminates manual configuration while supporting diverse training methodologies. Key achievements:

1. **Single Implementation**: One screen serves all modalities via configuration-driven rendering
2. **Zero Learning Curve**: UI terminology and controls match user's mental model
3. **Robust State Management**: Map-based timer state prevents conflicts
4. **Progressive Disclosure**: List/detail view split balances overview and focus

This architecture demonstrates how **data-driven UI rendering** (effortKind → widget switch) combined with **domain-specific configuration** (ModalityConfig) can create a flexible system without sacrificing usability or code maintainability.

---

**Document Version**: 1.7
**Last Updated**: October 16, 2026
**Author**: Automated documentation generated from codebase analysis
**Related Docs**:
- [modality_tracking.md](modality_tracking.md) — Data layer + business logic
- [exercise_ranking.md](exercise_ranking.md) — Exercise picker sorting algorithm
- [create_new_exercise.md](create_new_exercise.md) — Create custom exercises from the picker
- [my_routines.md](my_routines.md) — Reusable workout template system


---

> **Doc freshness** — Last reconciled against source: 2026-10-16. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
