// filepath: test/docs_indexing_contract_test.dart
//
// Automated validation of the agent documentation set in
// `.github/agents/docs/`.
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
// This test walks the docs tree and fails the build on either.
//
// The ceiling
// -----------
// `_maxDocBytes` is 64 KiB. See the note on that constant for what is and is
// not known about the real limit, and how to tighten it.
//
// This test reads only documentation. It touches no application source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Root of the agent documentation set.
const String _docsRoot = '.github/agents/docs';

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

Iterable<File> _markdownFiles() sync* {
  final dir = Directory(_docsRoot);
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.md')) yield entity;
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
            'current. Unbuilt ideas belong in .github/agents/plans/.\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
