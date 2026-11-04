import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/exercise_metric.dart';
import '../../../core/models/instrument_list.dart';
import '../../../core/models/stats_progress.dart';
import '../../../core/navigation/omni_navigator.dart';
import '../../../state/settings/settings_state.dart';
import '../../../state/workout/workout_state.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../exercise_progress_screen.dart';
import 'instrument_row.dart';

/// How many rows a section shows before it offers to show the rest. The cap is
/// per section, so a busy kind of work never hides a quiet one.
const int kInstrumentRowCap = 5;

/// The window's work, one section per kind, one row per exercise, each section
/// expandable past [kInstrumentRowCap].
class InstrumentList extends StatefulWidget {
  final List<InstrumentSectionData> sections;
  final StatsWindow window;
  final OmniThemeColors themeColors;
  final WorkoutState workoutState;
  final SettingsState settingsState;

  const InstrumentList({
    super.key,
    required this.sections,
    required this.window,
    required this.themeColors,
    required this.workoutState,
    required this.settingsState,
  });

  @override
  State<InstrumentList> createState() => _InstrumentListState();
}

class _InstrumentListState extends State<InstrumentList> {
  /// Expanded sections, by kind. Local to this widget and keyed on the section,
  /// so expanding one section never expands another.
  final Set<ExerciseSection> _expanded = <ExerciseSection>{};

  void _toggle(ExerciseSection section) {
    setState(() {
      if (!_expanded.remove(section)) _expanded.add(section);
    });
  }

  void _openExercise(String exerciseId) {
    OmniNavigator.push(
      context,
      (_) => ExerciseProgressScreen(
        workoutState: widget.workoutState,
        settingsState: widget.settingsState,
        exerciseId: exerciseId,
      ),
    );
  }

  /// Whole weeks when the window is a multiple of seven days, otherwise days.
  static String _span(int days) {
    if (days % 7 == 0) {
      final weeks = days ~/ 7;
      return weeks == 1 ? '1 week' : '$weeks weeks';
    }
    return days == 1 ? '1 day' : '$days days';
  }

  /// The one line under the first header: the window in words, then what the
  /// change is measured against (D-17303).
  Text _caption(BuildContext context) {
    final window = widget.window;
    return Text(
      '${window.label}. Change is against the ${_span(window.dayCount)} before.',
      key: const Key('instrument_caption'),
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: widget.themeColors.textMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    for (var i = 0; i < widget.sections.length; i++) {
      final section = widget.sections[i];
      final expanded = _expanded.contains(section.section);
      final rows = expanded
          ? section.rows
          : section.rows.take(kInstrumentRowCap).toList();

      children.add(OmniCardHeader(title: section.section.label.toUpperCase()));

      if (i == 0) children.add(_caption(context));

      for (final row in rows) {
        children.add(
          InstrumentRowTile(
            row: row,
            settingsState: widget.settingsState,
            themeColors: widget.themeColors,
            onTap: () => _openExercise(row.summary.exerciseId),
          ),
        );
      }

      if (section.rows.length > kInstrumentRowCap) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: Key('instrument_show_all_${section.section.name}'),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              onPressed: () => _toggle(section.section),
              child: Text(
                expanded ? 'Show less' : 'Show all (${section.rows.length})',
              ),
            ),
          ),
        );
      }

      if (i < widget.sections.length - 1) {
        children.add(const SizedBox(height: 8));
      }
    }

    return Column(
      key: const Key('instrument_list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
