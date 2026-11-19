import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/muscle_display.dart';
import '../../data/models/models.dart';

/// The Discipline + Muscle filter pair shared by the exercise picker and the
/// Exercise Library, so both screens filter the same way.
///
/// Stateless: the owning screen holds the selected ids and re-runs its search
/// from [onDisciplineChanged] / [onMuscleChanged]. `null` means "All".
class ExerciseFilterRow extends StatelessWidget {
  final List<Discipline> disciplines;
  final List<MuscleGroup> muscleGroups;
  final String? disciplineId;
  final String? muscleGroupId;
  final ValueChanged<String?> onDisciplineChanged;
  final ValueChanged<String?> onMuscleChanged;

  const ExerciseFilterRow({
    super.key,
    required this.disciplines,
    required this.muscleGroups,
    required this.disciplineId,
    required this.muscleGroupId,
    required this.onDisciplineChanged,
    required this.onMuscleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muscleEntries = muscleFilterEntries(muscleGroups);
    TextStyle? itemStyle([FontWeight? weight]) => theme.textTheme.bodySmall
        ?.copyWith(color: OmniTheme.colors.textSecondary, fontWeight: weight);

    return Row(
      children: [
        Expanded(
          child: _FilterDropdown(
            key: const Key('exercise_filter_discipline'),
            label: 'Discipline',
            value: disciplineId,
            onChanged: onDisciplineChanged,
            items: [
              DropdownMenuItem(
                value: null,
                child: Text('All', style: itemStyle()),
              ),
              ...disciplines.map(
                (d) => DropdownMenuItem(
                  value: d.id,
                  child: Text(
                    d.name,
                    overflow: TextOverflow.ellipsis,
                    style: itemStyle(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FilterDropdown(
            key: const Key('exercise_filter_muscle'),
            label: 'Muscle',
            value: muscleGroupId,
            onChanged: onMuscleChanged,
            items: [
              DropdownMenuItem(
                value: null,
                child: Text('All', style: itemStyle()),
              ),
              ...muscleEntries.map(
                (entry) => DropdownMenuItem(
                  value: entry.group.id,
                  child: Padding(
                    padding: EdgeInsets.only(left: 16.0 * entry.depth),
                    child: Text(
                      entry.group.name,
                      overflow: TextOverflow.ellipsis,
                      style: itemStyle(
                        entry.depth == 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            // The closed field shows the bare name, without the menu's indent.
            selectedItemBuilder: (context) => [
              Text('All', style: itemStyle()),
              for (final entry in muscleEntries)
                Text(
                  entry.group.name,
                  overflow: TextOverflow.ellipsis,
                  style: itemStyle(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final DropdownButtonBuilder? selectedItemBuilder;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.selectedItemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderSide: BorderSide(color: color),
      borderRadius: BorderRadius.circular(8),
    );

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      style: theme.textTheme.bodySmall?.copyWith(
        color: OmniTheme.colors.textSecondary,
      ),
      decoration: InputDecoration(
        labelText: label,
        enabledBorder: border(themeColors.surfaceBorder),
        focusedBorder: border(theme.colorScheme.primary),
        border: border(themeColors.surfaceBorder),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      items: items,
      selectedItemBuilder: selectedItemBuilder,
      onChanged: onChanged,
    );
  }
}
