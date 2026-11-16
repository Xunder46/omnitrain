# Plan 212 — One failing signal or food read no longer blanks the Stats screen

Series: Stats pre-launch review group D (item 8, first half, of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). The second half of item 8 (Stats does not refresh while open) is plan 213, planned separately. Phone only (`lib/core`, `lib/features/stats`), two builder runs, then docs. Status: BUILT, reviewed (APPROVE WITH FIXES, fixed), uncommitted.

## Goal and acceptance

`StatsScreen._loadData` (`lib/features/stats/stats_screen.dart:119`) is one `try`: any throw anywhere sets `_loadFailed` and the whole screen becomes "Could not load your stats." Three of its reads are optional extras, not the screen: each registered signal (`SignalsService.evaluateCandidates`, `signals_service.dart:54-64`, calls `signal.evaluate` with no guard, while `waitingLines` right below it already says "Absent rather than broken"), the Fuel summary (`computeFuelSummary`, `stats_progress_service.dart:2186`) and the Weight trend (`WeightTrendService.compute` already catches and returns null). After this change a signal that throws is left out of the list while the others still speak, and a Fuel read that throws leaves the Fuel row out. The totals, the Instruments list and the Mix layer stay the screen's core: a failure there still shows "Could not load your stats." with Try again.

Acceptance: S-21301..S-21304 green, the ones marked "fails without" red at the base commit; the existing Stats tests green (`stats_load_failure_test`, `signals_service_test`, `signals_waiting_test`, `signals_layer_screen_test`, `stats_load_single_read_test`, `fuel_row_screen_test`); `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Before: one signal with unreadable data (or a food read that fails) turns the whole Stats screen into "Could not load your stats." even though the Mix strip and Instruments could have loaded.
- After: the screen loads; the broken signal's card, or the Fuel row, is simply missing. Nothing says it is missing (the cards and the Fuel row are conditional already; a quiet card is normal).
- To SEE it: not reachable on a healthy history; it shows only when data is malformed. Tests pin it.
- Unchanged: a failure in the totals, Instruments or Mix still shows the failure line and Try again; the dismissal store, waiting lines and the Weight block.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `SignalsService.evaluateCandidates` wraps each `signal.evaluate(context)` in `try`/`catch (_)`; a throwing signal is skipped (`continue`), the order and dismissal rules of the others are untouched. | `signals_service.dart:56`, `waitingLines` precedent (`:87-94`) |
| D-2 | `StatsScreen._loadData` reads `computeFuelSummary()` inside its own `try`/`catch`; on a throw the summary is null (no Fuel row). The totals, Instruments and Mix reads stay outside any guard. | `stats_screen.dart:145`, `:390` (`if (_fuelSummary != null)`) |
| D-3 | A swallowed failure is not recorded anywhere (the Stats screen holds no diagnostics log); hidden failures are the accepted cost, named in Open items. | scope |
| D-4 | No change to retry, the failure view, the silent-reload path or the load generation guard. | `stats_screen.dart:119-243` |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21301 | `SignalsService` over a registry of three fake signals: A returns a card, B throws, C returns a card; one completed session so the context is valid (copy the fake and setup of `test/signals_waiting_test.dart`, which already has a `throwing` fake). `evaluateCandidates`. | Returns A's and C's cards in registry order; does not throw. | the throw from B propagates |
| S-21302 | The same service, every signal throws. | Returns an empty list; does not throw. | the first throw propagates |
| S-21303 | `StatsScreen` (Mock) over one completed session with `signals:` = [a throwing fake, a fake that returns a visible card] (copy how `test/signals_layer_screen_test.dart` injects fakes and finds a card). | `Could not load your stats.` is absent; the Instruments caption is present; the healthy fake's card is visible. | the whole screen reads "Could not load your stats." |
| S-21304 | `StatsScreen` (Mock subclass whose nutrition read used by `computeFuelSummary` throws) over one completed session plus food logged today (copy the seeding of `test/fuel_row_screen_test.dart`). | `Could not load your stats.` is absent; the Instruments caption is present; no Fuel row. | the whole screen reads "Could not load your stats." |

## Input-reality checklist

1. Writers and units: signals read stored history the logging screen, importer and watch wrote; a malformed row (a stored value in a shape a signal did not expect) is the realistic cause of a throw.
2. Lifecycle: a signal skipped in one load is evaluated again in the next (no memory).
3. Settings: none.
4. Time: none.
5. Cost: one try/catch per signal; no extra read.
6. Words: no new on-screen wording; docs in the Docs delta.
7. Slot competition: `evaluateCandidates` is called by `stats_screen.dart:187` only (plus tests); the dismissal and `waitingLines` paths are untouched.

## Phases

1. **P1 builder-app, scope `lib/core/services/signals_service.dart`, `lib/features/stats/stats_screen.dart`, `test/stats_one_failure_service_test.dart` (new):** the exact production code in the brief and S-21301, S-21302 (Mock and Hive). Report FIRST as a skeleton. No full suite.
2. **P2 builder-app, scope `test/stats_one_failure_screen_test.dart` (new), `test/signals_layer_screen_test.dart` (one test rewritten):** S-21303, S-21304 (Mock only: a widget test body runs under FakeAsync), and the rewrite of `S-18207` (see Readers). Separate run because a screen-test file has design latitude.
3. **P3 lead:** docs, mutation pass, `crew-reviewer`, full suite.

## Readers (existing tests that pin the old rule)

`test/signals_service_test.dart`, `test/signals_waiting_test.dart`, `test/signals_layer_screen_test.dart`, `test/stats_load_single_read_test.dart`, `test/stats_load_failure_test.dart`, `test/fuel_row_screen_test.dart`. A red anywhere else is reported, not edited.

Known reader that pins the old rule (found by the lead before P1): `test/signals_layer_screen_test.dart` `S-18207 a reload that succeeds replaces the failure view` (line ~1111) makes the first load fail with `_FlakySignal` (a signal that throws once). After this plan that load no longer fails, so the test goes red by design. P2 rewrites it to fail the first load through a core read instead (a Mock subclass whose `getAllSessions` throws on the first call only, like `_GatedDismissalRepository` in the same file) and a `_StubSignal` whose card text proves the reload ran under `sunday`; the assertions (failure line first, then gone, `recovered on sunday` shown, a second load happened) keep their meaning. `_FlakySignal` is deleted if nothing else uses it.

## Mutation list (lead)

(a) the per-signal guard removed; (b) the guard rethrows on the first signal only; (c) the Fuel guard removed; (d) the Fuel guard wraps the Instruments read too (a core failure would be hidden: `stats_load_failure_test` must stay red-on-purpose green, i.e. the core failure test still shows the failure line).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen.md` | MODIFIED | When that one load read throws, the body is `LoadFailureView` | When a core read throws (the totals, the Instruments list or the Mix layer), the body is `LoadFailureView` | S-21303, S-21304 |
| `docs/stats_screen.md` | ADDED | - | Each signal and the Fuel row are optional | S-21303, S-21304 |
| `docs/signals.md` | ADDED | - | A signal that throws is left out | S-21301, S-21302 |
| `docs/signals.md` | ADDED | - | `test/stats_one_failure_service_test.dart` | S-21301 |

Stale-term sweep (`grep -rIniE "one load read|Could not load your stats|failing signal|evaluates each" docs`, minus plans/history/releases): `stats_screen.md:603-604` (the row above), `signals.md:264` (the paragraph the ADDED row follows), `widget_catalog/layout_and_inputs.md:278` (an example string, still true) and `:269-270` (the `LoadFailureView` entry, "when their one load read throws": reworded after the review).

## Open items

1. A swallowed signal or Fuel failure leaves no trace (D-3). A later plan can wire the Diagnostics log into Stats.
2. `SignalsService.loadDismissals` still reads the preference store unguarded, so a store that cannot be read still fails the whole load (review minor; pre-existing).
3. Totals, Instruments and Mix remain all-or-nothing: if only one of them cannot be read, the screen still fails whole.
4. Plan 213: Stats does not reload while open when new data (a watch session, a food log, a weigh-in) arrives.

## Predicted files

`signals_service.dart` (+8), `stats_screen.dart` (+8), two new test files, `docs/stats_screen.md`, `docs/signals.md`.

## Progress

- [x] Seeded (scout of `_loadData`, `evaluateCandidates`, `waitingLines`, `WeightTrendService`)
- [x] P1 build (3.2 min)
- [x] P2 screen tests and the S-18207 rewrite (8.4 min)
- [x] Docs, mutation pass (4 mutants, 4 killed)
- [x] Review: APPROVE WITH FIXES (major: a stale catalog sentence, fixed; minor: `loadDismissals`, now Open item 2)
- [x] Full suite (+7764, 0 failures)

## Assumption Log

- 2026-11-16: base commit `b70dc61b` on `claude_develop`; the tree holds other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart`, outside this plan's scopes.
- 2026-11-16: scenario ids S-213xx; grep over `test`, `docs`, `lib`, `watch` found none.
- 2026-11-16: the owner's item-8 wording was "one failing signal blanks the whole screen"; the Fuel read is added because it is the other optional extra that can throw without a guard.

## Feedback

(none yet)
