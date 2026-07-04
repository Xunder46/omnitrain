// filepath: test/avatar_crop_sheet_test.dart
//
// Standalone tests for `AvatarCropSheet` exercised via direct
// Navigator push. These cover the full picker → crop → save flow
// against the live render pipeline:
//
//   * `RepaintBoundary.toImage` capture works in the test
//     environment (software rendering, headless).
//   * The captured bytes flow out of the sheet via `Navigator.pop`.
//   * The persisted file under the managed directory is a
//     non-empty PNG (signature check).
//   * Cancel returns `null` and leaves any pre-existing avatar
//     unchanged.
//
// The capture happens inside `tester.runAsync` because
// `RepaintBoundary.toImage` requires real time to elapse for the
// engine to schedule and finish the frame, and
// `writeAsBytes` is real I/O that the test zone's fake async
// clock cannot drive.
//
// See `test/avatar_crop_test.dart` for the wired ProfileScreen
// tests (sheet appears, Remove Photo unaffected, etc.).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/widgets/avatar_crop_sheet.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:path/path.dart' as p;

import 'helpers/test_image_storage.dart';

/// A real, decodable JPEG byte buffer. We need a real JPEG so
/// `Image.memory` can decode it inside the crop sheet, which
/// then renders into the `RepaintBoundary` we capture via
/// `toImage`. A 2×2 black JPEG is the smallest practical one.
Uint8List _smallValidJpeg() {
  return Uint8List.fromList(<int>[
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
    0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
    0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
    0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
    0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x02,
    0x00, 0x02, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
    0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
    0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
    0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
    0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
    0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
    0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
    0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
    0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
    0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
    0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
    0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
    0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
    0x00, 0x00, 0x3F, 0x00, 0xFB, 0xD0, 0xFF, 0xD9,
  ]);
}

/// A tiny non-uniform PNG (four differently-colored quadrants),
/// encoded via `dart:ui`. Used by the off-center/zoomed crop test
/// — a uniform-color fixture like [_smallValidJpeg] renders
/// identically under any pan/zoom transform (translating or
/// scaling a solid color still yields that same solid color), so
/// it cannot prove the `InteractiveViewer`'s matrix actually
/// changes the captured pixels. Must be awaited inside
/// `tester.runAsync` — the `dart:ui` image pipeline needs real
/// time to schedule, same as the capture path it is feeding.
Future<Uint8List> _quadrantPatternImage() async {
  const side = 8.0;
  const half = side / 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, half, half), Paint()..color = Colors.red);
  canvas.drawRect(
      const Rect.fromLTWH(half, 0, half, half), Paint()..color = Colors.blue);
  canvas.drawRect(
      const Rect.fromLTWH(0, half, half, half), Paint()..color = Colors.green);
  canvas.drawRect(const Rect.fromLTWH(half, half, half, half),
      Paint()..color = Colors.yellow);
  final picture = recorder.endRecording();
  final image = await picture.toImage(side.toInt(), side.toInt());
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Helper that drives the picker → crop step → save flow against
/// the live render pipeline (no synth fixtures). Pushes the
/// AvatarCropSheet, taps Use Photo, lets the capture finish in
/// real time, then persists the bytes via `persistImageBytes` +
/// `updateAvatarPath`. Returns the basename assigned to the
/// profile.
Future<String> _driveCaptureFlow({
  required WidgetTester tester,
  required TestImageStorage imageStorage,
  required ProfileState profileState,
  Uint8List? imageBytes,
}) async {
  final bytes = imageBytes ?? _smallValidJpeg();

  late Uint8List? capturedBytes;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                capturedBytes = await Navigator.of(context).push<Uint8List?>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => AvatarCropSheet(imageBytes: bytes),
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

  // Tap Use Photo. The capture + persist runs in real async;
  // we let the engine schedule and finish a frame, then the
  // continuation (toByteData, dispose, Navigator.pop) runs in
  // the test zone. After pumpAndSettle the captured bytes are
  // available via the local.
  await tester.tap(find.text('Use Photo'));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  });
  await tester.pumpAndSettle();

  expect(find.byType(AvatarCropSheet), findsNothing,
      reason: 'sheet must pop after capture');
  expect(capturedBytes, isNotNull,
      reason: 'sheet must pop with non-null bytes on confirm');

  // Persist via the wired state method, inside runAsync so the
  // writeAsBytes real I/O completes.
  String? basename;
  await tester.runAsync(() async {
    basename =
        await imageStorage.service.persistImageBytes(capturedBytes!);
    await profileState.updateAvatarPath(basename);
  });
  await tester.pumpAndSettle();

  return basename!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AvatarCropSheet: standalone capture flow', () {
    testWidgets(
      'Cancel returns null and does not write any managed file',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final profileState =
            ProfileState(repo, imageStorage: imageStorage.service);
        await profileState.loadProfile();

        final bytes = _smallValidJpeg();
        late Uint8List? capturedBytes;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      capturedBytes =
                          await Navigator.of(context).push<Uint8List?>(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) =>
                              AvatarCropSheet(imageBytes: bytes),
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

        await tester.tap(find.text('Cancel'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();

        expect(find.byType(AvatarCropSheet), findsNothing);
        expect(capturedBytes, isNull,
            reason: 'cancel must return null bytes from the sheet');

        // No managed files written (the managed dir is created
        // on first persist; check the listing if it exists).
        final managedDir = Directory(imageStorage.service.managedDirectoryPath);
        if (managedDir.existsSync()) {
          expect(managedDir.listSync(), isEmpty,
              reason: 'cancel must not write any file under the managed dir');
        }
        // Avatar path is unchanged (still null on a fresh state).
        expect(profileState.profile?.avatarPath, isNull);
      },
    );

    testWidgets(
      'Use Photo captures PNG bytes via RepaintBoundary.toImage and the '
      'persisted file under the managed dir is a valid PNG',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final profileState =
            ProfileState(repo, imageStorage: imageStorage.service);
        await profileState.loadProfile();

        final basename = await _driveCaptureFlow(
          tester: tester,
          imageStorage: imageStorage,
          profileState: profileState,
        );

        // The persisted file is a fresh PNG with the captured bytes.
        expect(p.extension(basename), '.png');
        final managedFile = File(
          p.join(imageStorage.service.managedDirectoryPath, basename),
        );
        expect(managedFile.existsSync(), isTrue);

        final storedBytes = managedFile.readAsBytesSync();
        expect(storedBytes.length, greaterThan(8));
        expect(storedBytes[0], 0x89,
            reason: 'PNG signature byte 0 must be 0x89');
        expect(storedBytes[1], 0x50);
        expect(storedBytes[2], 0x4E);
        expect(storedBytes[3], 0x47);

        // Avatar is wired to the new basename.
        expect(profileState.profile?.avatarPath, basename);
      },
    );

    testWidgets(
      'a deliberately off-center, zoomed crop preserves the user\'s '
      'framing — captured bytes differ from an identity capture',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);

        // Non-uniform fixture: a plain color would look identical
        // under any pan/zoom, which would make this test
        // vacuously true. See `_quadrantPatternImage`.
        late Uint8List patternBytes;
        await tester.runAsync(() async {
          patternBytes = await _quadrantPatternImage();
        });

        // First capture: identity transformation.
        final imageStorageA = TestImageStorage.create();
        addTearDown(imageStorageA.dispose);
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final stateA =
            ProfileState(repoA, imageStorage: imageStorageA.service);
        await stateA.loadProfile();
        final identityBasename = await _driveCaptureFlow(
          tester: tester,
          imageStorage: imageStorageA,
          profileState: stateA,
          imageBytes: patternBytes,
        );
        final identityBytes = File(
          p.join(imageStorageA.service.managedDirectoryPath, identityBasename),
        ).readAsBytesSync();

        // Second capture: pan + zoom via the InteractiveViewer.
        final imageStorageB = TestImageStorage.create();
        addTearDown(imageStorageB.dispose);
        final repoB = MockWorkoutRepository();
        await repoB.initialize();
        final stateB =
            ProfileState(repoB, imageStorage: imageStorageB.service);
        await stateB.loadProfile();

        // Pump the sheet again, drive a non-identity matrix
        // BEFORE tapping Use Photo.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await Navigator.of(context).push<Uint8List?>(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => AvatarCropSheet(
                            imageBytes: patternBytes,
                          ),
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

        // ignore: avoid-dynamic
        final cropState =
            tester.state(find.byType(AvatarCropSheet)) as dynamic;
        // ignore: avoid-dynamic
        final originalMatrix =
            cropState.transformationControllerForTesting.value as dynamic;
        // ignore: avoid-dynamic
        final transformedMatrix = (originalMatrix.clone() as dynamic)
          // ignore: avoid-dynamic
          ..translate(-40.0, -20.0)
          ..scale(1.5);
        // ignore: avoid-dynamic
        cropState.transformationControllerForTesting.value =
            // ignore: avoid-dynamic
            transformedMatrix as dynamic;
        await tester.pumpAndSettle();

        // Tap Use Photo and let the capture run.
        await tester.tap(find.text('Use Photo'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        });
        await tester.pumpAndSettle();
        expect(find.byType(AvatarCropSheet), findsNothing);

        // Now we need the captured bytes from this second flow.
        // Re-drive through the persist helper would lose the
        // matrix change, so we persist via the service directly
        // — but we don't have access to the captured bytes
        // because the closure above discarded them. Re-drive
        // using the helper to also verify state wiring; the
        // matrix change doesn't survive across `_driveCaptureFlow`
        // because it builds its own pumpWidget.
        //
        // Instead, drive a one-off that captures the bytes from
        // a closure local.
        late Uint8List capturedBytes;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      capturedBytes =
                          await Navigator.of(context).push<Uint8List?>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => AvatarCropSheet(
                                    imageBytes: patternBytes,
                                  ),
                                ),
                              ) ??
                              Uint8List(0);
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

        // ignore: avoid-dynamic
        final cropState2 =
            tester.state(find.byType(AvatarCropSheet)) as dynamic;
        // ignore: avoid-dynamic
        final original2 = cropState2.transformationControllerForTesting.value
            // ignore: avoid-dynamic
            as dynamic;
        // ignore: avoid-dynamic
        final transformed2 = (original2.clone() as dynamic)
          // ignore: avoid-dynamic
          ..translate(-40.0, -20.0)
          ..scale(1.5);
        // ignore: avoid-dynamic
        cropState2.transformationControllerForTesting.value =
            // ignore: avoid-dynamic
            transformed2 as dynamic;
        await tester.pumpAndSettle();

        await tester.tap(find.text('Use Photo'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        });
        await tester.pumpAndSettle();

        final zoomedBytes = capturedBytes;
        expect(zoomedBytes.length, greaterThan(0));

        // The zoomed capture differs from the identity capture —
        // the InteractiveViewer's matrix actually affects what
        // RepaintBoundary.toImage returns. Both captures are
        // valid PNGs.
        expect(zoomedBytes, isNot(equals(identityBytes)));
        expect(zoomedBytes[0], 0x89);
        expect(zoomedBytes[1], 0x50);
        expect(zoomedBytes[2], 0x4E);
        expect(zoomedBytes[3], 0x47);
      },
    );
  });
}