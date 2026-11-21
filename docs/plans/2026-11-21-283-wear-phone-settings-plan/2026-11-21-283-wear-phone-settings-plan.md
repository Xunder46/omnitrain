# Plan 283 — The Wear wrist reads the phone's settings (preferences_down)

Series 283: **283a (this plan)** the Wear wrist learns the phone's settings; **283b** the effort-rating state and the stored "rating owed" record; **283c** the rating prompt screen and its shell/menu wiring. 283b and 283c are planned after 283a lands (owner chose this order 2026-11-21: "phone settings first, then rating"). Wrist only, `lib/watch/`. No wire, phone or schema change (the phone already sends `preferences_down`). Base commit: `.work/2026-11-21-283-wear-phone-settings/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

Found 2026-11-21: `WatchSyncOrchestrator.receive` handles `routines_down` and `foods_down` but not `preferences_down`, so a Wear watch always shows kilograms and kilometres whatever the phone is set to, never pings on a rest, and cannot learn the effort-rating setting.

After 283a, on a Wear watch: when the phone's sync brings its settings, the logging surface shows weights in the phone's unit (`kg` or `lb`: the value, the step, the label) and distances in the phone's unit (`km` or `mi`); the rest surface pings at the phone's Rest Ping interval (0 = never, the default); the wrist remembers them across restarts (a copy is stored; the newest wins); a watch that has never heard from the phone behaves exactly as today. The accent colour and the effort-rating flag are stored and readable (`accentColorHex`, `asksForEffortRating`) but nothing shows them yet (283c and a later accent item).

Acceptance: S-28301..S-28313 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/watch_session_engine_test.dart`, `test/watch_nutrition_quick_log_test.dart`, `test/watch_logging_surfaces_test.dart`, `test/wear_app_test.dart`, `test/wear_menu_screen_test.dart`, `test/wear_logging_layout_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; no new red in the full suite; Docs delta applied.

## Feature invariants

- The store stays append-only: a newer copy is a newer row; `WatchSessionStore` gains no method (S-004 guard in `test/watch_session_engine_test.dart`).
- A copy older than the one that applies is understood and dropped; a copy stamped the same instant goes to the later-received one (PROTOCOL.md).
- A copy the wrist cannot read is refused whole, nothing stored, and the caller learns it was not applied.
- The Swift `WatchPhonePreferences.swift` is the reference: same rules, same field handling.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28301 | New record `WatchPreferencesRecord` (`recordType` `preferences`, like `WatchFoodCatalogRecord`: no session, `sessionId` empty): `generatedAt`, `effortRatingPrompt`, `restPingSeconds`, optional `accentColorHex`, `weightUnit`, `distanceUnit`. It is registered in `WatchRecord.fromJson`, in `WatchStoreContents.preferences` (default `const []`, part of `isEmpty`), in both stores' `readAll` and in the Hive store's row type list. | `watch_records.dart` `WatchFoodCatalogRecord` (763-826) and `fromJson` switch (205-215); `watch_session_store.dart` `WatchStoreContents`; `hive_watch_session_store.dart` 50-80, 120-135; `in_memory_watch_session_store.dart` 38-70; Swift `WatchPreferencesRecord` |
| D-28302 | New class `WatchPhonePreferences` in `lib/watch/start/watch_phone_preferences.dart`: `restore()` (reads `preferences` from the store), `applyPreferencesDown(Map envelope)` returning `Future<bool>` (true when the stored copy now applies), `current`, `asksForEffortRating` (false until a copy), `restPingSeconds` (0), `accentColorHex`, `units` (a full `WatchUnitPreferences`: weight, distance and rest ping; `kg`/`km`/0 until a copy). The validator step is `SyncProtocolValidator.evaluateOrAccept(validator, envelope)` as `WatchNutritionState.applyFoodsDown` does; a refused or unreadable message returns false and stores nothing. | Swift `WatchPhonePreferences.swift` 134-275; Dart `watch_nutrition_state.dart` `applyFoodsDown` (147-186) |
| D-28303 | Unreadable means: `effortRatingPrompt` not a bool, `restPingSeconds` not a non-negative integer (a double such as `90.5`, a string, a bool and a negative are refused), `generatedAt` not a UTC instant. `weightUnit` / `distanceUnit` / `accentColorHex` are read as strings when present (the validator's closed enum and pattern come first); an absent key stores the absence (the wrist then reads kg / km, not the previous copy's unit). | Swift `applyPreferencesDown`, `wholeSeconds` |
| D-28304 | `WatchLoggingState.units` becomes a getter: the constructor keeps `units:` (default `const WatchUnitPreferences()`) and gains an optional `WatchUnitPreferences Function()? unitsProvider`; when it is given the getter returns `unitsProvider()` on every read, else the fixed `units`. Every existing caller keeps working unchanged. | `watch_logging_state.dart` 120-170 (`units` is a final field read at 271, 288, 291, 552-575); `watch_rest_screen.dart:75`; `watch_logging_screen.dart:252` |
| D-28305 | The orchestrator gets an optional `WatchPhonePreferences? preferences` constructor parameter; `receive` routes `preferences_down` to it (returns its bool; with no preferences owner it returns false like `foods_down`). The shell (`WearApp`) gets the same optional parameter, restores it in `_boot` next to the other `restore()` calls, and builds `_logging` with `unitsProvider` reading `preferences.units` when it is present. `wear_main.dart` builds one `WatchPhonePreferences(store: store)` and passes it to both. | `watch_sync_orchestrator.dart` 41-52, 141-146; `wear_app.dart` `WearApp`, `_logging`, `_boot`; `wear_main.dart` |
| D-28306 | The rest ping interval needs no code of its own: `WatchRestScreen` already reads `widget.state.units.restPingSeconds` (line 75), which D-28304 now makes live. | `watch_rest_screen.dart:75` |
| D-28307 | Not in scope: the accent theming (item 8), the effort-rating state and prompt (283b, 283c), any phone or wire change, a settings screen on the wrist. | plan 280 open items 3 and 8 |

## Input-reality checklist

1. **Writers.** One writer: `applyPreferencesDown` (the phone's frame, arriving at the wrist's next sync). Readers: the logging state's `units`, the rest screen's ping, later the rating state and the accent.
2. **Lifecycle.** Never heard (defaults), heard then restarted (restore), heard twice with the older arriving last (dropped), heard with an absent unit after a present one (absence stored), a session already running when the copy arrives (the next 1 s repaint shows the new unit; dialled values are canonical kilograms/metres, so nothing is converted twice).
3. **Settings changing while open.** The phone changes a unit while a Wear session runs: it reaches the wrist at the next sync, the logging surface re-reads `units` on its next rebuild (1 s tick).
4. **Time.** A tie in `generatedAt` goes to the later-received copy (the store `sequence` breaks it).
5. **Load.** `units` is built per read from `current`; `current` is a max over a few rows (the store keeps every copy, like the catalogs). Reads happen per repaint of the logging surface: cheap, no I/O.
6. **Words.** Old wording found by grep: `Live sensors are the same story` stays; the line in `docs/wear_os_app.md` listing what the Wear wrist lacks does not mention units or settings, so a new sentence is added (Docs delta).
7. **Competition.** None (no screen space is used).

## Scenarios

`test/watch_phone_preferences_test.dart` (new, P1; Mock store, and the same round-trip against `HiveWatchSessionStore` for S-28307 as `test/watch_nutrition_quick_log_test.dart` 1572 does) and `test/wear_phone_settings_test.dart` (new, P2).

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28301 | a fresh `WatchPhonePreferences` over an empty store | `asksForEffortRating` false, `restPingSeconds` 0, `accentColorHex` null, `units` = kg / km / 0, `current` null | the class does not exist |
| S-28302 | apply `preferences_down` (effortRatingPrompt true, restPingSeconds 90, accentColorHex `#336699`, weightUnit `lbs`, distanceUnit `miles`, generatedAt T1) | returns true; every getter shows those values; `units.weightUnit == 'lbs'`, `units.distanceUnit == 'miles'`, `units.restPingSeconds == 90`; one `preferences` row in `readAll` | the frame is ignored |
| S-28303 | apply a copy at T1 (lbs), then a copy at T2 > T1 (kg, restPing 0) | the second applies (returns true); `units.weightUnit == 'kg'`, `restPingSeconds == 0` | the older copy would win, or the second is not stored |
| S-28304 | apply a copy at T2, then a copy at T1 < T2 (lbs) arriving late | returns false; getters still show the T2 copy; no second row stored | a late copy replaces a newer one |
| S-28305 | apply two copies with the same `generatedAt` (first lbs, then kg) | the later-received applies: `weightUnit == 'kg'` | a tie goes to the first |
| S-28306 | apply a copy with `weightUnit lbs`, `accentColorHex`, then a newer copy with neither | `weightUnit` reads kg, `accentColorHex` null (absence stored, not the earlier value kept) | an absent key keeps the previous unit |
| S-28307 | apply a copy, build a NEW `WatchPhonePreferences` over the same store (Mock, then Hive), `restore()` | the new instance shows the same getters | the copy is not stored, or `restore` does not read it |
| S-28308 | apply (a) `restPingSeconds: -1`, (b) `90.5`, (c) `"90"`, (d) `effortRatingPrompt: "yes"`, (e) a bad `generatedAt` | each returns false; nothing stored; getters unchanged | an unreadable copy is stored or read as Off |
| S-28309 | the same envelope (same `messageId`) applied twice | one row; second returns true or false consistently with the first copy still applying (the test names which) | duplicates rows |
| S-28308f | a valid preferences envelope with only `type` changed to `foods_down` | false, nothing stored | the type is not checked |
| S-28308g | a real schema validator: a valid copy, then the same with `origin: 'watch'` | true then false; one row | the validator's verdict is ignored |
| S-28309b | `msg-1` at T1, `msg-2` at T2, then `msg-1` again stamped T3 > T2 | false; the T2 copy still applies; two rows | the return value ignores that the stored row is the old one |
| S-28310 | `WatchSyncOrchestrator(preferences: p).receive(<preferences_down>)`, then the same with an older copy, then with `preferences: null` | true, false, false | `receive` falls through to "no use for it" |
| S-28311 | a `WatchLoggingState` with `unitsProvider: () => prefs.units` over a set slot with a 100 kg load dialled; apply a `lbs` copy | the weight row's `displayValue` and `unitLabel` change from kg to lb (220.5 lb at the 2.2046 factor: the test reads what `UnitFormatter.fromKilograms` gives); a state built without the provider still reads its fixed `units` | `units` is a fixed field |
| S-28312 | the shell booted over a store that already holds a `lbs` copy and a running set session (`WearApp(preferences: p)`) | the logging surface shows the lb unit (`Load · lb` at 192 dp) | `_boot` does not restore, or `_logging` ignores the provider |
| S-28312b | the shell with no copy (rows say kg), then the orchestrator receives an lbs copy and one second passes | rows say lb | the provider is not read on repaint |
| S-28313 | the shell with a `restPingSeconds: 60` copy applied: `_logging.units.restPingSeconds` | 60 (and 0 for a shell with no copy) | the rest screen would always read 0 |

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "write the report FIRST as a skeleton". Serial.

1. **P1 — record, stores, owner class** (`crew-builder-watch`; scope `lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_store.dart`, `lib/watch/session/in_memory_watch_session_store.dart`, `lib/watch/session/hive_watch_session_store.dart`, `lib/watch/start/watch_phone_preferences.dart`, `test/watch_phone_preferences_test.dart`). Items: D-28301..D-28303, S-28301..S-28309. Production about 170 lines.
2. **P2 — wiring** (`crew-builder-watch`; scope `lib/watch/logging/watch_logging_state.dart`, `lib/watch/start/watch_sync_orchestrator.dart`, `lib/watch/app/wear_app.dart`, `lib/watch/wear_main.dart`). Exact code in the brief. Items: D-28304..D-28306. About 40 lines.
3. **P2t — wiring tests** (`crew-builder-watch`; scope `test/wear_phone_settings_test.dart`). S-28310..S-28313.
4. **P3 — docs** (`crew-docs-keeper`, no test run).
5. **Lead:** mutation pass, full suite, review.

Predicted production code about 210 lines in 8 files, one track: inside the budget.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | the effort-rating prompt, the personal-record banner, the water bar, the | the personal-record banner, the water bar, the | S-28302 |
| docs/wear_os_app.md | ADDED | - | ## The phone's settings | S-28302 |
| docs/wear_os_app.md | ADDED | - | until the phone has sent its settings the wrist reads kilograms and kilometres | S-28301 |

Stale-term sweep: `grep -rIn "effort-rating prompt" docs | grep -v "docs/plans\|docs/history\|docs/releases"` hits `docs/wear_os_app.md` (the Apple-hosts-more paragraph, row 1) and unrelated Apple/phone pages; those stay.

## Assumption Log

- The phone sends `preferences_down` before every `routines_down` bundle and the Wear transport already delivers every frame to `WatchSyncOrchestrator.receive` (`wear_app.dart` `_onFrame`), so no transport change is needed (verified by reading `_onFrame`).
- `WatchRestScreen` reads `widget.state.units.restPingSeconds` (line 75) and `WatchLoggingScreen` reads units through the state: no other reader of the fixed `units` field exists outside `watch_logging_state.dart` (grep `units\.` in `lib/watch`).
- `SyncProtocolValidator.evaluateOrAccept(null, envelope)` accepts without a validator, so a wrist built without schemas still applies a well-formed copy (as `applyFoodsDown`).
- 283b/283c are not seeded here; their prerequisites (this plan) are what they need.

## Progress

- [x] P1 record, stores, owner class
- [x] P2 wiring
- [x] P2t wiring tests
- [x] P3 docs
- [x] Mutation pass, full suite, review
