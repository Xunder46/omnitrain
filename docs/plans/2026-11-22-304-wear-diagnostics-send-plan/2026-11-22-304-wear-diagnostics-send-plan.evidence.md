# Plan 304 evidence

Built and proved by the lead alone (Kotlin is outside the crew's write ceiling and the gateway hangs for builders on this PC). No independent reviewer ran.

## Observed output

- `flutter test test/wear_diagnostics_send_test.dart`: 33 passed (S-30401..S-30408).
- Neighbouring set (send, shell, transport, summary, queue-newest, start-up read, link package, merged text, settings watch log, wear app): `+112 All tests passed`.
- `flutter analyze`: 174 issues, 0 errors (baseline unchanged).
- `flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart` and `flutter build apk --debug --flavor phone`: both built (the plugin's Kotlin compiled in both).
- Watch/wear test set (126 files) on this Windows PC: 1468 pass, 760 fail. All failures are the Windows baseline (path separators, CRLF, Hive). The 22 failing names that were not matched by name in `.work/windows-base-failing-tests.txt` were re-run on a clean HEAD (stash) and fail there too (rating engine/state S-284xx, S-004, S-28132, S-28308 and the rest of the engine-contract tests).
- One regression of mine was caught by an existing guard and fixed: the first constant name `KEY_SENT_AT_MS` sat inside the region plan 294's `S-29415` scans for `KEY_SENT_AT`; renamed `KEY_STAMP_MS`.
- One finding fixed in the build: the new button had no `shape:`, which `S-2601` (every button constructor sets a shape) flags; it now carries the rounded rectangle every other wrist button uses.

## Mutation pass (35 mutants, one run per mutant over `test/wear_diagnostics_send_test.dart`)

34 killed, 1 equivalent survivor:
- Equivalent: M13 removing `|| _sending` from `_send`'s guard. The button is already disabled while sending (M12 is killed), so the guard is defence in depth and unreachable by a tap.
- Killed: outcome mapping (3), the empty rule, success outcome, the log line, the timeout, the catch-all outcome, the link's error codes and argument key, `rawText`, the disabled button, the stored outcome, the screen's catch, button height, the button's presence, the shell's wiring (2), two sentences, and 15 Kotlin source mutants (watch-only, peer check, path, stamp, role, takeQueuedItem order, own-item skip, main-thread read, temp file, delete only after a good write, descriptor release, file name, directory, method registration).
- Note: M25 (stamp) was run under the old constant name; after the rename the guard string was updated with it (`putLong(KEY_STAMP_MS, ...)`).

## Not observed

- A real send between a watch and a phone, and the file arriving: owner check 21 (`docs/wear_os_app.md`). The emulator process crashes (exit 139) whenever the app puts a data item (plan 295 note), so the put could not be run there either.
- The Kotlin receive is proved by source guards only (no Kotlin test harness): the asset read, the rename and the delete are text-checked, not executed.
