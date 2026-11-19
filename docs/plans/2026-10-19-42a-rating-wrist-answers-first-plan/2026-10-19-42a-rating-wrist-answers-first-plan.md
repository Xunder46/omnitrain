# Feature: 42a — the watch answers the effort question first: the phone's question closes and cannot overwrite

> Status: BUILT, PROVED (8 of 9; 1 unobservable), docs written, review pending (2026-10-19)
> Next handoff: P1 (`crew-builder-app`)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: e6ff75b0 (branch claude_develop; the tree is NOT clean: plan 41 and earlier work are uncommitted and unrelated, never touched here). Team: the crew (`.claude/crew.md`). The architect step is skipped on purpose: this seed carries decisions, scenarios and phases and the lead validates it.
> Split by the scope guard from one 5-phase, two-track seed: this is 42a (phone only). The other half, the phone answering first so the watch's question closes, is `docs/plans/2026-10-19-42b-rating-phone-answers-first-plan/`.
> Scout sheets: `.work/crew/2026-10-19-42-rating-first-answer-wins/scout-phone.md`, `scout-wire.md` (quotes below were read from them and spot-checked).

## Goal and acceptance

A workout finished on the watch asks "How hard was this session?" on both devices. In 42a: when the watch is answered first, the phone's question closes by itself, the Summary's EFFORT row shows the watch's number, and a late tap on the phone cannot replace it.

| What the user does | Now | After 42a |
|---|---|---|
| Finishes on the watch, answers on the watch first | the phone's sheet stays open; a later phone answer replaces the watch's | the phone's sheet closes by itself, EFFORT shows the watch's number |
| Both answer within moments | last write wins | the phone's number stands (the phone's rating is final, D-138); a rare, documented limit |
| Taps Add rating / Change rating on the Summary afterwards | edits the rating | unchanged: an explicit edit still overwrites; only the automatic post-workout prompt is first-answer-wins |
| Finishes on the phone | only the phone asks | unchanged |

Answering on the phone first is 42b (until it ships, the watch's question stays open and its later answer is ignored by the phone).

## Owner decision (2026-10-19, in chat)

- O-1 first answer wins on both devices; the second device's question closes by itself and cannot overwrite. (42a covers the phone's side of it.)

## Decision Ledger

- D-1 Wrist → phone, state half. The importer already keeps the phone's rating and applies the wrist's only while the row has none (`_topUpRating`, `lib/core/services/watch_session_importer.dart:554-569`, D-138). It writes the repository row only: `WorkoutState.currentSession.sessionFeeling` is untouched and nothing notifies an open Summary (scout-phone Q1). Add `WatchSessionImport.appliedRating` (`int?`: the rating `_topUpRating` actually wrote; set from both call sites, `:284` and `:456`), a callback `onSessionRated(sessionId, rating)` on `WatchSessionInbox` called in `_settleNow` beside `onSessionRowsChanged` (`lib/state/watch/watch_session_inbox.dart:436-446`) only when `appliedRating != null`, wired in `lib/state/watch/watch_sync_wiring.dart` (`:176-185`) to a NEW `WorkoutState.adoptSessionFeeling(sessionId, feeling)` that updates the in-memory `currentSession` when it is that session and notifies, and writes NOTHING (the importer already wrote the row). Implemented in `session_core_lifecycle.dart` beside `updateSessionFeeling` (`:183`) and delegated in `workout_state.dart` (`:154` shows the delegation pattern).
- D-2 First-answer-wins guard, state half: `WorkoutState.updateSessionFeeling(sessionId, feeling, {bool onlyIfUnrated = false})` (`session_core_lifecycle.dart:183`, delegate `workout_state.dart:154`). With `onlyIfUnrated` it reads the stored row first (`_repository.getSession`) and does nothing when the row already holds a rating (the importer may have written it before `adoptSessionFeeling` ran). The default stays false: every other caller (the change control; `_catchUpSessionRow`, `watch_session_adoption_bridge.dart:757-764`) is unchanged.
- D-3 UI half (`lib/features/session/session_summary_screen.dart`): the AUTOMATIC prompt (`_showFeelingSheet` `:264`, `mustAnswer: true`) saves through `updateSessionFeeling(..., onlyIfUnrated: true)`, and while it is open a listener on `workoutState` closes it when `currentSession.sessionFeeling` becomes non-null. The sheet is `showModalBottomSheet` (`lib/widgets/session/effort_rating_sheet.dart`); `mustAnswer` blocks tap-outside, swipe and system back, so the close is programmatic: pop the sheet's own route. The builder reads `docs/navigation_contract.md` first and reports which pop it used. The user-opened change sheet (`_openEffortRatingSheet` `:293`, `mustAnswer: false`) is NOT changed. The Summary has no `workoutState` listener today (no `addListener`/`ListenableBuilder` in the file): add it only for the lifetime of the open automatic sheet and remove it afterwards and in `dispose`. `EffortRatingSheet` keeps writing nothing itself.
- D-4 Limit, stated not fixed: both answered inside the radio latency window, the phone's number stands on the phone and the watch screen of the loser may show its own tap until 42b.

## Code pointers (current text)

`watch_session_importer.dart:554-569`:
```dart
  Future<void> _topUpRating(TrainingSession session, List<WatchInboxEntry> unapplied) async {
    final phone = _ratingOf(unapplied, WatchInboxEntry.kindPhoneRating);
    final wrist = _ratingOf(unapplied, WatchInboxEntry.kindEffortRating);
    final rating = phone ?? (session.sessionFeeling == null ? wrist : null);
    if (rating == null || rating == session.sessionFeeling) return;
    await _repository.updateSession(TrainingSession.fromMap({...session.toMap(), 'session_feeling': rating}));
    changed = true;
  }
```
Called at `:284` (`await pass._topUpRating(existing, unapplied);`, the phone-owned merge) and `:456` (`await _topUpRating(existing, unapplied);`, the history pass). Result type `WatchSessionImport` `:34-52` (`appliedEntryIds`, `changedEffortIds`, `historyChanged`), built at `:218` and `:370`.

`watch_session_inbox.dart:436-446` (`_settleNow`): `final pass = await _importer.apply(sessionId, phoneOwnsSession: ...);` `changed = changed || pass.historyChanged;` `if (pass.changedEffortIds.isNotEmpty) { await _onSessionRowsChanged?.call(sessionId, pass.changedEffortIds); }`

`watch_sync_wiring.dart:176-185`: `final inbox = WatchSessionInbox(repository: repository, transport: resolved, clock: clock, onHistoryChanged: onHistoryChanged, phoneOwnsSession: adoption.holdsSession, onSessionRowsChanged: adoption.refreshHeldEfforts);`

`session_core_lifecycle.dart:183-217` `updateSessionFeeling`: range check, `_repository.updateSessionFeeling`, rebuilds `_currentSession` with `sessionFeeling: feeling`, `_notify()`.

`session_summary_screen.dart:264-290` `_showFeelingSheet` (guards `showFeelingSurvey`, `_hasShownFeelingSheet`, `_isHistoricalView`, `session.sessionFeeling != null`; then `EffortRatingSheet.show(context, mustAnswer: true, ..., onRated: _saveEffortRating)`); `:323-328` `_saveEffortRating` → `widget.workoutState.updateSessionFeeling(session.id, rating)`; `:293` `_openEffortRatingSheet` passes the same `_saveEffortRating` (it must keep the unguarded write).

## Core scenarios (ids checked unused: `grep -rE "S-43[0-9]{2}"` in test/ docs/ watch/ lib/ returns nothing)

Harness: state tests are plain `test()` (never `testWidgets`) under Mock AND Hive for anything stored. Copy the setups of `test/watch_session_import_test.dart` groups `S-264` (`:607`) and `the phone's own rating` (`:1658`) for importer/inbox; `test/pr4_session_controls_test.dart:685` (S-174) for a Summary reached through the bridge; `test/session_summary_effort_row_test.dart:135` (Task 1a) for the Summary sheet.

- S-4301 The session row exists, no rating; the wrist's `effort_rating` (rating 4, id `rating-s-w1`) is staged and settled. Expect `onSessionRated('s-w1', 4)` exactly once, the row's feeling 4, and with the wiring `workoutState.currentSession.sessionFeeling == 4` when that session is current. Fails without: no callback, `currentSession` stays unrated.
- S-4302 The row already holds the phone's 2; a wrist 5 arrives. Expect NO `onSessionRated` call and the row still 2 (D-138). Fails without: a callback fired on every wrist rating would report 5.
- S-4303 Summary widget: an ended fresh session, no rating, survey on, the automatic sheet open. Then `workoutState.adoptSessionFeeling(id, 4)`. Expect the sheet gone after `pump`, the EFFORT row reading `4 / 5`, and the stored row not written by the screen. Fails without: the sheet stays open.
- S-4304 State test: the row holds 4 (the importer wrote it), `currentSession.sessionFeeling` still null (adopt not yet run). `updateSessionFeeling(id, 2, onlyIfUnrated: true)` leaves the row 4 and writes nothing; `updateSessionFeeling(id, 2)` (default) still writes 2. Fails without: the late tap overwrites.
- S-4305 Existing `test/session_summary_effort_row_test.dart` "Fresh session — Change replaces an existing rating" stays green, untouched.

## Readers of what this seed touches (builders run them)

- `WatchSessionImport(` constructors (`watch_session_importer.dart:218,370`) and tests building one: grep `WatchSessionImport(` in `test/`.
- `WatchSessionInbox(` callers: `watch_sync_wiring.dart:176`, `test/watch_session_import_test.dart`, `test/watch_session_merge_test.dart`, others by grep. The new parameter is optional.
- `updateSessionFeeling(` callers: `session_summary_screen.dart` (via `_saveEffortRating`), `watch_session_adoption_bridge.dart:763`, tests (grep).
- Sibling tests to run: `test/watch_session_import_test.dart`, `test/watch_session_merge_test.dart`, `test/pr4_session_controls_test.dart`, `test/session_summary_effort_row_test.dart`, `test/interaction_flow_test.dart`, `test/watch_effort_rating_copy_parity_test.dart`.

## Phases (serial; the lead verifies after each; no builder runs the full suite)

- P1 `crew-builder-app` — D-1 and D-2 with S-4301, S-4302, S-4304 (Mock + Hive). Scope: `lib/core/services/watch_session_importer.dart`, `lib/state/watch/watch_session_inbox.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/workout_state.dart`, new `test/rating_first_answer_state_test.dart`.
- P2 `crew-builder-app` — D-3 with S-4303 and S-4305. Scope: `lib/features/session/session_summary_screen.dart`, new `test/rating_first_answer_summary_test.dart`. Report which pop is used.
- P3 `crew-docs-keeper` — `docs/watch_session_sync.md` (52,218 of 65,536 bytes: add at most ~1 KB), `docs/session_summary.md`, `docs/state_management/watch_surface.md` only if it names the changed classes, plan evidence.
- Then `crew-prover` (mutations applied by the lead), `crew-reviewer`, a simulator look at the Summary sheet.

Size: about 70 production lines, about 300 test lines, 3 phases, one track (phone): inside the scope budget.

## Owner checks (owner)

- (owner) Finish a session on the watch with the effort question on; answer on the watch: the phone's sheet closes and the Summary shows the watch's number.
- (owner) Afterwards tap Change rating on the Summary: it still changes the number.

## Progress

| Phase | What | Result |
|---|---|---|
| P1 | `crew-builder-app` — D-1, D-2 with S-4301, S-4302, S-4304 (Mock + Hive) | Done: importer `appliedRating`, inbox `onSessionRated`, wiring `adoptRating`, `adoptSessionFeeling`, `onlyIfUnrated`; `test/rating_first_answer_state_test.dart` (5 tests) green on Mock and Hive |
| P2 | `crew-builder-app` — D-3 with S-4303 and S-4305 | Done: `_saveAutomaticRating` (`onlyIfUnrated: true`), `_closeAutoSheetOnOutsideRating` listener; `test/rating_first_answer_summary_test.dart` (3 tests) green; S-4305 untouched and green |
| Gap round | `crew-prover` — 9 mutations by hand | 8 made a named test red and were restored byte for byte; 1 unobservable (`route.isCurrent` guard in `_closeAutoSheetOnOutsideRating`, defensive) — see the evidence file |
| P3 | `crew-docs-keeper` — docs and evidence | Done: `docs/session_summary.md`, `docs/watch_session_sync.md`, `docs/state_management/workout_state.md` (`updateSessionFeeling` parameter, `adoptSessionFeeling` row); `docs/state_management/watch_surface.md` checked — names `WatchSessionInbox` only as a graph component, no surface described, no update required; evidence file written |

## Assumption Log

- A-1 The automatic prompt is the only first-answer-wins surface; the Summary's Add/Change control stays an explicit edit.
