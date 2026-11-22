# Review: plan 286 · P1-P3 · f1c02a7..working tree (uncommitted)
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 1 · minor 2 · tests: BLOCKED — full suite hung
(see Test run)
Diff vs Predicted Files: conforms (7 files in the diff; the two extra docs —
`docs/watch-app-setup-and-qa.md` and `docs/plans/2026-11-20-280-wear-os-shell-plan.md` —
are named by the brief and the plan's stale-term sweep respectively)

## Test run

`.github/copilot/scripts/windows/gateway.cmd test` (once, 900 s timeout,
exit 124): reached `+88 -1` by 00:30 and produced no further line for the
remaining ~870 s. The one failure is an environment error, not an assertion:
`loading test/active_energy_import_test.dart [E] PathExistsException ... Cannot
copy file to 'C:\Webapps\omnitrain\build\test_cache\...\cache.dill.track.dill'
(OS Error: Cannot create a file when that file already exists, errno = 183)` —
a known flutter_tools Windows flake where two compiler requests collide on the
shared track dill; the next file's compile then hung the run. Log:
`.work/gateway/test-20261121-204114-38740.log`. The `test` check takes no
arguments (gateway list), so a changed re-run was not possible; the plan-286
files (alphabetically later) were never reached in this pass. The brief's
established facts stand for the five Wear shell files and the two new accent
files; `test/ui_standards_contract_test.dart` and
`test/docs_indexing_contract_test.dart` were not observed green in this run.

## Findings

1. [Blocker] docs/wear_os_app.md:439-440 (new `## The accent colour`) — "the
   buttons, the selected number in the rating question and the progress ring
   all take" the primary colour. The Wear wrist has no progress ring: no
   CustomPainter/ProgressRing exists in `lib/watch` (the only circular element
   is the loading `CircularProgressIndicator`, lib/watch/app/wear_app.dart:297).
   An owner running the QA checklist looks for a ring the watch never draws.
   Fix: drop "and the progress ring". Guard: none needed beyond the doc (the
   section's other claims are tied to real tests).
2. [Major] docs/wear_os_app.md:439-440 — the enumeration is not exhaustive and
   misses a real reader of the changed surface: the nutrition screen's
   selected-food border also wears the accent
   (lib/watch/nutrition/watch_nutrition_screen.dart:230,
   `theme.colorScheme.primary`). A maintainer auditing who the accent reaches
   is told a shorter list than the code draws. Fix: add the selected-food
   border to the sentence. Guard: no new test needed (a reader enumeration, not
   new behaviour); optionally one assertion that the border follows the accent.
3. [Minor] docs/wear_os_app.md:457-458 — "A colour that arrives while the watch
   is open shows at the next once-a-second repaint": the repaint is triggered
   by `_onFrame`'s own `setState` the moment the frame applies
   (lib/watch/app/wear_app.dart:195-197); the once-a-second ticker only runs
   while a session is active (wear_app.dart:204-215). The user-visible claim
   (shows without restarting) is true and covered by S-28611, but the
   mechanism sentence is wrong for an idle shell. Fix: "shows on the repaint
   the arriving frame itself triggers".
4. [Minor] plan file, scenario S-28610 — the fixture says "nothing synced,
   start surface" while the expectation says "the first FilledButton's
   Material colour is that cyan"; the start surface builds no FilledButton
   until routines sync. The test resolves it sensibly (session created first,
   noted in-file), so coverage is intact; the plan text stays contradictory
   for the next reader.

## Assumption Log rulings

- "`WatchPhonePreferences.accentColorHex` returns the applying copy's string
  (null when the copy had none)" — RATIFIED: lib/watch/start/watch_phone_preferences.dart:56
  `String? get accentColorHex => current?.accentColorHex;`, stored at :117
  `accentColorHex: accent is String ? accent : null`. Note the stored string is
  not sanitised (any string the phone sends is kept); the class's defensive
  parse covers it and S-28605 walks garbage, empty and too-dark strings.
- "`WearApp._onFrame` runs `setState` after `orchestrator.receive`" — RATIFIED:
  lib/watch/app/wear_app.dart:185-197; `transport.deliver(frame)` is the path
  the harness and S-28611 use.
- "`ColorScheme.copyWith(primary:, onPrimary:)` leaves every other role alone" —
  RATIFIED IN PART: the copyWith half is framework-documented semantics; the
  deeper half — that `ThemeData(useMaterial3: true, colorScheme: scheme)` built
  from the dark scheme differs from `ThemeData(useMaterial3: true, brightness:
  Brightness.dark)` in nothing but the two copied roles — could NOT be verified
  against the Flutter SDK source (the SDK at C:/Users/ezhix/flutter/flutter is
  outside this run's read scope; every read of it was denied). Reasoned
  conclusion from the factory's documented behaviour: all colour defaults
  derive from the supplied scheme and the brightness, both of which are
  identical except primary/onPrimary. Escalated to the governor: verify against
  `theme_data.dart` (or accept on the green shell tests) before the lead's full
  suite. No Wear code reads a role the copy could have disturbed other than
  `colorScheme.error` (destructive, watch_menu_screen.dart:211-213,323),
  `onSurface` and the nutrition border.

## Questions (the brief's five)

1. **Swift vs Dart.** No decision differs. Parse: Swift `hex.count == 7` +
   hasPrefix("#") + `allSatisfy(\.isHexDigit)` + `Int(digits, radix: 16)`
   accepts exactly what the Dart regex `^#[0-9A-Fa-f]{6}$` accepts (Swift's
   `isHexDigit` is ASCII, so `+`/`-`/space are refused in both). Luminance,
   both contrasts, `labelIsDark >=` rule, the 3.0 floor and the `#2DE2E6`
   fallback are line-for-line the same; Dart holds channels as 0..255 ints
   where Swift holds 0..1 doubles (planned, D-28601) and derives `color` /
   `labelColor` getters Swift does not carry in this file. The Swift doc
   comment "an accent too dark to carry black labels is refused here" is stale
   in the Swift file (the floor is contrast-against-black); the Dart comment
   reads correctly.
2. **Cache staleness.** No stale path. `String?` is immutable and `==` on the
   raw hex is exact, so "changes but compares equal" cannot happen; null and
   `''` are distinct keys that both resolve to the fallback theme; a runtime
   swap of `widget.preferences` is re-read from `widget.preferences` every
   build, so a different owner with a different hex builds a new theme. Only
   weakness: a one-entry cache rebuilds on every A/B/A alternation — perf, not
   correctness (S-28617 covers the steady-state identity).
3. **ThemeData role diff.** See Assumption Log row 3: not verifiable on this
   machine; reasoned no-other-role-change; no Wear code reads a role that the
   two constructions could plausibly differ on except the ones already named.
4. **Screens reading the old lilac `primary`.** Grep `colorScheme.primary` over
   `lib/watch`: one reader, the nutrition selected-food border
   (watch_nutrition_screen.dart:230). The destructive uses read
   `colorScheme.error` (watch_menu_screen.dart:211-213,323) and stay fixed —
   matching the Apple wrist's fixed red. Nothing reads a hex lilac.
5. **Doc claims vs code/tests.** One false claim (the progress ring, finding 1)
   and one incomplete enumeration (the nutrition border, finding 2). Every
   other sentence in `## The accent colour` names a test that exists with the
   quoted name (all 13 references verified by reading both test files); the
   "desktop QA harness delivers a copy with no accent" claim matches
   lib/watch/debug/wear_menu_debug_main.dart:108-120 (no `accentColorHex` key).

## Docs delta

| Doc | Change | Status |
|---|---|---|
| docs/wear_os_app.md | "and the accent colour still shows" -> "the accent colour tints the buttons" | applied |
| docs/wear_os_app.md | "nothing — the accent theming stays on the Apple-only list above." -> "described in `## The accent colour`" | applied |
| docs/wear_os_app.md | "spoken timer cues and the accent" -> "and spoken timer cues" | applied |
| docs/wear_os_app.md | ADDED `## The accent colour` | applied |
| docs/wear_os_app.md | ADDED "8. (owner) with a paired phone set to a colour theme" | applied |

Doc edits the table does not name: `docs/watch-app-setup-and-qa.md` (the
one-sentence move; named by the brief) — applied; and
`docs/plans/2026-11-20-280-wear-os-shell-plan.md` (2 lines, the plan-280
record; named by the plan's stale-term sweep prose) — applied. The stale-term
sweep's "line 267 stays true" holds: the preferences store does keep the
accent (`watch_phone_preferences.dart:117`).

## Scenario coverage

S-28601 -> test/watch_accent_test.dart · S-28601 the contract's six accents parse and read the table's contrast figures
S-28602 -> test/watch_accent_test.dart · S-28602 the parser accepts #RRGGBB and nothing else
S-28603 -> test/watch_accent_test.dart · S-28603 the wearability floor is 3.0
S-28604 -> test/watch_accent_test.dart · S-28604 the label rule compares the two contrasts
S-28605 -> test/watch_accent_test.dart · S-28605 worn falls back or wears the accent
S-28606 -> test/watch_accent_test.dart · S-28606 the channels are not mixed
S-28610 -> test/wear_accent_theme_test.dart · S-28610 the fresh shell wears the phone's default accent
S-28611 -> test/wear_accent_theme_test.dart · S-28611 a delivered accent becomes the shell's
S-28612 -> test/wear_accent_theme_test.dart · S-28612 a newer copy replaces it, a copy without accent restores the default
S-28613 -> test/wear_accent_theme_test.dart · S-28613 an accent too dark is refused; a usable grey wears with white labels
S-28614 -> test/wear_accent_theme_test.dart · S-28614 an older copy does not replace the newer one
S-28615 -> test/wear_accent_theme_test.dart · S-28615 a shell without preferences stays on the default
S-28616 -> test/wear_accent_theme_test.dart · S-28616 a store that holds a copy dresses the new shell
S-28617 -> test/wear_accent_theme_test.dart · S-28617 the theme is cached across the 1 s ticks and rebuilt on a new accent

No scenario missing. Each test asserts something the diff changed (the class,
the theme builder) and would fail without it.
