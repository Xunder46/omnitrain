// filepath: test/docs_indexing_contract_test.dart
//
// Automated validation of the agent documentation set in
// `docs/`.
//
// Why this exists
// ---------------
// These documents are the source of truth that planning and implementation
// agents read before doing work. They are only useful if they can actually be
// retrieved. Two failure modes make a document unreachable even though it is
// present in the repository:
//
//   1. **Oversized files.** The tools that index this folder skip any single
//      file above a per-file byte ceiling. Before the 2026-07-26 docs audit,
//      `widget_catalog.md` was ~95 KB and its tail was silently unretrievable.
//      Content that cannot be found is functionally the same as content that
//      was never written.
//   2. **Broken or orphaned links.** A page nothing links to, or a link that
//      resolves to nothing, is a dead end for an agent following references.
//
//   3. **Stale names and restated values.** A doc that names a symbol the code
//      no longer declares, or repeats a number the theme owns, is read as
//      authoritative and is wrong (plan 30, E-3 and E-4).
//
// This test walks the docs tree and fails the build on either.
//
// The ceiling
// -----------
// `_maxDocBytes` is 64 KiB. See the note on that constant for what is and is
// not known about the real limit, and how to tighten it.
//
// This test reads the documentation set and the declarations in `lib/` it
// names. It touches no application source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/dart_source_scan.dart';

/// Root of the agent documentation set.
const String _docsRoot = 'docs';

/// Hard per-file ceiling, in bytes, for any Markdown file under [_docsRoot].
///
/// 64 KiB is the assumed per-file indexing ceiling for the tools that serve
/// this folder to agents. It is an **assumption**: the exact limit of the
/// consuming indexer was never recorded in this repository, and the audit that
/// added this test could not establish it from any in-repo source.
///
/// If your indexer uses a lower bound, lower this number — every current file
/// is comfortably beneath it, so tightening is cheap. Do not raise it to make
/// a failing file pass; split the file instead, as
/// `widget_catalog.md` and `state_management.md` were split, keeping the
/// original path as an index page so inbound links keep resolving.
const int _maxDocBytes = 64 * 1024;

/// Warning band. A file above this fraction of the ceiling still passes, but
/// is close enough that the next substantial edit would breach it. Kept as a
/// separate, softer signal so the build does not break on a near-miss.
const double _warnFraction = 0.80;

/// Subfolders of [_docsRoot] that hold working records rather than the
/// documentation set: plans (with their evidence and review files), release
/// notes and agent memories. They are not indexed, size-limited or held to
/// the content prohibitions.
const List<String> _recordFolders = ['plans', 'releases', 'memories'];

/// Owner-facing files in [_docsRoot] that are not part of the indexed
/// documentation set: the unbuilt-ideas list and the manual watch setup guide.
const List<String> _recordFiles = ['future-work.md', 'watch-app-setup-and-qa.md'];

bool _isRecord(File file) =>
    _recordFolders.any(
      (folder) => file.path.startsWith('$_docsRoot/$folder/'),
    ) ||
    _recordFiles.any((name) => file.path == '$_docsRoot/$name');

Iterable<File> _markdownFiles() sync* {
  final dir = Directory(_docsRoot);
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.md') && !_isRecord(entity)) {
      yield entity;
    }
  }
}

/// Strips fenced code blocks so link-like text inside a code sample is not
/// mistaken for a real Markdown link.
String _stripCodeFences(String content) =>
    content.replaceAll(RegExp(r'```[\s\S]*?```'), '');

/// The single document permitted to discuss visual presentation at all, per
/// `documentation_standard.md` §6.1. Its exemption covers visual *rules* only —
/// it is still forbidden from carrying colour values, which is why the hex
/// guard below asserts it contains none either.
const String _designSystemDoc = '$_docsRoot/design_system.md';

/// Frozen records under `history/`, plus dated audit records, are exempt from
/// the content prohibitions (standard §7). They deliberately preserve what was
/// true at a past moment and must not be edited to conform.
bool _isFrozenRecord(File file) =>
    file.path.contains('$_docsRoot/history/') ||
    RegExp(r'docs-audit-\d{4}-\d{2}-\d{2}\.md$').hasMatch(file.path);

/// The standard itself quotes the patterns it bans, so pattern guards would
/// always fire on it. Exempting it keeps the guards honest rather than forcing
/// the standard to describe its own rules obliquely.
bool _isStandardItself(File file) =>
    file.path.endsWith('$_docsRoot/documentation_standard.md');

/// Files subject to the content guards below.
Iterable<File> _guardedFiles() =>
    _markdownFiles().where((f) => !_isFrozenRecord(f) && !_isStandardItself(f));

// ── Symbol and value guards (plan 30, E-3 and E-4) ──────────────────────────
//
// The whole point of the docs set is that an agent can trust a name it reads
// there. E-3 makes a name the code no longer declares fail the build; E-4 keeps
// the values that belong to `lib/core/constants/omni_theme.dart` from creeping
// back into prose (documentation standard 3.4).

/// The design documents the guards below cover. The
/// `design_system_shared_pieces.md` split is listed for the day it lands; a
/// missing file is skipped rather than failed.
const List<String> _designDocs = <String>[
  '$_docsRoot/design_system.md',
  '$_docsRoot/design_system_shared_pieces.md',
  '$_docsRoot/widget_catalog.md',
];

/// The design documents that exist today: [_designDocs] plus every page of the
/// widget catalog split.
List<File> _designDocFiles() {
  final files = <File>[];
  for (final path in _designDocs) {
    final file = File(path);
    if (file.existsSync()) files.add(file);
  }
  final catalog = Directory('$_docsRoot/widget_catalog');
  if (!catalog.existsSync()) return files;
  for (final entity in catalog.listSync(followLinks: false)) {
    if (entity is File && entity.path.endsWith('.md')) files.add(entity);
  }
  return files;
}

/// [content] with every fenced code block's non-newline characters blanked.
///
/// A code sample keeps its line numbers — so a reported `doc:line` still points
/// at the right line — but is not read as prose: E-4 ignores fenced blocks, and
/// a fence is not an inline-code span either.
String _blankCodeFences(String content) => content.replaceAllMapped(
  RegExp(r'```[\s\S]*?```'),
  (match) => match.group(0)!.replaceAll(RegExp(r'[^\n]'), ''),
);

/// An inline-code span, `` `...` ``. Markdown inline code carries no newline.
final RegExp _inlineCodePattern = RegExp(r'`([^`\n]+)`');

/// An `OmniXxx` name (E-3).
final RegExp _omniNamePattern = RegExp(r'\bOmni[A-Z]\w*');

/// An `OmniTheme.<member>` reference (E-3).
final RegExp _omniThemeMemberPattern = RegExp(r'\bOmniTheme\.([A-Za-z_]\w*)');

/// The names every `class`, `enum`, `mixin` or `typedef` declaration gives in
/// `lib/`, `lib/watch/` included: a wrist widget is still declared there.
Set<String> _libDeclarationNames() {
  final pattern = RegExp(r'\b(?:class|enum|mixin|typedef)\s+([A-Za-z0-9_]+)');
  final names = <String>{};
  for (final file in dartSourcesUnder(
    const ['lib'],
    excludedPrefixes: const <String>[],
  )) {
    names.addAll(
      pattern
          .allMatches(blankLiteralsAndComments(file.source))
          .map((match) => match.group(1)!),
    );
  }
  return names;
}

/// The single file that declares the theme tokens the design docs name (E-3).
const String _omniThemeFile = 'lib/core/constants/omni_theme.dart';

/// The member names `lib/core/constants/omni_theme.dart` declares: a typed
/// field (`static const double x = …`), a getter (`static X get y =>`) or a
/// method (`static X z(…)`).
///
/// A spelling check, not a parse: [docSymbolFindings] only needs to know
/// whether the token a doc names is still declared there.
Set<String> _omniThemeMemberNames() {
  final source = blankLiteralsAndComments(
    File(_omniThemeFile).readAsStringSync(),
  );
  final pattern = RegExp(
    r'\bget\s+([A-Za-z_]\w*)\b|'
    r'\b[A-Za-z_]\w*(?:<[^(){}]*>)?\s+([A-Za-z_]\w*)\s*(?:=|=>|\()',
  );
  final names = <String>{};
  for (final match in pattern.allMatches(source)) {
    names.add(match.group(1) ?? match.group(2)!);
  }
  return names;
}

/// The 1-based line of [index] in [content].
int _lineOf(String content, int index) {
  var line = 1;
  for (var i = 0; i < index && i < content.length; i++) {
    if (content.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// Every `OmniXxx` name and `OmniTheme.<member>` [content] names in inline code
/// that neither [libNames] nor [themeMembers] declares, as `doc:line name`
/// (E-3).
///
/// Fenced code blocks and a bare `Omni` are not namings. A name has to sit
/// inside backticks, so a path such as `lib/widgets/layout/omni_surface.dart`
/// is prose about a file, not a claim about a symbol.
List<String> docSymbolFindings(
  String doc,
  String content, {
  required Set<String> libNames,
  required Set<String> themeMembers,
}) {
  final prose = _blankCodeFences(content);
  final findings = <String>[];

  for (final span in _inlineCodePattern.allMatches(prose)) {
    final text = span.group(1)!;
    final start = span.start + 1;

    for (final name in _omniNamePattern.allMatches(text)) {
      final symbol = name.group(0)!;
      // `OmniTheme.buttonBorderRadius` is one naming, and the member loop below
      // owns it: reporting the qualifier as well would double-count.
      final qualified =
          name.end < text.length && text.codeUnitAt(name.end) == 0x2E;
      if (qualified && symbol == 'OmniTheme') continue;
      if (libNames.contains(symbol)) continue;
      findings.add('$doc:${_lineOf(prose, start + name.start)} $symbol');
    }

    for (final member in _omniThemeMemberPattern.allMatches(text)) {
      final name = member.group(1)!;
      if (themeMembers.contains(name)) continue;
      findings.add(
        '$doc:${_lineOf(prose, start + member.start)} OmniTheme.$name',
      );
    }
  }

  return findings;
}

/// A measurement value in prose: a number with a `dp`, `px`, `ms` or `pt` unit,
/// or a percentage (E-4, documentation standard 3.4). A test id (`S-3003`)
/// carries no unit, so it never matches.
final RegExp _docValuePattern = RegExp(
  r'\b\d+(?:\.\d+)?\s?(?:dp|px|ms|pt)\b|\b\d+(?:\.\d+)?%',
);

/// Every measurement value in [content], as `doc:line value` (E-4).
List<String> docValueFindings(String doc, String content) {
  final prose = _blankCodeFences(content);
  return <String>[
    for (final match in _docValuePattern.allMatches(prose))
      '$doc:${_lineOf(prose, match.start)} ${match.group(0)!.trim()}',
  ];
}

String _symbolsWhy(List<String> findings) =>
    '''
A design document names a symbol the code no longer declares, so an agent that
reads the doc goes looking for something that is not there. The documents are
the source of truth for planning and implementation, and a name in them is a
claim about `lib/`.

Fix the document (rename or delete the mention) or restore the declaration; what
must not happen is the doc and the code disagreeing in silence.

Findings (doc:line name):
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _valuesWhy(List<String> findings) =>
    '''
A measurement in prose is a second source of truth: it stays behind when the
token it describes changes, and it still reads as authoritative
(documentation standard 3.4). Geometry, durations and percentages live in
`lib/core/constants/omni_theme.dart`; a doc names the token and its role.

Fix the document by naming the token instead of the number.

Findings (doc:line value):
${findings.map((finding) => '  · $finding').join('\n')}
''';

void main() {
  group('Docs indexing contract', () {
    test('the docs root exists and contains Markdown', () {
      final files = _markdownFiles().toList();
      expect(
        files,
        isNotEmpty,
        reason:
            'No Markdown found under $_docsRoot. Either the docs set moved '
            'or this test is pointing at the wrong directory.',
      );
    });

    test('no documentation file exceeds the indexing ceiling', () {
      final oversized = <String>[];

      for (final file in _markdownFiles()) {
        final bytes = file.lengthSync();
        if (bytes > _maxDocBytes) {
          oversized.add(
            '${file.path}: $bytes bytes '
            '(${(bytes / 1024).toStringAsFixed(1)} KiB) — over the '
            '${_maxDocBytes ~/ 1024} KiB ceiling by '
            '${bytes - _maxDocBytes} bytes',
          );
        }
      }

      expect(
        oversized,
        isEmpty,
        reason:
            'Documentation files above the ${_maxDocBytes ~/ 1024} KiB '
            'per-file indexing ceiling are silently skipped by the tools that '
            'serve these docs to agents — the content is present but '
            'unreachable.\n'
            'Fix by splitting the file into part pages under a '
            'same-named subdirectory and turning the original path into an '
            'index that links to them, so inbound links keep resolving. See '
            '$_docsRoot/widget_catalog.md for the pattern.\n'
            'Do NOT raise _maxDocBytes to make this pass.\n'
            'Offending files:\n${oversized.join('\n')}',
      );
    });

    test('no documentation file is within the warning band of the ceiling', () {
      final threshold = (_maxDocBytes * _warnFraction).round();
      final nearLimit = <String>[];

      for (final file in _markdownFiles()) {
        final bytes = file.lengthSync();
        if (bytes > threshold && bytes <= _maxDocBytes) {
          nearLimit.add(
            '${file.path}: $bytes bytes '
            '(${(bytes / _maxDocBytes * 100).toStringAsFixed(0)}% of ceiling)',
          );
        }
      }

      expect(
        nearLimit,
        isEmpty,
        reason:
            'These files are above '
            '${(_warnFraction * 100).toStringAsFixed(0)}% of the '
            '${_maxDocBytes ~/ 1024} KiB ceiling. They still index today, but '
            'the next substantial edit would push them over. Split them now '
            'rather than after they become unreachable.\n'
            '${nearLimit.join('\n')}',
      );
    });

    test('every relative link resolves to a file that exists', () {
      final broken = <String>[];
      // [label](target) — target up to '#' or ')'.
      final linkPattern = RegExp(r'\[[^\]]*\]\(([^)#]+?)(?:#[^)]*)?\)');

      for (final file in _markdownFiles()) {
        final content = _stripCodeFences(file.readAsStringSync());
        final baseDir = file.parent.path;

        for (final match in linkPattern.allMatches(content)) {
          final target = match.group(1)!.trim();
          if (target.startsWith('http://') ||
              target.startsWith('https://') ||
              target.startsWith('mailto:')) {
            continue;
          }
          final resolved = File(Uri.file('$baseDir/$target').toFilePath());
          final resolvedPath = resolved.absolute.uri
              .normalizePath()
              .toFilePath();
          if (!File(resolvedPath).existsSync() &&
              !Directory(resolvedPath).existsSync()) {
            broken.add('${file.path} -> $target');
          }
        }
      }

      expect(
        broken,
        isEmpty,
        reason:
            'Broken relative links in the docs set. An agent following one of '
            'these reaches nothing.\n${broken.join('\n')}',
      );
    });

    test('every doc page is reachable from another doc page', () {
      // A page nothing links to will not be found by an agent navigating from
      // the index, even when it indexes cleanly on its own.
      final all = _markdownFiles().toList();
      final linkPattern = RegExp(r'\[[^\]]*\]\(([^)#]+?)(?:#[^)]*)?\)');

      final linkedTargets = <String>{};
      for (final file in all) {
        final content = _stripCodeFences(file.readAsStringSync());
        final baseDir = file.parent.path;
        for (final match in linkPattern.allMatches(content)) {
          final target = match.group(1)!.trim();
          if (target.startsWith('http')) continue;
          final resolvedPath = File(
            Uri.file('$baseDir/$target').toFilePath(),
          ).absolute.uri.normalizePath().toFilePath();
          linkedTargets.add(resolvedPath);
        }
      }

      final orphans = <String>[];
      for (final file in all) {
        // README is the entry point; nothing is expected to link to it.
        if (file.path.endsWith('$_docsRoot/README.md')) continue;
        final self = file.absolute.uri.normalizePath().toFilePath();
        if (!linkedTargets.contains(self)) orphans.add(file.path);
      }

      expect(
        orphans,
        isEmpty,
        reason:
            'These doc pages are not linked from any other doc page, so an '
            'agent starting at the index will never reach them. Add a link '
            'from the index or from the relevant feature doc.\n'
            '${orphans.join('\n')}',
      );
    });

    // ── Content guards ──────────────────────────────────────────────────────
    //
    // These assert the ABSENCE of prohibited prose patterns. They never assert
    // that a document says anything, so they cannot go false when the app
    // changes — the same property that justifies the structural checks above.
    //
    // They catch the mechanical cases only. Control inventories, copied code,
    // and restated numerics are not detectable by pattern and remain the
    // reviewer's job (see `.github/agents/code-reviewer.agent.md`).

    test('no document carries a hexadecimal colour literal', () {
      // Colour values live in lib/core/constants/omni_theme.dart and nowhere
      // else. A hex literal in prose is a second source of truth that no test
      // guards — and one previously drifted to six wrong values while still
      // reading as authoritative.
      final hex = RegExp(r'#[0-9A-Fa-f]{6}\b|0x[0-9A-Fa-f]{8}\b');
      final offenders = <String>[];

      for (final file in _guardedFiles()) {
        final lines = _stripCodeFences(file.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (hex.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Hexadecimal colour literals found in documentation. Colour values '
            'belong to lib/core/constants/omni_theme.dart alone; docs name the '
            'token and its role, never its value.\n'
            'This applies to design_system.md too — its exemption covers '
            'visual RULES, not values (standard 6.1).\n'
            '${offenders.join('\n')}',
      );
    });

    test('design_system.md exists and is itself hex-free', () {
      // Guarded explicitly: the exemption in 6.1 is the most likely one to be
      // misread as blanket permission, and the file above is skipped by no
      // filter — so this asserts the intent directly rather than by omission.
      final file = File(_designSystemDoc);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '$_designSystemDoc is the single owner of visual rules. If it moved, '
            'update this test and standard 6.1 together.',
      );
      expect(
        RegExp(
          r'#[0-9A-Fa-f]{6}\b',
        ).hasMatch(_stripCodeFences(file.readAsStringSync())),
        isFalse,
        reason:
            '$_designSystemDoc contains a hex colour literal. Its exemption is '
            'from visual-presentation RULES only; values are still prohibited.',
      );
    });

    test('no document carries a step-by-step flow walkthrough', () {
      // Numbered "User Workflow" headings and arrow chains describing user
      // actions are the largest prohibited category and the one most likely to
      // creep back, because they read as helpful while going stale silently.
      //
      // The arrow rule is deliberately narrowed to chains that also name a
      // user action. An arrow alone is not a walkthrough — state machines
      // (`notStarted → active ⇄ paused → finished`), type hierarchies,
      // fallback orders, and signature notation all use arrows legitimately
      // and are exactly the structural content this standard wants kept.
      // Widening this to every arrow would delete the invariants worth having.
      final userAction = RegExp(
        r'\b(tap|taps|tapping|swipe|press|click|select|selects|choose|'
        r'chooses|user|enters?|navigates?)\b',
        caseSensitive: false,
      );
      final arrowChain = RegExp(r'(→|->).*(→|->)');
      final flowHeading = RegExp(
        r'^#{1,6}\s+(\d+\.\s*)?(user\s+)?(work)?flows?\b',
        caseSensitive: false,
      );
      final offenders = <String>[];

      for (final file in _guardedFiles()) {
        final lines = _stripCodeFences(file.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (flowHeading.hasMatch(line)) {
            offenders.add(
              '${file.path}:${i + 1}: flow heading — ${line.trim()}',
            );
          } else if (arrowChain.hasMatch(line) && userAction.hasMatch(line)) {
            offenders.add(
              '${file.path}:${i + 1}: user-action arrow chain — ${line.trim()}',
            );
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Step-by-step flow walkthroughs found in documentation. Behaviour '
            'belongs in a test that fails when it goes false; the document '
            'should point at that test instead of narrating the steps.\n'
            '${offenders.join('\n')}',
      );
    });

    test('no document carries a scheduling or roadmap annotation', () {
      // Extends the Part A scheduling guard to the roadmap headings that
      // produced the same failure: a planned item ships, nobody deletes the
      // entry, and the doc now asserts a shipped feature does not exist.
      final phrases = <RegExp>[
        RegExp(r'scheduled,\s*not\s*current', caseSensitive: false),
        RegExp(r'\bnot yet implemented\b', caseSensitive: false),
        RegExp(r'\bwill be (removed|added|replaced)\b', caseSensitive: false),
      ];
      final headings = <RegExp>[
        RegExp(
          r'^#{1,6}\s+.*\b(future enhancements?|planned features?|roadmap|'
          r'phase\s*[23]|still deferred|recommended extension points|'
          r'known inconsistencies)\b',
          caseSensitive: false,
        ),
      ];
      final offenders = <String>[];

      for (final file in _guardedFiles()) {
        final lines = _stripCodeFences(file.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final hit =
              headings.any((r) => r.hasMatch(line)) ||
              phrases.any((r) => r.hasMatch(line));
          if (hit) offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Roadmap or scheduled-change content found in documentation. '
            'Every such annotation in this repository has eventually inverted, '
            'labelling shipped behaviour as upcoming and removed behaviour as '
            'current. Unbuilt ideas belong in docs/plans/.\n'
            '${offenders.join('\n')}',
      );
    });

    test('the symbol scan flags an Omni name and an OmniTheme member that no '
        'declaration answers', () {
      const libNames = <String>{'OmniSurface'};
      const members = <String>{'buttonBorderRadius'};

      expect(
        docSymbolFindings(
          'docs/design_system.md',
          'Cards are built by `OmniSurfacez` (see below).',
          libNames: libNames,
          themeMembers: members,
        ),
        contains('docs/design_system.md:1 OmniSurfacez'),
      );
      expect(
        docSymbolFindings(
          'docs/design_system.md',
          'Geometry comes from `OmniTheme.buttonUtilityRadiusz`.',
          libNames: libNames,
          themeMembers: members,
        ),
        contains('docs/design_system.md:1 OmniTheme.buttonUtilityRadiusz'),
      );
      expect(
        docSymbolFindings(
          'docs/design_system.md',
          'Use `OmniSurface` and `OmniTheme.buttonBorderRadius`, both on\n'
              'line two.\n'
              '```\n'
              'A sample naming `OmniSurfacez` and '
              '`OmniTheme.buttonUtilityRadiusz`.\n'
              '```\n'
              'A path such as `lib/widgets/layout/omni_surface.dart` is prose.\n',
          libNames: libNames,
          themeMembers: members,
        ),
        isEmpty,
        reason: 'declared names pass, a fence is not prose and a path is not a '
            'symbol',
      );
    });

    test('every Omni symbol the design docs name is declared in lib/', () {
      final docs = _designDocFiles();
      expect(
        docs,
        isNotEmpty,
        reason: 'the design docs have to exist, or the scan passes in silence',
      );

      final libNames = _libDeclarationNames();
      final themeMembers = _omniThemeMemberNames();
      final findings = <String>[];
      for (final file in docs) {
        findings.addAll(
          docSymbolFindings(
            file.path,
            file.readAsStringSync(),
            libNames: libNames,
            themeMembers: themeMembers,
          ),
        );
      }

      expect(findings, isEmpty, reason: _symbolsWhy(findings));
    });

    test('the value scan flags a unit value and a percentage, and skips a fence '
        'and a test id', () {
      expect(
        docValueFindings('docs/design_system.md', 'The row is 12 dp tall.'),
        contains('docs/design_system.md:1 12 dp'),
      );
      expect(
        docValueFindings('docs/design_system.md', 'The fade takes 180ms.'),
        contains('docs/design_system.md:1 180ms'),
      );
      expect(
        docValueFindings('docs/design_system.md', 'The track is 100% wide.'),
        contains('docs/design_system.md:1 100%'),
      );
      expect(
        docValueFindings(
          'docs/design_system.md',
          'Covered by S-3003 and the group `S-2601 button shape`.\n'
              '```\n'
              'A sample with 12 dp, 180ms and 100% in it.\n'
              '```\n',
        ),
        isEmpty,
        reason: 'a test id carries no unit and a fenced block is not prose',
      );
    });

    test('no design doc carries a unit value or a percentage', () {
      final docs = _designDocFiles();
      expect(
        docs,
        isNotEmpty,
        reason: 'the design docs have to exist, or the scan passes in silence',
      );

      final findings = <String>[];
      for (final file in docs) {
        findings.addAll(docValueFindings(file.path, file.readAsStringSync()));
      }

      expect(findings, isEmpty, reason: _valuesWhy(findings));
    });
  });
}
