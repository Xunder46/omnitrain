// filepath: test/bundled_food_asset_contract_test.dart
//
// Belt-and-braces contract for the bundled food-photo asset pipeline:
//
//   1. Every catalog food id resolves to a real `.webp` file under
//      `assets/images/` — the convention held by `FoodPhotoService` is
//      anchored to the on-disk layout.
//   2. Every `food_*.webp` file maps to a live catalog id — no orphan
//      files accumulate when a row is removed from `food_catalog.json`.
//   3. The shipped bytes stay inside an explicit budget so the bundle
//      remains suitable for over-the-air install on cellular.
//
// Uses `dart:io` / `dart:convert` (matching the docs-indexing test style)
// rather than the widget test harness because this is a pure file-system
// contract with no UI in scope.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/food_photo_service.dart';

void main() {
  group('Bundled food photo asset contract', () {
    // Budgets are intentionally strict (under, not at-or-under) so the
    // threshold is unambiguous and a regression on the exact boundary
    // surfaces in CI rather than being silently absorbed.
    const maxPerFileBytes = 30 * 1024; // strict under 30 KiB
    const maxTotalBytes = 4 * 1024 * 1024; // strict under 4 MiB

    late Directory imagesDir;
    late File catalogJson;
    late Map<String, dynamic> catalog;
    late Set<String> catalogIds;

    setUpAll(() {
      imagesDir = Directory('assets/images');
      catalogJson = File('assets/data/food_catalog.json');

      expect(
        imagesDir.existsSync(),
        isTrue,
        reason:
            'assets/images/ missing — bundled-photo tier cannot be tested '
            'without the on-disk photo directory.',
      );
      expect(
        catalogJson.existsSync(),
        isTrue,
        reason:
            'assets/data/food_catalog.json missing at project root — '
            'the contract test must be run from the project root.',
      );

      catalog =
          jsonDecode(catalogJson.readAsStringSync()) as Map<String, dynamic>;
      catalogIds = (catalog['foods'] as List<dynamic>)
          .map((dynamic e) => (e as Map<String, dynamic>)['id'] as String)
          .toSet();
    });

    test('every catalog id has a matching bundled photo on disk', () {
      final missing = <String>[];

      for (final id in catalogIds) {
        final path = FoodPhotoService.bundledPhotoAssetPath(id);
        if (!File(path).existsSync()) {
          missing.add('$id → $path');
        }
      }

      expect(
        missing,
        isEmpty,
        reason: missing.isEmpty
            ? 'never reached'
            : 'These catalog ids have no bundled photo at the expected '
                  '`assets/images/food_<id>.webp` path. Either the convention '
                  'drifted in `FoodPhotoService.bundledPhotoAssetPath`, or the '
                  'image was never added to the asset folder.\n'
                  'Missing:\n${missing.join('\n')}',
      );
    });

    test('every bundled photo maps to a live catalog id', () {
      final imageIds = imagesDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name.startsWith('food_') && name.endsWith('.webp'))
          .map(
            (name) =>
                name.substring('food_'.length, name.length - '.webp'.length),
          )
          .toSet();

      // Sanity check: the directory really does host the expected hero files.
      expect(
        imageIds.contains('chicken_breast'),
        isTrue,
        reason:
            'Smoke check — a representative catalog id (chicken_breast) '
            'should ship an `assets/images/food_chicken_breast.webp` file. '
            'If this fires, the listing logic above is probably wrong.',
      );

      final orphans = imageIds.difference(catalogIds).toList()..sort();

      expect(
        orphans,
        isEmpty,
        reason: orphans.isEmpty
            ? 'never reached'
            : 'These `food_*.webp` files do not map to any catalog id and '
                  'will never be displayed. Either remove them or restore the '
                  'missing row in `assets/data/food_catalog.json`.\n'
                  'Orphans:\n${orphans.join('\n')}',
      );
    });

    test('catalog and image directories agree on count', () {
      final imageCount = imagesDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name.startsWith('food_') && name.endsWith('.webp'))
          .length;

      expect(
        imageCount,
        catalogIds.length,
        reason:
            'Number of bundled food photos ($imageCount) does not match '
            'number of catalog foods (${catalogIds.length}). A drift usually '
            'means a row was added/removed from `food_catalog.json` without '
            'matching the asset folder, or vice versa.',
      );
    });

    test(
      'every bundled photo file is strictly under $maxPerFileBytes bytes',
      () {
        final oversized = <String>[];

        for (final file in imagesDir.listSync().whereType<File>()) {
          final name = file.uri.pathSegments.last;
          if (!name.startsWith('food_') || !name.endsWith('.webp')) continue;

          final bytes = file.lengthSync();
          if (bytes >= maxPerFileBytes) {
            oversized.add(
              '$name: $bytes bytes '
              '(${(bytes / 1024).toStringAsFixed(1)} KiB) — must be strictly '
              'less than ${maxPerFileBytes ~/ 1024} KiB',
            );
          }
        }

        expect(
          oversized,
          isEmpty,
          reason: oversized.isEmpty
              ? 'never reached'
              : 'One or more bundled food photos exceeded the per-file size '
                    'budget. Re-encode at the source (smaller dimensions or '
                    'higher quality reduction) so each file stays below '
                    '${maxPerFileBytes ~/ 1024} KiB.\n'
                    'Offending files:\n${oversized.join('\n')}',
        );
      },
    );

    test('total bundled-photo bytes are strictly under '
        '${maxTotalBytes ~/ (1024 * 1024)} MiB', () {
      var total = 0;
      var fileCount = 0;

      for (final file in imagesDir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.startsWith('food_') || !name.endsWith('.webp')) continue;
        total += file.lengthSync();
        fileCount += 1;
      }

      expect(
        total < maxTotalBytes,
        isTrue,
        reason:
            'Bundled food photos add up to $total bytes '
            '(${(total / (1024 * 1024)).toStringAsFixed(2)} MiB across '
            '$fileCount files). Total must stay strictly under '
            '${maxTotalBytes ~/ (1024 * 1024)} MiB so the app bundle keeps '
            'fitting inside the cellular install envelope.',
      );
    });
  });
}
