# Report — plans 61/62, phase P3 (crew-docs-keeper)

No test run (the brief forbids it; nothing here was verified by a check this run — every behavioural sentence cites a test read from its file this run).

## Files changed

- `docs/state_management/watch_surface_wrist.md` — the rest-ping paragraph now tells how the wrist asks: the host's `WatchRestPingScheduler` (`restPings`), `arm()` on every `revision` bump and on activation, the catch-up tap, the 50 ms margin in `nextWait`, the dimmed whole-minutes clock on the rest's own minute marks, tests `WatchRestPingSchedulerTests` S-9101..S-9108 and `WatchRestPingWiringSourceTests` S-9109, and "the Dart twin `lib/watch` has no scheduler and is unchanged". The haptics paragraph's "the rest ping (below)" still points at the paragraph below it — left as is.
- `docs/state_management/watch_surface.md` — the `WatchSyncRequestHandler` section rewritten to the new rule (three frames, one bundle stamp, `since` skip, `routines_down` last and withheld on an undelivered preferences/foods frame, version check independent of the bundle); the "preferences ride every `routines` request" sentence replaced (a change now moves the bundle stamp; the Sync button asks for everything); the "preferences travel on every `routines` request" rationale in the `preferences_down` section replaced; the Verified-by line now cites S-9208, S-7101…S-7105, S-9201..S-9212, S-9213 and S-9220.
- `docs/state_management/watch_reference_data.md` — "Where the two ends stand" opening rewritten to the bundle-stamp rule in two sentences (tests S-9201…S-9212, S-9213); the now-false clause "and only the preferences and the routines travel" dropped from the version-early-return sentence.
- `docs/watch-app-setup-and-qa.md` — steps 22 and 23 added after step 21 of the PR 2b logging walkthrough, in the list's style, each naming the tests that hold the off-device parts; every other line byte-identical (steps 25/26 of the other list untouched).
- `docs/plans/2026-10-23-61-…/2026-10-23-61-….evidence.md` — created (phases, 861 tests / 0 failures, BUILD SUCCEEDED, 23 mutants with the two closers and the endless-loop kill, the whole-minutes deviation, owner checks open).
- `docs/plans/2026-10-23-62-…/2026-10-23-62-….evidence.md` — created (phases, 190 passed on the 7 touched files, 15 mutants with the equivalent and the S-9213 closer, owner checks open).
- Both plan files — Status line set to "BUILT, PROVED AND DOCUMENTED 2026-10-23 (uncommitted; review pending; owner device checks open)"; Progress line set to "P1, P2 and P3 done 2026-10-23 (P3: docs and evidence). Owner device checks open."

## Item 5 — pages opened, none changed

Every sentence the change could have made false was checked; all still hold:

- `docs/rest_tracking.md` — the rest-ping sentence ("a repeating nudge at each multiple… a haptic tap and no sound on the wrist") is still true; no edit.
- `docs/theme_and_settings.md` — "a change reaches the wrist with the answer to the wrist's next sync request" (effort rating, units) is still true: a change moves the stamp, so the next request re-sends; no edit.
- `docs/global_conventions.md` — the rest-rule row is unchanged by both plans; no edit.
- `docs/watch_session_sync/what_does_not_sync.md` — the wrist-taps sentence is still true (the wrist does tap at each multiple; only who asks it changed); no edit.
- `docs/state_management/services_and_utils.md` — the notification scheduler line is phone-side and unchanged; no edit.
- `docs/watch_session_sync.md` — "re-asking for the routines on every wake" (the wrist still asks) and "What the Sync button is still for" (first fetch, manual retry) both still hold; the owed-frame re-send text is about session frames, not the bundle; no edit.
- `docs/watch_session_sync/*.md` — the glob holds only `what_does_not_sync.md`, covered above.

## Size concern

- `docs/watch-app-setup-and-qa.md` is now 60.2 KB (was 58.6 KB before these two steps; ceiling 64 KiB, ~92%). Plan 60's evidence already flagged it for a split before the next watch unit adds a step — that split is not mine to do here.

## Open questions

- None blocking. Interpretation made: "set each plan's Status line" was read as replacing the status phrase only, keeping the Owner/Series/Base-commit tail of the line.

## Governor actions

- None. No file needed to be deleted, moved, or created outside `docs/`.
