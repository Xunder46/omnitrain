// Contract test: rest is a count-up, on every device, for good.
//
// Rule: `docs/global_conventions.md`, "Rest rule: rest is a count-up".
// Plan: `docs/plans/2026-10-08-18b-watch-rest-count-up-plan` (D-160, D-164,
// D-168).
//
// The owner, on why this is a test and not a paragraph: OmniTrain doesn't have
// such a thing as a rest timer with a preset value; rest always starts from
// zero and ticks up until you start the next set. A preset rest length or a
// rest countdown is cheap to write and easy to miss in review, so it is caught
// here, mechanically, instead of in a review that a language model writes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the rule is written down, in the words the validators already use.
const String restRuleWhere =
    'docs/global_conventions.md, "Rest rule: rest is a count-up"';

/// The trees, and the documents, that may not plan a rest, count a rest down,
/// or hold a stored rest length.
///
/// The routine prescription (`lib/data/models`, `lib/features/routine`,
/// `lib/state/routine`, `lib/core/models`, `docs/my_routines.md`) is
/// deliberately absent: a routine's `restSeconds` is a prescription read when a
/// routine is set up, never a timer (D-168, S-168).
///
/// The app target is here because it is where the branch that picks the whole
/// wrist surface lives (`ios/OmniTrain Watch App/ContentView.swift`), and the
/// documents are the ones this change edited (minus `docs/plans/**`, which is
/// history and freely quotes what it retired).
const List<String> restRuleRoots = [
  'lib/watch',
  'lib/state/watch',
  'lib/core/sync_protocol',
  'watch/watchos/Sources',
  'watch/sync_protocol/schemas',
  'ios/OmniTrain Watch App',
  'docs/README.md',
  'docs/global_conventions.md',
  'docs/rest_tracking.md',
  'docs/watch_session_sync.md',
  'docs/state_management/watch_surface.md',
  'docs/watch-app-setup-and-qa.md',
  'docs/theme_and_settings.md',
  'docs/modality_based_exercise_ui.md',
];

/// A stored rest length under any spelling, including `restCountdown`.
final RegExp _restCountdownWording = RegExp(
  r'rest[\s_-]*countdown|countdown[\s_-]*rest|'
  r'rest[\s_-]*remaining|remaining[\s_-]*rest',
  caseSensitive: false,
);

/// A stored rest length, under any of the spellings it comes back as.
///
/// `restSeconds`/`rest_seconds`, `restLengthMs`, `restDurationMs`/
/// `restDurationSeconds`, `defaultRestSeconds`/`defaultRestMs` and
/// `kRestSeconds`/`kRestMs` are one field under six names: a preset rest length
/// a rest row, a routine step or a default would carry. Case-insensitive, so a
/// constant's `REST_SECONDS` is caught too (F4).
final RegExp _restLengthSpelling = RegExp(
  r'rest_?seconds|rest_?duration_?(?:ms|seconds)|rest_?length_?ms|'
  r'default_?rest_?(?:seconds|ms)|krest\w*(?:seconds|ms)',
  caseSensitive: false,
);

/// The words that *deny* a rest countdown.
///
/// A document whose subject is the rule has to name what it forbids — the rule
/// itself, the contract's restatement, the QA walkthrough's reminder — so a
/// prose line is a finding only when neither it nor the line before it denies
/// one. The rest of the allow-list is kept and unchanged: the validators'
/// refusal text and the schema's conditional are never flagged at all, because
/// they name `plannedDurationMs` (not a rest-length spelling) and the
/// conditional is what `restSchemaFindings` requires to be there; the routine
/// prescription is out of scope by root.
final RegExp _deniesRestLength = RegExp(
  r'\bno\b|\bnot\b|\bnever\b|\bnone\b|forbid|refus|reject|fail|count-?up',
  caseSensitive: false,
);

/// Every way [content] breaks the rest rule, as human-readable findings.
///
/// [path] is the repository-relative path; it appears in the findings only.
/// Prose (`.md`) is read for rest-countdown wording only — the documents that
/// state the rule, and the routine prescription they define, have to be able to
/// name `restSeconds` in order to say it is a prescription, never a timer
/// (D-168); what prose must never do is describe a rest as a remaining time.
/// Code is held to the tokens themselves, under every spelling.
List<String> restCountUpFindings(String path, String content) {
  final findings = <String>[];
  final lines = content.split('\n');
  final prose = path.endsWith('.md');

  for (var i = 0; i < lines.length; i++) {
    final number = i + 1;
    // A sentence wraps, so a denial on the line before the match still governs
    // it (`docs/rest_tracking.md:20-21`).
    if (prose && _deniesRestLength.hasMatch(lines[i])) continue;
    if (prose && i > 0 && _deniesRestLength.hasMatch(lines[i - 1])) continue;

    final spelling = prose ? null : _restLengthSpelling.firstMatch(lines[i]);
    if (spelling != null) {
      findings.add(
        '$path:$number names `${spelling[0]}`: a stored rest length is a preset '
        'rest length',
      );
    }
    if (_restCountdownWording.hasMatch(lines[i])) {
      findings.add(
        '$path:$number counts a rest down: a rest is a count-up, never a '
        'remaining time',
      );
    }
  }

  for (final (number, call) in _startTimerCalls(lines)) {
    final startsARest = call.contains('WatchTimerKind.rest');
    if (startsARest && call.contains('plannedDurationMs')) {
      findings.add(
        '$path:$number starts a rest with `plannedDurationMs`: a rest has no '
        'length to plan',
      );
    }
  }

  return findings;
}

/// The `startTimer(...)` call opened on each line that opens one.
///
/// A call spans its arguments, so the kind and a plan can sit on different
/// lines of the same statement; a line-by-line scan would miss the pair. The
/// parentheses are counted from the call's own `(` so a nested call inside an
/// argument cannot end the statement early.
Iterable<(int, String)> _startTimerCalls(List<String> lines) sync* {
  for (var i = 0; i < lines.length; i++) {
    final open = lines[i].indexOf('startTimer(');
    if (open < 0) continue;

    final call = StringBuffer();
    var depth = 0;
    for (var j = i; j < lines.length && j <= i + 12; j++) {
      final text = lines[j];
      call.writeln(text);
      for (
        var k = j == i ? open + 'startTimer'.length : 0;
        k < text.length;
        k++
      ) {
        if (text[k] == '(') depth++;
        if (text[k] == ')') depth--;
      }
      if (depth <= 0) break;
    }
    yield (i + 1, call.toString());
  }
}

/// Every way the shared envelope schema stops refusing a planned length on a
/// rest, given the decoded schema.
///
/// The refusal is the exception the rest rule allows: the schema names
/// `plannedDurationMs` in order to forbid it for `kind == "rest"`, and it has
/// to keep the property defined so the other timer kinds can carry one (D-164).
List<String> restSchemaFindings(Map<String, Object?> schema) {
  final findings = <String>[];
  final timer = _map(_map(schema['\$defs'])?['timer']);
  if (timer == null) {
    return [
      'the envelope schema has no `\$defs.timer` to refuse a rest length',
    ];
  }

  final properties = _map(timer['properties']);
  if (properties?['plannedDurationMs'] == null) {
    findings.add(
      '`\$defs.timer` defines no `plannedDurationMs`: the round, hold and '
      'elapsed timers need one',
    );
  }

  final kinds = (_list(_map(properties?['kind'])?['enum']) ?? const [])
      .whereType<String>();
  if (!kinds.contains('rest')) {
    findings.add('`\$defs.timer.properties.kind.enum` no longer lists `rest`');
  }

  final condition = _map(timer['if']);
  final isRest =
      _map(_map(condition?['properties'])?['kind'])?['const'] == 'rest';
  if (!isRest) {
    findings.add(
      '`\$defs.timer.if` no longer keys the guard on `kind == "rest"`',
    );
  }

  final then = _map(timer['then']);
  final refused = _list(_map(then?['not'])?['required']) ?? const [];
  if (then?['not'] == null || !refused.contains('plannedDurationMs')) {
    findings.add(
      '`\$defs.timer.then.not.required` no longer refuses `plannedDurationMs`, '
      'so the wire accepts a rest length again',
    );
  }

  final restTimer = _map(
    _map(_map(_map(schema['\$defs'])?['timers'])?['properties'])?['rest'],
  );
  final referencesTimer = (_list(restTimer?['oneOf']) ?? const []).any(
    (entry) => _map(entry)?['\$ref'] == '#/\$defs/timer',
  );
  if (!referencesTimer) {
    findings.add('`\$defs.timers.rest` no longer uses `\$defs.timer`');
  }

  return findings;
}

Map<String, Object?>? _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<Object?>? _list(Object? value) => value is List ? value : null;

String _why(List<String> findings) =>
    '''
Rest is a count-up: it runs from the moment a set is logged to the moment the
next set starts, and nothing stores, sends, shows, counts down or alarms a rest
length. That is $restRuleWhere; the decisions are D-160 (the wrist), D-164
(the wire) and D-168 (a routine's `restSeconds` is a prescription, never a
timer) in
docs/plans/2026-10-08-18b-watch-rest-count-up-plan.

The owner's words, because this keeps coming back: OmniTrain doesn't have such a
thing as a rest timer with a preset value; rest always starts from zero and
ticks up until you start the next set.

Do not add a preset rest length or a rest countdown; if you think the product
needs one, ask the owner.

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

void main() {
  group('restIsCountUpContract', () {
    test('S-166 the scanner flags a stored rest length and a planned rest', () {
      expect(
        restCountUpFindings(
          'lib/watch/session/example.dart',
          'const restSeconds = 90;\n',
        ),
        hasLength(1),
        reason: 'a stored rest length is the preset value the rule forbids',
      );
      expect(
        restCountUpFindings(
          'lib/watch/session/example.dart',
          'await _engine.startTimer(\n'
              '  WatchTimerKind.rest,\n'
              '  plannedDurationMs: 90 * 1000,\n'
              ');\n',
        ),
        hasLength(1),
        reason: 'a rest is started with no length at all',
      );
      expect(
        restCountUpFindings(
          'lib/watch/session/example.dart',
          'await _engine.startTimer(WatchTimerKind.rest);\n',
        ),
        isEmpty,
        reason: 'the rest timer record itself is not the regression',
      );
    });

    test(
      'S-166 the scanner flags rest-countdown wording under any spelling',
      () {
        for (final wording in [
          'rest countdown',
          'rest-countdown',
          'restCountdown',
          'countdown rest',
          'countdown-rest',
          'rest remaining',
          'remaining rest time',
        ]) {
          expect(
            restCountUpFindings('lib/watch/session/example.dart', '$wording\n'),
            hasLength(1),
            reason: '"$wording" describes a rest as a remaining time',
          );
        }
      },
    );

    test('S-166 the scanner flags a stored rest length under any spelling', () {
      for (final spelling in [
        'restSeconds',
        'rest_seconds',
        'REST_SECONDS',
        'restLengthMs',
        'rest_length_ms',
        'restDurationMs',
        'restDurationSeconds',
        'defaultRestSeconds',
        'defaultRestMs',
        'kRestSeconds',
        'kRestMs',
      ]) {
        expect(
          restCountUpFindings(
            'lib/watch/session/example.dart',
            'final $spelling = 90;\n',
          ),
          hasLength(1),
          reason: '`$spelling` is a stored rest length under another name',
        );
      }
    });

    test('S-166 the scan reaches the app target and the documents, and prose '
        'is held to the countdown wording', () {
      expect(
        restRuleRoots,
        containsAll(<String>[
          'ios/OmniTrain Watch App',
          'docs/global_conventions.md',
          'docs/rest_tracking.md',
          'docs/watch_session_sync.md',
          'docs/state_management/watch_surface.md',
          'docs/watch-app-setup-and-qa.md',
        ]),
        reason: 'the app target picks the surface; the docs carried the '
            'countdown prose this change removed',
      );
      for (final root in restRuleRoots) {
        expect(
          FileSystemEntity.typeSync(root),
          isNot(FileSystemEntityType.notFound),
          reason: '$root has to exist, or the scan skips it in silence',
        );
      }

      expect(
        restCountUpFindings(
          'docs/watch_session_sync.md',
          'The rest countdown shows how much rest is left.\n',
        ),
        hasLength(1),
        reason: 'a document describing a rest as a remaining time is exactly '
            'the regression S-166 predicted',
      );
      for (final denial in [
        'There is no rest countdown and no rest alarm anywhere.\n',
        'the contract test fails if a scanned tree\n'
            'reintroduces a rest length or a rest countdown.\n',
        'A routine\'s stored `restSeconds` is a prescription, never a timer.\n',
      ]) {
        expect(
          restCountUpFindings('docs/rest_tracking.md', denial),
          isEmpty,
          reason: 'the allow-list: prose that denies a rest countdown is the '
              'rule stating itself, and the prescription may be named',
        );
      }
    });

    test('S-166 a round countdown and a round plan are not this rule\'s', () {
      expect(
        restCountUpFindings(
          'lib/watch/logging/example.dart',
          'await _engine.startTimer(\n'
              '  WatchTimerKind.round,\n'
              '  plannedDurationMs: (length * 1000).round(),\n'
              ');\n',
        ),
        isEmpty,
        reason: 'a round has a planned length and a countdown of its own',
      );
      expect(
        restCountUpFindings(
          'lib/watch/logging/example.dart',
          '// The round countdown fires a milestone an hour in.\n',
        ),
        isEmpty,
        reason: 'round wording is not rest wording',
      );
    });

    test('S-166 no scanned file plans a rest, counts one down or stores a '
        'rest length', () {
      final findings = <String>[];
      for (final file in _scannedFiles()) {
        findings.addAll(
          restCountUpFindings(file.path, file.readAsStringSync()),
        );
      }
      expect(findings, isEmpty, reason: _why(findings));
    });

    test(
      'S-166 the envelope schema still refuses a planned length on a rest',
      () {
        final file = File('watch/sync_protocol/schemas/envelope.schema.json');
        final schema =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

        expect(restSchemaFindings(schema), isEmpty, reason: _why(const []));

        final withoutGuard =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        ((withoutGuard['\$defs'] as Map)['timer'] as Map).remove('then');

        expect(
          restSchemaFindings(withoutGuard),
          isNotEmpty,
          reason:
              'dropping the conditional has to be caught: it is the refusal',
        );
      },
    );

    test('S-166 both validators still refuse a planned length on a rest', () {
      final sites = {
        'lib/core/sync_protocol/message_validator.dart': "timers?['rest']",
        'watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift':
            'timers["rest"]',
      };

      for (final entry in sites.entries) {
        final source = File(entry.key).readAsStringSync();
        expect(
          source,
          contains(entry.value),
          reason:
              'the refusal is the only reason this file may speak of a rest '
              'length at all',
        );
        expect(source, contains('plannedDurationMs'), reason: _why(const []));
      }
    });

    test('S-168 the routine prescription keeps `restSeconds` and is not '
        'scanned', () {
      expect(
        File('lib/data/models/models.dart').readAsStringSync(),
        contains('restSeconds'),
        reason: 'a routine\'s Rest duration is a prescription, not a timer',
      );
      for (final root in restRuleRoots) {
        expect(
          root.startsWith('lib/data') ||
              root.contains('features/routine') ||
              root.contains('state/routine') ||
              root.startsWith('lib/core/models'),
          isFalse,
          reason: 'the routine prescription is out of scope (D-168)',
        );
      }
    });
  });
}

/// Every file under [restRuleRoots]: a listed document whole, and the `.dart`
/// and `.swift` files of a source tree.
Iterable<File> _scannedFiles() sync* {
  for (final root in restRuleRoots) {
    if (FileSystemEntity.isFileSync(root)) {
      yield File(root);
      continue;
    }
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (entity.path.split('/').any((segment) => segment.startsWith('.'))) {
        continue;
      }
      if (entity.path.endsWith('.dart') || entity.path.endsWith('.swift')) {
        yield entity;
      }
    }
  }
}
