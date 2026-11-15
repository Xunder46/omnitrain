# Plan 178: the watch app declares the Audio background mode for its haptics

> Status: Implemented (governor, 2026-11-15). Owner decision: follow Apple's guide.

## Why
Fable's pre-launch review (item 2) and Apple's HealthKit guide "Running workout sessions" (developer.apple.com/documentation/healthkit/running-workout-sessions): workout sessions need the Workout processing background mode; an app that plays audio or gives haptic feedback during the session "must also add the Audio background mode". The watch app declared only `workout-processing` (`WKBackgroundModes`). Its rest pings and timer taps are haptics. The owner reports that taps already arrive with the wrist down and the screen black ("very subtle"); the owner decided to follow the guide anyway.

## Decisions
- **D-17801** The watch app's Info.plist fragment (`ios/OmniTrainWatchApp-Info.plist`) adds `UIBackgroundModes` = `audio` beside `WKBackgroundModes` = `workout-processing`. No audio is played by the app; the mode is declared for the haptics, as Apple's guide says. If App Review asks, the answer is that guide.
- **D-17802** Background location is NOT changed: the location manager keeps its current configuration (`CoreLocationRawSource`: fitness activity type, no background-location flag); the owner saw sensible distance with the wrist down. Revisit only if a device walk shows distance gaps.

## Scenarios
- **S-17801** `WatchBackgroundModesSourceTests`: the plist declares `workout-processing` in `WKBackgroundModes` and `audio` in `UIBackgroundModes`. Red before the plist change (audio test failed), green after.

## Verification
`swift test --filter WatchBackgroundModesSourceTests`; the governor compile-checks the watch target (`xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -sdk watchsimulator`, Debug and Release) because the plist is part of the target. Device check: a wrist-down walk with a rest timer: taps still arrive; nothing else changes.

## Not done / open
- App Review wording for the Audio mode is untested.
- `docs/watch-app-setup-and-qa.md` (54.6 KB, past the split band) names the background mode at ~line 154: update that sentence when plan 177's builder has finished editing the file.
