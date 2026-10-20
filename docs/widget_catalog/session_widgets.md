# Session, Picker & Presentation Widgets

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.

---

## Session Metric Widgets

### `DominantMetricWidget`

**File**: `lib/widgets/session/set_metric_widget.dart`

Unified large-metric display widget used across all effort kinds. Renders exactly **one** large metric value.

| Prop | Type | Description |
|------|------|-------------|
| `displayText` | `String` | The value to show (e.g., "10", "03:00", "Round 1\n03:00") |
| `isMultiline` | `bool` | Multi-line rendering for round display |
| `onTap` | `VoidCallback?` | Tap handler (edit reps, toggle timer) |

> **Corrected 2026-07-26 (docs audit).** This entry listed three "stub
> redirect" files kept for import compatibility —
> `lib/widgets/session/drill_metric_widget.dart`, `round_metric_widget.dart`,
> and `timed_metric_widget.dart`. **None of them exist any more.**
> `lib/widgets/session/` now contains `set_metric_widget.dart` (which is where
> `DominantMetricWidget` is actually declared), `inline_metric_editor.dart`,
> `metric_crown_widget.dart`, `duration_entry_dialog.dart`, and
> `pr_toast.dart`. Import `DominantMetricWidget` from `set_metric_widget.dart`.

### `InlineMetricEditor`

**File**: `lib/widgets/session/inline_metric_editor.dart`

Touch-optimized value input for workout environments. Tap the number to open a numeric-entry modal (the crown scrub control is present in the codebase but not rendered — see `MetricCrownWidget`).

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | `reps`, `weight`, `duration`, `rpe`, `extra-weight` |
| `currentValue` | `dynamic` | Value to display |
| `unitLabel` | `String` | Label under the value (e.g., "REPS", "LBS") |
| `emphasisTier` | `MetricEmphasisTier?` | Optional value emphasis: `hero`, `dominant`, `secondary`, `muted`; default keeps legacy displayLarge styling |
| `unitGap` | `double` | Gap between the number and the unit label in the column layout; the default is the historical spacing, and `ValueStepperRow` passes 0 so the label hugs the number |
| `showTapHint` | `bool` | When true — and the editor is not read-only — a dim `tap to type` line (key `tap-hint`) sits under the unit label; default false |
| `valueFontSize` | `double?` | Overrides the tier's font size; the ring passes `kRingDigitsFontSize` |
| `isReadOnly` | `bool` | When true: disables tap-to-edit popup. Used for live timer displays. |
| `onTap` | `VoidCallback?` | When provided, tapping the number calls this instead of opening the generic popup (e.g. timer toggle, duration dialog). |
| `onNumberTap` | `VoidCallback?` | Called on every tap of the number, before the tap's own action (popup, `onTap` or nothing) — the logger uses it to mark the control's `tap to type` hint learned (plan 44 D-6); `null` calls nothing |
| `onValueChanged` | `Function(dynamic)` | Immediate callback on value change |

**Interaction model**:
- Number tap is the sole value-change mechanism.
  - `onTap` provided → delegates to `onTap`.
  - `onTap` null and `!isReadOnly` → opens `showMetricEditPopup`.
  - `isReadOnly: true` → no interactive affordance.
- The crown scrub control (`MetricCrownWidget`) is dormant — it remains in the codebase at `lib/widgets/session/metric_crown_widget.dart` and can be re-enabled in the row without rebuilding the widget.

**Visual**: the value renders at the tier's size — `hero` (the count-up
readout, `kCountUpDigitsFontSize` in `lib/widgets/session/inline_metric_editor.dart`),
`dominant`, `secondary`, `muted` — and `valueFontSize` overrides the tier's
size. The crown is not rendered. When `isReadOnly` and `emphasisTier` are
both set, the emphasis tier wins and the value is not dimmed.

**Session context (live timed/round/drill)**: In `WorkoutSessionScreen`
detail view the live `timed` and `drill` editors render the elapsed time as
plain large digits at the `hero` tier inside a scale-down `FittedBox`, with
the unit label as the caption — `ELAPSED` while the entry is unfinished,
`COMPLETED` once it is finished; the digits read `mm:ss` below an hour and
`h:mm:ss` from it (`OmniDateUtils.formatTimerDigits`). They are read-only and
tapping the digits opens nothing — corrections happen in the session editor,
whose duration dialogs are `Edit Interval Duration` and `Edit Hold Duration`.
The live `round` editor sits inside a `TimerRing` (below) with the caption
`REMAINING` under the digits and `COMPLETED` once the round is finished; the
ring passes `valueFontSize: kRingDigitsFontSize`, and the old status label
(`RUNNING` / `STOPPED` / …) is gone. The centre button carries the timer
control (`Start`, then `Log Interval` / `Log Hold` / `Log Round`; `Resume`
for an entry restored paused) — never a tap on the value display.

Verified by `test/count_up_screen_test.dart` (group `Count-up — timed
intervals (S-4260..S-4263)` · `S-4260: an interval with no load shows digits
and no chrome`, `S-4262: the interval editor keeps its duration dialog only`,
`S-4277: a live interval's digits open nothing on a tap`; group `Count-up —
holds (S-4264..S-4270)` · `S-4264: a hold shows digits plus one weight row`,
`S-4278: a live hold's digits open nothing on a tap`, `S-4279: the hold
editor keeps its duration dialog`; group `Count-up — restored paused entries
(S-4273, S-4274)` · `S-4273: a paused interval shows its elapsed and Resume`;
group `Count-up — a finished entry reads COMPLETED (S-4402)` · `S-4402: a
finished interval swaps ELAPSED for COMPLETED`, `S-4402: a finished hold
swaps ELAPSED for COMPLETED`),
`test/round_countdown_screen_test.dart` (group `Round countdown — digits and
caption (S-4402)` · `S-4402: martial arts reads 03:00 + REMAINING with no old
chrome`, `S-4402: sports reads 03:00 + REMAINING with no old chrome`),
`test/count_up_hero_layout_test.dart` (group `S-4710 hero count-up digits` ·
`the live interval digits are 112 sp inside a scaleDown FittedBox, captioned
ELAPSED`, `the live hold digits are 112 sp inside a scaleDown FittedBox,
captioned ELAPSED`, `an interval past an hour reads 1:15:35`, `the sports
ring digits are 48 sp inside the ring chord`) and
`test/sports_emphasis_redesign_test.dart` (group `Sports effort emphasis
redesign` · `S-001 free session stopped hierarchy is correct`, `S-002 free
session running hierarchy is correct` — the ring and its caption).

---

### `TimerRing`

**File**: `lib/widgets/session/timer_ring.dart`

Countdown ring for the `round` effort: a track circle and a `primary` arc
that empties as the time runs out, with the digits centred inside it. The arc
sweeps clockwise from the top for `progress` of a full turn (1.0 = full ring,
0.0 = expired), with a round cap; colours come from
`Theme.of(context).colorScheme` only — the ready look's dim primary and the
track grey are the shared `SessionProgressColors`
(`lib/widgets/session/session_progress_colors.dart`), the same two fills
`SetSegmentBar` reads. The ring is a `StatefulWidget` — the
state owns the sweep between the screen's 1 Hz ticks.

| Prop | Type | Description |
|------|------|-------------|
| `progress` | `double` | Remaining fraction, 1.0 (nothing elapsed) down to 0.0 (expired) |
| `running` | `bool` | Whether the ring is counting down — only then does a falling progress sweep |
| `look` | `TimerRingLook` | `ready` (before Start) or `counting` (default) — see below |
| `child` | `Widget` | Centred inside the ring: the remaining-time digits |
| `size` | `double` | Largest diameter; a narrow surface shrinks it so the ring never touches the screen edges (the default size and the kept-clear inset are owned by `timer_ring.dart`) |

**Looks** (plan 44 D-4): the *ready* look — the round has not started — is a
full circle (progress 1.0) in dim primary, the set bar's focused-unlogged
segment colour, with no grey track, so it never reads as a finished round.
The *counting* look is the ring's normal look: a primary arc of `progress`
over the grey track. A round logged early keeps the counting look, frozen at
what was left (`(planned − actual) / planned`); only when the round is fully
drained — expired, completed, or logged with nothing left — is the ring the
grey track alone: the painter draws no arc at progress 0. The screen picks
the look and the progress in the round branch of `_buildMetricWidget`
(`lib/features/session/workout_session_detail_view.dart`).

**Behaviour**: while `running` a falling `progress` animates linearly over
one second between the ticks, so the ring and the digits move together; a
stopped ring and a progress that rises (the round length was just edited)
apply at once. The ring carries a `Time remaining` semantics label; the
digits are scaled down by a `FittedBox` rather than overflowing the ring, and
the box is bounded to the ring's usable chord — the kept-clear inset is
`_kRingDigitsInset` in `lib/widgets/session/timer_ring.dart`. The session
detail view passes `valueFontSize: kRingDigitsFontSize` for the digits.

Verified by `test/timer_ring_test.dart` (group `S-4401 ring progress` ·
`a full ring reads progress 1.0 with scheme colours`, `0.75 and 0.0 read back
unchanged`; group `S-4402 digits` · `the child is centred inside the ring`,
`the ring carries the remaining-time label`; group `S-4408 size` (the default
diameter and its narrow-surface clamp); group `S-4408 sweep` · `a
falling progress sweeps while running`, `a stopped ring applies the new value
at once`, `a growing progress while running is applied at once`) and
`test/round_countdown_screen_test.dart` (group `Round countdown — ring
(S-4401)` · `S-4401: a fresh 180 s round draws a full ring`, `S-4401: an
active round 45 s in shows a 0.75 ring`; group `Round countdown — ring looks
(plan 44)` · `S-5101: before Start the ring is a full dim circle with no
track`, `S-5103: Start makes the ring bright over the grey track`, `S-5104: a
paused round keeps its 0.75 fraction`, `S-5105: a round logged early shows the
120 s left at 0.6667`, `S-5106: an expired 15 s round is the grey track only`,
`S-5106: a round logged with nothing left is the grey track only`,
`S-5107: each of three rounds shows its own look`; group `Round countdown —
restored instances (S-4410, S-4411)` · `S-4410: a paused round 45 s in reads
02:15, frozen at 0.75`, `S-5105: a round logged early reads 01:00 + COMPLETED,
ring at 120/180`) and `test/session_progress_colors_test.dart` (group
`S-5106 drained ring paints the track only` — the painter draws no arc at
progress 0).

**Call site**: the live `round` branch of `_buildMetricWidget` in
`lib/features/session/workout_session_detail_view.dart` — the only `TimerRing`
in `lib/`. The session editor shows the round-length row without the ring.

---

### `SetSegmentBar`

**File**: `lib/widgets/session/set_segment_bar.dart`

Thin set-progress bar for the session exercise screen: one tappable segment per
entry of the effort — set, interval, round or hold — so the bar is identical
across every modality. Tapping a segment jumps to that entry. Each segment is
a tap cell whose height is `kSetBarCaptionedHeight` with captions and
`kSetBarPlainHeight` without them (constants in
`lib/widgets/session/set_segment_bar.dart`), the painted bar pinned to the
cell's top, so a caption under a segment lives in the same cell and no dead
space is left under the bar.

| Prop | Type | Description |
|------|------|-------------|
| `count` | `int` | Number of entries in the current effort (1..`maxEntriesPerEffort`) |
| `focusedIndex` | `int` | Zero-based index of the entry the screen is showing |
| `isLogged` | `bool Function(int)` | Whether the entry at the given index has been logged |
| `captions` | `List<String?>?` | Optional caption under each segment — the logged value, or `null` for a blank one. Rendered only when the list has exactly `count` entries and `count <= kSetBarCaptionMaxSets` (5); with 6 or more sets there are no captions and no reserved space |
| `onTap` | `ValueChanged<int>` | Called with the tapped segment's index |

**Visual**: a `Row` of `Expanded` segments; each segment's painted bar is a
thin strip with a small corner radius and no border, the same thickness on
every segment, pinned to the top of its tap cell. Three looks:
not logged (track grey), focused and not logged (dim primary), logged (full
`primary`). The first two are the shared `SessionProgressColors`
(`lib/widgets/session/session_progress_colors.dart`) — the same two fills the
countdown ring reads, so the bar and the ring cannot drift apart; the values
stay pinned by the tests. A segment that is both logged and focused shows the
logged fill. Colours come from `Theme.of(context).colorScheme` only.

**Captions**: one line under their own segment, `bodySmall`, centred,
ellipsised, in a fixed-height row that keeps its height when every caption is
blank, so the first log does not push the body down. The focused set's caption
is `OmniTheme.colors.textDominant`, the others `textSecondary` — the only focus
cue a logged, focused set carries beyond its fill. Caption keys
`set-caption-$i` (i = 0-based segment index).

**Keys and semantics**: segment keys `set-segment-$i`; each segment carries a
`Semantics` label `Set N of M, logged|not logged|current|logged, current`.

Verified by `test/set_shell_widgets_test.dart` (groups `Mock S-4201
SetSegmentBar` — the three segment-look tests, each pinning its fill, the
absent border and the uniform bar height (`S-4201`); `Mock S-4202
SetSegmentBar logged and focused` · `the label reads logged, current and the
fill is logged` (`S-4202`); `Mock S-4325 SetSegmentBar captions` · `one caption
per set, in its cell, under a top-aligned bar`, `the focused caption is
dominant, the others secondary`, `no captions without a list, with a short list
or above the set cap` (`S-4325`)) and `test/logger_shell_screen_test.dart`
(group `Logger shell — bar and chip (S-4232/S-4222)` · `S-4232: tapping a
segment jumps to that set`; group `Logger polish — header, captions, boxes,
layout (S-4311..S-4317, S-4322..S-4324)` · `S-4312: six sets drop the captions
and their space`, `S-4323: the captions row is there, blank, before a log`,
`S-4324: a logged, focused set reads dominant`, and `S-4314`, which pins the
absent border and the uniform bar height on the screen) and
`test/count_up_hero_layout_test.dart` (group `S-4711 tightened body` — the
two cell-height tests, captioned and plain, and the ring-gap test; their
names spell the cell heights, which the docs value scan may not quote).
The two shared fills are pinned per theme by
`test/session_progress_colors_test.dart` (group `S-5102 session progress
colours` · the dim-primary and track-grey assertions, which also pin the
pixel-identical values).

### `SetCountStepper`

**File**: `lib/widgets/session/set_count_stepper.dart`

Boxed full-width control that adds or removes an entry of the current effort:
`−` on the left, the count line in the middle, `+` on the right, inside an
`OmniSurface(showShadow: false)` with the control's own horizontal outer
margin. It sits in the body below the exercise's controls, away from the
primary row, and is shorter than a reps/weight row.

| Prop | Type | Description |
|------|------|-------------|
| `text` | `String` | The count line between the two buttons, e.g. `Set 2 of 3`, `Interval 2 of 3`, `Round`/`Period 2 of 3`, `Hold 2 of 3` — the caller's whole line, so the control stays modality-neutral |
| `canAdd` | `bool` | Whether another entry may be added (`false` at the per-effort cap) |
| `removeIsExercise` | `bool` | When true the `−` removes the whole exercise instead of one entry |
| `onAdd` | `VoidCallback` | Called by `+` |
| `onRemove` | `VoidCallback` | Called by `−` |
| `canRemove` | `bool` | When false the `−` button is disabled and does nothing (default `true`). Callers whose rule is narrower than `removeIsExercise` pass it instead of hiding the button — the routine editor only removes the last entry of several |
| `addKey` | `Key?` | Replaces the `+` button's key (default `set-count-add`) |
| `removeKey` | `Key?` | Replaces the `−` button's key (default `set-count-remove`) |

**Behaviour**: both buttons meet the platform minimum touch target even though
the glyphs are small. Tooltips: `Add set`, `Remove set`, `Remove exercise` (when
`removeIsExercise`, which also swaps the icon to `Icons.delete_outline`), and
`Max 12 entries` on the disabled `+` at the cap. Keys `set-count-remove` and
`set-count-add`, overridable per caller with `removeKey` / `addKey` — the
routine editor passes `routine-remove-set` / `routine-add-set`. A `canRemove:
false` `−` stays in the tree, disabled. The old separate `3` + `SETS` pair is
gone — the count text is the middle of the control.

Verified by `test/set_shell_widgets_test.dart` (group `Mock S-4204
SetCountStepper` · the tooltips/touch-target/callbacks test — its name spells
the target size, which the docs value scan may not quote — plus `add
disabled at the cap carries the cap tooltip and fires nothing`, `a one-set
exercise offers Remove exercise with a trash icon`, `addKey / removeKey
override the default button keys`, `canRemove false nulls the minus callback
and leaves plus working`, `without the new parameters the keys are
set-count-add / set-count-remove and both buttons are enabled`) and
`test/logger_shell_screen_test.dart` (group `Logger shell — sets stepper
(S-4220/S-4230/S-4231)`; group `Logger polish — header, captions, boxes,
layout (S-4311..S-4317, S-4322..S-4324)` · `S-4315: the sets control boxes the
count text`, `S-4317: at 390 x 844 the bar hugs the header and the sets control
stays reachable`).

---

### `ValueStepperRow`

**File**: `lib/widgets/session/value_stepper_row.dart`

Full-width `−  <number>  +` row for a reps, weight or duration metric: a
round step button on the left, the number in the middle, a round step button
on the right. The row is boxed in the shared `OmniSurface(showShadow: false)`
— the row owns its outer margin left/right and top/bottom, and the stepper
inside it has its own inner padding — and the number is the
existing `InlineMetricEditor`, so tapping it opens `showMetricEditPopup`
unless the caller replaces the tap with `onEditorTap`; the two buttons step
the value by `step` in the shown unit. The unit label sits directly under the
number, centred (the inner editor gets `unitGap: 0`), and when the row is
editable a `tap to type` hint (`showTapHint`, key `tap-hint`) sits under the
label; a locked row keeps the label and hides the hint.

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | `reps`, `weight` or `duration` |
| `currentValue` | `num` | The value to show, in the unit the screen displays (`int` for reps and duration, `double` for weight) |
| `unitLabel` | `String` | The unit under the number (`REPS`, `KG`, `LBS`, `ROUND LENGTH`) |
| `step` | `double?` | One step, in the shown unit (`MetricStepping.weightStepFor` for weight); optional — defaults to 15 s for `duration` and 1 otherwise |
| `isReadOnly` | `bool` | When true the buttons are dimmed and do nothing and the number is not tappable (a logged set is locked) |
| `min` | `num?` | Optional floor for the stepped value: a step that would land below it lands on it, and a row at the floor steps no further down; the ceiling stays `MetricStepCalc`'s |
| `onEditorTap` | `VoidCallback?` | When given, handed to the inner editor as its `onTap`, so tapping the number calls it instead of opening `showMetricEditPopup` (the round-length row opens the duration dialog); `null` keeps the popup |
| `showTapHint` | `bool` | Whether the `tap to type` hint shows at all; default true (the routine editor keeps it on every row, plan 44 D-13); the logger passes the control's learned flag |
| `onNumberTap` | `VoidCallback?` | Called once per tap of the number, before the tap's own action and never on `−`/`+` or a read-only row — the logger marks the control's hint learned with it (plan 44 D-6, D-12); `null` calls nothing |
| `onValueChanged` | `ValueChanged<dynamic>` | Called with the stepped value (`int` for reps and duration, `double` for weight) |

**Behaviour**: a quick tap commits at once through `onValueChanged` and keeps a
pending value, so two quick taps compose before the parent rebuilds. Press and
hold repeats the step — the first tick fires when the long press starts, then
the repeat speeds up in two stages (`ValueStepperRow.repeatInterval` owns the
schedule); the number follows the hold and `onValueChanged` is called once when
the finger lifts, and a cancelled hold also commits once. Step math goes
through `MetricStepCalc.parseAndClamp` (reps clamped to 0..999, weight to
-200..999 in the shown unit), the same clamp owner the edit popup uses; a step
that changes nothing does nothing. A read-only row's buttons do nothing and
its number is not tappable; the button icons are dimmed (`test/value_stepper_row_test.dart`,
group `S-4246 read-only` · `a locked row dims its buttons`; the circle fill's
alpha is unasserted). A lock that arrives mid-hold drops the hold without
storing. Pending is cleared when the parent's value changes; it stays when the
store takes no write (an entry with no row for the metric), so the stepped
number remains on screen until the screen next loads — unguarded (no test
drives a repository that drops the write). Keys
`value-stepper-minus-<metricType>` and `value-stepper-plus-<metricType>`;
tooltips `Decrease reps`, `Increase reps`, `Decrease weight`,
`Increase weight`, `Decrease duration`, `Increase duration`. The step buttons
are deliberately not `IconButton`s — a long-press tooltip trigger would fight
the hold-to-repeat.

**Duration mode**: a `duration` row keeps the value an `int` number of
seconds (the editor renders it as clock text), steps 15 s at a time by
default (`ValueStepperRow.durationStepSeconds`) unless the caller gives
`step`, is floored by `min`, and is capped by `MetricStepCalc.maxDurationSeconds`
(in `lib/widgets/session/metric_crown_widget.dart`); it hands `onEditorTap`
to the inner editor's `onTap` — `null` keeps the generic popup. The
step-button noun reads `duration`.

Verified by `test/value_stepper_row_test.dart` (group `S-4413 duration mode`
· `an int duration renders as clock text with its label`, `plus and minus
step 15 s and report an int`, `the duration step is 15 s when the caller
gives none`, `a step that would cross the 15 s floor lands on it`, `minus at
15 s calls nothing`, `S-4704: plus at 3600 s steps to 3615 and reads
1:00:15`, `S-4704: minus at 3615 s steps back to 3600`, `S-4704: plus at the
10-hour ceiling calls nothing`, `S-4705: 8130 s reads 2:15:30 and 135 s reads
02:15`, `S-4705: 10:00:00 still fits a 320 x 568 phone`, `onEditorTap takes
the number tap and no popup opens`, `without onEditorTap the number keeps the
generic popup`, `a read-only duration row steps nothing and taps nothing`;
group `S-4707 anatomy` · `a duration row centres its label and hint under the
number`, `a locked row hides the hint and keeps the label under the number`,
`S-4707/S-4704: the widest weight and duration values do not overflow 390 x 844`,
`a locked duration row keeps the label and hides the hint`).

Verified by `test/value_stepper_row_test.dart` (group `Plan 44 hint switch
and number tap` · `the default row shows one tap-to-type hint`,
`showTapHint: false shows no hint`, `tapping the number reports the tap once,
with no popup`, `the step buttons never report a number tap`, `a read-only
row reports no number tap`) and `test/tap_hint_learned_test.dart` (the
per-control learning rule, S-5120..S-5125 — see `docs/modality_based_exercise_ui.md`,
"Tap-to-type hint").

Verified by `test/value_stepper_row_test.dart` (groups `S-4241 reps row`,
`S-4242 weight row`, `S-4243 pending`, `S-4244/S-4245 hold`, `S-4246
read-only`, `S-4247 geometry`, `S-4258 clamped step`, `S-4259 lock mid-hold`,
`S-4248 hold teardown`, `S-4326 boxed row` · `one shadowless OmniSurface, 20/4
outside, 12/8 inside`, `S-4413 duration mode`) and `test/reps_screen_test.dart`
(group `Reps screen — stepper rows — resistance (S-4250..S-4256)`).

**Hold call site**: the session detail view uses the row for an isometric
hold's weight (`_buildHoldWeightRow` in
`lib/features/session/workout_session_detail_view.dart`) — its third call
site after the reps screen's two rows. `metricType` is `weight`; the stored
key stays `extra-weight`, which the screen converts from the shown unit to kg
inside the `onValueChanged` closure. Tapping the number opens the existing
`Edit Weight` popup (limits −200..999 in the shown unit, and the number
carries no `+` sign); the step is `MetricStepping.weightStepFor`. The row is
always visible under the hold's digits and is locked (`isReadOnly`) once the
hold is logged in a live session — never in the session editor. Its key
includes the set, so moving to another set discards a hold in progress.

Verified by `test/count_up_screen_test.dart` (group `Count-up — holds
(S-4264..S-4270)` · `S-4264: a hold shows digits plus one weight row`,
`S-4265: the hold weight steps 2.5 kg at a time`, `S-4265: a pounds
preference steps 5 lb and stores kg`, `S-4267: a logged hold locks both
weight buttons`, `S-4267: a logged hold stays editable in the editor`,
`S-4268: the hold weight number opens Edit Weight`, `S-4276: a hold dies with
its set when the arrows move focus`), `test/logger_shell_screen_test.dart`
(group `Logger shell — logged sets are locked live (S-4216/S-4217)` ·
`S-4217: a logged hold's weight is read-only live`, `S-4217: edit mode keeps
a logged hold's weight editable`) and `test/exercise_detail_emphasis_tier_test.dart`
(`S-106 hold effort weight row renders dominant tier`).

**Steps**: the step sizes live in `MetricStepping`
(`lib/core/utils/metric_stepping.dart`): `kilogramsPerStep`, `poundsPerStep`,
`repsPerStep`, and `weightStepFor(unit)`, which returns the weight step in the
shown unit. A test pins the numbers to the watch's `WatchMetricStepping`
detents, so a crown detent and a phone tap move the same amount; phone code
never imports `lib/watch`.

Verified by `test/metric_stepping_test.dart` (group `S-4240 MetricStepping`).

**Round-length call site**: the live `round` branch of the session detail
view uses the row for the round length — `metricType: 'duration'`, inline
label `ROUND LENGTH`, `min: 15`, `onEditorTap` opening
`showDurationEntryDialog` (`Edit Round Duration`, `Edit Period Duration` in sports) — and locks it
(`isReadOnly`) while the round runs, mid-round or finished. A live change
writes the edited round and every later round that has not started
(`WorkoutState.updatePlannedDurationFrom`); the session editor shows the same
row without the ring. Verified by `test/round_countdown_screen_test.dart`
(group `Round countdown — length row (S-4403, S-4413)` · `S-4403: + adds 15 s
to the round length (03:15)`, `S-4413: − at 00:15 stays at 00:15`, `S-4403:
the row number opens the duration dialog`, `S-4403: the row is read-only
while the round runs`; group `Round countdown — layout and edit mode
(S-4408, S-4409)` · `S-4409: edit mode shows the length row and no ring`),
`test/state_test.dart` (`round: updatePlannedDurationFrom reaches the later
unstarted rounds`, `round: updatePlannedDurationFrom keeps the running round
its length`) and `test/round_planned_duration_parity_test.dart` (groups
`Mock` and `Hive` · `S-4412 a finished round keeps its length, the later ones
follow`, `S-4412 a running round keeps the length it started with`).

---

### `MetricCrownWidget`

**File**: `lib/widgets/session/metric_crown_widget.dart`

**Status: dormant — not rendered anywhere in `lib/`.** A rotatable thumb-wheel control that
`InlineMetricEditor` does not use in any interaction path. Its value-step maths live in
`MetricStepCalc`, which *is* live (see below). Whether this widget should be wired up or deleted
is an open product decision, not a documented behaviour.

### `showMetricEditPopup`

**File**: `lib/widgets/session/metric_crown_widget.dart` (top-level function)

Opens an `AlertDialog` for exact numeric entry of a metric value.

```dart
Future<void> showMetricEditPopup(
  BuildContext context, {
  required String metricType,
  required dynamic currentValue,
  required String unitLabel,
  required Function(dynamic) onValueChanged,
})
```

- Pre-fills field with formatted current value; selects all text on open.
- Confirm ("Ok"): parses + clamps → `onValueChanged` → closes.
- Barrier tap (outside dialog): closes without calling `onValueChanged`. There is NO Cancel button.
- Empty or unparseable text → treated as dismiss (no value change).
- Keyboard: `signed: true` for `weight`/`extra-weight`; `signed: false` for all other metric types (e.g., `reps`).
- Ok button has explicit `shape: RoundedRectangleBorder(borderRadius: OmniTheme.buttonUtilityRadius)`.

Verified by `test/crown_control_tap_to_edit_test.dart` (parse, clamp, rounding
and the dialog title).

---

### `showDurationEntryDialog`

**File**: `lib/widgets/session/duration_entry_dialog.dart` (top-level function)

Shared h/m/s duration-entry dialog. Used by `WorkoutSessionScreen` (both live and edit modes) and `RoutineSetupScreen` (round effort duration targets).

```dart
Future<int?> showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
  int? maxSecs,
})
```

- Returns confirmed duration in whole seconds (`h*3600 + m*60 + s`), or `null` if dismissed.
- Three `TextField` instances for hours, minutes, seconds. Pre-filled from `initialSecs`.
- `maxSecs`: when given, the confirmed duration is clamped to it; the three
  round-length callers (live, session editor, routine editor) pass
  `MetricStepCalc.maxDurationSeconds`, the others pass nothing.
- Single "Ok" `FilledButton`. No Cancel button. Barrier tap dismisses without applying.
- `TextEditingController`s are deferred-disposed shortly after the
  dialog closes (inline delay in
  `lib/widgets/session/duration_entry_dialog.dart`) to avoid
  use-after-dispose errors.

Verified by `test/tap_to_edit_unification_test.dart` (group `Duration dialog
ceiling (maxSecs)` · `U-19: over-ceiling input is clamped to maxSecs`,
`U-20: no maxSecs leaves the value unchanged`, `U-21: value under maxSecs is
returned unchanged`).

**Usage**: Wire to `onTap` on `InlineMetricEditor` when `metricType == 'duration'`.

---

### `MetricStepCalc`

**File**: `lib/widgets/session/metric_crown_widget.dart` (static class)

Shared utility for value-adjustment math and popup parsing. Used by both `MetricCrownWidget` and `showMetricEditPopup`.

- `MetricStepCalc.apply(metricType, currentValue, deltaY)` — drag step math (identical to previous `InlineMetricEditor._calculateNewValue`).
- `MetricStepCalc.parseAndClamp(metricType, text)` — parse popup input, clamp to metric range, return typed result (`int` for reps, `double` for others). Returns `null` if unparseable.
- `MetricStepCalc.maxDurationSeconds` — the duration ceiling for the steppers
  and the typed popup; `showDurationEntryDialog` callers pass it as `maxSecs`.

### `SessionDistanceCard`

**File**: `lib/widgets/session/session_distance_card.dart`

The Session Summary's DISTANCE card. Renders one `DistanceRowModel` per entry that carries a
distance; the screen builds the models, so the card reads no state and holds no distance rule.
Presentation-only: it renders the name, value text and unit label it is given, and the estimate
marker is a suffix of the unit label rather than a flag of its own. An entry with no distance is
rendered as `absentValue`, never as a zero. Rows are tap-to-edit — the callback is the caller's —
and the card says so: a hint above the rows reads `Tap a row to enter or correct it.` and each row
ends with a pencil. Hides itself when its row list is empty, so the hint cannot appear without rows.
Verified by `test/session_summary_distance_test.dart` (`S-3213 the card says how to edit a row,
above the rows`, `S-3213 a session with no distance rows shows neither the card nor the hint`,
`S-3214 every row ends with a pencil, and the row still opens the editor`, and the narrow-width
fit guard `S-3215`).

See [Session Summary](../session_summary.md#distance) for what the section lists and
[Distance Source & Pairing](../distance_source.md) for what a stored distance means.

### `PRToast`

**File**: `lib/widgets/session/pr_toast.dart`

Static factory for the in-session "new PR" celebration `SnackBar`. Two axis variants share one
visual treatment: a weight-axis toast for loaded-exercise e1RM records and a reps-axis toast for
bodyweight max-reps records.

**It is the one exception to the shared `OmniMessage` look**: the celebration toast keeps its own
`SnackBar` construction by design, and the message-look scan lets the `PRToast.` argument through.
Verified by `test/ui_standards_contract_test.dart` (group `S-2702 one message look`: `the scan
flags a raw bar and lets the PRToast argument through`).

**The toast never asks the user to dismiss it.** There is no `action:` field, it auto-dismisses,
and it floats rather than displacing the bottom controls — the user can keep logging through it.
A celebration that interrupts logging would defeat the point of celebrating.

**PR definition is shared, not local.** The in-session check uses the same
`StatsProgressService.epley1RM` / `getAllTimeBestE1RM` helpers for the weight axis and
`getAllTimeBestReps` for the reps axis that the Stats screen and the Session Summary use. There is
exactly one PR definition per axis; all three surfaces change together.

Triggered from `WorkoutSessionScreen._logSet()`, gated on `set`-kind efforts, suppressed in edit
mode, and fired on a strict `>` against both the standing best and the session's running best.

### `EffortRatingSheet`

**File**: `lib/widgets/session/effort_rating_sheet.dart`

The session effort rating question, for every phone surface that asks it: the Session Summary's
automatic prompt and its EFFORT row's add/change control. `EffortRatingSheet.show` decides only
whether the question must be answered (`mustAnswer`); where the answer goes is the caller's
`onRated`, so the sheet writes nothing and the caller owns the rating — `WorkoutState` for a
session in history.

**Shared, so both copies ask one question.** The question, the scale and the end labels are held
to `watch/contract/watch_effort_rating_contract.json`, the file the wrist's copy is held to.
Verified by `test/watch_effort_rating_copy_parity_test.dart` (`S-287`). The rules the
session-summary caller applies are in [Session Summary](../session_summary.md) ("Effort Rating
Capture"); the wrist's own ask is in [Watch Session Capture](../watch_session_capture.md).

### `MusclePicker`

**File**: `lib/widgets/exercise/muscle_picker.dart`

The exercise editor's muscle section: the fixed taxonomy rows of chips (each region row starting
with a `Whole <region>` chip) plus the `Main: …` / `Assists: …` summary lines.

**Presentation only** — it holds no state, reads no repository and never persists. Inputs:

| Prop | Type | Description |
|------|------|-------------|
| `groups` | `List<MuscleGroup>` | Names by id; an id missing here gets no chip, the summary still names it from `MuscleTaxonomy` |
| `selection` | `MuscleSelection` | The roles the host owns and renders |
| `onTap` | `ValueChanged<String>` | Called with the tapped chip's group id; the host cycles the selection |

Row order comes from `lib/core/utils/muscle_display.dart` (`kMuscleStandaloneIds`
for the standalone row, `kMuscleRegionOrder` for the region rows). Chip keys
`muscle_chip_<id>`, summary keys `muscle_summary_main` / `muscle_summary_assists`, hint key
`muscle_picker_hint`. Verified by `test/muscle_picker_test.dart` (`S-3 the six
row labels run top to bottom in plan order`, `S-12 a group id missing from
groups is skipped and still named`).

---

---

## Picker Dialogs

### `ExercisePickerScreen` (was `ExercisePickerDialog`)

**File**: `lib/features/exercise/exercise_picker_screen.dart`

> **Corrected 2026-07-26 (docs audit).** This entry described an
> `ExercisePickerDialog` modal at
> `lib/widgets/pickers/exercise_picker_dialog.dart`. **That class and file no
> longer exist** — `lib/widgets/pickers/` holds only
> `metric_chooser_dialog.dart` and `modality_picker_dialog.dart`. Exercise
> selection is now a **full-screen page push**, not a modal dialog:
> `OmniNavigator.push<Exercise>(context, (_) => ExercisePickerScreen(...))`,
> which returns the selected `Exercise` on pop (or `null` if dismissed).

Full-screen exercise search and selection. Receives `sessionModality` to rank
exercises by relevance.

**Key features**:
- Real-time search with `TextField`, filtered and ranked through `FuzzySearch.filterAndRank`
- Exercises ranked by `getExercisesRankedForModality()` (relevance score)
- Filter by discipline or muscle group; the muscle filter is one list grouped
  by region (`muscleFilterEntries` in `lib/core/utils/muscle_display.dart`),
  and each row shows the exercise's main (primary) muscles as chips
  (verified by `test/muscle_filter_picker_test.dart`, groups
  `S-2: Muscle filter grouped by region` and `S-3 / S-9: rows show main
  muscles only`)
- Empty-state "New Exercise" creation: when the filtered list is empty, the
  `No exercises found` `OmniEmptyState` carries an outlined `New Exercise`
  button (`exercise_picker_new_button`) that pushes `ExerciseEditorScreen` with
  the session modality prefilled via `contextModality`; on return the created
  exercise's name is placed in the search field and the list re-searches
  (verified by `test/screen_widget_test.dart`, group `ExercisePickerScreen` ·
  `S-4108: empty results offer New Exercise; a populated list does not`,
  `S-4109: the button opens the editor with the session modality`,
  `S-4110: a saved exercise lands in the picker search field and list`). With
  any result listed the button is not shown, and the picker has no top create
  button (`S-4101: no New Exercise button; search field comes first`) —
  creating from the library lives on `ExerciseLibraryScreen`'s header `+`
- Returns the selected `Exercise` on pop

Pushed from `WorkoutSessionScreen`,
`RoutineSetupScreen`, and the save-as-routine sheet on
`SessionSummaryScreen`. (`SessionOverviewScreen` also pushes it, but that screen
is not reachable from the app — no code in `lib/` builds it.)

### `MetricChooserDialog`

**File**: `lib/widgets/pickers/metric_chooser_dialog.dart`

Modal dialog for choosing a tracking method. Shown in Free Training mode and routine creation.

**Key features**:
- Displays only capabilities the selected exercise supports
- Each capability shown as tappable tile with icon and label
- Returns chosen metric string (e.g., `'time'`, `'reps'`, `'hold'`, `'rounds'`)

### `ModalityPickerDialog`

**File**: `lib/widgets/pickers/modality_picker_dialog.dart`

Modal dialog for selecting a modality for an exercise being added.

**Where it appears**:
- Live Free Training sessions (null modality)
- Routine building when the routine's **Focus Modality is "Mixed / Not set"** (null)
- Per-exercise `Change Tracking` override on an already-added exercise (both focus-set and Mixed routines)

**Where it does NOT appear**:
- Live Resistance / Cardio / Sports / Isometric sessions (the session's modality is already known)
- Routine building when the routine's Focus Modality is set — the new exercise silently inherits the focus modality's `effortKind`

**Key features**:
- Shows the four modalities (Cardio, Resistance, Sports, Isometric); there is no "General" option
- Returns `(true, String? modality)` record when the user picks an option:
  - Specific modality: `(true, 'cardio_endurance')` etc.
- Returns `null` when the user cancels (so callers can distinguish cancel from a pick)
- Callers use `showDialog<(bool, String?)>` and check for `null` before destructuring

---

---

## Presentation Models

### `UiSetData`

**File**: `lib/widgets/models/ui_set_data.dart`

Mutable presentation-layer data class for set tracking. **Not a persistence model.**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier |
| `exerciseId` | `String` | Parent exercise |
| `reps` | `int` | Mutable — current reps value |
| `weight` | `double` | Mutable — current weight value |
| `duration` | `int` | Mutable — current duration in seconds |
| `timestamp` | `DateTime` | When created |

Used by `WorkoutSessionScreen` and `RoutineSetupScreen` for ephemeral UI state.

---

> **Doc freshness** — Last reconciled against source: 2026-10-15. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
