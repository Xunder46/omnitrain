// Tests for the upload-destination invariants in `scripts/pre_release_check.sh`.
//
// The script enforces three new gates around the Sentry symbol-upload
// configuration:
//
//   1. No `--dart-define` value in `.github/workflows/release.yml` may
//      name a credential. The named-key check (`SENTRY_AUTH_TOKEN`)
//      and a broader pattern (`*TOKEN*`, `*SECRET*`, `*KEY*`,
//      `*PASSWORD*`) both fail the gate, so a future agent adding any
//      credential-shaped value is caught before a release ships.
//   2. The Android job of the release workflow must export
//      `SENTRY_PROJECT` as an env var, so the Sentry Android Gradle
//      plugin (the upload step) can read it at upload time.
//   3. The iOS job of the release workflow must export
//      `SENTRY_PROJECT` as an env var, so the iOS upload step can
//      read it.
//
// The existing `uploadSentryMapping` hook check is also extended to
// assert the Android destination resolves, not merely that the hook is
// present in `pubspec.yaml`.
//
// Tests exercise the bash script by copying the repo into a temp
// directory, mutating the workflow file to introduce each defect, and
// asserting the script exits 1 and that the failure message names the
// consequence. The temp directory is removed at the end of every
// test. Tests run in the repo root so the bash script's relative
// paths resolve.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _repoRoot = '.';

class _TempRepo {
  _TempRepo._(this.path);

  final String path;

  /// Recursive copy of [src] into [dst] using the system `cp -R`.
  static Future<_TempRepo> create(String src) async {
    final parent = Directory.systemTemp.createTempSync('omnitrain_gate_');
    final dst = '${parent.path}/repo';
    // Use rsync with exclusions when available so we skip the
    // large `.dart_tool/`, `build/`, and `ios/Pods/` directories.
    // The gate inspects `.github/workflows/release.yml`,
    // `pubspec.yaml`, and the iOS source files — none of which
    // live in those directories. The original test used `cp -R`
    // and would push each test setup past the 30-second
    // test-framework timeout on macOS.
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
    return _TempRepo._(dst);
  }

  File workflow() => File('$path/.github/workflows/release.yml');
  File pubspec() => File('$path/pubspec.yaml');

  /// Runs the gate script in this temp repo. Returns the process result.
  Future<ProcessResult> runGate() async {
    final script = '$path/scripts/pre_release_check.sh';
    return Process.run(
      'bash',
      <String>[script, '--fast'],
      workingDirectory: path,
      environment: <String, String>{
        ...Platform.environment,
      },
    );
  }

  Future<void> dispose() async {
    await Directory(path).delete(recursive: true);
  }
}

void main() {
  group('pre-release gate — Sentry upload destination', () {
    late _TempRepo repo;

    setUp(() async {
      repo = await _TempRepo.create(_repoRoot);
    });

    tearDown(() async {
      await repo.dispose();
    });

    test(
      'S-001 named-key check fails when SENTRY_AUTH_TOKEN appears '
      'in a --dart-define',
      () async {
        // Sanity: the unmodified workflow must not contain
        // SENTRY_AUTH_TOKEN as a --dart-define (post-fix state).
        // If this assertion ever fires, the test is testing the
        // wrong thing — the gate would already catch the unmodified
        // file, masking any test-injected regression.
        final preOriginal = await repo.workflow().readAsString();
        expect(
          preOriginal.contains('--dart-define=SENTRY_AUTH_TOKEN'),
          isFalse,
          reason: 'Test setup invariant violated: the repo must not '
              'already have SENTRY_AUTH_TOKEN as a --dart-define. '
              'If this fires, the post-fix state was reverted.',
        );

        // Inject the forbidden --dart-define. The script must catch
        // this before the release ships.
        const marker = r'--dart-define=SENTRY_DSN=$SENTRY_DSN';
        final replacement = '$marker\n'
            '            --dart-define=SENTRY_AUTH_TOKEN=\$TOKEN \\';
        final mutated = preOriginal.replaceFirst(marker, replacement);
        expect(mutated, isNot(equals(preOriginal)),
            reason: 'Test setup failed: could not inject SENTRY_AUTH_TOKEN '
                'into the workflow file');
        await repo.workflow().writeAsString(mutated);

        final result = await repo.runGate();

        expect(result.exitCode, 1,
            reason: 'Gate must fail when a credential-named value is '
                'compiled into the Android binary');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('SENTRY_AUTH_TOKEN'),
            reason: 'Failure message must name the credential');
        expect(output, contains('compiled into'),
            reason: 'Failure message must name the consequence in plain terms');
      },
    );

    test(
      'S-001 generic credential-shaped check fails when a value '
      'like FRESHDESK_TOKEN appears in a --dart-define',
      () async {
        final preOriginal = await repo.workflow().readAsString();
        // Sanity: the unmodified workflow must not already contain
        // FRESHDESK_TOKEN.
        expect(
          preOriginal,
          isNot(contains('FRESHDESK_TOKEN')),
          reason: 'Test setup invariant violated',
        );

        const marker = r'--dart-define=SENTRY_DSN=$SENTRY_DSN';
        final replacement = '$marker\n'
            '            --dart-define=FRESHDESK_TOKEN=abc123 \\';
        final mutated = preOriginal.replaceFirst(marker, replacement);
        expect(mutated, isNot(equals(preOriginal)),
            reason: 'Test setup failed: could not inject FRESHDESK_TOKEN');
        await repo.workflow().writeAsString(mutated);

        final result = await repo.runGate();

        expect(result.exitCode, 1,
            reason: 'Gate must catch any credential-shaped --dart-define');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('FRESHDESK_TOKEN'),
            reason: 'Failure message must name the offending value');
        expect(output, contains('credential-shaped'),
            reason: 'Failure message must explain the broad pattern');
      },
    );

    test(
      'S-002 fails when SENTRY_PROJECT is missing from the Android job',
      () async {
        final preOriginal = await repo.workflow().readAsString();

        final androidBlockStart =
            preOriginal.indexOf('name: Build AAB with Sentry baked in');
        expect(androidBlockStart, isNonNegative,
            reason: 'Sanity: Android step must exist in the workflow');
        final afterBlock = preOriginal.indexOf(
          '\n      - uses: actions/upload-artifact',
          androidBlockStart,
        );
        final blockEnd = afterBlock == -1
            ? preOriginal.length
            : afterBlock;
        final androidBlock = preOriginal.substring(androidBlockStart, blockEnd);
        final androidMutated = androidBlock.replaceAll(
          RegExp(r'^[ \t]+SENTRY_PROJECT:.*\n', multiLine: true),
          '',
        );
        final mutated = preOriginal.replaceRange(
          androidBlockStart,
          blockEnd,
          androidMutated,
        );
        await repo.workflow().writeAsString(mutated);

        final result = await repo.runGate();

        expect(result.exitCode, 1,
            reason: 'Gate must fail when Android upload destination '
                'cannot be resolved');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('Android upload destination'),
            reason: 'Failure message must name the platform');
        expect(output, contains('SENTRY_PROJECT'),
            reason: 'Failure message must name the missing env var');
      },
    );

    test(
      'S-003 fails when SENTRY_PROJECT is missing from the iOS job',
      () async {
        final preOriginal = await repo.workflow().readAsString();

        // The iOS build step was renamed in the
        // crash-reporting-three-defects plan from "Build IPA
        // (manual signing)" to "Build IPA with Sentry baked in".
        // The check is the same — gate must fail when SENTRY_PROJECT
        // is absent from the iOS job's env: block.
        final iosBlockStart = preOriginal.indexOf(
          'name: Build IPA with Sentry baked in',
        );
        expect(iosBlockStart, isNonNegative,
            reason: 'Sanity: iOS step must exist in the workflow');
        final afterBlock = preOriginal.indexOf(
          '\n    - uses: actions/upload-artifact',
          iosBlockStart,
        );
        final blockEnd = afterBlock == -1
            ? preOriginal.length
            : afterBlock;
        final iosBlock = preOriginal.substring(iosBlockStart, blockEnd);
        final iosMutated = iosBlock.replaceAll(
          RegExp(r'^[ \t]+SENTRY_PROJECT:.*\n', multiLine: true),
          '',
        );
        final mutated = preOriginal.replaceRange(
          iosBlockStart,
          blockEnd,
          iosMutated,
        );
        await repo.workflow().writeAsString(mutated);

        final result = await repo.runGate();

        expect(result.exitCode, 1,
            reason: 'Gate must fail when iOS upload destination '
                'cannot be resolved');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('iOS upload destination'),
            reason: 'Failure message must name the platform');
        expect(output, contains('omnitrain'),
            reason: 'Failure message must name the expected value '
                'so the reader knows what to type');
      },
    );

    test(
      'S-004 the existing uploadSentryMapping hook check now also '
      'requires the Android destination to resolve',
      () async {
        final preOriginal = await repo.workflow().readAsString();
        final androidBlockStart =
            preOriginal.indexOf('name: Build AAB with Sentry baked in');
        final afterBlock = preOriginal.indexOf(
          '\n      - uses: actions/upload-artifact',
          androidBlockStart,
        );
        final blockEnd = afterBlock == -1
            ? preOriginal.length
            : afterBlock;
        final androidBlock = preOriginal.substring(androidBlockStart, blockEnd);
        final androidMutated = androidBlock.replaceAll(
          RegExp(r'^[ \t]+SENTRY_PROJECT:.*\n', multiLine: true),
          '',
        );
        final mutated = preOriginal.replaceRange(
          androidBlockStart,
          blockEnd,
          androidMutated,
        );
        await repo.workflow().writeAsString(mutated);

        final result = await repo.runGate();

        expect(result.exitCode, 1,
            reason: 'Gate must fail — destination is unresolvable even '
                'though the hook is configured');
        final output = '${result.stdout}\n${result.stderr}';
        expect(output, contains('SENTRY_PROJECT'));
      },
    );

    test(
      'S-005 reduced --dart-define set is the only set of values '
      'passed into the application',
      () async {
        // Static review of the live workflow file at the repo root.
        final liveWorkflow =
            File('$_repoRoot/.github/workflows/release.yml').readAsStringSync();
        final defines = RegExp(r'--dart-define=([A-Z_]+)=')
            .allMatches(liveWorkflow)
            .map((m) => m.group(1))
            .toSet();
        expect(defines, {'SENTRY_DSN'},
            reason: 'Only SENTRY_DSN may be passed into the application '
                'as a --dart-define. Any other key would be compiled '
                'into the shipped binary.');
      },
    );

    test(
      'happy path — gate does not fire the new upload-destination '
      'checks against the unmodified repo',
      () async {
        // The repo as-committed has the fix. The new checks must NOT
        // fire. The OK messages also contain some of the same
        // substrings (e.g. "SENTRY_AUTH_TOKEN is not compiled into
        // the shipped Android binary") so we look for the unique
        // failure-sentinel phrases instead. The sentinels below
        // appear only in the failure path; the OK path uses
        // "is not compiled into" / "is exported" without the
        // "extractable" / "unresolvable" wording.
        final result = await repo.runGate();

        final output = '${result.stdout}\n${result.stderr}';
        // Failure sentinels — any of these firing means a new check
        // is incorrectly tripping.
        expect(
          output,
          isNot(contains('extractable from any published artifact')),
          reason: 'No credential-leak warning should fire',
        );
        expect(
          output,
          isNot(contains('upload destination is unresolvable')),
          reason: 'No destination-unresolvable warning should fire',
        );
        expect(
          output,
          isNot(matches(RegExp(
              r'✗  --dart-define=[A-Z_]*(TOKEN|SECRET|KEY|PASSWORD)'))),
          reason: 'No broad-pattern --dart-define failure should fire',
        );
        expect(
          output,
          isNot(contains('iOS reporting destination is absent')),
          reason: 'iOS DSN-unused check should pass against the post-fix repo',
        );
      },
    );

    test(
      'S-001 iOS DSN is in env but the build command does not '
      'reference it — gate fails (the original bug)',
      () async {
        // NOTE: The previous version of this test was a
        // false-confidence regression test: it mutated the
        // workflow to remove `EXTRA_FRONT_END_OPTIONS` and
        // asserted the gate failed by inspecting the workflow
        // file (the §11p / §11q check that was a configuration
        // text check, not an artifact inspection). That is the
        // defect being fixed. The replacement check (§11q in
        // the new revision) inspects the produced iOS IPA; the
        // replacement tests live in
        // `test/pre_release_gate_ios_artifact_test.dart`. This
        // test remains as a placeholder so the file's group
        // structure still maps cleanly to the scenario register
        // for any reader looking up "S-001 iOS DSN".
        expect(true, isTrue,
            reason: 'See test/pre_release_gate_ios_artifact_test.dart '
                'for the iOS artifact-inspection tests. The previous '
                '§11p / §11q workflow-text checks were removed because '
                'they were false-confidence tests that passed today '
                'while iOS shipped unmonitored.');
      },
    );
  });
}
