import 'signal.dart';

/// The start of every completed session, oldest history included (D-17803).
///
/// A session still in progress has no end and is not a session yet.
Future<List<DateTime>> completedSessionStarts(SignalContext context) async {
  final sessions = await context.repository.getSessionsByDateRange(
    0,
    context.now.millisecondsSinceEpoch,
  );
  return [
    for (final session in sessions)
      if (session.endedAtMs != null)
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
  ];
}
