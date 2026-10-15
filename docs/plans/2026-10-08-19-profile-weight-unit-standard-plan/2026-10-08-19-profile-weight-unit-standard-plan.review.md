# Code Review — Profile weight quick chart honours the weight-unit preference

Plan: `docs/plans/2026-10-08-19-profile-weight-unit-standard-plan/2026-10-08-19-profile-weight-unit-standard-plan.md`
Layers in scope: state (read), features (`lib/features/profile/`), components (`lib/widgets/` read), docs, tests
Layers skipped: models, persistence, core (no changes)

Started: 2026-10-08 — findings appended as they are found.

---

## Review Process Results

### Step 2 — Diff vs Predicted Files

Conforms. Every predicted file was touched; one extra tracked test was edited
(`test/header_standardization_test.dart`), which is **justified** — its five
y-axis label assertions pinned the old `toStringAsFixed(1)` format that D-3
deliberately changed. The edit is format-string only (no logic change), and the
tests still assert the same *intent* (label count, position, `minV == maxV`).
`measurement_history_chart_sheet.dart` was the plan's read-only reference and was
**not** touched. No unfinished predicted file.

### 4c — Test run verification (blocking)

- Implementer's handoff pasted **actual counts**: yes (`4226 passed, 1 skipped`).
- Independently re-run: `.github/copilot/scripts/macos/gateway.sh test` →
  **4226 passed, 1 skipped, 0 failed** (2 min 11 s). Reproduced.
- Bug-fix mutation check: `prove-red HEAD test` ran the new test file against the
  unfixed source and went **RED** — S-1 `Expected '198.4'`, `Actual '90.0'` (raw
  kg), an assertion failure, not a compile error. Proven.
- Handoff Docs section: present, names each implicated doc as updated.

### 4a — Acceptance criteria

All met. AC1/AC2/AC4 verified by passing tests (S-1, S-2, S-4). AC3 (line range
scales) holds by construction — the painter's `maxV`/`minV`/`range` and both
`yForValue` call sites now read the converted `values` list. AC5 (guard fails on
a raw-weight chart) is satisfied by the S-1 assertion, which is the regression
guard for the exact defect; proven to fail without the fix.

> Note: AC5's literal wording ("the guard fails when a chart plots a raw
> `unit-kg` value") is met by S-1 acting as that guard. The plan's S-3 proposed a
> separate scratch-probe test; the implementer folded the guard into S-1 instead
> of adding a probe file. This is acceptable — the guard exists and was shown red
> on the raw-weight code — but it is a deviation from S-3's fixture wording. See
> WARNING-2.

### 4b — Scenario register cross-check

| Scenario | Test | Fixture conformant | Passes |
|---|---|---|---|
| S-1 (lbs labels) | `S-1: bodyweight sparkline labels in pounds under lbs` | ✅ 80 kg + 90 kg | ✅ |
| S-2 (kg unchanged) | `S-2: bodyweight sparkline labels in kg under kg` | ✅ | ✅ |
| S-4 (non-weight) | `S-4: non-weight measurement ignores the weight preference` | ✅ `unit-pct` | ✅ |
| S-3 (guard probe) | — | folded into S-1 | — see WARNING-2 |

`S-2`'s stated Expected Outcome says the kg labels are `90.0` / `80.0` — *"byte-
identical to today's output."* The implemented test asserts `90` / `80`, because
D-3 changed the format. **The scenario text was not updated** to match. See
WARNING-1.

### 4g — Impact Check conformance

- Re-ran the plan's greps. All named readers exist: `profile_cleanup_test.dart`,
  `profile_screen_test.dart`, `header_standardization_test.dart`, and
  `measurement_history_chart_sheet.dart` / `profile_screen.dart` for the shared
  helpers.
- Grepped the touched surface myself for unlisted readers of the sparkline keys
  (`measurement_sparkline*`): only the four known files plus the widget itself.
  **No unlisted reader.** ✅

### Architecture compliance

- **features:** `MeasurementSparkline` still takes `settingsState` via
  constructor (unchanged call site); no direct persistence access; the
  conversion is presentation-boundary logic, correctly placed; empty / loading
  states intact. ✅
- **components:** painter is pure presentation; it no longer reaches into
  `BodyMeasurementEntry.value` — the host converts and passes `values`. ✅
- **Environment safety:** `UnitFormatter` is web-safe; no platform imports. ✅
- **Dead code:** `settingsState` is no longer dead — the doc-comment that said
  "No longer used internally" was corrected. ✅

### Test coverage

New public behaviour (unit-aware sparkline scale) covered by S-1/S-2/S-4;
regression guard proven red. Existing assertions updated, none deleted or left
stale. No `testWidgets` FakeAsync hazard: the tests seed via
`MockWorkoutRepository` and use `pumpAndSettle`, no real `Future.delayed`. ✅

### 4f — Conventions verification

```
PASS (1): Units + canonical storage — conversion goes through UnitFormatter; no
duplicated maths; canonical kg persisted; the new chart rule is itself satisfied.
N/A (8): theme tokens, card chrome, effort-kind, timestamps, canonical owner,
instrument panel, no-notify-during-build, rest rule — this change touches none of
those surfaces.
```

### DRY and clean code

`_toChartValue` mirrors `MeasurementHistoryChartSheet._toChartValue`
(duplicate ~4-line branch). Minor: two private helpers with the same name and
shape in two files. Not blocking — extracting a shared `UnitFormatter` entry
point for measurement entries would remove it, but it is presentation-layer
glue and the plan explicitly chose "mirror", not "extract". See SUGGEST-1.

---

## Findings

🟡 WARNING | docs/plans/.../2026-10-08-19-profile-weight-unit-standard-plan.md:102 (S-2) | S-2's Expected Outcome still says the kg labels are `90.0`/`80.0`, but the shipped test asserts `90`/`80` (D-3 changed the format) | update S-2's Expected Outcome to the `formatValue` output, or note D-3 supersedes it | @planner
🟡 WARNING | docs/plans/.../2026-10-08-19-profile-weight-unit-standard-plan.md (S-3) | S-3's scratch-probe guard was folded into S-1 rather than implemented as written | record in the plan that S-1 is the S-3 guard, or add the probe | @planner
💡 SUGGEST | lib/features/profile/widgets/measurement_sparkline.dart:162 | `_toChartValue` duplicates `MeasurementHistoryChartSheet._toChartValue` | optionally hoist a shared helper onto `UnitFormatter`/`ProfileMeasurements` | @developer
💡 SUGGEST | lib/features/profile/widgets/measurement_sparkline.dart:104,162 | `[MeasurementHistoryChartSheet]` doc refs don't resolve (class not imported); line 65 uses backticks | switch to backticks for consistency | @developer

### 4d — Documentation falsification

Implicated (no parseable scope declaration → cover everything):
`docs/profile_and_measurements.md`, `docs/global_conventions.md`,
`docs/widget_catalog/feature_primitives.md`, `docs/stats_screen.md`.
Checked each against post-change code:

- `profile_and_measurements.md` — updated correctly; the new bullet states the
  behaviour and points at the test. No false claim found.
- `global_conventions.md` — the extended rule matches the shipped behaviour.
- `feature_primitives.md` — the `MeasurementSparkline` entry describes structure
  only; it is **silent** about the unit behaviour (incomplete, not false).
- `stats_screen.md:572` — `InstrumentSparkline` described as "the row's trend
  line"; still true and unit-free. No false claim.

No conflicts between documents.

```
DOC FALSIFICATION: 🟡 WARNING (0 reject, 1 incomplete) — docs/widget_catalog/feature_primitives.md — incomplete: the MeasurementSparkline entry doesn't mention the unit-aware scale (says nothing false)
DOC FALSIFICATION: ✅ PASS — docs/profile_and_measurements.md, docs/global_conventions.md, docs/stats_screen.md
```

### 4e — Documentation standard enforcement

Added prose: the convention rule (a rule statement — permitted) and the profile
bullet (behaviour + test pointer — the required form). No prohibited class: no
step-by-step flow, no visual values, no control inventory, no restated source
numeric, no copied code, no roadmap, no unshipped-change note.

```
DOC STANDARD: ✅ PASS — no prohibited content added
```

### Assumption Log adjudication

- **A-1** (format `.0` drop) — **RATIFY.** Consistent with D-3; the consequence
  is real (five test assertions changed) and correctly logged. Recommend
  promoting to a numbered decision (binds the header tests).
- **A-2** (`body_fat_pct` type) — **RATIFY.** Factual, corrected pre-
  implementation.

---

Critical: 0 | Warnings: 2 | Suggestions: 2

→ @planner: two plan-text-only warnings (S-2 Expected Outcome; S-3 guard wording). No code change required.

---
⏸️ **PIPELINE PAUSED** — no blockers found.
Approve as-is, or send the two plan-text warnings back for a fix?

---

## Fix Round 1 — 2026-10-09

Addressed all four findings. No code behaviour changed (the only `lib/` edit is a
doc comment); the rest is plan text and one widget-catalog sentence.

| Finding | Fix |
|---|---|
| 🟡 W1 — S-2 Expected Outcome stale | Updated S-2 to `90` / `80` and noted D-3 supersedes the old `.0` form. |
| 🟡 W2 — S-3 guard folded into S-1 | Added an implementation note to S-3 recording that S-1 is the guard, with the `prove-red` evidence. |
| 💡 SUGGEST — unresolved `[MeasurementHistoryChartSheet]` doc refs | Switched the two bracket refs to backticks in `measurement_sparkline.dart`. |
| 🟡 DOC FALSIFICATION — `feature_primitives.md` incomplete | Added a short unit-scale sentence to the `MeasurementSparkline` entry, linking `profile_and_measurements.md`. |

Also corrected the S-4 fixture type in the plan (`bodyfat` → `body_fat_pct`),
which still read the pre-implementation value.

**SUGGEST-1 (duplicate `_toChartValue`) — deferred, not changed.** The plan's D-1
deliberately chose "mirror the sheet" over "extract a shared helper"; the pair is
presentation-layer glue and the doc comment names the mirror. Not worth a new
`UnitFormatter` API for two four-line branches.

### Re-verification after the fix

- `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`
  → **9 passed** (new relative link resolves; size contract holds).
- `.github/copilot/scripts/macos/gateway.sh test test/profile_measurement_sparkline_unit_test.dart test/header_standardization_test.dart test/profile_screen_test.dart`
  → **85 passed**.
- `.github/copilot/scripts/macos/gateway.sh lint` → **196 issues**, unchanged from
  baseline; none in a changed file.

All findings resolved. No open critical or warning items.


