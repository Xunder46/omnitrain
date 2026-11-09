# Plan 38f — Logger polish after the owner's side-by-side look (shell + one bug)

Status: SEEDED by the lead on 2026-10-15; validated and completed by the architect 2026-10-15 (every code pointer below re-checked against the tree with 38a/38b/38c landed; seed text kept verbatim, additions appended). NOT STARTED. Runs AFTER plan 38c has landed (38c is being built in another session and edits the same screen files: never two writers in one tree). Re-quote every "current line" from the tree at brief time; line numbers below are symbols only. Base commit `80928669` plus the uncommitted 38a, 38b and 38c work. Not authorised to commit: the owner commits; never push.
Series: `docs/plans/2026-10-15-38-logger-rework-series.md` (O-1..O-12, T-1..T-4 bind). Scenario ids: `S-43xx` (checked free in `test/`, `docs/`, `watch/`, `lib/`).
Owner input: a screenshot of the simulator beside the mockup, seven points (2026-10-15), answers "ok" to the lead's four defaults.

## Goal and acceptance (what the user sees)

- A1. Header (detail view of an exercise): the line under the exercise name is ONE line, `Exercise 1 / 4 · Main Workout`; with no section name just `Exercise 1 / 4`. (Today: two lines.)
- A2. The set bar sits directly under the header and does not scroll with the content (pinned). Gap between header and bar no more than 8 dp.
- A3. Segment look, no border anywhere, all segments the same thickness (6 dp): logged = full accent (`primary`), the focused set = dimmer accent (`primary` at alpha 115), not logged and not focused = grey (`onSurface` at alpha 51). A logged set that is also focused reads as logged (full accent); its caption (A4) is drawn in the dominant text colour, the others in the secondary one, as the only focus cue.
- A4. Values of logged sets sit directly under their own segment, one caption per segment, centred, one line, only when the exercise has 5 sets or fewer; with 6 or more sets no captions and no reserved space. With 5 or fewer, the captions row keeps its height when nothing is logged (no jump on the first log). Unlogged sets: blank. Formats: reps exercise `reps×weight` ALWAYS, including weight 0 (`12×0`) and negative weight (`10×-5`), weight in the user's unit as today; intervals, holds and rounds `m:ss`. The old single `LoggedValuesLine` is removed.
- A5. Reps row, weight row (and, from 38c, the hold's weight row) each sit in a rounded, greyish, half-transparent box (the shared `OmniSurface`, no shadow), full width with the existing circular − / + inside the box; number and unit label unchanged.
- A6. The sets control is a boxed full-width control, shorter than the reps/weight boxes: `−` on the left, the count text in the middle, `+` on the right. The middle reads `Set 2 of 3` (`Interval …`, `Round`/`Period …`, `Hold …`: the text the screen shows today) at today's text style; the separate `3 SETS` count and its label are gone, and the count text no longer sits under the bar. Tooltips `Add set`, `Remove set`, `Remove exercise`, `Max 12 entries` and keys `set-count-remove` / `set-count-add` unchanged; targets stay 48 dp or more.
- A7 (bug, owner point 7). Deleting a logged set removes it for good: add a set afterwards and it is a NEW unlogged set (button `Log Set`/`Start`, segment not logged, no `LOGGED`), pre-filled with the previous set's reps and weight as today's carry-forward does. Deleting a set in the middle keeps the other sets' logged state (a logged set stays logged, an unlogged one stays unlogged) and their rest records.
- A8. Unchanged: rest chip and strip, arrows-and-button row, timers, auto-advance, the lock of logged sets, the `−` rule (last unlogged set), edit-mode behaviour, 38b's hold-to-repeat, 38c's count-up screens.
- A9. `flutter analyze` not above the baseline recorded at Phase 0 (0 errors); `flutter test` not below the Phase 0 pass count plus this plan's new tests minus the tests it removes (list them); no allowlist entry, no ratchet raised.

## Cause of A7 (verified by reading, to be proven by a failing test first)

A set is "logged" exactly when an `EntryRest` row sits at its index + 1 (`_isSetLogged`, `workout_session_screen.dart`). `deleteEntry` (`lib/state/workout/session_core_entry.dart`) deletes the set's observations (and the timed/round instance) but leaves the rest rows alone, and the screen's `_loggedSetKeys` set is only ever added to. After deleting logged set 3 of 3, the rest at index 3 survives, so a new set 3 reads as logged again; and `_logSet`'s early return on `_loggedSetKeys` would swallow a real log of it.

## Decision Ledger

- D-1 Rest rows follow the delete (technical, state layer, no repository interface change): after the set at 0-based `d` is removed, remove the rest at index `d + 1` (the "set d is logged" mark), re-key every rest with index `> d + 1` down by one, keep the rest at index `d` and every rest below it. Done in a new `TimerManager` method called from `deleteEntry` for every effort kind, using only the existing repository methods: `deleteEntryRestsForEffort(effortId)` then `createEntryRest` for each kept rest with the new `entryIndex` and id `rest-<effortId>-<index>` (the id shape the watch importer already uses: grep before writing). The in-memory `_entryRests` cache is updated first, the persists follow, errors go to `_setError` like the rest of `deleteEntry`.
- D-2 `_loggedSetKeys` (screen): after any `_deleteSetAt` (and the exercise removal) clear the keys of that effort and refill them from `_isSetLogged` over the new entries (the same loop `_loadExercises` runs at load).
- D-3 `SetSegmentBar` gains `captions: List<String?>?` (null or length != count → no captions row) and a constant `kSetBarCaptionMaxSets = 5`; captions render under each segment in the same `Expanded` cell, `bodySmall`, one line, ellipsis, `OmniTheme.colors.textSecondary`, the focused segment's caption `textDominant`; the border and the 10 dp focused height are removed; `isLogged` and the semantic labels stay. The caption row is `SizedBox(height: 20)`.
- D-4 `LoggedValuesLine`, `loggedValuesText`, their test group and the design-system row are deleted. Caption strings come from `_loggedValueText` (detail view, 38a D-4) with the zero-weight branch removed: `'$reps×$weightText'` for every `set`.
- D-5 Boxed rows: `ValueStepperRow` (38b) wraps its content in `OmniSurface(showShadow: false, padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8))`; the screen passes spacing between rows. If `OmniSurface`'s colours are not "greyish half-transparent" on the active theme, the architect states what differs and the lead decides; never a raw colour, never a new surface piece without owner OK.
- D-6 `SetCountStepper` gains `text` (the middle text, replaces `label` and `count` display) inside the same `OmniSurface`; `label`/`count` parameters are removed or kept only if a reader needs them (architect greps). The tooltip for `+` at the cap and the trash icon logic stay.
- D-7 Header: `_buildHeader` (`workout_session_list_view.dart`) detail branch merges `Exercise N / M` and the segment name into one `Text` (`'$a · $b'`), one line with ellipsis; the separate segment-name `Padding(Text)` is removed. List-view and edit-mode headers unchanged.
- D-8 Layout: the bar block (bar + captions) moves out of the scroll `Column` into the fixed column right below `_buildHeader`, padding horizontal 20, top 0; the scroll column starts with the exercise's controls then the sets control. The rest strip and the controls row stay below.

Appended by the architect (validated against the tree 2026-10-15):

- D-9 The edit snapshot captures rests (state layer, no repository interface change): `SessionEditSnapshot` (`lib/core/models/session_edit_snapshot.dart`) gains `entryRests: Map<String, List<EntryRest>>` (deep-copied per effort; constructor default `const {}` — no test constructs the class, grep clean). `snapshotSessionState` (`session_core_lifecycle.dart:273`) fills it; `restoreSessionSnapshot` (`:305`) for every surviving effort runs `deleteEntryRestsForEffort` + re-creates the snapshot's rests, and for efforts the restore re-creates (removed while editing) also re-creates their rests (`deleteEffort` cascaded them away). The NOTE at `session_edit_snapshot.dart:96-99` ("rest records are never structurally mutated during edit mode") is stale — `_logSet` creates rests in edit mode and D-1 re-keys them on delete — and is replaced. Without D-9, an edit-mode delete + cancel leaves D-1's re-keyed rests in place and the wrong sets read logged (S-4318).
- D-10 Caption test contract: each caption `Text` carries `Key('set-caption-$i')` (i = 0-based segment index). A shared helper (`setCaption(tester, i)`, plus a captions-present probe) lives in a new `test/helpers/set_captions.dart`; the four `_loggedLine` reader files migrate to it (see Readers).
- D-11 (found by the P1 builder, lead-confirmed) Rests are positional everywhere (screen `_isSetLogged`, `recordRestStart`, the watch importer D-167, and D-1's re-key), but the watch bridge read them as set NUMBERS (`EntryRows.loggedSetNumbers`, `WatchSessionAdoptionBridge._entriesFor`). After a middle delete (numbers keep a hole, positions do not) the phone would have told the wrist to delete a set that still exists (`test/watch_session_auto_push_test.dart` S-121, S-122, F3 went red). Fix: new `EntryRows.loggedSetNumbersOf(groups, rests)` maps rest positions to the numbers of the groups at those positions; the bridge uses it. Wire format unchanged. Scope: `lib/core/utils/entry_rows.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `test/entry_rows_test.dart` (fix round 1 of P1).
- D-5 finding (architect → lead, no code change): `OmniSurface` paints an opaque `themeColors.surface` — #102842 (Abyssal Neon), #3A2712, #262626 (Graphite), #2A2350, #3A1A16, #182E1B across the six themes — with a ~19 %-white `surfaceBorder` (0x30FFFFFF), radius 20 (`omni_theme.dart:239-411`, `:471`, `:473`). Against A5's "rounded, greyish, half-transparent": rounded ✓; greyish ✗ (theme-tinted — only Graphite is grey); half-transparent ✗ (opaque). `docs/design_system.md`'s shared-pieces table routes every card surface through `OmniSurface` and `test/ui_standards_contract_test.dart` bans raw colours, so a translucent grey would need a new owner-approved token. Recommendation: ship `OmniSurface(showShadow: false, ...)` (one job one piece) and show the owner a screenshot; a translucent grey is a separate owner decision.

## Readers of what this plan changes (grep, migrate, never loosen)

Every line below was grepped/read this run (2026-10-15, tree with 38a/38b/38c). "stays green" = no edit needed, verified.

- `logged-values-line` / `LoggedValuesLine` / `loggedValuesText` (defined `lib/widgets/session/logged_values_line.dart:10,17`; used `workout_session_detail_view.dart:622-623`, imported `workout_session_screen.dart:28`):
  - `test/set_shell_widgets_test.dart:173-196` — S-4203 group; deleted together with the widget (P3).
  - `test/logger_shell_screen_test.dart` — helper `:110-115`; uses `:176, :205-206, :225, :244, :264, :285` (+ size assert `:287`), `:498` (S-4221 layout anchor), `:858`, `:1063`. Migrate to per-segment caption reads (D-10); multi-value strings split into per-index expects; the `''` + height-24 asserts become "captions row present, all captions blank".
  - `test/count_up_screen_test.dart` — helper `:147-152`, use `:405` (`'0:00'`).
  - `test/reps_screen_test.dart` — helper `:115-120`, use `:455` (`'11×60'`).
  - Docs: `docs/design_system.md` (widget row), `docs/widget_catalog/session_widgets.md`, `docs/modality_based_exercise_ui.md` (D phase).
- `set-segment-*` colours and heights:
  - `test/set_shell_widgets_test.dart` S-4201/S-4202 — heights 6/10 + focused border → all 6, `border == null` (P2).
  - `test/resistance_emphasis_redesign_test.dart:303-335` — `_segmentColors`/`_expectSegmentColors` read only Container colours, which D-3 does not change → stays green (verified; re-run in P3's suite).
  - `test/sports_emphasis_redesign_test.dart:449-459` — focused segment found by height ≥ 10 → switch to the colour `primary.withAlpha(115)` (the `accentedSegments` count already covers it); drop the height loop (P3).
- Count text `Set N of M`: the string is unchanged and still exactly one widget, so every `find.text` keeps working. Position asserts: `test/logger_shell_screen_test.dart:498-510` (S-4221) re-derived in P3; hit-test asserts (S-4224 `:940-960`, count_up S-4271 `:292-335`, reps S-4255 `:99-160`) stay green.
- `SetCountStepper(label:, count:)` constructor: callers are exactly `lib/features/session/workout_session_list_view.dart:840` and `test/set_shell_widgets_test.dart:212-276` (S-4204, three constructions) → migrate to `text:` (P2). No other constructor callers (grep clean).
- Header text `Exercise N / M`: exactly three finds — `test/logger_shell_screen_test.dart:667, :672` (S-4215 next-exercise test) and `test/screen_widget_test.dart:9131` → each becomes the merged string `Exercise N / M · <segmentName>`; every screen fixture carries the segment name `Main Workout` (`lib/core/utils/logged_entry_rows.dart:31` — a free session's default segment), and `buildExercisesWithEntries` always supplies a non-empty name (`session_summary_builder.dart:419`, fallback `'Block N'`). The seed named `header_standardization_test.dart` and `session_toolbar_rework_test.dart`: checked this run — no `Exercise N / M` or segment-name-text finds in either (header_standardization_test.dart:373-521 is OmniBackHeader/ExerciseEditorScreen; session_toolbar_rework_test.dart: no matches) → no migration there.
- `ValueStepperRow` look: `test/value_stepper_row_test.dart` exists (confirmed) — box asserts added (P2); `test/count_up_screen_test.dart:292-335` (48×48 targets, stacking) and `test/reps_screen_test.dart:99-160` (relations) stay green — the box wraps, the 48 dp buttons and the order do not change.
- Rest rows after delete:
  - `test/watch_session_import_test.dart:2668-2697` — S-327 "deleting the set leaves its rest" asserts the rest SURVIVES (D-167(b)). D-1 deliberately flips this for the phone's delete path (owner point 7): rewritten in P1 — after `deleteEntry(bench, 0)` the imported rest (entryIndex 1) is gone.
  - `test/watch_session_merge_test.dart:1749-1790` — S-337: the leftover-rest expectations (`rest-sl-1-1` surviving open) are re-derived under D-1; the test's purpose (the wrist's unresolvable rest is consumed, not retried) is unchanged.
  - `test/state_test.dart:1896-1936, :2624`, `test/edge_case_test.dart:292-309`, `test/entry_rows_test.dart:165`, `test/entry_identity_test.dart` (14 deleteEntry calls), `test/exercise_set_last_value_test.dart` — no rest reads after delete → stays green.
  - `test/watch_session_auto_push_test.dart` (12 deleteEntry calls), `test/row_invariants_guard_test.dart:337-588` — no rest reads → stays green.
  - `test/watch_session_edit_restore_late_entry_test.dart:474`, `test/watch_session_edit_restore_summaries_test.dart:296,411,449` — edit + Discard flows; D-9 adds rest restore, neither file reads rests → stays green; the new behaviour is guarded by S-4318.
  - `test/unified_rest_overlay_test.dart`, `test/session_rest_closing_race_test.dart`, `test/rest_timer_docked_strip_test.dart` — no deleteEntry → stays green. `test/session_toolbar_rework_test.dart` S-015/S-016 — not checked this run; the P1 builder greps `deleteEntry` in it before running.
- Contract tests: `test/ui_standards_contract_test.dart` (OmniSurface card rule — D-5 uses the shared piece → stays green), `test/palette_legibility_contract_test.dart` (no colour change → expected green, not checked), `test/docs_indexing_contract_test.dart` (D phase keeps the docs indexed).

## Core scenarios (exact fixtures, to be completed by the architect)

Fixture vocabulary: `harnessFactories` from `test/helpers/repository_harness.dart` (Mock + Hive, playbook (i)); `effortId` = `addExerciseToSession(exercise-barbell-squat, chosenMetric: 'reps')`; "rest k" = an `EntryRest` with `entryIndex` k (1-based set number just logged, `timer_manager.dart:692-735`, id `rest-<effortId>-<index>`); "set i" = 0-based entry index i. Rest entryIndexes are read via `getEntryRests(effortId)` (sorted by entryIndex).

State (`test/entry_delete_rests_test.dart`, NEW file; BOTH harnesses):

- S-4301 effort with 3 sets, rests at indexes 1, 2, 3 (all logged); `deleteEntry(effortId, 2)`; rests are exactly {1, 2}; `addEntry`; the new set 3 is not logged. Fails today: rest 3 survives.
  - Fixture: `addEntry` ×3, `recordRestStart(effortId, 1/2/3)` → rests {1,2,3}. Act: `deleteEntry(effortId, 2)`. Expect: rest entryIndexes exactly {1,2} (rest 3 removed; none above to re-key); after `addEntry`, no rest at entryIndex 3 → the new set 3 unlogged.
  - Why it fails today: `deleteEntry` (`session_core_entry.dart:648-690`) deletes only the observation group for a `set`; rest 3 survives, so the new set 3 reads logged and `_logSet`'s early return on `_loggedSetKeys` (`workout_session_screen.dart:818`) would swallow a real log.
  - Guard: prover `prove-red` at the base commit.
- S-4302 same three logged sets, `deleteEntry(effortId, 0)`: rests become {1, 2} with the durations of the old rests 2 and 3 (re-keyed); sets 1 and 2 still read logged.
  - Fixture: as S-4301, with distinct `restStartMs` 1000/2000/3000. Act: `deleteEntry(effortId, 0)`. Expect: rests exactly {1,2}; the entryIndex-1 row carries old rest 2's stamps (startMs 2000), entryIndex-2 carries old rest 3's (3000); every kept rest's id is `rest-<effortId>-<newIndex>` (the shape the watch importer/merge writes — `watch_session_merge_test.dart` S-337 asserts `rest-sl-1-1`).
  - Why it fails today: rests keep indexes {1,2,3} → the new set 3 reads logged and rest analytics shift by one.
  - Guard: prove-red.
- S-4303 sets 1 and 2 logged (rests 1, 2), set 3 unlogged; delete set 2 (index 1): remaining rests {1}: set 1 logged, the old set 3 (now set 2) unlogged.
  - Fixture: `addEntry` ×3, `recordRestStart(effortId, 1/2)` only. Act: `deleteEntry(effortId, 1)`. Expect: rests exactly {1} (rest 2 removed; no rest 3 to re-key).
  - Why it fails today: rest 2 survives at index 2 → the old set 3 (now index 1) reads logged.
  - Guard: prove-red.
- S-4304 `timed` and `round` efforts: same rule (one test each).
  - Fixture: `timed` — `addExerciseToSession(..., effortKindOverride: 'timed')`, two entries logged via `setTimedEntryDuration` + `recordRestStart(effortId, 1/2)`; `round` — same shape with rounds. Act: `deleteEntry(effortId, 0)`. Expect: rests {1} re-keyed from old 2.
  - Why it fails today: `deleteEntry` early-returns into `deleteTimedEntry`/`deleteRound` (`timer_manager.dart:584/:308` — both re-index their own rows, neither touches rests).
  - Guard: prove-red.

Screen (`test/logger_shell_screen_test.dart`, Mock, `testWidgets`, Mock-first — no Hive harness inside `testWidgets`):

- S-4310 log 3 sets by tapping `Log Set`, `−` + confirm `Delete logged Set?` (last set), `+`: the new third set shows `Log Set`, its segment label says `not logged`, no `LOGGED`; tapping `Log Set` logs it (a rest at index 3 appears) — guards D-2.
  - Fixture: 3 sets, all logged via `Log Set` taps (600×1200 surface). Act: `set-count-remove` → `find.textContaining('Delete logged Set?')` → confirm `workout-delete-logged-entry-confirm` → `set-count-add`. Expect: `Log Set` button visible, segment 2 reads the focused-unlogged accent `primary.withAlpha(115)`, `find.text('LOGGED')` findsNothing; tap `Log Set` → `getEntryRests(effortId)` gains entryIndex 3.
  - Why it fails today: `_loggedSetKeys` still holds `$effortId-2` (`_logSet` :960 adds, nothing removes) → the new set reads logged and the tap is swallowed.
  - Guard: prove-red.
- S-4311 header: `Exercise 1 / 1 · Main Workout` is ONE text; with no section name `Exercise 1 / 1`.
  - Fixture: `_buildDeps()` (default segment `Main Workout`, `logged_entry_rows.dart:31`), one exercise. Expect: `find.text('Exercise 1 / 1 · Main Workout')` findsOneWidget and `find.text('Exercise 1 / 1')` findsNothing. The no-name half is S-4322 (heavier fixture).
  - Why it fails today: two `Text`s — `Exercise 1 / 1` and a separate segment-name `Padding(Text)` (`workout_session_list_view.dart:1006-1032`).
  - Guard: prove-red.
- S-4312 captions: 3 sets, sets 1-2 logged (10×60.0, 8×62.5): the captions row has two non-empty captions `10×60` and `8×62.5` located within the horizontal span of segments 0 and 1 and below the bar; with 6 sets no caption widget exists.
  - Fixture: values via `updateEntryValue(effortId, 0, 'reps', 10)` / `('weight', 60.0)` / `(1, 'reps', 8)` / `(1, 'weight', 62.5)`. Expect: `Key('set-caption-0')` text `10×60`, `Key('set-caption-1')` text `8×62.5` (D-10); each caption's rect inside segment i's horizontal span; caption top ≥ bar bottom. Second fixture: 6 sets, sets 1-2 logged → `find.byKey(Key('set-caption-0'))` findsNothing.
  - Why it fails today: captions do not exist (the single `LoggedValuesLine` renders instead).
  - Guard: prove-red.
- S-4313 weight 0 and negative: logged set reps 12 weight 0.0 → caption `12×0`; weight -5.0 → `10×-5`.
  - Fixture: set 1 reps 12 weight 0.0; set 2 reps 10 weight -5.0 (both logged). Expect captions `12×0` and `10×-5` (formatting already correct: `formatWeightValue` → `_formatNumber` drops `.0` and keeps the minus, `unit_formatter.dart:69,257-271`).
  - Why it fails today: `_loggedValueText`'s `if (weightKg <= 0) return '$reps';` branch (`workout_session_detail_view.dart:132-163`) drops the weight.
  - Guard: prove-red.
- S-4314 no border: the segment `Container` decoration has `border == null` for focused segments; all segment heights equal 6.
  - Fixture: 3 sets, none logged (segment 0 focused). Expect: every segment Container `decoration.border == null` and `constraints.maxHeight == 6`, focused included.
  - Why it fails today: the focused segment is 10 dp with a border (`set_segment_bar.dart`).
  - Guard: prove-red.
- S-4315 the sets control shows `Set 2 of 3` inside the box with `−`/`+`; no `SETS` label text exists on the screen.
  - Fixture: 3 sets, focus set 2. Expect: the `SetCountStepper`'s middle text is exactly `Set 2 of 3` inside its `OmniSurface`; `find.text('SETS')` findsNothing; tooltips `Add set`/`Remove set`/`Remove exercise`/`Max 12 entries` and keys `set-count-remove`/`set-count-add` unchanged.
  - Why it fails today: the stepper renders label `SETS` + count `3` as two texts (`set_count_stepper.dart:33+`, S-4204).
  - Guard: prove-red.
- S-4316 boxed rows: reps and weight rows are descendants of an `OmniSurface`.
  - Fixture: reps exercise with load. Expect: `find.ancestor(of: find.byType(ValueStepperRow), matching: find.byType(OmniSurface))` findsOneWidget per row.
  - Why it fails today: no `OmniSurface` around the rows.
  - Guard: prove-red.
- S-4317 layout at 390 x 844 with the rest strip up: bar top within 8 dp of the header bottom; the sets control is hit-testable (38a S-4224 stays green).
  - Fixture: 3 sets, `recordRestStart(effortId, 1)` (strip up), surface 390×844. Expect: bar-block top − header bottom ≤ 8 dp (probe baseline: header bottom 100, bar visible top 137 → 37 dp today); `set-count-add` hit-testable.
  - Why it fails today: the bar is centred in a 48 dp cell 37 dp below the header and scrolls with the content.
  - Guard: prove-red.

Edge scenarios (appended by the architect):

- S-4318 (D-9, state, BOTH harnesses) edit-mode delete + cancel restores the rests: 3 sets logged (rests {1,2,3}, startMs 1000/2000/3000); `snapshotSessionState()`; `deleteEntry(effortId, 1)` (rests become {1,2} re-keyed); `restoreSessionSnapshot(snapshot)`; rests are again exactly {1,2,3} with the original stamps (entryIndex 2 startMs 2000, entryIndex 3 startMs 3000).
  - Why it fails: `SessionEditSnapshot` captures no rests (`session_edit_snapshot.dart:96-99`) and `restoreSessionSnapshot` (`session_core_lifecycle.dart:305-383`) never writes them — and after D-1 the re-keyed rows persist, so old set 3 reads unlogged and old set 2's rest marks the wrong set.
  - Guard: GREEN at the base commit (today's deleteEntry leaves rests alone); RED at the D-1-only intermediate commit; the prover proves red there, then the mutation "remove the rest-restore loop" turns it red again after D-9.
- S-4319 (screen, Mock) edit-mode delete + Save keeps the re-key: 3 sets logged; enter edit mode; `set-count-remove` + confirm; Save → rests exactly {1,2}; the surviving old set 3 (now set 2) unlogged.
  - Why it fails today: rests untouched → old set 3 reads logged.
  - Guard: prove-red.
- S-4320 (screen, Mock) deleting the set whose rest is open hides the chip: 3 sets all logged, rest 3 OPEN (logged last, never closed); `set-count-remove` + confirm → `rest-overlay-chip` gone, `getEntryRests(effortId)` = {1,2} all closed.
  - Why it fails today: the chip already hides (the open rest is not deleted today — after D-1 it is, and the hide must survive); the NEW risk is the scheduled rest pings: the screen glue must call `cancelRestNotifications()` + `_lastRestPingFiredAt.remove(effortId)` when the deleted set's rest was open (mirroring `_logSet`'s close path `workout_session_screen.dart:866-876`).
  - Guard: the two visible asserts are prove-red-able only for the ping half via mutation (the `cancelRestNotifications()` call site); the chip/rest asserts are regression guards.
- S-4321 (screen, Mock, regression guard — not prove-red) exercise removal cascades: effort with 1 logged set; `set-count-remove` → `Remove Exercise?` → confirm → `getExercisesWithEntries()` lacks the effort and the repository holds no rests for it (`deleteEffort` cascades, mock `:772` / hive `:1447`); `_loggedSetKeys`/`_inProgressKeys` hold no key of that effort.
  - Why it needs a test: D-2's refill loop must not resurrect keys for a removed effort; the removal path already clears `_inProgressKeys` (`:1351`) — the test pins both key sets.
- S-4322 (screen, Mock) header with no section name: seed the repository directly — a session whose segment has `name: ''` (exact calls derived from `test/helpers/repository_harness.dart`), one effort, `loadHistoricalSession`; expect ONE text `Exercise 1 / 1` (no `·` suffix).
  - Why it fails today: no merge exists. Reachability note: `buildExercisesWithEntries` falls back to `'Block N'` only for a NULL name (`session_summary_builder.dart:419`); an empty-string name is the only public path to a nameless header.
  - Guard: prove-red.
- S-4323 (screen, Mock) captions row keeps its height before the first log (A4 no-jump): 3 sets, none logged → a captions row exists (all captions blank, `Key('set-caption-0')` findsOneWidget with empty text); log set 1 → the bar block's rect is unchanged in height.
  - Why it fails today: no captions row exists at all.
  - Guard: existence half prove-red; the no-jump half is a regression guard on D-3's constant `SizedBox(height: 20)`.
- S-4324 (screen, Mock) logged AND focused set (A3): log set 1, tap segment 0 to focus it → its bar fill is full `primary` (not `primary.withAlpha(115)`) and its caption Text's style colour is `textDominant` while the other logged caption (log set 2 as well) is `textSecondary`.
  - Why it fails today: no captions exist (colour half red); the bar half is today's behaviour (logged wins over focused) — regression guard.
  - Guard: caption half prove-red.

## Lead decisions after the architect run (2026-10-15)

- L-1 D-5 stands as the architect recommends: ship `OmniSurface(showShadow: false)`; the owner sees it on a screenshot and decides on a translucent-grey token later (owner item). No new surface piece.
- L-2 D-1 stands, S-327 is rewritten (a user-deleted set takes its rest with it). Owner-visible in rest history only.
- L-3 D-9 and D-10 accepted.
- L-4 Phase split changed so that no tree state fails to compile when P1 and P2 run side by side: `SetCountStepper` (D-6) moves from P2 to P3a together with its only caller; P2 keeps `SetSegmentBar` constructor additive (`captions` optional, default null). P3 is split in two runs: P3a production wiring with its new red-first tests, P3b the mechanical reader migrations. Full suite runs after P3b (by the lead); P1 and P2 run only their named test files.
- L-5 Segment cell layout (for A2): each cell stays a 48 dp tap target (`Key('set-segment-$i')`, opaque `GestureDetector`) but the 6 dp bar sits at the TOP of the cell (not centred), the caption `SizedBox(height: 20)` directly under it with a 4 dp gap; the bar block has no outer vertical padding. The widget itself applies the cap: captions render only when `captions != null`, `captions.length == count` and `count <= kSetBarCaptionMaxSets (5)`. The detail header gets `Key('session-detail-header')` on its outer Padding (P3a) so S-4317 measures `bar.top - header.bottom` in `[0, 8]` without a magic number.
- L-6 `ValueStepperRow` owns its outer margin: `Padding(horizontal: 20, vertical: 4)` around the `OmniSurface` (inner padding as D-5), replacing today's `Padding(horizontal: 16)`; the screen adds no spacers between rows and the hold weight row inherits it.
- L-7 `SetCountStepper` is `Padding(horizontal: 20)` + `OmniSurface(showShadow: false, padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2))` + `Row[ − , Expanded(Center(text)), + ]`; the text keeps today's style (`titleMedium`, letterSpacing 2.0, `textSecondary`, w500 as `_buildSetBar` sets it now: the style travels with the text, built in the screen and passed as a `String`; the widget applies the style). The two 48 dp buttons stay 48 dp, so the control is about 52 dp tall, shorter than a row (about 80 dp).

## Phases (each one agent run, at most 8 items; builders `crew-builder-app`)

Scopes are quoted globs. P1 and P2 are disjoint and run in parallel; neither runs the full suite (their named files only; reds in the files P3a/P3b migrate are expected while the other phase is in the tree). P3a after both; P3b after P3a; D after P3b. The lead runs the full suite after P3b and deletes `logged_values_line.dart`.

### P1 — A7/D-1/D-2/D-9 (state + screen glue)

Write scope: `lib/state/workout/timer_manager.dart`, `lib/state/workout/session_core_entry.dart`, `lib/state/workout/session_core_lifecycle.dart`, `lib/core/models/session_edit_snapshot.dart`, `lib/features/session/workout_session_screen.dart`, `test/entry_delete_rests_test.dart`, `test/logger_shell_screen_test.dart`, `test/watch_session_import_test.dart`, `test/watch_session_merge_test.dart`

1. [ ] Red state tests S-4301..S-4304 (id shape asserts of S-4302), both harnesses via `harnessFactories` — test/entry_delete_rests_test.dart · new file
2. [ ] `TimerManager.rekeyEntryRestsAfterDelete(effortId, deletedIndex)`: cache first, then `deleteEntryRestsForEffort` + `createEntryRest` per kept rest (new `entryIndex`, id `rest-<effortId>-<index>`); errors to `_setError` — lib/state/workout/timer_manager.dart
3. [ ] Call it from `deleteEntry` for every effort kind (set, timed, drill, round) — lib/state/workout/session_core_entry.dart
4. [ ] Red S-4318 (edit snapshot restores rests, both harnesses) — test/entry_delete_rests_test.dart
5. [ ] D-9: `entryRests` in `SessionEditSnapshot`, capture and restore (including re-created efforts), replace the stale NOTE — lib/core/models/session_edit_snapshot.dart; lib/state/workout/session_core_lifecycle.dart
6. [ ] D-2: in `_deleteSetAt` (both paths) clear and refill `_loggedSetKeys` of the effort via `_isSetLogged`; clear `_inProgressKeys` in the multi-set path; if the deleted set's rest was open call `cancelRestNotifications()` and `_lastRestPingFiredAt.remove(effortId)` — lib/features/session/workout_session_screen.dart
7. [ ] Screen tests S-4310, S-4319, S-4320, S-4321 (Mock, red first where marked) — test/logger_shell_screen_test.dart · ONE new group; touch no existing test
8. [ ] Rewrite S-327; re-derive S-337 under D-1 — test/watch_session_import_test.dart; test/watch_session_merge_test.dart

Done: `test/entry_delete_rests_test.dart` green on both harnesses; the new logger group green (`--plain-name`); S-327/S-337 green; the rest/state files listed in Readers (`state_test`, `watch_session_*`, `unified_rest_overlay`, `session_rest_closing_race`, `rest_timer_docked_strip`, `session_toolbar_rework`, `edge_case`, `entry_*`, `row_invariants_guard`) run green; analyze count not above 182.

### P2 — widgets: bar captions, no border, boxed rows (D-3, D-5, L-5, L-6)

Write scope: `lib/widgets/session/set_segment_bar.dart`, `lib/widgets/session/value_stepper_row.dart`, `test/set_shell_widgets_test.dart`, `test/value_stepper_row_test.dart`

1. [ ] Red widget tests: no border and all segments 6 dp (focused too); captions render under their segment only when `captions` has `count` entries and `count <= 5`, key `set-caption-$i`, blank text kept (row height 20 even when all blank), focused caption `textDominant`, others `textSecondary`; with 6 segments no caption widget; bar top-aligned in the 48 dp cell — test/set_shell_widgets_test.dart · S-4201/S-4202 migrated, new group
2. [ ] `SetSegmentBar`: optional `captions`, `kSetBarCaptionMaxSets = 5`, border and 10 dp focused height removed, bar at the top of its cell, caption row — lib/widgets/session/set_segment_bar.dart
3. [ ] Red tests: `ValueStepperRow` content is an `OmniSurface` descendant, 48 x 48 buttons unchanged, outer margin 20/4 — test/value_stepper_row_test.dart
4. [ ] `ValueStepperRow` wrapped as in L-6 — lib/widgets/session/value_stepper_row.dart

Done: the two test files green, analyze not above 182. Do not touch `SetCountStepper`, its S-4204 group or S-4203 (P3a/P3b).

### P3a — wiring: captions, pinned bar, one-line header, sets control (D-4, D-6, D-7, D-8, L-5, L-7)

Write scope: `lib/features/session/workout_session_detail_view.dart`, `lib/features/session/workout_session_list_view.dart`, `lib/features/session/workout_session_screen.dart`, `lib/widgets/session/set_count_stepper.dart`, `test/helpers/set_captions.dart`, `test/logger_shell_screen_test.dart`, `test/set_shell_widgets_test.dart`

1. [ ] Helper `setCaption(tester, i)` and `captionsPresent` (D-10) — test/helpers/set_captions.dart · new file
2. [ ] Red tests S-4311..S-4317, S-4322..S-4324 in a NEW group, and `SetCountStepper` `text:` tests (S-4204 migrated: middle text, no `SETS`, inside `OmniSurface`, keys/tooltips/48 dp unchanged) — test/logger_shell_screen_test.dart; test/set_shell_widgets_test.dart
3. [ ] `SetCountStepper(text:, canAdd:, removeIsExercise:, onAdd:, onRemove:)` per L-7; `label`/`count` removed — lib/widgets/session/set_count_stepper.dart
4. [ ] `_loggedValueText`: no zero-weight branch (`'$reps×$weightText'` for every `set`) — lib/features/session/workout_session_detail_view.dart
5. [ ] `_buildSetBar` returns the bar with `captions` (per-set `_loggedValueText`); the count text moves to the `SetCountStepper` `text`; `LoggedValuesLine` usage and the `logged_values_line.dart` import removed — lib/features/session/workout_session_detail_view.dart; lib/features/session/workout_session_screen.dart
6. [ ] Pin the bar: the bar block sits in the fixed column right under `_buildHeader` (horizontal 20, no vertical padding); the scroll column starts with the exercise controls then the `SetCountStepper` — lib/features/session/workout_session_list_view.dart · detail body
7. [ ] Header: one `Text('Exercise N / M · Section')` (just `Exercise N / M` for an empty name), one line, ellipsis; `Key('session-detail-header')` on the header's outer Padding; list-view and edit-mode headers unchanged — lib/features/session/workout_session_list_view.dart · `_buildHeader`
8. [ ] New group green; list the OLD tests that go red (expected, P3b's) in the report

Done: the new group and the `SetCountStepper` tests green; analyze not above 182 (the old readers may be red).

### P3b — reader migrations (tests only)

Write scope: `test/logger_shell_screen_test.dart`, `test/count_up_screen_test.dart`, `test/reps_screen_test.dart`, `test/sports_emphasis_redesign_test.dart`, `test/screen_widget_test.dart`, `test/set_shell_widgets_test.dart`, `test/helpers/set_captions.dart`

1. [ ] `_loggedLine` readers in `logger_shell_screen_test.dart` (:176, :205-206, :225, :244, :264, :285, :287 height assert, :298, :498 S-4221 anchor, :858, :1063) to the caption helper; S-4221 position asserts re-derived (`SETS` text gone; sets control below the exercise controls)
2. [ ] `count_up_screen_test.dart` :147-152 helper and :405; `reps_screen_test.dart` :115-120 helper and :455 to the caption helper
3. [ ] `sports_emphasis_redesign_test.dart` :449-459: focused segment by colour `primary.withAlpha(115)`, drop the height loop
4. [ ] Header readers: `logger_shell_screen_test.dart` :667/:672 and `screen_widget_test.dart` :9131 to `Exercise N / M · Main Workout`
5. [ ] Delete the S-4203 group (`LoggedValuesLine`, `loggedValuesText`) from `set_shell_widgets_test.dart`
6. [ ] Each touched file green on its own; report any other failure instead of fixing it

Done: the six files green, analyze not above 182.

### D — docs (after P3b) — crew-docs-keeper

Write scope: `docs/design_system.md`, `docs/widget_catalog/session_widgets.md`, `docs/modality_based_exercise_ui.md`, `docs/plans/2026-10-15-38f-logger-polish-plan/2026-10-15-38f-logger-polish-plan.evidence.md`

1. [ ] design_system.md shared-pieces table: remove the `LoggedValuesLine` row; the bar carries captions; boxed rows use `OmniSurface`
2. [ ] session_widgets.md: `SetSegmentBar` captions, `SetCountStepper` text, `ValueStepperRow` box
3. [ ] modality_based_exercise_ui.md: one-line header, captions at 5 sets or fewer, deleted logged set removes its rest (D-1)
4. [ ] Evidence file

Done: `test/docs_indexing_contract_test.dart` green; every behaviour sentence names an existing test.

## Scope-budget check (architect, 2026-10-15)

Hard limits: plan ≤ 800 lines (this file ~560 after completion ✓); ≤ 5 phases (0, P1, P2, P3, D = 5 ✓); ~1500 lines predicted production code (≈ 350: timer_manager ~40, session_core_entry ~10, snapshot+lifecycle ~50, screen ~30, three widgets ~120, detail_view ~60, list_view ~40 ✓). Soft signals: plan length > 500 (1), phases 5 > 3 (1) → 2 soft signals. Mitigation: the phase structure is the seed's own; P1/P2 scopes are disjoint; if the build overruns, the recommended split point is P3 item 8 + D into a second PR (the production code is complete without it, but A9's full-suite gate then needs the migrated readers x-excluded — the lead decides). Kept as one PR, flagged.

## Measurements wanted (lead, simulator/probe, after P3)

- Rendered height of a boxed `ValueStepperRow` and of the new boxed `SetCountStepper` at 390 width (A6: the sets box shorter than the reps/weight boxes).
- Bar-block height with captions at 5 sets (expected 48 + 20 = 68) and at 6 sets (expected 48).
- Confirm the header bottom stays 100 after the D-7 merge (probe baseline: header bottom 100, scroll body 116, bar top 137, sets stepper bottom 488, rest chip top 686, 198 dp free).
- Rest chip top with the new layout (198 dp free − ~20 captions − ~32 boxes ≈ 146 dp spare expected).

## Progress / Assumption Log / Feedback / Open questions

### Progress
- 2026-10-16 built by the crew: P1 (state), P2 (widgets), fix 1 (D-11 watch bridge), P3a (wiring), P3b (reader migrations), docs, prover (36 rows) + lead mutations (35 red, 1 no test), fix 2 (13 gap tests, all 13 mutations red), review APPROVE WITH FIXES (3 Major, 1 Minor), fix 3 (importer planned-set search, mutation red). Final: `flutter analyze` 182, 0 errors; full suite `+4893 ~1` all passed (baseline `+4846 ~1`); invariant grep clean.
- Seeded 2026-10-15 (lead). 38c landed (uncommitted). Phase 0 done 2026-10-15: base commit `80928669` plus uncommitted 38a/38b/38c; `flutter analyze` 182 issues, 0 errors; full suite `+4846 ~1` (all passed); layout probe at 390x844 (header bottom 100, scroll body 116, today's visible bar top 137, sets stepper bottom 488, rest chip top 686).
- 2026-10-15 architect: validated every D-1..D-8 pointer against the tree (38a/38b/38c landed); completed scenarios S-4301..S-4317 with fixtures; appended S-4318..S-4324, D-9, D-10, the D-5 finding, the Readers table, the phase table, the scope-budget check. Plan ready to build.

### Assumption Log
- A-1 (lead, 2026-10-16) Rests are positional everywhere the phone reads them; row numbers are not renumbered after a delete. Held for the screen, the delete re-key, the watch bridge (D-11) and the importer's planned-set search (fix 3). NOT held, and left for a follow-up PR: the importer WRITES rests at the row number + 1 (`index + 1`) and its wrist-delete path never re-keys surviving rests (review findings 1-2, the write half and the delete half). Both only matter after a phone-side middle delete in a live watch merge.
- A-2 (lead) `_lastRestPingFiredAt.remove(effortId)` after a delete has no test (review finding 3): a stale entry would delay the next rest's first ping by one interval. Accepted as an unproven guard and reported.
- A-3 (lead) Interval and hold screens were not looked at on the device (they share the bar, header, boxes and sets control with the round and reps screens that were).

### Feedback
- (none yet)

### Open questions
- (owner, report only) With the border gone a logged set that is also focused cannot be told from a logged set by the bar alone: the caption colour (5 sets or fewer) and the sets control text carry the focus. Say if you want a visible cue on the bar itself.
- RESOLVED 2026-10-16 (owner): keep `OmniSurface` as built; no translucent-grey token. (lead) D-5: `OmniSurface` is opaque and theme-tinted, not "greyish half-transparent" (see the D-5 finding above). Ship it as-is, or approve a new translucent-grey token? A raw colour is banned by the ui_standards contract.
- (lead) D-1 deliberately flips S-327's D-167(b) contract ("a rest is not an entry: deleting the set deletes the observations and nothing else") for the phone's delete path — owner point 7 sanctions it; the watch importer's own rest handling is untouched.
- (lead) A1's "with no section name just `Exercise 1 / 4`" is reachable only via a segment whose name is the empty string (a NULL name falls back to `'Block N'`, `session_summary_builder.dart:419`); S-4322 tests that path by seeding the repository directly.
- (lead) P1's full-suite gate must run when P2's edits are quiescent (both phases may edit in parallel in one tree); the lead serialises that one run.
