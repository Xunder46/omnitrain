# Evidence — plan 51e (the wrist taps to confirm a log, and VoiceOver names the list button)

## Scenario-to-test table

| Scenario | Test (`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggedHapticTests.swift`) |
|---|---|
| S-7801 a set plays one tap per logged set | `testS7801ASetPlaysOneTapPerLoggedSet` |
| S-7802 a timed effort starts silently, then logs | `testS7802ATimedEffortStartsSilentlyAndLogsOnTheSecondTap` |
| S-7803 the other entry (`log()`) plays the same tap | `testS7803LogPlaysTheTap` |
| S-7804 a refused log plays nothing | `testS7804ARefusedLogPlaysNothing` |
| S-7805 the surfaces play the taps and name the list button | `testS7805TheSurfacesPlayTheTapsAndNameTheListButton` |

## Measured results

- Full `swift test`: 727 tests, 0 failures.
- The lead's mutation pass: 9 mutants (no tap in `primaryAction`; tap unguarded
  in `primaryAction`; tap on Start; no tap in `log()`; tap unguarded in
  `log()`; `WristHaptics` success mapped to another type; next mapped to the
  ping's click; Next without its tap; food tap unguarded). All caught; every
  file restored byte-for-byte.
- The watch app target builds with `xcodebuild`.
- NOT verified: how the taps feel on a real wrist, and the VoiceOver reading of
  the list button — owner checks.
