// Screen-level regression coverage for the hub sheet at short viewports —
// the mirror of `home_short_viewport_test.dart` for the other grid.
//
// The hub's destination tiles used to size from tile width and a fixed
// aspect ratio, with available height playing no part. On a tall screen that
// passed. On a short one the tiles were far larger than their contents
// needed, mostly empty, and the grid ran past the bottom of the sheet. No
// test noticed, because every hub test rendered on a tall surface.
//
// Tiles now size against the sheet's FULLY-OPEN height, not its live extent.
// That distinction is load-bearing and has its own test below: sizing
// against the current extent would resize the whole grid continuously
// during a drag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/constants/supported_viewport.dart';
import 'package:omnitrain/core/constants/tile_artwork_metrics.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/widgets/cards/maintenance_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omnitrain/features/home/home_screen.dart'
    show hubHandleTopPadding;

import 'home_logo_hub_open_test.dart' show buildHomeScreen;

/// The five hub destinations, in the order `_buildMaintenanceGrid` declares
/// them. Labels are the content: every one must render, at full size, at
/// every viewport and text scale.
const List<String> _destinationLabels = <String>[
  'Profile',
  'Stats',
  'Calendar',
  'Settings',
  'Exercise Library',
];

/// Pumps the Home screen at [viewport] and [textScale] and opens the hub.
///
/// The viewport is applied twice on purpose: `setSurfaceSize` drives layout,
/// while the `MediaQuery` override drives what the code reads back. They are
/// separate knobs in `flutter_test` and a short-viewport test that sets only
/// one of them is not testing a short viewport.
Future<void> _openHubAt(
  WidgetTester tester, {
  required Size viewport,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final screen = await buildHomeScreen(MockWorkoutRepository());
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: viewport,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byType(Image));
  await tester.pumpAndSettle();
}

void main() {
  const double kMinTextScale = 1.0;
  const double kMaxTextScale = OmniTheme.kTextScaleMax;

  /// The shortest phone the app supports.
  const Size supportedFloor = SupportedViewport.minimumSize;

  /// A mid-short viewport: taller than the floor, still short enough that
  /// the natural square-ish tile proportion cannot seat three rows.
  const Size midShort = Size(390, 700);

  group('Hub sheet short-viewport regression', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // ───────────────────────────────────────────────────────────────────
    // H-001 — viewport sweep: no overflow, every destination identifies.
    // ───────────────────────────────────────────────────────────────────
    testWidgets(
      'no overflow and all five destination labels render across the sweep',
      (tester) async {
        for (final viewport in <Size>[supportedFloor, midShort]) {
          for (final scale in <double>[kMinTextScale, kMaxTextScale]) {
            await _openHubAt(tester, viewport: viewport, textScale: scale);

            expect(
              tester.takeException(),
              isNull,
              reason:
                  'hub sheet at $viewport, text scale $scale must not '
                  'overflow',
            );
            expect(
              find.byType(MaintenanceTile),
              findsNWidgets(5),
              reason: 'all five destinations must be built at $viewport',
            );
            for (final label in _destinationLabels) {
              expect(
                find.text(label),
                findsOneWidget,
                reason:
                    'destination "$label" must render at $viewport, text '
                    'scale $scale',
              );
            }
          }
        }
      },
    );

    // ───────────────────────────────────────────────────────────────────
    // H-002 — the whole grid fits the open sheet on the shortest device.
    // ───────────────────────────────────────────────────────────────────
    testWidgets(
      'at the fully-open height on the shortest supported viewport, every '
      'tile is fully visible without scrolling',
      (tester) async {
        await _openHubAt(
          tester,
          viewport: supportedFloor,
          textScale: kMinTextScale,
        );

        for (var i = 0; i < 5; i++) {
          final rect = tester.getRect(find.byType(MaintenanceTile).at(i));
          expect(
            rect.bottom,
            lessThanOrEqualTo(supportedFloor.height + 0.5),
            reason:
                'tile $i runs past the bottom of the shortest supported '
                'viewport (bottom ${rect.bottom} vs '
                '${supportedFloor.height}) — the grid does not fit the '
                'open sheet',
          );
          expect(
            rect.top,
            greaterThanOrEqualTo(-0.5),
            reason: 'tile $i is pushed off the top of the viewport',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(supportedFloor.width + 0.5),
            reason: 'tile $i runs past the right edge',
          );
        }
      },
    );

    // ───────────────────────────────────────────────────────────────────
    // H-003 — sizing is against the OPEN height, not the live extent.
    // ───────────────────────────────────────────────────────────────────
    testWidgets('tile size is identical at two different sheet drag extents', (
      tester,
    ) async {
      await _openHubAt(tester, viewport: midShort, textScale: kMinTextScale);

      final fullyOpen = tester.getSize(find.byType(MaintenanceTile).first);

      // Drag the sheet part-way closed and measure again mid-drag. If the
      // grid were sized against the live extent, every tile would resize
      // continuously while the user drags — visually unstable, and it
      // draws the eye to the chrome instead of the destinations.
      await tester.drag(
        find.byType(MaintenanceTile).first,
        const Offset(0, 120),
      );
      await tester.pump();

      final partway = tester.getSize(find.byType(MaintenanceTile).first);

      expect(
        partway,
        fullyOpen,
        reason:
            'hub tile size changed between drag extents ($fullyOpen -> '
            '$partway). Tiles must be laid out once against the sheet\'s '
            'fully-open height and hold still while it is dragged.',
      );
    });

    // ───────────────────────────────────────────────────────────────────
    // H-004 — the hub consumes the shared rule, not fixed values.
    // ───────────────────────────────────────────────────────────────────
    testWidgets(
      'hub icon size matches what the shared rule produces at that tile '
      'height',
      (tester) async {
        for (final viewport in <Size>[supportedFloor, midShort]) {
          await _openHubAt(
            tester,
            viewport: viewport,
            textScale: kMinTextScale,
          );

          final tileHeight = tester
              .getSize(find.byType(MaintenanceTile).first)
              .height;

          // Recomputed from the rule rather than asserted against a
          // constant: if the hub ever drifts back to a fixed icon size,
          // this diverges the moment the tile height moves off whatever
          // height that constant happened to suit.
          final expected = TileArtworkMetrics.resolve(
            tileHeight: tileHeight,
            maxArtworkSize: 42,
            labelLineHeight: 15 * 1.1,
          );

          final icons = tester
              .widgetList<Icon>(
                find.descendant(
                  of: find.byType(MaintenanceTile),
                  matching: find.byType(Icon),
                ),
              )
              .toList(growable: false);

          if (!expected.showArtwork) {
            expect(
              icons,
              isEmpty,
              reason:
                  'below the shared drop threshold the hub must omit its '
                  'icons entirely, at $viewport',
            );
            continue;
          }

          expect(
            icons.length,
            5,
            reason:
                'artwork presence must be uniform across the grid at '
                '$viewport — no tile may keep an icon while others drop it',
          );
          for (final icon in icons) {
            expect(
              icon.size,
              closeTo(expected.artworkSize, 0.01),
              reason:
                  'hub icon size (${icon.size}) must equal the shared '
                  'rule\'s result (${expected.artworkSize}) at tile height '
                  '$tileHeight, viewport $viewport',
            );
          }
        }
      },
    );

    // ───────────────────────────────────────────────────────────────────
    // H-006 — the open sheet stops just under the logo button.
    //
    // The sheet's top edge is positioned from `MediaQuery.padding.top` plus
    // the AppBar's toolbar height. Inside the Scaffold body the padding
    // ALREADY includes that toolbar (the body extends behind the AppBar), so
    // reading the MediaQuery from a context below the Scaffold subtracts it
    // twice and opens the sheet a full toolbar short — far enough to leave
    // the TRAIN title uncovered. Nothing errors; the sheet just stops low.
    // ───────────────────────────────────────────────────────────────────
    testWidgets(
      'the fully-open sheet stops just below the logo button and covers the '
      'TRAIN title',
      (tester) async {
        for (final viewport in <Size>[
          supportedFloor,
          midShort,
          const Size(475, 746),
        ]) {
          await _openHubAt(
            tester,
            viewport: viewport,
            textScale: kMinTextScale,
          );

          // The handle bar is the topmost thing inside the sheet surface, at
          // a known inset — derived from the constant the sheet itself uses,
          // so this stays honest if the inset changes.
          final handle = tester.getRect(
            find.descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.constraints?.maxHeight == 6,
              ),
            ),
          );
          final sheetTop = handle.top - hubHandleTopPadding;
          final logo = tester.getRect(find.byType(Image));

          expect(
            sheetTop,
            greaterThan(logo.bottom),
            reason:
                'the sheet must not cover the logo button at $viewport '
                '(sheet top $sheetTop vs logo bottom ${logo.bottom})',
          );
          expect(
            sheetTop - logo.bottom,
            lessThanOrEqualTo(16.0),
            reason:
                'the gap between the logo button and the open sheet must stay '
                'tiny at $viewport — it is ${sheetTop - logo.bottom}pt. A gap '
                'near a full toolbar height means the AppBar was subtracted '
                'twice.',
          );

          final train = tester.getRect(find.text('TRAIN'));
          expect(
            sheetTop,
            lessThanOrEqualTo(train.top + 1),
            reason:
                'the open sheet must cover the TRAIN title at $viewport '
                '(sheet top $sheetTop vs title top ${train.top})',
          );
        }
      },
    );

    // ───────────────────────────────────────────────────────────────────
    // H-005 — artwork presence is uniform, labels never sacrificed.
    // ───────────────────────────────────────────────────────────────────
    testWidgets(
      'artwork is present or absent across the whole grid, never mixed, and '
      'labels always render',
      (tester) async {
        for (final viewport in <Size>[supportedFloor, midShort]) {
          for (final scale in <double>[kMinTextScale, kMaxTextScale]) {
            await _openHubAt(tester, viewport: viewport, textScale: scale);

            final iconCount = find
                .descendant(
                  of: find.byType(MaintenanceTile),
                  matching: find.byType(Icon),
                )
                .evaluate()
                .length;

            expect(
              iconCount == 0 || iconCount == 5,
              isTrue,
              reason:
                  'mixed artwork state at $viewport, text scale $scale: '
                  '$iconCount of 5 tiles carry an icon',
            );

            for (final label in _destinationLabels) {
              expect(
                find.text(label),
                findsOneWidget,
                reason:
                    'label "$label" must survive at $viewport, text scale '
                    '$scale — labels are the content, artwork is the '
                    'decoration that gives way',
              );
            }
          }
        }
      },
    );
  });
}
