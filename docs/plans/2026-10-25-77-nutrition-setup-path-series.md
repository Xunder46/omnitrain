# Series 77 — Nutrition setup path

> Status: 77a seeded 2026-10-25; 77b-77d outlined, not planned. Owner analysis of the first-run nutrition path (2026-10-25) split into PR-sized units (`.github/copilot/pr-scope-budget.md`). One unit at a time; none grows to absorb another.

## Owner decisions (2026-10-25, asked and answered)

- **O-1** Editing a food picked from the built-in catalog changes only the user's own copy. The shipped catalog entry is never altered. An edited food offers "Reset to original".
- **O-2** The manage screen has two tabs: **Library** (every food; ones the user created are tagged "Yours"; a "Create new food" button lives inside Library) and **Categories**. The "My Foods" tab goes away.
- **O-3** In Library, tapping a food row adds it to / removes it from the user's list. A food that is in the list shows a clear primary-colour outline and a check (no red trash can). Editing is a small, explicit Edit control on the row.
- **O-4** Eating the same food twice: out of scope. The user updates the amount.

## Lead's defaults (stated to the owner; change on request)

- **L-1** Edit control only on foods already in the user's list (it edits "your copy"). Foods not yet in the list show no Edit control.
- **L-2** Removing an in-list food by tapping its row still asks first (it also takes the food off today's log).
- **L-3** Foods the user created keep today's edit behaviour (they have no shipped original), and show no Reset.

## Units

| Unit | What the user sees | Status |
|---|---|---|
| 77a | Library: row tap adds/removes with outline + check; small Edit control; edits touch only your copy, with Reset to original; "48 cal per 100 ml" on every Library row | seeded |
| 77b | Manage screen: "My Foods" tab merged into Library ("Yours" tag, "Create new food" button inside); Library grouped by category | outlined |
| 77c | First run: empty Foods I Eat list IS the picker; home card says what it is; day-one water/sodium noise reduced | outlined |
| 77d | Foods I Eat row: clearer log toggle and amount caption; primer shows at a better moment | outlined |
