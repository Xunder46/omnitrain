// Parity coverage between custom-drawn tile artwork and standard icons.
//
// The defect this file exists for: the Resistance tile's figure was
// constructed at a fixed size in the tile definition list, so `EnergyTile`'s
// height-responsive rule never reached it. Every neighbouring tile shrank on
// a short screen while the figure stayed at 70pt and clipped at the tile
// edge. Nothing errored — the tile simply stopped participating.
//
// No assertion in the suite compared custom artwork against a standard icon,
// which is why the whole class of defect was invisible. These tests make the
// comparison directly, so any future custom artwork that opts out of the
// shared rule fails here instead of shipping.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/home_tiles.dart';
import 'package:omnitrain/core/constants/tile_artwork_metrics.dart';
import 'package:omnitrain/widgets/cards/energy_tile.dart';
import 'package:omnitrain/widgets/icons/overhead_press_icon.dart';

/// The Resistance tile's definition — the one that carries custom artwork.
HomeTileConfig get _resistanceTile =>
    HomeTiles.all.firstWhere((t) => t.key == 'resistance');

Widget _host({
  required Widget tile,
  required double width,
  required double height,
  required double textScale,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: tile),
        ),
      ),
    ),
  );
}

Finder _artworkOf(String title) =>
    find.byKey(ValueKey('energy_tile_artwork_$title'));

void main() {
  // Heights spanning the full Home responsive range: the 56pt tile floor,
  // the compressed band, the drop threshold, and the uncompressed top end.
  const List<double> heights = <double>[
    56,
    64,
    76,
    84,
    96,
    110,
    120,
    140,
    160,
    180,
    200,
  ];

  group('custom artwork and standard icons size identically', () {
    testWidgets(
      'the Resistance figure measures the same as a standard-icon tile at '
      'every height in the Home sweep',
      (tester) async {
        for (final height in heights) {
          for (final isSecondary in <bool>[false, true]) {
            // Same title on both tiles: the artwork key is derived from it,
            // and an identical title also guarantees an identical label
            // reservation, so any difference in measurement can only come
            // from how the artwork itself is sized.
            const title = 'Resistance';

            await tester.pumpWidget(
              _host(
                width: 156,
                height: height,
                textScale: 1.0,
                tile: EnergyTile(
                  title: title,
                  artworkBuilder: _resistanceTile.artworkBuilder,
                  accentColor: const Color(0xFF2DE2E6),
                  isSecondary: isSecondary,
                  onTap: () {},
                ),
              ),
            );
            final customPresent = _artworkOf(title).evaluate().isNotEmpty;
            final customRect = customPresent
                ? tester.getRect(_artworkOf(title))
                : null;

            await tester.pumpWidget(
              _host(
                width: 156,
                height: height,
                textScale: 1.0,
                tile: EnergyTile(
                  title: title,
                  icon: Icons.directions_run,
                  accentColor: const Color(0xFF2DE2E6),
                  isSecondary: isSecondary,
                  onTap: () {},
                ),
              ),
            );
            final iconPresent = _artworkOf(title).evaluate().isNotEmpty;
            final iconRect = iconPresent
                ? tester.getRect(_artworkOf(title))
                : null;

            expect(
              customPresent,
              iconPresent,
              reason:
                  'custom artwork and a standard icon must appear and drop '
                  'out at the same height — height $height, '
                  'secondary=$isSecondary',
            );

            if (customPresent) {
              expect(
                customRect!.height,
                closeTo(iconRect!.height, 0.01),
                reason:
                    'custom artwork height (${customRect.height}) must match '
                    'a standard icon (${iconRect.height}) at height $height, '
                    'secondary=$isSecondary — this is the assertion the '
                    'fixed-size Resistance figure would have failed',
              );
              expect(
                customRect.width,
                closeTo(iconRect.width, 0.01),
                reason:
                    'custom artwork width must match a standard icon at '
                    'height $height, secondary=$isSecondary',
              );
            }
          }
        }
      },
    );

    testWidgets('the figure scales with its tile rather than staying fixed', (
      tester,
    ) async {
      final measured = <double>[];
      for (final height in <double>[96, 120, 160, 200]) {
        await tester.pumpWidget(
          _host(
            width: 156,
            height: height,
            textScale: 1.0,
            tile: EnergyTile(
              title: 'Resistance',
              artworkBuilder: _resistanceTile.artworkBuilder,
              accentColor: const Color(0xFF2DE2E6),
              onTap: () {},
            ),
          ),
        );
        measured.add(tester.getRect(_artworkOf('Resistance')).height);
      }

      expect(
        measured.toSet().length,
        greaterThan(1),
        reason:
            'the figure must change size across tile heights; a single '
            'repeated value means it is pinned again',
      );
      for (var i = 1; i < measured.length; i++) {
        expect(measured[i] + 1e-9, greaterThanOrEqualTo(measured[i - 1]));
      }
      expect(
        measured.last,
        70,
        reason: 'a tall primary tile still renders the figure at 70pt',
      );
    });
  });

  group('the Resistance figure stays inside its tile', () {
    /// The smallest height in the sweep at which artwork still renders.
    Future<double> smallestHeightWithArtwork(
      WidgetTester tester,
      double textScale,
    ) async {
      for (var height = 56.0; height <= 220.0; height += 0.25) {
        await tester.pumpWidget(
          _host(
            width: 156,
            height: height,
            textScale: textScale,
            tile: EnergyTile(
              title: 'Resistance',
              artworkBuilder: _resistanceTile.artworkBuilder,
              accentColor: const Color(0xFF2DE2E6),
              onTap: () {},
            ),
          ),
        );
        if (_artworkOf('Resistance').evaluate().isNotEmpty) return height;
      }
      fail('artwork never rendered anywhere in the swept height range');
    }

    testWidgets(
      'at the smallest height where artwork renders, the figure is fully '
      'contained — including the parts it deliberately paints outside its box',
      (tester) async {
        for (final textScale in <double>[1.0, 1.6]) {
          final height = await smallestHeightWithArtwork(tester, textScale);

          final artwork = tester.getRect(_artworkOf('Resistance'));
          final tile = tester.getRect(find.byType(EnergyTile));

          // The painter deliberately draws the barbell plates above the top
          // of its box and runs the shaft a fraction past the right edge.
          // `getRect` reports the box, not the ink, so the overshoot is
          // added back here — otherwise this test would pass while the
          // plates were being clipped by the tile.
          final paintedTop =
              artwork.top -
              artwork.height * OverheadPressIcon.topOvershootRatio;
          final paintedRight =
              artwork.right +
              artwork.width * OverheadPressIcon.rightOvershootRatio;

          expect(
            paintedTop,
            greaterThanOrEqualTo(tile.top - 0.01),
            reason:
                'the barbell plates (painted ${artwork.height * OverheadPressIcon.topOvershootRatio}pt '
                'above the artwork box) must clear the tile top at height '
                '$height, text scale $textScale',
          );
          expect(
            paintedRight,
            lessThanOrEqualTo(tile.right + 0.01),
            reason:
                'the barbell shaft must clear the tile right edge at height '
                '$height, text scale $textScale',
          );
          expect(
            artwork.left,
            greaterThanOrEqualTo(tile.left - 0.01),
            reason: 'artwork must clear the tile left edge',
          );
          expect(
            artwork.bottom,
            lessThanOrEqualTo(tile.bottom + 0.01),
            reason: 'artwork must clear the tile bottom edge',
          );
        }
      },
    );

    testWidgets('the figure is contained at every swept height and scale', (
      tester,
    ) async {
      // Square tiles as well as wide ones. The Home grid lays its tiles out
      // square, and a square tile is where an over-wide artwork escapes
      // sideways first — a wide host would hide that behind spare margin.
      for (final height in heights) {
        for (final width in <double>[height, 156]) {
          for (final textScale in <double>[1.0, 1.6]) {
            await tester.pumpWidget(
              _host(
                width: width,
                height: height,
                textScale: textScale,
                tile: EnergyTile(
                  title: 'Resistance',
                  artworkBuilder: _resistanceTile.artworkBuilder,
                  accentColor: const Color(0xFF2DE2E6),
                  onTap: () {},
                ),
              ),
            );
            if (_artworkOf('Resistance').evaluate().isEmpty) continue;

            final artwork = tester.getRect(_artworkOf('Resistance'));
            final tile = tester.getRect(find.byType(EnergyTile));
            final paintedTop =
                artwork.top -
                artwork.height * OverheadPressIcon.topOvershootRatio;
            final paintedRight =
                artwork.right +
                artwork.width * OverheadPressIcon.rightOvershootRatio;

            expect(
              paintedTop >= tile.top - 0.01 &&
                  paintedRight <= tile.right + 0.01 &&
                  artwork.left >= tile.left - 0.01 &&
                  artwork.bottom <= tile.bottom + 0.01,
              isTrue,
              reason:
                  'figure escapes its tile at ${width}x$height, text scale '
                  '$textScale (artwork $artwork, tile $tile)',
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    });
  });

  group('tile definitions carry no dimensions', () {
    test('no Home tile definition pre-constructs sized artwork', () {
      for (final tile in HomeTiles.all) {
        // A definition names artwork; the tile sizes it. The builder
        // signature is what enforces this — a definition cannot hand over a
        // finished widget with its size already baked in.
        expect(
          tile.iconData != null || tile.artworkBuilder != null,
          isTrue,
          reason: '${tile.key} must declare artwork of some kind',
        );
      }
    });

    testWidgets('the definition builder honours whatever size it is given', (
      tester,
    ) async {
      // Calling the builder directly with an arbitrary size proves the
      // definition holds no dimension of its own.
      for (final size in <double>[TileArtworkMetrics.minArtworkSize, 33, 70]) {
        final built = _resistanceTile.artworkBuilder!(size, Colors.white);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Center(child: built)),
          ),
        );
        final rect = tester.getRect(find.byType(OverheadPressIcon));
        expect(rect.width, closeTo(size, 0.01));
        expect(rect.height, closeTo(size, 0.01));
      }
    });
  });
}
