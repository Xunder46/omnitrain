/// What happened when the wrist offered its diagnostics log to the phone
/// (plan 304, D-30405). The Dart twin of the Apple client's
/// `WatchDiagnosticsSendOutcome`, with one more case for an empty log.
enum WatchDiagnosticsSendOutcome {
  sent,
  phoneAppMissing,
  notReady,
  failed,
  nothingToSend;

  /// The words the Diagnostics screen shows.
  String get message => switch (this) {
    WatchDiagnosticsSendOutcome.sent =>
      'Sent. The phone has it when it next wakes.',
    WatchDiagnosticsSendOutcome.phoneAppMissing =>
      'Install the OmniTrain app on the phone.',
    WatchDiagnosticsSendOutcome.notReady => 'Phone link not ready.',
    WatchDiagnosticsSendOutcome.failed => 'Could not send.',
    WatchDiagnosticsSendOutcome.nothingToSend => 'Nothing to send.',
  };
}
