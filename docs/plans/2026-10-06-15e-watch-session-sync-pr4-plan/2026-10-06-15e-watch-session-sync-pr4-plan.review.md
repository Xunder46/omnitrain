# Code review 1 (PR 4a)

Plan: `docs/plans/2026-10-06-15e-watch-session-sync-pr4-plan/2026-10-06-15e-watch-session-sync-pr4-plan.md`
Base: `b353bed` · Scope: Phases 1–3 (PR 4a). PR 4b (G2, G3, F-9, S-48/S-52/S-56) is out of scope.

Layers in scope: Swift package (`watch/watchos`), watch shell (`ios/OmniTrain Watch App`), docs.
Layers skipped: models, persistence (Dart), state (Dart), features (Dart), widgets, core — no Dart source changed.

## Findings

**F1 · major (blocking) · `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift:262-270`
(with `:72-95`, `:303-305`)**
`appendLine` discards every failure — `try?` on `createFile`, `FileHandle(forWritingTo:)`, `write` and
`synchronize` — and returns `Void`, while `appendLocked` then updates the cache and returns the record
with its assigned sequence regardless. An append that never reached the disk is therefore
indistinguishable from a durable one, which contradicts **D-47** ("Every append is durable before it
returns") and **R1**. `ensureDirectory` (`:304`) swallows its failure the same way, so an unwritable
directory yields zero durability with zero signal. Observable consequence: the session keeps logging
and the surface shows its rows; after a force-quit everything logged since the first failed write is
gone. Weighted by **D-51** (the file is never compacted in production and grows one line per record
with no bound), a late-life failed write on a full watch disk is plausible, not academic.
Fix: make `appendLine`/`ensureDirectory` report failure (throwing or `Bool`) and have `appendLocked`
leave the cache untouched and return the record unchanged when the write fails — the same shape the
version-gate path already uses at `:74`.
Guard: a store over a directory it cannot write (or a `Data`-backed failing handle) must return the
record unchanged with sequence 0, and `readAll()` must not contain it.

**F2 · minor · `…/FileWatchSessionStore.swift:160-161`, `:183-184`, `:276-300`**
`compact` returns silently on a failed temp write (`:287-290`) and swallows a failed replace
(`try?` at `:293`, `:297`), while both prune callers set `rows = survivors` unconditionally — so the
cache drops rows the file still holds. Latent today (`pruneConfirmed` / `pruneSensorSamples` have no
production caller, D-51) but not harmless: `nextSequence()` (`:307-309`) is then
`max(survivors) + 1`, which can equal the sequence of a row still on disk, and sequence is what picks
the "newest" row (`WatchSessionEngine.swift:114`, `:1162`) — a duplicate sequence can resurrect a
pruned row over a new one after a relaunch.
Fix: have `compact` report success and leave the cache untouched when it fails.
Guard: prune with the temp write made to fail → `readAll()` still returns the pre-prune rows and the
next append's sequence is unchanged.

**F3 · minor · `…/FileWatchSessionStore.swift:208-216`, `:89-92`**
Only the **first** line is tested for the marker (`:208-216`), and `appendLine` always seeks to the end
— so a non-empty file whose first line is not a marker sets `needsMarker = true` and the marker is
written at the **end** of the file, which leaves `needsMarker` true on the next launch: every launch
that then appends adds one more marker line. No data loss (parsing tolerates the extra line) and
nothing produces such a file today; it matters only because the marker's position is load-bearing for
the version gate (D-45).
Fix: when `needsMarker` is true and the file is non-empty, rewrite it through `compact` (marker first)
instead of appending the marker.
Guard: a rows-without-marker file, launched and appended twice, holds exactly one marker and it is the
first line.

**F4 · minor · `…/FileWatchSessionStore.swift:307-309` vs `…/WatchSessionStore.swift:145`, `:195`**
D-48/AC8 say the two stores answer the same for the same sequence, but they derive it differently: the
file store takes `max(sequence) + 1` over its current rows, the in-memory store increments a counter
that `rows.removeAll` (`:195`) never rewinds. After a prune that drops the highest-sequence row, the
same next append gets different sequences. Relative order is preserved, so no tested behaviour
diverges, and S-54 prunes but never appends afterwards — nothing pins it.
Fix: derive the sequence the same way in both stores (the one-line change is in
`InMemoryWatchSessionStore.append`; D-44 records `max(root) + 1` as the Dart Hive twin's precedent, so
the file store's rule is the one to keep — the point is that it must be one rule, not two), or restate
D-48 as parity of contents rather than of sequences.
Guard: extend S-54 with one append after both prunes, comparing the two stores' returned sequence.

**F5 · minor · `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift:130-131`**
`restore()` still sends `objectWillChange` **before** assigning `prompts` — the order D-54 removed in
`end()`/`confirm()`. Not a bug today: there is no suspension between the two lines and the shell's
consumer defers its read by a `Task`, so no observer can see the gap. It is the same shape this PR
fixed twice, and the next `await` added on that path makes it real.
Fix: move the send after `prompts = owed`.
Guard: none needed now; a `SuspendingStore.readAll` would make the current order red.

**F6 · minor (observation, owner-visible) · `ios/OmniTrain Watch App/ContentView.swift:177`**
`restore()` runs in `.task`, after the first `body` evaluation, so the first frame reads
`engine.session` / `rating.isPromptOwed` while both are still empty: a relaunch with a live session or
an owed question shows the start surface for the length of the file read. Nothing in the plan asks for
a gate, the window is one local file read, and I cannot build the shell (`xcodebuild` is the
governor's step) so I cannot call it a defect — this is a thing for the owner to watch in QA step 17.
If it is visible, the fix is a `restored` flag gating `body`.

**F7 · minor (plan hygiene) · Phase 3 record**
Phase 3 changed two files outside its own `**Predicted Files**` list (`:263`) — the D-50 case in
`WatchFileStoreTests.swift` and the comment edit in `ContentView.swift` — and neither appears in its
steps 1-7, though both are inside PR 4a's `## Files Affected` and the D-50 case is a plan decision.
Paperwork drift, not scope creep.

### Passes worth recording

- The lock is correct: `locked` (`:190`) is synchronous and wraps every public method, so no lock
  spans a suspension point; the async methods are `await`-free shims over `…Locked` helpers.
- The version gate (D-45) is honest: unknown version → `readAll()` empty, `append` returns the record
  unchanged with sequence 0, file byte-identical (S-53 asserts the bytes, not just the count).
- S-004's surface check walks the sources directory itself, so `FileWatchSessionStore` is covered with
  no test edit, and the four-method public surface holds (`init` and the private helpers excluded).
- S-55's cases are non-vacuous under both mutations (a: 3 failures, b: 2) per the evidence file, and
  the `@Published selected` write in `select(3)` cannot mask them because it happens before the
  subscription is installed.
- The D-50 case does say it pins a limit: its name ends `…UntilTheNextSync` and it is filed under
  `// MARK: - D-50 the re-stated set and the relaunch`, and the evidence records that its non-vacuity
  was proven by moving its own expectation (`60` → `65`), which is right for a limit-pinning case.
- S-54's fixture names a row of every family plus both prunes and compares both stores' `readAll()`
  and both prune return arrays; it is the case that catches a prune that keeps the wrong rows. The
  cache-not-refreshed-after-prune and prune-keeps-confirmed-row mutations both turn it red (F2's
  analysis above), even though neither appears in the evidence file's mutation table.
- No dead production caller was left behind: `pruneSettledSensorSamples` still has none, which is what
  makes the docs' "never trimmed" claim true.

## Verification

- `gateway.sh git-diff b353bed --stat` → 10 files, +1594 / -74: the 8 PR 4a files of `## Files
  Affected` (4 Swift sources/tests + the shell) plus this plan's plan and evidence files. No stray
  file, no unrelated file, no formatter-wide rewrite (every hunk is hand-shaped; the only bulk is the
  new 310-line store and the new 677-line test file).
- `gateway.sh test` → **3945 passing / 1 skipped / 0 failing**, exit 0 (log
  `.work/gateway/test-20261006-131944-98641.log`, `01:44 +3945 ~1: All tests passed!`) — the plan's
  baseline exactly, as expected: no Dart file changed.
- `gateway.sh swift-test` → **287 passing / 0 failing**, exit 0 — matches the plan's Progress for
  Phase 3 (286 baseline + the D-50 case).
- Handoff summaries do paste real counts: the evidence file gives 287 / 0 for `swift-test`, 3945 / ~1
  / 0 for `test`, 196 issues / 0 errors for `lint`, plus the red-first and mutation tables. No claim
  of success without counts.
- Acceptance criteria in 4a's scope: AC1 (S-44, S-51), AC2 (S-44, S-46, S-47), AC3 (S-45, S-51),
  AC4 (S-49), AC5 (S-50), AC7 (S-53), AC8 (S-54, modulo F4), AC9 (S-55) — met. AC6's S-48/S-52 and
  AC10's S-48 and AC11's S-56 are PR 4b's; S-48 is explicitly deferred by A-30.
- Scenarios: every 4a scenario (S-44…S-47, S-49…S-51, S-53…S-55) has a passing test asserting its
  stated outcome. Three fixtures deviate from the plan's wording and say so — A-31 (S-45 drives
  `pendingObservations`, one layer below the transport), A-32 (S-44 uses the shared `setEvent`
  payload instead of the plan's 60/60/62.5 kg), A-35 (the store-level S-47 half dropped as
  redundant). A-33's added prune-then-append stage in S-51 is what separates "highest stored
  sequence + 1" from "row count + 1".
- Docs: the three rewritten docs read true against the post-change code, and every test name they
  cite exists and asserts what the prose claims (`testS44…`, `testS45…`, `testS46…`, `testS47…`,
  `testS49…`, `testS53…`, `testS54…`, `testD50…`, both `WatchEffortRatingTests.testS55…`). No live
  doc still says the wrist store is in memory-only, that a force-quit loses the session, or that step
  17 needs a later PR; the plan's three sweeps over `docs/**/*.md` back that, and the one live-doc hit
  (`state_management/nutrition_state.md:198`) is about the nutrition primer's seen-flag.
- `docs/watch-app-setup-and-qa.md` carries **no scope declaration** (it opens with a title and a
  "Companion plan" note), so by the falsification rule it is implicated by every change; it was read
  and its touched rows hold. Recorded as 🟡 SCOPE, not a defect of this PR.
- Impact table: the eight rows' greps still match the tree. One reader class the table does not
  enumerate: `WatchSensorSummaries.swift:142-143`, `:176` and the sequence-order readers
  (`WatchSessionEngine.swift:114`, `:159`, `:179`, `:1162`, `:1321`, `:1454`,
  `WatchStartPaths.swift:292`, `:427`, `:435`, `WatchPhonePreferences.swift:105`,
  `WatchNutritionState.swift:117`, `WatchEffortRating.swift:189`) consume the sequences the store
  assigns. Judged **minor**, not the rubric's "unlisted reader is critical": the primary reader is
  `WatchSessionEngine` itself, and S-44…S-47 guard exactly that surface; what the table omits is which
  row names it, not whether anything covers it. F4 is the sequence-specific half of this gap.

VERDICT: CHANGES_REQUESTED — one bounded round: F1 (with F2, same code path), each with the guard
tests above. F3-F7 are optional and must not extend this PR.

DOC FALSIFICATION: ✅ PASS (3 implicated — `docs/watch_session_sync.md`,
`docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`; the un-scoped remainder of
`docs/` cleared by the plan's three sweeps) 🟡 SCOPE — `docs/watch-app-setup-and-qa.md` has no scope
declaration.
DOC STANDARD: ✅ PASS — no prohibited content added (the added prose points at named test cases; no
walkthroughs, no visual values, no restated numbers).
IMPACT: 8 rows checked, 1 unlisted reader class (sequence-order readers) — minor, see above.
CONVENTIONS/DECISIONS: **PASS (10)** — D-43 (load-once cache and the lock), D-44 (format and line
tolerance; D-44 itself names `max(root)+1` as the Dart twin's precedent, which is F4's mitigation),
D-45 (version gate), D-46 (atomic compaction), D-49 (Dart twin untouched), D-50 (lens memory-only, and
the D-50 case pins it with a stated name), D-51 (pruning unscheduled; the file bound is a stated
follow-up), D-54 (the send lands after the mutation in `end()`/`confirm()`), D-56 (exactly-once
unchanged), D-57 (shell owns the location, package owns the format).
**FAIL (2)** — D-47 — `FileWatchSessionStore.swift:262-270` — a failed write returns as if durable →
see F1; D-48 — `FileWatchSessionStore.swift:307-309` — the two stores derive the sequence differently
→ see F4.
**N/A (7)** — D-52, D-53, D-55 (PR 4b's G2/G3/F-9); the Dart persistence, state, features, widgets
and core layers; the formatter/typecheck rules (no Dart file changed, `flutter analyze` untouched).
Architecture: the store depends on the protocol only, the engine names no concrete store, and no
platform-specific branch entered shared code — PASS.
Dead code: no new unreferenced class; `pruneSettledSensorSamples`'s missing production caller is
pre-existing and is what makes the docs' "never trimmed" claim true — PASS.

---

# Code review 2 (PR 4a fix 1)

Base `fa1c4ff` · reviewed `0077d95` (HEAD) — the round that answers review 1's F1–F3 and records
A-37…A-42. Layers in scope: the Swift package (`watch/watchos`) and `docs/`. Skipped: the Dart
models, persistence, state, features, widgets and core layers — no Dart file changed.

## Answers to the brief's five questions

1. **F1 — fixed.** No cache mutation survives a failed write. `appendLocked` reaches
   `rows?.append`/`fileHasContent` only through `guard prepareFile(), appendLine(line)`
   (`FileWatchSessionStore.swift:97-99`) and still hands the caller `stored`; both prunes reach
   `rows = survivors` only through `guard compact(survivors)` (`:165-166`, `:188-189`); `loadRows`'
   `rows = resolved` *is* the load. `compact` returns false before it clears `tornTail`,
   `needsMarker` or `fileHasContent`, and `ensureDirectory` reports its failure. Sequence: the
   counter is instance state (`:53`) that only ever rises, seeded once from the file's own maximum
   when the rows are loaded (`:233`) and incremented per call (`:340-343`); no load, append, prune or
   compact path rewinds it, so a refused append burns its number and nothing reuses it.
   A-41's residual is real and harmless: a refused append consumes a number that a *relaunch*
   recomputes away — the refused row is in neither the cache nor the file, so no two live rows can
   collide.
2. **F2 — fixed in both prunes; one gap.** Both prunes guard `compact` and return `[]` before
   touching the cache, and a failed `compact` leaves the file untouched: the function returns at
   the directory step, at the temp write, or at the replace, always before the bookkeeping.
   Temp file: it is removed (`try?`, best effort) **only** on the replace-failure path (`:331`); the
   temp-*write* failure path returns without attempting cleanup, so a partial
   `watch-session.jsonl.tmp` can be left behind — harmless (the next compact truncates it) and
   untested — G2.
3. **F3 — fixed.** `prepareFile` (`:277-292`) compacts when `tornTail || (needsMarker &&
   fileHasContent)`, so a marker-less file and a torn-tail file are each rewritten marker-first once;
   the marker is appended only to an empty file, and a file whose first line carries the expected
   marker takes the plain-append path. An unknown version returns at `:79` before `prepareFile`, so
   the file is left byte-identical. Nothing visible is lost: `compact` writes exactly `loadRows()`,
   so it can only drop lines that already fail `parseLine` — the torn fragment is the record that
   never landed. No recursion (the compact path is a leaf) and no path is skipped. One positional
   limit: a marker naming an unknown version that is *not* the first line is treated as marker-less
   rows, so it is dropped and the file rewritten as v1 — G4.
4. **The three guards assert their claims, and they are not vacuous on this host.** `testF1…`
   asserts the refused row is absent from `readAll`, that the on-disk rows are unchanged, and that
   the refused row still carries a *fresh* sequence while the next successful append carries a
   higher one — the assertion pair that makes reuse impossible to reintroduce silently. `testF2…`
   asserts the empty return, the cache unchanged and the file byte-unchanged, then a successful
   prune that really does drop. `testF3…` asserts marker-first, exactly one marker and all four rows
   in order. Each F1/F2 case **asserts its own unwritability precondition** before using it (the
   handle throws / a probe write throws) and restores attributes in a teardown block; those
   preconditions passed in my own green run, which is what makes the technique non-vacuous here —
   on a host that could write anyway, the probe assertion fails first, so a green run cannot be the
   vacuous outcome. `testF3…` uses no permission trick at all. The only gap in the F2 technique is
   its reach: it is applied to `pruneConfirmed` and not to `pruneSensorSamples` — G1.
5. **The new doc sentence is true of the code and its cited test.** `docs/watch_session_sync.md:245-252`
   matches the code: the store returns the row it refused, so the engine still holds it in the list
   the surface reads, and that list is what `pendingObservations()` emits at the next Sync — while
   the store's `readAll()` will not return it. Hence "still visible and still sent … lost if the app
   is killed before the next Sync" is exact, and `testF1…` asserts both halves. No other sentence
   was made false by the fix: "the wrist's record file is never trimmed — nothing is ever deleted"
   is about production pruning (D-51) and stays true, since a dropped torn fragment is not a record
   and the fix adds no caller.

## Findings

**G1 · warning (test gap) · `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift:188`
(vs `WatchFileStoreTests.swift:702`)**
`pruneSensorSamples`'s failed-compact branch is the same line as `pruneConfirmed`'s but no test
guards it, so a re-introduced defect there would be caught by nothing while the confirmed path stays
red.
Fix: drive the F2 case over both prunes (parameterise, or add the sensor twin). **Not blocking** —
route it with PR 4b's prune work, where S-48 extends every prune case anyway. → @developer

**G2 · suggestion · `…/FileWatchSessionStore.swift:326-331`**
A failed temp write returns without removing a possibly partial `.tmp`, and the replace-failure
cleanup is best-effort `try?`, so a stale temp can outlive the failure; nothing asserts its absence.
Fix: `try?` remove the temp on the write-failure path too, and assert no `.tmp` remains in the F2
case. → @developer

**G3 · warning (plan ledger) · plan `D-47` and `D-51`**
Two decisions now describe code that does not exist: D-47 ("Every append is durable before it
returns … that one write is the only file I/O an append does") is false for a refused append and for
the torn/marker-less path, which rewrites the whole file in `prepareFile`; D-51's "the file is never
compacted in production" is false for that same path. A-41 records the override but the decisions
were not amended, so a later phase reads a contract the code does not implement.
Fix: amend D-47/D-51, or add the one superseding decision the ratification of A-41 asks for. → planner

**G4 · suggestion · `…/FileWatchSessionStore.swift:212-232`**
The version gate is positional — only line 1 is read as a marker — so a marker naming an unknown
version anywhere else is ignored, its line dropped and the file rewritten as v1, which is the one
shape where R6's "left alone, not overwritten" does not hold. Only a pre-fix build's own output
(F3's bug) or a hand-made file can produce it.
Fix: state the limit in D-45, or scan parsed lines for an unknown marker before writing. → planner

## Verification

- `gateway.sh test` → **3945 passing / 1 skipped / 0 failing**, exit 0
  (`test-20261006-133943-14855.log`: `01:41 +3945 ~1: All tests passed!`) — the plan's baseline to
  the case; the fix touches no Dart file.
- `gateway.sh swift-test` → **290 passing / 0 failing**, exit 0
  (`swift-test-20261006-133943-14861.log`) — 287 baseline + the three guards, and the F1/F2
  unwritability preconditions pass on this host, so neither guard is vacuous here.
- Red-first and mutation evidence is in the evidence file §Fix 1 (three cases red before the fix;
  each red under its own mutation; restored green after each). Mutation (d) — reverting `nextSequence`
  to a max-of-rows rule — going red on the *ordering* assertion is the direct proof that the
  monotonic counter is what prevents reuse.
- The sequence rule change is safe for every reader: all twelve consumers only order
  (`max`/`min`/`sorted`/`>=`/`>`) and none assumes contiguity or uses the value as an index
  (`WatchSessionEngine.swift:114,159,179,1162,1321,1454`, `WatchStartPaths.swift:292,427,435`,
  `WatchPhonePreferences.swift:105`, `WatchNutritionState.swift:117`, `WatchEffortRating.swift:189`,
  `WatchSensorSummaries.swift:142-143,176`). F4/AC8 now holds: both stores use one monotonic counter
  that neither rewinds.
- Acceptance criteria re-checked for the touched behaviour: AC1–AC5 (S-44…S-47, S-49…S-51), AC7
  (S-53) and AC8 (S-54) still met; AC6's S-48/S-52 and AC11's S-56 stay PR 4b's (A-30).
- Diff vs Predicted Files: conforms for this round — one source file, one test file, the plan, the
  evidence and the three docs. F7 (the Phase-3 paperwork drift) is untouched and remains the PR's
  only deviation.

DOC FALSIFICATION: ✅ PASS (3 implicated docs changed — `docs/watch_session_sync.md` (new sentence
true of the code and of `testF1…`), `docs/state_management/watch_surface.md` (store paragraph and its
test pointers still true; no durability claim about a refused append), `docs/watch-app-setup-and-qa.md`;
no other `docs/` file claims a failed append is durable)
DOC STANDARD: ✅ PASS — the added sentence names its test and adds no walkthrough, value or code
DECISIONS: **PASS (12)** — D-43, D-44, D-45 (positional limit noted, G4), D-46, D-47 as implemented
(ledger text stale, G3), D-48 (one rule now), D-49, D-50, D-51 (pruning still unscheduled), D-54,
D-56, D-57. **N/A (7)** — the remainder, as review 1.
IMPACT: **PASS** — the fix's one cross-cutting effect is the sequence rule; its reader class was
re-grepped (twelve files, all order-only, no unlisted reader) and the store's own S-44…S-54 cases pass.
Assumption Log: **RATIFY** A-40 (the unwritability technique is real here), **RATIFY** A-41 — and
**promote it to a numbered decision**, since the doc sentence now depends on the returned row keeping
its sequence and D-47's text must be superseded; **RATIFY** A-42 (F1 only; the prunes still have no
production caller).

Critical: 0 | Warnings: 2 | Suggestions: 2
→ G1 with PR 4b's prune cases, G3 to the planner's ledger; G2 and G4 optional.

VERDICT: APPROVE
