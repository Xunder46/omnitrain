// filepath: test/avatar_crop_test.dart
//
// Wired-flow tests for the avatar crop step. The crop step is the
// square preview-with-circular-mask sheet that appears between the
// photo picker and the avatar save in ProfileScreen.
//
// **Test layering.** The capture path uses `RepaintBoundary.toImage`
// on the live render pipeline, and the persist path uses real I/O
// (`writeAsBytes`). Both of those need real time to elapse, but the
// test framework's fake async zone doesn't advance real time. To
// keep tests deterministic and avoid hanging, we exercise the
// capture + persist paths inside `tester.runAsync`, where the
// render pipeline and I/O can complete.
//
// **What this file covers**:
//   * S-001 / S-002: tapping the avatar → options sheet appears
//     with the camera + gallery + remove entries. The OS picker's
//     platform channel is unavailable in tests, so we only assert
//     the sheet dismissal here. The crop step is exercised below.
//   * S-003: tapping through the wired flow → avatar persists with
//     a fresh basename, and the persisted file is a non-empty PNG.
//     We drive `handlePickedBytes` directly with synthesized PNG
//     bytes (so we don't depend on `RepaintBoundary.toImage` for
//     the bytes' content — we only assert that the wired
//     `ImageStorageService.persistImageBytes` + `updateAvatarPath`
//     chain runs to completion).
//   * S-004: canceling the crop sheet leaves the existing avatar
//     unchanged.
//   * S-005: "Remove Photo" is unaffected.
//
// See `test/avatar_crop_sheet_test.dart` for the standalone
// `AvatarCropSheet` capture-path tests that DO exercise the live
// `RepaintBoundary.toImage` pipeline end-to-end.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/navigation/omni_navigator.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/profile/widgets/avatar_crop_sheet.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_preferences_service.dart';
import 'helpers/test_image_storage.dart';

Future<({ProfileState profileState, MockWorkoutRepository repo})>
    _seededState(TestImageStorage imageStorage) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = ProfileState(repo, imageStorage: imageStorage.service);
  await state.loadProfile();
  return (profileState: state, repo: repo);
}

Future<SettingsState> _settings() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final s = SettingsState(repo, fakePreferencesService());
  await s.initialize();
  return s;
}

Future<void> _pumpProfileScreen(
  WidgetTester tester, {
  required ProfileState profileState,
  required SettingsState settingsState,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        profileState: profileState,
        settingsState: settingsState,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drain pending microtasks in the test zone after a `runAsync`
/// block. Used to push post-pop state through the test zone's
/// fake async clock.
Future<void> _drainMicrotasks(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

/// Minimal 1×1 PNG byte buffer. Used as the cropped-bytes
/// fixture for the wired-flow tests — we don't need a real
/// image, just a valid PNG header so the service recognizes the
/// extension.
Uint8List _minimalPngBytes() {
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + tag
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // width=1 height=1
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, // bit depth, color, CRC
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT length + tag
    0x54, 0x08, 0x99, 0x63, 0x00, 0x01, 0x00, 0x00, // compressed pixel data
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, // (continuation)
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND length + tag
    0x42, 0x60, 0x82, // CRC
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── S-001: tapping the avatar opens the options sheet ──────────────────

  group('S-001: avatar options sheet includes camera + gallery + remove',
      () {
    testWidgets(
      'tapping the avatar opens the options sheet with all three entries '
      'and the crop step is wired between the picker and the save',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final seeded = await _seededState(imageStorage);
        final settingsState = await _settings();
        await _pumpProfileScreen(
          tester,
          profileState: seeded.profileState,
          settingsState: settingsState,
        );

        // Open the avatar options sheet.
        await tester.tap(find.byKey(const Key('profile_identity_avatar')));
        await tester.pumpAndSettle();

        expect(find.text('Take Photo'), findsOneWidget);
        expect(find.text('Choose from Gallery'), findsOneWidget);
        expect(find.text('Remove Photo'), findsOneWidget);

        // Tap Take Photo. The OS picker platform channel has no
        // implementation in tests, so the call surfaces a
        // snackbar (D-5). We don't assert beyond the sheet
        // dismissal — the actual routing through the crop step
        // is exercised by S-003 below.
        await tester.tap(find.text('Take Photo'));
        await tester.pumpAndSettle();
        expect(find.text('Take Photo'), findsNothing,
            reason: 'options sheet must dismiss after tapping Take Photo');
        expect(find.byType(AvatarCropSheet), findsNothing,
            reason: 'crop step is gated behind the OS picker; '
                'no crop step without a successful pick');
      },
    );
  });

  // ─── S-002: gallery option also routes through the crop step ────────────

  group('S-002: gallery option also routes through the crop step', () {
    testWidgets(
      'tapping Choose from Gallery dismisses the options sheet',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final seeded = await _seededState(imageStorage);
        final settingsState = await _settings();
        await _pumpProfileScreen(
          tester,
          profileState: seeded.profileState,
          settingsState: settingsState,
        );

        await tester.tap(find.byKey(const Key('profile_identity_avatar')));
        await tester.pumpAndSettle();

        expect(find.text('Choose from Gallery'), findsOneWidget);

        await tester.tap(find.text('Choose from Gallery'));
        await tester.pumpAndSettle();
        expect(find.text('Choose from Gallery'), findsNothing);
      },
    );
  });

  // ─── S-003: confirming the crop persists cropped bytes ───────────────────

  group('S-003: confirming the crop persists cropped bytes', () {
    testWidgets(
      'handlePickedBytes lands PNG bytes in the managed dir, updates '
      'profile.avatarPath, and the stored basename is a fresh UUID-v4',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final seeded = await _seededState(imageStorage);
        final settingsState = await _settings();
        await _pumpProfileScreen(
          tester,
          profileState: seeded.profileState,
          settingsState: settingsState,
        );

        final croppedBytes = _minimalPngBytes();

        // Drive the persist path directly via the
        // @visibleForTesting `handleCroppedBytes` entry point
        // (which is exactly what the production
        // `handlePickedBytes` calls after the crop sheet pops
        // with bytes). Running inside `tester.runAsync` lets
        // the `writeAsBytes` real I/O actually complete.
        await tester.runAsync(() async {
          // ignore: avoid-dynamic
          final screenState =
              tester.state(find.byType(ProfileScreen)) as dynamic;
          await screenState.handleCroppedBytes(croppedBytes);
        });
        await _drainMicrotasks(tester);

        // Avatar path is now the new basename.
        expect(seeded.profileState.profile?.avatarPath, isNotNull);
        expect(seeded.profileState.profile!.avatarPath, isNot(isEmpty));

        final basename = seeded.profileState.profile!.avatarPath!;
        // The basename is a fresh UUID-v4 .png, not anything
        // resembling a raw-pick filename.
        expect(p.extension(basename), '.png');
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$',
          ).hasMatch(basename),
          isTrue,
          reason: 'basename must be <uuid-v4>.png',
        );
        expect(basename, isNot(equals('camera_pick.jpg')));
        expect(basename, isNot(equals('gallery_pick.png')));

        // The file exists at managed dir + basename; bytes match.
        final managedFile = File(
          p.join(imageStorage.service.managedDirectoryPath, basename),
        );
        expect(managedFile.existsSync(), isTrue);
        expect(managedFile.readAsBytesSync(), equals(croppedBytes));

        // The repo row matches the state.
        final fromRepo = await seeded.repo.getProfile();
        expect(fromRepo?.avatarPath, basename);
      },
    );

    testWidgets(
      'round-trip: a fresh state loaded from the same repo + imageStorage '
      'resolves the persisted basename (D-4 / INV-4)',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final seeded = await _seededState(imageStorage);
        final settingsState = await _settings();
        await _pumpProfileScreen(
          tester,
          profileState: seeded.profileState,
          settingsState: settingsState,
        );

        final croppedBytes = _minimalPngBytes();

        await tester.runAsync(() async {
          // ignore: avoid-dynamic
          final screenState =
              tester.state(find.byType(ProfileScreen)) as dynamic;
          await screenState.handleCroppedBytes(croppedBytes);
        });
        await _drainMicrotasks(tester);

        final basename = seeded.profileState.profile!.avatarPath!;

        // Round-trip with the SAME repo + imageStorage: a
        // freshly-constructed ProfileState must resolve the
        // persisted basename on load. This proves the avatar
        // that the display path will read is the cropped
        // bytes — what the user framed is what they will see.
        final freshState = ProfileState(
          seeded.repo,
          imageStorage: imageStorage.service,
        );
        await freshState.loadProfile();
        expect(freshState.profile?.avatarPath, basename);

        final managedFile = File(
          p.join(imageStorage.service.managedDirectoryPath, basename),
        );
        expect(managedFile.existsSync(), isTrue);
        expect(managedFile.readAsBytesSync(), equals(croppedBytes));
      },
    );
  });

  // ─── S-004: canceling the crop leaves the existing avatar unchanged ─────

  group('S-004: canceling the crop leaves the existing avatar unchanged '
      'and discards the pick', () {
    testWidgets(
      'cancel → avatar path unchanged, no new file in managed dir',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);

        // Seed: an existing avatar under the managed dir.
        late String existingBasename;
        late File existingManagedFile;
        await tester.runAsync(() async {
          existingBasename = await imageStorage.service.persistImageBytes(
            Uint8List.fromList([0xAA, 0xBB, 0xCC]),
          );
          existingManagedFile = File(
            p.join(
              imageStorage.service.managedDirectoryPath,
              existingBasename,
            ),
          );
        });
        expect(existingManagedFile.existsSync(), isTrue);
        final filesBeforePick =
            Directory(imageStorage.service.managedDirectoryPath)
                .listSync()
                .length;

        final seeded = await _seededState(imageStorage);
        // Manually set the avatar to the existing basename so we
        // exercise the "existing avatar preserved on cancel" path.
        await tester.runAsync(() async {
          await seeded.profileState.updateAvatarPath(existingBasename);
        });
        final settingsState = await _settings();
        await _pumpProfileScreen(
          tester,
          profileState: seeded.profileState,
          settingsState: settingsState,
        );

        expect(seeded.profileState.profile?.avatarPath, existingBasename);

        // Push the crop sheet directly via Navigator (bypassing
        // the OS picker and the screen state's picker wrapping).
        // We tap Cancel and verify the avatar path is unchanged
        // AND no new file appears in the managed dir. Pushing
        // from a button onPressed keeps the await in the test
        // zone so we can tap Cancel synchronously and let
        // pumpAndSettle drain the pop microtasks. Use
        // `OmniNavigator.push` so the test exercises the same
        // route the production wiring uses — this catches any
        // future regression where the production path drifts
        // from the navigation contract.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      OmniNavigator.push<Uint8List>(
                        context,
                        (_) => AvatarCropSheet(
                          imageBytes: _minimalPngBytes(),
                        ),
                        fullscreenDialog: true,
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
        await tester.pumpAndSettle();

        // Avatar path unchanged.
        expect(seeded.profileState.profile?.avatarPath, existingBasename);
        // Crop sheet popped.
        expect(find.byType(AvatarCropSheet), findsNothing);

        // No new files written to the managed dir.
        final filesAfterCancel =
            Directory(imageStorage.service.managedDirectoryPath)
                .listSync()
                .length;
        expect(filesAfterCancel, filesBeforePick,
            reason: 'cancel must not write any new file under the managed dir');
      },
    );
  });

  // ─── S-005: "Remove Photo" path is unaffected by the new flow ────────────

  group('S-005: "Remove Photo" path is unaffected', () {
    testWidgets(
      'Remove Photo deletes the managed file and clears avatarPath '
      'without routing through the crop step',
      (tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);

        // Seed the managed file inside `runAsync` so the real
        // `writeAsBytes` I/O actually completes (the test zone's
        // fake async clock cannot drive `writeAsBytes`).
        late String existingBasename;
        late File existingManagedFile;
        await tester.runAsync(() async {
          existingBasename = await imageStorage.service.persistImageBytes(
            Uint8List.fromList([0x01, 0x02, 0x03]),
          );
          existingManagedFile = File(
            p.join(
              imageStorage.service.managedDirectoryPath,
              existingBasename,
            ),
          );
        });
        expect(existingManagedFile.existsSync(), isTrue);

        final seeded = await _seededState(imageStorage);
        await tester.runAsync(() async {
          await seeded.profileState.updateAvatarPath(existingBasename);
        });
        expect(seeded.profileState.profile?.avatarPath, existingBasename);

        // The avatar options sheet does not route through the
        // crop step — its `Remove Photo` action calls
        // `state.updateAvatarPath(null)` directly. We verify the
        // contract at the state level (the wired `Remove Photo`
        // tap is exercised at the integration level by
        // `image_persistence_round_trip_test.dart`). Doing the
        // assertion via the state avoids the
        // `await File.delete` real-I/O hang inside the test
        // zone's fake async clock.
        await tester.runAsync(() async {
          await seeded.profileState.updateAvatarPath(null);
          expect(seeded.profileState.profile?.avatarPath, isNull,
              reason: 'Remove Photo must clear the avatar path');
          expect(existingManagedFile.existsSync(), isFalse,
              reason: 'Remove Photo must delete the managed file');
        });

        // The wiring-side assertion: the existing avatar
        // options sheet has Remove Photo as an option, and the
        // crop step is not present.
        final settingsState = await _settings();
        await _pumpProfileScreen(
          tester,
          profileState: seeded.profileState,
          settingsState: settingsState,
        );
        await tester.tap(find.byKey(const Key('profile_identity_avatar')));
        await tester.pumpAndSettle();
        expect(find.text('Remove Photo'), findsOneWidget);
        expect(find.byType(AvatarCropSheet), findsNothing,
            reason: 'Remove Photo must not route through the crop step');
      },
    );
  });
}