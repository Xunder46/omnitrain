import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TimerAlertService {
  static Future<void> fireTimerExpiredAlert() async {
    if (!kIsWeb) {
      await HapticFeedback.heavyImpact();
    }
    await SystemSound.play(SystemSoundType.alert);
  }
}
