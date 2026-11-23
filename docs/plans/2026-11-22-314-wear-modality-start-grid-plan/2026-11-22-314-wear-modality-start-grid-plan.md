# Plan 314 — The Wear Start screen offers the four modality buttons, and backing out of the picker leaves no empty workout (series 310-314) — OUTLINE, not yet seeded for building

Status: outline. Depends on plan 312 (the modality's own exercises come first because the phone tags each exercise with `recommendedFor`). The owner chose the four buttons for the Apple wrist on 2026-11-13 ("four modality buttons instead of Free workout", plan 176): this plan carries that decision to Wear.

## What the review found

The Apple Start surface opens with a 2x2 grid, in the phone's home-tile order, in the phone's own colours: Cardio, Resistance, Sports, Isometric (`WatchModalityStart.swift`; word and colour source `watch/contract/watch_modality_start_contract.json`; view `WatchStartView.swift` `WatchModalityStartGridView`). A tap creates nothing: it remembers the modality and opens the picker over the same list, modality's exercises first (`beginModalityStart`, `listModality`); the pick is what starts the session, and the session carries the modality, so the phone's calendar and Health typing are right. Closing the picker without a pick drops the mode and cancels an empty free workout (`cancelModalityStart`, `cancelEmptyFreeWorkout` 828, plan 57). The Wear Start screen has a single `Free workout` button (`lib/watch/start/watch_start_screen.dart` 208-213) that creates the session before the pick (`startFreeWorkout`, modality null), so a swipe back from the picker leaves an empty active session that syncs to the phone, and a Wear workout always has no modality (plan 308: a Free workout types as its first exercise).

## Goal (draft)

The Wear Start screen shows the four modality buttons first (compact layout at 192/227 dp measured, labels and colours from the contract); a tap opens the picker with that modality's exercises first; the pick starts a session that carries the modality; leaving the picker without a pick leaves nothing behind. `Free workout` goes away on Wear as it did on Apple (confirm in the Apple view that no free-workout button remains; if one does, keep it).

## Decisions to take when seeding (technical, mine)

- Add a Dart reader of `watch_modality_start_contract.json` (the Apple suite and the phone's tokens already hold to it: so neither client can move a colour or a word alone).
- Port `beginModalityStart` / `cancelModalityStart` / `startModalityWorkout` / `cancelEmptyFreeWorkout` into `WatchSessionStartPaths`.
- The cancel rule also covers the Wear's other way into an empty session; check `WearApp` for a path that lands on "No exercise".
- Compact layout: a 2x2 grid with 4 dp gaps inside the round bezel, the routines and utility buttons below in the one scrolling list.
- Order of work: 312 first (list), then this; the empty-session fix can ship first on its own if 312 slips (it needs no list).

## Owner questions

None expected. A way to SEE it: the desktop harness `lib/watch/debug/watch_start_debug_main.dart` and the 192 dp emulator.
