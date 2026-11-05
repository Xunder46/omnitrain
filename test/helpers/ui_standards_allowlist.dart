// The single place a UI-standards guard in
// `test/ui_standards_contract_test.dart` may excuse a site, plus the recorded
// `Colors.white`/`Colors.black` ratchet: this file is the exceptions register
// for the UI rules the plans `docs/plans/2026-10-13-26-ui-rule-breaks-plan`
// (D-26.5 to D-26.7) and `docs/plans/2026-10-13-27-ui-messages-plan` (D-27.5)
// write down. Entries may only be removed; to add one you
// need an owner-approved reason in the plan, and the reason string has to say
// what makes the site different from every other call site — a guard that
// excuses silently is worse than a guard that fails. Fix a listed violation
// when you touch its file, instead of leaving it for the guard to re-report.
//
// A guard reads a site's own call text, so an entry names one call and not a
// whole file; `ratchet` counts below name a file on purpose.
//
// Two of the ratchets are single totals rather than per-file maps: hand-built
// sheets (`showModalBottomSheet(`) and hand-built dialogs (`AlertDialog(`). No
// shared piece owns either job yet, so the recorded number is the size of the
// debt, and it may only go down.
//
// One false positive is accepted on purpose: the button-shape scan reads the
// call's own text, so a *shared* `style:` variable that carries the `shape:` is
// flagged at every call site that passes it. Set `shape:` inline in the call,
// as the button spec in `docs/design_system.md` shows.

/// One excused site: a file, a needle inside the call text that identifies the
/// site, and the reason the rule does not apply to it.
class UiStandardsException {
  const UiStandardsException({
    required this.path,
    required this.needle,
    required this.reason,
  });

  /// Repository-relative path, e.g. `lib/features/calendar/calendar_screen.dart`.
  final String path;

  /// Text that must appear in the offending call's code, so the entry names
  /// one call and not a whole file.
  final String needle;

  /// Why the rule does not apply here. A guard failure prints this.
  final String reason;
}

/// S-2601 — button shape. No button in `lib/` is exempt: D-26.2 is a shape the
/// design system already specifies for every dialog action.
const List<UiStandardsException> buttonShapeExceptions = <UiStandardsException>[];

/// S-2603 — raw `Card(` in `lib/features` and `lib/widgets`. No card is
/// exempt: the shared card look is `OmniSurface` (D-26.3).
const List<UiStandardsException> rawCardExceptions = <UiStandardsException>[];

/// S-2606 — every `IconButton` carries a `tooltip:`, or a `Semantics` label of
/// its own. No button is exempt: D-26.8 wants a plain verb phrase at every
/// site, and the phrases are per-site, not per-file.
const List<UiStandardsException> iconButtonTooltipExceptions =
    <UiStandardsException>[];

/// S-2604 — raw colours (D-26.6). These are the sites D-26.7 keeps on purpose:
/// a scrim, a shadow, a user-chosen value and a user-pickable palette all *are*
/// the colour, so no theme token can stand in for them.
const List<UiStandardsException> rawColourExceptions = <UiStandardsException>[
  UiStandardsException(
    path: 'lib/features/session/workout_session_global_timer.dart',
    needle: 'Color(0xBF000000)',
    reason: 'scrim over content',
  ),
  UiStandardsException(
    path: 'lib/widgets/cards/energy_tile.dart',
    needle: 'Color(0x4D000000)',
    reason: 'black shadow',
  ),
  UiStandardsException(
    path: 'lib/features/calendar/calendar_screen.dart',
    needle: 'Color(0xFF000000 | value)',
    reason: 'user-chosen period colour',
  ),
  UiStandardsException(
    path: 'lib/features/period/create_period_screen.dart',
    needle: 'int.parse(colorHex.substring(1), radix: 16) + 0xFF000000',
    reason: 'user-pickable swatches',
  ),
];

/// S-2607 — the `Colors.white` ratchet. D-26.6 keeps the two neutral names
/// legal, because most of their call sites do mean "ink on a surface", but it
/// freezes today's counts: a listed file may fall, never rise, and a file that
/// is missing from the map may not use the name at all.
///
/// Recorded 2026-10-13 over `lib/`, excluding `lib/watch/`, `lib/mock/`,
/// `lib/app.dart` and `lib/core/constants/omni_theme.dart`. Counts are
/// occurrences (a line with two `Colors.white`s counts two):
///
/// The pattern is `Colors\.(white|black)\d*`, so the shaded neutrals
/// (`Colors.white70`, `Colors.black54`, …) count under the same name.
///
///   Colors.white
///   lib/widgets/layout/noise_overlay_painter.dart          2
///   lib/widgets/layout/omni_gradient_background.dart       1
///   lib/widgets/common/interactive_logo.dart               1
///   lib/widgets/cards/energy_tile.dart                     4
///   lib/features/period/create_period_screen.dart          1
///   lib/features/nutrition/widgets/macro_donut_chart.dart  1
///   lib/features/settings/settings_screen.dart             1
///   lib/features/splash/omni_splash_screen.dart            1
///   lib/features/profile/widgets/avatar_crop_sheet.dart    1
const Map<String, int> colorsWhiteRatchet = <String, int>{
  'lib/widgets/layout/noise_overlay_painter.dart': 2,
  'lib/widgets/layout/omni_gradient_background.dart': 1,
  'lib/widgets/common/interactive_logo.dart': 1,
  'lib/widgets/cards/energy_tile.dart': 4,
  'lib/features/period/create_period_screen.dart': 1,
  'lib/features/nutrition/widgets/macro_donut_chart.dart': 1,
  'lib/features/settings/settings_screen.dart': 1,
  'lib/features/splash/omni_splash_screen.dart': 1,
  'lib/features/profile/widgets/avatar_crop_sheet.dart': 1,
};

/// S-2607 — the `Colors.black` ratchet; see [colorsWhiteRatchet] for how it was
/// recorded and what it allows.
///
///   Colors.black
///   lib/widgets/logo/animated_zen_halo.dart                1
///   lib/widgets/cards/energy_tile.dart                     1
///   lib/features/session/workout_session_global_timer.dart 1
///   lib/features/settings/settings_screen.dart             2
///   lib/features/home/maintenance_placeholder_screen.dart  1
///   lib/features/home/home_screen.dart                     3
///   lib/features/profile/widgets/avatar_crop_sheet.dart    1
///   lib/features/nutrition/widgets/macro_donut_chart.dart  1
const Map<String, int> colorsBlackRatchet = <String, int>{
  'lib/widgets/logo/animated_zen_halo.dart': 1,
  'lib/widgets/cards/energy_tile.dart': 1,
  'lib/features/session/workout_session_global_timer.dart': 1,
  'lib/features/settings/settings_screen.dart': 2,
  'lib/features/home/maintenance_placeholder_screen.dart': 1,
  'lib/features/home/home_screen.dart': 3,
  'lib/features/profile/widgets/avatar_crop_sheet.dart': 1,
  'lib/features/nutrition/widgets/macro_donut_chart.dart': 1,
};

/// S-3001 — hand-built bottom sheets. Recorded 2026-10-13 over `lib/`:
/// `showModalBottomSheet(` call sites outside the files that own a shared
/// sheet — everything under `lib/widgets/` plus the three primer/effort sheet
/// files (`lib/features/nutrition/widgets/nutrition_primer_sheet.dart`,
/// `lib/features/stats/widgets/stats_primer_sheet.dart`,
/// `lib/widgets/session/effort_rating_sheet.dart`).
///
/// Hand-built sheets, no shared piece yet; may only go down.
const int handBuiltSheetRatchet = 16;

/// S-3001 — hand-built dialogs. Recorded 2026-10-13 over `lib/`: raw
/// `AlertDialog(` call sites outside `lib/widgets/dialogs/` and
/// `lib/widgets/pickers/`, the two trees that own the shared dialogs.
///
/// Hand-built text-entry dialogs, no shared piece yet; may only go down.
const int handBuiltDialogRatchet = 9;

/// S-2702 — raw `SnackBar(`/`showSnackBar(` sites (D-27.5). Two files *are* the
/// shared look rather than a caller of it, so each entry excuses the whole file
/// and [rawSnackBarAllowed] answers true for it; the `needle` names a call that
/// is still in the file today.
const List<UiStandardsException> rawSnackBarExceptions = <UiStandardsException>[
  UiStandardsException(
    path: 'lib/widgets/feedback/omni_message.dart',
    needle: 'messenger.showSnackBar(',
    reason: 'the one shared message look is built here (D-27.1)',
  ),
  UiStandardsException(
    path: 'lib/widgets/session/pr_toast.dart',
    needle: 'return SnackBar(',
    reason: 'the PR celebration keeps its own celebration look (D-27.3)',
  ),
];

/// S-2703 — an exception interpolated into a message's text (D-27.2). No site
/// is exempt: the copy rule is "Could not [verb] [thing]. Try again.", and the
/// exception object belongs in a `debugPrint`.
const List<UiStandardsException> exceptionInMessageExceptions =
    <UiStandardsException>[];

/// Whether [path] may build its own message bar at all (S-2702).
///
/// S-2702 is a rule about *call sites*: every screen shows its messages through
/// `OmniMessage`. The two files in [rawSnackBarExceptions] are the shared look
/// itself — `omni_message.dart` builds it, `pr_toast.dart` owns the celebration
/// — so they are excused as files rather than one call at a time.
bool rawSnackBarAllowed(String path) =>
    rawSnackBarExceptions.any((exception) => exception.path == path);

/// Every excused site, whatever rule it belongs to. The self-check in
/// `test/ui_standards_contract_test.dart` walks this list, so a new list has to
/// be added here too.
const List<UiStandardsException> allUiStandardsExceptions =
    <UiStandardsException>[
      ...buttonShapeExceptions,
      ...rawCardExceptions,
      ...iconButtonTooltipExceptions,
      ...rawColourExceptions,
      ...rawSnackBarExceptions,
      ...exceptionInMessageExceptions,
    ];

/// Whether [path]'s failing call, whose code is [callCode], is excused by one
/// of [exceptions].
bool isAllowlisted(
  List<UiStandardsException> exceptions,
  String path,
  String callCode,
) {
  for (final exception in exceptions) {
    if (exception.path == path && callCode.contains(exception.needle)) {
      return true;
    }
  }
  return false;
}
