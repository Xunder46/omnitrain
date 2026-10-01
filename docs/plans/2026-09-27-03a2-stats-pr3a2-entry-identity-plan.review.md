# PR 3a2 — Code review (entry identity)

> Plan: `2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md` · Evidence: `…plan.evidence.md`.
> Reviewed 2026-09-27: the uncommitted tree on `feature/stats-pr3a2-entry-identity` (base `develop` = 4bb4afb).
> **Verdict: CHANGES REQUESTED.** 3 CRITICAL (all documentation, all cheap), 4 WARNING, 2 SUGGEST, 2 NIT.
> **Triage (budget "At review"):** 9 substantive findings (> 6), and two DESIGN findings that span the rule and
> its readers and writers, so the work splits. §8 lists what to fix in this PR, in one round, with no
> second review. Those items prove themselves with their own red→green records and the two suites.
> Everything else goes to a follow-up PR planned with conductor-v2.

## 1. Scope

- **Layers in scope:** `core/utils` (entry_rows, distance_source, observation_grouper); `data/repositories`
  (clone only); `state/workout`; `features/session` (Summary); the SQL contract; tests; docs.
- **Layers skipped:** models and widgets (no change); `core/services` (read, not changed).
- **Watch, confirmed untouched:** no diff under `watch/`, `lib/watch/`, `lib/core/sync_protocol/` or
  `lib/core/services/watch_session_importer.dart`.

## 2. Observed runs (reviewer, this tree)

| Check | Result |
|---|---|
| `flutter test` (full) | exit 0, `01:15 +3091 ~1: All tests passed!`, which is 3052 + 39. The only skip annotation in the suite is `test/profile_navigation_test.dart:39`. |
| New tests (counted from source) | `entry_rows_test` 14, `entry_identity_test` 19, `entry_identity_summary_test` 4, `db_seed_test` +2: 39 in all, which matches the rise. |
| `flutter analyze` | exit 1 (infos), `242 issues found.` = baseline; 11 warnings = baseline. `session_summary_screen.dart` 10, `session_core.dart` 1, every other touched file 0. |
| Done Criteria suites | Phase 1 `+171`, Phase 2 `+283`, Phase 3 `+18`, all exit 0 (as in the evidence). |
| Watch import | `test/watch_session_import_test.dart` `+45`; the full run includes it. `swift test` not re-run: no Swift or watch file changed. |
| Tree after mutations | 28/28 checksums identical; `git diff` byte-identical; `stats_progress_service.dart` identical to develop; stashes untouched. |

## 3. D-320 gate, mutations and probes

**Set bugs (evidence §3 plus reviewer re-runs):**
- **SP-1:** reproduced on both stores, fixed. Re-run: with the set delete reverted to the id-prefix delete,
  S-851 and S-852 fail on both stores, leaving reps 7 instead of 6. Restored: green.
- **SP-2:** reproduced on Hive, fixed. Re-run: with `updateEntryValue` reverted to the n-th raw row, Hive
  S-853 fails (`Expected 99, Actual 3`) and Mock stays green (insertion order). Restored: green.
- **SP-3:** reproduced on Hive per the evidence (`Expected 0 / Actual 3`); M2 fails Hive S-854 again.
- **SP-4:** reproduced on Hive per the evidence (`Expected 3 / Actual 11`); M2 fails Hive S-843 again.
- **SP-5:** reproduced on both stores per the evidence (created `…-1-extra-weight`). The first run missed
  it because the fixture differed from the plan. The fixture now matches the plan, which is legitimate.
- Dropped: none. Every shipped fix had a red run.

**Mutations** (copy aside, mutate, run, restore, checksum):

| # | Mutation | Failed | Failing value is the defect? |
|---|---|---|---|
| M2 | The shared rule reverted to raw store order (companions and set groups) | Hive S-842, S-843, S-844, S-853, S-854, S-860; S-857 on both stores | Yes. On Hive, entry 2 reads set 10's values (reps 11, 1100 m), the G1 key order. The Mock twins stay green, so the 12-entry parity tests really exercise Hive. |
| M3 | New-row number = count of numbers used (pre-F-5) | S-845, S-856 (state and Summary), S-860 | Yes. The add reuses number 2 and overwrites the stored 3000 m row. |
| M4 | Distance write keeps its own list (every distance row) | S-859 only | Yes. Tapping "Plank" writes row -0-, and row -1- keeps 400 m (`Expected 0.0, Actual 400.0`). That is F-6's class; 3a's S-815–S-823 stay green under it. |
| M5 | Stats day total counts every stored distance | Summary+Stats S-858 | Yes. "Distance: 5.50 km" is not found because the leftover now counts. The state-level S-858 does not read Stats, so D-321 is guarded on Mock only, as the plan split it. |

**Probes** (scratchpad tests, identical results on Mock and Hive):
- A, B, C, D and E back F-4 to F-8.
- M6a and M6b re-ran A, C and D on develop's code, to separate regressions from pre-existing defects.

## 4. Done Criteria per phase

| Phase | Criterion | Result |
|---|---|---|
| 1 | Targeted suites exit 0 | MET (`+171`) |
| 1, 2, 3 | Full suite ≥ 3052 + new, skip 1; analyzer ≤ 242 with per-file ceilings | MET |
| 1 | Diff within Phase 1 Predicted Files | NOT MET as written. `timer_manager`, `session_summary_builder` and `workout_state` (Phase 2 files) and `session_core.dart` changed in Phase 1, but evidence line 91 names only `session_core.dart`. Assumption Log 1 covers the move, and the union of all phases is fine. |
| 2 | Targeted suites exit 0 | MET (`+283`) |
| 2, 3 | Diff within Predicted Files | MET |
| 3 | `db_seed` + docs contract exit 0 | MET (`+18`) |
| 3 | Residue greps | MET in intent. Grep 1 prints nothing rather than `entry_rows.dart`, because that file builds its pattern without a raw string; grep 2 is empty. A broader sweep finds `entry_rows.dart` is the only phone id parser; the importer keeps its own, as allowed. |

## 5. Predicted Files deviations

- **`lib/state/workout/session_core.dart`** (not predicted): an import swap only, required because
  `session_core_entry.dart` is a part of it. Legitimate.
- **`lib/core/services/stats_progress_service.dart`** (predicted, unchanged): its pairing already calls
  `DistancePairing.forEntries`, now a delegate, so leftovers drop out with no edit. Legitimate; see N-1.
- **`observation_grouper.dart`, `timer_manager.dart`:** both predicted (Phase 1 item 2, Phase 2 item 2).
- **No unrequested production change.** Call sites checked:
  - `workout_session_screen.dart:976-1025, 1190, 1222`;
  - `workout_session_edit_mode.dart:207`;
  - `session_core_io.dart:296`;
  - `stats_progress_service.dart:569, 649, 967, 1038`;
  - `session_summary_service.dart:522`.
- **Plan size:** 484 lines, 23 past 461, within the 150-line budget. Copilot appended Progress, Assumption
  Log 1–4 and O-4.

## 6. Owner decisions and planned behaviour

| Item | Result | Evidence |
|---|---|---|
| D-320: set bugs fixed only where reproduced | PASS | SP-1 to SP-5 all red on unfixed code; SP-1 and SP-2 re-run by the reviewer; none dropped |
| Deleting a second set removes the right set | PASS | S-851, S-852 on both stores; M1 |
| An edit in a reopened 11–12-set session lands on the chosen set | PASS | S-853; M1b |
| Bodyweight sets 11–12 list in order | PASS | S-843; M2 |
| D-321: leftovers never count in Stats distance or pace | PARTIAL | Holds while the entry count stays put (S-858, M5). After an add, the leftover pairs with the new entry and counts (F-6). |
| D-322: nothing deleted, rewritten, migrated or renumbered | PARTIAL | Deletes take only the entry's own rows; the leftover stays stored; gaps are kept. Exception: F-4 overwrites a stored row in legacy-shaped data. |
| D-323: D-134 and D-135 confirmed, docs only | PASS | Series index :46; PR 2 plan :416, :446; nothing built |
| One rule for sets, timed and holds | PARTIAL | Holds everywhere except two paths that apply the wrong half of the rule: the set extra-weight overlay uses the timed rule (F-5), and hold/timed extra-weight creation uses the set rule (F-4). |
| Duplicated blocks get readable, addressable ids | PASS, with an edge | S-847; a suffixed source id collides (F-8) |
| A leftover is whatever the rule places after the last entry | PASS | `entry_rows.dart:119-131`; consequence F-6 |
| 3a pairing helper is a thin wrapper; `entryNumberInId` removed | PASS | `distance_source.dart` delegates; grep empty |
| F-5 carry-over: a Summary distance stays on its entry through delete and add | PASS | S-856 (state and Summary); M3 |
| F-6 carry-over: one shared distance-entry list | PASS | `getEffortDistanceEntries` feeds the Summary and both writes; M4 |
| N-4 carry-over: a lone old row doesn't read "Plank · 2" | PASS | S-859 |
| O-4 carry-over: the SQL CHECK accepts the app's rows | PASS | S-861 |
| Unchanged 3a behaviour: D-319, "est.", confirm clears "est.", 0 removes, Q9 pace | PASS | 3a S-805–S-808, S-815–S-823, S-831–S-837 green; S-858 pace 327 s/km |
| Architecture: interface only; Hive = Mock; theme tokens; SQL contract in step with the model | PASS | State uses `_repository` only; identical `_clonedRowId`; no styling change; CHECK matches `toMap` |
| Docs under 64 KiB, per the standard | FAIL | Sizes OK (largest 35.5 KB); standard: F-1 to F-3 |

## 7. Findings, most severe first

Format: severity, kind, where; the failure, as input → wrong output; the fix; where it's routed.

- **F-1: CRITICAL, MECHANICAL (Step 5c).** `data_models.md:513-515`.
  - **False claim:** the doc says `EntryRows` is "the one place the phone reads an observation id" and that
    "every phone reader and writer of entry rows goes through it".
  - **Actual:** the watch import parses ids itself (the doc's own :532). The routine-template defaults
    read the first raw row (`session_summary_builder.dart:265-297`); on Hive that can be another entry's.
  - **Fix:** delete both clauses, then point at `test/entry_rows_test.dart` and `test/entry_identity_test.dart`.
  - **Route:** this PR.
- **F-2: CRITICAL, MECHANICAL (Step 5c).** `stats_best_load_investigation.md:587-593` (open question 5).
  - **False claim:** the grouper's pattern at `observation_grouper.dart:49` can't read extra-weight ids, so
    every bodyweight effort falls back to sequential grouping at `:82`.
  - **Actual:** this PR removed both; `EntryRows` reads extra-weight ids. The doc has no scope block and no
    HISTORY label, so it misleads.
  - **Fix:** delete item 5 and point at `test/entry_rows_test.dart` (S-843).
  - **Route:** this PR.
- **F-3: CRITICAL, MECHANICAL (Step 5c-2).** Behaviour described with no test pointer.
  - **Missing pointers:**
    - `workout_state.md:103` (`updateEntryValue`) → S-853, S-857;
    - `workout_state.md:106` (`markSetSkipped`) → S-854;
    - `workout_state.md:203` (`deleteTimedEntry`) → S-855, S-860. That row also has 2 cells in a 3-column
      table, so its text renders under "Transition";
    - `data_models.md:532-534` (watch-import compatibility) → `test/watch_session_import_test.dart`, group
      `A-51`.
  - **Also:** `distance_source.md:3-12` declares a scope that omits `lib/core/utils/entry_rows.dart` and
    `getEffortDistanceEntries`, which the body now depends on. Widen it.
  - **Route:** this PR.
- **F-4: WARNING, MECHANICAL.** New extra-weight rows for holds and timed entries break D-325.
  - **(a) Observed:** `session_core_entry.dart:273-276` numbers them with the set rule (`_setNumberAt`),
    not highest-plus-one.
    - Input: a Plank with 2 holds, a legacy distance row #0 and an extra-weight row #1 (7 kg); set hold 2's
      added weight to 5 kg.
    - Wrong output, on both stores: row #1 is overwritten, so hold 1's 7 kg becomes 5 kg, hold 2 still reads
      0, and memory holds a duplicate id (probe E).
    - Reach: the live screen writes a hold's extra weight on every log (`workout_session_screen.dart:1019-1025`).
  - **(b) By code reading:** with no fill for earlier unpaired entries, a value typed on the later of two
    row-less entries shows on the earlier one.
  - **(c) Cosmetic:** the distance write numbers from the entry's position when nothing is numbered
    (`:371`), where D-325 says 0.
  - **Fix:** use the set number only for `set` efforts. For holds and timed entries, number past the highest
    and fill earlier entries, as `_writeEntryDistance` does. Use `EntryRows.nextNumber` at `:371`. Add
    probe E's scenario on both stores. This also makes `data_models.md:526-528` true again.
  - **Route:** this PR.
- **F-5: WARNING, MECHANICAL.** `session_summary_builder.dart:394-404`: the bodyweight extra-weight overlay
  pairs rows by order (the timed rule), not by each set's own number (D-324's set rule, D-327).
  - Input: bodyweight sets 0–2, with extra weight only on sets 1 and 2 (1 kg, 2 kg).
  - Wrong output, on both stores: the session list shows [1, 2, 2] kg, while Stats and PRs read [none, 1, 2].
    Editing set 0 then writes set 0's own row (probe A).
  - Pre-existing: develop showed [1, 2, 2] on Mock and [1, 2, 0] on Hive (M6a). Not a regression, but D-327
    put it in scope.
  - **Fix:** when every row is numbered, read each set group's own extra-weight row; keep the positional
    overlay only on the legacy fallback. Add probe A's scenario on both stores.
  - **Route:** this PR.
- **F-6: WARNING, DESIGN.** A leftover is adopted by the next added entry.
  - Cause: timed companions pair by position (`entry_rows.dart:119-131`), and new rows are numbered above
    every row, leftovers included (`session_core_entry.dart:87`).
  - Input: S-858's own fixture (1 run; distance rows #0 = 5000 m and #7 = 1000 m leftover); add an entry
    in Edit Session.
  - Wrong output: the new entry reads 1.00 km, in the Summary and after reopening. Stats counts 6.00 km for
    the day, contrary to D-321 and AC-5 (probe C).
  - With develop's numbering the same data gave [5000, 0] (M6b), so it's a regression for this shape.
    Leftovers from the old double-delete bug are on `main` (`timer_manager.dart:516` there); develop
    misplaced those too.
  - **Fix:** needs a rule decision (keep new rows ahead of leftovers, or an explicit instance link) plus
    scenarios.
  - **Route:** follow-up.
- **F-7: WARNING, DESIGN.** A number group with no reps row counts as a set (`entry_rows.dart:152-163`).
  - Input: a bodyweight effort with sets #0 and #2, plus an old stray `…-1-extra-weight` row (what SP-5's
    bug wrote).
  - Wrong output: develop showed 2 sets, with 5 kg on set 2 (M6a). Now there are 3: a 0-rep phantom set
    carrying 5 kg sits between them, on both stores (probe D).
  - Rare: current phone and watch creation always writes a bodyweight set's extra-weight row
    (`logged_entry_rows.dart:73`).
  - **Fix:** decide whether a group needs a reps row to be a set; the rule's readers and writers change
    together.
  - **Route:** follow-up.
- **F-8: SUGGEST, MECHANICAL.** `_clonedRowId` (`hive_workout_repository.dart:2914`,
  `mock_workout_repository.dart:2098`) drops a 3a suffix.
  - Input: duplicate a block holding S-846's rows (`…-3-distance` plus `…-3-distance-9000`).
  - Wrong output: both land on one id, so the copy has 4 rows for 5 entries, and its 2000 m moves from
    "· 4" to "· 3" (probe B). Exposure: develop-only data.
  - **Fix:** replace only the effort-id part, as D-329's wording says; add a suffixed row to S-847.
  - **Route:** this PR.
- **F-9: SUGGEST, MECHANICAL.** Test tightening; optional.
  - `entry_rows_test.dart:321`: S-847 checks the timed copy's row count only, and its fixture lacks
    `entered`.
  - `entry_identity_test.dart:197-204`: S-855 counts the stored rows without naming them.
  - `entry_identity_test.dart:417`: the uniqueness assertion can't fail, because both stores key rows by id.
  - `entry_identity_test.dart:251-267`: S-856's reopened half. A 2 ms real delay in its plain `test()`
    avoids the O-4 same-millisecond collision and allows the full five-entry assertion.
  - **Route:** this PR.
- **N-1: NIT.** `stats_progress_service.dart:645-648`: the comment cites the superseded D-312 and says the day
  total counts "every stored distance", which contradicts D-321.
- **N-2: NIT.** Plan and evidence hygiene:
  - the plan header still says "not started", and the phase item checkboxes are unticked;
  - Assumption Log 2 runs 4 lines (budget §2 allows 3);
  - evidence line 91's Predicted Files claim (see §4);
  - evidence lines 199-202 are template leftovers;
  - `db_seed_test.dart:190`: the `effortId` parameter is never passed.

## 8. Split (budget "At review")

- **This PR, one round, no re-review:** F-1, F-2, F-3, F-4, F-5, F-8, N-1, N-2; F-9 optional.
- **Follow-up PR via conductor-v2 (don't grow this plan):**
  - F-6 and F-7: rule decisions, each needing scenarios;
  - O-4 (the instance-id collision);
  - the routine-template defaults that bypass the rule (`session_summary_builder.dart:265-297`, a non-goal
    here);
  - best folded into 3b with O-2.

## 9. Assumption Log rulings

1. **RATIFIED.** Same store-order defect as S-843 (S-844 red on Hive, as M2 confirms); no new scope.
2. **RATIFIED.** Matches D-324's own effort-wide wording, so the reader and the writer agree.
3. **RATIFIED.** D-326 keeps the positional delete for the legacy fallback.
4. **RATIFIED, conditionally.** O-4 only fires when two operations land in the same millisecond, which
   happens in tests, not in use. Keep O-4 open for 3b; F-9 lets the reopened half assert the full list.

## 10. Documentation and conventions

- DOC FALSIFICATION: REJECT — `data_models.md:513-515` — every reader and writer goes through `EntryRows` —
  now the importer and the template defaults don't → delete the clauses, point at tests (F-1).
- DOC FALSIFICATION: REJECT — `stats_best_load_investigation.md:587-593` — the old pattern and the
  sequential fallback — now gone → delete item 5, point at S-843 (F-2).
- DOC FALSIFICATION: REJECT — `data_models.md:526-528` — every new row takes the highest number plus one
  (0 when there's none) — now false for hold/timed extra weight and the distance write's start →
  the code fix in F-4 resolves it.
- DOC FALSIFICATION: SCOPE — `distance_source.md:3-12` — declared scope narrower than the content;
  verified anyway (F-3).
- DOC FALSIFICATION: PASS for the other 34 of 38 implicated docs (26 have no scope declaration).
  - Swept for the removed symbols: `entryNumberInId`, `_nextSetEntryIndex`, `_distanceEntryCount`, the two
    Summary pairing helpers and the old regex.
  - Swept for the changed claims: the D-313 suffix, O-3, raw-order pairing, clone UUIDs and the exactly-one
    CHECK.
  - Touched docs read in full diff.
- DOC STANDARD: REJECT — `workout_state.md:103, 106, 203` and `data_models.md:532-534` — behaviour without a
  test pointer (F-3).
- DOC STANDARD: PASS — none of the seven prohibited classes was added. The cap is named as
  `WorkoutConstants.maxEntriesPerEffort`, not restated, and the old regex literal was removed from
  `data_models.md:54`.
- **Conventions:**
  - PASS (5 rules): units and canonical storage, theme tokens only, effort kind drives analytics,
    timestamps are source data, reuse the canonical owner;
  - N/A (2 rules): card chrome and headers, instrument panel (no UI chrome or UX change).
