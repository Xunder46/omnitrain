# The Watch Surface — the Wrist's Exercise Pager

**Scope.** The swipe between a session's exercises on the wrist: one logger, the slide-in, the lock while an effort clock runs. Source: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingPagerView.swift`, `WatchPagerModel.swift`.

> Part of [State Management & Services](../state_management.md), split from [The Watch Surface — the Wrist's Half](watch_surface_wrist.md) on 2026-10-26 to keep that page under the size band. The section below moved verbatim.

---

## The logging screen pages the session's exercises

**Files**: `watch/watchos/Sources/WatchSessionEngine/WatchPagerModel.swift`,
`.../WatchLoggingPagerView.swift`; the shell mount is
`ios/OmniTrain Watch App/ContentView.swift` (`loggingSurface`).

**The pager is a rule over the menu, not a second way to move the session.**
`WatchPagerModel` is a `@MainActor` model over one `WatchMenuState`, with one
construction site (`menuState`) read by both the pager and the menu sheet. Every
access constructs a plain wrapper over the same engine, paths and rating, so the
instances are equivalent; a settled swipe is the menu's own select path,
`jump(to:)`, and nothing else writes the session. The rows, the position and the
counter are read from the menu on every access, never cached, so a frame that
lands while the pager is open is already the page the user sees. Verified by
`WatchPagerModelTests.swift` (`testS6601TheModelReadsTheLadderAndThePositionOnEveryAccess`,
`…testS6607APhoneSideAdvanceIsVisibleOnTheNextRead`).

**The session moves only when the swipe has settled.** `WatchPagerModel.land(on:)`
makes one select per settled page — one `exercise_advanced` lifecycle frame, the
existing emission — and a page that is already current settles true without
selecting anything. A page outside the rows, including one the phone removed
between the swipe and the settle, changes nothing and is not a locked swipe.
Verified by `…testS6602ASettledPageMovesTheSessionOnceAndEmitsOneFrame`,
`…testS6602TheSameIndexArmSelectsNothing`,
`…testS6604APageOutsideTheRowsChangesNothing` and
`…testS6608SettlingOnAPageThePhoneRemovedChangesNothing`. (The method is
`land`, not `settle`: the module's S-004 source guard bans new names that start
with `set`.)

**While an effort clock runs there is no pager.** `showsPager` is false, the
view renders one page with no swipe paging, and a mostly-horizontal swipe over
the drag minimum plays the failure haptic and raises the one-line notice
`WatchPagerCopy.lockedNotice` — the menu's own lock words — for
`WatchPagerCopy.noticeSeconds`; a running rest is not a lock and the pager
stays free. Verified by `…testS6603ASwipeDuringAWorkClockIsRefusedAndRaisesTheNotice`,
`…testS6605ARunningRestLeavesThePagerFree` and
`…testS6606ThePagerShowsOnlyForSeveralExercisesAndAnUnlockedMenu`, which also
holds that a session with one exercise shows no pager and no counter at all
(`pageLabel` nil).

**The view is the shape around that model, and the desktop toolchain holds only
its outline.** `WatchLoggingPagerView` (watchOS-only) mounts ONE
`WatchLoggingView` for the shown exercise — its n/m counter sits beside the
exercise name (`WatchLoggingView(pageLabel:)`) — rebuilt per exercise through
`.id(<shown slot id>)`, so no tile or Crown state of one exercise leaks into
the next. There is no page-turn and no name-only card at any moment: a
mostly-horizontal drag longer than 24 points on the shown logger asks
`WatchPagerModel.neighbourIndex(of:towardsNext:)` for the neighbouring page
(a finger moving left goes to the NEXT exercise, right to the previous; no
wrap; nil when the pager is not shown), plays `.click`, sets
`state.focusSlotId = pager.focusSlotId(for: target)` and then moves the
selection; `.onChange(of: selection)` calls `land(on:)` unchanged, so the
logging surface shows the exercise the user swiped to before the engine has
moved. Since plan 85 the switch is animated: the next exercise's logger slides
in from the swiped side in 0.2 s (`WatchPagerCopy.slideSeconds`), with Reduce
Motion falling back to a fade, and the leaving logger disappears at once
(removal `.identity`: it reads the live session and would show the new
exercise's numbers while leaving); only the user's own swipe animates — a
phone push or a menu jump switches without animation — and the first and last
exercise do not move. Verified by `WatchPagerSlideSourceTests.swift`
(S-15401..S-15403, S-15408). `land(on:)` clears the
focus whether it moved or was refused (also on its early return, and
`followEngine()` clears a focus left over when no landing is in flight), and the
next settled swipe names its own focus again. While the focus is ahead of the
engine, `startWork()` is refused, so a clock is never started against an
exercise the engine has not reached and a refused landing cannot strand one
(`WatchPagerFocusTests` S-7915, S-7916). The shell's `loggingSurface` mounts the pager and not the bare
logging view, and the pager binds no Crown and takes no
`.focusable` focus — the Crown stays on `WatchLoggingView`, stepping the
outlined value, and never changes exercise. Verified by
`WatchPagerSourceTests.swift`
(`testS6610TheLoggingSurfaceMountsThePagerAndNotTheBareView`,
`…testS6611ThePagerIsNoTabViewAndStillAnswersADragWhenLocked`,
`…testS9111ThePagerIsOneLoggerWithASwipe`,
`…testS6612ThePagerTakesNoCrownAndNoFocus`) and `WatchPagerFocusTests.swift`
(`testS7913ThePagerViewWiresTheFocusThroughTheSwipe`, S-7911, S-7912, S-7914:
the focus shows the focused exercise and logs against it, the
pager names a focus only for another live page and none for a locked session,
and a slot with no id of its own reached
through the id its exercise derives). The rest screen replaces the
logging screen as before, so there is no paging in rest; the phone screen does
not follow a wrist swipe (owner decision O-5).
