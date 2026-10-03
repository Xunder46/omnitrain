// The Mix layer (Stats PR 5b, Phase 1) — the window's training mix, drawn.
//
// The layer renders and computes nothing: every figure it shows is one
// `MixLayerData` already carries, so the widget is a pure function of the
// model. The measure decides the vocabulary — `by time` reads minutes, `by
// load` reads load — and the model decides which of the two the window
// supports (D-920, D-921).
//
// The usual bar and the baseline note are mutually exclusive by construction:
// the usual bar needs a load baseline, and the note exists only to explain why
// the load measure is unavailable (D-934).

import 'package:flutter/material.dart';

import '../../../core/constants/modality_colors.dart';
import '../../../core/constants/omni_theme.dart';
import '../../../core/models/exercise_metric.dart';
import '../../../core/models/stats_progress.dart';
import '../../../core/models/training_load.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../../../widgets/layout/omni_surface.dart';
import 'window_chip.dart';

/// The window's training mix: a modality bar, the usual split behind it, and
/// the last [kMixStripWeeks] weeks as a stacked strip.
class MixLayerSection extends StatelessWidget {
  final MixLayerData layer;
  final StatsWindow window;
  final OmniThemeColors themeColors;

  const MixLayerSection({
    super.key,
    required this.layer,
    required this.window,
    required this.themeColors,
  });

  // Geometry. Local to the layer: no other surface draws a mix bar, so these
  // are not theme tokens.
  static const double _barHeight = 14;
  static const double _barGap = 3;
  static const double _usualBarHeight = 6;
  static const double _stripHeight = 64;
  static const double _weekGap = 6;
  static const double _blockGap = 16;
  static const double _tightGap = 6;

  /// The section colours. `ModalityColors` is keyed by `Modality`, and the
  /// summary-group map spells resistance `strength`, so the section accents are
  /// named here rather than derived.
  static const Map<ExerciseSection, Color> _sectionColors = {
    ExerciseSection.resistance: ModalityColors.resistanceLifting,
    ExerciseSection.cardio: ModalityColors.cardioEndurance,
    ExerciseSection.isometric: ModalityColors.isometricStretching,
    ExerciseSection.sports: ModalityColors.sports,
  };

  static Color _colorFor(ExerciseSection section) =>
      _sectionColors[section] ?? ModalityColors.resistanceLifting;

  /// A segment's share of the bar, as an integer flex. Scaled so a small share
  /// of a large total still gets a visible sliver.
  static int _flex(double measure) {
    final flex = (measure * 1000).round();
    return flex < 1 ? 1 : flex;
  }

  bool get _isLoad => layer.measure == MixMeasure.load;

  String get _measureLabel => _isLoad ? 'by load' : 'by time';

  String get _unit => _isLoad ? 'load' : 'min';

  /// The baseline's segments in display order: the bar's modalities first, in
  /// the bar's order, then any modality the baseline has and the window does
  /// not, in declaration order.
  List<MixSegment> get _usualSegments {
    final remaining = <ExerciseSection, MixSegment>{
      for (final segment in layer.baselineSegments) segment.section: segment,
    };
    final ordered = <MixSegment>[];
    for (final segment in layer.segments) {
      final match = remaining.remove(segment.section);
      if (match != null) ordered.add(match);
    }
    for (final section in ExerciseSection.values) {
      final match = remaining.remove(section);
      if (match != null) ordered.add(match);
    }
    return ordered;
  }

  /// The tallest week in the strip, so the columns share one scale.
  double get _maxWeekMeasure {
    var max = 0.0;
    for (final week in layer.weeks) {
      if (week.measure > max) max = week.measure;
    }
    return max;
  }

  String _weekLabel(MixWeek week) {
    final figure = week.measure.round();
    final base =
        '${OmniDateUtils.formatShort(week.weekStart)}: $figure $_unit';
    return week.inProgress ? '$base (in progress)' : base;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usualSegments = _usualSegments;
    final maxWeekMeasure = _maxWeekMeasure;

    return OmniSurface(
      key: const Key('mix_layer'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OmniCardHeader(
            title: 'TRAINING MIX',
            actions: [
              StatsWindowChip(window: window, themeColors: themeColors),
            ],
          ),
          const SizedBox(height: _blockGap),
          _measureText(theme),
          const SizedBox(height: _tightGap),
          _buildBar(),
          if (usualSegments.isNotEmpty) ...[
            const SizedBox(height: _tightGap),
            Text(
              'usual',
              key: const Key('mix_usual_label'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 2),
            _buildUsualBar(usualSegments),
          ],
          const SizedBox(height: _blockGap),
          _buildLegend(theme),
          if (!_isLoad && layer.ratedBaselineWeeks < kTrainingLoadMinRatedWeeks) ...[
            const SizedBox(height: _tightGap),
            Text(
              'Load baseline: '
              '${layer.ratedBaselineWeeks.clamp(0, kTrainingLoadMinRatedWeeks)}'
              ' of $kTrainingLoadMinRatedWeeks weeks rated',
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
          ],
          if (layer.unratedSessionCount > 0) ...[
            const SizedBox(height: _tightGap),
            Text(
              layer.unratedSessionCount == 1
                  ? '1 unrated session'
                  : '${layer.unratedSessionCount} unrated sessions',
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: _blockGap),
          _measureText(theme),
          const SizedBox(height: _tightGap),
          _buildStrip(maxWeekMeasure),
        ],
      ),
    );
  }

  Widget _measureText(ThemeData theme) => Text(
    _measureLabel,
    style: theme.textTheme.labelSmall?.copyWith(color: themeColors.textMuted),
  );

  /// The bar: one segment per modality, in the model's order, at the model's
  /// proportions.
  Widget _buildBar() {
    final label = layer.segments
        .map((segment) => '${segment.section.label} ${segment.percent}%')
        .join(', ');

    return Semantics(
      key: const Key('mix_bar'),
      container: true,
      label: 'Training mix $_measureLabel: $label',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        child: SizedBox(
          height: _barHeight,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              for (var i = 0; i < layer.segments.length; i++) ...[
                if (i > 0) const SizedBox(width: _barGap),
                Expanded(
                  flex: _flex(layer.segments[i].measure),
                  child: Container(
                    key: Key('mix_bar_segment_$i'),
                    color: _colorFor(layer.segments[i].section),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The usual split: the same width as the bar, a fraction of its height, so
  /// the two read as one comparison.
  Widget _buildUsualBar(List<MixSegment> segments) {
    final label = segments
        .map((segment) => '${segment.section.label} ${segment.percent}%')
        .join(', ');

    return Semantics(
      key: const Key('mix_usual_bar'),
      container: true,
      label: 'Usual split: $label',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        child: SizedBox(
          height: _usualBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const SizedBox(width: _barGap),
                Expanded(
                  flex: _flex(segments[i].measure),
                  child: Container(
                    key: Key('mix_usual_segment_$i'),
                    color: _colorFor(segments[i].section),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The legend. Decorative: the bar's semantics already read the same figures
  /// out, so the text is excluded from the tree rather than repeated in it.
  Widget _buildLegend(ThemeData theme) => ExcludeSemantics(
    child: Wrap(
      key: const Key('mix_legend'),
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final segment in layer.segments)
          Text(
            '${segment.section.label} ${segment.percent}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: themeColors.textSecondary,
            ),
          ),
      ],
    ),
  );

  /// The strip: one column per week, oldest first, each stacked bottom-up by
  /// modality and scaled against the tallest week.
  Widget _buildStrip(double maxWeekMeasure) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (var i = 0; i < layer.weeks.length; i++) ...[
        if (i > 0) const SizedBox(width: _weekGap),
        Expanded(child: _buildWeekColumn(i, maxWeekMeasure)),
      ],
    ],
  );

  Widget _buildWeekColumn(int index, double maxWeekMeasure) {
    final week = layer.weeks[index];
    final column = Semantics(
      key: Key('mix_week_${index}_semantics'),
      container: true,
      label: _weekLabel(week),
      child: Container(
        key: Key('mix_week_$index'),
        height: _stripHeight,
        // A foreground decoration draws the mark without insetting the child:
        // a background decoration's border would take its 2 dp out of the
        // fixed column height and overflow the stack by exactly that much.
        foregroundDecoration: week.inProgress
            ? BoxDecoration(
                borderRadius:
                    BorderRadius.circular(OmniTheme.buttonUtilityRadius),
                border: Border.all(
                  color: themeColors.textMuted,
                  width: OmniTheme.surfaceBorderWidth,
                ),
              )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Bottom-most first, so the largest modality sits on the floor.
              for (var j = week.segments.length - 1; j >= 0; j--)
                Container(
                  key: Key('mix_week_${index}_segment_$j'),
                  height: maxWeekMeasure <= 0
                      ? 0
                      : week.segments[j].measure / maxWeekMeasure * _stripHeight,
                  color: _colorFor(week.segments[j].section),
                ),
            ],
          ),
        ),
      ),
    );

    // The current week is marked on the column itself, so the marker and the
    // column are one widget to a reader.
    return week.inProgress
        ? KeyedSubtree(key: const Key('mix_week_current'), child: column)
        : column;
  }
}
