# Review: plan 86 (wrist owns rest pings) · P1+P2+P4 · f0d0d08..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 0 · nit 0 · tests: 5733 passed / 0 failed (lead's full run, per brief; not re-run)
Diff vs Predicted Files: conforms — exactly the plan's P1/P2 predicted files (`rest_notification_service.dart`, `wrist_rest_ping_rule.dart`, `main.dart`, `watch_rest_ping_wiring.dart`, the three new test files) plus P4's docs (`rest_tracking.md`, `state_management/watch_surface.md`, `watch-app-setup-and-qa.md`) and the plan file itself.

## Findings

1. [Major] `lib/state/watch/watch_rest_ping_wiring.dart:57-60` — the mirror listener's cancel branch fires on a session *switch*, not only on a session *end*, and `cancelRestNotifications()` forgets the remembered request, so the phone's own rest goes silent. Sequence: the phone's session `s-1` runs with an open rest, the wrist owns the pings (`previousGate == true`, request remembered); the wrist abandons `s-1` with no delivered end frame (watch app killed mid-workout, user starts a new workout on the watch) and the mirror receives the new session's snapshot — `LiveSessionMirrorState.receive` switches the held session wholesale (`live_session_mirror_state.dart:233-236`) and notifies. The listener then sees `wasOwned == true`, `mirrorStillHoldsPhoneSession == false` (mirror active on the new id ≠ `s-1`) and calls `cancelRestNotifications()`: the phone's still-open `s-1` rest is cancelled AND forgotten, the wrist is pinging the new session, and the phone stays silent for the rest of that rest (until the next lifecycle/settings/next-rest trigger). This violates the plan invariant "A rest is never silent: when the phone stops owning the pings mid-rest it re-schedules the remaining boundaries". The plan's D-8/S-15611 assumed "mirror no longer holds the phone's session" ⇒ "the wrist finished the rest"; a switch to another *active* session is the case where that is false. Fix: take the cancel+forget branch only when the mirror's held session itself ended — `if (wasOwned && !mirrorStillHoldsPhoneSession && !mirror.isActive)` cancel, else `reevaluate()` (S-15611 still hits it: the wrist's `session_lifecycle completed` leaves `isActive == false`; the switch case re-evaluates with the gate false and re-schedules from the remembered request). Guard: a wiring test — request remembered under a true gate, then the mirror receives a snapshot naming `s-2` while the phone stays on `s-1` → the remaining boundaries are scheduled (today: 0 schedules, request forgotten).

## Assumption Log rulings

- Per-frame `reevaluate()` churn (every `WatchLinkState._onHeard` notify runs a pass of up to 50 no-op cancels): **ratify** — the plan's Assumption Log explicitly bounds it and scopes the "gate unchanged and true → skip" short-circuit out.
- "A wrist frame that ends the session is assumed to also end its open rest": **ratify** for a delivered end frame (the adoption bridge ends the phone's session with it). The unlogged sibling — the wrist moving to a new session with *no* delivered end — is finding 1; escalate that one case to the plan owner.
- `MockWorkoutRepository` + `loadHistoricalSession('s-1')` as the wiring fixture: **ratify** (the same call the adoption bridge makes).
- Foreground double (phone in-app ping + wrist tap while the phone is open): **ratify** (owner agreed, recorded in the plan header).

## Scenario coverage

- S-15601 → `test/wrist_rest_ping_rule_test.dart` · group `wristOwnsRestPings`, 6 cases (true shape + 5 single deviations) ✓
- S-15602 → `test/rest_ping_gate_test.dart` · `scheduleRestPings schedules nothing and cancels the 50 ping ids` ✓
- S-15603 → same file · `schedules the future boundaries exactly as today` ✓
- S-15604 → same file · `gate true->false schedules the 48 future boundaries; false->true cancels` ✓
- S-15605 → same file · `does nothing before a request and after cancelRestNotifications` ✓
- S-15606 → same file · `nothing scheduled at either gate and reevaluate keeps it so` ✓
- Queue (D-7) → same file · `rest ping queue` group · `overlapping scheduleRestPings and reevaluate finish in order with no interleaved ids` ✓
- S-15609 → `test/rest_ping_gate_wiring_test.dart` · `true while owned, false after the link drops, false after the wrist moves on` and `with no watch graph the gate stays null` ✓
- S-15610 → same file · `link drop re-schedules the 48 future boundaries; link return cancels` ✓
- S-15611 → same file · `lifecycle completed cancels and forgets; a later link flap schedules nothing` ✓
- Mirror-switch-while-the-phone's-rest-continues (finding 1) → MISSING

## Brief answers (evidence read)

1. Queue — no finding. `_scheduleRestPingsNow` cancels via the raw `_cancelRestNotificationsNow` (`rest_notification_service.dart:325`), `_reevaluateNow` calls the raw `_scheduleRestPingsNow` (`:677`), the public cancel's body calls the raw cancel (`:688`); no queued body awaits a queued entry point, so no deadlock. `_enqueueRestPingPass` re-chains through `onError: (Object _) {}` (`:163-165`), so a throwing pass cannot poison the passes behind it. Ordering proven by the `rest ping queue` test.
2. Existing callers — no finding. `workout_session_finish.dart:85` awaits the cancel before `cancelEffortTimerNotification` (id 200 only — no overlap with the queued 100..149 pass), so the deterministic finish order holds; the mixin (`:670,:752`) and screen (`:271,:351,:365,:884,:1414,:1471,:1843`) sites are all `unawaited` with no statement that depends on the cancel having started. The queue adds at most one in-flight pass of delay to the awaited finish cancel — bounded, not a deadlock.
3. Gate semantics — no finding. A true gate still cancels first (`:325` before the `wristOwns` return at `:326`), so a takeover withdraws leftovers, and every pass cancels before scheduling, so an interrupted pass is cleaned by the next one. `playSound` staleness is self-correcting: every foreground/background transition runs `_scheduleActiveRestNotifications` (background — re-schedules and refreshes the memory with the current `!_isAppForeground`) or `cancelRestNotifications` (resume — forgets), and `_onSettingsChanged` re-schedules too (`workout_session_screen.dart:265-296`), so a `reevaluate` always reads a memory that matches the app's current foreground state; a reevaluate while foregrounded schedules `playSound: false`, which is what a fresh foreground schedule does today.
4. Wiring — finding 1 above. The brief's own scenario (mirror notifies, gate still true, `currentSession` a stale ended session) is harmless: the phone's session is over, so there is no rest to ping, and the phone-side end paths (`completeSession` via `_sendOwn`'s local apply, `reportLifecycleFor`'s local apply) flip the mirror off `active` and drive `previousGate` false before a new session can start.
5. `main.dart` — no finding. `bindRestPingGate` at `main.dart:405-410`, after `watchSync` (`:371`) and `workoutState` (`:387`) and the `bindWorkoutState` block, before `MyApp` is returned; nothing can schedule a ping before the screens receive the service. `watchSync == null` → both states null → the wiring returns early (`watch_rest_ping_wiring.dart:22-23`), the gate stays null, behaviour byte-identical (tested).

Docs: every behaviour sentence added by P4 names tests/files I read this run (`wrist_rest_ping_rule_test.dart`, `rest_ping_gate_test.dart` S-15602..S-15606 + queue group, `rest_ping_gate_wiring_test.dart` S-15609..S-15611, `bindRestPingGate`, `wristOwnsPings`, `reevaluate`) — all exist. QA step 34 matches the owner table.
