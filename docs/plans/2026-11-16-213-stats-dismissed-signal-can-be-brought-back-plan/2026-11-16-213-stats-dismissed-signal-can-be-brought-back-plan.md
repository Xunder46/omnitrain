# Plan 213 — A dismissed signal can be brought back

Series: Stats pre-launch review group E (item 9, the "dismiss has no undo" part, of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). The number 213 is the one freed when the owner dropped "reload Stats while open" (2026-11-16); this plan's scenario ids are S-21390..S-21396 because S-213xx (plan 212), S-214xx (plan 214) and S-212xx (plan 211) are taken. Phone only (`lib/core/models/signals.dart`, `lib/features/stats/stats_screen.dart`), one builder run for the code, one for the screen tests, then docs. Status: BUILT, reviewed (APPROVE WITH FIXES, fixed), uncommitted.

## Goal and acceptance

Tapping the dismiss control on a Signals card hides that signal for 14 days (`kSignalDismissalDays`) and nothing says so or offers a way back: a mis-tap hides a card for two weeks. After this change the dismiss shows a small bottom message, `Signal hidden for 14 days.`, with an `Undo` action. Undo brings the card back at once and takes the dismissal out of the store.

Acceptance: S-21390..S-21396 green, the ones marked "fails without" red at the base commit; the existing Signals tests green (`signals_layer_screen_test`, `signals_framework_test`, `signals_service_test`, `progression_rate_signal_screen_test` and the other `*_signal_screen_test` files that tap a dismiss control); `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Before: tap the dismiss control on a card, the card vanishes, and that is all.
- After: the card vanishes and a message at the bottom reads `Signal hidden for 14 days.` with `Undo` for 6 seconds. Tapping `Undo` puts the card back where it was. Dismissing a second card replaces the message (Undo then applies to the newest dismissal only). If the user leaves Stats before the message goes away and taps `Undo`, the dismissal is still taken back (it shows next time).
- To SEE it: open Stats on a history that shows a Signals card, tap the card's dismiss control.
- Unchanged: the 14-day rule, the dismissal store format, what a dismissed card does after 14 days, the quiet line.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | New pure `signalDismissalsWithout(Map<String, int> current, String id)` in `lib/core/models/signals.dart` beside `signalDismissalsWith` (`:149`): a NEW map of every entry but `id`; `current` is never mutated. | `signalDismissalsWith` precedent |
| D-2 | `StatsScreen._dismissSignal` (`stats_screen.dart:~262`) keeps its order (view first, then the chained write) and then clears any current message and shows `OmniMessage.show(context, 'Signal hidden for $kSignalDismissalDays days.', duration: const Duration(seconds: 6), action: SnackBarAction(label: 'Undo', onPressed: () => _undoDismissal(id)))`. The message goes through `OmniMessage` as the design system requires. | `docs/design_system.md` "Messages", `omni_message.dart:30` |
| D-3 | New `_undoDismissal(String id)`: the new store is `signalDismissalsWithout(_signalsDismissedAtMs, id)`; while mounted the view re-resolves the held candidates against it in the same frame (like the dismissal does); the write is appended to the same `_signalsWriteTail` chain (so it is ordered after the dismissal's write) whether or not the screen is still mounted. | `stats_screen.dart:262-290`, D-1010 |
| D-4 | Undo removes only `id`; a different card dismissed in between stays dismissed. | S-21393 |
| D-6 | Found by the P2 builder (the timeout test could not observe the message expiring) and confirmed in Flutter's source (`snack_bar.dart:303`): a `SnackBar` with an action ignores `duration` and persists until dismissed or replaced (`persist` defaults to `action != null`). `OmniMessage.show` / `showOn` / `_present` (`lib/widgets/feedback/omni_message.dart`) gain an optional `bool? persist` passed straight to the `SnackBar` (null keeps Flutter's default, so every other caller is unchanged; Stats is the only caller with an action). The dismissal message passes `persist: false`, so the 6 s duration is real. | `snack_bar.dart:303`, `omni_message.dart:34-47` |
| D-5 | The message copy is a default (owner said to proceed and explain defaults); 6 s is the chosen duration (the default 4 s is short for a recovery action). | scope |

## Scenarios

Screen scenarios on `StatsScreen` over Mock (a widget test body runs under FakeAsync), one completed session, injected stub signals that need no ratings (copy `_StubSignal` and the dismiss tap from `test/signals_layer_screen_test.dart`, S-1709 near line ~600-700). The store is read back with `parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey))` inside `tester.runAsync`.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21390 | Pure: `signalDismissalsWithout({'a': 1, 'b': 2}, 'a')`; `signalDismissalsWithout({'a': 1}, 'zz')`; and the input map afterwards. | `{'b': 2}`; `{'a': 1}`; the input is unchanged. | the function does not exist |
| S-21391 | One card; tap its dismiss control. | The card is gone; `Signal hidden for 14 days.` and an `Undo` action are on screen. | there is no message |
| S-21392 | As S-21391, then tap `Undo`. | The card is back; after the store write settles the store has no entry for that id. | no Undo exists |
| S-21393 | Two cards (a caution and a positive); dismiss the caution, then dismiss the positive; tap `Undo`. | The positive card is back, the caution card stays hidden; the store holds the caution's entry only. | Undo would restore both or neither |
| S-21394 | One card; dismiss; do NOT tap Undo; `pump` past 6 s. | The message really expires (gone from screen: no `clearSnackBars` emulation), the card stays hidden; the store holds the entry. | without `persist: false` the message never expires (D-6); the dismissal-stands half passes either way (mutation: Undo fires on timeout) |
| S-21396 | `OmniMessage.show` with an `action` and `persist: false` (and, as the control, without `persist`), in `test/omni_message_test.dart`'s style. | With `persist: false` the message is gone after its duration; without it (action present) it is still on screen after the same time. | `persist` is not accepted (compile error); the control pins that the default is unchanged |
| S-21395 | One card; dismiss; pop the Stats screen (it was pushed on a `Navigator`); tap `Undo` on the message that is still showing. | No exception; after the write settles the store has no entry for that id. | no Undo exists |

## Input-reality checklist

1. Writers and units: the store is written only by dismiss and now undo, as `{id: epochMs}` JSON; undo removes keys only.
2. Lifecycle: a message outlives the screen (the messenger belongs to the app); S-21395 pins that Undo still works after the screen is gone, because the State's fields survive disposal and the write needs no widget.
3. Settings changing while open: none read.
4. Time: the message is 6 s; the 14-day window is unchanged.
5. Cost: none.
6. Words: `Signal hidden for 14 days.` and `Undo`; the 14 comes from `kSignalDismissalDays`, never a literal.
7. Slot competition: the Stats screen has no other bottom message; the dismissal of a second card clears the first message so two never queue.

## Phases

1. **P1 builder-app, scope `lib/core/models/signals.dart`, `lib/features/stats/stats_screen.dart`, `test/stats_signal_undo_service_test.dart` (new):** the exact production code in the brief and S-21390 (pure). Report FIRST as a skeleton. No full suite.
2. **P2 builder-app, scope `test/stats_signal_undo_screen_test.dart` (new):** S-21391..S-21395 (Mock). Separate run because a screen-test file has design latitude.
3. **P3 lead:** docs, mutation pass, `crew-reviewer`, full suite.

## Readers (existing tests that may feel the new message)

`test/signals_layer_screen_test.dart` (S-1709, S-17507, S-18206 and the other dismissal tests), the `*_signal_screen_test.dart` files with a dismiss tap (`S-2216`, `S-2412`, `S-2511` and siblings). The message adds a `SnackBar` over the screen; a finder that is now ambiguous (for example `find.text('Dismiss signal')`) or a `pumpAndSettle` that now waits for the 6 s timer is reported, not edited, except where the plan's P2 says otherwise.

## Mutation list (lead)

(a) the dismiss shows no message; (b) Undo does not re-resolve the view; (c) Undo does not write the store; (d) Undo writes the old map back whole (restores every dismissal); (e) the first message is not cleared on a second dismissal; (f) Undo skipped when the screen is unmounted; (g) `persist: false` dropped at the Stats call site (S-21394 must go red); (h) `OmniMessage` ignores `persist` (S-21396 and S-21394 red).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen/signals_layer.md` | ADDED | - | Signal hidden for 14 days. | S-21391, S-21392 |
| `docs/signals.md` | ADDED | - | `signalDismissalsWithout` | S-21390 |
| `docs/signals.md` | ADDED | - | `test/stats_signal_undo_screen_test.dart` | S-21392, S-21395 |
| `docs/design_system.md` | ADDED | - | A message with an action stays until it is dismissed | S-21396, S-21394 |
| `docs/widget_catalog.md` | ADDED | - | the dismiss control offers Undo | S-21391 |

Stale-term sweep (`grep -rIniE "dismissal|dismiss" docs`, minus plans/history/releases): `signals_layer.md:80-95`, `signals.md:186-210` (the paragraphs the new sentences follow), `widget_catalog.md:35`, and `widget_catalog/layout_and_inputs.md:212,214` (the `OmniMessage` API rows, which gained `persist` after the review).

## Open items

1. The rest of item 9 (jargon such as "In this window" and "Resistance progression rate", and findability: Stats in the swipe-up sheet, Records & Trends behind an unlabeled icon) is not in this plan.
2. A silent reload (Start of Week flip) that overlaps an Undo can show the undone card hidden until the next reload (view only; the store is right; same exposure as the dismissal path, review minor 2).
3. The dismiss still hides for a fixed 14 days; there is no screen to see or restore dismissed signals later.
4. (owner) A device check: dismiss a card, tap Undo within 6 seconds.

## Predicted files

`signals.dart` (+10), `stats_screen.dart` (+40), `omni_message.dart` (+8), `test/omni_message_test.dart` (+2 cases), two new test files, four docs.

## Progress

- [x] Seeded (scout of `_dismissSignal`, `signalDismissalsWith`, `OmniMessage`, the docs)
- [x] P1 build (3.0 min)
- [x] P2 screen tests (16.7 min); the P2 builder could not observe the message expiring, which exposed D-6
- [x] Fix 1: `persist` on `OmniMessage` (2.9 min)
- [x] Docs, mutation pass (9 mutants, 9 killed)
- [x] Review: APPROVE WITH FIXES (minor: catalog API rows, fixed; minor: reload overlap, Open item 2)
- [x] Full suite (+7784, 0 failures)

## Assumption Log

- 2026-11-16: base commit `da111335` on `claude_develop`; other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-16: plan number 213 reused (no folder or file ever existed for it); scenario ids S-21390..S-21395 chosen after grep over `test`, `docs`, `lib`, `watch` found none.
- 2026-11-16: copy and the 6 s duration are the lead's defaults.

## Feedback

(none yet)
