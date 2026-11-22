# Plan 289 — The Wear wrist shows "New PR" (plan 280 open item 4, part 2; series 288)

Part 2 of the personal-records item: plan 288 made the wrist hold the phone's bests and judge a set. This part uses the verdict. The owner's decisions are series 87's (`docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md`) and the Apple wrist is the model (`WatchPersonalRecordBanner.swift`, plan 88): a short "New PR" banner with a trophy over the exercise screen for about 4 seconds plus a distinct tap, never blocking Log, the rest timer or Next; no data, no message; one banner per device (a set logged on the wrist gets the wrist banner, a phone-logged set keeps the phone's toast). Like the Apple wrist, the banner shows on **both** the logging surface and the rest surface, because logging a set starts a rest at once and the logging screen is replaced by the rest screen. Wrist only (`lib/watch/`); no wire, phone, schema or Swift change. Base commit: `.work/2026-11-22-289-wear-new-pr-banner/base.txt`. Analyze baseline: 174 issues, 0 errors. Not in this part: `holdsBests` on the routines request (288c).

## Goal and acceptance

On a Wear watch that holds the phone's bests, logging a set that beats the standing best shows a small capsule with a trophy and the words `New PR`, in the phone's accent colour, over the top of the screen for 4 seconds, and gives one distinct tap on the wrist. It stays through the rest screen that replaces the logging screen at once, goes by itself after 4 seconds, and a second record inside the window restarts the 4 seconds. It never takes a touch: Log, Next and the Menu button work under it. A set that does not beat the best, a log that is not a set (a timed effort, a round, a hold), a wrist that has no bests frame, and a set the phone logged all show nothing and give no tap. A screen reader announces `New personal record`.

Acceptance: S-28901..S-28914 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the existing Wear files (`wear_app_test`, `wear_menu_screen_test`, `watch_logging_surfaces_test`, `wear_logging_layout_test`, `wear_pager_screen_test`, `wear_phone_settings_test`, `wear_accent_theme_test`) no new red; Docs delta applied.

## Feature invariants

- The verdict is read on one path only: `WatchLoggingState.log()` after the entry is stored. It cannot throw, await or change the event (a failed write gives no verdict), and a set that arrives from the phone never reaches it (Apple 87b D-4).
- The banner takes no touch (`IgnorePointer`) and moves nothing: it only appears and disappears, so reduced motion needs nothing extra.
- The one cue per log: the record's own tap on a record, nothing extra otherwise (the Wear wrist plays no "logged" tap today, so the rule "never both" holds by construction).

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28901 | `WatchLoggingState` takes an optional `WatchPersonalBests? bests`. After `appendObservation(event)` in `log()` it asks `bests.noteLogged(kind, exerciseId, reps, loadKg)` from the event just stored (`reps` the event's int or 0, `loadKg` its number or null), sets `lastLogWasPersonalRecord`, and on a record sets `personalRecordBannerUntil = now + 4 s` (a second record restarts the window). `isPersonalRecordBannerVisible(instant)` is true strictly before the expiry. | `WatchLoggingState.swift` 1186-1199, 383-387; `watch_logging_state.dart` `log()` |
| D-28902 | `WatchPersonalRecordCopy` (in `lib/watch/widgets/watch_personal_record_banner.dart`): `bannerDuration` 4 s, `label` `New PR`, `spoken` `New personal record`. | `WatchPersonalRecordCopy`, `WatchSpokenText.personalRecord` |
| D-28903 | New widget `WatchPersonalRecordBanner(state:)` in `lib/watch/widgets/watch_personal_record_banner.dart`: nothing while the window is closed; else an `IgnorePointer` capsule (trophy icon `Icons.emoji_events` and the label) filled with the theme's `primary` with `onPrimary` content, so it wears the phone's accent (plan 286) with a readable label; `Semantics(label: spoken, liveRegion: true)` over it with the children excluded. | `WatchPersonalRecordBanner.swift` 26-53; `watch_accent.dart` |
| D-28904 | Both surfaces overlay it: `WatchLoggingScreen` and `WatchRestScreen` put their existing body and the banner (top, centred) in one `Stack`. The banner is read on each surface's own once-a-second tick (no timer of its own), so it is gone within a second of the 4 s window ending, as on the Apple wrist. | `WatchLoggingView.swift` 151; `WatchRestView.swift` 115 |
| D-28905 | `WatchHaptics` gains `playPersonalRecord()`; `SystemWatchHaptics` plays `HapticFeedback.vibrate()` (the pager's click, the lock's heavy tap and the rest ping's medium tap are taken, so the record's is a distinct fourth). `WatchLoggingScreen._log` calls it after a stored log when `state.lastLogWasPersonalRecord`. The test double `_RecordingHaptics` in `test/watch_logging_surfaces_test.dart` is its only other implementer. | `WatchLoggingModel.swift` 217; `watch_logging_screen.dart` 22-40, `_log` |
| D-28906 | `WearApp` gives its `WatchLoggingState` the shell's `bests` (plan 288). | `wear_app.dart` `_logging` |
| D-28907 | Wear deviation, stated: the Apple wrist announces a record once with a per-stamp ticket (`takePersonalRecordAnnouncement`) because two surfaces mount the same banner. Here the banner's live region announces when it appears, so a record that is still inside its 4 s window when the user taps Next is announced again by the logging screen's banner. Owner check 10 says so. | `WatchLoggingState.swift` 389-402 |
| D-28908 | Not in scope: `holdsBests`, a fold of phone-logged sets into the wrist's own bests during a live workout, the Apple announce-once ticket. | series 87 index (87c, 87d) |

## Input-reality checklist

1. **Writers.** `lastLogWasPersonalRecord` and `personalRecordBannerUntil`: only `log()`. The bests: plan 288's owner.
2. **Units.** The verdict compares kilograms; the banner shows no number.
3. **Lifecycle.** The shell rebuilds `WatchLoggingState` never (it is held for the app's life); the stamp lives on it, so it survives the swap between the logging and rest screens and the pager's per-page rebuild of the logging screen. App killed: the banner is gone (it is a 4 s notice).
4. **Settings changing while open.** The accent changing re-themes the banner on the next build.
5. **Time.** `now()` is the state's injected clock; visibility is `now < until`; exactly at the window end it is gone.
6. **Load.** One map lookup per log.
7. **Wording.** `New PR` and `New personal record` as the Apple wrist says them; stale wording: `docs/wear_os_app.md` lists the personal-record banner among the things the Apple wrist hosts and the Wear wrist does not (the Docs delta), and the shell header comment in `wear_app.dart` names the banner as not hosted.
8. **Slot competition.** The capsule overlays the top of the screen where the exercise name sits; it is small and lets touches through; the layout is measured at 192x192 and 227x227 dp with the new tests (S-28912).

## Scenarios

State (`test/wear_personal_record_state_test.dart`, new, plain `test()`; an in-memory engine with a session of one set exercise, a `WatchPersonalBests` over the same store given a frame, a fixed clock):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28901 | frame `ex-x` `e1rmKg` 1 (any real set beats it); `log()` | `lastLogWasPersonalRecord` true; `personalRecordBannerUntil` = clock + 4 s; visible at +3.999 s, not at +4 s, not before the log | the hook does not exist |
| S-28902 | frame `ex-x` `e1rmKg` 1000000; `log()` | false; no stamp; never visible | every set celebrates |
| S-28903 | no bests owner given | false; no stamp | an absent owner throws or celebrates |
| S-28904 | an owner holding no frame | false | a no-data wrist celebrates |
| S-28905 | a timed exercise (capability `time`) with an empty frame held; `log()` | false: only a set is a claim | a timed effort celebrates |
| S-28906 | two records 2 s apart (clock advanced between logs) | the second stamp is the second log + 4 s; visible at +5 s after the first log | the window is not restarted |
| S-28907 | a record, then a non-record log | `lastLogWasPersonalRecord` false again; the stamp of the first record stays until its own expiry | the flag is sticky, or the later log clears the window |
| S-28908 | `log()` on a state whose store write throws (a held-failing store) | no verdict: the flag false, no stamp, the owner's own best unchanged (a later equal set is still a record) | the verdict runs before the write |
| S-28909 | a set appended through `engine.appendObservation` (the way the phone's mirrored sets arrive), no `log()` | no stamp, `lastLogWasPersonalRecord` false | the engine path reaches the judge |

Widgets (`test/wear_personal_record_banner_test.dart`, new; in-memory store, Mock-first, explicit pumps):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28910 | the logging screen with a recording haptics double; a frame beaten; tap `Log` | `New PR` and the trophy found; `playPersonalRecord` once; after pumping 4 s in 1 s steps the banner is gone | no banner, or no tap |
| S-28911 | the same with a frame not beaten | no `New PR`; no `playPersonalRecord` | every log shows it |
| S-28912 | at 192x192 and 227x227 dp with a long exercise name | no overflow exception; the banner inside the screen | the banner overflows or leaves the screen |
| S-28913 | the banner is `IgnorePointer`ing, and with it up `Log` still logs a second set | the second set is logged | the banner takes touches |
| S-28914 | the shell (`WearApp` with a bests owner holding a beaten frame): tap `Log`; the rest screen is up | `New PR` shows on the rest screen (one banner), it is the phone's accent (`primary`); the semantics label `New personal record` exists; tapping `Next` during the window shows the banner again on the logging screen; after 4 s with no tap it is gone | the rest surface has no banner, the shell does not wire the state, or the accent is ignored |

Guard families the lead proves by mutation: the verdict's call site and its position after the write, the 4 s window and its strict end, the restart, the flag reset, the event-to-claim mapping (kind, exercise id, reps, load), the banner's visibility test, the two overlays, `IgnorePointer`, the tap and its condition, the shell's wiring, the accent fill.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — state, banner, overlays, tap, wiring** (`crew-builder-watch`; scope `lib/watch/logging/watch_logging_state.dart`, `lib/watch/widgets/watch_personal_record_banner.dart` (new), `lib/watch/logging/watch_logging_screen.dart`, `lib/watch/logging/watch_rest_screen.dart`, `lib/watch/app/wear_app.dart`). Exact code in the brief. About 110 lines.
2. **P2 — tests** (lead, as in plans 287 and 288): the two new files and the `_RecordingHaptics` method.
3. **P3 — docs** (lead).
4. **Lead:** analyze, readers, mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | Nothing on the screen uses the verdict yet: the banner and the tap on a logged set come next. | A set that beats the standing best shows a small `New PR` banner | S-28910 |
| docs/wear_os_app.md | ADDED | - | `test/wear_personal_record_banner_test.dart` | S-28910 |
| docs/wear_os_app.md | ADDED | - | 10. (owner) on a Wear watch with a paired phone | S-28914 |

Stale-term sweep: `grep -rIn -i "personal-record banner" docs | grep -v "docs/plans\|docs/history\|docs/releases"` hits `docs/wear_os_app.md` (the Apple-only list: edited by hand, the keeper-style row above covers the section sentence) and Apple pages that stay true. Plan 280's open item 4 is a plan record (annotated "part 2 built by plan 289").

## Assumption Log

- `WatchLoggingState.now()` exists and reads the injected clock (`watch_logging_state.dart` 228); both screens already tick once a second.
- The set event carries `reps` as an `int` (`reps.round()`) and `loadKg` as a number only when non-zero (`_metricPayload`).
- `Icons.emoji_events` is the trophy.

## Progress

- [x] P1 production (crew builder)
- [x] P2 tests (lead; S-28901..S-28916)
- [x] P3 docs (lead)
- [x] Verify and prove (analyze 174; 159 Wear tests green; 19 of 19 mutants killed)
- [ ] (owner) check 10 in `docs/wear_os_app.md` on a watch
