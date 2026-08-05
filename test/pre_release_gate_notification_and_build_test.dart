// Tests for the §11r and §11s pre-release gate checks added in
// `.github/agents/plans/crash-reporting-rate-limit-plan.md`
// (Iteration 3).
//
// Two invariants are added beside the existing crash-reporting checks:
//
//   §11r — The Android release build's notification protections
//           (ProGuard `-keep` for `com.dexterous.flutterlocalnotifications.**
//            classes and `keep.xml` raw-resource declarations) MUST
//            take effect in the produced artifact. Verified by:
//             a) seeds.txt — R8 records every class matched by a
//                `-keep` rule, in
//                android/app/build/outputs/mapping/release/seeds.txt.
//             b) The AAB / APK contains the raw sound resources
//                declared in keep.xml.
//
//   §11s — A release build MUST be producible. The gate invokes
//           `flutter build appbundle --release` (or the APK fallback)
//           and fails loudly on non-zero exit, surfacing the captured
//           stderr so the underlying error is not masked.
//
// Both §11r and §11s run regardless of `--fast` — they ARE the gate.
//
// Testing strategy
// ────────────────
// Running `flutter build appbundle` from inside a Dart test would take
// minutes and require a full Android toolchain on every CI worker.
// The gate script therefore honours an environment-variable hook,
// `PRE_RELEASE_GATE_FAKE_BUILD`, that is documented as test-only:
// when set, the build helper is skipped and instead the helper
// writes whatever artifacts the variable describes directly into the
// build output paths. This lets each test case inject a green or red
// build result deterministically and quickly.
//
// `flutter analyze` and `flutter test` are still skipped via
// `--fast`. The build (§11s) and notification checks (§11r) under
// test are not gated on `SKIP_HEAVY`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _repoRoot = '.';

class _TempRepo {
  _TempRepo._(this.path);

  final String path;

  /// Recursive copy of [src] into a fresh temp directory. The copy
  /// is followed by a best-effort `git init && git add -A && git
  /// commit` so that the gate's "pubspec has uncommitted changes"
  /// check does not spuriously fail this test. The original repo
  /// may have local uncommitted edits that are unrelated to the
  /// invariants under test.
  ///
  /// Uses rsync with exclusions when available so we skip the
  /// large `.dart_tool/`, `build/`, and `ios/Pods/` directories.
  /// Without exclusions, each test setup copies hundreds of MB
  /// and the suite runs past the 30-second test-framework
  /// timeout. The gate inspects `.github/workflows/release.yml`,
  /// `pubspec.yaml`, and the iOS source files — none of which
  /// live in those directories.
  static Future<_TempRepo> create(String src) async {
    final parent = Directory.systemTemp.createTempSync('omnitrain_gate3_');
    final dst = '${parent.path}/repo';
    final hasRsync = await Process.run('which', <String>['rsync'])
            .then((r) => r.exitCode == 0);
    ProcessResult result;
    if (hasRsync) {
      result = await Process.run('rsync', <String>[
        '-a',
        '--exclude', '.git',
        '--exclude', '.dart_tool',
        '--exclude', 'build',
        '--exclude', 'ios/Pods',
        '--exclude', 'ios/.symlinks',
        '--exclude', 'ios/Flutter/Flutter.framework',
        '--exclude', 'ios/Flutter/ephemeral',
        '--exclude', 'macos/Pods',
        '--exclude', 'macos/Flutter/Flutter.framework',
        '--exclude', 'macos/Flutter/ephemeral',
        '--exclude', '.venv',
        '--exclude', '.claude',
        '--exclude', '.idea',
        '$src/',
        dst,
      ]);
    } else {
      result = await Process.run('cp', ['-R', '$src/.', dst]);
    }
    if (result.exitCode != 0) {
      throw StateError('cp/rsync failed: ${result.stderr}');
    }
    final repo = _TempRepo._(dst);
    // Use a per-repo identity so the synthetic commit has an author.
    await Process.run('git', <String>['init', '-q', dst]);
    await Process.run(
      'git',
      <String>['config', 'user.email', 'gate-test@omnitrain'],
      workingDirectory: dst,
    );
    await Process.run(
      'git',
      <String>['config', 'user.name', 'Gate Test'],
      workingDirectory: dst,
    );
    await Process.run(
      'git',
      <String>['add', '-A'],
      workingDirectory: dst,
    );
    await Process.run(
      'git',
      <String>['commit', '-q', '-m', 'gate test seed'],
      workingDirectory: dst,
    );
    // Truncate the .last-released-build file inside the temp copy
    // so the existing repo's old "last released" build number does
    // not interact with the current pubspec version. Set it to 0 —
    // any positive value the test touches will exceed it.
    final lastReleaseFile = File('$dst/docs/releases/.last-released-build');
    if (lastReleaseFile.existsSync()) {
      lastReleaseFile.writeAsStringSync('0');
    }
    // Lay down a green iOS IPA so the §11q artifact check does
    // not spuriously fail this test. The §11r / §11s checks
    // (which this test exercises) verify the produced Android
    // artifact; the iOS check is orthogonal but runs in the
    // same gate script. Without this IPA the gate would exit
    // non-zero on §11q alone and the §11r / §11s tests would
    // fail.
    await repo.writeFakeIpa();
    return repo;
  }

  /// Writes a synthetic R8 `seeds.txt` matching what `flutter build`
  /// produces after the post-fix `proguard-rules.pro`. The seeds
  /// contain one line per `-keep` match.
  void writeGreenSeeds() {
    final dir = Directory('$path/android/app/build/outputs/mapping/release');
    dir.createSync(recursive: true);
    File('${dir.path}/seeds.txt').writeAsStringSync('''
com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin: pi:com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin in:.
com.dexterous.flutterlocalnotifications.models.NotificationDetails: pi:com.dexterous.flutterlocalnotifications.models.NotificationDetails
com.google.gson.reflect.TypeToken: pi:com.google.gson.reflect.TypeToken
''');
  }

  /// Writes a synthetic R8 `seeds.txt` with the notification keeps
  /// stripped — simulates the case where the protection did not take
  /// effect (the regression that §11r catches).
  void writeRedSeeds() {
    final dir = Directory('$path/android/app/build/outputs/mapping/release');
    dir.createSync(recursive: true);
    File('${dir.path}/seeds.txt').writeAsStringSync('''
com.google.gson.reflect.TypeToken: pi:com.google.gson.reflect.TypeToken
io.sentry.Sentry: pi:io.sentry.Sentry
''');
  }

  /// Writes the minimum valid AndroidManifest that Gradle / AAPT2
  /// expect in an AAB. The `aapt`-style binary format is not
  /// required for the gate — the script only inspects the zip's
  /// central directory entries, which `unzip -l` and ZipFile
  /// both surface. A two-file AAB with AndroidManifest + the kept
  /// raw resources is sufficient and parses cleanly.
  Future<void> writeFakeAabWith(
      {required Iterable<String> keptRawResources}) async {
    final outDir =
        Directory('$path/build/app/outputs/bundle/release');
    outDir.createSync(recursive: true);
    final aabPath = '${outDir.path}/app-release.aab';
    await _writeZip(aabPath, <_ZipEntry>[
      _ZipEntry(
        'AndroidManifest.xml',
        <int>[0x03, 0x00, 0x08, 0x00], // arbitrary non-empty payload
      ),
      for (final name in keptRawResources)
        _ZipEntry('res/raw/$name', <int>[0x01, 0x02, 0x03]),
    ]);
  }

  /// Writes a synthetic iOS IPA whose `Runner.app/Runner` binary
  /// contains the literal Sentry DSN string. The Dart front-end
  /// compiles `--dart-define=SENTRY_DSN=<value>` into the App
  /// binary as a string constant. The gate greps for the DSN to
  /// confirm the artifact check (§11q) passes. The minimal
  /// Runner.app structure satisfies the gate's IPA inspection.
  Future<void> writeFakeIpa() async {
    const dsn = 'https://examplePublicKey@o0.ingest.sentry.io/0';
    final outDir = Directory('$path/build/ios/ipa');
    outDir.createSync(recursive: true);
    final ipaPath = '${outDir.path}/Runner.ipa';
    await _writeZip(ipaPath, <_ZipEntry>[
      _ZipEntry(
        'Runner.app/Runner',
        <int>[
          ...utf8Bytes(
            'OmniTrain iOS binary placeholder. '
            'Sentry DSN here: $dsn '
            '(synthetic, test-only).',
          ),
          ...List<int>.filled(64, 0x20),
        ],
      ),
      _ZipEntry(
        'Runner.app/Info.plist',
        <int>[0x3C, 0x3F, 0x78, 0x6D, 0x6C],
      ),
    ]);
  }

  /// Runs the pre-release gate. `--fast` is used so `flutter
  /// analyze` and `flutter test` are skipped; §11s / §11r must NOT
  /// be skipped by `--fast` per the gate's design.
  Future<ProcessResult> runGate({String? fakeBuild}) async {
    final script = '$path/scripts/pre_release_check.sh';
    final env = <String, String>{
      ...Platform.environment,
      // `flutter` is not on PATH inside this test runner; setting
      // the fake-build hooks is what makes §11s and §11q
      // trustworthy in tests. The gate refuses to run `flutter
      // build` when these are set; otherwise the gate would
      // attempt the build and either slow the test to minutes or
      // fail when the toolchain is absent.
      'PRE_RELEASE_GATE_FAKE_BUILD': fakeBuild ?? 'ok',
      'PRE_RELEASE_GATE_FAKE_IP_BUILD': 'ok',
    };
    return Process.run(
      'bash',
      <String>[script, '--fast'],
      workingDirectory: path,
      environment: env,
    );
  }

  Future<void> dispose() async {
    await Directory(path).delete(recursive: true);
  }
}

/// A minimal zip writer implementing the two methods the gate uses:
/// write a list of (path, bytes) entries and read the central
/// directory listing back. Flutter ships no zip writer in this
/// codebase, so the test runs the system `zip` CLI which is present
/// on every macOS / Linux CI worker.
Future<void> _writeZip(String path, List<_ZipEntry> entries) async {
  // Use the system `zip` to avoid a Dart dependency. The CLI is
  // available on macOS (which is where these tests were originally
  // authored) and most Linux CI images; this keeps the test pure-Dart
  // for setup while outsourcing the actual byte packing to a
  // standard tool.
  final tmp = Directory.systemTemp.createTempSync('omnitrain_aab_');
  for (final e in entries) {
    final f = File('${tmp.path}/${e.path}');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(e.bytes);
  }
  // -X strips extra filesystem metadata so the zip is deterministic
  // across runs.
  final result = await Process.run(
      'zip', <String>['-qX', '-r', path, '.'], workingDirectory: tmp.path);
  if (result.exitCode != 0) {
    throw StateError('zip failed: ${result.stderr}');
  }
  await tmp.delete(recursive: true);
}

class _ZipEntry {
  _ZipEntry(this.path, this.bytes);
  final String path;
  final List<int> bytes;
}

List<int> utf8Bytes(String s) => s.codeUnits;

/// Verifies the system has `zip` and `unzip` available — both are
/// required for the tests in this file (the script uses `unzip -l`).
/// Failure here is reported clearly because the gate test itself is
/// the missing-test environment, not a flaky test.
Future<bool> _hasZipCli() async {
  final r = await Process.run('which', <String>['zip']);
  return r.exitCode == 0;
}

Future<bool> _hasUnzipCli() async {
  final r = await Process.run('which', <String>['unzip']);
  return r.exitCode == 0;
}

void main() {
  // Set up: skip the whole file gracefully when the host is missing
  // `zip` / `unzip` (the test tools we use to build fake AABs and
  // the script uses to inspect them). Skipping is preferable to a
  // red suite on a developer machine without the toolchain.
  late bool canRun;
  setUpAll(() async {
    final hasZip = await _hasZipCli();
    final hasUnzip = await _hasUnzipCli();
    canRun = hasZip && hasUnzip;
    if (!canRun) {
      // ignore: avoid_print
      print('SKIP: zip and/or unzip not on PATH — required for the '
          '§11r / §11s gate tests.');
    }
  });

  group('pre-release gate — §11r notification protections '
      '(artifact inspection)', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test(
      'GREEN: seeds.txt contains the kept flutter_local_notifications '
      'classes — §11r passes for code protection',
      () async {
        if (!canRun) {
          return;
        }
        repo.writeGreenSeeds();
        await repo.writeFakeAabWith(
          keptRawResources: <String>{
            'boxing_bell',
            'digital_buzzer',
            'soft_chime',
            'double_tap',
            'signal_tone',
          },
        );

        final result = await repo.runGate(fakeBuild: 'ok');

        expect(result.exitCode, 0,
            reason: 'Gate must pass for the post-fix state');
        final output = '${result.stdout}\n${result.stderr}';
        // Failure sentinels — any of these firing means §11r is
        // incorrectly tripping.
        expect(
          output,
          isNot(contains('notification code protection did not apply')),
          reason: 'Code-protection failure message must not appear',
        );
        expect(
          output,
          isNot(contains('notification resource protection did not apply')),
          reason: 'Resource-protection failure message must not appear',
        );
        // The OK path should produce a positive signal that future
        // readers can grep for.
        expect(output, contains('notification code protection'),
            reason: '§11r must announce which protection it verified');
      },
    );

    test(
      'RED: seeds.txt omits the kept flutter_local_notifications '
      'classes — §11r fails for code protection',
      () async {
        if (!canRun) {
          return;
        }
        repo.writeRedSeeds();
        await repo.writeFakeAabWith(
          keptRawResources: <String>{
            'boxing_bell',
            'digital_buzzer',
            'soft_chime',
            'double_tap',
            'signal_tone',
          },
        );

        final result = await repo.runGate(fakeBuild: 'ok');

        expect(result.exitCode, 1,
            reason: 'Gate must fail when the kept notification '
                'classes did not survive R8');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('notification code protection'),
            reason: 'Failure message must name the check');
        expect(output,
            contains('com.dexterous.flutterlocalnotifications'),
            reason: 'Failure message must name the expected classes');
        expect(output, contains('every notification schedule'),
            reason: 'Failure message must name the user-facing '
                'consequence');
      },
    );

    test(
      'RED: AAB is missing the raw sound resources declared in '
      'keep.xml — §11r fails for resource protection',
      () async {
        if (!canRun) {
          return;
        }
        repo.writeGreenSeeds();
        await repo.writeFakeAabWith(
          keptRawResources: <String>{},
        );

        final result = await repo.runGate(fakeBuild: 'ok');

        expect(result.exitCode, 1,
            reason: 'Gate must fail when the raw sound resources '
                'are missing from the produced AAB');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('notification resource protection'),
            reason: 'Failure message must name the check');
        expect(output, contains('boxing_bell'),
            reason: 'Failure message must name at least one '
                'expected resource so the reader knows what '
                'keep.xml declared');
        expect(output, contains('PlatformException'),
            reason: 'Failure message must name the runtime '
                'consequence (RawResourceAndroidNotificationSound '
                'throws invalid_sound when the resource is missing)');
      },
    );

    test(
      'RED: build output is absent — §11r fails rather than silently '
      'passing (PASS-BY-DEFAULT IS REJECTED)',
      () async {
        if (!canRun) {
          return;
        }
        // No seeds.txt, no AAB. The fake-build flag is set to
        // `ok` so §11s succeeds, isolating §11r. Per the
        // acceptance criterion: missing output must fail, never
        // pass by default.
        final result = await repo.runGate(fakeBuild: 'ok');

        expect(result.exitCode, 1,
            reason: 'Gate must fail when the expected build output '
                'is absent (acceptance criterion: '
                '"fails rather than passing by default when '
                'expected build output is missing entirely")');
        final output = '${result.stdout}\n${result.stderr}';
        // The failure message must make clear that the missing
        // build output IS the failure cause — not silently
        // pass-through.
        final tellsCause =
            output.contains('expected build output') ||
                output.contains('release build did not produce') ||
                output.contains('seeds.txt') ||
                output.contains('app-release.aab') ||
                output.contains('app-release.apk');
        expect(tellsCause, isTrue,
            reason: 'Failure message must name the missing build '
                'output so the reader knows §11s produced nothing '
                'usable, rather than discovering it via the '
                '"blocking error" summary alone');
      },
    );
  });

  group('pre-release gate — §11s release build must succeed', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test(
      'GREEN: fake-build hook reports success — §11s passes',
      () async {
        if (!canRun) {
          return;
        }
        repo.writeGreenSeeds();
        await repo.writeFakeAabWith(
          keptRawResources: <String>{
            'boxing_bell',
            'digital_buzzer',
            'soft_chime',
            'double_tap',
            'signal_tone',
          },
        );

        final result = await repo.runGate(fakeBuild: 'ok');

        expect(result.exitCode, 0,
            reason: 'Gate must pass when the fake-build hook '
                'reports success');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('release build'),
            reason: '§11s must announce which check it ran');
        // Failure sentinels — none of these should fire when the
        // build succeeded.
        expect(
          output,
          isNot(contains('release build could not be produced')),
          reason: 'Build-success message must not appear as a '
              'failure',
        );
        expect(
          output,
          isNot(contains('build error')),
          reason: 'No underlying-build-error message should fire',
        );
      },
    );

    test(
      'RED: fake-build hook reports failure — §11s fails AND the '
      'underlying error text appears in the gate output (not masked)',
      () async {
        if (!canRun) {
          return;
        }
        const fakeError = 'error: bracket-list-expression cannot '
            'match empty list.';
        final result = await repo.runGate(fakeBuild: 'fail:$fakeError');

        expect(result.exitCode, 1,
            reason: 'Gate must fail when the release build '
                'returns non-zero');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('release build could not be produced'),
            reason: 'Failure message must name the check');
        expect(output, contains(fakeError),
            reason: 'The underlying build error text must be '
                'surfaced in the gate output — it may NOT be '
                'masked by a friendly summary that drops the '
                'actual diagnostic');
        // The reader at release time should not need to reconstruct
        // the history of this incident to know what to do — the
        // message must connect the dots between the build error
        // and the action required.
        final tellsWhyReleaseIsBlocked =
            output.contains('configuration could not compile') ||
                output.contains('configuration changes') ||
                output.contains('cannot ship');
        expect(tellsWhyReleaseIsBlocked, isTrue,
            reason: 'Failure message must connect the dot for a '
                'reader at release time: this gate catches a '
                'broken configuration so a release cannot ship '
                'with a build that does not compile');
      },
    );
  });

  group('pre-release gate — §11r / §11s combined', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test(
      'the §11r / §11s section as a whole fails when ANY single '
      'subcheck fails (pre-existing pattern from §11k–§11q)',
      () async {
        if (!canRun) {
          return;
        }
        // Code protection OK; resource protection NOT OK; build OK.
        // The whole section must fail.
        repo.writeGreenSeeds();
        await repo.writeFakeAabWith(keptRawResources: <String>{});
        final result = await repo.runGate(fakeBuild: 'ok');

        expect(result.exitCode, 1,
            reason: 'A single failing subcheck must fail the gate '
                'as a whole, matching the §11k–§11q "single '
                'blocking error blocks release" convention');
        final output = '${result.stdout}\n${result.stderr}';
        // The §11k–§11q pattern: every individual ✗ must count as
        // a blocking error, and the summary at the bottom lists
        // them all.
        expect(output, contains('✗'),
            reason: 'Summary must contain at least one ✗ marker');
        expect(output, contains('blocking error'),
            reason: 'Summary must surface that the gate has at '
                'least one blocking error');
      },
    );

    test(
      '--fast does NOT skip §11r / §11s (they are not heavy; they '
      'ARE the gate)',
      () async {
        if (!canRun) {
          return;
        }
        // Force both checks red; even with --fast the gate must
        // still catch them.
        repo.writeRedSeeds();
        await repo.writeFakeAabWith(keptRawResources: <String>{});
        final result =
            await repo.runGate(fakeBuild: 'fail:synthetic');

        expect(result.exitCode, 1,
            reason: '§11r / §11s must run under --fast — the '
                'opposite would mean a developer running the '
                'fast variant skips the actual gate');
      },
    );
  });
}

// (no-oped test pattern kept here for reader reference; the file
// uses `if (!canRun) return;` directly)
