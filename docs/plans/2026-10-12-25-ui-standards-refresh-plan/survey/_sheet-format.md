# Common sheet format: UI/UX standards survey (read-only)

Purpose: the owner wants the written UI/UX standards (`docs/design_system.md`, `docs/widget_catalog/`, the
screen docs, `docs/global_conventions.md`) to match what the phone app really does, plus a list of gaps.
You are collecting FACTS. You do not rewrite docs, change code, or decide who is right. Phone app only:
ignore `watch/`, `lib/watch/` and the Swift package.

The project's documentation standard (`docs/documentation_standard.md`) says docs may hold only structure,
rationale, invariants (each naming the test that enforces it) and vocabulary. They must NOT hold visual
values (hex colours, sizes, spacings, durations), control/gesture inventories, or step-by-step flows. So
"a doc claim is stale" and "a doc claim should not be in a doc at all" are different findings.

## How to work

- `grep`/`glob` first, then `view` ranges. Quote verbatim (at most 12 lines per quote) with `path:line`.
- Write the sheet as you go (create after the first finding, then append). Keep it under ~350 lines: be
  selective, prefer the findings an owner would care about. Say how many you saw if you stop at a cap.
- Never write "probably" without saying what you did not check. "Searched X, found nothing" is a result.
- Final message: sheet path and, per section, a one-line status (done / partly / not done).

## One block per finding

```
### F<n> · <KIND> · <short title in plain words>
- Where the doc says it: <doc path:line, quoted>   (omit for NO-RULE)
- Where the code does it: <lib path:line, quoted>  (omit if not applicable)
- What a user would see: <one or two plain sentences, no identifiers>
- Guard: <test file + group/test name that enforces it, or "none found: searched <terms>">
- Unsure: <what you could not establish>
```

KIND is exactly one of:
- STALE-DOC: the doc names something (widget, token, screen, rule) that no longer exists or no longer works that way.
- BREAKS-RULE: a written rule exists and the code does not follow it (give the rule and the offending place).
- NO-RULE: the code does something consistent and user-visible that no doc states as a rule.
- INCONSISTENT: two places do the same job two different ways, and no document says which is right.
- NO-GUARD: a written rule that holds today, but no test would fail if it stopped holding.
- DOC-OFF-STANDARD: a doc passage breaks `documentation_standard.md` (hex, numbers, control list, flow, roadmap, to-do).
- CONFLICT: two documents disagree with each other.

Do not list findings of kind OK. Do not list tiny wording drift. Order the sheet: BREAKS-RULE, INCONSISTENT,
CONFLICT, STALE-DOC, NO-RULE, NO-GUARD, DOC-OFF-STANDARD.

## The pattern matrix (only the area scouts S6-S9 fill this)

At the end of your sheet add a table, one row per screen in your area, one column per pattern, each cell the
shared component it uses (name it), "custom" (and where), or "none":

P1 screen top bar/header · P2 section/card header · P3 empty state (what it says) · P4 locked/unavailable
explanation · P5 confirmation dialog · P6 unsaved-changes guard · P7 text/number entry (select-on-focus,
keyboard dismissal, capitalisation) · P8 bottom primary action · P9 bottom sheets and modals · P10 buttons
and colours from theme tokens (any raw colour or font size) · P11 text-scale overflow / tap-target size /
semantics labels · P12 charts

Cells you did not check: write "?" and say why in a line under the table. Never guess a cell.
