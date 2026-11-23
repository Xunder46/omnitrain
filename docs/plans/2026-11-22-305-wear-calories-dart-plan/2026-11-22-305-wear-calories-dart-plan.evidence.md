# Plan 305 evidence

Built and proved by the lead alone (the gateway hangs for builders on this PC). No independent reviewer ran.

## Observed output

- `flutter test test/wear_calories_test.dart`: 42 passed (S-30501..S-30509).
- Neighbouring tests (calories, diagnostics send, sensors shell, sensor recording, platform workout store, transport, diagnostics transport): `+155 All tests passed`.
- `flutter analyze`: 174 issues, 0 errors (baseline unchanged). Two transient analyzer errors while building were mine and fixed (the two interfaces do not promote together: the source is tested as an `Object`).
- Watch/wear test set on this Windows PC (126 files, plus the two contract tests and the merged-diagnostics test): the failures are the Windows baseline (path separators, CRLF, Hive). Compared by name with the run before this plan, the only differences are the 12 contract-test names that run was not given; the same 12 fail on a clean checkout (docs indexing contract: `+6 -7` with and without this change, checked with a stash).
- Windows note for new tests: a schema loader that cuts paths with `substring` yields backslash keys here; the new test normalises them, so its validator is real.

## Mutation pass (39 mutants over `test/wear_calories_test.dart`)

39 killed after strengthening, 0 survivors. The first pass killed 30; the survivors were weak tests, not production defects, and were fixed in the tests:
- M08 negative filter: needed a chain where a negative count sits between two real ones (`10, -5, 30` is 30, not 40).
- M09 kind filter: a heart-rate sample inside an energy chain.
- M11 status check: the first test announced after finish while a stored count suppressed the frame anyway; now no count is stored, so only the status keeps it from going out.
- M19 raw total: the mutant I first wrote was a no-op; rewritten to feed the announce an empty sample list.
- M26 no cancel: the clock was not advanced between the two readings, so the second sample had the first one's id and was an idempotent no-op; the test now advances it.
- M30 sample instant: the recorder and the engine shared one clock; they now differ.
- M39 rest fit: needs a screen narrow enough to force scaling (110 dp wide).
- M01 and M35: the mutant text did not match the formatted source; fixed and re-run (killed).

## Not observed

- Any real calorie count: there is no native half until plan 306, so on a watch the source reads `unavailable` and nothing changes. Owner check 22 comes with plan 306.
- The phone receiving a Wear wrist's `energy_live` or `session_end` total (the phone side is plans 134c1 and 135 and is unchanged).
