# Review — a negative load (band assist) on a set works on the phone and the watch

Plan: `2026-10-06-16-watch-negative-load-plan.md`. Findings go here, one per item, quantified (count,
examples, the root-cause line). Findings are never written into the plan; defects open a Phase X.Y
remediation sub-phase with a structural guard.

## Checklist the reviewer owes

1. **Diff vs Predicted Files** per phase — an out-of-bounds file and an untouched predicted file are
   both findings.
2. **Per-S-x conformance** — S-58…S-67 exist as tests (or as fixture replays), each with the fixture
   its scenario enumerates; an assertion that passes only because the fixture is thinner than the
   scenario is a finding.
3. **Impact-Check conformance** — re-run every grep in the plan's Existing-Functionality Impact table;
   a reader of a touched surface the table does not name is a finding. Confirm the "deliberately
   untouched" list is untouched.
4. **Parity** — `MockWorkoutRepository` and `HiveWorkoutRepository` return the same set for a negative
   `weightKg`; the Dart and Swift floors agree with the schema (D-59) and with each other.
5. **The floor is one number** — no `-200` literal outside `wire_limits.dart` and
   `WatchMetricStepping.minimumLoadKg`; no `> 0` / `>= 0` load guard left in `lib/watch/` or
   `watch/watchos/Sources/`.
6. **Omission semantics** — only `reps < 1` and a below-floor load are omitted; a zero weight still
   sends no `loadKg`; the version-mismatch path is untouched (D-66).
7. **Docs** — `docs/watch_session_sync.md` no longer claims an assisted set cannot travel;
   `docs/state_management/watch_surface.md` is untouched; `docs/watch-app-setup-and-qa.md` has the
   owner step and no new "known gap".
8. **Assumption Log adjudication** — ratify (promote to a D-x) or revert each entry; an entry that
   contradicts a D-x or an invariant is a revert with a remediation item.

## Findings

(none yet)
