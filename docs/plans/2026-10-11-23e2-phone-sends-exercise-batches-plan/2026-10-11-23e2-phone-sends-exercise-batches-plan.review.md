# Review: 2026-10-11-23e2 phone-sends-exercise-batches · P0–P2 · 35b31729..working tree (+ untracked test/watch_sync_request_handler_test.dart)
Verdict: CHANGES_REQUESTED
Counts: blocker 1 · major 0 · minor 3 · tests: governor-run full `flutter test` `+4294 ~1: All tests passed!` (1 pre-existing skip), `flutter analyze` 196 (baseline), `swift test` 550/0 — not re-run per brief
Diff vs Predicted Files: conforms for P0–P2 (10 files, all in the plan's phase scopes; the untracked handler test is the plan's new file). Missing: every P3/D-3835 docs file — no `docs/**` file is in the diff.

## Findings

1. [Blocker] docs/state_management/watch_reference_data.md:158–167 (also docs/state_management/watch_surface.md:278–285 and :299–301, and docs/watch-app-setup-and-qa.md:733–736) — D-3835 / phase P3 was never executed: no docs file is in the diff, and three pages now state falsehoods a maintainer or owner would act on. `watch_reference_data.md` still says "The phone still sends the whole list in `routines_down.fallbackExercises`" and carries a "Not yet changed (23e2)" section asserting the sender is untouched — both false after D-3830. `watch_surface.md:278` still says "`buildRoutinesDown` returns **null** only when…" and "`fallbackExercises` is the phone's whole catalog", and :299 still justifies `preferences_down` being "its own message … because `buildRoutinesDown` answers null" — the null return no longer exists. `watch-app-setup-and-qa.md:733` still says the Add list "is the phone's whole exercise list, so it only reaches the wrist at **Sync** … (D-3601)" and lacks the owner step the plan orders (Sync → Add Exercise; Sync again → nothing resent; add a custom exercise → Sync → it appears). Fix: run P3 as written (D-3835), rewriting each sentence to the present tense and adding the QA step. Guard: the D-3835 review item itself; no doc test exists.

2. [Minor] lib/state/watch/watch_sync_request_handler.dart:112 — when the phone's capable list is empty (`batches.isEmpty`), the handler sends preferences and `routines_down` and returns: a wrist already holding a list is never told the catalog became empty, so after the user deletes every exercise on the phone the watch's Add Exercise keeps offering all of them indefinitely (until any exercise is added). The plan ratifies this (D-3831 "empty list returns `[]`"; the schema's `exercises` minItems 1 cannot express an empty list), so it is not a defect against the plan — but the decision is unpinned at the handler level. Fix: none in code this round; add a handler test (phone with no capable exercise → `['preferences_down','routines_down']`, no batch) next to S-3850 so the ratified behaviour is deliberate. Guard: that test in `test/watch_sync_request_handler_test.dart`.

3. [Minor] test/watch_reference_sync_test.dart:510 — S-3843's name-order assertion is `orderedEquals([...names]..sort())`: Dart's default code-unit sort, which agrees with `compareFoodNames` (lowercase `compareTo`) only because the generated names `Exercise 000…249` are case-uniform ASCII. A regression to a case-sensitive comparator would pass this test. Fix: sort the expectation with `compareFoodNames`, or add one lowercase/uppercase pair to the 250 generated names. Guard: S-3843 with mixed-case names.

4. [Minor] test/watch_reference_sync_test.dart:441–520 — the 23c guard S-3607 ("the seeded catalog fits well under the frame budget", measured over the real 252-exercise seeded catalog with real names) was deleted with its group and replaced by S-3843, which measures synthetic short names (~8 KB per 100). The real-catalog batch size (~111 B/exercise by the plan's own 28 KB figure → ~11 KB per 100-batch, still under 16,000) is now unpinned; a future field added to `catalogExercise` could push real batches over the frame budget with every synthetic test green. Fix: in an existing seeded-catalog test (e.g. the S-3851 handler test or a reference-sync test over the default seed), print and assert the first batch's encoded size < 16,000. Guard: that size assert.

## Checked, no finding

- **End-to-end against the committed wrist (23e1 D-3815/D-3816/D-3823).** `generatedAt` is `_clock()` once per `handle` and stamps every batch of that Sync (`watch_sync_request_handler.dart:100–119`). Two overlapping Syncs of unchanged content produce the same `catalogVersion` with different `generatedAt`: same-version rows share the idempotent recordId `exb-<version>-<index>`, complete once (D-3823's post-append read), and the second completion is a no-op ("not already the active version"). Two Syncs with different content resolve by D-3815 rule 2: whichever version completes, the other's later batches carry an earlier `generatedAt` and are dropped, so the wrist ends on the newer list; a lost batch leaves that version incomplete and the wrist on its previous list, and the next Sync (wrist still reporting the old version or none) resends everything. Phone clock set backwards is the 23e1-review-ratified consequence of rule 2, not new here.
- **List changing between a Sync's `routines_down` and its batches.** The two builds are separate awaits, so a concurrent edit can make the fallback list and the batch list disagree — but the wrist unions `routines_down.fallbackExercises` into `syncedFallback` (D-3817), so a routine's exercise is covered either way, and the next Sync carries the new version. No hole.
- **Batches built once per Sync.** `buildExercisesDown` encodes the list and derives the version before any send (`watch_reference_sync.dart:226–244`), so one Sync's batches are one consistent version. Confirmed in code.
- **Version determinism.** Order is `_catalogOrder` (`compareFoodNames` = lowercase code-unit `compareTo`, ties by id — locale-independent); capabilities travel in the order stored by `setExerciseCapabilities` (Hive box list, stable across Syncs; an edit is a genuine content change). Same content → same version every Sync, so the skip holds. Canonical-text ambiguity from a name containing `|` or `\n` does not matter: exercise ids are app-generated and never contain either delimiter, and nothing parses the canonical text back — a collision would need two exercises whose id/name pairs trade the delimiter.
- **Web safety.** `h*65599` peaks at ~2^48, `h*33` at ~2^37 — both below 2^53 (`watch_reference_sync.dart:262–266`).
- **Resolver cost.** `buildExercisesDown` does 1 `getExercises` + N `getExerciseCapabilities` per Sync; the deleted 23c loop inside `buildRoutinesDown` did exactly the same work before, so nothing is new per Sync. Referenced exercises are now resolved twice per Sync (once per build) — same order of cost.
- **`routines: []` + `fallbackExercises: []` readers.** Swift `applyRoutinesDown` accepts it (fixture `routines_down_empty.json` since 23e1; S-3840 walks the Dart wrist `WatchRoutinesDown.fromEnvelope`). The Wear client (`lib/watch/start/watch_sync_orchestrator.dart:162` `default: return false`) ignores `exercises_down` and its `requestRoutines({since})` names no version, so it is sent the full batch list every Sync and offers only the routines' exercises — acceptance 6 / D-3805, divergence documented in the series plan (`docs/plans/2026-10-11-23e-watch-batched-exercise-list-series.md:41`). `lib/watch/session/watch_records.dart:701` reads a missing `fallbackExercises` as `const []`.
- **Frame twin and contract.** Dart `routinesFrame`/`exercisesVersionOf` (`watch_transport.dart:73–97`) and Swift S-3820 both read the one contract entry `routinesExercises`; S-3856 and S-3820 compare against it, never retyped. The Wear interface is untouched (D-3833).
- **Send order and stop rule.** preferences → `routines_down` → batches in index order, break on the first `WatchDelivery.undelivered` (`watch_sync_request_handler.dart:117–119`). `undelivered` covers both an unreachable wrist and a refused frame by D-196's definition; the wrist sees nothing either way and keeps its list — one behaviour, correctly one branch.
- **Replaced 23c group S-3604..S-3607.** S-3604/S-3605 (whole catalog in the fallback list) are superseded by design (D-3830) and their replacement coverage is S-3840/S-3841 + the batches tests; S-3606 (no exercises → null) is replaced by S-3842/S-3845; S-3607's budget check is finding 4. No behaviour that still matters was dropped silently.
- **Stale comments in code.** None found: the handler's and builder's doc comments were rewritten in the diff; the two stale reason strings P1 flagged in `test/watch_transport_test.dart` were rewritten by P2.
- **Mutations.** `mutate.py` lists 10 (F1–F10) matching the plan's verification list; the brief states all red on the named scenario. F1→S-3840/S-3841, F2/F3→S-3844, F4→S-3843, F5→S-3850/51/52, F6→S-3853, F7→S-3855, F8/F9→S-3856, F10→S-3851 — each named scenario has the test I read.

## Assumption Log rulings

The plan carries no Assumption Log section; the builder reports raise open questions. Rulings:

- P1: "D-3832 vectors not independently recomputed" — **ratified**. The constant `v1-2-004dbda823a1b308` is pinned identically in three places (S-3844, the contract entry, and S-3856/S-3820 which read the contract), and the version is opaque to the wrist: a wrong vector would be a consistently wrong constant no behaviour depends on. (Reviewer's own recomputation was attempted and denied by the permission rule — see Open questions.)
- P1: "`_sendRoutines` doc stale, left for P2" — **ratified**: P2's diff replaces it.
- P2: "S-3850's expected version derived by the same function the handler calls" — **ratified**: the skip logic, not the version function, is that test's subject; S-3844 and S-3856 pin the version itself.
- P2: "S-003/S-253 expectations changed beyond the brief's named tests" — **ratified**: the plan's phase table assigns `test/watch_transport_test.dart` to P2, and the changes are the direct consequence of D-3830/D-3834 (batches now follow the routines); each rewritten expectation still asserts something that can fail.
- P0: "contract `description` edit (three → four frames) not asked for" — **ratified**: the fourth entry made the old sentence false; no test reads the description.

## Scenario coverage

| S-n | Test |
|---|---|
| S-3840 | test/watch_reference_sync_test.dart · `S-3840 no templates: a message with both lists empty` |
| S-3841 | test/watch_reference_sync_test.dart · `S-3841 the fallback list is the exercises the routines use` |
| S-3842 | test/watch_reference_sync_test.dart · `S-3842 a phone with no exercises at all still answers` |
| S-3843 | test/watch_reference_sync_test.dart · `S-3843 250 exercises arrive as three batches in name order` |
| S-3844 | test/watch_reference_sync_test.dart · `S-3844 the vector, over the wire objects themselves` / `…through the batches it builds` / `…another insertion order is one version` / `…a name, a capability, a period length or a removal is another version` |
| S-3845 | test/watch_reference_sync_test.dart · `S-3845 no capable exercise is no batch at all` |
| S-3846 | test/watch_reference_sync_test.dart · `S-3846 a batch size outside 1..100 is refused` |
| S-3850 | test/watch_sync_request_handler_test.dart · `S-3850 the wrist names the current version: no batch travels` |
| S-3851 | test/watch_sync_request_handler_test.dart · `S-3851 with no version the phone sends the whole list, in index order` |
| S-3852 | test/watch_sync_request_handler_test.dart · `S-3852 a version the phone no longer holds sends the whole list` |
| S-3853 | test/watch_sync_request_handler_test.dart · `S-3853 a batch the radio refuses stops the rest, and the answer still holds` |
| S-3854 | test/watch_sync_request_handler_test.dart · `S-3854 a sync with the sent version sends no batch, and a custom exercise stales it` |
| S-3855 | test/watch_session_projection_test.dart · `S-3855 a request naming the current version sends no exercise batch` / `S-3855 a request naming no version sends the whole exercise list` |
| S-3856 | test/watch_transport_test.dart · `S-3856 a wrist that holds a list names its version the way the contract does` / `S-3856 a request with no version holds no version key` / `S-3856 the version a frame names is read back…` (+ Swift `testS3820…` over the same contract entry) |

No scenario is MISSING a test. All scenarios have a test that would fail without the change (each is the red target of a listed mutation, or — for the builder-level S-3840..S-3846 — fails to compile/behave without D-3830..D-3832).


## Governor ruling (after the round)
- Finding 1 (Blocker): void. The reviewer ran in parallel with the docs keeper (phase P3); the docs were written by the time the round ended (see report-docs.md; the three named pages were rewritten and the QA step added). Verified by grep for the stale sentences.
- Findings 2, 3, 4 (Minor): accepted; fixed in one closed round (tests only): the empty-catalog handler test, mixed-case names in S-3843 with the expectation sorted by compareFoodNames, and a size assertion over the real seeded catalog.
