# Plan 295 evidence

Base commit `1d2f9608`. Windows PC: the full suite is red in the baseline and was not run; evidence is the touched and neighbouring files, `flutter analyze`, a Kotlin compile and the emulator.

## Builds

- P1 (the read): `crew-builder-watch`, run `20261122-133930`, 1.4 min, no denial, no stop. Two files; the Kotlin text is exactly as briefed (the old `onDataChanged` per-item body now lives in `takeQueuedItem`, called from `onDataChanged` and from the new `drainWaiting`, which `onAttachedToEngine` calls after `attachListeners()`).
- Tests, docs, mutation pass and the emulator attempt: lead.

## Checks (observed)

- `flutter test test/watch_link_start_up_read_test.dart test/wear_queue_newest_test.dart test/watch_link_package_test.dart`: `+41: All tests passed!` (the new file has 4).
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).
- `flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart`: built (Kotlin compiles).
- Wear emulator `OmniWear_Small` (Wear OS 5, round 192 dp): the build with the read installed and launched, and the app stayed up for 20 s with the read running at launch (no crash, no `AndroidRuntime` error). This shows the read does not break start-up. It does NOT show that a waiting item is taken.

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

13 mutants over the Kotlin plugin against the four source guards: no start-up read; read after the peer is resolved; read before the listeners; a failed listing not guarded; the buffer not released; the release outside `finally`; the read takes nothing; the change event deletes by itself; the change event no longer shares the rule; own items taken; path prefix ignored; delete before emit; frame decode skipped. **13 of 13 killed.** These are source-text guards: they prove the text and its order, not the behaviour on a data layer.

## Not observed (S-29505)

The probe was a temporary hook in the plugin (reverted by restoring the saved copy and `cmp`; `grep TEMP-295-PROBE` finds 0) that put one peer-role data item at the first launch when a marker file existed, followed by a force-stop and a relaunch to see the item taken. It could not run: every time the app put a data item the emulator process itself died (host exit code 139, a segfault) and adb lost the device; installing, launching and idling without the put never crashed it (`install -r`, launch and 20 s survived; an earlier idle crash, 5+ minutes into the first session while a Gradle build and a mutation pass loaded the machine, may have another cause). The windowed run also logged `UpdateLayeredWindowIndirect failed`. Tried: `-gpu swiftshader_indirect` windowed and headless, `-gpu guest -memory 2048` headless; same result. So the behaviour (a waiting item is read and deleted at launch) is unobserved here; owner check 15 on a paired watch and phone covers it.

## Not verified here

- The data layer's behaviour with a real peer: items arriving while the app is closed and listed by `getDataItems` at the next start (the platform contract the fix relies on).
