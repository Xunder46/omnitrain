# Evidence: plan 124

- Baseline `flutter analyze`: 181 issues; after: 181.
- Phase 0 (new test file, before the fix): `+13 -10`. Red: S-12401, S-12405, S-12406, S-12407 (Mock + Hive), S-12408 "one read per load", S-12411 p-1. Green: the guards.
- Phase 1 (after the fix): new file all green (25 tests incl. empty-string Focus), calendar suites + ui_standards + docs contract green (`+161`, `DaySessionListScreen` group `+15`), invariant grep empty.
- Mutations (lead, in place, restored by `cmp`): routineFocus ignored -> killed (`-9`); empty-string guard removed -> first survived, killed after adding the empty-Focus test (`-2`); `any` guard forced true -> killed (`-1`); subtitle branch off -> killed (`-1`); `p.modality ?? routineFocus` swap -> equivalent (routine plans store null by design).
- Docs: `calendar_periods.md` 13746 B, `my_routines.md` 28545 B (< 53 248); small additive diffs.
- Review: APPROVE WITH FIXES; fixed: unfounded "finished session keeps its Focus" sentence reworded, p-7 exclusion assertion added. Not done: orphan title "Custom Routine" widget test (existing untouched behaviour); `my_routines.md` line sits under "Deleting a Routine" (no planning section exists).
- Written by the lead: `models.dart` doc comment (data-layer file outside the builder's scope).
