// 125b Phase C: the phone sends a routine's Focus in `routines_down`
// (D-12564), whenever the routine has one.
//
// Plan: `docs/plans/2026-11-05-125-wrist-routine-focus-modality-plan/`
// `2026-11-05-125b-watch-app-plan.md`, D-12564, D-12566.
// Scenario mapping:
//   S-12573 buildRoutinesDown carries focusModality for a routine that has one
//   S-12574 a null Focus emits no key
//   S-12575 one build: sports emitted, '' omitted, null omitted, legacy verbatim
//   S-12576 a Focus edit re-sends at the wrist's old since (Mock + revisioned)
//   S-12577 a Focus clear re-sends without the key
//   S-12578 a Focus edit moves the template's stamp
//   S-12579 the sender's output conforms to the wire schema
//   S-12580 a relaunched phone re-sends the focus at the wrist's old since
//
// Plain `test()`, no widget. The request-handler harness (`_firstStamp`, the
// recording transport, the clock) is copied from
// `test/watch_sync_changed_only_test.dart`, which another session modified —
// it is NOT edited from here. The template/segment/effort seeding follows
// `_seedRoutine` in `test/watch_routine_link_import_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_sync_request_handler.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/revisioned_repository.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

const int _atMs = 1730000000000;

/// The stamp the first request carries: the test clock truncated to whole
/// milliseconds. The clock starts with a non-zero microsecond part, so a test
/// that sees this stamp has seen the truncation.
final DateTime _firstStamp = DateTime.utc(2026, 10, 23, 12, 0, 0, 123);

/// A transport that keeps what it was handed, in send order.
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}

  List<String> get types => [
    for (final frame in sent) frame['type']! as String,
  ];

  /// Every frame of [type], in send order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final frame in sent)
      if (frame['type'] == type) frame,
  ];
}

/// The test's clock: a variable the handler's `clock:` reads, so a test moves
/// time. It starts with a non-zero microsecond part, which the handler's stamp
/// must truncate away.
final TestClock clock = TestClock(DateTime.utc(2026, 10, 23, 12, 0, 0, 123, 456));

/// Lets real-time futures (the autosave timer above all) run, until [done]
/// holds or a few seconds pass: the polls are generous but bounded, and the
/// assertions name no wall-clock number.
Future<void> _waitFor(
  Future<bool> Function() done,
  String reason,
) async {
  for (var wait = 0; wait < 80; wait++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('gave up waiting: $reason');
}

/// One two-slot routine (`drill` + `set`, as the 122 seeding shapes them)
/// whose exercises exist in the catalog, with [updatedAtMs] settable for
/// S-12578's old template.
Future<WorkoutTemplate> _seedRoutine(
  MockWorkoutRepository repository, {
  required String id,
  required String name,
  String? focusModality,
  required List<String> effortIds,
  int updatedAtMs = _atMs,
}) async {
  await seedExercise(
    repository,
    id: 'ex-hold-$id',
    name: 'Hold $id',
    capabilities: ['hold', 'time', 'sets'],
  );
  await seedExercise(
    repository,
    id: 'ex-reps-$id',
    name: 'Reps $id',
    capabilities: ['reps', 'sets', 'load'],
  );
  await repository.createTemplate(
    WorkoutTemplate(
      id: id,
      name: name,
      focusModality: focusModality,
      createdAtMs: _atMs,
      updatedAtMs: updatedAtMs,
    ),
  );
  await repository.createTemplateSegment(
    TemplateSegment(
      id: 'seg-$id',
      templateId: id,
      orderIndex: 0,
      segmentType: BlockTypes.strengthSets,
      name: 'Main',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  var order = 0;
  for (final effortId in effortIds) {
    await repository.createTemplateEffort(
      TemplateEffort(
        id: effortId,
        templateSegmentId: 'seg-$id',
        orderIndex: order++,
        effortKind: order == 1 ? BlockTypes.drill : BlockTypes.set,
        exerciseId: order == 1 ? 'ex-hold-$id' : 'ex-reps-$id',
        createdAtMs: _atMs,
      ),
    );
  }
  return await repository.getTemplateById(id) ?? (throw StateError('seeding'));
}

/// The `routines_down` frame [fromLast] frames from the end of the capture,
/// so a test that never clears it can name the first answer and the re-send.
Map<String, Object?> _routinesDownFrame(
  _RecordingTransport transport, {
  int fromLast = 1,
}) => transport
    .ofType('routines_down')
    .reversed
    .take(fromLast)
    .last;

/// The one routine map inside a `routines_down` frame.
Map<String, Object?> routineOf(Map<String, Object?> frame) =>
    objectsOf(asObject(frame['payload'])['routines']).single;

/// The `generatedAt` stamp of a `routines_down` frame.
DateTime stampOf(Map<String, Object?> frame) =>
    parseUtcIso(asObject(frame['payload'])['generatedAt']);

/// Loads the routine named [templateId] into a fresh [RoutineState] over
/// [repository] so the test can edit the routine's Focus the way the user's
/// editor does. The caller owns `cancelPendingAutosave` on the returned state.
Future<RoutineState> _openRoutine(
  MockWorkoutRepository repository,
  String templateId,
) async {
  final state = RoutineState(repository);
  await state.loadRoutineForEditing(templateId);
  return state;
}

void main() {
  late MockWorkoutRepository repository;
  late SettingsState settings;
  late _RecordingTransport transport;
  late WatchSyncRequestHandler handler;

  setUp(() async {
    repository = MockWorkoutRepository();
    await repository.initialize();
    settings = SettingsState(repository, fakePreferencesService());
    transport = _RecordingTransport();
    clock.now = DateTime.utc(2026, 10, 23, 12, 0, 0, 123, 456);
    handler = WatchSyncRequestHandler(
      mirror: LiveSessionMirrorState(
        transport: transport,
        snapshot: watchSessionPlaceholder,
      ),
      transport: transport,
      repository: repository,
      settings: settings,
      foodLibrary: FoodLibraryState(repository),
      clock: clock.call,
    );
  });

  group('125b D-12564 the phone emits the routine Focus', () {
    test(
      'S-12573 buildRoutinesDown carries focusModality for a routine that '
      'has one (125b D-12564)',
      () async {
        for (final focus in const [
          Modality.cardioEndurance,
          Modality.resistanceLifting,
          Modality.sports,
          Modality.isometricStretching,
        ]) {
          final repository = MockWorkoutRepository();
          await repository.initialize();
          await _seedRoutine(
            repository,
            id: 'tpl-$focus',
            name: 'Routine $focus',
            focusModality: focus,
            effortIds: ['teff-$focus-a', 'teff-$focus-b'],
          );

          final message = await WatchReferenceSync.buildRoutinesDown(
            repository: repository,
            generatedAt: clock.now,
          );
          final routines = objectsOf(asObject(message['payload'])['routines']);
          expect(routines, hasLength(1), reason: 'one routine for $focus');
          final routine = routines.single;
          expect(
            routine['focusModality'],
            focus,
            reason: 'S-12573 the Focus travels verbatim for $focus',
          );
          expect(
            routine.containsKey('updatedAt'),
            isTrue,
            reason: 'the stamp still travels for $focus',
          );
          expect(
            routine['segments'],
            isNotEmpty,
            reason: 'the segments still travel for $focus',
          );
        }
      },
    );

    test('S-12574 buildRoutinesDown emits NO focusModality key for a null '
        'Focus, not null', () async {
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Mixed Day',
        focusModality: null,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: clock.now,
      );
      final routine = routineOf(message);
      expect(
        routine.containsKey('focusModality'),
        isFalse,
        reason: 'S-12574 an emitted null would make the wrist refuse the list',
      );
    });

    test('S-12575 one build: sports emitted, empty string omitted, null '
        'omitted, legacy_unknown verbatim', () async {
      await _seedRoutine(
        repository,
        id: 'tpl-sports',
        name: 'Sports Day',
        focusModality: Modality.sports,
        effortIds: ['teff-sports-a', 'teff-sports-b'],
      );
      await _seedRoutine(
        repository,
        id: 'tpl-empty',
        name: 'Old Data',
        focusModality: '',
        effortIds: ['teff-empty-a', 'teff-empty-b'],
      );
      await _seedRoutine(
        repository,
        id: 'tpl-null',
        name: 'No Focus',
        focusModality: null,
        effortIds: ['teff-null-a', 'teff-null-b'],
      );
      await _seedRoutine(
        repository,
        id: 'tpl-legacy',
        name: 'Legacy Key',
        focusModality: 'legacy_unknown',
        effortIds: ['teff-legacy-a', 'teff-legacy-b'],
      );

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: clock.now,
      );
      final routines = {
        for (final routine
            in objectsOf(asObject(message['payload'])['routines']))
          routine['routineId'] as String: routine,
      };
      expect(routines.keys.toList(), [
        'tpl-sports',
        'tpl-empty',
        'tpl-null',
        'tpl-legacy',
      ], reason: 'the four templates all built');
      expect(
        routines['tpl-sports']!['focusModality'],
        Modality.sports,
        reason: 'a known value travels verbatim',
      );
      expect(
        routines['tpl-empty']!.containsKey('focusModality'),
        isFalse,
        reason: 'S-12575 an empty value would break the schema minLength',
      );
      expect(
        routines['tpl-null']!.containsKey('focusModality'),
        isFalse,
        reason: 'S-12575 a null Focus emits no key',
      );
      expect(
        routines['tpl-legacy']!['focusModality'],
        'legacy_unknown',
        reason: 'S-12575 the phone does not filter on the wrist table',
      );
    });

    test('S-12576 (Mock arm) a Focus edit re-sends the routines at the '
        "wrist's old since, with the Focus aboard", () async {
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: null,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final firstStamp = stampOf(_routinesDownFrame(transport));
      expect(firstStamp, _firstStamp);

      clock.advance(const Duration(seconds: 7));
      final state = await _openRoutine(repository, 'tpl-r');
      await state.updateRoutineFocusModality(Modality.sports);
      await _waitFor(
        () async =>
            (await repository.getTemplateById('tpl-r'))?.focusModality ==
            Modality.sports,
        'the autosave to land the Focus in the repository',
      );
      state.cancelPendingAutosave();

      expect(
        await handler.handle(WatchTransportRequest.routines, since: firstStamp),
        isTrue,
        reason: 'the edit moved the stamped content, so the frame re-travels',
      );

      expect(
        transport.ofType('routines_down'),
        hasLength(2),
        reason: 'S-12576 the same since is answered again, not dropped',
      );
      final resent = _routinesDownFrame(transport);
      expect(
        stampOf(resent).isAfter(firstStamp),
        isTrue,
        reason: "S-12576 the re-send is stamped later than the wrist's since",
      );
      expect(
        routineOf(resent)['focusModality'],
        Modality.sports,
        reason: 'S-12576 the re-sent frame carries the new Focus',
      );
    });

    test('S-12576 (revisioned arm) a revision bump after the Focus edit '
        "re-sends at the wrist's old since, with the Focus aboard",
        () async {
      final repo = RevisionedRepository();
      await repo.initialize();
      repository = repo;
      settings = SettingsState(repo, fakePreferencesService());
      handler = WatchSyncRequestHandler(
        mirror: LiveSessionMirrorState(
          transport: transport,
          snapshot: watchSessionPlaceholder,
        ),
        transport: transport,
        repository: repo,
        settings: settings,
        foodLibrary: FoodLibraryState(repo),
        clock: clock.call,
      );
      await _seedRoutine(
        repo,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: null,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final firstStamp = stampOf(_routinesDownFrame(transport));

      clock.advance(const Duration(seconds: 7));
      final state = await _openRoutine(repo, 'tpl-r');
      await state.updateRoutineFocusModality(Modality.sports);
      await _waitFor(
        () async =>
            (await repo.getTemplateById('tpl-r'))?.focusModality ==
            Modality.sports,
        'the autosave to land the Focus',
      );
      state.cancelPendingAutosave();
      repo.revision = (repo.revision ?? 1) + 1;

      expect(
        await handler.handle(WatchTransportRequest.routines, since: firstStamp),
        isTrue,
      );

      expect(
        transport.ofType('routines_down'),
        hasLength(2),
        reason: 'S-12576 the revision moved, so no held frame is reused',
      );
      final resent = _routinesDownFrame(transport);
      expect(
        stampOf(resent).isAfter(firstStamp),
        isTrue,
      );
      expect(
        routineOf(resent)['focusModality'],
        Modality.sports,
      );
    });

    test('S-12577 a Focus clear re-sends the routines without the key',
        () async {
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: Modality.sports,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final firstAnswer = _routinesDownFrame(transport, fromLast: 2);
      expect(
        routineOf(firstAnswer)['focusModality'],
        Modality.sports,
        reason: 'the Focus rode the first answer',
      );
      final firstStamp = stampOf(firstAnswer);

      clock.advance(const Duration(seconds: 7));
      final state = await _openRoutine(repository, 'tpl-r');
      await state.updateRoutineFocusModality(null);
      await _waitFor(
        () async =>
            (await repository.getTemplateById('tpl-r'))?.focusModality == null,
        'the autosave to land the clear in the repository',
      );
      state.cancelPendingAutosave();

      expect(
        await handler.handle(WatchTransportRequest.routines, since: firstStamp),
        isTrue,
      );
      expect(
        transport.ofType('routines_down'),
        hasLength(2),
        reason: 'S-12577 the clear also moves the stamped content',
      );
      final resent = _routinesDownFrame(transport);
      expect(
        routineOf(resent).containsKey('focusModality'),
        isFalse,
        reason: 'S-12577 the cleared routine carries no focusModality key',
      );
    });

    test('S-12578 a Focus edit moves the template stamp beyond 1000, for a '
        'set and for a clear', () async {
      await _seedRoutine(
        repository,
        id: 'tpl-old',
        name: 'Old Stamp',
        focusModality: null,
        effortIds: ['teff-old-a', 'teff-old-b'],
        updatedAtMs: 1000,
      );

      final state = await _openRoutine(repository, 'tpl-old');
      expect(state.currentTemplate!.updatedAtMs, 1000);

      await state.updateRoutineFocusModality(Modality.cardioEndurance);
      expect(
        state.currentTemplate!.updatedAtMs,
        greaterThan(1000),
        reason: 'S-12578 the set stamps the template fresh',
      );
      final stampedSet = state.currentTemplate!.updatedAtMs;
      await _waitFor(
        () async =>
            (await repository.getTemplateById('tpl-old'))!.updatedAtMs ==
            stampedSet,
        'the autosave to move the stored stamp for the set',
      );

      await state.updateRoutineFocusModality(null);
      expect(
        state.currentTemplate!.updatedAtMs,
        greaterThan(stampedSet),
        reason: 'S-12578 the clear also stamps fresh, not back to 1000',
      );
      final stampedClear = state.currentTemplate!.updatedAtMs;
      await _waitFor(
        () async {
          final stored = await repository.getTemplateById('tpl-old');
          return stored!.updatedAtMs == stampedClear &&
              stored.focusModality == null;
        },
        'the autosave to move the stored stamp for the clear',
      );
      state.cancelPendingAutosave();
    });

    test('S-12579 the sender output for the four Focus values conforms to '
        'the wire schema with zero rejections', () async {
      for (final focus in const [
        Modality.cardioEndurance,
        Modality.resistanceLifting,
        Modality.sports,
        Modality.isometricStretching,
      ]) {
        await _seedRoutine(
          repository,
          id: 'tpl-$focus',
          name: 'Routine $focus',
          focusModality: focus,
          effortIds: ['teff-$focus-a', 'teff-$focus-b'],
        );
      }

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: clock.now,
      );
      expect(
        loadProtocolValidator().validateEnvelope(message),
        isEmpty,
        reason: 'S-12579 the whole envelope validates, key included',
      );
    });

    test('S-12580 a relaunched phone (fresh handler, no held frame) answers '
        'an old since with the routines frame that carries the Focus',
        () async {
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: Modality.sports,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final oldSince = stampOf(_routinesDownFrame(transport, fromLast: 2));

      clock.advance(const Duration(seconds: 7));
      final relaunched = WatchSyncRequestHandler(
        mirror: LiveSessionMirrorState(
          transport: transport,
          snapshot: watchSessionPlaceholder,
        ),
        transport: transport,
        repository: repository,
        settings: settings,
        foodLibrary: FoodLibraryState(repository),
        clock: clock.call,
      );

      expect(
        await relaunched.handle(
          WatchTransportRequest.routines,
          since: oldSince,
        ),
        isTrue,
        reason: 'S-12580 the new handler holds no stamp, so the old since is '
            'older than whatever it derives, and the frame travels',
      );
      final resent = _routinesDownFrame(transport);
      expect(
        routineOf(resent)['focusModality'],
        Modality.sports,
        reason: 'S-12580 the relaunched frame carries the Focus',
      );
      expect(
        stampOf(resent).isAfter(oldSince),
        isTrue,
      );
    });
  });
}
