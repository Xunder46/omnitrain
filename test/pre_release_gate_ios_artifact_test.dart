// Tests for the iOS reporting-destination pre-release gate check added
// in `docs/plans/crash-reporting-three-defects-plan.md`.
//
// The previous gate (§11p / §11q in older revisions of
// `scripts/pre_release_check.sh`) inspected the workflow file —
// `SENTRY_DSN:` in the iOS job's env: block, and
// `EXTRA_FRONT_END_OPTIONS: ... --dart-define=SENTRY_DSN=...` in the
// run block. Both passed today while iOS shipped unmonitored. That
// was the defect: a configuration check that does not exercise the
// actual artifact is false confidence.
//
// The replacement check inspects the produced iOS IPA. The Dart
// front-end compiles `--dart-define=SENTRY_DSN=<value>` into the
// `App.framework/App` (or legacy `Runner.app/Runner`) binary as a
// string constant. A grep over the binary finds the DSN when the
// build actually injected it; the absence of the DSN is the failure
// signal. The check exercises the artifact, not the configuration.
//
// Three invariants under test:
//
//   §11p (new)  — iOS build invocation must use `flutter build ipa`
//                 (the tooling-driven build) so `--dart-define`
//                 flows through the supported mechanism. A future
//                 agent who reverts to the bespoke `xcodebuild`
//                 invocation fails the gate.
//   §11q (new)  — the produced iOS IPA must contain the
//                 SENTRY_DSN string. Verified by extracting the IPA
//                 and grepping the App binary for the DSN. Passes
//                 only when the DSN is present in the artifact.
//   §11n / §11o (extended) — both platforms' SENTRY_PROJECT env var
//                 must be exactly `omnitrain`. A future agent who
//                 re-introduces per-platform destinations
//                 (`omnitrain-ios`, `omnitrain-android`) fails the
//                 gate.
//
// `flutter analyze` and `flutter test` are still skipped via
// `--fast`. The build (§11s) and iOS artifact checks (§11q) under
// test are not gated on `SKIP_HEAVY`.
//
// Testing strategy
// ────────────────
// Running `flutter build ipa` from inside a Dart test would take
// minutes and require a full Xcode toolchain on every CI worker.
// The gate script therefore honours an environment-variable hook,
// `PRE_RELEASE_GATE_FAKE_IP_BUILD`, that is documented as test-only:
// when set, the build helper is skipped and instead the helper
// writes whatever artifacts the variable describes directly into
// the build output paths. The hook mirrors the existing
// `PRE_RELEASE_GATE_FAKE_BUILD` hook that §11s honours for Android.
// `unzip` is used to inspect the produced IPA.

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
  /// The copy uses `rsync` when available so we can exclude
  /// `.dart_tool/`, `build/`, `.build/`, `ios/Pods/`, and other generated
  /// directories that the gate does not inspect. `build` does not match
  /// `.build`, and the watchOS package's build output is large enough that
  /// copying it per test approaches the 30-second test-framework timeout.
  /// `cp -R` would
  /// copy the entire `.dart_tool` cache (hundreds of MB), pushing
  /// each test setup past the 30-second test-framework timeout.
  /// The gate's checks read `.github/workflows/release.yml`,
  /// `pubspec.yaml`, the iOS source files (`Info.plist`,
  /// `project.pbxproj`), and the test-injected `build/ios/ipa/`
  /// artifacts — none of which live in `.dart_tool` or
  /// `ios/Pods/`.
  static Future<_TempRepo> create(String src) async {
    final parent = Directory.systemTemp.createTempSync('omnitrain_gate_ios_');
    final dst = '${parent.path}/repo';
    final hasRsync = await Process.run('which', <String>[
      'rsync',
    ]).then((r) => r.exitCode == 0);
    ProcessResult result;
    if (hasRsync) {
      result = await Process.run('rsync', <String>[
        '-a',
        '--exclude',
        '.git',
        '--exclude',
        '.dart_tool',
        '--exclude',
        'build',
        '--exclude',
        '.build',
        '--exclude',
        'ios/Pods',
        '--exclude',
        'ios/.symlinks',
        '--exclude',
        'ios/Flutter/Flutter.framework',
        '--exclude',
        'ios/Flutter/ephemeral',
        '--exclude',
        'macos/Pods',
        '--exclude',
        'macos/Flutter/Flutter.framework',
        '--exclude',
        'macos/Flutter/ephemeral',
        '--exclude',
        '.venv',
        '--exclude',
        '.claude',
        '--exclude',
        '.idea',
        '$src/',
        dst,
      ]);
    } else {
      // Fallback to cp -R; tests will be slow but correct.
      result = await Process.run('cp', ['-R', '$src/.', dst]);
    }
    if (result.exitCode != 0) {
      throw StateError('cp/rsync failed: ${result.stderr}');
    }
    final repo = _TempRepo._(dst);
    // Use a per-repo identity so the synthetic commit has an author.
    await Process.run('git', <String>['init', '-q', dst]);
    await Process.run('git', <String>[
      'config',
      'user.email',
      'gate-test@omnitrain',
    ], workingDirectory: dst);
    await Process.run('git', <String>[
      'config',
      'user.name',
      'Gate Test',
    ], workingDirectory: dst);
    await Process.run('git', <String>['add', '-A'], workingDirectory: dst);
    await Process.run('git', <String>[
      'commit',
      '-q',
      '-m',
      'gate test seed',
    ], workingDirectory: dst);
    // Truncate the .last-released-build file inside the temp copy
    // so the existing repo's old "last released" build number does
    // not interact with the current pubspec version. Set it to 0 —
    // any positive value the test touches will exceed it.
    final lastReleaseFile = File('$dst/docs/releases/.last-released-build');
    if (lastReleaseFile.existsSync()) {
      lastReleaseFile.writeAsStringSync('0');
    }
    // Lay down a green Android build artifact and seeds.txt so
    // the §11r/§11s checks do not spuriously fail this test.
    // These checks verify the produced artifact, not the
    // workflow text — the iOS artifact tests should not have to
    // know how to satisfy them. The fake Android artifacts
    // mirror the pattern used in
    // `test/pre_release_gate_notification_and_build_test.dart`.
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

  /// Writes the minimum valid AAB that satisfies the §11r resource
  /// check. A two-file AAB with AndroidManifest + the kept raw
  /// resources is sufficient and parses cleanly.
  Future<void> writeFakeAabWith({
    required Iterable<String> keptRawResources,
  }) async {
    final outDir = Directory('$path/build/app/outputs/bundle/release');
    outDir.createSync(recursive: true);
    final aabPath = '${outDir.path}/app-release.aab';
    await _writeZip(aabPath, <_ZipEntry>[
      _ZipEntry('AndroidManifest.xml', <int>[0x03, 0x00, 0x08, 0x00]),
      for (final name in keptRawResources)
        _ZipEntry('res/raw/$name', <int>[0x01, 0x02, 0x03]),
    ]);
  }

  File workflow() => File('$path/.github/workflows/release.yml');
  File pubspec() => File('$path/pubspec.yaml');

  /// Writes a synthetic iOS IPA whose `Runner.app/Runner` binary
  /// contains the literal DSN string. The Dart front-end compiles
  /// `--dart-define=SENTRY_DSN=<value>` into the App binary as a
  /// string constant; the gate greps for it. The minimal
  /// Runner.app structure required by the gate:
  ///   - `Runner.app/Runner` (the binary; the gate greps this)
  ///   - `Runner.app/Info.plist` (so the central directory looks
  ///      like a real app bundle)
  Future<void> writeFakeIpaWithDsn({required String dsn}) async {
    final outDir = Directory('$path/build/ios/ipa');
    outDir.createSync(recursive: true);
    final ipaPath = '${outDir.path}/Runner.ipa';
    await _writeZip(ipaPath, <_ZipEntry>[
      _ZipEntry(
        'Runner.app/Runner',
        // The binary is a synthetic blob. The string the gate
        // greps for must be present verbatim. Padding bytes give
        // the file a non-trivial length so the check is not a
        // false positive on an empty file.
        <int>[
          ...utf8Bytes(
            'OmniTrain iOS binary placeholder. '
            'Sentry DSN here: $dsn'
            ' (synthetic, test-only).',
          ),
          ...List<int>.filled(64, 0x20),
        ],
      ),
      _ZipEntry('Runner.app/Info.plist', <int>[0x3C, 0x3F, 0x78, 0x6D, 0x6C]),
    ]);
  }

  /// Writes a synthetic iOS IPA whose `Runner.app/Runner` binary
  /// does NOT contain a Sentry DSN. Mirrors the regression
  /// scenario: the workflow was configured correctly but the
  /// build did not inject the DSN into the binary.
  Future<void> writeFakeIpaWithoutDsn() async {
    final outDir = Directory('$path/build/ios/ipa');
    outDir.createSync(recursive: true);
    final ipaPath = '${outDir.path}/Runner.ipa';
    await _writeZip(ipaPath, <_ZipEntry>[
      _ZipEntry(
        'Runner.app/Runner',
        // Synthetic binary without any DSN string. The gate must
        // detect this and fail.
        <int>[
          ...utf8Bytes(
            'OmniTrain iOS binary placeholder without '
            'Sentry DSN (synthetic, test-only).',
          ),
          ...List<int>.filled(64, 0x20),
        ],
      ),
      _ZipEntry('Runner.app/Info.plist', <int>[0x3C, 0x3F, 0x78, 0x6D, 0x6C]),
    ]);
  }

  /// Runs the pre-release gate. `--fast` is used so `flutter
  /// analyze` and `flutter test` are skipped; the iOS artifact
  /// check must NOT be skipped by `--fast`.
  ///
  /// The build is faked by default. Both the Android
  /// (`PRE_RELEASE_GATE_FAKE_BUILD`) and iOS
  /// (`PRE_RELEASE_GATE_FAKE_IP_BUILD`) hooks are honoured by
  /// the gate as test-only. Without these hooks the gate would
  /// invoke `flutter build ipa` (which takes minutes and
  /// requires a full Xcode toolchain) and `flutter build
  /// appbundle` (which requires the Android SDK). The tests
  /// exercise the gate's verdict semantics by injecting the
  /// artifacts the build would have produced.
  Future<ProcessResult> runGate({String? fakeIosBuild}) async {
    final script = '$path/scripts/pre_release_check.sh';
    final env = <String, String>{
      ...Platform.environment,
      'PRE_RELEASE_GATE_FAKE_BUILD': 'ok',
      // Default to faking the iOS build too — otherwise the
      // gate would attempt `flutter build ipa` for real, which
      // takes minutes and either fails when the toolchain is
      // absent or hangs the test past its timeout. Tests that
      // want to exercise the build failure path pass
      // `fakeIosBuild: 'fail:<error>'`.
      // ignore: use_null_aware_elements
      if (fakeIosBuild != null)
        'PRE_RELEASE_GATE_FAKE_IP_BUILD': fakeIosBuild
      else
        'PRE_RELEASE_GATE_FAKE_IP_BUILD': 'ok',
    };
    return Process.run(
      'bash',
      // `--all` forces BOTH platform sections into scope. Without it the
      // gate auto-detects from the host toolchain, so these assertions
      // would silently become no-ops on a machine that cannot build the
      // other platform (a Mac has no Android SDK; a PC has no Xcode).
      // The fake-build hooks above stand in for the real artifacts, so
      // forcing both platforms costs nothing and keeps the expectations
      // host-independent.
      <String>[script, '--fast', '--all'],
      workingDirectory: path,
      environment: env,
    );
  }

  Future<void> dispose() async {
    await Directory(path).delete(recursive: true);
  }
}

/// A minimal zip writer. Flutter ships no zip writer in this
/// codebase, so the test runs the system `zip` CLI which is present
/// on every macOS / Linux CI worker.
Future<void> _writeZip(String path, List<_ZipEntry> entries) async {
  final tmp = Directory.systemTemp.createTempSync('omnitrain_ipa_');
  for (final e in entries) {
    final f = File('${tmp.path}/${e.path}');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(e.bytes);
  }
  // -X strips extra filesystem metadata so the zip is deterministic
  // across runs.
  final result = await Process.run('zip', <String>[
    '-qX',
    '-r',
    path,
    '.',
  ], workingDirectory: tmp.path);
  if (result.exitCode != 0) {
    throw StateError('zip failed: ${result.stderr}');
  }
  await tmp.delete(recursive: true);
}

List<int> utf8Bytes(String s) => s.codeUnits;

class _ZipEntry {
  _ZipEntry(this.path, this.bytes);
  final String path;
  final List<int> bytes;
}

/// Verifies the system has `zip` and `unzip` available — both are
/// required for the tests in this file (the script uses `unzip -l`
/// and the test scaffolding uses `zip`). Failure here is reported
/// clearly because the gate test itself is the missing-test
/// environment, not a flaky test.
Future<bool> _hasZipCli() async {
  final r = await Process.run('which', <String>['zip']);
  return r.exitCode == 0;
}

Future<bool> _hasUnzipCli() async {
  final r = await Process.run('which', <String>['unzip']);
  return r.exitCode == 0;
}

void main() {
  late bool canRun;
  setUpAll(() async {
    final hasZip = await _hasZipCli();
    final hasUnzip = await _hasUnzipCli();
    canRun = hasZip && hasUnzip;
    if (!canRun) {
      // ignore: avoid_print
      print(
        'SKIP: zip and/or unzip not on PATH — required for the '
        'iOS artifact gate tests.',
      );
    }
  });

  group('pre-release gate — §11q iOS reporting destination '
      '(IPA artifact inspection)', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test('GREEN: iOS IPA contains the DSN string — §11q passes', () async {
      if (!canRun) {
        return;
      }
      // Write an IPA whose binary contains the literal DSN. The
      // gate must extract the IPA, grep the binary, and find
      // the DSN.
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      );

      final result = await repo.runGate();

      expect(
        result.exitCode,
        0,
        reason:
            'Gate must pass when the produced IPA '
            'contains the SENTRY_DSN value',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        isNot(contains('iOS reporting destination is absent')),
        reason: 'No reporting-destination failure should fire',
      );
      // The OK path must announce which check it ran.
      expect(
        output,
        contains('iOS reporting destination'),
        reason: '§11q must announce which check it verified',
      );
    });

    test('RED: iOS IPA does NOT contain the DSN string — §11q fails '
        '(the original bug, reproduced)', () async {
      if (!canRun) {
        return;
      }
      // Write an IPA whose binary omits any DSN. This mirrors
      // the regression where the workflow claims the DSN is
      // injected but the build did not inject it. The gate
      // must detect this by inspecting the artifact, not the
      // workflow file.
      await repo.writeFakeIpaWithoutDsn();

      final result = await repo.runGate();

      expect(
        result.exitCode,
        1,
        reason:
            'Gate must fail when the produced iOS '
            'artifact lacks a working reporting destination',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        contains('iOS'),
        reason: 'Failure message must name the platform',
      );
      expect(
        output,
        contains('SENTRY_DSN'),
        reason: 'Failure message must name the missing env var',
      );
      expect(
        output,
        contains('silently never'),
        reason:
            'Failure message must name the user-facing '
            'consequence — iOS would appear monitored but '
            'produce nothing',
      );
    });

    test('RED: iOS artifact is absent — §11q fails rather than '
        'silently passing (PASS-BY-DEFAULT IS REJECTED)', () async {
      if (!canRun) {
        return;
      }
      // No IPA produced. The fake-build hook is set to `ok`
      // for the Android build (§11s succeeds), isolating §11q.
      // Per the acceptance criterion: missing output must fail,
      // never pass by default.
      final result = await repo.runGate();

      expect(
        result.exitCode,
        1,
        reason:
            'Gate must fail when the expected iOS '
            'artifact is absent (acceptance criterion: '
            '"fails rather than passing by default when '
            'expected build output is missing entirely")',
      );
      final output = '${result.stdout}\n${result.stderr}';
      // The failure message must name the missing artifact so
      // the reader knows §11q has nothing to inspect, rather
      // than discovering it via the "blocking error" summary
      // alone.
      final tellsCause =
          output.contains('iOS artifact') ||
          output.contains('iOS build did not produce') ||
          output.contains('Runner.ipa') ||
          output.contains('build/ios/ipa');
      expect(
        tellsCause,
        isTrue,
        reason:
            'Failure message must name the missing iOS '
            'artifact so the reader knows §11q produced '
            'nothing usable',
      );
    });

    test('GREEN: §11q is satisfied for both DSN shapes — the DSN '
        'value, however it was configured, must appear in the '
        'binary', () async {
      if (!canRun) {
        return;
      }
      // The DSN check should be string-content based, not
      // shape-based. A different DSN value still satisfies
      // the check.
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://otherKey@o123.ingest.sentry.io/456',
      );

      final result = await repo.runGate();

      expect(
        result.exitCode,
        0,
        reason:
            'Gate must pass for any non-empty DSN value '
            'present in the IPA binary',
      );
    });
  });

  group('pre-release gate — §11p iOS build invocation shape', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test('GREEN: workflow uses `flutter build ipa` — §11p passes', () async {
      if (!canRun) {
        return;
      }
      // Sanity: the unmodified workflow must use
      // `flutter build ipa`. If this assertion ever fires,
      // the workflow shape was reverted and the test is
      // testing the wrong thing.
      final preOriginal = await repo.workflow().readAsString();
      expect(
        preOriginal,
        contains('flutter build ipa'),
        reason:
            'Test setup invariant violated: the repo must '
            'already use flutter build ipa. If this fires, '
            'the workflow shape was reverted.',
      );
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      );

      final result = await repo.runGate();

      expect(
        result.exitCode,
        0,
        reason: 'Gate must pass for the post-fix workflow',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        isNot(contains('iOS build must use')),
        reason:
            '§11p failure message must not fire against '
            'the post-fix workflow',
      );
    });

    test('RED: workflow reverts from `flutter build ipa` to '
        'bespoke xcodebuild — §11p fails', () async {
      if (!canRun) {
        return;
      }
      final preOriginal = await repo.workflow().readAsString();
      expect(
        preOriginal,
        contains('flutter build ipa'),
        reason:
            'Sanity: the unmodified workflow must use '
            'flutter build ipa',
      );

      // Replace `flutter build ipa ...` with the old bespoke
      // xcodebuild invocation. The gate must catch the
      // reversion.
      final mutated = preOriginal.replaceFirst(
        RegExp(r'flutter build ipa[^\n]*\n'),
        '          xcodebuild -workspace ios/Runner.xcworkspace '
        '-scheme Runner -configuration Release archive\n',
      );
      expect(
        mutated,
        isNot(equals(preOriginal)),
        reason:
            'Test setup failed: could not replace '
            'flutter build ipa with xcodebuild',
      );
      await repo.workflow().writeAsString(mutated);
      // The bespoke xcodebuild invocation does not have a
      // verified DSN-forwarding path; the IPA must therefore
      // lack the DSN to mirror the regression.
      await repo.writeFakeIpaWithoutDsn();

      final result = await repo.runGate();

      expect(
        result.exitCode,
        1,
        reason:
            'Gate must fail when the iOS build is '
            'reverted to bespoke xcodebuild',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        contains('flutter build ipa'),
        reason:
            'Failure message must name the missing '
            'invocation shape',
      );
    });
  });

  group('pre-release gate — §11n / §11o upload destination '
      'must be exactly `omnitrain`', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test('GREEN: Android SENTRY_PROJECT == omnitrain — §11n passes', () async {
      if (!canRun) {
        return;
      }
      // Sanity: the unmodified workflow has the post-fix value.
      //
      // The block is delimited by the JOB key, not by the build step.
      // SENTRY_PROJECT is declared once at job level so every step
      // inherits it; anchoring this assertion on the build step (as it
      // once did) would miss a correct job-level declaration and fail
      // for the wrong reason. This mirrors how the gate itself parses
      // the workflow — see `extract_workflow_job_block` in
      // `scripts/pre_release_check.sh`.
      final preOriginal = await repo.workflow().readAsString();
      final androidBlockStart = preOriginal.indexOf('\n  android:');
      expect(
        androidBlockStart,
        isNonNegative,
        reason: 'Sanity: Android job must exist',
      );
      final androidBlock = preOriginal.substring(androidBlockStart);
      expect(
        androidBlock,
        contains('SENTRY_PROJECT: omnitrain'),
        reason:
            'Test setup invariant violated: the Android '
            'job must already use SENTRY_PROJECT: omnitrain. '
            'If this fires, the fix was reverted.',
      );
      expect(
        androidBlock,
        isNot(contains('SENTRY_PROJECT: omnitrain-android')),
        reason:
            'Test setup invariant violated: the Android '
            'job must not name a per-platform destination.',
      );
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      );

      final result = await repo.runGate();

      expect(
        result.exitCode,
        0,
        reason:
            'Gate must pass when SENTRY_PROJECT is '
            'exactly omnitrain on Android',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        isNot(contains('Android upload destination is wrong')),
        reason: 'No Android upload-destination WRONG failure should fire',
      );
      expect(
        output,
        contains("Android upload destination is 'omnitrain'"),
        reason: '§11n OK message should announce omnitrain',
      );
    });

    test('RED: Android SENTRY_PROJECT is renamed to omnitrain-android — '
        '§11n fails (the per-platform regression cannot reappear)', () async {
      if (!canRun) {
        return;
      }
      final preOriginal = await repo.workflow().readAsString();
      final mutated = preOriginal.replaceFirst(
        'SENTRY_PROJECT: omnitrain',
        'SENTRY_PROJECT: omnitrain-android',
      );
      expect(
        mutated,
        isNot(equals(preOriginal)),
        reason:
            'Test setup failed: could not reintroduce '
            'the per-platform destination',
      );
      await repo.workflow().writeAsString(mutated);
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      );

      final result = await repo.runGate();

      expect(
        result.exitCode,
        1,
        reason:
            'Gate must fail when Android SENTRY_PROJECT '
            'names anything other than omnitrain',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        contains('Android upload destination'),
        reason: 'Failure message must name the platform',
      );
      expect(
        output,
        contains('omnitrain'),
        reason:
            'Failure message must name the correct value '
            'so the reader knows what to type',
      );
    });

    test('RED: iOS SENTRY_PROJECT is renamed to omnitrain-ios — '
        '§11o fails (the per-platform regression cannot reappear)', () async {
      if (!canRun) {
        return;
      }
      final preOriginal = await repo.workflow().readAsString();
      // The post-fix workflow has SENTRY_PROJECT: omnitrain
      // in both jobs. Replace ONLY the iOS job's value.
      final iosBlockStart = preOriginal.indexOf('name: Build IPA');
      expect(
        iosBlockStart,
        isNonNegative,
        reason: 'Sanity: iOS step must exist',
      );
      final iosBlockEnd = preOriginal.indexOf('name: Build AAB', iosBlockStart);
      final iosBlock = preOriginal.substring(
        iosBlockStart,
        iosBlockEnd == -1 ? preOriginal.length : iosBlockEnd,
      );
      final iosBlockMutated = iosBlock.replaceFirst(
        'SENTRY_PROJECT: omnitrain',
        'SENTRY_PROJECT: omnitrain-ios',
      );
      final mutated = preOriginal.replaceRange(
        iosBlockStart,
        iosBlockEnd == -1 ? preOriginal.length : iosBlockEnd,
        iosBlockMutated,
      );
      expect(
        mutated,
        isNot(equals(preOriginal)),
        reason:
            'Test setup failed: could not reintroduce '
            'the per-platform destination for iOS',
      );
      await repo.workflow().writeAsString(mutated);
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      );

      final result = await repo.runGate();

      expect(
        result.exitCode,
        1,
        reason:
            'Gate must fail when iOS SENTRY_PROJECT '
            'names anything other than omnitrain',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        contains('iOS upload destination'),
        reason: 'Failure message must name the platform',
      );
      expect(
        output,
        contains('omnitrain'),
        reason: 'Failure message must name the correct value',
      );
    });

    test('RED: iOS SENTRY_PROJECT is blank — §11o fails', () async {
      if (!canRun) {
        return;
      }
      final preOriginal = await repo.workflow().readAsString();
      final mutated = preOriginal.replaceFirst(
        'SENTRY_PROJECT: omnitrain',
        'SENTRY_PROJECT: ',
      );
      expect(
        mutated,
        isNot(equals(preOriginal)),
        reason:
            'Test setup failed: could not blank '
            'SENTRY_PROJECT',
      );
      await repo.workflow().writeAsString(mutated);
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      );

      final result = await repo.runGate();

      expect(
        result.exitCode,
        1,
        reason:
            'Gate must fail when iOS SENTRY_PROJECT is '
            'blank',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(output, contains('iOS upload destination'));
    });
  });

  group('pre-release gate — combined crash-reporting section '
      'fails when any single invariant fails', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test('a single failing subcheck fails the gate as a whole '
        '(pre-existing pattern from §11k–§11q)', () async {
      if (!canRun) {
        return;
      }
      // Single defect: iOS IPA lacks the DSN. Every other
      // check passes. The whole gate must fail and the
      // summary must list the failure.
      await repo.writeFakeIpaWithoutDsn();

      final result = await repo.runGate();

      expect(
        result.exitCode,
        1,
        reason:
            'A single failing subcheck must fail the '
            'gate as a whole, matching the §11k–§11q '
            '"single blocking error blocks release" '
            'convention',
      );
      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        contains('blocking error'),
        reason:
            'Summary must surface that the gate has at '
            'least one blocking error',
      );
    });

    test('happy path — gate does not fire the new iOS artifact '
        'checks against the post-fix repo', () async {
      if (!canRun) {
        return;
      }
      await repo.writeFakeIpaWithDsn(
        dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      );

      final result = await repo.runGate();

      final output = '${result.stdout}\n${result.stderr}';
      expect(
        output,
        isNot(contains('iOS reporting destination is absent')),
        reason: 'No iOS reporting-destination failure should fire',
      );
      expect(
        output,
        isNot(contains('iOS build must use')),
        reason: 'No build-invocation-shape failure should fire',
      );
      expect(
        output,
        isNot(contains('Android upload destination is unresolvable')),
        reason: 'No Android upload-destination failure should fire',
      );
      expect(
        output,
        isNot(contains('iOS upload destination is unresolvable')),
        reason: 'No iOS upload-destination failure should fire',
      );
    });
  });
}
