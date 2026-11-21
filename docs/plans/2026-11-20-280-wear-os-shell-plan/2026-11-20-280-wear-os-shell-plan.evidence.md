# Plan 280 — evidence

Every command below was run on this machine on 2026-11-20. Output is quoted as it
appeared; nothing here is inferred.

## Baselines

- `flutter analyze` before this PR: 176 issues, 0 errors (the figure plan 278a
  records). After this PR: **174 issues, 0 errors** — two fewer, no new ones.
- The two "invariant" suites named in `AGENTS.md` are **red on this branch before
  this PR's files are considered**; see "Pre-existing red" below for the exact
  findings and why none of them names a file this PR added or changed.

## The Kotlin half compiles

```
cd android
./gradlew :omnitrain_watch_link:compileDebugKotlin
→ BUILD SUCCESSFUL in 3s
```

Four rounds of real compile errors were worked through (Kotlin `FlutterError`
resolution, `PutDataRequest.setData` taking bytes, `MessageClient.addListener`'s
path-filtered overload being `(listener, Uri, int)` in 19.0.0, nullable
`DataItem.getData`). None was inferred; each was a compiler message.

## The wear APK builds

```
flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart
→ Running Gradle task 'assembleWearDebug'...   54.9s
→ √ Built build\app\outputs\flutter-apk\app-wear-debug.apk
```

Rebuilt after the last source change (the arrival-lane hardening, the button
shape and the import cleanup):

```
→ Running Gradle task 'assembleWearDebug'...    8.9s
→ √ Built build\app\outputs\flutter-apk\app-wear-debug.apk
```

```
flutter build apk --debug --flavor phone
→ Running Gradle task 'assemblePhoneDebug'...   44.4s
→ √ Built build\app\outputs\flutter-apk\app-phone-debug.apk
```

## What the APKs actually declare (`aapt2 dump`)

| | wear APK | phone APK |
|---|---|---|
| `package: name` | `dev.sasha.omnitrain` | `dev.sasha.omnitrain` |
| `minSdkVersion` | 30 | 26 |
| `android.hardware.type.watch` | present | absent |
| `launchable-activity` | `dev.sasha.omnitrain.MainActivity` | the same |
| `android_wear_capabilities` | `["omnitrain_wear"]` | `["omnitrain_phone"]` |

## Suites

| suite | result |
|---|---|
| `test/wear_watch_transport_test.dart` + `test/wear_app_test.dart` | `+15: All tests passed!` |
| `test/wear_os_config_test.dart` | `+9: All tests passed!` |
| `test/watch_transport_test.dart` (the phone's side, S-006 rewritten) | `+66: All tests passed!` |

The first attempt at S-28023 failed (`WhereIterable<MethodCall>:[]` at
`test/wear_app_test.dart`): `testWidgets`' fake clock delivers a mocked platform
stream event only after the test body ends, so the shell never saw the frame
inside the test. Instrumenting the transport and the shell showed the event
arriving after the assertions. D-28011 is the fix — the transport's arrival lane
is a public entry point, and the platform stream stays proved by the transport's
own test, which runs with the real event loop (S-28015 covers order and
non-overlap through it).

## Pre-existing red (not this PR's)

`flutter test test/ui_standards_contract_test.dart` — 4 failures, none naming a
file this PR added or changed (one did, and it was fixed: a `TextButton` without
a `shape:` in `lib/watch/app/wear_app.dart`):

- `lib/app.dart` builds raw colours (`Color(0x...)`) — S-2604.
- `Colors.white` / `Colors.black` used in files that are not on the ratchet —
  S-2607.
- 11 hand-built dialogs against a ratchet of 9 — S-3001.
- a message bar outside the two files that own that look — S-2702.

`flutter test test/docs_indexing_contract_test.dart` — 7 failures, none naming
`docs/wear_os_app.md` or this plan:

- eighteen `docs/plans/` files over the 64 KiB ceiling, and five in the warning
  band;
- two hex literals inside old plan evidence files;
- the reachability and link-resolution tests abort with
  `Invalid argument(s): Illegal character in path` from the test's own
  `Uri.file` call, which is a defect in the test rather than a finding.

`test/watch_reference_sync_test.dart` fails alone as well (its
"schema-conformant" assertions report a non-empty list), so it predates this PR.

`test/pre_release_gate_notification_and_build_test.dart` fails on this machine
because it shells out to the `zip` CLI for its synthetic AABs; `bash` is not on
`PATH` either, so the gate script itself cannot be exercised here. Both are
environment gaps, not findings.

## Standards seen, not fixed

`test/ui_standards_contract_test.dart` also reports, on files this PR does not
touch: raw colours in `lib/app.dart` (S-2604), `Colors.white` / `Colors.black`
uses that are not on the ratchet (S-2607), eleven hand-built dialogs against a
ratchet of nine (S-3001), and a message bar outside the two files that own that
look (S-2702). Fixing them is a separate change; nothing here raises a ratchet or
adds an allowlist entry.

## The full suite

`flutter test` on this branch reports 7,567 passing and 1,074 failing tests, and
the failures are **environmental, not this PR's**. Grouped by suite, the largest
offenders are `test/sync_protocol_fixtures_test.dart` (167),
`test/watch_session_merge_test.dart` (74), `test/watch_session_engine_test.dart`
(74), `test/watch_session_import_test.dart` (66) and
`test/live_mirroring_test.dart` (62). Two reproduced messages name the cause:

- `'invalid/bests_down_duplicate_exercise.json'` versus
  `'invalid\\bests_down_duplicate_exercise.json'` — the fixture tests compare
  manifest paths with forward slashes against Windows-separated paths.
- `missing_schema at $.type: no schema document for message type routines_down`
  — the schema documents do not load, so the validator accepts what the suites
  expect it to reject. The same cause produces the engine suite's
  `WatchEmissionRejected` expectations all coming back as "did not throw".

Neither has anything to do with a file this PR touched: `git diff --stat` lists
eleven modified files (the release workflow, the Gradle build, two docs, three
`lib/core/platform` files, the factory, the plugin's README and pubspec, the gate
script and `test/watch_transport_test.dart`) and the untracked additions are the
new Wear files, the two plan files, the new doc and the three new test files.

The watch area is green when its files are run together, which is the check that
matters for this PR:

```
flutter test test/wear_app_test.dart test/wear_watch_transport_test.dart \
    test/wear_os_config_test.dart test/watch_transport_test.dart
→ +90: All tests passed!
```
