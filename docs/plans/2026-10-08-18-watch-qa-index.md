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
| 18c | `docs/plans/2026-10-08-18c-…` (not yet written) | The remainder of 18b, designed but not shipped there: the wrist's rest **reaches the phone** as an `observations_up` `rest` entry, and the importer writes an `EntryRest` (start = the set's logged time, end = Next / the next set), so the phone's rest history includes wrist rests | phone history + watch client + sync contract | 3 (outlined) | D-166/D-167 (pinned in 18b), S-ids assigned when planned | placeholder — planned after 18b lands |
| 19 | 19a: `2026-10-08-19a-phone-authority-plan/2026-10-08-19a-phone-authority-plan.md`; 19b: reliable delivery that survives locked screens (planned after 19a) | Reliable delivery and **ONE** shared session (the phone and the wrist must not diverge into two sessions): the watch refuses a second session (D-171), the phone ends the wrist's own session and then asserts its own (D-170/D-172), no end is lost and no second rating prompt appears (D-173/D-174); the "each keeps its own" rule and the pages that carry it are superseded (D-181) | phone + watch + sync contract | 4 | D-170…D-181, S-170…S-185 | 19a expanded by the planner — @developer Phase 1 |
| 20 | not yet planned | Watch menu screen: exercise/set navigation, add exercise, finish | watch client | — | — | placeholder — no design |
| 21 | not yet planned | Watch Start → Log for the timed kinds (the watch can start and log timed sets itself) | watch client | — | — | placeholder — no design |

## Order and dependencies

- **18a and 18b are independent.** 18a touches `session_summary_service.dart` and `session_core*`;
  18b touches neither the phone's state nor its repositories. Either order works; if both are open,
  the second rebases and re-runs the phone suites.
- **18b before 18c.** 18c implements the wire kind and the importer that 18b's Ledger (D-166/D-167)
  pins; 18b ships the refusal that makes a rest length impossible, so 18c cannot re-introduce one.
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
