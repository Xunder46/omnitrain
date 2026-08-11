// Direct unit coverage for the shared tile artwork sizing rule.
//
// The rule used to live inside `EnergyTile`'s private layout block, where the
// only way to test it was to pump a widget and measure. It is now a pure
// function, so it is tested as one: artwork size at representative heights,
// monotonic behaviour, and the drop threshold. Both the Home training grid
// and the hub sheet's destination grid consume this — a drift here is a
// drift in both, which is exactly why it is cheap to pin down here.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/tile_artwork_metrics.dart';

/// The Home training tile's inputs: `titleSmall` at 16pt, primary tier.
TileArtworkMetrics _atHeight(
  double height, {
  double maxArtworkSize = 70,
  double labelLineHeight = 16,
}) {
  return TileArtworkMetrics.resolve(
    tileHeight: height,
    maxArtworkSize: maxArtworkSize,
    labelLineHeight: labelLineHeight,
  );
}

void main() {
  group('TileArtworkMetrics — outer padding', () {
    test('scales with tile height between a 4pt floor and a 20pt cap', () {
      // Floor: 10% of 56pt is 5.6pt, above the floor.
      expect(_atHeight(56).outerPadding, closeTo(5.6, 1e-9));
      // Floor bites below 40pt.
      expect(_atHeight(20).outerPadding, TileArtworkMetrics.minOuterPadding);
      // Cap bites above 200pt, preserving the original 200x200 look.
      expect(_atHeight(200).outerPadding, TileArtworkMetrics.maxOuterPadding);
      expect(_atHeight(400).outerPadding, TileArtworkMetrics.maxOuterPadding);
    });
  });

  group('TileArtworkMetrics — artwork size', () {
    test('a tall tile renders artwork at its full per-tier ceiling', () {
      expect(_atHeight(200).artworkSize, 70);
      expect(_atHeight(200, maxArtworkSize: 56).artworkSize, 56);
      expect(_atHeight(200, maxArtworkSize: 42).artworkSize, 42);
    });

    test('artwork never exceeds the ceiling it was given', () {
      for (final height in <double>[84, 120, 200, 400, 1000]) {
        final metrics = _atHeight(height, maxArtworkSize: 42);
        expect(
          metrics.artworkSize,
          lessThanOrEqualTo(42),
          reason: 'ceiling must hold at height $height',
        );
      }
    });

    test('representative heights produce the documented sizes', () {
      // budget = tileHeight - 2 * outerPadding - labelLine - labelGap
      //          - artworkTopInset
      // At these heights the outer padding is 10% and the label gap is at
      // its full 20pt reserve, so budget = 0.8h - 51.
      expect(_atHeight(120).artworkSize, closeTo(0.8 * 120 - 51, 1e-9)); // 45
      expect(_atHeight(96).artworkSize, closeTo(0.8 * 96 - 51, 1e-9)); // 25.8
      expect(_atHeight(84).artworkSize, closeTo(0.8 * 84 - 51, 1e-9)); // 16.2
    });

    test('artwork size increases monotonically with tile height', () {
      double previous = -1;
      for (var height = 56.0; height <= 260.0; height += 0.5) {
        final size = _atHeight(height).artworkSize;
        if (size == 0) continue; // below the drop threshold
        expect(
          size + 1e-9,
          greaterThanOrEqualTo(previous),
          reason: 'artwork shrank going from a shorter tile to $height',
        );
        previous = size;
      }
      expect(previous, 70, reason: 'the sweep must reach the full ceiling');
    });
  });

  group('TileArtworkMetrics — drop threshold', () {
    // Solving `0.8h - 51 = minArtworkSize` for the primary tier at text
    // scale 1.0 puts the threshold at 83.75pt.
    const double thresholdHeight = 83.75;

    test('artwork is present at the threshold and absent just below it', () {
      final atThreshold = _atHeight(thresholdHeight);
      expect(atThreshold.showArtwork, isTrue);
      expect(
        atThreshold.artworkSize,
        closeTo(TileArtworkMetrics.minArtworkSize, 1e-9),
      );

      final below = _atHeight(thresholdHeight - 0.5);
      expect(below.showArtwork, isFalse);
      expect(below.artworkSize, 0);
    });

    test('a dropped artwork reports zero size, never a residual sliver', () {
      for (final height in <double>[0, 20, 40, 56, 70, 80]) {
        final metrics = _atHeight(height);
        expect(metrics.showArtwork, isFalse, reason: 'height $height');
        expect(metrics.artworkSize, 0, reason: 'height $height');
      }
    });

    test('the threshold does not depend on the artwork ceiling', () {
      // Every tile in a grid must cross the threshold at the same height,
      // even though the two tiers carry different ceilings. If the ceiling
      // influenced the threshold, a grid could show artwork on its primary
      // tiles and not its secondary ones.
      for (final ceiling in <double>[42, 56, 70]) {
        expect(
          _atHeight(thresholdHeight, maxArtworkSize: ceiling).showArtwork,
          isTrue,
          reason: 'ceiling $ceiling must not delay the threshold',
        );
        expect(
          _atHeight(thresholdHeight - 0.5, maxArtworkSize: ceiling).showArtwork,
          isFalse,
          reason: 'ceiling $ceiling must not defer the drop',
        );
      }
    });

    test(
      'a larger label pushes the threshold up, never shrinking the label',
      () {
        // The label is the content: at maximum text scale it still reserves
        // its full line height, so the artwork drops out sooner.
        final atDefaultScale = _atHeight(96, labelLineHeight: 16);
        final atMaxScale = _atHeight(96, labelLineHeight: 16 * 1.6);
        expect(atDefaultScale.showArtwork, isTrue);
        expect(
          atMaxScale.artworkSize,
          lessThan(atDefaultScale.artworkSize),
          reason: 'a taller label must take its space from the artwork',
        );
      },
    );
  });

  group('TileArtworkMetrics — label gap', () {
    test('a tall tile gets the full reserve, split 40/60 top to bottom', () {
      final metrics = _atHeight(200);
      expect(metrics.labelGap, TileArtworkMetrics.labelGapReserve);
      expect(metrics.labelGapTop, closeTo(8, 1e-9));
      expect(metrics.labelGapBottom, closeTo(12, 1e-9));
      expect(
        metrics.labelGapTop + metrics.labelGapBottom,
        closeTo(metrics.labelGap, 1e-9),
      );
    });

    test('the gap compresses rather than the label on a cramped tile', () {
      // 30pt tile: content is 22pt, less than a 16pt label plus the 20pt
      // reserve, so the gap gives way first and never goes negative.
      final metrics = _atHeight(30);
      expect(metrics.labelGap, lessThan(TileArtworkMetrics.labelGapReserve));
      expect(metrics.labelGap, greaterThanOrEqualTo(0));
    });

    test('the gap is clamped at zero when the label alone overflows', () {
      expect(_atHeight(10).labelGap, 0);
      expect(_atHeight(0).labelGap, 0);
    });
  });

  group('TileArtworkMetrics — degenerate input', () {
    test('a zero or unbounded-collapsed height resolves without throwing', () {
      expect(_atHeight(0).showArtwork, isFalse);
      expect(_atHeight(0).artworkSize, 0);
      expect(_atHeight(0).outerPadding, TileArtworkMetrics.minOuterPadding);
    });
  });
}
