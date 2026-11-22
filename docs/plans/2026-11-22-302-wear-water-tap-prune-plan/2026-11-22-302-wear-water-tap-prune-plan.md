# Plan 302 — The Wear wrist drops old water taps the phone has confirmed (plan 280 leftover; the Apple wrist's plan 96)

The wrist stores each tap of the water bar as a `water_glass` observation. The count it shows is computed from the phone's frame plus the wrist's own taps of local today, so a tap is only ever read on the day it was logged; the phone holds it as soon as it receipts it. Nothing ever removes the old ones, so a watch that is used for years keeps every confirmed tap for ever (at most 500 a day). The Apple wrist drops them at launch (plan 96 D-43, D-44: `pruneWaterTaps(loggedBefore:)` on the store and engine, called from `WatchWaterState.restore()` with a cutoff of now minus 72 hours). Wear never got the prune (plan 291). This plan ports it. Wrist Dart only (`lib/watch/`); no wire, phone, Kotlin or Swift change. **Shared tree:** another session has uncommitted work in `lib/core/constants/data_version.dart` and `lib/data/repositories/*` (the food-category repair); this plan touches none of it and every check and commit is scoped to its own paths. Base commit: `.work/2026-11-22-302-wear-water-tap-prune/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

At every launch of the Wear app, after the engine's own restore, the wrist deletes the water taps that the phone has confirmed (a receipt) and that were logged more than 72 hours before now. Every other row stays: an unconfirmed tap whatever its age, a recent tap, a tap whose logged time cannot be read, every other kind of observation (a set, a rest), the confirmation rows themselves. The count the bar shows does not change, because no count reads a tap older than 25 hours. The prune runs only at launch, never when a frame arrives or a tap is pressed.

Acceptance: S-30201..S-30206 green on the in-memory and Hive stores and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; Docs delta applied.

## Feature invariants

- Dropping is gated twice: a receipt AND an age beyond the retention. A tap the phone has not confirmed is never dropped, however old.
- Strictly earlier: a tap logged exactly at the cutoff stays.
- Nothing else is touched: other observation kinds, confirmations, frames, sessions.
- A prune that drops nothing writes nothing.
- The retention (72 h) outlasts the longest local day by more than a day: the count reads only taps of local today, and a local day lasts at most 25 h.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-30201 | `WatchSessionStore` gains `pruneWaterTaps({required DateTime loggedBefore})` returning the dropped record ids in store order: it drops `water_glass` observations with a receipt (`confirmedAt != null` after confirmations are folded in, as `pruneConfirmed` reads them) whose `payload['loggedAt']` parses and is strictly earlier than the cutoff; an unparseable `loggedAt` keeps the tap. In-memory and Hive stores implement it with one shared rule. | Apple `confirmedWaterTapIds(in:loggedBefore:)`, `WatchSessionStore.swift` 440-455 |
| D-30202 | `WatchSessionEngine.pruneWaterTaps({required DateTime loggedBefore})` calls the store and trims what the engine holds in memory exactly as `pruneConfirmed` does (the observation list and the entry-correction and deletion lenses). | `watch_session_engine.dart` 2162-2177; Apple `WatchSessionEngine.swift` 2605 |
| D-30203 | `WatchWaterLimits.confirmedTapRetention` = 72 hours. `WatchWaterState.restore()` runs `engine.pruneWaterTaps(loggedBefore: clock() - 72 h)` first inside its exclusive section, then reads the held frame as before. Nothing else calls it. | Apple `WatchWater.swift` 33-41, 128-131 |
| D-30204 | Not in scope: pruning unconfirmed taps, a settings knob, pruning on a timer, any change to the water count or the phone. | plan 290 |

## Input-reality checklist

1. **Writers.** The engine stores taps; the phone's receipt confirms them; the prune runs once per launch inside the water state's exclusive gate, so a tap pressed during restore waits for it. A tap the user presses right after launch is unconfirmed and recent: never a candidate.
2. **Units.** Instants in UTC; the cutoff is plain instant arithmetic, so a zone change cannot move it.
3. **Lifecycle.** A watch that has not been opened for a month prunes a month of confirmed taps at its next launch in one write; a launch with nothing old writes nothing.
4. **Settings changing while open.** None.
5. **Time.** A launch clock that runs fast by up to 47 h cannot drop a tap a count can read (the 72 h margin); a clock far in the future could drop recent confirmed taps, whose phone copies stay: accepted (the same rule as the Apple wrist).
6. **Load.** One store read and at most one compacting write at launch.
7. **Wording.** None.
8. **Slot competition.** None.

Readers: every implementation of `WatchSessionStore` (`grep -rn "implements WatchSessionStore\|extends InMemoryWatchSessionStore" lib test`): the in-memory and Hive stores in `lib/`, and test doubles in `test/` that extend the in-memory store (inherited, no change). `WatchWaterState` callers of `restore()`: the Wear shell's boot (`wear_app.dart`) and the water tests; the existing water tests pin that a restore reads the newest frame and does not change the count, which stays true.

## Scenarios

`test/watch_water_prune_test.dart` (new; plain `test()` for the store and the engine under the in-memory store and Hive in a temp directory, as `watch_water_store_test.dart` does; the water state with the in-memory store):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-30201 | at now `2026-11-22T09:00Z`: confirmed taps logged 4 days, 73 h and 71 h earlier, an unconfirmed tap 4 days old, a confirmed `set` observation 4 days old, a confirmed tap with an unreadable `loggedAt`, a confirmed tap logged exactly at now − 72 h; cutoff now − 72 h | exactly the 4-day and 73 h confirmed taps are dropped (their ids returned in store order); the 71 h tap, the exact-cutoff tap, the unconfirmed tap, the set and the unreadable tap stay; the confirmation rows stay | an unconfirmed or recent tap is dropped, the age is not strict, or another kind is touched |
| S-30202 | S-30201 again, then a store with nothing old | the second call returns nothing and writes nothing (the stored rows are byte-for-byte as left) | a prune that finds nothing still rewrites |
| S-30203 | the engine after S-30201's fixture is restored into it | `waterLog` no longer lists the dropped taps and still lists the kept ones; an entry correction recorded for a dropped tap is gone from the lens | memory keeps a tap the store dropped |
| S-30204 | `WatchWaterState.restore()` with a clock; taps confirmed 73 h and 71 h old, an unconfirmed 5-day-old tap, and a tap of local today | the 73 h tap is gone from the store, the others stay; the snapshot's glass count equals what it was before the prune | restore does not prune, or the prune changes the count |
| S-30205 | `WatchWaterLimits.confirmedTapRetention` | equals 72 hours and is at least 49 hours | the margin shrinks below the longest local day plus a day |
| S-30206 | apply a `water_down` frame and press a tap with an old confirmed tap stored | the old tap is still there (only `restore` prunes) | the prune runs on the radio or tap path |

Guard families the lead proves by mutation: the receipt gate, the strict age comparison and its direction, the kind filter, the unreadable-time rule, the shared rule across both stores, the memory trim, the cutoff arithmetic (72 h), the call site (restore only), the idempotent no-write.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — the prune** (`crew-builder-watch`; scope `lib/watch/session/watch_session_store.dart`, `lib/watch/session/in_memory_watch_session_store.dart`, `lib/watch/session/hive_watch_session_store.dart`, `lib/watch/session/watch_session_engine.dart`, `lib/watch/nutrition/watch_water_state.dart`). Exact code in the brief. About 70 lines.
2. **P2 — tests** (lead): the new file.
3. **P3 — docs** (lead), then **Lead:** analyze, the water and session tests, the mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | The launch prune of old confirmed taps (plan 96) is not built | A launch drops the water taps the phone has confirmed that are older than 72 hours | S-30201 |
| docs/wear_os_app.md | ADDED | - | `test/watch_water_prune_test.dart` | S-30201 |

## Assumption Log

- Hive's `observations` read returns `confirmedAt` folded in from the confirmation rows (the existing `pruneConfirmed` relies on it).
- A `water_glass` observation's `loggedAt` is a UTC ISO string in its payload (`logWaterGlass`), parsed with `DateTime.tryParse`.

## Progress

- [x] P1 the prune (crew builder, 1.4 min; the lead undid the formatter's reflow in the engine)
- [x] P2 tests (lead; S-30201..S-30206, 9 tests)
- [x] P3 docs (`docs/wear_os_app.md`: the not-built sentence replaced, a tests bullet)
- [x] Verify and prove: changed files analyze clean; the water tests pass; 12 of 14 mutants killed, 2 unobservable (evidence file)
