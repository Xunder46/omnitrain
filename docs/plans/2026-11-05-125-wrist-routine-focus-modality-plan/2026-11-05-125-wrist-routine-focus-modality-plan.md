# Feature: 125 — INDEX: a routine started on the watch carries the routine's Focus

> Status: INDEX. Evidence gathered by reading code (nothing run). Only 125a is planned in full
> (`2026-11-05-125a-contract-and-phone-plan.md`, this folder); 125b and 125c are outlined here and
> are planned when 125a lands. Do NOT merge them back into one plan: the three tracks exceed
> `.github/copilot/pr-scope-budget.md` (phone + watch + contract = three tracks; with the owner
> questions below it is also more than 20 decisions-worth of surface).
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md` (versioning policy,
> validation profiles), `docs/watch_session_sync.md`.
> Related: plan 122 (`docs/plans/2026-11-05-122-routine-session-modality-plan/`, read-only here) stamps the
> Focus on phone-started routine sessions and on the phone's adoption of a wrist routine. 121a edits
> `lib/state/watch/watch_timer_push.dart` and `watch_sync_wiring.dart`: **no part of 125 touches either file**.

## Overview

A routine's Focus Modality (`WorkoutTemplate.focusModality`, `lib/data/models/models.dart:668`) never
reaches the wrist, so a workout started from a routine on the Apple Watch is a "no modality" workout
everywhere it is shown or saved. The owner treats this as a bug.

## Evidence (read from code, not run)

| # | Claim | Verdict | Where |
|---|---|---|---|
| a | The wrist's routine row has no Focus; the phone never sends one | **Real.** `routines_down` `$defs.routine` is closed (`additionalProperties:false`) with only `routineId, name, updatedAt, segments`; `buildRoutinesDown` writes exactly those four (`lib/core/utils/watch_reference_sync.dart:136-146`). `startFromRoutine` creates the session with `modality: nil` (`WatchStartPaths.swift:584`), same in the Dart copy (`lib/watch/start/watch_session_start_paths.dart:197`). | |
| b | The wrist's own Health workout type is "Other" | **Real, as a consequence of (a).** `WatchActivityType.forModality(nil)` and `for(session)` fall to `generic` = "other" (`WatchPlatformWorkout.swift:96-98, 182`). Once a modality exists, resistance/strength → traditional strength, isometric/mobility/recovery → flexibility, conditioning → cross training, **cardio → running**, **sports/skill/competition → still "other"** (table :62-93). The phone's own mapper says cardio → Cardio and sports → Sport (`health_modality_mapper.dart`), so the two devices disagree for those two Focuses (Q2). | |
| c1 | A wrist-started routine that the phone **adopts** is saved without a Focus | **Real until 122 lands.** `_adopt` already links the routine (title, `intent:'routine'`, `routineTemplateId`) by decoding `sx-<effortId>~<token>` slot ids against the phone's templates (`watch_session_adoption_bridge.dart:873-915`), but writes no `modality` (:805-822). 122 D-12201(c) fills it. No wire change needed for this case. | |
| c2 | The **importer** never links a routine | **Real.** `_createSession` writes `id, owner, start, end, modality: end.modality, rating` only (`watch_session_importer.dart:579-592`); no `intent`, `routineTemplateId` or title. This is the path for a wrist session the phone never adopted (phone away or app closed during the workout). `end.modality` is the wrist's (the wire carries `modality` on a `session_end` entry only, `envelope.schema.json:296`; the wrist emits it when set, `WatchSessionEngine.swift:1664`), so today it is always absent for a routine. | |
| d | Other wrist behaviour that keys on the session's modality | **Found, owner-visible.** Setting a modality on the wrist session also changes: round word (`sports` → "Periods", `cardio_endurance` → "Intervals", else "Rounds"; `WatchLoggingState.swift:608-615`, "Period length" :886), and **GPS** (cardio and sports modalities declare `distance`, so `WatchGpsPolicy.isRequired(session)` is true from the start, `WatchPlatformWorkout.swift:222-240`, even if the routine holds no distance exercise) (Q3). | |
| e | Smart Stack / Live Activity label | **Not established.** `grep -ri "smart stack\|WidgetKit\|Complication" watch/watchos/Sources` found nothing; there is no such surface in the repo, so none is claimed. | |
| f | Apple Health on the **phone** for a wrist session | **Not established / probably none.** `grep -i health lib/core/services/watch_session_importer.dart` → 0 hits; the wrist writes its own workout. 122's note about the phone writing a Health workout concerns phone-run sessions. | |

What the owner sees today after a wrist-started routine (e.g. Focus = Stretching):
- Calendar and day list: if the phone adopted it, it is titled with the routine's name but labelled and
  coloured "Free Training" (fixed by 122); if the phone imported it afterwards, it is a plain "Free
  Training" with no routine name and does not appear in that routine's history (c2).
- Health on the watch: "Other" (b).
- On the wrist itself: no Focus label anywhere (none is shown today either; adding one is NOT in scope).

## Questions for the owner (defaults the plan builds against)

- **Q1. Old watch after a phone update.** The watch checks incoming messages strictly, so a phone that
  starts sending the new Focus before the watch app is updated would make the old watch **reject the
  whole routine list**. Default: the phone starts sending only in 125b, together with the watch
  update, and the two are installed together (same as every earlier protocol addition).
- **Q2. Health type on the wrist for Cardio and Sports Focus.** Default: reuse the watch's existing
  table, so Cardio focus = Running and Sports focus = Other, even for a routine of only squats.
  Alternative: for a routine session, take the type from the routine's exercises instead. (Decided in 125b.)
- **Q3. GPS and round words.** Default: a Cardio or Sports Focus routine turns the wrist's GPS on from
  the start and calls rounds "Intervals"/"Periods", exactly like a workout started from that tile.
  Alternative: routine sessions keep today's behaviour for these and only the Health type changes.
  (Decided in 125b.)

## Split (all tracks, in landing order)

| PR | Track | Content | Status |
|---|---|---|---|
| **125a** | contract + phone | Optional `focusModality` on a `routines_down` routine (schema, fixtures, PROTOCOL amendment, shared contract file); both validators and the Dart wrist copy accept and keep it; phone importer links the routine and stamps its Focus. **The phone does not send the field yet.** | planned in full |
| 125b | watch (Swift + Dart copy) + one phone line | The wrist reads the field, starts the routine session with that modality (Health type, round word, GPS per Q2/Q3); `buildRoutinesDown` starts emitting it. Install together (Q1). | outline |
| 125c | phone | Only if still needed after 125a/122: route the importer and the adoption bridge through one shared routine matcher (see 125a D-125-3) and remove duplicate lookups. | outline, may be dropped |

### 125b outline
Swift: `WatchRoutine` (`WatchRoutineRecords.swift`) gains `focusModality: String?` (dropped silently when
empty or not in `WatchActivityType.byModality`); `startFromRoutine` passes it to `createSession(modality:)`
(both branches: the new session, and the "fill the held empty session" branch must set the held
session's modality too). Dart: same in `lib/watch/start/watch_routine_catalog.dart` and
`watch_session_start_paths.dart`. Phone: `buildRoutinesDown` adds `'focusModality'` when non-null.
Fixtures: regenerate nothing; add the 125a valid fixtures to both suites. The `routines_down` `updatedAt`
stamp: a Focus-only edit must bump `template.updatedAtMs` (verify the editor does) or the wrist keeps a
stale Focus (`since` rule, PROTOCOL 2026-10-23).

## Adversarial fixtures (owned by the PR named)

| ID | Case | PR |
|---|---|---|
| S-12501 | Old watch build (field unknown) receives a routine WITH the field | 125a documents the strict rejection (`unexpected_field` at `$.payload.routines[0].focusModality`) as the reason the phone does not emit yet; 125b proves the emit gate |
| S-12502 | Old phone (no field) → new watch | 125a/125b: routine parses, Focus nil, session as today |
| S-12503 | Routine with no Focus (null/absent), and Focus "" | 125a: schema refuses "" (`minLength:1`); phone omits null |
| S-12504 | Routine deleted on the phone while the watch holds it, then the wrist session ends | 125a: importer finds no template → session saved free, no link, no crash |
| S-12505 | Round trip: wrist routine session → phone adopts (122) → wrist follows the snapshot | 125a: adopted row keeps `routineTemplateId`, modality = template Focus; 125b: wrist's own modality survives the snapshot (a snapshot carries none; the wrist must not null it) |
| S-12506 | 40 mm layout | 125b: no new view is added; assert no layout file changes (`git diff --stat watch/` shows no View/Screen file) |
| S-12507 | Focus changed on the phone after the wrist synced | 125b: stale Focus until next sync; documented, not a bug |
| S-12508 | Routine edited after the wrist started (effort ids replaced) | 125a: importer finds no match → free |

## Owner device checks (plain language, after 125b)
1. Give a routine a Focus of Stretching; sync the watch; start that routine on the watch, log one hold,
   end it. In Apple Health the workout should be Flexibility, not Other.
2. Open the OmniTrain calendar: that day shows the Stretching colour and name and the routine's name.
3. Repeat with the phone switched off or the app closed during the workout; open the phone afterwards:
   same result (this is the import path).
4. Repeat with a routine that has no Focus: still "Free Training" on the calendar, Other in Health.
5. Delete the routine on the phone while the watch still lists it, run it on the watch: the workout
   saves, labelled Free Training, no error.
6. Cardio-focus routine: note whether the watch asks for location and says "Intervals" (Q3).
7. Look at the small 40 mm watch: nothing should look different.

## Progress

- **125a: built, verified, reviewed (APPROVE, 0 blocker, 0 major). Not committed.** The contract accepts an optional `focusModality` on a `routines_down` routine; the phone importer links a wrist routine it never adopted (title, intent, routine link, routine Focus as modality when the wrist sent none); the phone still does not send the field. Evidence: `2026-11-05-125a-contract-and-phone-plan.evidence.md`, review: `…125a….review.md`.
- 125b, 125c: not started.
