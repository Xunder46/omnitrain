import 'dart:typed_data';

/// Helper to inject a minimal valid 1×1 WebP into tests.
///
/// The bundled-photo convention is `assets/images/food_<id>.webp`, so widget
/// tests that exercise tier-2 (bundled-photo) of the FoodThumbnail precedence
/// chain serve a decodable `.webp` payload to the [FakeAssetBundle].
class TestImageHelper {
  /// A valid 1×1 lossless red WebP (36 bytes).
  ///
  /// These exact bytes are a RIFF/WEBP container with a VP8L stream and are
  /// verified decodable by the platform image codecs. Do NOT hand-edit them:
  /// invalid fixture bytes would make the bundled-photo tests exercise the
  /// placeholder fallback instead of the image path.
  ///
  /// Regenerate with a WebP-capable image encoder if the fixture ever needs to
  /// change; keep it tiny so the test remains self-contained.
  static final ByteData testWebp1x1Red = ByteData.view(
    Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, // 'RIFF'
      0x1C, 0x00, 0x00, 0x00, // file size minus 8 (28)
      0x57, 0x45, 0x42, 0x50, // 'WEBP'
      0x56, 0x50, 0x38, 0x4C, // 'VP8L'
      0x0F, 0x00, 0x00, 0x00, // chunk size (15)
      0x2F, 0x00, 0x00, 0x00, // signature byte 0x2F, width/height/etc.
      0x00, 0x07, 0x10, 0xFD,
      0x8F, 0xFE, 0x07, 0x22,
      0xA2, 0xFF, 0x01, 0x00,
    ]).buffer,
  );
}
