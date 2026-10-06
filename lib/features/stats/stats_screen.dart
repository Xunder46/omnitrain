import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/fuel_summary.dart';
import '../../core/models/instrument_list.dart';
import '../../core/models/signals.dart';
import '../../core/models/stats_progress.dart';
import '../../core/models/training_load.dart';
import '../../core/services/signals/signal.dart';
import '../../core/services/signals_service.dart';
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
import 'widgets/signals_layer.dart';
import 'widgets/stats_pill.dart';
import 'widgets/stats_primer_sheet.dart';

class StatsScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final SettingsState settingsState;

  /// The signals the layer evaluates, or `null` for the app's registry.
  ///
  /// A seam for tests only: the shipped screen passes nothing and gets
  /// `buildSignalRegistry()` (D-1016).
  final List<Signal>? signals;

  /// Whether the first-use explanation surfaces render: the header "?" and
  /// the `How Stats works` button on the empty card.
  ///
  /// Defaults to `false`, so every existing `StatsScreen` consumer renders
  /// today's tree unchanged. The screen deliberately holds no
  /// `StatsPrimerState`: with `onDismiss: null` on both hosts it has no
  /// reference through which it could mark the flag, so reopening from here
  /// can never mark seen (D-2019).
  final bool showPrimerHelp;

  const StatsScreen({
    super.key,
    required this.workoutState,
    required this.settingsState,
    this.signals,
    this.showPrimerHelp = false,
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

  SignalsData? _signalsData;
  List<SignalCard> _signalsCandidates = const [];
  Map<String, int> _signalsDismissedAtMs = const {};
  SignalsService? _signalsService;

  /// The tail of the dismissal-write chain.
  ///
  /// Every dismissal appends its write to this future, so two rapid taps
  /// cannot race: the later store is written only after the earlier one, and
  /// the last write wins (S-1709, D-1010).
  Future<void> _signalsWriteTail = Future<void>.value();

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

      // One load reads one "now": the Mix layer and the signals are evaluated
      // against the same instant, so a card can never disagree with the layer
      // it sits under.
      final now = DateTime.now();

      // The Mix layer reads the same window as the Instruments list, so it
      // resolves nothing of its own.
      final mixLayer = await service.computeMixLayer(
        window: progressData.window,
        now: now,
        startOfWeek: widget.settingsState.startOfWeek,
      );

      // The signals share this load: the same service instance, so no second
      // walk of history, and the same `now` (D-1014). When the gate is unmet
      // nothing is evaluated and the layer is absent (D-1006).
      final signalsService = SignalsService(
        repository: widget.workoutState.repository,
        progressService: service,
        signals: widget.signals,
      );
      final gateMet = signalsGateMet(mixLayer);
      final signalsDismissedAtMs = gateMet
          ? await signalsService.loadDismissals()
          : const <String, int>{};
      final signalsCandidates = gateMet
          ? await signalsService.evaluateCandidates(
              now: now,
              window: progressData.window,
              mix: mixLayer,
              dismissedAtMs: signalsDismissedAtMs,
            )
          : const <SignalCard>[];
      final signalsData = gateMet
          ? resolveSignals(
              candidates: signalsCandidates,
              dismissedAtMs: signalsDismissedAtMs,
              now: now,
              gateMet: true,
            )
          : null;

      if (!mounted) return;

      setState(() {
        _totalSessions = totals.completedSessions;
        _totalDurationMs = totals.durationMs;
        _streakDays = streak;
        _window = progressData.window;
        _instrumentSections = instrumentSections;
        _fuelSummary = fuelSummary;
        _mixLayer = mixLayer;
        _signalsService = signalsService;
        _signalsCandidates = signalsCandidates;
        _signalsDismissedAtMs = signalsDismissedAtMs;
        _signalsData = signalsData;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// Records a dismissal and re-resolves the held candidates — no reload, no
  /// second walk of history (D-1010, D-1014).
  ///
  /// The view moves first, in the tap's own frame; the write is chained and
  /// forgotten, so a store that is slow (or fails) cannot hold the card on
  /// screen and cannot reorder a later dismissal's write.
  void _dismissSignal(String id) {
    final service = _signalsService;
    if (service == null) return;

    final now = DateTime.now();
    final next = signalDismissalsWith(_signalsDismissedAtMs, id, now);
    if (!mounted) return;

    setState(() {
      _signalsDismissedAtMs = next;
      _signalsData = resolveSignals(
        candidates: _signalsCandidates,
        dismissedAtMs: next,
        now: now,
        gateMet: signalsGateMet(_mixLayer),
      );
    });

    final store = next;
    _signalsWriteTail = _signalsWriteTail.then(
      (_) => _persistSignalDismissals(service, store),
    );
  }

  /// Writes [store], never throwing: a dismissal whose write fails is simply
  /// not remembered, and the caller has already moved the view on (D-1010).
  Future<void> _persistSignalDismissals(
    SignalsService service,
    Map<String, int> store,
  ) async {
    try {
      await service.persistDismissals(store);
    } catch (_) {
      // Not remembered; nothing else changes.
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
              if (widget.showPrimerHelp)
                Semantics(
                  label: 'About Stats',
                  button: true,
                  child: IconButton(
                    key: const Key('stats_primer_help'),
                    icon: const Icon(Icons.help_outline),
                    color: OmniTheme.colors.textDominant,
                    tooltip: 'About Stats',
                    onPressed: _reopenPrimer,
                  ),
                ),
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
                            if (_signalsData != null) ...[
                              SignalsLayerSection(
                                data: _signalsData!,
                                themeColors: themeColors,
                                onDismiss: _dismissSignal,
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

  /// Reopen the one-shot primer sheet at any time. The seen state is NOT
  /// mutated — the screen holds no primer state and hosts the sheet with a
  /// null `onDismiss`, so the "?" and the empty-card button are the way to
  /// read the primer without committing (D-2019).
  Future<void> _reopenPrimer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: const StatsPrimerSheet(),
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
          if (widget.showPrimerHelp) ...[
            const SizedBox(height: 12),
            Text(
              'Your training mix, by kind of work.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your records, and how each exercise changes over time.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How your eating lines up with your training, once you log '
              'food.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('stats_primer_empty_cta'),
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        OmniTheme.buttonUtilityRadius,
                      ),
                    ),
                  ),
                ),
                onPressed: _reopenPrimer,
                child: const Text('How Stats works'),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Formats a duration in milliseconds as "Xh Ym" for all-time totals.
  String _formatDuration(int ms) => OmniDateUtils.formatDurationHoursMins(ms);
}
