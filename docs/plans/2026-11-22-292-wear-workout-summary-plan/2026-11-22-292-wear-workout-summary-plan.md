# Plan 292 — The Wear wrist shows a short summary when a workout ends (plan 280 open item 6)

The Apple wrist shows a "Workout done" screen when the wrist ends a workout (plan 66a: `docs/plans/2026-10-23-66a-wrist-workout-summary-and-skip-plan/`). The owner's decisions there are binding and this plan matches them: the summary shows `Time`, `Sets` (or `Efforts` when the workout holds anything but sets) and `Avg HR` (only when the wrist recorded heart rate), then a `Done` button; it appears after the effort question, only for a workout the wrist ended with at least one logged effort, and only if the app saw that workout running (a relaunch after the end shows nothing); an end the phone made closes the workout without a summary; a new workout starting gives way to nothing; Skip on the effort question already exists on the Wear wrist (plan 285). Wrist only (`lib/watch/`); no wire, phone, schema or Swift change. Base commit: `.work/2026-11-22-292-wear-workout-summary/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch, ending a workout from the menu (Finish) with at least one logged effort shows, after the effort question when the phone asks for one, a screen titled `Workout done` with `Time 12:34` (`h:mm:ss` from an hour), `Sets 12` (`Efforts 2` when the workout holds a timed effort, a round or a hold), `Avg HR 128 bpm` only when the wrist holds heart-rate readings for the workout, and a `Done` button that returns to the start screen. A workout ended with nothing logged, an abandoned or discarded one, one the phone ended, and one that ended while the app was closed show no summary. A new workout starting while the summary is up replaces it. Today's Wear wrist has no heart-rate source, so in practice the row appears only once live sensors (item 9) exist; the rule is built now so that item needs no change here. The Apple "no heart rate because Health is off" note is not built (Wear has no Health-access state to read).

Acceptance: S-29201..S-29216 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the existing Wear files no new red; Docs delta applied.

## Feature invariants

- The summary is local state derived from the engine's own session and entries; nothing is sent, nothing stored; the app keeps no summary across a relaunch.
- One summary per workout, and only for a workout this process saw active.
- The shell's order of surfaces is: the effort question (when owed), the summary, then the existing surfaces.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29201 | New file `lib/watch/logging/watch_workout_summary.dart` holding `WatchWorkoutSummaryCopy` (`title` `Workout done`, `time` `Time`, `sets` `Sets`, `efforts` `Efforts`, `avgHeartRate` `Avg HR`, `done` `Done`, `bpm` `bpm`), `WatchSummaryRow` (`label`, `value`), `WatchWorkoutSummary` (`sessionId`, `startedAt`, `endedAt`, `effortCount`, `allSets`, `averageBpm`; `rows`; static `durationText(seconds)`: `m:ss` under an hour, `h:mm:ss` from an hour, a negative length `0:00`) and `WatchWorkoutSummaryState` (`note(session)`, `pending`, `dismissPending()`). | `WatchWorkoutSummary.swift` 20-162 |
| D-29202 | `note(session)` rules, in order: null does nothing; an `active` session records it as seen, and drops a held summary that belongs to another session; anything but a `completed` session of the seen one that is still the engine's session, or one already held, does nothing; the seen id is cleared; an end the phone made (its session row id starts with the engine's lifecycle prefix) owes nothing; a workout with no effort entry (`WatchObservationKind.efforts`) owes nothing; else the summary is built from the engine's entries (`effortCount`, `allSets`), the session's `startedAt` and its row's `recordedAt` as the end, and the average of the heart-rate readings (`WatchSensorKind.heartRate`) whose `recordedAt` lies in `[startedAt, endedAt]`, rounded to a whole number, null with none. | `WatchWorkoutSummary.swift` 105-150 |
| D-29203 | The engine gains one read-only helper, `endedByPhone(WatchSessionRecord session)` (true when the row's id starts with the private lifecycle prefix `life-`), so the summary state does not duplicate the prefix. | `watch_session_engine.dart` 77, 961 |
| D-29204 | New screen `WatchWorkoutSummaryScreen(summary:, onDone:)` (`lib/watch/logging/watch_workout_summary_screen.dart`): a scrollable column: the title as a header, one label/value row per summary row (label secondary, value in tabular digits, each row one semantics node), a full-width `Done` `FilledButton` at the token shape and height (compact under the wrist rule). Keys `doneKey`. | `WatchWorkoutSummaryView.swift` 30-66; `watch_effort_rating_screen.dart` as the Wear screen pattern |
| D-29205 | The shell owns one `WatchWorkoutSummaryState`, notes the engine's session at the start of each `_surface` build (it is idempotent and notifies nothing), and after the effort-question check shows the screen while `pending != null`; `Done` dismisses it and rebuilds. A session that becomes active again replaces a held summary through `note`. | `ContentView.swift` 515-519; `wear_app.dart` `_surface` |
| D-29206 | Not in scope: the "no heart rate" note (needs a Health-access state Wear does not have), the summary after a relaunch, a summary for the phone's end, distance or pace rows. | plan 66a |

## Input-reality checklist

1. **Writers.** `pending` and the seen id: only `note` and `dismissPending`. The session and entries: the engine.
2. **Units.** Seconds for the time; whole beats per minute.
3. **Lifecycle.** Seen active then completed by the wrist (a summary); completed by the phone (none); completed before this process saw it active (none); abandoned or discarded (none); a second workout started while the summary is up (it gives way); `Done` then nothing returns; a rating owed first (the question wins, the summary waits behind it and shows after the answer or Skip).
4. **Settings changing while open.** None.
5. **Time.** The window and the length come from the session row's own times, not a clock read, so the summary reads the same whenever the shell builds.
6. **Load.** One pass over the session's entries and samples, once, at the completing build.
7. **Wording.** `Workout done`, `Time`, `Sets`, `Efforts`, `Avg HR`, `Done` as the Apple wrist says them. Stale wording: `docs/wear_os_app.md` lists the workout summary among the Apple-only items; the shell header comment names it as not hosted (the Docs delta; the comment is fixed in P1).
8. **Slot competition.** The summary is a full screen of its own; the only layout risk is a short screen (scrollable, measured at 192 and 227 dp, S-29214).

## Scenarios

State (`test/wear_workout_summary_state_test.dart`, new, plain `test()`; an in-memory engine and store, a fixed clock the test moves):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29201 | `durationText` of 0, 59, 754, 3599, 3600, 3725, -5 | `0:00`, `0:59`, `12:34`, `59:59`, `1:00:00`, `1:02:05`, `0:00` | the format or the hour branch is wrong |
| S-29202 | a summary of 3 efforts, all sets, 130 bpm; of a timed and a set effort; with no heart rate | rows `Time 12:34`, `Sets 3`, `Avg HR 130 bpm`; the label `Efforts` for a mix; exactly two rows without heart rate | the rows or labels differ |
| S-29203 | a workout seen active, two sets and a rest and a nutrition log in it, finished by the wrist | `pending` with `effortCount` 2, `allSets` true, `startedAt` the session's, `endedAt` the finishing row's time, `sessionId` | a rest or a food counts as an effort, or the times are wrong |
| S-29204 | heart-rate readings 120, 130, 140 inside the window and 200 before the start; and 129.5 alone | `averageBpm` 130 (the early reading ignored); 130 (rounded); none: null | the window or the rounding is wrong |
| S-29205 | each gate: (a) completed but never seen active (a first `note` of the completed row); (b) completed with no effort; (c) abandoned; (d) the same completed row noted again after `dismissPending()` | no summary in each | a gate is missing |
| S-29206 | a workout the phone completed (a `session_lifecycle` completed frame applied through the engine) after the wrist saw it active | no summary | the phone's end owes one |
| S-29207 | a summary pending for workout A, then `note(active B)` | `pending` null | a new workout does not replace it |
| S-29208 | `dismissPending()` | `pending` null; a later `note` of the same completed row makes none | a dismissed summary returns |
| S-29209 | the engine's `endedByPhone` for a wrist-finished and a phone-completed row | false; true | the helper is missing or wrong |

Widgets (`test/wear_workout_summary_screen_test.dart`, new; in-memory store, Mock-first, explicit pumps):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29210 | the screen over a summary of 12:34, 12 sets, 128 bpm | the title, three label/value pairs, a `Done` button; each row one semantics node (`Time, 12:34`); no `Avg HR` row without heart rate | the screen is missing or shows a row it should not |
| S-29211 | tap `Done` | `onDone` called once | the button does nothing |
| S-29212 | the shell: start a workout, log a set, finish from the menu (effort question off) | the summary shows with `Sets 1`; `Done` returns to the start screen and it does not come back | the shell does not show it, or shows it twice |
| S-29213 | the shell with the effort question on: finish | the question first; after Skip the summary; after `Done` the start screen | the order is wrong |
| S-29214 | the screen at 192x192 and 227x227 dp with the longest rows | no overflow exception; `Done` reachable | the screen overflows |
| S-29215 | the shell: a workout ended with nothing logged; a workout the phone ends | the start screen, no summary | an empty or phone-ended workout shows one |
| S-29216 | the shell: a summary up, then a new workout started from the phone's push | the summary gives way to the new workout | the summary sticks |

Guard families the lead proves by mutation: each `note` gate, the effort filter, the all-sets rule, the window edges and the rounding, the duration format, the row set and labels, the shell's order and its note call, `Done`.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — state, screen, helper, shell** (`crew-builder-watch`; scope `lib/watch/logging/watch_workout_summary.dart` (new), `lib/watch/logging/watch_workout_summary_screen.dart` (new), `lib/watch/session/watch_session_engine.dart`, `lib/watch/app/wear_app.dart`). Exact code in the brief. About 230 lines.
2. **P2 — tests** (lead): the two new files.
3. **P3 — docs** (lead).
4. **Lead:** analyze, readers, mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | ## The workout summary | S-29203 |
| docs/wear_os_app.md | ADDED | - | `test/wear_workout_summary_state_test.dart` | S-29203 |
| docs/wear_os_app.md | ADDED | - | 12. (owner) on a Wear watch | S-29212 |

The Apple-only list loses "the workout summary," (hand edit). Plan 280's open item 6 is a plan record ("built by plan 292").

## Assumption Log

- A completed row the wrist writes carries a `recordId` that does not start with `life-` (`_transitionTo`), and a phone-completed row does (`watch_session_engine.dart` 961): S-29206 proves it through the engine.
- The Wear wrist has no heart-rate source today (`docs/wear_os_app.md`: the shell passes no source), so the `Avg HR` rule is proven with stored readings, not a live feed.
- `WatchSessionEngine.entries` is the current session's projected entries (effort kinds are `WatchObservationKind.efforts`).

## Progress

- [x] P1 production (crew builder)
- [x] P2 tests (lead; S-29201..S-29216; seven older tests updated)
- [x] P3 docs (lead)
- [x] Verify and prove (analyze 174; 244 Wear tests, one pre-existing red; 25 of 25 mutants killed)
- [ ] (owner) check 12 in `docs/wear_os_app.md` on a watch
