// Source-scan helpers for the UI-standards guards.
//
// Plan: `docs/plans/2026-10-13-26-ui-rule-breaks-plan` (D-26.5). The guards in
// `test/ui_standards_contract_test.dart` read `lib/` as text — no build, no
// widget pump — so a rule about *how* a constructor is called is checked over
// every call site, not only the ones a test happens to render.
//
// Pure Dart on purpose: no `flutter_test`, so the helper can be unit-tested and
// reused without a binding.

import 'dart:io';

/// A `.dart` file and its source, read once.
class DartSourceFile {
  const DartSourceFile(this.path, this.source);

  /// Repository-relative path, e.g. `lib/features/calendar/calendar_screen.dart`.
  final String path;

  final String source;
}

/// Every `.dart` file under [roots], repository-relative paths, sorted.
///
/// [excludedPrefixes] drops whole trees. The default drops `lib/watch/`: the
/// watchOS surface has its own component set, so the phone's component rules
/// do not reach it.
List<DartSourceFile> dartSourcesUnder(
  List<String> roots, {
  List<String> excludedPrefixes = const ['lib/watch/'],
}) {
  final files = <DartSourceFile>[];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart')) continue;
      if (excludedPrefixes.any(path.startsWith)) continue;
      if (path.split('/').any((segment) => segment.startsWith('.'))) continue;
      files.add(DartSourceFile(path, entity.readAsStringSync()));
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// One constructor call: `Name(` or `Name.member(`.
class ConstructorCall {
  const ConstructorCall({
    required this.line,
    required this.openIndex,
    required this.text,
    required this.code,
  });

  /// 1-based line of the opening `(`.
  final int line;

  /// Index of the opening `(` in the source it was found in.
  final int openIndex;

  /// The call text, from the opening `(` through its matching `)`.
  final String text;

  /// The same slice with the contents of strings and comments blanked, so
  /// `code.contains('shape')` is about code and not about a `Text('shape')`.
  final String code;
}

/// The 1-based line number of the character at [index].
int lineNumberAt(String source, int index) {
  var line = 1;
  final end = index < source.length ? index : source.length;
  for (var i = 0; i < end; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// [source] with the contents of string literals and comments blanked out —
/// same length, same newlines, quotes and comment markers replaced by spaces.
///
/// Both comment forms (`//`, nested `/* */`), both quote forms, triple quotes
/// and the `r'...'` raw prefix are understood. Blanking is what makes a
/// *literal*, a *comment* and a *substring of another identifier* invisible to
/// the constructor search while code stays in place.
String blankLiteralsAndComments(String source) {
  final out = StringBuffer();
  var i = 0;

  while (i < source.length) {
    final c = source[i];

    if (c == '/' && _charAt(source, i + 1) == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }

    if (c == '/' && _charAt(source, i + 1) == '*') {
      var depth = 0;
      while (i < source.length) {
        if (source[i] == '/' && _charAt(source, i + 1) == '*') {
          depth++;
          out.write('  ');
          i += 2;
          continue;
        }
        if (source[i] == '*' && _charAt(source, i + 1) == '/') {
          depth--;
          out.write('  ');
          i += 2;
          if (depth == 0) break;
          continue;
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    if (c == "'" || c == '"') {
      final triple =
          _charAt(source, i + 1) == c && _charAt(source, i + 2) == c;
      final quote = _quotes(c, triple ? 3 : 1);
      final raw = _isRawStringPrefix(source, i);
      i += quote.length;
      out.write(quote);
      while (i < source.length) {
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          out.write('  ');
          i += 2;
          continue;
        }
        if (source.startsWith(quote, i)) {
          out.write(quote);
          i += quote.length;
          break;
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    out.write(c);
    i++;
  }

  return out.toString();
}

/// The text of the call that opens at [openParen] — the index of its `(` —
/// through the `)` that closes it.
///
/// Parentheses inside string literals and comments do not count. [mask] is the
/// [blankLiteralsAndComments] result for [source], passed in only so a file is
/// blanked once rather than once per call site.
String balancedCallText(String source, int openParen, {String? mask}) {
  final scanned = mask ?? blankLiteralsAndComments(source);
  var depth = 0;
  for (var i = openParen; i < scanned.length; i++) {
    final c = scanned[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(openParen, i + 1);
    }
  }
  return source.substring(openParen);
}

/// Every `[name](...)` / `[name].member(...)` constructor call in [source].
///
/// [excludedMembers] are the dot-reached helpers that are not constructor
/// calls: `FilledButton.styleFrom(...)` styles a button, it does not create
/// one.
///
/// A name inside a comment, a string literal, or a longer identifier
/// (`_buildTextButton(`) is not a call of that name.
List<ConstructorCall> constructorCalls(
  String source,
  String name, {
  Set<String> excludedMembers = const {'styleFrom', 'themeStyleOf', 'lerp'},
}) {
  final mask = blankLiteralsAndComments(source);
  final pattern = RegExp('${RegExp.escape(name)}(\\.[A-Za-z0-9_]+)?\\(');
  final calls = <ConstructorCall>[];

  for (final match in pattern.allMatches(mask)) {
    if (match.start > 0 &&
        RegExp(r'[A-Za-z0-9_$.]').hasMatch(mask[match.start - 1])) {
      continue;
    }
    final member = match.group(1);
    if (member != null && excludedMembers.contains(member.substring(1))) {
      continue;
    }
    final open = match.end - 1;
    calls.add(
      ConstructorCall(
        line: lineNumberAt(mask, open),
        openIndex: open,
        text: balancedCallText(source, open, mask: mask),
        code: balancedCallText(mask, open, mask: mask),
      ),
    );
  }

  return calls;
}

String _charAt(String source, int index) =>
    index < 0 || index >= source.length ? '' : source[index];

String _quotes(String quote, int length) =>
    List<String>.filled(length, quote).join();

/// `r'...'`: the raw prefix is one quote back, and not the tail of an
/// identifier (`var r = 'x';` is not a raw string).
bool _isRawStringPrefix(String source, int quoteIndex) {
  final previous = _charAt(source, quoteIndex - 1);
  if (previous != 'r' && previous != 'R') return false;
  final before = _charAt(source, quoteIndex - 2);
  if (before.isEmpty) return true;
  return !RegExp(r'[A-Za-z0-9_$]').hasMatch(before);
}
