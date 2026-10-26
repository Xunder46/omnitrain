# Evidence — plan 38e phase D (crew-docs-keeper)

Run 2026-10-16. Write scope: `docs/my_routines.md`,
`docs/widget_catalog/session_widgets.md`, `docs/modality_based_exercise_ui.md`,
`docs/navigation_and_screens.md`, this file.

| Doc | Section | What changed | Verified against file:line |
|---|---|---|---|
| `docs/my_routines.md` | RoutineSetupScreen · Detail View (per-exercise) | Rewrote the section: the `InlineMetricEditor` wording is replaced by the shared pieces (`SetSegmentBar`, `ValueStepperRow`, `SetCountStepper`); header title = exercise name, one subtitle `Exercise N / M · <block name>`, old body name lines gone; pinned bar (focused dimmer accent, others grey, no logged state, tap jumps, one-set effort keeps one segment); per-kind rows — `set`: two boxed rows, reps `targetInt` / weight canonical kg `targetMin`, step 2.5 kg or 5 lb with the `LBS` label; `timed`: no editable value, stored `extraWeight` targets ignored (O-11); `drill`: one `extraWeight` weight row; `round`: one `ROUND LENGTH` duration row, 15 s step, 15 s floor, number opens `showDurationEntryDialog`, both paths write `roundDuration` + `rounds: 1`, old `ROUND n`/`PERIOD n` heading gone; sets control — `+` adds and focuses a set capped at 12 with the `Max 12 entries` tooltip, `−` enabled only when more than one set exists and the focused set is the last, keys `routine-add-set` / `routine-remove-set`; Previous/Next Set arrows unchanged. Every behaviour sentence names an existing test (groups/tests read this run in `test/routine_detail_screen_test.dart`, `test/screen_widget_test.dart`, `test/header_standardization_test.dart`, `test/sports_emphasis_redesign_test.dart`). | `lib/features/routine/routine_setup_screen.dart:609-687` (`_buildDetailView`), `:1255-1272` (`_setCountText`), `:1274-1306` (`_setRoundLength`/`_editRoundLength`), `:1309-1399` (`_buildMetricWidget`), `:1401-1419` (`_buildSetControls`); `lib/widgets/session/set_count_stepper.dart:24-56` (`canRemove`/`addKey`/`removeKey`), `:88-91` (`onPressed: canRemove ? onRemove : null`); `lib/core/constants/workout_constants.dart:4` (`maxEntriesPerEffort = 12`); `lib/core/utils/metric_stepping.dart:15-16,32-40` (2.5 kg / 5 lb); `lib/widgets/session/value_stepper_row.dart:33-36,74-76` (duration step 15 s, boxed `OmniSurface`) |
| `docs/my_routines.md` | Smart Defaults for Targets | New-exercise default bullet for `timed`: "no visible metric editor unless an extra-weight target is present" → "no editable value in the detail — a stored extra-weight target stays in the data and is ignored (owner rule O-11)" (the old sentence described the removed editor behaviour). | `lib/features/routine/routine_setup_screen.dart:1363-1366` (`timed` → `SizedBox.shrink()`) |
| `docs/widget_catalog/session_widgets.md` | `SetCountStepper` | Props table extended with `canRemove` (default `true`; `false` disables `−`), `addKey`, `removeKey`; the behaviour paragraph now says the keys are overridable per caller (the routine editor passes `routine-remove-set` / `routine-add-set`) and that a `canRemove: false` `−` stays in the tree disabled; the Verified-by list gained the three new `Mock S-4204 SetCountStepper` tests. No sentence in the catalog says the routine editor has its own controls (grep run this run: no such claim), so none was fixed. | `lib/widgets/session/set_count_stepper.dart:24-56`, `:66-71` (key defaults), `:88-91` (`canRemove` → `onPressed` null) |
| `docs/modality_based_exercise_ui.md` | — | No change required: the doc covers the session screen only. Grep for `RoutineSetupScreen` / "routine editor" / "routine setup": no matches; the `InlineMetricEditor` / `ROUND LENGTH` / `ROUND n` mentions it carries are session-screen claims with their own tests. | grep run this run (no matches for routine-editor claims) |
| `docs/navigation_and_screens.md` | — | No change required: the `RoutineSetupScreen` row (:191) reads "Create/edit routines (dual view)" and no sentence names the removed controls. Grep for `Set X of Y` / `InlineMetricEditor` / `dots` / `EXTRA KG` / `ROUND n` / `SetSegmentBar` / `SetCountStepper` / `ValueStepperRow`: no matches. | grep run this run (no matches) |

## Gateway check

`.github/copilot/scripts/macos/gateway.sh test` on
`test/docs_indexing_contract_test.dart` (paste of the real output follows):

```
gateway: test (timeout 900s): flutter test test/docs_indexing_contract_test.dart
00:00 +0: loading /Users/irinakutsenko/Developer/omnitrain/test/docs_indexing_contract_test.dart
00:00 +0: Docs indexing contract the docs root exists and contains Markdown
00:00 +1: Docs indexing contract no documentation file exceeds the indexing ceiling
00:00 +2: Docs indexing contract no documentation file is within the warning band of the ceiling
00:00 +3: Docs indexing contract every relative link resolves to a file that exists
00:00 +4: Docs indexing contract every doc page is reachable from another doc page
00:00 +5: Docs indexing contract no document carries a hexadecimal colour literal
00:00 +6: Docs indexing contract design_system.md exists and is itself hex-free
00:00 +7: Docs indexing contract no document carries a step-by-step flow walkthrough
00:00 +8: Docs indexing contract no document carries a scheduling or roadmap annotation
00:00 +9: Docs indexing contract the symbol scan flags an Omni name and an OmniTheme member that no declaration answers
00:00 +10: Docs indexing contract every Omni symbol the design docs name is declared in lib/
00:00 +11: Docs indexing contract the value scan flags a unit value and a percentage, and skips a fence and a test id
00:00 +12: Docs indexing contract no design doc carries a unit value or a percentage
00:00 +13: All tests passed!
```

Exit code 0. The size ceiling tests (`no documentation file exceeds the
indexing ceiling`, `no documentation file is within the warning band of the
ceiling`) passed over the edited files, so every touched doc is under the
64 KiB hard limit and out of the warning band.
