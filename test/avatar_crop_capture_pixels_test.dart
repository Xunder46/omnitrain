// filepath: test/avatar_crop_capture_pixels_test.dart
//
// Regression test for the **cropped avatar keeps the background
// edges** bug.
//
// Symptom (reported by the user): after picking a photo, the
// crop step shows dark bands above and below the photo inside
// the circle, and those bands end up in the saved profile
// picture.
//
// Two root causes, both fixed in `AvatarCropSheet`:
//
//   1. The image was laid out with `BoxFit.contain` inside the
//      square viewport, so any non-square photo was letterboxed
//      and the empty bands were captured as part of the avatar.
//      The pannable child is now sized to **cover** the viewport
//      (shorter side == viewport side), with the long axis
//      overflowing for the user to pan through.
//   2. The circular dim scrim + hairline ring were painted
//      INSIDE the captured `RepaintBoundary`, so the preview
//      chrome was baked into the PNG (a dimmed square frame and
//      a light ring at the circle's edge). The scrim now sits
//      outside the boundary.
//
// Both are asserted on the actual captured pixels: a solid-color
// source must come back as that solid color, fully opaque, in
// every pixel of the capture.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/features/profile/widgets/avatar_crop_sheet.dart';

/// Encode a solid-red PNG of [width]×[height]. Real encoded bytes
/// (not a synth fixture) because the sheet decodes them twice:
/// once via `Image.memory` for display, once via
/// `instantiateImageCodec` for the cover sizing.
Future<Uint8List> _solidRedPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Decoded RGBA view of a captured PNG.
class _Pixels {
  final int width;
  final int height;
  final ByteData rgba;

  const _Pixels(this.width, this.height, this.rgba);

  /// (r, g, b, a) at pixel ([x], [y]).
  List<int> at(int x, int y) {
    final offset = (y * width + x) * 4;
    return <int>[
      rgba.getUint8(offset),
      rgba.getUint8(offset + 1),
      rgba.getUint8(offset + 2),
      rgba.getUint8(offset + 3),
    ];
  }
}

Future<_Pixels> _decodePixels(Uint8List pngBytes) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return _Pixels(image.width, image.height, data!);
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Push the crop sheet on [sourceBytes], tap **Use Photo**, and
/// return the PNG bytes the sheet popped with.
Future<Uint8List> _capture(WidgetTester tester, Uint8List sourceBytes) async {
  Uint8List? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await Navigator.of(context).push<Uint8List?>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => AvatarCropSheet(imageBytes: sourceBytes),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.byType(AvatarCropSheet), findsOneWidget);

  // The source decode (for the cover sizing) and the capture
  // itself both need real time — `toImage` schedules an engine
  // frame that the fake clock cannot drive.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pumpAndSettle();

  await tester.tap(find.text('Use Photo'));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  });
  await tester.pumpAndSettle();

  expect(
    find.byType(AvatarCropSheet),
    findsNothing,
    reason: 'sheet must pop after capture',
  );
  expect(captured, isNotNull, reason: 'confirm must return capture bytes');
  return captured!;
}

/// Assert every pixel of [pixels] is opaque red. Samples a grid
/// rather than all ~1M pixels so the test stays fast while still
/// covering the letterbox bands (top/bottom edges), the scrim
/// corners, and the hairline ring's radius.
void _expectAllOpaqueRed(_Pixels pixels, {required String reason}) {
  const steps = 60;
  final dx = (pixels.width - 1) / steps;
  final dy = (pixels.height - 1) / steps;
  for (var iy = 0; iy <= steps; iy++) {
    for (var ix = 0; ix <= steps; ix++) {
      final x = (ix * dx).round();
      final y = (iy * dy).round();
      final px = pixels.at(x, y);
      expect(
        px[3],
        255,
        reason: 'pixel ($x, $y) must be fully opaque — $reason',
      );
      // Tolerances absorb the sampling filter, not a visible
      // band: a letterboxed pixel reads as (0,0,0,0) and a
      // scrim-dimmed one as roughly (140,0,0,255).
      expect(
        px[0],
        greaterThan(200),
        reason: 'pixel ($x, $y) must keep the source red — $reason',
      );
      expect(
        px[1],
        lessThan(60),
        reason: 'pixel ($x, $y) must not be lightened — $reason',
      );
      expect(
        px[2],
        lessThan(60),
        reason: 'pixel ($x, $y) must not be lightened — $reason',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AvatarCropSheet: captured pixels', () {
    testWidgets(
      'a landscape photo is captured edge-to-edge — no letterbox bands',
      (tester) async {
        late Uint8List source;
        await tester.runAsync(() async {
          source = await _solidRedPng(400, 200);
        });

        final captured = await _capture(tester, source);

        late _Pixels pixels;
        await tester.runAsync(() async {
          pixels = await _decodePixels(captured);
        });

        expect(
          pixels.width,
          pixels.height,
          reason: 'the avatar capture is square',
        );
        _expectAllOpaqueRed(
          pixels,
          reason:
              'a 2:1 source must cover the square viewport, not be '
              'letterboxed into it',
        );
      },
    );

    testWidgets(
      'a portrait photo is captured edge-to-edge — no letterbox bands',
      (tester) async {
        late Uint8List source;
        await tester.runAsync(() async {
          source = await _solidRedPng(200, 400);
        });

        final captured = await _capture(tester, source);

        late _Pixels pixels;
        await tester.runAsync(() async {
          pixels = await _decodePixels(captured);
        });

        _expectAllOpaqueRed(
          pixels,
          reason:
              'a 1:2 source must cover the square viewport, not be '
              'letterboxed into it',
        );
      },
    );

    testWidgets(
      'the circular scrim and its hairline are preview chrome, not captured '
      'pixels',
      (tester) async {
        late Uint8List source;
        await tester.runAsync(() async {
          source = await _solidRedPng(300, 300);
        });

        final captured = await _capture(tester, source);

        late _Pixels pixels;
        await tester.runAsync(() async {
          pixels = await _decodePixels(captured);
        });

        // A square source cannot letterbox, so any deviation from
        // pure red here is the scrim (dimmed corners) or the
        // hairline ring (lightened pixels on the circle's edge).
        _expectAllOpaqueRed(
          pixels,
          reason:
              'the dim scrim / hairline ring must not be baked into the '
              'saved avatar',
        );
      },
    );
  });
}
