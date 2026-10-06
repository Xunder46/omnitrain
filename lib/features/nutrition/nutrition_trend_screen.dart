import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/stats_progress.dart';
import '../../core/services/stats_progress_service.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import 'widgets/nutrition_trend_card.dart';

/// The full-history nutrition trend.
///
/// Both hosts pass the same card the same repository data.
class NutritionTrendScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final SettingsState settingsState;

  const NutritionTrendScreen({
    super.key,
    required this.workoutState,
    required this.settingsState,
  });

  @override
  State<NutritionTrendScreen> createState() => _NutritionTrendScreenState();
}

class _NutritionTrendScreenState extends State<NutritionTrendScreen> {
  bool _isLoading = true;
  List<NutritionTrendPoint> _trend = const [];
  NutritionAdherence? _adherence;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      // One service instance for the whole load: it caches its history
      // snapshot per instance, so both calls share a single read.
      final service = StatsProgressService(widget.workoutState.repository);
      // `days: null` is the point of this screen — full history.
      final trend = await service.computeNutritionTrend(days: null);
      final adherence = await service.computeNutritionAdherence();

      if (!mounted) return;
      setState(() {
        _trend = trend;
        _adherence = adherence;
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
          appBar: const OmniBackHeader(
            title: 'Nutrition',
            subtitle: 'Full history',
          ),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      const OmniCardHeader(title: 'NUTRITION'),
                      NutritionTrendCard(
                        trend: _trend,
                        adherence: _adherence,
                        themeColors: themeColors,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
