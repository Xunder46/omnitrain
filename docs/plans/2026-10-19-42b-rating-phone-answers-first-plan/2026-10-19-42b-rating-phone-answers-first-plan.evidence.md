# Evidence — plan 42b (the phone answers the effort question first)

Lead proof, 2026-10-19. Docs and evidence by `crew-docs-keeper` (P3), same day.

## Baselines

| Check | Before | After |
|---|---|---|
| `flutter analyze` | 181 issues | 181 issues |
| `flutter test` (full suite) | 5054 tests | 5054 tests, ~1 (skip), all passed |
| `swift test` (watchOS package) | — | 610 tests, 0 failures |
| watch app target build | — | `xcodebuild … OmniTrain Watch App … watchOS Simulator` BUILD SUCCEEDED |

## Test table

| Scenario | Test | File |
|---|---|---|
| S-4306 the answered session sends one snapshot carrying `rating-s-w1`, which validates and which the wrist stores under that id | group `S-4306 the phone's answer travels to the wrist as one snapshot` · `S-4306 the answered session sends one snapshot carrying rating-s-w1, which validates and which the wrist stores under that id` | `test/rating_first_answer_push_test.dart` |
| S-4307 a rated session already told to the wrist sends nothing more on the next trigger | group `S-4307 the first answer stands and nothing is echoed` · `S-4307 a rated session already told to the wrist sends nothing more on the next trigger` | `test/rating_first_answer_push_test.dart` |
| S-4307 a mirror that already holds the wrist's own rating sends nothing, even when the phone row is rated too | group `S-4307 the first answer stands and nothing is echoed` · `S-4307 a mirror that already holds the wrist's own rating sends nothing, even when the phone row is rated too` | `test/rating_first_answer_push_test.dart` |
| S-4308 the first send answers not-delivered, the next trigger sends again, and once delivered it stops | group `S-4308 a rating frame the radio did not carry is re-offered` · `S-4308 the first send answers not-delivered, the next trigger sends again, and once delivered it stops` | `test/rating_first_answer_push_test.dart` |
| S-4309 a session still active with a rating sends no rating frame | group `S-4309 the negative guards` · `S-4309 a session still active with a rating sends no rating frame` | `test/rating_first_answer_push_test.dart` |
| S-4309 an ended session with no rating sends no rating frame | group `S-4309 the negative guards` · `S-4309 an ended session with no rating sends no rating frame` | `test/rating_first_answer_push_test.dart` |
| S-4309 a mirror holding another session than the phone's current one sends no rating frame | group `S-4309 the negative guards` · `S-4309 a mirror holding another session than the phone's current one sends no rating frame` | `test/rating_first_answer_push_test.dart` |
| S-4310 the phone's rating in a snapshot closes the owed question (prompt drops, `confirm()` nil, `recordEffortRating` refuses, `objectWillChange` fires) | `testS4310ThePhonesRatingInASnapshotClosesTheOwedQuestion` | `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift` |
| S-4311 the phone's rating is not uploaded back as an effort rating | `testS4311ThePhonesRatingIsNotUploadedBackAsAnEffortRating` | `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift` |

## Mutations (lead, 2026-10-19)

11 mutations of the Dart side applied by hand; each made a named test red and
was restored byte for byte. The lead's list names them as: step not called;
delivered frame not remembered; echo guard off; active-session guard off; the
two redundant mirror-session guards off together; wrong entry id; undelivered
remembered; step placed after the early return; rating value ignored (nine
descriptions for the eleven mutations — the lead reported the count, the list
is the lead's).

Plus one Swift mutation: the engine's `objectWillChange.send()` removed —
S-4310 times out and fails.

Unproven: none, except the main-queue hop (`receive(on:)` in
`WatchEffortRatingState`), which no test can observe.

## Pending

- `crew-reviewer` review.
- Owner device checks (the plan's two owner items).
- `watch/sync_protocol/PROTOCOL.md` amendment (D-5) — pending, separate run.
