# Evidence — plan 311 (the Wear wrist sends heart rate on each timed, round and hold entry, and a round's paused time)

- Built by `crew-builder-watch` (run `20261122-220212`, 6 min 50 s, exact-code
  brief, no gateway command); the lead fixed one fixture (the hand-built round
  of S-31108 lacked the two slot ids, so it was refused for the wrong reason)
  and added the `S-31109` group.
- `flutter analyze`: 174 issues, 0 errors (baseline 174).
- `test/wear_heart_rate_per_effort_test.dart`: 25 passed.
- Readers: every `test/watch_*.dart`, `test/wear_*.dart`,
  `test/live_mirroring_test.dart`, `test/distance_source_import_test.dart` and
  `test/row_invariants_guard_test.dart` ran: 1654 passed, 827 failed; every
  failure is in the Windows baseline (path separators, CRLF, Hive paths) and
  none is new.
- Mutation pass by the lead (23 mutants over: pause start and end bounds, the
  exclusion check, the other-timer filter, row ordering, resume detection, the
  stop fallback and its precedence, resume instant, the window cap, the open
  pause and its stop, post-window pause, accumulated clamp, the zero rule, the
  exclusion kind, the hold kind, the log-time merge, the exclusion argument,
  `timerRows` session and kind, the timed kind, the set kind): 18 killed first
  time; M05 (rows not sorted), M08 (a stop beats a resume), M12 (an open pause
  ends at the stop) and M14 (negative accumulated pause) survived and were
  killed by four tests added in `S-31109`; M22 (the kind guard for a set) is
  EQUIVALENT: a set event carries no `startedAt`/`endedAt`, so the window
  check returns before the kind matters.
- Independent review of plan 310 (same area) by `crew-reviewer`: APPROVE;
  plan 311 has not been reviewed.
- Not proven here: owner check 26 (needs a real watch).
- Standards seen, not fixed: none.
