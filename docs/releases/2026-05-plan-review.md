# May 2026 Plan Review

This document summarizes the implementation plans reviewed for the window **2026-04-17 through 2026-05-17** and records the user-facing or operator-facing changes that landed in the app.

It is a release-style roundup, not a source-of-truth architecture document. For deeper behavior details, follow the linked feature docs.

---

## Session Flow Updates

- **Live session detail controls were reworked**.
  - Set progress now uses inline `remove · label · add` controls.
  - The main action row uses `back · Start/Log/Logged · forward`.
  - Timed, round, and drill entries start or pause from the timer display itself.
- **Session elapsed time now starts when training starts**, not when the shell session is created.
  - The session clock stays at `00:00` until the first exercise is added.
- **Cold-start resume for unfinished sessions** is implemented on the home screen.
  - If an in-progress session exists in storage, home presents an `Unfinished Session` dialog with continue/discard actions.

See:

- `.github/agents/docs/modality_based_exercise_ui.md`
- `.github/agents/docs/navigation_and_screens.md`

---

## Exercise and Routine Authoring

- **Custom exercise creation is modality-first**.
  - The form requires a modality.
  - Discipline choices are filtered by the selected modality's category.
  - Capability chips are filtered by modality-specific form rules.
  - Muscle-group chips only appear for resistance and isometric exercises.
  - Edit mode preserves unsupported historical capabilities as removable `Legacy` chips.
- **Routine detail editing now mirrors the live session mental model more closely**.
  - Inline add/remove set controls flank the progress label.
  - Preferred unit labels carry through when settings are available.

See:

- `.github/agents/docs/create_new_exercise.md`
- `.github/agents/docs/my_routines.md`

---

## Settings, Inputs, and Alerts

- **Settings is now a broader control surface**, not just a theme picker.
  - Start of week
  - Weight unit
  - Distance unit
  - Effort timer sound
  - Rest ping interval
  - Rest ping sound
  - Feeling survey toggle
  - Theme selection
- **Timer alerts moved to bundled audio assets**.
  - Five selectable sounds are preloaded through `TimerAlertService`.
  - Effort completion uses heavier haptics; rest ping uses lighter haptics on native platforms.
- **Shared text-input behavior was tightened up** across recent form work.
  - Numeric entry surfaces use the native done-bar pattern where supported.
  - Text fields now default to word or sentence capitalization where appropriate.
  - Tap-outside dismissal is used more consistently.

See:

- `.github/agents/docs/theme_and_settings.md`
- `.github/agents/docs/state_management.md`

---

## Home and Surface Polish

- **The maintenance sheet now opens in a single step**.
  - The previous middle snap point was removed.
- Visual polish plans from this period included spacing, shadow, and card-alignment work.
  - These were reviewed but are mostly doc-neutral unless they changed interaction behavior.

See:

- `.github/agents/docs/app_philosophy.md`

---

## Operator-Facing Release Work

- **The iOS TestFlight release path is now documented and supported by checks**.
  - `scripts/pre_release_check.sh` validates build-number monotonicity and release configuration expectations.
  - `docs/releases/ios-testflight.md` is the canonical upload checklist.

See:

- `docs/releases/ios-testflight.md`

---

## Reviewed But Mostly Doc-Neutral

These plans were reviewed but do not currently require deep standalone documentation updates beyond code comments or the higher-level notes above:

- home tile shadow parity
- gradient window layer refactor
- session detail spacing polish
- failing-tests repair work
- other pure layout or visual parity cleanup tasks

---

**Reviewed Window**: 2026-04-17 to 2026-05-17
**Recorded On**: 2026-05-17