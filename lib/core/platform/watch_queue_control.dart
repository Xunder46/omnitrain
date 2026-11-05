/// What the phone's link can do with transfers the OS still holds for the
/// watch, in core types.
///
/// Plan: `docs/plans/2026-10-23-67a-phone-queues-workout-messages-plan/2026-10-23-67a-phone-queues-workout-messages-plan.md`
/// (D-9). A core value type and interface: the plugin's own transfer objects
/// stop at the channel, so the app depends on this and not on the package.
library;

/// One transfer the OS still holds for the watch, read from the frame it carries.
class WatchQueuedTransfer {
  const WatchQueuedTransfer({
    required this.messageId,
    required this.type,
    this.sessionId,
    this.changeId,
  });

  final String messageId;
  final String type;
  final String? sessionId;
  final String? changeId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchQueuedTransfer &&
          other.messageId == messageId &&
          other.type == type &&
          other.sessionId == sessionId &&
          other.changeId == changeId;

  @override
  int get hashCode => Object.hash(messageId, type, sessionId, changeId);

  @override
  String toString() =>
      'WatchQueuedTransfer(messageId: $messageId, type: $type, '
      'sessionId: $sessionId, changeId: $changeId)';
}

/// What the phone's link can do with transfers it already handed the OS.
abstract interface class WatchQueueControl {
  Future<List<WatchQueuedTransfer>> outstandingTransfers();

  /// How many of [messageIds] were cancelled.
  Future<int> cancelTransfers(List<String> messageIds);
}
