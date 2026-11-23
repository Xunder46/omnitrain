# Plan 309 evidence

Built and proved by the lead alone (Kotlin is outside the crew's write ceiling; the gateway hangs for builders on this PC). No independent reviewer ran.

## Observed output

- `flutter test test/wear_ongoing_activity_test.dart`: 18 passed (S-30901..S-30907). Plan 300's `S-30010` guard was updated for the new service text (`builder.build()`, the activity in the notification text).
- Wear and neighbouring suites (every `wear_`, `watch_link`, `watch_sensor` and `watch_platform` test, plus the docs and UI-standards contracts), compared by name against a clean checkout (stash): 553 pass / 14 fail before, 571 pass / 13 fail after; **no new failures** (the failures are the Windows baseline).
- `flutter analyze`: 174 issues, 0 errors. Both flavors build (`app-wear-debug.apk`, `app-phone-debug.apk`; the phone carries neither new library).
- Phase 0: `docs/wear_os_app.md` was 52.0 KB against the 52.4 KB band; "The sensors" moved whole to `docs/wear_os_app_sensors.md` (indexed). The docs contract is `+6 -7` before and after.

## Build environment

Gradle could not download `androidx.wear:wear-ongoing` here: Avast's web shield intercepts TLS and the build's Java does not trust its certificate. With the owner's approval, a temporary copy of Android Studio's Java trust file with Avast's own certificate added (`%LOCALAPPDATA%\Temp\omnitrain-trust\cacerts`) was pointed at only the build commands through `JAVA_TOOL_OPTIONS`; nothing system-wide changed. The copy was deleted after the last build. (`WINDOWS-ROOT` is not available in that Java, so the copy was the way.)

## Emulator (S-30907), `OmniWear_Small`, Wear OS 5, Health Services synthetic data

A throwaway Dart probe (deleted) called `WearPlatformWorkoutStore.begin`:
- Notification permission DENIED: the foreground service runs (`isForeground=true`, `types=health`, "has extras") but the app's notifications are `importance=NONE` (blocked); no icon on the watch face. So the chip needs the permission.
- Notification permission GRANTED: the notification is posted (`category=workout`, text `Strength training in progress`) with `android.wearable.ongoingactivities.EXTENSIONS` in its extras; a dumbbell icon appears on the watch face; tapping it brings the app to the front.
- The final flow, on a freshly cleared app: three system questions in order (vital signs, physical activity, "Allow OmniTrain to send you notifications?"), Allow on each, then the notification read `Running in progress` with the Ongoing Activity extras and the icon on the face.
- The face shows the icon only; the chip's stopwatch line belongs to the recents list, which was not opened.

## Mutation pass (32 mutants over `test/wear_ongoing_activity_test.dart`)

32 killed. One survivor on the first run (`memo all`: remembering an `unavailable` answer too) was a weak test, fixed by asking `unavailable` twice. Mutants: the compat builder, category, ongoing flag, icon, touch intent, status, apply, the template order, the stopwatch's start, the fallback and capitalisation and empty-words rules, the extra's key and both ends of its journey, the notification text, the service type and not-sticky start, the Kotlin permission (method, Android 13 gate, request code, shared prompt, answer word), the store's ask (removed, reordered, catch removed), the memo (read, write, scope), both dependencies, the manifest and the icon's colour.

## Not observed

- A real watch (owner check 24), Wear OS 6, the recents list's chip with its stopwatch, and the chip after a recovered workout (its stopwatch restarts at zero by design).
- The label function running (it is Kotlin with no harness): guarded as text, and its result seen in the notification text on the emulator (`Strength training`, `Running`).
