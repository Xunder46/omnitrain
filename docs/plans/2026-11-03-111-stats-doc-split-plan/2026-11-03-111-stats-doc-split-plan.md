# 111 — Split the Signals layer out of the Stats Screen doc

Status: DONE by the lead 2026-11-03 (docs only; no code, no test change). Base commit `ccbaf65a`.
Unrelated dirty files, never touched: `lib/core/services/stats_progress_service.dart` and `test/stats_dst_day_arithmetic_test.dart` (another session's DST work).
Owner: "Yes, split it" (offered after plan 110 left `docs/stats_screen.md` 60 bytes under the 80% size band).

## Goal and acceptance

`docs/stats_screen.md` goes from 52,368 bytes to about 40.5 KB, so the next Stats doc change has room, and nothing a reader or a test relies on moves:

1. The `### Signals layer` section's body (12.3 KB: gate, cards, quiet line, waiting lines, dismissal, load behaviour) moves word for word to the new part page `docs/stats_screen/signals_layer.md`, with only its relative links re-pointed (`signals.md` to `../signals.md`, `signals_registered.md` to `../signals_registered.md`).
2. `docs/stats_screen.md` keeps the `### Signals layer` heading (so every `#signals-layer` anchor still resolves) and a short pointer paragraph to the part page.
3. The part page is indexed in `docs/README.md` and linked from the Stats page's pointer and its Related Documentation list (the docs contract test fails on an orphan).

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-18501 | Move the Signals layer, the largest self-contained section, rather than several small ones: it already has its framework page (`signals.md`) and definitions page (`signals_registered.md`), and nothing outside the Stats page anchors into its body | docs |
| D-18502 | The part page lives in a folder named after its parent (`docs/stats_screen/`), like `docs/state_management/` and `docs/widget_catalog/`, and carries the same `Part of ... Return to ...` line those pages carry | docs |
| D-18503 | Docs only: the "tests" for this unit are the existing docs contract tests (links resolve, every page reachable, no file over the ceiling or inside its warning band) | S-18501 |

## Scenarios

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-18501 | `flutter test test/docs_indexing_contract_test.dart` | all pass, including `no documentation file is within the warning band of the ceiling`, `every relative link resolves to a file that exists` and `every doc page is reachable from another doc page` | without the split the next Stats doc edit pushes `stats_screen.md` over the band (52,428 bytes); with the part page unlinked the reachability test fails |

## Phases

| Phase | Agent | Write scope | Items |
|---|---|---|---|
| P1 | the lead | `docs/stats_screen.md`, `docs/stats_screen/signals_layer.md`, `docs/README.md` | move, pointer, index row, Related Documentation line |

Done criteria: `docs_indexing_contract_test.dart` green; `docs/stats_screen.md` well under 52,428 bytes; `plan-lint.py after` clean; the full suite unchanged.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/stats_screen.md | MODIFIED | `signalsGateMet(mix)`, the Mix layer's `ratedWeeks` — | [Stats Screen — Signals Layer](stats_screen/signals_layer.md); the framework is in | S-18501 |
| docs/stats_screen/signals_layer.md | ADDED | - | # Stats Screen — Signals Layer | S-18501 |
| docs/README.md | ADDED | - | [Stats Screen — Signals Layer](stats_screen/signals_layer.md) | S-18501 |

## Progress

- [x] Move the section, re-point its links
- [x] Pointer paragraph, README row, Related Documentation line
- [x] Docs contract test green; size measured

## Assumption Log

- 2026-11-03 lead: no crew run; a word-for-word move plus a pointer is mechanical (the crew rules have the lead split pages). The moved text was compared byte for byte with the original section (12,316 bytes of body).
