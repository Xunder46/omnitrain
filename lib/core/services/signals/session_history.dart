import 'signal.dart';

/// The start of every completed session, oldest history included (D-17803).
///
/// A session still in progress has no end and is not a session yet. The read
/// rides the service's cached history snapshot (plan 107, D-18102), so it costs
/// the screen no repository read of its own.
Future<List<DateTime>> completedSessionStarts(SignalContext context) =>
    context.progressService.completedSessionStarts(now: context.now);
