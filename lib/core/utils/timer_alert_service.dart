import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// How loud an alert may be relative to the phone's silent switch.
enum TimerAlertAudio {
  /// Heard even with the ringer off: the effort timer ending and the
  /// Settings sound preview (the user just tapped to hear it).
  alarm,

  /// Follows the silent switch: the rest ping is a nudge, not an alarm, so
  /// silent mode means no sound (the haptic tap still fires).
  nudge,
}

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
  final Future<void> Function(AudioSessionConfiguration)? _configureOverride;
  TimerAlertAudio? _activeAudio;

  TimerAlertService() : _isWebOverride = null, _configureOverride = null;

  @visibleForTesting
  TimerAlertService.forTesting({
    required bool isWeb,
    Future<void> Function(AudioSessionConfiguration)? configureSession,
  }) : _isWebOverride = isWeb,
       _configureOverride = configureSession;

  bool get _isWeb => _isWebOverride ?? kIsWeb;

  @visibleForTesting
  static AudioSessionConfiguration configurationFor(TimerAlertAudio audio) {
    switch (audio) {
      case TimerAlertAudio.alarm:
        return AudioSessionConfiguration(
          // Use playback (not ambient) so alerts are heard even when the
          // iOS ringer/mute switch is off. mixWithOthers + duckOthers means
          // background music ducks briefly rather than stopping.
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.duckOthers,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.notificationEvent,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidWillPauseWhenDucked: false,
        );
      case TimerAlertAudio.nudge:
        return AudioSessionConfiguration(
          // Ambient obeys the iOS silent switch and never ducks music. No
          // audibility-enforced flag on Android, so the notification volume
          // and silent/DND settings apply.
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.notificationEvent,
          ),
          androidWillPauseWhenDucked: false,
        );
    }
  }

  /// Switches the shared audio session to [audio]'s profile if it is not
  /// already active. Failures are logged; the alert then plays under
  /// whatever profile was last applied.
  Future<void> _useAudio(TimerAlertAudio audio) async {
    if (_activeAudio == audio) return;
    try {
      final config = configurationFor(audio);
      final override = _configureOverride;
      if (override != null) {
        await override(config);
      } else {
        await (await AudioSession.instance).configure(config);
      }
      _activeAudio = audio;
    } catch (e) {
      debugPrint('[TimerAlertService] could not apply $audio session: $e');
    }
  }

  Future<void> initialize() async {
    if (_isWeb) return;
    try {
      await _useAudio(TimerAlertAudio.alarm);
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
      audio: TimerAlertAudio.alarm,
    );
    if (!_isWeb) await HapticFeedback.heavyImpact();
  }

  Future<void> fireRestPingAlert(String soundId) async {
    await _playSound(
      soundId,
      fallback: 'soft_chime',
      alertType: 'rest_ping',
      audio: TimerAlertAudio.nudge,
    );
    if (!_isWeb) await HapticFeedback.lightImpact();
  }

  Future<void> playPreview(String soundId) async {
    await _playSound(
      soundId,
      fallback: 'boxing_bell',
      alertType: 'sound_preview',
      audio: TimerAlertAudio.alarm,
    );
  }

  Future<void> _playSound(
    String soundId, {
    required String fallback,
    required String alertType,
    required TimerAlertAudio audio,
  }) async {
    if (_isWeb) {
      debugPrint(
        '[TimerAlertService][web] alert=$alertType soundId=$soundId fallback=$fallback',
      );
      return;
    }
    await _useAudio(audio);
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
