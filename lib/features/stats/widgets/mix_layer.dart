// The Mix layer (Stats PR 5b, Phase 1) — the window's training mix, drawn.
//
// The layer renders the model: every figure it shows is one `MixLayerData`
// already carries. The arithmetic it does itself is presentation only — the
// flex that turns a measure into a share of the bar, and the tallest week that
// sets one scale for all eight strip columns. The measure decides which figures
// the strip names — minutes or load — and the model decides which of the two
// the window supports (D-920, D-921). The copy says as much in words, once
// (D-3201).
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

  String get _unit => _isLoad ? 'load' : 'min';

  /// What the card is splitting, in words (D-3201). The measure itself is the
  /// model's (D-920, D-921); this only says it out loud, once.
  String get _explainer => _isLoad
      ? 'Your training split by how hard each session felt.'
      : 'Your training split by time spent.';

  /// The rated weeks behind the window, held to the threshold the baseline note
  /// names (D-3204).
  int get _ratedWeeks =>
      layer.ratedBaselineWeeks.clamp(0, kTrainingLoadMinRatedWeeks);

  /// How much of the window carried no effort rating (D-3204). Under the load
  /// measure the sessions are missing from the figures above; under the time
  /// measure they are counted, they simply carry no rating.
  String get _unratedNote {
    final count = layer.unratedSessionCount;
    if (_isLoad) {
      return count == 1
          ? "1 session isn't counted – no effort rating yet"
          : "$count sessions aren't counted – no effort rating yet";
    }
    return count == 1
        ? '1 session has no effort rating yet'
        : '$count sessions have no effort rating yet';
  }

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

  /// Whether the payload carries weeks, none of them holds any work, and the
  /// span holds no session either (D-4004, S-4021).
  ///
  /// An empty [MixLayerData.weeks] is *not* an empty strip: that payload has
  /// no strip at all (the period payload D-1204 returns), and neither the
  /// strip nor the empty line is a claim it can support.
  ///
  /// Nor is a span a session sits inside: a completed session can carry zero
  /// measure (unrated under the load measure, zero-duration under the time
  /// one), and the line would then say "no training in the last 8 weeks" while
  /// naming a session *within* those 8 weeks. When a session lies inside the
  /// span the strip draws, and the empty line stays out.
  bool get _stripIsEmpty =>
      layer.weeks.isNotEmpty &&
      layer.weeks.every((week) => week.measure <= 0) &&
      (layer.lastSessionDay == null ||
          layer.lastSessionDay!.isBefore(layer.weeks.first.weekStart));

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
          _buildExplainer(theme),
          const SizedBox(height: _tightGap),
          if (usualSegments.isNotEmpty) ...[
            _buildWindowBarLabel(theme),
            const SizedBox(height: _tightGap),
          ],
          _buildBar(),
          if (usualSegments.isNotEmpty) ...[
            const SizedBox(height: _tightGap),
            Text(
              'Your usual',
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
              'Showing time for now. Effort appears once '
              '$kTrainingLoadMinRatedWeeks weeks are rated '
              '($_ratedWeeks of $kTrainingLoadMinRatedWeeks so far).',
              key: const Key('mix_baseline_note'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
          ],
          if (layer.unratedSessionCount > 0) ...[
            const SizedBox(height: _tightGap),
            Text(
              _unratedNote,
              key: const Key('mix_unrated_note'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: _blockGap),
          if (_stripIsEmpty)
            _buildEmptyStrip(theme)
          else if (layer.weeks.isNotEmpty) ...[
            Text(
              'Week by week · last $kMixStripWeeks weeks',
              key: const Key('mix_strip_title'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: _tightGap),
            _buildStrip(maxWeekMeasure),
            const SizedBox(height: _tightGap),
            _buildCaption(theme),
          ],
        ],
      ),
    );
  }

  /// The one sentence that says what the bars split (D-3201). It replaces the
  /// `by load` / `by time` labels that sat above the bar and above the strip:
  /// the same words repeated twice explained nothing.
  Widget _buildExplainer(ThemeData theme) => Text(
    _explainer,
    key: const Key('mix_explainer'),
    style: theme.textTheme.bodySmall?.copyWith(
      color: themeColors.textSecondary,
    ),
  );

  /// The first bar's label, drawn only when a second bar sits under it and the
  /// two need telling apart (D-3202).
  Widget _buildWindowBarLabel(ThemeData theme) => Text(
    'In this window',
    key: const Key('mix_window_bar_label'),
    style: theme.textTheme.labelSmall?.copyWith(color: themeColors.textMuted),
  );

  /// The strip's caption: how far back the columns reach on the left, and that
  /// the last one is still running on the right, so the eight columns carry a
  /// time axis (D-3205). The oldest week's own start day is still read out by
  /// its column (D-3205: `_weekLabel`).
  ///
  /// Both ends are flexible: at the largest text scale the two labels are wider
  /// than the card together, and a flexible label ellipsises instead of
  /// overflowing the strip's Row.
  Widget _buildCaption(ThemeData theme) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        fit: FlexFit.loose,
        child: Text(
          '${kMixStripWeeks - 1} weeks ago',
          key: const Key('mix_strip_start_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: themeColors.textMuted,
          ),
        ),
      ),
      Flexible(
        child: Text(
          'This week so far',
          key: const Key('mix_strip_current_label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: themeColors.textMuted,
          ),
        ),
      ),
    ],
  );

  /// The empty strip's one line: eight weeks with no work at all are not a
  /// strip, and the line says so in words (D-4004).
  ///
  /// The last session's day is the payload's own ([MixLayerData.lastSessionDay]),
  /// never re-derived here and never read from a clock.
  Widget _buildEmptyStrip(ThemeData theme) {
    final lastSessionDay = layer.lastSessionDay;
    return Text(
      lastSessionDay == null
          ? 'No training in the last $kMixStripWeeks weeks.'
          : 'No training in the last $kMixStripWeeks weeks. '
                'Last session: ${OmniDateUtils.formatShort(lastSessionDay)}.',
      key: const Key('mix_strip_empty'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: themeColors.textMuted,
      ),
    );
  }

  /// The bar: one segment per modality, in the model's order, at the model's
  /// proportions.
  ///
  /// Its semantics label names the same figures the legend does — a 0% segment
  /// still reads here, even though the legend drops it (D-3203).
  Widget _buildBar() {
    final label = layer.segments
        .map((segment) => '${segment.section.label} ${segment.percent}%')
        .join(', ');

    return Semantics(
      key: const Key('mix_bar'),
      container: true,
      label: 'Training mix: $label',
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

  /// The legend: a colour dot and the share per modality, so the bar's colours
  /// mean something without counting positions (D-3203).
  ///
  /// A modality with no share is left out — `Sports 0%` explained nothing (the
  /// bar still draws its sliver and still reads it out in its semantics).
  /// Decorative otherwise: the bar's semantics already reads the same figures,
  /// so the text is excluded from the tree rather than repeated in it.
  Widget _buildLegend(ThemeData theme) => ExcludeSemantics(
    child: Wrap(
      key: const Key('mix_legend'),
      spacing: 16,
      runSpacing: 6,
      children: [
        for (var i = 0; i < layer.segments.length; i++)
          if (layer.segments[i].percent > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: Key('mix_legend_dot_$i'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colorFor(layer.segments[i].section),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                // The label shrinks instead of running past the card: at the
                // largest text scale a full `Resistance 98%` is wider than the
                // card beside its dot.
                Flexible(
                  child: Text(
                    '${layer.segments[i].section.label} '
                    '${layer.segments[i].percent}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: themeColors.textSecondary,
                    ),
                  ),
                ),
              ],
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
              // A week with no work still shows a floor: a 2 dp mark in the
              // card's muted colour, so the strip reads as eight weeks and not
              // as one lone bar (D-3206).
              if (week.measure <= 0)
                Container(
                  key: Key('mix_week_${index}_empty'),
                  height: 2,
                  color: themeColors.textMuted,
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
