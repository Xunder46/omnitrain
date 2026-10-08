// D-151 — the structural guard for the defect class Phase 1 fixes.
//
// `WorkoutState` and `RoutineState` notify their listeners at the top of their
// loads (`session_core_io.dart:137`, `routine_state.dart:108`), so an `initState`
// that calls one of them asks every listener mounted above the screen to rebuild
// while the framework is still building, which it reports as
// `setState() or markNeedsBuild() called during build`. The fix is always the
// same one (D-150: wait for the frame that mounts the screen); this test makes
// the next occurrence of the shape fail here rather than in the owner's console.
//
// The scan is textual and deliberately narrow: it reads every `initState` under
// `lib/features/`, follows calls into methods declared in the same file, skips
// whatever sits inside `addPostFrameCallback` / `Future.microtask` /
// `Future.delayed`, and flags the notifying methods by name. It can miss an
// indirect call (through a service, or a notify under another name) — the
// scenario tests are the behavioural half, this one catches the shape.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The state methods whose first statements notify their listeners, so calling
/// one of them during a build marks a listener dirty mid-build.
const Set<String> _notifyingMethods = {
  'createNewSession',
  'loadSessionData',
  'loadHistoricalSession',
  'loadRoutines',
  'endSession',
  'resetSessionTimerStart',
};

/// Wrappers that move their body out of the build phase: a call inside them is
/// not a build-phase call.
const List<String> _deferringWrappers = [
  'addPostFrameCallback',
  'Future.microtask',
  'Future.delayed',
  'scheduleMicrotask',
];

/// Keywords that look like a call but are not one.
const Set<String> _notACall = {
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'else',
  'do',
  'try',
  'return',
  'super',
  'assert',
  'case',
  'in',
  'await',
  'is',
  'new',
};

final RegExp _initStateStart = RegExp(r'void\s+initState\s*\(\s*\)\s*\{');
final RegExp _call = RegExp(r'\b([A-Za-z_$][A-Za-z0-9_$]*)\s*\(');
final RegExp _methodStart = RegExp(
  r'\b([A-Za-z_$][A-Za-z0-9_$]*)\s*\([^;{}]*\)\s*(?:async\s*)?\{',
);

/// `path: initState -> _load -> loadSessionData()` for every notifying call a
/// file's `initState` reaches without leaving the build phase.
List<String> findInitStateNotifyViolations(String path, String source) {
  final stripped = _stripLiteralsAndComments(source);
  final start = _initStateStart.firstMatch(stripped);
  if (start == null) return const [];
  final body = _bracedBody(stripped, start.end - 1);
  return [
    for (final call in _reachedNotifyingCalls(
      body: body,
      methods: _methodsIn(stripped),
      path: const ['initState'],
      visited: const {'initState'},
    ))
      '$path: $call',
  ];
}

/// Whether [source] declares an `initState` for the scan to read.
bool hasInitStateToScan(String source) =>
    _initStateStart.hasMatch(_stripLiteralsAndComments(source));

/// The call paths from [body] that end in a notifying method, following calls
/// into [methods] (same-file declarations) without cycles.
List<String> _reachedNotifyingCalls({
  required String body,
  required Map<String, String> methods,
  required List<String> path,
  required Set<String> visited,
}) {
  final violations = <String>[];
  for (final call in _callsIn(_blankDeferredCalls(body))) {
    final callPath = [...path, call];
    if (_notifyingMethods.contains(call)) {
      violations.add('${callPath.join(' -> ')}()');
      continue;
    }
    final nested = methods[call];
    if (nested == null || visited.contains(call) || callPath.length > 6) {
      continue;
    }
    violations.addAll(
      _reachedNotifyingCalls(
        body: nested,
        methods: methods,
        path: callPath,
        visited: {...visited, call},
      ),
    );
  }
  return violations;
}

/// Every method name declared in [text], mapped to its body.
Map<String, String> _methodsIn(String text) {
  final methods = <String, String>{};
  for (final match in _methodStart.allMatches(text)) {
    final name = match.group(1)!;
    if (_notACall.contains(name)) continue;
    methods[name] = _bracedBody(text, match.end - 1);
  }
  return methods;
}

Iterable<String> _callsIn(String text) sync* {
  for (final match in _call.allMatches(text)) {
    final name = match.group(1)!;
    if (_notACall.contains(name)) continue;
    yield name;
  }
}

/// [text] with everything inside the deferring wrappers replaced by spaces.
String _blankDeferredCalls(String text) {
  var result = text;
  for (final wrapper in _deferringWrappers) {
    final marker = RegExp('\\b${RegExp.escape(wrapper)}\\s*\\(');
    while (true) {
      final match = marker.firstMatch(result);
      if (match == null) break;
      final open = result.indexOf('(', match.start);
      final close = _matchingParen(result, open);
      if (close == null) break;
      result = result.replaceRange(open, close + 1, ' ');
    }
  }
  return result;
}

/// The text between the brace at [openIndex] and its match.
String _bracedBody(String text, int openIndex) {
  var depth = 0;
  for (var index = openIndex; index < text.length; index++) {
    if (text[index] == '{') depth++;
    if (text[index] == '}') {
      depth--;
      if (depth == 0) return text.substring(openIndex + 1, index);
    }
  }
  return text.substring(openIndex + 1);
}

int? _matchingParen(String text, int openIndex) {
  var depth = 0;
  for (var index = openIndex; index < text.length; index++) {
    if (text[index] == '(') depth++;
    if (text[index] == ')') {
      depth--;
      if (depth == 0) return index;
    }
  }
  return null;
}

/// [source] with comments removed and string literals blanked, so a name or a
/// brace inside either cannot be read as code.
String _stripLiteralsAndComments(String source) {
  final out = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';
    if (char == '/' && next == '/') {
      while (index < source.length && source[index] != '\n') {
        out.write(' ');
        index++;
      }
      continue;
    }
    if (char == '/' && next == '*') {
      out.write('  ');
      index += 2;
      while (index < source.length) {
        if (source[index] == '*' && index + 1 < source.length) {
          if (source[index + 1] == '/') {
            out.write('  ');
            index += 2;
            break;
          }
        }
        out.write(source[index] == '\n' ? '\n' : ' ');
        index++;
      }
      continue;
    }
    if (char == "'" || char == '"') {
      out.write(' ');
      index++;
      while (index < source.length && source[index] != char) {
        if (source[index] == r'\') {
          out.write('  ');
          index += 2;
          continue;
        }
        out.write(' ');
        index++;
      }
      if (index < source.length) {
        out.write(' ');
        index++;
      }
      continue;
    }
    out.write(char);
    index++;
  }
  return out.toString();
}

void main() {
  group('initStateNotifyContractTest', () {
    const badFixture = '''
class _BadState extends State<Bad> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.workoutState.loadSessionData();
  }
}
''';
    const goodFixture = '''
class _GoodState extends State<Good> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    await widget.workoutState.loadSessionData();
  }
}
''';

    test('the scan flags a direct notifying call and accepts the deferred shape', () {
      expect(
        findInitStateNotifyViolations('bad_screen.dart', badFixture),
        ['bad_screen.dart: initState -> _load -> loadSessionData()'],
        reason:
            'an `initState` that reaches a notifying state method without leaving the build phase '
            'is the defect this contract exists for',
      );
      expect(
        findInitStateNotifyViolations('good_screen.dart', goodFixture),
        isEmpty,
        reason:
            'the same load inside `addPostFrameCallback` runs after the frame, which is the fix '
            '(D-150)',
      );
      expect(
        findInitStateNotifyViolations('no_init_state.dart', goodFixture),
        isEmpty,
      );
    });

    test('no initState under lib/features notifies a state during build', () {
      final files = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final violations = <String>[];
      final scannedInitStates = <String>[];
      for (final file in files) {
        final source = file.readAsStringSync();
        if (hasInitStateToScan(source)) scannedInitStates.add(file.path);
        violations.addAll(findInitStateNotifyViolations(file.path, source));
      }

      expect(
        scannedInitStates.length,
        greaterThan(5),
        reason: 'the scan reads the real tree: lib/features holds many initStates',
      );
      if (violations.isNotEmpty) {
        fail(
          'an `initState` calls a state method that notifies its listeners before it yields:\n'
          '${violations.join('\n')}\n'
          'A listener mounted above the screen cannot be marked dirty while the frame is '
          'building, so the framework reports `setState() or markNeedsBuild() called during '
          'build`. Defer the first load to the frame that mounts the screen (D-150):\n'
          '  WidgetsBinding.instance.addPostFrameCallback((_) {\n'
          '    if (mounted) _load();\n'
          '  });\n'
          'Rule: docs/global_conventions.md, "No state notification during the build phase".',
        );
      }
    });
  });
}
