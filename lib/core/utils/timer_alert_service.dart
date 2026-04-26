import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class TimerAlertService {
  static const List<String> _soundIds = [
    'boxing_bell',
    'digital_buzzer',
    'soft_chime',
    'double_tap',
    'signal_tone',
  ];

  final Map<String, AudioPlayer> _players = {};
  final bool? _isWebOverride;

  TimerAlertService() : _isWebOverride = null;

  @visibleForTesting
  TimerAlertService.forTesting({required bool isWeb}) : _isWebOverride = isWeb;

  bool get _isWeb => _isWebOverride ?? kIsWeb;

  Future<void> initialize() async {
    if (_isWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.duckOthers,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.notificationEvent,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidWillPauseWhenDucked: false,
        ),
      );
      for (final soundId in _soundIds) {
        final player = AudioPlayer();
        try {
          await player.setAsset('assets/sounds/$soundId.mp3');
        } catch (e) {
          debugPrint('[TimerAlertService] Could not load $soundId: $e');
        }
        _players[soundId] = player;
      }
    } catch (e) {
      debugPrint('[TimerAlertService] initialize() failed: $e');
    }
  }

  Future<void> fireEffortTimerAlert(String soundId) async {
    await _playSound(
      soundId,
      fallback: 'boxing_bell',
      alertType: 'effort_timer',
    );
    if (!_isWeb) await HapticFeedback.heavyImpact();
  }

  Future<void> fireRestPingAlert(String soundId) async {
    await _playSound(
      soundId,
      fallback: 'soft_chime',
      alertType: 'rest_ping',
    );
    if (!_isWeb) await HapticFeedback.lightImpact();
  }

  Future<void> playPreview(String soundId) async {
    await _playSound(
      soundId,
      fallback: 'boxing_bell',
      alertType: 'sound_preview',
    );
  }

  Future<void> _playSound(
    String soundId, {
    required String fallback,
    required String alertType,
  }) async {
    if (_isWeb) {
      debugPrint(
        '[TimerAlertService][web] alert=$alertType soundId=$soundId fallback=$fallback',
      );
      return;
    }
    final player = _players[soundId] ?? _players[fallback];
    if (player == null) return;
    try {
      await player.seek(Duration.zero);
      unawaited(player.play());
    } catch (e) {
      debugPrint('[TimerAlertService] playback failed for $soundId: $e');
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
