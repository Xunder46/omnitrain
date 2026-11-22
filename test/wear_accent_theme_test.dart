// The widget tests for plan 286: the theme the Wear shell wears
// (`WearAppState._themeFor` in `lib/watch/app/wear_app.dart`), read off the
// shell the way a watch renders it.
//
// Scenario mapping (plan
// `docs/plans/2026-11-21-286-wear-accent-theming-plan/2026-11-21-286-wear-accent-theming-plan.md`,
// section "Scenarios"):
//   S-28610 the fresh shell wears the phone's default accent → `S-28610 ...`
//   S-28611 a delivered accent becomes the shell's → `S-28611 ...`
//   S-28612 a newer copy replaces it, a copy without accent restores the
//           default → `S-28612 ...`
//   S-28613 an accent too dark is refused; a usable grey wears with white
//           labels → `S-28613 ...`
//   S-28614 an older copy does not replace the newer one → `S-28614 ...`
//   S-28615 a shell without preferences stays on the default → `S-28615 ...`
//   S-28616 a store that holds a copy dresses the new shell → `S-28616 ...`
//   S-28617 the theme is cached across the 1 s ticks and rebuilt on a new
//           accent → `S-28617 ...`
//
// The unit half (the accent class) is `test/watch_accent_test.dart`.
//
// The harness is copied from `test/wear_phone_settings_test.dart` (a test file
// is never imported); the accent fields are what plan 286 adds. Never
// `pumpAndSettle` and never a real `Future.delayed` inside `testWidgets` (the
// shell owns a 1 s periodic ticker; FakeAsync). Every wait is an explicit
// `pump`.
//
// One deliberate extra wait: `MaterialApp` animates a theme change over 200 ms
// (`AnimatedTheme`), and a zero-duration `pump()` never advances the FakeAsync
// clock, so a theme read straight after a delivered frame still shows the
// colour being animated away from. `_deliver` and `_open` therefore end with
// one time-advancing pump so every read below is of the settled theme.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_phone_preferences.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const String _t1 = '2026-09-25T09:00:00Z';
const String _t2 = '2026-09-25T10:00:00Z';
const String _t3 = '2026-09-25T11:00:00Z';

/// A `preferences_down` envelope, the helper from
/// `test/watch_phone_preferences_test.dart`: protocolVersion 1, a phone
/// origin, and a payload whose optional keys are present only when given.
Map<String, Object?> _envelope({
  String messageId = 'msg-prefs',
  Object? generatedAt,
  String? accentColorHex,
}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'preferences_down',
  'origin': 'phone',
  'sentAt': '2026-09-25T09:00:00Z',
  'payload': {
    'effortRatingPrompt': false,
    'restPingSeconds': 0,
    'generatedAt': ?generatedAt,
    'accentColorHex': ?accentColorHex,
  },
};

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

final List<MethodCall> _calls = <MethodCall>[];

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// The shell's graph, built the way `wear_main.dart` builds it but over an
/// in-memory store and a fake radio. When no owner is handed in, one fresh
/// `WatchPhonePreferences` is built over the store and given to BOTH the
/// orchestrator and the shell, exactly as `wear_main.dart` does; with
/// `withPreferences: false` the shell is built with `preferences: null` while
/// the orchestrator keeps its own owner.
class _Harness {
  factory _Harness({
    InMemoryWatchSessionStore? store,
    WatchPhonePreferences? preferences,
    bool withPreferences = true,
  }) {
    final effectiveStore = store ?? InMemoryWatchSessionStore();
    return _Harness._(
      effectiveStore,
      preferences ?? WatchPhonePreferences(store: effectiveStore),
      withPreferences,
    );
  }

  _Harness._(this.store, this.preferences, this.withPreferences)
    : transport = WearWatchTransport(link: WatchLink()) {
    engine = WatchSessionEngine(store, onEmit: transport.send);
    paths = WatchSessionStartPaths(engine: engine, store: store);
    nutrition = WatchNutritionState(engine: engine, store: store);
    orchestrator = WatchSyncOrchestrator(
      transport: transport,
      paths: paths,
      engine: engine,
      nutrition: nutrition,
      preferences: preferences,
    );
  }

  final InMemoryWatchSessionStore store;
  final WearWatchTransport transport;
  final WatchPhonePreferences preferences;
  final bool withPreferences;
  late final WatchSessionEngine engine;
  late final WatchSessionStartPaths paths;
  late final WatchNutritionState nutrition;
  late final WatchSyncOrchestrator orchestrator;

  Widget app() => WearApp(
    engine: engine,
    paths: paths,
    nutrition: nutrition,
    orchestrator: orchestrator,
    transport: transport,
    preferences: withPreferences ? preferences : null,
  );
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness.app());
  // Restore, the status read and the first frame: all microtasks, no clock.
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
  // The launch may have moved the theme (a store that already holds an accent
  // copy); settle the theme animation before any read.
  await tester.pump(const Duration(milliseconds: 250));
}

/// A running `set` session with the load-capable slot, as the phone writes it.
Future<void> _kindSession(
  _Harness harness,
  String kind,
  List<String> capabilities,
) async {
  await harness.engine.createSession(
    modality: 'resistance_lifting',
    exercises: <Map<String, Object?>>[
      <String, Object?>{
        'sessionExerciseId': 'sx-$kind',
        'exerciseId': 'ex-$kind',
        'name': 'Slot $kind',
        'capabilities': capabilities,
        'effortKind': kind,
      },
    ],
  );
}

void _setView(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

Color? _buttonColor(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(
        of: find.byType(FilledButton).first,
        matching: find.byType(Material),
      ),
    )
    .color;

Future<void> _deliver(
  WidgetTester tester,
  _Harness h,
  Map<String, Object?> frame,
) async {
  await h.transport.deliver(frame);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  setUp(() {
    _calls.clear();
    _messenger.setMockMethodCallHandler(_methods, (call) async {
      _calls.add(call);
      return switch (call.method) {
        'status' => <String, Object?>{
          'supported': true,
          'paired': true,
          'appInstalled': true,
          'activated': true,
          'reachable': true,
        },
        _ => null,
      };
    });
    _messenger.setMockStreamHandler(
      _events,
      // The shell listens for arrivals; here the frames are handed to the
      // orchestrator directly.
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

  testWidgets('S-28610 the fresh shell wears the phone\'s default accent', (
    tester,
  ) async {
    _setView(tester, 227, 227);
    final harness = _Harness();
    await _open(tester, harness);

    expect(
      _scheme(tester).primary,
      const Color(0xFF2DE2E6),
      reason: 'S-28610 before a sync the wrist wears the phone\'s default '
          'theme accent, not Material\'s default lilac',
    );
    expect(
      _scheme(tester).onPrimary,
      Colors.black,
      reason: 'S-28610 cyan takes dark labels',
    );

    // The start surface builds no FilledButton until the phone has synced its
    // routines (S-28610 finding), so the button check runs on the first one
    // that exists once a session is running, as the brief asks.
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);
    expect(
      _buttonColor(tester),
      const Color(0xFF2DE2E6),
      reason: 'S-28610 the shell\'s buttons wear the default accent',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28611 a delivered accent becomes the shell\'s', (tester) async {
    _setView(tester, 227, 227);
    final harness = _Harness();
    // The start surface builds no FilledButton until a sync brings routines,
    // so the button check runs once a session is running (S-28610 finding).
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    await _deliver(
      tester,
      harness,
      _envelope(
        messageId: 'm1',
        generatedAt: _t1,
        accentColorHex: '#FF7B45',
      ),
    );

    expect(
      _scheme(tester).primary,
      const Color(0xFFFF7B45),
      reason: 'S-28611 the copy the phone sent dresses the shell',
    );
    expect(
      _scheme(tester).onPrimary,
      Colors.black,
      reason: 'S-28611 #FF7B45 takes dark labels',
    );
    expect(
      _buttonColor(tester),
      const Color(0xFFFF7B45),
      reason: 'S-28611 the shell repaints after the frame',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'S-28612 a newer copy replaces it, a copy without accent restores the default',
    (tester) async {
      _setView(tester, 227, 227);
      final harness = _Harness();
      await _open(tester, harness);

      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm1',
          generatedAt: _t1,
          accentColorHex: '#FF7B45',
        ),
      );
      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm2',
          generatedAt: _t2,
          accentColorHex: '#A478FF',
        ),
      );
      expect(
        _scheme(tester).primary,
        const Color(0xFFA478FF),
        reason: 'S-28612 the newer copy wins',
      );

      await _deliver(
        tester,
        harness,
        _envelope(messageId: 'm3', generatedAt: _t3),
      );
      expect(
        _scheme(tester).primary,
        const Color(0xFF2DE2E6),
        reason: 'S-28612 a copy with no accent is not "keep the old one": the '
            'wrist restores its default look',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-28613 an accent too dark is refused; a usable grey wears with white labels',
    (tester) async {
      _setView(tester, 227, 227);
      final harness = _Harness();
      await _open(tester, harness);

      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm1',
          generatedAt: _t1,
          accentColorHex: '#202020',
        ),
      );
      expect(
        _scheme(tester).primary,
        const Color(0xFF2DE2E6),
        reason: 'S-28613 #202020 is too dark to read on a black screen and is '
            'refused; the wrist keeps its default',
      );

      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm2',
          generatedAt: _t2,
          accentColorHex: '#757575',
        ),
      );
      expect(
        _scheme(tester).primary,
        const Color(0xFF757575),
        reason: 'S-28613 #757575 clears the floor and is worn',
      );
      expect(
        _scheme(tester).onPrimary,
        Colors.white,
        reason: 'S-28613 #757575 reads better with white labels',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-28614 an older copy does not replace the newer one',
    (tester) async {
      _setView(tester, 227, 227);
      final harness = _Harness();
      await _open(tester, harness);

      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm-new',
          generatedAt: _t2,
          accentColorHex: '#FF7B45',
        ),
      );
      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm-old',
          generatedAt: _t1,
          accentColorHex: '#24B85A',
        ),
      );
      expect(
        _scheme(tester).primary,
        const Color(0xFFFF7B45),
        reason: 'S-28614 the theme reads the copy that applies, not the last '
            'frame that arrived',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-28615 a shell without preferences stays on the default',
    (tester) async {
      _setView(tester, 227, 227);
      final harness = _Harness(withPreferences: false);
      await _open(tester, harness);

      expect(
        _scheme(tester).primary,
        const Color(0xFF2DE2E6),
        reason: 'S-28615 a shell that reads no owner wears the default accent',
      );

      // The frame still reaches the orchestrator's own owner; the shell, not
      // being wired to it, does not follow.
      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm1',
          generatedAt: _t1,
          accentColorHex: '#FF7B45',
        ),
      );
      expect(
        _scheme(tester).primary,
        const Color(0xFF2DE2E6),
        reason: 'S-28615 the shell\'s theme is built from its own preferences, '
            'which it does not have',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-28616 a store that holds a copy dresses the new shell',
    (tester) async {
      _setView(tester, 227, 227);
      final store = InMemoryWatchSessionStore();
      final stored = WatchPhonePreferences(store: store);
      expect(
        await stored.applyPreferencesDown(
          _envelope(
            messageId: 'm-stored',
            generatedAt: _t1,
            accentColorHex: '#E8B420',
          ),
        ),
        isTrue,
      );

      final harness = _Harness(store: store);
      await _open(tester, harness);
      expect(
        _scheme(tester).primary,
        const Color(0xFFE8B420),
        reason: 'S-28616 the restored copy is already on the first settled '
            'frame: `_boot` repaints after the restore',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-28617 the theme is cached across the 1 s ticks and rebuilt on a new accent',
    (tester) async {
      _setView(tester, 227, 227);
      final harness = _Harness();
      await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
      await _open(tester, harness);

      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm1',
          generatedAt: _t1,
          accentColorHex: '#FF7B45',
        ),
      );
      final first = Theme.of(tester.element(find.byType(Scaffold).first));
      final firstAppTheme =
          tester.widget<MaterialApp>(find.byType(MaterialApp).first).theme;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp).first).theme,
          same(firstAppTheme),
          reason: 'S-28617 the once-a-second rebuild hands MaterialApp the '
              'same cached ThemeData, not a freshly built one',
        );
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)),
          first,
          reason: 'S-28617 the worn theme does not change while the accent has '
              'not changed (the framework lerps a deep-equal copy each build; '
              'the shell\'s cache is asserted on the MaterialApp above)',
        );
      }

      await _deliver(
        tester,
        harness,
        _envelope(
          messageId: 'm2',
          generatedAt: _t2,
          accentColorHex: '#A478FF',
        ),
      );
      expect(
        _scheme(tester).primary,
        const Color(0xFFA478FF),
        reason: 'S-28617 a new accent does reach the shell',
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp).first).theme,
        isNot(same(firstAppTheme)),
        reason: 'S-28617 a new accent is a new ThemeData from the cache, not '
            'the old instance',
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)),
        isNot(first),
        reason: 'S-28617 the worn theme follows the new accent',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
