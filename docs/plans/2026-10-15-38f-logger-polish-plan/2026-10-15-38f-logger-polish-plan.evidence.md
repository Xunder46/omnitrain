# Evidence — plan 38f (logger polish)

Lead-run checks, per phase. Counts are as the lead pasted them; this file
records them, it does not re-run anything (docs-only phase).

## Baseline

- Tree: base commit `80928669` plus the uncommitted 38a, 38b and 38c work.
- `flutter analyze`: 182 issues, 0 errors.
- `flutter test` (full suite): `+4846 ~1` — all passed.

## After the build (38f complete)

- `flutter analyze`: 182 issues, 0 errors — unchanged from the baseline.
- `flutter test` (full suite): `+4881 ~1` — all passed.

## Layout probe (lead, throwaway, 390 x 844)

Before (38c tree): header bottom 100, scroll body top 116, visible bar top 137
— the bar sat inside the scroll, 16 dp under the header and out of reach of the
pin. After: the bar block is pinned directly under the header (gap within the
8 dp budget; `S-4317: at 390 x 844 the bar hugs the header and the sets control
stays reachable` in `test/logger_shell_screen_test.dart` asserts the gap is
0..8 dp and that the sets control stays reachable with the rest strip up).

## iOS simulator (iPhone 17, real font), live session

- Round screen: the set bar and captions render on a round effort like on a
  reps one.
- Reps screen with 2, 4 and 6 sets: captions under their own segments at 2 and
  4 sets; at 6 sets no captions and no reserved space.
- Negative weight: a set logged at −5.0 kg reads `10×-5`; a zero-weight set
  reads `10×0` — both always `reps×weight`.
- Delete a logged set, then add: the new set is unlogged (button `Log Set`,
  grey segment), pre-filled from the previous set (10 × −5.0).

## Still open for the owner

- `OmniSurface` is theme-tinted and opaque, not the translucent grey the owner
  sketched (plan D-5 finding; a token decision — `L-1` ships
  `OmniSurface(showShadow: false)` meanwhile).
- A logged-and-focused set differs from a logged one only by its caption
  colour (the fill is the same full accent).
- The rest history of a deleted set is dropped with it (owner point 7
  sanctions this; visible in the rest history only).
- The watch bridge now reads rests as positions
  (`EntryRows.loggedSetNumbersOf`); the wire format is unchanged.
- Interval and hold screens were not looked at on the device; they share the
  same pieces and are covered by tests.
- The session editor and the pounds preference are covered by tests only.

## Closing numbers (2026-10-16, after the review round)

- `flutter analyze`: 182 issues, 0 errors (unchanged from the base).
- Full suite: `+4893 ~1`, all passed (base `+4846 ~1`).
- Mutations: the prover's 36 rows plus 13 gap rows plus 1 importer row: 48 turned a named test red; one has no test (clearing the ping bookkeeping after a delete).
- Review: APPROVE WITH FIXES; the importer's planned-set search was fixed in a closing round (test S-4334); the importer's rest-number writes and its wrist-delete path are a follow-up PR.
