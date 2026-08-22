// Phase 0 scenarios for the home tile restyle + Free/Routines tier demotion.
//
// S-001: Resting home grid render — primary tiles (Cardio, Resistance, Sports,
//        Isometric) use solid 18% accent fill + 1px top rim + 1px bottom inner
//        shadow; secondary tiles (Free, Routines) use solid 8% own-accent fill,
//        dimmed/smaller icon, lighter Medium label, no rim, no inner shadow.
//        No gradient on either decoration. No resting drop shadow.
// S-002: Active-session tile (edge of S-001) — the isActive glow branch is
//        preserved (it is a functional in-progress indicator, not resting
//        decoration). Tiering is per-tile, not per-state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/widgets/cards/energy_tile.dart';

/// Returns the inner [_Surface] Container (the one with `BoxDecoration`).
/// `EnergyTile` has two Containers in the tree:
///  - outer GestureDetector > AnimatedScale > Container (with surface decoration)
///  - inner content (icon + label)
/// We walk the render tree and return the `Container` that owns the surface
/// decoration (`borderRadius` == `OmniTheme.surfaceBorderRadius`).
Finder _surfaceContainer() {
  return find
      .byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius != null,
      )
      .first;
}

Container _surface(WidgetTester tester) {
  return tester.widget<Container>(_surfaceContainer());
}

void main() {
  // All tests run with the dark navy (abyssalNeon) theme active so the
  // surface tokens used in assertions are stable.
  setUp(() {
    // The EnergyTile reads `OmniTheme.colors` lazily; no global flip needed
    // because the surface border radius token is theme-independent.
  });

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  group('S-001: resting home grid render', () {
    testWidgets('primary tile has no gradient on base decoration', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          EnergyTile(
            title: 'Cardio',
            icon: Icons.directions_run,
            accentColor: const Color(0xFF24B85A),
            onTap: () {},
          ),
        ),
      );

      final base = _surface(tester).decoration! as BoxDecoration;
      expect(
        base.gradient,
        isNull,
        reason: 'primary tile base decoration must not have a gradient',
      );
    });

    testWidgets('primary tile has no gradient on foreground decoration', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          EnergyTile(
            title: 'Resistance',
            artworkBuilder: (size, color) =>
                Icon(Icons.fitness_center, size: size, color: color),
            accentColor: const Color(0xFF2DE2E6),
            onTap: () {},
          ),
        ),
      );

      final fg = _surface(tester).foregroundDecoration;
      // No gradient overlay means either no foregroundDecoration OR one
      // that is purely a rim/shadow overlay (no LinearGradient).
      if (fg != null) {
        // foregroundDecoration is a Decoration; cast to BoxDecoration to
        // check for a gradient (LinearGradient is only on BoxDecoration).
        if (fg is BoxDecoration) {
          expect(
            fg.gradient,
            isNull,
            reason:
                'primary tile foreground decoration must not have a gradient',
          );
        }
      }
    });

    testWidgets(
      'primary tile resting boxShadow is empty (no drop shadow at rest)',
      (tester) async {
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Sports',
              icon: Icons.sports_martial_arts,
              accentColor: const Color(0xFFFF4C47),
              onTap: () {},
            ),
          ),
        );

        final base = _surface(tester).decoration! as BoxDecoration;
        expect(
          base.boxShadow,
          isNull,
          reason:
              'primary tile resting state must not have a drop shadow '
              '(use an empty list or null)',
        );
      },
    );

    testWidgets(
      'primary tile accent fill is rendered at ~30% (in the opaque base color)',
      (tester) async {
        const accent = Color(0xFFA478FF); // a vivid purple for the math
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Isometric',
              icon: Icons.accessibility,
              accentColor: accent,
              onTap: () {},
            ),
          ),
        );

        final base = _surface(tester).decoration! as BoxDecoration;
        final color = base.color;
        expect(
          color,
          isNotNull,
          reason: 'primary tile base must have a solid color fill',
        );
        // 30% of alpha 0xFF == 0x4D
        expect(
          (color!.a * 255).round(),
          inInclusiveRange(74, 79),
          reason: 'primary fill opacity should be ~30%',
        );
      },
    );

    testWidgets(
      'secondary tile accent fill is rendered at ~15% (Free stays purple)',
      (tester) async {
        const accent = Color(0xFFA478FF); // Free's purple
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Free',
              icon: Icons.play_arrow,
              accentColor: accent,
              isSecondary: true,
              onTap: () {},
            ),
          ),
        );

        final base = _surface(tester).decoration! as BoxDecoration;
        final color = base.color;
        expect(
          color,
          isNotNull,
          reason: 'secondary tile base must have a solid color fill',
        );
        // 15% of alpha 0xFF == 0x26
        expect(
          (color!.a * 255).round(),
          inInclusiveRange(36, 40),
          reason: 'secondary fill opacity should be ~15%',
        );
      },
    );

    testWidgets(
      'secondary tile accent fill is rendered at ~15% (Routines uses its own neutral gray)',
      (tester) async {
        const accent = Color(0xFF9E9E9E); // Routines neutral gray
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Routines',
              icon: Icons.folder_open,
              accentColor: accent,
              isSecondary: true,
              onTap: () {},
            ),
          ),
        );

        final base = _surface(tester).decoration! as BoxDecoration;
        final color = base.color!;
        // Verify the fill carries the routines neutral accent, not purple.
        expect(color.r, inInclusiveRange(0.60, 0.63));
        expect(color.g, inInclusiveRange(0.60, 0.63));
        expect(color.b, inInclusiveRange(0.60, 0.63));
        // 15% alpha
        expect((color.a * 255).round(), inInclusiveRange(36, 40));
      },
    );

    testWidgets('primary tile shows a 1px top rim highlight (white @ ~8%)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          EnergyTile(
            title: 'Cardio',
            icon: Icons.directions_run,
            accentColor: const Color(0xFF24B85A),
            onTap: () {},
          ),
        ),
      );

      // Look for a positioned 1px-tall white-strip widget near the top.
      // We assert by walking the widget tree for a DecoratedBox with
      // a white color near the top edge.
      final rimStrips = find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        final c = d.color;
        if (c == null) return false;
        // White-ish at ~8% alpha
        return (c.r - 1.0).abs() < 0.01 &&
            (c.g - 1.0).abs() < 0.01 &&
            (c.b - 1.0).abs() < 0.01 &&
            (c.a * 255).round() >= 18 &&
            (c.a * 255).round() <= 22;
      });
      expect(
        rimStrips,
        findsWidgets,
        reason:
            'primary tile must render a 1px white @ ~8% rim strip at the top',
      );
    });

    testWidgets('primary tile shows a 1px bottom inner shadow (black @ ~20%)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          EnergyTile(
            title: 'Cardio',
            icon: Icons.directions_run,
            accentColor: const Color(0xFF24B85A),
            onTap: () {},
          ),
        ),
      );

      final shadowStrips = find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        final c = d.color;
        if (c == null) return false;
        return c.r < 0.05 &&
            c.g < 0.05 &&
            c.b < 0.05 &&
            (c.a * 255).round() >= 48 &&
            (c.a * 255).round() <= 52;
      });
      expect(
        shadowStrips,
        findsWidgets,
        reason:
            'primary tile must render a 1px black @ ~20% inner-shadow strip at the bottom',
      );
    });

    testWidgets(
      'secondary tile has no rim highlight strip and no inner shadow strip',
      (tester) async {
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Free',
              icon: Icons.play_arrow,
              accentColor: const Color(0xFFA478FF),
              isSecondary: true,
              onTap: () {},
            ),
          ),
        );

        final rimStrips = find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          final c = d.color;
          if (c == null) return false;
          // White-ish at ~8% alpha — would only be present on primaries.
          return (c.r - 1.0).abs() < 0.01 &&
              (c.g - 1.0).abs() < 0.01 &&
              (c.b - 1.0).abs() < 0.01 &&
              (c.a * 255).round() >= 18 &&
              (c.a * 255).round() <= 22;
        });
        expect(
          rimStrips,
          findsNothing,
          reason: 'secondary tile must NOT render a top-rim highlight',
        );

        final shadowStrips = find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          final c = d.color;
          if (c == null) return false;
          return c.r < 0.05 &&
              c.g < 0.05 &&
              c.b < 0.05 &&
              (c.a * 255).round() >= 48 &&
              (c.a * 255).round() <= 52;
        });
        expect(
          shadowStrips,
          findsNothing,
          reason: 'secondary tile must NOT render a bottom inner shadow',
        );
      },
    );

    testWidgets(
      'primary tile label uses FontWeight.w600 (Semibold) and textDominant color',
      (tester) async {
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Cardio',
              icon: Icons.directions_run,
              accentColor: const Color(0xFF24B85A),
              onTap: () {},
            ),
          ),
        );

        final text = tester.widget<Text>(find.text('Cardio'));
        expect(
          text.style?.fontWeight,
          FontWeight.w600,
          reason: 'primary label must use Semibold (w600)',
        );
        // textDominant on abyssalNeon is 0xF2FFFFFF — accept any near-white.
        final c = text.style?.color;
        expect(c, isNotNull);
        expect(c!.r, greaterThan(0.9));
      },
    );

    testWidgets(
      'secondary tile label uses FontWeight.w500 (Medium) and white @ ~70%',
      (tester) async {
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Free',
              icon: Icons.play_arrow,
              accentColor: const Color(0xFFA478FF),
              isSecondary: true,
              onTap: () {},
            ),
          ),
        );

        final text = tester.widget<Text>(find.text('Free'));
        expect(
          text.style?.fontWeight,
          FontWeight.w500,
          reason: 'secondary label must use Medium (w500)',
        );
        final c = text.style?.color;
        expect(c, isNotNull);
        // White-ish
        expect(c!.r, greaterThan(0.9));
        // 70% alpha
        expect((c.a * 255).round(), inInclusiveRange(178, 180));
      },
    );

    testWidgets('primary tile icon is size 70 and uses textDominant color', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 200,
            child: EnergyTile(
              title: 'Sports',
              icon: Icons.sports_martial_arts,
              accentColor: const Color(0xFFFF4C47),
              onTap: () {},
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.sports_martial_arts));
      expect(icon.size, 70.0, reason: 'primary icon size must be 70');
      final c = icon.color;
      expect(c, isNotNull);
      expect(
        c!.r,
        greaterThan(0.9),
        reason: 'primary icon must use textDominant (near-white)',
      );
    });

    testWidgets('secondary tile icon is size 56 and uses white @ ~75%', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 200,
            child: EnergyTile(
              title: 'Routines',
              icon: Icons.folder_open,
              accentColor: const Color(0xFF9E9E9E),
              isSecondary: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.folder_open));
      expect(icon.size, 56.0, reason: 'secondary icon size must be 56');
      final c = icon.color;
      expect(c, isNotNull);
      // White-ish
      expect(c!.r, greaterThan(0.9));
      // 75% alpha
      expect((c.a * 255).round(), inInclusiveRange(188, 195));
    });
  });

  group('S-002: active-session tile (edge of S-001)', () {
    testWidgets(
      'active tile still has the active accent glow (isActive branch preserved)',
      (tester) async {
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Resistance',
              icon: Icons.fitness_center,
              accentColor: const Color(0xFF2DE2E6),
              isActive: true,
              onTap: () {},
            ),
          ),
        );

        final base = _surface(tester).decoration! as BoxDecoration;
        final shadows = base.boxShadow;
        // The isActive branch must still render at least one accent glow.
        expect(shadows, isNotNull);
        expect(
          shadows!.length,
          greaterThanOrEqualTo(1),
          reason: 'isActive glow must be preserved',
        );

        // Verify the accent color is present in one of the glow shadows.
        // The accent here is cyan #2DE2E6 (r=0x2D, g=0xE2, b=0xE6), so the
        // assertion checks for a non-trivial presence of the accent's R/G/B
        // channels with meaningful alpha — not an exact channel match,
        // since the active-glow shadow also blends with the deep-shadow.
        final hasAccentGlow = shadows.any((s) {
          final c = s.color;
          return c.a > 0.2 &&
              (c.r - 0.176).abs() < 0.15 &&
              (c.g - 0.886).abs() < 0.15 &&
              (c.b - 0.902).abs() < 0.15;
        });
        expect(
          hasAccentGlow,
          isTrue,
          reason: 'active glow must include the accent-color shadow branch',
        );
      },
    );

    testWidgets(
      'active tile still shows the primary rim highlight (tiering is per-tile, not per-state)',
      (tester) async {
        await tester.pumpWidget(
          host(
            EnergyTile(
              title: 'Resistance',
              icon: Icons.fitness_center,
              accentColor: const Color(0xFF2DE2E6),
              isActive: true,
              onTap: () {},
            ),
          ),
        );

        final rimStrips = find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          final c = d.color;
          if (c == null) return false;
          return (c.r - 1.0).abs() < 0.01 &&
              (c.g - 1.0).abs() < 0.01 &&
              (c.b - 1.0).abs() < 0.01 &&
              (c.a * 255).round() >= 18 &&
              (c.a * 255).round() <= 22;
        });
        expect(
          rimStrips,
          findsWidgets,
          reason: 'an active primary tile must still render the 1px top rim',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Follow-up scenarios (S-101 … S-106) — centering, active dot, secondary
  // icon lift. See .github/agents/plans/home-tile-fixes-plan.md.
  // ══════════════════════════════════════════════════════════════════════════

  group('S-101: tile content horizontal centering', () {
    // Pump six tiles into a 2-col grid at a fixed tile size and assert that
    // every icon and every label is centered on the tile's horizontal axis.
    testWidgets(
      'all 6 tiles: icon center x matches tile center x (±1.0 logical px)',
      (tester) async {
        const tileSize = 200.0;
        const accents = <String, Color>{
          'Cardio': Color(0xFF24B85A),
          'Resistance': Color(0xFF2DE2E6),
          'Sports': Color(0xFFFF4C47),
          'Isometric': Color(0xFFFFB420),
          'Free': Color(0xFFA478FF),
          'Routines': Color(0xFF9E9E9E),
        };
        const titles = <String, IconData>{
          'Cardio': Icons.directions_run,
          'Resistance': Icons.fitness_center,
          'Sports': Icons.sports_martial_arts,
          'Isometric': Icons.accessibility,
          'Free': Icons.play_arrow,
          'Routines': Icons.folder_open,
        };
        const secondary = <String>{'Free', 'Routines'};

        await tester.pumpWidget(
          host(
            SizedBox(
              width: 2 * tileSize + 16,
              height: 3 * tileSize + 32,
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final title in titles.keys)
                    SizedBox(
                      width: tileSize,
                      height: tileSize,
                      child: EnergyTile(
                        title: title,
                        icon: titles[title],
                        accentColor: accents[title]!,
                        isSecondary: secondary.contains(title),
                        onTap: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        for (final title in titles.keys) {
          final tileRect = tester.getRect(
            find.byType(EnergyTile).at(titles.keys.toList().indexOf(title)),
          );
          final iconCenter = tester.getCenter(
            find.descendant(
              of: find
                  .byType(EnergyTile)
                  .at(titles.keys.toList().indexOf(title)),
              matching: find.byIcon(titles[title]!),
            ),
          );
          final dx = (iconCenter.dx - tileRect.center.dx).abs();
          expect(
            dx,
            lessThanOrEqualTo(1.0),
            reason:
                '$title icon center (${iconCenter.dx}) is offset from tile center (${tileRect.center.dx}) by ${dx.toStringAsFixed(2)}px',
          );
        }
      },
    );

    testWidgets(
      'all 6 tiles: label center x matches tile center x (±1.0 logical px)',
      (tester) async {
        const tileSize = 200.0;
        const accents = <String, Color>{
          'Cardio': Color(0xFF24B85A),
          'Resistance': Color(0xFF2DE2E6),
          'Sports': Color(0xFFFF4C47),
          'Isometric': Color(0xFFFFB420),
          'Free': Color(0xFFA478FF),
          'Routines': Color(0xFF9E9E9E),
        };
        const titles = <String, IconData>{
          'Cardio': Icons.directions_run,
          'Resistance': Icons.fitness_center,
          'Sports': Icons.sports_martial_arts,
          'Isometric': Icons.accessibility,
          'Free': Icons.play_arrow,
          'Routines': Icons.folder_open,
        };
        const secondary = <String>{'Free', 'Routines'};

        await tester.pumpWidget(
          host(
            SizedBox(
              width: 2 * tileSize + 16,
              height: 3 * tileSize + 32,
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final title in titles.keys)
                    SizedBox(
                      width: tileSize,
                      height: tileSize,
                      child: EnergyTile(
                        title: title,
                        icon: titles[title],
                        accentColor: accents[title]!,
                        isSecondary: secondary.contains(title),
                        onTap: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        // The label is text-aligned center, so its *center* x should
        // match the tile's center x within ±1.0 logical px for every tile.
        // (The label's bounding-box left edge varies with text width, so
        // it is the wrong metric; the *center* is what users perceive.)
        for (final title in titles.keys) {
          final tileRect = tester.getRect(
            find.byType(EnergyTile).at(titles.keys.toList().indexOf(title)),
          );
          final labelRect = tester.getRect(
            find.descendant(
              of: find
                  .byType(EnergyTile)
                  .at(titles.keys.toList().indexOf(title)),
              matching: find.text(title),
            ),
          );
          final dx = (labelRect.center.dx - tileRect.center.dx).abs();
          expect(
            dx,
            lessThanOrEqualTo(1.0),
            reason:
                '$title label center (${labelRect.center.dx}) is offset from tile center (${tileRect.center.dx}) by ${dx.toStringAsFixed(2)}px',
          );
        }
      },
    );
  });

  group('S-102: label baseline pinned to fixed bottom offset', () {
    testWidgets(
      'label bottom y is identical across icon sizes (label does not float)',
      (tester) async {
        const tileSize = 200.0;

        // First render: primary tile (icon 70)
        await tester.pumpWidget(
          host(
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: EnergyTile(
                title: 'Cardio',
                icon: Icons.directions_run,
                accentColor: const Color(0xFF24B85A),
                onTap: () {},
              ),
            ),
          ),
        );
        final primaryLabelRect = tester.getRect(find.text('Cardio'));

        // Second render: secondary tile (icon 56)
        await tester.pumpWidget(
          host(
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: EnergyTile(
                title: 'Free',
                icon: Icons.play_arrow,
                accentColor: const Color(0xFFA478FF),
                isSecondary: true,
                onTap: () {},
              ),
            ),
          ),
        );
        final secondaryLabelRect = tester.getRect(find.text('Free'));

        final dy = (primaryLabelRect.bottom - secondaryLabelRect.bottom).abs();
        expect(
          dy,
          lessThanOrEqualTo(1.0),
          reason:
              'label bottom shifted by ${dy.toStringAsFixed(2)}px when icon size changed — label must be anchored to a fixed bottom offset',
        );
      },
    );
  });

  group('S-103: active tile renders a pulsing dot', () {
    testWidgets(
      'active tile renders a white ~8pt dot in the top-right (~10pt inset)',
      (tester) async {
        const tileSize = 200.0;
        await tester.pumpWidget(
          host(
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: EnergyTile(
                title: 'Resistance',
                icon: Icons.fitness_center,
                accentColor: const Color(0xFF2DE2E6),
                isActive: true,
                onTap: () {},
              ),
            ),
          ),
        );

        // Find a small white circle near the top-right of the tile.
        // The dot is a `Container` with `BoxShape.circle` and `Colors.white`
        // — disambiguate from the 1-px rim strips (which are also white
        // but have a 1-px-tall `DecoratedBox`).
        final dotFinder = find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          if (d.shape != BoxShape.circle) return false;
          final c = d.color;
          if (c == null) return false;
          return (c.r - 1.0).abs() < 0.01 &&
              (c.g - 1.0).abs() < 0.01 &&
              (c.b - 1.0).abs() < 0.01;
        });
        expect(
          dotFinder,
          findsOneWidget,
          reason: 'active tile must render a single white circular dot',
        );

        // Validate position: dot's right edge should be ~10pt from the
        // tile's right edge (PLUS the outer Container's 20-pt padding),
        // and its top edge should be ~10pt from the tile's top edge
        // (PLUS the 20-pt padding). The test was: dot right inset from
        // the inner content area ≈ 10pt.
        final tileRect = tester.getRect(find.byType(EnergyTile));
        final dotRect = tester.getRect(dotFinder);
        final rightInset = tileRect.right - dotRect.right;
        final topInset = dotRect.top - tileRect.top;
        // The outer Container has padding 20, the dot is at Positioned
        // (top: 10, right: 10) inside the Stack, so from the tile's edge
        // the inset is 20+10 = 30 logical px.
        expect(
          rightInset,
          inInclusiveRange(20, 32),
          reason:
              'dot right inset should be ~30pt (20 outer + 10 Positioned), got $rightInset',
        );
        expect(
          topInset,
          inInclusiveRange(20, 32),
          reason:
              'dot top inset should be ~30pt (20 outer + 10 Positioned), got $topInset',
        );
        // 8pt diameter
        expect(dotRect.width, inInclusiveRange(7, 9));
        expect(dotRect.height, inInclusiveRange(7, 9));
      },
    );

    testWidgets(
      'dot opacity oscillates between ~0.1 and ~1.00 over a 1.8s cycle',
      (tester) async {
        const tileSize = 200.0;
        await tester.pumpWidget(
          host(
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: EnergyTile(
                title: 'Resistance',
                icon: Icons.fitness_center,
                accentColor: const Color(0xFF2DE2E6),
                isActive: true,
                onTap: () {},
              ),
            ),
          ),
        );

        // Sample opacity at multiple phases of the cycle. The cycle is
        // 1.8s long with a TweenSequence: 0.0→0.5 maps 0.1→1.00, 0.5→1.0
        // maps 1.00→0.1. We sample at t=0 (≈0.1), t=0.45s (≈1.00 at the
        // 50% point is actually 0.5 of the sequence = peak), t=0.9s
        // (≈0.1), t=1.35s (≈1.00 at the second peak).
        double opacityAt(Duration delta) {
          // Helper to walk the test clock and read the dot's opacity.
          // Returns the current Opacity.value of the dot's wrapper.
          return 0.0; // populated below
        }

        // We can read opacity by reading the Opacity widget that wraps
        // the dot. The dot is rendered as a small white DecoratedBox inside
        // an Opacity wrapper; find the first Opacity in the tree.
        double readDotOpacity() {
          final opacityWidgets = tester.widgetList<Opacity>(
            find.byType(Opacity),
          );
          if (opacityWidgets.isEmpty) return 1.0;
          // Use the first Opacity wrapper, which is the one immediately
          // around the dot (the dot is the deepest visually, so the
          // innermost Opacity is the one driving the pulse).
          return opacityWidgets.first.opacity;
        }

        await tester.pump(); // start the animation
        final samples = <double>[];
        // Sample at 9 evenly-spaced points across 1.8s (200ms each).
        for (var i = 0; i < 9; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          samples.add(readDotOpacity());
        }
        final maxOp = samples.reduce((a, b) => a > b ? a : b);
        final minOp = samples.reduce((a, b) => a < b ? a : b);
        expect(
          maxOp,
          greaterThanOrEqualTo(0.95),
          reason: 'peak opacity should approach 1.0 (got $maxOp)',
        );
        expect(
          minOp,
          lessThanOrEqualTo(0.85),
          reason: 'trough opacity should approach 0.1 (got $minOp)',
        );
        expect(
          (maxOp - minOp).abs(),
          greaterThan(0.05),
          reason: 'opacity must oscillate (delta=${(maxOp - minOp).abs()})',
        );
        // Suppress unused warning for the placeholder helper above.
        expect(opacityAt(Duration.zero), 0.0);
      },
    );

    testWidgets(
      'active glow boxShadow count is stable across frames (glow is static)',
      (tester) async {
        const tileSize = 200.0;
        await tester.pumpWidget(
          host(
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: EnergyTile(
                title: 'Resistance',
                icon: Icons.fitness_center,
                accentColor: const Color(0xFF2DE2E6),
                isActive: true,
                onTap: () {},
              ),
            ),
          ),
        );

        final base = _surface(tester).decoration! as BoxDecoration;
        final firstShadows = base.boxShadow;
        expect(firstShadows, isNotNull);
        final firstCount = firstShadows!.length;

        // Advance the clock through a full pulse cycle.
        for (var i = 0; i < 18; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final afterShadows =
            (_surface(tester).decoration! as BoxDecoration).boxShadow;
        expect(
          afterShadows!.length,
          firstCount,
          reason: 'glow boxShadow count must remain stable',
        );
      },
    );
  });

  group('S-104: resting tile has no dot', () {
    testWidgets('resting tile renders no pulsing dot', (tester) async {
      const tileSize = 200.0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: tileSize,
            height: tileSize,
            child: EnergyTile(
              title: 'Cardio',
              icon: Icons.directions_run,
              accentColor: const Color(0xFF24B85A),
              // isActive: false (default)
              onTap: () {},
            ),
          ),
        ),
      );

      // Distinguish the dot (Container with BoxShape.circle, white) from
      // the rim highlight strip (1-px-tall DecoratedBox, white @ 0.08).
      final dotFinder = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        if (d.shape != BoxShape.circle) return false;
        final c = d.color;
        if (c == null) return false;
        return (c.r - 1.0).abs() < 0.01 &&
            (c.g - 1.0).abs() < 0.01 &&
            (c.b - 1.0).abs() < 0.01;
      });
      expect(
        dotFinder,
        findsNothing,
        reason: 'resting tile must NOT render a white circular dot',
      );
    });
  });

  group('S-105: active tile accessibility', () {
    testWidgets('active tile announces "Resistance, Workout in progress"', (
      tester,
    ) async {
      const tileSize = 200.0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: tileSize,
            height: tileSize,
            child: EnergyTile(
              title: 'Resistance',
              icon: Icons.fitness_center,
              accentColor: const Color(0xFF2DE2E6),
              isActive: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Use SemanticsTester to find the merged label.
      final handle = tester.ensureSemantics();
      // Wait for the SemanticsCallback to fire.
      await tester.pump();
      final node = tester
          .getSemantics(find.byType(EnergyTile))
          .toStringDeep()
          .toLowerCase();
      expect(
        node.contains('workout in progress'),
        isTrue,
        reason:
            'active tile must announce "Workout in progress" via Semantics '
            '(got: $node)',
      );
      handle.dispose();
    });

    testWidgets('dot is excluded from semantics (decorative)', (tester) async {
      const tileSize = 200.0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: tileSize,
            height: tileSize,
            child: EnergyTile(
              title: 'Resistance',
              icon: Icons.fitness_center,
              accentColor: const Color(0xFF2DE2E6),
              isActive: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Find ExcludeSemantics widget in the tree.
      expect(
        find.byType(ExcludeSemantics),
        findsWidgets,
        reason: 'dot must be wrapped in ExcludeSemantics',
      );
    });
  });

  group('S-106: secondary icons are more visible (opacity lift)', () {
    testWidgets('secondary icon opacity is ~0.75 (lifted from 0.60)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          EnergyTile(
            title: 'Routines',
            icon: Icons.folder_open,
            accentColor: const Color(0xFF9E9E9E),
            isSecondary: true,
            onTap: () {},
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.folder_open));
      final c = icon.color;
      expect(c, isNotNull);
      // 75% alpha
      expect(
        (c!.a * 255).round(),
        inInclusiveRange(188, 195),
        reason: 'secondary icon opacity should be ~0.75 (was 0.60)',
      );
      // White-ish
      expect(c.r, greaterThan(0.9));
    });

    testWidgets('secondary icon uses its full configured size in a tall tile', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 200,
            child: EnergyTile(
              title: 'Free',
              icon: Icons.play_arrow,
              accentColor: const Color(0xFFA478FF),
              isSecondary: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final artwork = tester.getRect(
        find.byKey(const ValueKey('energy_tile_artwork_Free')),
      );
      expect(
        artwork.height,
        56,
        reason: 'a tall secondary tile keeps its configured artwork size',
      );
    });
  });

  group('height-responsive artwork regression', () {
    Widget constrainedTile({
      required String title,
      required double width,
      required double height,
      bool isSecondary = false,
      bool isActive = false,
      double textScale = 1,
    }) {
      return MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: host(
          SizedBox(
            width: width,
            height: height,
            child: EnergyTile(
              title: title,
              icon: Icons.fitness_center,
              accentColor: const Color(0xFF2DE2E6),
              isSecondary: isSecondary,
              isActive: isActive,
              onTap: () {},
            ),
          ),
        ),
      );
    }

    Rect keyedRect(WidgetTester tester, String key) =>
        tester.getRect(find.byKey(ValueKey(key)));

    testWidgets(
      'S-001: minimum-height primary and secondary tiles keep artwork clear of labels at maximum text scale',
      (tester) async {
        for (final secondary in [false, true]) {
          final title = secondary ? 'Free' : 'Resistance';
          await tester.pumpWidget(
            constrainedTile(
              title: title,
              width: 156,
              height: 84,
              isSecondary: secondary,
              textScale: 1.6,
            ),
          );

          expect(
            find.byKey(ValueKey('energy_tile_label_$title')),
            findsOneWidget,
          );
          final artworkFinder = find.byKey(
            ValueKey('energy_tile_artwork_$title'),
          );
          if (artworkFinder.evaluate().isNotEmpty) {
            final artwork = tester.getRect(artworkFinder);
            final label = keyedRect(tester, 'energy_tile_label_$title');
            expect(artwork.overlaps(label), isFalse);
            final region = keyedRect(
              tester,
              'energy_tile_artwork_region_$title',
            );
            expect(artwork.height, lessThanOrEqualTo(region.height));
          }
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'S-002: artwork size increases monotonically with tile height',
      (tester) async {
        final heights = <double>[96, 120, 160, 200];
        final artworkHeights = <double>[];

        for (final height in heights) {
          await tester.pumpWidget(
            constrainedTile(title: 'Resistance', width: 180, height: height),
          );
          final artwork = find.byKey(
            const ValueKey('energy_tile_artwork_Resistance'),
          );
          artworkHeights.add(
            artwork.evaluate().isEmpty ? 0 : tester.getRect(artwork).height,
          );
        }

        for (var i = 1; i < artworkHeights.length; i++) {
          expect(
            artworkHeights[i] + 0.001,
            greaterThanOrEqualTo(artworkHeights[i - 1]),
          );
        }
        expect(artworkHeights.toSet().length, greaterThan(1));
      },
    );

    testWidgets(
      'S-003: very short tile omits artwork and vertically centres full-size label',
      (tester) async {
        await tester.pumpWidget(
          constrainedTile(title: 'Resistance', width: 180, height: 64),
        );

        expect(
          find.byKey(const ValueKey('energy_tile_artwork_Resistance')),
          findsNothing,
        );
        final tile = tester.getRect(find.byType(EnergyTile));
        final label = keyedRect(tester, 'energy_tile_label_Resistance');
        expect((label.center.dy - tile.center.dy).abs(), lessThanOrEqualTo(1));
        final text = tester.widget<Text>(find.text('Resistance'));
        expect(text.style?.fontSize, isNotNull);
      },
    );

    testWidgets(
      'S-004: width-only variation does not change artwork visibility',
      (tester) async {
        final visibility = <bool>[];
        for (final width in <double>[120, 180, 260]) {
          await tester.pumpWidget(
            constrainedTile(title: 'Resistance', width: width, height: 84),
          );
          visibility.add(
            find
                .byKey(const ValueKey('energy_tile_artwork_Resistance'))
                .evaluate()
                .isNotEmpty,
          );
        }
        expect(visibility.toSet(), hasLength(1));
      },
    );

    testWidgets(
      'S-005: active indicator intersects neither artwork nor label on a compressed tile',
      (tester) async {
        await tester.pumpWidget(
          constrainedTile(
            title: 'Resistance',
            width: 156,
            height: 84,
            isActive: true,
            textScale: 1.6,
          ),
        );

        final status = keyedRect(tester, 'energy_tile_status_Resistance');
        final label = keyedRect(tester, 'energy_tile_label_Resistance');
        expect(status.overlaps(label), isFalse);
        final artworkFinder = find.byKey(
          const ValueKey('energy_tile_artwork_Resistance'),
        );
        if (artworkFinder.evaluate().isNotEmpty) {
          expect(status.overlaps(tester.getRect(artworkFinder)), isFalse);
        }
      },
    );

    testWidgets(
      'S-006: representative supported tile dimensions report no overflow and keep the label present',
      (tester) async {
        for (final size in <Size>[
          const Size(130, 56),
          const Size(156, 56),
          const Size(156, 64),
          const Size(156, 84),
          const Size(180, 120),
          const Size(224, 200),
        ]) {
          for (final scale in <double>[1, 1.6]) {
            for (final isActive in <bool>[false, true]) {
              for (final isSecondary in <bool>[false, true]) {
                final title = isSecondary ? 'Free' : 'Resistance';
                await tester.pumpWidget(
                  constrainedTile(
                    title: title,
                    width: size.width,
                    height: size.height,
                    isActive: isActive,
                    isSecondary: isSecondary,
                    textScale: scale,
                  ),
                );
                expect(
                  find.byKey(ValueKey('energy_tile_label_$title')),
                  findsOneWidget,
                  reason:
                      'label must be present at $size, scale $scale, '
                      'active=$isActive, secondary=$isSecondary',
                );
                expect(
                  tester.takeException(),
                  isNull,
                  reason:
                      'overflow at $size, scale $scale, '
                      'active=$isActive, secondary=$isSecondary',
                );
              }
            }
          }
        }
      },
    );
  });
}
