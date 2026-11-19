/// What the phone's WatchConnectivity session says about the pairing.
class WatchLinkStatus {
  const WatchLinkStatus({
    required this.supported,
    required this.paired,
    required this.appInstalled,
    required this.activated,
    required this.reachable,
  });

  final bool supported;
  final bool paired;
  final bool appInstalled;
  final bool activated;
  final bool reachable;

  factory WatchLinkStatus.fromMap(Map<Object?, Object?> map) => WatchLinkStatus(
        supported: map['supported'] == true,
        paired: map['paired'] == true,
        appInstalled: map['appInstalled'] == true,
        activated: map['activated'] == true,
        reachable: map['reachable'] == true,
      );
}

/// One thing the native link reported, in arrival order.
sealed class WatchLinkEvent {
  const WatchLinkEvent();
}

/// A frame the watch sent with `sendMessage`.
class WatchLinkMessage extends WatchLinkEvent {
  const WatchLinkMessage(this.frame);
  final Map<String, Object?> frame;
}

/// A frame the watch queued with `transferUserInfo`, delivered by the OS.
class WatchLinkUserInfo extends WatchLinkEvent {
  const WatchLinkUserInfo(this.frame);
  final Map<String, Object?> frame;
}

/// The watch became reachable or unreachable.
class WatchLinkReachability extends WatchLinkEvent {
  const WatchLinkReachability(this.reachable);
  final bool reachable;
}

/// The pairing or the session's activation changed.
class WatchLinkStateChanged extends WatchLinkEvent {
  const WatchLinkStateChanged(this.status);
  final WatchLinkStatus status;
}
