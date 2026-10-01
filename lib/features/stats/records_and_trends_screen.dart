import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/exercise_metric.dart';
import '../../core/models/stats_progress.dart';
import '../../core/navigation/omni_navigator.dart';
import '../../core/services/stats_progress_service.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/fuzzy_search.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/layout/omni_surface.dart';
import 'exercise_progress_screen.dart';
import 'widgets/native_value_format.dart';
import 'widgets/recent_pr_list.dart';
import 'widgets/stats_pill.dart';

/// Every exercise the user has logged, grouped by section, with a search
/// filter and the all-time figures the Stats screen shows.
///
/// One read of the repository feeds the whole screen: one
/// [StatsProgressService] answers the totals, the PR list and the per-exercise
/// metrics, so the figures here cannot disagree with each other.
class RecordsAndTrendsScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final SettingsState settingsState;

  const RecordsAndTrendsScreen({
    super.key,
    required this.workoutState,
    required this.settingsState,
  });

  @override
  State<RecordsAndTrendsScreen> createState() => _RecordsAndTrendsScreenState();
}

class _RecordsAndTrendsScreenState extends State<RecordsAndTrendsScreen> {
  bool _isLoading = true;
  int _totalSessions = 0;
  int _totalDurationMs = 0;
  int _streakDays = 0;
  List<StatsPR> _recentPRs = const [];
  List<ExerciseMetricSummary> _summaries = const [];

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Reuse CalendarState streak logic — the calendar keeps owning that
      // rule; this screen only displays it.
      final calendarState = CalendarState(widget.workoutState.repository);
      await calendarState.init();
      final streak = calendarState.streakDays;

      // One service instance for the whole load. The service caches its
      // history snapshot per instance, so every `compute*` call below shares a
      // single read of the repository.
      final service = StatsProgressService(widget.workoutState.repository);
      final totals = await service.computeTotals();
      final progressData = await service.computeProgressData();
      final summaries = await service.computeExerciseMetrics();

      if (!mounted) return;

      setState(() {
        _totalSessions = totals.completedSessions;
        _totalDurationMs = totals.durationMs;
        _streakDays = streak;
        _recentPRs = progressData.recentPRs;
        _summaries = summaries;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settingsState,
      builder: (context, _) {
        final themeColors = OmniTheme.colorsForTheme(
          widget.settingsState.appTheme,
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: const OmniBackHeader(title: 'Records & Trends'),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: _summaries.isEmpty
                        ? [_buildEmptyState(context, themeColors)]
                        : _buildContent(context, themeColors),
                  ),
          ),
        );
      },
    );
  }

  List<Widget> _buildContent(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final theme = Theme.of(context);
    final query = _query.trim();
    final children = <Widget>[
      const OmniCardHeader(title: 'ALL TIME'),
      _buildAggregateCard(context, themeColors),
    ];

    if (_recentPRs.isNotEmpty) {
      children.add(const SizedBox(height: 24));
      children.add(
        RecentPRList(prs: _recentPRs, settingsState: widget.settingsState),
      );
    }

    children.add(const SizedBox(height: 24));
    children.add(
      TextField(
        key: const Key('records_and_trends_search_field'),
        controller: _searchController,
        textCapitalization: TextCapitalization.none,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: 'Search exercises...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: themeColors.surfaceBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: themeColors.surfaceBorder),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );

    for (final section in ExerciseSection.values) {
      final entries =
          _summaries
              .where(
                (summary) =>
                    summary.section == section &&
                    (query.isEmpty || FuzzySearch.matches(query, summary.name)),
              )
              .toList()
            ..sort((a, b) {
              // Training-day share descending: the exercises the user trains most
              // often lead the section. Ties fall back to the name, so the order
              // never depends on how the store happened to return the rows.
              final byShare = b.points.length.compareTo(a.points.length);
              if (byShare != 0) return byShare;
              final byName = a.name.compareTo(b.name);
              return byName != 0
                  ? byName
                  : a.exerciseId.compareTo(b.exerciseId);
            });
      if (entries.isEmpty) continue;

      children.add(const SizedBox(height: 24));
      children.add(OmniCardHeader(title: section.label));
      for (final summary in entries) {
        children.add(_buildEntry(context, themeColors, summary));
      }
    }

    return children;
  }

  Widget _buildAggregateCard(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final theme = Theme.of(context);

    return OmniSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: StatsPill(
              label: 'Sessions',
              value: _totalSessions.toString(),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: StatsPill(
              label: 'Time',
              value: OmniDateUtils.formatDurationHoursMins(_totalDurationMs),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: StatsPill(
              label: 'Streak',
              value: '$_streakDays d',
              themeColors: themeColors,
              theme: theme,
              trailingIcon: _streakDays >= 3
                  ? Icon(
                      Icons.local_fire_department,
                      size: 18,
                      color: themeColors.primary,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(
    BuildContext context,
    OmniThemeColors themeColors,
    ExerciseMetricSummary summary,
  ) {
    final theme = Theme.of(context);
    final secondary = formatNativeSecondary(summary.best, widget.settingsState);
    final lastTrained = OmniDateUtils.formatShort(
      DateTime.fromMillisecondsSinceEpoch(summary.lastTrainedMs),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OmniSurface(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: InkWell(
          key: Key('records_entry_${summary.exerciseId}'),
          onTap: () => OmniNavigator.push(
            context,
            (_) => ExerciseProgressScreen(
              workoutState: widget.workoutState,
              settingsState: widget.settingsState,
              exerciseId: summary.exerciseId,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: OmniTheme.colors.textDominant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last trained $lastTrained',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: themeColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatNativeValue(summary.best, widget.settingsState),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (secondary != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      secondary,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: themeColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, OmniThemeColors themeColors) {
    final theme = Theme.of(context);

    return OmniSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.show_chart,
            size: 48,
            color: themeColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No sessions yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: OmniTheme.colors.textDominant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete your first session to see stats here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: themeColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
