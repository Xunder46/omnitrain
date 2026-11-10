# Review: 134b + 134c1 + 134d · the phone side of the calories-burned work · ff398e1a..working tree

Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: full suite run by the lead after this review (brief says so; the lead's counts for the touched files: 12+10, 66, 32+, 26, 8+; analyze 181 = baseline)

Diff vs Predicted Files: conforms for the three plans. The rest of the uncommitted tree belongs to 134a (already reviewed) and the 134e wrist-rest unit (`lib/data/models/models.dart`, the repositories, `main.dart`, `session_summary_screen.dart`, the watch engine Swift files, `ios/.../HealthKitSensorFeed.swift`, `docs/rest_tracking.md`, …); none of those files is claimed here.

## Findings

1. [Minor] `lib/features/session/workout_session_list_view.dart:504-520, 571-587` — Decision Ledger D-13444 says both bars become `Row(children: [_buildSessionTimeWidget(theme), const Spacer(), if (!widget.editMode) _buildSessionCaloriesWidget(theme)])`, but the code builds `Row([_buildSessionTimeWidget(theme), const Spacer(), Flexible(fit: FlexFit.tight, flex: 20, child: _buildSessionCaloriesWidget(theme))])` and the chip wraps its content in a `FittedBox(fit: BoxFit.scaleDown)`. A maintainer checking the code against the ledger sees a discrepancy. No code change required: the FittedBox scale-down on the narrowest phone is a decision the lead lists as owner-seen, and without the `Flexible` the chip would overflow the 320 dp bar instead of shrinking. Fix: none needed in code; the lead may amend D-13444's wording. Guard: `test/session_live_calories_test.dart` S-13445, S-13447 geometry.

## Answers to the brief's five questions

**1. Orphan energy rows across the four call sites (severity: none).**
`_attachMeasuredEnergy` (`watch_session_importer.dart:1736`) is reached only through `_attachSessionSummary` (:1713), whose four call sites are each preceded by a guard that the session row exists:
- import create (`run` → `_createSession`, :619): `_createSession` first calls `_repository.createSession(...)` (:585-603) and only then `_attachSessionSummary` — the row it wrote is the target id (`sessionId` is the created session's id).
- import top-up (`run` else-branch, :516): the caller `_applyImport` guarantees `existing != null` (an `existing == null` pass with `deletedByUser || live.isEmpty` returns `_consume` at :243-248 and never runs).
- followed end (:257): guarded by `end.status == _completed && await _repository.getSession(watchSessionId) != null` (:255-256).
- merge (`_mergeHeld` → :331): guarded by `if (existing == null) return _consume(unapplied)` at :430.
No call site can store a row for a session id without a `TrainingSession` row, so neither a Hive orphan nor a documented-schema foreign-key violation is reachable.

**2. `_burnedInWindow` vs `_trainingDayKeys` (severity: none).**
Both (`stats_progress_service.dart:2248-2261` and :2216-2235) skip `endedAtMs == null`, key the session on `OmniDateUtils.startOfDayMs(DateTime.fromMillisecondsSinceEpoch(s.startedAtMs))` — the local start day — and take the same `[OmniDateUtils.startOfDayMs(from), OmniDateUtils.startOfDayMs(to)]` window. The callers pass the same pair, `windowStart, yesterday`, built identically for both (:2163-2167, :2157, :2187). A rolling session that was finished (gains `endedAtMs`), a duration edit after the end (rewrites only `endedAtMs`), and a session started before midnight all feed both helpers the same `startedAtMs`/`endedAtMs`, so the burned count cannot disagree with a training-day label or read another day. The one asymmetry — `_burnedInWindow` also skips row-less sessions — is D-13431, decided and tested (S-13432).

**3. The active session screen (severity: none).**
- No `setState` after dispose: every write goes through `_updateUi`, which checks `mounted` (`workout_session_screen.dart:169-172`); `_loadLiveWeight` additionally checks `mounted` after its await (`workout_session_global_timer.dart:44-52`).
- No leaked timer: `_ticker` is created only in `initState` under `!widget.editMode` (:265-267) and cancelled in `dispose` (:1865).
- Early return for an ended session: `_tick` returns when `session == null` or `session.endedAtMs != null` (:11-15), so `_elapsedSecs`/`_liveKcal` freeze instead of advancing past the end.
- `_loadLiveWeight` is `unawaited`; an awaited result cannot throw into the tick, and an error thrown inside it (`getLatestMeasurement` on Mock/Hive is a plain list read, `mock_workout_repository.dart:589-594`, `hive_workout_repository.dart:1315-1319`) would surface as an unhandled zone error — the same contract the screen's other unawaited loads (`_loadExerciseNoteForIndex` :1034/:1161) already accept. Not a regression of this change.
- The 60th-tick counter (`_liveTicks`) only advances in the exercised branch, so a first exercise added before the 60th tick shifts the next re-read by that many ticks — harmless (S-13445b pins the re-read).

**4. Fuel card caption at 320×568 (severity: none).**
Available width: Stats screen `ListView` padding 20 + 20 (`stats_screen.dart:344`) plus the row's inner `Padding(EdgeInsets.all(20))` (`fuel_section.dart` build) = 320 − 80 = 240 dp. Caption style `labelSmall` = fontSize 11, letterSpacing 0.5, M3 default height 1.45 (`omni_theme.dart:785-789`). Longest realistic strings: `Training days: 1950 kcal · 123 g protein` ≈ 209 px, `Burned per session: ~310 kcal · 5 sessions` ≈ 220 px at scale 1.0 — both fit on one line within 240 dp. At scale 1.3 they reach ≈ 272 / ≈ 286 px, so the line wraps once, which `maxLines: 2` (`fuel_section.dart:358-372`) admits; clipping would need more than 2 × 240 = 480 px, reachable only with a value roughly twice again the realistic magnitudes (e.g. `99999 kcal · 9999 sessions` ≈ 300 px at 1.3, still inside two lines). No clipping or overflow.

**5. Out-of-scope hunks (severity: none).**
Every hunk in the three plans' files serves its plan: `fuel_summary.dart` (three fields), `stats_progress_service.dart` (one call site + `_burnedInWindow`), `fuel_section.dart` (labels, `_split`, `_burned`, `maxLines`, `fuel_burned`), `message_validator.dart` (one gate row), `watch_session_importer.dart` (doc comment, `_attachMeasuredEnergy`, `_End` field), `active_energy_service.dart` (rename + `liveKcal`), `workout_state.dart` (field + passthrough), the three session-screen files (fields, tick, chip, two bars), the wire files (schema row, both validator gates, three fixtures, manifest rows, PROTOCOL.md bullet/table/changelog row), and the six test files. No debug leftover, no unrelated edit, no formatter reflow of untouched code. The only plan-vs-code divergence is finding 1.

## Assumption Log rulings

134b — A-1 ratified (the burned line is drawn only in the `showsAverages` block, `fuel_section.dart:236-279`; S-13434's 2-logged-day arm asserts the absence). A-2 ratified (any estimated row sets the flag; S-13431 states both arms).
134c1 — A-1 ratified (schema `minimum: 0`; the importer's `kcal <= 0` return, `watch_session_importer.dart:1739-1741`; S-13462 covers absent/0/-5/string/NaN on both a row-less and an estimated session). A-2 ratified (D-13464's accepted edge: a wrist end stores into a session the phone holds while it has not ended; the "phone keeps it" half rests on 134a's settle-never-overwrites-measured invariant, not re-proven in this unit's tests — as the plan says).
134d — A-1 ratified (the chip is always `~N kcal` or `—`: `_liveCaloriesLabel`, `workout_session_global_timer.dart:54-58`). A-2 ratified (resistance fallback in `liveKcal`, `active_energy_service.dart:85-90`; S-13448).

## Scenario coverage

134b: S-13430 → `test/fuel_burned_summary_test.dart:150` · S-13431 → :213, :242 · S-13432 → :267, :299 · S-13433 → :313 · S-13434 → `test/fuel_section_widget_test.dart` (five S-13434 tests) · S-13435 → same file (the net/surplus/deficit sweep).
134c1: S-13460 → `test/watch_energy_import_test.dart:153` · S-13461 → :202 · S-13462 → :280 loop (estimate arm), :308 (no-row arm), :334, :344 (NaN refused at staging) · S-13463 → :381, :410 · S-13464 → :438 · S-13465 → :488 · S-13466..S-13468 → the fixture walks (`test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift`) over the three manifest rows (read in `fixtures/manifest.json:231-236, 913-928`).
134d: S-13440 → `test/active_energy_live_test.dart:65` · S-13441 → :139 · S-13442 → :210 · S-13443 → :246 · S-13444 → :291 · S-13445(+b) → `test/session_live_calories_test.dart:160, 175` · S-13446 → :210 · S-13447 → :219 group · S-13448 → :242 · S-13449 → :254 group (no-exercise arm, edit-mode arm, S-13449c :279 for the empty-state bar).

## Docs delta
134b: docs/stats_screen.md Training-days-and-rest-days heading → applied (stats_screen.md:432). docs/stats_screen.md **Burned per session.** → applied (:393; texts true, named tests all verified to exist). stats_screen.md not-enough-logged-days row → applied (:637). stats_screen.md FuelSummary summary row → applied (:642). docs/widget_catalog.md → applied (:43). docs/data_models.md → applied (:491-494; `burnedKcalAverage`, `burnedSessionCount`, `burnedIsEstimate` match the model).
134c1: docs/watch_session_capture.md followed-sentence → applied (:244-246; the sentence's added clause runs on into "from it", matching the plan's New marker verbatim). **Measured active energy.** → applied (:248-260; test names verified). docs/data_models.md activeEnergyKcal → applied (:665).
134d: docs/modality_based_exercise_ui.md **Live calories.** → applied (:371-393; each claim traced to code and each named test read). services_and_utils.md D-13407 sentence extension → applied (:81). latestWeightKg() → applied (:87). liveKcal( → applied (:88). latestBodyWeightKg → applied (:90).
No doc edit outside the tables was found in the three plans' docs.
