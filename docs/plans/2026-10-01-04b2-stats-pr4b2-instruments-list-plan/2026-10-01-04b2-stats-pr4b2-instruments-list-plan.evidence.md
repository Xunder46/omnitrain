# Evidence — Stats PR 4b2, the Instruments list on the Stats screen

> **Companion to:** `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/2026-10-01-04b2-stats-pr4b2-instruments-list-plan.md`
> **Rule:** baselines, suite output, mutation proofs and surface-height bumps go **here**, never into the
> plan.
> **Status:** created by the planner with §1's baselines and the ground truth pre-filled; the implementer and
> the reviewer fill §4…§9 as the phase runs.
> **Siblings:** the Instruments data is
> `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/…`; the Fuel row is
> `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/…` (NOT READY).

---

## §1 Baselines (planner-recorded, re-run by the implementer before Phase 1)

Commands are `.github/copilot/scripts/macos/gateway.sh …` from the repository root.

| Command | Recorded by the planner (pre-4b) | Re-run by the implementer (post-4b) |
|---|---|---|
| `gateway.sh lint` | `199 issues found.` (4 warnings, 0 errors, 195 infos) | `199 issues found. (ran in 1.5s)` — 4 warnings, 0 errors, 195 infos; identical to the planner's, i.e. 4b added no new issue |
| `gateway.sh test` | `+3153 ~1: All tests passed!` | `+3183 ~1: All tests passed!` — 3183 = 3153 + 4b's three new suites; the baseline for this phase is **3183** |

The post-4b baseline is **3183 passing, 1 skipped, 0 failures**, and lint is **199 issues, 0 errors**. The
planner's `+3153` is pre-4b; the difference is 4b's own suites, exactly as the note below predicts.
`gateway.sh git-diff --stat -- lib test docs` was empty at the start of the phase, so the baseline numbers
are measured against a clean tree.

**The implementer's numbers will be higher than the planner's**, because 4b merged first and added its own
suites (`test/sensor_summaries_by_session_test.dart`, `test/instrument_list_service_test.dart`,
`test/instrument_change_format_test.dart`). Record the post-4b numbers as the baseline and say so; do not
"correct" them to the planner's.

**If your numbers differ, record what you saw and say so.** A different baseline is information; a missing
baseline is a failed phase.

The analyzer bar for the phase: **0 errors** and **no more than the baseline issue count**; every file the
phase touches has **0 issues of its own**.

`~1` is a pre-existing skipped test. It is not this PR's business; do not "fix" it.

---

## §2 Ground truth the plan was written against (H-numbered, continuing 4b's list)

Verified by reading `lib/` on the plan's date. If any of these is false when you start, the step that
depends on it is wrong — say so in §7 rather than working around it.

| # | Fact | Where | Used by |
|---|---|---|---|
| H-14 | `StatsScreen._loadData()` builds one `CalendarState` and one `StatsProgressService`; `build()` renders `OmniCardHeader('ALL TIME')` → `_buildAggregateCard` → five legacy sections separated by 24dp | `lib/features/stats/stats_screen.dart` | Steps 6, 9 |
| H-15 | `_buildWindowChip` renders `Text(key: Key('stats_window_chip'), '· ${window.label}', labelSmall + textMuted + italic, maxLines 1, ellipsis)` and is used by the four legacy headers | same (~172) | Steps 1, 6 |
| H-16 | `docs/design_system.md`'s canonical-header inventory lists Stats as `ALL TIME`, `STRENGTH`/`CARDIO`, `NUTRITION` (~line 180) — it will not mention the four Instruments headers until Step 10 | `docs/design_system.md` | Step 10 |
| H-17 | `docs/stats_screen.md`'s Key Constants table is at ~line 499 (`kTopLiftCount`, `kTopCardioCount`, `kRecentPRCount`, `kRecentTrainingDaysWindow`) — `kInstrumentRowCap` goes beside them | `docs/stats_screen.md` | Step 10 |
| H-18 | `docs/navigation_and_screens.md` (~line 197) says `ExerciseProgressScreen` is "reached only from `RecordsAndTrendsScreen`" — false after Step 6 | `docs/navigation_and_screens.md` | Step 10 |
| H-19 | `docs/` files over 64 KiB are skipped by the indexing tools; `docs/plans/`, `docs/releases/` and `docs/memories/` are exempt record folders | `test/docs_indexing_contract_test.dart` | doc checklist |
| H-20 | `ExerciseProgressScreen({required workoutState, required settingsState, required exerciseId})` — no other constructor, and the class name is what Step 8's guard scans for | `lib/features/stats/exercise_progress_screen.dart` (~26) | Steps 6, 8 |
| H-21 | `test/records_and_trends_screen_test.dart` (~line 648) already holds the structural guard "`StatsScreen` is the only file in `lib/` that constructs `RecordsAndTrendsScreen`", reading files with `dart:io` and asserting exact list equality | same | Step 8 |
| H-22 | `test/screen_widget_test.dart` and `test/header_standardization_test.dart` pump at fixed surface heights and assert legacy Stats content; the sites the plan names (~3542, ~3672, ~4001–4308, ~4461, ~4618; ~2710 at 1800) are the ones expected to fall below the fold | both files | Step 9 |
| H-23 | `test/records_and_trends_screen_test.dart` is the template for a harness-factory widget test: `for (final factory in harnessFactories)`, harness open/close in `setUp`/`tearDown`, `addTearDown(() => tester.binding.setSurfaceSize(null))` | same | Step 7 |

---

## §3 Drift found while planning

| # | Kind | Finding | Disposition |
|---|---|---|---|
| DR-1 | docs ↔ code | `docs/navigation_and_screens.md` states `ExerciseProgressScreen` is reached only from Records & Trends. After this PR it is also reached from the Stats Instruments rows. | Step 10 corrects the doc; S-1014 and Step 8's guard are the proof. |
| DR-3 | docs ↔ code | `docs/design_system.md`'s canonical-header inventory does not list the four Instruments headers, and there is no statement anywhere that the legacy Stats headers are uppercase while 4a's group labels are title case. | Step 10 adds the inventory row; the casing rule is the plan's open question 4. |

Drift that belongs to 4b (the duplicated sensor comparator) is recorded in 4b's evidence file.

---

## §4 Per-phase evidence (implementer fills)

### Phase 1 — the Instruments list on the Stats screen (@developer)

| Item | Output (verbatim) |
|---|---|
| Red run (`test/instrument_list_screen_test.dart` before the widgets exist) | `00:02 +0 -24: Some tests failed.` — 12 scenarios × 2 harnesses, all 24 failing, every failure a missing widget (`Found 0 widgets with key [<'instrument_row_…'>]`, `…[<'stats_legacy_sections'>]`, `…[<'instrument_show_all_cardio'>]`) — no harness or configuration error. S-1011's earlier assertions (`window.isPeriodScoped`, `label == 'Block A'`, `sections == [resistance]`, `'Deadlift'` absent) all passed, which validates the fixture independently of the missing UI. |
| Green run — the new file | `00:02 +24: All tests passed!` |
| Green run — `test/screen_widget_test.dart test/header_standardization_test.dart` | `00:08 +315: All tests passed!` — **unmodified**, no surface-height bumps (see §5) |
| Green run — `test/stats_progress_test.dart test/navigation_contract_enforcement_test.dart test/screen_overflow_contract_test.dart test/docs_indexing_contract_test.dart test/records_and_trends_screen_test.dart` | `00:02 +142: All tests passed!` |
| Full suite | `01:13 +3208 ~1: All tests passed!` (3183 baseline + 24 new + 1 new guard = 3208; 0 failures) |
| `gateway.sh lint` (per-file: 0 issues for the four new widgets and `stats_screen.dart`) | `199 issues found. (ran in 4.2s)` — 0 errors, equal to the baseline. 0 issues in the four new widget files and the new test file. `stats_screen.dart`'s only issue is the **pre-existing** `_ChartSeries` unused declaration (`unused_element`, line 2126), which is inside the baseline 199 and not in this phase's diff; the brief forbids fixing unrelated pre-existing issues. |
| Search sweep — `Key('stats_legacy_sections')` in `lib/` | exactly 1 construction (`stats_screen.dart:171`); the only other hits are the two finders in `test/instrument_list_screen_test.dart` |
| Search sweep — `_buildWindowChip` / `StatsWindowChip` in `lib/` | `_buildWindowChip`: 0 hits (gone). `StatsWindowChip`: 1 declaration (`widgets/window_chip.dart`) + 5 call sites (4 legacy headers in `stats_screen.dart` + the Instruments header in `widgets/instrument_list.dart`) |
| Search sweep — `kInstrumentRowCap` in `lib/` | 1 declaration (`instrument_list.dart:17`) + 2 reads (`take(kInstrumentRowCap)` at :72, the `>` comparison at :99) + 1 doc reference — the plan's "1 read" is a floor, not a cap; the second read is the control's own visibility rule |
| Search sweep — `MaterialPageRoute(` / `PageRouteBuilder(` outside `lib/core/navigation/` | 0 hits anywhere in `lib/` — no raw route was introduced |
| Mutation M5 (cap = 100) — failing / restored output | `00:02 +22 -2: Some tests failed.` — exactly the two S-1016 tests (Mock + Hive) failed, `Found 0 widgets with key [<'instrument_show_all_cardio'>]` (the control disappears when nothing is capped); all 22 others passed. Restored → `00:02 +24: All tests passed!` |
| Mutation M6 (`< 2` points → `< 0`) — failing / restored output | `00:02 +22 -2: Some tests failed.` — exactly the two S-1017 tests failed, `Expected: Size:<Size(0.0, 0.0)> / Actual: Size:<Size(56.0, 24.0)>` (a one-point row then draws a line); all 22 others passed. Restored → `00:02 +24: All tests passed!` |
| Mutation M7 (wrapper key removed) — failing output, or the no-failing-test note | `00:02 +20 -4: Some tests failed.` — exactly S-1012 ×2 and S-1015 ×2, `Found 0 widgets with key [<'stats_legacy_sections'>]`; all 20 others passed. Restored → `00:02 +24: All tests passed!` |
| `gateway.sh git-diff --stat -- lib test docs` | `docs/design_system.md \| 2 +-`, `docs/navigation_and_screens.md \| 4 +-`, `docs/records_and_trends.md \| 14 +++---`, `docs/stats_screen.md \| 86 ++++++---`, `docs/widget_catalog.md \| 4 ++`, `lib/features/stats/stats_screen.dart \| 85 ++++----`, `test/records_and_trends_screen_test.dart \| 21 ++++` — 7 files, +158/−58. The four new widget files and the new test file are untracked and so absent from `git diff`; that is also why M5 and M6 (which mutate two of them) leave no diff to inspect. |
| `gateway.sh git-status` | `M` on the five docs, `lib/features/stats/stats_screen.dart`, `test/records_and_trends_screen_test.dart`; `??` on the four new widgets, `test/instrument_list_screen_test.dart`, and both plan folders. **Not this phase:** `.claude/commands/feature.md` shows as `M` and was already modified in the shared working tree before this phase began — this phase never wrote to `.claude/`, and the file is untouched by the diff above. |
| `gateway.sh format` on the seven touched Dart files | `Formatted 7 files (2 changed) in 0.04 seconds.` — `lib/features/stats/widgets/instrument_list.dart` and `test/instrument_list_screen_test.dart` |
| `gateway.sh lint` immediately after formatting | `200 issues found.` — the formatter split a one-line `if` across two lines, which raised `curly_braces_in_flow_control_structures` at `instrument_list.dart:124` (a file this phase owns, so it must be clean). Braces added explicitly; re-run `199 issues found. (ran in 1.5s)` — 0 errors, equal to the baseline, 0 issues in every file this phase touched except the pre-existing `_ChartSeries` note. |
| Final full suite (frozen tree, after `format` and the brace fix) | `01:16 +3208 ~1: All tests passed!` — 0 failures, 0 new skips; the last run before hand-off |
| Assumption-log entries opened this phase | A-1…A-10 (see the plan's Assumption Log) |

---

## §5 Surface-height bumps (Step 9)

One row per bumped test. A bump with no row here is a reviewer finding. **No assertion's meaning may change
in this table** — only the pumped surface height.

| Test file | Test (line) | Old height | New height | Why it fell below the fold |
|---|---|---|---|---|
| — | — | — | — | **No bump was required.** |

**No bump was required.** `gateway.sh test test/screen_widget_test.dart test/header_standardization_test.dart`
passed `00:08 +315: All tests passed!` with both files **unmodified**, so the plan's H-22 prediction did not
hold: the Instruments list did not push any asserted content below a fixed surface height. Every site the
plan named ran and passed as-is — `all-non-strength dataset`, `D-5: Inter-section gaps`, `S-601`…`S-605`,
`Multi-modality`, `S-601/S-603 … positioned correctly`, and the `S-018` header walk (the D-5 gap test pumps
`Size(400, 1400)` and still finds its content). The likely reason is that the two suites scroll to their
targets or assert on widgets already above the fold, and the list only renders when the seeded window has
work of the harness's kinds.

Also confirm: no assertion was weakened (`findsOneWidget` → `findsWidgets`), and no test was deleted or
skipped. `gateway.sh git-diff -- test/screen_widget_test.dart test/header_standardization_test.dart` should
show only `setSurfaceSize` height arguments plus this PR's guard in the third file.

Both files are byte-identical to `develop` — `git-diff --stat` lists neither, so the diff shows **no**
`setSurfaceSize` changes at all. The only weakened assertions in this phase are in the **new** file
(`S-1014`'s day-label `findsWidgets`, A-6), which the plan does not cover; no existing assertion was
weakened, and no test was deleted or skipped.

---

## §6 Doc updates (checked off as done)

| Doc | Claim added | Test named in the plan's table |
|---|---|---|
| `docs/stats_screen.md` | New `### Instruments list` subsection: the list is the window's work, ranked biggest block first (tiebreak = the enum's order); sections are data-driven, absent when empty, and the whole list is absent when the window has no work; the first header carries the shared window chip; the row's parts and their join order; the change chip's no-change dash and raw-sign arrow; the per-section cap and its control; the trend line's ≥2-point rule; a row is an entry point to Exercise Progress. Plus: the windowed/not-windowed table gains the Instruments row, the Overview no longer claims the screen has no interactive controls, the window-label section names `StatsWindowChip`, `kInstrumentRowCap` joins the Key Constants table, and the Core Files table gains the four widgets and the `instrument_list.dart` models file. | S-1001, S-1011, S-1012, S-1014, S-1015, S-1016, S-1017; `test/instrument_list_service_test.dart` S-1006, S-1018 |
| `docs/widget_catalog.md` | A "Note on the Stats screen's Instruments widgets" bullet under Overview naming the four files and what each widget is responsible for, and pointing at `stats_screen.md` for behaviour. | S-1001, S-1016, S-1017 (via the pointer to `stats_screen.md`) |
| `docs/navigation_and_screens.md` | The `ExerciseProgressScreen` row no longer says "reached only from a `RecordsAndTrendsScreen` entry" — it now names both entry points; the `StatsScreen` row gains the Instruments list. | S-1014 + the entry-point guard in `test/records_and_trends_screen_test.dart` |
| `docs/design_system.md` | The Stats row of the canonical-header inventory gains the four title-case Instruments headers, notes the legacy headers stay uppercase, and names the test. | S-1001, S-1011, S-1015 |
| `docs/records_and_trends.md` **(not in Predicted Files — see A-9)** | "Exercise Progress has no single-entry rule" → two named entry points, and the flow diagram gains the Instruments row. | S-1014 + the entry-point guard |

Also confirm: no file in `docs/` outside `docs/plans/` exceeds 64 KiB
(`test/docs_indexing_contract_test.dart` green).

`test/docs_indexing_contract_test.dart` is green in the §4 combined run (`+142`, which includes it), so no
file in `docs/` outside `docs/plans/` exceeds 64 KiB. `docs/stats_screen.md` grew 86 lines and remains well
under the ceiling.

---

## §7 Deviations from the plan

Anything done that the plan did not say, and anything the plan said that was not done. The reviewer reads
this list first; an empty list after a phase that touched nine test sites is itself suspicious.

| Step | Deviation | Why |
|---|---|---|
| 4 (widgets) | `StatsWindowChip` / `InstrumentList` take `themeColors` instead of reading `OmniTheme.colors.textMuted`. | A-1: the deleted chip read the active theme's colours; a parameter keeps the rendering identical and matches `StatsPill`. |
| 4 (widgets) | The expand control is a `TextButton`, not the `OutlinedButton.icon` the design-system table lists for an inline compact action. | A-4: D-507 says "a text control"; `shape` is set explicitly per the button rule. Flagged for the reviewer as the one place the plan and the button table disagree. |
| 6 (screen) | The Instruments block is conditional on `window != null && _instrumentSections.isNotEmpty`. | A-3: S-1012's "legacy renders exactly as today" would otherwise be falsified by a stray 24dp gap. |
| 7 (test) | S-1012's fixture is two completed sessions 35/40 days back with no efforts. | A-5: with any completed session, `resolveWindow` always returns a 14-training-day window, so this is the reachable form of "nothing in the window". |
| 7 (test) | S-1014's day-label assertions are `findsWidgets`, not `findsOneWidget`. | A-6: the pushed screen shows the same day label in the chart axis and in the history row. |
| 9 (bumps) | **No surface-height bump was needed**; both legacy suites pass unmodified. | H-22's prediction did not hold — see §5. No assertion in either file changed. |
| 10 (docs) | The new prose names constants and tests rather than restating the cap's value and the row's literal strings. | A-8: `docs/documentation_standard.md` §3.4/§3.5 forbid restating values and copied content, and it governs `docs/`. |
| 10 (docs) | `docs/records_and_trends.md` was edited, and it is not in Predicted Files. | A-9: Step 6 falsified its "no single-entry rule for Exercise Progress" sentence. |
| 4 (widgets) | The stale `// ── Section label ──` divider was relabelled `// ── All-time aggregate ──`. | A-10: it headed the deleted `_buildWindowChip`. Comment only. |
| 0 (baseline) | Lint was already 199 issues at baseline, not 0. | Pre-existing. `stats_screen.dart`'s one issue (`_ChartSeries` unused, line 2126) is inside that baseline and outside this phase's diff; fixing it would be unrelated pre-existing work, which the brief forbids. |
| 10 (format) | `gateway.sh format` was run on the seven touched Dart files, and it reflowed one `if` in `instrument_list.dart` into a form the analyzer flags. | The brief requires formatting the files this phase created or changed. The reflow was corrected by adding braces rather than by leaving a new issue in an owned file; lint returned to the baseline 199. |
| — | `.claude/commands/feature.md` shows as modified in `git-status`. | **Not this phase.** It was already modified in the shared working tree before Phase 0 and this phase never wrote to `.claude/`. It appears in no diff this phase produced. |

Nothing the plan said was left undone. The two items the plan flagged as open — Q7's control styling and the
"H-22 bumps" prediction — are resolved above; no remediation item is opened.

---

## §8 Reviewer findings

Filled by `@code-reviewer` against the plan's checklist. Quantify every defect: count, examples, and the
root-cause line. Each defect that becomes a remediation phase must carry a structural guard.

**Findings, the Predicted-Files audit and the structural-guard audit live in
`2026-10-01-04b2-stats-pr4b2-instruments-list-plan.review.md`** (same folder) — verdict
`APPROVE`, six findings, none blocking. Not duplicated here.

| # | Severity | Finding | Count / examples | Root cause | Disposition |
|---|---|---|---|---|---|
| 1–6 | see review file | | | | non-blocking; fix in one pass |

**Predicted-Files audit:**

| Out-of-bounds files touched | Predicted files untouched |
|---|---|
| `docs/records_and_trends.md` (declared, A-9); `.claude/commands/feature.md` (not this phase) | `lib/features/stats/widgets/native_value_format.dart` ✓, `test/db_seed_test.dart` ✓, `test/screen_widget_test.dart` ✓, `test/header_standardization_test.dart` ✓ |

Pay particular attention to: `lib/features/stats/widgets/native_value_format.dart` (must be untouched — its
changes belong to 4b) and `test/db_seed_test.dart` (must be unmodified).

**Structural-guard audit:** Step 8's guard asserts exact list equality over the files constructing
`ExerciseProgressScreen`. Confirm it fails when a third constructor is introduced, and record the mutation
output here.

The mutation was **not run** by the review phase (review finding 5). The reviewer verified by reading that the
assertion is exact list equality over a `lib/` scan, so a third construction site cannot pass. The **polish
pass ran it** — see below.

### Polish pass — structural-guard mutation (review finding 5)

Tracked-file mutation on `lib/features/stats/stats_screen.dart`: added a comment containing the literal
`ExerciseProgressScreen(`, then ran `gateway.sh test test/records_and_trends_screen_test.dart`:

```
00:01 +13 -1: only Records & Trends and the Instruments list construct ExerciseProgressScreen [E]
  Expected: [
              'lib/features/stats/records_and_trends_screen.dart',
              'lib/features/stats/widgets/instrument_list.dart'
            ]
    Actual: [
              'lib/features/stats/records_and_trends_screen.dart',
              'lib/features/stats/stats_screen.dart',
              'lib/features/stats/widgets/instrument_list.dart'
            ]
  test/records_and_trends_screen_test.dart 676:5      main.<fn>
00:01 +13 -1: Some tests failed.
```

The guard **FAILS** as designed; the failing line is `test/records_and_trends_screen_test.dart:676:5`. The
inverse edit was applied immediately. `gateway.sh git-diff -- lib/features/stats/stats_screen.dart` returns
the pre-mutation diff (`index 8a36d09..6dfc1dd`, 47 insertions / 38 deletions — the hash and stat noted
before the mutation), and the same test then reports `00:01 +14: All tests passed!`.

---

## §9 Scenario conformance

One row per scenario this plan owns, with the test that covers it and the fixture-population check. A
scenario whose fixture was not populated as stated is a defect, not a passing test. S-1002…S-1010, S-1013
and S-1018 are 4b's; S-1101…S-1110 are 4b3's.

| Scenario | Test | Fixture as specified? | Result |
|---|---|---|---|
| S-1001 | `test/instrument_list_screen_test.dart` → `S-1001` (6 tests × 2 harnesses: section order, row order with the duplicate name and the untrained-in-window exercise absent, the figure against the service's own value for the same window, the secondary line's parts, the change chip vs the previous range) | **Yes**, plus one addition the plan did not state: `ex-squat` also has sessions 20 and 40 days back. The 20-day session is the previous equal-length range (so the change chip has something to compare against) and the 40-day one is the "older than the window" history S-1014 needs. Days 5–14 are empty completed sessions that pin the 14-training-day window so days 20 and 40 fall outside it. | PASS ×6 (Mock + Hive) |
| S-1011 | same file → `S-1011` | **Yes** — an active qualifying training period plus training inside and outside it. | PASS ×2 |
| S-1012 | same file → `S-1012` | **Partly** — two completed sessions 35 and 40 days back, but they carry **no efforts** (A-5): with any completed session `resolveWindow` always returns a window, so this is the only reachable form of "nothing in the window". The scenario's assertions (no section, no control, no row, legacy intact, nothing throws) all hold. | PASS ×2 |
| S-1014 | same file → `S-1014` | **Yes** — the tapped exercise has history 20 and 40 days back and one session inside the window, and the test also taps a second row to prove the push carries that row's exercise. Day labels are asserted with `findsWidgets` (A-6). | PASS ×2 |
| S-1015 | same file → `S-1015` (the Instruments list sits above the untouched legacy sections) **and** `test/screen_widget_test.dart` + `test/header_standardization_test.dart` + `test/stats_progress_test.dart` run **unmodified** | **Yes** — and stronger than specified: the plan allowed surface-height bumps, and none were needed (§5). Every legacy assertion (`STRENGTH`, `CARDIO`, `ISOMETRIC`, `SPORTS`, `NUTRITION`, `ALL TIME`, the chip, the 24dp gaps, the legacy axes and empty states) passed as-is. | PASS |
| S-1016 | same file → `S-1016` (5 / 6 / 8 rows, expand and collapse, per section) | **Yes** — the three populations are separate sections in one fixture, so the "per section, not per list" clause is exercised rather than assumed. Mutation M5 proves the test fails when the cap changes. | PASS ×2 |
| S-1017 | same file → `S-1017` (3 points / exactly 1 / the zero-valued row with no readable points) | **Yes** — visibility is asserted by the rendered size (`Size(56, 24)` vs `Size.zero`), so "takes no space" is what is actually checked, not merely "absent". Mutation M6 proves it fails when the guard changes. | PASS ×2 |

---

## Polish pass (post-review, 2026-10-01)

Review verdict `APPROVE`, five non-blocking items. Fixes only, no behaviour change:

| Item | Finding | Change | Observed check |
|---|---|---|---|
| P-1 | 1 | None — kept `themeColors.textMuted`; recorded as A-11 in the plan. | `docs/global_conventions.md` (theme tokens only); code unchanged. |
| P-2 | 2 | D-507 parenthetical corrected to "local UI state, which survives a reload"; recorded as A-12. | Plan text matches the code; code unchanged. |
| P-3 | 3 | `window_chip.dart` comment: "the five legacy headers" → "the four legacy headers". | `gateway.sh test test/instrument_list_screen_test.dart` green. |
| P-4 | 5 | Guard mutation run (see §8) and restored. | Fails at `test/records_and_trends_screen_test.dart:676:5`; diff back to `8a36d09..6dfc1dd`; then `+14: All tests passed!`. |
| P-5 | 6 | `docs/README.md` Stats Screen row now names the Instruments list above the legacy sections. | `gateway.sh test test/docs_indexing_contract_test.dart` green. |
