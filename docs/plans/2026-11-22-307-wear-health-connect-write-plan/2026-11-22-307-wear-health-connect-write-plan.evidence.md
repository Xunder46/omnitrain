# Plan 307 evidence

Built and proved by the lead alone (the gateway hangs for builders on this PC). No independent reviewer ran. Owner answers (2026-11-22): match the Apple watch where possible, otherwise the defaults; so the phone writes Wear workouts, calories go in as Health Connect's total-calories record (Apple's active-only figure is not available from Wear), and the typing match is plan 308.

## Observed output

- `flutter test test/wear_health_write_test.dart`: 32 passed (S-30701..S-30709).
- Neighbouring health, watch-session, workout-state and settings tests (33 files, plus the UI-standards contract): compared by name against a clean checkout (stash): 512 pass / 380 fail before, 544 pass / 380 fail after; **no new failures**; the 380 are the Windows baseline (paths, CRLF, Hive). The 32 extra passes are the new tests.
- `flutter analyze`: 174 issues, 0 errors (baseline unchanged).
- `flutter build apk --debug --flavor phone`: built (the manifest merges with the new permission).
- A real bug in my first version was caught by the existing suite, not by my tests: `health_effort_native_test` "Android never calls the effort channel" failed with "The length of [types] must be same as that of [permissions]". Asking the workout and its calories together made two types with one access entry, and the plugin refuses that, which would have made enabling Write workouts fail on every Android phone. Fixed (one access entry per type) and pinned by a behavioural test through the plugin channel (S-30707).
- The formatter reflowed unrelated lines in three files while I formatted my own edits; those hunks were reverted so the diff holds only this plan's changes.

## Mutation pass (24 mutants over `test/wear_health_write_test.dart`)

23 killed, 1 equivalent:
- Equivalent: removing `if (energyKcal == null) return;` in `onEnergyAttached`. A null energy is also stopped by the memo comparison (`_energyWritten[id] == null`), so the guard only matters if an energy once written later disappears, which the importer never does (a measured row is never replaced by an estimate). Kept as a safety.
- The first run left two survivors that were weak tests, fixed: a measured zero (needed its own test) and the planned-set rule (needed a test that observes the exercise kept on Android). A third (the ledger check) turned out to be duplicated inside `_replaceWorkout`; the redundant copy was removed from `onEnergyAttached` and the remaining one is guarded.
- Killed: the platform flag at the end and at the wrist's end, the planned-set rule, never skipping, estimate written as measured, rounding, zero energy, the memo (read and write), the setting gate, the ledger check, the gateway's rounding, retry, energy argument, permission list and permission list length, iOS asking for calories, the manifest, the wiring and the inbox hook and call.

## Not observed

- A real Wear watch finishing a workout and Health Connect showing it (owner check 23); Health Connect on an Android 13 phone with the separate app; a user who enabled Write workouts before this change (they have the old permission: their workouts are written without calories until they switch the setting off and on, by design D-30705).
- The late-energy replacement against a real Health Connect store (the fake store proves delete-then-write; the plugin's delete is by the session's own start window, as plan 146c's rewrite already does).
