# S9 — Area scout sheet: Stats · Records & Trends · Signals (UI/UX standards survey)

Scout: S9 (crew-scout) · Date: 2026-10-12 · Read-only run; no product file touched.
Area docs: `docs/stats_screen.md` (v3.1), `docs/records_and_trends.md` (v1.0), `docs/signals.md`,
`docs/training_load.md`, `docs/session_summary.md` (matrix row only, shared with S6),
`docs/design_system.md`, `docs/widget_catalog.md`, `docs/global_conventions.md`,
`docs/plans/2026-10-12-24-stats-clarity-plan/2026-10-12-24-stats-clarity-plan.md`.
Area code: `lib/features/stats/` (3 screens + 11 widgets), `lib/widgets/chart/` (3 widgets),
`lib/widgets/layout/omni_card_header.dart`, `lib/core/models/signals.dart`.
Out of scope: watch behaviour (not reported).

---

## 1. Doc-vs-code checks (STALE-DOC / CONFLICT)

**Names checked: 61. Stale: 0. Conflicts: 0.** Every doc-named symbol in the three area docs was
grepped in `lib/` and found at the documented place. Checked (grouped):

- Constants: `kSignalQuietLine`, `kSignalMaxCards` (=2), `kSignalDismissalDays` (=14),
  `kMixStripWeeks` (=8), `kTrainingLoadMinRatedWeeks` (=4), `kTrainingLoadMaxUnratedShare` (=0.25),
  `kRecentTrainingDaysWindow` (=14), `kFuelWindowDays` (=7), `kFuelVisibilityDays` (=14),
  `kInstrumentRowCap` (=5), `kRecentSessionCount` (=20), `kFuelAbsent`.
- Services/models: `StatsProgressService`, `SignalsService`, `buildSignalRegistry`, `SignalsData`,
  `SignalCard`, `MixLayerData` (incl. `lastSessionDay`), `StatsWindow.dayCount`, `StatsPR`,
  `signalsGateMet`, `signalsLockedLine`, `ExerciseSectionLabel` labels
  (`Resistance`/`Cardio`/`Isometric`/`Sports`), `nativePrimaryLabel`, `formatNativeChange`.
- Widgets/screens: `OmniBackHeader` (with `subtitle`), `OmniCardHeader`, `OmniBottomCTA`,
  `OmniSurface`, `ScrollableTrendChart`, `ChartAxisHelper`, `buildEdgeAwareDateLabel`,
  `buildSinglePointCard`, `StatsPrimerSheet`/`StatsPrimerState` (`primer_seen_stats`),
  `ModalityColors.*`, `FuzzySearch.matches`, `OmniTheme` tokens, `localMidnightDay`
  (in `lib/core/models/training_load.dart:136`, not `date_utils.dart` — docs point at the model, correct).
- Navigation: `stats_screen.dart:269` is the only `lib/` construction of `RecordsAndTrendsScreen`;
  `ExerciseProgressScreen` is constructed only at `instrument_list.dart:55` and
  `records_and_trends_screen.dart:281`. Matches `docs/records_and_trends.md` ("the Stats header
  chart icon is the only entry point") and its guard
  `test/records_and_trends_screen_test.dart:694` ("StatsScreen is the only file in lib/ that constructs").
- Test scenario IDs spot-checked (~25): S-9xx, S-10xx, S-11xx, S-12xx, S-16xx, S-17xx, S-27xx, S-40xx
  all present in the named test files.
- Clarity-plan decisions D-4001–D-4010 (locked Signals line, strip caption, empty-strip line,
  Instruments caption, window chips) — all present in code and now documented in
  `stats_screen.md`/`signals.md`/`widget_catalog.md`. No residue.

### F1 · STALE-DOC · design_system.md's canonical-header screen table omits two screens that do route through OmniCardHeader

- Where the doc says it: `docs/design_system.md:176-186`
  ```
  ### Where the canonical header is used

  Every section / card header in the app routes through `OmniCardHeader`. The widget enforces the
  contract above; raw `Text` widgets above outlined cards are **not permitted** (see
  `docs/global_conventions.md`).

  | Screen | Headers |
  |--------|---------|
  | **Settings** | `PREFERENCES`, `SOUNDS & ALERTS`, `WORKOUT`, `APPEARANCE` |
  | **Session Summary** | Date (with the modality chip in actions), `DISTANCE`, `SESSION NOTE` (note card), month label (with `Open Calendar` in actions) |
  | **Daily Nutrition** | `Today` (with `nutrition_target_button` labelled `OutlinedButton.icon` in actions — PR 3 / S-002), `Foods I Eat` (with `food_library_manage_pencil` in actions) |
  | **Profile** | One title-only header per measurement definition; the `+` add button lives in the card body. Verified by `test/header_standardization_test.dart` (`S-011`). |
  | **Stats** | `TRAINING MIX` (carrying the window chip in actions); `SIGNALS`; `ALL TIME`; the Instruments list's four title-case headers, `Resistance`, `Cardio`, `Isometric`, `Sports`, the first of them carrying the window chip in actions; and the Fuel row's `Fuel`. Verified by `test/mix_layer_screen_test.dart` (`S-1601`, `S-1612`), `test/signals_layer_screen_test.dart` (`S-1701`), `test/instrument_list_screen_test.dart` (`S-1001`, `S-1011`, `S-1015`) and `test/fuel_row_screen_test.dart`. |
  ```
- Where the code does it: both area screens use `OmniCardHeader` but appear nowhere in the table.
  `lib/features/stats/records_and_trends_screen.dart:134`:
  ```
      final children = <Widget>[
        const OmniCardHeader(title: 'ALL TIME'),
        _buildAggregateCard(context, themeColors),
      ];
  ```
  `lib/features/stats/exercise_progress_screen.dart` — `OmniCardHeader(title: 'ALL TIME')`,
  `OmniCardHeader(title: 'TREND')`, `OmniCardHeader(title: 'RECENT SESSIONS')` (grep-verified,
  3 occurrences in that file).
- What a user would see: nothing (doc inventory gap only).
- Guard: none found: searched `header_standardization_test.dart` for `RecordsAndTrends`,
  `ExerciseProgress`, `records_and_trends`, `exercise_progress` — no matches.
- Unsure: whether the table is meant to be exhaustive ("Every section / card header in the app"
  suggests yes) or illustrative.

No other STALE-DOC or CONFLICT found in the area docs.

---

## 2. UI behaviours written nowhere (NO-RULE / INCONSISTENT / BREAKS-RULE)

### F2 · BREAKS-RULE · `RecentPRList` card title is a raw `Text`, not the canonical D-1 header typography

- Where the doc says it: `docs/design_system.md:160`
  ```
  Every section eyebrow and per-card title in the app uses the **canonical D-1 typography** — there
  is one and only one style for these elements. The contract is enforced by the `OmniCardHeader`
  widget (see `docs/widget_catalog.md`); callers cannot override the style.
  ```
  `docs/global_conventions.md:11`:
  ```
  | Card chrome via `OmniSurface`; card headers via `OmniCardHeader` | Every outlined card in the app must route through `OmniSurface` (single source of truth for border, radius, shadow); every section / card header must route through `OmniCardHeader` (single source of truth for canonical D-1 typography). Raw Flutter `Card(...)` widgets and raw `Text` widgets above outlined cards are not permitted. Per-screen `_SectionHeader` / `_SectionLabel` / `_SummaryCard` / `_MeasurementRow` style widgets have been migrated to these primitives. | `docs/widget_catalog.md`, `docs/design_system.md` ("Section / Card Headers"), `lib/widgets/layout/omni_surface.dart`, `lib/widgets/layout/omni_card_header.dart`, `docs/plans/unified-card-and-header-plan.md` |
  ```
- Where the code does it: `lib/features/stats/widgets/recent_pr_list.dart:33-41` — the card's
  title is a raw `Text` inside the `OmniSurface`, in `titleSmall`/w600/`textDominant`, i.e. none of
  the D-1 properties (`labelSmall`, letterSpacing 2.0, `textMuted`):
  ```
    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent PRs',
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
  ```
- What a user would see: the Recent PRs card title reads larger, brighter and unspaced next to the
  `ALL TIME` eyebrow above it — two different "card title" styles on one screen.
- Guard: none found: searched `test/header_standardization_test.dart` for `RecentPRList`,
  `Recent PRs`, `records_and_trends` — no matches.
- Unsure: whether `RecentPRList`'s title counts as a "per-card title" under D-1 or as body lead-in;
  the rule's wording ("per-card title") reads as covering it.

### F3 · INCONSISTENT · Two different single-point cards: the screen's private one and the shared primitive

- Where the doc says it: `docs/widget_catalog/feature_primitives.md` documents the shared
  single-point card (via `chart_primitives.dart`); `docs/records_and_trends.md` describes the
  Exercise Progress series but not its single-point fallback.
- Where the code does it: `lib/features/stats/exercise_progress_screen.dart:316-341` builds a
  private `_buildSinglePointCard` whose first line is `'$label · ${OmniDateUtils.formatShort(date)}'`:
  ```
          Text(
            '$label · ${OmniDateUtils.formatShort(date)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '1 session — log more to see a trend',
  ```
  while the shared `lib/widgets/chart/chart_primitives.dart:45-66` `buildSinglePointCard` renders
  `'$label $value'` (no date) with identical container decoration and identical second line:
  ```
  /// Deliberate single-point card for a metric whose history holds exactly one
  /// day — the chart is replaced by the one value rather than a one-point line.
  Widget buildSinglePointCard({
    required ThemeData theme,
    required OmniThemeColors themeColors,
    required String label,
    required String value,
    required DateTime date,
  }) {
  ```
  Caller of the shared one: `lib/features/stats/widgets/nutrition_trend_card.dart:623`.
- What a user would see: in Exercise Progress the one-point state reads `Deadlift 82.5 kg · 12 Oct`
  (value + date); in the nutrition trend card it reads `Weight 82.5 kg` (label + value, no date).
  Same component name, same second line, different first-line content shape.
- Guard: none found: searched `test/` for `buildSinglePointCard` — only the nutrition-trend usage;
  no test covers the Exercise Progress single-point card's text.
- Unsure: whether the date suffix is a deliberate Exercise Progress requirement (not written anywhere).

### F4 · INCONSISTENT · Section-header capitalisation: uppercase eyebrows and title-case headers on the same screens, no rule for which

- Where the doc says it: `docs/design_system.md` D-1 table row "Letter spacing | `2.0` | The
  'Labels' track — uppercase or small-caps feel" describes the style, not the case; the
  "Where the canonical header is used" table enumerates both styles per screen without a rule
  (`PREFERENCES` uppercase; `Today`, `Foods I Eat` title-case; Stats mixes both).
- Where the code does it: on Stats, uppercase `TRAINING MIX`, `SIGNALS`, `ALL TIME` sit beside
  title-case `Resistance`, `Cardio`, `Isometric`, `Sports`, `Fuel` (all via `OmniCardHeader`,
  grep-verified in `mix_layer.dart`, `signals_layer.dart`, `instrument_list.dart`, `fuel_section.dart`,
  `stats_screen.dart`); Records & Trends has uppercase `ALL TIME` and title-case section labels.
- What a user would see: two header "voices" on one screen; nothing tells a developer which case a
  new section header should use.
- Guard: `test/instrument_list_screen_test.dart` (`S-1001`, `S-1011`, `S-1015`) asserts the
  title-case labels; no test asserts the uppercase ones' case as a rule.
- Unsure: none.

### F5 · NO-RULE · Loading state: a centred `CircularProgressIndicator`, documented nowhere

- Where the doc says it: nowhere. A prior plan deliberately deleted the sentence:
  `docs/plans/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.evidence.md:266`:
  `| F-5 | docs/stats_screen.md claimed a loading spinner that no test covers | sentence deleted | doc-standard violation removed |`
- Where the code does it: all three screens, same shape — `lib/features/stats/stats_screen.dart:279-280`:
  ```
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
  ```
  `records_and_trends_screen.dart:111-112` and `exercise_progress_screen.dart:99-100` are identical.
- What a user would see: a bare centred spinner on the theme background while data loads; no
  skeleton, no copy. Consistent across the area but unwritten.
- Guard: none found: searched `test/` for `CircularProgressIndicator` under stats tests — no matches.
- Unsure: none.

### F6 · NO-RULE · Silent error handling: `catch (_) { _isLoading = false; }` renders an empty screen, no error surface

- Where the doc says it: nowhere in the area docs (no error-state section in `stats_screen.md`,
  `records_and_trends.md`).
- Where the code does it: all three screens — `lib/features/stats/stats_screen.dart:182-185`:
  ```
      } catch (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
  ```
  `records_and_trends_screen.dart:90-93` and `exercise_progress_screen.dart:74-77` are identical.
  (A fourth `catch (_)` at `stats_screen.dart:226-228` only skips persisting signal dismissals —
  commented, fine.)
- What a user would see: a load failure looks exactly like "no data": Stats shows the first-use
  empty state, Records & Trends shows `No sessions yet`, Exercise Progress shows its empty state.
  No error copy, no retry.
- Guard: none found: searched `test/` for stats tests asserting error/exception paths on these
  screens — none.
- Unsure: whether a repository failure is even reachable in production (repos are local Hive).

### F7 · NO-RULE · Empty-state card pattern (OmniSurface + icon + title + body) shared by the screens, written only per-screen

- Where the doc says it: `docs/stats_screen.md:49-58` documents the Stats first-use card's exact
  copy and primer extension; `docs/records_and_trends.md` and `docs/records_and_trends.md:126`
  mention "an empty state" without describing it; no doc states the shared visual pattern as a rule.
- Where the code does it: `_buildEmptyState` in `stats_screen.dart` and
  `records_and_trends_screen.dart` (same OmniSurface + icon + `No sessions yet` +
  `Complete your first session to see stats here.` shape); `exercise_progress_screen.dart` has its
  own `No history for this exercise` variant.
- What a user would see: consistent empty states (good), but a developer has no written pattern to
  follow for the next screen.
- Guard: `test/stats_primer_screen_test.dart` (`S-2707`) covers the Stats card's copy; none covers
  the pattern as a rule.
- Unsure: none.

### F8 · NO-RULE · Streak flame icon appears at ≥3 days, rule lives only in an old plan doc

- Where the doc says it: not in any standing doc. Only
  `docs/plans/stats-screen-plan.md:86`: "Streak row includes flame icon (🔥 or
  `Icons.local_fire_department`) when streak ≥ 3, colored primary" (a historical plan, not a standard).
- Where the code does it: `lib/features/stats/stats_screen.dart:402-409` and
  `records_and_trends_screen.dart:249-256`, identical:
  ```
              trailingIcon: _streakDays >= 3
                  ? Icon(
                      Icons.local_fire_department,
                      size: 18,
                      color: themeColors.primary,
                    )
                  : null,
  ```
- What a user would see: a primary-coloured flame next to the streak value from 3 days up; below 3
  days no icon. The threshold is invisible to the reader and unwritten for developers.
- Guard: none found: searched `test/` for `local_fire_department` — no matches.
- Unsure: none.

### F9 · NO-RULE · Change-colour semantics (primary = increase, error@0.8 = decrease, muted = none/absent) consistent in code, unwritten

- Where the doc says it: nowhere; `docs/stats_screen.md` describes the Instruments change column
  and Fuel deltas but assigns no colour rule.
- Where the code does it: `lib/features/stats/widgets/instrument_row.dart:141-152` (`InstrumentChangeChip`):
  ```
      final change = delta;
      final Color color;
      if (change == null || change == 0) {
        color = themeColors.textMuted;
      } else if (change > 0) {
        color = theme.colorScheme.primary;
      } else {
        color = theme.colorScheme.error.withValues(alpha: 0.8);
      }
  ```
  and `lib/features/stats/widgets/fuel_section.dart:231-236`:
  ```
    Color _changeColor(ThemeData theme, String change) {
      if (change == kFuelAbsent) return themeColors.textMuted;
      return change.startsWith('↑')
          ? theme.colorScheme.primary
          : theme.colorScheme.error.withValues(alpha: 0.8);
    }
  ```
- What a user would see: consistent green-up/red-down/muted-flat across Instruments and Fuel —
  but the convention exists only in code, duplicated in two places.
- Guard: none found: searched `test/` for `withValues(alpha: 0.8)` assertions on these widgets — none.
- Unsure: none.

### F10 · NO-RULE · Records & Trends search field: `TextCapitalization.none`, no select-on-focus, keyboard dismissal only via the app-wide wrapper

- Where the doc says it: `docs/records_and_trends.md:104-110` documents filtering behaviour only.
  The capitalisation rule exists only in a plan:
  `docs/plans/keyboard-dismissal-and-capitalization-plan.md:103`: "this is a search field, use
  `TextCapitalization.none` (search should not auto-cap)". No standing doc carries it.
- Where the code does it: `lib/features/stats/records_and_trends_screen.dart:146-148`:
  ```
        TextField(
          key: const Key('records_and_trends_search_field'),
          controller: _searchController,
          textCapitalization: TextCapitalization.none,
  ```
- What a user would see: search text stays as typed (no auto-cap); dismissal depends on the
  app-wide tap-outside wrapper, not on anything this screen does.
- Guard: `test/capitalization_defaults_test.dart` covers search fields generally (per the plan's
  log); no stats-specific assertion found: searched it for `records_and_trends` — no matches.
- Unsure: none.

NOTICED: `lib/core/models/signals.dart:60` — stale pre-D-4001 comment `/// layer renders nothing at all.`
on `SignalsData`; D-4001 replaced "renders nothing" with the locked line, so the comment no longer
matches `signalsLockedLine` behaviour (code defect in a comment only; behaviour is correct).

---

## 3. Pattern matrix (P1–P12) for the area's screens

Legend: ✓ = verified this run (file:line noted) · — = not applicable · ? = not checked (reason below).

| Screen | P1 top bar/header | P2 section/card header | P3 empty state | P4 locked/unavailable | P5 confirmation | P6 unsaved guard | P7 text entry | P8 bottom action | P9 sheets/modals | P10 theme tokens | P11 a11y/scale/targets | P12 charts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| StatsScreen | ✓ OmniBackHeader('Stats') + '?' & chart-icon actions | ✓ OmniCardHeader: TRAINING MIX(+chip), SIGNALS, ALL TIME, 4 title-case instruments(+chip on 1st), Fuel | ✓ OmniSurface card, 'No sessions yet' / 'Complete your first session to see stats here.' (+primer lines/button) | ✓ SignalsLockedSection 'Unlocks after 4 weeks…'; Fuel '—' (kFuelAbsent); change '—' | — none (signal dismissal unconfirmed by design, documented) | — read-only | — none | — none (no OmniBottomCTA; read-only screen) | ✓ StatsPrimerSheet via showModalBottomSheet (auto-open from Home + '?') | ✓ OmniTheme tokens + ModalityColors; no raw colours/sizes found | ✓ Semantics on header actions, mix bar/weeks, fuel row, primer help; dismiss 48dp; legend ExcludeSemantics | — no chart on this screen (S-1210 forbids); mix bar/strip are custom Rows |
| RecordsAndTrendsScreen | ✓ OmniBackHeader('Records & Trends') | ✓ OmniCardHeader 'ALL TIME' + title-case section labels; ✗ RecentPRList raw Text title (F2) | ✓ same 'No sessions yet' card | — n/a | — none | — read-only | ✓ search TextField, TextCapitalization.none, clear button (F10) | — none | — none | ✓ tokens; no raw colours/sizes found | ? InkWells/rows not audited for Semantics/tap targets this run | — none |
| ExerciseProgressScreen | ✓ OmniBackHeader('Exercise Progress', subtitle: exercise name) | ✓ OmniCardHeader 'ALL TIME', 'TREND', 'RECENT SESSIONS' | ✓ 'No history for this exercise' | ✓ single-point card '1 session — log more to see a trend' (private variant, F3) | — none | — read-only | — none | — none | — none | ✓ tokens; raw TextStyle(fontSize: 9) on chart date labels (screen + ScrollableTrendChart pinned axis) | ? chart-label text-scale behaviour not audited | ✓ ScrollableTrendChart + fl_chart LineChart, LineTouchData(enabled: false), ChartAxisHelper bounds, edge-aware date labels |
| SessionSummaryScreen (row only, shared with S6) | ✓ OmniBackHeader(title, actions: overflow Edit/Save-as-Routine/Discard) | ✓ OmniCardHeader date(+modality chip), 'DISTANCE', 'SESSION NOTE', month(+Open Calendar); group cards use raw titleMedium coloured titles (S6's area) | ? group cards simply absent when empty (S6 owns) | — n/a | ✓ ConfirmationDialog.showTwoChoice('Discard session?') :340 | ? none seen; note autosaves (S6 owns) | ✓ note TextField :1200; distance via metric popup | ✓ OmniBottomCTA('Done') in Positioned bottom :742 | ✓ EffortRatingSheet.show :275/:297; save-as-routine showModalBottomSheet :481 + showDialog :502 | ✓ tokens; raw Colors.white.withOpacity(0.06) divider + onSurface.withOpacity(0.65) in group cards (S6's area) | ? not audited (S6 owns) | — none |

"?" reasons:
- RecordsAndTrends P11: entry rows/InkWells read as plain text; I did not audit Semantics labels or
  48dp targets row by row this run.
- ExerciseProgress P11: the 9px chart labels use `TextStyle(fontSize: 9)`; whether they scale with
  the system text scale was not tested this run.
- SessionSummary P3/P6/P11: that screen is S6's area; I only filled the cells I could verify from
  the shared-matrix requirement (P1/P2/P5/P7/P8/P9/P10/P12).

---

## Open questions for the governor

1. F2: treated `RecentPRList`'s 'Recent PRs' as a D-1 "per-card title" (rule wording supports it;
   the alternative reading — body lead-in — would make it NO-RULE instead of BREAKS-RULE).
2. F4: filed header capitalisation as INCONSISTENT (two conventions coexist on one screen) rather
   than NO-RULE; either kind fits.
3. F1: filed the design_system table omission as STALE-DOC (incomplete inventory) — the normative
   sentence above the table is still true.
4. `docs/signals.md` was read in full; its UI claims (locked line, quiet line, card pattern) all
   match code — no findings from it beyond what is listed.
