# Plan 262 — Add Session waits for a routine

Review item 34 (owner list: "Calendar: choosing 'Routine' without picking one saves as Free Training. Suggested: disable Add Session until a routine is chosen.").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

In the calendar's New Planned Session form, with `Routine` selected and no routine chosen, the `Add Session` button is off. Choosing a routine turns it on. `Free Training` mode is unchanged (on at once). Editing an existing routine plan (its routine already chosen) keeps `Save Changes` on.

Acceptance: S-26201..S-26203 green, S-26202 red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26201 | `_PlannedSessionFormState`: the submit button's `onPressed` is null while `_mode == 'routine' && _selectedTemplateId == null`. No helper text (the empty Routine dropdown already asks for a choice). | `day_session_list_screen.dart` |

## Scenarios

S-26201 Free Training: button on. S-26202 Routine, nothing chosen: button off (fails without: the button was on). S-26203 pick `Push day`: button on.

## Input-reality checklist

1. Writers: none. 2. Lifecycle: editing a routine plan starts with its routine chosen. 3. Settings: none. 4. Time: none. 5. Cost: none. 6. Words: none new. 7. Competition: none.

## Docs delta

`docs/calendar_periods.md`: one sentence before "Past days are read-only".

## Open items

1. (owner) With no routines saved, Routine mode keeps the button off and the dropdown empty: no message says why. Say if you want a hint line.
