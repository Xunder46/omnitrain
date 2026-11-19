# Modality-Based Exercise UI — Set Navigation and the List/Detail Toggle

> Part of the [Modality-Based Exercise Details Screen](../modality_based_exercise_ui.md). Return to that page for the overview, the architecture, the timer lifecycle and the rest of the screen. These two sections moved here verbatim on 2026-11-19 so the main page stays well under the per-file size ceiling.

---

### 6. Set Navigation and Control

The detail view's header is one line under the exercise name:
`Exercise N / M · <section name>` — just `Exercise N / M` when the section has
no name (key `session-detail-header`).

Directly under the header, pinned outside the scroll, sits the set bar block:
one tappable segment per set / interval / round / hold (`SetSegmentBar`) with
one caption per segment under it — the logged value (`reps×weight` for a set,
`mm:ss` for an interval, hold or round — the big timers' format,
`OmniDateUtils.formatTimerDigits`, plan 44 D-5), blank for an unlogged set,
shown only when the exercise has 5 sets or fewer. The entry stepper
(`SetCountStepper`)
sits in the scroll body below the exercise's controls, away from the primary
row: a boxed full-width control with `−` on the left, the count text in the
middle (`Set 2 of 3`, `Interval 2 of 3`, `Round`/`Period 2 of 3`, `Hold 2 of 3`)
and `+` on the right.

The caption format is one rule: every logged timed, drill and round caption
reads `mm:ss` below an hour and `h:mm:ss` from it, the same
`OmniDateUtils.formatTimerDigits` the big timers read; set captions stay
`reps×weight` with no units. Verified by `test/logger_shell_screen_test.dart`
(group `Logged time captions read like the big timers (plan 44 S-5108)` ·
`S-5108: logged intervals read mm:ss and h:mm:ss`, `S-5108: a hold logged at
0 s reads 00:00`, `S-5108: a round logged early reads mm:ss`,
`S-5108: a set caption keeps reps x weight and no units`).

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

**Forward-arrow end rule** (plan 44 D-1): the forward arrow is disabled —
the same dim look the back arrow has at the first set — exactly on the last
set of the last exercise, live and in the session editor, for every effort
kind; it wakes on the next rebuild once a set or an exercise is added. The
back arrow and the entry stepper are unchanged. Verified by
`test/logger_feedback_controls_test.dart` (group `Forward arrow and rest chip
(plan 44 T2a)` · `S-5109: the forward arrow dims and stops answering at the
last set`, `S-5110: a single unlogged set keeps both arrows dead, logging
included`, `S-5111: adding a set wakes the forward arrow`, `S-5112: the
session editor dims its forward arrow at the end`, `S-5113: a not-started
interval keeps the forward arrow dead and Start live`, `S-5113: a not-started
round keeps the forward arrow dead`).

**Reps anchoring** (plan 44 D-7): on a `set` effort (live and session editor)
the visible group — the metric rows through the entry stepper — sits slightly
below the centre of the scroll area: 60 % of the spare space above it, 40 %
below, recomputed when the rest strip opens or closes; when the group does
not fit (small phone, rest strip up) it is top-anchored and the area scrolls,
with no overflow. Timer efforts keep the top anchoring. Verified by
`test/logger_feedback_layout_test.dart` (group `Reps layout and exercise title
(plan 44)` · `S-5116: reps controls sit slightly below centre, rest open or
closed`, `S-5117: a short phone with the rest open never overflows`).

**Two-line title** (plan 44 D-8): the detail view's exercise name wraps to
two lines (ellipsis after the second); the list-view title and the subtitle
line stay one line. Verified by `test/logger_feedback_layout_test.dart`
(group `Reps layout and exercise title (plan 44)` · `S-5119: the long
exercise name takes two lines in the detail header`).

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
  - **set**: "2 of 3 sets" (logged of total; a check mark at the right end of the tile once every set is logged; edit mode keeps "3 sets" and no mark; verified by `test/session_list_progress_test.dart` `S-25501` to `S-25508`) (plan 255)
  - **timed**: "05:30 total"
  - **round**: "5 rounds"
  - **drill**: "1 of 3 holds", with the same check mark when every hold is finished (`S-25505`, and `S-25509` for a hold that finishes itself while the list is showing)
- Tap exercise to enter detail view
- The same `⋮` menu has `Move up` and `Move down` (greyed at the ends): a loose exercise swaps places with the item beside it (a block counts as one item, so an exercise can pass a block), and inside a block an exercise swaps with its neighbour. Positions are renumbered in the order shown, in the live list and in Edit Session; a rolling list only moves inside a block (plan 270, `test/move_exercise_test.dart`)
- Each tile has a `⋮` menu with `Remove exercise`: it asks (`Remove Exercise?`), then takes the whole exercise and everything logged for it out of the workout, in the live list and in Edit Session; its timers stop (plan 269, `test/remove_exercise_from_list_test.dart`)
- Inline add-exercise-and-block bar at the end of the list (centred in the empty state); there is no FAB
- Non-rolling list view does not render modality group headers.

**Detail View**:
- Single exercise focus
- Full metric editors
- Set-by-set tracking
- Back returns to the list view with the exercise you left in view
  (about a third of the way down the list; after walking to another exercise
  with the arrows, the exercise you are on), in the standard, rolling and
  session editor lists. Verified by `test/session_back_to_exercise_test.dart`
  (group `S-13908 header back returns to the exercise left`).

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
