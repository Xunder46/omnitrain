# Series 38 — Exercise logger rework (index)

Owner request 2026-10-15 with four mockups (reps, count-up, countdown, hold). Mockups are rough: the written spec wins where they differ. Owner: "mostly a UI update with minimal functionality adjustments"; the rest chip stays exactly as it is. Scenario ids for the series: `S-42xx` (checked free in `test/`, `docs/`, `watch/`, `lib/`).

Why a series: the shell touches every modality and 15 widget-test files; the reps, count-up and countdown screens each bring a new shared control; the routine editor reuses them. One plan would pass the 800-line / 5-phase budget (`.github/copilot/pr-scope-budget.md`).

## PRs, in order

| PR | Scope | Depends on |
|---|---|---|
| 38a | Shell for every modality, live and session-edit: segmented set bar (unlogged / focused / logged), set count text, logged-values line, `LOGGED` kept and logged inputs locked in live mode, focus to the next unlogged set after a log, small sets stepper, layout (hero top, empty space under it, controls at the bottom). Full plan: `2026-10-15-38a-logger-shell-plan/` | — |
| 38b | Reps screen: shared `ValueStepperRow` (full-width row, minus left, plus right, big number, tap opens the existing input popup, long-press accelerates); weight step from the unit setting (2.5 kg / 5 lb). Used for reps and weight in live and session-edit | 38a |
| 38c | Count-up (cardio intervals, holds): plain big elapsed digits, no ring, no time stepper, Start → Log locks the elapsed time; weight stepper on holds only, removed from cardio | 38b (weight row) |
| 38d | Countdown (rounds): shared timer ring with remaining digits, round-length row (15 s step + tap popup), locked while running, a change applies to this and the later unstarted rounds, Start → Log Round records time done | 38b | Plan: `2026-10-16-38d-countdown-plan/` (seeded 2026-10-16, runs after 38f).
| 38f | Polish from the owner's side-by-side look: header one line, bar pinned under it with captions (5 sets or fewer), no border, boxed rows and sets control with `Set X of Y` inside, weight 0/negative shown, and the bug that a deleted logged set came back. Plan `2026-10-15-38f-logger-polish-plan/` (seeded, runs after 38c lands) | 38c |
| 38e | Routine create/edit screens and session-edit controls use the same shared rows where the same control exists (reps, weight, round length, set count) | 38b, 38d |
| 39 | Round-2 polish of the same screens from the owner's second look: one digits formatter with hours (`OmniDateUtils.formatTimerDigits`), a 10 h duration ceiling (`MetricStepCalc.maxDurationSeconds`), the unit label under the number plus a `tap to type` hint, the cardio interval weight row back (supersedes O-11 for the interval), hero count-up digits, ring digits, tightened sports body. Plan: `2026-10-17-39-logger-polish-2-plan/` | 38a–38e |

Plan each later PR when its turn comes, against the code as it is by then.

## Decisions shared by every PR (owner, 2026-10-15)

- O-1 No Pause control (nothing to keep: the screen has none today).
- O-2 A logged set is a logged set: in a live session its inputs are locked and the centre control shows `LOGGED` (as today). Values change only in the session editor (edit mode), which keeps its navigation-only controls and the screen-level Save.
- O-3 After the last set of an exercise is logged focus goes to the next exercise (as today).
- O-4 The sets stepper `−` removes the last unlogged set (the last set when all are logged), with today's confirmations (logged set: `Delete logged …?`; only set left: `Remove Exercise?`). `+` adds a set as today (max `WorkoutConstants.maxEntriesPerEffort`).
- O-5 Reps screen: two full-width rows (reps, then weight), minus on the left, plus on the right, tap the number for the input popup as today.
- O-6 Round length: 15 s step; a change before Start applies to this round and every later unstarted round of the exercise.
- O-7 Session editor and routine create/edit screens match the live screen wherever the same control appears.
- O-8 The rest chip is untouched (appears after a log, hides while a timer runs, tap pauses/resumes).
- O-9 The logged-values line shows logged sets only; an unlogged set is blank, never `—`.
- O-10 Weight step follows the unit setting: 2.5 kg or 5 lb (the watch's steps); long-press accelerates.
- O-11 Hard product rule: the modality's effort kind decides the screen, not the exercise's flags. Weight control: resistance (`set`) and isometric holds (`drill`) only; never on cardio intervals (`timed`) or rounds, whatever the exercise carries. (Superseded for the interval by plan 39 D-5: the interval carries a weight row again; rounds still never do.)
- O-12 Tap-to-type keeps the existing popup (`showMetricEditPopup`, `showDurationEntryDialog`).
- O-13 (owner, 2026-10-16) Captions under the timer digits stay: `REMAINING` / `COMPLETED` on rounds, `ELAPSED` / `COMPLETED` on count-up (restored by 38d, 38c had removed them). The old heading and status row are not captions and stay removed.
- O-14 (owner, 2026-10-16) No approval needed between series PRs: the lead starts the next one when the previous has landed and is verified.

## Technical decisions shared by every PR (lead)

- T-1 New shared pieces live in `lib/widgets/session/` and are added to the shared-pieces table in `docs/design_system.md` (no stepper or segmented bar exists today; `OmniBottomCTA` is not used on this screen, the arrows-around-button row stays).
- T-2 No data-model, repository or watch-wire change anywhere in the series. Stored cardio `extra-weight` rows stay in the data; the screen stops showing them (38c).
- T-3 No new hand-built dialogs or sheets; touch targets at least 48 dp (no test enforces it: the lead measures on the simulator).
- T-4 Tooltips `Add set`, `Remove set`, `Remove exercise` and the button texts (`Log Set`, `Start`, ...) are kept so existing tests keep reading them.

## Status

- 38a built, reviewed (APPROVE), docs written, full suite `+4788 ~1` green, analyze 182; uncommitted (owner commits). Owner items: confirm the two open questions in the 38a plan, look at the screens on a device.
- 38b built, reviewed (APPROVE WITH FIXES, fixed), docs written; plan `2026-10-15-38b-reps-screen-plan/`; uncommitted on top of 38a (owner commits). Owner items: feel of the hold speed (A-1 in the 38b plan), look at the screen on a device, session editor and pounds.
- 38c built, reviewed (APPROVE WITH FIXES, fixed), docs written; plan `2026-10-15-38c-count-up-plan/`; uncommitted on top of 38a+38b (owner commits). Full suite `+4846 ~1`, analyze 182. Owner items: the bare `00:00` with no `ELAPSED` caption and no status row (plan A-1), hold weight limits -200..999 (A-2), look at the screens on a device.
- 38d-38e not planned: plan each when its turn comes, against the code as it is by then.

- 38d built, reviewed (APPROVE), docs written, full suite `+4969 ~1`, analyze 182; uncommitted. Next: 38e.
