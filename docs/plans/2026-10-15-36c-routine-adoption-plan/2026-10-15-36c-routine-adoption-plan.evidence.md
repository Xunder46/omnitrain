# Evidence — plan 36c (routine start sync, PR 3)

Phase D (docs keeper), 2026-10-15. Every claim below was checked against the
files named this run.

## Baselines (from the lead's P1 report, quoted in the brief)

| Check | After P1 | Before P1 |
| --- | --- | --- |
| `flutter test` (full suite) | `+4723 ~1` | `+4709 ~1` |
| `flutter analyze` | 182 | 182 (unchanged) |
| `swift test` (`watch/watchos`) | 592 | 592 (unchanged, no Swift change) |

## Red before green

P1 was written red-first (the plan's Phase P1 item 1: the new
`test/watch_routine_adoption_test.dart` with S-3640/S-3641/S-3643/S-3644/S-3648
at the base, where the triple is null and no planned rows are written). The
lead did not keep the red run's output, so no red table is reproduced here;
the red state is attested by the plan's scenario list ("Fails today: all three
fields are null", "Fails today: zero rows") and by the proof mutations below,
each of which re-produces a red verdict on the shipped code.

## Proof mutations (the lead's ten, each restored byte for byte)

Each row is a run of `flutter test test/watch_routine_adoption_test.dart
test/watch_session_adoption_bridge_test.dart` with one mutation applied to
`lib/state/watch/watch_session_adoption_bridge.dart`; the count is the failing
tests the run reported. All ten were restored byte for byte after their run.

| # | Mutation | Failing tests |
| --- | --- | --- |
| R1 | drop `intent: routine == null ? null : 'routine'` from `_adopt` | +36 −2 |
| R2 | drop `title: routine?.template.name` from `_adopt` | −2 |
| R3 | drop `routineTemplateId: routine?.template.id` from `_adopt` | −3 |
| R4 | `_createPlannedRows` set count `maxSetIndex + 1` → `maxSetIndex` (short by one) | −7 |
| R5 | default reps 10 → 0 | −2 |
| R6 | default load 0.0 → 1.0 | −2 |
| R7 | targets read for the wrong id (raw slot id instead of the stripped effort id) | −7 |
| R8 | match on any slot only (drop the every-id containment check) | −1 |
| R9 | load always known (`exerciseHasLoad: true` unconditionally) | −1 |
| R10 | non-`set` efforts get planned rows (drop the `_effortKind == BlockTypes.set` gate) | −1 |

## Doc-claim → test table

Every behaviour sentence the Phase D docs added, tied to the test that asserts
it (group and test name read from the test file this run).

| Doc, sentence | Test file · group · test |
| --- | --- |
| `docs/watch_session_sync.md` (D-2): an adopted ladder that is a run of one of the phone's routines links to it and its `set` efforts start with the routine's planned rows | `test/watch_routine_adoption_test.dart` · `Mock` · `S-3640 the snapshot adopts as the routine the wrist started`; `S-3641 the adopted effort holds the template's planned sets` |
| `docs/watch_session_sync.md` (D-2): a wrist free session stays free — no routine title, intent or link | `test/watch_session_adoption_bridge_test.dart` · `S-1 a wrist snapshot becomes the phone's in-progress session` (slots `sl-1`/`sl-2`, no `sx-` prefix; asserts `modality` null under the D-7 reason) |
| `docs/watch_session_sync.md` (D-2): an unmatched ladder adopts as a free session | `test/watch_routine_adoption_test.dart` · `Mock` · `S-3644a no template covers the ladder: a free session as today` |
| `docs/watch_session_sync.md` ("What does not sync"): a routine started on the wrist opens on the phone as that routine — template name, `intent = 'routine'`, `routineTemplateId`, planned rows from the phone's current template | `test/watch_routine_adoption_test.dart` · `Mock` · `S-3640 the snapshot adopts as the routine the wrist started`; `S-3641 the adopted effort holds the template's planned sets`; `S-3642 the phone's current routine is the source of truth` |
| `docs/watch_session_sync.md` ("What does not sync"): a ladder no template covers adopts as a free session exactly as before | `test/watch_routine_adoption_test.dart` · `Mock` · `S-3644a no template covers the ladder: a free session as today`; `S-3644c a mixed ladder: a free session as today`; `S-3648 a routine deleted before the snapshot: a free session` |
| `docs/my_routines.md` (template-to-session): the wrist-start sentence — the same triple and rows a phone-started routine session gets | `test/watch_routine_adoption_test.dart` · `Mock` · `S-3640 the snapshot adopts as the routine the wrist started`; `S-3641 the adopted effort holds the template's planned sets`; `S-3642 the phone's current routine is the source of truth` |
| `docs/my_routines.md` (template-to-session): a wrist ladder no template covers adopts as a free session | `test/watch_routine_adoption_test.dart` · `Mock` · `S-3644a no template covers the ladder: a free session as today`; `S-3648 a routine deleted before the snapshot: a free session` |

## Known limits stated in the docs (and where they come from)

- Routine efforts appended to an already-adopted EMPTY wrist session are not
  planned (the wrist's `startFromRoutine` absorb branch): plan D-5, not in this
  plan; no doc sentence claims otherwise.
- Timed / hold / round planned rows are not created: pinned by
  `test/watch_routine_adoption_test.dart` · `Mock` ·
  `S-3641 the adopted effort holds the template's planned sets` (the timed
  `sx-eff-plank` holds no rows).
- A template with more efforts than the wrist's ladder still matches (the
  ladder never gains an effort): pinned by `test/watch_routine_adoption_test.dart`
  · `Mock` · `S-3642 the phone's current routine is the source of truth`
  (the added `eff-row` is not adopted).

## Files changed in Phase D

- `docs/watch_session_sync.md` — the "What does not sync" bullet rewritten
  (the old "plan 36c takes that. No test pins the wrist-started case."
  sentence removed); one sentence added to the D-2 decision.
- `docs/my_routines.md` — the wrist-start sentence added to the
  template-to-session section (`RoutineSessionService.buildSessionFromTemplate`).
- `docs/plans/2026-10-15-36c-routine-adoption-plan/2026-10-15-36c-routine-adoption-plan.evidence.md` — this file.



## Addendum (lead, after the review)

- Hive parity: the new test file now runs every scenario under `Mock` and `Hive`; the Hive run found that S-3653's "first target in `getTemplateTargets` order wins" depended on the store (Mock insertion order, Hive box order). Fixed by a store-independent pick (explicit set index beats null, then the lowest id); `S-3653`, `S-3653b`, `S-3653c`.
- Final counts: Flutter suite `+4741 ~1` at the end (was `+4709 ~1` after 36b); analyze 182; `swift test` 592 (no Swift change).
- Mutations re-run on the final code, each restored byte for byte: R1 no intent (-4), R2 no title (-4), R3 no routine link (-6), R4 set count short by one (-16), R5 default reps 0 (-4), R6 default load 1.0 (-6), R7 targets read for the wrong id (-16), R8 match on any slot only (-2), R9 load always known (-2), R10 non-set efforts get rows (-2), R11 explicit index loses to null (-2, after `S-3653c`; it survived before it), R12 highest id wins ties (-2).
