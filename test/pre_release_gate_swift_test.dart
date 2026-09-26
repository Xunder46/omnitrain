// The pre-release gate runs the watchOS package's suite (`swift test` in
// `watch/watchos`) and blocks on a red one.
//
// Plan: `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
// (Stats PR 2), Phase 6 — D-144.
// Scenario mapping:
//   S-293 the gate runs `swift test` → `S-293 ...`
//
// The gate is exercised as the other gate suites exercise it: the repository
// is copied to a temporary directory and `scripts/pre_release_check.sh` runs
// there. Stand-ins for `flutter`, `swift` and `uname` go first on its PATH, so
// the run never re-enters this test suite, needs no real toolchain, and can
// play a Mac or not on any host. The `swift` stand-in records every directory
// it was asked to test in.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _repoRoot = '.';

/// The gate's line for a check that passed, failed, or was skipped.
const String _passed = '✓  watchOS package suite passed';
const String _failed = '✗  swift test failed in watch/watchos';
const String _skippedFast = '⚠  Skipping swift test for watch/watchos (--fast)';
const String _skippedHost = '⚠  swift test for watch/watchos SKIPPED';

class _GateRun {
  _GateRun(this.result, this.testedIn);

  final ProcessResult result;

  /// Every directory the `swift` stand-in was asked to `swift test` in.
  final List<String> testedIn;

  String get out => '${result.stdout}';

  /// The gate's closing list of blocking errors, or '' when there is none.
  String get failedChecks {
    final at = out.indexOf('Failed checks:');
    return at < 0 ? '' : out.substring(at);
  }
}

class _Gate {
  _Gate._(this._parent, this.repo, this._shims);

  final Directory _parent;
  final String repo;
  final Directory _shims;

  static Future<_Gate> create() async {
    final parent = Directory.systemTemp.createTempSync('omnitrain_gate_swift_');
    final repo = '${parent.path}/repo';
    final copied = await Process.run('rsync', <String>[
      '-a',
      for (final skip in const [
        '.git',
        '.dart_tool',
        'build',
        '.build',
        'ios/Pods',
        'ios/.symlinks',
        'ios/Flutter/Flutter.framework',
        'ios/Flutter/ephemeral',
        'macos/Pods',
        'macos/Flutter/Flutter.framework',
        'macos/Flutter/ephemeral',
        '.venv',
        '.claude',
        '.idea',
      ]) ...['--exclude', skip],
      '$_repoRoot/',
      repo,
    ]);
    if (copied.exitCode != 0) {
      throw StateError('rsync failed: ${copied.stderr}');
    }

    final shims = Directory('${parent.path}/shims')..createSync();
    void shim(String name, String body) {
      final file = File('${shims.path}/$name')
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', file.path]);
    }

    // `flutter analyze` and `flutter test` pass at once: this suite is about
    // the step after them, and a real `flutter test` here would re-enter it.
    shim('flutter', 'echo "stand-in flutter \$*"\nexit 0');
    shim('swift', r'''
if [ "$1" = "--version" ]; then
  [ "$STANDIN_SWIFT_TOOLCHAIN" = "none" ] && exit 1
  echo "Swift version (stand-in)"
  exit 0
fi
if [ "$1" = "test" ]; then
  pwd >> "$STANDIN_SWIFT_LOG"
  if [ "$STANDIN_SWIFT_RESULT" = "fail" ]; then
    echo "Executed 3 tests, with 1 failure (0 unexpected)"
    exit 1
  fi
  echo "Executed 3 tests, with 0 failures (0 unexpected)"
  exit 0
fi
exit 2''');
    shim('uname', r'''
if [ "$1" = "-s" ]; then
  echo "${STANDIN_UNAME:-Darwin}"
  exit 0
fi
exec /usr/bin/uname "$@"''');
    return _Gate._(parent, repo, shims);
  }

  Future<_GateRun> run({
    bool fast = false,
    String swiftResult = 'pass',
    String toolchain = 'present',
    String host = 'Darwin',
  }) async {
    final log = File('${_parent.path}/swift-test-dirs.log');
    if (log.existsSync()) log.deleteSync();
    final result = await Process.run(
      'bash',
      <String>[
        '$repo/scripts/pre_release_check.sh',
        if (fast) '--fast',
        '--all',
      ],
      workingDirectory: repo,
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${_shims.path}:${Platform.environment['PATH']}',
        'PRE_RELEASE_GATE_FAKE_BUILD': 'ok',
        'PRE_RELEASE_GATE_FAKE_IP_BUILD': 'ok',
        'STANDIN_SWIFT_LOG': log.path,
        'STANDIN_SWIFT_RESULT': swiftResult,
        'STANDIN_SWIFT_TOOLCHAIN': toolchain,
        'STANDIN_UNAME': host,
      },
    );
    return _GateRun(
      result,
      log.existsSync() ? log.readAsLinesSync() : const <String>[],
    );
  }

  Future<void> dispose() => _parent.delete(recursive: true);
}

void main() {
  group('S-293 the pre-release gate runs swift test', () {
    late _Gate gate;

    setUpAll(() async {
      gate = await _Gate.create();
    });

    tearDownAll(() async {
      await gate.dispose();
    });

    test('S-293 the gate runs swift test in watch/watchos, and a green suite '
        'passes the step', () async {
      final run = await gate.run();

      expect(run.testedIn, [
        '${Directory(gate.repo).resolveSymbolicLinksSync()}/watch/watchos',
      ], reason: 'S-293 swift test runs once, in the watchOS package');
      expect(run.out, contains(_passed), reason: 'S-293 the step passes');
      expect(
        run.failedChecks,
        isNot(contains('swift test')),
        reason: 'S-293 a green suite is not a blocking error',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'S-293 a red swift test blocks the release',
      () async {
        final run = await gate.run(swiftResult: 'fail');

        expect(run.testedIn, hasLength(1), reason: 'S-293 the suite ran');
        expect(run.out, contains(_failed), reason: 'S-293 the step fails');
        expect(
          run.failedChecks,
          contains('swift test failed in watch/watchos'),
          reason: 'S-293 the red suite is one of the blocking errors',
        );
        expect(
          run.result.exitCode,
          1,
          reason: 'S-293 a blocking error fails the gate',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('S-293 a Mac with no usable Swift toolchain skips the step with a '
        'warning', () async {
      final run = await gate.run(toolchain: 'none');

      expect(run.testedIn, isEmpty, reason: 'S-293 nothing was tested');
      expect(
        run.out,
        contains(_skippedHost),
        reason: 'S-293 the skip is logged',
      );
      expect(
        run.failedChecks,
        isNot(contains('swift test')),
        reason: 'S-293 a skip is not a blocking error',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'S-293 a host that is not a Mac skips the step with a warning',
      () async {
        final run = await gate.run(host: 'Linux');

        expect(run.testedIn, isEmpty, reason: 'S-293 nothing was tested');
        expect(
          run.out,
          contains(_skippedHost),
          reason: 'S-293 the skip is logged',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'S-293 --fast skips the step, and says so',
      () async {
        final run = await gate.run(fast: true);

        expect(run.testedIn, isEmpty, reason: 'S-293 --fast runs no suite');
        expect(
          run.out,
          contains(_skippedFast),
          reason: 'S-293 the skip is logged',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
