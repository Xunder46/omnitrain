# Feature: 85 — swiping between exercises on the wrist slides the next exercise in, with no name card in between

> Status: BUILT AND PROVED 2026-10-26 (uncommitted). Four mutations (drop `withAnimation`, removal not `.identity`, edge written after the animation, slide seconds 0) each turned their guards red. The look and feel is an owner device check; the owner declined the simulator look. Earlier status: SEEDED 2026-10-26 (lead), architect done 2026-10-26 (line numbers verified and corrected, phases expanded, notes in `.work/crew/2026-10-26-85/architect-notes.md`). Base commit: `.work/2026-10-26-85/base.txt`. Team: the crew. Owner request (chat, 2026-10-26): "Add a UI change for the swipe, can it be animated/visible on swipe but without the middle screen that I removed in the previous iteration?" Builds on plan 79 (instant switch, no name card; its Assumption Log said a slide would be "a transition on the `.id`'d logger, not a second page"). Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md. Package targets watchOS 9.

## What the owner sees

| Moment | Today (plan 79) | After |
|---|---|---|
| Swipe left on a session with several exercises | the next exercise's logger replaces the current one at once, light tap | same tap; the next exercise's logger slides in from the right edge in about a fifth of a second. Nothing but the two loggers is ever drawn: no name card, no blank page in between |
| Swipe right | previous exercise replaces at once | the previous exercise slides in from the left edge |
| First exercise + swipe right, last + swipe left | nothing moves | nothing moves (no bounce) |
| The phone moves the wrist to another exercise, or a menu jump | switches at once | unchanged: only the user's own swipe animates |
| Swipe while an effort clock runs | failure tap, notice "An effort is running" | unchanged |
| Settings, Accessibility, Reduce Motion on | n/a | a quick fade instead of a slide |

Deliberate limit: the exercise being left disappears at once and the new one slides in (the leaving page is not dragged out). Reason: the leaving logger reads the live session, so a half-drawn departure would already show the NEW exercise's numbers. Dragging both pages with the finger would need two pinned copies of the logger and is a separate, larger change; ask the owner after seeing this one.

(owner) On a real watch, session with three exercises: (a) swipe left, right, left, right: the slide is visible and quick, no card; (b) at the ends nothing moves; (c) log a set right after a swipe: the set lands on the exercise shown.

## Decision Ledger

- D-1 `WatchLoggingPagerView.paged` (`WatchLoggingPagerView.swift:71-90`): wrap the logger in a `ZStack` so the `.id(...)` change is an insertion/removal inside a container. The logger keeps `.id(pager.rows.indices.contains(selection) ? pager.rows[selection].slotId : "")` and gets `.transition(.asymmetric(insertion: <D-2>, removal: .identity))`. The `.simultaneousGesture(DragGesture(minimumDistance: 24)…)` and `.onChange(of: selection)` move from the logger to the `ZStack` (they must not live on a view that is being replaced).
- D-2 Insertion: `.move(edge: slideFromTrailing ? .trailing : .leading).combined(with: .opacity)`, where `@State private var slideFromTrailing = true` is written in the gesture's `onEnded` BEFORE the animated change: `slideFromTrailing = across < 0` (finger moved left = next = slides in from the right, the direction rule of plan 79 D-3 is unchanged). With Reduce Motion (`@Environment(\.accessibilityReduceMotion)`), insertion is `.opacity` only.
- D-3 The change is animated only for a user swipe: in `onEnded` the existing `selection = target` becomes `withAnimation(WatchPagerCopy.slideAnimation) { selection = target }`, still AFTER `state.focusSlotId = pager.focusSlotId(for: target)` (plan 52 D-5: the focus names the page before the engine moves). `followEngine()` (`:150-155`) and `land(on:)` (`:120-146`) assign `selection` with no animation, so a phone push never slides. `WatchPagerCopy` (`WatchPagerModel.swift:24-27`) gains `slideSeconds: TimeInterval = 0.2` and `static var slideAnimation: Animation { .easeOut(duration: slideSeconds) }` (Animation needs SwiftUI: put `slideAnimation` in the view file as a private constant built from `WatchPagerCopy.slideSeconds`, keep the number in the model file so it is testable on macOS).
- D-4 `.clipped()` on the `ZStack` so the entering page cannot draw outside the screen frame.
- D-5 Rejected, recorded: a two-sided slide (`removal: .move(...)`) because the departing page re-renders with the new focus (D-3 of this plan, plan 52) and would show the new exercise while leaving; to be decided with the owner after seeing this slide.
- D-6 Unchanged: haptic `.click` on a swipe that moves, `WatchPagerModel`, the locked page (`single`, `:94-118`), tile/Crown state rebuilt per exercise (plan 79 D-5), the counter text, the phone, the protocol, Dart.

## Scenarios (exact fixtures; re-derive in the first run)

- S-15401 `WatchPagerCopy.slideSeconds == 0.2` and is `> 0` and `< WatchPagerCopy.noticeSeconds` (a slide is shorter than the locked notice). Fails today: no such constant.
- S-15402 source guard `WatchLoggingPagerView.swift` (comments stripped, exact statements): `ZStack {` encloses the `WatchLoggingView(` of `paged`; the logger has `.transition(.asymmetric(insertion:` and `removal: .identity)`; contains `slideFromTrailing = across < 0` BEFORE `withAnimation(` in the gesture closure; `withAnimation(` encloses exactly `selection = target`; `state.focusSlotId = pager.focusSlotId(for: target)` precedes that `withAnimation`; contains `accessibilityReduceMotion`; contains `.clipped()`.
- S-15403 source guard: `followEngine` and `land` contain no `withAnimation` (a phone push never slides): assert `withAnimation(` occurs exactly once in the file.
- S-15404 existing guards stay green: S-9111 (no `TabView`, no `WatchExercisePreviewPage`, no `.tabViewStyle`, `DragGesture(minimumDistance: 24)` at least twice, `pager.neighbourIndex(of: selection, towardsNext:`, `state.focusSlotId = pager.focusSlotId(for: target)`, `selection = target`, `.onChange(of: selection)`, `play(.click)`, still no `digitalCrownRotation` / `.focusable`). `selection = target` now sits inside `withAnimation { }`: the guard (`WatchPagerSourceTests`, `WatchPagerFocusTests` S-7913 "focus before selection") is updated in the SAME run to the new text, meaning unchanged except for the wrapper; S-6610, S-6612, S-7911, S-7912, S-7914..S-7916 unchanged.
- S-15405 `WatchPagerModel.neighbourIndex` S-9110 unchanged and green.
- S-15406 (lead, not a builder) on the watch simulator, if the Mac is unlocked and the owner agrees: seed `watch-session.jsonl` with three exercises (the trick in the memory note "Watch UX audit 2026-10-20"), swipe with computer-use; otherwise an owner check, stated.

Readers: `WatchPagerSourceTests.swift` (S-6611, S-9111, S-6612), `WatchPagerFocusTests.swift` (S-7913, S-7916), `WatchPagerModelTests.swift` (S-6601..S-6608, S-9110 — behaviour only, reads no file text), `docs/state_management/watch_surface_wrist.md` (pager paragraph `:755-789` describes the switch, no animation word), `docs/watch-app-setup-and-qa.md` (QA steps 1-28; NO pager step exists — plan 79's promised step was never added; P3 adds one). `WatchFollowPhoneEffortTests.swift` mentions the pager only in a comment (`:499`) and reads no file text.

## Answers with evidence (architect, 2026-10-26)

**(a) Which tests read the file's text, and what the new text does to them.** Grep `WatchLoggingPagerView` under `watch/watchos/Tests`: three files. `WatchFollowPhoneEffortTests.swift` mentions it only in a doc comment (`:499`) and reads no file text — unaffected. The two file-text readers:

- `WatchPagerSourceTests.swift` — S-6610 reads `ios/OmniTrain Watch App/ContentView.swift` and asserts `WatchLoggingPagerView(` is mounted (`ContentView.swift:537`); the view file is untouched there, green. S-6611 (`testS6611ThePagerIsOneLoggerWithASwipe`, `:79-101`): no `TabView(`, no `.tabViewStyle`, `DragGesture(minimumDistance: 24)` exactly 2, `let across = abs(value.translation.width)` present — all hold against the new text (the two drags are the new ZStack gesture and `single`'s locked drag). No edit. S-9111 (`:103-160`): 12 assertions over the comment-stripped source; every literal survives (`selection = target` is a substring of the wrapped statement; the DragGesture count stays 2; focus still precedes selection). Per S-15404 the `selection = target` assertion is updated in the same run to the wrapped literal `withAnimation(Self.slideAnimation) { selection = target }` — a strengthening, not a fix. S-6612 (no `digitalCrownRotation`/`.focusable`) holds.
- `WatchPagerFocusTests.swift` — S-7913 (`testS7913ThePagerViewWiresTheFocusThroughTheSwipe`, `:327-368`): focus range before selection range; `state.focusSlotId = nil` ≥ 2 (4 in the new text); `pageLabel:` literal; no `TabView(`/`selectionBinding`/`if index == selection`. All hold; the `selection = target` range is updated to the wrapped literal (S-15404). S-7916 parses the `land`/`followEngine` bodies (end marker `\n    }\n`) — both bodies untouched, green.

So: **no existing assertion breaks**; two assertions are strengthened to pin the wrapper (S-15407).

**(b) Where tests find the comment-stripping helper.** There is no shared helper: `strippingCommentLines(_:)` is a private copy in ~23 test files (`WatchPagerSourceTests.swift:54`, `WatchPagerFocusTests.swift:325`, …). The only shared pieces are `Fixtures.repositoryRoot` (`Tests/WatchSessionEngineTests/Fixtures.swift:17`, `#filePath` minus 5 components) and `Fixtures.sourcesRoot` (`:28`). The new `WatchPagerSlideSourceTests.swift` copies the private helpers (`engineSource`, `strippingCommentLines(_:)`, `propertyBody(named:in:)`, `occurrences(of:in:)`) from `WatchPagerSourceTests.swift:36-77` — the established pattern.

**(c) Is "the leaving page re-renders with the new focus" supported by code?** Yes, with a precise mechanism. `WatchLoggingState` is a plain class (`WatchLoggingState.swift:166`), not observable; `focusSlotId` (`:604`) is a plain stored var; `slot` (`:608-617`) reads it live on every access, and `exerciseName` (`:275`), `setCaption` (`:284`), `fields` (`:558`) all compute from `slot`. The mounted logger's `WatchLoggingModel` is an `ObservableObject` (`WatchLoggingModel.swift:19`) whose `poll()` sends `objectWillChange` (`:100-104`) and whose `start()` schedules a repeating 1 s `Timer` (`Self.tick = 1`, `:86-90`); `poll()` also runs on `turn`, `adjust`, `stepArmed`, `startWork`, `primaryAction`, `log`. So the focus write itself publishes nothing, but the leaving logger re-renders on its model's next publish (≤1 s away) and then reads the CURRENT `focusSlotId` through `slot` — inside any animated removal window it would show the new exercise's name and rows. `land(on:)`'s async completion also writes `state.focusSlotId = nil` (`:139`, `:142`), which would repaint a still-removing page to the engine's (new) exercise. Hence `removal: .identity` in both Reduce Motion states: the leaving page is discarded before any publish can repaint it.

## Feature invariants

- Only the user's own swipe animates: `withAnimation` appears exactly once in `WatchLoggingPagerView.swift`, in the swipe's `onEnded` (D-3, S-15403).
- The focus names the page before the engine moves: `state.focusSlotId = pager.focusSlotId(for: target)` precedes the animated `selection = target` (plan 52 D-5, S-15402).
- The leaving logger is never repainted: removal is `.identity` in both Reduce Motion states (D-5, S-15402, S-15408).
- The gesture and the `.onChange` live on the `ZStack`, never on the replaced logger (D-1, S-15402).
- The slide number lives in `WatchPagerCopy` so macOS tests can hold it; the `Animation` itself is built in the view file (D-3, D-7, S-15401).

## Existing-functionality impact

| Touched surface | What already reads it (search run this run) | Effect | Guarded by |
|---|---|---|---|
| `WatchLoggingPagerView.paged` | `WatchPagerSourceTests` S-6611/S-9111/S-6612, `WatchPagerFocusTests` S-7913/S-7916 (file-text readers); `ContentView.swift:537` mounts the view (S-6610 reads that file) | new text keeps every literal; two assertions strengthened to the wrapped literal | S-15402, S-15403, S-15404, S-15407 |
| `WatchPagerCopy` | `WatchPagerModel.swift:81`, `WatchLoggingPagerView.swift:104,111`, `WatchPagerModelTests.swift:330,334` (grep this run) | additive constant; no existing member changes | S-15401 |
| `single`, `land(on:)`, `followEngine()` | S-7916 parses both bodies (`\n    }\n` end marker); S-6611 asserts `let across = abs(value.translation.width)` in `single` | untouched | S-15403, S-6611, S-7916 |
| `WatchPagerModel` behaviour | `WatchPagerModelTests.swift` (S-6601..S-6608, S-9110) — behaviour tests, no file text | unchanged | S-15405 |
| `docs/state_management/watch_surface_wrist.md` pager paragraph (`:755-789`) | describes the swipe switch, no animation word (grep "at once" hits only `:161`, an unrelated session sentence) | P3 adds the slide sentence | P3 |
| `docs/watch-app-setup-and-qa.md` | QA steps 1-28; no pager/swipe step (grep this run) | P3 ADDS a step (29), does not update one | P3 |

## New decisions and scenarios

- D-7 The animation constant is a view-file `private static let slideAnimation = Animation.easeOut(duration: WatchPagerCopy.slideSeconds)` (D-3's parenthetical resolved: a computed `static var slideAnimation` on `WatchPagerCopy` would need SwiftUI in the model file, which imports none and is compiled on macOS by the model tests).
- D-8 Reduce Motion keeps `removal: .identity` and swaps only the insertion to `.opacity`; `withAnimation(Self.slideAnimation)` still runs, so the fade is 0.2 s ("a quick fade instead of a slide"). A whole-transition `.opacity` would fade the leaving page out, contradicting D-5.
- S-15407 the strengthened guards: S-9111's and S-7913's `selection = target` assertions read the wrapped literal `withAnimation(Self.slideAnimation) { selection = target }` (S-15404's "updated in the SAME run", made concrete).
- S-15408 source guard: the insertion branch is the ternary `reduceMotion ? .opacity : .move(edge: …).combined(with: .opacity)` inside the `.asymmetric(insertion:` block, and `removal: .identity)` sits outside the ternary — the Reduce Motion branch has its own guard, not just the `accessibilityReduceMotion` substring of S-15402.

## Code pointers (current lines, read this run; the lines below are the current ones)

`WatchLoggingPagerView.swift:36-37` (the property block P1 item 2 replaces):

```swift
    @State private var selection = 0
    @State private var landing = false
```

`paged` and its doc comment (`:66-90`, what P1 item 3 replaces):

```swift
    /// The shown exercise's logger, rebuilt per exercise. A horizontal swipe
    /// moves to the neighbouring exercise at once: the focus names the page the
    /// user reached before the engine has moved (plan 52 D-5), and `land(on:)`
    /// moves the engine behind it. No page-turn, so no name card in between.
    private var paged: some View {
        WatchLoggingView(
            state: state,
            onLogged: onSurfaceChange,
            pageLabel: "\(selection + 1)/\(pager.pageCount)"
        )
        .id(pager.rows.indices.contains(selection) ? pager.rows[selection].slotId : "")
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let across = value.translation.width
                guard abs(across) > 24, abs(across) > abs(value.translation.height),
                      let target = pager.neighbourIndex(of: selection, towardsNext: across < 0)
                else { return }
                WKInterfaceDevice.current().play(.click)
                state.focusSlotId = pager.focusSlotId(for: target)
                selection = target
            }
        )
        .onChange(of: selection) { newValue in land(on: newValue) }
    }
```

`land(on:)` (`:120-146`, untouched):

```swift
    private func land(on index: Int) {
        guard index != pager.currentIndex else {
            state.focusSlotId = nil
            return
        }
        landing = true
        Task {
            let moved = await pager.land(on: index)
            landing = false
            if moved {
                onSurfaceChange()
                // A swipe that settled while this one was landing was dropped
                // (its index equalled the engine's old position); the newest
                // settled page wins rather than being pulled back, and keeps
                // its focus until its own landing ends.
                if selection != pager.currentIndex {
                    state.focusSlotId = pager.focusSlotId(for: selection)
                    land(on: selection)
                } else {
                    state.focusSlotId = nil
                }
            } else {
                state.focusSlotId = nil
                selection = pager.currentIndex
            }
        }
    }
```

`followEngine()` (`:150-155`, untouched):

```swift
    private func followEngine() {
        // With no landing in flight, a focus left over from one is stale.
        if !landing { state.focusSlotId = nil }
        guard pager.showsPager, !landing, selection != pager.currentIndex else { return }
        selection = pager.currentIndex
    }
```

`WatchPagerCopy` (`WatchPagerModel.swift:24-27`, what P1 item 1 extends):

```swift
public enum WatchPagerCopy {
    public static let lockedNotice = "An effort is running"
    public static let noticeSeconds: TimeInterval = 1.5
}
```

## Phases (expanded)

- P1 `crew-builder-watch` — D-1..D-4, D-7, D-8, S-15401..S-15404, S-15407, S-15408 in ONE run (7 items), as EXACT replacement code below (crew rule q/z: a screen-branch rewrite goes into the brief as exact code). Serial (one Swift package); nothing runs in parallel with it — the guards and the code land together, and the package's tests must not be edited by two agents at once.
- P2 lead — after P1. `xcodebuild` watch app (watchOS 9 API check: `accessibilityReduceMotion` is watchOS 6+, `.transition(.asymmetric…)`/`.combined(with:)`/`withAnimation`/`.clipped()` are watchOS 6/7+; `Package.swift:26` declares `.watchOS(.v9)`), full `swift test` (900 s timeout), mutation pass in an isolated copy, simulator look only if asked (see below).
- P3 `crew-docs-keeper` — after P1 (the docs cite P1's guards): pager paragraph in `docs/state_management/watch_surface_wrist.md` (`:755-789`) and a NEW QA step in `docs/watch-app-setup-and-qa.md` (step 29 — none exists today, see Readers); then `crew-reviewer`.

### P1 — crew-builder-watch. One run; serial (one Swift package).

Write scope:
```
"watch/watchos/Sources/WatchSessionEngine/WatchLoggingPagerView.swift"
"watch/watchos/Sources/WatchSessionEngine/WatchPagerModel.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchPagerSourceTests.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchPagerFocusTests.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchPagerSlideSourceTests.swift"
```

Items:
1. [ ] Add `public static let slideSeconds: TimeInterval = 0.2` to `WatchPagerCopy`, after `noticeSeconds` (`:26`), matching the enum's `public static let` member style — `watch/watchos/Sources/WatchSessionEngine/WatchPagerModel.swift` · `WatchPagerCopy` (D-3, S-15401).
2. [ ] Replace the two `@State` declarations (`:36-37`) with the property block below (exact) — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingPagerView.swift` · struct properties (D-2, D-3, D-7).
3. [ ] Replace `paged` and its doc comment (`:66-90`) with the block below (exact) — same file · `paged` (D-1, D-2, D-4).
4. [ ] New `watch/watchos/Tests/WatchSessionEngineTests/WatchPagerSlideSourceTests.swift`: S-15401 (plain assertions on `WatchPagerCopy.slideSeconds`), S-15402, S-15403, S-15408 — copy the private helpers `engineSource`, `strippingCommentLines(_:)`, `propertyBody(named:in:)`, `occurrences(of:in:)` from `WatchPagerSourceTests.swift:36-77` (no shared helper exists, see (b)); read the source through `Fixtures.sourcesRoot`.
5. [ ] Update S-9111's `selection = target` assertion to `source.contains("withAnimation(Self.slideAnimation) { selection = target }")` — `watch/watchos/Tests/WatchSessionEngineTests/WatchPagerSourceTests.swift` · `testS9111…` (S-15404, S-15407).
6. [ ] Update S-7913's selection range to `source.range(of: "withAnimation(Self.slideAnimation) { selection = target }")` — `watch/watchos/Tests/WatchSessionEngineTests/WatchPagerFocusTests.swift` · `testS7913…` (S-15404, S-15407).
7. [ ] Run `swift test --filter WatchPagerSlideSourceTests --filter WatchPagerSourceTests --filter WatchPagerFocusTests --filter WatchPagerModelTests` and `swift build` — all green.

Done criteria: gateway `swift-test` green (`swift test --package-path watch/watchos`); S-15401..S-15404, S-15407, S-15408 green; S-6611, S-7913, S-9111, S-7916, S-9110 green (the strengthened guards included).

Fixtures: the source guards read `watch/watchos/Sources/WatchSessionEngine/WatchLoggingPagerView.swift` and `WatchPagerModel.swift` through `Fixtures.sourcesRoot` with the copied comment-stripping helper; S-15401 is a plain constant assertion (no engine, no fixture).

Exact replacement code — item 2 (replaces `:36-37`):
```swift
    @State private var selection = 0
    @State private var landing = false

    /// The side the next logger enters from, written in the swipe's `onEnded`
    /// before the animated change (plan 85 D-2): a finger moving left takes the
    /// next exercise, which slides in from the trailing edge.
    @State private var slideFromTrailing = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The swipe's slide. The number lives in `WatchPagerCopy` so the desktop
    /// tests can hold it; `Animation` needs SwiftUI, so the animation itself is
    /// built here (plan 85 D-3, D-7).
    private static let slideAnimation = Animation.easeOut(duration: WatchPagerCopy.slideSeconds)
```

Exact replacement code — item 3 (replaces `:66-90`, doc comment included):
```swift
    /// The shown exercise's logger, rebuilt per exercise. A horizontal swipe
    /// moves to the neighbouring exercise: the focus names the page the user
    /// reached before the engine has moved (plan 52 D-5), and `land(on:)` moves
    /// the engine behind it. No page-turn, so no name card in between; the
    /// logger the swipe reaches slides in from the swiped side (plan 85 D-1,
    /// D-2), and only the user's own swipe is animated (D-3).
    private var paged: some View {
        ZStack {
            WatchLoggingView(
                state: state,
                onLogged: onSurfaceChange,
                pageLabel: "\(selection + 1)/\(pager.pageCount)"
            )
            .id(pager.rows.indices.contains(selection) ? pager.rows[selection].slotId : "")
            .transition(.asymmetric(insertion:
                reduceMotion
                    ? .opacity
                    : .move(edge: slideFromTrailing ? .trailing : .leading)
                        .combined(with: .opacity),
                removal: .identity))
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let across = value.translation.width
                guard abs(across) > 24, abs(across) > abs(value.translation.height),
                      let target = pager.neighbourIndex(of: selection, towardsNext: across < 0)
                else { return }
                WKInterfaceDevice.current().play(.click)
                state.focusSlotId = pager.focusSlotId(for: target)
                slideFromTrailing = across < 0
                withAnimation(Self.slideAnimation) { selection = target }
            }
        )
        .onChange(of: selection) { newValue in land(on: newValue) }
    }
```

Formatting is load-bearing: `.transition(.asymmetric(insertion:` is one line and `removal: .identity))` closes right after `.identity` — S-15402 asserts those literals on comment-stripped source (lines joined with `\n`; a break inside a literal fails `contains`).

Predicted files: the five scope files, nothing else.

### P2 — lead. After P1.

`xcodebuild` watch app target (watchOS 9 simulator; only the governor runs `xcodebuild`), full `swift test` (900 s timeout), then the mutation pass in an isolated copy, each mutation proven red by the named guard:
- drop the `withAnimation` wrapper (`selection = target` bare) → S-15403 (count 0 ≠ 1), S-15402, S-15407 (both strengthened guards) red;
- move `slideFromTrailing = across < 0` after the `withAnimation` (or invert to `across >= 0`) → S-15402 red;
- change `removal: .identity` to `.opacity` → S-15402 red (and D-5's repaint risk returns);
- make `followEngine` animate (`withAnimation` around `selection = pager.currentIndex`) → S-15403 red (count 2);
- `slideSeconds` → 0 → S-15401 red;
- drop `.clipped()` → S-15402 red.

### P3 — crew-docs-keeper. After P1; then crew-reviewer.

`docs/state_management/watch_surface_wrist.md` pager paragraph (`:755-789`): the swipe sentence gains the slide (in about a fifth of a second, from the swiped side; Reduce Motion → a quick fade), every behaviour sentence naming an existing test (S-15402, S-15403). `docs/watch-app-setup-and-qa.md`: ADD a QA step (next number is 29 — steps 1-28 exist, none about the pager; plan 79's promised step was never added) — swipe between two exercises, the slide is visible, no name card, the counter changes, the set logged right after a swipe lands on the exercise shown. Files under `docs/` stay below 52 KB.

## Assumption Log

- Whether the incoming page slides over a black or the old page is decided by `removal: .identity`: the old page disappears, the background shows for 0.2 s. A visual check is wanted before the unit is called done (gesture + animation: the case where a test cannot see the change). The lead asks the owner once, in the closing report.
- Whether SwiftUI evaluates the transition's `slideFromTrailing` for the incoming view in the same transaction as the animated state write is checked in the build: if the edge is stale, the gesture's `onChanged` also writes it.

## Progress

| Item | Phase | Status |
|---|---|---|
| `slideSeconds` in `WatchPagerCopy` | P1 | [ ] |
| property block (`slideFromTrailing`, `reduceMotion`, `slideAnimation`) | P1 | [ ] |
| new `paged` (ZStack, transition, gesture, onChange) | P1 | [ ] |
| `WatchPagerSlideSourceTests.swift` (S-15401..S-15403, S-15408) | P1 | [ ] |
| S-9111 wrapped literal | P1 | [ ] |
| S-7913 wrapped literal | P1 | [ ] |
| swift test + swift build green | P1 | [ ] |
| xcodebuild + full swift test + mutations | P2 | [ ] |
| docs + QA step + review | P3 | [ ] |

## Architect notes (corrections made to the seed)

- D-3 line numbers corrected: `WatchPagerCopy` is `WatchPagerModel.swift:24-27` (enum `:24`, `lockedNotice` `:25`, `noticeSeconds` `:26`), not `:27-30`.
- The seed's Readers line said the QA doc holds "plan 79 QA step (a)": no such step exists — `docs/watch-app-setup-and-qa.md` has steps 1-28, none about the pager (grep this run); plan 79 D-9 planned to append one but it is not there (plan 79 has no Progress section; its P4 was not completed). P3 ADDS a step (29) instead of updating one.
- The seed's Readers line said the pager paragraph "says 'at once'": it does not (grep "at once" in `watch_surface_wrist.md` hits only `:161`, an unrelated session sentence); the paragraph (`:755-789`) describes the switch with no animation word. The words "at once" are in the view's own doc comment (`WatchLoggingPagerView.swift:67`), which P1 item 3 replaces.
- D-5's mechanism, made precise (see (c)): the focus write publishes nothing; the leaving logger re-renders on its `WatchLoggingModel`'s next publish (1 s ticker, `WatchLoggingModel.swift:86-90`) and then reads the live `focusSlotId` through `slot` (`WatchLoggingState.swift:608-617`). D-5's text stands; the removal must be `.identity` because any animated removal window outlives the gap to the next publish.
- S-15404's guard update is a strengthening, not a fix: every existing literal survives the new text (see (a)); the two `selection = target` assertions are updated anyway to pin the wrapper (S-15407).
- D-3's `static var slideAnimation` on `WatchPagerCopy` is resolved as a view-file `private static let` (D-7): `WatchPagerModel.swift` imports no SwiftUI and is compiled on macOS by the model tests.

## Open questions

- Whether SwiftUI evaluates `slideFromTrailing` for the incoming view in the same transaction as the animated write (the seed's Assumption Log entry) is not decidable from source; the P2 build check and the `onChanged` fallback stand.
- The exact visual of `removal: .identity` over the ZStack background (black vs the old page) is not decidable from source; the lead asks the owner after the simulator look (seeded Assumption Log).
- S-15406 (simulator swipe with computer-use) needs the Mac unlocked and the owner's agreement; otherwise it is an owner check, as seeded.

## Evidence and review

- Evidence: `docs/plans/2026-10-26-85-wrist-swipe-slide-plan/2026-10-26-85-wrist-swipe-slide-plan.evidence.md` (crew-prover, after P1/P2).
- Review: `docs/plans/2026-10-26-85-wrist-swipe-slide-plan/2026-10-26-85-wrist-swipe-slide-plan.review.md` (crew-reviewer, after P3).
