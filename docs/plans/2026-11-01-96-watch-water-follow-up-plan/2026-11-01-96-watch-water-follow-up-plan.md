# Feature: 96 — water follow-up on the watch (series 94, PR 94c)

> Status: READY 2026-11-01 — no open questions (nothing the owner sees changes); decisions D-40..D-47 binding.
> Next handoff: @code-reviewer
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md; docs/documentation_standard.md; docs/plans/2026-11-01-95-watch-water-bar-plan/2026-11-01-95-watch-water-bar-plan.md (D-22..D-39, S-94b-*; read D-25, D-26, D-27, D-34, D-37, D-39) and its `.review.md` (F6, F8, F9); docs/plans/2026-11-01-94-watch-water-logging-plan/2026-11-01-94-watch-water-logging-plan.md (Series 94 index; plan 94 D-2, D-7).
> Branch: the one checked out; never create or switch branches; never commit, stash, reset or check out (the governor owns git). Evidence goes in `2026-11-01-96-watch-water-follow-up-plan.evidence.md` beside this file; review findings in `….review.md`.
> Shared tree: another session holds uncommitted files (`lib/core/utils/{food_helpers,macro_targets,macro_energy}.dart`, `lib/state/workout/*`, `lib/state/watch/watch_session_adoption_bridge.dart`, `docs/state_management/workout_state.md`, Dart tests `food_form_serving`, `library_row_toggle`, `watch_live_refresh_screen`, `watch_routine_adoption`, `watch_session_merge`, `scripts/*.sh`). None is a predicted file here; never touch, format or revert them.

## Overview

PRs 94a (ea646be0) and 94b (baa8b6be) shipped the water bar on the watch's Nutrition screen. This PR changes nothing the owner sees. It fixes three review findings of plan 95:

- **F6.** One redraw of the bar computes today's taps about five times. Each pass filters every stored observation and parses a date for every water tap ever stored. D-37 keeps taps forever, so the cost grows for the life of the install (about 3,000 taps a year).
  - Fix: one pass per redraw.
  - Fix: only the taps whose day id can fall on local today get their date parsed.
  - Fix: confirmed taps older than a safe cutoff are dropped at launch. D-43 supersedes D-37.
- **F8.** The straggler check in S-94b-18 sits past the 20 s cap, so it cannot fail. Move it inside the cap.
- **F9.** The banned-wording scan (Dart test S-901) does not read `WatchWater.swift`. Add it.

Out of scope:
- F10 (the engine's unguarded observation list, pre-existing).
- Any phone, Dart-twin or sync-protocol change.
- Any visible change.

## Resolved Decisions (Ledger)

Series numbering continues after plan 95's D-39. Plan 94 D-1..D-21 and plan 95 D-22..D-39 bind unchanged, except D-37, which D-43 supersedes.

- **D-40 One pass per read, never a cache (F6).** `WatchWaterState.snapshot` returns a `WatchWaterSnapshot`: `glasses`, `canAdd`, `canRemove`, and `spokenCount` (= `WatchWaterCopy.spokenCount(glasses)`).
  - It is computed by D-25/D-27 from one `clock()` read and ONE read of the tap log (`engine.waterLog`).
  - `glasses`, `canAdd` and `canRemove` on the state stay. Each returns its field of one fresh snapshot.
  - `press(_:)` decides its rule on one snapshot.
  - Values are unchanged for every input (I-11).
  - Rejected: caching today's taps and invalidating on press, frame and restore. It also needs invalidation on receipts, the minute tick, midnight, clock and zone changes; a missed one shows a stale number. D-25's "computed on every read, never cached" and I-6 stand.
- **D-41 Parse only the candidates (F6).** Before parsing `loggedAt`, a tap is kept as a candidate only when its envelope `sessionId` equals `WatchNutritionSession.idFor(x)` for some instant x of local today (in the state's calendar). Every other tap is skipped unparsed.
  - Exact by construction. D-22 stores every tap under `idFor(loggedAt)`, the UTC date of the tap. Local today lasts at most 25 h, so its instants span at most three UTC dates.
  - Candidates are then judged by D-25 exactly (`calendar.isDate(loggedAt, inSameDayAs: now)`).
  - Mechanic hint, not binding: `idFor` of the day's first instant, its midpoint and its last instant yields exactly that set.
- **D-42 The model and the bar read one snapshot.** `WatchWaterModel` exposes `snapshot` and `press(_:)`. Its `glasses`, `canAdd`, `canRemove` and `spokenCount` accessors are removed, so no view can re-read them separately.
  - `WatchWaterBar` binds `let snapshot = model.snapshot` once, as the first statement inside the `TimelineView(.everyMinute)` closure, so the minute tick still re-reads (D-34).
  - Every control reads `snapshot.` (`.disabled(!snapshot.canRemove)`, `Text("\(snapshot.glasses)")`, `.accessibilityValue(snapshot.spokenCount)`, `.disabled(!snapshot.canAdd)`).
  - Presses stay `model.press(.add)`/`model.press(.remove)` (D-39).
- **D-43 supersedes D-37: launch drops old confirmed taps.** `WatchWaterState.restore()` drops stored water taps, inside its gate and before it holds the frame. A tap is dropped only when all of these hold:
  - its kind is `water_glass`;
  - a receipt names it (its `confirmedAt` is folded from confirmation rows);
  - its `loggedAt` parses and is strictly earlier than `clock() − WatchWaterLimits.confirmedTapRetention` (72 h).

  What is never dropped:
  - an unconfirmed tap, at any age;
  - a tap whose `loggedAt` cannot be read;
  - any row of another kind;
  - the confirmation rows themselves. They are kept, as `pruneConfirmed` keeps them, so `knowsObservation` still knows a dropped tap ("acknowledged and pruned since").

  `onWaterChanged` still fires once per restore. The drop runs at restore only (once per launch), not after frames or receipts. That keeps the new writer of the engine's observation list off the radio path (F10). A launch already reads the whole store. `pruneConfirmed()` keeps no production caller.

  **Why 72 h.**
  - The fold and the cap read only taps on local today (D-25, D-26).
  - Local today, in any calendar, contains now and lasts at most 25 h (a fall-back DST day). So it starts no earlier than now − 25 h, whatever zone the wrist was in when it stored the tap and whatever zone it is in now.
  - A tap logged before now − 25 h is therefore unreadable by every count in every zone.
  - The retention keeps a margin of at least one full day beyond that (it must be ≥ 49 h). 72 h gives a 47 h margin: a launch-time clock up to 47 h fast still drops nothing a count can read.
  - It is instant arithmetic, with no calendar, so a zone change cannot move the cutoff.
  - A clock even further ahead can drop a confirmed tap of the real today. If the held frame lists it, the count is unchanged. Otherwise the count is short by it until the next frame (the next sync). Accepted.
  - Plan 94 D-7 is unaffected: a dropped tap is never on local today.
- **D-44 The sixth prune.** New store operation `WatchSessionStore.pruneWaterTaps(loggedBefore: Date) async -> [String]`. It implements D-43's row rule and returns the dropped record ids.
  - In-memory and file stores alike. The file store compacts once when something drops and writes nothing when nothing does (D-3821, the `pruneBests` rule).
  - `testS004NoMutatingOperationExistsAnywhereInTheModule`'s allowed set gains it on purpose; its comment says "sixth".
  - Engine `pruneWaterTaps(loggedBefore:)` delegates to the store and drops the returned ids from its in-memory observation list and lens maps, exactly as `pruneConfirmed()` does.
  - Swift-only, like `pruneBests`/`pruneWater`: `grep -rln "pruneBests\|pruneWater" lib test` → empty, so no Dart store mirrors these prunes.
  - The name starts with `prune`, never a verb S-004 bans.
- **D-45 Counting seams (technical).** `WatchWaterState` takes two non-public, defaulted seams: the tap-log reader (default `{ engine.waterLog }`) and the `loggedAt` parser (default: `parseUtcIso`). Tests count reads and parses through them.
  - The host's call `WatchWaterState(engine: engine, store: store)` is unchanged (S-94b-23).
  - A counting store wrapper also asserts zero `readAll` per read. Alone it cannot catch F6: the bar never reads the store, before or after this PR. The tap-log and parse counts are the regression detectors.
- **D-46 The two test fixes.**
  - F8: S-94b-18's straggler moves to t0+5, after the quiet end (t0+4.5) and inside the 20 s cap, so it fails when `noteArrival`'s `isActive` guard is removed (S-94b-18a). The method name stays, because two docs cite it.
  - F9: S-901's native-surfaces list in `test/watch_logging_surfaces_test.dart` gains `'WatchWater.swift'` (S-94c-6). This is the only Dart file this PR edits; plan 95 D-36 bound 94b only.
  - New water copy and quoted comment text avoid S-901's banned terms. The scan reads every quoted literal, comments included.
- **D-47 Docs (sizes 2026-11-01; the fail line is 52,429 B, `test/docs_indexing_contract_test.dart`).**
  - `docs/state_management/watch_reference_data.md` 22,557 B: replace the "never pruned … has no caller" sentence (~l.325-327) with D-43 in words plus pointers to S-94c-10 and S-94b-25a; ≤ +450 B.
  - `docs/state_management/watch_sensors.md` 31,559 B: in "Every prune is gated on having nothing to lose" (~l.416-430), one clause for the tap prune plus a pointer to S-94c-10; ≤ +300 B.
  - `docs/state_management/watch_surface.md` 52,167 B (262 B under the line): edit only the receipt paragraph (~l.761-764). Delete ", the only way the observation box gives rows back," and update the test name to S-94b-25a's. Net size must not grow.
  - Not edited, each re-read and still true:
    - `docs/nutrition.md`;
    - `docs/state_management/watch_surface_wrist.md` (cites `testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply`, a name kept by D-46);
    - `docs/watch-app-qa-wrist-logging.md` (no owner step: nothing visible changes).
  - Docs name `confirmedTapRetention`, never its value (§3.4).

## Feature Invariants (this PR)

- **I-11** For every store content, clock and calendar, `glasses`, `canAdd` and `canRemove` equal plan 95 D-25/D-27. S-94b-3..S-94b-16 pass unedited.
- **I-12** (supersedes plan 95 I-10) No unconfirmed tap, no tap logged within `confirmedTapRetention` of now, and no non-tap row is ever dropped. The tap prune has exactly one caller, `WatchWaterState.restore()`.
- **I-6** (plan 95) stands: no count is stored anywhere.

## Requirements

- R-1 A bar redraw reads the tap log once and parses only candidate taps (D-40..D-42, D-45).
- R-2 Launch drops confirmed taps older than the retention, and nothing else (D-43, D-44).
- R-3 The straggler check of S-94b-18 can fail (D-46).
- R-4 The banned-wording scan reads `WatchWater.swift` (D-46).

## Acceptance Criteria

- AC-1 One tap-log read and candidate-only parses per read, on thousands of taps → S-94c-1, S-94c-3, S-94c-4.
- AC-2 Counts unchanged, across zones and midnight → S-94c-2, S-94b-3..16 (unedited).
- AC-3 The bar reads one snapshot → S-94c-5.
- AC-4 The prune drops exactly D-43's set, on both stores, and is idempotent → S-94c-10, S-94c-11.
- AC-5 A zone change across a relaunch → S-94c-12.
- AC-6 Guards → S-94b-18a, S-94b-25a, S-94c-6.

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchWaterState.glasses/canAdd/canRemove` | `grep -rn "\.glasses\b\|canAdd\|canRemove" watch/watchos/Sources "ios/OmniTrain Watch App"`: `WatchWater.swift` (model, `press`), `WatchNutritionView.swift` bar l.198-222. Tests: `WatchWaterStateTests`, `WatchWaterSyncTests` | same values, one pass each | I-11; S-94b-3..16 unedited |
| `WatchWaterModel` accessors | bar only (l.198, 203, 210, 222); `ContentView.swift` reads none. Tests: S-94b-21 (`WatchWaterStateTests`); needles in `WatchWaterBarSourceTests` l.232, 338, 346, 365, 370 | removed (D-42); test literals move to `snapshot.`, with assertions otherwise unchanged | S-94c-5 |
| `engine.waterLog` | `grep -rn "waterLog" watch/watchos/Sources "ios/OmniTrain Watch App"` → engine declaration plus `WatchWater.swift` l.223, l.242 only | read once per snapshot | S-94c-1 |
| `WatchSessionStore` protocol | conformers: InMemory, File, `StaleReadStore` (`WatchNutritionQuickLogTests` l.157), `SuspendingStore` (`WatchEffortRatingTests` l.160), `ContendedWatchSessionStore` (`WatchSensorRecordingTests` l.1046), plus Phase 1's counting wrapper | each forwards `pruneWaterTaps` | S-004 (allowed set +1) |
| Engine observation list loses rows | readers (plan 95 impact table, re-grepped): `observations`/`projectedEntries` (workout session id), sensor-prune gate, rest follow-on, `nutritionLog` (kind), `pendingObservations`/`unconfirmedObservations` (unconfirmed only, never dropped), `knowsObservation` (via `acknowledgedObservationIds`, whose confirmation rows are kept) | no effect | S-94c-10 (food and set kept; pending ids unchanged) |
| Confirmation rows | `applyConfirmations` (both stores), engine `restore` l.149 | untouched | S-94c-10 |
| `WatchWaterState.restore()` | `ContentView.swift` l.342 (once, from the root `.task`, after `engine.restore()`), tests | gains the prune; one `onWaterChanged` as before | S-94c-10, S-94b-4 unedited |
| File store compaction | `pruneWaterTaps` only | one rewrite when a tap drops, none otherwise | S-94c-11 |
| `WatchSyncProgress.noteArrival` | source unchanged | test instant moves | S-94b-18a |
| Dart S-901 scan | test only | reads one more file | S-94c-6 |
| Phone, Dart twin, protocol | `grep -rln "pruneBests\|pruneWater" lib test` → empty; tap storage is not on the wire | none (out of scope) | D-44 |
| Standing invariants | hive import grep (AGENTS.md); `ui_standards_contract_test`, `docs_indexing_contract_test`; append-only S-004 (deliberate sixth prune); InMemory↔File parity (S-94c-10 runs on both) | — | Done Criteria |

## UI Standards Impact

None. The SwiftUI bar reads one value per redraw and looks and behaves the same. No allowlist entry and no ratchet change.

## Scenarios

**Fixture X** (as plan 95):
- Calendar: Gregorian, `TimeZone(secondsFromGMT: 10800)`. Local time is UTC+3, so the local day turns at 21:00Z.
- `TestClock` at `2026-11-01T09:00:00Z` (12:00 local) unless stated.
- The id factory yields `w-1`, `w-2`, … in call order.
- Engine and `WatchWaterState` over one store, with `Harness.validator()`.
- `frame(gen, day, glasses, ids)`: `fixtures/valid/water_down.json` with that payload.
- `receipt(ids)`: `fixtures/valid/receipt.json`, delivered through `engine.applyMessage`.

**Tap rows and counters:**
- "Tap c at t" = a stored `water_glass` row shaped exactly like `logWaterGlass(c, loggedAt: t)`'s. Seeding many may append the rows to the store and then call `engine.restore()`; assert one seeded row equals one logged row field for field.
- Session ids are the UTC date of t.
- `reads` = tap-log reads and `parses` = `loggedAt` parses, both through D-45's seams. `storeReads` = `readAll` calls on a counting wrapper store.

**History H:** 2,920 unconfirmed add taps, 8 per day, for 2025-11-01 through 2026-10-31.
- That span is 30+31+31+28+31+30+31+30+31+31+30+31 = 365 days, and 365 × 8 = 2,920.
- Each day d has taps at d T06:00Z + i h, i = 0..7 (06:00Z to 13:00Z), so every session id is `nutrition-<d>`.

### S-94c-1: one tap-log read and candidate-only parses, on 2,924 taps (performance)
- Fixture:
  - X over a counting wrapper store;
  - H;
  - today: add 06:00Z, add 06:30Z, remove 07:00Z, add 07:30Z (2026-11-01);
  - no frame.
- Trigger: one `snapshot`; then `glasses`, `canAdd`, `canRemove` once each; then `model.snapshot` once.
- Expected:
  - The snapshot is `glasses` 2 (0 +1 +1 −1 +1), `canAdd` true (4 < `tapsPerDay`), `canRemove` true, `spokenCount` "2 glasses".
  - Every one of the five reads: `reads` == 1, `storeReads` == 0, `parses` ≤ 12.
  - The candidates are local today 11-01 = [10-31T21:00Z, 11-01T21:00Z), whose UTC dates are {10-31, 11-01}. That gives H's 8 taps of 10-31 plus the 4 of today. The other 2,912 are never parsed.
- Mutations:
  - no candidate filter → parses 2,924 → red;
  - `canRemove` computed by separate passes → reads ≥ 2 → red.
- Edge case of: none.

### S-94c-2: the filter is exact across zones, DST and local midnight
- Fixture: clock `2026-11-01T11:00:00Z`; no frame. Taps p1..p9, all adds except p6 (remove):

  | Tap | loggedAt | Session id |
  |---|---|---|
  | p1 | 2026-10-31T11:59:59Z | 10-31 |
  | p2 | 2026-10-31T12:00:00Z | 10-31 |
  | p3 | 2026-10-31T18:15:00Z | 10-31 |
  | p4 | 2026-10-31T20:59:59Z | 10-31 |
  | p5 | 2026-10-31T21:00:00Z | 10-31 |
  | p6 (remove) | 2026-11-01T03:59:59Z | 11-01 |
  | p7 | 2026-11-01T04:00:00Z | 11-01 |
  | p8 | 2026-11-01T10:00:00Z | 11-01 |
  | p9 | 2026-11-01T10:59:59Z | 11-01 |

  Plus 300 distractor adds at `2026-10-01T00:00:00Z` + k·2 h, k = 0..299 (last 10-25T22:00Z).
- Trigger: one state per calendar over the same store; `snapshot` and `parses` for each.
- Expected (local today, today's taps folded, glasses, parses ≤):

  | Calendar | Local today | Fold | Glasses | Parses ≤ |
  |---|---|---|---|---|
  | UTC+3 | [10-31T21:00Z, 11-01T21:00Z) | p5 +1, p6 −1, p7, p8, p9 | 3 | 9 |
  | UTC+14 (`secondsFromGMT 50400`) | 11-02 = [11-01T10:00Z, 11-02T10:00Z) | p8, p9 | 2 | 4 (p6..p9) |
  | UTC−12 (`−43200`) | 10-31 = [10-31T12:00Z, 11-01T12:00Z) | p2 1, p3 2, p4 3, p5 4, p6 3, p7 4, p8 5, p9 6 | 6 | 9 |
  | `America/New_York` (DST ends 06:00Z this day, a 25 h day) | [11-01T04:00Z, 11-02T05:00Z) | p7, p8, p9; p6 is 1 s before | 3 | 4 |
  | `Asia/Kathmandu` (+5:45) | [10-31T18:15Z, 11-01T18:15Z) | p3 at the exact local midnight 1, p4 2, p5 3, p6 2, p7 3, p8 4, p9 5 | 5 | 9 |

  - UTC+3: p5 is the exact local midnight; p4 (23:59:59 on 10-31) shares p5's session id and is excluded.
  - No distractor is ever parsed.
- Edge case of: plan 95 S-94b-3, S-94b-14.

### S-94c-3: the cap holds with a long history
- Fixture: X over a counting wrapper store; H; 500 adds today at `2026-11-01T00:00:00Z` + i s, i = 0..499 (03:00 local).
- Trigger: `snapshot`; `press(.add)`; `press(.remove)`.
- Expected:
  - `glasses` 500, `canAdd` false, `canRemove` false;
  - both presses return false, store no row and emit nothing; `waterLog.count` stays 3,420;
  - per snapshot: `reads` 1, `parses` ≤ 508 (8 + 500).
- Edge case of: S-94b-15.

### S-94c-4: an empty store
- Fixture: X over a counting wrapper store; no taps; no frame.
- Trigger: `snapshot`.
- Expected: (0, true, false, "0 glasses"); `reads` 1, `parses` 0, `storeReads` 0.
- Edge case of: S-94b-8.

### S-94c-5: the bar reads one snapshot per redraw
- Fixture: `WatchNutritionView.swift` and `WatchWater.swift`, comment lines stripped.
- Trigger: source scan.
- Expected:
  - In `WatchWaterBar`'s body, `model.snapshot` occurs exactly once, as `let snapshot = model.snapshot`, the first statement after `TimelineView(.everyMinute) {`.
  - Zero occurrences of `model.glasses`, `model.canAdd`, `model.canRemove` or `model.spokenCount` anywhere in Sources or the app.
  - `WatchWaterModel`'s body declares no `var glasses`, `var canAdd`, `var canRemove` or `var spokenCount`.
  - S-94b-22/24's assertions hold with the `snapshot.` needles.
- Mutation: a second `model.snapshot` read or a `model.glasses` read → red.
- Edge case of: S-94b-24.

### S-94b-18a (supersedes S-94b-18's progress half): a straggler inside the cap does not revive a finished sync
- Fixture: `WatchSyncProgress` with a clock at t0; `begin(at: t0)`; `noteArrival("routines_down", t0+1)`; `noteArrival("water_down", t0+2.5)`.
- Trigger: `isActive(t0+4)`, `isActive(t0+4.6)`; then `noteArrival("water_down", t0+5)`; `isActive(t0+5)`, `isActive(t0+6)`.
- Expected: true, false, false, false.
- Mutation: remove `isActive(at: now),` from `noteArrival`'s guard → `isActive(t0+5)` true → red.
- The receive half of S-94b-18 is unchanged.
- Edge case of: S-94b-17.

### S-94c-6: the banned-wording scan reads the water copy
- Fixture: `test/watch_logging_surfaces_test.dart` S-901; `watch/watchos/Sources/WatchSessionEngine/WatchWater.swift`.
- Expected:
  - the scanned list contains the file, and the test passes;
  - a missing file fails the read.
- Mutation: `WatchWaterCopy.countLabel = "Water, try to drink"` → red, with the reason naming `WatchWater.swift`. Restore it afterwards.
- Edge case of: none.

### S-94c-10: launch drops only old confirmed taps (both stores)
- Fixture: X, run once on an `InMemoryWatchSessionStore` and once on a `FileWatchSessionStore` in a fresh temp directory. Cutoff = 09:00Z − 72 h = `2026-10-29T09:00:00Z`. Rows, in seeding order:

  | Id | Row | Confirmed | Expected at launch |
  |---|---|---|---|
  | w-1 | add 2026-10-20T08:00:00Z | yes | dropped |
  | w-2 | add 2026-10-29T08:59:59Z | yes | dropped (1 s before the cutoff) |
  | w-3 | add 2026-10-29T09:00:00Z | yes | kept (exactly the cutoff) |
  | w-4 | add 2026-10-31T19:00:00Z | yes | kept (yesterday 22:00 local) |
  | w-5 | add 2026-10-29T06:30:00Z | no | kept (three days ago, older than the cutoff) |
  | w-6 | remove 2026-10-25T10:00:00Z | no | kept |
  | w-7 | add 2026-11-01T06:00:00Z | yes | kept |
  | w-8 | add 2026-11-01T07:00:00Z | no | kept |
  | w-9 | food `logNutrition(foodId: "f-1", servings: 1, loggedAt: 2026-10-20T08:00:00Z)` | yes | kept |
  | s-1 | a `set` in workout session `w9` (`createSession` with one lift slot) | yes | kept |

  - `receipt(["w-1","w-2","w-3","w-4","w-7","w-9","s-1"])`.
  - Held frame: `frame(08:30Z, "2026-11-01", 4, ["w-7"])`.
- Trigger:
  - Build the population through one engine and state (the frame applied with `applyWaterDown`), and read the count.
  - Then a launch: a new engine and state over the same store, `engine.restore()`, `water.restore()`.
- Expected:
  - Dropped exactly {w-1, w-2}, from the store and from `engine.waterLog`.
  - `waterLog` = [w-3, w-4, w-5, w-6, w-7, w-8] in store order.
  - w-9 is in `nutritionLog`; s-1 is still stored.
  - The confirmation row count is unchanged; one water frame row remains.
  - The unconfirmed water-tap ids are [w-5, w-6, w-8] before and after.
  - Shown 5 before and after (base 4; w-7 listed; w-8 +1). The launch fires one `onWaterChanged`.
  - `WatchWaterLimits.confirmedTapRetention` ≥ 49 h (25 h longest local day + 24 h margin, D-43).
- Mutations:
  - unconfirmed taps dropped → w-5/w-6 missing → red;
  - `<=` → w-3 dropped → red;
  - kind ignored → w-9/s-1 dropped → red;
  - engine memory not trimmed → w-1 still in `waterLog` → red;
  - retention 24 h → the margin check and w-3 → red.
- Edge case of: none.

### S-94c-11: relaunch after pruning
- Fixture: S-94c-10 on the file store, after its launch.
- Trigger:
  - (a) A second launch: new store, engine and state over the same directory, same clock.
  - (b) A fresh `FileWatchSessionStore` over the same directory, with a torn tail appended (bytes `{"recordType":"obs` with no newline); then `pruneWaterTaps(loggedBefore: 2026-10-29T09:00:00Z)`.
  - (c) A third launch with the clock at `2026-11-04T09:00:01Z` (cutoff `2026-11-01T09:00:01Z`).
- Expected:
  - (a) Nothing dropped; shown 5; the unconfirmed water taps are [w-5, w-6, w-8], and their `pendingObservations()` envelopes carry `msg-w-5`, `msg-w-6`, `msg-w-8`, as before the first launch.
  - (b) Returns []; the file is byte-identical, torn fragment included.
  - (c) Drops {w-3, w-4, w-7}; keeps w-5, w-6, w-8; shown 0 (frame day 11-01 ≠ local 11-04; no tap today); `canRemove` false.
- Mutation: compact even when nothing drops → (b) red.
- Edge case of: S-94c-10, S-94b-16.

### S-94c-12: a time-zone change across a relaunch
- Fixture: X (UTC+3), InMemory store, with:
  - A = w-1 add `2026-10-31T12:00:00Z`;
  - C = w-2 add `2026-10-31T09:59:00Z`;
  - B = w-3 add `2026-11-01T08:00:00Z`;
  - `receipt(["w-1","w-2"])`;
  - `frame(08:30Z, "2026-11-01", 2, [])`.
- Trigger: (a) launch under UTC+3; (b) relaunch with a new engine and state, calendar `secondsFromGMT −36000` (UTC−10), same clock; (c) relaunch under UTC+14 (`50400`).
- Expected:
  - (a) Base 2, plus B → 3 (A and C are 10-31 local).
  - (b) Local now is 10-31 23:00, today = [10-31T10:00Z, 11-01T10:00Z). Frame day 11-01 ≠ 10-31, so base 0. A +1, B +1, C excluded (09:59Z) → 2. Nothing dropped (A and C are 21 h and 23 h old).
  - (c) Local now is 11-01 23:00, same window, frame day matches → 2 + A + B = 4. That is D-25 under the current calendar; the phone/watch zone split stays out of scope (plan 94 D-7, plan 95 D-26).
- Edge case of: S-94c-2.

### S-94b-25a (supersedes S-94b-25): `pruneConfirmed()` has no caller; only launch prunes taps
- Fixture: `watch/watchos/Sources` and `ios/OmniTrain Watch App`, comments stripped.
- Expected:
  - zero `pruneConfirmed(` outside its declarations and the engine's own delegation (as before);
  - `pruneWaterTaps(` outside its declarations and the engine's store delegation occurs exactly once, in `WatchWater.swift` inside `restore()`;
  - the failure message names plan 96 D-43.
- Test renamed `testS94b25aPruneConfirmedHasNoCallerAndOnlyLaunchPrunesTaps`.
- Mutation: a second caller (e.g. in `applyWaterDown`) → red.
- Edge case of: none.

Mutation rule (every mutation above): hand-edit from a byte copy, run, restore, confirm `cmp` identical, record in the evidence. Never `git stash`.

## Iteration 1

### Phase 1: One read per redraw, and the two test fixes (@developer)
1. [x] Snapshot and filter — `watch/watchos/Sources/WatchSessionEngine/WatchWater.swift` · `WatchWaterSnapshot`; `WatchWaterState.snapshot` (D-40). `glasses`, `canAdd`, `canRemove` delegate to it; `press(_:)` uses one; the candidate filter goes inside today's taps (D-41).
2. [x] Seams — same file · D-45's two defaulted non-public seams; the host call is unchanged.
3. [x] Model — same file · `WatchWaterModel.snapshot`; remove its four accessors (D-42).
4. [x] Bar — `WatchNutritionView.swift` · `WatchWaterBar`: `let snapshot = model.snapshot` first in the `TimelineView` closure; the controls read `snapshot.` (D-42).
5. [x] Tests (new) — `Tests/WatchSessionEngineTests/WatchWaterSnapshotTests.swift`: S-94c-1..S-94c-4, with a counting wrapper store (forwards every store method).
6. [x] Tests (edited) — `WatchWaterStateTests.swift` S-94b-21 reads through `model.snapshot` (values unchanged). `WatchWaterBarSourceTests.swift`: S-94b-22/24 needles become `snapshot.`, plus a new S-94c-5 test.
7. [x] F8 — `WatchWaterSyncTests.swift` · `testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply` per S-94b-18a; the name is kept.
8. [x] F9 — `test/watch_logging_surfaces_test.dart` · S-901's native list gains `'WatchWater.swift'` (S-94c-6).

**Done Criteria** (run until green):
- Record the baseline in the evidence first. Plan 95 closed at 1181 swift tests.
- `.github/copilot/scripts/macos/gateway.sh swift-test`: 0 failures; count = baseline + new; S-94b-3..16 unedited and green.
- `gateway.sh test test/watch_logging_surfaces_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`: all pass.
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` is empty.
- These mutations are red, then green, in the evidence: S-94c-1 (both), S-94c-5, S-94b-18a, S-94c-6.
- Watch target build. The bar is watchOS-only code. Run `xcodebuild build -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -sdk watchsimulator -configuration Debug SYMROOT=<fresh scratch> OBJROOT=<fresh scratch> CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
  - Claude Code: wrap it in `bash .claude/scripts/macos/with-timeout.sh 600`.
  - Copilot: the gateway has no such check. State that the view was not compiled; the governor builds before review.
- Docs: none invalidated. `watch_surface.md` l.374 still names `WatchWaterModel` truly.

**Predicted Files**:
- `watch/watchos/Sources/WatchSessionEngine/{WatchWater,WatchNutritionView}.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/{WatchWaterStateTests,WatchWaterBarSourceTests,WatchWaterSyncTests}.swift`
- `WatchWaterSnapshotTests.swift` (new)
- `test/watch_logging_surfaces_test.dart`
- this plan; the evidence file

### Phase 2: Launch drops old confirmed taps (@developer)
1. [x] Store contract — `WatchSessionStore.swift` · protocol `pruneWaterTaps(loggedBefore:)` with its gate comment, the InMemory implementation, and header "six ways". The `pruneWater` comment drops "(D-37)" → "taps leave only through `pruneWaterTaps` (plan 96 D-43)" (D-44).
2. [x] File store — `FileWatchSessionStore.swift` · `pruneWaterTaps` and its locked body: one `compact` when something drops, no write otherwise.
3. [x] Conformers and S-004:
   - forward the method in `StaleReadStore` (`WatchNutritionQuickLogTests.swift`), `SuspendingStore` (`WatchEffortRatingTests.swift`), `ContendedWatchSessionStore` (`WatchSensorRecordingTests.swift`) and Phase 1's wrapper (`WatchWaterSnapshotTests.swift`);
   - in `WatchSessionEngineTests.swift`, S-004's allowed set gains `pruneWaterTaps`, and its comment says "sixth" and cites D-43/D-44.
4. [x] Engine — `WatchSessionEngine.swift` · `pruneWaterTaps(loggedBefore:)` beside `pruneConfirmed()`, with the same memory and lens cleanup. The header comment (l.16-18) names the tap prune.
5. [x] Launch — `WatchWater.swift` · `WatchWaterLimits.confirmedTapRetention` with the D-43 derivation in its comment. `restore()` calls the engine prune with `clock() − retention`, inside the gate and before reading the frame. Update the file header.
6. [x] Guard — `WatchWaterBarSourceTests.swift` · S-94b-25 → S-94b-25a (rename, rule, message); the header's "D-37" → "D-43 (supersedes D-37)".
7. [x] Tests (new) — `Tests/WatchSessionEngineTests/WatchWaterPruneTests.swift`: S-94c-10 (both stores), S-94c-11, S-94c-12.
8. [x] Docs — per D-47: `watch_reference_data.md`, `watch_sensors.md`, `watch_surface.md` (net ≤ 0 B). Each claim points at its test by class and method name.

**Done Criteria** (run until green):
- `gateway.sh swift-test`: 0 failures. These pass unedited: `testS005UnconfirmedEntriesAreNeverPruned`, `testS94b4APruneNamingAnAbsentRowDropsNothingAndWritesNothing`, `testS94b4ThePruneTouchesNoOtherKindOfRow`, S-94b-3..16.
- Mutations of S-94c-10 (all five), S-94c-11 and S-94b-25a are red, then green, in the evidence.
- `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart test/watch_logging_surfaces_test.dart`.
- The hive grep is empty.
- `wc -c` of the three docs: each < 52,429 B, and `watch_surface.md` ≤ its pre-edit size. Record them.
- Residue: `grep -rn "TapsAreNeverPruned\|five ways\|never pruned — the count" watch/watchos/Sources watch/watchos/Tests "ios/OmniTrain Watch App" docs --exclude-dir=plans --exclude-dir=history --exclude-dir=.build` → no hits. Every remaining `D-37` hit there says it is superseded by D-43.
- No watchOS-only file changes in this phase (`swift test` compiles every touched file). The governor's one pre-review watch build covers the PR.

**Predicted Files**:
- `watch/watchos/Sources/WatchSessionEngine/{WatchSessionStore,FileWatchSessionStore,WatchSessionEngine,WatchWater}.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/{WatchNutritionQuickLogTests,WatchEffortRatingTests,WatchSensorRecordingTests,WatchSessionEngineTests,WatchWaterBarSourceTests,WatchWaterSnapshotTests}.swift`
- `WatchWaterPruneTests.swift` (new)
- `docs/state_management/{watch_reference_data,watch_sensors,watch_surface}.md`
- this plan; the evidence file

## Files Affected (whole PR)

- **Production (Swift, ≈ 150-200 lines):** `WatchWater.swift`, `WatchNutritionView.swift`, `WatchSessionStore.swift`, `FileWatchSessionStore.swift`, `WatchSessionEngine.swift`.
- **Tests:**
  - new: `WatchWaterSnapshotTests.swift`, `WatchWaterPruneTests.swift`;
  - edited: `WatchWaterStateTests`, `WatchWaterBarSourceTests`, `WatchWaterSyncTests`, `WatchNutritionQuickLogTests`, `WatchEffortRatingTests`, `WatchSensorRecordingTests`, `WatchSessionEngineTests` (all `.swift`), and the Dart `test/watch_logging_surfaces_test.dart`.
- **Docs:** three files (D-47).
- **Read-only dependents, green and unedited:**
  - `ios/OmniTrain Watch App/ContentView.swift`;
  - `WatchSyncProgress.swift`;
  - `docs/nutrition.md`, `docs/state_management/watch_surface_wrist.md`;
  - every `lib/` file and `lib/watch/**`;
  - `watch/sync_protocol/**`, `watch/contract/**`.

## Notes

- **Dependency graph:** 1 → 2. Phase 2 adds a protocol requirement that Phase 1's counting wrapper must forward.
  - Running Phase 2 first works too: the wrapper then forwards from birth.
  - Neither order shows anything to the owner.
- **Intermediate states:** both are green and invisible. After Phase 1 a redraw costs one pass; taps are still kept forever. After Phase 2 a launch also bounds the stored taps.
- **Pre-existing, not changed:**
  - The host builds `WatchWaterState` with `Calendar.current`, a snapshot taken at construction. A zone change while the app stays alive moves the day boundary only at the next launch (S-94c-12 drives it by relaunch).
  - F10: the engine's observation list is unguarded. The new removal runs at launch, in the same window as `engine.restore()`'s own assignment.
  - Confirmation rows still grow by one per receipt. D-43 keeps them on purpose.
- **Governor:** one watch-target build before review. No owner device step, no QA-guide step, no simulator walk.
- **Budget** (`.github/copilot/pr-scope-budget.md` §1): 2 phases, one track (watch) plus one Dart test-file edit, 8 decisions, 12 scenarios, ≈ 200 production lines. No soft signal, no hard limit: one PR.

## Progress

- [x] Phase 1 One read per redraw, and the two test fixes — @developer — **Complete** 2026-11-01: swift 1186/0 (1181 + 5), Dart 3 files +87 pass, watch build SUCCEEDED, M1-M6 red→green (evidence).
- [x] Phase 2 Launch drops old confirmed taps — @developer — **Complete** 2026-11-01: swift 1191/0 (1186 + 5), red 11 on both stores first, M7-M13 red→green, Dart contracts +87, flutter TZ=UTC +6024 ~2 (local −21 DST-day only), docs within D-47 (evidence).
- [ ] Review — @code-reviewer

## Assumption Log

- Executors append here (≤ 3 lines each: decision, options considered, choice and why). The reviewer ratifies (→ D-x) or reverts (→ remediation).
- A-1 (Phase 1, D-41) Candidate ids: walk UTC midnights across `calendar.dateInterval(of: .day)` instead of the first/mid/last hint; exact for any day length, same set for ≤ 25 h. No interval → no filter (every tap parsed, I-11 kept).
- A-2 (Phase 1, D-45) Seams are parameters of an internal designated init; the public init (host call unchanged) is a `convenience init` passing the defaults. Options: defaulted public params (would make seams public) — rejected.
- A-3 (Phase 1) `press(_:)`'s post-store check `engine.waterLog.contains(tap)` stays a direct engine read, not the seam: it is not part of a redraw, and S-94c-3 counts per snapshot only.
- A-4 (Phase 2, D-44) One row rule for both stores: internal free `confirmedWaterTapIds(in:loggedBefore:)` in `WatchSessionStore.swift` (column 0, outside S-004's store-surface scan). The engine's memory cleanup is a private `trimPrunedObservations(_:)` shared with `pruneConfirmed()`, so both trim exactly alike. Option rejected: two copies of each.
- A-5 (Phase 2, S-94c-10) The scenario gives s-1 no instant: it is logged at 2026-10-20T08:00Z so the kind-ignored mutant drops it too. The file-store launch uses a fresh `FileWatchSessionStore` over the same directory (a real relaunch) rather than the same instance.
- A-6 (governor, review minors) The one-line 94c row in plan 94's series table is sanctioned plan maintenance, not a Predicted File. The engine header's prune sentence now points at the store header's list of all six prunes.

## Feedback

Review written to `2026-11-01-96-watch-water-follow-up-plan.review.md` — Verdict: APPROVE, 0 blocker / 0 major / 2 minor (a plan-94 index row outside the Predicted Files; the engine header's partial drop list).
