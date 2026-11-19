# Plan 174 evidence — the phone's decisions reach the diagnostics log

Baselines and observed runs for `2026-11-14-174-phone-adoption-diagnostics-plan.md`.
Every count below is pasted from a gateway run, not restated from memory.

## Baselines (HEAD 7e570d0c)

- `gateway.sh lint` (flutter analyze): **181 issues**, all pre-existing info notices (the
  repo-wide baseline the plan names).
- Full `gateway.sh test` before this run: `+7635 ~4` (skipped) — the plan's baseline.

## Phase 1 — the seam

Working tree after the four seam files and the structural guard:

```
lib/core/services/watch_session_importer.dart      |  6 +++++
lib/state/watch/watch_session_adoption_bridge.dart |  8 +++++++
lib/state/watch/watch_session_inbox.dart           |  6 +++++
lib/state/watch/watch_sync_wiring.dart             |  6 +++++
test/diagnostics_wiring_source_test.dart           | 26 ++++++++++++++++++++++
5 files changed, 52 insertions(+)
```

Focused run (`test/diagnostics_wiring_source_test.dart`): `+3: All tests passed!`

prove-red, guard `the wiring passes diagnostics to the adoption bridge and the inbox`:

```
gateway: prove-red: RED AT HEAD (exit 1)
  Expected: contains 'diagnostics: diagnostics'
    Actual: 'final adoption = _WiringAdoptionBridge(\n ... validator: validator,'
     Which: does not contain 'diagnostics: diagnostics'
  `final adoption = _WiringAdoptionBridge(` must receive the graph's diagnostics log,
  or the phone records no decision about a wrist session (D-17401)
```

Note on the guard's scan: the first `);` after the constructor call sits inside the call's own
comment ("(plan 129, D-8973);"), so the terminator is the call's closing `\n  );`.

## Phase 2 — the bridge's six kinds

Red before implementation (`test/watch_session_adoption_bridge_test.dart`, new group
`plan 174 the log records what the bridge decided`): `+46 -11`, every new test failing on the
empty log:

```
S-17401 ... Expected: ['adopted status=active start=2026-10-05T12:00:00.000Z']  Actual: []
S-17407 ... Expected: ['from=2026-10-05T18:00:00.000Z to=2026-10-05T13:05:00.000Z who=lifecycle']  Actual: []
S-17409 ... Expected: ['who=end_session instant=2026-10-05T12:30:00.000Z status=completed']  Actual: []
S-17410 ... Expected: ['who=held']  Actual: []
```

Green after the notes (`gateway.sh test test/watch_session_adoption_bridge_test.dart`):
`+57: All tests passed!` (46 existing + 11 new).

### Mutations (the file cannot compile at HEAD — the seam parameter is new)

1. Every detail gains a token — `_note` was changed to
   `diagnostics?.note(kind, session: session, detail: '$detail x');`
   (original: `detail: detail`).
   Result: `+0 -11` — **all eleven** new tests red, each on its exact line
   (`... start=2026-10-05T12:00:00.000Z x`). Restored, re-run green.
2. Dedupe off — `if (!_notedAdoptions.add('$sessionId $detail')) return;` became a bare
   `_notedAdoptions.add(...)` (original line kept beside it).
   Result: `+8 -3` — exactly S-17402, S-17403 and S-17412 red (`Expected: an object with length
   of <1>`, actual the repeated lines); the other eight green. Restored, re-run green.
3. Privacy — the adopted note gained `' title=${target.currentSession?.title}'`.
   Result: `+9 -2` — S-17401 and S-17412 red
   (`Actual: ['adopted status=active start=... title=null']`), which is the whole line, so no
   session content beyond the id can be added without a test failing. Restored, re-run green.

## Phase 3 — the importer's notes

Written red first (`test/watch_session_import_test.dart`, new group `import diagnostics notes`):
`+0 -6`, every test failing `Actual: []` — no note reached the log.

Green after the notes (`gateway.sh test test/watch_session_import_test.dart`):
`+91: All tests passed!` (85 prior + 6 new).

Where the six kinds come from: `_createSession` notes `end_clamped` (when `_End.clampedFromMs` is
set, computed in `_End.parse` from `boundedEndMs`), `session_row_created` (`path=import`) and
`end_applied` (`who=import instant=… status=…`); `_catchUpEnd` notes `end_clamped` only when the
bound moved the end (`bounded != latest`) and `end_applied` with the new instant; `_mergeHeld` and
`_Pass.run` note `session_start_corrected` (`path=merge` / `path=import`) when `_carryWristStart`
returned a corrected row.

### Mutations (same reason as Phase 2: the tests name the new `diagnostics:` parameter)

1. Instant helper broken — `_noteIso` body became `=> 'MUTANT'`
   (original: `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();`).
   Result: `+0 -6` — all six red, each on its own expected detail
   (`Actual: ['from=MUTANT to=MUTANT who=import']`). Restored, re-run green.
2. Path label — the merge site's `path: 'merge'` became `path: 'import'`.
   Result: `+0 -1` on S-17406 A (`Actual: ['... path=import']`) while S-17406 B stayed green, so
   the two paths are told apart by the log. Restored, re-run green.
3. Clamp record dropped — `clampedFromMs: boundedEndMs == endedAtMs ? null : endedAtMs` became
   `clampedFromMs: null`.
   Result: S-17408 red (`Expected: ['from=…17:00… to=…11:05… who=import']`, `Actual: []`), S-17408 b
   unaffected (its own catch-up path). Restored, re-run green.

## Phase 4 — docs and the whole suite

- Docs: `docs/state_management/watch_diagnostics.md` gained "The phone's decisions." (six kinds with
  their shapes, the dedupe rule, the privacy pointer) and the two test files joined the "The phone."
  paragraph's verified-by list; the new paragraph names every test by group and name.
- Verify-no-change: `docs/watch_session_sync.md`, `docs/watch_session_capture.md` and
  `docs/state_management/workout_state.md` mention no diagnostics behaviour, so nothing they claim
  became false.
- Residue sweep over `lib/`: 14 hits, all at D-17402 sites — bridge 8 (adoption_decision,
  end_applied ×2, discard_applied ×2, session_row_created ×2, end_clamped), importer 6 (end_clamped
  ×2, session_row_created, end_applied ×2, session_start_corrected).
- Full suite: `+7653 ~4: All tests passed!` (baseline `+7635 ~4`; +11 bridge, +6 importer, +1
  structural guard).
- `gateway.sh lint`: `181 issues found` — the plan's baseline, none in a file this change touched.
- Docs contract: `+13: All tests passed!`; invariant grep over `lib/state lib/features lib/widgets
  lib/core` for `import .*hive_workout_repository`: no matches.
