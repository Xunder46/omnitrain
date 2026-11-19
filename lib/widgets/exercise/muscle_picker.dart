import 'package:flutter/material.dart';

import '../../core/utils/muscle_display.dart';
import '../../core/utils/muscle_selection.dart';
import '../../data/models/models.dart';
import '../../data/models/muscle_taxonomy.dart';

/// The exercise editor's muscle picker: the fixed taxonomy rows of chips plus
/// the main/assists summary.
///
/// Presentation only — it holds no state and never persists. A tap reports the
/// chip's group id through [onTap]; the owning screen owns the [selection] and
/// cycles it.
class MusclePicker extends StatelessWidget {
  const MusclePicker({
    super.key,
    required this.groups,
    required this.selection,
    required this.onTap,
  });

  /// The muscle groups whose names the chips show, by id. An id that is not
  /// here gets no chip; the summary still names it from [MuscleTaxonomy].
  final List<MuscleGroup> groups;

  final MuscleSelection selection;

  /// Called with the tapped chip's group id.
  final ValueChanged<String> onTap;

  static const Key hintKey = Key('muscle_picker_hint');
  static const Key mainSummaryKey = Key('muscle_summary_main');
  static const Key assistsSummaryKey = Key('muscle_summary_assists');

  static Key chipKey(String id) => Key('muscle_chip_$id');

  /// The rows in display order: the label and the region the row is built
  /// from, or `null` for the standalone row (Chest, Neck) that carries no
  /// region chip.
  static final List<(String, String?)> _rows = [
    ('Chest and neck', null),
    for (final id in kMuscleRegionOrder) (muscleTaxonomyName(id), id),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tap once for a main muscle, twice for one that assists, '
          'a third time to clear.',
          key: hintKey,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final (label, regionId) in _rows) ...[
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _rowChips(context, regionId),
          ),
          const SizedBox(height: 12),
        ],
        Text('Main: ${_summary(MuscleRole.primary)}', key: mainSummaryKey),
        const SizedBox(height: 4),
        Text(
          'Assists: ${_summary(MuscleRole.secondary)}',
          key: assistsSummaryKey,
        ),
      ],
    );
  }

  /// The chips of one row, in display order.
  List<Widget> _rowChips(BuildContext context, String? regionId) {
    if (regionId == null) {
      return [
        for (final id in kMuscleStandaloneIds)
          if (_groupName(id) != null) _chip(context, id),
      ];
    }

    final chips = <Widget>[];
    final regionName = _groupName(regionId);
    if (regionName != null) {
      chips.add(
        _chip(context, regionId, label: 'Whole ${regionName.toLowerCase()}'),
      );
    }
    for (final id in MuscleTaxonomy.musclesOf(regionId)) {
      if (_groupName(id) == null) continue;
      chips.add(_chip(context, id));
    }
    return chips;
  }

  Widget _chip(BuildContext context, String id, {String? label}) {
    final theme = Theme.of(context);
    final name = label ?? _groupName(id) ?? muscleTaxonomyName(id);
    final role = selection.roleOf(id);
    final covered = selection.isCovered(id);
    final assists = role == MuscleRole.secondary;

    final String semanticsLabel;
    if (covered) {
      semanticsLabel = '$name, covered by chosen muscles';
    } else if (role == MuscleRole.primary) {
      semanticsLabel = '$name, main muscle';
    } else if (assists) {
      semanticsLabel = '$name, assists';
    } else {
      semanticsLabel = '$name, not selected';
    }

    return Semantics(
      label: semanticsLabel,
      button: true,
      excludeSemantics: true,
      child: FilterChip(
        key: chipKey(id),
        label: Text(assists ? '$name · assists' : name),
        selected: role == MuscleRole.primary,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        side: assists
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : null,
        labelStyle: assists
            ? TextStyle(color: theme.colorScheme.primary)
            : null,
        onSelected: covered ? null : (_) => onTap(id),
      ),
    );
  }

  /// The name the chips and the summary show for [id].
  String _summary(MuscleRole role) {
    final ids = selection.idsWith(role);
    if (ids.isEmpty) return 'none';
    return [
      for (final id in ids) _groupName(id) ?? muscleTaxonomyName(id),
    ].join(', ');
  }

  String? _groupName(String id) {
    for (final group in groups) {
      if (group.id == id) return group.name;
    }
    return null;
  }
}
