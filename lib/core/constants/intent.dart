/// Intent constants - session purpose classification
/// Used for filtering, summaries, and progress grouping

class Intent {
  static const String easyBase = 'easy_base';
  static const String intervalsSpeed = 'intervals_speed';
  static const String tempoThreshold = 'tempo_threshold';
  static const String strength = 'strength';
  static const String hypertrophy = 'hypertrophy';
  static const String power = 'power';
  static const String techniqueDrills = 'technique_drills';
  static const String sparringLive = 'sparring_live';
  static const String recovery = 'recovery';
  static const String testBenchmark = 'test_benchmark';

  static const List<String> all = [
    easyBase,
    intervalsSpeed,
    tempoThreshold,
    strength,
    hypertrophy,
    power,
    techniqueDrills,
    sparringLive,
    recovery,
    testBenchmark,
  ];

  static String getDisplayName(String intent) {
    switch (intent) {
      case easyBase:
        return 'Easy / Base';
      case intervalsSpeed:
        return 'Intervals / Speed';
      case tempoThreshold:
        return 'Tempo / Threshold';
      case strength:
        return 'Strength';
      case hypertrophy:
        return 'Hypertrophy';
      case power:
        return 'Power';
      case techniqueDrills:
        return 'Technique / Drills';
      case sparringLive:
        return 'Sparring / Live';
      case recovery:
        return 'Recovery';
      case testBenchmark:
        return 'Test / Benchmark';
      default:
        return intent;
    }
  }
}
