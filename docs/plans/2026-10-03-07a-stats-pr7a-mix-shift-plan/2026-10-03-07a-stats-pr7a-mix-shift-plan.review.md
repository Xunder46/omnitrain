# Review — Modality Mix Shift (Stats PR 7a, pack item 10)

> Plan: `2026-10-03-07a-stats-pr7a-mix-shift-plan.md` · Evidence: `2026-10-03-07a-stats-pr7a-mix-shift-plan.evidence.md`
> Base `638fdf6`, branch `develop`, work uncommitted. Read-only review: no product code, test or reference-doc edit was made.

**Layers in scope:** core/models (new rule), core/services (signal, service extraction, registry), test, docs.
**Layers skipped:** data (models/repositories), state, features, widgets — no diff (`git-status` confirms the file list in the brief).

**Observed runs (not inferred).** `gateway.sh test test/modality_mix_shift_test.dart test/modality_mix_period_service_test.dart test/modality_mix_shift_signal_screen_test.dart test/mix_layer_service_test.dart test/mix_layer_screen_test.dart test/docs_indexing_contract_test.dart` → `+139: All tests passed!`. Baselines not re-run (governor: `flutter analyze` 196 issues; full suite `+3582 ~1`).

**What is right.** The rule is a faithful transcription of pack item 10: the `10 ×`-cross-multiplied regularly-trained floor (inclusive), the `2 ×`-cross-multiplied fire test (strict — exactly half abstains), load-measure-only, largest-relative-drop with declaration-order tie-break, the second sentence omitted when the reported modality is the largest recent one, caution kind, priority 400. I re-derived every fixture by hand (S-1901/1902/1903/1905/1906/1908/1910/1911 and the F-MIX/F-TIME service fixtures): all arithmetic and all percents check out. The copy is character-for-character the pack's wording, and the nouns/articles are right. The service extraction is behaviour-preserving (declarations and the loop move; `_sessionInWindow` gains explicit bounds), one walk, one payload; the signal is one class plus one registry line with no framework diff and no repository read of its own (`_loadHistory` is memoised, so one screen evaluation is one read). Scenario coverage is complete (S-1901…S-1913), the boundary tests are real (mutation (a) reddens S-1902/S-1908), and Phase 3's guards redden under the recorded mutations. Everything below is documentation and test-hygiene; no behavioural defect was found.

---

## Findings

**1. `docs/signals.md:62-68` — blocker — the caution order is written as shipped, not as planned.** The paragraph lists six cautions and then asserts, in the present tense, "Each signal's own priority constant carries its place in that order" (line 64-65). Two cautions exist as classes today (one caution, `modality-mix-shift`; `progression-rate` is a positive), so five of the six priority constants the sentence asserts do not exist. A reader of a reference doc cannot tell what ships from what is planned: `documentation_standard.md` §3.6 ("Documentation describes **what exists**") and the doc-falsification rule (a false claim about the current product is rejection-class, not a warning). The brief permits recording the order only "as PLAN ... not as shipped", and the second sentence is the shipped-voice part. **Fix:** keep the structural invariant and drop the shipped-voice enumeration — e.g. the order the pack fixes is carried by each signal's own priority constant rather than by the selection rule — and leave the six-name list in the plan. → @developer

**2. `docs/stats_screen.md:163` — major — a numeric value defined in source is restated in prose.** "over the last 28 days" restates `kModalityMixShiftPeriodDays`; the constant is already named elsewhere in the same doc set, and a copied number is a second source of truth that no test guards (`documentation_standard.md` §3.4). **Fix:** name the constant (or drop the span from that clause and let the Signals pointer carry it). → @developer

**3. `docs/signals.md:215` — minor — a derived duration is restated next to the constant that produces it.** "the `kTrainingLoadBaselineWeeks` consecutive 7-calendar-day blocks that tile the 84 days immediately before the period's start day" names the constant and then restates its product; if the constant changes the prose goes false silently (§3.4). **Fix:** delete "the 84 days" (the named constant and the block count already say it). → @developer

**4. `docs/signals.md:241-243` — minor — the Mix Shift Copy bullet omits the suggestion.** `docs/stats_screen.md:164-166` says the rules — "the two sentences **and the suggestion**" — live in Signals and are not restated there, but the Signals Copy bullet describes only the observation and the second sentence; the Progression Rate bullet above it does name its suggestion. The cross-reference therefore points at a rule that is not stated. **Fix:** add one clause stating that every fired card carries the suggestion (statement-of-effect wording), pointing at the same test. → @developer

**5. `test/modality_mix_shift_signal_screen_test.dart:424` — minor — a test whose name claims an assertion its body does not make.** The S-1909 test is named "the caution card shows with the exact copy, the caution label and its key…", but the body asserts the key, the label, the absence of the quiet line, the position and the untouched blocks — never any copy text. The plan's S-1909 outcome asks for "the exact observation and suggestion from S-1901's rule applied to F-MIX", and F-MIX's literal strings are asserted nowhere (S-1901 pins a different fixture; the payload-equality guard at line 545 compares the card to copy built from the same payload, so it cannot catch a wrong literal). **Fix:** assert the two F-MIX strings, or rename the test to what it checks. → @developer

**6. `test/modality_mix_shift_signal_screen_test.dart:464-465` — minor — stale comment contradicting assumption A-6.** It says F-MIX's window is "period-scoped to the last 10 days" and that a chip-following period "would see only the `day(5)` isometric session"; A-6 re-scoped the fixture to 3 days with the isometric session at `day(2)`. The guard's reasoning is sound but the comment describes a fixture that no longer exists. **Fix:** update the two numbers. → @developer

### Carried (not in the fix set)

- **Scope declarations under-claim.** `docs/signals.md:3-9` declares only the four framework files yet documents `lib/core/models/progression_rate.dart`, `lib/core/models/modality_mix_shift.dart` and their two adapters; `docs/training_load.md:3-9` names only `computeMixLayer` while the doc now also documents `computeMixPeriod`. A narrower-than-content declaration makes a later reviewer skip a doc it should read (§5c rule 5). Fix when either doc is next touched.
- **Missing scope blocks.** `docs/stats_screen.md` and `docs/constants_reference.md` open with no scope block; §4.1/§5 call that a blocker. Pre-existing and not content this diff adds — flagging, not blocking this PR.
- **Unrelated formatting.** `lib/core/services/stats_progress_service.dart` (~line 912) carries a `dart format` reflow of a `groupsByExercise` wrap in a method this feature does not touch. Harmless; mention so the diff stays honest.
- **"over the last 4 weeks" inside the Copy bullet** is a quotation of the user-visible string (vocabulary the test pins), not the doc's own description of the span — I did not treat it as a §3.4 restatement, unlike finding 2. If the owner reads §3.4 strictly, it collapses into the same fix as finding 3.
- **`docs/constants_reference.md`'s new table** names the three constants and what each governs, with no values — §3.4-compliant; the plan's phrase "names and values only" is loose, the shipped doc is right.

---

## Acceptance criteria and scenario register

All thirteen ACs map to a scenario and every scenario has a passing test asserting its registered outcome. AC-12 ("the framework and the PR path are untouched") is met by the governor's no-diff check plus the untouched suites, which is the correct form for an absence. No AC is unmet.

S-1901…S-1913 in `test/modality_mix_shift_test.dart` (pure rule and copy), `test/modality_mix_period_service_test.dart` (period payload, both harnesses) and `test/modality_mix_shift_signal_screen_test.dart` (card, chip-independence, dismissal, registry). The dismissal-tap scenario is Mock-only by design (a Hive write cannot drain inside `FakeAsync`); the registry guard names the Mix Shift card by key rather than counting cards, so another signal cannot break it. Fixtures changed from the plan are A-1, A-2 and A-6, all documented, none weakening a boundary.

## Test gaps

- 🧪 MISSING: `test/modality_mix_shift_signal_screen_test.dart` — no literal assertion of the F-MIX observation/suggestion (finding 5).
- 🧪 MISSING: no fixture separates the exact `measure` read from the rounded `percent` read at screen level; the rule-level guard (Phase 3) does cover it, and the plan records the earlier gap as O-5, closed.
- No stale tests: nothing renamed or removed, and the two Mix suites are unmodified and green.

## Global conventions (`docs/global_conventions.md`)

- PASS (4 rules): Effort-kind drives analytics (the rule and the signal consume `ExerciseSection` from the shared payload; no second effort→modality mapping — asserted by the "walks no history of its own" guard); Timestamps are source data (bounds from `context.now` calendar components, sessions selected by persisted `startedAtMs`, no local counters); Reuse the canonical owner (one `_mixPayload` for both entry points, shared `baselineBlockStarts`, copy derives no percentage of its own); Instrument panel, not influencer (factual observation plus one statement-of-effect suggestion; no coaching copy).
- N/A (3 rules): Units + canonical storage, Theme tokens only, Card chrome via `OmniSurface`/`OmniCardHeader` — no styling, no unit conversion and no widget is added; both new files are Flutter-free.
- FAIL: none.

## Step 5c — documentation falsification

- DOC FALSIFICATION: ❌ REJECT — `docs/signals.md:64-65` — asserts every caution in the six-name order has its own priority constant; only `modality-mix-shift` (caution) and `progression-rate` (positive) exist → delete the shipped-voice enumeration, keep the invariant, point at the constant-contracts test (finding 1).
- DOC FALSIFICATION: ❌ REJECT — `docs/stats_screen.md:163` — restates `kModalityMixShiftPeriodDays` as "28 days" (finding 2).
- DOC FALSIFICATION: 🟡 WARNING — `docs/signals.md:241-243` — incomplete: the Copy bullet is silent about the suggestion that `docs/stats_screen.md` sends readers there for (finding 4).
- DOC FALSIFICATION: 🟡 SCOPE — `docs/signals.md` (line 3-9) and `docs/training_load.md` (line 3-9) — declared scope narrower than content; verified anyway.
- No cross-document conflict found. No other implicated claim is false: the period bounds, the abutting baseline, the measure gate, the two thresholds, the tie-break, the omitted second sentence and the payload-sharing claim all match `lib/` and each names a test that exists and passes.

## Step 5c-2 — documentation standard

- DOC STANDARD: ❌ REJECT — `docs/signals.md:62-68` — class 6 (roadmap/planned work presented as current) — remove the unshipped enumeration or reword to plan voice.
- DOC STANDARD: ❌ REJECT — `docs/stats_screen.md:163` — class 4 (numeric value defined in source) — name the constant.
- DOC STANDARD: ❌ REJECT — `docs/signals.md:215` — class 4 (derived duration restated) — delete "the 84 days".
- Classes 1, 2, 3, 5, 7: none added (the docs-contract guards are green, and the five diffs contain no code, no control inventory, no visual values).
- The three rejection-class rows above are cheap one-line edits; the standard's own severity ("prohibited content is a review blocker", §5) is why this PR is not approvable as-is.

## Architecture and clean code

Models: no Flutter or platform import, pure rule, immutable result type — PASS. Repositories: no diff. State: no diff. Features/widgets: no diff (the card is drawn by the untouched Signals layer). Core/services: the extracted helper is private, `computeMixLayer`'s contract is unchanged, the registry stays a list. Naming and size are clean; no magic number outside the three named constants; no dead code introduced. One structural-guard family covers the duplication risks that matter (no local percentage, no second walk, payload-derived segments).

## Open questions

- Whether finding 1 should be read as a blocker or a major: I read the brief's "as PLAN only if worded as planned, not as shipped" strictly, and the second sentence of that paragraph is shipped voice. Findings 2 and 3 are independently rejection-class under §3.4, so the verdict does not depend on how finding 1 is read.
- The brief restricts this review to writing the review file, so I did not add the plan's `## Feedback` pointer + fix checklist; the fix set is the six findings above.

VERDICT: CHANGES_REQUESTED
