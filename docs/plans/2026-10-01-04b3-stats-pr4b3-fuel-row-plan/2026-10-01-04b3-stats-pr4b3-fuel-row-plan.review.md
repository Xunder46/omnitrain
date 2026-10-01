# Review — Stats PR 4b3 (the nutrition-card extraction and the Fuel row)

Reviewer: Code Reviewer agent · Base: `HEAD` on `develop` (whole change uncommitted)
Plan: `2026-10-01-04b3-stats-pr4b3-fuel-row-plan.md` · Evidence: `2026-10-01-04b3-stats-pr4b3-fuel-row-plan.evidence.md`

## Verdict

**CHANGES_REQUESTED** — 2 blockers, 2 majors, 4 minors, 3 nits.
The code is correct against every Fuel rule the owner confirmed. What blocks is a
**scenario the plan itself required and nobody wrote** (S-1110(b)), the **false doc
pointer and false evidence claim built on it**, and **three false code comments**
that contradict the service and the docs. All six in-PR fixes are small.

## Gate results (re-run in this session)

| Command | Final line (verbatim) |
|---|---|
| `gateway.sh lint` | `199 issues found. (ran in 2.6s)` — 0 lines matching `error •` |
| `gateway.sh test` | `01:15 +3254 ~1: All tests passed!` |

Both match the bar (0 errors, ≤199 issues, green) and the last known `+3254 ~1`.
No new warning was introduced: the total is unchanged from the pre-change baseline, which is
also the proof that the `_ChartSeries` warning in `stats_screen.dart` is pre-existing.

## Layers in scope

`core/services`, `core/models`, `features/stats`, `features/nutrition`, `widgets/chart`, `test/`, `docs/`.
No repository, no `lib/state/`, no `lib/data/models/` change — those checklist sections are skipped.

---

## Findings

### 1. blocker — S-1110(b) has no test anywhere
`test/fuel_row_screen_test.dart`, `test/nutrition_trend_screen_test.dart`, plan `:634`
The plan's Doc-claim → test table requires the claim "the row is hidden when the last 14 days
have no logs, **and the zero-session empty state wins**" to be proved by `S-1107, S-1110(b)`, and
states its own rule: *a claim with no test does not ship*. `S-1110(b)` does not exist — a repo-wide
search finds `S-1110` only as `S-1110(a)` in `test/nutrition_trend_screen_test.dart:200`. D-525's
precedence rule (the empty state wins over the Fuel row) is therefore implemented but unverified.
Fix: add an `S-1110(b)` group to `test/nutrition_trend_screen_test.dart` (the file the plan maps
S-1110 to, plan `:644`) seeding food today and no session, asserting the empty state renders and
`Key('fuel_section')` is absent. → @developer

### 2. blocker — the doc points at a test that does not exist
`docs/stats_screen.md:152`
"Verified by the same file (`S-1107`, `S-1110(b)`)" — "the same file" is `test/fuel_row_screen_test.dart`
(established at `:145`), which contains no `S-1110` of any kind; and the plan maps `S-1110` to
`test/nutrition_trend_screen_test.dart`, so the pointer is wrong twice. The behaviour itself is
correct (`stats_screen.dart:155` branches on `_totalSessions == 0` before the Fuel gate at `:174`).
Fix: finding 1 makes the claim true; correct the file name to the file that holds it. → @developer

### 3. major — the evidence claims an assertion that was never written
`2026-10-01-04b3-stats-pr4b3-fuel-row-plan.evidence.md:351`
"The screen's zero-session empty state wins and no Fuel row renders at all (D-525), which is asserted
deliberately by S-1110(b)." Nothing asserts it. The evidence file is the proof-of-work artifact, so a
claim of a verification that was not performed is the failure mode the working rules call out by name.
Same root cause as finding 1. Fix: write the test, then re-record the sentence with the observed run. → @developer

### 4. major — three comments claim a window the code does not use
`lib/features/nutrition/nutrition_trend_screen.dart:11`–`:14`, `lib/features/nutrition/nutrition_trend_screen.dart:44`–`:45`,
`lib/features/nutrition/widgets/nutrition_trend_card.dart:21`–`:26`
All three say the Stats NUTRITION card renders the service's soft window (`kNutritionTrendDays`) and that
the two hosts differ in the window they pass. They do not: `stats_progress_service.dart:588` passes
`days: null` from `computeProgressData()`, exactly as the trend screen does at `nutrition_trend_screen.dart:47`.
Both hosts are full history — which is what `docs/stats_screen.md:421`, `:585` and `:626` correctly say, so the
source now contradicts the docs. No behaviour depends on it; a reader does. Fix: delete the window claim
from all three sites (the doc already carries the truth), or point at the parity test. → @developer

### 5. minor — D-533 is not literally met: two of the three primitives still have private copies
`lib/features/stats/exercise_progress_screen.dart:47`, `:317`
D-533 says "no copy of any of the three may remain in `lib/`". `:47` re-declares the bottom-axis reserved
size (the same value as `kChartBottomAxisReservedSize`) and `:317` re-implements the single-point card,
including its chrome and its string. Verdict on the three options the brief asks for: a **real DRY
violation**, **pre-existing and outside the Predicted Files** (absent from `git-diff`, so the move did not
create it), and **disclosed rather than absorbed** — evidence §2.4 and A-5 name it, and A-5 records the
judgement that Rule 5's bar is "none new". That judgement is right, but the decision's absolute wording is
now false. Fix: one-line swap of the constant for the shared one (no scope growth). The card is a divergent
variant — it renders the label and date in one line where the shared one takes label and value — so amend
D-533 to name that exception instead of forcing a signature change. → @developer

### 6. minor — the nutrition → stats import makes the dependency two-way
`lib/features/nutrition/widgets/nutrition_trend_card.dart:10`
The moved card imports `../../stats/widgets/scrollable_trend_chart.dart`, so `nutrition → stats` exists until
4c removes the Stats host; D-532 wanted the direction one way. Disclosed in A-1, and the Predicted Files do
not list that move, so leaving it is defensible — but D-533's own reasoning (a file shared across features
belongs under `lib/widgets/chart/`) applies verbatim to `scrollable_trend_chart.dart`. Fix: move it to
`lib/widgets/chart/` in 4c. → @developer (4c)

### 7. minor — nothing renders the Fuel row at a narrow width or a large text scale
`test/fuel_row_screen_test.dart:34`, `test/screen_overflow_contract_test.dart:166`
The fuel test's only viewport is a normal phone width, and the overflow contract test does render
`StatsScreen` at three phone sizes — but it seeds no food, so `FuelSection` never enters the tree there and
its overflow is untested. The brief asks "is there a test?" — the answer is no. Fix: add a narrow-width and
a scaled-text case inside the new `test/fuel_row_screen_test.dart` (do not touch the shared contract file,
which this PR leaves unmodified). → @developer

### 8. minor — the new derived value type is absent from the models reference
`docs/data_models.md:591`–`:595`
The code-reference table lists the other derived value-type files (`session_summary.dart`,
`routine_session_manifest.dart`, `exercise_metric.dart`, `instrument_list.dart`) and the doc has a dedicated
section for the Instruments value types, but nothing names `lib/core/models/fuel_summary.dart`. Incomplete,
not false. Fix: add the row (and, if the section pattern holds, a sentence pointing at its test). → @developer

### 9. nit — the no-chip assertion is weaker than the rule it proves
`test/fuel_row_screen_test.dart:740`
It asserts a chip count of five, not the absence of a chip inside the Fuel section (A-7), so a sixth chip
elsewhere would still pass. Fix: also assert no `StatsWindowChip` is a descendant of the Fuel section. → @developer

### 10. nit — M4's mutation cites the wrong scenario
evidence, mutation table row M4 (A-8)
The mutation is recorded as failing S-1107(b); it actually fails S-1107(a). Fix: correct the citation. → @developer

### 11. nit — the tappable row carries no explicit accessibility label
`lib/features/stats/widgets/fuel_section.dart:86`–`:87`
`InkWell` supplies the tap action and the row's text children are read, so a screen reader does announce the
row; no explicit label and no assertion of one. Fix: optional — add a label and assert it. → @developer

---

## The seven checks

1. **The move is faithful — checked, fine.** Spot-checked four regions of `nutrition_trend_card.dart`
   against the removed code (the legend builder, the single-point card, the reserved-size constant, and the
   macro target-series painter) plus the nutrition toggle, the calories chart, the macros chart, the empty
   chart and the empty-section gate: byte-identical, no numeric, string, key, colour or condition changed.
   The two intended renames (the primitives now called by their shared names, and the size constant) are the
   only differences and the plan names both. The old NUTRITION section renders through the new card with the
   same inputs (`stats_screen.dart:910` onward). The one defect the check surfaced is finding 4, and it is a
   comment, not a figure.
2. **Fuel rules — checked, fine.** Judged each owner-confirmed rule against the code *and* its test: the
   window and the previous range are calendar arithmetic on `DateTime` (DST-safe), a logged day is a day with
   a food row, the averages divide by the group's own length and are null when it is empty, a training day
   requires a finished session, the target is today's and compared only when above zero, the previous range
   is the fallback, the header is exactly `Fuel` with no chip, the tap goes through `OmniNavigator.push` with
   no raw route, and the row is gated so the empty state wins. The tests assert the rendered strings as well
   as the value type, so a wrong figure cannot pass on one side only. Finding 1 is the one rule with no test.
3. **The tests bite — checked, fine, with finding 1.** S-1101…S-1109 and S-1111…S-1112 each have a test that
   fails if the behaviour is wrong; the assertions are exact values and exact rendered strings, with
   `findsNothing` where absence is the claim, and I found no vacuous pass (no `findsWidgets`, no empty finder,
   no loop over nothing). Seeding and every model read happen in `setUp`, never in a body, so the file cannot
   hit the `FakeAsync` hang the implementer diagnosed. Spot-checked M1 and M3 by reading the assertion each
   cites: M1's `const []` trend fails the parity test's figure assertion, and M3's divisor change fails
   S-1101's average. I could not re-run a mutation myself — this review may not write to `lib/` — so M2, M4
   and M5 rest on the recorded runs.
4. **Architecture and design — checked, fine, with findings 5 and 6.** The three primitives each have one
   declaration in `chart_primitives.dart` and every other occurrence is a reader in one of the two intended
   hosts (re-run with a text search, which this checkout does support — the executor's A-11 note that no
   search primitive existed does not hold here, and the search confirms the residue the evidence already
   reported). Colours come from theme tokens only, card chrome routes through `OmniSurface` and
   `OmniCardHeader`, no hex literal, no `Exercise Details` naming, no raw route constructor, no button added
   (so the button checklist is N/A), and the row's units follow the nutrition precedent — kcal and grams are
   canonical with no saved preference, so rule 1 holds.
5. **Legacy and scope — checked, fine.** `git-status` lists no existing test file, and the PR-toast tests,
   `watch/` and `scripts/sqlite_*` are untouched. `stats_screen.dart` changed only where the plan says (the
   imports, the load, the render block, six call-site renames, the move, and three removals), with no
   formatter churn elsewhere. All five legacy sections remain inside the legacy column, and the unused
   `_ChartSeries` warning is pre-existing (the lint total is unchanged).
6. **Docs — one blocker, one minor, otherwise fine.** Every behaviour sentence in the added prose names a
   test, and every type, file and constant named exists — checked each by reading the code. Constants are
   named, not restated. No hex, line number, hash, walkthrough, roadmap or unshipped-change phrase. The stats
   doc describes the Fuel row and the old NUTRITION section truthfully. Findings 2, 8 and the doc table below.
7. **No scratch or churn — checked, fine.** `git-status` shows only the plan folder, the six new source/test
   files and the four doc edits; no probe, scratch or placeholder file, and no `TODO`/`FIXME` in the new files.

---

## Doc falsification (run on the code, not the summary)

Implicated set derived from the changed files: `stats_screen.md`, `widget_catalog.md`,
`navigation_and_screens.md`, `data_models.md`, `README.md`, `constants_reference.md`, `design_system.md`,
`navigation_contract.md`, `state_management/*`, `db_integration.md`.

| Doc | Result |
|---|---|
| `docs/stats_screen.md` | ❌ **REJECT** — `:152` — names `S-1110(b)` as verified by `test/fuel_row_screen_test.dart`; no such test exists in any file → finding 1, then correct the file name (finding 2) |
| `docs/widget_catalog.md` | ✅ PASS — both new notes name real types and files and point at real tests |
| `docs/navigation_and_screens.md` | ✅ PASS — the new screen's row and its entry point are both true |
| `docs/README.md` | ✅ PASS — the index already describes the Stats NUTRITION card as full history, which the code still is |
| `docs/data_models.md` | 🟡 WARNING — incomplete: the new derived value type is unnamed (finding 8) |
| `docs/constants_reference.md` | ✅ PASS — its declared scope is `lib/core/constants/`; the two new constants live in the service, out of scope |
| `docs/navigation_contract.md` | ✅ PASS — a rule doc with no route inventory; the change complies and its enforcement test is green |
| `docs/design_system.md` | ✅ PASS — no theme value, token or visual rule added |
| `docs/state_management/*` | ✅ PASS — no `ChangeNotifier` added or changed; the new screen holds local state only, so the index is not made false |
| `docs/db_integration.md` | ✅ PASS — nothing new is persisted; the schema and seed SQL are untouched |

No conflict found between two docs on the same area.

## Documentation standard

`DOC STANDARD: ✅ PASS — no prohibited content added.` The added prose carries rules and test pointers, not
step-by-step flows, visual values, control inventories, restated numerics, copied code, roadmap or
unshipped-change notes.

## Global conventions

- **PASS (6 rules):** units + canonical storage (kcal and grams are canonical with no saved preference, so
  the row follows the existing nutrition precedent rather than duplicating conversion math); theme tokens
  only; card chrome via `OmniSurface` and `OmniCardHeader`; effort-kind drives analytics (the training-day
  split keys off persisted completion, not a session or modality label, and no classification was added);
  timestamps are source data (the window is calendar arithmetic and the split reads persisted start and end
  times); instrument panel, not influencer (figures and a split only — no recommendation, no new target, no
  time-range selector, per D-527).
- **PASS with a recorded divergence (1 rule):** reuse the canonical owner — `computeFuelSummary` lives in the
  existing `StatsProgressService` and reuses `computeNutritionTrend` for the per-day rule (D-531). The row
  formats its own whole-unit, dash and arrow strings instead of calling `formatNativeChange`, which is
  metric-keyed and has no kcal or gram metric; the plan decided this (D-529) and `docs/stats_screen.md`
  records the reason and the precedent. Not a FAIL.
- **N/A (0 rules):** none — all seven were applicable and checked.

## Test gaps

- `test/nutrition_trend_screen_test.dart` — 🧪 MISSING: S-1110(b), the zero-session empty state winning over
  the Fuel row (finding 1). Blocking: the plan requires it and a doc claims it.
- `test/fuel_row_screen_test.dart` — 🧪 MISSING: any narrow-width or large-text-scale render of the Fuel row
  (finding 7).
- No stale test: no test file was modified, and no test references a removed or renamed member.

## Scope budget

Eight substantive findings is a split signal, so the round is bounded deliberately.

**Fix in this PR (one round, all small):** findings 1, 2, 3, 4, 5 (the one-line swap and the D-533 wording),
9 and 10.
**Defer to 4c:** findings 6 (move `scrollable_trend_chart.dart`), 7 (narrow-width and scaled-text coverage),
8 (the models-reference row) and 11 (the accessibility label). None of the four changes behaviour and none is
a blocker, so none should be absorbed into this round.
