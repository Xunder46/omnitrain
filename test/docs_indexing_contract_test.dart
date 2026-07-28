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
          final resolvedPath = resolved.absolute.uri.normalizePath().toFilePath();
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
          final resolvedPath = File(Uri.file('$baseDir/$target').toFilePath())
              .absolute
              .uri
              .normalizePath()
              .toFilePath();
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
  });
}
