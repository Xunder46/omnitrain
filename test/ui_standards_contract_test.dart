// Contract tests: the UI standards the app already wrote down.
//
// Plan: `docs/plans/2026-10-13-26-ui-rule-breaks-plan` — S-2601 (button
// shape), S-2603 (no raw `Card(`), S-2604 (no raw colours), S-2606 (every
// `IconButton` has a tooltip), S-2607 (`Colors.white`/`Colors.black` ratchet).
// `docs/plans/2026-10-13-27-ui-messages-plan` — S-2702 (no raw message bar
// outside the two files that own a look), S-2703 (no exception interpolated
// into a message).
// `docs/plans/2026-10-13-30-ui-standards-enforcement-plan` — S-3001 (the
// hand-built sheet and hand-built dialog ratchets).
// The rules themselves live in `docs/design_system.md`; the reasons are D-26.1
// to D-26.8 and D-27.1 to D-27.5 in those plans' Decision Ledgers.
//
// These are source scans, not widget tests (D-26.5): a rule about how a
// constructor is *called* has to hold at every call site, in every screen, and
// a rule that only holds where a test happens to render is a rule that comes
// back. Reading `lib/` as text is what makes the guard complete.
//
// `lib/watch/` is out of scope: the wrist surface has its own component set.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/dart_source_scan.dart';
import 'helpers/ui_standards_allowlist.dart';

/// The trees the phone rules cover.
const List<String> uiStandardRoots = <String>['lib'];

/// The trees that may not build a raw Material `Card` (S-2603). `lib/state`
/// and `lib/core` hold no widgets.
const List<String> cardRoots = <String>['lib/features', 'lib/widgets'];

/// The button constructors that must carry a `shape:` (S-2601).
const List<String> buttonConstructorNames = <String>[
  'TextButton',
  'FilledButton',
  'OutlinedButton',
  'ElevatedButton',
];

/// Every button constructor in [source] whose call does not set a shape.
///
/// A shape is either named directly (`shape:`) or spelled inside the `style:`
/// the call passes — the button's own style object is part of its call text,
/// so `ButtonStyle(shape: ...)` and `X.styleFrom(shape: ...)` both count.
List<String> buttonShapeFindings(String path, String source) {
  final findings = <String>[];
  for (final name in buttonConstructorNames) {
    for (final call in constructorCalls(source, name)) {
      if (call.code.contains('shape')) continue;
      if (isAllowlisted(buttonShapeExceptions, path, call.code)) continue;
      findings.add(
        '$path:${call.line} `$name` is built with no `shape:`',
      );
    }
  }
  return findings;
}

/// Every raw Material `Card(` call in [source] (S-2603).
List<String> rawCardFindings(String path, String source) {
  final findings = <String>[];
  for (final call in constructorCalls(source, 'Card')) {
    if (isAllowlisted(rawCardExceptions, path, call.code)) continue;
    findings.add('$path:${call.line} builds a raw Material `Card(`');
  }
  return findings;
}

/// Every class named `…EmptyState` in [source] other than [OmniEmptyState]
/// (S-2804). A screen-local copy of the composition is what D-28.4 deletes, and
/// what this scan keeps from coming back under another private name.
List<String> emptyStateClassFindings(String path, String source) {
  final mask = blankLiteralsAndComments(source);
  final findings = <String>[];
  final pattern = RegExp(r'\bclass\s+(_?[A-Za-z0-9_]*EmptyState)\b');
  for (final match in pattern.allMatches(mask)) {
    final name = match.group(1)!;
    if (name == 'OmniEmptyState') continue;
    findings.add(
      '$path:${lineNumberAt(mask, match.start)} declares `class $name`',
    );
  }
  return findings;
}

/// Every `IconButton` in [source] with neither a `tooltip:` nor an enclosing
/// `Semantics` (S-2606).
List<String> iconButtonTooltipFindings(String path, String source) {
  final mask = blankLiteralsAndComments(source);
  final findings = <String>[];
  for (final call in constructorCalls(source, 'IconButton')) {
    if (call.code.contains('tooltip')) continue;
    if (_insideSemantics(mask, call.openIndex)) continue;
    if (isAllowlisted(iconButtonTooltipExceptions, path, call.code)) continue;
    findings.add('$path:${call.line} `IconButton` carries no `tooltip:`');
  }
  return findings;
}

/// Whether the parenthesis at [index] opens inside a `Semantics(...)` call.
///
/// The plan allows an icon-only button to carry a screen-reader label through
/// `Semantics` instead of a tooltip. Its own `Semantics` wrapper is a caller's
/// business, but a `Semantics(label: ...)` around the button says the same
/// thing to a screen reader.
bool _insideSemantics(String mask, int index) {
  final openers = <String>[];
  for (var i = 0; i < index && i < mask.length; i++) {
    if (mask[i] == '(') {
      openers.add(_openerName(mask, i));
    } else if (mask[i] == ')' && openers.isNotEmpty) {
      openers.removeLast();
    }
  }
  return openers.contains('Semantics');
}

/// The name a `(` at [parenIndex] belongs to, or `''` when it is a grouping
/// parenthesis.
String _openerName(String mask, int parenIndex) {
  final buffer = StringBuffer();
  for (var i = parenIndex - 1; i >= 0; i--) {
    if (RegExp(r'[A-Za-z0-9_$.]').hasMatch(mask[i])) {
      buffer.write(mask[i]);
      continue;
    }
    break;
  }
  return buffer.toString().split('').reversed.join();
}

/// The hue-bearing `Colors.<name>` members D-26.6 bans. The neutral names
/// (`white`, `black`, `transparent`) are missing on purpose: their per-file
/// counts are the ratchet instead.
const List<String> hueColourNames = <String>[
  'red',
  'redAccent',
  'blue',
  'grey',
  'green',
  'orange',
  'amber',
  'yellow',
  'purple',
  'teal',
  'cyan',
  'pink',
  'indigo',
  'brown',
  'lime',
  'deepOrange',
  'lightBlue',
  'lightGreen',
  'blueGrey',
];

/// The trees the raw-colour rule does not reach: D-26.6 exempts the app's own
/// role mapping, and `lib/mock/` is seed data.
const List<String> rawColourExemptPaths = <String>[
  'lib/app.dart',
  'lib/core/constants/omni_theme.dart',
  'lib/core/constants/modality_colors.dart',
];

/// Whether [path] is outside the raw-colour rule's reach.
bool rawColourExempt(String path) =>
    rawColourExemptPaths.contains(path) || path.startsWith('lib/mock/');

final RegExp _hueColourPattern = RegExp(
  'Colors\\.(${hueColourNames.join('|')})\\b',
);
final RegExp _hexLiteralPattern = RegExp(r'0x[0-9A-Fa-f]+');

/// A raw colour D-26.6 bans: a `Color(...)` call carrying a hex literal, or a
/// hue-bearing `Colors.<name>` — with or without an index or an opacity call,
/// which is still the same literal.
///
/// Skips comments and string literals (the mask), so prose about a colour is
/// not a colour.
List<String> rawColourFindings(String path, String source) {
  final mask = blankLiteralsAndComments(source);
  final findings = <String>[];

  for (final call in constructorCalls(source, 'Color')) {
    if (!_hexLiteralPattern.hasMatch(call.code)) continue;
    final snippet = 'Color${call.text}';
    if (isAllowlisted(rawColourExceptions, path, snippet)) continue;
    findings.add('$path:${call.line} builds a raw colour `$snippet`');
  }

  for (final match in _hueColourPattern.allMatches(mask)) {
    if (match.start > 0 &&
        RegExp(r'[A-Za-z0-9_$]').hasMatch(mask[match.start - 1])) {
      continue;
    }
    var end = match.end;
    final index = RegExp(r'^\[\d+\]').firstMatch(mask.substring(end));
    if (index != null) end += index.end;
    final opacity = RegExp(r'^\.withOpacity').firstMatch(mask.substring(end));
    if (opacity != null) end += opacity.end;
    final snippet = mask.substring(match.start, end);
    if (isAllowlisted(rawColourExceptions, path, snippet)) continue;
    findings.add('$path:${lineNumberAt(mask, match.start)} uses `$snippet`');
  }

  return findings;
}

/// The `Colors.<member>` ratchet pattern: the neutral name with or without its
/// shade digits (`Colors.white`, `Colors.white70`, `Colors.black54`).
RegExp _neutralColourPattern(String member) =>
    RegExp('Colors\\.$member\\d*\\b');

/// The paths the ratchet covers: everything under `lib/` except `lib/watch/`
/// (dropped by [dartSourcesUnder]), the two neutral names' own definitions and
/// the seeds.
bool ratchetExempt(String path) =>
    path.startsWith('lib/mock/') ||
    path == 'lib/app.dart' ||
    path == 'lib/core/constants/omni_theme.dart';

/// Every file whose use of [member] (`Colors.white`, `Colors.black`) is not
/// covered by [ratchet] — either more than its recorded count, or a file the
/// map does not list at all.
///
/// The shaded neutrals count too: `Colors.white70` and `Colors.black54` are the
/// same literal as `Colors.white` and `Colors.black` with an alpha, so the
/// pattern takes any digit suffix.
///
/// [files] defaults to the tree the ratchet covers; tests pass their own.
List<String> ratchetFindings(
  String member,
  Map<String, int> ratchet, {
  List<DartSourceFile>? files,
}) {
  final pattern = _neutralColourPattern(member);
  final findings = <String>[];
  for (final file in files ?? ratchetFiles()) {
    final count = pattern
        .allMatches(blankLiteralsAndComments(file.source))
        .length;
    if (count == 0) continue;
    final max = ratchet[file.path];
    if (max == null) {
      findings.add('${file.path} uses `Colors.$member` $count×, unlisted');
    } else if (count > max) {
      findings.add('${file.path} uses `Colors.$member` $count× (ratchet $max)');
    }
  }
  return findings;
}

/// S-3001 — the trees that own a shared bottom sheet: every widget in
/// `lib/widgets/`, plus the three primer/effort sheets the screens wrap in
/// `showModalBottomSheet`.
const List<String> sheetOwnerFiles = <String>[
  'lib/features/nutrition/widgets/nutrition_primer_sheet.dart',
  'lib/features/stats/widgets/stats_primer_sheet.dart',
  'lib/widgets/session/effort_rating_sheet.dart',
];

/// Whether [path] is one of the files that own a sheet.
bool sheetOwner(String path) =>
    path.startsWith('lib/widgets/') || sheetOwnerFiles.contains(path);

/// The `showModalBottomSheet` call, with or without a type argument — every
/// call site in `lib/` names the argument, so a name-only scan would miss most
/// of them.
final RegExp _showModalBottomSheetPattern = RegExp(
  r'\bshowModalBottomSheet\s*(<[^(){}]*>\s*)?\(',
);

/// Every hand-built `showModalBottomSheet(` call in [source] (S-3001): one
/// outside the files that own a shared sheet. The count is the ratchet.
List<String> handBuiltSheetFindings(String path, String source) {
  if (sheetOwner(path)) return const <String>[];
  final mask = blankLiteralsAndComments(source);
  final findings = <String>[];
  for (final match in _showModalBottomSheetPattern.allMatches(mask)) {
    findings.add(
      '$path:${lineNumberAt(mask, match.end - 1)} calls `showModalBottomSheet(`',
    );
  }
  return findings;
}

/// The trees that own the shared dialogs (S-3001).
const List<String> dialogOwnerRoots = <String>[
  'lib/widgets/dialogs',
  'lib/widgets/pickers',
];

/// Whether [path] is one of the files that own a dialog.
bool dialogOwner(String path) =>
    dialogOwnerRoots.any((root) => path.startsWith('$root/'));

/// Every raw `AlertDialog(` call in [source] (S-3001) outside the trees that
/// own the shared dialogs — a hand-built text-entry dialog. The count is the
/// ratchet.
List<String> handBuiltDialogFindings(String path, String source) {
  if (dialogOwner(path)) return const <String>[];
  final findings = <String>[];
  for (final call in constructorCalls(source, 'AlertDialog')) {
    findings.add('$path:${call.line} builds a raw `AlertDialog(`');
  }
  return findings;
}

/// S-2702 — the `showSnackBar(` call S-2702 bans, unless its argument is a
/// `PRToast` bar.
final RegExp _showSnackBarPattern = RegExp(r'\bshowSnackBar\(');

/// Every raw message bar in [source] (S-2702): a `SnackBar(` constructor, or a
/// `showSnackBar(` call whose argument does not start with `PRToast.` — the
/// celebration toast, the one named exception (D-27.3).
///
/// The two files that *own* a look are excused whole
/// ([rawSnackBarAllowed]): the rule is about call sites, and those files are
/// what every call site shares.
List<String> rawSnackBarFindings(String path, String source) {
  if (rawSnackBarAllowed(path)) return const <String>[];

  final mask = blankLiteralsAndComments(source);
  final findings = <String>[];

  for (final call in constructorCalls(source, 'SnackBar')) {
    findings.add('$path:${call.line} builds a raw `SnackBar(`');
  }

  for (final match in _showSnackBarPattern.allMatches(mask)) {
    final open = match.end - 1;
    final argument = balancedCallText(mask, open, mask: mask)
        .substring(1)
        .trimLeft();
    if (argument.startsWith('PRToast.')) continue;
    findings.add(
      '$path:${lineNumberAt(mask, open)} calls `showSnackBar(` with '
      'something other than a `PRToast` bar',
    );
  }

  return findings;
}

/// An exception interpolated into a message: `$e`, `${e}`, `$error`, `$ex`,
/// `$err`.
final RegExp _exceptionInterpolationPattern = RegExp(
  r'\$\{?(?:e|error|ex|err)\b',
);

/// Every `OmniMessage.` call in [source] whose text interpolates an exception
/// object (S-2703, D-27.2).
///
/// This one reads the call's *raw* text, not the masked one: the interpolation
/// sits inside a string literal, which [blankLiteralsAndComments] blanks — the
/// mask is exactly what makes it invisible to the other scans.
List<String> exceptionInMessageFindings(String path, String source) {
  final findings = <String>[];
  for (final call in constructorCalls(source, 'OmniMessage')) {
    final match = _exceptionInterpolationPattern.firstMatch(call.text);
    if (match == null) continue;
    findings.add(
      '$path:${call.line} interpolates `${match.group(0)}` into a message',
    );
  }
  return findings;
}

/// The files the ratchet covers: `lib/` minus `lib/watch/` (dropped by
/// [dartSourcesUnder]), the seeds, and the definitions the roles are built
/// from.
List<DartSourceFile> ratchetFiles() => dartSourcesUnder(uiStandardRoots)
    .where((file) => !ratchetExempt(file.path))
    .toList();

/// The ratchet entries that no longer point at a use of [member] — a count
/// that would otherwise sit in the map pretending to allow something.
List<String> staleRatchetEntries(String member, Map<String, int> ratchet) {
  final findings = <String>[];
  for (final path in ratchet.keys) {
    final file = File(path);
    if (!file.existsSync()) {
      findings.add('$path is gone');
      continue;
    }
    final count = _neutralColourPattern(
      member,
    ).allMatches(blankLiteralsAndComments(file.readAsStringSync())).length;
    if (count == 0) {
      findings.add('$path has no `Colors.$member` left');
    }
  }
  return findings;
}

String _buttonsWhy(List<String> findings) =>
    '''
Every button in OmniTrain is a rounded rectangle, and the radius comes from the
`OmniTheme` tokens (`buttonBorderRadius` for CTAs and pairs,
`buttonUtilityRadius` for compact and dialog actions, `buttonIconRadius` for
icon-only squares). A button that does not set `shape:` falls back to
Material's `StadiumBorder` — a pill — which is the one shape the design system
does not use.

Set `shape:` explicitly, as `lib/widgets/dialogs/confirmation_dialog.dart` does
(D-26.2):

  style: ButtonStyle(
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
      ),
    ),
  ),

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _cardsWhy(List<String> findings) =>
    '''
Cards are built once, by `OmniSurface`, so every card in the app shares the
surface colour, the corner radius, the border and the shadow
(`docs/design_system.md`). A raw Material `Card(` picks its own fill and
elevation, and drifts (D-26.3).

Use `OmniSurface(padding: ...)`, wrapped in a `Padding` when the call site
wants an outer margin.

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _tooltipsWhy(List<String> findings) =>
    '''
An icon-only button has no text, so its `tooltip:` is the only label a screen
reader or a long-press can find. Every `IconButton` carries one — a plain verb
phrase from the icon and its context ("Previous month", "Close", "Delete
period"), or an enclosing `Semantics` label (D-26.8).

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _coloursWhy(List<String> findings) =>
    '''
A colour literal is a colour the theme cannot change: the wrong one stays
wrong in all six themes, and it skips the contrast contracts the
`ColorScheme` roles are measured against (`docs/design_system.md`).

Use a role — `theme.colorScheme.surface`, `onSurface`, `primary`, `error`,
`outlineVariant` — or an `OmniTheme.colors` token. A site that genuinely *is*
the colour (a scrim, a shadow, a value the user picked) belongs in
`rawColourExceptions` with its reason (D-26.7).

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _ratchetWhy(List<String> findings) =>
    '''
`Colors.white` and `Colors.black` are legal (D-26.6) but frozen — including
their shaded forms (`Colors.white70`, `Colors.black54`, …), which the pattern
counts under the same name: the counts in
`test/helpers/ui_standards_allowlist.dart` were recorded from `lib/` on
2026-10-13 and may only fall. A new `Colors.white` in a listed file, or any use
in a file the map does not list, means a theme token should be doing that job.

If a count fell because you removed uses, lower the number in the map in the
same change. The table of recorded counts lives in
`test/helpers/ui_standards_allowlist.dart`.

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _messagesWhy(List<String> findings) =>
    '''
Every small message at the bottom of a screen comes through `OmniMessage`, so
they all read the same: the theme's surface colour, the theme's text colour and
the corner radius the dialog actions use (D-27.1, `docs/design_system.md`). A
raw `SnackBar(` picks its own colours, shape and behaviour, and drifts.

Use `OmniMessage.show(context, text)` for a message and
`OmniMessage.error(context, text)` for a failed action, as
`lib/features/nutrition/add_food_screen.dart` does. The PR celebration is the
one exception (D-27.3): its call site hands `showSnackBar` a `PRToast.` bar.

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _exceptionTextWhy(List<String> findings) =>
    '''
A message never shows the exception. `Exception: ...` is not something the user
can act on, so a failed action says what failed and what to do —
"Could not save the entry. Try again." (D-27.2). The exception object goes to
`debugPrint('<where>: \$e')` instead, where a developer can find it.

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _emptyStateWhy(List<String> findings) =>
    '''
Plan 28 gives every screen and list with nothing to show one composition,
`OmniEmptyState` (D-28.1). A private `_EmptyState` class is a second copy of it,
so the next copy change lands in one place and this one drifts.

Delete the private class and render `OmniEmptyState` instead; the compact
variant (`compact: true`) is the one for use inside a card (D-28.4).

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _sheetsWhy(int count, List<String> findings) =>
    '''
A bottom sheet a screen builds itself picks its own chrome — drag handle,
corner radius, safe-area padding, scroll behaviour — and drifts from every
other sheet in the app (`docs/design_system.md`).

No shared sheet piece owns the job yet, so the hand-built call sites are
counted instead of banned: `handBuiltSheetRatchet` in
`test/helpers/ui_standards_allowlist.dart` is the total recorded on 2026-10-13
and may only fall. Lower it in the same change that removes a call site.

The files that do not count: everything under `lib/widgets/` and the three
primer/effort sheets the screens wrap.

Hand-built sheet call sites: $count (ratchet $handBuiltSheetRatchet).

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _dialogsWhy(int count, List<String> findings) =>
    '''
A raw `AlertDialog(` copies the framework's Material look — its own shape,
padding and text styles — instead of the dialog the design system specifies
(`docs/design_system.md`). The shared dialogs are `ConfirmationDialog` and the
pickers in `lib/widgets/pickers/`.

No shared piece owns text entry yet, so the hand-built dialogs are counted
instead of banned: `handBuiltDialogRatchet` in
`test/helpers/ui_standards_allowlist.dart` is the total recorded on 2026-10-13
and may only fall. Lower it in the same change that removes a call site.

Hand-built dialog call sites: $count (ratchet $handBuiltDialogRatchet).

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

String _allowlistWhy(List<String> findings) =>
    '''
An exception that no longer matches anything is a rule pretending to have a
hole. The site it excused was fixed (or moved), so delete the entry in
`test/helpers/ui_standards_allowlist.dart` — the lists only ever shrink
(D-26.5).

Findings:
${findings.map((finding) => '  · $finding').join('\n')}
''';

void main() {
  group('dartSourceScan', () {
    test('balancedCallText ignores parentheses in strings and comments', () {
      const source =
          "FilledButton(\n"
          "  child: Text('a (b) c'), // a comment with a )\n"
          "  onPressed: () {},\n"
          ')';
      final open = source.indexOf('(');
      final text = balancedCallText(source, open);
      expect(text, source.substring(open), reason: 'stops only at the 4th paren');
      expect(text, endsWith(')'));
    });

    test('balancedCallText survives a nested call and a block comment', () {
      const source =
          'Card(\n'
          '  /* Card( ) Card( */\n'
          '  child: Padding(padding: EdgeInsets.all(12), child: Text("x")),\n'
          ')';
      final open = source.indexOf('(');
      final text = balancedCallText(source, open);
      expect(text, source.substring(open));
      expect(text, endsWith(')'));
    });

    test('constructorCalls reports the line of the opening parenthesis', () {
      const source = 'void f() {\n  return OutlinedButton(\n    child: Text("x"),\n  );\n}\n';
      final calls = constructorCalls(source, 'OutlinedButton');
      expect(calls, hasLength(1));
      expect(calls.single.line, 2);
      expect(calls.single.text, startsWith('('));
    });

    test('constructorCalls skips static factories and longer identifiers', () {
      const source =
          'a() {\n'
          '  final a = FilledButton.styleFrom(shape: null);\n'
          '  return _buildFilledButton(\n'
          '    child: Text("x"),\n'
          '  );\n'
          '}\n';
      expect(constructorCalls(source, 'FilledButton'), isEmpty);
    });

    test('constructorCalls sees a name in a comment or a string as nothing', () {
      const source =
          '// Card(\n'
          'const s = "Card(";\n'
          "const t = 'TextButton(';\n";
      expect(constructorCalls(source, 'Card'), isEmpty);
      expect(constructorCalls(source, 'TextButton'), isEmpty);
    });

    test('constructorCalls finds a named constructor through a dot', () {
      const source = 'x() {\n  return OutlinedButton.icon(\n    onPressed: null,\n  );\n}\n';
      final calls = constructorCalls(source, 'OutlinedButton');
      expect(calls, hasLength(1));
      expect(calls.single.line, 2);
    });

    test('dartSourcesUnder skips lib/watch/ and the other trees stay', () {
      final files = dartSourcesUnder(const ['lib']);
      expect(files, isNotEmpty);
      expect(
        files.where((file) => file.path.startsWith('lib/watch/')),
        isEmpty,
        reason: 'the wrist surface has its own component set',
      );
      expect(
        files.where((file) => file.path.endsWith('/watch_logging_screen.dart')),
        isEmpty,
      );
    });
  });

  group('S-2601 button shape', () {
    test('the scan flags a button with no shape and accepts the two spellings '
        'of the rule', () {
      expect(
        buttonShapeFindings(
          'lib/features/x.dart',
          'TextButton(onPressed: () {}, child: Text("OK"))',
        ),
        hasLength(1),
        reason: 'a default-styled dialog button is a pill',
      );
      for (final styled in [
        'TextButton(\n  style: ButtonStyle(\n'
            '    shape: WidgetStateProperty.all(\n'
            '      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),\n'
            '    ),\n  ),\n  child: Text("OK"),\n)',
        'FilledButton(\n  style: FilledButton.styleFrom(\n'
            '    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),\n'
            '  ),\n  child: Text("OK"),\n)',
        'OutlinedButton.icon(\n  style: OutlinedButton.styleFrom(shape: null),\n'
            '  onPressed: null,\n  icon: Icon(Icons.x),\n  label: Text("x"),\n)',
      ]) {
        expect(
          buttonShapeFindings('lib/features/x.dart', styled),
          isEmpty,
          reason: 'the shape may sit inside the call’s own style',
        );
      }
    });

    test('every button constructor in lib/ sets a shape', () {
      for (final root in uiStandardRoots) {
        expect(
          Directory(root).existsSync(),
          isTrue,
          reason: '$root has to exist, or the scan passes in silence',
        );
      }

      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        findings.addAll(buttonShapeFindings(file.path, file.source));
      }
      expect(findings, isEmpty, reason: _buttonsWhy(findings));
    });
  });

  group('S-2603 no raw Card', () {
    test('the scan flags a raw Card and skips a name that ends with Card', () {
      expect(
        rawCardFindings('lib/features/x.dart', 'Card(child: Text("x"))'),
        hasLength(1),
      );
      expect(
        rawCardFindings(
          'lib/features/x.dart',
          'OmniCardHeader(title: "X");\n'
          'return MyCard(child: Text("x"));\n'
          '// Card() used to be here',
        ),
        isEmpty,
        reason: 'only the bare Material constructor is the finding',
      );
    });

    test('no feature or widget file builds a raw Card', () {
      for (final root in cardRoots) {
        expect(
          Directory(root).existsSync(),
          isTrue,
          reason: '$root has to exist, or the scan passes in silence',
        );
      }

      final findings = <String>[];
      for (final file in dartSourcesUnder(cardRoots)) {
        findings.addAll(rawCardFindings(file.path, file.source));
      }
      expect(findings, isEmpty, reason: _cardsWhy(findings));
    });
  });

  group('S-2604 no raw colours', () {
    test('the scan flags a hex literal and a hue name, in every spelling', () {
      expect(
        rawColourFindings(
          'lib/features/x.dart',
          'const c = Color(0xFF1A1A2E);',
        ),
        hasLength(1),
      );
      expect(
        rawColourFindings(
          'lib/features/x.dart',
          'Color(int.parse(hex, radix: 16) + 0xFF000000)',
        ),
        hasLength(1),
        reason: 'a hex literal is the literal even when the call is built',
      );
      for (final hue in [
        'Colors.grey.withOpacity(0.08)',
        'Colors.grey[700]',
        'Colors.redAccent',
        'Colors.blueGrey.shade200',
        'Colors.lightBlue',
      ]) {
        expect(
          rawColourFindings('lib/features/x.dart', 'return $hue;'),
          hasLength(1),
          reason: '$hue is a colour the theme cannot change',
        );
      }
      for (final allowed in [
        'Colors.white.withOpacity(0.06)',
        'Colors.black87',
        'Colors.transparent',
        'const Color(value);',
        '// Color(0xFF1A1A2E) used to be here',
        "Text('Colors.grey')",
        'MyColors.red',
        'Colors.whitish',
        'final x = 0xFF000000;',
      ]) {
        expect(
          rawColourFindings('lib/features/x.dart', allowed),
          isEmpty,
          reason: '$allowed is not a banned site',
        );
      }
    });

    test('every raw colour in lib/ is a fixed site or an allowlisted one', () {
      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        if (rawColourExempt(file.path)) continue;
        findings.addAll(rawColourFindings(file.path, file.source));
      }
      expect(findings, isEmpty, reason: _coloursWhy(findings));
    });
  });

  group('S-2606 IconButton tooltip', () {
    test('the scan flags an icon-only button with no label', () {
      expect(
        iconButtonTooltipFindings(
          'lib/features/x.dart',
          'IconButton(icon: Icon(Icons.close), onPressed: () {})',
        ),
        hasLength(1),
        reason: 'an icon alone is not a label',
      );
      for (final labelled in [
        'IconButton(tooltip: "Close", icon: Icon(Icons.close), onPressed: () {})',
        'Semantics(\n  label: "Close",\n  child: IconButton(\n'
            '    icon: Icon(Icons.close),\n    onPressed: () {},\n  ),\n)',
      ]) {
        expect(
          iconButtonTooltipFindings('lib/features/x.dart', labelled),
          isEmpty,
          reason: 'a tooltip or an enclosing Semantics is the label',
        );
      }
      expect(
        iconButtonTooltipFindings(
          'lib/features/x.dart',
          'Semantics(\n  label: "Close",\n)\n'
              'IconButton(icon: Icon(Icons.close), onPressed: () {});',
        ),
        hasLength(1),
        reason: 'a Semantics that closed before the button labels nothing',
      );
    });

    test('every IconButton in lib/ carries a tooltip', () {
      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        findings.addAll(iconButtonTooltipFindings(file.path, file.source));
      }
      expect(findings, isEmpty, reason: _tooltipsWhy(findings));
    });
  });

  group('S-2607 colour ratchet', () {
    test('the scan flags an over-count and a file the map does not list', () {
      const file = DartSourceFile('lib/features/x.dart', 'Colors.white');
      expect(
        ratchetFindings('white', const {'lib/features/x.dart': 1}, files: const [file]),
        isEmpty,
        reason: 'the ratchet allows the one use the file has',
      );
      expect(
        ratchetFindings('white', const {}, files: const [file]),
        contains('lib/features/x.dart uses `Colors.white` 1×, unlisted'),
        reason: 'a file the map does not list may not use the name at all',
      );
      expect(
        ratchetFindings(
          'black',
          const {'lib/features/x.dart': 0},
          files: const [DartSourceFile('lib/features/x.dart', 'Colors.black')],
        ),
        contains('lib/features/x.dart uses `Colors.black` 1× (ratchet 0)'),
      );
      expect(
        ratchetFindings('white', const {'lib/features/x.dart': 9}, files: const [file]),
        isEmpty,
        reason: 'a lower count than the ratchet is the point of a ratchet',
      );
    });

    test('no file uses Colors.white or Colors.black above its ratchet', () {
      final findings = <String>[
        ...ratchetFindings('white', colorsWhiteRatchet),
        ...ratchetFindings('black', colorsBlackRatchet),
      ];
      expect(findings, isEmpty, reason: _ratchetWhy(findings));
    });
  });

  group('S-3001 hand-built sheet ratchet', () {
    test('the scan counts a call site, type argument or not, and lets the '
        'owner files through', () {
      for (final call in [
        'await showModalBottomSheet(\n  context: context,\n);',
        'await showModalBottomSheet<void>(\n  context: context,\n);',
        'showModalBottomSheet<_Choice>(\n  context: context,\n);',
      ]) {
        expect(
          handBuiltSheetFindings('lib/features/x.dart', call),
          hasLength(1),
          reason: '$call is a hand-built sheet',
        );
      }
      for (final allowed in [
        '// showModalBottomSheet<void>(context: context)',
        'const s = "showModalBottomSheet(";',
        'return _showModalBottomSheet(context);',
        'final builder = showModalBottomSheet;',
      ]) {
        expect(
          handBuiltSheetFindings('lib/features/x.dart', allowed),
          isEmpty,
          reason: '$allowed is not a call site',
        );
      }
      for (final owner in [
        'lib/widgets/layout/omni_surface.dart',
        'lib/widgets/session/effort_rating_sheet.dart',
        'lib/features/stats/widgets/stats_primer_sheet.dart',
        'lib/features/nutrition/widgets/nutrition_primer_sheet.dart',
      ]) {
        expect(
          handBuiltSheetFindings(
            owner,
            'showModalBottomSheet<void>(context: context)',
          ),
          isEmpty,
          reason: '$owner owns a shared sheet',
        );
      }
    });

    test('no more hand-built sheets than the ratchet allows', () {
      for (final root in uiStandardRoots) {
        expect(
          Directory(root).existsSync(),
          isTrue,
          reason: '$root has to exist, or the scan passes in silence',
        );
      }

      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        findings.addAll(handBuiltSheetFindings(file.path, file.source));
      }
      expect(
        findings.length,
        lessThanOrEqualTo(handBuiltSheetRatchet),
        reason: _sheetsWhy(findings.length, findings),
      );
    });
  });

  group('S-3001 hand-built dialog ratchet', () {
    test('the scan counts a raw AlertDialog and lets the owner trees through',
        () {
      expect(
        handBuiltDialogFindings(
          'lib/features/x.dart',
          'return AlertDialog(\n  title: Text("Rename"),\n);',
        ),
        hasLength(1),
      );
      expect(
        handBuiltDialogFindings(
          'lib/features/x.dart',
          '// AlertDialog(\n'
              'const s = "AlertDialog(";\n'
              'return _buildAlertDialog();\n',
        ),
        isEmpty,
        reason: 'a comment, a string and a longer name are not call sites',
      );
      for (final owner in [
        'lib/widgets/dialogs/confirmation_dialog.dart',
        'lib/widgets/pickers/metric_chooser_dialog.dart',
      ]) {
        expect(
          handBuiltDialogFindings(
            owner,
            'return AlertDialog(title: Text("x"));',
          ),
          isEmpty,
          reason: '$owner owns a shared dialog',
        );
      }
    });

    test('no more hand-built dialogs than the ratchet allows', () {
      for (final root in uiStandardRoots) {
        expect(
          Directory(root).existsSync(),
          isTrue,
          reason: '$root has to exist, or the scan passes in silence',
        );
      }

      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        findings.addAll(handBuiltDialogFindings(file.path, file.source));
      }
      expect(
        findings.length,
        lessThanOrEqualTo(handBuiltDialogRatchet),
        reason: _dialogsWhy(findings.length, findings),
      );
    });
  });

  group('S-2702 one message look', () {
    test('the scan flags a raw bar and lets the PRToast argument through', () {
      expect(
        rawSnackBarFindings(
          'lib/features/x.dart',
          'ScaffoldMessenger.of(context).showSnackBar(\n'
              "  SnackBar(content: Text('saved')),\n"
              ');',
        ),
        hasLength(2),
        reason: 'the call and the constructor it builds are both raw',
      );
      expect(
        rawSnackBarFindings(
          'lib/features/x.dart',
          'messenger.showSnackBar(PRToast.buildPRSnackBar(theme));',
        ),
        isEmpty,
        reason: 'the celebration toast keeps its own look (D-27.3)',
      );
      expect(
        rawSnackBarFindings(
          'lib/features/x.dart',
          '// SnackBar(content: Text("gone"))\n'
              'const s = "SnackBar(";\n'
              'return _buildSnackBar();\n',
        ),
        isEmpty,
        reason: 'a comment, a string and a longer name are not call sites',
      );
      expect(
        rawSnackBarFindings(
          'lib/widgets/feedback/omni_message.dart',
          'SnackBar(content: Text(text))',
        ),
        isEmpty,
        reason: 'the shared look is built in that file (D-27.1)',
      );
      expect(
        rawSnackBarFindings(
          'lib/features/x.dart',
          'messenger.showSnackBar(OmniMessage.build(text));',
        ),
        hasLength(1),
        reason: 'only a `PRToast.` argument is the named exception',
      );
    });

    test('no file outside the two that own a look builds a message bar', () {
      for (final root in uiStandardRoots) {
        expect(
          Directory(root).existsSync(),
          isTrue,
          reason: '$root has to exist, or the scan passes in silence',
        );
      }

      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        findings.addAll(rawSnackBarFindings(file.path, file.source));
      }
      expect(findings, isEmpty, reason: _messagesWhy(findings));
    });
  });

  group('S-2703 no exception text in a message', () {
    test('the scan flags an exception interpolated into a message', () {
      for (final text in [
        r"OmniMessage.error(context, 'Failed to save: $e');",
        r"OmniMessage.errorOn(messenger, theme, 'Save failed: $error');",
        r"OmniMessage.show(context, '${ex}');",
        r"OmniMessage.error(context, 'Failed: $err');",
      ]) {
        expect(
          exceptionInMessageFindings('lib/features/x.dart', text),
          hasLength(1),
          reason: '$text shows the exception',
        );
      }
      for (final text in [
        "OmniMessage.error(context, 'Could not save the entry. Try again.');",
        "OmniMessage.errorOn(\n  messenger,\n  theme,\n"
            "  'Could not save \${food.name}. Try again.',\n);",
        "OmniMessage.show(context, 'Saved'); // \$e goes to debugPrint",
      ]) {
        expect(
          exceptionInMessageFindings('lib/features/x.dart', text),
          isEmpty,
          reason: '$text names no exception object',
        );
      }
    });

    test('no message in lib/ interpolates an exception', () {
      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        findings.addAll(exceptionInMessageFindings(file.path, file.source));
      }
      expect(findings, isEmpty, reason: _exceptionTextWhy(findings));
    });
  });

  group('S-2804 one empty-state composition', () {
    test('the scan flags a screen-local empty-state class and accepts the '
        'shared widget', () {
      // The declaration phase 3 deleted from
      // `lib/features/exercise/exercise_library_screen.dart` (D-28.4).
      expect(
        emptyStateClassFindings(
          'lib/features/x.dart',
          'class _EmptyState extends StatelessWidget {\n'
              '  const _EmptyState();\n'
              '}\n',
        ),
        hasLength(1),
        reason: 'a screen-local copy of the composition is what D-28.4 removes',
      );
      expect(
        emptyStateClassFindings(
          'lib/features/x.dart',
          'class ExercisesEmptyState extends StatelessWidget {}\n',
        ),
        hasLength(1),
        reason: 'the private name is not the rule: any second copy counts',
      );
      expect(
        emptyStateClassFindings(
          'lib/widgets/common/omni_empty_state.dart',
          'class OmniEmptyState extends StatelessWidget {\n'
              '  const OmniEmptyState();\n'
              '}\n',
        ),
        isEmpty,
        reason: 'the shared widget is the one copy the rule wants',
      );
      expect(
        emptyStateClassFindings(
          'lib/features/x.dart',
          '// class _EmptyState stays in the plan text\n'
              "const String s = 'class _EmptyState';\n"
              'class _EmptyStateRow extends StatelessWidget {}\n',
        ),
        isEmpty,
        reason: 'a comment, a string and a longer name are not declarations',
      );
    });

    test('only one empty-state class is declared in lib/', () {
      for (final root in uiStandardRoots) {
        expect(
          Directory(root).existsSync(),
          isTrue,
          reason: '$root has to exist, or the scan passes in silence',
        );
      }

      final findings = <String>[];
      for (final file in dartSourcesUnder(uiStandardRoots)) {
        findings.addAll(emptyStateClassFindings(file.path, file.source));
      }
      expect(findings, isEmpty, reason: _emptyStateWhy(findings));
    });
  });

  group('allowlist self-check', () {
    test('every ratchet entry still names a file that uses the name', () {
      final findings = <String>[
        ...staleRatchetEntries('white', colorsWhiteRatchet),
        ...staleRatchetEntries('black', colorsBlackRatchet),
      ];
      expect(findings, isEmpty, reason: _allowlistWhy(findings));
    });

    test('every allowlist entry still matches a line in its file', () {
      final findings = <String>[];
      for (final exception in allUiStandardsExceptions) {
        final file = File(exception.path);
        if (!file.existsSync()) {
          findings.add(
            '${exception.path} is gone, so the entry for `${exception.needle}` '
            'excuses nothing',
          );
          continue;
        }
        final source = blankLiteralsAndComments(file.readAsStringSync());
        if (!source.contains(exception.needle)) {
          findings.add(
            '${exception.path} no longer contains `${exception.needle}`, so the '
            'entry excuses nothing',
          );
        }
      }
      expect(findings, isEmpty, reason: _allowlistWhy(findings));
    });
  });
}
