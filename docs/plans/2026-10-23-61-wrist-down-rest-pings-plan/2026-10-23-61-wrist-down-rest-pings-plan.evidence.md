# Evidence: 61 — the wrist pings on time with the screen down, and a dimmed screen shows a correct rest clock

## Phases

| Phase | Run | What |
|---|---|---|
| P1 | crew-builder-watch | `WatchRestPingScheduler` (D-1), `WatchLoggingState.restElapsedMilliseconds` / `restStartedAt` / `dimmedRestClock` (D-2), `WatchRestPingSchedulerTests` S-9101..S-9108 |
| P2 | crew-builder-watch | `WatchRestView` stops pinging and shows the dimmed minutes clock (D-3), `WatchAppHost` owns `restPings` and arms it (D-4), `WatchRestPingWiringSourceTests` S-9109 |
| P3 | crew-docs-keeper | `watch_surface_wrist.md` (the ping paragraph), `watch-app-setup-and-qa.md` (QA steps 22 and 23), this evidence file |

## Governor read-backs (observed by the lead)

- `swift test` in `watch/watchos` (package suite): 861 tests, 0 failures.
- `xcodebuild` of the watch app target: BUILD SUCCEEDED.

## Mutation pass (observed by the lead)

23 mutants: 21 killed on the first pass; 2 alive — `max(0,…)` in `dimmedRestClock` and the `dimmed` condition in `WatchRestView.elapsed` — closed by a tests-only fix 1 and then killed. One mutant (the scheduler returns 0 instead of nil with no rest) was killed by an endless loop.

## Deviation from the Goal table

The dimmed rest clock shows whole minutes ("3 min"); the owner asked for a "correct" dimmed clock without naming a format, and whole minutes is what a once-a-minute dimmed redraw can keep correct.

## Not verified (owner)

- Whether watchOS lets the app tap with the wrist down, and the dimmed redraw cadence — QA step 22 in the PR 2b list (`docs/watch-app-setup-and-qa.md`).
- Whether the phone's own rest notification mirrors to the watch as a second tap when the phone is locked — the same QA step; a follow-up plan decides which tap yields if it does.
