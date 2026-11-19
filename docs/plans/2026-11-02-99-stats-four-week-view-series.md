# Series 99 — Stats describes the last four weeks (index)

Owner request 2026-11-02, four changes to the Stats screen. Split into three PRs, in this order.
Each PR is planned when its turn comes, against the code as it is by then.

| PR | Scope | Plan |
|---|---|---|
| 99a | The screen always describes the 28 days ending today; period no longer scopes it; chip reads "· Last 4 weeks"; a break shows one line | `2026-11-02-99a-stats-four-week-window-plan/` |
| 99b | "Rated weeks" counts the last 12 weeks ending today, current ones included; the counter, the load/time gate and the Signals gate all read it | not planned |
| 99c | Fuel: averages over the 7 days ending yesterday, a sentence below 3 logged days, neutral comparison colour (red only for protein under target) | not planned |

## Owner decisions (2026-11-02)

- O-1 Chip text on the Mix and Instruments headers: **"· Last 4 weeks"** (not removed).
- O-2 No training in the last 4 weeks: the Mix card shows one line, **"No training in the last 4 weeks. Last session: <date>."**, with no bar and no Instruments.
- O-3 Fuel gets **no** "Today so far" line (Home shows today).
- O-4 Fuel arrows: **neutral for every comparison** (target or previous week); red only for protein under target.
- O-5 (from the request) Instruments compare against the 4 weeks before; the "N/7 days logged" line stays; below 3 logged days the averages read as the sentence "Log food on 3 days to see a weekly average".

## Shared decisions

- D-17001 The Stats window is a **new** calendar rule (`StatsProgressService.statsWindow`), not a change to `resolveWindow`.
  `resolveWindow` and `computeProgressData` stay as they are, because Records & Trends reads `recentPRs`, which are chosen by
  that window's lift selection (`records_and_trends_screen.dart:87`). Periods keep their meaning everywhere else.
- D-17002 The Stats screen stops calling `computeProgressData`: its PR scan was only read for `.window`.
- Ids: scenarios `S-17001..` (99a), `S-17101..` (99b), `S-17201..` (99c); decisions `D-17001..`. The `S-99xx` range is taken.

## Not decided here (owner may change)

- Records & Trends keeps picking its Recent PR lifts the old way (period, else last 14 training days). Say so if the owner wants that screen on the 4-week rule too.
