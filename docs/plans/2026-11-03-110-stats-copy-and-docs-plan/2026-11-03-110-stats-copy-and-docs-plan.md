# 110 — Two honest sentences on Stats, and the docs the analysis found missing

Status: SEEDED by the lead 2026-11-03 (no architect run: exact production text below; test text sits in the builder brief).
Base commit: `.work/2026-11-03-110-stats-copy-and-docs/base.txt` (3fa8c9a9). Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart` (another session's DST hunks) and `test/stats_dst_day_arithmetic_test.dart`.
Series: Stats screen analysis 2026-11-03, PR 4 of 4 (items W3, W4, D2, D3, D4). Owner answers 2026-11-03: **W2 leave as is** (the "How Stats works" sheet already says "a few weeks of history"); **W3 a shorter line when waiting lines show**. Committing is pre-approved when verified (`commit-ok.txt`).
Out of scope: W2 (decided: no change), D1/D5 beyond keeping `docs/stats_screen.md` under its size band, any other copy.

## Goal and acceptance

What a user sees after this PR:

1. **W3** When Signals has nothing to say but a waiting line sits under it (for example "Protein Consistency: log food on 9 more days of the last 14."), the quiet line reads **`No signals right now.`** instead of `No signals — nothing outside your usual range.`, which read as "nothing here" right above lines about things that are here. With no waiting line the quiet line is unchanged.
2. **W4** The "How Stats works" sheet says the Weight rule as it is: `... and your weight change once you have two weigh-ins at least a week apart in the last four weeks.`
3. Docs: the Settings screen row lists the `STATS` section and `Weight on Stats` and says what Start of Week now drives (D2); the widget catalog has a `WeightTrendRow` entry (D3); the Stats screen's Weight block section points at the rule's page instead of only naming a test (D4).

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-18401 | New constant `kSignalQuietLineWithWaiting = 'No signals right now.'` next to `kSignalQuietLine`; `SignalsLayerSection._quietLine` returns it when `waiting.isNotEmpty` (the lines actually passed to the layer, at most `kSignalMaxWaitingLines`), otherwise `kSignalQuietLine`. The widget key stays `signals_quiet_line` in both cases | `signals.dart`, `signals_layer.dart` |
| D-18402 | The primer's page block ends `... and your weight change once you have two weigh-ins at least a week apart in the last four weeks.` (the real rule: kilogram readings, at least 7 calendar days apart, within 28 days; the switch and a completed session are shown elsewhere) | `stats_primer_sheet.dart` |
| D-18403 | The test that pinned the old copy next to waiting lines (`S-17605 ... the quiet line keeps its copy and the line follows it`) changes its expectation and its name to `the quiet line shortens and the line follows it`; the doc line that cites it changes with it | `signals_layer_screen_test.dart`, `stats_screen.md:297` |
| D-18404 | `docs/stats_screen.md` is at 52,290 bytes and its band is 52,428: its two edits (the test name, the Weight block pointer) add at most 80 bytes; the lead measures after. The explanation of the shorter line goes in `docs/signals.md` (15 KB) | docs |
| D-18405 | Ids S-18401 (shorter line with waiting lines), S-18402 (constant pin), S-18403 (primer wording: the existing group `S-18001 the primer says what the Stats screen shows today` changes its expected string, no new test) | tests |
| D-18407 | The three docs-only rows (Settings row, `WeightTrendRow` entry, Weight block pointer) are backed by tests that already exist and that the new sentences name: `test/weight_trend_screen_test.dart` groups `S-17705 the Weight block` and `S-17706 the Weight on Stats switch` | docs |
| D-18406 | Proof: the lead's mutations M1-M3; the docs are written by the lead (small, exact) | Assumption Log |

## Exact production code

`lib/core/models/signals.dart`, directly after the `kSignalQuietLine` constant (line 27):

```dart

/// The quiet line when waiting lines sit under it (plan 110, D-18401): "nothing
/// outside your usual range" would read as "nothing here" right above lines
/// that name what is still missing, so this one claims only the present.
const String kSignalQuietLineWithWaiting = 'No signals right now.';
```

`lib/features/stats/widgets/signals_layer.dart`, `_quietLine`: the line `kSignalQuietLine,` inside `Text(` becomes

```dart
      waiting.isNotEmpty ? kSignalQuietLineWithWaiting : kSignalQuietLine,
```

`lib/features/stats/widgets/stats_primer_sheet.dart` (the page block, lines ~94-96): the last two string pieces
`'before, your Fuel row once you log food, and your weight '` / `'change once you have two weigh-ins a week apart.',` become
`'before, your Fuel row once you log food, and your weight '` / `'change once you have two weigh-ins at least a week apart '` / `'in the last four weeks.',`.

## Scenarios

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-18401 | `signals_layer_screen_test.dart`, gate met, one abstaining stub with a waiting line (the existing S-17605 fixture) | the `signals_quiet_line` text is `kSignalQuietLineWithWaiting` (`No signals right now.`) and the waiting line sits below it. With NO waiting line (the existing S-1703 fixtures) the text stays `kSignalQuietLine` | the layer ignores `waiting` (M1: always the long line; M2: always the short line fails S-1703) |
| S-18402 | `signals_framework_test.dart`: the two strings | `kSignalQuietLine` is `No signals — nothing outside your usual range.` and `kSignalQuietLineWithWaiting` is `No signals right now.` | the constant is missing or reworded |
| S-18403 | `stats_primer_copy_test.dart`, group `S-18001 the primer says what the Stats screen shows today`: the page block body | ends `... your weight change once you have two weigh-ins at least a week apart in the last four weeks.` | the sheet still says `a week apart.` (M3) |

## Phases

| Phase | Agent | Write scope | Items | Order |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/core/models/signals.dart`, `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/widgets/stats_primer_sheet.dart` | 3 | first |
| P2 | crew-builder-app | `test/signals_layer_screen_test.dart`, `test/signals_framework_test.dart`, `test/stats_primer_copy_test.dart` | 3 | after P1 |
| P3 | the lead | `docs/navigation_and_screens.md`, `docs/widget_catalog.md`, `docs/stats_screen.md`, `docs/signals.md`, `docs/constants_reference.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Readers of the changed strings (grepped): `kSignalQuietLine` text is asserted in `signals_framework_test.dart:84`, `signals_layer_screen_test.dart` (~877, ~1347, ~1371); the other tests find the quiet line by key only. The primer body is asserted only in `stats_primer_copy_test.dart:36-43`. If the full suite finds another reader, a closed fix brief adds its file.
Done criteria: touched tests green with real counts; `flutter analyze` not above 181; full `flutter test` green apart from the known flaky red (S-R3); invariant grep clean; `docs_indexing_contract_test.dart` and `ui_standards_contract_test.dart` green; `docs/stats_screen.md` still under 52,428 bytes; `plan-lint.py after` clean.
Mutations (lead): M1 `waiting.isNotEmpty ? kSignalQuietLineWithWaiting : kSignalQuietLine` to `kSignalQuietLine`; M2 to `kSignalQuietLineWithWaiting`; M3 the primer's `'change once you have two weigh-ins at least a week apart '` back to `'change once you have two weigh-ins a week apart.',` (drop the next piece).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/navigation_and_screens.md | MODIFIED | Calendar start-of-week, weight/distance units, | the `STATS` section with the `Weight on Stats` switch | D-18407 |
| docs/widget_catalog.md | ADDED | - | Note on the Stats screen's Weight block: | D-18407 |
| docs/stats_screen.md | MODIFIED | the `Weight on Stats` switch on. Verified by | the `Weight on Stats` switch on; the rule is in | D-18407 |
| docs/stats_screen.md | MODIFIED | lines sit under whatever the block shows` › `the quiet line keeps its copy and | lines sit under whatever the block shows` › `the quiet line shortens and | S-18401 |
| docs/signals.md | MODIFIED | state instead of cards: `kSignalQuietLine` is the sentence and the caller draws | `kSignalQuietLineWithWaiting` | S-18401 |
| docs/constants_reference.md | ADDED | - | `kSignalQuietLineWithWaiting` | S-18402 |

## Progress

- [x] P1 production text
- [x] P2 tests
- [x] P3 docs
- [x] P4 review
- [x] lead: verify, mutations, full suite

## Assumption Log

- 2026-11-03 lead: owner chose W2 "leave" and W3 "shorter line when waiting lines show" (asked with a recommended default each). W4 is an accuracy fix with no behaviour choice in it, applied without asking.
- 2026-11-03 lead: no architect run; the docs are written by the lead because each is a few exact sentences (D-18406).
- 2026-11-03 lead: results. Mutations M1-M4 (long line always, short line always, primer reverted, constant reworded) each failed a test. Review: APPROVE, one minor (the three `ensureVisible` calls no longer pin that the primer's `Got it` button is on screen without scrolling at 400x900; the sheet scrolls by design, so not fixed). The full suite found two readers the seed did not list (`test/stats_primer_home_test.dart` S-2701 and S-2718: the primer sentence is one wrapped line longer, so at 400x900 the sheet now fills the screen, the button sits at the edge and there is no empty modal barrier); fix round 1 gave S-2701 an `ensureVisible` and S-2718 a 400x1100 surface. Lesson recorded in friction: grep every test that taps a widget whose copy grows, not only the file named first.
