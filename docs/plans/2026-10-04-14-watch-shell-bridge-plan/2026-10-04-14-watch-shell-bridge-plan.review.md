# Code Review — watch shell bridge (brief-review-1b)

Base: `373c39b2e1ea8f51add01a27c80c9350adff9b5a`
Plan: `2026-10-04-14-watch-shell-bridge-plan.md`
Evidence: `2026-10-04-14-watch-shell-bridge-plan.evidence.md`

Layers in scope: watch package (`watch/watchos/`), watch app target (`ios/OmniTrain Watch App/`),
contract (`watch/contract/`), tests (`test/`, `watch/watchos/Tests/`), docs.
Layers skipped: `lib/` (I-6 — no behaviour change; the only Dart change is a test file),
`lib/state/`, `lib/features/`, `lib/widgets/`, `lib/core/` (no source change).

Governor-run results (taken as given, not re-run): `flutter analyze` 196; `flutter test`
+3881 ~1; `swift test` 261/0; both schemes build.

## Verified and cleared (no finding raised)

- **Wire fidelity — request frames.** `WatchTransportRequest.routinesFrame(since:)`
  (`watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift:52-68`) mirrors
  `WatchTransportRequest.routinesFrame` (`lib/core/platform/watch_transport.dart:72-77`):
  `request` key, `since` omitted rather than nulled, no `type` key. Both suites assert against
  the one contract block (`watch/contract/watch_start_paths_contract.json:245-252`), Swift at
  `WatchConnectivityBridgeTests.swift:163,181,207`, Dart at `test/watch_transport_test.dart:723-760`.
- **I-1 (nothing unsolicited).** No timer, no queue, no retry in the bridge; the host's only
  sender is the Sync button (`ios/OmniTrain Watch App/ContentView.swift:116`), and
  `WatchConnectivityBridgeTests.swift:511` pins it.
- **I-4 / D-12 (refuse whole; a push with no session changes nothing).** The conformance gate
  runs before the no-session guard (`WatchSessionEngine.swift:372-375`), so an unreadable push is
  still a refusal; `applyMessage` reports `current?.recordId != before` (`:413-415`), which is
  `false` with no session. `testS110:582`, `testS108:528`, `testS109:562`.
- **I-3 / D-4 / D-5 (plist safety, no coercion).** `PropertyListFrames` + `testS112:291`,
  `testS113:339`, `testD5:371`.
- **D-8 reachability, three-state.** The re-ask in `OmniTrainWatchConnectivity.onReachabilityChange`
  cannot be lost: it is delivered from a `Task { @MainActor in … }`, which is enqueued and runs
  only after `WatchAppHost.init` has returned and set the bridge's handler
  (`ContentView.swift:59-73`). `activationDidCompleteWith` is the second net.
- **The two closures Phase 3 flagged as runtime-unverified.** Both are sound.
  `OmniTrainWatchConnectivity.deliver`'s `Task { @MainActor in … }` is enqueued, never reentrant,
  so the bridge's handler is assigned before it runs; `ContentView`'s `onIncoming` closure is
  MainActor-isolated under the app target's `-default-isolation=MainActor` and is reached with
  `await` from the bridge, so its `revision += 1` lands on the main actor. Benign note, not a
  finding: the bridge's `inbound` is read on the concurrent executor while the host writes it on
  the main actor — a single pointer load/store, and no worse than the seam's own contract.
- **Start-screen wording and ordering.** Contract labels
  (`watch_start_paths_contract.json:242-245`) match `WatchStartSurfaceCopy`, pinned by
  `testTheContractLabelsMatchWatchStartSurfaceCopy:493`; the unreachable sentence is absent at
  `unknown`, present only after observation (`testS111:458`); picker order is session-slots-first,
  deduplicated, fallback behind (`:608`, `:659`).
- **A1–A7** met. **A8** is an owner step by the plan's own "Verification ownership" note and is
  not claimed by the evidence file.
- **Out-of-scope changes: none.** All 11 tracked and 8 new paths fall inside the phases'
  Predicted Files; no `lib/` source, no `.claude/`, `.github/`, `CLAUDE.md`, no stray scratch
  files (`.work/`, `.build/` are gitignored).
- **Docs name only shipped tests.** All 13 `test/*.dart` files and all 12
  `WatchConnectivityBridgeTests.*` names cited by the changed docs exist.

## Findings

1. **blocker** — `docs/watch-app-setup-and-qa.md:23` — §1's Build-target row (rewritten by this
   change) says "the package link is still an open human step (§3.5)", but the
   `OmniTrain Watch App` target links the product: `ios/Runner.xcodeproj/project.pbxproj:112`
   (the target's Frameworks phase, declared at `:238-243`) carries `WatchSessionEngine in
   Frameworks`, backed by `:13`, `:315`, `:978-991` (`relativePath = ../watch/watchos`), and both
   app-target files `import WatchSessionEngine`. A doc asserting an untrue state of the product.
   **Fix**: delete the clause and point at the build that proves the link.
2. **blocker** — `docs/plans/2026-09-21-13-watch-integration-shipping.md:1169` — the line this
   change *adds* lists "the Swift Package link" among "Remaining human steps", which the same
   evidence as finding 1 contradicts. **Fix**: drop "the Swift Package link" from that list.
3. **blocker** — `docs/watch-app-setup-and-qa.md:158-171` — §3.5 still instructs a human to add
   the package dependency, and its "**One catch**" claims `Package.swift` declares macOS only and
   that a watchOS platform entry "must happen before the watch target will link it". Both are
   false (`watch/watchos/Package.swift:26` declares `.macOS(.v13), .watchOS(.v9)`), and the same
   file marks that entry done at `:54`. **Fix**: delete the section body and the catch paragraph,
   or reduce them to a pointer at the target that already links it.
4. **minor** — `test/watch_transport_test.dart:11,772-786` — the phone-fixture null walk (plan
   Phase 2 item 6) is labelled scenario `S-112`, but the register reserves `S-112` for "the frames
   the wrist sends survive the plist round trip" (plan:244, implemented at
   `WatchConnectivityBridgeTests.swift:291`). One id, two scenarios, two expected outcomes.
   **Fix**: give the Dart group its own label (the plan assigns it none) and correct the mapping
   comment at `:11`.
5. **minor** — `docs/state_management/watch_surface.md:325` — "a push that lands while the picker
   is open appears without the user leaving and re-entering it" is app-target re-render behaviour;
   the two cited tests (`:329-330`) cover row derivation only, and no test covers the re-render.
   The claim is true of the code (`ContentView.swift:118` passes `host.revision`;
   `WatchStartView.swift:177` forwards it to the picker), but the doc's rule is that a behaviour
   sentence names the test that verifies it. **Fix**: point the sentence at the Level 3
   walkthrough step that covers it, or cut it.
6. **minor** — `docs/plans/2026-10-04-14-watch-shell-bridge-plan.md:281-360` — the Phase 1, 2 and
   3 checklists (13 items) are still unticked while `## Progress` (`:452-457`) marks all four
   phases Complete. **Fix**: tick the completed items, or say why they are not ticked.
7. **minor** — `docs/plans/2026-10-04-14-watch-shell-bridge-plan.md:349-353` — Phase 3 item 3 asks
   for a note "in the doc" that the unreachable label moves into the contract if the Wear OS client
   ever ships one; it exists only as a Swift doc comment
   (`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:47-51`). **Fix**: if `docs/`
   was meant, add the one line to `watch_surface.md`.

## Global conventions

`docs/global_conventions.md` — 7 rules.

PASS (3 rules): timestamps are source data (the wrist's frames are stamped from persisted rows and
encoded by the package's own wire encoder, not a local counter); reuse the canonical owner (the
new Swift code reuses the package's `utcIso`/`parseUtcIso` and the shared contract file rather than
restating values, and the bridge conforms to the existing `WatchSyncTransport`); instrument panel,
not influencer (the start surface stays a start surface — no logging chrome, and Phase 4 item 5
kept it that way).

N/A (4 rules): units + canonical storage, theme tokens only, card chrome via `OmniSurface` /
`OmniCardHeader`, effort-kind drives analytics — no `lib/` behaviour, no Flutter UI, no analytics
changed (I-6).

FAIL: none.

## Doc falsification (5c)

Implicated set: all of `docs/` — most documents carry no scope declaration, so they are implicated
by rule. Read in full: `global_conventions.md`, `documentation_standard.md`, `README.md`,
`state_management/watch_surface.md`, `watch-app-setup-and-qa.md`, the two plan files. Spot-checked
against the changed symbols: `data_models.md`, `navigation_and_screens.md`, `modality_tracking.md`,
`db_integration.md`, `widget_catalog.md`, `constants_reference.md`.

DOC FALSIFICATION: ❌ REJECT — `docs/watch-app-setup-and-qa.md:23` — claims the package link is
still an open human step — it is linked (`project.pbxproj:112`) → delete the claim, point at the
build.
DOC FALSIFICATION: ❌ REJECT — `docs/plans/2026-09-21-13-watch-integration-shipping.md:1169` —
lists the Swift Package link as remaining work → delete it from the list.
DOC FALSIFICATION: ❌ REJECT — `docs/watch-app-setup-and-qa.md:158-171` — claims `Package.swift`
declares macOS only and that a watchOS entry must be added before the target can link the package —
`Package.swift:26` declares both platforms and the target links it → delete the section body.
DOC FALSIFICATION: 🟡 WARNING — `docs/state_management/watch_surface.md` — incomplete: the wrist
shell's second surface and the in-memory store are described in `watch-app-setup-and-qa.md` but not
here, where the rest of the wrist surface lives.
DOC FALSIFICATION: 🟡 SCOPE — `docs/state_management/watch_surface.md` — no scope declaration;
verified against the whole change.

## Doc standard (5c-2)

DOC STANDARD: ✅ PASS — no prohibited content added to a guarded document. The new
`watch_surface.md` section adds rules and names real tests, with no hex literal, no control
inventory, no restated numeric and no copied code. The numbered walkthrough added to
`watch-app-setup-and-qa.md` is a flow walkthrough, which is permitted there: that path is in
`_recordFiles` (`test/docs_indexing_contract_test.dart`), so the record-file exemption applies by
design.

## Triage (one round, no re-review)

Fix in this PR, together: findings 1, 2, 3 (delete three false passages) and 4, 6, 7 (mechanical
label/checkbox/one-line fixes). Finding 5 is a one-line edit or deletion, so it rides along.
Nothing here needs a second review round, and nothing is deferred to a follow-up plan — the
unit's remaining scope (durable wrist store, logging surface, the phone-side gaps) is already
listed under the plan's Moved scope.
