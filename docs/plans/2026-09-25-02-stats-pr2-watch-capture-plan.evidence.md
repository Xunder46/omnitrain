# PR 2 — Evidence for the final mechanical round (N1 – N7)

Companion to `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`.
Findings are `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.review.md`
(re-review, 2026-09-26, APPROVE WITH NITS). §2 of `.github/agents/pr_scope_budget.md`
is why this file exists and the plan holds only one line per item.

Start of the round: the re-reviewed tree. `flutter test` `01:14 +2994 ~1: All tests
passed!`, `swift test` `Executed 242 tests, with 0 failures`, `flutter analyze`
`242 issues found.`

## Round totals

| Check | Start of round | After the round | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` | `242 issues found. (ran in 3.4s)` | No new diagnostics |
| `flutter test` | `01:14 +2994 ~1` | `01:15 +2999 ~1: All tests passed!` | +5, all new: N1's two end-of-scale tests, N2's calendar test, N4(c)'s two setter tests |
| `cd watch/watchos && swift test` | `Executed 242 tests, with 0 failures` | `Executed 242 tests, with 0 failures (0 unexpected) in 0.838 (0.850) seconds` | Count unchanged: N3 and N6 changed an existing test and a rejection message, not the number of tests |
| watchOS type-check, simulator SDK, `arm64-apple-watchos9.0-simulator` | exit 0 | exit 0, 0 errors | `WatchEffortRatingView.swift` still compiles for the watch (the view is `#if os(watchOS)`, so `swift test` cannot see it) |
| watchOS type-check, device SDK, `arm64_32-apple-watchos9.0` | exit 0 | exit 0, 0 errors | The arch the reviewer checked; the simulator SDK has no arm64_32 standard library |
| `swift build --build-tests` warnings in the changed files | — | none | No new warning in `SyncProtocolValidator`, `WatchEffortRating`, `WatchSensor*` |
| `flutter test test/docs_indexing_contract_test.dart` | — | `00:00 +9: All tests passed!` | `theme_and_settings.md` 7,318 B, `watch_session_capture.md` 19,044 B, both under the band |
| Line endings | — | every touched file `CR=0` | `test/watch_session_import_test.dart`, `test/settings_state_test.dart`, `manifest.json`, `PROTOCOL.md`, `SyncProtocolValidator.swift`, `WatchEffortRatingTests.swift`, both docs: LF before and after |

## What each finding's fix is

- **N1.** The `A-50` group gained two tests for the ends of the scale: 1 and 5 are
  recorded and staged before the import, and written to the session after it.
- **N2.** A new `F-8 the calendar shows the rating the write left` test drives a real
  `CalendarState` through `onHistoryChanged` (as S-271's test does) and reads the rating
  back off the entry.
- **N3.** The F-7 test picks 3 before the wraps, so the clamp cannot stand in for the
  guard; a one-detent turn after a wrap asserts a middle value.
- **N4.** `theme_and_settings.md`: the `show_feeling_survey` key rationale is back, as one
  sentence; the "or off App State" clause is gone; the setter-normalisation claim is
  pinned by two new tests in `test/settings_state_test.dart` (weight unit, week start);
  and the Theme System section carries a §5 flag naming its enum block and token table as
  prohibited-but-pre-existing.
- **N5.** `PROTOCOL.md`'s schema-dialect paragraph states that `integer` means an integer
  on the wire, cites the new fixture, and points at its `expectedReasonContains`.
- **N6.** `describe` keeps the fraction for a float-typed number, so Swift and Dart both
  read `expected integer, found 3200.0`; the fixture's register entry pins that wording.
- **N7.** `watch_session_capture.md`'s liveness invariant now cites the S-284 refresh
  assertions as well as S-271; the plan's A-50 note says "state layer" instead of "both
  layers".

## Red→green

Harness `/private/tmp/pr2_nits_redgreen.py`, logs in `$TMPDIR/pr2-nits-redgreen/`. Per
case: shasum and copy the file, apply one textual mutation (asserted to match exactly
once — N4(c)'s first draft matched twice, because `_loadFromPrefs` carries the same line,
and the case was narrowed to the setter body), require a failure whose log cites the
finding and holds no compile error, copy back, prove the restore with `cmp` and a matching
shasum, re-run green. All five restored byte-identically and went green.

| # | Finding | Behaviour reverted (file) | Red — failing assertion | Green |
|---|---|---|---|---|
| 1 | N1 | the range check made exclusive: `rating <= 1 \|\| rating >= 5` (`watch_session_inbox.dart`) | `Expected: true / Actual: <false>` — `A-50 1 is on the 1–5 scale` | `+1` |
| 2 | N2 | the refresh moved ahead of the write (`watch_session_inbox.dart`) | `Expected: <2> / Actual: <4>` — `F-8 the refresh runs after the write, so the calendar holds the phone's rating (D-142)` | `+1` |
| 3 | N3 | the wrap guard widened to twice the range (`WatchEffortRating.swift`) | three assertions, `WatchEffortRatingTests.swift:436,438,443`: `("Optional(1)")` vs `Optional(3)` — `F-7 a wrapped −10 after +10 does not move the picked number`; `("Optional(5)")` vs `Optional(3)`; `("Optional(4)")` vs `Optional(2)` — `a turn after a wrap counts from where the crown now is` | `Executed 1, 0 failures` |
| 4 | N6 | the fraction dropped again in `describe` (`SyncProtocolValidator.swift`) | `invalid/observations_up_steps_as_double.json: no rejection explains expected integer, found 3200.0` | `Executed 1, 0 failures` |
| 5 | N4(c) | `setPreferredWeightUnit` no longer accepts `lb` (`settings_state.dart`) | `Expected: 'lbs' / Actual: 'kg'` — `given LB` | `Executed 1, 0 failures` |

The new N1 and N2 tests were shown red before the round's first change too: with the
original `recordPhoneRating` the calendar test read 4 where the write had left 2.

Assertion-change table: **empty.** No pre-existing assertion, expectation or fixture was
modified. `watch_session_import_test.dart` changed in construction plus additions: the
`septemberCalendar`/`holds` helpers moved out of the S-271 group to file scope (so the new
F-8 test can use them; `holds` is now a thin wrapper over the new `calendarEntryIn`), and
the A-50 group gained two tests. Nothing was loosened; no skip or tolerance was added.

## Footprint

- N1, N2: `test/watch_session_import_test.dart`.
- N3: `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift`.
- N4: `docs/theme_and_settings.md`, `test/settings_state_test.dart`.
- N5: `watch/sync_protocol/PROTOCOL.md`.
- N6: `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`,
  `watch/sync_protocol/fixtures/manifest.json`.
- N7: `docs/watch_session_capture.md`, this plan's A-50 note.
- This file.

No production Dart was touched: the round is tests, one Swift rejection message, two docs,
one protocol doc and one fixture register entry. Nothing under `lib/watch/` (D-101);
`lib/state/watch/watch_session_inbox.dart` and `lib/state/settings/settings_state.dart`
were read and mutated in place only, and both were restored byte-identically.

## Left out, on purpose

- **N8** (pre-existing crown wrap in `WatchLoggingView`/`WatchNutritionView`) — Open Item
  O-20 in the plan; outside PR 2.
- **N9** (the durable store must reload integers as integers) — a shipping-plan Phase 7
  checklist item, where the store is built.
- `F-12`'s scenario-id renames and the `live_session_screen` import nit were the
  reviewer's optional items and remain undone, as the plan records.

## V round (V-1 – V-4) — @developer, 2026-09-26

Findings: the pre-approval verification pass (APPROVED WITH WARNINGS), section V in the review
companion. Start of the round: `flutter test` `01:16 +3000 ~1` (the new V-1 test already in the
tree), `swift test` `Executed 242 tests, with 0 failures`, `flutter analyze` `242 issues found.`

| Check | Start of round | After the round | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` | `242 issues found. (ran in 2.7s)` | No new diagnostics; the five in `lib/state/watch/` and `effort_rating_sheet.dart` are pre-existing `withOpacity` deprecations |
| `flutter test` | `01:16 +3000 ~1` | `01:14 +3000 ~1: All tests passed!` | Count unchanged: V-1's test landed before the round's first measurement, and V-3 removed an unread field rather than a test |
| `cd watch/watchos && swift test` | `Executed 242 tests, with 0 failures` | `Executed 242 tests, with 0 failures (0 unexpected) in 0.826 (0.839) seconds` | No Swift file is touched by this round |
| Suites touching the two edited files | — | `flutter test test/watch_session_import_test.dart test/watch_capture_contract_test.dart test/watch_transport_test.dart test/live_session_effort_rating_test.dart test/session_summary_effort_row_test.dart test/watch_capture_repository_parity_test.dart test/watch_effort_rating_copy_parity_test.dart` → `00:02 +134: All tests passed!` | Covers every reader of `WatchInboxResult` and `EffortRatingSheet` after V-3's signature change |
| `dart format --output=none` on the three edited Dart files | — | `Formatted 3 files (0 changed)` | — |
| Line endings | — | `CR=0` for `test/settings_state_test.dart`, `lib/state/watch/watch_session_inbox.dart`, `lib/widgets/session/effort_rating_sheet.dart`, `feature_primitives.md` | LF before and after (the repo's CRLF files were not touched) |

### Red→green

| Finding | Mutation | Red | Restore | Green |
|---|---|---|---|---|
| V-1 | the default passed to `getPreferenceString` in `SettingsState._loadFromPrefs`, `'kg'` → `'lbs'` | `SettingsState defaults preferred weight unit to kg [E]`: `Expected: 'kg' / Actual: 'lbs'`, `test/settings_state_test.dart:142:5` | `cmp` clean, sha `789d1b7d4630…` both sides | `test/settings_state_test.dart` `00:00 +50: All tests passed!` |

The **first** mutation tried — the field initialiser `String _preferredWeightUnit = 'kg';` — stayed
green. That is the finding worth keeping: `initialize()` recomputes the value through
`_loadFromPrefs`, so the initialiser is shadowed and only the repository default decides (A-72). A
green mutation is a failed measurement, not proof that the test is weak; the mutation was retargeted
rather than the test accepted.

### V-4 — why the barrier literal could go and the radii could not

- `barrierColor: Colors.black54` **deleted.** The SDK resolves it to the identical colour:
  `bottom_sheet.dart:1285` passes `barrierColor ?? Theme.of(context).bottomSheetTheme.modalBarrierColor`,
  and `:1064` reads `Color get barrierColor => modalBarrierColor ?? Colors.black54`. The app defines no
  `BottomSheetThemeData` (grep: no match in `lib/`), so the fallback lands on `Colors.black54`. The
  argument could only ever have restated it.
- The sheet's top radius `Radius.circular(20)` → `OmniTheme.surfaceBorderRadius`. Same value (20.0),
  and it was the only literal in the file with a token to take.
- `BorderRadius.circular(14)` (tile) and `backgroundColor: Colors.transparent` **stay.** No radius
  token exists between 12 and 20, and both are PR 1's values moved verbatim; changing either moves
  pixels against the extraction's zero-visual-change mandate. Recorded as A-73 and Open Item O-21, not
  fixed silently.

### Footprint

- `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md` — one Progress line, O-21,
  A-72/A-73.
- `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.review.md` — the resolution
  section under the V verdict.
- This file.
- Production Dart: `lib/state/watch/watch_session_inbox.dart` (V-3) and
  `lib/widgets/session/effort_rating_sheet.dart` (V-4). Tests: `test/settings_state_test.dart` (V-1).
  Docs: `widget_catalog/feature_primitives.md` (V-2, pre-existing drift the reviewer raised).
- `lib/state/settings/settings_state.dart` was mutated twice and restored byte-identically both times
  (`789d1b7d4630…`).
