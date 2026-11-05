# Review: 26-ui-rule-breaks · phases 1-2 · 6d17994..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 1 · minor 4 · tests: governor ran the full suite (+4375 ~1, all passed) and `flutter analyze` (187 issues, baseline 195, 0 errors) — not re-run here
Diff vs Predicted Files: conforms for plan 26's own files (17 lib files + 4 new test files + 1 edited test). The same diff also carries concurrent agents' work that is not plan 26 and was not reviewed here: `lib/features/stats/exercise_progress_screen.dart`, `lib/features/stats/stats_screen.dart`, the `LoadFailureView` half of `lib/features/stats/records_and_trends_screen.dart`, `pubspec.yaml` (sqlite3 hooks), and untracked `lib/features/stats/widgets/load_failure_view.dart`, `lib/features/stats/widgets/omni_message.dart`, `test/omni_message_test.dart`, `test/stats_load_failure_test.dart` (plans 27/28 + a build fix).

## Findings

1. [Blocker] lib/core/constants/home_tiles.dart:102 — Goal 7 is only three-quarters met: the Routines home tile accent is still the fixed grey `Color(0xFF9E9E9E)` in all six themes, and the diff adds an allowlist entry (`rawColourExceptions`, reason "tile accent is const, needs a design decision") to excuse it. The entry is reasoned, self-checked, and matches the phase-2 brief's STOP clause verbatim, but D-26.7 does not list `home_tiles.dart`, so the plan never ratified it. The STOP rationale is verified: `HomeTiles.all` is `static const`, the other five accents are `ModalityColors.*` consts, and `accentColor` is consumed raw (`energy_tile.dart`, passed through `home_screen.dart`), so a theme-aware accent needs a non-const config and every consumer touched. Fix: owner decision — amend D-26.7 to ratify the entry (and goal 7's wording), or commission the theme-aware tile accent as its own plan item. Guard: the allowlist self-check keeps the entry honest either way.
2. [Major] lib/features/routine/routine_setup_screen.dart:1113-1121 — the effort/exercise row's tap feedback is lost. The old `Card` provided a Material for the `InkWell` splash; `OmniSurface` is a plain coloured `Container`, so the splash now paints on the scaffold's Material *under* the opaque surface — tapping an exercise row in routine setup shows no ripple. Builder disclosed it; no test covers the splash. Fix (smallest): wrap the `InkWell` in `Material(type: MaterialType.transparency)` inside the surface (or move the ink above the colour). Guard: a widget test asserting a tap on the row changes something visible, or at least that the `InkWell` has a Material between it and the surface colour.
3. [Minor] lib/features/calendar/calendar_screen.dart:472 — the no-period day-cell fill went from `Colors.grey.withOpacity(0.08)` to `colorScheme.outlineVariant` (white at 19%): ~2.4× more opaque, so empty day cells read clearly lighter than before, and `design_system.md:386` documents `outlineVariant` for dividers/borders, not as a fill under text (day-number contrast drops slightly). Brief-authorized token (the brief named `surfaceBorder`/`outlineVariant`); legible in all six dark themes. If the owner wants the old subtlety, pick a lower-alpha role. QA-visible.
4. [Minor] lib/features/session/session_summary_screen.dart:556,1105 — the save-as-routine sheet border and the PR divider went from 6% white hairlines to `outlineVariant` (19% white): both are noticeably more visible. Brief-authorized; legible. QA-visible.
5. [Minor] test/ui_standards_contract_test.dart (ratchet regex `Colors\.$member\b`) — shaded neutrals (`Colors.white70`, `Colors.black54`, …) do not match on the word boundary, so they escape both the ratchet and the hue scan. Latent: `grep "Colors\.(white|black)\d" lib/` is currently empty (builder disclosed). Fix: widen the ratchet pattern to `Colors\.(white|black)\d*\b` or add the shaded names to `hueColourNames`; route to plan 30 (E-1) with the hex-two-step gap (`final x = 0xFF…; Color(x)` also escapes, currently unused).
6. [Minor] test/ui_standards_contract_test.dart (`buttonShapeFindings`) — a button whose `style:` is a shared variable that carries a shape (`style: _dialogButtonStyle`) would be flagged as a false positive, because only the call's own text is searched; the guard forces inline styles. No current site (scan green; the day-list mode buttons were deliberately given `.copyWith(shape:)` at the call sites). Acceptable for now; note for plan 30 if a shared-style idiom appears.

## Assumption Log rulings

- Helper/allowlist in `test/helpers/` not the plan's `test/support/` — **ratify** (the phase-2 brief resolves it: "the plan's `test/support/` means `test/helpers/`"; amend D-26.5's path when convenient).
- Day-list mode buttons get the shape via `.copyWith(shape: _modeButtonShape)` at the call sites with `OmniTheme.buttonBorderRadius` (12), not D-26.2's `buttonUtilityRadius` — **ratify**: those four buttons already had a 12px shape inside their style helpers before this change; the fix only makes it visible to the scan, and changing the radius would have been an unlisted visual change. D-26.2's utility radius applies to the dialog actions, which all got it.
- `home_tiles.dart` STOP + allowlist entry — **escalate** (finding 1).
- `InkWell` splash under `OmniSurface` — **escalate** (finding 2).
- Ratchet word-boundary gap — **escalate to plan 30** (finding 5).

## Scenario coverage

- S-2601 → test/ui_standards_contract_test.dart · `S-2601 button shape / every button constructor in lib/ sets a shape` · PROVEN RED AT 6d17994, exactly the plan's 8 sites.
- S-2602 → test/ui_standards_widget_test.dart · `Mock S-2602 ModalityPickerDialog` (3 tests; shape+no-OutlinedButton and Cancel-returns-null PROVEN RED; row-returns-value is a preservation guard, green at base by design).
- S-2603 → test/ui_standards_contract_test.dart · `S-2603 no raw Card / no feature or widget file builds a raw Card` · PROVEN RED, the plan's 3 sites.
- S-2604 → test/ui_standards_contract_test.dart · `S-2604 no raw colours / every raw colour in lib/ is a fixed site or an allowlisted one` · PROVEN RED, 13 findings containing all the plan's sites.
- S-2605 → test/ui_standards_widget_test.dart · `Mock S-2605a RecentPRList` (2) + `Mock S-2605b DaySessionListScreen headers` (2) · 3 PROVEN RED, empty-day test is a preservation guard.
- S-2606 → test/ui_standards_contract_test.dart · `S-2606 IconButton tooltip / every IconButton in lib/ carries a tooltip` · PROVEN RED, exactly the plan's 18 sites.
- S-2607 → test/ui_standards_contract_test.dart · `S-2607 colour ratchet / no file uses Colors.white or Colors.black above its ratchet` + the two allowlist self-checks · guards present, UNPROVEN (prover verdict NOT PROVEN; three mutations listed in `.work/crew/2026-10-12-25-ui-standards/report-prover-26.md` for the governor).

## User-visible changes (was -> now)

- 4 dialog action buttons (add-food cannot-delete OK and delete-group Cancel, metric-chooser Close and Cancel): default pill -> 8px-rounded rectangle (`buttonUtilityRadius`).
- Modality picker Cancel: outlined button with primary border -> plain text button, 8px-rounded.
- Modality picker dialog: fixed #1a1a1a background, white text, blue selection accents, grey borders -> theme `surfaceContainerHigh` / `onSurface` / `primary` / `outline` / `onSurfaceVariant`; now follows all six themes.
- Session block card, routine segment card, routine effort row: 70%-translucent surface fill + Material elevation 2 + 12px corners -> opaque `OmniSurface`: theme surface, surface border, deep shadow, 20px corners. Outer margins preserved (16/0/16/16; bottom 16; bottom 12); effort-row ripple radius 12 -> 20 (and the ripple is now invisible — finding 2).
- Records page: "Recent PRs" title inside the card (titleSmall, dominant) -> `RECENT PRS` section header above the card (labelSmall, wide tracking, muted); rows unchanged.
- Calendar day list: `Completed` / `Planned` / `In Progress` private headers -> `COMPLETED` / `PLANNED` / `IN PROGRESS` `OmniCardHeader`s; same 4/8 spacing, same group order.
- Delete icons on calendar session rows, period rows and the session-list popup item: `Colors.redAccent`/`Colors.red` -> `colorScheme.error` (slightly deeper red in all themes).
- 18 icon-only buttons gained screen-reader tooltips: Previous month, Next month, Edit session, Delete session, Close (day list), Clear search (exercise library, exercise picker, records), Back (maintenance placeholder, session list, back header), Delete period, Move block up, Move block down, Remove exercise (session overview, session summary), Close (settings ×2).
- Onboarding "Get Started" label: fixed #060B14 -> `colorScheme.onPrimary` on the primary fill.
- Session coach-mark card: fixed #1A1A2E background with white text and black87 button label -> theme `surface` / `onSurface` / `onPrimary`.
- Calendar day cells without a period: 8% grey tint -> `outlineVariant` (19% white) — cells read lighter (finding 3).
- Session summary save-as-routine sheet border and PR divider: 6% white hairline -> `outlineVariant` (19% white) — more visible (finding 4).
- Routines home tile: unchanged — grey accent stays, allowlisted (finding 1).
