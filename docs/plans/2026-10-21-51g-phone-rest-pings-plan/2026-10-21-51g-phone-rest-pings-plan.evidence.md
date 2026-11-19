# Evidence — plan 51g (the phone stops pinging a rest the watch ended)

Proof date: 2026-10-21 (lead: unit tests, mutation pass). Docs and evidence: docs keeper, 2026-10-21.

## Test table (scenario → test → file)

| Scenario | Test | File |
|---|---|---|
| S-7521 a rest the wrist ends cancels the pings and schedules nothing new | `S-7521 a rest the wrist ends cancels the pings and schedules nothing new` | `test/rest_pings_watch_end_test.dart` |
| S-7522 a rest the wrist replaced schedules from the NEW rest's start | `S-7522 a rest the wrist replaced schedules from the NEW rest's start` | same file |
| S-7523 a resync with the same rest open schedules again from that rest's own start | `S-7523 a resync with the same rest open schedules again from that rest's own start` | same file |
| S-7524 a resync with no rest ever open cancels and never schedules | `S-7524 a resync with no rest ever open cancels and never schedules` | same file |

Count: 4 new tests, 0 failures.

## Verified

- The tests above green (lead, 2026-10-21), Mock harness (`FakeRestNotificationService`).
- The lead's mutations, each red then restored: removing the added line (S-7521..S-7524 all fail); cancel-only (S-7522, S-7523 fail); schedule-only-when-open (S-7521, S-7524 fail).

## Not verified

- The two devices live. Owner check: phone in the pocket, watch worn — log a set on the phone, press Next on the watch, the phone does not ping.

## Docs

- `docs/rest_tracking.md`: one sentence after the both-devices-ping sentence — a rest the watch ends cancels the phone's scheduled pings, a rest the watch replaces reschedules them (citing S-7521..S-7524).
