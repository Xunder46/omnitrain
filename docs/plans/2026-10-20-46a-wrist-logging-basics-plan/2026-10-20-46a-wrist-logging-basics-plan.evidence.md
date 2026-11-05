# Evidence — 46a, the Crown turns the armed value; the logging screen fits a 40 mm watch; each exercise keeps its own numbers (2026-10-20)

Record of the build and proof of this plan, as reported to the docs keeper.
Every test file named below was read this run.

## Runs

- Swift package full run (`swift test --package-path watch/watchos`):
  **644 tests, 0 failures** after phase 2 — builder-reported; the governor
  re-runs it before the unit closes.
- Dart watch files green: **+83**, governor-observed.
- Layout: seen on the Apple Watch SE 3 (40 mm) simulator (screenshots) — Log
  fully visible, the − / + buttons small, the unit beside the value, the
  exercise name a one-line header below the menu button. No unit test sees a
  layout.

## Mutation pass (governor, on the model)

9 of 11 mutants red. The two green ones — arming, or counting, a
sensor-measured row as open — are unreachable today: no effort kind prescribes
a distance row, so `fields` never holds a measured row.

## Owner checks

The plan's Owner checks section already lists the Crown on a physical watch;
not verified this run.

## Docs contract (docs keeper, this run)

`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`:
**+40 -1**. The one red test is `no documentation file is within the warning
band of the ceiling` — `docs/state_management/watch_surface.md: 53724 bytes
(82% of ceiling)`: the file already sat at 79.65% before this run's insertion,
and the band is 80% of the 64 KiB ceiling. The rulebook's fix, a split into
`docs/state_management/watch_surface_wrist.md`, needs a new file the docs
keeper's write scope denies; it is handed to the governor in
`.work/crew/2026-10-20-46a/report-docs.md`. Everything else in both contract
files is green.

## Governor re-runs after the review

- Swift package full run: Executed 645 tests, 0 failures. Dart `test/watch_dialled_per_exercise_test.dart`, `watch_logging_timers_test.dart`, `watch_logging_surfaces_test.dart`, `docs_indexing_contract_test.dart`, `ui_standards_contract_test.dart`: +102, all passed. Full `flutter test` before fix-2: +5322 ~2, all passed.
- Mutations M12 and M13 (clear by the current key instead of the logged key): red in Swift and Dart.
- Simulator (Apple Watch SE 3, 40 mm, seeded 3-exercise session): Log fully visible, exercise name on one line clear of the menu button, Reps row outlined on entry. A Crown turn could not be driven (screen locked): owner check.
