// filepath: test/helpers/fake_asset_bundle.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Test asset bundle that models the production condition accurately.
///
/// In production the app ships with a full `AssetManifest.bin` declaring every
/// asset path; only an individual file's *bytes* can be missing. `Image.asset`
/// (and `FoodThumbnail`'s bundled-photo tier) consults the manifest via
/// `AssetBundle.loadStructuredBinaryData` to validate the path, then calls
/// `load` to fetch the bytes. A missing file triggers `errorBuilder`; a
/// present file renders.
///
/// The previous version of this helper threw on every key not in the test's
/// `assets` map, including `AssetManifest.bin`. That made the bundled-photo
/// tests vacuous: every lookup — declared or not — failed the same way, so
/// no test verified that a shipped photo actually rendered. The fix loads
/// the real `build/unit_test_assets/AssetManifest.bin` once and serves it to
/// `Image.asset`, so path validation matches production. Bytes for assets the
/// test wants to exercise come from the test's `assets` map; any asset key the
/// test does *not* declare behaves exactly like a missing file in production
/// (the lookup throws, `errorBuilder` fires).
class FakeAssetBundle extends CachingAssetBundle {
  FakeAssetBundle(this.assets) {
    final manifestBytes = _loadManifestFromBuildDir();
    if (manifestBytes != null) {
      _manifestData = _decodeManifest(manifestBytes);
    }
  }

  /// Map of asset keys to decoded [ByteData].
  ///
  /// A test that includes a key here gets the bytes for that asset; the
  /// bundled-photo tier's `Image.asset` resolves and decodes them, mirroring
  /// production. A key the test does *not* include is treated as missing:
  /// `load` throws `FlutterError('Unable to load asset: $key')`, which is
  /// exactly the failure mode of a real file that has been removed from the
  /// asset directory.
  final Map<String, ByteData> assets;

  /// Raw bytes of the cached manifest (used to answer `load('AssetManifest.bin')`
  /// lookups) and the decoded manifest data, kept side by side.
  /// `_manifestData` is `null` if the test build directory does not provide
  /// a manifest. The raw bytes cache is process-wide so repeated
  /// `FakeAssetBundle` constructions in the same test don't re-read the
  /// file.
  Map<Object?, Object?>? _manifestData;

  static Uint8List? _cachedManifestBytes;

  /// One-shot loader for the manifest. Caches the raw bytes so repeated
  /// `FakeAssetBundle` constructions in the same test process don't re-read
  /// the file.
  Uint8List? _loadManifestFromBuildDir() {
    if (_cachedManifestBytes != null) return _cachedManifestBytes;
    final manifestFile = File('build/unit_test_assets/AssetManifest.bin');
    if (!manifestFile.existsSync()) return null;
    final bytes = manifestFile.readAsBytesSync();
    _cachedManifestBytes = bytes;
    return bytes;
  }

  /// Decodes the StandardMessageCodec-encoded `AssetManifest.bin`. Returns
  /// `null` if the bytes can't be decoded, which the test should treat as
  /// "no manifest available".
  static Map<Object?, Object?>? _decodeManifest(Uint8List bytes) {
    try {
      final data = ByteData.view(bytes.buffer);
      final decoded = const StandardMessageCodec().decodeMessage(data);
      if (decoded is Map<Object?, Object?>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Whether the test manifest declares [path] as a known asset.
  /// Returns `false` when the manifest could not be loaded or does not list
  /// the path — the same as a path that was never declared in pubspec.
  bool manifestContains(String path) {
    final manifest = _manifestData;
    if (manifest == null) return false;
    return manifest.containsKey(path);
  }

  @override
  Future<ByteData> load(String key) async {
    // Always serve the test environment's manifest if we have it. Without
    // this, `Image.asset`'s path validation throws before `load` is ever
    // asked for the real asset, so the bundled-photo tier never reaches
    // its image render path.
    if (key == 'AssetManifest.bin') {
      final bytes = _cachedManifestBytes;
      if (bytes == null) {
        throw FlutterError(
          'AssetManifest.bin not available — did you run '
          '`flutter test` so build/unit_test_assets is populated?',
        );
      }
      return ByteData.view(bytes.buffer);
    }
    // Test-supplied bytes win. A key here represents an asset the test
    // has explicitly declared; production-equivalent: file present, decode
    // succeeds.
    final testData = assets[key];
    if (testData != null) {
      return testData;
    }
    // No bytes for this key. Model the production "missing file" failure:
    // throw, exactly as `CachingAssetBundle` does when a real bundled file
    // has been deleted from the asset directory. `Image.asset` translates
    // this into an `errorBuilder` invocation.
    throw FlutterError('Unable to load asset: $key');
  }

  /// Test-side helper: returns the manifest entry for [path] (the variants
  /// list), or `null` if the manifest does not declare it. Mirrors
  /// `AssetManifest.getAssetVariants(path)` so widget code that wants to
  /// distinguish "asset is declared" from "asset is genuinely missing" can
  /// do so against the same source the renderer consults.
  List<dynamic>? getAssetVariants(String path) {
    final manifest = _manifestData;
    if (manifest == null) return null;
    final entry = manifest[path];
    if (entry is List) return entry;
    return null;
  }

  /// Convenience for tests: returns whether the manifest entry for [path]
  /// declares any variant at all. Equivalent to a non-null result from
  /// [getAssetVariants], kept terse for callers that only need the bool.
  @visibleForTesting
  bool isDeclaredAsset(String path) => manifestContains(path);
}
