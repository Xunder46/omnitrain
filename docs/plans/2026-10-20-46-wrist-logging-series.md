# Series 46: the wrist logging screen, Crown and swipe

> Status: 46a BUILT 2026-10-20; 46c seeded (`2026-10-20-46c-engine-serialisation-plan/`); 46b to be seeded after 46c. Seeded from the watch UX audit.
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md

## Owner decisions (2026-10-20, in chat)

O-1 On the owner's watch the Crown steps no value on the logging screen (it only scrolls lists): that is a bug, to be fixed.
O-2 The Crown turns the highlighted value row: one row (the first) is outlined on entry, a tap on a row (or its − / +) moves the outline, the Crown steps the outlined value with a tick. The Crown never changes exercise.
O-3 On a 40 mm watch the − / + buttons shrink so the Log button is fully visible and the exercise name does not run under the menu button.
O-4 Each exercise keeps its own half-dialled numbers; Log clears only that exercise's.
O-5 Swiping to another exercise needs no change on the phone screen.
O-6 Rest keeps replacing the whole screen; the user ends the rest by hand before the next set or exercise; no swiping in rest.
O-7 Swipe previews and commits on settle; it is locked, with visible feedback, while an effort clock runs.

## Split (scope budget: one concern per PR)

- 46a wrist logging basics: O-1..O-4 (model + view + Dart mirror parity). Plan: `2026-10-20-46a-wrist-logging-basics-plan/`.
- 46b swipe pager: O-5..O-7. Needs 46a (per-exercise numbers, Crown on the surface). Seed after 46a lands.
- 46c inbound frames hop to the main actor; engine serialises select vs phone snapshot (audit section 3, `WatchSessionEngine` read-modify-write). Independent; needed before 46b ships (a pager bound to the engine index races the phone's snapshot).
- Not in series: sync reliability (queued delivery, phone-side watch status, plugin replacement): its own series.
