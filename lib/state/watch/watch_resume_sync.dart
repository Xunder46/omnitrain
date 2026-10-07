/// The phone asks the wrist for its session once per resume (D-96).
///
/// Plan: `docs/plans/2026-10-06-17b-watch-auto-sync-pr2-plan/2026-10-06-17b-watch-auto-sync-pr2-plan.md`
/// (D-96). A wrist that was out of reach while the phone was in the background
/// may hold work the phone never saw; `resumed` is the moment the radio is
/// usable again, and the graph's `sync` is the one call that converges the pair
/// (the mirror hands the wrist the phone's own state and then asks for the
/// wrist's).
///
/// Nothing here decides whether a sync is needed, holds a session or reads
/// storage: it is one callback per lifecycle transition, no timer and no
/// polling, so a phone with no wrist is not observed at all — the app mounts
/// this widget only when there is a graph (`lib/app.dart`).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Runs [onResume] once for every `resumed` transition, and nothing for any
/// other app lifecycle state.
class WatchResumeSync extends StatefulWidget {
  const WatchResumeSync({
    super.key,
    required this.onResume,
    required this.child,
  });

  /// The graph's catch-up call. Called once per `resumed` transition, never
  /// awaited — a slow radio must not hold the observer.
  final Future<void> Function() onResume;

  final Widget child;

  @override
  State<WatchResumeSync> createState() => _WatchResumeSyncState();
}

class _WatchResumeSyncState extends State<WatchResumeSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.onResume());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
