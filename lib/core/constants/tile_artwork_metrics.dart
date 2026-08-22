import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The single height-responsive sizing rule shared by every tile that pairs
/// decorative artwork with a label.
///
/// Two grids consume it: the Home training grid (`EnergyTile`) and the hub
/// sheet's destination grid (`MaintenanceTile`). Neither owns the rule and
/// neither restates it — both call [resolve] and render what it reports.
///
/// ## The contract the rule encodes
///
/// The label is the content; the artwork is decoration. So the label is
/// reserved first, at full size, and the artwork takes whatever vertical
/// space is left over. Below [minArtworkSize] of leftover space the artwork
/// is dropped entirely and the label is centred. Because the rule depends
/// only on tile height (never width), every tile in a grid crosses the drop
/// threshold at the same moment — a grid can never show artwork on some
/// tiles and not others.
///
/// The numbers here were extracted verbatim from `EnergyTile`'s former
/// private layout block. Changing any of them changes both grids.
@immutable
class TileArtworkMetrics {
  /// Leftover artwork space below which the artwork is omitted entirely.
  ///
  /// Applies identically to standard icons and to custom-drawn artwork.
  static const double minArtworkSize = 16.0;

  /// Breathing room above the artwork so it never collides with a tile's
  /// top-right status indicator.
  static const double artworkTopInset = 15.0;

  /// Vertical space reserved between the artwork and the label on a tile
  /// tall enough to afford it. Compressed on shorter tiles so the label
  /// itself never has to shrink.
  static const double labelGapReserve = 20.0;

  /// The gap is split 40% above the label and 60% below it.
  static const double _labelGapTopShare = 0.4;

  static const double minOuterPadding = 4.0;
  static const double maxOuterPadding = 20.0;
  static const double _outerPaddingRatio = 0.1;

  /// Padding between the tile's surface edge and its content.
  final double outerPadding;

  /// Total vertical gap reserved around the label.
  final double labelGap;

  /// Whether the tile has room to render artwork at all.
  final bool showArtwork;

  /// Edge length of the artwork. Zero when [showArtwork] is false.
  ///
  /// This is the only artwork dimension in the codebase. A tile definition
  /// states *which* artwork to show; this states how large it renders.
  final double artworkSize;

  const TileArtworkMetrics._({
    required this.outerPadding,
    required this.labelGap,
    required this.showArtwork,
    required this.artworkSize,
  });

  /// Space above the label, when the artwork is present.
  double get labelGapTop => labelGap * _labelGapTopShare;

  /// Space below the label, when the artwork is present.
  double get labelGapBottom => labelGap * (1 - _labelGapTopShare);

  /// Resolves the rule for a tile of [tileHeight].
  ///
  /// [maxArtworkSize] is the artwork's size on a tile with room to spare —
  /// the per-tier ceiling, not a fixed dimension. [labelLineHeight] is the
  /// label's already-text-scaled line height; the caller supplies it because
  /// the two grids use different label styles.
  static TileArtworkMetrics resolve({
    required double tileHeight,
    required double maxArtworkSize,
    required double labelLineHeight,
  }) {
    // Outer padding scales with tile height, floored so the Home grid's
    // 56-point tile still has breathing room and capped so tall tiles keep
    // the original 200x200 look.
    final outerPadding = math.min(
      maxOuterPadding,
      math.max(minOuterPadding, tileHeight * _outerPaddingRatio),
    );

    final contentHeight = tileHeight - 2 * outerPadding;

    // The label is pinned first and always at full size. When the tile is
    // too short to afford the full gap, the gap compresses rather than the
    // label.
    final labelGap = math.max(
      0.0,
      math.min(labelGapReserve, contentHeight - labelLineHeight),
    );

    // Whatever survives the label reservation is the artwork's budget.
    final artworkBudget = math.max(
      0.0,
      contentHeight - (labelLineHeight + labelGap) - artworkTopInset,
    );

    final showArtwork = artworkBudget >= minArtworkSize;

    return TileArtworkMetrics._(
      outerPadding: outerPadding,
      labelGap: labelGap,
      showArtwork: showArtwork,
      artworkSize: showArtwork ? math.min(maxArtworkSize, artworkBudget) : 0.0,
    );
  }
}

/// Builds custom-drawn tile artwork at the size and colour the shared rule
/// resolved.
///
/// Tile definitions reference a builder, never a constructed widget, so the
/// definition cannot smuggle a fixed size past the rule. Standard icons and
/// custom artwork therefore shrink and drop out at exactly the same points.
typedef TileArtworkBuilder = Widget Function(double size, Color color);
