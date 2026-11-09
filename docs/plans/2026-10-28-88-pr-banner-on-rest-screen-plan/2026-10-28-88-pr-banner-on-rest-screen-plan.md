# Plan 88: the "New PR" banner shows on the rest screen, right after the log

> Status: BUILT 2026-10-28, awaiting review (developer run; Phase 1 Complete). Series: `docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md`. Follows 87b (`403d96d9`), which put the banner on the logging screen only.

## Goal and acceptance

Owner report (2026-10-28, on the real watch): the "New PR" banner appears only when Next is pressed, never at the moment of the log. Cause (read from source): logging a set starts the rest and the app shell swaps the logging screen for the rest screen at once (`ios/OmniTrain Watch App/ContentView.swift:448`, D-161); the banner is an overlay of `WatchLoggingView` only, so it is torn down with that screen and the 4 s window usually runs out during the rest. The record tap and the state are right; only the screen is wrong.

Acceptance: (1) a set that is a record shows the same "New PR" banner (trophy, accent capsule, top) on the rest screen from the moment the rest screen appears, until the 4 s window ends, then it goes; (2) Next stays tappable under it and nothing moves; (3) VoiceOver hears exactly one announcement per record, whichever screen is up when it is due, never two; (4) the logging screen keeps its banner for logs that do not start a rest; (5) the rest screen adds no timer: it reads the window on its existing TimelineView tick; (6) the record tap, the detection and the banner copy are unchanged.

## Decision Ledger

- D-1 One banner view, two hosts. Extract the banner now inline in `WatchLoggingView.personalRecordBanner` (`WatchLoggingView.swift:185`) into one `WatchPersonalRecordBanner` view (watchOS-only file or the same file, `#if os(watchOS)`), taking the `WatchLoggingState` and the accent; `WatchLoggingView` and `WatchRestView` both overlay it at the top. No second copy of the capsule.
- D-2 Rest host: overlay inside `WatchRestView`'s `TimelineView` closure (`WatchRestView.swift:61`), so the visibility check runs on its existing tick (1 s, 60 s dimmed). `isPersonalRecordBannerVisible(at: state.now())` is time-based, so a late tick cannot show a stale banner on wake.
- D-3 One announcement per record across both screens: `WatchLoggingState` gets `takePersonalRecordAnnouncement() -> Bool`, true once for each stamp of `personalRecordBannerUntil` (it remembers the stamp it last handed out), false otherwise (no stamp, same stamp again, window already over is still true once: the announcement is not time-limited). A second record has a new stamp, so it is true again. Both views call it: `WatchLoggingView` from its existing `onChange` of the stamp, `WatchRestView` from `onAppear` and its own `onChange` of the stamp; only a true answer posts the announcement. The post stays guarded `#available(watchOS 10.0, *)` and the string stays `WatchSpokenText.personalRecord`.
- D-4 Out of scope: the banner length, look and copy; detection; the record tap (played at log time by `WatchLoggingModel.playLogCue`, unchanged); a banner on the summary or rating screens; the phone.
- D-5 Docs: net-zero or smaller. `docs/state_management/watch_surface_wrist.md` is 52196 bytes against a 52428 warning band: reword the existing paragraph "A record logged on the wrist is announced..." (around :591-608) in place so it says the banner shows on the rest screen too, and measure with `wc -c`; if it would pass 52428, shorten other words of the same paragraph. QA step 35 in `docs/watch-app-qa-wrist-logging.md` (b): say the banner shows on the rest screen straight after the log and goes after about four seconds.

## Scenarios

- S-88-1 `takePersonalRecordAnnouncement()`: false before any record; true right after a record log; false the second time for the same record; true again after a second record (new stamp); false after a log that is not a record. Red today (the method does not exist).
- S-88-2 The announcement flag is independent of the clock: still true once when the window has already run out (rest began late), then false.
- S-88-3 Structure (source scan, the pattern of `WatchPersonalBestsWiringSourceTests`): `WatchRestView.swift` hosts the banner view inside its TimelineView and calls `takePersonalRecordAnnouncement`; `WatchLoggingView.swift` hosts the same view; the capsule markup (`trophy.fill`) appears in exactly one source file; no `Timer` appears in `WatchRestView.swift` or the banner file. Must fail on the base commit.
- S-88-4 What 87b pinned still passes: `WatchPersonalRecordBannerTests` (including S-87b10), `WatchPersonalBestsWiringSourceTests` S-87b14 and S-87b22 (the planner of this brief expects the scan strings of S-87b14/S-87b22 to follow the markup into its new file: update the file they scan, never loosen what they assert).

Mutation checks (developer runs, records in evidence): `takePersonalRecordAnnouncement` always true (S-88-1 must fail); never mark the stamp as handed out (S-88-1 second call must fail); remove the banner from `WatchRestView` (S-88-3 must fail); add a `Timer` to `WatchRestView` (S-88-3 must fail).

## Phase 1 (single)

1. Add `takePersonalRecordAnnouncement()` to `WatchLoggingState` (next to `isPersonalRecordBannerVisible`, `WatchLoggingState.swift:332`); private storage of the last stamp handed out.
2. Extract `WatchPersonalRecordBanner`; use it from `WatchLoggingView`; switch the logging view's announcement to the D-3 call.
3. Overlay it in `WatchRestView` with the D-3 `onAppear` / `onChange` announcement.
4. Tests S-88-1..3 (new file `WatchPersonalRecordRestScreenTests.swift` or in `WatchPersonalRecordBannerTests`), update the S-87b14/S-87b22 scans only if the markup moved files.
5. Docs per D-5, plan Progress, evidence file `...plan.evidence.md` (red proof on the base for S-88-1 and S-88-3, the four mutations, test counts).

Done: `gateway.sh swift-test` green (baseline 1124 passed before this plan, record the new number), `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` green, `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty. The governor runs the watch app `xcodebuild` (views compile only for watchOS).

Predicted files: `WatchLoggingState.swift`, `WatchLoggingView.swift`, `WatchRestView.swift`, new banner view file, the new/updated tests, `watch_surface_wrist.md`, `docs/watch-app-qa-wrist-logging.md`, this plan + evidence + index status line.

## Progress

Phase 1 — **Complete** 2026-10-28. Evidence, red proofs and mutations: `...plan.evidence.md`.

- [x] 1. `takePersonalRecordAnnouncement()` on `WatchLoggingState` — private `announcedPersonalRecordUntil`, true once per stamp, false for a non-record and for the same stamp again.
- [x] 2. `WatchPersonalRecordBanner` extracted; `WatchLoggingView` overlays it and announces through the D-3 gate.
- [x] 3. `WatchRestView` overlays the same view inside its TimelineView, with `onAppear` and `onChange` of the stamp calling the gate.
- [x] 4. S-88-1 and S-88-2 added to `WatchPersonalRecordBannerTests`; S-88-3 added to `WatchPersonalBestsWiringSourceTests`, whose S-87b14/S-87b22 scans now read the banner file (assertions unchanged). Red at base: S-88-3 by assertion, S-88-1/2 by compile-then-mutation.
- [x] 5. Docs per D-5, this Progress, the evidence file.
- [x] Done checks: `swift-test` 1127 passed / 0 failed; docs and UI contracts 42 passed; full Flutter suite green; hive import sweep empty.

## Assumption Log

- S-88-1/S-88-2 live in `WatchPersonalRecordBannerTests`, not the new test file the Phase 1 text offers as an option: that class already owns the banner's state tests and the announcement is the same feature.
- The rest host announces from `onAppear` as well as `onChange`: a record whose window is already stamped when the swap happens would otherwise be missed, and the gate makes a second call harmless.
- The logging host keeps its own `onChange` hook instead of a shared modifier: these watchOS surfaces are plain `View` structs with no shared base, and the gate means only one of the two can post.
- D-5 byte band: the paragraph was rewritten shorter per sentence, not longer; two older test names (`testS87b10A…`, `testS87b22…`) left that paragraph while its claims stay backed by the named `testS87b10…`, `…testS88_1…`, `…testS88_2…` and `…testS88_3…`. QA step 35 keeps the full list.
