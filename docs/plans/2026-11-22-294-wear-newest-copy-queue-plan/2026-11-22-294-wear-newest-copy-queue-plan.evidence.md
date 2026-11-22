# Plan 294 evidence

Base commit `95d5938f`. Windows PC: the full suite is red in the baseline (path separators, CRLF, Hive paths) and the owner said not to chase it; the evidence is the touched and neighbouring files, `flutter analyze` and a Kotlin compile.

## Builds

- P1 (plugin descriptor): `crew-builder-watch`, run `20261122-132156`, 1.3 min, 17 model requests, no denial, no stop. Three files, the Kotlin insertion exactly as briefed.
- P2 (the rule in the transport): `crew-builder-watch`, run `20261122-132206`, 1.7 min, no denial, no stop. One file. The lead ran `dart format` on it by explicit path; the formatter also joined `requestSnapshot` onto one line (a two-line change outside the plan).
- P1 and P2 ran in parallel on disjoint scopes (the P2 brief named the P1 fields). Tests, docs and the mutation pass: lead (builders were told to run no gateway command; the gateway hangs on this machine).

## Checks (observed)

- `flutter test test/wear_queue_newest_test.dart test/wear_watch_transport_test.dart test/wear_diagnostics_transport_test.dart test/watch_link_package_test.dart`: `+51: All tests passed!` on the first run (before the four tests added for mutation survivors). Final: `wear_queue_newest_test.dart` `+21` all passed; `watch_link_package_test.dart` `+16`.
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).
- Readers of `WatchLinkTransfer`: `test/watch_link_package_test.dart` (constructs and compares) and `lib/core/platform/watch_connectivity_channel.dart` (maps to the core `WatchQueuedTransfer`, unchanged); both green.
- Wear APK compile (Kotlin): see Progress in the plan.

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

30 mutants over the transport, the plugin's Dart read and the Kotlin source guard.

- Killed: snapshot arm off; lifecycle replaces snapshot always / never; a terminal copy withdrawn; a lifecycle copy never withdrawn; equal stamp counts as newer; stale rule reversed; a terminal frame can be stale; an unreadable stamp newest on a copy; oldest on the frame; own-id skip removed; own-id skip applied to snapshots; no dedupe of an own id; dedupe applied to snapshots; session not matched; no live withdraw; live withdraw for any frame; no lane; stale frame still queued; list failure unreported; `abandoned` / `completed` not terminal; a frame with no session replaces nothing; the plugin's `state` read, `sentAt` read and equality; the Kotlin `state` and `sentAt` reads.
- Survivors found by the first pass and closed by four tests the lead added (three written before the pass because the mutant list predicted them, one after it): the own-id dedupe on a replayed terminal (assert exactly one `queue:mC`), a live snapshot of an ended workout (withdraws nothing, lists nothing), a live lifecycle whose own copy waits (not cancelled), and a frame naming no session.
- Equivalent (2): `found.olderIds.isNotEmpty` removed on the queue path and on the live path. `WatchLink.cancelTransfers` already answers 0 for an empty list without calling the platform, so the guard changes nothing the channel can see. One more was not mutated for the same reason: `copy.type.isEmpty`, because the session check before it already skips every copy with no type.

## Not verified here

- The data layer's behaviour on a real watch (a delete followed by a put at the same path, and a copy the peer takes between the list and the cancel): owner check 14 in `docs/wear_os_app.md`.
