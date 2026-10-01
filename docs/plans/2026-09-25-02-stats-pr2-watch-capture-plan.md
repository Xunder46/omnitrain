# Feature: Stats PR 2 — Watch Capture (effort rating at session end, per-effort heart rate and steps)

> Status: Iteration 1 — COMPLETE for implementation. Phases 1–6 done (2026-09-26). Review round 1
> (CHANGES REQUESTED) produced F-1 – F-19; all of F-1 – F-12 are fixed and verified. The re-review
> (2026-09-26) was APPROVE WITH NITS, and its mechanical round N1 – N7 is done; N8 and N9 moved out
> (O-20 and a shipping-plan Phase 7 item). Findings and their fixes live next to this plan:
> `2026-09-25-02-stats-pr2-watch-capture-plan.review.md` (findings) and
> `2026-09-25-02-stats-pr2-watch-capture-plan.evidence.md` (baselines, suites, red→green, footprints).
> No item is open for implementation; it is committed on `develop` as 21b5176. Manual QA on hardware is the owner's and
> waits on the shipping plan's Phases 7 and 8. The owner was unavailable during planning: every
> question was resolved with a recommended default, marked **Default — owner to confirm** in the
> Ledger; the Assumption Log adds A-62, A-65 and A-68 to confirm. A veto becomes a superseding
> Ledger entry.
> Next handoff: none. The PR is APPROVED WITH WARNINGS (@code-reviewer, 2026-09-26), and V-1 – V-4 are
> addressed (see the review companion). The next Stats work is the PR 3 series:
> `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.
> Tier: STANDARD. Consolidation findings (F-1 to F-19) widened the scope. See D-110 and D-111.
> Branch: committed on `develop` as 21b5176, squashed. Its title, "Add tests for session end handling
> and phone preferences synchronization", doesn't say it is PR 2. It contains every later fix round.
> The branch `feature/stats-pr2-watch-capture` (b9348fe), which 21b5176 superseded, was deleted on
> 2026-09-27. 21b5176 is on origin/develop.
> Binding conventions: `docs/global_conventions.md`, `CLAUDE.md` ("Verification
> is observed output"), `docs/documentation_standard.md` (every doc edit),
> `watch/sync_protocol/PROTOCOL.md` (normative wire spec).
> Feature docs to read first: `docs/state_management/services_and_utils.md`
> ("Watch ↔ Phone Live Session Mirroring", "Watch Sensors and the Platform Workout"),
> `docs/data_models.md`, `docs/db_integration.md`,
> `docs/session_summary.md`, `docs/theme_and_settings.md`.
> Source of scope: `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md`,
> items 2 and 3 only. Related plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`.
> In that plan, Phases 1–6 are done, Phase 7 (Xcode watch app target) is manual and not
> done, and Phase 8 (real sensor bindings) is blocked on Phase 7.

---

## Overview

Pack item 2 asks the watchOS app for the session effort rating (1–5) when a session ends on
the wrist. It asks only when the phone's effort-rating setting is on, and the question must be
answered. Pack item 3 asks the watchOS app to compute heart-rate summaries: per session, per
timed effort (with a step total), per round, and per hold or set effort. They are computed from
the wrist's raw readings before those readings are pruned, and they travel to the phone,
append-only. Both items are watchOS only (D-101). The phone must receive, validate, apply and
store what the wrist sends.

### Ground truth found during planning (drives scope — read before building)

- **F-1 — No watch session reaches the phone's history.** `LiveSessionMirrorState.completedRecord`
  is an in-memory map (`lib/state/watch/live_session_mirror_state.dart:85, 405-413`), rendered
  once by `_CompletedSession` in `lib/features/session/live_session_screen.dart`. No code under
  `lib/state/watch/` or `lib/core/sync_protocol/` creates a `TrainingSession`. A wrist session
  never appears in the calendar, the Session Summary or Stats, and is lost when the phone app
  restarts. Without an import, the rating has no `TrainingSession.sessionFeeling` to live in
  and the summaries have nothing to attach to (D-110).
- **F-2 — The phone re-asserts a stale session.** When a wrist snapshot names a session
  different from the one the mirror holds, `_shapeDiffers` is true and `_holdsLadder(before)`
  sends the old session back (`live_session_mirror_state.dart:182-196`). Swift
  `applySnapshot` adopts any snapshot as current (`WatchSessionEngine.swift:382-424`). The
  second wrist session synced while the phone app still holds the first is yanked back to the
  first on the wrist.
- **F-3 — The phone reconciler merges entries across sessions.** `_applySnapshot` never clears
  `_entries` (`lib/core/sync_protocol/session_reconciler.dart:106-121`).
- **F-4 — The wrist re-sends only the current session's owed observations**
  (`WatchSessionEngine.swift:1079-1109`). An earlier session's unsent entries are never re-sent
  once a new session starts.
- **F-5 — Session observations are never receipted.** Only quick-logs get a `receipt`
  (`lib/state/watch/watch_nutrition_log_bridge.dart`). Session entries are confirmed only when a
  phone snapshot happens to carry them.
- **F-6 — Neither wrist client has an End-session UI.** Only `finishSession()` exists. The Dart
  debug harness calls it (`lib/watch/debug/watch_session_debug_surface.dart:258`).
- **F-7 — Wrist sessions carry no modality and no routine id.** Both start paths call
  `createSession(modality: nil)` (`WatchStartPaths.swift:217, 226`).
- **F-8 — Set events carry only `loggedAt`.** They have no start or end time
  (`WatchLoggingState.swift:585-589`). Timed and hold windows are `[loggedAt − dialled
  duration, loggedAt]`. Round windows come from the round countdown, including its pause
  bookkeeping (`WatchLoggingState.swift:602-628`).
- **F-9 — Heart rate is stored on the wrist for the live readout only.** It is never sent.
  Nothing records steps (`WatchSensorRecording.swift`, `watch/contract/watch_sensor_contract.json`).
- **F-10 — Nothing calls `pruneConfirmed()` or `pruneSettledSensorSamples()` in production.**
  Only the Dart debug harness calls them.
- **F-11 — `swift test` is in no automated gate.** It is absent from `scripts/pre_release_check.sh`
  and `.github/workflows/release.yml`.
- **F-12 — The append-only guard is a source scan.** `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`
  rejects any 4-space-indented `func` in `watch/watchos/Sources/` whose name starts with
  update|delete|remove|replace|edit|overwrite|write|clear|purge|wipe|reset|drop|truncate|erase|forget|modify|mutate|destroy|set.
  It also pins the store surface to exactly `append/readAll/pruneConfirmed/pruneSensorSamples`.
- **F-13 — Docs have hard limits.** Docs in `docs/` fail `test/docs_indexing_contract_test.dart`
  above 80% of 64 KiB (52,428 bytes). `services_and_utils.md` is about 40 KB now. The docs
  standard forbids flows, UI descriptions, restated numbers, copied field lists and roadmap
  notes.
- **F-14 — `metric-heart-rate` exists but nothing uses it.** It is seeded
  (`lib/mock/seed_data.dart:4479`, `scripts/sqlite_seed.sql:131`) as a manual, single-value int
  metric for timed/interval efforts, with no reader and no writer.
- **F-15 — The phone setting is a string preference.** `show_feeling_survey` is stored as the
  string `'true'`/`'false'` and defaults to on (`lib/state/settings/settings_state.dart:15, 318-323`).
- **F-16 — `endSession` returns early for an ended session**
  (`lib/state/workout/session_core_lifecycle.dart:5-6`). It is the only caller of the platform
  health write (`:48-51`).
- **F-17 — Invalid fixtures are replayed event by event.** Each event of every invalid
  `observations_up` fixture is replayed through both watch engines and must be refused
  (`SyncProtocolFixturesTests.swift:101-138`, `test/watch_session_engine_test.dart:549-595`), so
  an invalid fixture may contain only offending events.
- **F-18 — The Dart wrist ignores unknown message types.** It does so at
  `lib/watch/start/watch_sync_orchestrator.dart:121-143`, and scopes observations to the current
  session (`lib/watch/session/watch_session_engine.dart:160-163`). New message types and event
  kinds are therefore accepted or ignored by `lib/watch/` without code changes.
- **F-19 — Kind lists are pinned by equality tests.** Each client's sensor kinds must equal the
  sensor contract's `kinds` (`test/watch_sensor_recording_test.dart:643-646`,
  `WatchSensorRecordingTests.swift:456-460`). Each client's observation kinds are a pinned
  closed set (`test/watch_nutrition_quick_log_test.dart:1326`, `WatchNutritionQuickLogTests.swift:585-591`).

---

## Resolved Decisions (Ledger)

Numbering starts at D-101 so this plan's IDs never collide with the prompt pack's D-1…D-15. Pack
decisions are cited as "Pack D-n". Entries are immutable. A change is a new superseding entry.

### Binding — settled by the owner

- **D-101 — watchOS only (Pack D-1).** Wrist work goes in the Swift package `watch/watchos/`.
  `lib/watch/` gets **no new behavior**. Every shared fixture and contract test must keep
  passing, so every protocol addition is something the Dart wrist accepts or ignores. The only
  permitted `lib/watch/` edit is D-127. The phone side is in scope: `lib/core/sync_protocol/`,
  `lib/state/watch/`, repository and models.
- **D-102 — The rating (Pack D-4, D-5, D-14).** The session effort rating is an integer 1–5.
  The title is "How hard was this session?". "Very easy" goes under 1 and "Max effort" under 5.
  It is stored in the existing `TrainingSession.sessionFeeling`, with no migration. PR 1 owns
  that field's phone labels and comments, and PR 2 does not edit them.
- **D-103 — When the wrist prompts (Pack D-10 and shipping-plan D-7).** The wrist prompts if and
  only if the phone's setting (preference key `show_feeling_survey`) is on, as last learned by
  the wrist. Once shown, the prompt must be answered: there is no skip and no dismiss. The wrist
  learns the setting at sync. Sync is started from the wrist, so a change on the phone reaches
  the wrist at its next sync.
- **D-104 — Item 2 rules.**
  - (a) The rating is recorded as part of completing the session on the wrist.
  - (b) The wrist never modifies an existing rating.
  - (c) On a live-mirrored session, only the device that ended the session prompts.
  - (d) A rating captured while disconnected arrives intact later.
  - (e) The phone's value is final and never overwritten by a later wrist sync.
- **D-105 — Item 3 rules.**
  - Summaries: session average/maximum HR; per timed effort, average/maximum HR over its active
    time plus a step total; per round, average/maximum HR; per hold or set effort,
    average/maximum HR over its active span.
  - Paused time is excluded.
  - No samples means no summary, never zero.
  - Steps are recorded only on timed efforts.
  - Summaries are computed on the wrist before raw samples are pruned.
  - Summaries are append-only and never rewritten.
  - Live HR, GPS and the platform health write must not regress.
- **D-106 — Steps.** Steps are a new sensor kind in the existing sensor abstraction and in
  `watch/contract/watch_sensor_contract.json`, exercised with the existing test doubles. The
  real platform binding belongs to shipping-plan Phase 8 (O-2).

### Scope

- **D-110 — Watch sessions are imported into the phone's history. Default — owner to confirm
  (product).** Grounded in F-1. When the phone learns that a wrist session was completed (its
  `session_end`, D-120), the phone creates an ordinary `TrainingSession` holding that session's
  entries, rating (D-138) and summaries (D-131).
  - Without the import, the rating and summary requirements can't be met (AC-2.2, AC-2.3,
    AC-2.6, AC-3.1, AC-3.5).
  - *Alternative:* ship the import as a prerequisite PR 2a. PR 2 alone would then store nothing
    durable on the phone.
- **D-111 — The multi-session defects are fixed in PR 2. Default — owner to confirm
  (product).** F-2, F-3 and F-4 together make a second wrist session sync badly while the phone
  app still holds the first:
  - it gets mixed with the first session's entries on the phone;
  - it gets yanked back to the first session on the wrist;
  - its older unsent entries are never re-sent.

  PR 2 fixes all three (D-128, D-130), because the import would otherwise persist corrupted
  history.
  - *Alternative:* a separate remediation PR merged before PR 2.
- **D-112 — Protocol versioning. Default — owner to confirm (technical).** Everything ships
  inside protocol **v1** as additive amendments:
  - the `preferences_down` message;
  - the `effort_rating` and `session_end` event kinds;
  - new optional fields;
  - the session-switch clarification;
  - the resend rule.

  `PROTOCOL.md` › Version history gains a row "1 (amended) · 2026-09-25", justified the same way
  the `receipt` addition was: both clients ship from this repo in one release, v1 is unreleased,
  and no receiver that predates the change exists.
  - No existing fixture is edited except by addition.
  - New semantic rules constrain only the new fields. Existing fields keep their current
    permissiveness.
  - *Alternative:* bump to v2, with a new schema set, dual-version fixtures and snapshot-only
    exchange between versions.

### The setting reaching the wrist

- **D-113 — The `preferences_down` message. Default — owner to confirm (technical).** It is a
  new phone → watch reference message. Its payload is `{generatedAt, effortRatingPrompt:
  boolean}`, both required, with no `sessionId`.
  - The phone answers every wrist sync request (the existing `routines` request) with
    `preferences_down`, **always**, even when it holds no routines, and before any
    `routines_down`.
  - The wrist stores preferences append-only. The preferences with the latest `generatedAt` win;
    on a tie, the later-received wins. An older copy arriving late never replaces a newer one.
  - *Alternative:* an optional field on `routines_down`. It never reaches the wrist when the
    phone has no routines, because `buildRoutinesDown` returns null.
- **D-114 — Before the first sync. Default — owner to confirm (product).** A wrist that has
  never received `preferences_down` does not prompt.
  - *Alternative:* assume the phone's default (on) and prompt.
- **D-115 — The phone reads the setting through `SettingsState`. Derived from global conventions
  ("Reuse the canonical owner") — vetoable.** The value sent is `SettingsState`'s current
  effort-rating toggle, whatever PR 1 names the getter. No code re-parses the preference string.

### The rating on the wrist

- **D-116 — `effort_rating` event. Default — owner to confirm (technical).** It is a new
  `observations_up` kind with `rating` (integer, 1–5).
  - It is session-scoped: no slot, no exercise.
  - `entryId = eventId = "rating-<sessionId>"`. The wrist appends at most one per session, and a
    repeat is a store no-op.
  - Nothing on the wrist edits a rating or creates a second one.
  - *Alternative:* a field on `session_lifecycle` or `session_snapshot`. That is not durable:
    lifecycle messages are never re-sent, and a snapshot goes only for the current session.
- **D-117 — When a prompt is owed. Default — owner to confirm (product: the empty-session
  clause).** A prompt is owed for a session if and only if all of these hold:
  - the wrist's own End action completed the session;
  - the wrist's stored preferences said `effortRatingPrompt = true` at that moment;
  - the session had at least one effort entry (set, timed, round or hold) after phone deletions;
  - no `effort_rating` exists for the session.

  The owed state is written to the wrist store at End, never only to memory. A kill before the
  answer therefore re-presents the prompt at the next launch, before anything else. A completion
  that reaches the wrist from the phone (a lifecycle message or a snapshot) never owes a prompt.
  - *Alternative for the empty-session clause:* prompt even when nothing was logged.
- **D-118 — Prompt interaction. Default — owner to confirm (product).**
  - Nothing is preselected.
  - With the crown, the first clockwise detent from "unselected" selects 1. Further clockwise
    detents step up and stop at 5. Counter-clockwise detents step down and stop at 1; they never
    return to "unselected".
  - Every number is also tappable.
  - Confirm is enabled only once a number is selected, and confirming appends the rating.
  - There is no skip, dismiss, back or cancel.
  - Copy and scale come from `watch/contract/watch_effort_rating_contract.json`.
  - Crown detent size reuses `WatchMetricStepping.pointsPerDetent`.
  - *Alternative:* preselect 3.
- **D-119 — UI placement. Default — owner to confirm (product).** PR 2 ships a prompt view and a
  minimal End-control view behind `#if os(watchOS)`. Both are driven by testable state that sits
  outside the guard.
  - Composing them into the app's navigation, including presenting an owed prompt at launch, is
    the app-shell work of shipping-plan Phase 7 (O-1).
  - *Alternative:* add an End button to `WatchLoggingView` now.

### Session end and summaries on the wrist

- **D-120 — `session_end` event. Default — owner to confirm (technical).** It is a new
  session-scoped `observations_up` kind. `entryId = eventId = "end-<sessionId>"`.
  - **Fields:**
    - `startedAt`: the wrist session's start;
    - `endedAt`;
    - `status`: `completed` or `abandoned`;
    - optional `modality`, omitted when the wrist session has none, which today is always
      (F-7);
    - optional session `avgHeartRateBpm` and `maxHeartRateBpm`;
    - optional `setBlockHeartRates` (D-121).
  - **When it is appended:** exactly once per wrist-created session (source `"watch"`), at that
    session's first transition to completed or abandoned by any path: wrist End, wrist abandon,
    a phone `session_lifecycle`, or a phone `session_snapshot`. It is appended before anything
    else is stored for the session.
  - **What `endedAt` is:**

    | How the session ended | `endedAt` |
    |---|---|
    | Wrist End or abandon | The wrist clock at that moment |
    | Phone lifecycle message | The message payload's `at` |
    | Phone snapshot | The snapshot's `sentAt` |

    `loggedAt` is the wrist clock when the event is appended.
  - **Exceptions:** a reopened session that ends again gets no second `session_end`. A session
    the wrist joined from the phone (source `"phone"`) gets none.
  - *Alternative:* durable session fields on `session_snapshot`.
- **D-121 — Where summaries travel. Default — owner to confirm (technical).**
  - Timed, round and hold events carry their own summary, computed at log time:
    - optional `avgHeartRateBpm` and `maxHeartRateBpm` on all three;
    - on timed events, also optional `steps` (D-125);
    - on round events, also optional `pausedMs` (D-126).
  - The session summary and the set blocks travel in `session_end`. Each set block is a
    `setBlockHeartRates` item: `{sessionExerciseId, exerciseId, startedAt, endedAt,
    avgHeartRateBpm, maxHeartRateBpm}`.
  - Set events never carry HR.
  - An emitted event is never re-emitted with different values, not even after a relaunch.
  - *Alternative:* compute every summary at session end as separate events keyed by `entryId`.
- **D-122 — Heart-rate math. Default — owner to confirm (technical).**
  - (a) **Window membership.** A sample belongs to a window if its `recordedAt` is inside
    `[startedAt, endedAt]` (both ends inclusive) and it is outside every pause interval.
  - (b) **Pause intervals are half-open**, `[pausedAt, resumedAt)`.
  - (c) **Where pauses come from.** They come from the stored rows of the wrist timer that
    timed the entry: for a round, the round-timer rows whose `startedAt` equals the event's
    `startedAt`. A pause begins at a row's `pausedAt`. It ends at the `recordedAt` of the first
    later row of that timer without `pausedAt`, else at that row's `stoppedAt`, else at the
    window end. Timed and hold entries have no pauses on watchOS today.
  - (d) **Glitch samples.** Samples with a value ≤ 0 are ignored.
  - (e) **The math.** The average is the arithmetic mean of the qualifying values, unrounded
    (a double). The maximum is the largest qualifying value.
  - (f) **No samples, no fields.** With no qualifying sample, both fields are absent, never 0.
    The fields are both present or both absent, and average ≤ maximum. Schema `minimum: 1`
    makes a zero unsendable.
  - (g) **Session window.** It is `[session start, session_end.endedAt]`. A round's pause is
    not a session pause, so it is not excluded from the session summary.
- **D-123 — Set-block span (sets carry only `loggedAt`, F-8). Default — owner to confirm
  (product).**
  - A set block is every set entry of the session with the same `(sessionExerciseId,
    exerciseId)`, after phone deletions.
  - Its span starts at the `loggedAt` of the latest effort entry (any slot, any kind) logged
    strictly before the block's first set, or at the session start if there is none. It ends at
    the block's last set's `loggedAt`.
  - The span therefore includes the rests between sets. Interleaved blocks (supersets) may
    overlap.
  - *Alternative:* start the span when the wrist moved onto that exercise. That needs position
    history the wrist does not keep per slot.
- **D-124 — Holds are summarised per hold. Default — owner to confirm (product).** Each hold
  entry carries its own summary over its window. There is no per-slot hold-block summary.
  - *Alternative:* also add hold blocks to `session_end`.
- **D-125 — Steps. Default — owner to confirm (technical).**
  - **Sample kind and unit.** The sample kind is `steps`, in unit `cumulativeCount`: the
    platform's step count since the platform workout began.
  - **When recorded.** For every session with steps permission, because a timed effort can occur
    in any session (Pack D-3). Steps attach only to timed events.
  - **The math.** The baseline is the latest steps sample before `startedAt`, else 0. The chain
    is the baseline followed by every steps sample in `[startedAt, endedAt]`. For each
    consecutive pair, add `next − previous` when `next ≥ previous`, or `next` when it is smaller
    (the counter restarted after a workout recovery).
  - **Absence and zero.** With no steps sample inside the window there is no `steps` field. A
    measured 0 is sent.
  - *Alternative:* per-interval increment samples, summed inside the window.
- **D-126 — Round pause travels as `pausedMs`. Default — owner to confirm (product).**
  - Round events carry `pausedMs`, in integer milliseconds and present only when > 0. It is the
    round countdown's accumulated pause at log time, plus any pause still open.
  - The phone stores it as the round's paused total, so an imported round's duration excludes
    pause time, which matches its HR window.
  - *Alternative:* omit it. Imported round durations then include pauses (pausing isn't
    reachable from the wrist UI today).
- **D-127 — Dart wrist vocabulary. Default — owner to confirm (touches D-101).**
  `lib/watch/session/watch_records.dart` `WatchSensorKind` gains the `steps` constant, and it
  joins `all`.
  - This is a vocabulary constant with no recording and no behavior. It keeps the exact
    kind-equality test against the shared contract exact (F-19). It is the only `lib/watch/`
    edit in PR 2.
  - The Dart `WatchObservationKind` stays at five kinds, because the Dart wrist emits none of the
    new ones.
  - *Alternative:* leave the contract's `kinds` unchanged and put `steps` under a separate
    watchOS-only contract key.
- **D-128 — Resend every session's owed observations (F-4). Default — owner to confirm
  (technical).** On sync, the wrist re-sends every unacknowledged observation of every session
  it stores, in store order, plus standalone quick-logs as today. watchOS only (Wear debt, see
  Notes).
- **D-129 — Prune gate. Default — owner to confirm (technical).** `pruneSettledSensorSamples`
  never releases the samples of a completed or abandoned wrist-created session until its
  `session_end` is stored **and acknowledged**. This is in addition to today's gates. The store's
  public surface stays exactly `append/readAll/pruneConfirmed/pruneSensorSamples`.

### The phone

- **D-130 — Mirror session switch (F-2, F-3). Default — owner to confirm (technical).**
  - A snapshot naming a session other than the one held replaces it wholesale: structure,
    status, position, revision, timers **and entries**. Entries never merge across sessions.
  - The mirror's completed record is cleared, and the phone answers nothing to such a snapshot.
  - Re-assertion (PROTOCOL.md, S-008) applies only to a snapshot naming the held session.
  - The reference reconciler implements the entry rule. `LiveSessionMirrorState` implements the
    no-answer rule and the completed-record rule.
- **D-131 — Summaries live in a new model, `SensorSummary`, not in `metric-heart-rate`.
  Default — owner to confirm (technical).** The brief asked for this decision.
  - **Why not `metric-heart-rate`:**
    - A summary is an average+maximum pair plus steps. It attaches to a session, a set block
      (`SegmentEffort`), a timed or hold entry (`TimedInstance`) or a round (`RoundInstance`).
    - An `EffortObservation` holds one value per metric per effort-entry index. It cannot
      address a session or a `RoundInstance`.
    - Summaries are measured by the wrist, never entered by the user, and must not be read or
      edited as a manual metric.
  - **Why not new columns on `TrainingSession`, `TimedInstance` or `RoundInstance`:** those rows
    are rebuilt field by field in several places (for example `endSession` and
    `updateSessionFeeling`), where a new field would be silently dropped.
  - `metric-heart-rate` stays seeded and unused (O-9).
  - **Rules:**
    - one row per (scope, target);
    - scope is one of `session`, `effort`, `timed_instance`, `round_instance`;
    - the HR pair is both-or-neither, with 1 ≤ average ≤ maximum;
    - steps are ≥ 0 and only for `timed_instance`;
    - a row exists only with at least one measured value;
    - each row carries the window it summarises and source `watch`;
    - it is deleted together with its target.
- **D-132 — The watch session inbox. Default — owner to confirm (technical).**
  - **What is staged.** Everything the phone learns about a wrist session before it becomes
    history is staged durably in the repository on arrival:
    - every `set`, `timed`, `round`, `hold`, `effort_rating` and `session_end` event from
      `observations_up`;
    - the same kinds from a wrist `session_snapshot`'s entries;
    - the phone's own annotations: live corrections and deletions (D-137) and the phone-ended
      rating (D-139).
  - **How it is staged.** Rows are keyed by `entryId`, put-if-absent: a redelivered or altered
    copy never replaces a staged row. Staging happens before any other consumer can answer the
    message.
  - **When import runs.** When a session's `session_end` is staged, and at app start for any
    staged but unapplied `session_end`. An imported session is topped up as more of its rows
    arrive.
  - **When the phone sends receipts.** It sends a `receipt` for a session's rows once they are
    applied (materialised, or deliberately discarded), never on mere arrival. It uses the single
    existing receipt builder (`WatchNutritionLogBridge.receiptFor`, moved to a shared home if
    needed).
  - **Tombstones.** Staged rows are marked applied and never deleted; they are the tombstones of
    D-136.
  - **Guarantees.** Import is idempotent and independent of arrival order. Nutrition quick-logs
    stay with `WatchNutritionLogBridge`.
- **D-133 — What is imported. Default — owner to confirm (product).**
  - Only sessions whose `session_end` says `completed` and that hold at least one effort entry
    after phone deletions are imported. The phone already discards its own empty sessions
    (`workout_session_finish.dart:10-17`).
  - Abandoned and empty sessions are consumed and acknowledged without creating history.
  - *Alternative:* import abandoned sessions too.
- **D-134 — The shape of an imported session. Confirmed by the owner, 2026-09-27 (product; the
  mapping itself is technical).**
  - **Session.** `TrainingSession.id` is the wrist `sessionId`. The owner is the owner id the
    phone's own sessions use. `startedAt`, `endedAt` and `modality` come from `session_end`.
    `title`, `note`, `intent` and `routineTemplateId` are null, `isRolling` is false, and
    `sessionFeeling` follows D-138. There is one segment, shaped like the phone's default
    segment.
  - **Efforts.** There is one `SegmentEffort` per `(sessionExerciseId, exerciseId, kind)`, with
    kinds mapped set→`set`, timed→`timed`, round→`round`, hold→`drill`. Efforts are ordered by
    their first entry's `loggedAt`, ties by `entryId`. Entry index is the 0-based order by
    `loggedAt`, then `entryId`.
  - **Every row matches phone-logged rows.** Each row has exactly the shape the phone's own
    logging produces for the same entry (`lib/state/workout/session_core_entry.dart`): effort
    kind, metric ids, units, the `obs-<effortId>-<index>-<metricKey>` id pattern, and the
    companion observations with their defaults, including extra-weight 0 when the phone's
    catalog shows the exercise lacks `load`, or doesn't know the exercise. Per entry kind:

    | Entry | Rows created |
    |---|---|
    | Set | Reps, weight (`loadKg` or 0), and extra-weight 0 when the exercise lacks `load` |
    | Timed | A finished `TimedInstance` over its window, distance (`distanceMeters` or 0), and extra-weight 0 |
    | Hold | A finished `TimedInstance` plus extra-weight (`extraLoadKg` or 0) |
    | Round | A finished `RoundInstance`: start and finish from its window; paused total = `pausedMs` or 0; actual = window − pause; planned = actual; completed = true |

  - **Ids, timestamps, rests.** Row ids derive deterministically from wrist ids. `createdAt` is
    the entry's `loggedAt`. No rest records are created.
  - **Summaries.** Summaries attach per D-131. A summary whose target arrives later is attached
    when the target is created.
  - Reuse the phone's own row builders rather than restating them (the "Reuse the canonical
    owner" rule).
- **D-135 — No routine or modality link yet. Confirmed by the owner, 2026-09-27 (product).**
  - F-7 means imported sessions appear in history as Free Training with no routine link.
    Analytics are unaffected (Pack D-3).
  - *Alternative:* add `routineId` to `session_end` in PR 2 and set `routineTemplateId` on import
    (see O-7).
- **D-136 — Deleted history stays deleted. Default — owner to confirm (product).** If the user
  deletes an imported session, or a row of one, on the phone, no later sync re-creates it. Late
  entries for a deleted session are acknowledged and dropped.
- **D-137 — Live phone corrections and deletions carry into history. Default — owner to confirm
  (product).**
  - Every `correct_entry` or `delete_entry` the phone sends for a wrist entry is staged before
    it is sent (D-132).
  - At import, corrected values apply and deleted entries are omitted.
  - An annotation that arrives after import edits or removes the imported row.
- **D-138 — Rating precedence on the phone. Derived from D-104(e) — vetoable.**
  - At import, `sessionFeeling` is the phone's staged own rating (D-139) if there is one, else
    the staged wrist `effort_rating`, else null.
  - After import, a wrist rating applies only while `sessionFeeling` is null.
  - Any phone-side write (the Summary control from PR 1, or the phone prompt) always wins.
- **D-139 — The phone-ended mirrored session. Default — owner to confirm (product).**
  - When the phone's own Finish on the Watch Session screen completes a session that was active
    on the mirror, and the setting is on, the phone shows PR 1's effort-rating sheet, which must
    be answered.
  - The answer is written to the imported session if it exists; otherwise it is staged as the
    phone's own rating (D-138).
  - If the wrist completed the session, the screen shows the completed state, offers no Finish
    and never prompts.
  - *Alternative:* open the imported session's Session Summary and let its existing prompt run.
- **D-140 — The phone never writes an imported session to platform health. Derived — vetoable.**
  - The wrist's own platform workout is the health record for a wrist session (Phase 8).
  - This holds structurally: imported sessions are created with `endedAt` set, and `endSession`
    returns early for those (F-16).
  - A test guards it.
- **D-141 — The Watch Session screen lists effort entries only. Default — owner to confirm
  (technical).** `effort_rating` and `session_end` entries never appear in, or count toward, the
  live list, the status count or the completed-card count.
- **D-142 — History liveness. Default — owner to confirm (technical).** An import or top-up that
  changes history refreshes the calendar's loaded month once. A redelivery that changes nothing
  refreshes nothing.

### Process

- **D-143 — Merge order and copy parity. Default — owner to confirm (process).**
  - PR 1 merges to `develop` before PR 2. Phase 5 starts only after this branch is rebased onto
    a `develop` that contains PR 1.
  - `watch/contract/watch_effort_rating_contract.json` is the wrist's single source for the
    copy. Phase 5 adds the phone-side assertion that PR 1's sheet uses the same title, end
    labels and scale.
- **D-144 — `swift test` joins the release gate. Default — owner to confirm (process).**
  - Because of F-11, Phase 6 adds `swift test` (run in `watch/watchos/`) to
    `scripts/pre_release_check.sh`.
  - Without a Swift toolchain the step is skipped with a logged warning. A failure blocks.
  - *Alternative:* keep running `swift test` by hand.

---

## Feature Invariants

- **The wrist store stays append-only.** New wrist data enters only through `append`. The
  `testS004…` guard keeps its allowed set of exactly four names, and no new func name starts
  with a guarded verb (F-12). Suggested names: `answer`, `confirm`, `select`, `end`, `record`,
  `stage`.
- **Raw sensor samples never leave the wrist.** The only derived values on the wire are the
  D-121 fields. Appending a sample still emits nothing (`testAReadingIsStoredWithoutBeingSentAnywhere`
  stays unchanged and green).
- **Missing HR or steps means absence, never zero.** The schema (`minimum: 1` for HR),
  `SensorSummary` construction and the importer all refuse zero-filled summaries.
- **One `effort_rating` and one `session_end` per wrist session,** with deterministic ids.
- **The phone's rating is final** (D-138).
- **The import is idempotent, order-independent and durable.** Everything is staged before any
  answer, and deleted history is never resurrected.
- **Imported rows are indistinguishable in shape from phone-logged rows** (S-274).
- **`lib/watch/` gains no behavior** (D-101). Every shared fixture and contract test passes on
  both stacks after every phase.
- **Hive ↔ Mock parity** (standing rule): `MockWorkoutRepository` mirrors
  `HiveWorkoutRepository` value for value on every new repository path.
  `scripts/sqlite_schema.sql` documents every new table and is executed by
  `test/db_seed_test.dart`.
- **Docs follow the documentation standard.** Docs obey `docs/documentation_standard.md`
  and stay under the warning band (F-13).

---

## Requirements

- **R-1 — Protocol and contracts.** The protocol carries the setting (D-113), the rating
  (D-116), session ends (D-120), summaries, steps and round pause (D-121 – D-126). Every client
  validates them, and the Dart wrist accepts or ignores them.
- **R-2 — The wrist learns the setting at sync** and honours it from then on (D-113, D-114).
- **R-3 — The wrist prompts at End when owed** (D-117). The prompt must be answered, is
  kill-safe, and appends one rating (D-116, D-118).
- **R-4 — The wrist computes and sends summaries and steps before any prune,** re-sends every
  owed observation, and never regresses live HR, GPS or the platform workout (D-120 – D-129).
- **R-5 — The phone mirror switches sessions cleanly.** The phone answers syncs with
  preferences, and the live screen lists effort entries only (D-113, D-130, D-141).
- **R-6 — The phone stores staged wrist data and summaries** with Hive/Mock parity and the SQL
  contract (D-131, D-132).
- **R-7 — The phone imports completed wrist sessions into history.** It honours rating
  precedence, live corrections, tombstones, receipts and liveness, and never writes them to
  platform health (D-132 – D-142).
- **R-8 — Phone-ended prompt, Summary integration and copy parity,** after PR 1 (D-139, D-143).
- **R-9 — Docs, QA guide, shipping-plan cross-references and release gate** (D-144).

---

## Acceptance Criteria

Each criterion maps to scenarios.

**Pack item 2:**

| ID | Criterion | Scenarios |
|---|---|---|
| AC-2.1 | With the setting on, ending a session on the wrist shows the 1–5 prompt ("Very easy" at 1, "Max effort" at 5), and the prompt can't be closed without a choice | S-211, S-219 |
| AC-2.2 | A rating chosen on the wrist appears on the phone's Session Summary for that session after sync | S-261, S-286 |
| AC-2.3 | With the setting off (as of the last sync), the wrist doesn't prompt, and the phone's Session Summary offers to add a rating | S-212, S-213, S-285 |
| AC-2.4 | On a live-mirrored session, ending on the wrist prompts only the wrist, and ending on the phone prompts only the phone | S-216, S-217, S-281, S-283 |
| AC-2.5 | A session ended on a disconnected wrist and synced later arrives with its rating intact | S-215, S-261, S-268 |
| AC-2.6 | A phone-changed rating persists through later syncs | S-264 |

**Pack item 3:**

| ID | Criterion | Scenarios |
|---|---|---|
| AC-3.1 | After a wrist session with a run, a three-round sports effort and a set block syncs, the phone has session, run, per-round and set-block average/maximum | S-231, S-232, S-233, S-234, S-261 |
| AC-3.2 | The run has a step total; the sports and set efforts have none | S-231, S-232, S-202 |
| AC-3.3 | With the sensor unavailable for the whole session, the session syncs with no summaries and no zeros | S-235, S-269 |
| AC-3.4 | A phone-only session has no HR or step data and renders exactly as before | S-270, plus the unchanged full suite |
| AC-3.5 | Summaries remain on the phone after the wrist deletes the raw readings | S-237, S-261 |
| AC-3.6 | Live HR, GPS and the platform health write behave as before | S-239, S-270 |

**Foundation:**

| ID | Criterion | Scenarios |
|---|---|---|
| AC-F.1 | Every client passes every fixture; the Dart wrist accepts or ignores the additions | S-201 – S-207 |
| AC-F.2 | Multi-session correctness | S-205, S-240, S-251, S-268 |
| AC-F.3 | The import is idempotent, order-independent, durable, tombstoned and parity-checked | S-262, S-263, S-266, S-267, S-272 |
| AC-F.4 | Imported rows are shaped like phone-logged rows | S-274 |
| AC-F.5 | The setting reaches the wrist | S-214, S-253 |
| AC-F.6 | Docs, reachability and the gate | S-291, S-292, S-293 |

---

## Scenarios

Tests and code comments cite these IDs. The IDs are stable, never reused, and grouped by
phase with gaps between groups.

### Shared fixture F-CAP (`watch/contract/watch_capture_contract.json`, authored in Phase 1)

All times are 2026-09-25 UTC. When a sample and a log happen at the same instant, the sensor
sample is applied before the log.

- **Phone catalog.** It holds `ex-run` [time, distance], `ex-bjj` [time, rounds] and `ex-bench`
  [sets, reps, load].
- **09:00:00.** The wrist applies `preferences_down` (generatedAt 09:00:00,
  effortRatingPrompt `true`).
- **10:00:00.** The wrist creates session `s-cap-1` (free workout, no modality) with slots
  `sx-run`→ex-run, `sx-bjj`→ex-bjj and `sx-bench`→ex-bench. None declares an effort kind, so
  the kinds derive to timed, round and set. The scripted entry-id factory yields e-run, e-r1,
  e-r2, e-r3, e-set1, e-set2, e-set3.
- **HR samples (bpm):**

  | Time | bpm | Time | bpm |
  |---|---|---|---|
  | 10:05:00 | 120 | 10:36:00 | 180 |
  | 10:10:00 | 140 | 10:37:05 | 145 |
  | 10:15:00 | 160 | 10:40:00 | 165 |
  | 10:24:30 | 100 | 10:42:08 | 175 |
  | 10:26:00 | 150 | 10:44:00 | 110 |
  | 10:28:00 | 170 | 10:47:00 | 130 |
  | 10:31:00 | 150 | 10:50:00 | **0** (glitch) |
  | 10:33:00 | 100 | 10:51:00 | 150 |

- **Steps samples (cumulative):** 10:05:00 800 · 10:10:00 1600 · 10:20:00 3200 · 10:30:00 3300.
- **10:20:00 — log e-run.** Timed, with a dialled duration of 1200 s, so the window is
  10:00:00–10:20:00. No distance.
- **10:30:00 — log e-r1.** After advancing to sx-bjj: round length dialled to 300 s with no
  countdown running, so the window is 10:25:00–10:30:00, roundNumber 1. The follow-on countdown
  starts at 10:30:00, planned 300 s.
- **10:32:00 / 10:34:00.** The round timer is paused, then resumed.
- **10:37:05 — log e-r2.** The countdown completed at 10:37:00, so the window is
  10:30:00–10:37:00, roundNumber 2, `pausedMs` 120000. The next countdown starts at 10:37:05.
- **10:42:10 — log e-r3.** The countdown completed at 10:42:05, so the window is
  10:37:05–10:42:05, roundNumber 3.
- **10:45:00, 10:48:00, 10:51:00 — log e-set1, e-set2, e-set3** (after advancing to sx-bench):
  5 reps × 80 kg each.
- **10:55:00 — wrist End.** At 10:55:20 the user answers **4**.

**Expected wrist events (case `full`, store order):**

| Entry | Summary fields | Derivation |
|---|---|---|
| e-run | avg 140, max 160, steps 3200 | Samples 120/140/160 are in the window. Steps chain 0→800→1600→3200; the 3300 at 10:30 is outside the window |
| e-r1 | avg 160, max 170 | 150 and 170 are in the window; the 100 at 10:24:30 is before it |
| e-r2 | avg 165, max 180, `pausedMs` 120000 | 150 and 180. The 100 at 10:33 falls in the pause [10:32, 10:34), so it is excluded. Including it would give 143.33 |
| e-r3 | avg 155, max 165 | 145 at the window start (inclusive) and 165. The 175 at 10:42:08 is after the window end |
| e-set1, e-set2, e-set3 | none | Set events never carry HR |
| end-s-cap-1 | completed, 10:00:00–10:55:00, avg 143, max 180; setBlock sx-bench/ex-bench 10:42:10–10:51:00, avg 130, max 150 | Session: 15 positive samples summing to 2145. Block span starts at e-r3's loggedAt, so the 175 at 10:42:08 is excluded; 110/130/150 count; the 0 is ignored; 10:51:00 is inclusive |
| rating-s-cap-1 | rating 4, loggedAt 10:55:20 | — |

No round carries steps, even though the steps sample at 10:30:00 lies in e-r1's and e-r2's
windows.

**Case `no-sensors`.** Same timeline with HR and steps permission denied, so there are no
samples. No event carries a summary field. `end-s-cap-1` has no average/maximum and no
`setBlockHeartRates`.

**Case `prompt-off`.** Same as `full`, but the preferences say `false`. There is no
`rating-s-cap-1` event, so there are 8 events.

**Expected phone import (case `full`).**
- `TrainingSession` `s-cap-1`: 10:00:00–10:55:00, modality null, `sessionFeeling` 4.
- Efforts, in order:
  - timed ex-run: one `TimedInstance`, 10:00:00–10:20:00, 1200 s, distance 0, extra-weight 0;
  - round ex-bjj: three `RoundInstance`s of 300 s each, with #1 carrying a paused total of
    120000;
  - set ex-bench: three sets of 5 × 80.0, with no extra-weight observation because ex-bench has
    `load`.
- Six `SensorSummary` rows:

  | Scope | Target | avg | max | Other |
  |---|---|---|---|---|
  | session | s-cap-1 | 143 | 180 | |
  | effort | the bench effort | 130 | 150 | |
  | timed_instance | the run | 140 | 160 | steps 3200 |
  | round_instance | round #0 | 160 | 170 | |
  | round_instance | round #1 | 165 | 180 | |
  | round_instance | round #2 | 155 | 165 | |

- The union of receipted `entryId`s is exactly the 9 events.

In case `no-sensors`: zero `SensorSummary` rows. In case `prompt-off`: `sessionFeeling` null
and 8 receipted `entryId`s.

### Phase 1 — Protocol and contracts

**S-201 — Capture fields conform on every client**
- **Fixture:** `fixtures/valid/observations_up_session_capture.json`, session `s-cap-fx`. Events:
  - a legacy `set` 5×80 with no new fields (adversarial);
  - a `timed` event with avg 140, max 160, steps 3200;
  - a `round` event with avg 165, max 180, `pausedMs` 120000;
  - a `hold` event with avg 120, max 130;
  - `effort_rating` 4;
  - `session_end` (completed, avg 143, max 180, one set block 130/150).
- **Trigger:** the manifest walk.
- **Expected:** both validators report zero rejections. The Dart and Swift wrist emission
  pipelines each emit one conformant envelope per event, so the Dart wrist accepts them.
- **Edge case of:** none.

**S-202 — Malformed capture data is refused before storage**
- **Fixture:** one file per offence under `fixtures/invalid/`, each containing only the
  offending event (F-17):
  - steps on a round;
  - HR on a set;
  - avg 0;
  - avg above max;
  - avg without max;
  - rating 6;
  - `session_end` without `endedAt`;
  - `pausedMs` on a timed event;
  - `setBlockHeartRates` on a timed event;
  - `preferences_down` missing `effortRatingPrompt`;
  - a snapshot with a `set` entry missing its slot.
- **Trigger:** the manifest walk.
- **Expected:** each file is rejected with the manifest's code and reason substring, identically
  on both validators. Neither wrist engine stores or emits it.
- **Edge case of:** S-201.

**S-203 — Session-scoped entries in snapshots**
- **Fixture:** `valid/session_snapshot_session_capture.json`, a wrist snapshot whose entries
  are a slotted set, an `effort_rating` and a `session_end`.
- **Expected:** valid on both validators. The slot-less-set invalid fixture from S-202 is still
  refused.
- **Edge case of:** S-201.

**S-204 — `preferences_down` conforms, and the Dart wrist ignores it**
- **Fixture:** `valid/preferences_down.json` (effortRatingPrompt false).
- **Trigger:** the Dart `WatchSyncOrchestrator.receive`.
- **Expected:** it returns false (not applied), and the Dart wrist store is unchanged.
- **Edge case of:** none.

**S-205 — A snapshot for another session replaces it**
- **Fixture:** `reconciliation/session_switch.json`. Initial snapshot: `s-sw-a`, completed,
  ladder [sx-a], entries [e-a1 set]. Stream: a wrist snapshot for `s-sw-b`, active, ladder
  [sx-b], entries [e-b1 set].
- **Expected:** on the phone reconciler, the Dart wrist and the Swift wrist, the state is
  `s-sw-b`, ladder [sx-b], entries [e-b1] only. The cross-stack structure comparison agrees.
- **Edge case of:** none.

**S-206 — `steps` is in the shared sensor vocabulary**
- **Fixture:** the updated sensor contract (`kinds` gains `steps`; `sampleUnits.steps` is
  `cumulativeCount`).
- **Expected:** the existing equality tests pass unchanged on both stacks.

**S-207 — The capture contract conforms**
- **Fixture:** F-CAP's three cases.
- **Expected:** every `expectedEvents` entry, wrapped as a wrist `observations_up`, validates on
  both stacks.

### Phase 4b — The rating on the wrist

**S-211 — Prompt owed and answered**
- **Fixture:** preferences {true, generatedAt 09:00}; wrist session `s-r-1` (one slot `sx-bench`,
  with `e-1` set logged).
- **Trigger:** End at 10:10:00 via the End control's state.
- **Expected:**
  - exactly one `session_lifecycle` completed and one `session_end` are emitted;
  - a prompt is owed for `s-r-1`;
  - the prompt's title, labels and scale equal `watch_effort_rating_contract.json`;
  - the state exposes no skip or dismiss;
  - Confirm is disabled while nothing is selected;
  - selecting 4 and confirming appends exactly one `effort_rating` {rating 4, id
    `rating-s-r-1`, loggedAt = the confirm instant}, after which the prompt is no longer owed.

**S-212 — Setting off.** Same as S-211 with preferences {false}. **Expected:** no prompt owed and
no `effort_rating`; `session_end` is present.

**S-213 — Never synced.** Same as S-211 with no preferences record. **Expected:** no prompt owed.

**S-214 — The setting arrives at sync and is honoured from then on**
- **Fixture:** preferences {false, T1 = 09:00}.
- **Flow:**
  1. End session A.
  2. Apply {true, T2 = 09:30}, then End session B.
  3. Apply {false, T1} again (stale), then End session C.
- **Expected:** A is not owed; B is owed; C is owed.

**S-215 — Kill during the prompt**
- **Fixture:** as S-211.
- **Flow:** End, discard the engine, restore a new engine over the same store, then confirm 2.
- **Expected:** after the restore, a prompt is owed for `s-r-1`. Exactly one `effort_rating` is
  written (rating 2). Across both processes there is exactly one lifecycle "completed".
- **Edge case of:** S-211.

**S-216 — The phone ended it via lifecycle**
- **Fixture:** wrist session `s-r-2`, active, with `e-1`.
- **Trigger:** apply a phone `session_lifecycle` completed with `at` 10:20:00.
- **Expected:** no prompt is owed. `session_end` has `endedAt` 10:20:00. No `effort_rating`.

**S-217 — The phone ended it via snapshot**
- **Fixture:** wrist session `s-r-3`, active.
- **Trigger:** apply a phone snapshot with status completed and `sentAt` 10:30:00, twice.
- **Expected:** not owed. Exactly one `session_end`, with `endedAt` 10:30:00.

**S-218 — The wrist never changes an existing rating**
- **Fixture:** the end state of S-211.
- **Flow:** a second confirm; then a phone lifecycle "started" reopens the session, `e-2` is
  logged, and the wrist Ends again.
- **Expected:** no new `effort_rating`, no second `session_end`, and no prompt owed.

**S-219 — Crown and tap mapping.** Starting from "unselected":
- +1 detent → 1;
- +3 → 4;
- +5 → 5 (clamped);
- −10 → 1 (clamped);
- tap 3 → 3.

Confirm is disabled only before the first selection. Detent size is `WatchMetricStepping.pointsPerDetent`.

**S-220 — Empty session**
- **Fixture:** preferences true; a session with no entries. A second variant has one set the
  phone deleted live.
- **Expected:** End → no prompt owed.

### Phase 4a — Summaries, steps, session end, resend and prune gate on the wrist

**S-231 — The run.** F-CAP e-run carries exactly avg 140, max 160, steps 3200, and no `pausedMs`.

**S-232 — The rounds.** F-CAP e-r1 160/170; e-r2 165/180 with `pausedMs` 120000; e-r3 155/165.
No round carries steps.

**S-233 — The set block.** F-CAP `end-s-cap-1` carries `setBlockHeartRates` [sx-bench/ex-bench,
10:42:10–10:51:00, 130/150]. Set events carry no HR.

**S-234 — The session**
- F-CAP `end-s-cap-1` covers 10:00:00–10:55:00 with 143/180.
- **Variant:** a phone lifecycle completion with `at` 10:20:00 is applied at 10:25:00 on a
  session with samples at 10:18 (130) and 10:22 (200). The session summary is 130/130: 10:22 is
  after `endedAt`.

**S-235 — No samples**
- F-CAP `no-sensors`: no HR or steps field anywhere; `session_end` has neither average/maximum
  nor `setBlockHeartRates`.
- **Variants:**
  - a timed entry with HR samples but no steps samples → HR present, steps absent;
  - a timed entry whose only in-window steps sample equals the baseline → `steps` 0 present.

**S-236 — A hold**
- **Fixture:** slot `sx-plank` (ex-plank [time, hold]); a hold logged at 11:01:00 with a dialled
  60 s, so the window is 11:00:00–11:01:00. Samples: 11:00:30 125, 11:01:00 135, 11:01:30 200.
- **Expected:** avg 130, max 135.

**S-237 — Summaries before the prune**
- **Fixture:** the F-CAP end state.
- **Flow:**
  1. Confirm the 7 effort entries → prune releases 0.
  2. Also confirm `rating-s-cap-1` → still 0.
  3. Confirm `end-s-cap-1` → all of the session's samples are released.
- **Structural variant:** a completed wrist-created session seeded without any `session_end`
  is never released.

**S-238 — Never rewritten**
- **Fixture:** after e-run is logged, append a late HR sample at 10:19:59 (inside its window);
  relaunch.
- **Expected:** `pendingObservations` re-emits e-run with the original 140/160. `end-s-cap-1` is
  not recomputed on relaunch.

**S-239 — No regression**
- **Fixture:** the existing sensor suites, run with steps permission granted and with it denied.
- **Expected:**
  - the HR and distance readouts are identical;
  - the GPS subscription decision is identical;
  - the platform workout begin/end call sequence is identical;
  - stop cancels the steps subscription;
  - appending any sample, `steps` included, emits nothing;
  - `testAReadingIsStoredWithoutBeingSentAnywhere` is unchanged.

**S-240 — Resend across sessions**
- **Fixture:** session A (one set, ended offline, unconfirmed); session B started later (one
  set).
- **Expected:** `pendingObservations` holds A's events, then B's, in store order. A receipt for
  A's ids removes them.

### Phase 3a — Phone mirror, preferences and the live screen

**S-251 — Clean switch**
- **Fixture:** the mirror holds `s-prev` (completed; ladder [sx-p]; entries [e-p1]), with
  `completedRecord` set by the phone's Finish.
- **Trigger:** a wrist snapshot for `s-next` (active; ladder [sx-b]; entries [e-b1]).
- **Expected:**
  - the mirror is on `s-next` with entries [e-b1] only;
  - `completedRecord` is null;
  - the transport sent nothing;
  - a subsequent Finish produces a record for `s-next`.

**S-252 — Same-session disagreement still re-asserts.** The existing S-008 tests in
`test/live_mirroring_test.dart` stay unchanged and green.

**S-253 — The phone answers with preferences**
- **Fixture:** no routines; the setting is off.
- **Flow:** the wrist sends a `routines` request; then the setting is turned on, a routine is
  seeded, and the wrist asks again.
- **Expected:** the first request yields exactly [`preferences_down` {false}]. The second yields
  [`preferences_down` {true}, `routines_down`], in that order. `generatedAt` is the phone clock
  at send.

**S-254 — Effort entries only.** The mirror's entries are [e-1 set, rating-x, end-x]. The
LOGGED list shows one row (`live_session_entry_e-1`), the status reads "1 logged", and the
completed card counts 1.

### Phase 3b — The phone inbox and import

**S-261 — Import from the offline stream.** F-CAP `full`: nine `observations_up` envelopes (one
event each, origin watch, session `s-cap-1`) pass through the router against the Mock
repository. **Expected:** exactly F-CAP's "Expected phone import". The receipts are sent after
the rows exist, and their union is the 9 `entryId`s. Also run `no-sensors` and `prompt-off`.

**S-262 — Arrival order doesn't matter.** Four orders: contract order, reversed, `session_end`
first, and rating first. **Expected:** identical repository state and receipt union in every
order.

**S-263 — Redelivery.** Deliver F-CAP twice, the second time with an altered e-run (avg 999).
**Expected:** no new rows, no changed values, and no second calendar refresh.

**S-264 — The phone's value is final**
- **Main case:** import F-CAP (4) → the phone writes 2 through the repository's existing rating
  update → redeliver all 9 events plus an altered `rating-s-cap-1` (5). **Expected:** 2, and
  the summaries are unchanged.
- **Variant:** deliver the 8 non-rating events (imported, null) → the phone writes 2 → the rating
  4 arrives. **Expected:** 2.

**S-265 — Abandoned.** `s-ab-1` has one set `e-ab1` and a `session_end` with status abandoned.
**Expected:** no `TrainingSession`; staged rows applied; the receipt carries [e-ab1,
end-s-ab-1].

**S-266 — Tombstones**
- **Main case:** import F-CAP → delete the session on the phone → redeliver the 9 events plus a
  late `e-late` set. **Expected:** no session re-created; `e-late` receipted and dropped.
- **Variant:** delete `e-set2`'s observation rows through the phone's edit path, then redeliver.
  **Expected:** `e-set2` rows are not re-created.

**S-267 — Live corrections**
- **Flow:**
  1. The mirror holds `s-cap-1` live and sends `correct_entry(e-set2, {reps: 6})` and
     `delete_entry(e-set3)`.
  2. The phone restarts (a new inbox over the same repository), then the F-CAP events arrive.
- **Expected:** the bench effort has 2 sets (5×80, 6×80) and nothing for e-set3.
- **Variant:** a correction staged after import (`e-set1` reps 4) updates the imported row.

**S-268 — Two offline sessions**
- **Fixture:**
  - `s-off-a`: created 08:00:00; e-a1 set 5×60 on ex-bench at 08:05:00; End 08:10:00; rating 3.
  - `s-off-b`: created 09:00:00; e-b1 set 5×70 at 09:05:00; End 09:10:00; rating 5.
  - No HR. The mirror holds a completed `s-prev` with e-p1.
- **Trigger:** a wrist sync sends A's 3 events and B's 3 events (D-128), then B's snapshot.
- **Expected:** the mirror is on `s-off-b` with its entries only, and nothing was sent back. The
  repository has `s-off-a` (3, one set 5×60) and `s-off-b` (5, one set 5×70), with nothing from
  `s-prev`.

**S-269 — No sensors.** F-CAP `no-sensors` imports the session with zero `SensorSummary` rows
and no zero-valued field anywhere.

**S-270 — Health write**
- **Fixture:** a recording fake for `HealthSyncService`.
- **Flow:**
  1. A phone session is logged and finished.
  2. F-CAP is imported, `loadHistoricalSession(s-cap-1)` runs, then `endSession()`.
- **Expected:** after step 1 there is exactly one write (unchanged behaviour). The total after
  step 2 is still one.

**S-271 — Calendar liveness.** With the calendar month 2026-09 loaded, import F-CAP.
**Expected:** exactly one refresh, and the month contains `s-cap-1`. Redelivery triggers no
refresh.

**S-272 — Parity.** Run S-261 against Hive (temp dir) and Mock. **Expected:** every created row
(session, segment, efforts, observations, instances, summaries, staged rows) is equal by
`toMap`.

**S-273 — Empty completed session.** `s-empty-1` is completed with no effort entries and a
rating of 3. **Expected:** nothing imported; the receipt carries [end-s-empty-1,
rating-s-empty-1].

**S-274 — Shape parity with phone logging**
- **Fixture:** through `WorkoutState`, the phone logs:
  - a set 5×80 on a load exercise (ex-bench);
  - a set on a no-load exercise (ex-pushup [sets, reps]);
  - a timed entry on ex-run;
  - a drill on ex-plank;
  - a round on ex-bjj.

  The equivalent wrist events are then imported.
- **Expected:** per row, these are equal except ids and timestamps: effort kind, metric id,
  unit id, value fields, observation-id pattern, the set of companion observations, and
  instance state and fields.

### Phase 5 — The phone-ended prompt and the Summary (after PR 1)

**S-281 — Phone Finish, setting on.** The mirror holds `s-live-1` active with e-1. The phone's
Finish shows PR 1's sheet; the user can't dismiss it and answers 3. **Expected:** the rating is
staged as the phone's own. After F-CAP-style import with a wrist `effort_rating` 5 also
present, `sessionFeeling` is 3. The wrist owes no prompt (S-216).

**S-282 — Phone Finish, setting off.** **Expected:** no sheet.

**S-283 — The wrist ended it.** The mirror's `s-live-2` was completed by the wrist's lifecycle.
**Expected:** the screen shows the completed state, no Finish control, and no sheet.

**S-284 — Answered after import.** The phone Finish happens and the import lands before the
answer. **Expected:** the answer (2) is written directly to `sessionFeeling`.

**S-285 — The Summary offers to add.** An imported watch session with no rating, opened from the
calendar, offers PR 1's add-rating control. Adding 4 persists and survives reopening.

**S-286 — The Summary shows the wrist rating.** Imported F-CAP (4), opened from the calendar,
shows rating 4 as PR 1 displays ratings.

**S-287 — Copy parity.** PR 1's sheet title, end labels and scale equal
`watch_effort_rating_contract.json`.

### Phase 6 — Docs, gate and residue

**S-291 — Docs contract.** `test/docs_indexing_contract_test.dart` passes. The new doc is
reachable and under the warning band, and `services_and_utils.md` stays under the band.

**S-292 — Residue sweep.** Every command in Phase 6 item 5 is run and its output pasted, each
matching the expected result.

**S-293 — The gate runs `swift test`** (if D-144 stands). The pre-release gate runs it and
blocks on failure; the gate tests pass.

---

## Iteration 1

### Common procedures (every phase)

- **Baseline.** Before the first change on this branch, record the following in Progress ›
  Baseline, with the summary lines pasted:
  - `flutter analyze`;
  - `flutter test` (full);
  - `cd watch/watchos && swift test`;
  - `git status --porcelain`.

  The main tree's figures (2817 passed / 1 skipped, and 148 Swift tests) do not apply to this
  worktree until re-measured here. For the review-fix round, re-measure on `develop` before the
  first change; the handoff figures are in "## Progress › Review fix round".
- **Counting.** Every phase pastes the full-suite summary line for `flutter test`
  (`+N ~S -F: …`) and for `swift test` ("Executed N tests, with 0 failures"). Deltas are
  explained against the previous phase: new tests added, tests updated. A hang or timeout is a
  failure.
- **Red→green, with copy-and-restore and never `git stash`** (the stash is shared across
  worktrees). For every new behaviour test:
  1. Run `shasum <impl file>`, then `cp <impl file> "$TMPDIR/pr2-redgreen/<name>.bak"`.
  2. Revert **only** the behaviour under test to its pre-change behaviour, keeping signatures
     so the code compiles.
  3. Run that single test (`flutter test <file> --plain-name "<name>"` or
     `swift test --filter <Class>/<method>`). It must fail **on an assertion that cites its
     S-id**. A compile error does not count as red.
  4. `cp` the backup back, and prove the restore with a matching `shasum`.
  5. Re-run the test; it passes.
  6. Paste the evidence into the phase's red→green table: test, S-id, failing assertion line,
     passing line.
- **No relaxed assertions.** Every modified pre-existing assertion goes into the phase's
  assertion-change table (file:line, before, after, rule or D-id). An assertion may change to a
  new exact expectation. It may never be loosened. Loosening includes:
  - equality turned into contains or matches;
  - an exact count turned into a greater-than-or-equal;
  - a removed `expect` or `XCTAssert`;
  - an added `skip:` or `XCTSkip`;
  - a widened tolerance;
  - an assertion commented out.
- **Footprint.** Compare `git status --porcelain` at phase start and end against the phase's
  Predicted Files. An extra file is a finding and needs an Assumption Log entry, and so does a
  predicted file left untouched.
- **Docs.** Every doc edit follows `docs/documentation_standard.md`: structure,
  rationale, invariants with enforcement, and vocabulary only. No flows, UI descriptions,
  restated numbers or copied field lists.
- **Ambiguity.** Never stop on ambiguity: decide, log it in ## Assumption Log, and continue. A
  contradiction with a D-entry, or a failure of `lib/watch/` on a new shared fixture (which
  would breach D-101), goes to ## Feedback. Leave that item open and continue with the rest.

### Phase 1: Protocol and shared contracts (@developer)

Implements D-112, D-113, D-116, D-120 – D-127 (the wire part) and D-130 (the entry rule).

1. [x] Record the Baseline, unless Phase 2 already recorded it.
2. [x] `watch/sync_protocol/schemas/envelope.schema.json`:
   - add `preferences_down` to `type`;
   - add `effort_rating` and `session_end` to `entry.kind`;
   - add these `entry` properties:
     - `rating` (integer 1–5);
     - `status` (`completed` or `abandoned`);
     - `modality` (string, minLength 1);
     - `avgHeartRateBpm` and `maxHeartRateBpm` (number, minimum 1);
     - `steps` (integer, minimum 0);
     - `pausedMs` (integer, minimum 0);
     - `setBlockHeartRates` (array, minItems 1, of closed objects with required
       `sessionExerciseId`, `exerciseId`, `startedAt`, `endedAt`, `avgHeartRateBpm`,
       `maxHeartRateBpm`, each typed as above).
3. [x] `watch/sync_protocol/schemas/messages/observations_up.schema.json`: add `oneOf` variants
   `effort_rating` (requires kind and rating) and `session_end` (requires kind, startedAt,
   endedAt and status).
4. [x] New `watch/sync_protocol/schemas/messages/preferences_down.schema.json`: origin const
   `phone`; payload `{generatedAt: timestamp, effortRatingPrompt: boolean}`, both required and
   closed.
5. [x] Semantic rules, identical codes and wording in `lib/core/sync_protocol/message_validator.dart`
   **and** `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`, applied to
   `observations_up` events and snapshot entries alike:
   - `steps` appears only on timed events;
   - HR fields appear only on timed, round, hold and `session_end`; they are both or neither,
     with average ≤ maximum;
   - `pausedMs` appears only on rounds, and is ≤ `endedAt − startedAt`;
   - `setBlockHeartRates` appears only on `session_end`; each item has average ≤ maximum; slots
     are unique;
   - `rating` appears only on `effort_rating`;
   - `status` and `modality` appear only on `session_end`;
   - the snapshot entry-identity rule also exempts `effort_rating` and `session_end` (see
     `_entryIdentityRejections` and `entryIdentityRejections`);
   - add `preferences_down` to both `messageTypes` lists.
6. [x] `lib/core/sync_protocol/session_reconciler.dart`: a snapshot whose `sessionId` differs
   from the held one starts from its own entries (D-130 entry rule). Keep the cross-stack comment.
7. [x] Fixtures, each registered in `watch/sync_protocol/fixtures/manifest.json` with a scenario
   ID:
   - valid: `preferences_down.json`, `observations_up_session_capture.json`,
     `session_snapshot_session_capture.json` (S-201, S-203, S-204);
   - invalid: the eleven files of S-202, each containing only its offending event, with
     `expectedCode` and `expectedReasonContains` set to what both validators actually produce;
   - reconciliation: `session_switch.json` (S-205).
8. [x] Contracts:
   - `watch/contract/watch_sensor_contract.json`: add `steps` to `kinds` and `steps:
     cumulativeCount` to `sampleUnits`, and describe the unit.
   - New `watch/contract/watch_effort_rating_contract.json`: title, labels {1: "Very easy",
     5: "Max effort"}, scale {min 1, max 5}, the preference key, and "no prompt before the first
     sync" (D-114).
   - New `watch/contract/watch_capture_contract.json`: F-CAP with cases `full`, `no-sensors`
     and `prompt-off`. Each case has a `timeline` (op vocabulary suggestion: `preferences`,
     `start`, `hr`, `steps`, `dial`, `log`, `advance`, `pauseRound`, `resumeRound`, `end`,
     `answer`), `expectedEvents` and `expectedImport`, plus a `derivation` note per summary value
     copied from the F-CAP table so a reviewer can recheck the arithmetic.
9. [x] Vocabulary constants: Swift `WatchSensorKind.steps` (plus `all`) in `WatchRecords.swift`,
   and Dart `WatchSensorKind.steps` (plus `all`) in `lib/watch/session/watch_records.dart` (D-127,
   the only `lib/watch/` edit).
10. [x] Tests:
    - new `test/watch_capture_contract_conformance_test.dart`, covering S-207 (every contract
      event validates) and S-204 (the Dart wrist ignores `preferences_down`);
    - a Swift conformance test for S-207 in `SyncProtocolFixturesTests.swift`, with loaders in
      `Fixtures.swift`;
    - the manifest-walking suites cover S-201 – S-203 and S-205 without edits
      (`test/sync_protocol_fixtures_test.dart`, `test/live_mirroring_test.dart`,
      `test/watch_reconciliation_cross_stack_test.dart`, `test/watch_session_engine_test.dart`,
      and Swift `SyncProtocolFixturesTests` and `WatchLiveMirroringTests`).
11. [x] `watch/sync_protocol/PROTOCOL.md`:
    - add a `preferences_down` row to the message table and its notes, including the
      newest-wins rule;
    - add session-scoped kinds and amend "Every observation event is self-contained";
    - define the summary fields (wrist-computed from its own readings; absent means not
      measured, never zero; which kinds carry which fields);
    - state one rating and one `session_end` per wrist session, and that the phone accepts a
      wrist rating but keeps its own (authority rule 4 clarified);
    - add the resend rule (D-128);
    - add the session switch to "Idempotency and reconciliation" (D-130);
    - add the Version history row (D-112).

**Done Criteria** (run until green; paste into Progress):
- `flutter analyze`: no new diagnostics against the Baseline.
- `flutter test`: full summary line, 0 failures.
- `cd watch/watchos && swift test`: "Executed N tests, with 0 failures".
- Phase suites: `flutter test test/sync_protocol_fixtures_test.dart test/live_mirroring_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_session_engine_test.dart test/watch_sensor_recording_test.dart test/watch_capture_contract_conformance_test.dart`.
- Red→green evidence for: S-201 (revert one new schema property → the valid fixture is
  refused); each S-202 semantic rule (revert the rule → its fixture is accepted); S-203; S-205
  (revert the reconciler rule → the phone keeps e-a1); S-207.
- An empty assertion-change table, or justified entries.
- No file under `lib/watch/` changed except `watch_records.dart` (D-127). Prove it with
  `git status --porcelain lib/watch`.

**Predicted Files:**
- `watch/sync_protocol/PROTOCOL.md`
- `watch/sync_protocol/schemas/envelope.schema.json`
- `watch/sync_protocol/schemas/messages/observations_up.schema.json`
- `watch/sync_protocol/schemas/messages/preferences_down.schema.json` (new)
- `watch/sync_protocol/fixtures/manifest.json`
- `watch/sync_protocol/fixtures/valid/{preferences_down,observations_up_session_capture,session_snapshot_session_capture}.json` (new)
- `watch/sync_protocol/fixtures/invalid/*` (11 new)
- `watch/sync_protocol/fixtures/reconciliation/session_switch.json` (new)
- `watch/contract/watch_sensor_contract.json`
- `watch/contract/watch_effort_rating_contract.json` (new)
- `watch/contract/watch_capture_contract.json` (new)
- `lib/core/sync_protocol/message_validator.dart`
- `lib/core/sync_protocol/session_reconciler.dart`
- `lib/watch/session/watch_records.dart`
- `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`
- `test/watch_capture_contract_conformance_test.dart` (new)
- `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/Fixtures.swift`

**Phase 1 verification notes (@developer, 2026-09-25):**

Full suites, after the change (Baseline in Progress):

| Check | Baseline | After Phase 1 | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` (0 errors / 11 warnings / 231 infos) | `242 issues found.` — a line-number-insensitive diff of the diagnostics against the Baseline is empty | No new diagnostics |
| `flutter test` | `01:15 +2823 ~1: All tests passed!` | `01:05 +2863 ~1: All tests passed!` | +40, all new: 20 manifest-walk cases in `sync_protocol_fixtures_test.dart` (3 valid + 17 invalid), 2 in `live_mirroring_test.dart` (phone + watch replay of `session_switch.json`), 1 in `watch_reconciliation_cross_stack_test.dart`, 17 in the new `watch_capture_contract_conformance_test.dart`. No existing test changed |
| `cd watch/watchos && swift test` | `Executed 148 tests, with 0 failures` | `Executed 149 tests, with 0 failures (0 unexpected) in 0.344 (0.352) seconds` | +1: `SyncProtocolFixturesTests.testS207EveryCaptureContractEventConformsAsTheWristSendsIt`. The new fixtures ride the existing manifest walks |
| Phase suites (the six Done-Criteria files) | — | `00:00 +190: All tests passed!` | — |
| `git status --porcelain lib/watch` | empty | ` M lib/watch/session/watch_records.dart` | D-127 only |

Red run before any implementation (tests and fixtures written first): the six Dart phase files gave
`+163 -27: Some tests failed.` and `swift test` gave `Executed 149 tests, with 78 failures (1 unexpected)`.
Every failure was a new fixture, S-207, S-204 conformance, the session-switch replay on the phone, or the
S-206 kind equality. `S-204 … the Dart wrist ignores it` passed before any change, as it should (D-101: the Dart
wrist gains no behaviour); its red below is by mutation.

Red→green, by copy-and-restore, never `git stash` (harness: copy the file aside, apply one mutation, run
one test, `cp` back, prove the restore with a matching `shasum` and `cmp`, re-run). Every restore
matched its pre-mutation hash. The manifest-walk tests are named after the fixture path; the manifest
registers each path under its S-id (`scenario`), which is how a failure there cites the scenario.
Dart reds on an invalid fixture fail `expect(rejections, isNotEmpty, reason: 'an invalid fixture must
not conform')` (`Expected: non-empty / Actual: []`); Swift reds fail `XCTAssertFalse … must not conform`.

| # | S-id | Behaviour reverted (file) | Red — failing test and assertion | Green |
|---|---|---|---|---|
| 1 | S-201 | `steps` removed from `entry` properties (envelope schema) | Dart `S-001 fixtures valid/observations_up_session_capture.json conforms …` `Expected: empty`; Swift `testEveryValidFixtureConforms`: `unexpected_field at $.payload.events[1].steps` | `+1: All tests passed!` / `Executed 1 test, with 0 failures` |
| 2 | S-202 | `steps` placement (both validators) | `invalid/observations_up_steps_on_round.json` accepted — Dart `+0 -1`, Swift `must not conform` | both green |
| 3 | S-202 | heart-rate placement | `invalid/observations_up_heart_rate_on_set.json` accepted on both | both green |
| 4 | S-202 | heart-rate pair travels together | `invalid/observations_up_heart_rate_avg_without_max.json` accepted on both | both green |
| 5 | S-202 | average ≤ maximum (entry) | `invalid/observations_up_heart_rate_avg_above_max.json` accepted on both | both green |
| 6 | S-202 | average ≤ maximum (set block; same rule) | `invalid/observations_up_set_block_avg_above_max.json` accepted on both | both green |
| 7 | S-202 | `pausedMs` placement | `invalid/observations_up_paused_ms_on_timed.json` accepted on both | both green |
| 8 | S-202 | `pausedMs` ≤ window | `invalid/observations_up_paused_ms_exceeds_window.json` accepted on both | both green |
| 9 | S-202 | `setBlockHeartRates` placement | `invalid/observations_up_set_blocks_on_timed.json` accepted on both | both green |
| 10 | S-202 | set blocks unique | `invalid/observations_up_set_block_repeated.json` accepted on both | both green |
| 11 | S-202 | `rating` placement | `invalid/observations_up_rating_on_set.json` accepted on both | both green |
| 12 | S-202 | `status` placement | `invalid/observations_up_status_on_timed.json` accepted on both | both green |
| 13 | S-202 | `modality` placement | `invalid/observations_up_modality_on_timed.json` accepted on both | both green |
| 14 | S-202 | heart-rate `minimum: 1` (envelope schema) | `invalid/observations_up_heart_rate_zero.json` accepted on both | both green |
| 15 | S-202 | `rating` `maximum: 5` (envelope schema) | `invalid/observations_up_rating_out_of_range.json` accepted on both | both green |
| 16 | S-202 | `endedAt` required on `session_end` (observations_up schema) | `invalid/observations_up_session_end_missing_ended_at.json` accepted on both | both green |
| 17 | S-202 | `effortRatingPrompt` required (preferences_down schema) | `invalid/preferences_down_missing_effort_rating_prompt.json` accepted on both | both green |
| 18 | S-203 | identity exemption for `effort_rating`/`session_end` (both validators) | `valid/session_snapshot_session_capture.json` refused: `a workout entry must name the exercise it logged and the slot it logged it in; missing on end-s-cap-snap, rating-s-cap-snap` (Dart and Swift) | both green |
| 19 | S-204 | `preferences_down` removed from Dart `messageTypes` | `S-204 preferences_down conforms to the protocol` — `Expected: empty`, reason `S-204 preferences_down must conform` | `+1` |
| 20 | S-204 | Dart wrist orchestrator made to apply `preferences_down` (`lib/watch/start/watch_sync_orchestrator.dart`, restored; hash `477a968…` matched) | `S-204 … the Dart wrist ignores it and stores nothing` — `Expected: false / Actual: <true>`, reason `S-204 the Dart wrist has no use for preferences_down` | `+1` |
| 21 | S-205 | switch rule removed from `session_reconciler.dart` | `S-004 every reconciliation fixture converges …` and `phone: reconciliation/session_switch.json converges …`: `Which: at location ['entries'][0]['entryId'] is 'e-a1' instead of 'e-b1'` (the phone keeps e-a1) | both `+1` |
| 22 | S-206 | `steps` removed from `WatchSensorKind.all` (Dart, then Swift) | Dart `Actual: ['hr', 'gps', 'distance'] / Expected: equals [… 'steps'] unordered`; Swift `testTheSampleKindsAreTheOnesBothClientsAgreedOn` `XCTAssertEqual failed` | both green |
| 23 | S-207 | `setBlockHeartRates` removed from `entry` properties (envelope schema) | Dart `S-207 … full: every expected event … accepts` `Expected: empty`; Swift `testS207…`: `S-207 full: end-s-cap-1 must conform, got [unexpected_field …setBlockHeartRates…]` (full and prompt-off) | both green |

Assertion-change table: **empty.** No pre-existing assertion, expectation or fixture was modified.
`testS004NoMutatingOperationExistsAnywhereInTheModule` stayed unedited: it caught a first draft's
`setBlockRejections` (a func name starting with the guarded verb "set"), and the helper was renamed
`blockHeartRateRejections` on both stacks instead.

Footprint versus Predicted Files: every predicted file was touched. Extra: six invalid fixtures beyond
S-202's eleven (A-2). Nothing else outside the list; the plan file itself carries Progress.

Known intermediate state (Notes › Intermediate states, "After P1"): PROTOCOL.md now says a receiver
MUST NOT answer a snapshot for another session, but `LiveSessionMirrorState` still re-asserts the held
session until Phase 3a. The phone *reconciler* already switches cleanly (S-205).

### Phase 2: Phone data layer for staging and summaries (@dba)

Implements D-131, D-132 (storage) and the Hive ↔ Mock parity standing rule.

1. [x] Record the Baseline, unless Phase 1 already recorded it.
2. [x] `lib/data/models/models.dart`: add `SensorSummary` (D-131) and `WatchInboxEntry` (D-132)
   with `fromMap`/`toMap`.
   - `WatchInboxEntry` fields: `entryId`, `watchSessionId`, `kind`, `origin` (`watch` or
     `phone`), the event `payload` as a JSON map, `receivedAtMs`, and a nullable `appliedAtMs`.
   - Phone-annotation kinds: `phone_rating`, `phone_correction`, `phone_deletion`, with
     deterministic ids `phone-rating-<sid>` and `phone-change-<changeId>-<index>`.
   - `SensorSummary` enforces its invariants at construction.
   - **Do not edit** `TrainingSession.sessionFeeling` or its comment (PR 1 owns them).
3. [x] `lib/data/repositories/workout_repository.dart`: interface methods (names are free):
   - stage an inbox entry (put-if-absent; reports whether it was stored);
   - read a watch session's staged entries (ordered by `receivedAtMs`, then `entryId`);
   - read one staged entry by `entryId`;
   - mark entries applied (batch);
   - list watch session ids with an unapplied `session_end`;
   - create a sensor summary (put-if-absent by id);
   - read summaries for a session.
4. [x] `lib/data/repositories/hive_workout_repository.dart`: two new boxes. Cascades:
   - `deleteSession` removes its summaries;
   - `deleteEffort`, `deleteTimedInstance`, `deleteTimedInstancesForEffort`,
     `deleteRoundInstance` and `deleteRoundInstancesForEffort` remove summaries that target the
     deleted rows;
   - the inbox is never cascaded (tombstones).
5. [x] `lib/data/repositories/mock_workout_repository.dart`: identical semantics, ordering and
   cascades.
6. [x] `scripts/sqlite_schema.sql`: `app_sensor_summary` and `app_watch_inbox_entry`, with
   indices, the repository→SQL contract comments (in the file's existing style), and CHECK
   constraints wherever SQL can express the D-131 rules (scope enum, average ≤ maximum,
   steps ≥ 0).
7. [x] `test/db_seed_test.dart`: assert both tables exist, and that each new model's `toMap`
   keys are a subset of its table's columns (a structural guard against model↔schema drift).
8. [x] New `test/watch_capture_repository_parity_test.dart`: one scripted sequence run on Hive
   (temp dir, with the `path_provider` channel mock pattern from
   `test/food_library_persistence_test.dart`) and on Mock with identical results. It covers:
   - put-if-absent staging, including an altered duplicate being refused;
   - ordering;
   - mark applied;
   - put-if-absent summaries and the invariant refusals (zero HR, average > maximum, steps on a
     non-timed scope, an empty row);
   - every cascade;
   - the inbox surviving `deleteSession`.
9. [x] Docs: `docs/data_models.md` and `docs/db_integration.md` —
   structure, rationale (D-131's "why not"), and invariants with enforcement. No copied field
   lists and no copied SQL.

**Done Criteria:**
- `flutter analyze`: no new diagnostics.
- `flutter test`: full summary line, 0 failures.
- `cd watch/watchos && swift test`: count unchanged, 0 failures.
- `flutter test test/db_seed_test.dart test/watch_capture_repository_parity_test.dart`.
- Red→green evidence for each invariant refusal and each cascade: remove the check or cascade in
  one repository → its test fails; restore it.
- Parity: the same test body runs against both repositories, with no per-repository expected
  values.
- An assertion-change table.

**Predicted Files:**
- `lib/data/models/models.dart`
- `lib/data/repositories/workout_repository.dart`
- `lib/data/repositories/hive_workout_repository.dart`
- `lib/data/repositories/mock_workout_repository.dart`
- `scripts/sqlite_schema.sql`
- `test/db_seed_test.dart`
- `test/watch_capture_repository_parity_test.dart` (new)
- `docs/data_models.md`
- `docs/db_integration.md`

**Phase 2 verification notes (@dba, 2026-09-25):**

Item 1: the Baseline was recorded by Phase 1 (Progress › Baseline). For this phase's analyzer diff, the
pre-change `flutter analyze` output was re-captured at `ae66f39` before the first edit (242 issues).

Full suites, after the change:

| Check | Start of phase (`ae66f39`) | After Phase 2 | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` | `242 issues found. (ran in 2.7s)`; a line-number-insensitive diff of the diagnostics against the pre-change run is empty | No new diagnostics |
| `flutter test` | `+2863 ~1: All tests passed!` | `01:06 +2901 ~1: All tests passed!` (exit 0) | +38, all new: 34 in `test/watch_capture_repository_parity_test.dart` (15 per repository, 1 cross-repository, 3 model rules) and 4 in `test/db_seed_test.dart`. No existing test changed |
| `cd watch/watchos && swift test` | `Executed 149 tests, with 0 failures` | `Executed 149 tests, with 0 failures (0 unexpected) in 0.344 (0.354) seconds` | Unchanged; nothing under `watch/` changed |
| `flutter test test/db_seed_test.dart test/watch_capture_repository_parity_test.dart` | — | `00:00 +39: All tests passed!` | 5 + 34 |
| `flutter test test/docs_indexing_contract_test.dart` | — | `00:00 +9: All tests passed!` | Two docs edited; `data_models.md` 30,868 B, `db_integration.md` 35,069 B, both under the band |
| `git status --porcelain watch lib/watch` | empty | empty | — |

Line endings: `lib/data/models/models.dart` 2735/2735 lines CRLF, `scripts/sqlite_schema.sql` 1659/1659,
`test/db_seed_test.dart` 580/580. The LF files stay LF. `git diff --numstat` shows additions only for every
file under `lib/`, `scripts/` and `test/` (0 deletions), so no existing line of code changed.

Parity design: `_parityTests` is one test body registered twice (`group('Mock', …)`, `group('Hive', …)`)
through a harness whose `restart()` closes Hive and opens a new repository over the same files; Mock
hands back its store. No expected value depends on the repository. The cross-repository test runs one
scripted sequence on both and compares every inbox row, summary and unapplied-end list by `toMap`, with
Hive read back after a restart.

Red→green, by copy-and-restore, never `git stash`. The harness is
`<scratchpad>/pr2_p2_redgreen.py`, with logs in `<scratchpad>/pr2-redgreen/`. For each case it shasums and
copies the file, applies one textual edit (asserted to match exactly once), runs the one test by
`--plain-name`, copies the backup back, proves the restore with `cmp` and a matching shasum, and re-runs the
test green. After each of the three batches, `shasum -c` over every touched file matched the pre-batch
snapshot, and a scan of every red log found no compile error.
- Phase 2 has no S-ids, so tests and reasons cite D-131 and D-132.
- A plain name matches both repository variants. A one-sided mutation therefore fails exactly its own
  variant (`+1 -1`), and a model mutation fails both (`+0 -2`).

The misses, recorded rather than dropped:
- **#54 `s-roundtrip`** went red on a thrown `DatabaseException`, not on an assertion, because `completes`
  does not turn an error into a matcher failure. The test now captures each insert's outcome
  (`_insertRefusal`) and asserts `isNull` with a D-id reason. #74 is the proper red.
- **#75 `m-finite` and #76 `m-summary-ids` stayed green: a flawed mutation, not a flawed test.**
  `if (false && a || b)` parses as `(false && a) || b`, so half of each guard stayed live. They were
  redone parenthesised as #83 and #84, and both went red. #77's mutation was half-live the same way but
  disabled the half under test; it was redone as #85. No batch-1 mutation had an unparenthesised `||`.
- **#11 and #16–18 went red on their assertions, but those expectations had no `reason:`.** Reasons citing
  D-131 or D-132 were added, and the reds were re-run as #79–82.
- **The inbox tie-break cannot be observed on Hive.** Hive iterates a box in key order, so the `entryId`
  tie-break coincides with Hive's own order. Its red is shown on Mock (#23), and the `receivedAtMs`
  criterion's red on both (#21, #22).
- **Additions for coverage.** The first pass left four guards untested: finite heart rate, empty ids on
  both models, and non-JSON `payload_json`. Expectations were added to existing new tests, with reds #78
  and #83–85.

| # | Key | Reverted (file) | Red: failing variant(s) — assertion | Green |
|---|---|---|---|---|
| 1 | `m-zero-hr` | `avg ≥ 1` guard (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses a zero heart rate` | `+2` |
| 2 | `m-avg-above-max` | `avg ≤ max` guard (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses an average above the maximum` | `+2` |
| 3 | `m-steps-scope` | steps only on `timed_instance` (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses steps on a round` | `+2` |
| 4 | `m-empty` | at-least-one-value guard (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses an empty summary` | `+2` |
| 5 | `m-pair` | HR pair both-or-neither (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses an average without a maximum` | `+2` |
| 6 | `m-neg-steps` | `steps ≥ 0` (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses negative steps` | `+2` |
| 7 | `m-scope-enum` | known-scope guard (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses an unknown scope` | `+2` |
| 8 | `m-session-target` | session scope targets its own session (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses a session summary that targets another session` | `+2` |
| 9 | `m-window` | ordered window (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses a window that ends before it starts` | `+2` |
| 10 | `m-source` | source vocabulary (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses a source other than the watch` | `+2` |
| 11 | `m-stored-id` | `fromMap` stored-id check (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `` | `+1` |
| 12 | `m-kind-vocab` | kind-for-origin vocabulary (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: quick-logs stay with the nutrition bridge` | `+1` |
| 13 | `m-origin` | unknown origin refused (made to fall back to watch kinds) (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: origin is watch or phone` | `+1` |
| 14 | `m-rating-id` | `phoneRatingId` id rule (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: one phone rating per session, under its fixed id` | `+1` |
| 15 | `m-change-prefix` | `phoneChangeId` id rule (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: a phone change is keyed by its changeId and index` | `+1` |
| 16 | `m-json-refusal` | non-JSON payload refused (encoder given `toEncodable`) (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `` | `+1` |
| 17 | `m-payload-object` | payload must be a JSON object (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `` | `+1` |
| 18 | `m-payload-copy` | `payload` returns a copy (made a cached map) (models) | `+0 -1` model rules — Expected: { Which: at location ['avgHeartRateBpm'] is <999> instead of <140> ; reason `` | `+1` |
| 19 | `h-stage` | stage put-if-absent (Hive) | `+1 -1` Hive — Expected: false Actual: <true> ; reason `D-132: a redelivered or altered copy is refused` | `+2` |
| 20 | `k-stage` | stage put-if-absent (Mock) | `+1 -1` Mock — Expected: false Actual: <true> ; reason `D-132: a redelivered or altered copy is refused` | `+2` |
| 21 | `h-order` | inbox order: `receivedAtMs` criterion removed (Hive) | `+1 -1` Hive — Expected: ['end-s-cap-1', 'rating-s-cap- Which: at location [0] is 'e-r1' instead of 'end-s-cap-1' ; reason `D-132: ordered by receivedAtMs, then entryId` | `+2` |
| 22 | `k-order` | inbox order: `receivedAtMs` criterion removed (Mock) | `+1 -1` Mock — Expected: ['end-s-cap-1', 'rating-s-cap- Which: at location [0] is 'e-r1' instead of 'end-s-cap-1' ; reason `D-132: ordered by receivedAtMs, then entryId` | `+2` |
| 23 | `k-order-tie` | inbox order: `entryId` tie-break removed (Mock) | `+1 -1` Mock — Expected: ['end-s-cap-1', 'rating-s-cap- Which: at location [0] is 'rating-s-cap-1' instead of 'end-s-cap-1' ; reason `D-132: ordered by receivedAtMs, then entryId` | `+2` |
| 24 | `h-applied` | first applied stamp kept (Hive) | `+1 -1` Hive — Expected: {'e-a': 5000, 'e-b': 5000, 'e- Which: at location ['e-a'] is <6000> instead of <5000> ; reason `D-132: a tombstone keeps its first stamp` | `+2` |
| 25 | `k-applied` | first applied stamp kept (Mock) | `+1 -1` Mock — Expected: {'e-a': 5000, 'e-b': 5000, 'e- Which: at location ['e-a'] is <6000> instead of <5000> ; reason `D-132: a tombstone keeps its first stamp` | `+2` |
| 26 | `h-unapplied` | unapplied filter (Hive) | `+1 -1` Hive — Expected: ['s-c', 's-b', 's-f', 's-a'] Which: at location [1] is 's-e' instead of 's-b' ; reason `D-132: import resumes for every staged, unapplied session_end; no end ` | `+2` |
| 27 | `k-unapplied` | unapplied filter (Mock) | `+1 -1` Mock — Expected: ['s-c', 's-b', 's-f', 's-a'] Which: at location [1] is 's-e' instead of 's-b' ; reason `D-132: import resumes for every staged, unapplied session_end; no end ` | `+2` |
| 28 | `h-unapplied-dedupe` | one id per session (Hive) | `+1 -1` Hive — Expected: ['s-c', 's-b', 's-f', 's-a'] Which: at location [4] is ['s-c', 's-b', 's-f', 's-a', 's-c'] which longer than expected ; reason `D-132: import resumes for every staged, unapplied session_end; no end ` | `+2` |
| 29 | `k-unapplied-dedupe` | one id per session (Mock) | `+1 -1` Mock — Expected: ['s-c', 's-b', 's-f', 's-a'] Which: at location [4] is ['s-c', 's-b', 's-f', 's-a', 's-c'] which longer than expected ; reason `D-132: import resumes for every staged, unapplied session_end; no end ` | `+2` |
| 30 | `h-sum-put` | summary put-if-absent (Hive) | `+1 -1` Hive — Expected: false Actual: <true> ; reason `D-131: one row per (scope, target), never rewritten` | `+2` |
| 31 | `k-sum-put` | summary put-if-absent (Mock) | `+1 -1` Mock — Expected: false Actual: <true> ; reason `D-131: one row per (scope, target), never rewritten` | `+2` |
| 32 | `h-sum-order` | summary order: scope criterion (Hive) | `+1 -1` Hive — Expected: [ Which: at location [1]['id'] is 'sensor-timed_instance-ti-run-b' instead of 'sensor-effort-eff- ; reason `D-131: scope order, then windowStartMs, then targetId` | `+2` |
| 33 | `k-sum-order` | summary order: scope criterion (Mock) | `+1 -1` Mock — Expected: [ Which: at location [1]['id'] is 'sensor-timed_instance-ti-run-b' instead of 'sensor-effort-eff- ; reason `D-131: scope order, then windowStartMs, then targetId` | `+2` |
| 34 | `h-casc-session` | `deleteSession` cascade (Hive) | `+1 -1` Hive — Expected: empty Actual: [ ; reason `D-131: no summary outlives its session` | `+2` |
| 35 | `k-casc-session` | `deleteSession` cascade (Mock) | `+1 -1` Mock — Expected: empty Actual: [ ; reason `D-131: no summary outlives its session` | `+2` |
| 36 | `h-casc-effort` | `deleteEffort` cascade (Hive) | `+1 -1` Hive — Expected: [ Which: at location [1] is 'sensor-effort-eff-bench' instead of 'sensor-effort-eff-curl' ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 37 | `k-casc-effort` | `deleteEffort` cascade (Mock) | `+1 -1` Mock — Expected: [ Which: at location [1] is 'sensor-effort-eff-bench' instead of 'sensor-effort-eff-curl' ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 38 | `h-casc-ti` | `deleteTimedInstance` cascade (Hive) | `+1 -1` Hive — Expected: [ Which: at location [3] is 'sensor-timed_instance-ti-run-b' instead of 'sensor-timed_instance-ti ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 39 | `k-casc-ti` | `deleteTimedInstance` cascade (Mock) | `+1 -1` Mock — Expected: [ Which: at location [3] is 'sensor-timed_instance-ti-run-b' instead of 'sensor-timed_instance-ti ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 40 | `h-casc-ti-eff` | `deleteTimedInstancesForEffort` cascade (Hive) | `+1 -1` Hive — Expected: [ Which: at location [3] is 'sensor-timed_instance-ti-run-b' instead of 'sensor-round_instance-ri ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 41 | `k-casc-ti-eff` | `deleteTimedInstancesForEffort` cascade (Mock) | `+1 -1` Mock — Expected: [ Which: at location [3] is 'sensor-timed_instance-ti-run-b' instead of 'sensor-round_instance-ri ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 42 | `h-casc-ri` | `deleteRoundInstance` cascade (Hive) | `+1 -1` Hive — Expected: [ Which: at location [6] is 'sensor-round_instance-ri-2' instead of 'sensor-round_instance-ri-3' ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 43 | `k-casc-ri` | `deleteRoundInstance` cascade (Mock) | `+1 -1` Mock — Expected: [ Which: at location [6] is 'sensor-round_instance-ri-2' instead of 'sensor-round_instance-ri-3' ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 44 | `h-casc-ri-eff` | `deleteRoundInstancesForEffort` cascade (Hive) | `+1 -1` Hive — Expected: [ Which: at location [5] is [ ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 45 | `k-casc-ri-eff` | `deleteRoundInstancesForEffort` cascade (Mock) | `+1 -1` Mock — Expected: [ Which: at location [5] is [ ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 46 | `h-casc-block` | `deleteSessionBlock` cascade (A-18) (Hive) | `+1 -1` Hive — Expected: ['sensor-session-s-cap-1', 'se Which: at location [1] is 'sensor-effort-eff-bench' instead of 'sensor-effort-eff-curl' ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 47 | `k-casc-block` | `deleteSessionBlock` cascade (A-18) (Mock) | `+1 -1` Mock — Expected: ['sensor-session-s-cap-1', 'se Which: at location [1] is 'sensor-effort-eff-bench' instead of 'sensor-effort-eff-curl' ; reason `D-131: a summary is deleted together with its target` | `+2` |
| 48 | `h-inbox-cascade` | bug injected: `deleteSession` cascades into the inbox (Hive) | `+1 -1` Hive — Expected: [ Which: at location [0] is [] which shorter than expected ; reason `D-132: no history delete cascades into the inbox` | `+2` |
| 49 | `k-inbox-cascade` | bug injected: `deleteSession` cascades into the inbox (Mock) | `+1 -1` Mock — Expected: [ Which: at location [0] is [] which shorter than expected ; reason `D-132: no history delete cascades into the inbox` | `+2` |
| 50 | `x-mock-diverges` | Mock-only divergence (applied-stamp guard) (Mock) | `+0 -1` cross-repo — Expected: { Which: at location ['inbox s-cap-1'][2]['applied_at_ms'] is <5000> instead of <6000> ; reason `` | `+1` |
| 51 | `x-hive-diverges` | Hive-only divergence (inbox order) (Hive) | `+0 -1` cross-repo — Expected: { Which: at location ['inbox s-cap-1'][0]['entry_id'] is 'e-run' instead of 'end-s-cap-1' ; reason `` | `+1` |
| 52 | `s-col-summary` | column `created_at_ms` renamed (schema) | `+0 -1` db_seed — Expected: empty Actual: Set:['created_at_ms'] ; reason `D-131: SensorSummary.toMap writes keys app_sensor_summary lacks` | `+1` |
| 53 | `s-col-inbox` | column `payload_json` renamed (schema) | `+0 -1` db_seed — Expected: empty Actual: Set:['payload_json'] ; reason `D-132: WatchInboxEntry.toMap writes keys app_watch_inbox_entry lacks` | `+1` |
| 54 | `s-roundtrip` | column `payload_json` renamed (schema) | `+0 -1` db_seed —   ; reason `` | `+1` |
| 55 | `s-zero-hr` | CHECK avg ≥ 1 (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses a zero heart rate` | `+1` |
| 56 | `s-avg-above-max` | CHECK avg ≤ max (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses an average above the maximum` | `+1` |
| 57 | `s-steps-scope` | CHECK steps only on timed (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses steps on a round` | `+1` |
| 58 | `s-empty` | CHECK at least one value (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses an empty row` | `+1` |
| 59 | `s-pair` | CHECK HR pair (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses an average without a maximum` | `+1` |
| 60 | `s-neg-steps` | CHECK steps ≥ 0 (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses negative steps` | `+1` |
| 61 | `s-id-derived` | CHECK derived id (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses an id not derived from its scope and` | `+1` |
| 62 | `s-session-target` | CHECK session target (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses a session summary for another sessio` | `+1` |
| 63 | `s-window` | CHECK ordered window (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses a window that ends before it starts` | `+1` |
| 64 | `s-scope-enum` | CHECK scope enum (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses an unknown scope` | `+1` |
| 65 | `s-source` | CHECK source enum (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses an unknown source` | `+1` |
| 66 | `s-fk` | FK to session (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-131: app_sensor_summary refuses a summary of a session that does not` | `+1` |
| 67 | `s-one-per-target` | PK + unique (scope, target) (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <2> ; reason `D-131: app_sensor_summary refuses a second row for the same scope and ` | `+1` |
| 68 | `s-origin-pairing` | CHECK kind ↔ origin pairing (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-132: app_watch_inbox_entry refuses a wrist event as the phone's` | `+1` |
| 69 | `s-kind-enum` | CHECK kind enum (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-132: app_watch_inbox_entry refuses a kind it never stages` | `+1` |
| 70 | `s-origin-enum` | CHECK origin enum (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-132: app_watch_inbox_entry refuses an unknown origin` | `+1` |
| 71 | `s-rating-id` | CHECK phone rating id (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-132: app_watch_inbox_entry refuses a phone rating under another sess` | `+1` |
| 72 | `s-change-prefix` | CHECK phone change id (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <1> ; reason `D-132: app_watch_inbox_entry refuses a phone change not keyed by its c` | `+1` |
| 73 | `s-inbox-pk` | PK on entry_id (schema) | `+0 -1` db_seed — Expected: throws <Instance of 'DatabaseE Which: emitted <2> ; reason `D-132: app_watch_inbox_entry refuses a second row with the same entry ` | `+1` |
| 74 | `s-roundtrip-v2` | column `payload_json` renamed (redo, outcome-capturing test) (schema) | `+0 -1` db_seed — Expected: null Actual: SqfliteFfiException:<SqfliteFfiException(sqlite_error: 1, , SqliteException(1): while p ; reason `D-132: app_watch_inbox_entry accepts e-set1 as-is` | `+1` |
| 75 | `m-finite` | finite-HR guard — INEFFECTIVE mutation (precedence), redone as m-finite-v2 (models) | `NOT RED: 00:00 +2: All tests passed!` — none —   ; reason `` | `+2` |
| 76 | `m-summary-ids` | non-empty ids — INEFFECTIVE mutation (precedence), redone as m-summary-ids-v2 (models) | `NOT RED: 00:00 +2: All tests passed!` — none —   ; reason `` | `+2` |
| 77 | `m-inbox-ids` | non-empty entry id (half-disabled; redone as m-inbox-ids-v2) (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: a staged row names its entry` | `+1` |
| 78 | `m-json-format` | non-JSON `payload_json` refused (try/catch removed) (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: threw FormatException:<FormatException: Unexpected character (at character 2) ; reason `D-132: a stored payload that is not JSON is refused` | `+1` |
| 79 | `m-stored-id-v2` | `fromMap` stored-id check (re-run with reason) (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131: a stored id that is not derived is refused` | `+1` |
| 80 | `m-payload-copy-v2` | `payload` copy (re-run with reason) (models) | `+0 -1` model rules — Expected: { Which: at location ['avgHeartRateBpm'] is <999> instead of <140> ; reason `D-132: the map a caller reads is a copy` | `+1` |
| 81 | `m-json-refusal-v2` | non-JSON payload (re-run with reason) (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: a payload that is not JSON is refused` | `+1` |
| 82 | `m-payload-object-v2` | JSON object (re-run with reason) (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: a stored payload is a JSON object` | `+1` |
| 83 | `m-finite-v2` | finite-HR guard (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses a heart rate that is not a number` | `+2` |
| 84 | `m-summary-ids-v2` | non-empty session/target ids (models) | `+0 -2` Hive+Mock — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'SensorSummary'> ; reason `D-131 refuses a summary with no target` | `+2` |
| 85 | `m-inbox-ids-v2` | non-empty entry/session ids (models) | `+0 -1` model rules — Expected: throws <Instance of 'ArgumentE Which: returned <Instance of 'WatchInboxEntry'> ; reason `D-132: a staged row names its entry` | `+1` |

Assertion-change table: **empty.** No pre-existing assertion, expectation or fixture was modified.
`test/db_seed_test.dart` received additions only, and its original test body is byte-identical; no
other pre-existing test file was touched.

Footprint versus Predicted Files: all nine predicted files were touched, and
`test/watch_capture_repository_parity_test.dart` is new, as predicted. Nothing else changed apart from this
plan.

Findings, not fixed (outside Phase 2's scope):
- **Pre-existing schema drift.** `TrainingSession.toMap` writes `is_rolling`, but `app_training_session`
  has no such column; it appears only in a migration-note comment in `scripts/sqlite_schema.sql`. The new
  subset guard covers only the two new models. Worth a follow-up.
- **A formatter delta that is PR 1's.** `dart format` would reflow PR 1's `sessionFeeling` comment line in
  `models.dart`. It was left as is (D-102: PR 1 owns it); the Phase 2 block is format-clean.

For Phase 3b:
- **The inbox API.** Use `WorkoutRepository.stageWatchInboxEntry`, `getWatchInboxEntriesForSession`,
  `getWatchInboxEntry`, `markWatchInboxEntriesApplied` (the tombstone write),
  `getWatchSessionIdsWithUnappliedEnd`, `createSensorSummary` and `getSensorSummariesForSession`.
- **Ids come from the models.** Use `WatchInboxEntry.phoneRatingId` / `phoneChangeId` and
  `SensorSummary.idFor`.
- **Constructors throw.** Both models throw `ArgumentError` on anything D-131 or D-132 forbids (A-10,
  A-15), so filter wire input before constructing.

### Phase 3a: Phone mirror switch, preferences producer and live-screen filter (@developer)

Needs Phase 1. Implements D-113 (phone half), D-115, D-130 (mirror half) and D-141.

1. [x] `lib/state/watch/live_session_mirror_state.dart`: a wrist snapshot naming another session
   is adopted with no answer, and the completed record is cleared (D-130). Same-session
   re-assertion is unchanged.
2. [x] `lib/core/utils/watch_reference_sync.dart`: a `preferences_down` builder through
   `phoneEnvelope`.
3. [x] `lib/state/watch/watch_sync_request_handler.dart`: the `routines` request is answered with
   `preferences_down` (always), then `routines_down` (when there is one). The value is read from
   `SettingsState` (D-115).
4. [x] `lib/state/watch/watch_sync_wiring.dart` and `lib/main.dart`: pass `SettingsState` into
   `createWatchSync`.
5. [x] `lib/features/session/live_session_screen.dart`: D-141 filtering for the list, the status
   count and the completed-card count.
6. [x] Tests:
   - S-251 and S-252 in `test/live_mirroring_test.dart`;
   - S-253 in `test/watch_transport_test.dart`: update "S-003 a phone with nothing to send stays
     quiet" and the `hasLength(1)` routine test to the new exact expectations, and list them in
     the assertion-change table;
   - the builder in `test/watch_reference_sync_test.dart`;
   - S-254 in `test/phone_manage_bridge_test.dart`, or a new
     `test/live_session_capture_entries_test.dart`.
7. [x] Docs:
   - `docs/state_management/services_and_utils.md`: the switch rule under
     `LiveSessionMirrorState`, and the preferences answer under `WatchSyncRequestHandler` and
     `WatchReferenceSync`. Replace the sentence "A phone holding no routines … answers nothing
     at all". Stay under the warning band.
   - `docs/theme_and_settings.md`: one invariant stating that the effort-rating
     toggle also governs the wrist prompt and reaches the wrist at its next wrist-initiated sync.
     Keep it minimal: PR 1 also edits this file.

**Done Criteria:**
- `flutter analyze`.
- `flutter test`: full summary line.
- `swift test`: count unchanged.
- `flutter test test/live_mirroring_test.dart test/watch_transport_test.dart test/watch_reference_sync_test.dart test/phone_manage_bridge_test.dart test/interaction_flow_test.dart test/docs_indexing_contract_test.dart`.
- Red→green evidence for S-251, S-253 and S-254.
- An assertion-change table.

**Predicted Files:**
- `lib/state/watch/live_session_mirror_state.dart`
- `lib/state/watch/watch_sync_request_handler.dart`
- `lib/state/watch/watch_sync_wiring.dart`
- `lib/core/utils/watch_reference_sync.dart`
- `lib/main.dart`
- `lib/features/session/live_session_screen.dart`
- `test/live_mirroring_test.dart`
- `test/watch_transport_test.dart`
- `test/watch_reference_sync_test.dart`
- `test/phone_manage_bridge_test.dart`, or `test/live_session_capture_entries_test.dart` (new)
- `docs/state_management/services_and_utils.md`
- `docs/theme_and_settings.md`

**Phase 3a verification notes (@developer, 2026-09-25):**

Start of phase: HEAD `b3e0d98`, `flutter test` `+2901 ~1`, `swift test` 149, `flutter analyze` 242 (the
pre-change output was captured before the first edit for the diff below).

| Check | Start of phase | After Phase 3a | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` | `242 issues found. (ran in 2.7s)`; a line-number-insensitive diff of the diagnostics against the pre-change run is empty | No new diagnostics |
| `flutter test` | `+2901 ~1: All tests passed!` | `01:04 +2908 ~1: All tests passed!` (exit 0) | +7, all new: S-251 (1, `live_mirroring_test.dart`), S-253 (1, `watch_transport_test.dart`), the builder (2, `watch_reference_sync_test.dart`), S-254 (3, new `live_session_capture_entries_test.dart`). Two existing S-003 tests changed to new exact expectations (assertion-change table) |
| `cd watch/watchos && swift test` | `Executed 149 tests, with 0 failures` | `Executed 149 tests, with 0 failures (0 unexpected) in 0.335 (0.343) seconds` | Unchanged; nothing under `watch/` changed |
| Done-Criteria suites (`live_mirroring`, `watch_transport`, `watch_reference_sync`, `phone_manage_bridge`, `interaction_flow`, `docs_indexing_contract`) | — | `00:06 +164: All tests passed!` | — |
| `flutter test test/live_session_capture_entries_test.dart` | — | `00:00 +3: All tests passed!` | S-254 |
| `git status --porcelain watch lib/watch` | empty | empty | D-101 |

S-252: the two `S-008` tests in `test/live_mirroring_test.dart` are byte-identical and green in the runs above.

Red run before any implementation (tests written first): `live_mirroring_test.dart` `+41 -1` (S-251 failed on
`completedRecord`: `Expected: null / Actual: {…}`); `live_session_capture_entries_test.dart` `+0 -3` (all three
S-254 assertions); `watch_transport_test.dart` and `watch_reference_sync_test.dart` did not compile (`No named
parameter with the name 'settingsState'`, `Member not found: 'WatchReferenceSync.buildPreferencesDown'`) — the
API did not exist yet. A compile failure is not counted as red; every red below is an assertion failure by
mutation.

Red→green by copy-and-restore, never `git stash`. Harness `<scratchpad>/pr2_p3_redgreen.py`, cases
`<scratchpad>/pr2_p3a_cases.json`, logs `<scratchpad>/pr2-p3-redgreen/`. Per case: shasum and copy the file,
apply one textual mutation (asserted to occur exactly once and confirmed in the file before the run), run the one
test by `--plain-name`, copy the backup back, prove the restore with `cmp` and a matching shasum, re-run green.
Every red failed on an assertion whose reason cites its S-id; no red log holds a compile error; every restore
matched.

| # | S-id | Behaviour reverted (file) | Red — failing assertion | Green |
|---|---|---|---|---|
| 1 | S-251 | no-answer rule removed (mirror: the switch falls through to re-assertion) | `+0 -1` — Expected: <1> / Actual: <2> ; reason `S-251 a snapshot of another session is adopted, never answered` | `+1` |
| 2 | S-251 | completed-record clear removed (mirror) | `+0 -1` — Expected: null / Actual: {…} ; reason `S-251 the record the phone closed belongs to s-prev` | `+1` |
| 3 | S-251 | entries cleared on a switch removed (reconciler — the Phase 1 rule the mirror relies on) | `+0 -1` — Expected: ['e-b1'] / Actual: ['e-p1', 'e-b1'] ; reason `S-251 entries never merge across sessions` | `+1` |
| 4 | S-253 | preferences sent only when routines exist (handler) | `+0 -1` — Expected: ['preferences_down'] / Actual: [] ; reason `S-253 a phone with no routines still sends its preferences` | `+1` |
| 5 | S-253 | preferences sent after routines (handler) | `+0 -1` — Expected: ['preferences_down', 'routines_down'] / Actual: ['routines_down', 'preferences_down'] ; reason `S-253 preferences first, then the routines` | `+1` |
| 6 | S-253 | value hardcoded `true` instead of `SettingsState.showFeelingSurvey` (handler; D-115) | `+0 -1` — at location ['effortRatingPrompt'] is <true> instead of <false> ; reason `S-253 the setting as SettingsState holds it, stamped with the phone clock at send` | `+1` |
| 7 | S-253 | `generatedAt` from the wall clock instead of the injected phone clock (handler) | `+0 -1` — at location ['generatedAt'] is '2026-09-25T18:58:41.712479Z' instead of '2026-09-21T12:00:00.000Z' ; same reason | `+1` |
| 8 | S-253 | an extra payload field (builder; the schema closes the payload) | `+0 -1` — Expected: empty / Actual: [unexpected_field …] ; reason `S-253 the wrist must be able to accept it (true)` | `+1` |
| 9 | S-253 | content suffix dropped from the message id (builder) | `+0 -1` — Expected: not 'msg-preferences-1789993800000' / Actual: 'msg-preferences-1789993800000' ; reason `S-253 a tie on generatedAt goes to the later-received copy, …` | `+1` |
| 10 | S-253 | preferences never sent (handler) — the updated no-routines S-003 test | `+0 -1` — Expected: ['preferences_down'] / Actual: [] ; reason `S-253 no routines_down without routines, but the setting always travels` | `+1` |
| 11 | S-253 | preferences never sent (handler) — the updated seeded-routine S-003 test | `+0 -1` — Expected: ['preferences_down', 'routines_down'] / Actual: ['routines_down'] ; reason `S-253 every sync is answered with preferences first` | `+1` |
| 12 | S-254 | LOGGED list reads `entries` (screen) | `+0 -1` — Expected: no matching candidates / Actual: Found 1 widget with key `live_session_entry_rating-s-live-ui` ; reason `S-254 the effort rating is not a logged row` | `+1` |
| 13 | S-254 | status count reads `entries` (screen) | `+0 -1` — Found 0 widgets with text "1 of 3 · 1 logged" ; reason `S-254 the status reads "1 logged"` | `+1` |
| 14 | S-254 | completed card counts the raw record (screen) | `+0 -1` — Found 0 widgets with text "1 logged across 3 exercises — …" ; reason `S-254 the completed card counts 1` | `+1` |
| 15 | S-254 | `session_end` dropped from `sessionScopedKinds` (mirror) | `+0 -1` — Found 1 widget with key `live_session_entry_end-s-live-ui` ; reason `S-254 the session end is not a logged row` | `+1` |

Assertion-change table (all in `test/watch_transport_test.dart`, line numbers before the change; each is a new
exact expectation, none is loosened):

| File:line (before) | Before | After | Rule |
|---|---|---|---|
| `:428` | `expect(link.phone.sent, hasLength(1));` | `expect([for (final frame in link.phone.sent) frame['type']], ['preferences_down', 'routines_down'], reason: 'S-253 …')` — exact length, types and order | D-113 |
| `:429` | `final message = link.phone.sent.single;` | `final message = link.phone.sent.last;` (the length is asserted exactly on the line above; every expectation on `message` is unchanged) | D-113 |
| `:439` | test `S-003 a phone with nothing to send stays quiet` | renamed `S-003 a phone with no routines answers with its preferences only` — the old name states the behaviour D-113 retires | D-113 |
| `:443` | `expect(link.phone.sent, isEmpty);` | `expect([for (final frame in link.phone.sent) frame['type']], ['preferences_down'], reason: 'S-253 …')` — exact | D-113 |

Construction-only edits (no assertion touched): the `setUp` of `test/watch_transport_test.dart` and its S-006
"production graph is not built" case pass the new required `settingsState` to `createWatchSync`.

Footprint versus Predicted Files: every predicted file was touched; S-254 went to the new
`test/live_session_capture_entries_test.dart` (the plan's second option). Nothing else changed apart from this
plan. Line endings: `lib/main.dart` 413/413 CRLF (was 412/412; one CRLF line added); every other touched file LF.

### Phase 3b: Phone inbox, import, receipts and liveness (@developer)

Needs Phases 1, 2 and 3a. Implements D-110, D-132 – D-138 (state half), D-140 and D-142.

1. [x] The inbox, a new file under `lib/state/watch/` (name is free), consumes every accepted
   wrist message through `SyncProtocolValidator.evaluateOrAccept`. It stages per D-132.
   - `lib/state/watch/watch_incoming_router.dart` hands each message to the inbox **before**
     the mirror and the nutrition bridge, and extends `WatchIncomingReceipt` with the inbox
     verdict.
   - The mirror's outgoing `correct_entry` and `delete_entry` are staged before they are sent
     (D-137), through a hook on the mirror or a transport decorator (a mechanic).
2. [x] The importer is a service over `WorkoutRepository` only (e.g. under `lib/core/services/`;
   name is free). It implements D-133 – D-138:
   - summaries attach, including late targets;
   - top-ups;
   - tombstones;
   - resume at construction for unapplied `session_end` rows;
   - an injected clock.
3. [x] Receipts at application, through the single existing receipt builder (D-132).
4. [x] A phone-rating API for Phase 5: stage the phone's own rating for a watch session, or
   write it directly when the session is already imported (D-138/D-139, state half).
5. [x] Liveness (D-142): wire a calendar refresh from `createWatchSync`/`lib/main.dart`.
6. [x] Update router construction in `lib/state/watch/live_session_mirror_debug_main.dart` and
   `test/watch_nutrition_quick_log_test.dart` (S-002 cases): the inbox is added and the
   assertions are otherwise unchanged.
7. [x] Tests:
   - new `test/watch_session_import_test.dart`: S-261 – S-271, S-273, S-274, and the
     phone-rating state half of S-281/S-284;
   - new `test/watch_capture_contract_test.dart`: the Dart half of F-CAP, all three cases, on
     Mock and Hive (S-272).
8. [x] Docs: create `docs/watch_session_capture.md`, covering the inbox, the
   import, precedence, tombstones and the receipt timing, as structure, rationale, invariants
   with enforcement and vocabulary. Link it from `docs/README.md` and from
   `services_and_utils.md` in the same phase (reachability test).

**Done Criteria:**
- `flutter analyze`.
- `flutter test`: full summary line.
- `swift test`: count unchanged.
- `flutter test test/watch_session_import_test.dart test/watch_capture_contract_test.dart test/watch_nutrition_quick_log_test.dart test/live_mirroring_test.dart test/watch_transport_test.dart test/health_platform_test.dart test/docs_indexing_contract_test.dart`.
- Red→green evidence for every S-261 – S-274 test. For example: drop the put-if-absent → S-263
  fails; drop the tombstone check → S-266 fails; stage after the mirror → S-267 fails.
- Hive ↔ Mock parity (S-272) is green.
- An assertion-change table.

**Predicted Files:**
- `lib/state/watch/watch_session_inbox.dart` (new; name is free)
- `lib/core/services/watch_session_importer.dart` (new; name is free)
- `lib/state/watch/watch_incoming_router.dart`
- `lib/state/watch/watch_sync_wiring.dart`
- `lib/state/watch/live_session_mirror_state.dart`
- `lib/state/watch/live_session_mirror_debug_main.dart`
- `lib/state/watch/watch_nutrition_log_bridge.dart` (only if the receipt builder moves)
- `lib/main.dart`
- `test/watch_session_import_test.dart` (new)
- `test/watch_capture_contract_test.dart` (new)
- `test/watch_nutrition_quick_log_test.dart`
- `test/watch_transport_test.dart`
- `docs/watch_session_capture.md` (new)
- `docs/README.md`
- `docs/state_management/services_and_utils.md`

**Phase 3b verification notes (@developer, 2026-09-25):**

Start of phase: the Phase 3a state (uncommitted), `flutter test` `+2908 ~1`, `flutter analyze` 242.

| Check | Start of phase | After Phase 3b | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` | `242 issues found. (ran in 2.4s)`; a line-number-insensitive diff of the diagnostics against the pre-3a capture is empty | No new diagnostics |
| `flutter test` | `+2908 ~1: All tests passed!` | `01:05 +2950 ~1: All tests passed!` (exit 0) | +42, all new: 30 in `test/watch_session_import_test.dart`, 12 in `test/watch_capture_contract_test.dart`. No existing test changed; `test/watch_nutrition_quick_log_test.dart` changed in construction only (below) |
| `cd watch/watchos && swift test` | `Executed 149 tests, with 0 failures` | `Executed 222 tests, with 0 failures (0 unexpected) in 0.781 (0.794) seconds` | This phase changed nothing under `watch/`. The +73 is the parallel Phase 4a/4b Swift run's work in progress in the same worktree (its files: `watch/watchos/…`, per `git status`) |
| Done-Criteria suites (`watch_session_import`, `watch_capture_contract`, `watch_nutrition_quick_log`, `live_mirroring`, `watch_transport`, `health_platform`, `docs_indexing_contract`) | — | `00:04 +171: All tests passed!` | — |
| Hive ↔ Mock parity (S-272) | — | the 12 `S-272` tests in `test/watch_capture_contract_test.dart` green in both runs above | Every created row equal by `toMap`, contract order and reversed arrival |
| `flutter test test/docs_indexing_contract_test.dart` | — | `00:00 +9: All tests passed!` | `watch_session_capture.md` 8,132 B (new, reachable from README and `services_and_utils.md`); `services_and_utils.md` 46,163 B after both runs' edits, under the band |
| `git status --porcelain lib/watch` | empty | empty | D-101 |

Red run before any implementation (tests written first): none of the three suites compiled — `test/watch_session_import_test.dart` (`Undefined name 'WatchSessionImporter'`, `Type 'WatchSessionInbox' not found`, `No named parameter with the name 'inbox'`), `test/watch_capture_contract_test.dart` (`The method 'updateEffort' isn't defined for the type 'WorkoutRepository'`), `test/watch_nutrition_quick_log_test.dart` (`No named parameter with the name 'inbox'`). A compile failure is not counted as red; every red below is an assertion failure by mutation.

Test hardening done while recording red→green (the tests are new in this phase, so no pre-existing assertion moved):
- Every expectation in the two new suites and in the shared checker (`test/helpers/watch_capture_import_harness.dart`) carries a reason citing its S-id (or D-132 / A-3), so a red names its scenario. The tests' inbox rethrows its own failures (`onFailure: Error.throwWithStackTrace`); no red or green log contains a swallowed inbox failure.
- **S-266 variant was vacuous:** a redelivery that stages nothing runs no import pass, so no mutation of the tombstone logic could turn it red. The redelivery now carries a late set (`e-set4`), so the import runs again over the effort whose `e-set2` the user removed (row 15).
- **S-281's first draft missed the import-time rule:** it delivered the wrist rating after its session end, so reverting the import-time precedence stayed green (row 28). It now runs both arrival orders (rows 29, 30), one per rule.
- Added `S-267 a later correction leaves the user’s own edit of another metric` for A-43 (row 20).
- **S-264's main case is protected twice**: put-if-absent keeps the altered copy out, and the precedence rule would refuse it anyway. Each single reversion stays green (rows 10, 11); both together go red (row 9).

Red→green by copy-and-restore, never `git stash`. Harness `<scratchpad>/pr2_p3b_redgreen.py`, cases `<scratchpad>/pr2_p3b_cases.json`, logs `<scratchpad>/pr2-p3b-redgreen/`. Per case: shasum and copy every file the case edits, apply each textual mutation (asserted to occur exactly once, confirmed present in the file with a changed shasum before the run), run the one test by `--plain-name`, copy every backup back, prove the restore with `cmp` and a matching shasum, re-run green. 46 reds, each an assertion failure whose reason cites its scenario, none a compile error; every restore matched; every green re-run passed. Rows 27 and 46–49 print their reason far below a long `Expected:` block; those rows were re-derived from their saved logs with the whole failure block searched. Mutated files: the importer, the inbox, the router, the mirror (row 21 only), and the two repositories.

| # | Test | Behaviour reverted (file) | Red — failing assertion | Green |
|---|---|---|---|---|
| 1 | S-261 full | router never hands the message to the inbox (router) | `+0 -1` — Expected: not null / Actual: <null> ; reason `S-261 full: the session is imported` | `+1` |
| 2 | S-261 no-sensors | importer invents a heart rate when none was measured (importer) | `+0 -1` — Expected: [] / Actual: [ ; reason `S-261 no-sensors: exactly the summaries the wrist measured, on their targets` | `+1` |
| 3 | S-261 prompt-off | importer defaults a missing rating (importer) | `+0 -1` — Expected: <null> / Actual: <3> ; reason `S-261 prompt-off: the rating the phone holds` | `+1` |
| 4 | S-261 resumed | start-up resume applies nothing (inbox) | `+0 -1` — Expected: not null / Actual: <null> ; reason `S-261 resumed: the session is imported` | `+1` |
| 5 | S-262 reversed | entries whose position moved are not re-keyed (importer) | `+0 -1` — Which: is different. ; reason `S-262 reversed: the round instance derives from its entry` | `+1` |
| 6 | S-262 session_end first | an end consumed as empty is treated as deleted history (importer) | `+0 -1` — Expected: not null / Actual: <null> ; reason `S-262 session_end first: the session is imported` | `+1` |
| 7 | S-262 rating first | the import ignores a rating staged before the end (importer) | `+0 -1` — Expected: <4> / Actual: <null> ; reason `S-262 rating first: the rating the phone holds` | `+1` |
| 8 | S-263 | put-if-absent staging removed (Mock repository) | `+0 -1` — Which: does not contain WatchInboxOutcome:<WatchInboxOutcome.unchanged> ; reason `S-263 every copy is accepted and refused by put-if-absent` | `+1` |
| 9 | S-264 main | put-if-absent removed (Mock) **and** wrist rating wins over the phone’s (importer) | `+0 -1` — Expected: <2> / Actual: <5> ; reason `S-264 the phone’s value is final` | `+1` |
| 10 | S-264 main | put-if-absent removed only (Mock) — protection check | NOT RED (`+1: All tests passed!`) | `+1` |
| 11 | S-264 main | precedence reverted only (importer) — protection check | NOT RED (`+1: All tests passed!`) | `+1` |
| 12 | S-264 variant | a wrist rating replaces the phone’s after import (importer) | `+0 -1` — Expected: <2> / Actual: <4> ; reason `S-264 a wrist rating applies only while the phone has none` | `+1` |
| 13 | S-265 | the status check dropped: an abandoned session imports (importer) | `+0 -1` — Expected: null / Actual: <Instance of 'TrainingSession'> ; reason `S-265 an abandoned session creates no history` | `+1` |
| 14 | S-266 main | deleted-session detection off (importer) | `+0 -1` — Expected: null / Actual: <Instance of 'TrainingSession'> ; reason `S-266 no session is re-created` | `+1` |
| 15 | S-266 variant | applied rows not treated as materialised (importer) | `+0 -1` — Expected: null / Actual: <Instance of 'EffortObservation'> ; reason `S-266 e-set2’s rows are not re-created` | `+1` |
| 16 | S-267 main | corrections staged after the send instead of before (staging transport) | `+0 -1` — Which: at location [0] is <false> instead of <true> ; reason `S-267 each change is staged before it is sent` | `+1` |
| 17 | S-267 main | staged corrections not applied at import (importer) | `+0 -1` — Which: at location [1] is <5> instead of <6> ; reason `S-267 the bench holds 5×80 and 6×80, and nothing for e-set3` | `+1` |
| 18 | S-267 main | staged deletions not applied at import (importer) | `+0 -1` — Which: at location [2] is <5> instead of <null> ; reason `S-267 the bench holds 5×80 and 6×80, and nothing for e-set3` | `+1` |
| 19 | S-267 variant | corrections staged after import never applied (importer) | `+0 -1` — Expected: <4> / Actual: <5> ; reason `S-267 the imported row takes the correction` | `+1` |
| 20 | S-267 other metric | a later correction re-applies every corrected field (importer) | `+0 -1` — Expected: <90.0> / Actual: <85.0> ; reason `S-267 the user’s own edit of the weight stays` | `+1` |
| 21 | S-268 | the mirror answers a snapshot of another session (mirror, the Phase 3a rule) | `+0 -1` — Which: larger than expected ; reason `S-268 nothing was sent back but the receipts` | `+1` |
| 22 | S-269 | staged payloads zero-filled (inbox) | `+0 -1` — Expected: empty / Actual: [Instance of 'SensorSummary'] ; reason `S-269 zero SensorSummary rows` | `+1` |
| 23 | S-270 | the imported session created without its end (importer) | `+0 -1` — Which: has length of <2> ; reason `S-270 the wrist’s workout is the health record (D-140)` | `+1` |
| 24 | S-271 one import | refresh on every settle, changed or not (inbox) | `+0 -1` — Expected: <1> / Actual: <2> ; reason `S-271 a redelivery triggers no refresh` | `+1` |
| 25 | S-271 each change | a rating top-up not counted as a history change (importer) | `+0 -1` — Expected: <2> / Actual: <1> ; reason `S-271 the import at the session end, then the rating top-up` | `+1` |
| 26 | S-273 | the empty-session rule dropped (importer) | `+0 -1` — Expected: null / Actual: <Instance of 'TrainingSession'> ; reason `S-273 nothing imported` | `+1` |
| 27 | S-274 | the importer assumes every exercise carries load (importer) | `+0 -1` — Expected: [ ; reason `S-274 ex-pushup: metric, unit, values, id pattern and companion rows` | `+1` |
| 28 | S-281 (first draft) | wrist rating first at import (importer) — exposed the test gap | NOT RED (`+1: All tests passed!`) | `+1` |
| 29 | S-281 before its end | wrist rating first at import (importer) | `+0 -1` — Expected: <3> / Actual: <5> ; reason `S-281 the phone’s rating is the one history keeps` | `+1` |
| 30 | S-281 after its end | wrist rating wins at top-up (importer) | `+0 -1` — Expected: <3> / Actual: <5> ; reason `S-281 the phone’s rating is the one history keeps` | `+1` |
| 31 | S-284 | the direct write after import removed (inbox) | `+0 -1` — Expected: <2> / Actual: <4> ; reason `S-284 the answer is written to sessionFeeling directly` | `+1` |
| 32 | D-132 quick-log | quick-logs made stageable (inbox) | `+0 -1` — Expected: WatchInboxOutcome:<WatchInboxOutcome.ignored> / Actual: WatchInboxOutcome:<WatchInboxOutcome.unchanged> ; reason `D-132 a quick-log is the nutrition bridge alone` | `+1` |
| 33 | D-132 gate | the incoming gate skipped (inbox) | `+0 -1` — Expected: WatchInboxOutcome:<WatchInboxOutcome.refused> / Actual: WatchInboxOutcome:<WatchInboxOutcome.staged> ; reason `D-132 the gate refuses a v2 message` | `+1` |
| 34 | A-3 | the required-fields filter skipped (inbox) | `+0 -1` — Which: at location [1] is ['e-snap-1', 'rating-s-snap', 'end-s-snap'] which longer than expected ; reason `A-3 only the complete entry` | `+1` |
| 35 | D-132 snapshot | wrist snapshots not staged (inbox) | `+0 -1` — Expected: <2> / Actual: <null> ; reason `D-132 the snapshot session is imported with its rating` | `+1` |
| 36 | S-272 Mock full | round pause not carried (importer) | `+0 -1` — Expected: <120000> / Actual: <0> ; reason `S-272 Mock full: round.totalPausedDurationMs` | `+1` |
| 37 | S-272 Mock no-sensors | efforts ranked by entryId only (importer) | `+0 -1` — Expected: [ ; reason `S-272 Mock no-sensors: one effort per slot, exercise and kind, in first-entry order` | `+1` |
| 38 | S-272 Mock prompt-off | extra weight added to a load exercise (importer) | `+0 -1` — Expected: <false> / Actual: <true> ; reason `S-272 Mock prompt-off: extra weight exactly when the exercise lacks load` | `+1` |
| 39 | S-272 Mock updateEffort | updateEffort stores nothing (Mock) | `+0 -1` — Which: at location [0] is 'eff-a' instead of 'eff-b' ; reason `S-272 Mock: the order it is given is the order it keeps` | `+1` |
| 40 | S-272 Mock updateEffort | updateEffort creates an unknown id (Mock) | `+0 -1` — Which: at location [2] is ['eff-b', 'eff-a', 'eff-missing'] which longer than expected ; reason `S-272 Mock: the order it is given is the order it keeps` | `+1` |
| 41 | S-272 Hive full | round pause not carried (importer) | `+0 -1` — Expected: <120000> / Actual: <0> ; reason `S-272 Hive full: round.totalPausedDurationMs` | `+1` |
| 42 | S-272 Hive no-sensors | efforts ranked by entryId only (importer) | `+0 -1` — Expected: [ ; reason `S-272 Hive no-sensors: one effort per slot, exercise and kind, in first-entry order` | `+1` |
| 43 | S-272 Hive prompt-off | extra weight added to a load exercise (importer) | `+0 -1` — Expected: <false> / Actual: <true> ; reason `S-272 Hive prompt-off: extra weight exactly when the exercise lacks load` | `+1` |
| 44 | S-272 Hive updateEffort | updateEffort stores nothing (Hive) | `+0 -1` — Which: at location [0] is 'eff-a' instead of 'eff-b' ; reason `S-272 Hive: the order it is given is the order it keeps` | `+1` |
| 45 | S-272 Hive updateEffort | updateEffort creates an unknown id (Hive) | `+0 -1` — Which: at location [2] is ['eff-b', 'eff-a', 'eff-missing'] which longer than expected ; reason `S-272 Hive: the order it is given is the order it keeps` | `+1` |
| 46 | S-272 parity full | Hive-only: round pause dropped on write (Hive) | `+0 -1` — Which: at location ['roundInstances'][1]['total_paused_duration_ms'] is <0> instead of <120000> ; reason `S-272 full: Hive and Mock agree row for row` | `+1` |
| 47 | S-272 parity no-sensors | Mock-only: timed instance stamp altered on write (Mock) | `+0 -1` — Which: at location ['timedInstances'][0]['updated_at_ms'] is <1790331600000> instead of <0> ; reason `S-272 no-sensors: Hive and Mock agree row for row` | `+1` |
| 48 | S-272 parity prompt-off | Mock-only: applied stamp off by one (Mock) | `+0 -1` — Which: at location ['inbox'][0]['applied_at_ms'] is <1790334000000> instead of <1790334000001> ; reason `S-272 prompt-off: Hive and Mock agree row for row` | `+1` |
| 49 | S-272 parity reversed | Hive-only: updateEffort stores nothing (Hive) | `+0 -1` — Which: at location ['efforts'][1]['order_index'] is <0> instead of <1> ; reason `S-272 full, reversed: Hive and Mock agree row for row` | `+1` |

Every new test has at least one red: the 30 import tests (rows 1–9, 12–27, 29–35) and the 12 contract tests (rows 36–49).

Assertion-change table: **empty.** No pre-existing assertion, expectation or fixture was modified. `test/watch_nutrition_quick_log_test.dart` changed in construction only (`git diff --numstat`: 14 additions, 1 deletion): the two S-002 routers pass the new required `inbox`, and `_PhoneNutritionHarness` carries its repository for it (the one deleted line is that constructor's old signature).

Footprint versus Predicted Files:
- Predicted and touched: `lib/state/watch/watch_session_inbox.dart` (new), `lib/core/services/watch_session_importer.dart` (new), `lib/state/watch/watch_incoming_router.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/state/watch/live_session_mirror_debug_main.dart`, `lib/main.dart`, `test/watch_session_import_test.dart` (new), `test/watch_capture_contract_test.dart` (new), `test/watch_nutrition_quick_log_test.dart`, `docs/watch_session_capture.md` (new), `docs/README.md`, `docs/state_management/services_and_utils.md`.
- Predicted, untouched: `lib/state/watch/live_session_mirror_state.dart` (a transport decorator stages the corrections, A-41), `lib/state/watch/watch_nutrition_log_bridge.dart` (the receipt builder did not move, A-42), `test/watch_transport_test.dart` (nothing to change: the inbox stages nothing its cases need answered).
- Extra: `lib/core/utils/logged_entry_rows.dart` (new) and `lib/state/workout/session_core.dart`, `session_core_entry.dart`, `session_core_io.dart` (A-44); `lib/data/repositories/workout_repository.dart`, `mock_workout_repository.dart`, `hive_workout_repository.dart` (`updateEffort`, A-45); `test/helpers/watch_capture_import_harness.dart` (new, shared by the two suites).

Line endings: `lib/main.dart` 415/415 lines CRLF (was 413/413 after 3a; two CRLF lines added); every other touched file is LF, as it was.

### Phase 4a: Wrist summaries, steps, session end, resend and prune gate (@developer, Swift)

Needs Phase 1. Implements D-120 – D-126, D-128 and D-129.

1. [x] `WatchRecords.swift`: add `WatchObservationKind.effortRating` and `.sessionEnd`, and add
   them to `all`. Update the Swift closed-set test (`WatchNutritionQuickLogTests`) to the new
   exact set. The Dart closed set stays at five (D-127).
2. [x] `WatchSensorRecording.swift`:
   - `WatchSensorSource` gains a steps permission and a cumulative steps stream;
   - the recorder subscribes whenever permission is granted, stores `steps` samples, and
     cancels on `stop`;
   - `readings` is unchanged;
   - update every test double.
3. [x] A new pure summary-computation file in `Sources/WatchSessionEngine/` implementing D-122,
   D-123 and D-125, including pause intervals from the timer rows.
4. [x] `WatchLoggingState.swift` `log`: embed the D-121 per-entry fields and `pausedMs` at log
   time, from the engine's stored samples and timers.
5. [x] `WatchSessionEngine.swift`:
   - append `session_end` on the first terminal transition of a wrist-created session, by every
     path: `finishSession`, `abandonSession`, `applyLifecycle`, `applySnapshot` (D-120);
   - `pendingObservations` covers all sessions (D-128);
   - the prune gate (D-129).
6. [x] Tests:
   - new `WatchSensorSummaryTests.swift`: S-231 – S-236, S-238, and the pause-boundary
     half-open cases;
   - `WatchSensorRecordingTests.swift`: S-237 and S-239. Update the prune tests to confirm
     `end-<sid>` explicitly, never weakening the released counts;
   - `WatchSessionEngineTests.swift`: S-240 and the `session_end` paths. Update the emitted
     counts after `finishSession` to the new exact numbers;
   - replay F-CAP `full` and `no-sensors` up to End (the rating comes in 4b) and compare against
     the contract's events.
7. [x] Keep `testS004NoMutatingOperationExistsAnywhereInTheModule` green without editing it (F-12).
8. [x] Docs:
   - the wrist section of `watch_session_capture.md`;
   - `services_and_utils.md` "Watch Sensors" invariants: raw readings are never sent; the
     summary fields are the only derived values; the prune gate names `session_end`;
   - the vocabulary entries `session end` and `set block`.

   If this phase runs before 3b, it creates and links the doc (see 3b item 8).

**Done Criteria:**
- `flutter analyze`.
- `flutter test`: full summary line, count unchanged.
- `cd watch/watchos && swift test`: "Executed N tests, with 0 failures".
- `swift test --filter WatchSensorSummaryTests` and `--filter WatchSensorRecordingTests`.
- Red→green evidence for S-231 – S-240. For example: remove the pause exclusion → S-232 fails
  on e-r2 = 143.33; drop the `session_end` gate → S-237 fails; revert `pendingObservations` →
  S-240 fails.
- An assertion-change table that lists every updated count.
- `git status --porcelain lib/watch` is empty.

**Predicted Files:**
- `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchSensorSummaries.swift` (new; name is free)
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSummaryTests.swift` (new)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchLiveMirroringTests.swift` (only if emitted
  counts change)
- `watch/watchos/Tests/WatchSessionEngineTests/Fixtures.swift`
- `docs/watch_session_capture.md`
- `docs/state_management/services_and_utils.md`

**Phase 4a verification notes (@developer, 2026-09-25):**

Start of phase: HEAD `b3e0d98`, with the Dart run's uncommitted Phase 3a/3b work in the same worktree (nothing under
`watch/`). `swift test`: `Executed 149 tests, with 0 failures (0 unexpected) in 0.329 (0.336) seconds`. Per the
orchestrator, the Dart suite belongs to the parallel Dart run until the end of Phase 4b, where `flutter analyze` and
one full `flutter test` are run (see Phase 4b notes). No Dart file was touched in 4a.

| Check | Start of phase | After Phase 4a | Delta explained |
|---|---|---|---|
| `cd watch/watchos && swift test` | `Executed 149 tests, with 0 failures` | `Executed 222 tests, with 0 failures (0 unexpected) in 0.777 (0.790) seconds` | +73, all new: `WatchSensorSummaryTests` 17; `WatchCaptureContractTests` 2 (F-CAP `full` and `no-sensors` up to End); `WatchSensorRecordingTests` +8 (S-237 ×4, S-239 ×4); `WatchSensorRecordingStepsDeniedTests` 38 (the whole sensor class again with steps denied, S-239); `WatchSessionEngineTests` +8 (seven D-120 cases, S-240). Three existing assertions changed (table below) |
| `swift test --filter WatchSensorSummaryTests` | — | `Executed 17 tests, with 0 failures` | S-231 – S-236, S-238, D-122/D-123/D-125/D-126 boundaries |
| `swift test --filter WatchSensorRecordingTests` | — | `Executed 38 tests, with 0 failures` | S-237, S-239; `--filter WatchSensorRecordingStepsDeniedTests`: `Executed 38 tests, with 0 failures` |
| watchOS type-check (`swiftc -typecheck`, watchOS 26.4 simulator SDK, `arm64-apple-watchos9.0-simulator`, every file in `Sources/WatchSessionEngine/`) | exit 0, 0 errors | exit 0, 0 errors | the module still builds for the watch, `#if os(watchOS)` code included |
| `testS004NoMutatingOperationExistsAnywhereInTheModule` | green | green, unedited | no new func starts with a guarded verb; the store surface is unchanged |
| `git status --porcelain lib/watch` | empty | empty | D-101 |

What changed, in one line each: `WatchObservationKind` gains `effortRating`/`sessionEnd` (and `efforts`), with
`WatchSessionCapture` deriving `end-<sid>`/`rating-<sid>`; `WatchSensorSource` gains a steps permission and a
cumulative stream, recorded for every session with permission and cancelled on stop, through a write chain
(`WatchSensorWrites`, A-35); new pure `WatchSensorSummaries.swift` (D-122, D-123, D-125, D-126); `WatchLoggingState.log`
attaches heart rate (timed, round, hold), steps (timed) and `pausedMs` (round) at log time; `WatchSessionEngine` appends
`session_end` on every terminal path (A-25), re-sends every session's owed observations in store order (D-128), holds a
wrist session's readings until its `session_end` is acknowledged (D-129), remembers acknowledged ids across a prune
(A-27), and exposes `timerRows(_:)`.

The first full run after the sensor change crashed (signal 11) inside the S-239 comparison, which feeds three streams
at once: each stream's task wrote into the engine concurrently. That is the finding behind A-35; with the write chain
the suite is green, and `testS239EveryStreamReachesTheEngineOneReadingAtATime` pins it (a23).

Red→green, by copy-and-restore, never `git stash`. Harness `<scratchpad>/pr2_p4_redgreen.py`, cases
`<scratchpad>/pr2_p4a_cases.py`, logs and results `<scratchpad>/pr2-p4-redgreen/`. Per case: shasum and copy the file,
apply each mutation (asserted to occur exactly once, then confirmed in the file), run the one test with
`swift test --filter`, copy the backup back, prove the restore with `cmp` and a matching shasum, re-run green. Every
restore matched; no red log holds a compile error; every green re-run is `0 failures`.

| # | S-id | Behaviour reverted or bug injected (file) | Red — failing test and assertion | Green |
|---|---|---|---|---|
| a01 | S-231 | step total not attached to timed events (logging state) | red 1/1: `WatchSensorSummaryTests.testS231TheRunCarriesItsHeartRateAndStepTotalAndNoPause` — XCTAssertEqual failed: ("nil") is not equal to ("Optional(3200.0)") - S-231 the chain 0 → 800 → 1600 → 3200; the 3300 at 10:30 is outside the window | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a02 | S-231 | heart rate not attached to timed events (logging state) | red 2/1: `WatchSensorSummaryTests.testS231TheRunCarriesItsHeartRateAndStepTotalAndNoPause` — XCTAssertEqual failed: ("nil") is not equal to ("Optional(140.0)") - S-231 120, 140 and 160 are in the window | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a03 | S-232 | round pauses not excluded from heart rate (logging state) | red 1/1: `WatchSensorSummaryTests.testS232EachRoundIsSummarisedOverItsOwnActiveWindow` — XCTAssertEqual failed: ("Optional(143.33333333333334)") is not equal to ("Optional(165.0)") - S-232 e-r2: 150 and 180 — the 100 at 10:33 lies in the p… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a04 | S-232 | pausedMs never attached to rounds (logging state) | red 1/1: `WatchSensorSummaryTests.testS232EachRoundIsSummarisedOverItsOwnActiveWindow` — XCTAssertEqual failed: ("nil") is not equal to ("Optional(120000.0)") - S-232 e-r2 was paused for two minutes | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a05 | S-232 | bug injected: rounds carry a step total (logging state) | red 1/1: `WatchSensorSummaryTests.testS232EachRoundIsSummarisedOverItsOwnActiveWindow` — failed: caught error: "refusing to emit a non-conformant message: semantic_violation at $.payload.events[0].steps: steps is carried only by timed entr… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a06 | S-233 | set blocks never attached to the session end (engine) | red 1/1: `WatchSensorSummaryTests.testS233TheSessionEndCarriesTheSetBlockAndTheSetsCarryNothing` — XCTUnwrap failed: expected non-nil value of type "Array<Dictionary<String, Any>>" - S-233 no set blocks | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a07 | S-233 | set-block span starts at the session start (summaries) | red 3/1: `WatchSensorSummaryTests.testS233TheSessionEndCarriesTheSetBlockAndTheSetsCarryNothing` — XCTAssertEqual failed: ("Optional("2026-09-25T10:00:00.000Z")") is not equal to ("Optional("2026-09-25T10:42:10.000Z")") - S-233 the span starts at th… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a08 | S-234 | session heart rate never computed (engine) | red 2/1: `WatchSensorSummaryTests.testS234TheSessionEndCoversTheWholeSession` — XCTAssertEqual failed: ("nil") is not equal to ("Optional(143.0)") - S-234 fifteen positive readings summing to 2145; a round's pause is not a session… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a09 | S-234 | phone lifecycle end taken from sentAt, not the payload's at (engine) | red 3/1: `WatchSensorSummaryTests.testS234APhoneEndedSessionIsSummarisedUpToWhenThePhoneEndedIt` — XCTAssertEqual failed: ("Optional("2026-09-25T10:25:00.000Z")") is not equal to ("Optional("2026-09-25T10:20:00.000Z")") - S-234 the lifecycle's own `… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a10 | S-235 | no in-window count reported as 0 steps (summaries) - no-sensors case | red 1/1: `WatchSensorSummaryTests.testS235WithTheSensorsDeniedNoEventCarriesASummary` — XCTAssertNil failed: "0" - S-235 e-run carries steps with nothing measured | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a11 | S-235 | no in-window count reported as 0 steps (summaries) - HR-only case | red 1/1: `WatchSensorSummaryTests.testS235HeartRateWithoutAStepCountSendsNoStepTotal` — XCTAssertNil failed: "0" - S-235 no count was sampled, so there is no step total — not a zero | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a12 | S-235 | a measured zero dropped (summaries) | red 1/1: `WatchSensorSummaryTests.testS235AStepCountThatDidNotMoveIsAMeasuredZero` — XCTAssertEqual failed: ("nil") is not equal to ("Optional(0.0)") - S-235 the only count in the window equals the baseline before it: a measured zero i… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a13 | S-236 | heart rate not attached to holds (logging state) | red 2/1: `WatchSensorSummaryTests.testS236AHoldIsSummarisedOverItsOwnWindow` — XCTAssertEqual failed: ("nil") is not equal to ("Optional(130.0)") - S-236 125 and 135 (its end, inclusive) | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a14 | S-237 | D-129 gate removed (engine) | red 0/1: NOT RED (0 failures) | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a14b | S-237 | the prune waits only for effort entries, and the D-129 gate is removed (engine) | red 3/1: `WatchSensorRecordingTests.testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged` — XCTAssertEqual failed: ("["sen-s-cap-1-hr-1790330700000", "sen-s-cap-1-steps-1790330700000", "sen-s-cap-1-hr-1790331000000", "sen-s-cap-1-steps-179033… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a14c | S-237 | the prune waits only for effort entries; the D-129 gate kept (engine) - the gate alone holds it | red 0/1: NOT RED (0 failures) | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a15 | S-237 | D-129 gate removed (engine) - legacy session with no end | red 2/1: `WatchSensorRecordingTests.testS237ACompletedWristSessionWithNoEndIsNeverReleased` — XCTAssertEqual failed: ("["sen-legacy"]") is not equal to ("[]") - S-237 no end, so no summary the phone holds: the readings stay | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a16 | S-237 | acknowledgements not rebuilt from receipts at restore (engine) | red 1/1: `WatchSensorRecordingTests.testS237AnEndAcknowledgedAndPrunedStillReleasesTheLog` — XCTAssertEqual failed: ("0") is not equal to ("20") - S-237 an acknowledged end still counts after it was pruned | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a17 | S-237 | gate also holds joined sessions (engine) | red 1/1: `WatchSensorRecordingTests.testS237ASessionTheWristJoinedOwesNoEnd` — XCTAssertEqual failed: ("0") is not equal to ("1") - S-237 so nothing but today's gates holds its log | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a18 | S-237 | joined sessions get an end too (engine) | red 2/1: `WatchSensorRecordingTests.testS237ASessionTheWristJoinedOwesNoEnd` — XCTAssertTrue failed - S-237 a joined session gets no end (D-120) | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a19 | S-238 | bug injected: pending re-sends recompute heart rate from current samples (engine) | red 4/1: `WatchSensorSummaryTests.testS238ALateReadingNeverRewritesWhatWasSent` — XCTAssertEqual failed: ("Optional(155.0)") is not equal to ("Optional(140.0)") - S-238 e-run is re-sent as it was logged | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a20 | S-239 | bug injected: GPS made to depend on steps permission (recorder) | red 3/1: `WatchSensorRecordingTests.testS239StepsPermissionChangesNothingButTheStepsRecorded` — XCTAssertEqual failed: ("Optional(900.0)") is not equal to ("nil") - S-239 the distance readout is identical | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a21 | S-239 | steps subscribed only without permission (recorder) | red 3/1: `WatchSensorRecordingTests.testS239StepsPermissionChangesNothingButTheStepsRecorded` — failed - S-239 with permission, the count reaches storage | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a22 | S-239 | stop no longer cancels the steps subscription (recorder) | red 1/1: `WatchSensorRecordingTests.testS239StoppingEndsTheStepsSubscription` — failed - S-239 stop cancels the steps subscription | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a23 | S-239 | readings written straight to the engine, not chained (recorder) | red 1/1: `WatchSensorRecordingTests.testS239EveryStreamReachesTheEngineOneReadingAtATime` — XCTAssertEqual failed: ("10") is not equal to ("0") - S-239 a second always-on sensor must not make two writers: every reading waits for the one befor… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a24 | S-239 | bug injected: a stored reading is emitted (engine) | red 1/1: `WatchSensorRecordingTests.testS239AppendingAStepCountEmitsNothing` — XCTAssertEqual failed: ("3") is not equal to ("1") - S-239 raw readings, steps included, never leave the wrist | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a25 | S-239 | bug injected: heart rate recorded only with steps permission (recorder) - the denied re-run | red 8/38: `WatchSensorRecordingStepsDeniedTests.testS003BeatsAreStoredAgainstTheSessionAsTheyArrive` — XCTAssertEqual failed: ("0") is not equal to ("1") | Executed 38, 0 failures; cmp ✓ sha ✓ |
| a26 | S-240 | pendingObservations reverted to the current session plus quick-logs (engine) | red 2/1: `WatchSessionEngineTests.testS240EveryUnacknowledgedObservationOfEverySessionIsResentInStoreOrder` — XCTAssertEqual failed: ("["e-b1"]") is not equal to ("["e-a1", "end-s-a", "e-b1"]") - S-240 session A's events, then B's, in the order they were store… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a27 | D-120 | the wrist's end captured after the completed row (engine) | red 2/1: `WatchSessionEngineTests.testTheWristsEndIsStoredAndSentBeforeTheSessionIsMarkedComplete` — XCTAssertEqual failed: ("[Optional("session_lifecycle"), Optional("observations_up")]") is not equal to ("[Optional("observations_up"), Optional("sess… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a28 | D-120 | no session end on the wrist's End or abandon (engine) | red 2/2: `WatchSessionEngineTests.testAbandoningASessionKeepsWhatWasAlreadyLogged` — XCTAssertEqual failed: ("["e-1", "e-2"]") is not equal to ("["e-1", "e-2", "end-s-watch-1"]") - giving up on the session does not discard work already… | Executed 2, 0 failures; cmp ✓ sha ✓ |
| a29 | D-120 | status always 'completed' (engine) | red 1/1: `WatchSessionEngineTests.testAbandoningEndsTheSessionAsAbandoned` — XCTAssertEqual failed: ("Optional("completed")") is not equal to ("Optional("abandoned")") - D-120 | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a30 | D-120 | no session end on a phone lifecycle (engine) | red 4/1: `WatchSessionEngineTests.testThePhonesLifecycleEndsAWristSessionAtTheMomentItNames` — XCTAssertEqual failed: ("0") is not equal to ("1") - D-120 the first terminal transition ends it; the second does not | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a31 | D-120 | no session end on a phone snapshot (engine) | red 2/1: `WatchSessionEngineTests.testThePhonesSnapshotEndsAWristSessionOnceAtItsSentAt` — XCTAssertEqual failed: ("0") is not equal to ("1") - D-120 one end, however often the phone says so | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a32 | D-120 | snapshot end stamped with the wrist clock, not sentAt (engine) | red 1/1: `WatchSessionEngineTests.testThePhonesSnapshotEndsAWristSessionOnceAtItsSentAt` — XCTAssertEqual failed: ("Optional("2026-07-13T06:00:00.000Z")") is not equal to ("Optional("2026-07-13T06:30:00.000Z")") - D-120 the snapshot's sentAt | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a33 | D-120 | session end id minted per append (engine) | red 1/1: `WatchSessionEngineTests.testAReopenedSessionThatEndsAgainKeepsItsFirstEnd` — XCTAssertEqual failed: ("2") is not equal to ("1") - D-120 a reopened session gets no second end | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a34 | D-120 | an acknowledged-and-pruned end forgotten (engine) | red 2/1: `WatchSessionEngineTests.testAnEndThePhoneAcknowledgedIsNeverAppendedAgainAfterAPrune` — XCTAssertNil failed: "["eventId": "end-s-watch-1", "kind": "session_end", "endedAt": "2026-07-13T06:00:00.000Z", "loggedAt": "2026-07-13T06:00:00.000Z… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a35 | D-120 | joined sessions get an end (engine) | red 1/1: `WatchSessionEngineTests.testASessionTheWristJoinedEndsWithNoEnd` — XCTAssertNil failed: "["endedAt": "2026-07-13T06:00:00.000Z", "eventId": "end-s-phone", "status": "completed", "startedAt": "2026-07-13T06:00:00.000Z"… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a36 | S-231..S-234 | round pauses not excluded (logging state) - F-CAP full replay | red 1/1: `WatchCaptureContractTests.testFCapFullUpToEndEmitsTheContractsEvents` — failed - S-231/S-232/S-233/S-234 F-CAP full, up to End: e-r2.avgHeartRateBpm is 143.33333333333334, the contract says 165 | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a37 | S-235 | no in-window count reported as 0 steps (summaries) - F-CAP no-sensors replay | red 1/1: `WatchCaptureContractTests.testFCapNoSensorsUpToEndEmitsTheContractsEvents` — XCTAssertEqual failed: ("["sessionExerciseId", "eventId", "steps", "loggedAt", "startedAt", "exerciseId", "kind", "entryId", "endedAt"]") is not equal… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a38 | D-122 b | pause interval closed at its end (summaries) | red 1/1: `WatchSensorSummaryTests.testAPauseExcludesTheInstantItBeganButNotTheInstantItEnded` — XCTAssertEqual failed: ("Optional(WatchSessionEngine.WatchHeartRateSummary(averageBpm: 100.0, maximumBpm: 100.0))") is not equal to ("Optional(WatchSe… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a39 | D-122 b | pause interval open at its start (summaries) | red 1/1: `WatchSensorSummaryTests.testAPauseExcludesTheInstantItBeganButNotTheInstantItEnded` — XCTAssertEqual failed: ("Optional(WatchSessionEngine.WatchHeartRateSummary(averageBpm: 216.66666666666666, maximumBpm: 300.0))") is not equal to ("Opt… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a40 | D-122 c | pause end ignores the timer's resume row (summaries) | red 1/1: `WatchSensorSummaryTests.testAPauseReadFromTheTimersRowsEndsWhereThatTimerRanAgain` — XCTAssertEqual failed: ("[WatchSessionEngine.WatchPauseInterval(start: 2026-09-25 10:32:00 +0000, end: 2026-09-25 10:40:00 +0000)]") is not equal to (… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a41 | D-122 c | pauses read from every timer, not the one that timed the entry (summaries) | red 1/1: `WatchSensorSummaryTests.testAPauseReadFromTheTimersRowsEndsWhereThatTimerRanAgain` — XCTAssertEqual failed: ("[WatchSessionEngine.WatchPauseInterval(start: 2026-09-25 10:32:00 +0000, end: 2026-09-25 10:34:00 +0000), WatchSessionEngine.… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a42 | D-126 | pausedMs not capped at the window (summaries) | red 1/1: `WatchSensorSummaryTests.testARoundsPauseCountsOnlyWhatFallsInsideItsWindow` — XCTAssertEqual failed: ("400000") is not equal to ("300000") - never longer than the window: the protocol refuses a longer pause, and a refused event … | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a43 | D-126 | an open pause counted past the window's end (summaries) | red 1/1: `WatchSensorSummaryTests.testARoundsPauseCountsOnlyWhatFallsInsideItsWindow` — XCTAssertEqual failed: ("300000") is not equal to ("60000") - a countdown paused after it had run out paused nothing the round contains | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a44 | D-122 d | readings below 1 bpm accepted (summaries) | red 2/1: `WatchSensorSummaryTests.testAReadingBelowOneBeatPerMinuteIsNotAHeartRate` — XCTAssertNil failed: "WatchHeartRateSummary(averageBpm: 0.5, maximumBpm: 0.5)" - the protocol's minimum is 1 bpm: a pair built from these could not be… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a45 | D-122 e | unclamped mean (summaries) | red 2/1: `WatchSensorSummaryTests.testAnAverageOfEqualReadingsNeverExceedsItsMaximum` — XCTAssertLessThanOrEqual failed: ("60.20000000000001") is greater than ("60.2") - the validator refuses an average above its maximum, and a refused ev… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a46 | D-125 | counter restart not recognised (summaries) | red 1/1: `WatchSensorSummaryTests.testAStepCounterThatRestartedAddsItsNewCount` — XCTAssertEqual failed: ("Optional(-500)") is not equal to ("Optional(700)") - D-125: 1000 → 1200 adds 200, the restart adds 300, 300 → 500 adds 200; a… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a47 | D-125 | negative counts accepted (summaries) | red 1/1: `WatchSensorSummaryTests.testAStepCounterThatRestartedAddsItsNewCount` — XCTAssertEqual failed: ("Optional(680)") is not equal to ("Optional(700)") - D-125: 1000 → 1200 adds 200, the restart adds 300, 300 → 500 adds 200; a … | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a48 | D-123 | lead-in not strictly before the first set (summaries) | red 1/1: `WatchSensorSummaryTests.testSetBlocksAreSpannedFromTheEffortBeforeTheirFirstSet` — XCTAssertEqual failed: ("[WatchSessionEngine.WatchSetBlockSpan(sessionExerciseId: "sx-a", exerciseId: "ex-sx-a", startedAt: 2026-09-25 10:05:00 +0000,… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a49 | D-123 | session-scoped entries counted as efforts (summaries) | red 1/1: `WatchSensorSummaryTests.testSetBlocksAreSpannedFromTheEffortBeforeTheirFirstSet` — XCTAssertEqual failed: ("[WatchSessionEngine.WatchSetBlockSpan(sessionExerciseId: "sx-a", exerciseId: "ex-sx-a", startedAt: 2026-09-25 10:04:00 +0000,… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| a50 | item 1 | the two session-scoped kinds left out of `all` (records) | red 1/1: `WatchNutritionQuickLogTests.testTheKindsTheWristCanEmitAreAClosedSet` — XCTAssertEqual failed: ("["nutrition_quick_log", "hold", "round", "set", "timed"]") is not equal to ("["round", "session_end", "set", "effort_rating",… | Executed 1, 0 failures; cmp ✓ sha ✓ |

What the misses show, recorded rather than dropped:
- **a05 is red on a refusal, not on its S-232 assertion.** A round carrying `steps` is refused by the protocol validator
  (Phase 1's placement rule) before the event is stored, so the log throws and the test fails on the caught error. The
  S-232 "no round carries steps" assertion is a second line behind the protocol's own.
- **a14 and a14c stay green, by design — the two gates overlap.** A stored `session_end` is itself an observation of its
  session, so today's receipt gate already holds the log until it is acknowledged (a14: D-129 gate removed, still
  green). Narrowing the receipt gate to effort entries leaves D-129 holding it (a14c: still green). Only removing both
  releases the log early (a14b: red). D-129 is the only guard when no end exists at all (a15: red, the seeded legacy
  session).
- **a25's red is in inherited tests.** It is S-239's re-run of the whole sensor class with steps denied; the failing
  assertions (8 of 38) are the existing tests', which carry no S-id of this plan. The class that re-runs them does.
- **a39 was first not red** (the harness logged it): the test's readings 100/200/300 average to 200 with or without the
  pause-start reading. The middle reading was changed to 250 so the boundary shows; a38 and a39 were then re-run, both red.
- **a21 was first red only through `eventually`'s default message**; the wait was given an S-239 message and re-run.

Assertion-change table (line numbers before the change; each is a new exact expectation, none is loosened):

| File:line (before) | Before | After | Rule |
|---|---|---|---|
| `WatchNutritionQuickLogTests.swift:588` | `Set(["set", "timed", "round", "hold", WatchObservationKind.nutritionQuickLog])` | the same seven-kind set plus `"effort_rating", "session_end"` — exact | Plan 4a item 1 (D-116, D-120) |
| `WatchSessionEngineTests.swift:489` | `["e-1", "e-2"]` | `["e-1", "e-2", "end-s-watch-1"]` — exact; the message gains "and the session's end records that it was abandoned (D-120)" | D-120 |
| `WatchSensorRecordingTests.swift:512` | `XCTAssertEqual(engine.observations.count, 1)` | `XCTAssertEqual(engine.observations.count, 2, "e-1 and the session's end (D-120) are untouched")` — exact | D-120 |

Setup-only edits (no assertion touched): the two existing prune tests confirm `end-<sid>` explicitly (D-129).
`testASettledSessionReleasesItsLogAndARunningOneKeepsIt` keeps `released.count == 1`;
`testAnEntryStillOwedToThePhoneHoldsTheLogBack` keeps `released` empty, and with the end acknowledged the unacknowledged
entry is now the only thing holding the log. `FakeSensorSource` gains the steps seam; `WatchSensorRecordingTests` is no
longer `final` and reads its steps grant from `class var stepsGrant` in `setUp`, so the S-239 subclass can re-run it.
`testAReadingIsStoredWithoutBeingSentAnywhere` is byte-identical.

Footprint versus Predicted Files: touched as predicted — `WatchRecords.swift`, `WatchSensorRecording.swift`,
`WatchSensorSummaries.swift` (new), `WatchSessionEngine.swift`, `WatchLoggingState.swift`, `WatchSensorSummaryTests.swift`
(new), `WatchSensorRecordingTests.swift`, `WatchSessionEngineTests.swift`, `WatchNutritionQuickLogTests.swift`,
`services_and_utils.md`. Differences (A-36, A-37): `WatchCaptureContractTests.swift` created here although predicted for
4b; `Fixtures.swift` untouched (Phase 1's `captureContract()` loader suffices); `WatchLiveMirroringTests.swift` untouched
(no emitted count there changed); `watch_session_capture.md` did not exist when 4a started — the Dart run created it
during this phase — so its "The wrist half" section and the `session end` / `set block` vocabulary were added at the end
of 4a, and the `session_end` invariant and those two vocabulary entries moved there from `services_and_utils.md` (one
owner each, documentation standard §3.8). Docs: `flutter test test/docs_indexing_contract_test.dart` →
`00:00 +9: All tests passed!`; `watch_session_capture.md` 11,221 B and `services_and_utils.md` 45,464 B, both under the
band. Line endings: every touched Swift file and both docs are LF (0 CR), as before.

### Phase 4b: Wrist preferences and rating prompt (@developer, Swift)

Needs Phases 1 and 4a. Implements D-113 (wrist half), D-114 and D-116 – D-119.

1. [x] Preferences: a new stored record type (a `StoredWatchRecord` case plus a
   `WatchStoreContents` field) and its owner.
   - `WatchSyncOrchestrator.swift` routes `preferences_down` through the incoming gate.
   - The latest `generatedAt` wins, with later-received winning ties.
2. [x] Rating state (a new file; logic lives outside `#if os(watchOS)`):
   - an End action that finishes the session and writes the owed marker durably (D-117);
   - owed-prompt derivation from stored rows, across sessions, most recent first;
   - the selection model (D-118);
   - confirm appends `effort_rating` through the engine's append path (D-116);
   - no skip, dismiss or back;
   - copy and scale read from and asserted against `watch_effort_rating_contract.json`.
3. [x] SwiftUI, behind `#if os(watchOS)`: the prompt view and the End-control view, which only
   bind to the state (D-119). The views hold no logic.
4. [x] Structural guard: a new test source-scans the rating state and view files. It fails on
   any `func`, property or `Button` label that starts with or equals skip, dismiss, cancel,
   close, later or not now. `testS004…` stays green.
5. [x] Tests:
   - new `WatchEffortRatingTests.swift`: S-211 – S-220;
   - new `WatchCaptureContractTests.swift`: the Swift half of F-CAP (all three cases, from the
     timeline to emitted events equal to `expectedEvents`, exactly);
   - orchestrator routing: `preferences_down` is applied; a malformed one is refused with no
     state change (in `WatchSessionStartPathsTests.swift` or `WatchLiveMirroringTests.swift`).
6. [x] Docs: the rating and preferences sections of `watch_session_capture.md`.

**Done Criteria:**
- `flutter analyze`.
- `flutter test`: full summary line, count unchanged.
- `swift test`: full count, 0 failures.
- `swift test --filter WatchEffortRatingTests` and `--filter WatchCaptureContractTests`.
- Red→green evidence for S-211 – S-220 and the F-CAP replay. For example: skip the owed marker
  → S-215 fails; remove the newest-wins rule → S-214 (C) fails; allow a second append → S-218
  fails.
- The structural guard is shown red by temporarily adding a `func dismiss()` to the scanned
  file, then restored.
- An assertion-change table.

**Predicted Files:**
- `watch/watchos/Sources/WatchSessionEngine/WatchPhonePreferences.swift` (new; name is free)
- `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift` (new; name is free)
- `watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift` (new;
  `#if os(watchOS)`; name is free)
- `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionStore.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift` (new)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchCaptureContractTests.swift` (new)
- `watch/watchos/Tests/WatchSessionEngineTests/Fixtures.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` or
  `WatchLiveMirroringTests.swift`
- `docs/watch_session_capture.md`

**Phase 4b verification notes (@developer, 2026-09-26):**

Start of phase: the Phase 4a state (uncommitted), `swift test` `Executed 222 tests, with 0 failures`. The Dart run committed
Phases 3a/3b as `282ebc3` while 4b was in progress; that commit also carries this run's Phase 4a doc and plan edits (the
"Watch Sensors" changes in `services_and_utils.md`, "The wrist half" in `watch_session_capture.md`, the Phase 4a
verification notes and A-25 – A-38), but none of the Swift — every `watch/watchos/` change of 4a and 4b is still
uncommitted. No Dart file was touched in 4a or 4b.

| Check | Start of phase | After Phase 4b | Delta explained |
|---|---|---|---|
| `cd watch/watchos && swift test` | `Executed 222 tests, with 0 failures` | `Executed 241 tests, with 0 failures (0 unexpected) in 0.846 (0.859) seconds` | +19, all new: `WatchEffortRatingTests` 13 (S-211 – S-220, the contract's never-synced rule, the structural guard); `WatchCaptureContractTests` +3 (`full`, `no-sensors`, `prompt-off`, every event exact); `WatchSessionStartPathsTests` +3 (routing, refusal, newest-wins). No existing assertion changed |
| `swift test --filter WatchEffortRatingTests` | — | `Executed 13 tests, with 0 failures` | — |
| `swift test --filter WatchCaptureContractTests` | — | `Executed 5 tests, with 0 failures` | the two 4a replays up to End, and the three 4b cases |
| watchOS type-check (as in 4a) | exit 0, 0 errors | exit 0, 0 errors or warnings | `WatchEffortRatingView` and `WatchEndSessionView` compile for watchOS; `swift test` cannot build them |
| `testS004NoMutatingOperationExistsAnywhereInTheModule` | green | green, unedited | the store's public surface is unchanged |
| `flutter analyze` (once, at the end) | `242 issues found.` (the 3b figure) | `242 issues found. (ran in 2.5s)` | no Dart change |
| `flutter test` (once, at the end; the full suite) | `01:05 +2950 ~1: All tests passed!` (after 3b) | `01:08 +2950 ~1: All tests passed!` (exit 0) | unchanged, as both phases' Done Criteria require; it includes `test/docs_indexing_contract_test.dart`, `test/watch_capture_contract_conformance_test.dart` and `test/sync_protocol_fixtures_test.dart` |
| `git status --porcelain lib/watch watch/contract watch/sync_protocol` | empty | empty | D-101; no shared file was changed by 4a or 4b |

Red→green, by copy-and-restore, never `git stash`, with the 4a harness; cases `<scratchpad>/pr2_p4b_cases.py`. Every
restore matched (`cmp` and shasum); no red log holds a compile error; every green re-run is `0 failures`.

| # | S-id | Behaviour reverted or bug injected (file) | Red — failing test and assertion | Green |
|---|---|---|---|---|
| b01 | S-211 | the owed prompt is never noted at End (rating state) | red 4/1: `WatchEffortRatingTests.testS211AnEndThatOwesARatingAsksForItAndRecordsOneAnswer` — XCTAssertEqual failed: ("[]") is not equal to ("["s-r-1"]") - S-211 a prompt is owed for s-r-1 | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b02 | S-211 | a number preselected (rating state) | red 8/1: `WatchEffortRatingTests.testS211AnEndThatOwesARatingAsksForItAndRecordsOneAnswer` — XCTAssertNil failed: "3" - S-211 nothing is preselected | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b03 | S-211 | Confirm enabled with nothing selected (rating state) | red 1/1: `WatchEffortRatingTests.testS211AnEndThatOwesARatingAsksForItAndRecordsOneAnswer` — XCTAssertFalse failed - S-211 Confirm is disabled while nothing is selected | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b04 | S-211 | confirm records nothing (rating state) | red 2/1: `WatchEffortRatingTests.testS211AnEndThatOwesARatingAsksForItAndRecordsOneAnswer` — XCTAssertEqual failed: ("0") is not equal to ("1") - S-211 exactly one effort_rating | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b05 | S-211 | the question differs from the contract's (copy) | red 1/1: `WatchEffortRatingTests.testS211AnEndThatOwesARatingAsksForItAndRecordsOneAnswer` — XCTAssertEqual failed: ("Optional("How hard was it?")") is not equal to ("Optional("How hard was this session?")") - S-211 the contract's question | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b06 | S-212 | the owed decision ignores the phone's setting (rating state) | red 1/1: `WatchEffortRatingTests.testS212WithTheSettingOffTheEndOwesNothing` — XCTAssertFalse failed - S-212 the phone's setting is off | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b07 | S-213 | a never-synced wrist asks (preferences) | red 1/1: `WatchEffortRatingTests.testS213AWristThatNeverSyncedDoesNotAsk` — XCTAssertFalse failed - S-213 no preferences record: the setting is unknown, so no prompt | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b08 | S-214 | newest-wins removed: a late older copy stored, and the last received applies (preferences) | red 1/1: `WatchEffortRatingTests.testS214TheSettingArrivesAtSyncAndIsHonouredFromThenOn` — XCTAssertEqual failed: ("["s-b"]") is not equal to ("["s-c", "s-b"]") - S-214 C: a stale copy arriving late changes nothing; owed prompts come most re… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b09 | D-113 | newest-wins removed (preferences) - the routing tie/older test | red 2/1: `WatchSessionStartPathsTests.testTheNewestPreferencesApplyAndALaterCopyWinsATie` — XCTAssertFalse failed - D-113 an older copy arriving late never replaces a newer one | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b10 | S-215 | the owed prompt held only in memory, never stored (rating state) | red 3/1: `WatchEffortRatingTests.testS215AKillDuringThePromptAsksAgainAndRecordsOneAnswer` — XCTAssertEqual failed: ("[]") is not equal to ("["s-r-1"]") - S-215 the prompt was stored at End, so the relaunch still owes it | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b11 | S-216 | bug injected: any completed session without a rating owes a prompt (rating state) | red 1/1: `WatchEffortRatingTests.testS216ThePhonesLifecycleEndingItOwesNoPrompt` — XCTAssertFalse failed - S-216 a completion from the phone never owes a prompt | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b12 | S-217 | bug injected: any completed session without a rating owes a prompt (rating state) | red 1/1: `WatchEffortRatingTests.testS217ThePhonesSnapshotEndingItOwesNoPromptAndOneEnd` — XCTAssertFalse failed - S-217 a completion from the phone never owes a prompt | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b13 | S-218 | the engine allows a second rating append (engine) | red 1/1: `WatchEffortRatingTests.testS218TheWristNeverChangesARating` — XCTAssertNil failed: "WatchObservationRecord(recordId: "rating-s-r-1", sessionId: "s-r-1", recordedAt: 2026-09-25 10:10:00 +0000, sequence: 7, kind: "… | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b14 | S-219 | the first clockwise detent picks 2 (rating state) | red 2/1: `WatchEffortRatingTests.testS219TheCrownAndTheScaleMapToTheseNumbers` — XCTAssertEqual failed: ("Optional(2)") is not equal to ("Optional(1)") - S-219 +1 detent from unselected → 1 | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b15 | S-219 | counter-clockwise from nothing picks something (rating state) | red 2/1: `WatchEffortRatingTests.testS219TheCrownAndTheScaleMapToTheseNumbers` — XCTAssertNil failed: "-1" - S-219 counter-clockwise from nothing picks nothing | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b16 | S-219 | no clamp at the ends of the scale (rating state) | red 4/1: `WatchEffortRatingTests.testS219TheCrownAndTheScaleMapToTheseNumbers` — XCTAssertEqual failed: ("Optional(9)") is not equal to ("Optional(5)") - S-219 +5 → 5, clamped | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b17 | S-219 | crown travel short of a detent dropped (rating state) | red 1/1: `WatchEffortRatingTests.testS219TheCrownAndTheScaleMapToTheseNumbers` — XCTAssertEqual failed: ("Optional(1)") is not equal to ("Optional(2)") - S-219 the carried half and this one make a detent | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b18 | S-220 | the at-least-one-effort rule removed (rating state) | red 1/1: `WatchEffortRatingTests.testS220AnEmptySessionOwesNoPrompt` — XCTAssertFalse failed - S-220 nothing was logged, so nothing is asked | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b19 | S-220 | efforts counted before the phone's deletions (rating state) | red 1/1: `WatchEffortRatingTests.testS220ASessionWhoseOnlySetThePhoneDeletedOwesNoPrompt` — XCTAssertFalse failed - S-220 the phone deleted the only set, so nothing is asked | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b20 | D-118 guard | a `func dismiss()` added to the rating state | red 1/1: `WatchEffortRatingTests.testTheRatingOffersNoWayOutButAnAnswer` — failed - S-211 WatchEffortRating.swift declares `dismiss`: the prompt offers no way out but an answer (D-118) | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b21 | D-118 guard | a "Not now" button added to the prompt view | red 1/1: `WatchEffortRatingTests.testTheRatingOffersNoWayOutButAnAnswer` — failed - S-211 WatchEffortRatingView.swift has a "Not now" button: the prompt offers no way out but an answer (D-118) | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b22 | F-CAP | the rating stamped a second late (engine) | red 1/1: `WatchCaptureContractTests.testFCapFullEmitsExactlyTheContractsEvents` — failed - F-CAP full: rating-s-cap-1.loggedAt is "2026-09-25T10:55:21.000Z", the contract says "2026-09-25T10:55:20.000Z" | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b23 | F-CAP | the owed decision ignores the phone's setting (rating state) - prompt-off case | red 1/1: `WatchCaptureContractTests.testFCapPromptOffEmitsExactlyTheContractsEvents` — XCTAssertFalse failed - F-CAP prompt-off: the setting is off, so nothing is owed | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b24 | F-CAP | the answer recorded one lower (rating state) | red 1/1: `WatchCaptureContractTests.testFCapNoSensorsEmitsExactlyTheContractsEvents` — failed - F-CAP no-sensors: rating-s-cap-1.rating is 3, the contract says 4 | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b25 | D-113 | the orchestrator no longer routes preferences_down | red 3/1: `WatchSessionStartPathsTests.testThePhonesPreferencesAreRoutedStoredAndReadBackAfterARelaunch` — XCTAssertTrue failed - D-113 the orchestrator routes preferences_down to the preferences | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b26 | D-113 | the incoming gate skipped for preferences_down (preferences) | red 3/1: `WatchSessionStartPathsTests.testAPreferencesDownTheWristCannotReadIsRefusedAndChangesNothing` — XCTAssertFalse failed - D-113 a copy the wrist cannot read is refused | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b27 | D-113 | preferences not read back at launch (preferences) | red 1/1: `WatchSessionStartPathsTests.testThePhonesPreferencesAreRoutedStoredAndReadBackAfterARelaunch` — XCTAssertEqual failed: ("nil") is not equal to ("Optional(false)") - D-113 the setting is stored, so a relaunch still knows it | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b28 | D-113 | a tie goes to the first-received copy (preferences) | red 2/1: `WatchSessionStartPathsTests.testTheNewestPreferencesApplyAndALaterCopyWinsATie` — XCTAssertTrue failed - D-113 on a tie, the later-received copy applies | Executed 1, 0 failures; cmp ✓ sha ✓ |
| b29 | D-114 | the never-synced default differs from the contract's (copy) | red 1/1: `WatchEffortRatingTests.testWhetherANeverSyncedWristAsksIsTheContracts` — XCTAssertEqual failed: ("Optional(true)") is not equal to ("Optional(false)") - D-114 | Executed 1, 0 failures; cmp ✓ sha ✓ |

The one miss, recorded rather than dropped: **b08 was first not red.** S-214's stale copy was built with the same
content-derived message id as the first copy (A-22), so it was a byte-identical redelivery — a store no-op whatever the
newest-wins rule says. The test now sends the stale copy under its own id (the copy the rule exists for), and b08 was
re-run: red on `S-214 C: a stale copy arriving late changes nothing`, then green.

Assertion-change table: **empty.** No pre-existing assertion was modified. Construction-only edits: `WatchStartHarness`
builds a `WatchPhonePreferences`, restores it in `launch()` and passes it to its orchestrator; the F-CAP replay driver
(new in 4a) now delivers `preferences` through the orchestrator, ends through `WatchEffortRatingState.end()` and handles
`answer`, which leaves the two 4a replays' expectations untouched and green.

Footprint versus Predicted Files: every predicted file was touched — `WatchPhonePreferences.swift`, `WatchEffortRating.swift`
and `WatchEffortRatingView.swift` (new), `WatchRecords.swift`, `WatchSessionStore.swift`, `WatchSessionEngine.swift`,
`WatchSyncOrchestrator.swift`, `WatchEffortRatingTests.swift` (new), `WatchCaptureContractTests.swift` (created in 4a,
A-36), `Fixtures.swift` (the effort-rating contract loader), `WatchSessionStartPathsTests.swift`, and
`watch_session_capture.md` (the rating and preferences structure rows, rationale, invariants and vocabulary, 14,395 B).
Nothing else. Line endings: every touched Swift file and the doc are LF (0 CR).

### Phase 5: Phone-ended prompt and Summary integration (@developer) — precondition met (PR 1 is on `develop` and on this branch)

Needs Phase 3b, and PR 1 merged into `develop` with this branch rebased onto it (D-143).
Implements D-139 (UI) and D-143 (parity).

0. [x] Precondition. Record in Progress the `develop` commit that contains PR 1. Evidence: the
   Session Summary sheet title reads "How hard was this session?". If the precondition fails,
   mark Phase 5 BLOCKED in Progress and go on to Phase 6, leaving 6.1 open.
1. [x] `lib/features/session/live_session_screen.dart`: D-139.
   - The phone's own Finish on an active session, with the setting on, shows PR 1's sheet.
   - The answer goes through the Phase 3b phone-rating API.
   - A session the wrist completed shows the completed state, with no Finish and no sheet.
2. [x] Reuse PR 1's sheet widget. Extract it to a shared widget only if it can't be reused
   as-is. The extraction must cause zero visual change and leave its existing tests unedited.
3. [x] Tests:
   - new `test/live_session_effort_rating_test.dart`: S-281 – S-284;
   - new `test/watch_session_summary_integration_test.dart`: S-285 and S-286;
   - new `test/watch_effort_rating_copy_parity_test.dart`: S-287.
4. [x] Docs: `docs/session_summary.md` (watch-rated sessions; phone-final rule)
   and `watch_session_capture.md`.

**Done Criteria:**
- `flutter analyze`.
- `flutter test`: full summary line.
- `swift test`: count unchanged.
- The Phase 5 test files, plus PR 1's Summary tests, unedited.
- Red→green evidence for S-281 – S-287.
- An assertion-change table.

**Predicted Files:**
- `lib/features/session/live_session_screen.dart`
- `lib/state/watch/watch_session_inbox.dart` (only if the API needs a touch-up)
- PR 1's sheet file (only for extraction)
- `test/live_session_effort_rating_test.dart` (new)
- `test/watch_session_summary_integration_test.dart` (new)
- `test/watch_effort_rating_copy_parity_test.dart` (new)
- `docs/session_summary.md`
- `docs/watch_session_capture.md`

**Phase 5 verification notes (@developer, 2026-09-26):**

Precondition (item 0): PR 1 is `dcfe474` + `ae71e23`. `develop` is at `ae71e23`
(`git branch --contains ae71e23` → `develop`, `feature/stats-pr2-watch-capture`), and both commits are ancestors of this
branch's HEAD `4e54ca8` (`git merge-base --is-ancestor` true for each), so no rebase was needed. Evidence of PR 1's sheet:
`git show dcfe474:lib/features/session/session_summary_screen.dart` holds the question "How hard was this session?", which
S-287 now asserts against `watch/contract/watch_effort_rating_contract.json`.

Start of phase: HEAD `4e54ca8`, clean tree. `flutter test` `01:04 +2950 ~1: All tests passed!`, `swift test` `Executed 241 tests,
with 0 failures`, `flutter analyze` `242 issues found.` (output captured for the diff below).

| Check | Start of phase | After Phase 5 | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found. (ran in 2.7s)` | `242 issues found. (ran in 2.0s)` | A line-number-insensitive diff shows exactly the five `withOpacity` `deprecated_member_use` infos of PR 1's sheet leaving `lib/features/session/session_summary_screen.dart` and appearing in `lib/widgets/session/effort_rating_sheet.dart`: the same code, moved (A-64). No other diagnostic changed |
| `flutter test` | `01:04 +2950 ~1: All tests passed!` | `01:07 +2959 ~1: All tests passed!` (exit 0) | +9, all new: 5 in `test/live_session_effort_rating_test.dart` (S-281, S-282, S-283, S-284, A-62), 2 in `test/watch_session_summary_integration_test.dart` (S-285, S-286), 2 in `test/watch_effort_rating_copy_parity_test.dart` (S-287 ×2). `test/watch_transport_test.dart` changed in construction only (below) |
| `cd watch/watchos && swift test` | `Executed 241 tests, with 0 failures` | `Executed 241 tests, with 0 failures (0 unexpected) in 0.870 (0.883) seconds` | Unchanged; nothing under `watch/` changed |
| Phase 5 files + PR 1's Summary tests and the live-screen suites, unedited: `flutter test test/session_summary_effort_row_test.dart test/screen_widget_test.dart test/interaction_flow_test.dart test/header_standardization_test.dart test/session_finish_timers_test.dart test/calendar_summary_screen_bugs_test.dart test/live_session_capture_entries_test.dart test/phone_manage_bridge_test.dart test/in_session_pr_toast_test.dart test/watch_transport_test.dart test/live_mirroring_test.dart test/watch_session_import_test.dart test/home_logo_hub_open_test.dart test/widget_test.dart` | — | `00:12 +575: All tests passed!` | `git diff --stat` on PR 1's four Summary test files is empty |
| The three Phase 5 files | — | `00:01 +9: All tests passed!` | — |
| `flutter test test/docs_indexing_contract_test.dart` | — | `00:00 +9: All tests passed!` | `watch_session_capture.md` 16,004 B, `services_and_utils.md` 45,607 B, `session_summary.md` 12,095 B, `navigation_and_screens.md` 23,572 B, `widget_catalog/session_widgets.md` 13,385 B — all under the band |
| `git status --porcelain lib/watch watch` | empty | empty | D-101 |

Red run before any implementation (tests written first): `test/live_session_effort_rating_test.dart` and
`test/watch_effort_rating_copy_parity_test.dart` did not compile (`No named parameter with the name 'watchSessionRatings'`,
`Undefined name 'EffortRatingSheet'`, `Error when reading 'lib/widgets/session/effort_rating_sheet.dart'`) — not counted as red.
`test/watch_session_summary_integration_test.dart` passed before any change (`+2`): S-285 and S-286 verify that PR 1's Summary
already rates an imported session (Phase 3b made it an ordinary `TrainingSession`), so their reds are by mutation (p08 – p11).

Zero visual change (item 2): a temporary golden test captured PR 1's automatic prompt, the prompt mid-tap on 3, the summary
after the answer, and the Change sheet on a rated past session (pre-selected 4, date subtitle), all rendered with the extracted
`EffortRatingSheet` (`--update-goldens`, `+2`). The pre-change `session_summary_screen.dart` (`git show HEAD:…`, with its private
`_FeelingSheetContent`) was then swapped in and compared against those images: `+2: All tests passed!`, pixel-identical. Negative
control: with the extracted sheet's tile radius changed by 2 px the same comparison fails (`Pixel test failed, 0.13%, 1204px diff
detected`, `-2`). Every file was restored and proven (`cmp`, matching shasum); the temporary test and images were deleted.

Red→green by copy-and-restore, never `git stash`. Harness `<scratchpad>/pr2_redgreen.py`, cases `<scratchpad>/pr2_p5_cases.json`,
logs `<scratchpad>/pr2-p5-redgreen/`. Per case: shasum and copy each file, apply one textual mutation (asserted to occur exactly
once, confirmed in the file with a changed shasum), run the one test by `--plain-name`, require a failure whose log holds the
expected S-id reason and no compile error, copy back, prove the restore with `cmp` and a matching shasum, re-run green. All 15
were red on their S-id assertion (`+0 -1`), restored and green (`+1: All tests passed!`); `shasum -c` over the five mutated files
matched the pre-run snapshot afterwards.

| # | S-id | Behaviour reverted or bug injected (file) | Red — failing assertion ; reason | Green |
|---|---|---|---|---|
| p01 | S-281 | the phone's Finish never asks (screen) | Expected: exactly one matching candidate / Actual: Found 0 widgets with type "EffortRatingSheet" ; `S-281 the phone’s Finish shows PR 1’s effort-rating sheet` | `+1` |
| p02 | S-281 | the question can be dismissed: `mustAnswer: false` (screen) | Expected: exactly one matching candidate / Actual: Found 0 widgets with type "EffortRatingSheet" ; `S-281 a tap outside the sheet does not close it` | `+1` |
| p03 | S-281 | the answer is not recorded (screen) | Expected: <3> / Actual: <null> ; `S-281 nothing is imported yet, so the answer is staged as the phone’s own rating` | `+1` |
| p04 | A-62 | a session with nothing logged is asked too (screen) | Expected: no matching candidates / Actual: Found 1 widget with type "EffortRatingSheet" ; `A-62 an empty session is never history (D-133), so it is not rated …` | `+1` |
| p05 | S-282 | the Effort Rating setting ignored (screen) | Expected: no matching candidates / Actual: Found 1 widget with type "EffortRatingSheet" ; `S-282 with the setting off there is no sheet` | `+1` |
| p06 | S-283 | a session the wrist completed is shown running, with Finish (screen) | Expected: exactly one matching candidate / Actual: Found 0 widgets with key [<'live_session_completed'>] ; `S-283 the screen shows the completed state` | `+1` |
| p07 | S-284 | the answer staged even after the import (inbox) | Expected: null / Actual: <Instance of 'WatchInboxEntry'> ; `S-284 directly: nothing is staged for an imported session` | `+1` |
| p08 | S-285 | the Summary's sheet saves nothing (Summary) | Expected: exactly one matching candidate / Actual: Found 0 widgets with text "4 / 5" ; `S-285 added` | `+1` |
| p09 | S-285 | the day list not refreshed after a rating (Summary) | Expected: Color(… step 4 …) / Actual: <null> ; `S-285 the day list shows the new rating on return` | `+1` |
| p10 | S-286 | a wrist rating arriving after the end never applied (importer top-up) | Expected: <4> / Actual: <null> ; `S-286 the import carries the wrist’s rating` | `+1` |
| p11 | S-286 | the EFFORT row misreads the rating (Summary) | Expected: exactly one matching candidate / Actual: Found 0 widgets with text "4 / 5" ; `S-286 the EFFORT row shows the wrist’s rating` | `+1` |
| p12 | S-287 | the question differs from the contract (sheet) | Expected: 'How hard was this session?' / Actual: 'How hard was it?' ; `S-287 the sheet asks the contract’s question` | `+1` |
| p13 | S-287 | the scale stops at 4 (sheet) | Expected: [1, 2, 3, 4, 5] / Actual: [1, 2, 3, 4] ; `S-287 one tile per point of the contract’s scale, in order` | `+1` |
| p14 | S-287 | the low end's label differs (sheet) | Expected: ['Very easy', 'Max effort'] / Actual: ['Easy', 'Max effort'] ; `S-287 the end labels are the contract’s, and the last words` | `+1` |
| p15 | S-287 | the Summary's automatic prompt not opened (Summary) | Expected: exactly one matching candidate / Actual: Found 0 widgets with type "EffortRatingSheet" ; `S-287 PR 1’s automatic prompt is the shared sheet, …` | `+1` |

Assertion-change table: **empty.** No pre-existing assertion, expectation or fixture was modified. Construction-only edit:
`test/watch_transport_test.dart` (`git diff --numstat`: 2 additions, 2 deletions) reads the mirror out of the graph
`createWatchSync` now returns — `phoneMirror = (await createWatchSync(…))?.mirror;` — and its S-006 `expect(none, isNull)` is
untouched and green.

Footprint versus Predicted Files:
- Predicted and touched: `lib/features/session/live_session_screen.dart`, `lib/state/watch/watch_session_inbox.dart` (the
  `WatchSessionRatings` interface it implements), PR 1's sheet file `lib/features/session/session_summary_screen.dart`
  (extraction), the three new test files, `docs/session_summary.md`, `docs/watch_session_capture.md`.
- Extra (A-63, A-64, A-67): `lib/widgets/session/effort_rating_sheet.dart` (new, the extraction's target);
  `lib/state/watch/watch_sync_wiring.dart`, `lib/main.dart`, `lib/app.dart`, `lib/features/home/home_screen.dart`,
  `lib/state/watch/live_session_mirror_debug_main.dart` (A-50's wiring); `test/watch_transport_test.dart` (construction only);
  `docs/state_management/services_and_utils.md` and `navigation_and_screens.md` (claims the wiring made false),
  `widget_catalog.md` and `widget_catalog/session_widgets.md` (the new reusable widget).

Line endings: `lib/main.dart` 416/416 CRLF (was 415/415; one CRLF line added), `lib/app.dart` 439/439 CRLF (was 432/432; seven
CRLF lines added); every other touched file is LF, as it was. `git diff --numstat` shows no whole-file rewrite.

### Phase 6: Docs consolidation, release gate, residue sweep and closure (@developer)

Needs all previous phases. If Phase 5 is blocked, item 6.1 stays open until it lands.

1. [x] Complete `docs/watch_session_capture.md` as the consolidated feature doc:
   - structure: which component owns preferences, the prompt, summaries, `session_end`, the
     inbox and the import;
   - rationale: D-110, D-116, D-120, D-121, D-131, D-132;
   - invariants, each naming its enforcing test;
   - vocabulary: effort rating, session end, set block, session-scoped kind, watch session
     inbox, tombstone.

   Update the README index entry. Trim `services_and_utils.md` to pointers if it nears the band.
   (6.1: the phone-ended prompt part, after Phase 5.)
2. [x] `docs/watch-app-setup-and-qa.md`: on-device QA checks for items 2 and 3. They wait on
   shipping-plan Phases 7 and 8; see O-1 and O-2.
3. [x] `docs/plans/2026-09-21-13-watch-integration-shipping.md`: add the O-1 items to
   the Phase 7 checklist and the steps binding plus the latency check (O-2) to Phase 8.
4. [x] D-144: `scripts/pre_release_check.sh` runs `swift test` in `watch/watchos/`. Keep
   `test/pre_release_gate_*_test.dart` green. If they pin the step list, update them to the new
   exact list.
5. [x] Residue sweep. Run each command and paste the output, with the expected result:
   - `grep -rln "TrainingSession(" lib/state/watch lib/core/sync_protocol lib/core/services` →
     only the importer creates sessions from wrist data.
   - `grep -rn "metric-heart-rate" lib` → only `lib/mock/seed_data.dart` (O-9).
   - `grep -rn "show_feeling_survey" lib` → only `lib/state/settings/settings_state.dart`
     (D-115).
   - `grep -rn "answers nothing\|stays quiet\|never sent\|stored, never" docs watch/sync_protocol/PROTOCOL.md`
     → each remaining hit is still true.
   - `git status --porcelain lib/watch` → only `watch_records.dart` changed across the PR
     (D-101, D-127).
   - A table mapping every S-2xx ID in this plan to its tests. Produce it with
     `grep -rhoE "S-2[0-9]{2}" test watch/watchos/Tests | sort -u`; every scenario appears.
6. [x] Final full runs (flutter and swift), Progress closure, and an Assumption Log summary for
   the reviewer.

**Done Criteria:**
- `flutter analyze`.
- `flutter test`: full summary line.
- `swift test`: full count.
- `flutter test test/docs_indexing_contract_test.dart test/pre_release_gate_ios_artifact_test.dart test/pre_release_gate_notification_and_build_test.dart test/pre_release_gate_upload_destination_test.dart`.
- `./scripts/pre_release_check.sh --fast` shows the new step (or a logged skip).
- S-291 – S-293 evidence.
- The residue outputs, pasted.

**Predicted Files:**
- `docs/watch_session_capture.md`
- `docs/README.md`
- `docs/state_management/services_and_utils.md`
- `docs/watch-app-setup-and-qa.md`
- `docs/plans/2026-09-21-13-watch-integration-shipping.md`
- `scripts/pre_release_check.sh`
- `test/pre_release_gate_*_test.dart` (only if they pin the step list)
- this plan (Progress)

**Phase 6 verification notes (@developer, 2026-09-26):**

Start of phase: the Phase 5 state (uncommitted), `flutter test` `01:07 +2959 ~1`, `swift test` 241, analyze 242.

| Check | Start of phase | After Phase 6 | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` | `242 issues found. (ran in 2.6s)` | Line-number-insensitive diff against the start of Phase 5: only the five infos A-64 moved; nothing new in Phase 6 |
| `flutter test` | `01:07 +2959 ~1: All tests passed!` | `01:07 +2973 ~1: All tests passed!` (exit 0) | +14, all new: 9 in the `A-51` group of `test/watch_session_import_test.dart`, 5 in the new `test/pre_release_gate_swift_test.dart` (S-293). No existing test changed |
| `cd watch/watchos && swift test` | `Executed 241 tests, with 0 failures` | `Executed 241 tests, with 0 failures (0 unexpected) in 0.864 (0.880) seconds` | Unchanged; nothing under `watch/` changed in PR 2's Phases 5 and 6 |
| `flutter test test/docs_indexing_contract_test.dart test/pre_release_gate_ios_artifact_test.dart test/pre_release_gate_notification_and_build_test.dart test/pre_release_gate_upload_destination_test.dart test/pre_release_gate_swift_test.dart` | — | `00:20 +42: All tests passed!` | 9 docs-contract + 28 existing gate + 5 new gate tests |
| `bash scripts/pre_release_check.sh --fast` | — | `⚠  Skipping swift test for watch/watchos (--fast). Do NOT archive from a --fast run.` (the new step's logged skip); exit 1 on one blocking error, `✗ iOS reporting destination cannot be verified: … no IPA at build/ios/ipa/*.ipa` | Pre-existing and unrelated: the committed script (`git show HEAD:scripts/pre_release_check.sh`) run the same way gives the identical single ✗ and exit 1 — no IPA is built on this host. On this host only iOS is in scope, so the run built nothing |
| `git status --porcelain lib/watch watch` | empty | empty | D-101 |

**S-291 — docs contract.** `test/docs_indexing_contract_test.dart` is green (above). `watch_session_capture.md` (18,736 B) is
reachable from `README.md` and `services_and_utils.md`; `services_and_utils.md` is 45,607 B, under the band, so item 1's trim was
not needed (A-71).

**S-292 — residue sweep**, each command as run, with its output:

```
$ grep -rln "TrainingSession(" lib/state/watch lib/core/sync_protocol lib/core/services
lib/core/services/watch_session_importer.dart

$ grep -rn "metric-heart-rate" lib
lib/mock/seed_data.dart:4479:      id: 'metric-heart-rate',
lib/mock/seed_data.dart:4500:    MetricApplicability(metricId: 'metric-heart-rate', effortKind: 'timed'),
lib/mock/seed_data.dart:4509:    MetricApplicability(metricId: 'metric-heart-rate', effortKind: 'interval'),
lib/data/models/models.dart:2349:/// never read or edited as a manual metric (`metric-heart-rate` stays

$ grep -rn "show_feeling_survey" lib
lib/state/settings/settings_state.dart:15:  static const String _showFeelingSurveyKey = 'show_feeling_survey';

$ grep -rn "answers nothing\|stays quiet\|never sent\|stored, never" docs watch/sync_protocol/PROTOCOL.md
watch/sync_protocol/PROTOCOL.md:275:  `session_snapshot`. A device with no session to report answers nothing: an
docs/state_management/services_and_utils.md:696:- **A reading is stored, never sent.** Sensor rows are written through the same
docs/state_management/services_and_utils.md:729:- **Timers travel as wall-clock timestamps.** A countdown is never sent;

$ git status --porcelain lib/watch
$ git diff --name-only ae71e23 -- lib/watch
lib/watch/session/watch_records.dart
```

Against the expected results:
- Only the importer creates a `TrainingSession` from wrist data. ✓
- `metric-heart-rate`: the seed only; the fourth hit is `SensorSummary`'s doc comment saying the metric stays unused — a
  comment, not a reader or a writer (O-9). ✓
- `show_feeling_survey`: only `SettingsState` (D-115). ✓
- The three remaining phrases are still true: a device with no session answers a snapshot request with nothing (verified by
  `S-009` in `test/live_mirroring_test.dart`), a raw reading is never sent (`S-239`), and a countdown is never sent (`S-005`). The
  sentence Phase 3a retired ("A phone holding no routines … answers nothing at all") has no hit. ✓
- `lib/watch`: nothing uncommitted, and across the PR since its base `ae71e23` only `watch_records.dart` changed (D-101, D-127). ✓

Scenario → tests (`grep -rhoE "S-2[0-9]{2}" test watch/watchos/Tests | sort -u`, then the files citing each; Swift files by
name). Every scenario of this plan appears except S-291 and S-292, which are the checks above rather than tests. S-200 also
appears — it belongs to an unrelated nutrition plan, and S-201 – S-205 collide with older plans' ids in three unrelated files.
S-201 – S-205 are this plan's through `watch/sync_protocol/fixtures/manifest.json` (1, 16, 2, 1 and 1 fixtures registered), whose
walking suites — `test/sync_protocol_fixtures_test.dart`, `test/live_mirroring_test.dart`,
`test/watch_reconciliation_cross_stack_test.dart`, `test/watch_session_engine_test.dart`, Swift `SyncProtocolFixturesTests` and
`WatchLiveMirroringTests` — name each test by its fixture path.

| S-id | Cited in |
|---|---|
| S-201 | `watch_capture_contract_conformance_test.dart`; the manifest walks |
| S-202 | the manifest walks (16 invalid fixtures) |
| S-203 | `watch_capture_contract_conformance_test.dart`; the manifest walks |
| S-204 | `watch_capture_contract_conformance_test.dart`; the manifest walks |
| S-205 | `watch_capture_contract_conformance_test.dart`; the manifest walks |
| S-206 | `watch_capture_contract_conformance_test.dart` |
| S-207 | `SyncProtocolFixturesTests.swift`, `watch_capture_contract_conformance_test.dart` |
| S-211 | `WatchEffortRatingTests.swift`, `watch_effort_rating_copy_parity_test.dart` |
| S-212 – S-215, S-217, S-219, S-220 | `WatchEffortRatingTests.swift` |
| S-216 | `WatchEffortRatingTests.swift`, `live_session_effort_rating_test.dart` |
| S-218 | `WatchEffortRatingTests.swift`, `watch_session_import_test.dart` |
| S-231 – S-235 | `WatchCaptureContractTests.swift`, `WatchSensorSummaryTests.swift` |
| S-236, S-238 | `WatchSensorSummaryTests.swift` |
| S-237, S-239 | `WatchSensorRecordingTests.swift` |
| S-240 | `WatchSessionEngineTests.swift` |
| S-251, S-252 | `live_mirroring_test.dart` |
| S-253 | `watch_reference_sync_test.dart`, `watch_transport_test.dart` |
| S-254 | `live_session_capture_entries_test.dart` |
| S-261, S-274 | `watch_session_import_test.dart`, `helpers/watch_capture_import_harness.dart` |
| S-262 – S-271, S-273 | `watch_session_import_test.dart` |
| S-272 | `watch_capture_contract_test.dart`, `watch_session_import_test.dart`, `helpers/watch_capture_import_harness.dart` |
| S-281, S-284 | `live_session_effort_rating_test.dart`, `watch_session_import_test.dart` |
| S-282, S-283 | `live_session_effort_rating_test.dart` |
| S-285, S-286 | `watch_session_summary_integration_test.dart` |
| S-287 | `watch_effort_rating_copy_parity_test.dart` |
| S-291, S-292 | — (the checks above) |
| S-293 | `pre_release_gate_swift_test.dart` |

**A-51, reproduced before it was fixed.** The nine tests of the new `A-51` group were written first. Eight ran against the
committed importer before any change (`00:00 +0 -8: Some tests failed.`, every precondition holding — the user's rows were where
the phone put them); the ninth (the half-written pass) was added with the fix, and all nine were then run against the committed
importer swapped back in (`git show HEAD:…`; restored, `cmp` and shasum matched): `00:00 +0 -9: Some tests failed.`, no compile
error. What today's importer did:

| Test | Failing assertion — Expected / Actual ; reason |
|---|---|
| a late wrist set, after the user's set | `[8, 100.0]` / `[6, 80.0]` ; `A-51 the user’s set is never overwritten` — the reported data loss |
| a late wrist set logged before the others | `[8, 100.0]` / `[5, 80.0]` ; `A-51 the user’s set is never overwritten or moved` — the re-keying moved e-set3 onto it |
| the user's set where a deleted wrist set was | `[8, 100.0]` / `[5, 80.0]` ; `A-51 the user’s set is never taken for the wrist set it replaced` — moved as if it were e-set3 |
| a late wrist run | `<5000.0>` / `<400.0>` ; `A-51 the user’s timed entry is never overwritten` |
| a late wrist round | `<4>` / `<3>` ; `A-51 the late round takes the next free place` — two rounds at one place |
| a later correction of the late set | `[9, 80.0]` / `[null, null]` ; `A-51 the correction reaches the wrist set it names (D-137)` |
| a later deletion of the late set | `[8, 100.0]` / `[null, null]` ; `A-51 and never the user’s set` — the deletion removed the user's set |
| a half-written late set | `an object with length of <1>` / `[]` ; `A-51 the pass stopped half-way` — today's importer wrote the late set over the user's row, so the armed write never came |
| deleting every wrist entry of the effort | `[8, 100.0]` / `[null, null]` ; `A-51 the user’s set stays, and with it the effort` — the effort was deleted with it |

Then, with the fix, the whole import suite: `00:00 +39: All tests passed!`; with the contract and parity suites,
`00:01 +84: All tests passed!`.

Red→green by copy-and-restore, never `git stash` (the Phase 5 harness; cases `<scratchpad>/pr2_p6_cases.json` and
`<scratchpad>/pr2_p6_gate_cases.json`, logs `<scratchpad>/pr2-p6-redgreen/` and `<scratchpad>/pr2-p6-gate-redgreen/`). Every red
failed on an assertion whose reason cites A-51 or S-293, with no compile error; every restore matched (`cmp`, shasum); every green
re-run was `+1: All tests passed!`; `shasum -c` over the two mutated files matched afterwards. One miss is recorded: **q13 went red
on the assertion before the one its case named** — with finishing-in-place off, the half-written set is not finished where it was
put (`[6, null]`) before any duplicate can be counted; the case was re-run with that reason as q13b, red, then green.

| # | Test | Behaviour reverted (file) | Red — Expected / Actual ; reason |
|---|---|---|---|
| q01 | late set after | user rows never detected: every late entry takes its logged-order place (importer) | `[8, 100.0]` / `[6, 80.0]` ; `A-51 the user’s set is never overwritten` |
| q02 | late set before | same (importer) | `[8, 100.0]` / `[5, 80.0]` ; `A-51 the user’s set is never overwritten or moved` |
| q03 | late run | same (importer) | `<5000.0>` / `<400.0>` ; `A-51 the user’s timed entry is never overwritten` |
| q04 | late round | same (importer) | `<4>` / `<3>` ; `A-51 the late round takes the next free place` |
| q05 | later correction | same (importer) | `[9, 80.0]` / `[null, null]` ; `A-51 the correction reaches the wrist set it names (D-137)` |
| q06 | later deletion | same (importer) | `[8, 100.0]` / `[null, null]` ; `A-51 and never the user’s set` |
| q07 | user's set where a deleted wrist set was | rows told apart by position only, not by stamp (importer) | `[8, 100.0]` / `[5, 80.0]` ; `A-51 the user’s set is never taken for the wrist set it replaced` |
| q08 | late round | a user-made instance not counted as the user's (importer) | `<4>` / `<3>` ; `A-51 the late round takes the next free place` |
| q09 | late set after | the late entry placed on the last row instead of after it (importer) | `[8, 100.0]` / `[6, 80.0]` ; `A-51 the user’s set is never overwritten` |
| q10 | later correction | the correction sent to the logged-order position instead of the entry's rows (importer) | `[9, 80.0]` / `[6, 80.0]` ; `A-51 the correction reaches the wrist set it names (D-137)` |
| q11 | later deletion | the deletion finds none of the entry's rows (importer) | `[null, null]` / `[6, 80.0]` ; `A-51 the deletion removes the wrist set it names (D-137)` |
| q12 | every wrist entry deleted | the effort deleted with the user's rows (importer) | `[8, 100.0]` / `[null, null]` ; `A-51 the user’s set stays, and with it the effort` |
| q13b | half-written late set | a half-written entry placed again instead of finished (importer) | `[6, 80.0]` / `[6, null]` ; `A-51 the half-written set is finished where it was put` |
| g1 | S-293 runs, passes | the step never runs the suite (gate script) | Expected: [`<copy>/watch/watchos`] / Actual: [] ; `S-293 swift test runs once, in the watchOS package` |
| g2 | S-293 blocks | a red suite only warns (gate script) | Expected: contains `✗  swift test failed in watch/watchos` ; `S-293 the step fails` |
| g3 | S-293 runs, passes | the suite run from the repository root (gate script) | Actual: [`<copy>`] ; `S-293 swift test runs once, in the watchOS package` |
| g4 | S-293 no toolchain | the toolchain check removed (gate script) | Expected: empty / Actual: [`<copy>/watch/watchos`] ; `S-293 nothing was tested` |
| g5 | S-293 not a Mac | the macOS check removed (gate script) | Expected: empty / Actual: [`<copy>/watch/watchos`] ; `S-293 nothing was tested` |
| g6 | S-293 `--fast` | `--fast` runs the suite (gate script) | Expected: empty / Actual: [`<copy>/watch/watchos`] ; `S-293 --fast runs no suite` |

A further check, not a test: a throwaway probe (deleted after the run) opened an imported F-CAP session in history edit mode and
left without saving. Its summaries went from `[session, effort, timed_instance, round_instance, round_instance, round_instance]` to
`[session, effort]` — see A-70 and O-15.

Assertion-change table: **empty.** No pre-existing assertion, expectation or fixture was modified. `test/watch_session_import_test.dart`
gained the `A-51` group and a failing-once repository for it, nothing else; the three existing gate suites are untouched (they do not
pin the step list; a new file holds S-293).

Footprint versus Predicted Files:
- Predicted and touched: `docs/watch_session_capture.md`, `docs/README.md`,
  `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
  `scripts/pre_release_check.sh`, this plan.
- Predicted, untouched in this phase: `docs/state_management/services_and_utils.md` (under the band, no trim needed;
  it changed in Phase 5), and the three existing `test/pre_release_gate_*_test.dart` (they do not pin the step list).
- Extra (A-68, A-71): `lib/core/services/watch_session_importer.dart` and `test/watch_session_import_test.dart` (A-51, which the
  orchestrator assigned to this phase's residue), and `test/pre_release_gate_swift_test.dart` (new, S-293).

Line endings: every file touched in Phase 6 is LF (0 CR), as it was.

Formatting, then the closing re-run. `dart format` was applied to the Phase 5 and 6 files that are new or were format-clean at
`HEAD` (the four new test files, `test/watch_session_import_test.dart`, `lib/features/session/live_session_screen.dart`; the new
widget and the importer were already clean). Three touched files were not format-clean at `HEAD` —
`lib/features/session/session_summary_screen.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_transport_test.dart` —
and the formatter's remaining changes in them are all in lines this PR did not write, so they were left as they are. Everything
was then run again: `flutter analyze` `242 issues found. (ran in 2.6s)` (the same diff: only the five moved infos);
`flutter test` `01:08 +2973 ~1: All tests passed!`; `swift test` `Executed 241 tests, with 0 failures (0 unexpected) in 0.865
(0.879) seconds`; the docs contract, the four gate suites and the three Phase 5 files `00:20 +51: All tests passed!`. Line
endings unchanged (0 CR in every formatted file).

---

## Files Affected (whole feature)

- **Protocol and contracts:**
  - `watch/sync_protocol/PROTOCOL.md`
  - the schemas (`envelope`, `observations_up`, new `preferences_down`)
  - `fixtures/manifest.json` and the new valid, invalid and reconciliation fixtures
  - `watch/contract/watch_sensor_contract.json`
  - new `watch/contract/watch_effort_rating_contract.json` and
    `watch/contract/watch_capture_contract.json`
- **Phone:**
  - `lib/core/sync_protocol/{message_validator,session_reconciler}.dart`
  - `lib/core/utils/watch_reference_sync.dart`
  - `lib/state/watch/{live_session_mirror_state,watch_sync_request_handler,watch_sync_wiring,watch_incoming_router,live_session_mirror_debug_main}.dart`
  - the new inbox and importer
  - `lib/features/session/live_session_screen.dart`
  - `lib/main.dart`
  - `lib/data/models/models.dart`
  - `lib/data/repositories/{workout,hive_workout,mock_workout}_repository.dart`
  - `scripts/sqlite_schema.sql`
- **Dart wrist:** `lib/watch/session/watch_records.dart`, one vocabulary constant (D-127).
- **Swift wrist:**
  - `SyncProtocolValidator.swift`, `WatchRecords.swift`, `WatchSensorRecording.swift`,
    `WatchSessionEngine.swift`, `WatchLoggingState.swift`, `WatchSessionStore.swift`,
    `WatchSyncOrchestrator.swift`
  - the new summaries, preferences, rating-state and view files
- **Tests:** as listed per phase.
- **Docs:**
  - `docs/{watch_session_capture (new),README,data_models,db_integration,session_summary,theme_and_settings}.md`
  - `docs/state_management/services_and_utils.md`
  - `docs/watch-app-setup-and-qa.md`
- **Process:** `scripts/pre_release_check.sh`; the shipping plan (Phases 7 and 8 checklists).

---

## Notes

### Phase dependency graph

```
P1 ─┬──────────────> P3a ──> P3b ──┬──> P5 (also needs PR 1 on develop) ──> P6
    │                 ▲            │
P2 ─┼─────────────────┘ (P3b)      │
    └──> P4a ──> P4b ──────────────┘
```

- P1 and P2 run in parallel.
- The Swift track (P4a → P4b) runs in parallel with P2, P3a and P3b.
- P3b is the critical path.

**Re-ordering options:**
- Running P4a before P3a gives the wrist guarantees earlier. The cost: until P3a lands, the
  phone's live list would show `session_end` rows in tests. No production wrist exists yet, so
  there is no user impact.
- Running P3b before P4a is fine. The importer is exercised by the contract fixtures alone.

### Intermediate states

- **After P1.** All clients accept the new shapes, and none emits them. The phone reconciler no
  longer merges across sessions, but the mirror still answers other-session snapshots with the
  old session until P3a. A phone mirror would store new-kind entries as plain entries.
- **After P2.** The new boxes and tables exist, empty, with no writer.
- **After P3a.** Every wrist sync request is answered with preferences, and the mirror switches
  sessions cleanly.
- **After P3b.** The phone imports any wrist session that reports `session_end`. No wrist sends
  one yet: the Swift wrist starts in P4a, and the Dart wrist never does until the Wear job.
- **After P4a.** The Swift wrist emits summaries and `session_end`, and the path is proven
  end-to-end by the capture contract on both stacks.
- **After P4b.** The rating prompt exists in the package. It is not reachable on a device until
  shipping-plan Phase 7.
- **After P5.** The phone-ended prompt works and Summary integration is proven.
- **After P6.** Docs, gate and residue are complete.

### Legacy handling

- No wrist build has shipped (protocol v1 is unreleased), so there is no legacy wrist data.
- Dev devices with pre-PR 2 wrist stores hold sessions without a `session_end`. Those are never
  imported, and D-129 keeps their samples. Clear the wrist store on such devices.
- Phone data is untouched: the new boxes start empty, no migration is needed, and phone sessions
  gain no summaries.

### Wear OS cloning debt (inherited by the Wear job; not built here, D-101)

Port to `lib/watch/`:
- storing and routing `preferences_down`;
- the rating prompt and `effort_rating`;
- the `session_end` rule (D-120);
- per-entry summaries and `pausedMs` (D-121 – D-126);
- steps recording through Health Connect;
- the D-128 resend and the D-129 prune gate;
- the `WatchObservationKind` additions.

Until that is done, Wear sessions are never imported.

---

## Open Items

- **O-1 — Shipping-plan Phase 7, the app shell (human + agent).** The shell must:
  - host the End control and the prompt;
  - present an owed prompt at launch before any other surface;
  - schedule `pruneConfirmed` and `pruneSettledSensorSamples` only while no session is active.
    This is a pre-existing hazard: pruning a running session's confirmed rows changes wrist
    values derived from them, such as the next round number (F-10).
  - bundle the protocol schemas for the Swift validator;
  - carry `preferences_down` over the transport;
  - confine the engine and its store to one writer. The sensor recorder's own writes are chained
    (`WatchSensorWrites`), but the UI and that chain can still write at once (A-35).

  These are now items of the shipping plan's Phase 7 checklist.
- **O-2 — Shipping-plan Phase 8, sensor bindings.**
  - Add the HealthKit bindings for steps (the live workout builder's cumulative step count) and
    heart rate.
  - Measure sample delivery latency against log time. D-121 computes at log time, so if latency
    drops a material slice of the window, add a grace wait before computing.
  - Verify the counter restart after workout recovery (D-125).
  - On-device verification is Pack O-2. It needs a way to inspect imported `SensorSummary` rows,
    since the phone has no display until later pack items.
- **O-3 — Owner confirmation of scope.** Confirm D-110 and D-111, or split them into a PR 2a.
- **O-4 — PR 1 first.** Phase 5 is blocked until PR 1 is on `develop`. Expect small conflicts
  in `models.dart`, `sqlite_schema.sql` and `theme_and_settings.md`. **Resolved 2026-09-26:** PR 1
  (`dcfe474`, `ae71e23`) is on `develop` and in this branch's history (Phase 5 notes).
- **O-5 — Wear OS cloning debt.** See Notes.
- **O-6 — Store listing, privacy and permission declarations.** They must now cover per-effort
  heart rate and step collection (pack Deferred table). This is a release gate the owner owns.
- **O-7 — Routine and modality linkage for imported sessions** (the D-135 alternative). Decide
  before the watch release, because this PR fixes `session_end`'s shape.
- **O-8 — GPS on wrist sessions.** GPS never starts for wrist sessions started through the
  start paths, because the modality is always nil (F-7). This belongs to PR 3 (distance source)
  and is recorded, not changed, here.
- **O-9 — `metric-heart-rate`.** It stays seeded and unused. Retire it or repurpose it later.
- **O-10 — The gate, if D-144 is vetoed.** `swift test` then stays out of every automated gate.
- **O-11 — Lifecycle messages are fire-and-forget.** A phone Finish while the wrist is
  unreachable applies only when the wrist next syncs and the phone still holds the session in
  memory. After a phone restart, the wrist's session is adopted as active and both devices may
  prompt. The phone's own rating wins (D-138). This is a known edge, not addressed in PR 2.
- **O-12 — Pack O-2.** Does the watch release wait for on-device verification of items 2 and 3?
  The owner decides.
- **O-13 — Round countdown after a dialled round (A-4).** Today the next round's countdown reverts to the default length after the user dials a longer one. Owner decides whether it should keep the dialled length; PR 2 leaves it unchanged.
- **O-14 — The wrist forgets the phone's corrections and deletions after a relaunch (A-38).** They live
  only in the engine's memory; `restore` does not rebuild them. A relaunch between a phone deletion
  and End counts the deleted set when deciding whether a prompt is owed (D-117) and when spanning set
  blocks (D-123). Pre-existing; not fixed in PR 2.
- **O-15 — RESOLVED by review fix F-1 (2026-09-26).** Leaving history edit mode without saving
  dropped an imported session's timed and round heart-rate summaries (A-70). Verified by a probe in Phase 6. The set-block and session summaries
  survive. Not fixed in PR 2: the fix belongs to the phone's edit-mode restore, which every session
  uses. No user holds imported summaries until a watch build ships.
- **O-16 — `swift test` in CI.** D-144 put it in `scripts/pre_release_check.sh` only;
  `.github/workflows/release.yml` runs no suite at all (A-69). Adding one to the workflow's macOS
  job needs the package verified on that runner's toolchain first.
- **O-17 — A late wrist entry is lost if its session is open in edit mode and the user discards.**
  Found while fixing F-1 (verified by a probe on Mock): the bench has 2 sets; a late set arrives
  and is imported (3 sets); the user adds a set, then Discards → 2 sets; the wrist re-sends the
  entry → still 2 sets, because Discard replaces a snapshotted exercise's rows wholesale and the
  entry is already marked applied. Suggested direction: after `restoreSessionSnapshot`, re-run the
  import for the session's entries applied after the snapshot was taken (or un-mark them). Needs
  design; not fixed in PR 2.
- **O-18 — Review F-3: a session the user deleted can come back (low likelihood).** Import infers
  "the user deleted this session" from the already-imported entries, and a live phone deletion can
  empty that list; four conditions must coincide (see ## Feedback, F-3). Suggested fix: record
  durably that a session was imported (for example, a marker row staged when the importer creates
  it). **OWNER QUESTION:** should an imported session whose entries were all deleted live leave
  history, the way an empty session never enters it (D-133)?
- **O-19 — Review F-9: the wrist stores one extra preferences record per sync, forever.** The phone
  stamps each `preferences_down` with the send time and the wrist stores every copy. Latent until
  shipping-plan Phase 7 adds a durable store. Suggested fix: stamp with when the setting last
  changed (as `foods_down` does), or prune superseded rows.
- **O-20 — Re-review N8: pre-existing crown wrap outside PR 2.** `WatchLoggingView.swift` and
  `WatchNutritionView.swift` use a continuous crown with a plain delta, so a wrap shifts the value by about 20 steps.
  Candidate small follow-up PR (see the review file).
- **O-21 — Two literals remain in `EffortRatingSheet` (review V-4).** The tile radius is
  `BorderRadius.circular(14)` and the background `Colors.transparent`; neither has an `OmniTheme` token. Left as
  PR 1 wrote them so the extraction moves no pixels — a PR 1 follow-up if the tile radius is ever tokenised.

---

## Progress

### Baseline (fill once, before the first change)

Recorded by Phase 1 (@developer), 2026-09-25, in the worktree at HEAD `ae71e23`
(Flutter 3.41.9 stable; Apple Swift 6.3.1).

- `flutter analyze`: `242 issues found. (ran in 7.0s)` — 0 errors, 11 warnings, 231 infos
  (exit 1, pre-existing).
- `flutter test`: `01:15 +2823 ~1: All tests passed!`
- `cd watch/watchos && swift test`: `Executed 148 tests, with 0 failures (0 unexpected) in 0.500 (0.520) seconds`
- `git status --porcelain`: `?? docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`

### Phases

- [x] Phase 1 — Protocol and shared contracts (@developer) — **Complete** 2026-09-25. `flutter test`
  `+2863 ~1: All tests passed!`; `swift test` `Executed 149 tests, with 0 failures`; analyze unchanged
  (242). Evidence under "Phase 1 verification notes".
- [x] Phase 2 — Phone data layer (@dba) — **Complete** 2026-09-25. `flutter test`
  `01:06 +2901 ~1: All tests passed!`; `swift test` `Executed 149 tests, with 0 failures`; analyze unchanged
  (242). 85 red→green runs recorded (two ineffective mutations redone). Evidence under "Phase 2
  verification notes".
- [x] Phase 3a — Mirror switch, preferences producer, live-screen filter (@developer) — **Complete**
  2026-09-25. `flutter test` `01:04 +2908 ~1: All tests passed!`; `swift test` `Executed 149 tests, with 0
  failures`; analyze unchanged (242). 15 red→green runs. Evidence under "Phase 3a verification notes".
- [x] Phase 3b — Inbox, import, receipts, liveness (@developer) — **Complete** 2026-09-25. `flutter test`
  `01:05 +2950 ~1: All tests passed!`; analyze unchanged (242); `swift test` `Executed 222 tests, with 0 failures`
  (the Swift delta is the parallel 4a/4b run's; 3b changed nothing under `watch/`). 46 red→green runs, three
  documented stay-greens. Evidence under "Phase 3b verification notes".
- [x] Phase 4a — Wrist summaries, steps, session end, resend, prune gate (@developer) — **Complete** 2026-09-25.
  `swift test` `Executed 222 tests, with 0 failures` at the end of 4a (from 149); watchOS type-check clean; `lib/watch`
  untouched. 52 red→green runs, including a14/a14c as documented stay-greens (overlapping gates) and a05 red on a protocol
  refusal. Its Swift is uncommitted; its doc and plan edits went into `282ebc3`. Evidence under "Phase 4a verification notes".
- [x] Phase 4b — Wrist preferences and rating prompt (@developer) — **Complete** 2026-09-26. `swift test` `Executed 241
  tests, with 0 failures (0 unexpected) in 0.846 (0.859) seconds`; one full `flutter test` at the end
  `01:08 +2950 ~1: All tests passed!` (unchanged from 3b); analyze unchanged (242); watchOS type-check clean. 29
  red→green runs, including the structural guard (b20, `func dismiss()`). Evidence under "Phase 4b verification notes".
- [x] Phase 5 — Phone-ended prompt and Summary integration (@developer) — **Complete** 2026-09-26. Precondition met: PR 1
  (`dcfe474`, `ae71e23`) is on `develop` (`ae71e23`) and both commits are ancestors of this branch, so no rebase was needed.
  `flutter test` `01:07 +2959 ~1: All tests passed!`; `swift test` `Executed 241 tests, with 0 failures`; analyze 242 (five infos
  moved with the extracted sheet, none new). 15 red→green runs; the extraction pixel-identical to PR 1's sheet. Evidence under
  "Phase 5 verification notes".
- [x] Phase 6 — Docs, gate, residue, closure (@developer) — **Complete** 2026-09-26. A-51 fixed (A-68): reproduced by nine
  tests red against the committed importer, then green; thirteen mutation reds. D-144: `scripts/pre_release_check.sh` runs
  `swift test` (A-69); six mutation reds. Final runs, after the closing format pass: `flutter test`
  `01:08 +2973 ~1: All tests passed!`; `swift test` `Executed 241 tests, with 0 failures (0 unexpected) in 0.865 (0.879) seconds`;
  `flutter analyze` `242 issues found.` (nothing new since the Baseline but the five infos A-64 moved); docs contract, gate suites
  and Phase 5 files `00:20 +51: All tests passed!`. Evidence under "Phase 6 verification notes".
- [ ] **Manual QA — the owner's.** On paired hardware, `docs/watch-app-setup-and-qa.md` Level 3 steps 15–20. They cannot run
  before the shipping plan's Phase 7 (the app shell hosts the End control and the prompt, O-1) and Phase 8 (the HealthKit
  bindings, O-2) land. Whether the watch release waits for them is O-12.

### Review fix round (2026-09-26) — COMPLETE

Part 1 was F-1 (by @developer, Opus) and F-2, F-4, F-5, F-6 (a @developer, Sonnet, run verified by
the orchestrator). Part 2 was F-7, F-8, F-10, F-11 and F-12 by @developer. The re-review was
APPROVE WITH NITS, and part 3 — its mechanical round N1 – N7 — is done; all three parts' measurements,
red→green tables and footprints are in
`2026-09-25-02-stats-pr2-watch-capture-plan.evidence.md`, so this plan stays inside the scope budget
(§2).

Handoff state before part 2, measured on the staged tree:
`flutter test` `01:11 +2991 ~1: All tests passed!`; `swift test` `Executed 241 tests, with 0 failures`;
`flutter analyze` `242 issues found.` (the same as the Phase 6 baseline). Findings are in
"## Feedback › Code review — 2026-09-26"; each has file:line and a suggested fix. The Common
procedures above apply to every item: red first, copy-and-restore (never `git stash`), no
loosened assertions, both suites' full counts pasted, CRLF preserved in `lib/main.dart`,
`lib/app.dart`, `lib/data/models/models.dart`, `lib/core/constants/omni_theme.dart`,
`lib/state/workout/workout_state.dart` and `scripts/sqlite_schema.sql`.

- [x] **F-1** (CRITICAL) — edit-mode Discard restores an imported session's sensor summaries.
  Done by @developer (Opus); evidence in "## Feedback › Review fixes — F-1 (Opus)".
- [x] **F-2** — `WatchSessionInbox._settle` passes are chained, one at a time. Test group
  "F-2 concurrent frames settle one at a time" (`test/watch_capture_contract_test.dart`).
- [x] **F-4** — the must-answer effort-rating sheet also refuses the system back button
  (`PopScope`); the user-opened Change sheet stays dismissible. Tests in
  `test/live_session_effort_rating_test.dart` and `test/session_summary_effort_row_test.dart`.
- [x] **F-5** — the router's "inbox stages before the mirror answers" order is pinned by a test in
  `test/watch_session_import_test.dart`; `watch_session_capture.md` cites it.
- [x] **F-6** — fixtures `invalid/session_snapshot_steps_on_round.json` and
  `valid/observations_up_paused_ms_equals_window.json`, registered in `manifest.json`, cover both
  validators.
  - F-2, F-4, F-5 and F-6 were implemented by a @developer (Sonnet) run that hit a usage limit
    before writing its notes. The orchestrator verified them instead: targeted suites green, plus
    mutation spot-checks, each red and then restored byte-identically (`cmp`):
    - F-2: settle chain removed → `watch_capture_contract_test.dart` `+14 -2`.
    - F-4: `canPop: true` → the two sheet test files `+18 -2`.
    - F-5: mirror asked before the inbox → `watch_session_import_test.dart` `+39 -1`.
    - F-6a: snapshot capture rules dropped in the Dart validator → `sync_protocol_fixtures_test.dart`
      `+65 -1`.
    - F-6b: Dart `pausedMs <` instead of `<=` → `+65 -1`; Swift `>=` instead of `>` → `swift test`
      2 failures.
  - The orchestrator also fixed one `unnecessary_underscores` lint the F-2 change introduced
    (`onError: (_, _)`).
- [x] **F-7** — the crown cannot wrap the rating. `WatchEffortRatingView` asks for a discontinuous
  crown and takes its range from `WatchEffortRatingState.crownRangeDetents`; the state ignores any
  reading further from the last one than the whole range. Test
  `F-7 a crown that wrapped its range is not a turn` in `WatchEffortRatingTests.swift`, red first
  (`Optional(1)` vs `Optional(5)`); the module type-checks for watchOS (exit 0).
- [x] **F-8** — the phone's rating of an already-imported session signals the history change.
  `recordPhoneRating` calls `_onHistoryChanged` after the direct write (revises A-50). Asserted at
  the state layer (S-284 in `test/watch_session_import_test.dart`) and through the screen (S-284 in
  `test/live_session_effort_rating_test.dart`).
- [x] **F-10** — the Swift `integer` check refuses float-typed numbers (`CFNumberIsFloatType`),
  matching Dart's `value is int`. New invalid fixture `invalid/observations_up_steps_as_double.json`
  (`steps: 3200.0`), registered in `manifest.json`, red on Swift first; Dart already refused it.
- [x] **F-11** — DONE (doc only). Phase 7's "engine and store written by one actor" item in
  `docs/plans/2026-09-21-13-watch-integration-shipping.md` now says it needs a package
  change and names `WatchSensorWrites` and `consume(_:onElement:)` (`WatchSensorRecording.swift`).
- [x] **F-12** — DONE. An `A-50` group in `test/watch_session_import_test.dart`: a phone rating
  outside 1–5 is refused before the import (nothing staged) and after it (the session keeps the
  wrist's rating). `docs/theme_and_settings.md`'s `SettingsState` section no longer
  restates the field/default/key table or the sound and interval lists (standard §3.4, §3.5); it
  names the owner, the closed sets and the tests instead. The scenario-id renames and the
  `live_session_screen` import nit were optional and are not done.
- [x] Review F-3 and F-9 recorded as Open Items O-18 (with an owner question) and O-19. The new
  finding from F-1 is O-17.
- [x] Re-review (2026-09-26, @code-reviewer): APPROVE WITH NITS — `flutter test` +2994 ~1, `swift test` 242,
  analyze 242. Findings N1–N9: `2026-09-25-02-stats-pr2-watch-capture-plan.review.md` (not in this plan).
- [x] **Final mechanical round: N1–N7** — done 2026-09-26. `flutter test` `01:15 +2999 ~1`,
  `swift test` `Executed 242 tests, with 0 failures`, `flutter analyze` 242 (unchanged), watchOS
  type-checks clean for the simulator and for arm64_32. Five mutation reds, each restored
  byte-identically. Evidence: `2026-09-25-02-stats-pr2-watch-capture-plan.evidence.md`.
- Moved out: N8 → O-20; N9 → shipping plan Phase 7 (the durable store keeps integers as integers).
- [x] **Verification pass before approval** (2026-09-26, @code-reviewer) — APPROVED WITH WARNINGS:
  no critical finding, no unmet acceptance criterion, no stale test. V-1 – V-4 (two warnings, two
  suggestions) are in `2026-09-25-02-stats-pr2-watch-capture-plan.review.md`. No further review round
  proposed.
- [x] **V round — V-1 – V-4, done 2026-09-26 (@developer).** V-1: new weight-unit default test, whose
  red came only from mutating the default inside `_loadFromPrefs` (A-72). V-2: the two stale
  `**File**:` paths corrected. V-3: `WatchInboxResult.historyChanged` and the unread half of
  `_settle`'s record removed; the refresh stays inside `_settleNow`. V-4: the barrier literal deleted
  (SDK fallback is the same colour), the 20.0 sheet radius now reads `OmniTheme.surfaceBorderRadius`;
  the tile's `circular(14)` and `Colors.transparent` stay with no token to take (A-73, O-21).
  `flutter test` `01:14 +3000 ~1`, `swift test` `Executed 242 tests, with 0 failures`, `flutter analyze`
  242 (unchanged). Evidence: `2026-09-25-02-stats-pr2-watch-capture-plan.evidence.md`.

Per phase, record: the full-suite lines (flutter and swift), the red→green table, the
assertion-change table, the footprint versus Predicted Files, and the Done Criteria outputs.

#### Review fix round, part 2 (F-7, F-8, F-10, F-11, F-12) — @developer, 2026-09-26

Start of the round: the staged handoff state. `flutter test` `01:09 +2991 ~1: All tests passed!`,
`swift test` `Executed 241 tests, with 0 failures`, `flutter analyze` `242 issues found.`

| Check | Start of round | After the fixes | Delta explained |
|---|---|---|---|
| `flutter analyze` | `242 issues found.` | `242 issues found. (ran in 3.1s)` | No new diagnostics |
| `flutter test` | `01:09 +2991 ~1` | `01:14 +2994 ~1: All tests passed!` | +3, all new: the two `A-50` tests, and one manifest-walk case for `invalid/observations_up_steps_as_double.json`. The F-8 refresh assertions extend existing S-284 tests in place |
| `cd watch/watchos && swift test` | `Executed 241 tests, with 0 failures` | `Executed 242 tests, with 0 failures (0 unexpected) in 0.849 (0.861) seconds` | +1: `WatchEffortRatingTests.testF7ACrownThatWrappedItsRangeIsNotATurn` |
| watchOS type-check (`xcrun --sdk watchsimulator swiftc -typecheck`, every file in `Sources/WatchSessionEngine/`) | exit 0 | exit 0, 0 errors | the changed `#if os(watchOS)` view still builds for the watch — the F-7 partial attempt's failure mode |
| `flutter test test/docs_indexing_contract_test.dart` | — | `00:00 +9: All tests passed!` | `theme_and_settings.md` 6,675 B, under the band |
| `git status --porcelain lib/watch watch/contract watch/sync_protocol` | empty | `?? watch/sync_protocol/fixtures/invalid/observations_up_steps_as_double.json` | F-10's fixture, as predicted; nothing under `lib/watch/` (D-101) |

Red→green, by copy-and-restore, never `git stash`: harness `/private/tmp/pr2_fixes_redgreen.py`, logs in
`$TMPDIR/pr2-fixes-redgreen/`. Each case shasums and copies the file, applies one textual mutation
(asserted to match exactly once), requires a failure whose log cites the finding and holds no compile
error, copies back, proves the restore with `cmp` and a matching shasum, and re-runs green. All five
restored and went green.

| # | Finding | Behaviour reverted or bug injected (file) | Red — failing assertion | Green |
|---|---|---|---|---|
| 1 | F-7 | the wrap guard widened to twice the range (`WatchEffortRating.swift`) | `XCTAssertEqual failed: ("Optional(1)") is not equal to ("Optional(5)") - F-7 a wrapped −10 after +10 does not flip 5 to 1` | `Executed 1, 0 failures` |
| 2 | F-8 | the `_onHistoryChanged` call removed after the direct write (`watch_session_inbox.dart`) — the import test | `Expected: <3> / Actual: <2>` — `F-8 a rating written straight to an imported session is a history change, so the calendar refreshes (D-142)` | `+1` |
| 3 | F-8 (screen) | the same mutation — the S-284 screen test | `Expected: <2> / Actual: <1>`, same reason | `+1` |
| 4 | F-10 | the old whole-number check restored (`SyncProtocolValidator.swift`) | `invalid/observations_up_steps_as_double.json must not conform`; `expected code invalid_type, got []`; `no rejection explains expected integer, found` | `Executed 1, 0 failures` |
| 5 | A-50 | the 1–5 range check removed (`watch_session_inbox.dart`) | `Expected: false / Actual: <true>` — `A-50 0 is not on the 1–5 scale` | `+2` |

Before the fixes, the new assertions were shown red on unfixed code by the same runs: F-7
(`Optional(1)` vs `Optional(5)`, with `crownRangeDetents` added so the test compiled), F-8 at both
layers, F-10 on Swift while Dart already refused the fixture (`S-001 fixtures
invalid/observations_up_steps_as_double.json is rejected as invalid_type` passed unchanged), and the
A-50 tests.

Assertion-change table: **empty.** No pre-existing assertion, expectation or fixture was modified.
`live_session_effort_rating_test.dart`'s `_Graph` gained a refresh counter and its S-284 test one
extra expectation; `watch_session_import_test.dart`'s S-284 test gained the same
(construction plus a new assertion, no expectation loosened). `lib/watch/` untouched.

Footprint: `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift`,
`…/WatchEffortRatingView.swift`, `…/SyncProtocolValidator.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift`,
`watch/sync_protocol/fixtures/invalid/observations_up_steps_as_double.json` (new) and
`watch/sync_protocol/fixtures/manifest.json`, `lib/state/watch/watch_session_inbox.dart`,
`test/watch_session_import_test.dart`, `test/live_session_effort_rating_test.dart`,
`docs/theme_and_settings.md`,
`docs/plans/2026-09-21-13-watch-integration-shipping.md` and this plan. Every touched file
is LF (0 CR), as it was before. No other file changed.

No doc edit was needed for F-7, F-8 or F-10 beyond the two above: `watch_session_capture.md` carries
no claim about the crown or about integer typing (its scope points at `PROTOCOL.md` for validation),
and its liveness invariant already reads "a change to history refreshes the calendar once", which the
F-8 write now satisfies rather than contradicts. The tests are the record.

---

## Assumption Log

Executors append entries in this form: **A-n (Phase X)** — the decision made · the options
considered · the choice and why. The reviewer marks each entry RATIFIED (it becomes a superseding
D-entry) or REVERT (a remediation item with a structural guard). An empty log after Phase 3b or
Phase 4a is suspicious.

- **A-1 (Phase 1)** — What "slots are unique" means for `setBlockHeartRates` · unique
  `sessionExerciseId`, or unique `(sessionExerciseId, exerciseId)` pair · **the pair.** D-123 defines a
  set block by that pair, and a slot swapped mid-session legitimately yields two blocks on one
  `sessionExerciseId`; uniqueness on the slot alone would refuse a correct `session_end`. It also matches
  D-134's effort key.
- **A-2 (Phase 1)** — Coverage for the semantic rules S-202 lists no fixture for (`pausedMs` longer than
  its window, a set block's average above its maximum, a repeated set block, and `rating`, `status` or
  `modality` on the wrong kind) · Dart-only unit tests, no coverage, or more manifest fixtures · **six
  more invalid fixtures** (17 instead of 11), registered under S-202. Fixtures are the only mechanism that
  holds both validators to the same code and wording, and each rule needed its own red→green. Footprint
  finding: six files beyond Predicted Files.
- **A-3 (Phase 1)** — Kind-specific required fields for the new kinds on *snapshot* entries · add a
  semantic rule, or follow the existing precedent · **follow the precedent.** `rating` on
  `effort_rating` and `startedAt`/`endedAt`/`status` on `session_end` are required by the
  `observations_up` schema's `oneOf`, as the existing kinds' fields are. A snapshot `entry` is held only to
  the shared entry shape (a snapshot set without `reps` is valid today). The new placement rules and the
  identity exemption *do* apply to snapshot entries. Consequence for Phase 3b: when staging session-scoped
  kinds from a wrist snapshot, the inbox must treat an `effort_rating` without `rating`, or a
  `session_end` without its times or status, as not staged. A later amendment could add the rule instead.
- **A-4 (Phase 1) — needs Phase 4a's attention; may touch product behaviour.** F-CAP's follow-on round
  length · encode F-CAP as written, or rewrite F-CAP to today's wrist · **as written.** The contract says
  the follow-on round timer after `e-r1` is planned at the dialled 300 s, and states the rule in its
  description. Today `WatchLoggingState.log` clears the dialled values *before* `startFollowOnTimer`
  reads the round length. So on the current wrist, a round dialled to 300 s is followed by a countdown
  planned at `WatchLoggingDefaults.roundDurationSeconds`, and a literal replay would end `e-r2` at
  10:35:00, not 10:37:00. Rewriting F-CAP would bake that behaviour into the shared contract.
  Phase 4a must do one of two things. It can make the follow-on honour the dialled length (read it
  before clearing). That is user-visible: a user who dials 5-minute rounds currently gets a
  default-length next countdown. Or the replay can start the follow-on explicitly. The owner may want to
  confirm the first option.
  - **Orchestrator direction (2026-09-25, owner to confirm):** Phase 4a takes the second option: the contract replay starts the next round's countdown explicitly. The wrist's current behaviour (the next countdown reverts to the default length) is NOT changed in PR 2; that would be a user-visible change the owner has not approved. Recorded in Open Items as O-13.
- **A-5 (Phase 1)** — Timestamp form in `watch/contract/watch_capture_contract.json` · whole-second `Z`
  like the protocol fixtures, or the watchOS wire form · **the watchOS wire form** (`…T10:20:00.000Z`,
  what `utcIso` writes). Phase 4b compares emitted events to `expectedEvents` exactly. Both forms match the
  protocol's timestamp pattern and parse identically on the phone. The protocol fixtures keep their
  existing whole-second form.
- **A-6 (Phase 1)** — Contract vocabulary the plan left open · **chosen as follows:**
  - Timeline ops use the suggested names. `dial` is `{metric: <WatchMetricKey>, value}` in seconds or
    kilograms. `start` carries the scripted `entryIds`. Each case carries `sensorPermissions`.
  - `expectedImport` keys are named after the phone model fields: `timedInstances`, `roundInstances`
    (`roundIndex`, `totalPausedDurationMs`, `actualDurationSecs`, `plannedDurationSecs`, `completed`), and
    `observations` by `entryIndex`.
  - `sensorSummaries` are `{scope, target, …}`. `target` is `{sessionId}` for the session scope,
    `{effortKind, sessionExerciseId, exerciseId}` for the effort scope, and `{entryId}` for instance scopes.
  - `watch_effort_rating_contract.json` also carries `preferencesField` (`effortRatingPrompt`), the wire
    name of the setting.
  - Phase 3b may map these names, but must not change the values.
- **A-7 (Phase 1)** — What the reconciler resets on a session switch · entries only, or entries plus the
  applied event ids · **both.** If the applied-event-id set were kept, returning to an earlier session
  (A → B → A) would silently drop A's snapshot entries whose event ids had been seen. Applied change
  ids are kept: they are globally unique, and keeping them preserves at-most-once for structure changes.
- **A-8 (Phase 1)** — "`preferences_down` … with no `sessionId`" · forbid the envelope field, or just not
  require it · **not required, not forbidden.** The envelope keeps `sessionId` optional for every type, as
  for `routines_down` and `foods_down`. The fixture carries none, and PROTOCOL.md says the message names
  no session.
- **A-9 (Phase 1)** — Pause-window arithmetic parity · **whole milliseconds on both stacks.** Dart uses
  `Duration.inMilliseconds`, and Swift rounds the `Date` difference to whole milliseconds, which absorbs
  binary noise. The two agree exactly for the millisecond-precision timestamps both wrists write.
- **A-10 (Phase 2)** — Where D-131's rules are enforced · repository checks, the model constructor, or
  both · **the `SensorSummary` constructor (`ArgumentError`), mirrored by CHECK constraints on
  `app_sensor_summary`.** The repositories accept only constructed models, so a refused summary cannot
  reach either store, and `fromMap` goes through the same constructor, so a corrupted stored row fails
  loudly on read instead of rendering.
- **A-11 (Phase 2)** — How "one row per (scope, target)" is guaranteed · a free id plus a uniqueness
  check, or an id derived from both · **derived:** `SensorSummary.idFor(scope, targetId)` =
  `sensor-<scope>-<targetId>`, computed by the constructor. Put-if-absent by id then *is* one row per
  (scope, target), and Phase 3b never mints summary ids. `fromMap` refuses a stored id that disagrees.
- **A-12 (Phase 2)** — How "read summaries for a session" and the `deleteSession` cascade find a
  summary · walk each target back to its session, or store the owner · **every summary stores its
  owning `sessionId`**, whatever its scope. Both become a single filter, and the SQL table can hold a
  foreign key to the session. A `session`-scope summary must target its own session (refused otherwise).
- **A-13 (Phase 2)** — Rules beyond D-131's list · **added, in the model and in SQL:** a known scope
  (`SensorSummary.scopes`), finite heart rate, an ordered window (end ≥ start), source in
  `SensorSummary.sources` (only `watch` today), and the session-scope target rule of A-12. Each has its own
  red→green below.
- **A-14 (Phase 2)** — How the staged payload is stored · a nested map, or JSON text · **JSON text**
  (`payloadJson` / column `payload_json`), read through a `payload` getter that returns a fresh decoded
  copy. Hive's `_asStringMap` is shallow and hands back nested maps untyped, the SQL contract stores
  `TEXT`, and a staged row must not be alterable through a map a caller holds. A payload that is not a
  JSON object (for example one holding a `DateTime`) is refused at construction.
- **A-15 (Phase 2)** — `WatchInboxEntry` vocabulary · accept any kind and origin, or enforce ·
  **enforce, in the model and in SQL:** origin is `watch` or `phone`; watch kinds are the six wire kinds
  (`WatchInboxEntry.watchKinds`), phone kinds the three annotation kinds (`phoneKinds`), never crossed;
  `phone_rating` must use `phoneRatingId(sid)`, so the phone's own rating is staged at most once per
  session; `phone_correction`/`phone_deletion` must use a `phoneChangeId` id. Wrist-supplied ids are not
  pattern-checked (the protocol validator owns wire ids). **Consequence for Phase 3b:** constructing an
  entry with any other kind throws, so the inbox filters (nutrition quick-logs, for one) before it
  constructs.
- **A-16 (Phase 2)** — Marking applied twice · overwrite, or first stamp wins · **first stamp wins;
  unknown ids are skipped; nothing clears a stamp.** A tombstone's time never moves.
- **A-17 (Phase 2)** — Orders the plan left open · **`getWatchSessionIdsWithUnappliedEnd`:** by the
  `session_end` row's `receivedAtMs`, then session id, each session once (a malformed wrist that sends two
  ends for one session still yields one resume); **`getSensorSummariesForSession`:** scope in
  `SensorSummary.scopes` order, then `windowStartMs`, then `targetId`. The SQL contract states the
  equivalent `ORDER BY`.
- **A-18 (Phase 2)** — `deleteSessionBlock` is not in Phase 2 item 4's cascade list · **cascaded anyway,
  in both repositories, with its own test.** It deletes a block's efforts and their instances inline,
  without calling `deleteEffort`, so without its own cascade a block delete would orphan the summaries of
  those rows, contradicting D-131 "deleted together with its target". Footprint unchanged (same files).
- **A-19 (Phase 2)** — The whole-store `clear()` utility on both repositories (test-only; no `lib/`
  caller) · keep the new stores, or wipe them · **wipe them.** "The inbox is never cascaded" governs
  domain deletes; a full reset that kept tombstones for a history it erased would be inconsistent.
- **A-20 (Phase 2)** — Data versioning · **no migration step, `currentDataVersion` unchanged.** Both Hive
  boxes are new and open empty, and no existing row changes shape, as the plan's Legacy handling says. The
  box-opening site in `HiveWorkoutRepository.initialize` carries that rationale.
- **A-21 (Phase 3a)** — How D-141 decides what the Watch Session screen lists and counts · an allow-list of
  the four effort kinds in the screen, or a deny-list of the two session-scoped kinds in the state layer ·
  **the deny-list, owned by `LiveSessionMirrorState`** (`sessionScopedKinds`, `effortEntries`,
  `effortEntriesOf`), spelled with the models' `WatchInboxEntry.kindEffortRating` / `kindSessionEnd` rather
  than new literals. D-141 names exactly those two kinds; an allow-list would also hide a nutrition
  quick-log riding a session, a user-visible change nobody asked for. The mirror and the completed record keep
  every entry, because a re-asserted snapshot must carry them all; only the surface filters.
- **A-22 (Phase 3a)** — The `preferences_down` message id · derived from `generatedAt` only (the
  `routines_down` precedent), a uuid, or derived from the content · **derived from the content:
  `msg-preferences-<generatedAtMs>-<on|off>`.** The wrist keeps the newest copy and a tie goes to the
  later-received one (D-113); two different settings stamped in the same millisecond must not look like one
  message redelivered, while a rebuild of the same setting stays the same message.
- **A-23 (Phase 3a)** — `createWatchSync`'s new inputs · optional or required `settingsState`; how a test pins
  "generatedAt is the phone clock at send" · **`settingsState` is required** (production cannot forget the one
  owner of the setting, D-115; the two test call sites were updated) **and an optional `clock`** is threaded to
  `WatchSyncRequestHandler`, whose own `clock` parameter existed but was not reachable through the wiring. A
  `routines` request now always reports an answer (`handle` returns true), because the preferences always go.
- **A-24 (Phase 3a)** — Which `sessionId` decides a session switch in the mirror · the envelope's or the
  snapshot payload's · **the payload's**, the one the reconciler switches on. The validator already requires
  the two to match (PROTOCOL.md), so the choice only keeps the mirror and the reconciler reading one field.

- **A-25 (Phase 4a)** — Where `session_end` sits in the terminal transition ("appended before anything else is stored
  for the session", D-120) · after the row that records the new status, or before it · **before it, and emitted before
  the lifecycle message.** A kill between the two appends then leaves the session still running with its end already
  owed to the phone (a second End keeps that end), instead of a completed session with no end: one the phone would never
  import and whose readings D-129 would hold for ever. A launch-time repair was considered and rejected: it would also
  append ends for pre-PR 2 dev sessions, which Notes › Legacy handling says are never imported.
- **A-26 (Phase 4a)** — Which row says a session is "wrist-created" · the newest row's `source`, or the first stored row's
  · **the first stored row.** `applySnapshot` writes `source: "phone"` for any session that is not the current one, so a
  wrist session revisited through a phone snapshot (A → B → A) would otherwise lose its end.
- **A-27 (Phase 4a)** — What "stored and acknowledged" means after `pruneConfirmed` · the stored observation's
  `confirmedAt` only, or the confirmation rows too · **the confirmation rows too.** The engine keeps every acknowledged
  record id (`acknowledgedObservationIds`), rebuilt from all confirmation rows at `restore` — confirmation rows are never
  pruned. Without it, a pruned end reads as "no end" both to the prune gate (the log would never be released, red a16) and
  to the end capture (a reopened session that ends again would get a second end with new values, red a34).
- **A-28 (Phase 4a)** — Readings a summary ignores · D-122(d) names only heart rates ≤ 0 · **also heart rates below 1 bpm,
  non-finite values, and negative step counts.** The schema's `minimum: 1` (heart rate) and `minimum: 0` (steps) would
  otherwise make a glitch's summary unsendable, and `appendObservation` refuses a non-conformant event: a sensor glitch
  would refuse the user's log. F-CAP's only glitch is a 0 and is unaffected.
- **A-29 (Phase 4a)** — The heart-rate average (D-122 e) · the raw mean, or the mean clamped into the qualifying
  readings' range · **clamped.** The clamp only removes binary floating-point noise — three readings of 60.2 average to
  60.20000000000001, above their own maximum — which the validator would refuse as average > maximum.
- **A-30 (Phase 4a)** — `pausedMs` (D-126) · the countdown's accumulated pause plus any open pause up to the log instant ·
  **the open pause is counted up to the window's end, and the total is capped at the window.** Identical for every case
  the scenarios cover. It differs only for a countdown paused after it had already run out (reachable through a phone
  `timer_state`): the literal rule would exceed the window, which the validator refuses (Phase 1), refusing the log.
- **A-31 (Phase 4a)** — Precision of window membership and pause matching · **whole milliseconds, with each window first
  normalised to its wire form** (`WatchSensorSummaries.wireInstant`), extending A-9. The summary then covers exactly the
  window the phone reads from the event's own timestamps, and a pause row matches its entry whether or not the rows were
  read back from storage.
- **A-32 (Phase 4a)** — Shape choices D-120/D-121 leave open · **`setBlockHeartRates` lists blocks in the order they began**
  (first set's `loggedAt`, then `entryId`); a block with no qualifying reading is left out, and the field is omitted when
  none remains (the schema's `minItems: 1`). **`modality` is omitted when the session's is nil or empty** (the schema's
  `minLength: 1`).
- **A-33 (Phase 4a) — the O-13 direction, as built.** The F-CAP replay starts the next round's countdown itself after
  every round it logs, planned at the round length the surface showed just before the log. It does so after every round,
  not only when the wrist's own follow-on differs, so the replay applies the contract's rule without inspecting the
  wrist's. The wrist's behaviour is unchanged: its own follow-on still reverts to the default length after a dialled round.
- **A-34 (Phase 4a)** — "The existing sensor suites, run with steps permission granted and with it denied" (S-239) · a
  focused comparison test, or a real re-run · **both.** `WatchSensorRecordingTests` is no longer `final` and takes its
  steps grant from `class var stepsGrant`; `WatchSensorRecordingStepsDeniedTests` overrides it and re-runs all 38 tests.
  `testS239StepsPermissionChangesNothingButTheStepsRecorded` compares the two modes directly.
- **A-35 (Phase 4a) — beyond item 2's letter; touches runtime behaviour, not what the user sees.** A write chain in
  `WatchSensorRecorder` (`WatchSensorWrites`) · leave each stream's task writing into the engine directly · **chain the
  recorder's writes, in arrival order, the distance settle included.** Each stream runs on its own task and the engine and
  store are single-writer. Before PR 2 a strength session had one always-on stream; with steps every session has two, and
  the first full run crashed (signal 11) with three streams delivering at once. Pinned by
  `testS239EveryStreamReachesTheEngineOneReadingAtATime` (red a23). Not addressed: the engine can still be written by the
  UI and by the chain at once; confining the engine to one actor belongs to the app shell (shipping-plan Phase 7, O-1).
- **A-36 (Phase 4a)** — Where the F-CAP replay driver lives · a new helper file, `Fixtures.swift`, or the replay's own
  test file · **`WatchCaptureContractTests.swift`, created in 4a** (predicted for 4b): the 4a replay tests, S-231 – S-238
  and S-237 share the one driver, and 4b extends it. Footprint findings: that file is early; `Fixtures.swift` (predicted)
  was not needed; `WatchLiveMirroringTests.swift` (predicted "only if emitted counts change") did not change.
- **A-37 (Phase 4a)** — The 4a doc items while Phase 3b runs in the same worktree · create `watch_session_capture.md`
  from 4a, or leave it to 3b · **left to 3b**, which created it during this phase; creating it in parallel would have
  collided. The sensor invariants went into `services_and_utils.md` › "Watch Sensors and the Platform Workout"; once the
  capture doc existed, its "The wrist half" section, the `session_end` invariant and the `session end` / `set block`
  vocabulary went there (one owner per rule, documentation standard §3.8), with a pointer left in `services_and_utils.md`.
- **A-38 (Phase 4a) — finding, not fixed.** The phone's corrections and deletions of wrist entries
  (`entryCorrections`, `deletedEntryIds`) live only in the engine's memory; `restore` does not rebuild them. D-117's
  "after phone deletions" and D-123's set blocks are evaluated from that projection, so a relaunch between a phone
  deletion and End would count the deleted set. Pre-existing, outside 4a's items; flagged for the reviewer.

- **A-39 (Phase 3b)** — When the import runs, and what "empty" means over time · **only once the `session_end` is
  staged**; a completed session with no effort entry left after the phone's deletions is consumed and acknowledged,
  and a late effort entry arriving after that imports it then — the same history as if the entry had come before the
  end, which is what makes S-262's "session_end first" order equal to the contract order. A session whose end is
  applied, whose entries were once materialised and which no longer exists is one the user deleted: its rows are
  consumed without history (D-136).
- **A-40 (Phase 3b)** — Row identity and stamps on import · **deterministic ids from wrist ids**
  (`WatchSessionImporter.segmentIdFor`, `effortIdFor` = session + slot + exercise + phone kind, `timedInstanceIdFor` /
  `roundInstanceIdFor` = session + `entryId`); `createdAtMs`/`updatedAtMs` from the wrist's own times (the entry's
  `loggedAt`, the session's start and end) or, on a corrected row, the correction's staging stamp. The phone's clock
  stamps only staging and application. That is what makes S-262's equality exact; an effort id ends with its kind so
  the entry index the phone parses out of an observation id is never read from it.
- **A-41 (Phase 3b)** — How the mirror's corrections are staged (a hook or a decorator) · **a transport decorator,
  `WatchInboxStagingTransport`**, installed by `createWatchSync`; staging runs before the inner send, and a correction
  staged after the import is applied at once. `live_session_mirror_state.dart` is untouched in this phase (footprint).
- **A-42 (Phase 3b)** — The receipt builder · move it, or call it where it is · **called where it is**
  (`WatchNutritionLogBridge.receiptFor`): still one builder, and `watch_nutrition_log_bridge.dart` is untouched.
- **A-43 (Phase 3b) — rare, but visible in history; for the reviewer.** A correction staged after the import · re-apply
  every field ever corrected, or only the fields it names · **only the fields it names**, so a user's own edit of
  another metric of that row in history stays. A window correction updates a timed or round instance's timing, not a
  summary's window, which records what the wrist measured. Test: `S-267 a later correction leaves the user’s own edit
  of another metric`.
- **A-44 (Phase 3b)** — "Reuse the phone's own row builders" (D-134) · copy them into the importer, or share them ·
  **shared:** `lib/core/utils/logged_entry_rows.dart` builds the set, timed and drill rows and the default segment for
  both `SessionCore` and the importer. `SessionCore` calls it with no change to any row it writes (the whole suite is
  otherwise unchanged). Footprint: three `session_core*.dart` files and one new file.
- **A-45 (Phase 3b)** — Re-ranking an imported effort when a late entry precedes it · delete and re-create, or update
  in place · **`WorkoutRepository.updateEffort`**, on Mock and Hive (an unknown id is ignored, never created).
  Deleting would cascade away the effort's rows and any edit the user made. Parity: the `updateEffort` tests in
  `test/watch_capture_contract_test.dart`. Footprint: three repository files; `scripts/sqlite_schema.sql` unchanged
  (no new table or column).
- **A-46 (Phase 3b)** — Receipts · on application only, or also on redelivery · **on application, and again for a
  redelivered entry that is already applied**: a wrist re-sends only what it holds unacknowledged, so a re-send means
  the earlier receipt was lost. Rows waiting for their session end are never receipted, and neither are the phone's
  own annotations.
- **A-47 (Phase 3b)** — What the inbox stages from a wrist `session_snapshot` · **origin `watch` only; the six
  stageable kinds only; and only entries carrying the fields the `observations_up` schema requires of their kind** —
  A-3, extended from the two new kinds to all six, because a partial copy staged first would keep the whole one out
  for good (staging never replaces a row). Quick-logs are never staged (A-15).
- **A-48 (Phase 3b)** — "Resume at construction" · **an explicit `WatchSessionInbox.resume()`** that
  `createWatchSync` awaits once, right after building the graph (a constructor cannot await). Its receipt is
  fire-and-forget like any other; a lost one is answered again at the wrist's next sync (A-46).
- **A-49 (Phase 3b)** — Failures · **the inbox never throws**: a failure is reported (`debugPrint` by default) and
  answered `WatchInboxOutcome.failed`, and the router still hands the message to the mirror and the nutrition bridge.
  What was staged stays staged and is applied by the next message for its session, or at the next start.
- **A-50 (Phase 3b)** — The phone-rating API (item 4) · **`WatchSessionInbox.recordPhoneRating(sessionId, rating)`**:
  off the 1–5 scale it is refused; before the import it is staged once (`phoneRatingId`, so a second phone answer
  before the import is refused and the first stands); after the import it is written through `updateSessionFeeling`
  and nothing is staged; it triggers no calendar refresh. **Consequence for Phase 5:** `createWatchSync` returns only
  the mirror, so the live session screen cannot reach the inbox yet. Phase 5 must expose it — return the inbox from the
  wiring, or give the mirror a rating hook.
  - **Revised (2026-09-26, review F-8).** The write after an import **does** refresh the calendar: it is a history
    change like any other (D-142), and without the signal the calendar kept showing an imported session unrated after
    the user had answered. `recordPhoneRating` now calls `_onHistoryChanged` after the direct write, asserted in the
    S-284 tests of `test/watch_session_import_test.dart` and `test/live_session_effort_rating_test.dart`. The refusal
    and staging rules above are unchanged, and F-12's `A-50` group now pins the scale check (state layer; the ends of
    the scale by review N1).
- **A-51 (Phase 3b) — finding, not fixed.** A late wrist entry for an imported effort takes its D-134 position. If
  the user has meanwhile added a set to that effort in history, the late entry can land on that set's entry index and
  overwrite it. It needs an import, a phone edit of that effort, and then a late wrist entry for it (the reopen case,
  S-218). Flagged for the reviewer.
- **A-52 (Phase 3b)** — History liveness (D-142) · **`createWatchSync(onHistoryChanged:)`**, which `lib/main.dart`
  points at `CalendarState.refresh`; called at most once per received message, annotation or resume, and only when an
  import or top-up wrote something.

- **A-53 (Phase 4b)** — How the owed prompt is stored (D-117) · a field on the session row, an observation, or a record
  of its own · **a record of its own: `WatchRatingPromptRecord` (`rating_prompt`), id `prompt-<sessionId>`**, never
  pruned, and answered only by the session's `effort_rating`, stored or acknowledged (A-27). It is not an observation —
  nothing about it is sent — and the session row keeps the shape the protocol reflects. `WatchStoreContents` gains
  `preferences` and `ratingPrompts`; the store's public surface is unchanged (`testS004…` green and unedited).
- **A-54 (Phase 4b)** — When End writes the owed prompt · before or after `finishSession` · **after.** Whether it is owed
  is decided first (it needs the phone's deletions, which only the running process holds, A-38); then the session end and
  the completed row are stored (A-25); then the prompt. A kill between the completed row and the prompt loses the question
  for that session — the user is not asked — but never any data. Writing it first would leave a prompt for a session the
  phone might then end, which D-117 says never owes one.
- **A-55 (Phase 4b)** — What settles an owed prompt · the session's rating only, or also a later change to the session (the
  phone reopening or completing it) · **the rating only**: once shown it must be answered (D-103, D-118). S-218 — the
  phone reopens a rated session and the wrist ends it again — owes nothing new because the rating exists.
- **A-56 (Phase 4b)** — D-118's open case, a counter-clockwise detent while nothing is picked · pick the lowest, or pick
  nothing · **pick nothing.** "Never return to unselected" presumes a selection, and a turn away from the scale's start is
  not a choice of 1. Crown travel short of a detent carries to the next turn, as the logging surface's crown does.
- **A-57 (Phase 4b)** — Storing `preferences_down` (D-113) · every copy, or the catalog precedent · **the catalog
  precedent**: an older copy is understood and dropped; any other is stored under `prefs-<messageId>`, and the newest by
  `generatedAt`, then store order, applies. A byte-identical redelivery (A-22's content-derived id) is a store no-op, so it
  is the copy already held, not a later-received one. A copy the wrist cannot read is refused as a result — not thrown and
  not answered with a snapshot — as `routines_down` and `foods_down` are, being reference data too.
- **A-58 (Phase 4b)** — Where the wrist's copy of the question lives · read the contract at runtime, or constants held to
  it by tests · **constants (`WatchEffortRatingCopy`), asserted against `watch/contract/watch_effort_rating_contract.json`**
  (S-211): the package reads no repository file at runtime — the precedent of `WatchStartSurfaceCopy` and
  `WatchNutritionPortion`.
- **A-59 (Phase 4b)** — "No dismiss, no back" on the views (D-118, D-119) · leave it to the app shell, or carry it on the
  view · **on the view**: `interactiveDismissDisabled(true)` and `navigationBarBackButtonHidden(true)`, so the prompt
  cannot be swiped away however the shell presents it. `WatchEffortRatingState` is itself the `ObservableObject` the views
  bind to (Combine builds on macOS, as `WatchLoggingModel` shows), so no logic sits inside `#if os(watchOS)`. The views
  were type-checked against the watchOS 26.4 simulator SDK, since `swift test` cannot build them.
- **A-60 (Phase 4b)** — A second rating through the engine · throw, or record nothing · **record nothing and return nil**
  (`WatchSessionEngine.recordEffortRating`), as D-116 says of a repeated append; the state's own Confirm is disabled once
  nothing is owed.
- **A-61 (Phase 4b)** — What item 4's structural guard scans · **declared `func`, `var`, `let` and `case` names, and
  `Button` titles and `label:` texts, in `WatchEffortRating.swift` and `WatchEffortRatingView.swift`**, prefix-matched
  without case ("not now" also as `notNow`). A modifier such as `interactiveDismissDisabled` is a call, not a
  declaration, so it is not matched. The guard also fails if it finds no declaration or no label, so a scan that has
  stopped looking cannot pass.

- **A-62 (Phase 5) — Default — owner to confirm (product).** The phone-ended question for a session with nothing logged ·
  ask whenever the phone's Finish completes a running session (D-139's letter), or not when it holds no effort entry after the
  phone's deletions · **not asked.** An empty session never becomes history (D-133): the answer would be staged and discarded
  with it (S-273), and the wrist does not ask about an empty session either (D-117's empty-session clause). The Finish itself
  is unchanged — the session closes on both devices. Test: `A-62 a session with nothing logged asks nothing`
  (`test/live_session_effort_rating_test.dart`).
- **A-63 (Phase 5) — A-50 resolved.** How `recordPhoneRating` reaches the phone's rating path · a rating hook on the mirror,
  return the whole inbox, or a narrow capability threaded by constructor · **the narrow capability:** `WatchSessionRatings`
  (an interface `WatchSessionInbox` implements, with `recordPhoneRating` only). `createWatchSync` returns a `WatchSyncGraph`
  (`mirror`, `ratings`) instead of the bare mirror; `lib/main.dart` passes `liveSession: watchSync?.mirror` and
  `watchSessionRatings: watchSync?.ratings` to `MyApp`, which threads it through `HomeScreen` to `LiveSessionScreen` exactly as
  `liveSession` is threaded — optional at every level and null together, so web and desktop (no watch transport, a null
  graph) build no watch UI as before. A hook on the mirror would make it know about history, which A-41 kept it from; the
  whole inbox would put staging and applying within a screen's reach. The debug harness passes its own inbox. Of the
  "phone's rating paths", the Summary's automatic prompt and its Add rating / Change sheet keep writing through
  `WorkoutState.updateSessionFeeling`: every session a Summary shows is already history, for which `recordPhoneRating` makes
  that very write, and routing the Summary through the inbox would bypass `WorkoutState`'s loaded session (the EFFORT row would
  not refresh). What those paths share with the phone-ended question is the sheet (A-64). Verified by S-281 – S-286 and, for
  the Summary's write staying final, S-264.
- **A-64 (Phase 5)** — Reusing PR 1's sheet · as-is, or extracted · **extracted, because it could not be reused as-is:**
  `_FeelingSheetContent` was private to the Summary's library and wrote through `WorkoutState` itself. It is now
  `EffortRatingSheet` (`lib/widgets/session/effort_rating_sheet.dart`) with the identical widget tree, an injected
  `onRated` (the sheet closes only when it answers true, so the Summary keeps its old "no session loaded, nothing happens"),
  and `EffortRatingSheet.show(mustAnswer:)`, which carries the modal flags both callers used. Zero visual change is proven by
  pixel-identical goldens of the pre-change file (Phase 5 notes), and PR 1's tests are unedited and green. Its five
  `withOpacity` infos moved with it.
- **A-65 (Phase 5) — Default — owner to confirm (UX detail).** How the phone-ended question is put · **exactly as the
  Summary's automatic prompt:** no tap outside and no swipe closes it; its subtitle names no modality (a wrist session carries
  none, D-135, so it reads as history will list it) and "Today" (the mirror holds no start time, and the session is being
  finished now); and it closes once answered even if the inbox does not record the answer — a second phone answer before the
  import is refused and the first stands (A-50), and a storage failure is the inbox's to report, with the Summary's Add rating
  still open to the user (S-285). Keeping a must-answer sheet open on a failed write would trap the user.
- **A-66 (Phase 5)** — What the screen shows for a session it did not close · **completed by the wrist: the closed card,
  built from the mirror's own state, with no Finish and no question (S-283); abandoned: unchanged** (the running layout with
  Finish, whose question never appears because the session was not running when Finish was pressed). D-139 speaks to a
  wrist-completed session only, and no wrist surface abandons a session today (`WatchSessionEngine.abandonSession()` has no
  caller in the views).
- **A-67 (Phase 5)** — Footprint beyond Predicted Files · **accepted:** the new widget file (item 2's extraction), the five
  wiring files of A-63, the construction-only edit of `test/watch_transport_test.dart`, and four docs whose claims the wiring
  made false or which list reusable widgets (`services_and_utils.md`, `navigation_and_screens.md`, `widget_catalog.md`,
  `widget_catalog/session_widgets.md`).

- **A-68 (Phase 6) — A-51 fixed. Default — owner to confirm (product: the order of a late entry).** How an imported or late
  wrist entry never overwrites or displaces a row the user made in history · (a) keep logged order among wrist entries and let
  them skip the positions the user's rows hold — which re-orders wrist rows around the user's and needs every position
  remembered; (b) once the user has added a row to an effort, change nothing already in it and put a late wrist entry after its
  last row; (c) put late entries in a second effort — which breaks D-134's one effort per slot, exercise and kind · **(b).** An
  effort nobody added to keeps the exact pre-fix path — logged order, re-keyed moves — so every Phase 3b guarantee (S-262's
  order independence first) is unchanged. **How rows are told apart:** A-40 stamps every row the import writes with its entry's
  `loggedAt` as `createdAtMs`, and every phone path that edits a row keeps that stamp (`updateEntryValue`, `markSetSkipped`,
  `restoreSessionSnapshot`); instances carry ids the import derives from wrist ids. A row that is neither where logged order puts
  its entry nor stamped by an entry not yet placed — or an instance with an id no wrist entry gives — is the user's
  (`_EffortRows` in `lib/core/services/watch_session_importer.dart`). In such an effort: a live deletion removes only the
  entry's own rows; a later correction edits only the entry's own rows, found by its stamp, and is skipped if they cannot be told
  apart (two wrist entries logged in the same millisecond); deleting every wrist entry keeps the effort and the user's rows; and a
  pass that stopped half-way (A-49) finishes the entry where it started it — its instance says where, and a set's stamped rows are
  reused only if they hold exactly what the entry would write, so a reuse can never change a user's row. A row the user adds to a
  wrist entry (an extra weight, say) counts as the user's, which is the cautious side. **User-visible:** in an effort the user has
  added to, a wrist entry that arrives late is listed after the user's own rows, not in the order it was logged, and nothing
  already listed moves. Efforts themselves are not re-ordered by this: an effort the user added keeps sorting after imported
  efforts of equal rank (the repositories break ties by creation time), and no row of it is touched. Tests: the `A-51` group of
  `test/watch_session_import_test.dart` (nine; pre-fix red and thirteen mutation reds in the Phase 6 notes).
- **A-69 (Phase 6)** — Where D-144's `swift test` runs · `scripts/pre_release_check.sh`, and also a step in
  `.github/workflows/release.yml`'s iOS job, which does run on macOS (`macos-14`) · **the script only.** D-144 and Phase 6 item 4
  name only the script; the workflow is a build-and-upload job that runs no suite today, not even `flutter test` — the script is
  the code gate run before archiving; and the package is verified only against this machine's toolchain (Swift 6.3.1, Xcode
  26.4.1), not the runner's default one, so a workflow step could block the iOS release build for a toolchain reason (O-16). In
  the script it is §14: it runs on macOS with a usable toolchain and blocks on a red suite; it logs a skip under `--fast`, on a host
  that is not a Mac (the package imports Combine and SwiftUI outside any `#if`, so it builds only on Apple platforms) and on a Mac
  whose `swift --version` fails. No existing gate check changed. Test: `test/pre_release_gate_swift_test.dart` (S-293), which runs
  the gate in a temporary copy with stand-ins for `flutter`, `swift` and `uname`, so it proves the step on any host.
- **A-70 (Phase 6) — finding, not fixed; for the reviewer.** Opening an imported watch session in history edit mode and leaving
  without saving deletes its run's and rounds' heart-rate summaries: a probe took F-CAP's six summaries to two (session and set
  block). `restoreSessionSnapshot` restores by deleting and re-creating every timed and round instance
  (`deleteTimedInstancesForEffort`, `deleteRoundInstancesForEffort`), and Phase 2 made those deletes take the summaries that target
  the rows with them (D-131); re-creating the instances does not bring the summaries back. Options: restore instances by update
  rather than delete-and-create, or snapshot and restore the session's summaries too. Not changed here — it is the phone's
  edit-mode path for every session, outside PR 2's items, and no watch build ships yet (O-15).
- **A-71 (Phase 6)** — Footprint and the band · `services_and_utils.md` is 45,607 B, under the band, so item 1's trim was not
  needed and it was not touched in Phase 6. Extra files: the importer and its test (A-51, assigned to this phase's residue) and the
  new `test/pre_release_gate_swift_test.dart` (S-293; the existing gate suites do not pin the step list, so none changed).
- **A-72 (V round) — Which line the V-1 mutation had to hit.** The field initialiser caught nothing:
  `initialize()` recomputes the value through `_loadFromPrefs`, so the default that decides is the one passed to
  `getPreferenceString`. A mutation that stays green is a failed measurement, not evidence the test is weak.
- **A-73 (V round) — How far to take V-4.** All three literals were PR 1's, moved verbatim, so touching any of them
  risks pixels. The barrier went because the SDK's own fallback resolves to the identical value and no app
  `BottomSheetThemeData` exists; the 20.0 radius went to its existing token (same value). The tile radius stays (O-21).

**Assumption Log summary for the reviewer (Phase 6 item 6).**
- **Owner to confirm — user-visible:** A-4/A-33 with O-13 (the next round's countdown after a dialled round, unchanged); A-43
  (a correction staged after the import applies only the metrics it names, so the user's own edit of another stays); A-62
  (the phone's Finish does not ask about a session with nothing logged); A-65 (how the phone-ended question is put, and that it
  closes once answered even if the answer cannot be recorded); A-68 (a late wrist entry goes after the user's own rows in an
  effort the user added to). Every D-entry marked "Default — owner to confirm" still stands as written; none was vetoed
  (Feedback is empty).
- **Findings, not fixed — for the reviewer:** A-35 (engine concurrency; O-1, now on the shipping plan's Phase 7 checklist), A-38
  (the wrist forgets phone corrections after a relaunch; O-14), A-70 (edit-mode Back drops imported summaries; O-15), and Phase
  2's schema drift (`TrainingSession.toMap` writes `is_rolling`, which `app_training_session` lacks).
- **Beyond an item's letter, recorded where decided:** A-18 (block delete cascade), A-35 (the recorder's write chain), A-44 and
  A-45 (shared row builders; `updateEffort`), A-50/A-63 (the rating capability threaded through `MyApp` and `HomeScreen`), A-64
  (PR 1's sheet extracted to `lib/widgets/session/effort_rating_sheet.dart`), A-69 (the gate runs `swift test` in the script
  only).
- **Technical defaults with tests behind them:** A-1 – A-3, A-5 – A-17, A-19 – A-32, A-34, A-36, A-37, A-39 – A-42, A-46 – A-49,
  A-52 – A-61, A-66, A-67, A-71.

---

## Feedback

Owner vetoes of any "Default — owner to confirm" entry also go here and become an Iteration 2 block.

**Findings moved out of this plan 2026-09-26** (`.github/agents/pr_scope_budget.md` §2): round 1's
findings F-1 – F-19, the round-2 re-review's N1 – N9, and the pre-approval verification pass's
V-1 – V-4 live in `2026-09-25-02-stats-pr2-watch-capture-plan.review.md`; their fixes'
measurements, red→green tables and footprints live in
`2026-09-25-02-stats-pr2-watch-capture-plan.evidence.md`. The review round's fix checklist is in
"## Progress › Review fix round"; every F- and N-item on it is done. The verification pass approved
the PR with two warnings (V-1 one line of test, V-2 pre-existing stale paths in a doc this PR does
not touch) and two optional suggestions (V-3 one unread result field, V-4 the extracted sheet's
inherited colour/radius literals). None is critical; the owner decides whether to fix in this PR.
The copy of round 1's review narrative below is left as the record it was written as.

### Code review — 2026-09-26 (@code-reviewer), range `ae71e23..c7335de`

**Verdict: CHANGES REQUESTED.** One blocker (F-1). F-2, F-4, F-5 and F-6 are cheap and belong in
this PR; the rest may follow.

Reproduced in a scratch copy of the tree, never in the worktree: `flutter test` `01:07 +2973 ~1: All
tests passed!`, `swift test` `Executed 241 tests, with 0 failures`, `flutter analyze` `242 issues
found.` (none in files this PR changed). CRLF intact on `main.dart`, `app.dart`, `models.dart`,
`omni_theme.dart`, `sqlite_schema.sql` (every line, base and head). Every probe and mutation ran in
the copy and every file was restored byte-identically (`cmp` against the worktree).

**Mutation sample** (one mutation per row, the named rule reverted; Dart rows ran the named suite or
the full suite, Swift rows the full `swift test`):

| # | Rule reverted | Result |
|---|---|---|
| D1 | Phone's staged rating wins at import (D-138) | caught (S-281) |
| D2 | Deleted session stays deleted (D-136) | caught (S-266) |
| D3 | A-51 user-row detection | caught (7 A-51 tests) |
| D4 | Summary window is the measured one, not the corrected one (A-43) | NOT caught — full suite green |
| D5 | Receipt names only applied rows (D-132) | caught (4 tests) |
| D6 | Inbox staged before the mirror answers (D-132, router order) | NOT caught — full suite green |
| D8 | Capture-field placement on snapshot entries (Dart validator) | NOT caught — full suite green |
| D9 | `pausedMs` equal to its window accepted (Dart validator) | NOT caught — full suite green |
| D11 | Phone rating off the 1–5 scale refused (A-50) | NOT caught — full suite green |
| D12 | After import, a wrist rating applies only while none is held (D-138) | caught (S-264, S-281) |
| W1 | `session_end` exactly once, also after an acknowledged prune (D-120, A-27) | caught |
| W2 | Readings held until the `session_end` is acknowledged (D-129) | caught (S-237 legacy case) |
| W3 | Every session's owed observations re-sent (D-128) | caught (S-240) |
| W4 | An answered prompt is no longer owed (D-117) | caught (S-211, F-CAP) |
| W5 | Round pause excluded from heart rate (D-122) | caught (F-CAP) |
| W6 | No sensor readings means no summary, never zero (D-122 f) | caught (F-CAP no-sensors) |
| W7 | Capture-field placement on snapshot entries (Swift validator) | NOT caught — suite green |
| W8 | `pausedMs` equal to its window accepted (Swift validator) | NOT caught — suite green |
| W9 | Append-only guard (F-12): a guarded `func` name added | caught (`testS004…`) |
| W10 | Sensor writes chained (A-35) | caught (S-239) |

**Findings**

- **F-1 — CRITICAL — DESIGN — A-70 verified, and PR 2 must fix it.**
  `lib/state/workout/session_core_lifecycle.dart:272` (`restoreSessionSnapshot` deletes and
  re-creates every timed and round instance at `:319` and `:326`; `removeExerciseFromSession` →
  `deleteEffort`, `lib/state/workout/session_core_entry.dart:404`). With D-131's cascade these
  deletes take the summaries, and re-creating the rows does not bring them back. The A-70
  wording is too broad. Plain Back with nothing changed pops without restoring. The loss needs a
  structural edit followed by Discard. Verified on Mock and Hive: F-CAP imported → loaded → edit
  → add a set to the bench, or delete round 1 → Discard. Summaries go from
  `[session, effort, timed, round×3]` to `[session, effort]`. Removing the bench and then
  discarding leaves `[session]`. Save loses nothing. PR 2 created this regression: the restore
  was lossless before the cascade existed. The loss is silent, because no phone screen shows
  summaries. It is permanent, because the wrist prunes its readings once the end is acknowledged
  (D-129). It breaks AC-3.5, and neither this plan nor the shipping plan gates the watch release
  on O-15.
  **Fix:** carry the session's summaries in `SessionEditSnapshot`. Load them with the session in
  `SessionCore`, so `snapshotSessionState` stays synchronous. Re-create them with
  `createSensorSummary` (put-if-absent) at the end of `restoreSessionSnapshot`. Add a regression
  test for the three edits. A restore-by-diff alone is not enough: deleting a round or an
  exercise cascades live, before Discard.
- **F-2 — WARNING (medium) — MECHANICAL — import passes over one session run concurrently.**
  `lib/state/watch/watch_session_inbox.dart:321` (`_settle`) is not serialised.
  `lib/core/platform/watch_transport.dart:120,155` dispatches each frame without waiting for the
  last one, and the wrist sends one `observations_up` per stored observation.
  Verified through `createWatchSync` and the real `WatchConnectivityTransport`, with F-CAP `full`
  frames sent back to back:
  - Mock produced 2 timed and 6 round instances in contract order, and every round at index 0 in
    reversed order. `expectCaptureImport` fails.
  - Hive was correct in 16 of 16 runs (gaps of 0–20 ms, both orders). That holds only because
    Hive's reads are synchronous. Nothing tests or documents this, and S-272's parity does not
    hold for the production delivery pattern.
  **Fix:** chain every `_settle` (receive, resume, `recordPhoneRating`, `stagePhoneChanges`)
  through one future. Add a test that pushes F-CAP back to back through the real transport on
  Mock and Hive.
- **F-3 — WARNING (low) — DESIGN — D-136 edge: a deleted session is re-created.**
  `lib/core/services/watch_session_importer.dart:177-179` infers "the user deleted it" from
  `materialised`, which a live `delete_entry` empties. Verified:
  1. The session is imported with e-1; e-2's send failed.
  2. The lifecycle message was lost, so the mirror still shows the session live, and the user
     deletes e-1 there. The session stays in history with 0 efforts.
  3. The user deletes that session.
  4. e-2 arrives and the session is back.

  **Fix:** record durably that the session was materialised, for example a phone-origin marker
  staged by `_createSession`, and test for it. Owner question: should an imported session whose
  entries were all deleted live leave history, as D-133 keeps empty sessions out?
- **F-4 — WARNING (medium) — MECHANICAL — the system back closes the must-answer phone prompt.**
  `lib/widgets/session/effort_rating_sheet.dart:53-68` sets only `isDismissible` and `enableDrag`.
  Verified: the phone's Finish, then `handlePopRoute()` (Android back), closes the sheet with
  nothing staged. S-281 tests only a barrier tap and a drag. This is inherited by PR 1's automatic
  Summary prompt (same sheet). D-4 and D-139 already decide "must be answered".
  **Fix:** `PopScope(canPop: !mustAnswer)` in the sheet, plus a `handlePopRoute` assertion in
  S-281 and in PR 1's prompt test.
- **F-5 — WARNING — MECHANICAL — the D-132 ordering has no guard, and the doc's pointer can't
  fail.** D6 (mirror asked before inbox at `lib/state/watch/watch_incoming_router.dart:72`)
  passes the full suite. `test/watch_session_import_test.dart:270-277` gives the reason "staged
  before anything else answers", but the assertion checks only `receipt.inbox == staged`.
  `docs/watch_session_capture.md:132` cites it. The order matters because a phone
  snapshot confirms the entry ids it carries.
  **Fix:** in that test, assert at the mirror's re-assertion send that the entries of the
  triggering message are already staged.
- **F-6 — WARNING — MECHANICAL — two normative validator rules untested on both stacks.**
  - (a) Capture-field placement on snapshot entries (PROTOCOL.md "Session capture"):
    `lib/core/sync_protocol/message_validator.dart:336` and
    `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift:233` (D8, W7).
  - (b) `pausedMs` equal to its window: `message_validator.dart:473` and
    `SyncProtocolValidator.swift:363` (D9, W8). Equality is a real wire value, because A-30 caps
    at the window; a regression would refuse that round.

  **Fix:** an invalid snapshot fixture with steps on a round, and a valid round fixture whose
  pause equals its window, both registered in the manifest.
- **F-7 — WARNING (low) — MECHANICAL — the crown wrap can flip the rating.**
  `watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift:68`
  (`isContinuous: true` over ±10 detents) against `WatchEffortRating.swift:210` (a plain delta).
  Verified in state: +1 to +10 detents (5 picked), then the wrapped value −10 detents picks 1. On
  the device a continuous crown wraps at its range end, which `swift test` can't see.
  **Fix:** `isContinuous: false`, or ignore jumps larger than half the range.
- **F-8 — WARNING (low) — MECHANICAL — the phone's answer to an imported session refreshes
  nothing.** `lib/state/watch/watch_session_inbox.dart:245-247`. Verified: 1 refresh after the
  import, still 1 after `recordPhoneRating`. In S-284's order the calendar keeps showing the
  session unrated, whereas the Summary path refreshes.
  **Fix:** call `_onHistoryChanged` after the direct write (revises A-50).
- **F-9 — WARNING (low) — DESIGN — wrist preference rows grow by one per sync.**
  `lib/state/watch/watch_sync_request_handler.dart:77` stamps `generatedAt` with the send time,
  the id follows it (A-22), and `WatchPhonePreferences.swift:144` stores each copy. Nothing prunes
  them. Verified: 5 syncs with an unchanged setting leave 5 rows. This stays latent until the
  durable store of shipping Phase 7 exists.
  **Fix:** stamp `generatedAt` with when the setting last changed (the `foods_down` precedent),
  or prune superseded rows.
- **F-10 — SUGGEST — MECHANICAL — `integer` means different things on the two validators.**
  Verified on the same message: Swift accepts `steps: 3200.0`, and Dart refuses it
  (`invalid_type`). `WatchCaptureContractTests.swift:232` compares numbers by value, so an
  Int→Double drift on the wrist would pass `swift test` and be refused by the phone. The wrist
  emits Int today.
  **Fix:** make the Swift `integer` check reject float-typed numbers, and add an invalid fixture
  with an integral double.
- **F-11 — SUGGEST — DESIGN — A-35 residual (outside PR 2, tracked).** The shipping Phase 7 item
  "engine and store written by one actor" needs a package change, not only the shell. The
  recorder's stream tasks (`WatchSensorRecording.swift:204`) and `WatchSensorWrites` run
  unisolated. PR 2 widens exposure (always-on steps, summary reads at log time and at End) but
  adds no new class of race.
- **F-12 — SUGGEST — nits.**
  - D11 and D4 above are untested. D4's path is unreachable, because the phone corrects sets only.
  - `docs/theme_and_settings.md:88` sits under a field/default table in a section
    it touched (standard §5).
  - S-201, S-202 and S-205 reuse ids of `test/stats_progress_test.dart` and
    `test/home_nutrition_summary_card_test.dart`.
  - `lib/features/session/live_session_screen.dart:37` reaches into `lib/watch/` for one status
    constant; a mirror getter would do.

**Verified sound:**
- Arrival-order independence and redelivery (sequential), tombstones, the A-51 fix, rating
  precedence and receipts.
- Validator parity: same rules, wording and order.
- The session switch (S-205, S-251).
- The shared contract proven end to end: the wrist emits exactly `expectedEvents`, and the phone
  imports exactly `expectedImport`.
- Summary math, exactly-once `session_end`, the prune gate, the resend, and the kill-safe,
  answer-only prompt.
- `WatchSessionRatings` is null together with the mirror on web and desktop.
- The sheet extraction is behaviour-identical, and PR 1's tests are untouched.
- The docs: no prohibited content, under the band, every pointer resolves.
- The gate step is sound.
- `lib/watch/` changes only `WatchSensorKind.steps`.

**Assumption Log:**
- A-70: fix required (F-1).
- A-50's no-refresh: revise (F-8).
- A-22/A-57's per-sync copies: revise (F-9).
- The other entries: ratified as built.

### Review fixes — F-1 (Opus)

**Fix.** Discarding a history edit now returns the session to exactly the sensor summaries it had
when editing began. Save is unchanged.
- `SessionEditSnapshot` carries the session's summaries (`sensorSummaries`, required).
- `SessionCore` holds them in memory. `loadHistoricalSession` and `loadSessionData` load them with
  the session through `WorkoutRepository.getSensorSummariesForSession`. `clearSession` and
  `createNewSession` clear them. So `snapshotSessionState` stays synchronous.
- At the end of `restoreSessionSnapshot`, after the rows are back and before the reload, every
  snapshotted summary is re-created with `createSensorSummary`. Put-if-absent leaves the survivors
  untouched.
- Save is unchanged: nothing outside the restore re-creates a summary. A Save that deleted a round
  or an exercise loses that target's summary (D-131).
- `loadSessionData` re-reads the summaries before every snapshot. So after that Save, a later edit
  followed by Discard does not re-create a summary for a round that no longer exists.
- Summaries are loaded only for an ended session. They are imported with the wrist's session end,
  so a session in progress has none.
  - Why it matters: an unconditional load added one await to every live-session reload, and
    `test/screen_widget_test.dart` "empty session shows 00:00 timer and timer does not advance
    before first exercise" failed with it (3 of 3 runs) and passed without it (3 of 3).
  - With the condition, live-session loads are exactly as before, and that assertion is untouched.

**Tests.** New `test/watch_session_edit_restore_summaries_test.dart`, 10 tests, 5 per store. F-CAP
`full` is imported through the inbox on Mock and on Hive, and Hive is read back after a restart.
- Add a set to the bench, delete round 1, or remove the bench, each followed by Discard (3 per
  store). Each asserts:
  - the six summaries before, by exact id and value;
  - the live cascade right after the edit;
  - the six again after Discard, by id, value and full `toMap`;
  - the rows restored, and the summaries stored after a restart.
- Delete round 1, then Save: that round's summary is gone, and the other five are unchanged by
  `toMap`, also after a restart.
- That Save, then a later edit followed by Discard: the five, and no summary for the deleted round.

**Red → green.** Logs are `pr2_fix_f1_*.log` in the session scratchpad.
- Red, on unfixed code (HEAD `01793c3` lib plus the new test): `+2 -8`.
  - Add a set or delete a round, then Discard: `[session, effort]`.
  - Remove the bench, then Discard: `[session]`. These are the reviewer's numbers.
  - The later-Discard case: `[session, effort]`.
  - The two Save cases pass here by design, because they pin D-131's existing loss.
- Green, on fixed code: `+10: All tests passed!`.
- Mutation, the re-create loop removed from `restoreSessionSnapshot`: `+2 -8`, the eight
  Discard-dependent tests red. Done by copy-and-restore in place; `cmp` identical after.
- Mutation, `loadSessionData` no longer re-reading the summaries: `+8 -2`. Exactly the
  later-Discard test fails on both stores, because the deleted round's summary is re-created for a
  round that no longer exists. Run in a scratch copy of the tree.
- Mutation, the round-summary cascade removed from both repositories' `deleteRoundInstance`: the
  Save case goes red on both stores, so it does guard D-131. Run in a scratch copy of the tree.
- Targeted dependents, 24 files (the new file plus the edit-mode, session-lifecycle,
  history/summary and import suites): `+900: All tests passed!`. The full suite was not run here.

**Files changed.**
- `lib/core/models/session_edit_snapshot.dart`
- `lib/state/workout/session_core.dart`
- `lib/state/workout/session_core_io.dart`
- `lib/state/workout/session_core_lifecycle.dart`
- `test/watch_session_edit_restore_summaries_test.dart` (new)

All are LF before and after. No existing assertion changed.
