# Feature: Stats PR 5c — housekeeping (contract comment, inbox de-duplication, mix-layer ellipsis, doc wording, index refresh)

> **Status:** PLANNED (conductor) — nothing implemented. Two phases, both `@developer`.
> Baselines taken at HEAD `e993751` on `develop` via the gateway: `lint` = `196 issues found. (ran in 3.0s)`;
> `test` (full) = `01:26 +3423 ~1: All tests passed!`.
> Evidence (baselines, search hits, doc-claim → test table) lives in
> `2026-10-03-05c-stats-pr5c-housekeeping-plan.evidence.md`. Review findings go in
> `2026-10-03-05c-stats-pr5c-housekeeping-plan.review.md`.

## Overview

Five independent loose ends left behind by Stats PR 5a, 5b and 3d. None changes what the app does,
except one: three strings in the Mix layer are now capped to a single line and ellipsized instead of
wrapping. The rest is a stale data-contract comment, one duplicated transformation folded into a
model method, two doc sentences that describe the code inaccurately, and two index plans that still
read as "not started".

The unit is deliberately small: it exists to stop 5a/5b/3d drift accumulating into a follow-up PR
that is bigger than the feature it follows.

## Scope check

| Measure | Count | Notes |
| --- | --- | --- |
| Items in the brief | 5 | schema comment; inbox de-duplication; ellipsis; doc wording; index refresh |
| Phases | 2 | both `@developer`; no `@dba` phase — no schema, model-shape or repository-interface change |
| Production files touched | 4 | `models.dart`, `hive_workout_repository.dart`, `mock_workout_repository.dart`, `mix_layer.dart` |
| Test files touched | 2 | `watch_capture_repository_parity_test.dart`, `mix_layer_screen_test.dart` |
| Data-contract files touched | 1 | `scripts/sqlite_schema.sql` — a comment, no column, type, nullability or CHECK change |
| Doc files touched | 2 | `stats_screen.md`, `design_system.md` |
| Plan files touched | 2 | the PR 5 index and the PR 3 index — the only two the brief names |
| New public API members | 1 | `WatchInboxEntry.unapplied()` |
| New tests | 2 | one model-rules test, one widget assertion |
| Predicted production lines | net ≈ +12, ≈ 27 lines touched | see each phase's *Predicted Files* |
| Predicted doc lines | ≈ 40 touched | two reworded sentences, two index refreshes |
| Behaviour changes | 1 | three Mix-layer texts cap to one line and ellipsize |

All well inside the budget in `.github/agents/pr_scope_budget.md` (hard: 800 plan lines, 5 phases,
~1,500 production lines; soft: >500 lines, >3 phases, >1 track, >20 decisions, >30 scenarios).
This plan has 16 decisions and 8 scenarios, so the soft signals are not tripped either.

## Requirements

- R1. `scripts/sqlite_schema.sql` no longer tells a reader that the inbox's applied stamp is never
  cleared. The column comment names the write that unsets it.
- R2. The stamp-clearing transformation that `HiveWorkoutRepository.clearWatchInboxApplied` and
  `MockWorkoutRepository.clearWatchInboxApplied` each spell out is expressed once, as a model method.
  Both repositories call it. No skip rule, key or stored shape changes.
- R3. The three Mix-layer texts that can be long — the measure label, the baseline note and the
  unrated line — cap to one line and ellipsize instead of wrapping. Nothing else in the layer moves.
- R4. `docs/stats_screen.md` stops claiming the Mix layer computes nothing, and says what the layer
  does compute itself.
- R5. `docs/design_system.md` stops claiming the Profile measurement headers carry the add button in
  `actions`; the header is title-only and the button lives in the card body.
- R6. `docs/plans/2026-10-02-05-stats-pr5-index.md` reads DONE for 5a (`9d5dca2`) and 5b
  (`e993751`), and lists the fixes carried out of their reviews.
- R7. `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` reads DONE for 3a3 (`c25617a9`)
  and 3d (`8be0918`), with 3c still not planned.
- R8. No commit, no stage, no push, no branch. `develop` is the working branch throughout.

## Acceptance Criteria

- [ ] `scripts/sqlite_schema.sql`'s `applied_at_ms` comment no longer contains the phrase `never cleared`.
- [ ] The comment names `clearWatchInboxApplied` as the only write that unsets the stamp.
- [ ] `WatchInboxEntry.unapplied()` exists, returns a row equal to the receiver except that
      `appliedAtMs` is `null`, and is idempotent.
- [ ] `grep` over `lib/` finds no remaining `'applied_at_ms': null` literal outside `models.dart`.
- [ ] Both `clearWatchInboxApplied` implementations call `staged.unapplied()`.
- [ ] The Hive implementation still writes `.toMap()` into its box; the Mock implementation still
      stores the model itself.
- [ ] The measure label, the baseline note and the unrated line each report `maxLines == 1` and
      `overflow == TextOverflow.ellipsis`.
- [ ] No other `Text` in `mix_layer.dart` gained `maxLines` or `overflow`; `OmniCardHeader` is untouched.
- [ ] `docs/stats_screen.md` no longer contains the phrase `computes nothing itself`, and its sentence
      still names a test.
- [ ] `docs/design_system.md`'s Profile row no longer claims the add button is in `actions`, and names
      the test that verifies the title-only header.
- [ ] The PR 5 index's status line reads DONE and carries both commit hashes; its PR table marks 5a
      and 5b done; it lists the 5a and 5b review follow-ups.
- [ ] The PR 3 index's status line reads DONE for 3a3 and 3d with their hashes; 3c still reads not planned.
- [ ] No plan file other than those two is modified.
- [ ] `flutter analyze` reports no new issues above the 196-issue baseline, 0 errors.
- [ ] The full suite passes with no failures and no new skips.
- [ ] Each new test is shown to fail against the pre-change source before it is accepted.

## Decision Ledger

| # | Decision | Rationale |
| --- | --- | --- |
| **D-1101** | This unit is exactly the brief's five items, in two phases, and is one PR. | The brief names the scope; nothing in it requires a data-model or interface change, so no `@dba` phase is warranted. |
| **D-1102** | Item 1 is a comment-only edit. No column, type, nullability or `CHECK` change. | The column's shape is already correct; only the prose is stale. Leaving the shape alone keeps `scripts/sqlite_schema.sql` a valid contract for `test/db_seed_test.dart`. |
| **D-1103** | The SQL-contract block above the inbox table is **not** extended with `clearWatchInboxApplied`. | The brief scopes item 1 to the column comment. The block's closing sentence ("no delete statement exists for this table") stays true, and the block's job is to enumerate the statements the schema serves, not every Dart method that writes a column. See OQ-1. |
| **D-1104** | Item 2 adds `WatchInboxEntry.unapplied()`, not a general `copyWith()`. | The only duplicated transformation is the stamp clear. `WatchInboxEntry` has no `copyWith` today, and a general one would have to solve nullable-clearing for `appliedAtMs` alone — a wider surface than the duplication justifies. |
| **D-1105** | `unapplied()` copies every field verbatim and omits only `appliedAtMs`. It is idempotent. | The row must survive the round trip unchanged in every field the import keys on: `entryId`, `watchSessionId`, `kind`, `origin`, `payloadJson`, `receivedAtMs`. Calling it on an already-unapplied row must be a no-op. |
| **D-1106** | Both repositories call `staged.unapplied()`; Hive still writes `.toMap()`, Mock still stores the model. | Each store's persistence idiom is unchanged, so no stored shape moves. |
| **D-1107** | The skip rules are untouched: an entry the box does not hold is skipped, an entry whose stamp is already `null` is skipped, nothing is created and nothing is deleted. | The change is a refactor of one expression; a behaviour change smuggled in with it would be a regression the brief did not ask for. |
| **D-1108** | Item 2 needs no SQL-contract edit. | `unapplied()` adds no field and changes no `toMap()` key, so the contract block and the schema stay in step with the model for free. |
| **D-1109** | The new model test lands in `test/watch_capture_repository_parity_test.dart`'s `D-131/D-132 model rules` group, and builds `WatchInboxEntry(...)` directly with `appliedAtMs: 5000`. | That group is the file's home for model rules, and its `_wristRow` helper cannot set a stamp, so a direct construction is the only way to build the applied state the test needs. |
| **D-1110** | The `S-1412` parity test is left byte-identical. | Its literal `{...appliedA.toMap(), 'applied_at_ms': null}` is an independent check of the *outcome*; rewriting it to call the new method would make the test agree with the implementation by construction and weaken it. |
| **D-1111** | Ellipsis goes on exactly three `Text`s in `mix_layer.dart` — the measure label, the baseline note and the unrated line — and nowhere else. `OmniCardHeader` is not touched. | These are the three strings whose length the user's data decides. The header is shared and its cap is a separate, larger change (see D-1117). |
| **D-1112** | The new ellipsis assertion lands in the `S-1605` group, not `S-1615`. | `S-1605`'s fixture (`FX-BASELINE3`) is the only seeded state in which all three texts render together; the `S-1615` fixture is load-ready, so its baseline note is absent. `S-1615`'s own test stays unchanged and green. |
| **D-1113** | The `docs/stats_screen.md` sentence is reworded to name the layer's own presentation arithmetic — the segment flex and the strip's tallest week — and still names the test that verifies it. | The current sentence is loose rather than wrong: the layer computes nothing *about the data*, but it does compute how a measure becomes a share of the bar and which week sets the strip's scale. |
| **D-1114** | The `docs/design_system.md` Profile row is corrected to "title-only header, add button in the card body" and names its verifier. | The code renders a title-only header and puts the add button in the body; the row currently says the opposite, which is how a future header change would be made wrongly. |
| **D-1115** | The `mix_layer.dart` file-header comment, which says the layer "renders and computes nothing", is corrected in the same edit. | It is the same claim as D-1113, in the file being edited. Leaving it would put the corrected doc in direct contradiction with the comment above the widget it describes. A comment is not a string, key, semantic or layout, so D-1111's boundary holds. See OQ-2. |
| **D-1116** | Only the two index plans the brief names are edited: the PR 5 index and the PR 3 index. | The PR 6 plan folders and every other plan are out of scope. |
| **D-1117** | Out of scope, recorded and not fixed: the third `'min'` unit literal, `MixLayerData`'s `==`/`toString`, the unobservable `baselineTotal > 0` guard, and `OmniCardHeader`'s half-header cap. | Each was carried out of the 5a/5b reviews as a separate, larger change. Fixing them here would break the brief's scope and the budget. |
| **D-1118** | Verification runs through the gateway only: `lint`, then the two targeted test files, then the full suite. Each new test is shown to fail against the pre-change source before it is accepted. | A test that passes with and without the change proves nothing; and `flutter analyze` passing is not a test run. |

## Scenarios

Fixture key: `FX-BASELINE3` = `_seedThreeRatedWeeks`; `FX-DENSE` = `_seedDensest`; `FX-SCHEMA` =
`scripts/sqlite_schema.sql` executed by `test/db_seed_test.dart`.

### S-1801: The schema comment describes the stamp's real lifecycle
- Trigger: a developer reads the inbox table's `applied_at_ms` column comment.
- Precondition: FX-SCHEMA.
- Flow: open `scripts/sqlite_schema.sql` at the inbox table; read the `applied_at_ms` line.
- Expected outcome: the comment says the column is `NULL` while the row waits, is stamped once on
  apply, and is unset only by `clearWatchInboxApplied` — the phrase `never cleared` is gone.
- Edge case of: none.

### S-1802: `unapplied()` clears only the stamp
- Trigger: `WatchInboxEntry.unapplied()` is called on a row with `appliedAtMs: 5000`.
- Precondition: a row built with every field set, including a payload.
- Flow: call `unapplied()`; compare `toMap()` with the original's map plus `'applied_at_ms': null`.
- Expected outcome: the maps are equal; `appliedAtMs` is `null`; `entryId`, `watchSessionId`, `kind`,
  `origin`, `payloadJson` and `receivedAtMs` are untouched.
- Edge case of: none.

### S-1803: `unapplied()` is idempotent
- Trigger: `unapplied()` is called on a row that is already unapplied.
- Precondition: S-1802 has run, or the row was staged and never applied.
- Flow: call `unapplied()` a second time; compare maps.
- Expected outcome: the second call returns a row equal to the first — no field is nulled twice, no
  payload is re-encoded differently.
- Edge case of: S-1802.

### S-1804: Both stores still un-stamp, on the same skip rules
- Trigger: the user applies the watch inbox, then asks the app to clear what it applied.
- Precondition: the inbox holds one applied row, one unapplied row, and the caller names one id the
  box does not hold.
- Flow: call `clearWatchInboxApplied` on each store.
- Expected outcome: the applied row loses its stamp; the unapplied row is unchanged; the absent id is
  skipped without creating or deleting anything. The two stores agree.
- Edge case of: none.

### S-1805: The three layer texts cap to one line and ellipsize
- Trigger: the Stats screen renders the Mix layer over a window whose figures are long.
- Precondition: FX-BASELINE3 — a period-scoped window with 3 rated baseline weeks and one unrated
  session, so the measure label, the baseline note and the unrated line all render.
- Flow: pump the Stats screen; read the three `Text` widgets.
- Expected outcome: each reports `maxLines == 1` and `overflow == TextOverflow.ellipsis`; each is
  still found by its full string, so no copy changed.
- Edge case of: none.

### S-1806: The dense layer still fits its card
- Trigger: the Stats screen renders the Mix layer over the densest fixture at the narrowest supported
  width.
- Precondition: FX-DENSE, at 375×667 with text scale 1.3 and at 440×956 with text scale 1.0.
- Flow: pump the Stats screen at both sizes; let the layout settle.
- Expected outcome: no overflow exception; the strip's eight columns still share the card; the
  `S-1615` assertions pass unchanged.
- Edge case of: S-1805 — capping to one line can only shrink a text, never grow it.

### S-1807: No doc still makes the two corrected claims
- Trigger: a reader looks up the Mix layer or the Profile headers.
- Precondition: the two reworded docs.
- Flow: read the Mix-layer paragraph in `docs/stats_screen.md` and the Profile row in
  `docs/design_system.md`.
- Expected outcome: neither claims the layer "computes nothing itself" nor that the Profile add
  button is in the header's `actions`; each sentence names the test that verifies the corrected
  statement.
- Edge case of: none.

### S-1808: Both indexes read DONE with their hashes
- Trigger: a reader opens either index plan to find out what is left.
- Precondition: the two index refreshes.
- Flow: read the status block and the PR table of each index.
- Expected outcome: the PR 5 index reads DONE for 5a (`9d5dca2`) and 5b (`e993751`) and lists the
  fixes carried out of their reviews; the PR 3 index reads DONE for 3a3 (`c25617a9`) and 3d
  (`8be0918`) with 3c still not planned.
- Edge case of: none.

---

## Iteration 1

### Phase 1 — `@developer`: the inbox de-duplication and the ellipsis (items 2 and 3)

One concern per step. Items 2 and 3 share no file, so they may be done in either order, but each
step's red test must be observed before its implementation.

1. [ ] **Write the model test first (red).** Append one `test` to the `D-131/D-132 model rules` group
   at the end of `test/watch_capture_repository_parity_test.dart`. Build the row directly — the file's
   `_wristRow` helper cannot set a stamp — using `WatchInboxEntry(entryId: 'e-run', watchSessionId:
   _session, kind: WatchInboxEntry.kindTimed, origin: WatchInboxEntry.originWatch, payload:
   _runEvent(), receivedAtMs: 1000, appliedAtMs: 5000)`. Assert three things, each with a `reason`
   naming `D-132`: `cleared.appliedAtMs` is `null`; `cleared.toMap()` equals
   `{...applied.toMap(), 'applied_at_ms': null}`; `cleared.unapplied().toMap()` equals
   `cleared.toMap()`. **Run it and read the failure** — `unapplied()` does not exist yet, so the file
   must fail to compile. Record the exact output in the evidence file.
2. [ ] **Add `WatchInboxEntry.unapplied()`** to `lib/data/models/models.dart`, immediately after
   `fromMap` and before `toMap`. It returns `WatchInboxEntry._(...)` with `entryId`,
   `watchSessionId`, `kind`, `origin`, `payloadJson` and `receivedAtMs` copied verbatim and
   `appliedAtMs` omitted. Doc comment: a copy of this row with no applied stamp — the state it held
   before the import applied it. **Run step 1's test; it must now pass.** If it passes without the
   method, the test is wrong.
3. [ ] **Fold the Hive implementation onto it.** In
   `lib/data/repositories/hive_workout_repository.dart`, `clearWatchInboxApplied` currently writes
   `await _watchInboxBox.put(entryId, WatchInboxEntry.fromMap({...staged.toMap(),
   'applied_at_ms': null}).toMap());`. Replace the value with `staged.unapplied().toMap()` — the box
   still receives a map, so the stored shape is unchanged. Leave the skip conditions above it alone.
4. [ ] **Fold the Mock implementation onto it.** In
   `lib/data/repositories/mock_workout_repository.dart`, the same method currently writes
   `_watchInbox[entryId] = WatchInboxEntry.fromMap({...staged.toMap(), 'applied_at_ms': null});`.
   Replace the value with `staged.unapplied()` — the in-memory store still holds the model itself.
   Leave the skip conditions alone.
5. [ ] **Confirm the duplication is gone.** Search `lib/` for the literal `'applied_at_ms': null`; the
   only remaining hit must be inside `models.dart` (the `toMap()` key) — no repository builds the
   cleared map by hand any more.
6. [ ] **Run the parity file.** `test/watch_capture_repository_parity_test.dart` must pass unchanged,
   including `S-1412`, which is left byte-identical on purpose (D-1110).
7. [ ] **Write the ellipsis assertion (red first).** In `test/mix_layer_screen_test.dart`, inside the
   existing `S-1605` group (`FX-BASELINE3`, the only fixture where all three texts render together),
   add one `testWidgets`. Pump the Stats screen, then for each of the strings `by time`,
   `Load baseline: 3 of 4 weeks rated` and `1 unrated session`, read
   `tester.widget<Text>(find.text(label).first)` and assert `maxLines == 1` and
   `overflow == TextOverflow.ellipsis`, each with a `reason` naming `D-933`. The `.first` is required
   for `by time`, which renders twice. **Run it and read the failure** — three assertions must fail
   with `null` versus the expected values. Record the output.
8. [ ] **Add the two properties to the three texts.** In
   `lib/features/stats/widgets/mix_layer.dart`, add `maxLines: 1, overflow: TextOverflow.ellipsis` to
   the measure label in `_measureText`, to the `'Load baseline: …'` text, and to the unrated-session
   text. Change nothing else — not the strings, not the semantics, not the spacing, and not the
   shared `OmniCardHeader`. Also correct the file-header comment, which currently says the layer
   "renders and computes nothing", to the same statement the doc will carry (D-1115).
9. [ ] **Run the mix-layer file.** It must pass with the new assertion and with `S-1615` unchanged.
10. [ ] **Inverse-edit check.** Make `unapplied()` return `this`; step 1's test and `S-1412` must both
    fail. Restore. Remove `maxLines`/`overflow` from one of the three texts; step 7's test must fail.
    Restore. Record both in the evidence file.

### Phase 1 Done Criteria

- `test/watch_capture_repository_parity_test.dart` passes; its output names the new test.
- `test/mix_layer_screen_test.dart` passes; `S-1615`'s assertions are untouched.
- Step 5's search returns exactly one hit, inside `models.dart`.
- Both inverse edits produce the failures named in step 10, and the restored source passes.
- The two red runs in steps 1 and 7 are pasted into the evidence file.

### Phase 1 Predicted Files

| File | Predicted production lines | Change | Measured |
| --- | --- | --- | --- |
| `lib/data/models/models.dart` | +11 | the new `unapplied()` and its doc comment | +14 |
| `lib/data/repositories/hive_workout_repository.dart` | −4 | 5 duplicated lines become 1 call | −7 / +1 |
| `lib/data/repositories/mock_workout_repository.dart` | −3 | 4 duplicated lines become 1 call | −4 / +1 |
| `lib/features/stats/widgets/mix_layer.dart` | +7 | 6 property lines plus a 2-line comment correction | +12 / −5 |
| `test/watch_capture_repository_parity_test.dart` | not counted | +≈35 test lines | +28 |
| `test/mix_layer_screen_test.dart` | not counted | +≈25 test lines | +20 |

Net production delta ≈ +11; ≈ 27 production lines touched. Measured net production delta is +16
across 4 files (the doc comment on `unapplied()` is 4 lines longer than predicted).

### Phase 2 — `@developer`: the contract comment, the two doc sentences and the two index refreshes (items 1, 4, 5)

No production code changes in this phase. No step needs a red test; each step's evidence is the
search result or the file read-back named in it.

1. [ ] **Correct the schema comment (item 1).** In `scripts/sqlite_schema.sql`, the inbox table's
   `applied_at_ms` line ends `-- NULL = waiting; set once, never cleared`. Replace that trailing
   comment with one that says the column is `NULL` while the row waits, is stamped once when the
   import applies it, and is unset only by `clearWatchInboxApplied`. Change nothing else on the line
   and nothing else in the file — not the type, not the nullability, not the contract block above the
   table (D-1103).
2. [ ] **Prove the comment is unique and the contract still runs.** Search the repo for `never
   cleared`; the only remaining hit must be the unrelated skipped-set-marker note in
   `docs/plans/data-tracking-fixes-plan.md`. Then run `test/db_seed_test.dart`, which executes the
   schema; it must pass.
3. [ ] **Reword the Mix-layer sentence (item 4a).** In `docs/stats_screen.md`, the paragraph that
   currently reads "It is presentation only: every figure it draws is one `MixLayerData` supplies, and
   it computes nothing itself. Verified by `test/mix_layer_screen_test.dart` (`S-1601`)." becomes a
   statement that every figure it draws is one `MixLayerData` supplies, and that the arithmetic the
   layer does itself is presentation only — the flex that turns a measure into a share of the bar and
   the tallest week that sets one scale for all eight strip columns. Keep it naming the test file and
   its scenario ids. Do not introduce numbers, hex values or line references
   (`docs/documentation_standard.md`).
4. [ ] **Fix the Profile row (item 4b).** In `docs/design_system.md`'s header table, the Profile row
   currently reads "One header per measurement definition (label + `+` add button in actions)". Make
   it say the header is title-only — one per measurement definition — and that the `+` add button
   lives in the card body, and name `test/header_standardization_test.dart` (`S-011`) as the verifier.
5. [ ] **Read both doc claims back against the code.** Confirm `lib/features/profile/profile_screen.dart`
   renders a title-only `OmniCardHeader` for each measurement definition with the add button in the
   body, and that `lib/features/stats/widgets/mix_layer.dart` computes the segment flex and the
   strip's tallest week. If either read-back contradicts the new sentence, stop and report rather than
   softening the sentence.
6. [ ] **Refresh the PR 5 index (item 5a).** In `docs/plans/2026-10-02-05-stats-pr5-index.md`: replace
   the status line's "READY (planner) — 5a not started" with a DONE status dated 2026-10-03 that names
   5a's commit `9d5dca2` and 5b's commit `e993751`; add a status column to the "The PRs, in order"
   table marking 5a and 5b done with their hashes and adding one 5c row pointing at this plan folder;
   and add a section listing what the two reviews produced, split into what the fix rounds already
   landed (the 5a findings and the 5b findings) and what is carried here as 5c. Also correct the
   shared-decisions bullet that repeats the "computes nothing" claim, so the index does not
   contradict the doc it points at.
7. [ ] **Refresh the PR 3 index (item 5b).** In
   `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`: replace the status line with a DONE
   status dated 2026-10-03 naming 3a3's commit `c25617a9` and 3d's commit `8be0918`, leaving 3c as not
   planned; mark the 3a3 and 3d rows done in the PR table; and update the closing scope-check
   paragraph to match.
8. [ ] **Prove no other plan moved.** Confirm the only plan files changed in this unit are the two
   above (plus the two new files in this folder); the PR 6 folders and every other plan are untouched.
9. [ ] **Run the full suite and the linter.** `gateway.sh lint` must report 0 errors and no more than
   the 196-issue baseline; `gateway.sh test` must report no failures and no new skips. Paste both
   final lines into the evidence file.

### Phase 2 Done Criteria

- The schema's `applied_at_ms` comment names `clearWatchInboxApplied` and contains neither `never
  cleared` nor any other statement the code contradicts.
- `test/db_seed_test.dart` passes.
- Neither reworded sentence contains a number, a hex value or a line reference, and each names its
  verifier.
- The PR 5 index reads DONE for 5a and 5b with both hashes, marks them done in its table, and lists
  the carried fixes; the PR 3 index reads DONE for 3a3 and 3d with both hashes and keeps 3c
  unplanned.
- Step 8's check shows no other plan file modified.
- `gateway.sh lint` and `gateway.sh test` outputs are pasted into the evidence file.

### Phase 2 Predicted Files

| File | Predicted lines | Change | Measured |
| --- | --- | --- | --- |
| `scripts/sqlite_schema.sql` | 1 changed | the `applied_at_ms` comment only | 1 changed |
| `docs/stats_screen.md` | ≈ 6 | one reworded sentence | +5 / −3 |
| `docs/design_system.md` | ≈ 2 | one corrected table row | 1 changed |
| `docs/plans/2026-10-02-05-stats-pr5-index.md` | ≈ 25 | status line, table, follow-up section, one bullet | +31 / −5 |
| `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` | ≈ 10 | status line, table, closing paragraph | +11 / −10 |

## Governor actions

None required. Every decision above is a technical call inside the brief's stated scope, so it was
made and recorded rather than escalated (`.github/agents/pr_scope_budget.md` and the brief's
decision-ownership rule). The three questions that could have gone to the owner — whether the
schema's contract block grows a line, where the ellipsis assertion lives, and whether the 5c plan gets
a row in the PR 5 index — are recorded under *Open questions* with the defaults this plan assumes, and
the answers are cheap to reverse.

Stop-and-report conditions, if any of them occurs:

- A read-back in Phase 2 step 5 contradicts a reworded sentence.
- Correcting the schema comment requires touching anything other than that comment.
- De-duplicating the two repositories changes any skip rule or stored shape, or makes `S-1412` fail.
- The three texts cannot be capped without a layout change, or `S-1615` starts failing.
- The full suite or the linter regresses past the baselines for a reason this unit caused.

## Files Affected

**Production (4)**

- `lib/data/models/models.dart` — add `WatchInboxEntry.unapplied()`.
- `lib/data/repositories/hive_workout_repository.dart` — call it in `clearWatchInboxApplied`.
- `lib/data/repositories/mock_workout_repository.dart` — call it in `clearWatchInboxApplied`.
- `lib/features/stats/widgets/mix_layer.dart` — three texts cap to one line and ellipsize; header
  comment corrected.

**Data contract (1)**

- `scripts/sqlite_schema.sql` — the inbox `applied_at_ms` column comment.

**Tests (2)**

- `test/watch_capture_repository_parity_test.dart` — one model-rules test.
- `test/mix_layer_screen_test.dart` — one assertion in the `S-1605` group.

**Docs (2)**

- `docs/stats_screen.md` — the Mix-layer sentence.
- `docs/design_system.md` — the Profile row of the header table.

**Plans (2 edited, 2 created)**

- `docs/plans/2026-10-02-05-stats-pr5-index.md` — status, table, follow-ups.
- `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` — status, table, closing paragraph.
- `docs/plans/2026-10-03-05c-stats-pr5c-housekeeping-plan/2026-10-03-05c-stats-pr5c-housekeeping-plan.md` — this file.
- `docs/plans/2026-10-03-05c-stats-pr5c-housekeeping-plan/2026-10-03-05c-stats-pr5c-housekeeping-plan.evidence.md` — evidence.

## Progress

| # | Step | Phase | Owner | Status |
| --- | --- | --- | --- | --- |
| 1 | Model test for `unapplied()` written and observed failing | 1 | `@developer` | done — red: compile failure at line 1334 |
| 2 | `WatchInboxEntry.unapplied()` added; test green | 1 | `@developer` | done — `+37` |
| 3 | Hive `clearWatchInboxApplied` calls it | 1 | `@developer` | done |
| 4 | Mock `clearWatchInboxApplied` calls it | 1 | `@developer` | done |
| 5 | `'applied_at_ms': null` literal gone from `lib/` outside the model | 1 | `@developer` | done — only `models.dart`'s `toMap()` key remains |
| 6 | Parity file green, `S-1412` untouched | 1 | `@developer` | done — `+37`, `S-1412` byte-identical |
| 7 | Ellipsis assertion written and observed failing | 1 | `@developer` | done — red: 2 failures, `Expected: <1> Actual: <null>` |
| 8 | Three texts capped; header comment corrected | 1 | `@developer` | done |
| 9 | Mix-layer file green, `S-1615` untouched | 1 | `@developer` | done — `+56` |
| 10 | Inverse-edit checks recorded | 1 | `@developer` | done — evidence §5 |
| 11 | Schema comment corrected | 2 | `@developer` | done — 1 line |
| 12 | Comment uniqueness proven; seed test green | 2 | `@developer` | done — `+9` |
| 13 | `docs/stats_screen.md` sentence reworded | 2 | `@developer` | done |
| 14 | `docs/design_system.md` Profile row corrected | 2 | `@developer` | done |
| 15 | Both doc claims read back against the code | 2 | `@developer` | done — both confirmed, no contradiction |
| 16 | PR 5 index refreshed | 2 | `@developer` | done |
| 17 | PR 3 index refreshed | 2 | `@developer` | done |
| 18 | No other plan moved | 2 | `@developer` | done — `git-diff --name-only -- docs/plans/` returns the two indexes |
| 19 | Full suite and linter at baseline | 2 | `@developer` | done — `196 issues found.`; `+3426 ~1: All tests passed!` |
| 20 | Review of the finished unit | — | `@code-reviewer` | not started |

## Assumption Log

| # | Assumption | How it was checked | Confidence |
| --- | --- | --- | --- |
| A-1 | The stale comment exists only in `scripts/sqlite_schema.sql`. | Searched the repo for `never cleared` and `set once`: one schema hit, one unrelated plan hit. `docs/db_integration.md` and `docs/data_models.md` already state the corrected lifecycle. | high |
| A-2 | The three Mix-layer texts render together only under `FX-BASELINE3`. | The `S-1605` group is the only one asserting both the baseline note and the unrated line; the `S-1615` fixture is load-ready, so its note is absent. | high |
| A-3 | Neither repository needs a stored-shape change. | Hive writes `toMap()` into its box today and Mock stores the model today; both keep doing exactly that. | high |
| A-4 | The SQL contract stays in step with the model without an edit. | `unapplied()` adds no field and changes no `toMap()` key, so the contract block and the schema describe the same columns as before. | high |
| A-5 | `test/db_seed_test.dart` executes the schema, so a comment edit cannot break it — but it is run anyway. | The brief and `docs/db_integration.md` both say the schema is executed as a contract; the step runs it rather than assuming. | high |
| A-6 | 5a, 5b, 3a3 and 3d are committed at `9d5dca2`, `e993751`, `c25617a9` and `8be0918`. | Read from the gateway's `git-log`; `e993751` is HEAD. | high |
| A-7 | The lint baseline is 196 issues with 0 errors. | `gateway.sh lint` at HEAD: `196 issues found. (ran in 3.0s)`. | high |
| A-8 | The suite baseline is 3423 passing, 1 skipped, 0 failing. | `gateway.sh test` at HEAD: `01:26 +3423 ~1: All tests passed!`. | high |
| A-9 | The final suite is the baseline plus this unit's three new tests, with no new skips. | `gateway.sh test`: `01:24 +3426 ~1: All tests passed!` — 3423 + 3, same single skip. | high |
| A-10 | The repo is not `dart format`-clean at HEAD, so formatting the changed files reflows unrelated code. | `dart format` on the six changed Dart files reported 3 changed; the reflows were reverted by hand so only this unit's lines remain. | high |

## Feedback

*(empty — findings from `@code-reviewer` go in
`2026-10-03-05c-stats-pr5c-housekeeping-plan.review.md` and are folded into Iteration 2 here.)*

## Open questions

Each carries the default this plan assumes. All three are reversible at the cost of one line.

1. **Does the schema's SQL-contract block above the inbox table gain a line for
   `clearWatchInboxApplied`?** Default: **no**. The brief scopes item 1 to the column comment, and the
   block's closing sentence stays true. If the owner wants the block to enumerate every write that
   touches this table, it becomes one added line in Phase 2 step 1.
2. **Does the `mix_layer.dart` file-header comment get corrected too?** Default: **yes** (D-1115). It
   repeats the same claim the doc sentence is being corrected for, in the file being edited; leaving
   it would make the corrected doc contradict the code it points at. If the owner wants item 3 kept to
   the three property pairs and nothing else, this is one reverted comment.
3. **Does the 5c plan get a row in the PR 5 index?** Default: **yes**, one row. It is what makes the
   index answer "what is left" without opening a second file; if the owner prefers the index frozen
   at 5b, Phase 2 step 6 drops that row.
