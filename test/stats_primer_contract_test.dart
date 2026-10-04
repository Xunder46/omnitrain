import 'dart:io';

import 'package:test/test.dart';

/// Static-source guards for the Stats primer (S-2715).
///
/// These read the tree off disk, so they run once rather than once per
/// repository harness. They are structural: they make impossible the
/// regressions the rest of the feature's tests cannot see from the outside.
void main() {
  List<File> dartFilesUnder(String directory) {
    return Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  test('the Stats primer key is written in exactly one file', () {
    final holders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.readAsStringSync().contains('primer_seen_stats')) {
        holders.add(file.path);
      }
    }

    expect(holders, ['lib/state/stats/stats_primer_state.dart']);
  });

  test('the Home screen\'s primer state stays optional and nullable', () {
    final source = File(
      'lib/features/home/home_screen.dart',
    ).readAsStringSync();

    expect(source, contains('StatsPrimerState? statsPrimerState'));
  });

  test('the Stats screen holds no StatsPrimerState', () {
    // Comments are dropped first: the screen legitimately *mentions* the state
    // in a doc comment to say it holds none, and that mention is not a
    // dependency. What must not come back is a real reference.
    final code = File('lib/features/stats/stats_screen.dart')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    expect(code, contains('bool showPrimerHelp'));
    expect(code, isNot(contains('StatsPrimerState')));
    expect(code, isNot(contains('stats_primer_state.dart')));
  });

  test('no unfinished-feature wording reaches the Stats feature', () {
    // (i) Substring scan across the whole Stats feature: any of these anywhere
    // (including comments) is drafting residue that should not ship.
    const featureBanned = <String>[
      'still building',
      'coming soon',
      'unfinished',
    ];
    final offenders = <String>[];
    for (final directory in ['lib/features/stats', 'lib/state/stats']) {
      for (final file in dartFilesUnder(directory)) {
        final lower = file.readAsStringSync().toLowerCase();
        for (final banned in featureBanned) {
          if (lower.contains(banned)) {
            offenders.add('${file.path}: $banned');
          }
        }
      }
    }
    expect(offenders, isEmpty);

    // (ii) Whole-word scan of the user-facing copy only. "gate", "window" and
    // "load baseline" are legitimate English elsewhere in the feature's
    // internal comments (e.g. "navigate", a time "window"), so restricting
    // this to the sheet file — the one place the words would reach a user —
    // keeps the guard honest instead of banning ordinary vocabulary.
    const copyBanned = <String>[
      'gate',
      'window',
      'load baseline',
      'still building',
      'coming soon',
      'unfinished',
    ];
    final sheet = File(
      'lib/features/stats/widgets/stats_primer_sheet.dart',
    ).readAsStringSync();
    final copyOffenders = <String>[
      for (final banned in copyBanned)
        if (RegExp('\\b$banned\\b', caseSensitive: false).hasMatch(sheet))
          banned,
    ];
    expect(copyOffenders, isEmpty);
  });
}
