/// The session effort rating sheet: "How hard was this session?", on the 1–5
/// scale, with its two end labels.
///
/// One sheet for every phone surface that asks: the Session Summary's
/// automatic post-workout prompt and its EFFORT row's add/change control
/// (Stats PR 1), and the Watch Session screen's question after the phone's own
/// Finish (Stats PR 2, D-139). Where the answer goes is the caller's —
/// [EffortRatingSheet.onRated] — so the sheet itself holds no state beyond the
/// tile the user picked and writes nothing.
///
/// The question, the scale and the end labels are the ones the wrist asks
/// with: `watch/contract/watch_effort_rating_contract.json`, held to this
/// sheet by `test/watch_effort_rating_copy_parity_test.dart` (S-287).
library;

import 'package:flutter/material.dart';

import '../../core/constants/modality_display.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/session_feeling_utils.dart';

/// Modal bottom sheet content for the session effort rating (1-5). Pops
/// with the chosen rating once [onRated] has recorded it.
class EffortRatingSheet extends StatefulWidget {
  const EffortRatingSheet({
    super.key,
    this.modality,
    required this.startedAt,
    this.initialRating,
    required this.onRated,
    this.mustAnswer = false,
  });

  /// The rated session's modality, named in the subtitle.
  final String? modality;

  /// When the rated session started; the subtitle reads "Today" for a
  /// session that started today and the session's date otherwise.
  final DateTime startedAt;

  /// The rating the sheet opens with selected, if any.
  final int? initialRating;

  /// Records the rating the user picked. The sheet closes with it only when
  /// this answers true.
  final Future<bool> Function(int rating) onRated;

  /// Whether this sheet must be answered: it then ignores a tap outside it,
  /// a swipe, and the system back gesture alike, since all three are the
  /// same "leave without answering" the sheet has to refuse (F-4).
  final bool mustAnswer;

  /// Opens the sheet over [context].
  ///
  /// A sheet the user must answer ([mustAnswer]) cannot be closed by a tap
  /// outside it, a swipe or the system back button; one the user opened
  /// themselves can, and closing it that way answers null and records
  /// nothing.
  static Future<int?> show(
    BuildContext context, {
    required bool mustAnswer,
    String? modality,
    required DateTime startedAt,
    int? initialRating,
    required Future<bool> Function(int rating) onRated,
  }) => showModalBottomSheet<int>(
    context: context,
    isDismissible: !mustAnswer,
    enableDrag: !mustAnswer,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => EffortRatingSheet(
      modality: modality,
      startedAt: startedAt,
      initialRating: initialRating,
      onRated: onRated,
      mustAnswer: mustAnswer,
    ),
  );

  @override
  State<EffortRatingSheet> createState() => _EffortRatingSheetState();
}

class _EffortRatingSheetState extends State<EffortRatingSheet> {
  int? _selectedFeeling;

  @override
  void initState() {
    super.initState();
    // Pre-select the initial rating if provided
    _selectedFeeling = widget.initialRating;
  }

  /// Short "Mon D" date (e.g. "Sep 18").
  static String _formatDate(DateTime date) =>
      '${OmniDateUtils.shortMonthName(date.month)} ${date.day}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final displayName = ModalityDisplay.getName(widget.modality);
    final when = OmniDateUtils.isToday(widget.startedAt)
        ? 'Today'
        : _formatDate(widget.startedAt);
    final subtitle = '$displayName · $when';

    return PopScope(
      // The system back gesture is a third way to leave without answering,
      // alongside the barrier tap and the swipe `show` already guards with
      // `isDismissible`/`enableDrag` (F-4).
      canPop: !widget.mustAnswer,
      child: Container(
        decoration: BoxDecoration(
          color: themeColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(OmniTheme.surfaceBorderRadius),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          MediaQuery.of(context).padding.bottom + 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: themeColors.primary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
                margin: const EdgeInsets.only(bottom: 28),
              ),
            ),
            // Title
            Text(
              'How hard was this session?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.9),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 36),
            // Number tiles row
            Row(
              children: [
                for (int i = 1; i <= 5; i++) ...[
                  Expanded(child: _buildFeelingTile(i)),
                  if (i < 5) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Range labels row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Very easy',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.0,
                      color: themeColors.textMuted,
                    ),
                  ),
                  Text(
                    'Max effort',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.0,
                      color: themeColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeelingTile(int number) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final isSelected = _selectedFeeling == number;
    final tileColor = feelingColor(number, themeColors);
    final selectedTextColor = isSelected
        ? effortTileTextColor(
            number,
            themeColors,
            onPrimary: theme.colorScheme.onPrimary,
          )
        : theme.colorScheme.onSurface.withOpacity(0.35);

    return GestureDetector(
      onTap: () => _selectFeeling(number),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected
                ? tileColor
                : theme.colorScheme.surface.withOpacity(0.6),
            border: Border.all(
              color: isSelected
                  ? tileColor
                  : theme.colorScheme.onSurface.withOpacity(0.12),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: selectedTextColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectFeeling(int feeling) async {
    setState(() => _selectedFeeling = feeling);

    if (await widget.onRated(feeling) && mounted) {
      Navigator.of(context).pop(feeling);
    }
  }
}
