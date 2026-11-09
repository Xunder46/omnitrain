# Feature: 66b — the phone's session summary shows the heart rate the watch recorded

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (uncommitted; owner device check open). Owner: watch audit 3 (2026-10-23), fix order item 10 (second half: heart rate on the phone's summary), in chat. Series: with 63, 64, 65, 66a. Base commit: `.work/2026-10-23-66/base.txt`. Working branch: the one checked out (`claude_develop`); never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

Decision (lead, for the owner to veto): the session info card on the post-workout summary gets one row, **Avg heart rate / Max heart rate** (bpm), between the Duration/Rest row and the Effort row. It appears only when the watch recorded heart rate for the session; without it the card is unchanged. Rolling sessions (no Duration row) show it too.

| What you do | Now | After 66b |
|---|---|---|
| Finish a workout the watch recorded heart rate for (the phone already stores it from the watch's session end) | the summary shows no heart rate anywhere | the info card shows `AVG HEART RATE 128 bpm` and `MAX HEART RATE 171 bpm` side by side |
| Finish a workout with no watch / no heart rate | no heart rate | unchanged: no row, no gap |
| The watch recorded an average but no maximum | n/a | cannot happen: the model (`SensorSummary`, D-131) requires average and maximum together; the row always shows both pills |
| A past session opened from the calendar | n/a | not in this plan (the summary screen for a just-finished workout only) |

How to SEE it (owner): finish a workout recorded on the watch with the heart-rate permission granted; open the summary on the phone. Without a watch: the widget test is the proof; there is no phone-only way to produce a heart rate.

Not in this plan: heart rate on the calendar's past-session view, per-exercise heart rate, a chart, the Stats screen (it already aggregates per-effort averages).

## Facts from the scout (`.work/crew/2026-10-23-66/scout-finish.md`; lines spot-checked by the lead)

- The watch's heart rate reaches the phone: `lib/core/services/watch_session_importer.dart` `_attachSessionSummary` stores a `SensorSummary(scope: SensorSummary.scopeSession, targetId: sessionId, avgHeartRateBpm, maxHeartRateBpm)` when either is present. Model: `lib/data/models/models.dart` `SensorSummary` (`avgHeartRateBpm`/`maxHeartRateBpm` are `double?`).
- Read API on the interface: `WorkoutRepository.getSensorSummariesForSession(String sessionId)` returns the session's summaries ordered by scope then window start (`lib/data/repositories/workout_repository.dart` ~l.801).
- The summary screen (`lib/features/session/session_summary_screen.dart`) loads its async data in `_loadAsyncData` through `widget.sessionSummaryService` (`lib/core/services/session_summary_service.dart`, built on the `WorkoutRepository` interface; `computeSessionRestTimeMs` is the model to copy); the info card is `_buildSessionInfoCard`: Duration/Rest `Row` (hidden for rolling sessions), then the Effort row, using `_StatPill(label:, value:)`.
- No heart-rate field is read anywhere in `lib/features/session/` today (grep `heartRate|avgHr`, none).

## Decision Ledger

- D-1 `SessionSummaryService.getSessionHeartRate(String sessionId)` returns `Future<({int avgBpm, int? maxBpm})?>`: reads `_repository.getSensorSummariesForSession(sessionId)`, takes the first summary with `scope == SensorSummary.scopeSession` and a non-null `avgHeartRateBpm`, answers `(avgBpm: avg.round(), maxBpm: max?.round())`; null when there is none. It depends on the repository interface only (no concrete storage).
- D-2 `_loadAsyncData` (screen): `final heartRate = await widget.sessionSummaryService.getSessionHeartRate(currentSession.id);` next to the rest-time read, stored in `setState` as `_heartRate` (a `({int avgBpm, int? maxBpm})?` field beside `_restTimeMs`).
- D-3 `_buildSessionInfoCard`: between the `if (!isRolling) …` block (which ends with its own `SizedBox(height: 16)`) and the `// Effort rating row` comment: `if (_heartRate case final heartRate?) …[ Row(key: const Key('omni_session_heart_rate_row'), children: [ Expanded(child: _StatPill(label: 'Avg heart rate', value: '${heartRate.avgBpm} bpm')), if (heartRate.maxBpm != null) ...[ const SizedBox(width: 16), Expanded(child: _StatPill(label: 'Max heart rate', value: '${heartRate.maxBpm} bpm')) ] ]), const SizedBox(height: 16) ]`. The spacing mirrors the Duration row. Shared pieces only: `_StatPill`, `OmniSurface` (docs/design_system.md "Shared pieces and rules per job"); no new colour, size or font literal.
- D-4 `docs/session_summary.md` gets one paragraph (the docs keeper): where the heart rate comes from and when the row is absent.

## Readers listed

- `SessionSummaryService` constructors: `lib/main.dart`, `lib/features/session/session_summary_screen.dart` callers, `test/session_summary_*_test.dart` and `test/screen_widget_test.dart` build it over `MockWorkoutRepository`; no signature change (a new method only). A fake service in a test that implements the class would need the method: the builder greps `implements SessionSummaryService` / `extends SessionSummaryService`.
- Tests that pin the info card's children or its height: `test/session_summary_effort_row_test.dart` (the card's keys), `test/screen_widget_test.dart`; with no heart rate seeded they must stay green unchanged.
- Scenario ids S-9651..S-9665 checked free (grep `S-96`, 2026-10-23).

## Core scenarios

New `test/session_summary_heart_rate_test.dart` (plain `test()` for the service, `testWidgets` for the screen, copying the harness of `test/session_summary_effort_row_test.dart`; Mock repository; seed a finished session and, for the heart-rate cases, `repository.createSensorSummary(...)` with values unlike any default: avg 127.6, max 171.2).
- S-9651 service: session summary with avg 127.6 / max 171.2 -> `(avgBpm: 128, maxBpm: 171)` (rounded, not truncated: 127.6 -> 128 distinguishes `round` from `toInt`).
- S-9652 service: no summaries -> null; only an effort-scope summary (scope `effort`, avg 150) -> null (the session scope is what counts); a session summary with a max but no avg -> null.
- S-9653 service: avg present, max null -> `(avgBpm: 128, maxBpm: null)`.
- S-9654 screen: with the heart-rate summary seeded, the card holds `omni_session_heart_rate_row` with the texts `AVG HEART RATE`, `128 bpm`, `MAX HEART RATE`, `171 bpm` (the pill upper-cases its label); without it the key is absent and the card's children are the same as before.
- S-9655 screen: max null -> `128 bpm` shown, no `MAX HEART RATE` text.
- S-9656 screen, rolling session (Duration row hidden): the heart-rate row still shows.
- S-9657 the row sits between the Duration row and the Effort row: the vertical order of `Duration`, `AVG HEART RATE`, `Effort` text positions is ascending (`tester.getTopLeft`).
- S-9658 the Hive repository answers the same query: the existing repository test for `getSensorSummariesForSession` (builder names it) stays green; no Hive widget test is added (checklist: Hive harness in `testWidgets` hangs).

## Phases

- P1 `crew-builder-app` (D-1, D-2, D-3, S-9651..S-9657; 7 items): scope `lib/core/services/session_summary_service.dart`, `lib/features/session/session_summary_screen.dart`, `test/session_summary_heart_rate_test.dart` (new). Brief: report first; never the full suite; Done: `flutter test test/session_summary_heart_rate_test.dart test/session_summary_effort_row_test.dart test/session_summary_distance_test.dart test/screen_widget_test.dart test/watch_session_summary_integration_test.dart`, `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`, `flutter analyze` on touched files, invariant grep. UI standards: fix what you touch within the 10-line rule; never add an allowlist entry.
- P2 `crew-docs-keeper` (after P1): D-4 in `docs/session_summary.md` (keep its line endings). Run no test.

## Verify (governor)

`flutter test` full, analyze count vs baseline, invariant grep, the two contract tests. Mutations: service `.round()` -> `.toInt()`; scope filter dropped; row shown when avg null; `maxBpm != null` condition dropped; row placed after the Effort row; label strings changed; `getSessionHeartRate` read from a different session id. Simulator: the iOS simulator has no watch data: seed a finished session with a session-scope `SensorSummary` through a debug path if one exists, otherwise state plainly that the screen was checked by widget test only (owner check: a real watch workout with heart rate).

## Progress

Done 2026-10-23: P1 + fix 1 + P2 docs. Deviation from D-1/D-3 (ratified in review): `maxBpm` is non-null; S-9653 and S-9655 dropped (unconstructible, the model throws). Lead: full `flutter test` +5483 ~2 green, 6 of 7 mutants red (the seventh, max falls back to avg, is equivalent), reviewed APPROVE with one Minor (this plan text). Owner check (owner): a real watch workout with heart rate; open the phone's summary.
