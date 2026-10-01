/// Debug entry point for the watch session engine QA surface.
///
/// ```sh
/// flutter run -t lib/watch/debug/watch_session_debug_main.dart \
///   --dart-define=WATCH_SESSION_DEBUG=true
/// ```
///
/// Persistence is the real `HiveWatchSessionStore`, in a box prefix of its own
/// so a QA session can never collide with the app's own data.
library;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../session/hive_watch_session_store.dart';
import 'watch_session_debug_surface.dart';

/// Hive sub-directory for the debug store. Separate from the app's own.
const String _boxPrefix = 'omnitrain_watch_debug';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter(_boxPrefix);

  runApp(
    MaterialApp(
      title: 'Watch session debug',
      debugShowCheckedModeBanner: false,
      // Deliberately plain: this harness shows engine state, not theme work.
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: WatchSessionDebugSurface(
        store: HiveWatchSessionStore(name: _boxPrefix),
      ),
    ),
  );
}
