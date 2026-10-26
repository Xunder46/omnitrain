# Feature: 62 — a wrist raise no longer re-sends what the watch already holds

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (APPROVE WITH MINORS; uncommitted; owner device checks open). Owner: watch audit 3 (2026-10-23), fix order item 6, in chat. Series: with plan 61. Base commit: `.work/2026-10-23-62/base.txt`. Working branch: the one checked out (`claude_develop`); never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 62 |
|---|---|---|
| Raise the wrist (phone in reach), nothing changed on the phone since the last sync | the watch asks, the phone rebuilds and sends the settings, the routines and the foods again (3 messages, each stored as a new copy on the watch and re-applied), and checks the exercise list | the phone sends none of the three; the watch has nothing to store or re-apply; the exercise list is still checked by its version, as today |
| Change a phone setting (rest ping, units, theme accent), then raise the wrist | everything is re-sent | the settings, the routines and the foods are re-sent once (together), stamped as new; the next raise sends nothing again |
| Add a food, or edit a routine, on the phone, then raise the wrist | everything is re-sent | same: re-sent once, then quiet |
| The watch missed part of a sync (a message not delivered) | the next raise re-sends everything | the next raise re-sends the three again (the routines message goes last and only after the other two were carried, so the watch's "what I hold" can never claim data it does not have) |
| Tap Sync on the watch's start screen | asks for what changed since the last sync | asks for everything (the way out when something looks wrong): the phone re-sends all |
| Phone app is closed and reopened | n/a | one full re-send at the next raise (the phone forgets its stamp), then quiet |

What you will not see: no screen changes. What it saves: the radio traffic, the watch's disk writes and re-decoding per raise, and the phone's message building. What it does NOT save: the phone still reads the routines, foods and exercises from storage on each request to learn whether they changed (the cost of knowing); the watch still sends its request on each raise.

## Facts from the scout (`.work/crew/2026-10-23-62/scout-sync.md`; two items spot-checked against files)

- Trigger: `scenePhase == .active` -> `host.catchUpOnActivation()` and the reachability edge -> `orchestrator.catchUp(reachable:)` -> `sync(reconnect: paths.syncedAt != nil)` -> `transport.requestRoutines(since: reconnect ? paths.syncedAt : nil, exercisesVersion: paths.exercisesVersion)`. `paths.syncedAt` is `catalog?.generatedAt`, the generatedAt of the routines copy the watch holds (`WatchStartPaths.swift` ~l.345). Only an in-flight guard throttles it.
- The phone ignores `since`. `WatchSyncRequestHandler._sendRoutines` (`lib/state/watch/watch_sync_request_handler.dart:100-156`) always builds and sends `preferences_down`, `routines_down` and (when the phone has foods) `foods_down`, each stamped `generatedAt: _clock()` (a fresh instant per request), so the watch's older-copy drop (`sent.generatedAt < catalog.generatedAt`) never fires. The exercise list is already sent only when its content-derived version differs (D-3834).
- Each applied copy appends a new row on the watch (routines, foods, preferences) and re-decodes; preferences also grow an in-memory `copies` list.
- `WatchDelivery { delivered, queued, undelivered }` (`lib/core/platform/watch_delivery.dart:19`): `_transport.send` returns it.
- `utcIso` prints the instant's own precision (microseconds on a device); the watch may parse to milliseconds. A stamp is therefore normalised to whole milliseconds before it is used.

## Decision Ledger

- D-1 No new wire field and no down-payload change. The existing request key `since` (the watch's held routines stamp) becomes meaningful on the phone, and the three reference frames carry one shared "bundle stamp" that changes only when their content changes. The exercise list keeps its own version (unchanged).
- D-2 `lib/core/platform/watch_transport.dart`, in `WatchTransportRequest` beside `exercisesVersionOf` (current l.117-120: `static String? exercisesVersionOf(Map<String, Object?> frame) { final version = frame['exercisesVersion']; return version is String && version.isNotEmpty ? version : null; }`): add `static DateTime? sinceOf(Map<String, Object?> frame)` returning `DateTime.tryParse(value)?.toUtc()` when `frame['since']` is a non-empty String, else null (anything else, including a non-string, is null).
- D-3 `lib/state/watch/watch_sync_wiring.dart` (l.~262): `requests.handle(request, exercisesVersion: ..., since: WatchTransportRequest.sinceOf(frame))`; `WatchSyncRequestHandler.handle` gains an optional named `DateTime? since` passed to `_sendRoutines`.
- D-4 `WatchSyncRequestHandler._sendRoutines({String? exercisesVersion, DateTime? since})`, new order and logic (replacing l.100-141):
  1. Reload foods as today (the try/catch around `loadFoodGroups(includeArchived: true)` / `loadFoods()` stays, first).
  2. Build the three frames with `generatedAt: DateTime.utc(1970)` (a fixed instant; the foods frame only when `_foodLibrary.foods.isNotEmpty`) and compute `signature = jsonEncode([prefs, routines, foods])` (foods `null` when absent). The frames are plain JSON maps; a key order is the builders' insertion order, so equal content gives an equal string (builder confirms by test S-9205).
  3. In-memory field `({String signature, DateTime stamp})? _held`. When `_held?.signature != signature`, set `_held = (signature: signature, stamp: <_clock() truncated to whole milliseconds, UTC>)`.
  4. If `since != null && !since.isBefore(_held.stamp)`: the watch holds the current bundle: send none of the three.
     Else: rebuild the three with `generatedAt: _held.stamp` and send **preferences, then foods (if any), then routines**; if the preferences or the foods send returned `WatchDelivery.undelivered`, do not send the routines frame (the watch's `since` stays old, so the next request sends all three again). The routines frame is the commit marker of the bundle.
  5. The exercise list logic (l.143-155) is unchanged.
  The doc comments of `_sendRoutines` and the library header ("the phone never pushes, so every sync is answered with `preferences_down` first") are rewritten to the new rule.
- D-5 Wrist (`watch/watchos`): the Sync button asks for everything. `ios/OmniTrain Watch App/ContentView.swift` `requestSync()` (current l.299-305: `await orchestrator.sync(reconnect: paths.syncedAt != nil)`) becomes `await orchestrator.sync(reconnect: false)`. Catch-up on activation and on the reachability edge keep `reconnect: paths.syncedAt != nil`. No other watch code changes: with nothing re-sent, the per-message store/decode work disappears at the source. Known and left: `WatchPhonePreferences.copies` grows by one per applied copy (now rare); `applyExercisesDown` does two `store.readAll()` per batch (only when the list changed).
- D-6 `watch/sync_protocol/PROTOCOL.md` (a contract doc outside the docs keeper's ceiling): the sentence(s) describing the routines request and `since` say the phone answers a request that carries `since` equal to or later than its current bundle stamp with no reference frames, and that `since` absent means everything; the three frames of a bundle share one `generatedAt`. Builder-watch, docs-only run.
- D-8 (added after the lead read `WatchSyncProgress.swift`, before review) A wrist that already holds a catalog (`paths.syncedAt != nil`) opens no "syncing" window on its automatic catch-ups (activation and reachability edge): plan 55's spinner ends only when `routines_down` arrives (cap 20 s) and plan 60 then says "No answer from your phone", and since D-4 the phone sends nothing when nothing changed. `ContentView.swift`: `if reachable && self.paths.syncedAt == nil { self.beginSyncProgress() }` at the edge and `if reachable && paths.syncedAt == nil { beginSyncProgress() }` in `catchUpOnActivation()`. The Sync button still opens the window. Owner-visible: a raise with a catalog shows no spinner; data that did change arrives silently. **Owner confirmed 2026-10-23 (in chat): no spinner on a raise when the wrist already has routines; the spinner stays for the first sync and the Sync button.** S-9221 (source guard) in `WatchSyncProgressWiringTests`; the S-8508 guard updated. Scenario S-9221 is free (checked with the S-92 range).
- D-9 Known limitation, ratified after review (finding 2): the probe build (stamp 1970) and the stamped build are two reads of storage. Content that changes in the few milliseconds between them is sent under the stamp of the signature taken at the probe; if it then changes back before the next request, the wrist keeps the middle state until the next real content change. Not fixed: it needs re-stamping the probe's frames instead of rebuilding them, a larger change for a window of milliseconds that self-heals.
- D-7 Not in this plan: message ordering and newer-than checks on the watch (audit item 7), a phone-side change feed (item 11), bounding `copies`.

## Readers listed

- `WatchSyncRequestHandler` constructors/callers: `lib/state/watch/watch_sync_wiring.dart` (`handle(` call), `test/watch_sync_request_handler_test.dart`, `test/rest_ping_contract_test.dart`, `test/watch_accent_contract_test.dart` (the last two assert the preferences frame; builder re-runs them and fixes any that assumed "always sent first, every request").
- Tests that pin the old order or "always sent": `test/watch_sync_request_handler_test.dart` S-7101 (order preferences, routines, foods, exercises) and S-7103; they change to the new order (preferences, foods, routines, exercises) and to the first-request case. `test/live_mirroring_test.dart` S-186 and `test/watch_session_start_test.dart:1164` assert the request side only: re-run.
- Exact-payload assertions on the request frame: none change (the frame is unchanged); `test/watch_transport_test.dart` gains only the `sinceOf` cases.
- Readers of `generatedAt` stamping on the wrist (`applyRoutinesDown`, `applyFoodsDown`, `applyPreferencesDown`): unchanged; with equal stamps never re-sent they stay as they are (preferences keeps its "later copy wins a tie" rule).
- Concurrency: a request is handled by `resolved.onIncoming` which awaits `requests.handle`; two requests can overlap at the awaits. `_held` is read and set in one synchronous run between awaits (step 3 has no await between the read and the assignment), so the stamp cannot be torn; S-9211 pins an interleaving (two requests started without awaiting the first).
- Scenario ids S-9201..S-9220 checked free (grep of `S-[0-9]{4}` prefixes 2026-10-23: nothing at 92).

## Core scenarios

Phone: new `test/watch_sync_changed_only_test.dart`, built on the harness of `test/watch_sync_request_handler_test.dart` (copy its helper block: fake transport recording frames and deliveries, a controllable clock, settings, food library, repository). Let `T1` be the clock value of the first request.
- S-9201 first request (no `since`): frames in order `preferences_down`, `foods_down`, `routines_down` (+ exercise batches); the three share one `generatedAt` equal to `T1` truncated to ms. Fails without the change: the old order is prefs, routines, foods and the stamps are three separate `_clock()` reads.
- S-9202 second request with `since == the routines_down generatedAt` of S-9201, nothing changed, clock advanced 10 s, exercises version matching: zero frames sent.
- S-9203 `since == stamp - 1 ms` (boundary just before): all three re-sent with the SAME `generatedAt` as in S-9201 (stable stamp). `since == stamp` (S-9202) is the skip arm; `since == stamp + 1 ms` also skips (the wrist is never "older" than itself).
- S-9204 one test per signature arm, each: first request, change one thing, request with `since == old stamp` -> all three re-sent with a stamp greater than the old one: (a) the rest ping interval 30 -> 45 (the `preferences_down` payload carries 45), (b) a food added, (c) a routine added. And an arm per non-change: re-requesting with unchanged data yields the same stamp.
- S-9205 equal content gives an equal signature: two consecutive requests with `since: null` and no changes send identical payload maps (compare the encoded maps) with the same `generatedAt`.
- S-9206 delivery failure, one test per arm: (a) the transport returns `undelivered` for the preferences frame, (b) for the foods frame -> in both, no `routines_down` is sent in that request; the next request with the old `since` sends all three; and (c) `undelivered` for the routines frame itself changes nothing in the next request's behaviour (all three re-sent because the wrist's `since` is still old).
- S-9207 `since` garbage: absent, `''`, `42`, `'not a date'` -> treated as null: all three sent.
- S-9208 `sinceOf` table in `test/watch_transport_test.dart`: valid ISO with ms and with µs -> UTC DateTime; absent/`''`/`42`/`null`/garbage -> null.
- S-9209 the exercises stay independent: bundle skipped (matching `since`) but `exercisesVersion` different -> exercise batches still sent; bundle sent but `exercisesVersion` matching -> no batches.
- S-9210 a phone with no foods: the bundle is prefs + routines only; adding the first food changes the signature (the foods arm of S-9204 with an empty start).
- S-9213 (added with fix 1) in `test/watch_session_projection_test.dart`: the graph hands the frame's `since` to the handler (three tests: first request sends, `since == stamp` sends none, `since` 3 s older sends again).
- S-9211 interleaving: two requests started without awaiting the first (both `since: null`, a transport whose `send` suspends): both are answered, and every frame of both carries the same stamp.
- S-9212 phone relaunch: a NEW handler with the same data and the wrist's old `since` -> sends all three (the new handler's stamp is its clock), documenting the one-resend.
Watch (Swift): new `watch/watchos/Tests/WatchSessionEngineTests/WatchManualSyncSourceTests.swift` (helper copied from `WatchNutritionWiringSourceTests`): S-9220 `ContentView.swift` contains exactly the statement `await orchestrator.sync(reconnect: false)` inside `func requestSync()` (function body sliced) and `catchUpOnActivation()` still goes through `orchestrator.catchUp(reachable: reachable)` whose body keeps `await sync(reconnect: paths.syncedAt != nil)` in `WatchSyncOrchestrator.swift` (exact statements; no substring checks, checklist ao).

## Phases

- P1 `crew-builder-app` (≤7 items): D-2, D-3, D-4, S-9201..S-9212, updating S-7101/S-7103. Scope: `lib/core/platform/watch_transport.dart`, `lib/state/watch/watch_sync_request_handler.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_sync_changed_only_test.dart`, `test/watch_transport_test.dart`, `test/rest_ping_contract_test.dart`, `test/watch_accent_contract_test.dart`. Brief: report first as a skeleton; never the full suite; Done: those test files plus `test/live_mirroring_test.dart`, `test/watch_session_start_test.dart`, and the invariant grep.
- P2 `crew-builder-watch` (serial after plan 61 P2: both edit `ContentView.swift`): D-5, D-6, S-9220. Scope: `ios/OmniTrain Watch App/ContentView.swift`, `watch/sync_protocol/PROTOCOL.md`, the new Swift test file.
- P3 `crew-docs-keeper` (after the last test-adding round): `docs/state_management/` and `docs/watch_session_sync*` pages that say "every sync is answered with preferences first" / "the phone never pushes" (grep), plus the QA list (named in the brief).

## Verify (governor)

`flutter test` full (900 s), `flutter analyze` count, `swift test` full, `xcodebuild`, invariant grep. Mutations: signature includes only routines; `!since.isBefore` -> `since.isAfter`; stamp not truncated to ms; stamp renewed on every request; routines sent before the delivery check; `undelivered` ignored for foods; `undelivered` ignored for prefs; order restored to prefs-routines-foods; `sinceOf` returns null always; `requestSync` back to `paths.syncedAt != nil`. Simulator: nothing visible; the iOS simulator does not deliver watch-to-phone transfers (checklist ai), so the end-to-end is an owner check.

## Owner device checks (owner)

1. Raise the wrist twice in a row with the phone in reach: the start screen and routines look the same; (optional) Settings > Watch shows the last sync time unchanged on the second raise.
2. Change a phone setting (e.g. the accent colour or Rest Ping), raise the wrist: the watch picks it up (accent/ping), then raise again: nothing new.
3. Add a routine on the phone, raise the wrist: it appears.
4. Tap Sync on the watch start screen: it still completes (full re-send).

## Progress

P1, P2 and P3 done 2026-10-23 (P3: docs and evidence). Fix 2 (D-8) done 2026-10-23; docs P3b done. Owner device checks open. Reviewed 2026-10-23 (review file beside plan 62); fix 1 (S-9213) and fix 2 (D-8) done; final tree: `xcodebuild` BUILD SUCCEEDED, swift 875/0, flutter 5483 passed (2 skipped), analyze 180 (unchanged baseline).
