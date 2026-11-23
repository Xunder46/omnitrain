# Plan 313 — A Wear watch can start today's planned workout (series 310-314) — OUTLINE, not yet seeded for building

Status: outline. Needs a scout sheet before seeding. Independent of 312 and 314 except for the shared Start screen file (`lib/watch/start/watch_start_screen.dart`), so it runs serially with 314.

## What the review found

The phone sends the wrist today's startable plans as `planned_down` (`lib/core/utils/watch_reference_sync.dart` 183-235; built fresh at each request, `lib/state/watch/watch_sync_request_handler.dart` 270). The Apple wrist stores them (`WatchPlannedRecords.swift`, `plannedCatalog` record type, `applyPlannedDown` 431), and its Start surface shows a quiet bordered button first among the routines: the plan's name when there is one, `WatchStartSurfaceCopy.plannedLabel` when there are several (then a picker), and a start tells the phone which plan began (`startPlanned` 532, plan 129). The Wear router drops `planned_down` (`watch_sync_orchestrator.dart` default case), the Dart records have no planned-catalog type, and the Start screen has no such button. A Wear user cannot start the workout they planned on the phone.

## Goal (draft)

The Wear wrist stores the newest `planned_down` (survives a restart, ignores an older copy), the Start screen shows the planned button above the routines exactly as the Apple one does (one plan: its name; several: the shared label and a picker; none: no button; a plan for a routine no longer on the wrist: the "routine is no longer on the watch" notice), and starting it creates the session the same way a routine start does and reports the planned session's id to the phone.

## Decisions to take when seeding (technical, mine)

- Copy the Apple copy strings and rules verbatim from `WatchStartPaths.swift` (`startablePlannedSessions` 498, `startPlanned` 532) and `WatchStartView.swift` (`startPlanned`, `WatchPlannedPickerView`); the shared contract `watch/contract/watch_start_paths_contract.json` is the word source and its Dart reader should be added.
- New record type in both stores; tests under Mock AND Hive.
- The `session_started` frame is what tells the phone which plan began: check the Dart `WearWatchTransport` already sends it for routine starts and extend only the id.
- Start screen layout at 192/227 dp (the compact list from plan 296 scrolls; the planned button goes first).

## Owner questions

None expected: matches Apple.
