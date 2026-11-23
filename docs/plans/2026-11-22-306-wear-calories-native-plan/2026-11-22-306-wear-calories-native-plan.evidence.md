# Plan 306 evidence

Built and proved by the lead alone (Kotlin is outside the crew's write ceiling; the gateway hangs for builders on this PC). No independent reviewer ran.

## Observed output

- `flutter test test/wear_calories_native_test.dart`: 20 passed (S-30601..S-30606; S-30606 is the remembered refusal added after the emulator showed a second prompt).
- With the neighbours (plan 300/298/299 native guards, sensors shell, sensor source, platform workout store, plan 305 calories, wear config): all pass except `S-28132` in `wear_os_config_test.dart`, which is the Windows path-separator baseline (it fails on a clean checkout too).
- Two older source guards pinned the Kotlin text this plan moved (`S-30009` expected the exercise config inside `begin`, `S-30010` the one-line `WearWorkout(...)` registration); both were updated to the new structure and still guard the same rules (permission before the start, data types, service after the exercise, the registrar wiring).
- `flutter analyze`: 174 issues, 0 errors (baseline unchanged).
- `flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart` and `--flavor phone`: both built. The Kotlin compiled against Health Services 1.0.0 first time (`CALORIES_TOTAL`, `ExerciseUpdateCallback`, `getExerciseTypeCapabilities`).

## Emulator (S-30607), `OmniWear_Small`, Wear OS 5, headless, Health Services synthetic walking data

A throwaway Dart probe (deleted before the commit) called `WearPlatformWorkoutStore.begin('running')`, then the source's permission, heart rate and energy streams, on a freshly cleared app:
- The system prompts came in the planned order: the vital-signs one (heart rate), then "Allow OmniTrain to access your physical activity?" (from the store's energy question, before the exercise started).
- Allow: `perm: granted`, `hr: 115`, then the energy stream gave a cumulative number that grew: `n=12, last 3.3` and eight seconds later `n=24, last 6.9` (kilocalories, one reading about every half second).
- Don't allow: the prompt appeared a second time (the probe's own call after the store's), which is what the remembered refusal (D-30608) prevents in the real app. After the second refusal: `perm: denied`, `hr` still flowing, `kcal n=0`: the workout runs without calories.

## Mutation pass (23 mutants over `test/wear_calories_native_test.dart`)

23 killed. One survivor on the first run (`memo all`: remembering a non-granted answer, i.e. also `unavailable`) was a weak test, fixed by asking `unavailable` twice, then killed. Mutants: the store's ask (removed, moved before heart rate, catch removed), the memo (read, write, scope), and 17 Kotlin text mutants (method name, capability type, request code, shared prompt, answer word, channel name, main-thread post, sink cleared, permission gate, data types, callback set, clear on failure, emit, clear at end, manifest, registrar, total read).

## Not observed

- A real watch, Wear OS 6, and the phone receiving a Wear wrist's live total or end total end to end (the phone side is plans 134c1 and 135, unchanged; the Dart side is plan 305): owner check 22.
- The real app's rest screen showing the line from a live count (plan 305 proved the line with stored samples; the probe proved the stream): the two were not run together on the emulator because the emulator has no exercise to log a set against.
- A wrist-down run, and a stranded exercise recovered at launch.
