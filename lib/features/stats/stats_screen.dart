import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/fuel_summary.dart';
import '../../core/models/instrument_list.dart';
import '../../core/models/stats_progress.dart';
import '../../core/models/training_load.dart';
import '../../core/services/stats_progress_service.dart';
import '../../core/utils/date_utils.dart';
import '../../core/navigation/omni_navigator.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../nutrition/nutrition_trend_screen.dart';
import 'records_and_trends_screen.dart';
import 'widgets/fuel_section.dart';
import 'widgets/instrument_list.dart';
import 'widgets/mix_layer.dart';
import 'widgets/stats_pill.dart';

class StatsScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final SettingsState settingsState;

  const StatsScreen({
    super.key,
    required this.workoutState,
    required this.settingsState,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;
  int _totalSessions = 0;
  int _totalDurationMs = 0;
  int _streakDays = 0;

  StatsWindow? _window;
  List<InstrumentSectionData> _instrumentSections = const [];

  FuelSummary? _fuelSummary;

  MixLayerData? _mixLayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      // Reuse CalendarState streak logic — do not re-implement the calculation.
      final calendarState = CalendarState(widget.workoutState.repository);
      await calendarState.init();
      final streak = calendarState.streakDays;

      // One service instance for the whole load. The service caches its
      // history snapshot per instance, so every `compute*` call below
      // shares a single read of the repository — constructing a second
      // instance here would silently double that cost.
      final service = StatsProgressService(widget.workoutState.repository);

      // All-time aggregates (completed sessions and their duration) come from
      // the service, so the screen and Records & Trends agree on the figures.
      final totals = await service.computeTotals();

      // Compute progress data in one call so we don't double-walk the
      // repository: this screen reads the window (shared with the Instruments
      // list below).
      final progressData = await service.computeProgressData();

      // The Fuel row's own window, resolved in the same load as everything
      // else so the row never computes during a build.
      final fuelSummary = await service.computeFuelSummary();

      // The Instruments list is the same window's work, so it resolves the
      // window from the data we already have rather than resolving it again.
      final instrumentSections = await service.computeInstrumentSections(
        window: progressData.window,
      );

      // The Mix layer reads the same window as the Instruments list, so it
      // resolves nothing of its own.
      final mixLayer = await service.computeMixLayer(
        window: progressData.window,
        now: DateTime.now(),
        startOfWeek: widget.settingsState.startOfWeek,
      );

      if (!mounted) return;

      setState(() {
        _totalSessions = totals.completedSessions;
        _totalDurationMs = totals.durationMs;
        _streakDays = streak;
        _window = progressData.window;
        _instrumentSections = instrumentSections;
        _fuelSummary = fuelSummary;
        _mixLayer = mixLayer;
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
        final window = _window;

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: OmniBackHeader(
            title: 'Stats',
            actions: [
              Semantics(
                label: 'Records & Trends',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.show_chart),
                  color: OmniTheme.colors.textDominant,
                  tooltip: 'Records & Trends',
                  onPressed: () => OmniNavigator.push(
                    context,
                    (_) => RecordsAndTrendsScreen(
                      workoutState: widget.workoutState,
                      settingsState: widget.settingsState,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: _totalSessions == 0
                        ? [_buildEmptyState(context, themeColors)]
                        : [
                            if (_mixLayer != null && window != null) ...[
                              MixLayerSection(
                                layer: _mixLayer!,
                                window: window,
                                themeColors: themeColors,
                              ),
                              const SizedBox(height: 24),
                            ],
                            const OmniCardHeader(title: 'ALL TIME'),
                            _buildAggregateCard(context, themeColors),
                            const SizedBox(height: 24),
                            if (window != null &&
                                _instrumentSections.isNotEmpty) ...[
                              InstrumentList(
                                sections: _instrumentSections,
                                window: window,
                                themeColors: themeColors,
                                workoutState: widget.workoutState,
                                settingsState: widget.settingsState,
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (_fuelSummary != null) ...[
                              FuelSection(
                                summary: _fuelSummary!,
                                themeColors: themeColors,
                                onTap: () => OmniNavigator.push(
                                  context,
                                  (_) => NutritionTrendScreen(
                                    workoutState: widget.workoutState,
                                    settingsState: widget.settingsState,
                                  ),
                                ),
                              ),
                            ],
                          ],
                  ),
          ),
        );
      },
    );
  }

  // ── All-time aggregate ────────────────────────────────────────────────────

  Widget _buildAggregateCard(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final theme = Theme.of(context);

    return OmniSurface(
      key: const Key('all_time_card'),
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
              value: _formatDuration(_totalDurationMs),
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

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context, OmniThemeColors themeColors) {
    final theme = Theme.of(context);

    return OmniSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.bar_chart_outlined,
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

  /// Formats a duration in milliseconds as "Xh Ym" for all-time totals.
  String _formatDuration(int ms) => OmniDateUtils.formatDurationHoursMins(ms);
}
