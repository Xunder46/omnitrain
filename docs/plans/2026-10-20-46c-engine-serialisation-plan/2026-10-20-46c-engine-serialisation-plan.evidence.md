# Evidence — plan 46c (engine serialisation)

## Swift package full run

- Builder-reported: `swift test --package-path watch/watchos` full run — **657 tests, 0 failures**. The governor re-runs it; this line is builder-reported, not re-verified by the docs keeper.

## Governor mutation pass

- Governor-reported: **8 of 8 mutants red** — each of the five `exclusive` wraps removed (S-6501..S-6505), mutex LIFO, mutex without exclusion, the main-actor hop removed (S-6507). Governor-reported, not re-verified by the docs keeper.

## Docs

- `docs/state_management/watch_surface_wrist.md`: new subsection "The engine's session-row writers run one at a time" citing `WatchEngineSerialisationTests.swift` (S-6501..S-6505), `WatchAsyncMutexTests.swift` (S-6506), `WatchHostHopSourceTests.swift` (S-6507). All named symbols and tests grepped in the sources this run.
- `flutter test test/docs_indexing_contract_test.dart`: run once, count pasted in the crew report (`.work/crew/2026-10-20-46c/report-docs.md`).
