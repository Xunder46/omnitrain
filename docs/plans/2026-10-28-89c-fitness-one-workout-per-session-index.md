# Series 89c: Fitness keeps one workout per session, and follows deletes

> Index plan, 2026-10-28. Follows plan 89 (`docs/plans/2026-10-28-89-fitness-workouts-follow-the-session-plan/`), whose Phase 3 found that a phone-side delete cannot reach a workout the watch saved (P-1) and that a session the watch tracks is written twice (D-6). The owner then reported the second one live: an outdoor walk started on the watch showed up in Fitness as "Outdoor Walk" and as "Other".

## Why a series

Two different jobs came out of the plan 89 findings, with different size and risk, so they ship apart (`.github/copilot/pr-scope-budget.md`: two tracks, a possible wire change).

| PR | Job | State |
|---|---|---|
| 89c1 | Stop the phone writing a second workout for a session the watch already saved. Phone track, small, no wire change. Plan: `docs/plans/2026-10-28-89c1-one-workout-per-session-plan/` | planned |
| 89c2 | Make deleting a session on the phone also remove the workout the watch saved. **Closed without code, 2026-10-28**: the owner's real-watch check showed the existing phone delete already removes a finished watch workout (see below). | closed |

## 89c2 result (2026-10-28): no code needed

Owner device check, Write workouts on: a session finished on the watch (workout visible in Fitness) and then deleted on the phone lost its watch workout; a phone-only discard also removed its workout. So HealthKit treats the watch app's workouts as the OmniTrain app's own, and the existing `onSessionDeleted` (plan 89 D-4/D-5) reaches them. The wrist-side frame, the native Runner method and the `HKMetadataKeyExternalUUID` tie below are NOT needed and are dropped. Unchanged by choice: the delete still needs "Write workouts" on (plan 89 OQ-2); the window stays the session's exact span. Open (not blocking): the Source label could not be read on the watch (it is shown in the iPhone Health app); `healthWorkoutSaved` on `session_end` (89c1 D-3) stays unbuilt and unneeded until a real case shows it.

## Original 89c2 outline (superseded, kept for the record)

Problem: the watch's workout has the watch app as its source, and the health plugin's delete only reaches the phone app's own source (plan 89 P-1). It also has no identifier that ties it to an OmniTrain session.

Pieces any answer needs:
1. A tie between workout and session: the watch builder stamps `HKMetadataKeyExternalUUID` = the session id (`builder.addMetadata`) when it begins.
2. A way to delete it, one of:
   - **(a) Wrist-side delete.** The phone sends the watch a new "delete this session's workout" frame; the watch queries its own workout by that metadata and deletes it. New message family: schema, fixtures, Dart and Swift validators, queueing (`transferUserInfo`), receipts, protocol-table row. Works when the watch is out of reach later; honest about source.
   - **(b) Phone-side native delete.** A small native Runner method that queries workouts by the metadata and deletes them. Only works if HealthKit lets the phone app delete samples that carry the watch app's source. That is unproven; needs a one-off device spike before it can be planned.
3. Optional, closes 89c1's D-3: a `healthWorkoutSaved` flag on the wrist's `session_end`, so the phone knows the watch really holds a workout.

Owner decision needed when 89c2 is planned: (a) or (b), after the spike answers whether (b) is even possible.

## Order

89c1 first (it fixes what the owner sees today). 89c2 is planned only after 89c1 is built and reviewed.
