# Plan 32 — The Training Mix card and the Session Summary say what they mean

Status: SEEDED by the governor 2026-10-13 (no architect run: two copy-level phases with exact strings). Base commit: `.work/2026-10-13-32/base.txt`.
Branch: the crew's working branch (`claude_develop`); the owner commits. A parallel session builds the watch app and
commits to the same branch: every diff check in this unit is scoped to this plan's paths, never to the whole tree.

## Goal and acceptance

The owner's phone screenshots showed a Training Mix card that is hard to read (`by load` twice with no meaning, an
unexplained `usual` bar, `Sports 0%`, `1 unrated session` that leads nowhere, an eight-week strip that looks like one lone
bar under `this week`) and a Session Summary with an unlabelled `Change` button beside `3 / 5` and a DISTANCE row
(`Easy Run — MI`) that looks like read-only text but opens an editor. The owner approved the wording below on 2026-10-13.

Acceptance, as the user sees it:

1. **Training Mix reads in words.** One sentence under the title says what the bars are; the first bar is labelled
   `In this window` (only when the usual bar exists), the second `Your usual`; the legend has coloured dots, bigger text
   and no 0% entries; the notes say what they mean and what to do; the strip is titled `Week by week · last 8 weeks`,
   shows eight visible columns even when seven are empty, and is captioned `7 weeks ago` … `This week so far`.
2. **The Effort row explains itself.** Under `3 / 5` a muted line reads `How hard the session felt`; the button reads
   `Change rating` (still `Add rating` when unrated).
3. **The DISTANCE card looks editable.** A line at the top of the card reads `Tap a row to enter or correct it.` and each
   row ends with a pencil icon. A missing distance keeps its em dash (the owner's `Add distance` wording is NOT done in
   this unit: it would rewrite ~30 text assertions; the pencil and the hint carry the meaning).

Nothing else changes: no value, share, load rule, threshold, window, signal or distance rule is touched.

## Feature invariants

- **Presentation only.** `MixLayerData`, `StatsProgressService`, `SessionSummaryService`, `WorkoutState` and the
  repository are not edited. `SessionDistanceCard.absentValue` stays `'—'` and `DistanceRowModel`'s fields stay as they
  are (readers: `test/entry_identity_summary_test.dart`, `test/session_summary_distance_test.dart`).
- **Numbers in copy come from constants.** `kMixStripWeeks` (strip title, caption: `kMixStripWeeks - 1`) and
  `kTrainingLoadMinRatedWeeks` (baseline note) are never written as literals in the widget.
- **Keys survive.** Every existing key stays (`mix_layer`, `mix_bar`, `mix_usual_label`, `mix_usual_bar`, `mix_legend`,
  `mix_strip_start_label`, `mix_strip_current_label`, `mix_strip_empty`, `mix_week_<i>`, `mix_week_<i>_segment_<j>`,
  `mix_week_current`, `omni_session_info_card`, `omni_session_effort_marker`, `omni_session_distance_card`); only text changes
  and new keys are added.
- **Two window chips only.** `S-1612` asserts exactly two `stats_window_chip`s; no new chip-like text is added.
- **Non-text meaning.** Legend dots and empty-week stubs use `_colorFor` / `themeColors.textMuted`; no literal `Color(` or
  `Colors.` (`test/ui_standards_contract_test.dart`, palette tests).
- **Fit.** Everything fits 390x844 at the default scale and the narrowest viewport at the largest non-accessibility text
  scale with nothing wider than its card (`S-1615`'s harness); the distance row with a pencil fits 280 dp wide.
- **Widget tests Mock-first**, seeded in `setUp`; no real `Future.delayed` in `testWidgets`.
- **No stored shape changes**; no codegen; no new dependency.

## Decision Ledger

- **D-3201 Explainer line.** `lib/features/stats/widgets/mix_layer.dart` `build()`: directly under `OmniCardHeader`
  (before the first `_measureText`) one `Text`, `Key('mix_explainer')`, `bodySmall`, `themeColors.textSecondary`:
  load measure `'Your training split by how hard each session felt.'`; time measure `'Your training split by time spent.'`.
  `_measureLabel`, the two `_measureText(theme)` calls and the strings `by load` / `by time` are REMOVED (nothing else
  uses them; `_unit` stays for the week semantics).
- **D-3202 Bar labels.** When `usualSegments.isNotEmpty`, a `labelSmall` `textMuted` `Text('In this window')`,
  `Key('mix_window_bar_label')`, sits directly above `_buildBar()`; the existing label `'usual'` (`Key('mix_usual_label')`)
  becomes `'Your usual'`. No label above the bar when there is no usual bar.
- **D-3203 Legend.** `_buildLegend`: one `Row(mainAxisSize: min)` per segment with `segment.percent > 0` — a 10x10 rounded
  dot in `_colorFor(segment.section)` (`Key('mix_legend_dot_<i>')` with `<i>` the segment's index in `layer.segments`),
  a 6 dp gap, and the existing `'${section.label} ${percent}%'` text in `bodyMedium` / `textSecondary`. `Wrap`
  spacing 16, runSpacing 6. The bar and its semantics label are untouched (0% segments still draw their sliver and
  still read in the bar's semantics).
- **D-3204 Notes.**
  - Baseline note (shown when `!_isLoad && ratedBaselineWeeks < kTrainingLoadMinRatedWeeks`): replaces
    `Load baseline: N of 4 weeks rated` with
    `'Showing time for now. Effort appears once $kTrainingLoadMinRatedWeeks weeks are rated ($n of $kTrainingLoadMinRatedWeeks so far).'`
    (`$n` is the existing clamp). `maxLines: 2` (was 1) so it wraps instead of cutting. Key `mix_baseline_note`.
  - Unrated line (when `unratedSessionCount > 0`): load measure → `'1 session isn't counted – no effort rating yet'` /
    `'$n sessions aren't counted – no effort rating yet'`; time measure → `'1 session has no effort rating yet'` /
    `'$n sessions have no effort rating yet'`. The dash is U+2013. `maxLines: 2`. Key `mix_unrated_note`.
- **D-3205 Strip.** The second `_measureText` becomes a `labelSmall` `textMuted` `Text`,
  `Key('mix_strip_title')`, `'Week by week · last $kMixStripWeeks weeks'`. `_buildCaption`: left
  `'${kMixStripWeeks - 1} weeks ago'`, right `'This week so far'`; keys `mix_strip_start_label` /
  `mix_strip_current_label` unchanged. The column semantics label (`_weekLabel`, which carries the date) is unchanged,
  so the date is still available to a screen reader. The empty-strip line (`mix_strip_empty`) is unchanged.
- **D-3206 Empty-week stub.** `_buildWeekColumn`: a week with `measure <= 0` adds, at the bottom of its column, a 2 dp
  high `Container` `Key('mix_week_<i>_empty')` coloured `themeColors.textMuted` (no alpha math: use the colour as is),
  so eight columns are visible. A week with work gets no stub. The stub is not a stack segment: no key
  `mix_week_<i>_segment_<j>` is added for it, and the column's fixed `_stripHeight` is unchanged.
- **D-3207 Effort caption.** `lib/features/session/session_summary_screen.dart` `_StatPill` gains an optional
  `String? caption` rendered under the value as `bodySmall` in `onSurface.withOpacity(0.6)`; the EFFORT pill passes
  `caption: 'How hard the session felt'` (`Key('omni_session_effort_caption')`), rated or not, rolling or not.
  The other pills pass nothing and are unchanged.
- **D-3208 Button text.** `feeling != null ? 'Change' : 'Add rating'` becomes `feeling != null ? 'Change rating' :
  'Add rating'`. Nothing else about the button changes.
- **D-3209 Distance hint.** `lib/widgets/session/session_distance_card.dart`: first child of the card's `Column`, above the
  first row, a `Text('Tap a row to enter or correct it.')`, `Key('session_distance_hint')`, `bodySmall`,
  `theme.colorScheme.onSurfaceVariant`, with 4 dp below it. Rendered only when the card renders (rows non-empty).
- **D-3210 Pencil.** Each row's `Row` ends (after the unit text, 12 dp gap) with `Icon(Icons.edit_outlined, size: 16,
  color: theme.colorScheme.onSurfaceVariant)`, `Key('session_distance_edit_icon_<i>')`, `ExcludeSemantics` (the row's
  existing `Semantics(button: true)` already names the action). The row's `InkWell` / `onTap` / padding are unchanged.
- **D-3211 Docs.** `docs/stats_screen.md` (Mix layer section, lines ~126-180), `docs/widget_catalog.md` line 30,
  `docs/session_summary.md` (effort row, distance card) and `docs/widget_catalog/session_widgets.md` (~line 136) state the
  new copy, each behaviour sentence naming a test that exists. `docs/watch-app-setup-and-qa.md` (mentions `Add rating`,
  unchanged) belongs to the parallel watch session and is NOT touched. Each edited file stays under 52,429 bytes.

## Existing-functionality impact

| Touched surface | What already reads it | Effect | Guarded by |
|---|---|---|---|
| `by load` / `by time` texts, `usual`, `this week`, `Load baseline`, `N unrated session(s)` | 80+ assertions, all in `test/mix_layer_screen_test.dart` (groups S-1603, S-1604, S-1605, S-1606, S-1607, S-1608, S-1609, S-1611, S-1614, S-1615, S-1616); `_kSectionLabels` at ~1924 | text changes; the file's assertions are rewritten in phase A | the rewritten groups |
| `_buildLegend` | `_textsUnder(find.byKey(Key('mix_legend')))` at ~92, 876, 1645, 1715, 1739, 1875 | texts are the same minus 0% entries; collection order unchanged | S-3203 + the rewritten lists |
| strip column children | S-1608/S-1609 count `mix_week_<i>_segment_<j>` keys and heights | stub has its own key and no segment key | S-3206 |
| `'Change'` text | `test/session_summary_effort_row_test.dart` (≈20 hits), `test/header_standardization_test.dart:1346`, `test/watch_session_summary_integration_test.dart:380,415` | exact text becomes `Change rating`; `Add rating` untouched | rewritten finders |
| DISTANCE card texts | `test/session_summary_distance_test.dart` row text lists (e.g. `[_plank, absentValue, 'KM']`), `test/entry_identity_summary_test.dart:286-298` | the row's own texts are unchanged (the hint sits above the rows, the icon is not text); tests that collect every `Text` in the card gain one entry — adjust by reading rows, not by weakening | S-3213 |
| `SessionDistanceCard` / `DistanceRowModel` | constructed only in `session_summary_screen.dart` and in the tests above | no signature change | compile |
| `_StatPill` | private to `session_summary_screen.dart` | new optional field | S-3211 |

## Core scenarios

Fixtures reuse the existing seeders in `test/mix_layer_screen_test.dart` (FX-TIME `_seedTimeWindow` = time measure with
`1 unrated session`; FX-LOAD `_seedLoadReady` = load measure with a usual bar; FX-BASELINE3 `_seedThreeRatedWeeks` = time
measure with `3 of 4`; FX-STRIP `_seedStrip`; `_seedEveryStripWeek`) and in `test/session_summary_effort_row_test.dart` /
`test/session_summary_distance_test.dart`. The one new shape is S-3203's hand-built payload.

- **S-3201** FX-LOAD: `mix_explainer` reads `Your training split by how hard each session felt.`; FX-TIME: `Your training split by time spent.`;
  exactly one `mix_explainer`; no text `by load`, `by time`, `usual` anywhere under `mix_layer`. Fails today: no explainer, the old words exist.
- **S-3202** FX-LOAD: `mix_window_bar_label` reads `In this window` and sits above `mix_bar`; `mix_usual_label` reads `Your usual` and sits
  below `mix_bar`. FX-TIME (no usual bar): no `mix_window_bar_label`, no `mix_usual_label`. Fails today: neither label exists.
- **S-3203** Pump `MixLayerSection` directly with `MixLayerData(measure: MixMeasure.load, segments: [Resistance measure 98.4 percent 98,
  Isometric 1.0 percent 1, Cardio 0.6 percent 1, Sports 0.0 percent 0], baselineSegments: const [], unratedSessionCount: 0,
  ratedBaselineWeeks: 4, weeks: const [])` (the S-4016 shape): `_textsUnder(mix_legend)` is exactly `['Resistance 98%', 'Isometric 1%',
  'Cardio 1%']` (no Sports); three `mix_legend_dot_*` keys, indexes 0-2; `mix_bar` semantics label still names `Sports 0%`; four
  `mix_bar_segment_*`. Fails today: `Sports 0%` is in the legend and there are no dots.
- **S-3204** FX-BASELINE3 (3 of 4): `mix_baseline_note` reads `Showing time for now. Effort appears once 4 weeks are rated (3 of 4 so far).`;
  `0 of 4` variant on FX-TIME. FX-LOAD: no `mix_baseline_note`. Fails today: the text is `Load baseline: 3 of 4 weeks rated`.
- **S-3205** Unrated line: FX-TIME (time, 1 session) → `1 session has no effort rating yet`; a time-measure window with three unrated
  sessions → `3 sessions have no effort rating yet`; a load-measure window with one unrated session (the S-1606 twin) →
  `1 session isn't counted – no effort rating yet`; with three → `3 sessions aren't counted – no effort rating yet`; none → no
  `mix_unrated_note`. Fails today: the old `N unrated session(s)` text.
- **S-3206** FX-STRIP (sessions now, 7 days ago and 30 days ago = three distinct weeks with work: columns `7`,
  `_weekIndexOf(_day(7), startOfWeek)` and `_weekIndexOf(_day(30), startOfWeek)`, the test's own helper as S-1608 uses it):
  `mix_strip_title` reads `Week by week · last 8 weeks`; caption left `7 weeks ago`, right `This week so far`; exactly five
  `mix_week_<i>_empty` keys, on the other five column indexes and on none of those three; the stub is 2 dp high; columns
  keep their fixed 64 dp; the empty-strip fixture (all eight empty, S-4006 shape) still shows `mix_strip_empty` and NO strip, title, caption
  or stub. Fails today: no title, caption reads a date and `this week`, no stubs.
- **S-3207** Existing S-1608/S-1609 guards (eight columns, current week marked, strip reads the bar's measure) still hold after the rewrite;
  S-1609's "same measure" becomes: the week semantics unit text (`load` / `min`) matches the measure the explainer states.
- **S-3208** Overflow: the whole card at 390x844 default and at the narrowest viewport with text scale 1.3 and 2.0 (the S-1615 harness)
  raises no overflow, with the unrated and baseline notes on screen (two lines allowed).
- **S-3211** Session Summary, rated 3: `omni_session_effort_caption` reads `How hard the session felt` below `3 / 5`; unrated (`—`): caption present;
  rolling session: caption present. Duration and Rest Time pills have no caption. Fails today: no caption.
- **S-3212** Rated: `find.text('Change rating')` findsOneWidget, `find.text('Change')` findsNothing; unrated: `Add rating`; after rating via the
  sheet the button reads `Change rating`; tapping it still opens the sheet with the stored rating selected. Fails today: the text is `Change`.
- **S-3213** A session with two distance rows: `session_distance_hint` reads `Tap a row to enter or correct it.` exactly once, above the first
  row's name (`dy`), inside `omni_session_distance_card`; no distance rows (no timed entries): no card, no hint. Fails today: no hint.
- **S-3214** Each distance row (including one with `—`) has `session_distance_edit_icon_<i>`; tapping the row (not the icon) still opens the
  distance editor and an edit still saves (existing tests untouched in behaviour). Fails today: no icon.
- **S-3215** The distance card at 280 dp wide with an exercise name of 60 characters: no overflow, the pencil and the unit stay visible,
  the name ellipsises. Fails today: nothing to assert (guard for the new icon).

## Phases (both parallel: disjoint write scopes, no shared output; neither runs the full suite, the governor does)

### Phase A — Training Mix card (crew-builder-app)

Items (6): 1 D-3201 explainer + remove measure labels; 2 D-3202 bar labels; 3 D-3203 legend; 4 D-3204 notes; 5 D-3205 + D-3206 strip title,
caption, stubs; 6 rewrite the affected assertions and add S-3201..S-3208 in `test/mix_layer_screen_test.dart`.
Scope: `lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart`.
Code pointers: `mix_layer.dart` `build()` lines 130-203, `_buildCaption` 218-245, `_buildLegend` 338-353, `_buildWeekColumn` 367-414.
Done: `flutter test test/mix_layer_screen_test.dart test/signals_layer_screen_test.dart test/ui_standards_contract_test.dart
test/palette_legibility_contract_test.dart` green; `flutter analyze` on the two files clean.

### Phase B — Session Summary (crew-builder-app)

Items (5): 1 D-3207 caption; 2 D-3208 button text; 3 D-3209 hint; 4 D-3210 pencil; 5 update finders (`Change` → `Change rating`) and add
S-3211..S-3215.
Scope: `lib/features/session/session_summary_screen.dart`, `lib/widgets/session/session_distance_card.dart`,
`test/session_summary_effort_row_test.dart`, `test/session_summary_distance_test.dart`, `test/header_standardization_test.dart`,
`test/watch_session_summary_integration_test.dart`, `test/entry_identity_summary_test.dart`.
Code pointers: `_buildSessionInfoCard` 787-863, `_StatPill` 1385-1425, `session_distance_card.dart` 47-109.
Done: `flutter test` on those five test files plus `test/ui_standards_contract_test.dart` green; `flutter analyze` on the touched files clean.

### Phase C — Docs (crew-docs-keeper, after A and B) and Phase D — Review (crew-reviewer, after C)

Scope of C: D-3211's four files and this plan's evidence file. D reads the diff of this plan's paths only.

## Progress

- [x] A  - [x] B  - [x] prove  - [x] C  - [ ] D

## Assumption Log

- A-1 `window.label` is already shown by the card's single window chip, so no new window text is added above the bar (S-1612).
- A-2 `Add distance` wording deferred (see Acceptance 3); the owner is told.
- A-3 `7 weeks ago` is the true age of the oldest column's week start (current week + 7 prior weeks = `kMixStripWeeks` columns).

## Feedback

(none yet)

- (owner) Look at the result on the phone: Stats > TRAINING MIX card (explainer, labels, legend dots, `Week by week` strip with eight columns) and a finished cardio session's Summary (Effort caption, `Change rating`, DISTANCE hint and pencils). Reassess wording; `Add distance` wording was deferred (A-2).
- Review (2026-10-14): APPROVE, 0 blockers, 0 majors, 1 minor (the bar's screen-reader label no longer names the measure; D-3201 vs D-3203 conflict in the seed). Nothing committed; the owner commits.
