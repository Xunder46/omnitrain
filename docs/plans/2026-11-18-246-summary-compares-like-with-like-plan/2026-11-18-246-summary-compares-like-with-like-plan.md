# Plan 246 — The summary's up/down figures compare with the last run of the same routine or type, and say which

Review item 5 (owner suggestion, accepted 2026-11-18: "compare with the last run of the same routine or type, say which, and hide it otherwise").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

Today `SessionSummaryService.compareGroupsToPreviousSession` (`lib/core/services/session_summary_service.dart:458`) compares each group with the latest finished session of ANY kind, so a leg-day summary can show a big drop against a short run. After this change the comparison is against the last finished session that is like this one, and the summary says which:

- A session started from a routine (`TrainingSession.routineTemplateId` set) is compared with the last finished session of the SAME routine.
- Any other session is compared with the last finished session of the same type: no routine and the same `modality` (a null modality, Free Training, matches only other null-modality sessions with no routine).
- A group figure is shown only when the like session has that group too; otherwise the figure is hidden (the existing `—`).
- When at least one figure is shown, one muted line above the group cards names the basis: `Compared with your last Push Day (Nov 12)` for a routine (the routine's name is the session title), `Compared with your last Resistance / Lifting session (Nov 12)` for a type.
- No like session, or nothing to show: no line, every figure `—`.

Acceptance: S-24601..S-24608 (service) and S-24611..S-24613 (screen) green, "fails without" ones red at the base commit; the four existing tests of `compareGroupsToPreviousSession` in `test/services_test.dart` updated to the new return type and still green; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base commit's failing set (this Windows machine has 1075 environment failures at base; compare by name); Docs delta applied.

## What the user sees

- A strength session started from `Push Day` shows its volume change against the last `Push Day`, not against yesterday's run, and a line above the cards says so.
- A free session shows changes against the last session of the same type, never against a routine session.
- Nothing comparable yet: dashes and no line.
- To SEE it: finish the same routine twice with different weights; the second summary shows the arrow and the line.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-24601 | `compareGroupsToPreviousSession(currentSession, currentSummary)` keeps its name and parameters and returns a new `GroupComparison` (`deltas`: `Map<String, GroupDelta>`, `basis`: `ComparisonBasis?`) defined in `lib/core/models/session_summary.dart` next to `GroupDelta`. `ComparisonBasis` has `isRoutine` (bool), `label` (String), `previousStartedAtMs` (int). | `session_summary_service.dart:458`, `session_summary.dart:143` |
| D-24602 | The like session is chosen from `getAllSessions()` as today (finished: `endedAtMs != null`, not the current id, `startedAtMs < current.startedAtMs`, newest first), then filtered: routine current -> `s.routineTemplateId == current.routineTemplateId`; otherwise `s.routineTemplateId == null` (an empty string counts as null) and `s.modality == current.modality`. | `routine_session_service`/`my_routines_screen.dart:206` (a routine start writes `routineTemplateId`, `title: template.name`, `modality: focusModality`), `calendar/day_session_list_screen.dart:293` |
| D-24603 | `basis.label`: routine -> the CURRENT session's `title` when it is not blank, else `this routine`; type -> `ModalityDisplay.getName(current.modality)`. `basis` is null when there is no like session. | `modality_display.dart:getName` |
| D-24604 | A group the like session lacks (its `_computeGroupStats` map has no entry for the key) gives `GroupDelta(delta: null, hasPrevious: false)`; a group it has gives the delta as today (a present key with 0 is a real 0). | `session_summary_service.dart:_computeGroupStats` |
| D-24605 | Screen: `_loadAsyncData` keeps `comparison.deltas` in `_groupDeltas` and `comparison.basis` in a new field `_comparisonBasis`. `_buildGroupCards` adds, right after its first `SizedBox(height: 16)`, a caption `Text` (key `summary_comparison_basis`, `labelSmall`, `onSurfaceVariant`) when `_comparisonBasis != null` and some `_groupDeltas` value has `delta != null`: text `Compared with your last <label> (<date>)` for a routine and `Compared with your last <label> session (<date>)` for a type, date from the screen's `_formatDate`. | `session_summary_screen.dart:1157,1388` |
| D-24606 | `compareToPreviousSession` (the `VolumeComparison` method, not rendered) is left as it is. | docs/data_models.md |

## Scenarios

Fixtures. Level A (service, new file `test/summary_comparison_basis_test.dart`, Mock repository, plain `test()`): copy the seeding helper `_seedCompletedSetSession` and `_freshRepo` from `test/services_test.dart`, extend with `routineTemplateId`, `modality`, `title`; every session has one set exercise; volumes are set by reps x weight; the current session's `SessionSummary` is built by hand with `totalVolume` as in `services_test.dart` (comparison logic only). Times: S1 = 1000, S2 = 2000, S3 = 3000, current = 5000 (ended 6000).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24601 | Current: routine `t1` (title `Push Day`), strength volume 500. Earlier: S2 free session (no routine, modality `resistance_lifting`, volume 1000), S1 routine `t1` (volume 400). | `deltas['strength'].delta == 100` (500-400, not 500-1000); `basis.isRoutine`, `label 'Push Day'`, `previousStartedAtMs 1000`. | the base compares with S2 (delta -500) and has no basis |
| S-24602 | Current: routine `t1`. Earlier: only a free session. | `deltas['strength'].hasPrevious == false`, `delta == null`; `basis == null`. | the base compares with the free session |
| S-24603 | Current: routine `t1`. Earlier: only a routine `t2` session. | same as S-24602. | same |
| S-24604 | Current: free (no routine), modality null. Earlier: S3 routine `t1` session with modality null, S1 free session modality null (volume 400). | compares with S1: delta 100, `basis.isRoutine == false`, `label 'Free Training'`. | the base picks S3 |
| S-24605 | Current: no routine, modality `resistance_lifting`. Earlier: S3 no routine modality `sports`, S2 routine `t1` modality `resistance_lifting`, S1 no routine `resistance_lifting` (volume 400). | compares with S1 only; `label 'Resistance / Lifting'`; `previousStartedAtMs 1000`. | the base picks S3 |
| S-24606 | Current: routine `t1` with strength 500 AND cardio (timed) 600000 ms. Earlier: S1 routine `t1` with cardio only (300000 ms). | `deltas['cardio'].delta == 300000`, `hasPrevious true`; `deltas['strength'].hasPrevious == false`, `delta == null`. | the base gives strength a delta against 0 |
| S-24607 | Current: routine `t1`. Earlier: S3 routine `t1` UNFINISHED (`endedAtMs` null), S2 routine `t1` finished started AFTER the current (start 7000), S1 routine `t1` finished (volume 400). | compares with S1. | passes both ways on purpose (mutations: the finished check removed; the before-current check removed) |
| S-24608 | Current: routine `t1` with `title` null; and a second case with title `   `. | `label 'this routine'` in both. | the base has no basis |

Level B (screen, new file `test/summary_comparison_caption_screen_test.dart`, Mock only): copy the harness of `test/summary_exercise_list_screen_test.dart` (seeding, `_pumpSummary`).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24609 | Added after review. Current: `routineTemplateId ''`, modality `resistance_lifting` (500). Earlier: S2 no routine (null) same modality (400), S1 `routineTemplateId ''` same modality (300). | the empty id is no routine: compares with S2: delta 100, `basis.isRoutine == false`, label `Resistance / Lifting`, `previousStartedAtMs 2000`. | passes both ways on purpose (mutation: `_routineIdOf` returns the id as it is) |
| S-24611 | Routine `t1` titled `Push Day` finished twice (volumes 400 then 500), historical summary of the second. | the text `Compared with your last Push Day (<date of the first>)` is found, date built in the test with the same short-date rule as the screen (month abbreviation and day, read `_formatDate`); an up arrow chip exists. | no caption exists |
| S-24612 | The same routine, finished once. | `find.byKey(Key('summary_comparison_basis'))` finds nothing; no text containing `Compared with`. | passes both ways on purpose (mutation: caption shown whenever a basis exists, ignoring `delta`) |
| S-24614 | The same routine twice, the OLDER finished session has no effort at all (an empty finished session), the newer has a strength set; open the newer. | a like session exists (basis) but it has no group, so every figure is hidden: `find.byKey(Key('summary_comparison_basis'))` finds nothing. | passes both ways on purpose (mutation: the caption shown whenever a basis exists, the `anyFigure` check removed) |
| S-24613 | A free resistance session after an earlier free resistance session. | the text `Compared with your last Resistance / Lifting session (<date>)`. | no caption exists |

## Input-reality checklist

1. Writers: `routineTemplateId`, `title`, `modality`, `intent` are written at session creation by `my_routines_screen.dart:206` (phone routine start), `calendar/day_session_list_screen.dart:293,361` (a planned routine), the watch bridge (`watch_session_adoption_bridge.dart:1080-1129`, reads `routineTemplateId` from the payload) and `watch_session_importer.dart:717`. A routine session's modality is the routine's focus snapshot, so a routine session and a free session of the same modality are different kinds by D-24602. The routine's name is a title snapshot: a routine renamed later keeps the old title on old sessions; the caption uses the CURRENT session's title.
2. Lifecycle: unfinished sessions are skipped; rolling sessions compare as any other session by their routine/modality; deleted sessions are gone from the list; a session edited later changes its stored stats and so the next comparison (no cache).
3. Settings: none read by the comparison; the displayed weight unit already follows the Weight unit setting.
4. Time: "last" is by `startedAtMs`; a session dated in the future of the current one is ignored (S-24607); several sessions in one day are ordered by start time.
5. Cost: one `getAllSessions()` read as today, plus the same `_computeGroupStats` read for one session as today.
6. Words: old wording swept (grep in Docs delta); the caption is new copy.
7. Slot competition: `n/a`.

## Phases

1. **P1 builder-app**, scope `lib/core/models/session_summary.dart`, `lib/core/services/session_summary_service.dart`, `test/summary_comparison_basis_test.dart` (new), `test/services_test.dart` (update the four existing calls of `compareGroupsToPreviousSession`: read `.deltas`, same assertions): D-24601..D-24604, S-24601..S-24608. No full suite.
2. **P2 builder-app** (after P1), scope `lib/features/session/session_summary_screen.dart`: D-24605, exact code in the brief. No full suite.
3. **P3 builder-app** (after P2), scope `test/summary_comparison_caption_screen_test.dart` (new): S-24611..S-24613. No full suite.
4. **P4 lead**: summary and services test files, full suite compared with the base failing set, analyze, mutation pass, `crew-docs-keeper`, reviewer.

## Readers

`test/services_test.dart` group `compareGroupsToPreviousSession` (four calls, P1 updates them), `test/data_tracking_fixes_test.dart` (calls `compareToPreviousSession`, the untouched `VolumeComparison` method: stays green untouched). Screen readers: the summary test files from plan 245 (`session_summary_*`, `header_standardization_test`, `screen_widget_test` group `SessionSummaryScreen`) must stay green: the caption adds one `Text` only when a comparison exists, and those fixtures have no like session (check by running them).

## Mutation list (lead)

(a) routine filter removed (S-24601, S-24603); (b) type filter ignores modality (S-24605); (c) type filter lets routine sessions through (S-24604, S-24605); (d) finished check removed (S-24607); (e) before-current check removed (S-24607); (f) group missing in the like session gets 0 not null (S-24606); (g) label fallback removed (S-24608); (h) caption shown when basis exists regardless of delta (S-24612); (i) routine/type wording swapped (S-24611, S-24613).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/data_models.md` | MODIFIED | Per-group comparison chip data vs previous session | Per-group comparison chip data vs the last comparable session (same routine, else same type) | S-24601 |
| `docs/state_management/services_and_utils.md` | MODIFIED | Finds the most recent previous session; | Finds the last finished session of the same routine, or with no routine of the same type; | S-24601, S-24605 |
| `docs/state_management/services_and_utils.md` | MODIFIED | `Map<String, GroupDelta>` | `GroupComparison` | S-24601 |
| `docs/README.md` | MODIFIED | per-group comparison vs the previous session | per-group comparison vs the last comparable session | S-24601 |
| `docs/session_summary.md` | MODIFIED | Existing comparison delta chip from GroupDelta | Comparison delta chip from GroupDelta, against the last like session | S-24601 |
| `docs/session_summary.md` | ADDED | - | `## Comparison basis` | S-24611 |

The keeper adds a `## Comparison basis` section to `docs/session_summary.md` (after `## Group Cards`): the like-session rule (routine, else type), the hidden-figure rule (S-24602, S-24606), the caption wording and when it shows (S-24611..S-24613), each sentence citing its test. Stale-term sweep (done by the lead): `grep -rIn "previous session\|most recent completed\|compareGroupsToPreviousSession\|GroupDelta\|hasPrevious" docs` outside plans, history, releases: `data_models.md` 361-362, `README.md` 64, `session_summary.md` 255, 403, 420, 477, `services_and_utils.md` 68; rows above cover the wording ones, the others are names that stay.

## Open items

1. (owner) The routine's name in the caption is the name the routine had when the session started (a renamed routine reads its old name on old sessions; the caption uses the current session's, so it is always the name you started it under).
2. (owner) A routine started from the calendar plan or from the watch compares like any routine start. A session started free and later saved as a routine is still a free session for comparison.
3. Sessions finished before this change compare as they now would: nothing is stored.

## Predicted files

`session_summary.dart` (+30), `session_summary_service.dart` (+45 -25), `session_summary_screen.dart` (+30), `summary_comparison_basis_test.dart` (~300), `summary_comparison_caption_screen_test.dart` (~200), `services_test.dart` (small), docs (~30 lines across five).

## Progress

- [x] Seeded
- [x] P1 service and model (P1a), service tests (P1b, 10 tests incl. S-24609 added after review)
- [x] P2 screen caption
- [x] P3 screen tests (4, S-24614 added after the mutation pass)
- [x] P4 verify (full suite: no new red against the base failing set), mutation pass (11 of 11 killed), docs (keeper), review (0 blocker, 1 major, 3 minor: major fixed by test, 2 doc minors fixed, 1 minor recorded)
- [ ] (owner) look at it on a device, Open items 1 and 2

## Assumption Log

- 2026-11-18: base commit in `.work/item5/base.txt` (cd2fc178), branch `claude_develop`. Unrelated uncommitted files (`test/food_catalog_load_test.dart`, `macos/Flutter/GeneratedPluginRegistrant.swift`) are never staged.
- 2026-11-18: ids S-246xx: none found in `test/`, `docs/`, `watch/`.
- 2026-11-18: the method keeps its name `compareGroupsToPreviousSession` (technical choice: four doc sites and four tests name it; "previous" still reads right for "previous like session").
- 2026-11-18: no architect run (seed has phases, plan-lint clean), as plans 244 and 245.
- 2026-11-18: this Windows machine fails 1075 tests at the base commit (see the feedback file); the check is the failing-name set against the base commit, not "all green".

- 2026-11-18: full suite on this Windows machine: +7043 passed, 1073 failed; the failing-name set contains nothing that is not in the base commit's failing set (stored from the plan 245 base run).
- 2026-11-18: review finding 2 (Minor, not changed): two like sessions with an identical `startedAtMs` have an unspecified winner; same behaviour as before this plan and no real session pair shares a start to the millisecond.
- 2026-11-18: review minors 3 and 4 fixed by the lead (the `GroupDelta` row in `docs/data_models.md` now names `GroupComparison` and `ComparisonBasis` in the same row; the service row in `docs/state_management/services_and_utils.md` says what it returns). `data_models.md` is kept one line shorter than a new row would be to stay under the 80% size band on the repo's LF copy (51,948 bytes at base).
- 2026-11-18: mutation script note: the first pass aimed the finished-check mutant at `compareToPreviousSession` (same text, first occurrence); the lead re-aimed it at the second occurrence and it was killed.

## Feedback

(none yet)
