# The 18 series — the owner's first real-device QA of the watch app

Planned 2026-10-08 from the owner's `flutter run` log and the watch QA walkthrough. Each PR is
planned and reviewed separately; this index only orders them and records what each one is for. Plan
files live in `docs/plans/2026-10-08-<n><letter>-<name>-plan/`, each with an `.evidence.md` and a
`.review.md` beside it.

Baselines when the series was planned (every PR compares against these):
`.github/copilot/scripts/macos/gateway.sh test` 4061 tests / ~1 pre-existing failure;
`gateway.sh lint` 196 issues / 0 errors; `gateway.sh swift-test` 335 tests / 0 failures.

## The PRs

| PR | Plan | What it fixes | Tracks | Phases | Ledger / Scenarios | Status |
|---|---|---|---|---|---|---|
| 18a | `2026-10-08-18a-phone-hardening-plan/2026-10-08-18a-phone-hardening-plan.md` | Two phone crashes from the owner's log: `notifyListeners()` during the first build (`SessionCore._setLoading` ← `loadSessionData` ← `WorkoutSessionScreen.initState`), and `int.clamp` throwing in `SessionSummaryService.computeSessionRestTimeMs` on a session whose end is before its start — plus the root-cause writer fix and a migration repairing stored rows | phone (`lib/`) | 4 | D-150…D-154, S-150…S-156 | planned |
| 18b | `2026-10-08-18b-watch-rest-count-up-plan/2026-10-08-18b-watch-rest-count-up-plan.md` | The wrist's rest is a **count-up**, like the phone's: no `restSeconds`, no rest `plannedDurationMs`, no "left", no rest alarm; a rest screen of its own with a single **Next**; the wire refuses a rest length; the rule in `docs/global_conventions.md` and a contract test that fails if it comes back | watch client + sync contract | 4 | D-160…D-169, S-160…S-168 | planned |
| 18c | `2026-10-08-18c-watch-rest-to-phone-plan/2026-10-08-18c-watch-rest-to-phone-plan.md` | The remainder of 18b, designed but not shipped there: the wrist's rest **reaches the phone** as an `observations_up` `rest` entry, and the importer writes an `EntryRest` (start = the set's logged time, end = Next / the next set), so the phone's rest history includes wrist rests | phone history + watch client + sync contract | 3 | D-166/D-167 (pinned in 18b), D-214/D-215; S-ids in the plan | committed (dc69aa3 the wire, 2a19db2 the phone) |
| 18d | `2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md` | The half 18c left unwritten: the wrist **emits** its rest when it ends (one emission site; `afterEntryId` and a derived `eventId`), and the four docs that still said a rest cannot travel say what travels and what stays device-local | watch client + docs | 2 | D-210…D-224, S-320…S-341 | Phase 1 committed (ac5e26f); Phase 2 in review |
| 19 | 19a: `2026-10-08-19a-phone-authority-plan/2026-10-08-19a-phone-authority-plan.md` (committed); 19b: `2026-10-08-19b-honest-delivery-plan/2026-10-08-19b-honest-delivery-plan.md` (+ `.evidence.md`, `.review.md`) | Reliable delivery and **ONE** shared session (the phone and the wrist must not diverge into two sessions): the watch refuses a second session (D-171), the phone ends the wrist's own session and then asserts its own (D-170/D-172), no end is lost and no second rating prompt appears (D-173/D-174); the "each keeps its own" rule and the pages that carry it are superseded (D-181). 19b makes the delivery honest: `send` reports whether the frame got through (D-190/D-196), a frame that did not is owed and re-offered in full (D-197/D-202), a stranded wrist self-heals by re-announcing its finished sessions at catch-up (D-199), and the phone follows (D-198) | phone + watch + sync contract | 4 (19a) + 4 (19b) | D-170…D-203, S-170…S-218 | 19a committed; 19b expanded by the planner — @developer Phase 1 |
| 19c | not yet planned | Keeping the watch app alive on the wrist — a HealthKit workout session / extended runtime session, so a lowered wrist does not stop the radio: an app capability plus a provisioning change, so it needs the owner's approval and signing access. 19b needs none of it (it re-offers at the next frame), and no later PR may assume it exists until this row moves | watch client | — | — | placeholder — needs the owner's decision |
| 20 | `2026-10-09-20-watch-menu-plan/2026-10-09-20-watch-menu-plan.md` | Watch menu screen: exercise/set navigation, add exercise, finish — one toolbar control opens a list of the session's exercises (count, current marked), a row jumps, Add exercise appends from an add-only picker, Finish keeps End's rating rules | watch client | 2 | D-1100…D-1114, S-1100…S-1113 | committed (plan 2026-10-09-20: model f4fd2f3, surfaces + docs in the next commit); 20b (`2026-10-09-20b-watch-menu-session-only-plan/2026-10-09-20b-watch-menu-session-only-plan.md`) removed the menu's Add exercise and its picker: the menu is the session's exercises, then Finish |
| 21 | not yet planned | Watch Start → Log for the timed kinds (the watch can start and log timed sets itself) | watch client | — | — | placeholder — no design |
| 22 | `2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.md` (committed 06e3fe4) | The phone's **Rest Ping** setting reaches the Apple Watch: `preferences_down` carries `restPingSeconds` (D-240), the wrist stores the newest one it is sent (D-242) and taps at each multiple of it while **its own** rest counts up — haptically, soundlessly, and never as a rest timer or an end-of-rest alarm (D-243, D-250). Its former Phase 3 was moved whole to 22b by the scope check | sync contract + phone sender + watch client | 2 | D-240…D-250, S-221…S-225, S-241…S-247 | committed (06e3fe4) |
| 22b | `2026-10-08-22b-rest-ping-wear-settings-docs-plan/2026-10-08-22b-rest-ping-wear-settings-docs-plan.md` | The rest ping's other half: the Dart Wear logging surface pings from the same contract table, not a second copy of the numbers (D-260, D-261, D-265); the Settings subtitles name the device each row reaches — Rest Ping both, Rest Ping Sound phone only (D-262); the convention row and three docs say the rest ping is the one allowed rest cue while still denying a rest length, a countdown and an end-of-rest alarm (D-263); and the count-up contract test no longer claims "no rest alarm anywhere", with an allowance narrow enough that `restPingSeconds`, `rest_ping_interval` and `playRestPing()` are not findings (D-264). Two rows here because 22's Phase 3 became this PR (D-266) | Wear client (`lib/watch/`) + `lib/features/settings/` + docs | 1 | D-260…D-269, S-241…S-245 (Dart half), S-249, S-250 | planned — @developer Phase 1 |

## Order and dependencies

- **18a and 18b are independent.** 18a touches `session_summary_service.dart` and `session_core*`;
  18b touches neither the phone's state nor its repositories. Either order works; if both are open,
  the second rebases and re-runs the phone suites.
- **18b before 18c.** 18c implements the wire kind and the importer that 18b's Ledger (D-166/D-167)
  pins; 18b ships the refusal that makes a rest length impossible, so 18c cannot re-introduce one.
- **18c before 18d.** 18d writes the wrist half of 18c's contract — the emission site that feeds the
  importer 18c shipped — and 18c's importer is what makes the docs' travel claim true, so the doc
  edits wait for both.
- **19 is the prerequisite for 20 and 21** (a shared session is what makes menu navigation and
  watch-side logging meaningful); 20 and 21 are independent of each other.
- The rest rule (18b D-160) applies to every later PR: 20 and 21 must not add a rest preset, a rest
  countdown or a rest alarm on the watch menu or the Start → Log path.

## Standing constraints for every PR in this series

- Budget: `.github/copilot/pr-scope-budget.md`; at most 8 items per phase; two soft signals fire →
  plan the remainder as the next lettered PR and say so.
- Every phase ends with tests for its S-ids and the doc updates it invalidated; docs trail code by
  zero phases (`docs/documentation_standard.md`).
- Every scenario lists its fixture values and says "Red without the change because …" or marks itself
  a negative guard with its mutation.
- Agents run `gateway.sh test`, `swift-test`, `lint`, `prove-red` only. No `xcodebuild`, no simulators,
  no real devices: the governor builds the watch scheme and the owner walks through the QA doc.
- `testWidgets` runs in FakeAsync: run widget tests Mock-first, seed Hive in `setUp`, never await a
  real delay.
- `docs/state_management/watch_surface.md` is near its 51.2 KB ceiling: make room by removing stale
  prose rather than adding.
- The agent instruction files (`CLAUDE.md`, `.github/copilot/agent-rules.md`) are the owner's; plans
  may recommend a line for them but never edit them.
