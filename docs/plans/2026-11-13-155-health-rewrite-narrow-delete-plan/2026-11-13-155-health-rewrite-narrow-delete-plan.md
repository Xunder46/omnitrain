# Plan 155 — the Health re-write deletes only its own session's workout

Follow-up to plan 154 D-15404 (review major 4, second half). Dart-only; one PR, one phase.

## Finding that changes the plan

Plan 154 assumed an id-scoped delete needs native plugin code. Reading `health` 13.3.1 shows it does not, and that it is not worth it:

- **iOS** `delete` already deletes only this app's own objects (`HKSource.default()`) whose START lies in `[start, end]` (`.strictStartDate`). The phone's workout starts exactly at `session.startedAtMs`.
- **Android** `deleteRecords(TimeRangeFilter.between(...))` can only remove records this app wrote (Health Connect lets an app delete only its own).
- So the only remaining over-reach is the WINDOW: `rewriteWorkout` asks for `[startedAtMs, max(previousEndedAtMs, endedAtMs)]`. When an end moves later, that window can also cover another workout this app wrote that starts inside it (the next phone session, finished before the late end arrives). The window is the whole problem, not the missing id.
- A true id delete would need the written workout's id, but `writeWorkoutData` returns only a bool: it would mean replacing the plugin's write on both platforms with native code and changing the ledger format. Rejected (D-15502).

## Scope

`HealthSyncService.rewriteWorkout` (and the effort clear it calls) use a window that can only match the session's own workout.

## Decisions

- **D-15501** The delete and the effort clear use `[start, start + 1 s)` where `start` is the draft's start (`session.startedAtMs`). The write used exactly that start, so it matches the session's own workout and nothing that starts later; the 1 s margin absorbs the store's date rounding. `previousEndedAtMs` stays only for the "end moved later" gate and for restoring the previous span (D-15404).
- **D-15502** No native code and no ledger change; the plugin's `deleteByUUID` is not used because the write returns no id.
- **D-15503** `onSessionDeleted`'s wider window is left as it is: it must also reach a workout the watch saved, whose start is not the session's own.
- **D-15504** Known limit, unchanged: if the session's start was edited after the write, the narrow window finds nothing and the re-write adds a second workout (the old wide window had the same limit). Reported in the doc, not fixed here.

## Scenarios

- **S-15501** Two own workouts in a fake store: session A (start T) and session B starting inside A's old extended window; A's end moves later: only A's workout is deleted and rewritten, B stays.
- **S-15502** The platform call arguments are exactly `[start, start+1 s)` for both delete and effort clear.
- **S-15503** The existing S-14670/S-14671/S-15409/S-15410 stay green (one workout after one or two moves; no ledger = nothing; failed write restores the previous span; refused delete = nothing else).

## Phase 1 (developer)

Predicted files: `lib/core/services/health_sync_service.dart`, `test/health_platform_test.dart`, one doc line in `docs/state_management/services_and_utils.md`.
Done Criteria: `flutter test test/health_platform_test.dart test/watch_session_import_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`; S-15501 red at HEAD with the failing line pasted, green after; `flutter analyze` stays 181; full `flutter test` run by the lead.
Budget: far under `.github/copilot/pr-scope-budget.md` (about 60 lines).
