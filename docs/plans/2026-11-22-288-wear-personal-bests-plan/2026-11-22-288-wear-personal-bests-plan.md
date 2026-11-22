# Plan 288 — The Wear wrist holds the phone's bests and judges a logged set (plan 280 open item 4, part 1)

Owner request (2026-11-22): "continue the Wear OS development"; the next unbuilt item in plan 280's order is personal records. The Apple wrist's behaviour was decided by the owner in series 87 (`docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md`: a short "New PR" banner for about 4 s with a distinct tap; no bests held means no message; a first-ever set counts as a PR once bests are held; one banner per device) and this series matches it. Like 87a/87b it is split: **this part (288a) makes the wrist hold the bests and decide whether a set beat them, and nothing is visible yet**; 288b wires the decision into logging with the banner and the tap; 288c sends `holdsBests` and adds the rest-screen banner. Wrist only (`lib/watch/`). No wire, phone, schema or Swift change (`bests_down` is already in the contract, the validators and the phone sender, plan 87a). Base commit: `.work/2026-11-22-288-wear-personal-bests/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

What a user sees after 288a: nothing different. What is true underneath: when the phone's `bests_down` frame reaches a Wear watch, the watch keeps the newest copy (a frame older than the held one is dropped, a frame carrying the same numbers writes nothing, a frame it cannot read is refused whole), keeps only that copy in storage, and remembers it across restarts. Given a set, the watch can say whether it beats the standing best: the best of the phone's frame and of the sets the watch itself holds, strictly greater, on the weight axis (estimated one-rep max, Epley with at most 12 reps) for a loaded set and on the reps axis otherwise; a watch that never received a frame says nothing; with a frame held, an exercise absent from it makes its first set a record.

Acceptance: S-28801..S-28825 green under the in-memory store and the Hive store where storage is involved, each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/watch_session_engine_test.dart` (S-004, edited), `test/wear_app_test.dart`, `test/wear_phone_settings_test.dart`, `test/watch_phone_preferences_test.dart`, `test/wear_os_config_test.dart` no new red; Docs delta applied.

## Feature invariants

- The store stays append-only: bests enter by `append`; the one new way a row leaves is `pruneBests`, gated on keeping the newest frame (D-28802). The wrist never edits a number: the frame is the phone's truth.
- The rule is the phone's, unchanged: Epley `weight * (1 + min(reps, 12) / 30.0)` in that operation order so an equal set compares equal bit for bit; strict `>`; `set` efforts only; a set with no load or a negative one (assist) is measured on the reps axis (`StatsProgressService.epley1RM`, `WatchPersonalBests.swift`).
- No data, no verdict: without a frame `noteLogged` returns false for every set (D-3 of series 87).
- Mirrors the Apple `WatchPersonalBests` (87b D-1..D-5, D-10..D-12, D-15..D-17); a Wear deviation is a decision here.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28801 | New record `WatchBestsRecord` (`type` `bests`, `sessionId` empty, `generatedAt`, `entries`: the frame's `bests` array verbatim) in `watch_records.dart`, a `bests` list on `WatchStoreContents` (also in `isEmpty`), a case in `WatchRecord.fromJson`, and in both stores' `readAll`; the Hive store adds `WatchBestsRecord.type` to the box list `_allRows` reads. Modelled on `WatchPreferencesRecord`. | `watch_records.dart` 843-926, 222; `watch_session_store.dart` 14-62; `hive_watch_session_store.dart` 44-90, 130-143; `in_memory_watch_session_store.dart` 33-77 |
| D-28802 | A third prune on the store contract: `pruneBests({required String keepingRecordId})` drops every bests row except the named one and returns the dropped ids; when the named row is not stored it drops nothing (a stale call can never empty the frame). Both stores. It is added on purpose to the S-004 guard's allowed set (its own comment says "a third prune has to be added here on purpose"). Reason: the phone sends a frame at each change of its bests (about 20-30 KB, up to 300 entries), `readAll` decodes every row, and the preferences copies already accumulate. | `watch_session_store.dart` 82-100; `test/watch_session_engine_test.dart` 714-770; `WatchPersonalBests.swift` 155 `pruneBests` |
| D-28803 | New class `WatchPersonalBests` (`lib/watch/logging/watch_personal_bests.dart`): `restore()`, `applyBestsDown(envelope)` (true when it stored a frame that now applies), `noteLogged({kind, exerciseId, reps, loadKg})`, `hasFrame`. It holds the parsed frame, the frame's `generatedAt` and record id, and the wrist's own best per exercise per axis. | `WatchPersonalBests.swift` 40-208; `watch_phone_preferences.dart` as the Dart owner pattern |
| D-28804 | `applyBestsDown` rules, in order: the validator (`SyncProtocolValidator.evaluateOrAccept`) refuses a bad envelope; type, `messageId`, a `payload` map, a UTC `generatedAt` and a `bests` list of maps are required, else false; the entries are parsed whole (D-28805), else false with nothing stored; a frame whose `generatedAt` is before the held one is dropped; a frame with the same numbers as the held one writes nothing and returns false; else it is appended (`recordId` `bests-<messageId>`), becomes the held frame **unless a newer one was applied while the write was in flight**, and `pruneBests` keeps the held frame's row. A tie in `generatedAt` is accepted (the later-received applies). | `WatchPersonalBests.swift` 110-158; PROTOCOL.md `bests_down` note |
| D-28805 | An entry parses when it names a non-empty string `exerciseId` and at least one axis: `e1rmKg` a finite number above zero and/or `repsBest` a whole number (a Dart `int`) of one or more; a missing axis reads as zero, a present but invalid one refuses the whole frame, a repeated exercise keeps the larger of each axis. Same-numbers comparison: same exercise count and equal axes. | `WatchPersonalBests.swift` 278-326 |
| D-28806 | `noteLogged` returns false unless `kind == 'set'`, `exerciseId` is non-empty and `reps >= 1`. With a load above zero the set is measured on the weight axis, otherwise on the reps axis. The verdict is read against the held frame (the verdict is false when no frame is held), then the set is folded into the own best either way (so the same set never celebrates twice, with or without a frame). | `WatchPersonalBests.swift` 175-245 |
| D-28807 | `restore()` reads the newest `bests` row (latest `generatedAt`, a tie to the higher sequence) and rebuilds the own bests in one pass over every stored `set` observation with `reps >= 1`, confirmed or not and phone-sourced included, through the same fold. A relaunch therefore does not celebrate below a set the wrist already holds. | `WatchPersonalBests.swift` 85-98, 250-268 |
| D-28808 | The orchestrator takes an optional `WatchPersonalBests? bests`; `receive` routes `bests_down` to it (false with none). `WearApp` takes the same optional parameter and restores it in `_boot`; `wear_main.dart` builds one and passes it to both. Nothing reads the verdict in this part. | `watch_sync_orchestrator.dart` 43-66, 146-176; `wear_app.dart` `_boot`; `wear_main.dart` |
| D-28809 | Not in scope (named so they are not forgotten): the banner and the tap on a logged set (288b), `holdsBests` on the routines request, the rest-screen banner, a phone-set fold during a live workout. | series 87 index |

## Input-reality checklist

1. **Writers.** The held frame: only `applyBestsDown` and `restore`. The own bests: only `noteLogged` and `restore`. Rows in the store: `append` (this class) and `pruneBests` (this class). Two frames can arrive close together (the transport hands each to `receive` as it comes): the held frame is re-checked after the write so an older one that finishes last cannot replace a newer one (S-28823).
2. **Units.** Kilograms on the wire and in the comparison; the display unit never enters (the banner shows no number).
3. **Lifecycle.** Never received (no verdict); received then restarted (restore); received with `bests: []` (every first set a record); an unreadable frame after a good one (the good one keeps deciding); the app killed between the append and the prune (two rows, restore reads the newest, the next frame prunes).
4. **Settings changing while open.** None.
5. **Time.** A frame stamped the same moment as the held one is accepted when its numbers differ; an older one is dropped; the store `sequence` breaks the tie on restore.
6. **Load.** A verdict is two map lookups and one multiplication; the frame is parsed once when it arrives; memory holds the frame (at most 300 entries) and one entry per exercise the wrist logged. `restore()` reads `readAll` once, at launch.
7. **Wording.** Stale wording: `docs/wear_os_app.md` (the Apple-only list names the personal-record banner; it stays until 288b). The shell header comment names the banner as not hosted (stays true).
8. **Slot competition.** None (no UI).

## Scenarios

Store and record (`test/watch_bests_store_test.dart`, new, plain `test()`, each run under the in-memory store and the Hive store in a temp directory):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28801 | append a `WatchBestsRecord` (two entries, `generatedAt` T); `readAll` | `bests` holds it with the same `recordId`, `generatedAt`, `entries` and an assigned sequence; `isEmpty` false; appending the same id again returns the stored row and adds none | the record or the `bests` list does not exist |
| S-28802 | three bests rows `b1,b2,b3`, a session row and a preferences row; `pruneBests(keepingRecordId: 'b3')` | returns `['b1','b2']` (any order); `readAll().bests` is `[b3]`; the session and preferences rows are untouched; a second call returns `[]` | the prune does not exist, or drops other record types |
| S-28803 | `pruneBests(keepingRecordId: 'not-stored')` over `b1,b2` | returns `[]`; both rows stay | a stale id empties the frame |
| S-28804 | a bests row written through Hive, a new store over the same directory | `readAll().bests` returns it after the reopen | Hive does not list the new record type |

Class (`test/watch_personal_bests_test.dart`, new, plain `test()`; the envelope helper copied from `test/watch_phone_preferences_test.dart` with `type` `bests_down`):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28810 | no frame; `noteLogged` of a 200 kg x 5 set of `ex-bench` | false; `hasFrame` false | a no-data wrist celebrates |
| S-28811 | frame `ex-bench` `e1rmKg` 93.33333333333333 (= 80 x (1 + 5/30.0)); sets 80x5, 79x5, 85x5 | false (equal, strict), false, true | `>=` instead of `>`, or the Epley order differs |
| S-28812 | frame holding only `ex-bench`; a set of `ex-squat` | true (first-ever); then the same set again: false | an absent exercise is not a first-ever record, or the first set is not folded |
| S-28813 | frame `bests: []`; `hasFrame`; a first set | `hasFrame` true; true | an empty frame is read as "no frame" |
| S-28814 | frame `ex-push-up` `repsBest` 12; sets: unloaded 12, unloaded 13, load -20 (assist) 14, load 0 15 | false, true, true, true | the reps axis is not used for unloaded or assisted sets |
| S-28815 | frame holding everything; `noteLogged` with `kind: 'timed'`, with `reps: 0`, with `exerciseId: ''`, with `kind: 'round'` | all false | a non-set or an empty claim celebrates |
| S-28816 | frame `ex-bench` e1rm 100; a 110 x 5 set; the same again; 105 x 5 | true, false, false | the own best does not dedup |
| S-28817 | no frame, then a 120 x 5 set (false), then a frame with `ex-bench` e1rm 100; the same 120 x 5 set | false after the frame too (folded while no frame was held) | the set is only folded when a frame is held |
| S-28818 | 50 kg x 12 against 50 kg x 20 | the two estimates are equal, so with the frame at the 12-rep value neither beats it | the 12-rep cap is missing |
| S-28819 | frame T applied; an envelope stamped T-1 min with different numbers | false; the T numbers still decide a probe set | an older frame replaces a newer |
| S-28820 | frame T applied; an envelope stamped T with different numbers; a third stamped T with the second's numbers; a fourth with the third's numbers again | the tie applies (true), an identical frame writes nothing (false) and the store holds one bests row | a tie is dropped, or an unchanged frame writes |
| S-28821 | malformed envelopes: an entry with no `exerciseId`; an empty `exerciseId`; an entry with neither axis; `e1rmKg` 0; `e1rmKg` as a string; `repsBest` 15.0 (a double); `repsBest` true; `bests` not a list | each false; the store holds no new row; the previously held frame still decides | a bad frame is half-understood or replaces a good one |
| S-28822 | restart: a new `WatchPersonalBests` over the same store, `restore()`; a stored set observation 120 x 5 of `ex-bench`, frame e1rm 100 | `hasFrame` true; a 110 x 5 set is false (the own best rebuilt); a set of an exercise the frame has: judged against the frame | `restore` does not rebuild, or loses the frame |
| S-28823 | two envelopes (older T, newer T+1 min) handed to `applyBestsDown` together (`Future.wait`), in both orders | the newer decides a probe set in both orders; the store ends with one bests row, the newer's | the older frame that finishes last replaces the newer one |
| S-28824 | the real validator (`loadProtocolValidator`) with `fixtures/valid/bests_down.json`, `bests_down_empty.json`, `bests_down_both_axes.json` | each true; a copy with an unknown extra payload field is refused (false), nothing stored | the validator is not consulted |

Wiring (`test/wear_personal_bests_wiring_test.dart`, new):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28830 | a `WatchSyncOrchestrator` with a bests owner; `receive(bests_down)` | true; `hasFrame`; without an owner `receive` returns false | the route does not exist |
| S-28831 | the shell (`WearApp`) given a bests owner over a store that already holds a frame, opened | `hasFrame` true after the boot frames | `_boot` does not restore |
| S-28832 | `runWearApp`-level: the production entry builds one owner and gives it to both the orchestrator and the shell: a source-scan guard of `wear_main.dart` asserting both lines name the same variable | the scan finds `bests: bests` twice | the owner is not wired in the entry point |

S-004 (`test/watch_session_engine_test.dart`) is edited, not added: its allowed set gains `pruneBests` and its comment names the third prune.

Guard families the lead proves by mutation: the strict `>`, the Epley operation order and the 12 cap, the reps-axis rule (zero, negative), the first-ever rule, the no-frame silence, the kind/reps/id claim guard, the own-best fold (with and without a frame), the older-frame drop, the tie accept, the unchanged-frame skip, each of the parse refusals, the re-check after the write, the prune's keep-id and its absent-id guard, the restore rebuild.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop" (the gateway hangs for builders on this machine, plan 287). Serial.

1. **P1 — records, stores, class, wiring** (`crew-builder-watch`; scope `lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_store.dart`, `lib/watch/session/hive_watch_session_store.dart`, `lib/watch/session/in_memory_watch_session_store.dart`, `lib/watch/logging/watch_personal_bests.dart`, `lib/watch/start/watch_sync_orchestrator.dart`, `lib/watch/app/wear_app.dart`, `lib/watch/wear_main.dart`). Exact code in the brief. About 330 lines.
2. **P2 — tests** (lead, as in plan 287: no crew run can execute a test here): `test/watch_bests_store_test.dart`, `test/watch_personal_bests_test.dart`, `test/wear_personal_bests_wiring_test.dart`, and the S-004 edit.
3. **P3 — docs** (lead): `docs/wear_os_app.md`, plan 280 item 4.
4. **Lead:** analyze, readers, full suite compared as in plan 287, mutation pass, plan-lint.

Predicted production code about 330 lines in 8 files, tests about 650 lines: inside the budget.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | ## The personal bests | S-28811 |
| docs/wear_os_app.md | ADDED | - | `test/watch_personal_bests_test.dart` | S-28811 |

Plan 280's open item 4 is a plan record (the keeper adds "part 1 built by plan 288"). The Apple-only list in `docs/wear_os_app.md` keeps the personal-record banner (it is not on the Wear wrist until 288b). Stale-term sweep: `grep -rIn -i "bests_down\|personal.record" docs | grep -v "docs/plans\|docs/history\|docs/releases"` reviewed: the hits describe the phone and the Apple wrist and stay true; the wrist's new section says what the Wear wrist holds.

## Assumption Log

- `SyncProtocolValidator.evaluateOrAccept` accepts a `bests_down` envelope with the schema loaded and refuses an unknown extra field (the schema is closed), checked by S-28824, not assumed.
- `WatchObservationRecord.payload` carries `exerciseId`, `reps` and `loadKg` for a wrist-logged set (the shape `watch_menu_state_test.dart` `_setEvent` hands the engine and `WatchLoggingState.log` writes); S-28822 builds its observation that way.
- JSON `15.0` arrives as a Dart `double` and `15` as an `int` through the platform channel's standard codec, so `is int` is the whole-number test.

## Progress

- [x] P1 production (crew builder; lead edit: serialised applies)
- [x] P2 tests (lead; S-28801..S-28832 plus S-28811b and S-28825)
- [x] P3 docs (lead)
- [x] Verify and prove (analyze 174; 142 Wear tests green; 35 of 35 mutants killed)
