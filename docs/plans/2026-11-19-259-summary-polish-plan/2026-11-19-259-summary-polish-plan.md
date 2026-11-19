# Plan 259 — Summary polish: no pop-in, rounds titled by session type, "0s", phone clock

Review item 30 (owner list: "Summary: cards pop in after loading; any rounds are titled 'Sports'; rest reads '0' with no unit; clock always 12-hour").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

On the workout summary screen:

- The screen does not show its cards in two steps. On first open it shows a spinner under the header until the figures are ready, then everything at once (no group cards popping in under the session card). Reloads after an edit keep the screen as it is.
- The rounds card is titled `Sports` in a Sports session and `Rounds` in any other session (it was `Sports` everywhere).
- A zero rest or zero total time reads `0s` (was `0`).
- The date line follows the phone's 12/24-hour setting: `Nov 19 at 8:08 AM`, or `Nov 19 at 08:08` on a 24-hour phone (was always 12-hour).

Acceptance: S-25901..S-25905 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25901 | Hold the screen: a `_hasLoadedOnce` flag stays false until the first `_loadAsyncData` ends; while false the body shows the header, a centred spinner and no cards. Later reloads never blank the screen. | `session_summary_screen.dart` `_loadAsyncData`, `build` |
| D-25902 | `_groupLabels['rounds']` is replaced by a function: Sports session -> `Sports`, any other -> `Rounds`. | `_buildGroupCard` |
| D-25903 | `_formatDurationOrZero(<= 0)` returns `0s`. | `_formatDurationOrZero` |
| D-25904 | `_formatDateTime` uses `MaterialLocalizations.formatTimeOfDay` with `MediaQuery.alwaysUse24HourFormatOf(context)`. | `_formatDateTime` |

## Scenarios

| ID | Fixture | Expect | Fails without because |
|---|---|---|---|
| S-25901 | pump the summary of a finished strength workout, one frame only | no group card and a spinner; after settling the Strength card is there and the spinner gone | cards arrived after the first frame |
| S-25902 | a Sports session with a round exercise; and a Free session with one | `Sports` card title; `Rounds` card title | title always `Sports` |
| S-25903 | a finished workout with no rest | the REST TIME value reads `0s` | read `0` |
| S-25904 | MediaQuery 12-hour | date line ends with `AM` or `PM` | control |
| S-25905 | MediaQuery `alwaysUse24HourFormat: true` | no `AM`/`PM`, a `HH:mm` time | always 12-hour |

## Input-reality checklist

1. Writers: none. 2. Lifecycle: reload after Edit Session must not blank the screen (D-25901). 3. Settings: the phone's 12/24-hour setting only. 4. Time: only the date line. 5. Cost: none. 6. Words: `Rounds`, `0s` (owner to read). 7. Competition: the feeling sheet opens after the first frame as before.

## Phases

1. Production code in `lib/features/session/session_summary_screen.dart`.
2. Tests `test/summary_polish_test.dart`; fix readers that expected `0`, `Sports` or the old pop-in.
3. Full suite against the Windows base set, analyze, docs.

## Docs delta

`docs/session_summary.md`: Group Cards section names the rounds-card title rule, zero reads `0s`, the date line follows the phone's clock setting, and first open waits for the figures (plan 259).

## Open items

1. (owner) Defaults taken: hold-the-screen rather than reserving card space; `Rounds` as the non-sports title; the clock change covers the summary only (other screens' times unchanged).
