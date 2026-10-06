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
