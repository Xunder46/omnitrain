# Evidence — Stats clarity (plan 24)

> **Companion to:** `docs/plans/2026-10-12-24-stats-clarity-plan/2026-10-12-24-stats-clarity-plan.md`
> **Rule:** baselines, suite output, mutation proofs and red runs go **here**, never into the plan.
> **Status:** created empty by the crew-architect 2026-10-12; §1…§9 are filled as the phases run
> (baselines by the implementer before P1; §4 by each phase's owner; §6 by `crew-docs-keeper` in P4;
> §7…§9 by the prover and the reviewer).
> **Review file (reserved, not created):**
> `docs/plans/2026-10-12-24-stats-clarity-plan/2026-10-12-24-stats-clarity-plan.review.md`

---

## §1 Baselines (implementer: re-run before Phase 1)

Commands are `.github/copilot/scripts/macos/gateway.sh …` from the repository root.

| Command | Planner-recorded baseline | Re-run by the implementer |
|---|---|---|
| `gateway.sh lint` | 196 issues, 0 errors (plan brief) | 195 issues, 0 errors — measured by P1, P2 and P3 alike (each report's Checks section); no issue names a plan-24 file |
| `gateway.sh test` | (empty — record the pass/skip/fail counts on the phase's branch) | Governor's final verification: full suite `+4347 ~1: All tests passed!`; `flutter analyze` 195 issues, 0 errors; base commit `4e4fdd9a94245b0e9d849fd694c7e5de63ef2ebc` |

---

## §2 Ground truth the plan was written against

- `signalsGateMet(mix)` — `lib/core/models/signals.dart` (plan cited `:72`); P1 added `signalsLockedLine` directly after it (declaration `:82`).
- `MixLayerData` — `lib/core/models/training_load.dart` (plan cited `:103`, six fields); P2 added the optional `lastSessionDay` (field `:107`, ctor param `:116`).
- `_buildStrip` / `MixLayerSection` — `lib/features/stats/widgets/mix_layer.dart` (plan cited `:279` / `:33`); P2 added `_buildCaption` and `_buildEmptyStrip` in the same `build()`.
- `previousRangeFor` — `lib/core/services/stats_progress_service.dart` (plan cited `:1228-1246`); untouched. P3 added `StatsWindow.dayCount` (`lib/core/models/stats_progress.dart`, getter `:223`), pinned equal to it.
- `nativeSecondaryLabel` / `_secondaryLine` — `lib/features/stats/widgets/native_value_format.dart` / `instrument_row.dart`; P3 added `nativePrimaryLabel` (`:94`) and put it first in `_secondaryLine`.

---

## §3 Drift found while planning

- Assumption 1 (logged by the governor): `_seedGateUnmet` produces 0 rated weeks, not S-4001's 3; the new fixture `_seedGateUnmetThreeRatedWeeks` (S-4013) carries S-4001's numbers.
- Assumption 6: the Instruments caption prints the window's calendar span (`dayCount`), which can exceed the training-day count the chip shows (S-4017 pins `recentDays == 14`, `dayCount == 15`).

---

## §4 Per-phase evidence

### P1 Signals locked

All 8 items done (report `.work/crew/2026-10-12-24/report-p1.md`). Checks pasted there:
`gateway.sh test test/signals_layer_screen_test.dart --plain-name Mock` → `00:01 +27: All tests passed!`;
whole file → `00:03 +53: All tests passed!`; `test/signals_framework_test.dart test/signals_service_test.dart`
→ `+39`; `test/sustained_high_load_signal_screen_test.dart` → `+13`; `test/screen_widget_test.dart` → `+220`.
Lint 195, 0 errors. Deviation: S-4004's fixture replaced by one completed zero-duration session
(`_seedLifting(sessionId: 's-empty', daysAgo: 1, minutes: 0)`), because `resolveWindow` always contains a
completed session, so the plan's fixture could not null the Mix layer.

### P2 Strip

All 8 items done (reports `report-p2.md`, `report-p2-fix1.md`). Checks pasted there:
`test/mix_layer_screen_test.dart` → `00:03 +72: All tests passed!`;
`test/mix_layer_service_test.dart test/training_load_test.dart` → `+92`; post-revert re-run of the three files
→ `00:03 +164: All tests passed!`. Lint 195, 0 errors. Fix 1: the caption's two `Text`s wrapped in
`Flexible` (`maxLines: 1`, ellipsis) after the new 2.0-text-scale guard overflowed by 30 px; after the fix
`test/mix_layer_screen_test.dart` → `00:03 +74: All tests passed!` and `test/fuel_row_screen_test.dart`
→ `00:02 +42: All tests passed!`. Deviations: S-4006/S-4015 fixtures seed a sessionless `_seedPeriod` so the
recency rule picks the old days; `computeMixPeriod` takes `DateTime`, not epoch millis.

### P3 Instruments

All 8 items done (report `report-p3.md`). Checks pasted there:
`test/stats_window_day_count_test.dart test/instrument_change_format_test.dart test/instrument_list_screen_test.dart`
→ `00:02 +53: All tests passed!`; with `test/stats_legacy_removal_test.dart test/header_standardization_test.dart`
→ `00:05 +116: All tests passed!`; `test/instrument_list_service_test.dart` → `+18`. Lint 195, 0 errors.
Deviation: S-4011's fixture fixed to a midnight `fromMs` (a mid-day `fromMs` covers `dayCount + 1` calendar
days in its predecessor); assertion kept strict (`inDays == 13`, `dayCount == 14`, equality with
`previousRangeFor`). P3's own full-suite run was `02:03 +4343 ~1 -2` — the two failures were
`test/fuel_row_screen_test.dart`'s 390x844 @2.0 overflow, fixed in P2 fix 1.

### P4 Docs

All 8 items done (this phase). Edits: `docs/stats_screen.md` (What the Screen Displays, the strip, the
Signals gate, the Instruments caption and row labels, the line-532 paragraph, five Core Files rows),
`docs/signals.md` (the gate, the quiet line), `docs/widget_catalog.md` (Mix layer and Signals layer notes),
`docs/state_management/services_and_utils.md` (`lastSessionDay` in the `computeMixLayer` payload),
`docs/navigation_and_screens.md` (the StatsScreen row's Signals sentence),
`docs/training_load.md` (`lastSessionDay` in the `MixLayerData` field list), and this file.
Every cited scenario id and group name was grepped in its test file this run before being written.
Check: `gateway.sh test test/docs_indexing_contract_test.dart` → `00:00 +9: All tests passed!`
(link resolution, the 64 KiB ceiling, the 52,429-byte warning band all green).

---

## §5 Red runs and mutation proofs

From the builders' reports (the prover's own runs are §-reserved for the prover; the governor adds the proof
mutations):

- P1: `gateway.sh prove-red 4e4fdd9a… test test/signals_layer_screen_test.dart` → `RED AT 4e4fdd9a… (exit 1)`
  via compile/load error (`Method not found: 'signalsLockedLine'` at `:684`/`:685`) — the additive API cannot
  exist at base; the report notes rewritten guards need a mutation, which is the prover's call.
- P2: `prove-red` at base for both new guards is a load error (`The getter 'lastSessionDay' isn't defined for
  the type 'MixLayerData'`). The builder ran the plan's three named mutations against the shipped tree instead,
  each reverted immediately: track `startedAtMs` before the `endedAtMs == null` skip (S-4015) → `+0 -4`;
  `.last` instead of `.first` in `_buildCaption` (S-4014) → `+0 -2`; remove `layer.weeks.isNotEmpty &&` from
  `_stripIsEmpty` (S-4016) → `+0 -2` (`Found 1 widget with key [<'mix_strip_empty'>]` where none is expected).
- P2 fix 1: the new caption guard red before the fix — `A RenderFlex overflowed by 30 pixels on the right.`
  on both harnesses (`00:01 +8 -2`); green after (`+74`).
- P3: `gateway.sh prove-red 4e4fdd9a… test test/fuel_row_screen_test.dart` → `GREEN AT 4e4fdd9a…` — evidence
  the full-suite failure was this branch's uncommitted P1/P2 work, not base and not P3.


### Governor's verification (2026-10-12, observed by the governor, not taken from the reports)

- Full suite after the fix: `flutter test` → `+4347 ~1: All tests passed!` (exit 0). Before the fix the builder's run
  had `+4343 ~1 -2` (both `test/fuel_row_screen_test.dart`, 390x844 at 2.0 text scale); the governor bisected it by
  reverting one changed file at a time to its base copy: only `mix_layer.dart` made it green (the strip caption
  Row overflowed, 30 px, Ahem font). Fixed in P2 fix 1 with a guard first.
- `flutter analyze` → `195 issues found` (0 errors; the plan's recorded baseline was 196). Invariant grep
  (`hive_workout_repository` imported from state/features/widgets/core) → no output.
- Proof mutations applied by the governor, each restored and byte-compared: drop `.clamp` in `signalsLockedLine`
  → S-4002 red (Mock+Hive); pass `kTrainingLoadMinRatedWeeks` instead of `ratedBaselineWeeks` → S-4013 and S-4002
  red; skip-check removed in `_mixPayload` → S-4009, S-4015 red; `.first` → `.last` in the caption → S-4005, S-4014,
  S-4008 red; drop `layer.weeks.isNotEmpty` → S-4016 red; `+ 1` → `+ 0` in `dayCount` → S-4011 red (13 failures);
  drop the primary label in `_secondaryLine` → S-1001, S-4012, S-4019 red; `recentDays` in the caption → S-4017 red;
  caption under every section → 28 failures in `instrument_list_screen_test.dart` (S-4018 among them).
- Review round (crew-reviewer, glm-5.3-flash): APPROVE, 0 blocker, 0 major, 1 minor. The minor (the empty-strip
  line could name a day inside the span it calls empty, when a session in the last 8 weeks had zero measure) was
  fixed in P2 fix 2 with guard S-4021 (red before: `Found 1 widget with key mix_strip_empty ... Last session: Apr 20.`;
  green after). Final governor run: `flutter test` `+4349 ~1: All tests passed!`, `flutter analyze` 195 issues.
- **Equivalent mutant (survived):** removing `!signalsGateMet(_mixLayer)` from the locked branch in `stats_screen.dart`
  leaves `test/signals_layer_screen_test.dart` green (`+53`). It cannot be killed: the `else if` is reached only when
  `_signalsData == null`, and `_loadData` sets that exactly when the gate is unmet, so the half is redundant. The
  behaviour guard for "gate met shows no locked section" (S-4003) holds through the first branch. Kept as a
  defensive duplicate; the reviewer was asked whether to simplify.

---

## §6 Doc updates

- `docs/stats_screen.md` — the strip paragraph now states the caption (oldest week's date left, `this week`
  right, both ends shrink to fit) and the empty-strip line with the last session's date
  (`test/mix_layer_screen_test.dart`: `S-4005`, `S-4006`, `S-4015`, `S-4014`, `Guard — the caption fits
  390x844 dp and 2.0 text scale`); the Signals gate paragraph now states the locked section and its line
  (`test/signals_layer_screen_test.dart`: `S-1701`, `S-1702`, `S-4001`, `S-4002`, `S-4013`, `S-4003`,
  `S-4004`); the Instruments section gains the caption sentence (`S-4010`, `S-4017`, `S-4018`;
  `test/stats_window_day_count_test.dart` `S-4011`) and the per-row labels sentence (`S-4012`, `S-4019`;
  `test/instrument_change_format_test.dart` `nativePrimaryLabel`); the Core Files rows for `mix_layer.dart`,
  `signals_layer.dart`, `native_value_format.dart`, `training_load.dart` and `stats_progress.dart` name the
  new members; the "What the Screen Displays" and line-532 paragraphs mention the locked line.
- `docs/signals.md` — the gate section: "renders nothing at all" replaced by "evaluates nothing and shows the
  locked line" (`S-4001`, `S-4002`, `S-4013`); the quiet-line section names the locked line for a gate-unmet
  load (`S-4002`).
- `docs/widget_catalog.md` — the Mix layer note names the caption and the empty-strip line; the Signals layer
  note names the sibling `SignalsLockedSection`.
- `docs/state_management/services_and_utils.md` — the `computeMixLayer` payload names `lastSessionDay`.
- `docs/navigation_and_screens.md` — the `StatsScreen` row's Signals sentence states the locked line for
  fewer than four rated weeks.
- `docs/training_load.md` — the `MixLayerData` field list names `lastSessionDay` (`test/mix_layer_service_test.dart`
  `S-4009`).

---

## §7 Deviations from the plan

- P1: S-4004's fixture replaced (zero-duration session) — the plan's fixture cannot null the Mix layer.
- P2: S-4006/S-4015 fixtures seed a sessionless `_seedPeriod` so `resolveWindow` picks the old days;
  `computeMixPeriod` takes `DateTime`.
- P2 fix 1: the caption's two ends are `Flexible` with ellipsis — an unplanned guard and fix, red then green.
- P3: S-4011's fixture moved to a midnight `fromMs`; the 1-day S-4010 test renamed to read "a 1-day window
  the caption names the day before it".
- P4: none — docs only.

---

## §8 Reviewer findings

(empty)

---

## §9 Scenario conformance

Every id below was grepped in its test file this run (P4); group names as declared there.

| Scenario | Test file · group |
|---|---|
| S-4001 | `test/signals_layer_screen_test.dart` · `S-4013 the locked section takes the layer slot` (carries S-4001's numbers) |
| S-4002 | `test/signals_layer_screen_test.dart` · `S-4002 the locked line counts rated weeks` |
| S-4003 | `test/signals_layer_screen_test.dart` · `S-4003 gate met renders the layer, not the locked line` |
| S-4004 | `test/signals_layer_screen_test.dart` · `S-4004 a window with no time locks nothing` |
| S-4005 | `test/mix_layer_screen_test.dart` · `S-4005 the strip carries a caption naming its span` |
| S-4006 | `test/mix_layer_screen_test.dart` · `S-4006 eight empty weeks render one line, not a strip` |
| S-4007 | `test/mix_layer_screen_test.dart` · `S-4007 only the current week has training` |
| S-4008 | `test/mix_layer_screen_test.dart` · `S-4008 only the oldest of the eight weeks has training` |
| S-4009 | `test/mix_layer_service_test.dart` · `S-4009 lastSessionDay is the latest completed session in all history` |
| S-4010 | `test/instrument_list_screen_test.dart` · `S-4010 the caption states the window's real span` |
| S-4011 | `test/stats_window_day_count_test.dart` · `S-4011 StatsWindow.dayCount is the previous range's own length` |
| S-4012 | `test/instrument_list_screen_test.dart` · `S-4012 every row says what its number is` |
| S-4013 | `test/signals_layer_screen_test.dart` · `S-4013 the locked section takes the layer slot` |
| S-4014 | `test/mix_layer_screen_test.dart` · `S-4014 the caption’s two ends bracket the eight columns` |
| S-4015 | `test/mix_layer_screen_test.dart` · `S-4015 the empty line names the last completed session` |
| S-4016 | `test/mix_layer_screen_test.dart` · `S-4016 a payload with no weeks builds no strip` |
| S-4017 | `test/instrument_list_screen_test.dart` · `S-4017 the caption counts the comparison, not the chip's days` |
| S-4018 | `test/instrument_list_screen_test.dart` · `S-4018 one caption, under the first header` |
| S-4019 | `test/instrument_list_screen_test.dart` · `S-4019 the figures are untouched` |
| S-4020 | `test/instrument_list_screen_test.dart` · `S-4020 the new line uses the existing tokens` |
