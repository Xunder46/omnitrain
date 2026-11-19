# Evidence: 2026-11-14-175-phone-set-echo-duplicates-plan

Baselines collected by the Conductor (2026-11-14) during planning, before any code change.
Implementers append their own run outputs below each section.

## Doc sizes (against the 52 KB band, rule docs/documentation_standard.md)

- `docs/watch_session_capture.md` — 40.3 KB
- `docs/watch_session_sync.md` — 45.1 KB
- Both have headroom; the planned deltas are a few hundred bytes each.

## Sweep standing numbers (pre-fix, from 172's investigation, findings §2/§8)

- Contract sweep at 2000 seeds (`--dart-define=CONVERGENCE_SEEDS=2000`,
  `S-14509 every random seed converges`): 19 stalls, heal-only list of 13:
  [209, 270, 316, 899, 1662, 2043, 2380, 2387, 2510, 2669, 3189, 3548, 4098] (byte-identical across runs).
- Kill sweep at 2000 (`S-16310`): 19 stalls, heal-only list of 11:
  [352, 565, 209, 270, 2043, 316, 2380, 899, 2387, 2510, 2669].
- Stable heal core (shrunk to the 4-action echo trace, findings §3):
  [209, 270, 316, 899, 1662].
- Expected post-fix: heal-only lists empty in all three sweeps; the register's `heal`
  entry text states the measured count.

## Ratchet baselines (test/watch_convergence_random_test.dart)

- `shippingRatchet = (kSeedCount * 6 / 200).ceil()` (:232-235) — at 200 seeds = 6; heal
  is excluded from its count (:285-289).
- `phoneKillRatchetPer200 = 10` (:341-344) — heal excluded (:395-399).
- Decision rule (D-17508): touch only on a measured non-heal class shrink; never raise.

## `flutter analyze` baseline

- Measured at HEAD by the developer (2026-11-14, `gateway.sh lint`): **181 issues**
  (all pre-existing info notices plus one warning in `test/food_catalog_load_test.dart`;
  the check exits 1 on them). Plan 175 must stay at or under 181.

## Phase 1 — red at HEAD (prove-red)

Command (one per file, through the gateway):

    .github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_import_test.dart

- `test/watch_session_import_test.dart` — **RED AT HEAD (exit 1)**, 3 failing tests,
  each on the assertion the scenario names:
  - `S-17502 a snapshot carrying the phone’s own ids stages only the wrist’s own entry`
    — `Expected: ['w-entry-1'] / Actual: ['w-entry-1', 'entry-sx-bench-1', 'entry-sx-bench-2']`
  - `S-17503 the live events carry the phone’s own ids too: only the wrist’s event is staged`
    — `Expected: ['w-entry-1'] / Actual: ['w-entry-1', 'entry-sx-bench-1']`
  - `S-17504 a staged row under the phone’s own id imports nothing on the history path either`
    — `Expected: null / Actual: <Instance of 'TrainingSession'>`
  - S-17504's held-merge case and S-17511 passed at HEAD (they pin the receiver contract,
    not the bug; see the mutation table).

    .github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_convergence_harness_test.dart

- `test/watch_convergence_harness_test.dart` — **RED AT HEAD (exit 1)**, 5 failing tests,
  all `Expected: true / Actual: <false>` on `heal.converged` or on the set-group count:
  `S-17501 the echo loop adds no set (phone first)`,
  `S-17501 … (wrist first)`, `S-17506 the echo loop survives a phone kill`,
  `S-17506 … a wrist kill`, `S-17507 wrist logs two, phone one`. At HEAD the pair never
  reaches a fixed point, so the heal itself cannot settle — the same stall the 2000-seed
  baseline recorded as the `heal` class.

    .github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_convergence_random_test.dart

- `test/watch_convergence_random_test.dart` — **RED AT HEAD (exit 1)**, 2 failing tests:
  `S-17505 the healed seeds converge` and
  `S-17505 every healed seed’s generated trace converges`, both
  `Expected: true / Actual: <false>`.

## Phase 2 — fix green

Four edits, 35 changed lines in `lib/`:

| Edit | File | Guard proved by |
|---|---|---|
| `PhoneEntries.isPhoneEntryId` (grammar only: `entry-` prefix, non-empty body, `-<digits>` tail) | `lib/core/sync_protocol/phone_entries.dart` | every receiver test below |
| `_isStageable` refuses a phone-minted id (first refusal, nothing receipted) | `lib/state/watch/watch_session_inbox.dart` | S-17502, S-17503 |
| `apply`'s `entries` build drops one a durable row already holds | `lib/core/services/watch_session_importer.dart` | S-17504 (history path) |
| `_mergeHeld`'s `entries` build does the same | `lib/core/services/watch_session_importer.dart` | S-17504 (held merge) |

Post-fix runs (gateway, `--plain-name "plan 175"` unless stated):

- `test/watch_session_import_test.dart` — **5 passed, 0 failed** (S-17502, S-17503,
  S-17504 ×2, S-17511).
- `test/watch_convergence_harness_test.dart` — **5 passed, 0 failed** (S-17501 ×2,
  S-17506 ×2, S-17507).
- `test/watch_convergence_random_test.dart --plain-name "plan 175"` — **2 passed, 0 failed**
  (S-17505 ×2).

Mutation proofs (original line restored after each; the mutant is in the table):

| # | Mutant | Observed |
|---|---|---|
| A | `_mergeHeld` filter forced true (`(true \|\| !isPhoneEntryId)`) | **all 5 unit tests and all 5 harness tests still green** — with the inbox refusal in place no phone-minted id reaches the held merge, and a hand-staged one is absorbed by the merge's own placement rules. The filter is defence for a durable pre-fix row, not the fix's load-bearing line; recorded as A-175-8. |
| B | inbox refusal forced false (`if (false && …)`) | **RED**: S-17502 and S-17503 fail with the exact HEAD assertion messages — the staging refusal is the load-bearing guard for both. |
| C | `apply` filter forced true | **RED**: S-17504 (history path) fails `Expected: null / Actual: <Instance of 'TrainingSession'>` — the import-path filter is load-bearing. |

S-17504's held-merge test and S-17511 pass at HEAD and under all three mutants: the held
slice already absorbs an echo stamp that matches the phone's own row, and refuses an entry
whose slot the phone has no rows for. They are pins on the receiver contract (consumed,
applied and receipted, no resurrection), not the red witnesses — the red witnesses are the
harness and seed tests above.

## Phase 3 — 2000-seed re-measure

All three commands ran through the gateway and stayed inside its 900 s `test` check
(no exit 124, no timeout):

    .github/copilot/scripts/macos/gateway.sh test test/watch_convergence_random_test.dart \
      (default 200 seeds, whole file)                                       — 18 passed, 0 failed
    .github/copilot/scripts/macos/gateway.sh test test/watch_convergence_random_test.dart \
      --plain-name "S-14509 every random seed converges" --dart-define=CONVERGENCE_SEEDS=2000
    .github/copilot/scripts/macos/gateway.sh test test/watch_convergence_random_test.dart \
      --plain-name "S-16310 the phone-kill sweep" --dart-define=CONVERGENCE_SEEDS=2000

| Sweep | Pre-fix | Post-fix |
|---|---|---|
| Contract, 2000 seeds | 19 stalls, heal-only 13 `[209, 270, 316, 899, 1662, 2043, 2380, 2387, 2510, 2669, 3189, 3548, 4098]` | **1949 converge** on every trace; 31 diverge on a shipping trace `[94, 123, 145, 167, 238, 246, 256, 287, 302, 319, 385, 437, 523, 541, 642, 680, 815, 823, 1137, 1142, 1189, 1253, 1285, 1362, 1458, 1496, 1561, 1596, 1754, 1798, 1895]`; **0 heal stalls**; by class `{status: 42, entries: 9}` |
| Kill, 2000 seeds | 19 stalls, heal-only 11 `[352, 565, 209, 270, 2043, 316, 2380, 899, 2387, 2510, 2669]` | **1906 converge**; 76 diverge on a shipping trace; **0 heal stalls**; by class `{status: 54, entries: 5, absorbing: 36}` |
| Contract, 200 seeds | (pre-fix baseline in the section above) | **195 converge** on every trace; 4 diverge `[94, 123, 145, 167]`; 0 heal stalls; 1 diverges only on the harness-only re-assert `[138]` |
| Kill, 200 seeds | (pre-fix baseline in the section above) | **190 converge**; 7 diverge `[46, 60, 105, 113, 127, 145, 153]`; 0 heal stalls; 3 harness-only `[4, 70, 152]`; 95 traces carry a phone kill |

Register and ratchets:

- `knownClasses['heal']` rewritten to the measured 0 (kept: `_kindsOf` can still report the
  kind, and the `knownClasses.keys.toSet() == kKnownKinds` assert must keep passing).
- Both sweeps gained `expect(shippingFlake, isEmpty)` / `expect(phoneKillFlake, isEmpty)`:
  a heal stall is no longer a tolerated flake.
- Ratchets left unchanged, per D-17508: `shippingRatchet` 6/200 (measured 4-5 at 200, 31 at
  2000), `phoneKillRatchetPer200` 10 (measured 7 at 200, 76 at 2000). The 76 of 2000 is
  38/200 — headroom is kept because the phone reads the device clock and a divergence near
  the skew boundary moves between runs (A-146-15). Neither ratchet was raised.

## Phase 4 — Swift pin + corpus

**The `trace-echo` source is added** to `kCorpusSources`
(`test/watch_replay_corpus_test.dart`, after `trace-kills`): steps `phoneStart`,
`advance 3`, `phoneLog`, `wristLog`, `drop`, `rise`, `advance 31`, `wristFinish`,
tags `['entry', 'frame-prefix']`.

**The corpus cannot be re-recorded from this run, and the fix makes five existing
recordings stale.** `gateway.sh test test/watch_replay_corpus_test.dart` after the
source was added — **4 passed, 3 failed**:

- `S-15202` — `the corpus is missing trace-echo.json — regenerate with flutter test
  --dart-define=REPLAY_CORPUS_WRITE=true test/watch_replay_corpus_test.dart`
- `S-15204` — the manifest lists exactly the corpus, in order: expected 18 names,
  actual 17 (no `trace-echo`)
- `S-15207` — `stale recordings: [trace-s14501.json, trace-f7.json, trace-a2.json,
  seed-408.json, seed-857.json, trace-echo.json]` — the same regenerate command

The five stale *existing* recordings are this fix's doing, not pre-existing: the same
file at HEAD is green for the freshness test —

    .github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_replay_corpus_test.dart
    S-15202 … S-15207 the corpus is fresh: every file matches a fresh recording
    00:01 +7 ~1: All tests passed!
    gateway: prove-red: GREEN AT HEAD

(That GREEN AT HEAD is the point here — it establishes the staleness comes from the
change, and this file was used as a diagnostic, not as a proof of my own test.)
Their `expected` summaries still replay correctly (`S-15202` replays every recorded
file), so the recordings encode the bug: each of those five stories ends with the phone
holding an extra set minted from the wrist's echo, which the fix no longer creates.

Recording them needs `REPLAY_CORPUS_WRITE=true`, which this run's policy denies — a
governor action, one command for all six. If the re-record prints
`tags=…,refused-queued` for `trace-echo`, its declared tags need that extra entry
(`_tagsOf` counts a refused frame that is later drained); the run's steps never act
while the link is down, so it should not.

The Swift pin (`testS17510…` in `watch/watchos/Tests/WatchSessionEngineTests/
WatchSessionEngineTests.swift`) was **not** written: that file carries the parallel
plan-173 run's uncommitted diff and the standing rule forbids touching it (A-175-11).
`swift-test` was therefore not run in this pass — no `.swift` file changed under plan 175.

## Phase 5 — residue sweep + final gate

Residue greps (file tools over the repository):

- `isPhoneEntryId` — one definition (`lib/core/sync_protocol/phone_entries.dart:75`), three
  readers (`watch_session_inbox.dart` staging refusal, `watch_session_importer.dart` ×2 for
  `apply` and `_mergeHeld`) and the two docs that name it. No test-only or duplicate
  predicate; no production reader outside those three.
- `originWatch` under `lib/state/watch/` — four hits, all pre-existing:
  `watch_session_inbox.dart` (the wrist snapshot branch of `_stageable`, `_entryFor`'s
  origin) and `watch_session_adoption_bridge.dart` (its doc comment and the claim read).
  No new consumer, and the claim read is unaffected: a phone-minted row is never staged, so
  it can never claim a group.

Doc sizes after the delta:

- `docs/watch_session_capture.md` — planning baseline 40.3 KB, this run adds one Structure
  row and one short Rationale paragraph (about 1.2 KB).
- `docs/watch_session_sync.md` — planning baseline 45.1 KB, this run adds one Structure row
  (about 0.2 KB).
- Both stay well inside the 52 KB split band; `test/docs_indexing_contract_test.dart`
  (64 KiB hard limit) passes in the final full run. Exact byte counts are not measurable
  through the gateway's checks, so the figures above are the planning baseline plus the
  size of the added text.

- `docs/state_management/watch_surface.md` — **no change required**: its three inbox
  passages (the graph composition at `createWatchSync`, "the inbox by entry kind", "the
  inbox is asked first") describe which component claims what, never which entry ids are
  staged. The staged-id rule belongs to the capture doc, updated above.

Final gate:

- `gateway.sh lint` — **181 issues**, equal to the baseline (the two
  `unnecessary_brace_in_string_interps` infos this run had introduced are fixed).
- `gateway.sh test` (full, 900 s) — **`+7661 ~4 -4`**: four failures.
  - three are `test/watch_replay_corpus_test.dart` (`S-15202`, `S-15204`, `S-15207`),
    all three saying "regenerate with `REPLAY_CORPUS_WRITE=true`" — the governor action
    above;
  - one is `test/logger_feedback_controls_test.dart` `S-5115: the rest chip keeps its
    running look on the rolling list view` — **a pre-existing load-sensitive flake, not
    this change**. The same file passes on this working tree (`10 passed, 0 failed`,
    `gateway.sh test test/logger_feedback_controls_test.dart`) and passes at HEAD
    (`prove-red HEAD test test/logger_feedback_controls_test.dart` — `+10: All tests
    passed!`). It is a widget test whose rest chip is gated by the real clock, so it
    fails when the machine is loaded; it also fails when run with `--plain-name` because
    the filter skips the file's shared setup. Not edited (another feature's test).
  - The run before the `trace-echo` source was added was `+7664 ~4 -1`, that one failure
    being `S-15207` for the five stale recordings — so the flake appeared only in the
    later, more loaded run.
- `test/docs_indexing_contract_test.dart`, `test/ui_standards_contract_test.dart` —
  green in both full runs; no doc crossed 64 KiB, no UI source changed.
- Invariant grep — `import .*hive_workout_repository` under `lib/`: only `lib/main.dart`
  (the composition root), nothing in `lib/state`, `lib/features`, `lib/widgets` or
  `lib/core`.


