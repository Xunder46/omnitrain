# Plan 24 — The Stats screen explains itself

Status: SEEDED by the governor 2026-10-12 (crew-architect expands it). Base commit: see `.work/2026-10-12-24-stats-clarity/base.txt`.
Branch: the crew's working branch (`claude_develop`); the owner commits.

## Goal and acceptance

An owner's phone screenshot showed three places where the finished Stats redesign says nothing: an empty outlined
rectangle under "Training Mix", no sentence anywhere about the workouts, and numbers in the Instruments list whose
meaning is not stated. A crew audit (`.work/crew/2026-10-12-stats-audit/sheet-a|b|c.md`) found no missing feature and no
bug: every one is designed behaviour that reads as broken. The owner approved all three fixes on 2026-10-12.

Acceptance, as the user sees it:

1. **Signals locked.** While the Mix layer exists but fewer than 4 weeks are rated, a SIGNALS section appears in the
   place the layer will later occupy, reading `Unlocks after 4 weeks of rating your workouts — 3 of 4 so far.`
2. **Weekly strip labelled.** Under the eight columns a caption reads the oldest week's date on the left and
   `this week` on the right. When none of the eight weeks has any training, the strip is replaced by one line:
   `No training in the last 8 weeks. Last session: Aug 14.`
3. **Instruments explained.** One muted line under the first Instruments header says what the line and the change
   mean, with the real day count; resistance, cardio and pace rows say what their number is (`Est. 1RM`, `Best set`,
   `Total time`, `Best pace`).

Nothing else changes: no value, delta, sparkline, threshold or signal rule is touched.

## Feature invariants

The rules that bite in this unit; the project-wide ones live in `docs/global_conventions.md`.

- **One gate, not two.** `signalsGateMet(mix)` (`lib/core/models/signals.dart:72`) decides both whether anything is
  evaluated and which section renders. The locked section must be reachable in exactly the state the load already
  produces when the gate is unmet — `_signalsData == null`, because `stats_screen.dart:166-179` stores
  `gateMet ? resolveSignals(...) : null`. No second, independently computed condition may decide it.
- **Locked draws nothing.** The locked line is a function of the payload (`ratedBaselineWeeks`) alone: no clock, no
  repository read, no dismissal store.
- **Copy numbers come from constants.** The locked line quotes `kTrainingLoadMinRatedWeeks`, the empty-strip line
  quotes `kMixStripWeeks`; neither number is written as a literal in a widget.
- **The screen shows the service's number.** `lastSessionDay` is filled in `_mixPayload` and nowhere else; the caption's
  count is `StatsWindow.dayCount`, whose arithmetic is pinned equal to `previousRangeFor`'s rather than copied.
- **`WorkoutRepository` stays the only persistence dependency** of the service and the widgets; no new read, no `await`
  inside a session loop, no second walk of history.
- **Hive and Mock agree.** Every new field and payload is asserted on both harnesses; `MixLayerData`'s parity shape is
  `_layerShape` (`test/mix_layer_service_test.dart:160`).
- **Widget tests are Mock-first and seed in `setUp`.** A repository call or a real `Future.delayed` inside a
  `testWidgets` body hangs under FakeAsync at ~0% CPU; a red Mock group is fixed before its Hive group is read.
- **Additive only.** One optional model field, one optional constructor parameter, new leaves inside two existing
  widgets. Nothing is renamed, reordered or re-scoped, and `MixLayerData`'s four external constructions keep compiling.
- **No stored shape changes.** `lib/data/models/models.dart` and `scripts/sqlite_schema.sql` stay untouched, so this unit
  runs no codegen and no migration.
- **Presentation stays presentation.** No widget here gains a repository, a service, a clock or a navigation.
- **Docs stay under the guard and name tests.** Each edited doc file stays below the 52,429-byte warning band
  (`test/docs_indexing_contract_test.dart:49,54,156`) and every behaviour sentence names a test that exists.

## Decision Ledger

- **D-4001 Locked Signals section.** `lib/features/stats/stats_screen.dart` `build()` (the `children:` list, after the
  `MixLayerSection` block, currently `if (_signalsData != null) ...[ SignalsLayerSection(...) ]`) gains a branch:
  `else if (_mixLayer != null && !signalsGateMet(_mixLayer))` renders `SignalsLockedSection(ratedWeeks:
  _mixLayer!.ratedBaselineWeeks, themeColors)` then `SizedBox(height: 24)`. Mix null renders nothing, as today.
  The signals are still NOT evaluated when the gate is unmet (`gateMet ? ... : const <SignalCard>[]` in `_loadData` is
  untouched). `SignalsLayerSection` and the key `signals_layer` stay absent in that state, so the existing
  `findsNothing` assertions on `signals_layer` (e.g. `test/sustained_high_load_signal_screen_test.dart:693`) stay true.
  This supersedes the "nothing at all" half of D-1006 (`docs/plans/2026-10-03-06a-...`); the evaluation half stands.
- **D-4002 Locked copy.** `lib/core/models/signals.dart` gains `String signalsLockedLine(int ratedWeeks)` returning
  `'Unlocks after $kTrainingLoadMinRatedWeeks weeks of rating your workouts — ${ratedWeeks.clamp(0, kTrainingLoadMinRatedWeeks)} of $kTrainingLoadMinRatedWeeks so far.'`
  (the em dash is U+2014, like `kSignalQuietLine`). `SignalsLockedSection` (new, in
  `lib/features/stats/widgets/signals_layer.dart`) = `OmniCardHeader(title: 'SIGNALS')` + the line as
  `bodyMedium` in `themeColors.textSecondary`, `Key('signals_locked')`, the line `Key('signals_locked_line')`.
  Presentation only: no clock, no repository.
- **D-4003 Strip caption.** In `lib/features/stats/widgets/mix_layer.dart` `build()`, a `Row` under `_buildStrip` with
  two `labelSmall` `textMuted` texts: `OmniDateUtils.formatShort(layer.weeks.first.weekStart)` (`Key('mix_strip_start_label')`)
  at the left and `'this week'` (`Key('mix_strip_current_label')`) at the right (`MainAxisAlignment.spaceBetween`).
- **D-4004 Empty strip.** In the same `build()`: when every `layer.weeks[i].measure <= 0` (all `kMixStripWeeks`), the second
  `_measureText(theme)`, `_buildStrip` and the caption are NOT built; one `Text` is built instead,
  `Key('mix_strip_empty')`, `labelSmall`/`bodySmall` `textMuted`:
  `'No training in the last $kMixStripWeeks weeks.'` plus, when `layer.lastSessionDay != null`,
  `' Last session: ${OmniDateUtils.formatShort(lastSessionDay)}.'`. The bar, legend and notes above are unchanged.
- **D-4005 `MixLayerData.lastSessionDay`.** `lib/core/models/training_load.dart` `MixLayerData` gains
  `final DateTime? lastSessionDay;` as an optional constructor parameter (default `null`), so the four call sites that
  build `MixLayerData(` outside the model keep compiling. `StatsProgressService._mixPayload`
  (`lib/core/services/stats_progress_service.dart` ~710-802, the `for (final session in history.sessions)` loop, which
  already skips `session.endedAtMs == null`) tracks the latest `startedAtMs` and passes `localMidnightDay(...)` of it.
  Rolling sessions count (they are completed sessions). It is all history, not only the window and not only the strip.
- **D-4006 Instruments caption.** `lib/features/stats/widgets/instrument_list.dart` `build()` adds, after the first
  section's `OmniCardHeader` (`if (i == 0)`), one `Text` `Key('instrument_caption')`, `labelSmall` `textMuted`:
  `'Line: each training day in the window · Change: vs the ${window.dayCount} days before it'` — singular
  `'vs the day before it'` when `dayCount == 1`. Same text for period windows and recent-days windows.
- **D-4007 `StatsWindow.dayCount`.** `lib/core/models/stats_progress.dart` `StatsWindow` gains `int get dayCount`:
  `DateTime.utc(toMs.y,m,d).difference(DateTime.utc(fromMs.y,m,d)).inDays + 1`, i.e. exactly the arithmetic of
  `StatsProgressService.previousRangeFor` (`stats_progress_service.dart:1228-1246`). `previousRangeFor` is NOT edited in
  this plan (phase scopes are disjoint); a test pins that `dayCount` equals the previous range's day count.
- **D-4008 Row labels.** `lib/features/stats/widgets/native_value_format.dart` gains
  `String? nativePrimaryLabel(NativeMetric metric)`: `estimatedOneRepMax` -> `'Est. 1RM'`, `reps` -> `'Best set'`,
  `duration` -> `'Total time'`, `pace` -> `'Best pace'`, `hold`/`rounds`/`roundMinutes` -> `null` (the isometric and sports
  rows already carry a labelled second figure). `InstrumentRowTile._secondaryLine` (`instrument_row.dart:~27-40`) puts the
  primary label FIRST, then the existing `Total hold 3:02`-style part, then bpm, then cadence, joined by `' · '`.
  Only the Instruments rows change; Records & Trends and Exercise Progress format values elsewhere and are unaffected.
- **D-4009 Docs.** `docs/stats_screen.md` (36,902 B) and `docs/signals.md` (47,458 B) are edited in place, adding well under
  1 KiB each; `signals.md` must stay below the 52,428 B warning band. The Mix strip, Signals gate and Instruments row
  paragraphs are corrected; the D-1006 sentence "renders nothing at all" is restated as "evaluates nothing and shows a
  locked line".
- **D-4010 No other behaviour changes.** Values, deltas, sparkline shape and omission rule, window resolution, rated-week
  counting, signal rules, primer copy, Records & Trends: untouched.

## Existing-functionality impact

Searches run against the base commit for this plan; every effect names the guard that catches it.

| Touched surface | What already reads it (search → result) | Effect | Guarded by |
|---|---|---|---|
| The `if (_signalsData != null) ...[` element (`stats_screen.dart:294-301`) | `signalsGateMet` → `signals.dart:72`, `stats_screen.dart:145,208`, `signals_service.dart:42`; `signals_layer` → 43 hits in 9 files; `find.text('SIGNALS')` → 16 hits in 11 files | one new element appears for gate-unmet screens. Readers that assert the key `signals_layer` is absent stay true (the locked section uses a different key); the two that assert the *word* SIGNALS is absent flip, by design | S-4002/S-4003/S-4004/S-4013; the two rewritten guards in P1 items 4-5 |
| `signals_layer.dart` as a source file (`_kLayerPath` guard, `test/signals_layer_screen_test.dart:74,442-466`) | reads the file's source: forbids `Color(0x` and `Colors.`, allows only fields the `OmniThemeColors` typedef declares | the new class must be drawn with `themeColors.textSecondary` and a `bodyMedium`/`labelSmall` style, with no literal | the existing guard, untouched and re-run (P1 item 2) |
| `MixLayerData` (`training_load.dart:103`, six fields) | `MixLayerData(` → 4 constructions outside the model: `stats_progress_service.dart:783`, `test/cardio_efficiency_drift_signal_screen_test.dart:476`, `test/signals_framework_test.dart:34`, `test/signals_service_test.dart:66`; all four are named-argument | one additive optional field: all four compile unchanged, and `test/signals_framework_test.dart:34` already passes `weeks: const []` | S-4009 + `_layerShape` parity (P2 item 5) |
| The strip (`_buildStrip`, `mix_layer.dart:279`) | `'by time'`/`'by load'`/`mix_week_` → 38 hits, every one in `test/mix_layer_screen_test.dart` | the caption and the empty line are new keys; the existing `by time`, `mix_week_7` and `mix_week_current` assertions are unmoved except where D-4004 replaces the strip | S-4005..S-4008, S-4014..S-4016 |
| `MixLayerSection` (`mix_layer.dart:33`) | `MixLayerSection(` → constructed only at `stats_screen.dart:287`, never in `test/` | the caption and the empty line are reachable only through `computeMixLayer`'s payload (8 weeks). `computeMixPeriod`'s `weekStarts: const []` (`stats_progress_service.dart:539`) never reaches the widget through the screen | S-4016 is the only reader of the `weeks: []` shape at widget level |
| The Signals gate in the readers | `signals_layer` absent is asserted by `test/sustained_high_load_signal_screen_test.dart:693` (no history → mix null) and by the two guards above; `find.text('SIGNALS')` is also asserted on **Home** at `test/screen_widget_test.dart:2314-2325` (a different screen) | none of these move: S-1714 is Home, and a null mix still renders nothing | P1 Done Criteria re-run all three files |
| `StatsWindow` (`stats_progress.dart:168-210`) | `previousRangeFor` (`stats_progress_service.dart:1228-1246`), called by `computeInstrumentSections` (`:1154`) and read by six test files | one new getter; `previousRangeFor` is not edited, so its callers are unmoved | S-4011 pins `dayCount == previousRangeFor(window)`'s length for four windows |
| `_secondaryLine` (`instrument_row.dart:30-40`) | `nativeSecondaryLabel`/`_secondaryLine` → 32 hits in 8 files; the row's texts are asserted in `test/instrument_list_screen_test.dart:442-470` | resistance and cardio rows gain exactly one secondary `Text`; isometric and sports rows keep their exact strings and counts | S-4012/S-4019; the rewritten `hasLength(3)` guard (P3 item 5) |
| `nativeSecondaryLabel` (`native_value_format.dart:66-80`) | also read by `exercise_progress_screen.dart:152` and its tests | not edited. `nativePrimaryLabel` is a separate table over the primary metric, so Exercise Progress and Records & Trends keep their wording | D-4008; the new `nativePrimaryLabel` group in `test/instrument_change_format_test.dart` |
| `instrument_row_<id>` (`instrument_row.dart:56`) | `instrument_row_` → 21 hits in 4 files: the key itself, the `_rowTexts` helper (`test/instrument_list_screen_test.dart:51,79`), the four keys at `test/stats_legacy_removal_test.dart:438-441`, and `'instrument_row_'` as a forbidden fragment for `stats_screen.dart`'s source at `:120` | the key is unmoved, so every reader that finds a row by key still finds it — only the row's inner `Text` list grows | S-4012/S-4019; `test/stats_legacy_removal_test.dart` re-run in P3's Done Criteria |
| `instrument_list.dart`'s header loop (`:62-90`) | `test/stats_legacy_removal_test.dart:63-68,444` asserts each of `Resistance`/`Cardio`/`Isometric`/`Sports` renders exactly once; `test/header_standardization_test.dart:2860-2900` iterates only `['ALL TIME']` | the caption is one `Text` whose data is not a section title, added under the first header only, so neither guard moves | S-4018; both files are in P3's Done Criteria |

## Core scenarios (the architect adds edge scenarios; fixtures reuse the existing screen-test seeders)

- **S-4001** 3 rated baseline weeks (`_seedGateUnmet` in `test/signals_layer_screen_test.dart:392`): `signals_locked_line` text is
  `Unlocks after 4 weeks of rating your workouts — 3 of 4 so far.`; no `signals_layer`, no `signals_quiet_line`; stub signals
  evaluate 0 times; the section sits between `mix_layer` and `ALL TIME` (top-left `dy` ordering). Fails today: nothing renders.
- **S-4002** 0 rated weeks: `0 of 4 so far.` The number never exceeds 4 (`signalsLockedLine(9)` returns `4 of 4`).
- **S-4003** Gate met (4 rated weeks): `signals_locked` absent; `signals_layer` or the quiet line present as today.
- **S-4004** Mix layer null (sessions exist but the window has no time): no `signals_locked`.
- **S-4005** Normal data, `startOfWeek` `monday` then `sunday`: `mix_strip_start_label` equals `formatShort(` oldest column's week start `)`
  for that setting; `mix_strip_current_label` reads `this week`; both below the columns.
- **S-4006** Every completed session started before `startOfWeek(now) - 49 days` (the screenshot's data), last one on a known day: exactly
  one `by time` text; no `mix_week_*` keys; no caption keys; `mix_strip_empty` reads
  `No training in the last 8 weeks. Last session: <formatShort(that day)>.`; the bar still renders.
- **S-4007** Only the current week has training: strip shown, `mix_strip_empty` absent. **S-4008** Only the oldest of the eight weeks: same.
- **S-4009** Service: `computeMixLayer` over a finished session on day A and a later finished session on day B plus an unfinished one on day C > B:
  `lastSessionDay == localMidnightDay(B)`.
- **S-4010** Instruments caption exactly once (under the first section, never under the second): windows of 14, 20 and 1 calendar days read
  `14 days`, `20 days` and `the day before it`.
- **S-4011** `StatsWindow.dayCount` equals `previousRangeFor(window)`'s day count for those three windows.
- **S-4012** Reps row `Best set`; e1RM row `Est. 1RM`; cardio duration row `Total time`; pace row `Best pace`; isometric row still
  `Total hold 3:02` with no label before it; sports row unchanged; a pace row with a heart rate reads `Best pace · 148 bpm`.
  The existing test `instrument_list_screen_test.dart:~442-470` ("Resistance has no secondary line at all") is rewritten.

## Edge scenarios

Appendix, not a renumbering: the builder writes these as groups in the files P1-P3 already own.

- **S-4013 — the fixture S-4001 needs** (`test/signals_layer_screen_test.dart`). Seeded `_seedGateUnmet` has **no ratings**
  (`_seedLifting` takes `int? rating` and the fixture passes none, so `sessionFeeling == null`), and
  `_mixPayload` (`stats_progress_service.dart:748-752,770`) counts a baseline block as rated only when
  `session.sessionFeeling != null` — so it reports `0 of 4 so far.`, not S-4001's `3 of 4 so far.`. New fixture
  `_seedGateUnmetThreeRatedWeeks` = `_seedPeriod(name: 'Test Block', daysAgo: 10)` + `_seedGateUnmet`'s three unrated
  sessions + `_seedRatedBaseline(fromDay: 10, offsets: const [20, 40, 60])` (baseline days 30/50/70 fall in blocks
  9/6/3 of the twelve 7-day blocks `baselineBlockStarts` tiles, `training_load.dart:140-150`) → `ratedBaselineWeeks == 3`.
  Expected: `signals_locked_line` reads `Unlocks after 4 weeks of rating your workouts — 3 of 4 so far.`, no
  `signals_layer`, no `signals_quiet_line`, no `signal_card_*`, a registered stub whose condition is met still evaluates
  0 times, and `dy(mix_layer) < dy(signals_locked) < dy('ALL TIME')`. Fails today: no section exists.
  Prover: `prove-red <base> test test/signals_layer_screen_test.dart -- <the plan's carried files>` (the key cannot exist
  at base); mutations that must redden it — drop `.clamp` in `signalsLockedLine`, or pass `kTrainingLoadMinRatedWeeks`
  instead of `_mixLayer!.ratedBaselineWeeks`.
- **S-4014 — the caption's two ends** (`test/mix_layer_screen_test.dart`). The S-4005 fixture (a completed session in each
  of the eight weeks), pumped twice: `settingsState.setStartOfWeek('sunday')` then `'monday'`.
  Expected: `mix_strip_start_label` is `OmniDateUtils.formatShort(weeks.first.weekStart)` — the week containing `now`,
  shifted 49 calendar days back, so the two settings give two different dates; `mix_strip_current_label` is `'this week'`
  under both; both labels' `dy` is below `mix_week_7`. Fails today: no caption exists.
  Prover: base `prove-red`; mutation — `.last` instead of `.first` makes the left label the current week's own start.
- **S-4015 — which session the empty line names** (`test/mix_layer_screen_test.dart`). Fixture: a period window
  (`_seedPeriod(daysAgo: 10)`), one completed session on day 60, one on day 55, an unfinished session today (written
  directly with `endedAtMs: null`), and nothing in the last eight weeks. Expected: `mix_strip_empty` reads
  `No training in the last 8 weeks. Last session: <formatShort(day 55)>.` — the latest **completed** session, not the
  oldest (60), not the window's last day, and not today's unfinished one; the service's own payload reports
  `lastSessionDay == localMidnightDay(day 55)`; the elements D-4004 leaves alone (bar, legend, notes) are still built.
  Fails without the change: the field does not exist and the line does not exist.
  Prover: mutation — track `startedAtMs` without the `endedAtMs == null` skip (`stats_progress_service.dart:726`) makes
  the line name today.
- **S-4016 — the payload the widget was never built from** (`test/mix_layer_screen_test.dart`). Pump `MixLayerSection`
  directly (never done in `test/` today) with `MixLayerData(measure: MixMeasure.time, segments: const [],
  baselineSegments: const [], unratedSessionCount: 0, ratedBaselineWeeks: 0, weeks: const [])` — the shape D-1204's
  `computeMixPeriod` returns (`stats_progress_service.dart:539`) and `test/signals_framework_test.dart:34` already builds —
  plus a resolved `StatsWindow` and theme colours. Expected: it builds without an exception, renders no
  `mix_strip_start_label`, no `mix_strip_current_label`, no `mix_strip_empty` and no `mix_week_*`. Fails without the
  change: D-4003's `.first` throws on an empty list, and D-4004's "every week is empty" is vacuously true and would print
  a claim the payload cannot support. Prover: base `prove-red`; mutation — remove the `weeks.isNotEmpty` guard.
- **S-4017 — the number is the comparison length, not the chip's** (`test/instrument_list_screen_test.dart`).
  `_seedFlagship` (`:173`, days 1-14 are the window) → the chip reads `Last 14 training days`, while the caption's number
  is the window's span, 15 days, because `previousRangeFor`'s `to` is end-of-today (`stats_progress_service.dart:1228-1246`).
  Expected: `instrument_caption` reads `Line: each training day in the window · Change: vs the 15 days before it`, and the
  test asserts that 15 equals `StatsProgressService.previousRangeFor(window)`'s day count **and** that it differs from
  `window.recentDays` for this fixture. Fails today: no caption exists. Prover: mutation — print `window.recentDays`.
- **S-4018 — one caption, under the first header** (`test/instrument_list_screen_test.dart`). `_seedFlagship`:
  `instrument_caption` findsOneWidget; `dy(first 'Resistance' header) < dy(caption) < dy('instrument_row_ex-squat')`;
  `find.text('Resistance')` still findsOneWidget (one `Text`, never a repeated title); no `Line: each training day`
  text under the second header. Fails today: no caption exists. Prover: base `prove-red`; mutation — build the caption
  under every header.
- **S-4019 — the values are untouched** (`test/instrument_list_screen_test.dart`). On `_seedFlagship`, the squat row's
  texts are exactly `[name, 'Est. 1RM', figure, change]`, and the figure string equals
  `formatNativeValue(row.summary.best, settingsState)` (`native_value_format.dart:46`) read from the service payload in
  the test — the same helper `test/instrument_list_service_test.dart:575` uses — so the label cannot hide a reformatted
  number. The isometric and sports rows keep their exact text lists. Fails today: the label is missing and the row has
  three texts. Prover: mutation — append the label after the other parts, or reformat the figure.
- **S-4020 — the new lines use existing tokens** (`test/mix_layer_screen_test.dart`,
  `test/instrument_list_screen_test.dart`). The rendered `Text` widgets for `mix_strip_start_label`,
  `mix_strip_current_label`, `mix_strip_empty` and `instrument_caption` carry `OmniTheme.colors.textMuted`; the locked
  line keeps `themeColors.textSecondary` (asserted in P1's file). Fails today: the widgets do not exist.
  Prover: base `prove-red`; mutation — swap a token for a literal colour.

**Acceptance map.** 1 → S-4001, S-4002, S-4003, S-4004, S-4013. 2 → S-4005, S-4006, S-4007, S-4008, S-4014, S-4015,
S-4016. 3 → S-4010, S-4011, S-4012, S-4017, S-4018, S-4019, S-4020.

## Phase outline (the architect fixes item wording; every phase one agent run, at most 8 items)

All phases owner `crew-builder-app`. P1, P2, P3 have disjoint write scopes; at most 2 run at once, only the last one runs the full suite.

- **P1 Signals locked (parallel with P2).** D-4001, D-4002; scenarios S-4001..S-4004.
  Scope: `lib/core/models/signals.dart`, `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/stats_screen.dart`,
  `test/signals_layer_screen_test.dart` (the S-1702 group is rewritten to the new behaviour; keep its other assertions).
- **P2 Strip (parallel with P1).** D-4003, D-4004, D-4005; S-4005..S-4009.
  Scope: `lib/core/models/training_load.dart`, `lib/core/services/stats_progress_service.dart`,
  `lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart`, `test/mix_layer_service_test.dart`.
- **P3 Instruments (after P1 and P2; runs the full suite).** D-4006, D-4007, D-4008; S-4010..S-4012.
  Scope: `lib/core/models/stats_progress.dart`, `lib/features/stats/widgets/instrument_list.dart`,
  `lib/features/stats/widgets/instrument_row.dart`, `lib/features/stats/widgets/native_value_format.dart`,
  `test/instrument_list_screen_test.dart`, `test/instrument_change_format_test.dart`, new `test/stats_window_day_count_test.dart`.
- **P4 Docs (`crew-docs-keeper`, after P3).** D-4009. Scope: `docs/stats_screen.md`, `docs/signals.md`, this plan's evidence file.
- Then `crew-prover` on the unit's guards (scope: tests only), then `crew-reviewer`.

## Done Criteria conventions

- The gateway is the only way to run anything: `.github/copilot/scripts/macos/gateway.sh <check> [paths...]`, spelled
  exactly so, never piped, chained or `cd`-prefixed. A check that is denied is retried once in the same spelling and then
  reported, never worked around.
- `gateway.sh test <paths...>` forwards its paths to `flutter test`; each phase names the files it must see green. The
  check's own ceiling is 900 s, so a phase with more than four Hive-heavy screen tests runs them in separate invocations.
- `gateway.sh lint` (`flutter analyze`, 300 s) is green when the issue count matches the plan's baseline — 196 issues,
  0 errors, as recorded in the brief — and no new issue names a file the phase touched. A new error fails the phase even
  if the total is unchanged; the pre-existing info notices keep the exit code non-zero.
- `gateway.sh git-status` / `git-diff --name-only` close every phase: no file outside its Predicted Files may appear.
- A guard is proven only when it fails without the change. Brand-new test files are `prove-red`-checked at the base
  commit (`prove-red <ref> test <paths> -- <carried files>`, where a file that cannot compile at that commit counts as
  failing); a *rewritten* guard instead names the mutation that must turn it red, listed with the item.
- No phase runs a formatter, a codegen or a build: the unit changes no generated or persisted shape.

## Phases (expanded)

Each item is one edit; each phase is one agent run inside the scope line at its end.

### P1 Signals locked — owner `crew-builder-app` (parallel with P2)

1. [ ] Add `String signalsLockedLine(int ratedWeeks)` — `lib/core/models/signals.dart` · `signalsLockedLine` (beside
   `signalsGateMet` at `:72`; returns `'Unlocks after $kTrainingLoadMinRatedWeeks weeks of rating your workouts — '
   '${ratedWeeks.clamp(0, kTrainingLoadMinRatedWeeks)} of $kTrainingLoadMinRatedWeeks so far.'` with the U+2014 em dash,
   like `kSignalQuietLine` at `:24`, and a doc comment naming D-4001/D-4002).
2. [ ] Add `SignalsLockedSection` — `lib/features/stats/widgets/signals_layer.dart` · `SignalsLockedSection`
   (`Column(key: const Key('signals_locked'), children: [OmniCardHeader(title: 'SIGNALS'), const SizedBox(height: 8),
   Text(signalsLockedLine(ratedWeeks), key: const Key('signals_locked_line'))])`, the text in `bodyMedium` with
   `themeColors.textSecondary`; no `Color(0x`, no `Colors.`, no token the `OmniThemeColors` typedef does not declare).
3. [ ] Add the locked branch — `lib/features/stats/stats_screen.dart` · `_StatsScreenState.build` (in the `children:` list,
   immediately after the `if (_signalsData != null) ...[...]` element at `:294-301`, an
   `else if (_mixLayer != null && !signalsGateMet(_mixLayer)) ...[ SignalsLockedSection(ratedWeeks:
   _mixLayer!.ratedBaselineWeeks, themeColors: themeColors), const SizedBox(height: 24), ]`; `_loadData` is untouched,
   so nothing is evaluated when the gate is unmet; no new string literal in this file).
4. [ ] Rewrite the absence guard — `test/signals_layer_screen_test.dart` · group `S-1702 gate unmet renders nothing`
   (`:565-608`, the `expect(find.text('SIGNALS'), findsNothing)` at `:584`): rename the group to the locked behaviour,
   flip that expectation to findsOneWidget, add `signals_locked` and `signals_locked_line`, and keep every surviving
   assertion (`signals_layer`/`signals_quiet_line` absent, `_cardKeys()` empty, `evaluations == 0`, the Mix layer and
   `ALL TIME` present).
5. [ ] Rewrite the second absence guard — `test/signals_layer_screen_test.dart` · group `Structural guard — a gate-unmet
   screen renders no SIGNALS and evaluates nothing` (`:1264-1288`, the `find.text('SIGNALS')` at `:1280`): same purpose —
   `positive.evaluations == 0` with the stub's condition met, `signals_layer` and `signals_quiet_line` absent — with the
   locked line asserted in SIGNALS' place. This group is not named in the seed's P1 description; it is in the same file.
6. [ ] Add the fixture and S-4001 — `test/signals_layer_screen_test.dart` · `_seedGateUnmetThreeRatedWeeks` + group
   `S-4013` (S-4013 carries S-4001's numbers): `_seedPeriod(name: 'Test Block', daysAgo: 10)`, the three unrated
   `_seedLifting` sessions, and `_seedRatedBaseline(fromDay: 10, offsets: const [20, 40, 60])`.
7. [ ] Add S-4002 — `test/signals_layer_screen_test.dart` · group `S-4002`: `_seedGateUnmet` (0 rated weeks) reads
   `0 of 4 so far.`; `signalsLockedLine(9)` ends `4 of 4 so far.`; `signalsLockedLine(-3)` ends `0 of 4 so far.`.
8. [ ] Add S-4003 and S-4004 — `test/signals_layer_screen_test.dart` · groups `S-4003`, `S-4004`: `_seedGateMet` renders
   the layer and no `signals_locked` (`find.text('SIGNALS')` findsOneWidget); a new `_seedWindowWithoutTime`
   (`_seedPeriod(daysAgo: 10)` + `_seedLifting(daysAgo: 20)`, so the window holds no measurable time) renders neither
   `mix_layer` nor `signals_locked` while `ALL TIME` is present.

**Done Criteria P1.** `gateway.sh lint` at the baseline, and:
`gateway.sh test test/signals_layer_screen_test.dart` (Mock group read first), `gateway.sh test
test/signals_framework_test.dart test/signals_service_test.dart`,
`gateway.sh test test/sustained_high_load_signal_screen_test.dart` (the reader that asserts the layer is absent when
there is no history at all, `:693`), `gateway.sh test test/screen_widget_test.dart` (S-1714's SIGNALS assertion is on
Home, `:2314-2325`, and must not move). New guards: `prove-red` at the base commit. Rewritten guards, mutations that must
redden them: drop `.clamp` in `signalsLockedLine` (S-4002), pass `kTrainingLoadMinRatedWeeks` instead of
`_mixLayer!.ratedBaselineWeeks` (S-4013), drop the `!signalsGateMet` half of the branch (S-4003).

**Predicted Files P1.** `lib/core/models/signals.dart`, `lib/features/stats/widgets/signals_layer.dart`,
`lib/features/stats/stats_screen.dart`, `test/signals_layer_screen_test.dart`.

**Write scope P1.** `--scope lib/core/models/signals.dart lib/features/stats/widgets/signals_layer.dart
lib/features/stats/stats_screen.dart test/signals_layer_screen_test.dart`

### P2 Strip — owner `crew-builder-app` (parallel with P1)

1. [ ] Add the field — `lib/core/models/training_load.dart` · `MixLayerData.lastSessionDay` (`final DateTime? lastSessionDay;`
   as an optional named constructor parameter defaulting to `null`, so the four external constructions keep compiling;
   doc comment: the local-midnight day of the latest completed session in all history).
2. [ ] Fill it — `lib/core/services/stats_progress_service.dart` · `_mixPayload` (`:710-802`): inside the existing
   `for (final session in history.sessions)` loop, after the `endedAtMs == null` skip at `:726`, keep the maximum
   `startedAtMs`; pass `lastSessionDay:` in the `MixLayerData(` at `:783` as
   `latest == null ? null : localMidnightDay(DateTime.fromMillisecondsSinceEpoch(latest))` (`localMidnightDay` is at
   `training_load.dart:129`). Rolling sessions count; the walk is not widened beyond all history.
3. [ ] Add the caption — `lib/features/stats/widgets/mix_layer.dart` · `build` + new `_buildCaption` (under `_buildStrip`:
   `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween)` with `Text(OmniDateUtils.formatShort(layer.weeks.first.weekStart),
   key: const Key('mix_strip_start_label'))` and `Text('this week', key: const Key('mix_strip_current_label'))`, both
   `labelSmall` + `themeColors.textMuted`; built only when `layer.weeks.isNotEmpty`).
4. [ ] Add the empty strip — `lib/features/stats/widgets/mix_layer.dart` · `build` + new `bool get _stripIsEmpty` (when
   `layer.weeks.isNotEmpty` and no week's `measure > 0`: the second `_measureText(theme)`, `_buildStrip` and the caption are
   not built; one `Text` keyed `mix_strip_empty` reads `'No training in the last $kMixStripWeeks weeks.'`, extended by
   `' Last session: ${OmniDateUtils.formatShort(layer.lastSessionDay!)}.'` when the field is non-null; the bar, legend and
   notes above stay).
5. [ ] Guard the field at service level — `test/mix_layer_service_test.dart` · `_layerShape` (`:160`) + group `S-4009`:
   `lastSessionDay` joins the shape so both harnesses are compared value-for-value; a finished day-A / finished day-B /
   unfinished day-C fixture expects `localMidnightDay(day B)`; `computeMixPeriod`'s payload is asserted to carry the field
   too, even with `weeks` empty.
6. [ ] Guard the caption — `test/mix_layer_screen_test.dart` · groups `S-4005`, `S-4014`: one pump per `startOfWeek`
   setting (`settingsState.setStartOfWeek('sunday')`, then `'monday'`), the left label matching
   `weeks.first.weekStart` for that setting, `mix_strip_current_label` reading `'this week'`, both below `mix_week_7`.
7. [ ] Guard the empty strip — `test/mix_layer_screen_test.dart` · groups `S-4006`, `S-4007`, `S-4008`, `S-4015`: the
   screenshot's shape (every completed session older than `startOfWeek(now) − 49 days`), current-week-only, oldest-week-only,
   and the finished-day-55 / unfinished-today fixture.
8. [ ] Guard the empty payload at widget level — `test/mix_layer_screen_test.dart` · group `S-4016` (a direct
   `MixLayerSection` pump with `weeks: const []`).

**Done Criteria P2.** `gateway.sh lint` at the baseline, and: `gateway.sh test test/mix_layer_screen_test.dart`;
`gateway.sh test test/mix_layer_service_test.dart test/training_load_test.dart`,
`gateway.sh test test/nutrition_series_service_test.dart test/modality_mix_period_service_test.dart
test/interference_sessions_service_test.dart` (the `MixLayerData` readers outside this file set; the four signal screen
tests that also build or read a payload — `test/cardio_efficiency_drift_signal_screen_test.dart:476`,
`test/fuel_vs_load_signal_screen_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`,
`test/sustained_high_load_signal_screen_test.dart` — assert named fields and cannot be moved by an additive optional
field, so P3's full-suite run covers them). New guards: `prove-red` at the base commit. Mutations that must redden the
rewrites: track `startedAtMs` without the `endedAtMs == null` skip (S-4015), `.last` instead of `.first` (S-4014), remove
the `weeks.isNotEmpty` guard (S-4016).

**Predicted Files P2.** `lib/core/models/training_load.dart`, `lib/core/services/stats_progress_service.dart`,
`lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart`, `test/mix_layer_service_test.dart`.

**Write scope P2.** `--scope lib/core/models/training_load.dart lib/core/services/stats_progress_service.dart
lib/features/stats/widgets/mix_layer.dart test/mix_layer_screen_test.dart test/mix_layer_service_test.dart`

### P3 Instruments — owner `crew-builder-app` (after P1 and P2; runs the full suite)

1. [ ] Add the day count — `lib/core/models/stats_progress.dart` · `StatsWindow.dayCount` (`int get dayCount`, the
   `DateTime.utc(to.y, to.m, to.d).difference(DateTime.utc(from.y, from.m, from.d)).inDays + 1` arithmetic of
   `previousRangeFor`, `stats_progress_service.dart:1228-1246`, in a doc comment that names D-4007).
2. [ ] Add the label table — `lib/features/stats/widgets/native_value_format.dart` · `nativePrimaryLabel`
   (`estimatedOneRepMax` → `'Est. 1RM'`, `reps` → `'Best set'`, `duration` → `'Total time'`, `pace` → `'Best pace'`,
   `hold`/`rounds`/`roundMinutes` → `null`; `nativeSecondaryLabel` is untouched so Exercise Progress keeps its wording).
3. [ ] Compose it into the row — `lib/features/stats/widgets/instrument_row.dart` · `InstrumentRowTile._secondaryLine`
   (primary label first, then the existing `'$label $value'` part, then bpm, then cadence, joined by `' · '`; update the
   doc comment that says a resistance row carries no secondary line).
4. [ ] Add the caption — `lib/features/stats/widgets/instrument_list.dart` · `_InstrumentListState.build` (after the first
   header's `const SizedBox(height: 8)` when `i == 0`: one `Text` keyed `instrument_caption`, `labelSmall` +
   `themeColors.textMuted`, `'Line: each training day in the window · Change: vs the ${window.dayCount} days before it'`,
   singular `'vs the day before it'` when `dayCount == 1`; one Text, so no section title is repeated).
5. [ ] Rewrite the row-shape guard — `test/instrument_list_screen_test.dart` · the test-local `_secondaryLine` helper
   (`:105-108`) and the group at `:442-470`: the helper composes the primary label first (its plank/bjj expectations stay
   byte-identical, because both those primaries label to `null`), and `expect(_rowTexts('ex-squat'), hasLength(3))`
   (`:447`) becomes the labelled shape with the comment at `:446` corrected.
6. [ ] Add the label table test — `test/instrument_change_format_test.dart` · new group `nativePrimaryLabel`: each
   `NativeMetric` pinned, including the three nulls.
7. [ ] Add the Instruments screen guards — `test/instrument_list_screen_test.dart` · groups `S-4010`, `S-4012`, `S-4017`,
   `S-4018`, `S-4019`, `S-4020`: caption text for purpose-built 14-day, 20-day and 1-day windows (S-4010) and for
   `_seedFlagship` (S-4017), the labels row-by-row (S-4012), one caption under the first header only (S-4018), the
   untouched figure strings (S-4019), the muted tokens (S-4020).
8. [ ] Add the window test file — `test/stats_window_day_count_test.dart` · new file, group `S-4011`: plain `test()`, no
   repository, no `testWidgets`, pinning `dayCount` against `StatsProgressService.previousRangeFor(window)`'s range length
   for a recent-days window, a period window and a single-day window.

**Done Criteria P3.** `gateway.sh lint` at the baseline, and:
`gateway.sh test test/instrument_list_screen_test.dart`,
`gateway.sh test test/instrument_change_format_test.dart test/stats_window_day_count_test.dart`,
`gateway.sh test test/stats_legacy_removal_test.dart test/header_standardization_test.dart
test/instrument_list_service_test.dart` (the screen's structure guards), then the full suite once:
`gateway.sh test` (900 s) — this is the last word on the four signal screen tests, `test/screen_widget_test.dart` and the
docs contract. New guards: `prove-red` at the base commit. Mutations that must redden the rewrites: `+ 1` → `+ 0` in
`dayCount` (S-4011), drop `nativePrimaryLabel` from `_secondaryLine` (S-4012/S-4019), print `window.recentDays` instead of
`window.dayCount` (S-4017).

**Predicted Files P3.** `lib/core/models/stats_progress.dart`, `lib/features/stats/widgets/instrument_list.dart`,
`lib/features/stats/widgets/instrument_row.dart`, `lib/features/stats/widgets/native_value_format.dart`,
`test/instrument_list_screen_test.dart`, `test/instrument_change_format_test.dart`,
`test/stats_window_day_count_test.dart` (new).

**Write scope P3.** `--scope lib/core/models/stats_progress.dart lib/features/stats/widgets/instrument_list.dart
lib/features/stats/widgets/instrument_row.dart lib/features/stats/widgets/native_value_format.dart
test/instrument_list_screen_test.dart test/instrument_change_format_test.dart test/stats_window_day_count_test.dart`

### P4 Docs — owner `crew-docs-keeper` (after P3)

1. [ ] Correct the strip entry — `docs/stats_screen.md` · the `**The strip.**` paragraph at `:152-154`: the caption's two
   ends, and the empty-strip line with `lastSessionDay`; name `test/mix_layer_screen_test.dart` S-4005/S-4006/S-4015.
2. [ ] Correct the Signals gate — `docs/stats_screen.md` · the `### Signals layer` gate sentences at `:171-180`: a
   gate-unmet screen no longer "sees the screen without it" — it sees the locked line; name
   `test/signals_layer_screen_test.dart` S-4001/S-4002/S-4013.
3. [ ] Correct the Instruments section — `docs/stats_screen.md` · `### Instruments list` at `:333-353`: the caption and
   the per-row labels; name `test/instrument_list_screen_test.dart` S-4010/S-4012 and
   `test/stats_window_day_count_test.dart` S-4011.
4. [ ] Extend the exports table — `docs/stats_screen.md` · the table at `:560-585`: the new members on the
   `mix_layer.dart`, `signals_layer.dart`, `native_value_format.dart`, `training_load.dart` and `stats_progress.dart` rows.
5. [ ] Correct the gate section — `docs/signals.md` · `## The gate` at `:41-49`: "renders nothing at all" becomes
   "evaluates nothing and shows the locked line", keeping the evaluation half's meaning.
6. [ ] Correct the quiet-line section — `docs/signals.md` · `## The quiet line` at `:104-108`: a gate-unmet load reports
   neither cards nor the quiet line and shows the locked line instead; name S-4002.
7. [ ] Fill the evidence file — `docs/plans/2026-10-12-24-stats-clarity-plan/2026-10-12-24-stats-clarity-plan.evidence.md` ·
   the reserved sections.
8. [ ] Fix the two stale member lists (governor decision on Open question 8) — `docs/widget_catalog.md:30` (the Mix layer's
   caption and empty line, the locked Signals section) and `docs/state_management/services_and_utils.md:320`
   (`lastSessionDay` in the `computeMixLayer` payload); one sentence each, nothing else in those files.

**Done Criteria P4.** `gateway.sh test test/docs_indexing_contract_test.dart` green (link resolution, the 64 KiB ceiling
and the 52,429-byte warning band); no edited file above 52,429 bytes; every new behaviour sentence names a scenario id
that exists after P3. No `lint` run: docs are not analyzed.

**Predicted Files P4.** `docs/stats_screen.md`, `docs/signals.md`,
`docs/plans/2026-10-12-24-stats-clarity-plan/2026-10-12-24-stats-clarity-plan.evidence.md`.

**Write scope P4.** `--scope docs/stats_screen.md docs/signals.md docs/widget_catalog.md
docs/state_management/services_and_utils.md
docs/plans/2026-10-12-24-stats-clarity-plan/2026-10-12-24-stats-clarity-plan.evidence.md`

### Order and parallelism

**Governor decision (supersedes the parallel marks above):** P1, P2, P3 run one after another. They share no file, but they share one Dart package, so a half-edited file in one run can break the other's compile and test run (the crew's own rule: only trees that cannot break each other's compile run in parallel). Original note: P1 and P2 share no file and neither reads the other's output; at most these two could run at once. P3 waits for both
because it is the last code phase and its Done Criteria run the whole suite, which must include P1's and P2's files. P4
waits for P3 because its behaviour sentences must name tests that exist. Then `crew-prover` (tests only) and
`crew-reviewer`.

## Code pointers (current lines)

- `stats_screen.dart` build: `if (_signalsData != null) ...[ SignalsLayerSection( data: _signalsData!, themeColors: themeColors, onDismiss: _dismissSignal, ), const SizedBox(height: 24), ],`
- `signals.dart:72`: `bool signalsGateMet(MixLayerData? mix) => mix != null && mix.ratedBaselineWeeks >= kTrainingLoadMinRatedWeeks;` and `:24` `const String kSignalQuietLine = 'No signals — nothing outside your usual range.';`
- `mix_layer.dart` build tail: `const SizedBox(height: _blockGap), _measureText(theme), const SizedBox(height: _tightGap), _buildStrip(maxWeekMeasure),` ; helper `_buildStrip` ~279, `_buildWeekColumn` ~289; `OmniDateUtils.formatShort(DateTime)` -> `'Aug 17'` (`date_utils.dart:142`).
- `instrument_row.dart` `_secondaryLine`: `final label = nativeSecondaryLabel(best.secondaryMetric); final value = formatNativeSecondary(best, settingsState); if (label != null && value != null) parts.add('$label $value');`
- `instrument_list.dart`: `children.add(OmniCardHeader(title: section.section.label, actions: [ if (i == 0) StatsWindowChip(...) ])); children.add(const SizedBox(height: 8));`
- `stats_progress_service.dart:1228` `static ({int fromMs, int toMs}) previousRangeFor(StatsWindow window)`.

## Progress

| Phase | Item | Owner | Status |
|---|---|---|---|
| P1 | 1 `signalsLockedLine` | crew-builder-app | [x] |
| P1 | 2 `SignalsLockedSection` | crew-builder-app | [x] |
| P1 | 3 locked branch in `_StatsScreenState.build` | crew-builder-app | [x] |
| P1 | 4 rewrite S-1702 group | crew-builder-app | [x] |
| P1 | 5 rewrite the structural absence guard | crew-builder-app | [x] |
| P1 | 6 fixture `_seedGateUnmetThreeRatedWeeks` + S-4013 | crew-builder-app | [x] |
| P1 | 7 S-4002 group | crew-builder-app | [x] |
| P1 | 8 S-4003/S-4004 groups | crew-builder-app | [x] |
| P2 | 1 `MixLayerData.lastSessionDay` | crew-builder-app | [x] |
| P2 | 2 `_mixPayload` fills it | crew-builder-app | [x] |
| P2 | 3 `_buildCaption` | crew-builder-app | [x] |
| P2 | 4 empty strip + `_stripIsEmpty` | crew-builder-app | [x] |
| P2 | 5 `_layerShape` + S-4009 | crew-builder-app | [x] |
| P2 | 6 S-4005/S-4014 groups | crew-builder-app | [x] |
| P2 | 7 S-4006/S-4007/S-4008/S-4015 groups | crew-builder-app | [x] |
| P2 | 8 S-4016 direct-widget guard | crew-builder-app | [x] |
| P3 | 1 `StatsWindow.dayCount` | crew-builder-app | [x] |
| P3 | 2 `nativePrimaryLabel` | crew-builder-app | [x] |
| P3 | 3 `_secondaryLine` composition | crew-builder-app | [x] |
| P3 | 4 `instrument_caption` | crew-builder-app | [x] |
| P3 | 5 rewrite the row-shape guard | crew-builder-app | [x] |
| P3 | 6 `nativePrimaryLabel` table test | crew-builder-app | [x] |
| P3 | 7 S-4010/S-4012/S-4017/S-4018/S-4019/S-4020 groups | crew-builder-app | [x] |
| P3 | 8 new `test/stats_window_day_count_test.dart` (S-4011) | crew-builder-app | [x] |
| P4 | 1 strip entry in `docs/stats_screen.md` | crew-docs-keeper | [x] |
| P4 | 2 Signals gate sentences | crew-docs-keeper | [x] |
| P4 | 3 Instruments section | crew-docs-keeper | [x] |
| P4 | 4 exports table rows | crew-docs-keeper | [x] |
| P4 | 5 `docs/signals.md` gate section | crew-docs-keeper | [x] |
| P4 | 6 `docs/signals.md` quiet-line section | crew-docs-keeper | [x] |
| P4 | 7 evidence file sections | crew-docs-keeper | [x] |
| Post | prover on the unit's guards (tests only) | crew-prover | [ ] |
| Post | review | crew-reviewer | [ ] |

## Assumption Log

- 2026-10-12 governor, answers to the Open questions: (1) accepted, S-4013 carries the 3-of-4 number. (2), (3) accepted, in scope. (5) accepted: empty `weeks` renders neither caption nor `mix_strip_empty`. (6) accepted: the caption prints the window's calendar span, so a 14-training-day window may read 15 or more days. (7) the band is 52,429 and it fails the suite; P4 stays below it. (8) accepted, P4 item 8.

## Feedback

(empty)

## Open questions

1. **S-4001's fixture does not produce S-4001's number.** `_seedGateUnmet` (`test/signals_layer_screen_test.dart:392-402`)
   seeds three sessions through `_seedLifting` with no `rating:`, and `_seedLifting` takes `int? rating` with no default
   (`:216-232`), so every `sessionFeeling` is null; `_mixPayload` counts a baseline block as rated only when
   `session.sessionFeeling != null` (`lib/core/services/stats_progress_service.dart:748-752`, used at `:770`). The fixture
   therefore reports `0 of 4 so far.`, not `3 of 4 so far.`. S-4001 is kept verbatim and satisfied by the new
   `_seedGateUnmetThreeRatedWeeks` fixture (S-4013: `_seedRatedBaseline(fromDay: 10, offsets: const [20, 40, 60])` →
   blocks 9/6/3 → 3 rated weeks); S-4002 uses `_seedGateUnmet` for the 0 case.
2. **A second seeded-absence guard breaks and is not named in P1's description.**
   `test/signals_layer_screen_test.dart:1264-1288` (`find.text('SIGNALS')` at `:1280`) asserts the same absence as the
   S-1702 group. Same file, same write scope — P1 item 5 rewrites it; the planner may prefer to name it in P1's text.
3. **`test/instrument_list_screen_test.dart:447`** (`expect(_rowTexts('ex-squat'), hasLength(3))` under the comment at
   `:446`) breaks by design; the seed names only the comment. P3 item 5 rewrites it.
4. **Do the `MixLayerData(` call sites outside the model compile unchanged?** Yes. Four of them exist —
   `lib/core/services/stats_progress_service.dart:783`, `test/cardio_efficiency_drift_signal_screen_test.dart:476`,
   `test/signals_framework_test.dart:34`, `test/signals_service_test.dart:66` — and all four pass named arguments, so an
   added optional named parameter with a default is source-compatible. (`test/signals_framework_test.dart:34` already
   passes `weeks: const []`.)
5. **D-4003's `.first` over a payload that can be empty.** `computeMixPeriod` builds its payload with
   `weekStarts: const []` (`stats_progress_service.dart:539`), so `weeks` can be empty even though the screen only ever
   feeds `MixLayerSection` from `computeMixLayer` (`stats_screen.dart:131,287`). The plan adds `weeks.isNotEmpty` guards
   (P2 items 3-4) and, beyond D-4004's text, renders *neither* the caption nor `mix_strip_empty` for an empty list, since
   "No training in the last 8 weeks." is a claim an empty payload cannot support. S-4016 is the guard; the reviewer should
   confirm the choice.
6. **D-4006's number is the window's span, not `recentDays`.** `previousRangeFor` (`stats_progress_service.dart:1228-1246`)
   derives its length from the window's own bounds, whose `to` is always end-of-today, so `_seedFlagship`
   (`test/instrument_list_screen_test.dart:173`, days 1-14 as the window) prints `15 days` while the chip prints
   `Last 14 training days`. Kept as seeded, but S-4010's `14 / 20 / 1` need purpose-built windows; S-4017 pins the
   difference rather than hiding it.
7. **D-4009's 52,428 bytes is one below the guard's band, and the band is not soft.** `test/docs_indexing_contract_test.dart:49`
   (`_maxDocBytes = 64 * 1024`), `:54` (`_warnFraction = 0.80`) → `(65536 * 0.8).round() = 52429` at `:156`; the test's own
   doc comment (`:55-58`) says a file "above this fraction… still passes" and is "a separate, softer signal so the build
   does not break on a near-miss", but the body asserts `expect(nearLimit, isEmpty)` at `:161,177` — so the band **fails**
   the suite. D-4009's ceiling is therefore right and its 52,428 is off by one; P4 must stay under 52,429, not 52,428.
   (Files under `docs/plans/` are exempt — `_recordFolders` at `:62-67` — so this plan and its evidence file are neither
   size-limited nor link-checked.) The current byte sizes of `docs/stats_screen.md` and `docs/signals.md` were not
   re-derived this run (no measuring tool in scope); the seed's 36,902 / 47,458 are taken on trust. **Second question for
   the governor:** the doc comment and the assertion disagree about whether the band is a soft signal; the plan assumes
   the assertion wins.
8. **Docs outside P4's seeded scope go stale and are not edited:** `docs/widget_catalog.md:30` (the Mix layer's member
   list — it will miss the caption and the empty line) and `docs/state_management/services_and_utils.md:320` (the
   `computeMixLayer` payload list — it will miss `lastSessionDay`). The seed's P4 scope is `docs/stats_screen.md`,
   `docs/signals.md` and the evidence file; adding these two files is the governor's call.
9. **`MixLayerSection` with an empty `segments` list is untested today** (the widget is only ever built from a full
   `computeMixLayer` payload). S-4016 pumps it that way. If the bar or the legend requires a segment, that is a
   pre-existing gap the guard will expose: report it, do not fix it inside this unit.
10. **The three-rated-week arithmetic in S-4013 was derived, not observed.** `baselineBlockStarts`
    (`lib/core/models/training_load.dart:140-150`) tiles twelve 7-day blocks ending the day before `fromDay`; with
    `fromDay: 10` the starts are days 94, 87, 80, 73, 66, 59, 52, 45, 38, 31, 24, 17, and `_baselineBlockFor`
    (`stats_progress_service.dart:927`) returns the last start at or before a session's start — days 30/50/70 → blocks
    9/6/3, three distinct weeks. The builder must read the count from the service in the test rather than trust the
    number written here.
