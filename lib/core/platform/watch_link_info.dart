/// What the platform says about the watch at one instant.
///
/// Plan: `docs/plans/2026-10-21-47a-watch-link-plugin-plan/2026-10-21-47a-watch-link-plugin-plan.md`
/// (D-5). A core value type: the plugin's own status object stops at the
/// channel, so the app depends on this and not on the package.
library;

class WatchLinkInfo {
  const WatchLinkInfo({
    required this.paired,
    required this.appInstalled,
    required this.reachable,
  });

  /// Whether a watch is paired with this phone at all.
  final bool paired;

  /// Whether the watch app is installed on that watch.
  final bool appInstalled;

  /// Whether the watch can be reached right now.
  final bool reachable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchLinkInfo &&
          other.paired == paired &&
          other.appInstalled == appInstalled &&
          other.reachable == reachable;

  @override
  int get hashCode => Object.hash(paired, appInstalled, reachable);

  @override
  String toString() =>
      'WatchLinkInfo(paired: $paired, appInstalled: $appInstalled, '
      'reachable: $reachable)';
}
