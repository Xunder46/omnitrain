import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/services/screen_awake_port.dart';

/// Keeps the phone awake while a live session screen is open, the app is in
/// the foreground and a work timer is running or paused (plan 120 D-19501).
class SessionScreenAwake with WidgetsBindingObserver {
  SessionScreenAwake({
    required ScreenAwakePort port,
    required Listenable source,
    required bool Function() hasWorkTimer,
  }) : _port = port,
       _source = source,
       _hasWorkTimer = hasWorkTimer {
    _send(false); // clears a stale hold (D-19507)
  }

  final ScreenAwakePort _port;
  final Listenable _source;
  final bool Function() _hasWorkTimer;

  int _attached = 0;
  bool _foreground = true;
  bool _sent = false;

  int get attachedCount => _attached;
  bool get isKeepingAwake => _sent;

  /// A live session screen appeared. Never notifies listeners.
  void attach() {
    _attached++;
    if (_attached == 1) {
      final binding = WidgetsBinding.instance;
      _foreground = _isForeground(binding.lifecycleState);
      binding.addObserver(this);
      _source.addListener(_evaluate);
    }
    _evaluate();
  }

  /// A live session screen went away. Extra calls are no-ops.
  void detach() {
    if (_attached == 0) return;
    _attached--;
    if (_attached == 0) {
      WidgetsBinding.instance.removeObserver(this);
      _source.removeListener(_evaluate);
      _foreground = true;
    }
    _evaluate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    _evaluate();
  }

  static bool _isForeground(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  void _evaluate() {
    try {
      final want = _attached > 0 && _foreground && _hasWorkTimer();
      if (want == _sent) return;
      _sent = want;
      _send(want);
    } catch (error) {
      debugPrint('Screen awake evaluation failed: $error');
    }
  }

  void _send(bool on) {
    try {
      unawaited(
        _port.setKeepAwake(on).catchError((Object error) {
          debugPrint('Screen awake port failed: $error');
        }),
      );
    } catch (error) {
      debugPrint('Screen awake port failed: $error');
    }
  }
}
