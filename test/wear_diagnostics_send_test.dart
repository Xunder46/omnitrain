// The Wear wrist sends its diagnostics log to the phone (plan 304).
//
// Plan: `docs/plans/2026-11-22-304-wear-diagnostics-send-plan/2026-11-22-304-wear-diagnostics-send-plan.md`
//   S-30401 the link call: arguments, the error codes, a missing method
//   S-30402 the log's raw text
//   S-30403 the transport's outcome mapping and its one log line
//   S-30404 the outcome sentences
//   S-30405 the screen: button, outcome, disabled while sending, fits small
//   S-30406 the shell hands the screen the log's raw text
//   S-30407 the plugin's send, as source guards (no Kotlin harness exists)
//   S-30408 the plugin's receive, as source guards
//
// Mock-first, plain `test()` where no widget is needed. The behaviour on a
// real data layer is owner check 21.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/diagnostics/watch_diagnostics_screen.dart';
import 'package:omnitrain/watch/diagnostics/watch_diagnostics_send_outcome.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void _answer(Future<Object?> Function(MethodCall call) handler) =>
    _messenger.setMockMethodCallHandler(_methods, handler);

DiagnosticsLog _log() => DiagnosticsLog(
  storage: InMemoryDiagnosticsStorage(),
  clock: () => DateTime.utc(2026, 11, 22, 9),
);

final String _source = File(
  'packages/omnitrain_watch_link/android/src/main/kotlin/dev/sasha/'
  'omnitrain/watch_link/OmniTrainWatchLinkPlugin.kt',
).readAsStringSync().replaceAll('\r\n', '\n');

/// The text of the member that starts with [signature], up to the next member
/// or comment block at the same indentation.
String _body(String signature) {
  final start = _source.indexOf(signature);
  expect(start, greaterThan(0), reason: '$signature is missing');
  final rest = _source.substring(start + signature.length);
  final next = RegExp(
    r'\n    (/\*\*|// MARK|private fun |override fun )',
  ).firstMatch(rest);
  return _source.substring(
    start,
    next == null ? _source.length : start + signature.length + next.start,
  );
}

Widget _screen(
  DiagnosticsLog log,
  Future<WatchDiagnosticsSendOutcome> Function()? onSend,
) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: WatchDiagnosticsScreen(log: log, onSend: onSend),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _answer((_) async => null);
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, events) {},
        onCancel: (arguments) {},
      ),
    );
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  group('S-30401 the link call', () {
    test('sends the text under one key', () async {
      MethodCall? seen;
      _answer((call) async {
        seen = call;
        return null;
      });

      await WatchLink().sendDiagnostics('line one\nline two\n');

      expect(seen?.method, 'sendDiagnostics');
      expect(seen?.arguments, <String, Object?>{
        'text': 'line one\nline two\n',
      });
    });

    test('a platform error keeps its code', () async {
      _answer((_) async => throw PlatformException(code: 'phone_app_missing'));

      await expectLater(
        WatchLink().sendDiagnostics('x'),
        throwsA(
          isA<WatchLinkException>().having(
            (e) => e.code,
            'code',
            'phone_app_missing',
          ),
        ),
      );
    });

    test('a plugin without the call (iOS) is not_supported', () async {
      _answer((_) async => throw MissingPluginException());

      await expectLater(
        WatchLink().sendDiagnostics('x'),
        throwsA(
          isA<WatchLinkException>().having(
            (e) => e.code,
            'code',
            'not_supported',
          ),
        ),
      );
    });
  });

  group('S-30402 the log\'s raw text', () {
    test('is the stored lines exactly, and empty with none', () {
      final storage = InMemoryDiagnosticsStorage();
      final log = DiagnosticsLog(
        storage: storage,
        clock: () => DateTime.utc(2026, 11, 22, 9),
      );
      expect(log.rawText(), '');

      log
        ..note('launch', detail: 'previous=none')
        ..note('scene', detail: 'active')
        ..note('frame_sent', session: 's1', detail: 'observations_up live');

      expect(log.rawText(), storage.read());
      expect('\n'.allMatches(log.rawText()), hasLength(3));
      expect(log.rawText(), contains('"kind":"frame_sent"'));
    });
  });

  group('S-30403 the transport\'s outcomes', () {
    Future<(WatchDiagnosticsSendOutcome, DiagnosticsLog, List<MethodCall>)> run(
      String text,
      Future<Object?> Function(MethodCall call) answer, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final calls = <MethodCall>[];
      _answer((call) {
        calls.add(call);
        return answer(call);
      });
      final log = _log();
      final transport = WearWatchTransport(
        link: WatchLink(),
        diagnostics: log,
        diagnosticsSendTimeout: timeout,
      );
      addTearDown(transport.close);
      final outcome = await transport.sendDiagnostics(text);
      return (
        outcome,
        log,
        calls.where((c) => c.method == 'sendDiagnostics').toList(),
      );
    }

    test('empty text sends nothing and records nothing', () async {
      final (outcome, log, calls) = await run('', (_) async => null);

      expect(outcome, WatchDiagnosticsSendOutcome.nothingToSend);
      expect(calls, isEmpty);
      expect(log.events(), isEmpty);
    });

    test('success is sent, with one line naming the outcome only', () async {
      final (outcome, log, calls) = await run('SECRET-TEXT', (_) async => null);

      expect(outcome, WatchDiagnosticsSendOutcome.sent);
      expect(calls, hasLength(1));
      expect(log.events().map((e) => '${e.kind} ${e.detail}'), [
        'diagnostics_send sent',
      ]);
      expect(log.rawText(), isNot(contains('SECRET-TEXT')));
    });

    for (final entry in <String, WatchDiagnosticsSendOutcome>{
      'not_supported': WatchDiagnosticsSendOutcome.notReady,
      'phone_app_missing': WatchDiagnosticsSendOutcome.phoneAppMissing,
      'send_failed': WatchDiagnosticsSendOutcome.failed,
      'something_else': WatchDiagnosticsSendOutcome.failed,
    }.entries) {
      test('${entry.key} is ${entry.value.name}', () async {
        final (outcome, log, _) = await run(
          'x',
          (call) async => call.method == 'sendDiagnostics'
              ? throw PlatformException(code: entry.key)
              : null,
        );

        expect(outcome, entry.value);
        expect(log.events().single.detail, entry.value.name);
      });
    }

    test('a missing method is notReady (an iOS plugin)', () async {
      final (outcome, _, _) = await run(
        'x',
        (call) async => call.method == 'sendDiagnostics'
            ? throw MissingPluginException()
            : null,
      );

      expect(outcome, WatchDiagnosticsSendOutcome.notReady);
    });

    test('a call that never answers is failed after the timeout', () async {
      final never = Completer<Object?>();
      final (outcome, log, _) = await run(
        'x',
        (call) => call.method == 'sendDiagnostics'
            ? never.future
            : Future<Object?>.value(null),
        timeout: const Duration(milliseconds: 20),
      );

      expect(outcome, WatchDiagnosticsSendOutcome.failed);
      expect(log.events().single.detail, 'failed');
    });
  });

  test('S-30404 the outcome sentences', () {
    expect(
      {for (final o in WatchDiagnosticsSendOutcome.values) o.name: o.message},
      {
        'sent': 'Sent. The phone has it when it next wakes.',
        'phoneAppMissing': 'Install the OmniTrain app on the phone.',
        'notReady': 'Phone link not ready.',
        'failed': 'Could not send.',
        'nothingToSend': 'Nothing to send.',
      },
    );
  });

  group('S-30405 the screen', () {
    testWidgets('without onSend there is no button', (tester) async {
      await tester.pumpWidget(_screen(_log()..noteLaunch(), null));

      expect(find.text(WatchDiagnosticsScreen.sendLabel), findsNothing);
    });

    testWidgets('a tap sends once, disables meanwhile, then says the outcome', (
      tester,
    ) async {
      final pending = Completer<WatchDiagnosticsSendOutcome>();
      var calls = 0;
      await tester.pumpWidget(
        _screen(_log()..noteLaunch(), () {
          calls++;
          return pending.future;
        }),
      );
      await tester.scrollUntilVisible(
        find.text(WatchDiagnosticsScreen.sendLabel),
        100,
        scrollable: find.byType(Scrollable),
      );

      await tester.tap(find.text(WatchDiagnosticsScreen.sendLabel));
      await tester.pump();
      expect(calls, 1);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull, reason: 'disabled while sending');
      await tester.tap(
        find.text(WatchDiagnosticsScreen.sendLabel),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(calls, 1, reason: 'a second tap does not send again');

      pending.complete(WatchDiagnosticsSendOutcome.sent);
      await tester.pump();

      expect(
        find.text('Sent. The phone has it when it next wakes.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
        reason: 'enabled again, so a second send is possible',
      );
    });

    for (final outcome in WatchDiagnosticsSendOutcome.values) {
      testWidgets('shows "${outcome.message}" for ${outcome.name}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _screen(_log()..noteLaunch(), () async => outcome),
        );
        await tester.scrollUntilVisible(
          find.text(WatchDiagnosticsScreen.sendLabel),
          100,
          scrollable: find.byType(Scrollable),
        );
        await tester.tap(find.text(WatchDiagnosticsScreen.sendLabel));
        await tester.pump();
        await tester.pump();

        expect(find.text(outcome.message), findsOneWidget);
      });
    }

    testWidgets('a send that throws reads as could not send', (tester) async {
      await tester.pumpWidget(
        _screen(_log()..noteLaunch(), () async => throw StateError('x')),
      );
      await tester.scrollUntilVisible(
        find.text(WatchDiagnosticsScreen.sendLabel),
        100,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text(WatchDiagnosticsScreen.sendLabel));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not send.'), findsOneWidget);
    });

    for (final side in const [192.0, 227.0]) {
      testWidgets('fits ${side}dp with 60 lines and the button reachable', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(side, side);
        addTearDown(tester.view.reset);
        final log = _log()..noteLaunch();
        for (var i = 0; i < 60; i++) {
          log.note('frame_received', session: 's-$i', detail: 'frame $i');
        }
        await tester.pumpWidget(
          _screen(log, () async => WatchDiagnosticsSendOutcome.sent),
        );
        // The end of the list: the button and the outcome sit above the
        // bottom edge, not merely partly visible.
        await tester.fling(
          find.byType(ListView),
          const Offset(0, -20000),
          5000,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(WatchDiagnosticsScreen.sendLabel));
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'no overflow');
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.height, 40);
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(side));
      });
    }
  });

  testWidgets('S-30406 the shell hands the screen the log\'s raw text', (
    tester,
  ) async {
    final sent = <Object?>[];
    _answer((call) async {
      if (call.method == 'status') {
        return <String, Object?>{
          'supported': true,
          'paired': true,
          'appInstalled': true,
          'activated': true,
          'reachable': false,
        };
      }
      if (call.method == 'sendDiagnostics') sent.add(call.arguments);
      return null;
    });
    final log = _log()..noteLaunch();
    final store = InMemoryWatchSessionStore();
    final transport = WearWatchTransport(link: WatchLink(), diagnostics: log);
    final engine = WatchSessionEngine(store, onEmit: transport.send);
    final paths = WatchSessionStartPaths(engine: engine, store: store);
    final nutrition = WatchNutritionState(engine: engine, store: store);
    final orchestrator = WatchSyncOrchestrator(
      transport: transport,
      paths: paths,
      engine: engine,
      nutrition: nutrition,
    );
    await tester.pumpWidget(
      WearApp(
        engine: engine,
        paths: paths,
        nutrition: nutrition,
        orchestrator: orchestrator,
        transport: transport,
        diagnostics: log,
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await tester.tap(find.text(WatchStartScreen.diagnosticsLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final textAtTap = log.rawText();

    await tester.scrollUntilVisible(
      find.text(WatchDiagnosticsScreen.sendLabel),
      100,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text(WatchDiagnosticsScreen.sendLabel));
    await tester.pump();
    await tester.pump();

    expect(sent, hasLength(1));
    expect(sent.single, <String, Object?>{'text': textAtTap});
    expect(textAtTap, contains('"kind":"launch"'));
    expect(
      find.text('Sent. The phone has it when it next wakes.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    transport.close();
  });

  group('S-30407 the plugin sends (source guards)', () {
    test('the method is registered and the path and keys are fixed', () {
      expect(
        _body('override fun onMethodCall('),
        contains(
          '"sendDiagnostics" -> sendDiagnostics(call.arguments, result)',
        ),
      );
      expect(
        _source,
        contains(
          'private const val DIAGNOSTICS_PATH = "/omnitrain/diagnostics/watch-log"',
        ),
      );
      expect(_source, contains('private const val KEY_LOG = "log"'));
    });

    test('a phone or a missing peer is refused with the plain codes', () {
      final body = _body('private fun sendDiagnostics(');

      expect(
        body,
        contains(
          'if (!supported || !isWatch) return result.error(failure("not_supported"))',
        ),
      );
      expect(
        body,
        contains(
          'if (peerNodeId == null) return result.error(failure("phone_app_missing"))',
        ),
      );
      expect(body, contains('failure("send_failed"'));
    });

    test('the put carries the text as an asset, the role and a stamp', () {
      final body = _body('private fun sendDiagnostics(');

      expect(body, contains('PutDataMapRequest.create(DIAGNOSTICS_PATH)'));
      expect(
        body,
        contains(
          'putAsset(KEY_LOG, Asset.createFromBytes(text.toByteArray(Charsets.UTF_8)))',
        ),
      );
      expect(body, contains('putString(KEY_ROLE, ownRole())'));
      expect(
        body,
        contains('putLong(KEY_STAMP_MS, System.currentTimeMillis())'),
      );
      expect(
        body,
        contains('client.putDataItem(request.asPutDataRequest().setUrgent())'),
      );
      final put = body.indexOf('client.putDataItem');
      expect(body.indexOf('result.success(null)'), greaterThan(put));
    });

    test('it never goes through the frame queue', () {
      final body = _body('private fun sendDiagnostics(');

      expect(body, isNot(contains('QUEUE_PREFIX')));
      expect(body, isNot(contains('encodeFrame')));
      expect(body, isNot(contains('sendMessage')));
    });
  });

  group('S-30408 the plugin receives (source guards)', () {
    test('the shared rule hands the path to the diagnostics reader first', () {
      final body = _body('private fun takeQueuedItem(');

      final diagnostics = body.indexOf(
        'if (path == DIAGNOSTICS_PATH) return takeDiagnostics(item)',
      );
      final frames = body.indexOf('if (!path.startsWith(QUEUE_PREFIX)) return');
      expect(diagnostics, greaterThan(0));
      expect(frames, greaterThan(diagnostics));
    });

    test('its own item is ignored; the asset is read off the main thread', () {
      final body = _body('private fun takeDiagnostics(');

      expect(
        body,
        contains('if (map.getString(KEY_ROLE) == ownRole()) return'),
      );
      expect(body, contains('val asset = map.getAsset(KEY_LOG) ?: return'));
      expect(
        body,
        contains('client.getFdForAsset(asset).addOnSuccessListener(io)'),
      );
      expect(
        _source,
        contains('private val io = Executors.newSingleThreadExecutor()'),
      );
    });

    test('the file lands where the Dart reader opens it, via a temp name', () {
      final body = _body('private fun takeDiagnostics(');

      expect(
        _source,
        contains('private const val RECEIVED_DIRECTORY = "watch-diagnostics"'),
      );
      expect(
        _source,
        contains('private const val RECEIVED_FILE = "watch-received.jsonl"'),
      );
      expect(body, contains('File(it, RECEIVED_DIRECTORY)'));
      final part = body.indexOf('File(directory, "\$RECEIVED_FILE.part")');
      final copy = body.indexOf('input.copyTo(output)');
      final rename = body.indexOf(
        'part.renameTo(File(directory, RECEIVED_FILE))',
      );
      expect(part, greaterThan(0));
      expect(copy, greaterThan(part));
      expect(rename, greaterThan(copy));
    });

    test(
      'the descriptor is released; the item goes only after a good write',
      () {
        final body = _body('private fun takeDiagnostics(');

        expect(body, contains('response.release()'));
        expect(body, contains('catch (_: Exception) {\n                false'));
        expect(
          body,
          contains(
            'if (written) main.post { dataClient?.deleteDataItems(uri) }',
          ),
        );
        expect(body, isNot(contains('emit(')));
      },
    );

    test('the Dart reader still opens the same directory and file', () {
      final dart = File(
        'lib/core/services/diagnostics_storage_default_io.dart',
      ).readAsStringSync();

      expect(
        dart,
        contains(
          "p.join(base.path, 'watch-diagnostics', 'watch-received.jsonl')",
        ),
      );
    });
  });
}
