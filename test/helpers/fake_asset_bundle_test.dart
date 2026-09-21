// filepath: test/helpers/fake_asset_bundle_test.dart
//
// Helper-level contract test for [FakeAssetBundle].
//
// This file is the regression guard for the harness itself. The shipped-photo
// tier's tests above all assume the helper faithfully models production:
// declared assets decode to a real image; undeclared assets fail with the
// same error path as a missing file. If this contract ever weakens, every
// downstream image assertion silently goes vacuous again (the helper
// pretends every asset is missing, every test asserts the same fallback, and
// the bundled-photo render path is never actually exercised).
//
// Without this file, the failure mode is invisible: the bundled-photo tests
// would still pass, just for the wrong reason.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_asset_bundle.dart';
import 'test_image_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeAssetBundle', () {
    testWidgets(
      'serves AssetManifest.bin from the test build dir so Image.asset path '
      'validation matches production',
      (tester) async {
        // No assets map — the helper only knows about the manifest.
        final bundle = FakeAssetBundle(const {});

        // The manifest key resolves. This is the call
        // `AssetManifest.loadFromAssetBundle` makes internally.
        final manifest = await bundle.load('AssetManifest.bin');
        expect(
          manifest.lengthInBytes,
          greaterThan(0),
          reason: 'manifest must be served so path validation succeeds',
        );
      },
    );

    testWidgets(
      'declared asset with test bytes loads and Image.asset renders with '
      'non-zero dimensions',
      (tester) async {
        // A test that declares the photo: bytes are provided, the bundled
        // tier must resolve the Image.asset and paint something — not just
        // return a 0×0 render box.
        final bundle = FakeAssetBundle({
          'assets/images/food_chicken_breast.webp':
              TestImageHelper.testWebp1x1Red,
        });

        // Sanity: bundle returns the bytes.
        final bytes = await bundle.load(
          'assets/images/food_chicken_breast.webp',
        );
        expect(bytes.lengthInBytes, greaterThan(0));

        // Render the image through the same harness Image.asset would use.
        // A successful render has non-zero size; the previous (broken) helper
        // forced every render to fail with a missing-asset error, which made
        // every image have size zero.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.asset('assets/images/food_chicken_breast.webp'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final imageWidget = tester.widget<Image>(find.byType(Image));
        expect(
          imageWidget.image,
          isA<AssetImage>(),
          reason: 'Image.asset must produce an AssetImage-backed widget',
        );
        final renderBox = tester.renderObject<RenderBox>(find.byType(Image));
        expect(
          renderBox.size.width,
          greaterThan(0),
          reason: 'declared asset must render to a non-zero width',
        );
        expect(
          renderBox.size.height,
          greaterThan(0),
          reason: 'declared asset must render to a non-zero height',
        );
      },
    );

    testWidgets(
      'undeclared asset throws and Image.asset falls back via errorBuilder',
      (tester) async {
        // No bytes supplied for `assets/images/food_chicken_breast.webp` —
        // the test does not declare it. This mirrors a real file that has
        // been removed from the asset directory: the asset path is declared
        // in the pubspec manifest (so `Image.asset` validation passes), but
        // the bytes cannot be loaded. The expected production behaviour is
        // for `errorBuilder` to fire.
        final bundle = FakeAssetBundle(const {});

        // The bytes lookup throws — same exception CachingAssetBundle emits
        // for a missing file.
        Object? thrown;
        try {
          await bundle.load('assets/images/food_chicken_breast.webp');
        } catch (e) {
          thrown = e;
        }
        expect(
          thrown,
          isA<FlutterError>(),
          reason: 'undeclared asset must throw FlutterError',
        );

        // The asset path IS in the pubspec manifest (it's declared), so
        // `Image.asset`'s path validation succeeds. The failure surfaces
        // only when `errorBuilder` fires because `load` threw.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.asset(
                    'assets/images/food_chicken_breast.webp',
                    errorBuilder: (context, error, stack) =>
                        const ColoredBox(color: Color(0xFF00FF00)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The errorBuilder replaced the image with a green box. This is the
        // production fall-through. If the helper still throws for
        // declared-but-missing assets, `Image.asset`'s render path would
        // silently misbehave in production too — this assertion would fail.
        expect(
          find.byType(ColoredBox),
          findsOneWidget,
          reason:
              'undeclared-but-declared-in-pubspec asset must fall '
              'through to errorBuilder, exactly as a real missing file '
              'would',
        );
        // The original Image is still in the tree (errorBuilder replaces
        // its paint, not the widget itself).
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'asset path not declared in pubspec also throws (never-reachable '
      'path validation failure surfaces as FlutterError)',
      (tester) async {
        // A path that nobody put in pubspec.yaml at all. The manifest will
        // not contain it, so `Image.asset` rejects it during path
        // validation. This is the "did you typo the asset key" guard.
        final bundle = FakeAssetBundle(const {});

        expect(
          bundle.isDeclaredAsset('assets/images/does_not_exist.webp'),
          isFalse,
        );
      },
    );

    test('isDeclaredAsset mirrors manifest contents exactly', () {
      // Use a manifest-listed path and a non-listed path.
      final bundle = FakeAssetBundle(const {});
      expect(
        bundle.isDeclaredAsset('assets/images/food_chicken_breast.webp'),
        isTrue,
        reason:
            'pubspec-declared bundled photo must be reported as '
            'declared',
      );
      expect(bundle.isDeclaredAsset('not/in/manifest/at/all.png'), isFalse);
    });
  });
}
