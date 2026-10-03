# Review — Stats PR 4b2, the Instruments list on the Stats screen

Reviewer: `@code-reviewer`. Reviewed against the plan, `docs/global_conventions.md`,
`docs/design_system.md`, `docs/navigation_contract.md` and `docs/documentation_standard.md`.
The tree is the uncommitted `develop` working tree (8 modified, 6 untracked).

**Layers in scope:** features (`lib/features/stats/`, including its feature-local `widgets/`),
tests, docs.
**Layers skipped:** models, repositories, state, core — no file in those layers changed.

---

## Gates (re-run by the reviewer on this tree)

| Gate | Output (verbatim, last line) |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh lint` | `199 issues found. (ran in 2.5s)` — 0 errors, equal to the recorded baseline of 199 |
| `.github/copilot/scripts/macos/gateway.sh test` | `01:14 +3208 ~1: All tests passed!` — 0 failures, 0 new skips; 3183 baseline + 24 new + 1 guard |

Both match the implementer's §4 evidence. The red run (`+0 -24`, every failure a missing widget)
and mutations M5/M6/M7 are credible and reproduce the failure counts the plan predicted: M5 and M6
each fail exactly the two S-1016 / S-1017 tests, M7 fails exactly S-1012 ×2 and S-1015 ×2.

---

## Findings

| # | Severity | Location | Finding | Fix | Owner |
|---|---|---|---|---|---|
| 1 | minor | `lib/features/stats/widgets/instrument_row.dart:142` | The no-comparable / no-change dash uses `themeColors.textMuted`; D-508 names `_buildGroupComparisonChip`'s colour, which is `colorScheme.onSurface.withOpacity(0.65)` (`session_summary_screen.dart:1130`). Not in the evidence's deviations table. Width 92, right alignment, `labelSmall` + `w600` and both arrow colours do match. | Either derive the dash colour as the reference chip does, or record the token choice in the plan's Assumption Log. Non-blocking: `textMuted` is a token and the rule-2 (tokens only) alternative. | @developer (optional) |
| 2 | minor | `lib/features/stats/widgets/instrument_list.dart:44` | D-507 says the expanded state "reset[s] when `_loadData` produces new data"; `_expanded` survives a reload because the element is reused, so a section stays expanded across new data. Observable effect is benign (nothing is hidden), but the decision text and the code disagree and no test covers it. | Correct the decision's parenthetical, or add a `didUpdateWidget` reset plus a test. | plan owner / @developer |
| 3 | nit | `lib/features/stats/widgets/window_chip.dart:11` | Comment says "the five legacy headers"; there are four chip call sites (`STRENGTH`, `CARDIO`, `ISOMETRIC`, `SPORTS`). | Say four. | @developer |
| 4 | nit | `lib/features/stats/widgets/instrument_list.dart:103` | The expand control is a `TextButton`; the design-system variant table enumerates `TextButton` only in the Dialog row. D-507 mandates "a text control" and the mandatory shape rule is satisfied (`OmniTheme.buttonUtilityRadius`), with no hardcoded colour — so this is accepted, but the table now has no row for a bare inline text control. | No change required. Note the unenumerated variant for a later design-system pass. | — |
| 5 | nit (process) | evidence §8 | The structural-guard mutation was not run, so the guard's third-constructor failure is asserted rather than shown. The assertion is exact list equality over a `lib/` scan (`test/records_and_trends_screen_test.dart:664`), so an extra constructor cannot pass. | Record the mutation output in §8 for symmetry with M5/M6/M7. | @developer (evidence only) |
| 6 | warning | `docs/README.md:69` | The Stats Screen index row enumerates the screen's sections and does not mention the Instruments list — incomplete, but it states nothing false. | Add the Instruments list to that row. | @developer |
| 7 | observation | `.claude/commands/feature.md` | Modified in the shared working tree and not part of this change; the diff shows only a one-line change and this phase never wrote to `.claude/`. | Do not sweep it into the commit. | owner |

No blockers. Findings 1–5 are non-blocking; 6 is an incomplete-doc warning; 7 is working-tree hygiene.

---

## Step 5a — Acceptance criteria

| AC | Where it lands | Result |
|---|---|---|
| AC-1 four sections with the four kinds' figures | `S-1001` (6 tests × 2 harnesses): section order, row order, figure via `formatNativeValue(summary.best, settingsState)`, secondary line, change chip | PASS |
| AC-5 a lifting-only user sees only Resistance | render path applies no filter of its own; the section set is the service's (4b's `S-1013` / `S-1005`) | PASS |
| AC-6 8 exercises → 5 rows + `Show all (8)` | `S-1016` (5 / 6 / 8 rows, expand, collapse, per section); mutation M5 fails exactly these two | PASS |
| AC-8 row tap opens Exercise Progress with pre-window history | `S-1014`: asserts the pushed screen's `exerciseId` for two different rows, day labels 40/20/1, and back navigation | PASS |
| AC-11 old sections still appear | `S-1015` + `screen_widget_test.dart` and `header_standardization_test.dart` run unmodified (byte-identical to `develop`) | PASS |
| AC-12 exercises outside the old top-N now appear as rows | `S-1001` (the duplicate-name pair, `ex-old` absent) + 4b's `S-1010` | PASS |

AC-1, AC-2, AC-3, AC-4, AC-7, AC-9, AC-10 belong to 4b / 4b3.

## Step 5b — Scenario register

Every scenario this plan owns has a group in `test/instrument_list_screen_test.dart`, runs on both
repository harnesses, and passes (24 tests). Fixtures were populated as the register states, with the
two declared substitutions recorded in the evidence (§9) and re-checked here:

- `S-1012` — "nothing in the window" is reachable only as two effort-less completed sessions (A-5);
  the assertions (no section, no control, no row, legacy intact, nothing throws) all hold.
- `S-1014` — the day-label assertions use `findsWidgets` (A-6), which is non-vacuous here: the test
  also pins the pushed screen's `exerciseId` for both tapped rows.

No scenario is missing a passing test; no test asserts an outcome the register does not state.

## Step 5c — Documentation falsification

| Document | Verdict |
|---|---|
| `docs/stats_screen.md` | PASS — the Instruments subsection matches the shipped widget tree; the Overview no longer claims the screen has no controls; the window-label section names `StatsWindowChip`; the legacy sections are described as wrapped in `Key('stats_legacy_sections')` with structure unchanged, which is what `stats_screen.dart:171` does |
| `docs/widget_catalog.md` | PASS — names the four files and their responsibilities; all four exist |
| `docs/navigation_and_screens.md` | PASS — `ExerciseProgressScreen`'s "reached only from a `RecordsAndTrendsScreen` entry" is corrected to both entry points, matching the guard |
| `docs/design_system.md` | PASS — the Stats header row gains the four title-case Instruments headers and points at the test; no values or hex added |
| `docs/records_and_trends.md` | PASS — its "no single-entry rule" sentence was falsified by the new entry point and corrected; the edit is out of Predicted Files (A-9) but required |
| `docs/state_management/services_and_utils.md`, `docs/data_models.md` | PASS — their `computeInstrumentSections` and value-type claims are 4b's and still hold; `formatNativeChange` is still the only formatter the row uses |
| `docs/README.md` | 🟡 WARNING (finding 6) — incomplete, not false |
| `docs/constants_reference.md` | PASS — `kInstrumentRowCap` is feature-local, outside its declared `lib/core/constants/` scope |
| `docs/stats_best_load_investigation.md` | PASS — declares itself an investigation pinned to `HEAD 1c7c903`; its `file:line` citations are revision-pinned, not current-state claims |

No document was found asserting something untrue about the current product, and no two implicated
documents conflict.

## Step 5c-2 — Documentation standard

`DOC STANDARD: ✅ PASS — no prohibited content added.` The added prose names `kInstrumentRowCap`
without restating its value, names tests instead of restating behaviour, and adds no hex, no line
numbers, no walkthrough, no control table, no roadmap or unshipped-change note. `design_system.md`
stays inside its visual-rules exception; the three guard tests are green in the full suite.

## Step 5d — Global conventions

`PASS (7 rules): units/canonical storage, theme tokens only, card chrome via OmniSurface/OmniCardHeader, effort-kind drives analytics, timestamps are source data, reuse the canonical owner, instrument panel not influencer.`
`N/A (0 rules).`

Rule-by-rule basis: all four new widgets render theme tokens and read units through
`native_value_format.dart`; every section header routes through `OmniCardHeader`; sections and rows
come from the service keyed on `ExerciseSection`; no widget re-derives a timestamp; `StatsWindowChip`
is the single owner of the window chip and `formatNativeChange` the single formatter; the list is a
dense readout with no new motion, gradient or decorative chrome.

## Architecture (in-scope layers)

- **Features** — the screen takes state by constructor, does not touch the repository, and computes
  nothing in `build`; the only navigation is `OmniNavigator.push` with no raw route, so
  `test/navigation_contract_enforcement_test.dart` is green.
- **Feature-local widgets** — presentation-only; the only local state is the per-section expansion
  set, which is UI state.
- **Single window resolution (D-514)** — `_loadData` calls `computeInstrumentSections` once with
  `progressData.window` (`stats_screen.dart:92`) and assigns inside the same `setState`; no second
  resolution exists.
- **Buttons** — the one new button sets an explicit `shape` with `OmniTheme.buttonUtilityRadius`
  (`= 8.0`, `omni_theme.dart:545`), which exists; no `StadiumBorder`, no hardcoded colour.
- **Dead code** — `_buildWindowChip` is gone with no dangling reference; `StatsWindowChip` has one
  declaration and five call sites. `AppState` is untouched by this change and stays a known issue.

## Tests

Coverage is complete for the new public behaviour: 12 tests × 2 harnesses covering all seven
scenarios, each scenario's fixture populated as specified, plus one structural guard. Two gaps, both
recorded above and neither blocking:

- finding 2 — D-507's "reset on new data" clause has no test;
- finding 5 — the guard's mutation was not run.

No stale test remains: no existing assertion was weakened, deleted or skipped, and the two legacy
suites are byte-identical to `develop`.

## Predicted-Files audit

| Out-of-bounds files touched | Predicted files untouched |
|---|---|
| `docs/records_and_trends.md` (declared, A-9 — Step 6 falsified its single-entry sentence) | `lib/features/stats/widgets/native_value_format.dart` ✓ |
| `.claude/commands/feature.md` (not this phase — see finding 7) | `test/db_seed_test.dart` ✓ |
| | `test/screen_widget_test.dart`, `test/header_standardization_test.dart` ✓ |

## Structural guard

`test/records_and_trends_screen_test.dart:664` scans `lib/` for files containing the literal
`ExerciseProgressScreen(` and asserts exact list equality with the two known entry points. It is a
plain `test()`, so it runs once, and it cannot pass with a third constructor. Its only blind spot is
a construction written without the adjacent parenthesis, which Dart's grammar does not produce.

## Scope budget

Six substantive findings, none CRITICAL, none spanning layers, all fixable in one pass. **No split
recommended** — the plan's remaining work (removing the legacy sections) is already planned as 4c.

---

## Recommendation

`→ @developer` (non-blocking, one pass): findings 1, 3, 6; finding 5 in the evidence file only.
`→ @dba`: nothing.

**VERDICT: APPROVE** — no blockers; findings 1–5 are non-blocking and 6 is an incomplete-doc warning.
