// filepath: test/food_form_shipped_photo_test.dart
//
// Regression tests for the **Edit Food must show the shipped
// photo for a bundled food** fix.
//
// Symptom (reported by the user): opening the Edit Food screen
// for a bundled food shows an empty "Add photo" placeholder
// even when the food has a shipped `.webp` photograph — the
// same photo renders correctly on the library list. To the
// user it looks like the app lost the picture, or that the
// editor is a different food from the one they tapped.
//
// Root cause: the form's `FoodFormImageTile` consulted only
// `Food.imagePath` (the user's choice) and never asked the
// bundled-photo tier. The library list's `FoodThumbnail` walks
// the three-tier chain (user photo → bundled photo →
// placeholder); the form's tile had a binary user-photo /
// placeholder fork. Bundled foods with no user-set photo fell
// straight to the placeholder.
//
// Fix: `FoodFormImageTile` now renders the image body through
// the existing `FoodThumbnail` widget — the same widget the
// library list uses — passing `foodId` and `catalogId` from the
// form's `initial` Food. The tile's overlay chrome (× clear
// and edit replace) stays; the × (clear) overlay is hidden when
// the form's local `_imagePath` is null/empty so the user cannot
// try to delete a shipped photo they did not set. The bundled
// tier is render-only — it never writes to `Food.imagePath`.
//
// Behaviour pinned by these tests (S-001..S-007):

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/features/nutrition/widgets/food_thumbnail.dart';
import 'package:omnitrain/features/nutrition/widgets/food_thumbnail_stub.dart'
    if (dart.library.io) 'package:omnitrain/features/nutrition/widgets/food_thumbnail_io.dart';

import 'helpers/fake_asset_bundle.dart';
import 'helpers/test_image_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Build a tile directly (without the full form). This is the
  // unit under test; the form just threads foodId/catalogId into
  // it. The tile's API after the fix is:
  //   imagePath, imageStorage, foodId, catalogId,
  //   onPickGallery, onPickCamera, onClear, size.
  Widget pumpTile({
    Key? key,
    String? imagePath,
    String? foodId,
    String? catalogId,
    FakeAssetBundle? bundle,
    VoidCallback? onClear,
    VoidCallback? onPickGallery,
    VoidCallback? onPickCamera,
  }) {
    final tile = FoodFormImageTile(
      key: key,
      imagePath: imagePath,
      foodId: foodId,
      catalogId: catalogId,
      onPickGallery: onPickGallery ?? () {},
      onPickCamera: onPickCamera ?? () {},
      onClear: onClear ?? () {},
    );
    final wrapped = bundle == null
        ? tile
        : DefaultAssetBundle(bundle: bundle, child: tile);
    return MaterialApp(home: Scaffold(body: wrapped));
  }

  // ─── S-001: bundled food with shipped photo, no user photo ─────────────
  testWidgets(
    'S-001: bundled food with shipped photo renders the shipped photo '
    '(no Add-photo placeholder, no fallback)',
    (WidgetTester tester) async {
      // The bundled `chicken_breast` resolves to
      // `assets/images/food_chicken_breast.webp`. Inject a
      // decodable 1×1 red webp so the bundled tier renders.
      final fakeBundle = FakeAssetBundle({
        'assets/images/food_chicken_breast.webp':
            TestImageHelper.testWebp1x1Red,
      });
      await tester.pumpWidget(
        pumpTile(
          imagePath: null, // no user photo
          foodId: 'chicken_breast',
          catalogId: null,
          bundle: fakeBundle,
        ),
      );
      await tester.pumpAndSettle();

      // The form uses FoodThumbnail for the image body. Its
      // presence is the proof we hit the bundled tier (the
      // placeholder would be a Material/Container, not a
      // FoodThumbnail).
      expect(
        find.byType(FoodThumbnail),
        findsOneWidget,
        reason: 'image body must delegate to FoodThumbnail to reach '
            'the bundled-photo tier',
      );
      // The "Add photo" placeholder text must NOT appear when
      // the bundled tier rendered something.
      expect(find.text('Add photo'), findsNothing);
      // Image widget with AssetImage is present (Image.asset
      // produced by FoodThumbnail's bundled-photo branch).
      final imageWidgets = find.byType(Image);
      bool foundAsset = false;
      for (int i = 0; i < imageWidgets.evaluate().length; i++) {
        final w = imageWidgets.evaluate().elementAt(i).widget as Image;
        if (w.image is AssetImage || w.image is ExactAssetImage) {
          foundAsset = true;
          break;
        }
      }
      expect(foundAsset, isTrue,
          reason: 'FoodThumbnail bundled tier renders Image.asset');

      // Strengthened assertions: the photo must actually *display*
      // (render to a non-zero size), and the fallback icon-only
      // placeholder must NOT be in the visible tree. The previous
      // helper made the bundled tier's `Image.asset` fail every
      // time, so this assertion was vacuous — the harness now serves
      // the asset manifest and the test bytes, so the bundled-photo
      // render path is exercised end-to-end.
      final imageFinder = find.byType(Image);
      final imageRenderBox = tester.renderObject<RenderBox>(imageFinder);
      expect(imageRenderBox.size.width, greaterThan(0),
          reason: 'bundled photo must render with non-zero width');
      expect(imageRenderBox.size.height, greaterThan(0),
          reason: 'bundled photo must render with non-zero height');
      expect(find.byIcon(Icons.restaurant_outlined), findsNothing,
          reason: 'no icon-only fallback should be visible when the '
              'bundled photo rendered');
    },
  );

  // ─── S-002: user photo wins over bundled photo ─────────────────────────
  testWidgets(
    'S-002: user photo takes precedence over the shipped photo',
    (WidgetTester tester) async {
      if (kIsWeb) {
        return; // web stub ignores user photo
      }
      // Even though the bundle has the bundled asset, the
      // user's `imagePath` (a non-empty string) must win.
      final fakeBundle = FakeAssetBundle({
        'assets/images/food_chicken_breast.webp':
            TestImageHelper.testWebp1x1Red,
      });
      await tester.pumpWidget(
        pumpTile(
          imagePath: '/managed/user_picked.jpg',
          foodId: 'chicken_breast',
          catalogId: null,
          bundle: fakeBundle,
        ),
      );
      await tester.pumpAndSettle();

      // Tier 1 (FoodThumbnailImage, the IO renderer for the
      // user's photo) is reached, not the bundled tier.
      expect(find.byType(FoodThumbnailImage), findsOneWidget,
          reason: 'tier-1 (user photo) must be selected over tier-2');
      // No AssetImage must be rendered (bundled tier skipped).
      final imageWidgets = find.byType(Image);
      for (int i = 0; i < imageWidgets.evaluate().length; i++) {
        final w = imageWidgets.evaluate().elementAt(i).widget as Image;
        expect(
          w.image is! AssetImage && w.image is! ExactAssetImage,
          isTrue,
          reason: 'bundled Image.asset must not run when user photo is set',
        );
      }
    },
  );

  // ─── S-003: no shipped asset, no user photo → placeholder ──────────────
  testWidgets(
    'S-003: no user photo + no bundled asset renders the placeholder',
    (WidgetTester tester) async {
      // Empty bundle: nothing for the bundled tier to find.
      final fakeBundle = FakeAssetBundle({});
      await tester.pumpWidget(
        pumpTile(
          imagePath: null,
          foodId: 'no_such_food_id',
          catalogId: null,
          bundle: fakeBundle,
        ),
      );
      await tester.pumpAndSettle();

      // FoodThumbnail is rendered (the tile delegates to it).
      expect(find.byType(FoodThumbnail), findsOneWidget);
      // The bundled tier attempted to load an asset (this is
      // expected — the placeholder is reached via the
      // `errorBuilder` of `Image.asset` when the bundled file
      // is missing), so the placeholder icon is the visible
      // surface.
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget,
          reason: 'placeholder icon is rendered when no source has a photo');
      // The clear (×) overlay is hidden (no user photo).
      expect(find.byIcon(Icons.close), findsNothing);
    },
  );

  // ─── S-004: clear affordance gating ─────────────────────────────────────
  testWidgets(
    'S-004a: clear (×) overlay is absent when only the shipped photo is '
    'displayed (no user photo to clear)',
    (WidgetTester tester) async {
      final fakeBundle = FakeAssetBundle({
        'assets/images/food_chicken_breast.webp':
            TestImageHelper.testWebp1x1Red,
      });
      await tester.pumpWidget(
        pumpTile(
          imagePath: null,
          foodId: 'chicken_breast',
          bundle: fakeBundle,
        ),
      );
      await tester.pumpAndSettle();

      // The × clear icon must NOT be present when the user has
      // no photo to clear.
      expect(
        find.byIcon(Icons.close),
        findsNothing,
        reason: 'clear overlay must be hidden when only shipped photo shows',
      );
      // The edit (replace) overlay IS present (the user can
      // still pick their own photo over the shipped one).
      expect(find.byIcon(Icons.edit), findsOneWidget);
    },
  );

  testWidgets(
    'S-004b: clear (×) overlay is present when a user photo is displayed',
    (WidgetTester tester) async {
      if (kIsWeb) return;
      await tester.pumpWidget(
        pumpTile(
          imagePath: '/managed/user_picked.jpg',
          foodId: 'chicken_breast',
        ),
      );
      await tester.pumpAndSettle();

      // Both overlays are visible — the user can clear or replace.
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    },
  );

  // ─── S-005: clearing a user photo over a shipped photo falls back to
  //          the shipped photo, not the placeholder ───────────────────────
  testWidgets(
    'S-005: clearing a user photo on a food with a shipped photo returns '
    'to the shipped photo (not the empty placeholder)',
    (WidgetTester tester) async {
      // The "form state" before clearing: user has picked a
      // photo over the shipped one. We simulate by pumping the
      // tile with `imagePath != null` first, then re-pumping
      // with `imagePath = null` (the user's clear action).
      final fakeBundle = FakeAssetBundle({
        'assets/images/food_chicken_breast.webp':
            TestImageHelper.testWebp1x1Red,
      });

      // Stage 1: user photo set → tile renders the user photo.
      await tester.pumpWidget(
        pumpTile(
          imagePath: '/managed/user_picked.jpg',
          foodId: 'chicken_breast',
          bundle: fakeBundle,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Stage 2: user clears → imagePath becomes null in the
      // form's local state → tile should now render the
      // shipped photo (tier 2) rather than the placeholder
      // (tier 3).
      await tester.pumpWidget(
        pumpTile(
          imagePath: null,
          foodId: 'chicken_breast',
          bundle: fakeBundle,
        ),
      );
      await tester.pumpAndSettle();

      // The shipped photo must actually render (not just be in
      // the tree as an Image widget whose errorBuilder fell
      // through). With the helper fix, the bundled tier's
      // Image.asset resolves the declared bytes, so the
      // RenderBox size is non-zero.
      final bundledImageFinder = find.byType(Image);
      expect(bundledImageFinder, findsOneWidget,
          reason: 'shipped-photo Image must be in the tree');
      final bundledRenderBox =
          tester.renderObject<RenderBox>(bundledImageFinder);
      expect(bundledRenderBox.size.width, greaterThan(0),
          reason: 'shipped photo must render with non-zero width '
                'after clearing the user photo');
      expect(bundledRenderBox.size.height, greaterThan(0),
          reason: 'shipped photo must render with non-zero height '
                'after clearing the user photo');
      // No icon-only placeholder should be visible — clearing
      // must fall back to the bundled photo, not the empty
      // placeholder.
      expect(find.byIcon(Icons.restaurant_outlined), findsNothing,
          reason: 'icon-only placeholder must NOT be visible when '
                'the bundled photo rendered');
      // No "Add photo" caption either — clearing must not land on
      // tier 3.
      expect(find.text('Add photo'), findsNothing);
      // Clear overlay is hidden (no user photo).
      expect(find.byIcon(Icons.close), findsNothing);
      // Edit overlay is present.
      expect(find.byIcon(Icons.edit), findsOneWidget);
    },
  );

  // ─── S-006: library copy resolves via catalogId ─────────────────────────
  testWidgets(
    'S-006: library copy of a bundled food resolves the shipped photo via '
    'catalogId (not its own id)',
    (WidgetTester tester) async {
      // The library copy's id is fresh; only the catalogId
      // resolves to the shipped asset.
      final fakeBundle = FakeAssetBundle({
        'assets/images/food_chicken_breast.webp':
            TestImageHelper.testWebp1x1Red,
        // Intentionally no asset for the library copy's fresh
        // id; the resolution must go via catalogId.
      });
      await tester.pumpWidget(
        pumpTile(
          imagePath: null,
          foodId: 'lib_copy_xyz_123',
          catalogId: 'chicken_breast',
          bundle: fakeBundle,
        ),
      );
      await tester.pumpAndSettle();

      // The shipped photo must actually render — not just be in
      // the tree as an Image widget whose errorBuilder fired.
      // With the helper fix, the bundled tier's Image.asset
      // resolves via catalogId, and the RenderBox has non-zero
      // size.
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget,
          reason: 'shipped-photo Image must be in the tree');
      final imageRenderBox =
          tester.renderObject<RenderBox>(imageFinder);
      expect(imageRenderBox.size.width, greaterThan(0),
          reason: 'shipped photo must render with non-zero width '
                'when resolved via catalogId');
      expect(imageRenderBox.size.height, greaterThan(0),
          reason: 'shipped photo must render with non-zero height '
                'when resolved via catalogId');
      // The bundled tier rendered an Image.asset — assert that
      // it is an AssetImage-backed Image widget, not the icon-only
      // placeholder.
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, anyOf(isA<AssetImage>(), isA<ExactAssetImage>()),
          reason: 'library copy must resolve bundled photo via catalogId');
      // No icon-only placeholder should be visible.
      expect(find.byIcon(Icons.restaurant_outlined), findsNothing,
          reason: 'icon-only placeholder must NOT be visible when '
                'the shipped photo rendered via catalogId');
      // No "Add photo" caption — tier 3 must not be reached.
      expect(find.text('Add photo'), findsNothing);
    },
  );
}
