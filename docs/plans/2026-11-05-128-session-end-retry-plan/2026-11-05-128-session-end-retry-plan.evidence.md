# Plan 128 evidence — Phase-0 probes (planning run, base `ecf2d050` + uncommitted tree, 2026-11-05)

Probe source (not a committed test; the real file is Phase 0 of the plan):
`2026-11-05-128-session-end-retry-plan.probe-source.dart.txt` in this folder. It was run once as
`test/zz_probe_128_session_end_test.dart`, then moved here; nothing was left in `test/`.
Shape: shipping graph `createWatchSync` over a queueing fake radio (unreachable + durable frame → `queued`,
newest per type), wrist side = real Dart engine over `InMemoryWatchSessionStore`. The wrist starts a
one-slot session, the phone adopts it, the wrist goes away, the phone ends the session, and the queued
copy is then dropped (`queued.clear()`: reinstall, queue lost, app killed).

Command: `flutter test test/zz_probe_128_session_end_test.dart` → `+3 -3` (6 tests).

| Probe | Question | Result |
|---|---|---|
| P1 | end lost; the wrist later sends its **snapshot** (same phone run) | PASS: phone answers `completed`, wrist ends (D-182 `rememberedFateOf`) |
| P2 | same, phone app restarted first (fate memory empty) | PASS: the router's `alreadyEnded` path (session row is history) answers `completed` |
| P3 | end lost; the wrist sends only a `timer_state` frame (what a wrist logging a set/timer sends) | **FAIL**: no answer, wrist stays `active` |
| P4 | end lost; the watch comes back into reach (`emitLink(reachable: true)`) and nothing else | **FAIL**: nothing is re-offered, wrist stays `active` |
| P5 | reinstall: an empty wrist sends the snapshot **request** after the phone ended | **FAIL vs owner decision**: the phone answers with a `session_snapshot` of the ended session; the new wrist holds it with status `completed` (an old finished session shows up) |
| P6 | the OS delivers the old `completed` for session A onto a wrist that now holds session B | PASS: refused (`guardSession` compares session ids); B stays `active` |

Reading: the phone heals only when the wrist itself opens a snapshot conversation (catch-up on becoming the
active app while reachable, `WatchSyncOrchestrator.sync`). A wrist already in front, or one that talks only
in `timer_state` / observations, is never answered (O-4). The end is also forgotten by the phone's bookkeeping
the moment the (possibly queued) frame is handed over: `_announceEnd` removes the pending id when the mirror
holds the session (`watch_session_auto_push.dart:526-532`, S-217) and, for a non-held session, on
`delivered` only (a `queued` answer keeps it pending, but it is then re-sent as a fresh frame).
