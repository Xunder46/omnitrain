# PR 2 — Review findings (companion to `2026-09-25-02-stats-pr2-watch-capture-plan.md`)

Findings live in this file, per `.github/agents/pr_scope_budget.md` §2. The plan points here.

## Re-review — 2026-09-26 (@code-reviewer, Opus): APPROVE WITH NITS

**Scope:** the unstaged fix round on top of the staged handoff `b9348fe` — F-7, F-8, F-10, F-11
and F-12.

**Counts at the checkout:**
- `flutter test` `01:14 +2994 ~1: All tests passed!`
- `swift test` `Executed 242 tests, with 0 failures`
- `flutter analyze` `242 issues found.`, nothing new.
- No assertion was loosened. CRLF files are intact.

| Finding | Fixed as specified? | Main mutation caught? | Secondary gap |
|---|---|---|---|
| F-7 crown wrap | Yes. `isContinuous: false`, and wraps larger than half the span are ignored. The watchOS type-check is clean for the simulator and for arm64_32. | Yes | Two of the four test assertions can't fail (N3). |
| F-8 refresh after a phone rating | Yes | Yes (call removed) | The order "refresh after write" is untested (N2). |
| F-10 integer typing | Yes. The fixture is registered and exercised by both stacks. | Yes, on both stacks | Wording and spec text (N5, N6) |
| F-11 shipping-plan wording | Yes (doc only) | — | — |
| F-12 rating range, theme doc | Partly | Yes (range check removed) | The 1 and 5 boundaries are untested (N1). The doc lost a needed rationale (N4). |

## Findings

### Final mechanical round: fix in PR 2, one round, no further re-review loop

- **N1 — WARNING, MECHANICAL.** Nothing asserts that ratings of exactly 1 and 5 are accepted.
  - Where: test `test/watch_session_import_test.dart` ~1455–1491; source
    `lib/state/watch/watch_session_inbox.dart` ~244.
  - Failure: changing the check to `rating <= 1 || rating >= 5` passes the full suite. The live
    screen ignores the result (`live_session_screen.dart` ~135), so the must-answer sheet closes
    and the user's 1 or 5 is silently lost.
  - Fix: assert that 1 and 5 are recorded, both before and after the import.
- **N2 — WARNING, MECHANICAL.** F-8's "refresh after the write" is untested. Both tests only count
  refreshes (`watch_session_import_test.dart` ~1443–1449, `live_session_effort_rating_test.dart`
  ~413–419).
  - Failure: moving the refresh before the write re-creates F-8 (the calendar shows the session
    unrated), and every test still passes.
  - Fix: wire the refresh to a real calendar, as S-271 does (`watch_session_import_test.dart`
    ~1126–1139), and assert that the calendar shows the new rating.
- **N3 — WARNING, MECHANICAL.** Two of the F-7 test's assertions can't fail
  (`WatchEffortRatingTests.swift` ~434, ~437).
  - Line ~434 runs at selection 5, where an upward jump is capped anyway.
  - Line ~437 turns back to where the crown already was.
  - Fix: call `select(1)` before the reverse wrap. After the −end wrap, assert that a one-detent
    turn moves a middle value.
- **N4 — WARNING, MECHANICAL.** `docs/theme_and_settings.md` ~72–80.
  - (a) Restore, as one sentence with a pointer to `test/settings_state_test.dart` ~252, why the
    Effort Rating toggle keeps the `show_feeling_survey` key: every user's choice carried over.
    Renaming the key would reset everyone.
  - (b) Drop the "or off App State, which holds the field-level view" clause. The two docs point
    at each other, and App State's table is content the standard prohibits (§3.4/§3.5).
  - (c) Either pin the weight-unit and week-start setter fallbacks with a test, or narrow the
    claim that "each setter normalises".
  - (d) Flag the Theme System section (the enum code block and the token table) as §5 requires.
- **N5 — WARNING, MECHANICAL.** `watch/sync_protocol/PROTOCOL.md` ~27–31 calls the schema
  language a subset of JSON Schema 2020-12, under which `3200.0` is a valid `integer`. Add one
  sentence stating that whole-number doubles are refused, pointing at the new invalid fixture.
- **N6 — SUGGEST, MECHANICAL.** The two validators word the same refusal differently. Swift says
  "expected integer, found 3200" (`SyncProtocolValidator.swift` ~880–883, ~896–900); Dart says
  "found 3200.0". Keep the fraction when the number is float-typed.
- **N7 — SUGGEST, MECHANICAL.** `docs/watch_session_capture.md` ~160–161: the
  liveness invariant cites only S-271, so add the S-284 refresh assertions. The plan's A-50 note
  says "at both layers", but the tests are state-layer only; correct it.

### Moved out of PR 2

- **N8 — SUGGEST, DECISION (scope).** The same crown-wrap problem is pre-existing outside PR 2.
  `WatchLoggingView.swift` ~152 uses a continuous crown with a plain delta
  (`WatchLoggingModel.swift` ~97–108), and `WatchNutritionView.swift` ~166 is continuous too. A
  wrap adds or subtracts about 20 steps. Now PR 2 Open Item O-20, a candidate small follow-up PR.
- **N9 — SUGGEST, DESIGN.** A forward constraint from F-10: the wrist validates its own
  emissions (`WatchSessionEngine.swift` ~1547–1557). The durable store that shipping-plan Phase 7
  adds must reload integers as integers, or every resend after a relaunch will be refused. Now a
  Phase 7 checklist item in `2026-09-21-13-watch-integration-shipping.md`.

## Verification pass before approval — 2026-09-26 (@code-reviewer): APPROVED WITH WARNINGS

**Scope:** the whole PR as staged plus the three unstaged fix rounds — nothing was re-mutated; this
pass re-derived scope from the changed files and re-checked acceptance criteria, the scenario
register, the doc set and every `global_conventions.md` rule. N1–N7 verified as done by inspecting
the tests and the mutations the last round recorded (`….evidence.md`).

**Counts at the checkout:** `flutter test` `01:15 +2999 ~1: All tests passed!`; `swift test`
`Executed 242 tests, with 0 failures`; `flutter analyze` `242 issues found.` (the baseline's, none
new); watchOS type-checks clean for the simulator and for `arm64_32`.

**Checked, all PASS:**

- Every acceptance criterion maps to a test (AC-2.1…AC-2.6, AC-3.1…AC-3.6, AC-F.1…AC-F.6), with
  S-291/S-292 as the plan documents them — checks with evidence rather than tests.
- Scenario register: all 52 test-scenarios appear in `test/` and `watch/watchos/Tests/`, outcomes
  asserted as the register states; the two absent ids are S-291/S-292, which the plan declares as
  checks. S-200 in the tests belongs to another plan's range.
- Doc pointers: every `lib/`, `test/`, `watch/` and `scripts/` path cited by **every** document in
  `docs/` resolves — except the four below and the two docs that were already
  corrected in place (`db_integration.md:543-549`, `session_widgets.md:21-26,173-178`).
- Docs standard: no prohibited class added by this PR; the ten changed docs keep their scope,
  invariants and test pointers; the largest is `state_management/services_and_utils.md` at
  45,607 bytes — below the test's 52,429-byte warning threshold and the 65,536-byte ceiling, as
  `test/docs_indexing_contract_test.dart` (`+9`) confirms.
- Environment safety: no `dart:io` in shared code; the concrete repositories appear only in
  `lib/main.dart` and the debug harness; the inbox, importer, router and wiring import the
  `WorkoutRepository` interface only.
- Buttons: every button in the touched screens sets `shape` from an `OmniTheme` radius token; the
  new sheet has no buttons (its tiles are gesture targets).
- No assertion was loosened anywhere in the three rounds; the assertion-change tables are empty.

**Findings (none blocking):**

- **V-1 — WARNING, DOC ACCURACY.** `docs/theme_and_settings.md:86` claims "the
  defaults, the keys, the normalisation and the fallbacks are pinned by
  `test/settings_state_test.dart`". Every one is except the **preferred weight unit's default**:
  no test asserts `kg` with nothing saved (`test/settings_state_test.dart:123-133` loads a stored
  `lbs`; `:277` starts from a written value).
  **Fix:** add `expect(state.preferredWeightUnit, 'kg')` before the loop in
  `setPreferredWeightUnit keeps only lbs or kg`, or scope the sentence. One line either way.
  → @developer
- **V-2 — WARNING, STALE DOC (pre-existing, not this PR's).**
  `docs/widget_catalog/feature_primitives.md:108` names
  `lib/widgets/chart/measurement_sparkline.dart` and `:121` names
  `lib/features/home/widgets/home_logo_button.dart` as current `**File**:` claims; the classes live
  at `lib/features/profile/widgets/measurement_sparkline.dart` and
  `lib/widgets/common/home_logo_button.dart`, and the page carries no correction note. Nothing this
  PR changed made these false, and the page is outside its diff.
  **Fix:** correct the two paths. → @developer, follow-up (own PR or a docs tidy)
- **V-3 — SUGGEST, DEAD API.** `lib/state/watch/watch_session_inbox.dart:72` —
  `WatchInboxResult.historyChanged` is written (`:210`) and never read anywhere, including tests;
  the inbox performs the refresh itself through `_onHistoryChanged`.
  **Fix:** drop the field, or have a caller use it. → @developer, optional
- **V-4 — SUGGEST, INHERITED VALUES.** `lib/widgets/session/effort_rating_sheet.dart:72` uses
  `Colors.black54` and the sheet/tile radii at `:136` and `:229` are literals — the only non-token
  visual values in the new file. They are PR 1's, moved verbatim under the extraction's
  zero-visual-change mandate, so changing them here would alter pixels.
  **Fix:** route through `colorScheme.scrim` and tokens in a PR 1 follow-up. → @developer, later

**Verdict: APPROVED WITH WARNINGS.** No critical finding, no unmet acceptance criterion, no stale
test. V-1 is a one-line fix and V-2 is pre-existing drift; both are safe to land as-is or fix in
this PR — the owner decides. No further review round is proposed (`pr_scope_budget.md` §1).

### V-round resolution — 2026-09-26 (@developer)

All four addressed at the owner's direction; measurements in `….evidence.md`.

- **V-1 — FIXED.** New `SettingsState defaults preferred weight unit to kg`
  (`test/settings_state_test.dart`, after the stored-`lbs` test). Mutation red→green: the repository
  default inside `_loadFromPrefs` `'kg'`→`'lbs'` reddens it (`Expected: 'kg' / Actual: 'lbs'`, `:142`).
  The first mutation tried — the field initialiser — **passed**, because `_loadFromPrefs` overwrites
  it; recorded as A-72.
- **V-2 — FIXED.** Both `**File**:` paths corrected in `widget_catalog/feature_primitives.md`. They
  were repo-wide the only stale ones, and `widget_catalog.md`'s index points at the page, not the
  files, so it needed no edit.
- **V-3 — FIXED.** `WatchInboxResult.historyChanged` removed. `_settle`/`_settleNow` then returned a
  record whose `changed` component no caller read, so that went too: they now return the receipted
  ids, and the history refresh stays where it always happened, inside `_settleNow`.
- **V-4 — FIXED IN PART, REST DOCUMENTED.** `barrierColor: Colors.black54` deleted: the SDK's own
  fallback chain is `bottom_sheet.dart:1285` `barrierColor ?? Theme.of(context).bottomSheetTheme
  .modalBarrierColor` → `:1064` `modalBarrierColor ?? Colors.black54`, and the app defines no
  `BottomSheetThemeData`, so the value is provably the same one. The sheet's 20.0 top radius now
  reads `OmniTheme.surfaceBorderRadius` (same value, was the file's only literal that had a token).
  The tile's `circular(14)` and `backgroundColor: Colors.transparent` **stay**: no radius token
  exists, and changing either would move pixels against the extraction's zero-visual-change mandate
  (A-73, Open Item O-21).
