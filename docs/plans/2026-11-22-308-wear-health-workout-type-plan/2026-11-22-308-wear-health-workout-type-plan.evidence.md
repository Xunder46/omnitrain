# Plan 308 evidence

Built and proved by the lead alone (the gateway hangs for builders on this PC). No independent reviewer ran.

## Observed output

- `flutter test test/wear_health_type_test.dart`: 23 passed (S-30801..S-30807). Together with plan 307's file: 55 passed.
- Neighbouring health, watch-session, workout-state, settings, wear and watch-activity tests (67 files, plus the UI-standards contract): compared by name against a clean checkout (stash): 961 pass / 382 fail before, 984 pass / 381 fail after; **no new failures** (the failures are the Windows baseline; the 23 extra passes are the new tests; one baseline test that was flaky before did not fail the second time).
- `flutter analyze`: 174 issues, 0 errors (baseline unchanged; one transient `invalid_null_aware_operator` in my own test was fixed).
- The wrist's rule is unchanged: `forSession` now delegates to the new pure function and S-30801 proves the two agree for every modality (including an unknown one and none) against ten slot lists, among them the named-kind majority, the tie, the plank and an unknown kind.

## Findings on the way

- My first draft sorted a segment's efforts by their raw `orderIndex`. The repository's own order is the top-level position then the block position (a block can contradict the raw index), so that sort would have mis-ordered a routine with blocks and changed which exercise is "first" for a Free session. Removed; the service now uses the repository's order, and a test stores efforts whose raw index contradicts their position and expects the repository's order.
- The segment sort was redundant too (both repositories sort a session's segments); removed.
- Two older assumptions held: the Apple rule needs the exercises as the phone names them to the wrist, so the same `WatchReferenceSync.healthActivityOf` that builds the catalog is the input here; there is no wire change.

## Mutation pass (20 mutants over `test/wear_health_type_test.dart`)

19 killed, 1 equivalent:
- Equivalent: re-introducing a raw-`orderIndex` sort of the efforts survives because the in-memory repository normalises `orderIndex` to the top-level position on create, so the two orders cannot be made to disagree through the repository API. The correct order is a documented repository contract (`_compareEfforts`), which the test pins as far as the mock allows.
- Killed: the delegation of `forSession`, the named-kinds-first order, the modality rule, a Free session using all exercises instead of the first, a routine using only the first, no wrist (not typed), no inbox fallback, no memory of the wrist flag, the exercise's Health kind dropped, the name missing on the first write and on the replacement, the flag at the call site (never, and without the wrist's own end), the gateway ignoring the name, ignoring the iOS rule, the fallback, three table entries (running, cross training, a missing name).
- The first run left the two call-site flag mutants alive (the service-level tests passed the flag by hand); a real-session test (the wrist's own end, the phone's End of a wrist-run session, a phone-only session) killed them.

## Not observed

- A real Wear watch workout in Health Connect showing the type (owner check 23, with plan 307's other checks).
- An exercise added to a routine session after it started: the phone counts it, the Apple watch had fixed the type at the start (a documented difference, not a regression: before this plan every such session was Other).
- A custom exercise the user left untyped (no discipline): it carries no Health kind and falls through to its capabilities, as on the wrist.
