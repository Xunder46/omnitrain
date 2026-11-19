# Plan 38e — Routine editor: the exercise detail screen uses the same bar, rows and controls as the live screen

Status: SEEDED by the lead on 2026-10-16; plan completed by the architect 2026-10-16; NOT STARTED. Last PR of series 38 (`docs/plans/2026-10-15-38-logger-rework-series.md`). The live screens (38a-38d, 38f) are built and uncommitted in the working tree; build on top of them. Owner decisions that bind: O-7 (session editor and routine create/edit screens match the live screen wherever the same control appears), O-11 (weight only on resistance sets and isometric holds, never on cardio intervals or rounds), O-13 (captions stay), O-14 (no approval needed between PRs). Scenario ids `S-45xx` (grep-check free before use). Not authorised to commit: the owner commits; never push.

## Where the same controls appear (verified 2026-10-16)

- Session editor (`WorkoutSessionScreen` with `editMode: true`): ALREADY on the shared pieces: the bar, the boxed reps/weight rows, the hold weight row, the round length row (no ring), the sets control with `Set X of Y` (38a, 38b, 38c, 38d, 38f). Nothing to build there except a guard that it stays so (S-4501).
- Routine create/edit: `lib/features/routine/routine_setup_screen.dart` (1673 lines) `_buildDetailView` (`:606-703`) is the only screen with these controls: the one-exercise detail with `InlineMetricEditor`s (`_buildMetricWidget :1263-1405`), a `−  Set X of Y  +` row with `InkWell`s keyed `routine-remove-set` / `routine-add-set` (`_buildSetProgress :1407-1520`), a dots row (`_buildSetIndicator :1522-`), and a Previous/Next arrow row (`_buildSetControls :1573`). It still looks like the pre-38 live screen.

## Goal and acceptance (what the user sees on the routine's exercise screen)

- A1. Header: the title is the exercise name; the one subtitle line reads `Exercise N / M · <block name>` (today the subtitle is `Exercise N / M` and the block name and the exercise name are repeated in the body as small text and a headline: those two body lines are removed).
- A2. A pinned set bar directly under the header (`SetSegmentBar`, no logged state: the focused set is the dimmer accent, the others grey; no captions), tap jumps to that set (as the dots did). The dots row and its helper are removed. With one set the bar still shows one segment.
- A3. Resistance (`set`): reps and weight as two boxed full-width `ValueStepperRow`s (− left, + right, tap the number for the existing popup, hold to repeat, weight step 2.5 kg / 5 lb), exactly as on the live screen; targets are read and written as today (reps `targetInt`, weight canonical kg `targetMin`).
- A4. Isometric hold (`drill`): one boxed weight row (the `ValueStepperRow` weight row of 38c), writing the same `extraWeight` target as today.
- A5. Cardio interval (`timed`): NO weight row (O-11). The detail body shows no editable value (an interval has no other target); only the bar and the sets control appear. Stored interval `extraWeight` targets of old routines stay in the data and are ignored by the screen.
- A6. Rounds and periods (`round`): one boxed `ValueStepperRow` for the round length (`duration` mode, 15 s step, minimum 15 s, tap the number opens `showDurationEntryDialog`, caption `ROUND LENGTH`); the big `ROUND n` / `PERIOD n` heading is removed (captions stay, O-13); it writes the same `roundDuration` and `rounds: 1` targets as today (keep the second `setTargetValue` call). No ring (nothing is running).
- A7. Sets control: the boxed `SetCountStepper` (38f) below the controls with `Set 2 of 3` / `Interval` / `Round` / `Period` / `Hold` in the middle replaces the `−  Set X of Y  +` row. Rules as today: `+` adds a set (max 12, tooltip `Max 12 entries` at the cap); `−` removes the LAST set, only when there is more than one set and the focused set is the last one (otherwise `−` is disabled, never a dialog); tooltips `Add set` / `Remove set`.
- A8. Unchanged: the Previous Set / Next Set arrow row, the list view, saving, targets storage, routine start (template to session), the watch routine sync.
- A9. `flutter analyze` not above the Phase 0 baseline (0 errors, 182 today); `flutter test` not below the Phase 0 count plus new tests minus removed (list them); no allowlist entry, no ratchet raised, no data-model or repository-interface change.

## Open owner questions (reported at the end, defaults applied)

- Q-1 Routine screens show NO values under the bar (nothing is logged there). Say if you want the planned values (`10×60`) under the bars like the live screen.
- Q-2 A cardio interval's detail is now empty apart from the bar and the sets control (O-11 removed its only target).

## Decision Ledger (to be completed by the architect against the current code)

- D-1 Reuse `SetSegmentBar`, `SetCountStepper`, `ValueStepperRow` (38a/38b/38d/38f APIs: read their constructors; extend only with optional parameters). The routine keys `routine-remove-set` and `routine-add-set` are read by `test/screen_widget_test.dart`, `test/pr2_launch_quality_hotfix_test.dart` and `test/resistance_emphasis_redesign_test.dart`: either `SetCountStepper` takes optional `addKey` / `removeKey` (preferred, default the current `set-count-*` keys) or those tests migrate to the new keys; the architect picks and lists every test.
- D-2 `SetCountStepper` must support a disabled `−` (routine rule A7) if it does not already: optional `canRemove` (default true).
- D-3 `ValueStepperRow` `weight` step from `MetricStepping.weightStepFor(preferredWeightUnit)`; reps default step 1; duration mode from 38d (`min: 15`, `onEditorTap`). Values convert with the screen's existing `_fromCanonicalWeight` / `_toCanonicalWeight`.
- D-4 Layout like the live screen: header (`OmniBackHeader` with the merged subtitle), the bar pinned directly under it, a scrolling body with the controls then the sets control, the arrows row pinned at the bottom as today. Measure with a throwaway widget probe AND look at the device: the live screens twice hid a control below the fold that only the device showed (widget-test fonts are not the app's).
- D-5 `_buildSetProgress`, `_buildSetIndicator` and the removed in-body texts are deleted; any helper they orphan is removed.
- D-6 Import swap in `routine_setup_screen.dart`: add `set_segment_bar.dart`, `set_count_stepper.dart`, `value_stepper_row.dart`, `../../core/utils/metric_stepping.dart`; remove `../../widgets/session/inline_metric_editor.dart` — grep this run shows `InlineMetricEditor`/`MetricEmphasisTier` are used only inside `_buildMetricWidget`; `OmniSurface` (:359, :1106) and `OmniTheme` are used elsewhere, their imports stay.
- D-7 The `rounds: 1` second `setTargetValue` call (today only on the dialog path) is kept and shared by both write paths (dialog and stepper) via one `_setRoundLength` helper, so both leave the same target shape.

## Readers to migrate (completed by the architect; every row read this run)

| # | Reader | What it reads | Verdict | Change |
| --- | --- | --- | --- | --- |
| 1 | `screen_widget_test.dart:1379-1381, :1592-1595, :1265-1310, :1756-1775`; `pr2_launch_quality_hotfix_test.dart:616-640` | keys `routine-add-set`/`routine-remove-set`, `Set 1 of 1`→`Set 2 of 2`, `LBS` weight editor, `TIME` findsNothing + `Interval 1 of 1`, tooltips `Next Set`/`Previous Set` | survives | keys kept via `addKey`/`removeKey`; disabled `−` stays in the tree; weight row keeps `_preferredWeightUnitLabel`; `Interval 1 of 1` is now the stepper text; arrows untouched (A8) |
| 2 | `screen_widget_test.dart:1700-1745, :1791-1810, :1828-1845, :1864-1893` | timed `InlineMetricEditor` + `EXTRA KG` (#2 named "shows no metric editor" — stale name); drill `HOLD TIME` findsNothing + `EXTRA KG` + `Hold 1 of 1`; round `DURATION` + `ROUND 1` | BREAKS (A5/A4/A6) | timed: no editor (`findsNothing`), seeded `extraWeight` target unchanged; drill: `EXTRA KG` → `find.text('KG')`, rest survives; round: `ROUND LENGTH` findsOneWidget, `ROUND 1` findsNothing |
| 3 | `resistance_emphasis_redesign_test.dart:258-266, :635-649`; `sports_emphasis_redesign_test.dart:403-414, :510-530`; `timed_emphasis_redesign_test.dart:421-447` | `_triggerRoutineAddSet` reads the `InkWell` by key; `Icon` colour `withAlpha(89)`; `_expectDotColors(primaryCount: 0, minNeutralCount: 2)`; `PERIOD 1` colour + duration editor dominant + `Period 1 of 1`; timed AND drill each show one editor | BREAKS | read the `IconButton`, invoke `onPressed` (guard null); assert resolved `foregroundColor` == `onSurface.withAlpha(115)` (session leg :560-566) or drop; segments `set-segment-0/1` fills; `PERIOD 1` → `ROUND LENGTH` findsOneWidget, keep duration-dominant + `Period 1 of 1`; split timed (no editor) from drill (one, in the weight row) |
| 4 | `exercise_detail_emphasis_tier_test.dart:541` (S-108); `tap_to_edit_unification_test.dart:214-266` (U-06); `crown_control_tap_to_edit_test.dart:599-637` (T-16); `header_standardization_test.dart:509-540`; `interaction_flow_test.dart:2036-2200`; `routine_unsaved_changes_guard_test.dart`; `capitalization_defaults_test.dart:80`; `set_shell_widgets_test.dart:355-500` | editor tiers dominant; duration tap opens the h/m/s dialog; header/navigation/list; stepper unit tests | survive | editors keep `metricType` + dominant tier, `onEditorTap` wired; optional stepper params default to today's behaviour, new unit tests go here (P1) |
| 5 | Docs: `my_routines.md:289`; `widget_catalog/session_widgets.md:182-218`; `modality_based_exercise_ui.md:86`; `navigation_and_screens.md:191` | routine-editor wording; `SetCountStepper` entry; ROUND/PERIOD wording; table row | update 2 | D phase: rewrite :289, document the new params; :86 still true; :191 no change |

## Feature invariants (this plan only; project-wide rules stay in docs/global_conventions.md)

- O-7 parity: every control the routine detail shows is the shared piece (`SetSegmentBar`, `ValueStepperRow`, `SetCountStepper`), never a re-styled copy.
- O-11 + identical writes: weight rows only for `set` and `drill` (`timed`/`round` never render one even when old data carries `extraWeight` targets — stored rows stay untouched); reps `targetInt`/`unitReps`; weight and extraWeight canonical kg `targetMin`/`unitKg`; round `roundDuration` `targetInt`/`unitSeconds` plus `rounds: 1`/`unitRounds`.
- The keys `routine-add-set` / `routine-remove-set` survive on the shared `SetCountStepper` (three test files read them); no data-model, repository-interface or watch change (A8).

## Existing-functionality impact (searches run this run)

- `_buildDetailView` body and `_buildMetricWidget` → routine tests (table above) → layout replaced, rows become `ValueStepperRow`s → S-4502..S-4509.
- `_buildSetProgress`/`_buildSetIndicator` → key/dot tests → deleted (D-5) → S-4510, S-4511, S-4503.
- `SetCountStepper` (shared) → session screens; `test/set_shell_widgets_test.dart:355-500` → optional params only; defaults reproduce today's output → S-4501 + existing unit tests. Session editor (38a-38f screens) and watch routine sync (reads the same `TemplateTarget` rows; write calls unchanged) → untouched; watch code not read this run (not checked) → S-4501.

Grep: `_buildSetProgress` / `_buildSetIndicator` occur only in `routine_setup_screen.dart` (:671, :679, :1407, :1522) — no other lib/ user.

## Current code (quoted; `// …` elides; anchors verified this run)

```dart
// _buildDetailView :606-703 (abridged): :607 efforts = currentEfforts; :612-621
// locals effort/exercise/segment/targets/setCount/canAddSet/exerciseName
// (getSegmentForEffort, getEffortTargets, _getSetCount, maxEntriesPerEffort cap).
// :626-632 Scaffold(extendBody: true, extendBodyBehindAppBar: true, appBar:
// OmniBackHeader(title: exerciseName,
//   subtitle: 'Exercise ${_currentExerciseIndex + 1} / ${efforts.length}',
//   onBack: () { setState(() => _showListView = true); _scrollListToBottom(); })).
// :635-679 body SafeArea > Stack > Column > Expanded > SingleChildScrollView(
// padding h20 v8) > Column[Text(segment?.name ?? 'Block', bodySmall) :650,
// SizedBox(6), Text(exercise?.name ?? 'Unknown Exercise', headlineSmall w600) :659,
// SizedBox(24), Center(_buildMetricWidget(effort, targets, theme)) :667, SizedBox(16),
// Center(_buildSetProgress(setCount, effort, canAddSet, theme)) :671, SizedBox(12),
// Center(_buildSetIndicator(setCount, theme)) :679, SizedBox(80)],
// :687-695 Positioned(left:0, right:0, bottom:0) > SafeArea(top:false) >
// Padding(all:20) > _buildSetControls(setCount, effort).
// _buildSetProgress :1407-1520 (abridged; add-side beyond :1470 read earlier this
// run, not re-read after compaction — recorded: Tooltip 'Add set'/'Max 12 entries'
// > InkWell key routine-add-set, onTap _addSet): :1407-1411 signature
// (int totalEntries, TemplateEffort effort, bool canAddSet, ThemeData theme);
// :1413-1429 label switch ('set'→'Set n of m'; 'timed'→'Interval n of m'; 'round'→
// (effort.modality ?? _exerciseCache[...]?.modality ?? currentTemplate?.focusModality)
// == 'sports' ? 'Period n of m' : 'Round n of m'; 'drill'→'Hold n of m'; default
// 'Set n of m'); :1431 canRemove = totalEntries > 1 && _currentSet == totalEntries;
// :1433-… LayoutBuilder > Row(center): Tooltip('Remove set') > InkWell(key
// routine-remove-set, onTap: canRemove ? () => _deleteLastSet(effort) : null,
// customBorder: CircleBorder(), child: Container(50×50, Icon(Icons.remove, 24,
// color: canRemove ? onSurface.withAlpha(89) : onSurface.withAlpha(38)))),
// Expanded(Text(label, centre, compact letterSpacing)), then the recorded add side.
// _buildSetIndicator :1522-1571 (read earlier this run; abridged): a Row of dots —
// 10 dp circles (14 dp focused), GestureDetector onTap _jumpToSet(index+1), sports-round
// accent colour; deleted by this plan, internals moot.
// _buildSetControls :1573-1596 (stays): Row spaceBetween of two _buildArrowButton(
// 'Previous Set'/'Next Set'); _previousSet :1598, _nextSet :1602, _jumpToSet :1608,
// _addSet :1614 (cap maxEntriesPerEffort), _deleteLastSet :1627 (removeLastSetForEffort).
// _getSetCount :1224-1232, _getTargetInt :1234-1245, _getTargetDouble :1247-1260,
// _fromCanonicalWeight/_toCanonicalWeight/_preferredWeightUnitLabel (all stay; read
// earlier this run): kg ↔ display unit around UnitFormatter._kgToLbs (unit_formatter.dart:4
// = 2.20462); label 'KG'/'LBS' from settingsState.
// _buildMetricWidget :1262-1404 (seed says :1263-1405; the signature opens :1262).
// Skeleton; each case's exact label and write; reps defaults ?? 10, roundDuration
// ?? 180; round modality chain as in _setCountText below:
Widget _buildMetricWidget(TemplateEffort effort, List<TemplateTarget> targets,
    ThemeData theme) {
  final setIndex = _currentSet - 1;
  switch (effort.effortKind) {
    case 'set':   // Column(SizedBox(12), InlineMetricEditor('reps', reps, 'REPS',
                  //   dominant, → setTargetValue(effort.id, MetricIds.reps,
                  //   MetricIds.unitReps, setIndex, targetInt: value as int)),
                  //   InlineMetricEditor('weight', weight, _preferredWeightUnitLabel,
                  //   dominant, → setTargetValue(effort.id, MetricIds.weight,
                  //   MetricIds.unitKg, setIndex, targetMin: _toCanonicalWeight(v))))
    case 'timed': // InlineMetricEditor('extra-weight', timedExtraWeight,
                  //   'EXTRA $_preferredWeightUnitLabel', dominant, →
                  //   setTargetValue(effort.id, MetricIds.extraWeight, MetricIds.unitKg, setIndex, targetMin: _toCanonicalWeight(v)))
    case 'round': // Text('$roundLabel $_currentSet', displayLarge w300, ls -2,
                  //   displayMedium size, textSecondary) + SizedBox(12) +
                  //   InlineMetricEditor('duration', roundDuration, 'DURATION',
                  //   dominant, onTap: showDurationEntryDialog(context,
                  //   title: 'Edit Round Duration', initialSecs: roundDuration)
                  //   then setTargetValue(roundDuration/unitSeconds, result) AND
                  //   setTargetValue(rounds/unitRounds, 1); onValueChanged: (_) {})
    case 'drill': // InlineMetricEditor('extra-weight', extraWeight,
                  //   'EXTRA $_preferredWeightUnitLabel', dominant, →
                  //   setTargetValue(effort.id, MetricIds.extraWeight, MetricIds.unitKg, setIndex, targetMin: _toCanonicalWeight(v)))
    default:      // Text('—', style: theme.textTheme.displayLarge)
  }
}
```

## Shared-widget fit and the exact extensions (constructors read this run)

- `SetSegmentBar` and `ValueStepperRow` (`super.key` at :70) fit as-is — bar: `isLogged: (_) => false` (focused `primary.withAlpha(115)`, others `onSurface.withAlpha(51)`), `captions` omitted; rows: reps (default step 1), weight (`step: MetricStepping.weightStepFor(...)`), duration (`min: 15`, `onEditorTap` → dialog); no extension to either.
- `SetCountStepper`: two gaps (D-1, D-2) → fields `final Key? addKey; final Key? removeKey; final bool canRemove;`, constructor gains `this.addKey, this.removeKey, this.canRemove = true,`; build uses `key: removeKey ?? const Key('set-count-remove')` with `onPressed: canRemove ? onRemove : null`, and `key: addKey ?? const Key('set-count-add')`. Tooltips already correct (`Remove set` / `Add set` / `Max 12 entries`); `removeIsExercise` stays required (the routine passes `false`).

## Exact replacement code (compile-ready; every symbol verified this run)

```dart
// ── imports: ADD these four; REMOVE ../../widgets/session/inline_metric_editor.dart
import '../../core/utils/metric_stepping.dart';
import '../../widgets/session/set_count_stepper.dart';
import '../../widgets/session/set_segment_bar.dart';
import '../../widgets/session/value_stepper_row.dart';

// ── _buildDetailView :626-703 — appBar and body replaced ────────────────────
      appBar: OmniBackHeader(
        title: exerciseName,
        subtitle: 'Exercise ${_currentExerciseIndex + 1} / ${efforts.length}'
            ' · ${segment?.name ?? 'Block'}',
        onBack: () { setState(() => _showListView = true); _scrollListToBottom(); },
      ),
      body: SafeArea(child: Stack(children: [
        Column(children: [
          // A2: pinned under the header, outside the scroll view — same
          // structure as workout_session_list_view.dart:806-812.
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SetSegmentBar(count: setCount, focusedIndex: _currentSet - 1,
              isLogged: (_) => false, onTap: (index) => _jumpToSet(index + 1))),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            child: Column(children: [
              _buildMetricWidget(effort, targets, theme),
              const SizedBox(height: 16),
              SetCountStepper(text: _setCountText(setCount, effort),
                canAdd: canAddSet, removeIsExercise: false,
                canRemove: setCount > 1 && _currentSet == setCount,
                addKey: const Key('routine-add-set'),
                removeKey: const Key('routine-remove-set'),
                onAdd: () => _addSet(effort), onRemove: () => _deleteLastSet(effort)),
            ]))),
        ]),
        Positioned(                    // unchanged, :687-696
          left: 0, right: 0, bottom: 0,
          child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(20),
            child: _buildSetControls(setCount, effort)))),
      ])),
```

```dart
// ── new/changed methods (same extension as _getTargetInt) ───────────────────
String _setCountText(int totalEntries, TemplateEffort effort) {
  switch (effort.effortKind) {
    case 'timed':  return 'Interval $_currentSet of $totalEntries';
    case 'round':
      final effectiveModality = effort.modality ??
          _exerciseCache[effort.exerciseId]?.modality ??
          widget.routineState.currentTemplate?.focusModality;
      return '${effectiveModality == 'sports' ? 'Period' : 'Round'} '
          '$_currentSet of $totalEntries';
    case 'drill':  return 'Hold $_currentSet of $totalEntries';
    default:       return 'Set $_currentSet of $totalEntries';
  }
}
Future<void> _setRoundLength(TemplateEffort effort, int setIndex, int secs) async {
  await widget.routineState.setTargetValue(effort.id, MetricIds.roundDuration,
      MetricIds.unitSeconds, setIndex: setIndex, targetInt: secs);
  // Same pair of writes as today: a round template holds exactly one round.
  await widget.routineState.setTargetValue(effort.id, MetricIds.rounds,
      MetricIds.unitRounds, setIndex: setIndex, targetInt: 1);
}
Future<void> _editRoundLength(TemplateEffort effort, int setIndex, int secs) async {
  final result = await showDurationEntryDialog(context,
      title: 'Edit Round Duration', initialSecs: secs);
  if (result != null && mounted) await _setRoundLength(effort, setIndex, result);
}
// ── _buildMetricWidget :1262-1404 — full replacement ────────────────────────
Widget _buildMetricWidget(TemplateEffort effort, List<TemplateTarget> targets, ThemeData theme) {
  final setIndex = _currentSet - 1;
  final weightStep = MetricStepping.weightStepFor(widget.settingsState?.preferredWeightUnit);
  switch (effort.effortKind) {
    case 'set':
      final reps = _getTargetInt(targets, MetricIds.reps, setIndex) ?? 10;
      final weight = _fromCanonicalWeight(
          _getTargetDouble(targets, MetricIds.weight, setIndex));
      return Column(mainAxisSize: MainAxisSize.min, children: [
        ValueStepperRow(
          key: ValueKey('${effort.id}-$setIndex-reps'), metricType: 'reps',
          currentValue: reps, unitLabel: 'REPS',
          onValueChanged: (value) => widget.routineState.setTargetValue(
              effort.id, MetricIds.reps, MetricIds.unitReps,
              setIndex: setIndex, targetInt: value as int)),
        ValueStepperRow(
          key: ValueKey('${effort.id}-$setIndex-weight'), metricType: 'weight',
          currentValue: weight, unitLabel: _preferredWeightUnitLabel, step: weightStep,
          onValueChanged: (value) => widget.routineState.setTargetValue(
              effort.id, MetricIds.weight, MetricIds.unitKg, setIndex: setIndex,
              targetMin: _toCanonicalWeight(value as double))),
      ]);
    case 'timed':
      // O-11: an interval has no editable target; stored extraWeight rows of old
      // routines stay in the data, untouched and ignored here (A5).
      return const SizedBox.shrink();
    case 'round':
      final roundDuration = _getTargetInt(
          targets, MetricIds.roundDuration, setIndex) ?? 180;
      return ValueStepperRow(
        key: ValueKey('${effort.id}-$setIndex-round-length'),
        metricType: 'duration', currentValue: roundDuration,
        unitLabel: 'ROUND LENGTH', min: 15,
        onEditorTap: () => _editRoundLength(effort, setIndex, roundDuration),
        onValueChanged: (value) => _setRoundLength(effort, setIndex, value as int));
    case 'drill':
      final extraWeight = _fromCanonicalWeight(
          _getTargetDouble(targets, MetricIds.extraWeight, setIndex));
      return ValueStepperRow(
        key: ValueKey('${effort.id}-$setIndex-weight'), metricType: 'weight',
        currentValue: extraWeight, unitLabel: _preferredWeightUnitLabel, step: weightStep,
        onValueChanged: (value) => widget.routineState.setTargetValue(
            effort.id, MetricIds.extraWeight, MetricIds.unitKg, setIndex: setIndex,
            targetMin: _toCanonicalWeight(value as double)));
    default:
      return Text('—', style: theme.textTheme.displayLarge);
  }
}
// ── deletions (D-5): _buildSetProgress :1407-1520, _buildSetIndicator :1522-1571.
// _buildSetControls / _buildArrowButton / _previousSet / _nextSet / _jumpToSet /
// _addSet / _deleteLastSet stay (used by the stepper, the bar and the arrows).
```

## D-4 answer: layout and height budget

- `OmniBackHeader` takes `subtitle: String?` under the title; `preferredSize` stays `kToolbarHeight` (56) — the merged subtitle adds no header height. Pinning needs no new offset: `extendBodyBehindAppBar: true` (:629) already puts the app bar in the body's MediaQuery top padding and the existing `SafeArea` (:635) insets below the header; the bar is pinned as the first child of the Column inside that SafeArea, before the scroll view — the same structure the live screen uses (`workout_session_list_view.dart:806-812` pins `_buildSetBar` outside its scroll view). Height budget, 402×874 phone (status ~62, home ~34): header 56 + bar 48 + scroll top 8 + rows (`ValueStepperRow` ≈ 96 each: v-pads 8+16+24 + displayLarge-40 line ~48) → reps 192, other kinds 96, + gap 16 + sets control ≈ 52 + arrows block 88 (Padding 20+20 + button 48) + home 34 = 494 worst case of 874 → ~380 dp spare; the sets control clears the fold. The scroll keeps `bottom: 80` so the pinned arrows never cover it; 12 segments keep the bar at 48. The throwaway widget probe stays in P1's Done Criteria; the device look is the lead's simulator pass.

## Scenarios S-4501..S-4512 (fixtures Mock-first, no timers, no real delays; pattern `logger_shell_screen_test.dart:49` `_buildDeps` / `_buildSessionScreen(deps, editMode: true)`; open the routine detail unless said otherwise)

- S-4501 guard, session editor: 38a-38f editor (`editMode: true`), resistance effort, 3 entries → `SetSegmentBar`, `ValueStepperRow`, `SetCountStepper` still present by type, output unchanged. Fails without: any 38e leak into the session editor.
- S-4502/S-4503 A1 header + A2 bar: 2 efforts in segment `Main`, effort 1 → `find.text('Exercise 1 / 2 · Main')` findsOneWidget; `find.text('Main')` findsNothing (body block line gone); `find.text(<exercise name>)` findsOneWidget (header title only). Resistance, 3 sets, focused 1 → `set-segment-0` focused fill, `set-segment-1/2` neutral; tap `set-segment-2` → `Set 3 of 3`; a 1-set effort still shows `set-segment-0`. Fails without: subtitle lacks `· Main`, body repeats the name, dots have no `set-segment-*` keys.
- S-4504/S-4505 A3 writes: `set` effort, kg, reps 10, weight 50 → two rows; tap `value-stepper-plus-reps` → reps targetInt 11; tap `value-stepper-plus-weight` → targetMin 52.5. Lbs variant: preferredWeightUnit `lbs`, weight 0 → label `LBS`; one tap → stored `5 / 2.20462` ≈ 2.2679 kg, display 5. Fails without: today InlineMetricEditors without steppers, no unit-aware step.
- S-4506 A4 hold: `drill`, extraWeight 0 → exactly one weight row, no reps row; tap + → `extraWeight` targetMin 2.5 (kg). Fails without: today an `EXTRA KG` InlineMetricEditor.
- S-4507 A5 interval: `timed` with legacy `extraWeight` targetMin 10.0 seeded → no `ValueStepperRow`, no `InlineMetricEditor` in the body; after tapping `routine-add-set` the repository still holds extraWeight 10.0. Fails without: today the screen renders and edits that target.
- S-4508/S-4509 A6 row + dialog: `round`, roundDuration 180 → `find.text('ROUND LENGTH')` findsOneWidget, `find.text('ROUND 1')` findsNothing; tap `value-stepper-plus-duration` → roundDuration 195 AND rounds 1; at 15 the `−` tap leaves 15; tapping the number opens `showDurationEntryDialog` (`Edit Round Duration`), confirming 120 writes roundDuration 120 and rounds 1 via `_setRoundLength`. Fails without: caption `DURATION` under a `ROUND 1` heading, no stepper path, only the dialog writes `rounds: 1` (D-7).
- S-4510/S-4511 A7 add/remove: resistance, 1 set → tap `routine-add-set` → `Set 2 of 2`, focused 2; at 12 sets `+` disabled (onPressed null), tooltip `Max 12 entries`; 3 sets → focused 1: `routine-remove-set` IconButton onPressed null, tap changes nothing; focused 3: tap removes → `Set 2 of 2`; 1 set: disabled. Fails without: today a custom InkWell row, not the shared stepper; the stepper has no `canRemove`.
- S-4512 A8 arrows: resistance, 2 sets → tooltips `Previous Set`/`Next Set` still navigate (`Set 1 of 2` ↔ `Set 2 of 2`) after the rewrite. Fails without: an accidental `_buildSetControls` regression would slip through.

## Phases (each at most 8 items; builders `crew-builder-app`; closed briefs with the exact replacement code, a separate run for new test files: unit 34 and 38d lessons)

- Phase 0 (lead): baselines (analyze 182; full suite `+4969 ~1`).
- P1: `routine_setup_screen.dart` detail view rewrite (A1-A7) with the exact code from the architect; migrations of the readers.
- P2: new routine-detail tests (`test/routine_detail_screen_test.dart`) + the S-4501 guard that the session editor still uses the shared pieces.
- D: docs. Then lead mutations by script, reviewer (facts + 5 narrow questions), simulator look (routine editor: resistance, hold, interval, round, 1 and 6 sets), report.

### P1 — crew-builder-app — routine detail rewrite + reader migrations (after Phase 0)

1. [ ] Extend `SetCountStepper` with `addKey`/`removeKey`/`canRemove` (code above) — `lib/widgets/session/set_count_stepper.dart` · `SetCountStepper`
2. [ ] Add unit tests: keys override, `canRemove: false` disables `−`, defaults keep `set-count-*` enabled — `test/set_shell_widgets_test.dart` · Mock `SetCountStepper` group
3. [ ] Rewrite `_buildDetailView` appBar + body (code above) — `lib/features/routine/routine_setup_screen.dart` · `_buildDetailView`
4. [ ] Replace `_buildMetricWidget` (code above), add `_setCountText` / `_setRoundLength` / `_editRoundLength`, swap imports per D-6; delete `_buildSetProgress` and `_buildSetIndicator` (D-5) — `lib/features/routine/routine_setup_screen.dart` · `_buildMetricWidget`
5. [ ] Migrate readers #2 (screen_widget_test legs), #3 (emphasis tests) — `test/screen_widget_test.dart`, `test/resistance_emphasis_redesign_test.dart`, `test/sports_emphasis_redesign_test.dart`, `test/timed_emphasis_redesign_test.dart`
6. [ ] Run the gateway checks below; fix or report — `.github/copilot/scripts/macos/gateway.sh`

Done Criteria (gateway): `flutter analyze` ≤ 182 issues (Phase 0 baseline); targeted `flutter test test/screen_widget_test.dart test/set_shell_widgets_test.dart test/resistance_emphasis_redesign_test.dart test/sports_emphasis_redesign_test.dart test/timed_emphasis_redesign_test.dart test/exercise_detail_emphasis_tier_test.dart test/tap_to_edit_unification_test.dart test/pr2_launch_quality_hotfix_test.dart test/crown_control_tap_to_edit_test.dart test/header_standardization_test.dart` green; the D-4 throwaway widget probe matches the height budget above.

Predicted Files P1 = Write scope P1: `--scope "lib/features/routine/routine_setup_screen.dart lib/widgets/session/set_count_stepper.dart test/screen_widget_test.dart test/set_shell_widgets_test.dart test/resistance_emphasis_redesign_test.dart test/sports_emphasis_redesign_test.dart test/timed_emphasis_redesign_test.dart"`

### P2 — crew-builder-app — new routine-detail tests (after P1; scenarios are green against the P1 result and proven by mutation — e.g. flipping `canRemove`'s default or dropping the `rounds: 1` write — each scenario naming the mutated line)

1. [ ] Write S-4501..S-4512 (fixtures above) — `test/routine_detail_screen_test.dart` · new file
2. [ ] Run the gateway targeted check on the new file; fix or report — gateway

Done Criteria P2: new file green; `flutter analyze` ≤ 182; full suite ≥ Phase 0 count + the new testWidgets (A9; report the added count). Predicted Files P2 = Write scope P2: `--scope "test/routine_detail_screen_test.dart"`

### D — crew-docs-keeper (can run parallel to P2 once P1 item 1 lands; disjoint scopes)

1. [ ] Rewrite the routine-editor section to the shared rows/stepper/bar wording — `docs/my_routines.md` · :289
2. [ ] Document `addKey`/`removeKey`/`canRemove` — `docs/widget_catalog/session_widgets.md` · `SetCountStepper` :182-218
3. [ ] Update only mentions of the removed controls — `docs/modality_based_exercise_ui.md`, `docs/navigation_and_screens.md` :191

Done Criteria D: every behaviour sentence names an existing test; files < 52 KB. Predicted Files D = Write scope D: `--scope "docs/my_routines.md docs/widget_catalog/session_widgets.md docs/modality_based_exercise_ui.md docs/navigation_and_screens.md"`. Ordering: P1 → P2 (P2 asserts P1's output); D ∥ P2 (disjoint writes); P1 must not start before the Phase 0 baselines exist.

## Progress / Assumption Log / Feedback / Open questions

### Progress
- Seeded 2026-10-16 (lead); plan completed by the architect 2026-10-16.
- [ ] P1.1 SetCountStepper extension
- [ ] P1.2 stepper unit tests
- [ ] P1.3 _buildDetailView rewrite
- [ ] P1.4 _buildMetricWidget + helpers, deletions
- [ ] P1.5 import swap
- [ ] P1.6 screen_widget_test + emphasis-test migrations
- [ ] P1.7 gateway checks
- [ ] P2.1 routine_detail_screen_test.dart + gateway check
- [ ] D.1 my_routines.md + widget_catalog SetCountStepper
- [ ] D.2 modality/navigation docs

### Assumption Log
- Seed says `_buildMetricWidget :1263-1405`; the signature opens at :1262 (params :1263-1265), body ends :1404 — seed range kept. The add-side of `_buildSetProgress` beyond :1470 and `_buildSetIndicator` :1522-1571 were read earlier this run but not re-read after compaction; their quotes are marked elided and both are deleted anyway.
- `removeIsExercise` stays a required parameter (smallest extension; the routine passes `false`).
- The `rounds: 1` write is extended to the stepper path (today only the dialog writes it) so both paths leave the same target shape (D-7). The old trailing `SizedBox(height: 80)` is folded into the scroll view's `bottom: 80` padding.

### Feedback — (none yet)

### Open questions
- Q-1, Q-2 above.
- `test/screen_widget_test.dart:1864` is named "timed effort with no extra-weight target shows no metric editor" but its body asserts an editor IS shown (stale name); P1 rewrites the body — default: fix the name to match the new assertion. After the migration the routine leg of `_expectDotColors` in `resistance_emphasis_redesign_test.dart` is replaced by segment assertions; the helper stays if the session leg still uses it — the builder removes it only if analyze flags it.
- Watch side not checked: no watch file read this run; the target writes are unchanged so no watch impact is expected (A8).

Handoff: P1 → crew-builder-app, scope `lib/features/routine/routine_setup_screen.dart lib/widgets/session/set_count_stepper.dart test/screen_widget_test.dart test/set_shell_widgets_test.dart test/resistance_emphasis_redesign_test.dart test/sports_emphasis_redesign_test.dart test/timed_emphasis_redesign_test.dart`; then P2 → crew-builder-app, scope `test/routine_detail_screen_test.dart`; D → crew-docs-keeper, scope `docs/my_routines.md docs/widget_catalog/session_widgets.md docs/modality_based_exercise_ui.md docs/navigation_and_screens.md` (parallel to P2).

## Lead verification record (2026-10-16)

| Item | Result |
| --- | --- |
| Architect | validated and completed the plan (stopped by the runner for `loop` after 47 min at the very end, plan complete: exact code, reader table, scenarios) |
| P1a (builder-app, 4 min) | done: `SetCountStepper` `addKey` / `removeKey` / `canRemove`; routine detail rewritten onto the shared pieces (exact code from the plan, no symbol fixes needed); 9 predicted red tests listed |
| P1b (builder-app, 8 min) | done: the 9 routine tests migrated + 3 stepper unit tests |
| P2 (builder-app, 15 min) | done: `test/routine_detail_screen_test.dart` (S-4501..S-4512) |
| D (docs-keeper, 8 min) | done: `my_routines.md`, widget catalog, evidence file |
| Lead mutations | 14 single-line mutations, restored by `cmp`: 13 red at once, the hold weight unit conversion (E8b) closed by S-4505b (red afterwards) |
| Review | APPROVE: 0 blocker, 0 major, 1 minor (header subtitle had no ellipsis for a long block name): fixed by fix 2 (S-4513) |
| Final checks | see the report: full suite and analyze run after fix 2 |
