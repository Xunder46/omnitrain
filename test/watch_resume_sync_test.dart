// The phone's resume trigger — the app asks the wrist for its session once per
// resume (17b Phase 3).
//
// Plan: `docs/plans/2026-10-06-17b-watch-auto-sync-pr2-plan/2026-10-06-17b-watch-auto-sync-pr2-plan.md`
// (D-96). Scenario mapping:
//   S-109 the phone catches up on resume, once  → `S-109 ...` (this file: the
//         observer; the graph's half is in watch_session_projection_test.dart)
//
// The observer is driven the way the framework drives it — every change goes
// through `WidgetsBinding.handleAppLifecycleStateChanged`, the call a real
// resume ends in — so what is measured is the shipped trigger, not a direct
// call to its method.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/state/watch/watch_resume_sync.dart';

void main() {
  group('S-109 the phone catches up on resume, once', () {
    testWidgets(
      'S-109 a resume asks for one sync, no other lifecycle state asks for any, '
      'and an unmounted observer asks for none',
      (tester) async {
        final calls = <String>[];
        await tester.pumpWidget(
          WatchResumeSync(
            onResume: () {
              calls.add('sync');
              return Future<void>.value();
            },
            child: const SizedBox.shrink(),
          ),
        );
        expect(
          calls,
          isEmpty,
          reason: 'S-109 mounting the observer is not a resume',
        );

        Future<void> go(AppLifecycleState state) async {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }

        // Down the lifecycle and back up it, in the framework's own order: the
        // radio is not usable again until the app is actually resumed, so a
        // sync while it is leaving or away asks the wrist for a frame it cannot
        // receive.
        await go(AppLifecycleState.inactive);
        await go(AppLifecycleState.hidden);
        await go(AppLifecycleState.paused);
        expect(
          calls,
          isEmpty,
          reason:
              'S-109 no transition away from the app asks for a sync, so the '
              'phone does not poll while it is in the background',
        );

        await go(AppLifecycleState.hidden);
        await go(AppLifecycleState.inactive);
        await go(AppLifecycleState.resumed);
        expect(
          calls,
          ['sync'],
          reason:
              'S-109 the first resume asks the wrist for its session exactly '
              'once — one call, no timer and no polling',
        );

        // A second resume, with a real transition between the two.
        await go(AppLifecycleState.inactive);
        await go(AppLifecycleState.resumed);
        expect(
          calls,
          ['sync', 'sync'],
          reason: 'S-109 one sync per resume, and none in between',
        );

        // Unmounted: the app disposes the observer with the shell, and a resume
        // after that must not keep asking for a session.
        await tester.pumpWidget(const SizedBox.shrink());
        await go(AppLifecycleState.inactive);
        await go(AppLifecycleState.resumed);
        expect(
          calls,
          ['sync', 'sync'],
          reason:
              'S-109 an unmounted observer is removed from the binding, so a '
              'later resume asks for nothing',
        );
      },
    );

    testWidgets(
      'S-109 every reported resume asks for exactly one sync, and no other '
      'lifecycle state asks for any',
      (tester) async {
        final calls = <String>[];
        await tester.pumpWidget(
          WatchResumeSync(
            onResume: () {
              calls.add('sync');
              return Future<void>.value();
            },
            child: const SizedBox.shrink(),
          ),
        );

        Future<void> go(AppLifecycleState state) async {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }

        // The binding reports every state it is handed, a repeat of `resumed`
        // included (observed here, not assumed), so "once per resume" is "once
        // per reported `resumed`", and nothing else reported asks for anything.
        await go(AppLifecycleState.inactive);
        expect(calls, isEmpty, reason: 'S-109 leaving the app asks for nothing');
        await go(AppLifecycleState.resumed);
        expect(
          calls,
          ['sync'],
          reason: 'S-109 a resume is one sync — no timer, no polling',
        );
        await go(AppLifecycleState.resumed);
        expect(
          calls,
          ['sync', 'sync'],
          reason:
              'S-109 the binding reports a repeated `resumed` to its observers, '
              'so it is one more resume and one more sync',
        );
        await go(AppLifecycleState.inactive);
        await go(AppLifecycleState.resumed);
        expect(
          calls,
          ['sync', 'sync', 'sync'],
          reason: 'S-109 one more resume, one more sync, and none in between',
        );
      },
    );
  });
}
