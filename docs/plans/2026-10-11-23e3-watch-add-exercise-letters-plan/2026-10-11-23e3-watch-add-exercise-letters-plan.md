# Plan 23e3: jump to a letter in the watch's Add Exercise list

Series: `docs/plans/2026-10-11-23e-watch-batched-exercise-list-series.md` (item 6). Owner decision (2026-10-11): jump-to-letter first; search later if at all.
Base: `.work/2026-10-11-23e3/base.txt`. Governor-seeded, one phase. Track: watch UI (Swift package model + the view in the same package).

## Goal and acceptance (what the owner sees)

1. Add Exercise (menu, above End Session) opens the A to Z list as today. When the list holds MORE than 20 exercises, a grid of letters sits at the top of the list: one small button per first letter that exists
   in the list (a 250-exercise list shows the letters it has, not the whole alphabet), four per row.
2. Tapping a letter scrolls the list so that letter's first exercise is at the top. It does not add anything and does not leave the screen. Tapping an exercise still adds it at the end and returns to the menu (unchanged).
3. Names that start with a digit or a symbol are grouped under `#`, which sits where they sort: before A. A name starting with an accented letter (for example "Élan") has its own letter and sits where the list puts it (after Z), because the list order is plain lowercase text (23c, unchanged).
4. With 20 exercises or fewer there is no letter grid (the list fits a few scrolls).
5. The empty list and everything else on the screen are unchanged.

## Decision ledger

- D-3850 The letters are a pure function of the list the menu offers (`WatchSessionStartPaths.addableExercises`, `WatchStartPaths.swift:587`, sorted by lowercased name, ties by id), exposed on the menu state:
  `WatchMenuState.addExerciseLetters: [WatchAddExerciseLetter]` (`WatchMenu.swift`, next to `addableExercises` at line ~195) where `WatchAddExerciseLetter` is `Equatable` with `letter: String` and `firstExerciseId: String`.
  Key of an exercise = its name's first character, uppercased, when that character `isLetter`; otherwise `"#"`. One entry per distinct key, in the order the keys first appear in `addableExercises`, `firstExerciseId` = the first exercise with that key in that order. The key is read from the FIRST character as it is, whitespace included: a name that is empty or starts with whitespace has key `"#"` (a leading space sorts before every letter, so it sits in the `#` run and the grid stays contiguous with the list). (Revised by the governor after mutation H6 showed the earlier "skip leading whitespace" rule broke contiguity.)
  No diacritic folding and no locale: the grid must agree with the list order, which is plain lowercase text.
- D-3851 Threshold: `WatchMenuCopy.addLetterGridThreshold = 20` (an `Int` constant in `WatchMenuCopy`, `WatchMenu.swift:~55`): `addExerciseLetters` is `[]` when `addableExercises.count <= 20`.
- D-3852 View (`WatchMenuView.swift`, `WatchAddExerciseList`, ~line 184): wrap the existing `ScrollView` content in a `ScrollViewReader`; above the `LazyVStack` of rows, when `state.addExerciseLetters` is non-empty, a `LazyVGrid` of four flexible columns of `Button(letter.letter)` (`.buttonStyle(.bordered)`, `.font(.footnote)`) whose action is `proxy.scrollTo(letter.firstExerciseId, anchor: .top)` WITHOUT animation (restrained motion); each exercise button gets `.id(exercise.exerciseId)`. The existing add action, dismiss and title stay.
  A VoiceOver label for each letter button: `"Jump to \(letter)"` (`WatchMenuCopy.addLetterJumpLabel(_:)`, testable).
- D-3853 No wire, store, phone or Wear change. Docs: `docs/state_management/watch_reference_data.md` (the Add Exercise list paragraph; remove before adding) or the page that describes the menu (`grep -n "Add Exercise" docs/state_management/*.md`), and one owner QA step in `docs/watch-app-setup-and-qa.md`.

## Scenarios (tests first; each must fail without the change). `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`, using the harness there (read how `testS3611` builds its list; for a long list add a helper that seeds N exercises through the fallback/synced list)

- S-3900 a list of 21 names `a01`..`a21`-style on the letter A..: use 25 names built from letters so that: apple, Avocado, banana, Blueberry, cherry, ... gives the expected `[A, B, C, ...]` letters with the right `firstExerciseId` (name-ordered; "apple" before "Avocado").
- S-3901 `"#"`: names starting with "1", "5 minute plank", "(warm up)" are grouped under `"#"` which is FIRST (they sort before letters); one `#` entry whose `firstExerciseId` is the first of them in list order.
- S-3902 threshold: exactly 20 exercises -> `[]`; 21 -> non-empty. Assert against `WatchMenuCopy.addLetterGridThreshold` too.
- S-3903 case: "apple" and "Avocado" are one `"A"` entry; its `firstExerciseId` is the one the list shows first.
- S-3904 "Élan" has letter `"É"` and is the LAST entry (it sorts after "zebra" in the plain-lowercase order); "zebra" is `"Z"`.
- S-3905 contiguity property over a generated 120-name list (mixed case, digits, an accent): walking `addableExercises` in order, every exercise's key equals the key of the nearest preceding letter entry's first-exercise boundary, i.e. entry `i` covers exactly the exercises from its `firstExerciseId` up to (excluding) entry `i+1`'s; and every entry's `firstExerciseId` is in `addableExercises`.
- S-3906 the label: `WatchMenuCopy.addLetterJumpLabel("A") == "Jump to A"`.
- S-3907 an empty-name exercise falls under `"#"` (a name of only spaces too), a name with a LEADING space (" apple") keys to `"#"` not `"A"` and sits in the `#` run, and nothing crashes.

## Phase

| # | Agent | Scope | Items |
|---|---|---|---|
| L | crew-builder-watch | `watch/watchos/**`, `docs/state_management/**`, `docs/watch-app-setup-and-qa.md` | D-3850 model + struct, D-3851 constant, D-3852 view (compile only; the governor builds it), tests S-3900..S-3907, doc line, QA step (owner) |

## Verification (governor, observed)
`swift test` (550 + new), `xcodebuild` watch scheme (the view compiles into the app target only), `flutter analyze` 196, docs guard. Mutations: threshold `<` instead of `<=`; key not uppercased; digits not grouped under `#`; keys listed alphabetically instead of in list order (breaks `#`-first and `É`-last); first id taken as last. (owner) Real watch: open Add Exercise with the full list, tap letters, check the list moves to the right place and tapping an exercise still adds it; with a short list (a fresh install with few exercises) there is no grid.

- S-3908 (added after mutation H4) a symbol above `z` (for example `~stretch`) is the LAST row of the list, so the `#` entry then comes last, because the entries follow the list's order, not the alphabet.

## Progress and results (governor, observed)
- Phase L built by crew-builder-watch (558 tests), then two closed fixes: leading whitespace now keys to `#` (D-3850 revised; the old rule broke contiguity), and S-3908 (a guard that did not guard).
- Verified by the governor: swift 559/0; xcodebuild watch scheme BUILD SUCCEEDED (the view compiles); flutter analyze 196; full flutter test +4296 ~1; docs guard 9/9.
- Mutations: H1 threshold, H2 no uppercase, H3 digits not under `#`, H5 last id, H6 whitespace skipped, H4 alphabetical order: all red on the scenario named (H4 only after S-3908 was added; H6 only after S-3907 was extended).
- Known and accepted: symbols above `z` (`{ | } ~`) put a second run of `#` names at the end of the list; the single `#` entry jumps to the first run only (reach the late ones by scrolling). No independent review round for this PR (one view, one model, 8 scenarios, 6 mutations).
- (owner) QA step 14 in `docs/watch-app-setup-and-qa.md`: nothing about the grid's look (size of the 4-column buttons on a 42 mm watch) is verified; only the model is.
