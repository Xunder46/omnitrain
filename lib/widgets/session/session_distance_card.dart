import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../layout/omni_surface.dart';

/// One row of the Session Summary's DISTANCE card.
///
/// Presentation only: the label, the value text and the unit label are
/// computed by the caller, which owns the distance rules. The row renders
/// whatever it is given, and an absent distance reads as an em dash rather
/// than as a zero.
@immutable
class DistanceRowModel {
  /// The exercise name, with the entry number appended when the exercise has
  /// more than one entry.
  final String name;

  /// The distance as display text, or `absentValue` when the entry has none.
  final String value;

  /// The unit label, with the estimate marker appended for an estimate.
  final String unitLabel;

  final VoidCallback onTap;

  const DistanceRowModel({
    required this.name,
    required this.value,
    required this.unitLabel,
    required this.onTap,
  });
}

/// The Session Summary's DISTANCE card: one tap-to-edit row per entry that
/// carries a distance.
///
/// Reads no state. It is hidden by its caller when it has no rows, and it
/// renders nothing itself in that case so a stale empty card can never show.
class SessionDistanceCard extends StatelessWidget {
  /// What an entry with no distance shows — absence is never rendered as a
  /// zero.
  static const String absentValue = '—';

  final List<DistanceRowModel> rows;

  const SessionDistanceCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

    return OmniSurface(
      key: const Key('omni_session_distance_card'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: themeColors.surfaceBorder, height: 1),
            _buildRow(context, theme, rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    ThemeData theme,
    DistanceRowModel row,
  ) {
    final unitStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 1.0,
    );

    return InkWell(
      onTap: row.onTap,
      child: Semantics(
        button: true,
        label: '${row.name}, ${row.value} ${row.unitLabel}',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.name,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                row.value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(row.unitLabel.toUpperCase(), style: unitStyle),
            ],
          ),
        ),
      ),
    );
  }
}
