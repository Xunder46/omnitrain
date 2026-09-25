# OmniTrain — Stats Redesign Prompt Pack (Modality Lens)

> **Revision 2 — 2026-09-24.** Reconciled against the codebase and the owner's answers of
> 2026-09-24. What revision 1 assumed that the code contradicts is listed under
> [Revision notes](#revision-notes-2026-09-24). Every resolved question is in the
> [Decision Ledger](#decision-ledger), and the items still waiting on the owner are under
> [Open items](#open-items). Decisions are referenced inline as **D-n** and open items as **O-n**.

## Document Purpose

This pack redefines the Stats experience so it follows the same philosophy as tracking. In tracking, an exercise keeps its identity and the effort kind decides how it is measured. In Stats, **the modality decides the lens and the effort kind decides the native metric.** Today Stats shows a fixed number of charts per effort kind (the top 3 lifts and the top 2 each of cardio, isometric and sports exercises), plus a feeling trend and a nutrition trend. It shows no relationship between modalities, it silently leaves out every exercise outside those top slots, and it reads as a wall of charts. The redesign replaces it with three layers:

1. **Mix** — where the user's training went in the current window, by modality, against their own baseline.
2. **Signals** — at most two short, rule-based observation cards with an optional one-line suggestion.
3. **Instruments** — a per-exercise list using each effort kind's native metric, with full charts one tap away.

The previous screen's depth is kept as **Records & Trends**, opened from an icon in the Stats header.

Items are ordered by dependency and by the current watch v1 work in progress:

- **Tier 1 — Capture now.** Data that must be recorded from the first watch release. Every week without it is baseline that can't be recovered later. All four items are launch-critical for the watch release.
- **Tier 2 — Stats foundation.** The new screen structure. It works on existing data from day one and becomes richer as Tier 1 data accumulates.
- **Tier 3 — Signals.** Individual cards, ordered by how soon they have enough data to appear.

Launch-critical items are marked ⚑.

### Standing rules (apply to every item)

- **What was logged drives analytics.** Metrics come from the effort actually logged, never from session labels or tile names. A set logged in Free Training counts as Resistance, and a timed effort inside a lifting session counts as Cardio. There are no exceptions (D-3). See **Effort modality** below.
- **Instrument panel, not coach.** Every signal states a measured observation against the user's own history, then at most one light suggestion phrased as an option ("…is one option"). Signals never:
  - claim causes;
  - reference past "successful blocks" or outcomes;
  - use medical language;
  - suggest eating less or name a calorie number.
- **Positives count too.** Positive signals are first-class so the feature never reads as constant criticism.
- **Data sufficiency gates everything.** Anything that compares against a baseline stays hidden until enough data exists; it is never zero-filled, guessed or silently widened. Where it helps, the screen says what is still building (e.g., "Load baseline: 2 of 4 weeks").
- **Watch architecture is unchanged.** The watch is append-only, and the phone owns session structure and all edits. Timers stay as wall-clock timestamps. **Watch items in this pack are built for watchOS only (D-1).** Everything they add travels in the shared watch↔phone format, so the later Wear OS cloning job inherits it; no Wear OS work is part of this pack.
- **Units follow the user's saved preference** everywhere, including new metrics.
- **Personal records keep one source of truth.** The in-workout toast, Session Summary and Stats/Records must keep agreeing on what a PR is. This pack does not change the PR definition.
- **Estimated values are always labelled.** Any value that is estimated rather than measured says so wherever it appears.
- **Record the reversed decision.** The Stats documentation lists "no rest / deload / recovery suggestion" as a deliberate non-feature. This pack reverses that on purpose, limited to the signal rules below, and the documentation must say so. The app philosophy document lists a coaching-first experience and advanced predictive analytics as non-goals; it must gain a note that signals are observations against the user's own history, not coaching (D-13).

### Shared definitions (use consistently across all items)

- **Effort rating:** how hard the whole session was, on a 1–5 scale, from 1 (Very easy) to 5 (Max effort). It is the existing post-session prompt redefined (D-4): the same five numbered tiles, the same stored answer and the same settings toggle. Answers recorded before the redefinition are read as effort ratings on the same scale, with no conversion (D-5).
- **Session load:** session duration in minutes × effort rating. A session without a rating has no load and is counted as "unrated".
- **Effort modality:** which of the four modalities an effort belongs to. It is decided by the kind of effort logged, with no exceptions (D-3). A session started from a modality tile gives every exercise that tile's kind of effort, so in practice this is the modality the effort was tracked under:
  - a set → Resistance;
  - a hold → Isometric;
  - a round → Sports, whatever the exercise (D-15);
  - a timed effort → Cardio, whatever the exercise (D-3).
- **Measured time:** the active time recorded by timed, hold and round efforts (start to stop, pauses excluded). Sets record no time.
- **Time per modality within a session (D-8):** timed, hold and round efforts contribute their measured time to their own modality. Resistance gets the remainder: the session's duration minus all measured time, never below zero. When the split can't be determined — for example, the measured time exceeds the session's duration — the whole session goes to the dominant modality (the one with the most efforts), with ties resolved deterministically.
- **Rolling sessions (D-9):** a rolling (all-day) session has no meaningful duration. Its time is its measured time only; its sets add no time. Its load is measured time × rating, split by the measured time of each modality. A rolling session with only sets contributes no time and no load.
- **Mixed sessions (Free Training or sessions with several modalities):** load is split across modalities in proportion to the time per modality defined above.
- **Current window:** the existing Stats window (the active training period, otherwise the most recent 14 training days), shown by the existing chip in the header.
- **Baseline:** the user's own history in the comparison period defined by each item. It is never a population average, except where an item explicitly allows a commonly cited reference.
- **Consistently logged nutrition week:** food logged on at least 5 of 7 days.
- **Hard sports session:** a sports session whose load is in the user's top 25% of their rated sports sessions over the last 90 days. At least 8 rated sports sessions are required before any session can be classified as hard.
- **Distance sources:**
  - GPS (measured);
  - entered or corrected by the user (measured);
  - device-estimated (indoor distance estimated by the watch platform from motion and steps; labelled "est.").
- **Indoor and outdoor (D-2):** decided by the exercise. Treadmill Run, Stationary Bike, the Elliptical exercises, the rowing and ski ergs, and similar machine cardio are indoor. Every other distance exercise, including every custom exercise, is outdoor and uses GPS. An outdoor effort that never gets a GPS fix falls back to the platform's estimate, labelled "est.".

---

## Decision Ledger

| ID | Decision | Source |
|---|---|---|
| **D-1** | **Watch work is watchOS only.** Items 2–4 are built for watchOS. The data they add goes into the shared watch↔phone format, so the Wear OS cloning job named in the 2026-09-21 watch shipping plan inherits it. This keeps that plan's decision to prove the Apple path on hardware first. | Owner, 2026-09-24 |
| **D-2** | **Indoor vs outdoor is decided by the exercise, with a no-fix fallback.** Machine cardio (Treadmill Run, Stationary Bike, Elliptical, the ergs) is indoor and takes the platform's distance estimate. Everything else is outdoor and uses GPS. An outdoor effort with no GPS fix at all uses the estimate instead, labelled "est.". No extra tap for the user. | Owner, 2026-09-24 |
| **D-3** | **No exceptions: the kind of effort logged decides the modality.** Sets → Resistance, holds → Isometric, rounds → Sports, timed → Cardio, whatever the exercise. This is the existing app-wide rule, unchanged. Visible consequence, accepted: a Plank logged as timed (declared timed by a routine, or logged with time in Free Training) appears under Cardio with its duration and adds to Cardio time and load. A timed effort inside a lifting session also counts as Cardio. (Owner clarification 2026-09-24; replaces an earlier exercise-based exception.) | Owner, 2026-09-24 |
| **D-4** | **The effort rating is the existing feeling prompt, redefined.** Same sheet, same moment, same five numbered tiles, same must-answer behavior (no per-session skip), same stored answer, same toggle (relabelled). The title becomes "How hard was this session?", and the end labels "Very easy" (under 1) and "Max effort" (under 5) replace "Rough" and "Great". There are no per-number words: they were tried before and didn't fit the tile row. | Owner, 2026-09-24 |
| **D-5** | **Past feeling answers are effort ratings.** No conversion and no special logic: an answer stored before the change is read as a rating on the same scale. **Known consequence, accepted deliberately:** a past "Great" (5) now reads as "Max effort" and a past "Rough" (1) as "Very easy". That applies to the calendar tint, the Session Summary, and the load history that the Mix layer and the signals use as their baseline. Users with survey history get load mode immediately. Reversing this later means leaving ratings recorded before the redefinition date out of load. | Owner, 2026-09-24 |
| **D-6** | **The rating can be added or changed from the Session Summary.** This works on the post-workout Summary and on a past session's Summary opened from the calendar. It covers sessions finished with the setting off, sessions finished on the watch, and any past session. | Owner, 2026-09-24 |
| **D-7** | **Colors: a one-color intensity ramp** in the theme's accent, faintest at 1 and full strength at 5. Used on the prompt's tiles and the calendar border. It reads as "more", never as good or bad. Every step must pass the palette legibility contract on every theme. | Owner, 2026-09-24 |
| **D-8** | **Sets get the remainder of the session's time.** Session duration minus the measured time of timed, hold and round efforts is the Resistance share. The dominant-modality rule is only a fallback for when that can't be determined. | Owner, 2026-09-24 |
| **D-9** | **Rolling sessions count measured time only.** Sets in a rolling session add no time and no load. A rolling session with only lifting therefore counts as zero time and zero load. It still appears in the Instruments list and Progression Rate, which don't use time. | Owner, 2026-09-24 |
| **D-10** | **The watch prompt follows the phone's setting.** When the setting is on, the watch asks at session end, and the question must be answered, as on the phone. When it's off, the watch never asks. The watch learns the setting at sync. Sync is started by the user from the watch, so a change on the phone reaches the watch at the next sync. | Owner, 2026-09-24 |
| **D-11** | **Distance correction uses the existing edit-session flow,** which opens from the session's Summary. Editing a timed effort's distance there makes it "entered by the user". | Claude default — vetoable |
| **D-12** | **The shared chart view is called "Exercise Progress",** not "Exercise Detail". The app already has an "Exercise Details" page: the read-only info page opened from the exercise picker and the library. Two views with the same name and different content would confuse. | Claude default — vetoable |
| **D-13** | **Documentation follow-through.** Reconcile the Stats doc, which still describes the Records, Volume Trends and Consistency sections deleted in August and omits Isometric and Sports. Remove the Session Summary doc's claim that the survey sheet has a close/skip control; it never had one. Add the app-philosophy note from the standing rules. | Claude |
| **D-14** | **Storage.** The redefined rating keeps using the survey's existing stored answer; no migration. The separate, never-written 1–10 session effort field stays unused. | Claude (follows from D-4/D-5) |
| **D-15** | **How an effort was tracked decides its modality; the exercise doesn't.** A session started from a modality tile gives every exercise that tile's kind of effort, so an Interval Run tracked in a Sports session counts as Sports, in a Cardio session as Cardio, and as sets in a lifting session as Resistance. In Free Training, the metric the user picks decides. Same rule as D-3, no exceptions. (Resolves the former O-1.) | Owner, 2026-09-24 |

## Open items

| ID | Question | Proposed answer | Blocks |
|---|---|---|---|
| **O-2** | **On-device verification of the watch items.** The watch's sensors aren't connected to the platform yet; that waits on creating the watchOS app target in Xcode, a manual step described in `docs/watch-app-setup-and-qa.md`. Items 2–4 can be built and unit-tested now, but heart rate, steps and the platform distance estimate can only be seen working on a real watch after that step. | Decide whether the watch release waits for on-device verification of items 2–4. | Watch release, not the build work |

## Revision notes (2026-09-24)

What revision 1 assumed that the codebase contradicts, and what that changed in this pack:

- **Stats already shows Isometric and Sports.** They were added in the August Stats remediation as top-2 duration trends, alongside the top 3 lifts and the top 2 cardio exercises. Revision 1 said they didn't appear at all. The case for the redesign still stands, because fixed top-N slots hide every other exercise. The Overview and item 5 are reworded.
- **Records, Volume Trends and Consistency are already gone.** They were deleted in August. The Stats doc still describes them (D-13).
- **Recent PRs lives inside the Strength section** today, not as a section of its own. Item 6 moves it to Records & Trends unchanged.
- **The feeling survey has no per-session skip.** Once the sheet opens, it must be answered; the settings toggle is the only way not to be asked. The Session Summary doc claims an "explicit close affordance" that the code doesn't have, and revision 1 carried that claim over. The owner kept the must-answer behavior (D-4).
- **Changing a past session's rating needs only a new control.** The survey's stored answer can already be saved for any session, but no screen offers it after the first prompt, and the historical Summary never shows the prompt at all. (The unused 1–10 effort field, by contrast, can only be saved while its session is open; D-14 leaves it unused.)
- **Heart rate doesn't reach the phone.** The watch records heart rate and GPS during a session, but heart rate is used only for the live readout. It isn't part of what the watch sends the phone, and the raw readings are deleted once a session has synced. Steps aren't captured anywhere. Item 3 is rewritten around this.
- **The watch has no indoor/outdoor notion.** GPS turns on for every Cardio and Sports session regardless of exercise, and no platform distance estimate is collected (D-2).
- **Sets record no duration.** Timed efforts, holds and rounds record start and stop times; sets record reps and weight only (D-8).
- **Rolling sessions have no meaningful duration.** They are already left out of the Total Time figure (D-9).
- **Sessions started from a modality tile give every exercise that tile's effort kind.** Free Training and routines can choose otherwise. That is how a Plank becomes a timed effort (D-3) and an Interval Run a round effort (D-15).
- **The watch's sensors aren't connected to the platform yet** (O-2).

---

## Tier 1 — Capture Now (ships with watch v1)

Small, data-shape items that must be recorded from the first watch session onward. They have low visible payoff on their own, but they gate every load-based and efficiency-based signal in Tier 3.

---

### 1. ⚑ Session Effort Rating Redefines "How Did It Feel" (phone)

**Overview**

The post-session survey currently asks how the session felt, from Rough to Great. That is a wellbeing reading, not an effort reading: a brutal session can feel great. It feeds one passive chart and nothing else. The redesign needs a single number that makes a BJJ session, a heavy squat day, a tempo run and a mobility session comparable. The sports-science standard for this is session effort rating × duration.

This item keeps the survey exactly as it works today: the same moment, the same five numbered tiles, the same must-answer sheet, the same settings toggle. It changes what the survey asks, how hard the session was from 1 (Very easy) to 5 (Max effort), and how it's colored (D-4, D-7). Answers already recorded are read as effort ratings on the same scale, with no conversion (D-5). The one new capability is adding or changing the rating afterwards from the Session Summary (D-6). Ship this as early as possible, so every new answer carries the new meaning.

The calendar's per-session border tint, which currently reflects feeling, becomes an effort tint on a one-color intensity ramp. That turns the calendar into a weekly intensity map at no extra cost.

**Copilot Prompt**

```markdown
Redefine the post-workout "How did it feel" survey as a session effort rating. Keep the survey's
mechanics exactly as they are. Change what it asks, how it is labelled and colored, and add a
way to add or change the answer afterwards.

What the user experiences:
- At the same point where the feeling prompt appears today (on the Session Summary, after a
  session is completed), the same sheet asks "How hard was this session?".
- The same five numbered tiles, 1 to 5. The end labels read "Very easy" under 1 and "Max effort"
  under 5, replacing "Rough" and "Great". Do not add a word under every number: that was tried
  before and didn't fit the tile row.
- Unchanged: one tap records the answer and closes the sheet; the sheet can't be dismissed
  without choosing; it appears at most once per session; it doesn't appear for a session that
  already has an answer.
- The rating is shown on the Session Summary, and it can be added or changed there. This works
  on the post-workout Summary and on a past session's Summary opened from the calendar.

Colors:
- The tiles and the calendar border use a one-color intensity ramp in the theme's accent:
  1 is the faintest step and 5 is full strength. The ramp reads as "more", never as good or bad.
- Every step must stay legible on every theme.

Settings:
- The existing post-workout survey toggle controls the effort prompt. Relabel it to describe the
  effort rating. Preserve each user's current on/off choice through the change.

Calendar:
- The per-session border tint in the day session list shows the session's rating on the
  intensity ramp. Sessions with no rating show no tint.

Stats:
- Remove the "HOW DID IT FEEL" section from the Stats screen.

Historical data:
- Answers recorded before this change are effort ratings from now on: the same value, no
  conversion and no special handling. They appear on the Summary and in the calendar tint like
  any new rating, and they can be changed from the Summary.

Documentation:
- Update the Session Summary, Calendar, Settings and Stats documentation to describe the effort
  rating. Remove the Session Summary documentation's claim that the sheet has a close or skip
  control; it has never had one.

Why: the effort rating × session duration becomes the app's cross-modality training load, which
powers the new Stats mix layer and several upcoming signals. The feeling score cannot serve that
purpose.

Out of scope:
- Any load calculation, Stats mix display or signal (later items).
- The watch-side rating prompt (separate item).
- A per-session skip. The settings toggle remains the only way not to be asked.
- Per-exercise or per-set effort ratings; this is one rating per session.
```

**Acceptance Criteria**

- On completing a session with the toggle on, the Session Summary shows the five-tile sheet titled "How hard was this session?", with "Very easy" under 1 and "Max effort" under 5. The words "How did it feel", "Rough" and "Great" appear nowhere in the app.
- Selecting a value stores it on the session and closes the sheet; the Session Summary then displays the chosen value.
- The sheet can't be dismissed without a choice, and it doesn't reappear for a session that already has a rating.
- A session with no rating (for example, finished with the toggle off) offers a way to add one on its Session Summary. Adding one stores it.
- Changing the rating from the Session Summary replaces the stored value, and reopening the summary shows the new value. This also works for a past session opened from the calendar.
- With the toggle off, no prompt appears. A user who had the feeling survey turned off before the update still has the effort prompt turned off after it, and vice versa.
- In the calendar day session list, a session rated 1 and a session rated 5 show visibly different strengths of the same color; an unrated session shows no tint. Every step passes the legibility contract on every theme.
- A session answered 5 before the update shows a rating of 5 after the update, and its stored value is unchanged.
- The Stats screen no longer contains a HOW DID IT FEEL section.

**Unit Tests Required**

- **Update** the Session Summary survey-sheet tests (the sheet appears after the first frame, cannot be dismissed without a choice, doesn't reappear once set, respects the toggle) for the new title and end labels. The behavior they assert is unchanged.
- **Retire** the feeling-trend tests in `test/stats_progress_test.dart`, including its window-coupling and empty-state cases. They test a Stats section that no longer exists.
- **Update** tests that assert the feeling color palette on the survey tiles and the calendar border tint so they assert the intensity ramp. Every ramp step must be covered by `test/palette_legibility_contract_test.dart` on every theme; never relax a failing contrast assertion to fit a value.
- **Update** `test/settings_state_test.dart` to cover the relabelled toggle and preservation of each user's existing value.
- **Add** a test that adding and changing the rating from the Session Summary persists and survives reload, for the session just finished and for a past session opened from the calendar.
- **Add** a test that an answer stored before the change is read back unchanged as the session's effort rating (no migration, no conversion).

---

### 2. ⚑ Watch: Effort Rating at Session End (watchOS)

**Overview**

Sessions completed on the watch, especially runs and sports sessions where the phone stays in a bag, would otherwise never get an effort rating. That leaves holes in exactly the modalities where cross-modality load matters most. Apple's own Workout app and Garmin both ask for perceived effort at the end of an activity, so users already expect this moment.

The rating is captured at session end on whichever device ends the session. The watch appends it as part of completing the session; it is new data, not an edit. The phone remains authoritative and can change the rating afterwards. The watch asks only when the phone's setting is on, and then the question must be answered, exactly as on the phone (D-10). This item is watchOS only; the rating travels in the shared watch↔phone format, so the Wear OS cloning job inherits it (D-1).

**Copilot Prompt**

```markdown
Add the session effort rating prompt to the watchOS app. Wear OS is not part of this item: the
rating travels in the shared watch↔phone format, so the later Wear OS cloning job inherits it.

What the user experiences:
- When the user ends a session on the watch and the phone's effort-rating setting is on, they
  are asked "How hard was this session?" on the same 1–5 scale used on the phone, with
  "Very easy" at 1 and "Max effort" at 5.
- Choosing takes one interaction using the platform's natural input: turn the crown (or scroll)
  to a number, then confirm.
- As on the phone, the prompt must be answered once it appears. When the setting is off, the
  watch never asks.

Rules:
- The rating is recorded as part of completing the session on the watch. The watch never
  modifies a rating that already exists.
- When a session is mirrored live between phone and watch, the prompt appears only on the device
  that ended the session. The other device does not prompt.
- If the watch is disconnected, the rating is kept with the session and arrives on the phone
  with the rest of the session data.
- The phone can change or add the rating afterwards from the Session Summary. The phone's value
  is final.
- The watch learns the setting from the phone when it syncs. Sync is started by the user from
  the watch, so a change made on the phone reaches the watch at the next sync.

Why: without watch-side capture, watch-only sessions have no effort rating, and cross-modality
load would be missing exactly for runs and sports sessions.

Out of scope:
- Wear OS (inherited by the Wear OS cloning job).
- Showing ratings, history or any stats on the watch.
- Changing an existing rating from the watch.
- Any load calculation.
```

**Acceptance Criteria**

- With the setting on, ending a session on the watch shows the 1–5 prompt with "Very easy" at 1 and "Max effort" at 5, and the prompt can't be closed without a choice.
- A rating chosen on the watch appears on the phone's Session Summary for that session after sync.
- With the setting off (as of the last sync), the watch doesn't prompt, and the phone's Session Summary offers to add a rating.
- For a session mirrored live, ending it on the watch prompts only on the watch, and ending it on the phone prompts only on the phone.
- A session ended on a disconnected watch and synced later arrives on the phone with its rating intact.
- After the phone changes a watch-set rating, the phone value persists through later syncs.

**Unit Tests Required**

- **Add** watchOS tests that completing a session with the setting on records the rating with the session, and that with the setting off there is no prompt and no rating.
- **Add** a test that the prompt appears only on the ending device for mirrored sessions.
- **Add** a sync test that a rating captured while disconnected arrives intact.
- **Add** a test that a phone-side change to the rating is not overwritten by a later watch sync (append-only rule).
- **Add** a test that the setting reaches the watch with a sync and is honored from then on.
- **Update** the shared protocol schemas and fixtures so every client validates the rating, and any existing watch session-completion tests that assume completion has no follow-up prompt.

---

### 3. ⚑ Watch: Per-Effort Heart Rate Summary and Step Capture (watchOS)

**Overview**

The watch records heart rate and GPS during a session, but heart rate is only used for the live readout. It isn't part of what the watch sends the phone, and the raw readings are deleted once a session has synced. Steps aren't captured at all. For Stats to use them, the phone needs heart-rate summaries attached to each effort (each run, each round, each block of sets), not only to the session as a whole. Steps are needed for timed efforts so indoor cardio has a native, exact metric: cadence (steps per minute).

This unlocks three things:

- **Outdoor cardio efficiency:** pace at a given heart rate.
- **Sports intensity:** average heart rate per round.
- **Indoor cardio:** cadence.

These summaries must be captured from the first watch release. Changing what the watch records after release means a data migration, and it means the first months of watch data can't be used.

Heart rate is enrichment, not the load measure: it only exists when the watch is worn. The effort rating remains the universal load measure.

The watch's sensors aren't connected to the platform yet; that waits on creating the watchOS app target in Xcode. This item can be built and unit-tested now, but seeing it work on a real watch waits for that step (O-2).

**Copilot Prompt**

```markdown
Extend what the watchOS app records and sends so the phone has heart-rate and step information
for each logged effort. Wear OS is not part of this item: the summaries travel in the shared
watch↔phone format, so the later Wear OS cloning job inherits them.

Today heart rate is recorded on the watch for the live readout only. It is not sent to the phone,
and the raw readings are deleted once the session has synced. Steps are not recorded.

What must be available on the phone for every watch-recorded session:
- Session level: average and maximum heart rate for the whole session.
- Each timed effort (runs, rides, cardio): average and maximum heart rate over the effort's
  active time, plus total steps where the platform provides them.
- Each round in a round-based effort (sports): average and maximum heart rate for that round.
- Each hold or set-based effort: average and maximum heart rate over the effort's active span.

Rules:
- Summaries are computed on the watch from the raw readings before those readings are deleted.
- Summaries follow the existing append-only rule. They arrive with the effort they belong to,
  and the watch never rewrites them afterwards.
- Heart rate is optional everywhere. Sessions logged without a watch, or while the sensor had no
  reading, simply have no heart-rate summary. Nothing in the app may treat missing heart rate as
  zero.
- Steps are recorded only for timed efforts. Cadence (steps per minute of active time) is the
  derived figure the app will display.
- Existing heart-rate and GPS recording behavior, and the platform health write of completed
  sessions, must not regress.

Why: Stats will use per-effort heart rate for cardio efficiency and sports intensity, and steps
for indoor cadence. Capturing this before the watch ships avoids a data migration and avoids
losing the first months of data.

Out of scope:
- Wear OS (inherited by the Wear OS cloning job).
- Any display of these values on the phone (later items).
- Heart-rate zones, heart-rate-based load or training-effect scores.
- Using heart rate for anything the effort rating is meant to cover.
```

**Acceptance Criteria**

- After a watch session containing a run, a three-round sports effort and a block of sets syncs, the phone has:
  - a session average and maximum heart rate;
  - an average and maximum for the run;
  - an average and maximum for each of the three rounds;
  - an average and maximum for the set block.
- The synced run also has a step total. The sports and set efforts have no step total.
- A session with the heart-rate sensor unavailable for its whole duration syncs with no heart-rate summaries and no zero values.
- A phone-only session has no heart-rate or step data, and every existing phone screen renders it exactly as before.
- The summaries are still on the phone after the watch has deleted the session's raw readings.
- Existing live heart-rate display, GPS recording and platform health write behave as they did before this change.

**Unit Tests Required**

- **Add** tests that per-effort and per-round averages and maximums are computed only from samples inside that effort's or round's active time, including a paused round (paused time excluded).
- **Add** a test that an effort with no samples produces no summary rather than zero.
- **Add** a test that steps are attached only to timed efforts.
- **Add** a test that summaries are computed before the raw readings are deleted, so deleting them loses nothing.
- **Add** a sync test that summaries arrive with their efforts and are not rewritten by later syncs.
- **Update** the shared protocol schemas and fixtures, and any existing watch sync and serialization tests whose payload expectations don't include the new summaries.

---

### 4. ⚑ Distance Source: Measured vs Estimated, with Post-Session Correction

**Overview**

Indoor cardio has no GPS. The watch platforms estimate indoor distance from motion and steps. Apple calibrates against the user's outdoor GPS runs, and Garmin asks users to confirm treadmill distance afterwards. Those estimates are useful but not precise, commonly off by 5–10%. Stride length also shrinks with fatigue, which is exactly what the cardio efficiency signal is meant to detect. Estimated distance must therefore be shown, but clearly labelled, and kept out of any precision-sensitive comparison.

Today the watch has no notion of indoor or outdoor: GPS turns on for every Cardio and Sports session, and no platform estimate is collected. This item decides indoor and outdoor by the exercise (D-2), records where each distance came from (GPS, entered by the user, or device-estimated), labels estimated values everywhere, and lets the user correct a distance on the phone from the treadmill display. A corrected distance becomes measured. The user never has to enter anything. It has to be in place from the first watch release, or the app can't tell later which historical distances were estimates.

**Copilot Prompt**

```markdown
Record where every cardio distance came from, label estimates, and let the user correct a
distance after the session on the phone. Watch changes are for watchOS only; the distance source
travels in the shared watch↔phone format, so the later Wear OS cloning job inherits it.

Distance sources:
- GPS: recorded by the watch outdoors. Measured.
- Entered by the user: typed or corrected on the phone, during or after the session. Measured.
- Device-estimated: the watch platform's own distance estimate. Estimated.

Indoor and outdoor:
- Decided by the exercise. Treadmill Run, Stationary Bike, the Elliptical exercises, the rowing
  and ski ergs, and similar machine cardio are indoor. Every other distance exercise, including
  every custom exercise, is outdoor.
- Indoor efforts take the platform's distance estimate, never GPS.
- Outdoor efforts use GPS. An outdoor effort that never gets a GPS fix takes the platform's
  estimate instead.
- The user is never asked whether an effort is indoor or outdoor.

What changes:
- The watch records the platform's distance estimate where the rules above call for it. The app
  does not build its own stride model.
- Everywhere a distance or a pace derived from it appears, an estimated value carries a clear
  "est." marker. This covers the Session Summary, session and calendar detail, and every Stats
  surface.
- On the phone, the user can correct the distance of a timed effort after the session, through
  the existing session edit flow opened from that session's Summary. The corrected value becomes
  "entered by the user" and replaces the estimate everywhere. Pace updates accordingly.
- The watch never changes a distance; correction happens only on the phone.
- Existing distances logged on the phone count as entered by the user.

Why: estimated indoor distance is useful to show but too imprecise, and too sensitive to
fatigue, to compare efficiency over time. The app must know which distances are trustworthy.

Out of scope:
- Wear OS (inherited by the Wear OS cloning job).
- An indoor/outdoor question for the user, or an indoor flag the user can set on an exercise.
- A phone-side step or stride estimate for phone-only sessions.
- Calibration flows, calibration settings or stride-length settings.
- Correcting any other metric (duration, heart rate, steps).
```

**Acceptance Criteria**

- An outdoor run recorded on the watch shows its distance and pace without an "est." marker.
- A Treadmill Run recorded on the watch takes its distance from the platform estimate, not GPS, and shows its distance and pace with an "est." marker on the Session Summary, in the calendar detail and in Stats.
- An outdoor run that never got a GPS fix shows the platform's estimate with an "est." marker.
- Correcting that treadmill run's distance through the session edit flow removes the "est." marker, and the pace shown everywhere reflects the corrected distance.
- A run logged on the phone with a typed distance shows no "est." marker, including runs logged before this change.
- There is no way to correct a distance on the watch.
- An indoor effort for which the platform provided no estimate shows duration and cadence, with no distance and no pace.

**Unit Tests Required**

- **Add** tests that indoor and outdoor are decided by the exercise: a catalog machine-cardio exercise is indoor, a catalog outdoor exercise is outdoor, and a custom exercise is outdoor.
- **Add** tests that each distance source is assigned correctly for outdoor watch efforts, outdoor efforts with no GPS fix, indoor watch efforts and phone-entered efforts, including historical phone data.
- **Add** a test that correcting a distance changes its source to user-entered and that pace is recalculated from the new value.
- **Add** display tests that the "est." marker appears only for device-estimated values on each surface listed.
- **Update** existing pace and distance tests in `test/stats_progress_test.dart` and the Session Summary tests that assume every distance is equally trustworthy.
- **Add** a test that a sync after a phone-side correction doesn't restore the estimate.

---

## Tier 2 — Stats Foundation

This tier builds the new screen structure. Items 5 and 6 must ship together, because the Instruments layer replaces the old Strength, Cardio, Isometric, Sports and Nutrition sections, and Records & Trends is where their full-history depth moves. Item 7 works on day one: users with survey history have ratings already (D-5), and everyone else starts on time share and switches to load once ratings accumulate. Item 8 is the container every Tier 3 card plugs into.

---

### 5. Instruments Layer: Native Metric per Effort Kind, Plus a Fuel Row

**Overview**

Today Stats shows the top 3 lifts and the top 2 each of cardio, isometric and sports exercises as charts. Everything outside those slots is invisible, so a user training eight lifts, a BJJ player with several drills, or a mobility-focused user with a long list of holds opens Stats and doesn't find most of their own training. This item replaces the chart wall with a dense instrument list covering every exercise trained in the current window.

The list is grouped into Resistance, Cardio, Isometric and Sports. Each row shows the exercise's native metric, its change against that exercise's own recent history, and a small trend line. The full chart moves one tap away, into an Exercise Progress view shared with Records & Trends (D-12). This mirrors how tracking works: the same exercise identity, measured the way its effort kind is measured.

A **Fuel** row joins the list because nutrition is logged in the same app and relates directly to training. It shows 7-day average calories and protein against the user's own target (if set) and the prior week, how many days were logged, and training-day versus rest-day intake. Logging coverage is shown next to the numbers because an under-logged day looks exactly like an under-eaten one.

**Copilot Prompt**

```markdown
Replace the Strength, Cardio, Isometric, Sports and Nutrition chart sections on the Stats screen
with an Instruments list, and add a shared Exercise Progress view.

Instruments list:
- Grouped into four sections: Resistance, Cardio, Isometric, Sports.
- Which section an exercise appears in is decided by what was logged (the effort kind), not by
  which tile started the session:
  - sets → Resistance;
  - timed efforts → Cardio;
  - holds → Isometric;
  - rounds → Sports.
  There are no exceptions by exercise: a Plank logged as a timed effort appears under Cardio
  with its duration.
- A section appears only if the user trained that modality in the current window. Sections are
  ordered by their share of the user's training in the window, largest first.
- Each section lists exercises trained in the current window, most frequently trained first.
  Show up to 5, with "Show all (n)" to expand the rest.
- The existing window chip and window rule (active training period, otherwise the most recent
  14 training days) decide which exercises are listed.

Each row shows: exercise name, current value of its native metric, change versus that
exercise's own previous comparable value (arrow + amount), and a small trend line of its
recent values. Native metrics:
- Resistance, weighted exercises: best estimated 1RM. Bodyweight exercises: best reps, with any
  added weight noted. Keep the existing rule for classifying exercises as weighted or bodyweight
  unchanged.
- Cardio: pace when a distance exists, otherwise duration.
  - Add cadence when steps exist, and average heart rate when available.
  - Estimated distances and paces carry the "est." marker.
- Isometric: longest single hold, with total hold time as the secondary figure. Any added
  weight is noted.
- Sports: rounds completed and total round-minutes, with average heart rate per round when
  available.

Fuel row (its own section, after the training sections):
- 7-day average daily calories and protein, compared with the user's own daily target when one
  is set, and with the previous 7 days.
- A logged-days indicator (e.g., "5/7 days logged"). Averages count logged days only.
- Average intake on training days versus rest days.
- Hidden when no food has been logged in the last 14 days.

Exercise Progress (shared view, also used by Records & Trends):
- Tapping any row opens that exercise's full-history chart of its native metric, its all-time
  best on that metric, and a list of recent sessions with their values.
- Name it "Exercise Progress". The app already has an "Exercise Details" page (the read-only
  info page in the exercise picker and library); this view is separate and must not reuse that
  name.
- Tapping the Fuel row opens the existing full-history nutrition trend, keeping its Calories /
  Macros toggle.

Why: every modality the app tracks should be visible in Stats in its own terms, and the screen
should read as dense instruments rather than a stack of charts.

Out of scope:
- The Mix layer and Signals (separate items).
- Records & Trends itself (separate item, ships together with this one).
- Any change to how personal records are defined or detected.
- Nutrition recommendations or new nutrition targets.
- A time-range selector.
```

**Acceptance Criteria**

- A user whose window contains squats, a treadmill run, a plank and a BJJ session sees four sections: squats under Resistance with an e1RM value, the run under Cardio with pace marked "est." and a cadence value, the plank under Isometric with a longest hold, and BJJ under Sports with rounds and round-minutes.
- A set effort logged in a Free Training session appears under Resistance.
- A Plank logged as a timed effort (from a routine or in Free Training) appears under Cardio with its duration; a Plank logged as a hold appears under Isometric.
- A timed effort inside a lifting session (such as a routine's timed treadmill warm-up) appears under Cardio, and an Interval Run tracked in a Sports session appears under Sports.
- A user who only lifts sees only the Resistance section (plus Fuel, if food was logged).
- A section with 8 exercises shows 5 rows and a "Show all (8)" control that reveals the other 3.
- Each row's change indicator compares against that exercise's own previous comparable value. An exercise's first-ever appearance shows no change indicator.
- Tapping a row opens Exercise Progress with a full-history chart covering sessions older than the current window.
- The Fuel row shows the logged-days count. With food logged on 3 of the last 7 days, the averages are computed over those 3 days only.
- With a protein target set, the Fuel row shows protein against that target. With none set, it shows protein against the previous 7 days only.
- The Strength, Cardio, Isometric, Sports and Nutrition chart sections no longer appear on the main Stats screen.
- Exercises that don't make the old top-N limits now appear as rows.

**Unit Tests Required**

- **Update or retire** the top-N selection tests in `test/stats_progress_test.dart` that assert the old limits (top 3 lifts; top 2 cardio, isometric and sports). The new rule is every exercise in the window, capped at 5 per section with expansion.
- **Keep** the weighted/bodyweight classification tests unchanged; they must still pass.
- **Add** tests assigning sections by effort kind, including Free Training, a timed effort inside a lifting session (Cardio) and a timed Plank (Cardio).
- **Add** native-metric tests for holds (longest hold, total hold time) and rounds (rounds completed, round-minutes).
- **Add** change-indicator tests covering the first appearance (no indicator) and comparison against the exercise's own previous value.
- **Add** Fuel tests covering logged-days-only averaging, target versus no-target comparison, training-day versus rest-day split, and hiding after 14 days without logs.
- **Update** Stats screen widget tests that look for the old section headers (STRENGTH, CARDIO, ISOMETRIC, SPORTS, NUTRITION).

---

### 6. Records & Trends (Header Entry, Replaces the Old Screen)

**Overview**

The current Stats screen isn't useless. Its full-history charts, Recent PRs and all-time totals are genuinely valued by some users. Its weaknesses were the automatic top-N selection and having all of it on the main screen at once. Keeping the old screen as a second, parallel Stats screen would mean two mental models and every chart maintained twice.

Instead, its valuable depth moves into **Records & Trends**, opened from an icon in the Stats header. It contains the all-time totals (Sessions, Time, Streak), the existing Recent PRs (today shown inside the Strength section), and a searchable list of every exercise the user has ever logged, grouped by modality. Each exercise opens the same Exercise Progress view the Instruments rows use. This follows the exercise-detail pattern familiar from Hevy: depth on demand, without cluttering the main view.

**Copilot Prompt**

```markdown
Add a Records & Trends screen, opened from an icon button in the Stats screen header, and
retire the old Stats layout.

Records & Trends contains:
- All-time totals: Sessions, Total Time, Streak, exactly as they behave today.
- Recent PRs: the existing all-time personal records list (today shown inside the Strength
  section), with the same definition, the same detection and the same display as today.
- A list of every exercise the user has ever logged, grouped by the same four sections as the
  Instruments list (Resistance, Cardio, Isometric, Sports) and assigned by the same rule,
  searchable by name.
  - Each entry shows the exercise's all-time best on its native metric and when it was last
    trained.
  - Tapping an entry opens the shared Exercise Progress view.

Rules:
- Records & Trends is all-time; the current window does not apply here.
- "All-time best" for holds, cardio and rounds is a descriptive best shown in this list and in
  Exercise Progress. It is not a personal record event: it doesn't trigger toasts or Session
  Summary PR rows. Only the existing PR definition does that.
- The in-workout PR toast, the Session Summary and Records & Trends must continue to agree on
  every PR.
- The header icon is the only entry point. It needs an accessible label.

Why: keep the depth that some users rely on, one tap away, without a second parallel Stats
screen and without cluttering the main Stats view.

Out of scope:
- Extending personal record events to holds, cardio or rounds.
- Filters, sorting options or date ranges beyond name search.
- Any change to the all-time totals.
```

**Acceptance Criteria**

- The Stats header shows an icon button that opens Records & Trends, and it has an accessible label.
- Records & Trends shows Sessions, Total Time and Streak with the same values the previous Stats screen showed for the same data.
- Recent PRs lists the same entries, in the same order, that the previous Stats screen showed for the same data.
- An exercise last trained a year ago appears in the exercise list and opens its Exercise Progress view.
- Searching a partial name filters the list to matching exercises.
- An exercise's longest-ever plank hold is shown as its all-time best, and setting a new longest hold triggers no PR toast or Session Summary PR row.
- A PR set during a workout appears identically on the toast, the Session Summary and Records & Trends.
- The previous Stats layout is no longer reachable from anywhere in the app.

**Unit Tests Required**

- **Keep unchanged:** the cross-surface PR parity guard tests (the toast ↔ Stats structural guard and the toast ↔ Summary ↔ Stats parity test in `test/in_session_pr_toast_test.dart` / `test/pr_toast_test.dart` and related summary tests). They must pass without modification.
- **Update** Recent PRs and all-time totals widget tests to target Records & Trends instead of the main Stats screen.
- **Add** tests for the all-time exercise list: grouping by effort kind (same rule as Instruments), all-time best per native metric, and name search.
- **Add** a test that descriptive bests for holds, cardio and rounds produce no PR events.
- **Update** navigation tests (`test/home_logo_hub_open_test.dart` and the hub interaction tests) only if they assert Stats screen content rather than the navigation itself. New screens follow the navigation contract enforced by `test/navigation_contract_enforcement_test.dart`.

---

### 7. Mix Layer: Training Load by Modality

**Overview**

The top of Stats should answer the question only a multi-modality app can answer: where did my training go? This layer shows how the current window's training splits across Resistance, Cardio, Isometric and Sports, each against the user's own usual split. Below that, a weekly strip shows the last 8 weeks of load stacked by modality, so a rising block, an easier week or a sports-heavy stretch is visible at a glance. The closest real-world reference is Garmin's Training Load Focus, which shows a load split against a band.

The layer uses session load (duration × effort rating). Users with survey history already have ratings (D-5); everyone else starts without them, so the layer must be useful before ratings exist. Until there are enough rated sessions, it shows the split by training time, clearly labelled as time. It switches to load once the baseline is ready, and shows progress toward that point. This layer also defines the load and baseline figures every Tier 3 card reuses, so all signals agree with what the user sees at the top of the screen.

**Copilot Prompt**

```markdown
Add a Mix layer at the top of the Stats screen showing how the user's training splits across
modalities, and establish session load as the app's cross-modality training measure.

Definitions (these become the single source for every future signal):
- Session load = session duration in minutes × session effort rating (1–5). A session without a
  rating has no load and counts as "unrated".
- An effort's modality follows the Instruments rule: sets → Resistance; holds → Isometric;
  rounds → Sports; timed efforts → Cardio. No exceptions.
- Time per modality within a session: timed, hold and round efforts contribute their measured
  active time to their own modality. Resistance gets the remainder: the session's duration minus
  all measured time, never below zero.
- When that split can't be determined (for example, the measured time exceeds the session's
  duration), the whole session goes to the dominant modality (the one with the most efforts),
  with ties resolved deterministically.
- A session's load is split across modalities in proportion to its time per modality.
- Rolling (all-day) sessions have no meaningful duration. Count only their measured time: their
  sets add no time and no load, and their load is measured time × rating.

What the user sees:
- A single horizontal split bar for the current window showing each modality's share, using the
  existing modality colors, with percentages.
- For each modality, a marker showing the user's usual share (their baseline: the 12 weeks
  before the current window). Show it only once the baseline is ready.
- A weekly strip for the last 8 weeks: one bar per week, stacked by modality, with the current
  week visibly marked as in progress.
- Measure used:
  - Load is used when the baseline period contains at least 4 weeks with rated sessions and at
    most a quarter of the window's training time is unrated.
  - Otherwise the layer shows the split by training time, with a visible "by time" label and a
    short note on progress toward the load baseline (e.g., "Load baseline: 2 of 4 weeks rated").
- A small count of unrated sessions in the window, when there are any.

Rules:
- Missing ratings are never estimated or filled in.
- The existing window chip applies to this layer.
- Units, colors and modality names follow existing app conventions.

Why: this is the one view single-sport apps cannot offer, and it defines the load figures that
every upcoming signal uses.

Out of scope:
- Any signal card, suggestion or warning (later items).
- Heart-rate-based load.
- Interactive drill-down from the bar or the strip.
- A time-range selector.
```

**Acceptance Criteria**

- A 60-minute session rated 4 contributes 240 load. A 60-minute session with no rating contributes no load and increases the unrated count by one.
- A 60-minute Free Training session with 20 minutes of measured holds and the rest spent on sets, rated 3 (180 load), contributes 40 minutes and 120 load to Resistance and 20 minutes and 60 load to Isometric.
- A 75-minute lifting session that includes a 15-minute timed treadmill warm-up contributes 60 minutes to Resistance and 15 minutes to Cardio.
- A session whose measured time exceeds its duration goes entirely to its dominant modality.
- A rolling session with 30 minutes of measured timed work and a number of sets, rated 4, contributes 30 minutes and 120 load to Cardio and nothing to Resistance. A rolling session with only sets contributes no time and no load.
- A user with no ratings sees the split bar labelled "by time" and a baseline progress note; no baseline markers are shown.
- A user with 4+ rated weeks in the baseline period and fewer than 25% unrated minutes in the window sees the split by load, with no "by time" label, plus baseline markers. This includes a user whose ratings are all survey answers given before the redefinition.
- The weekly strip shows exactly 8 weeks, stacked by modality, with the current week marked as in progress.
- A lifting-only user sees a single-color bar at 100% Resistance, and no empty modality segments.
- Changing the active training period changes the split bar and leaves the weekly strip covering the last 8 calendar weeks.

**Unit Tests Required**

- **Add** load calculation tests covering a rated session, an unrated session, zero duration, and each rating from 1 to 5.
- **Add** attribution tests covering the remainder rule for sets, the proportional load split, measured time exceeding the session's duration (dominant-modality fallback), and a tie in the dominant-modality count (resolved deterministically).
- **Add** rolling-session tests: measured time only, sets contribute nothing, a sets-only rolling session contributes nothing.
- **Add** tests for switching between time and load, at exactly 4 rated baseline weeks and at exactly 25% unrated time.
- **Add** baseline tests confirming the 12 weeks before the current window are used and that the current window is excluded from its own baseline.
- **Add** weekly strip tests covering 8 weeks, empty weeks shown as empty (not removed), and the in-progress current week.
- **Add** a test that this layer and the Instruments list place the same effort under the same modality, including a timed Plank.

---

### 8. Signals Framework

**Overview**

Signals are the interpretive layer: short cards that notice something the user wouldn't see by scanning numbers. They are only valuable if they are rare, correct and calm. This item builds the container and the rules every card follows, before any card ships.

The rules:

- At most two cards are visible.
- When both a caution and a positive qualify, one of each is shown, so the feature never reads as constant criticism.
- Every card states a measured observation with real numbers against the user's own history, plus at most one light suggestion phrased as an option.
- Cards appear only when their data-sufficiency conditions are met.
- A dismissed card stays away for 14 days.
- When nothing qualifies, the layer says so in one quiet line. On an instrument panel, "nothing outside your usual range" is itself a reading.

Signals live on the Stats screen only. The Home screen belongs to logging.

**Copilot Prompt**

```markdown
Build the Signals layer on the Stats screen, between the Mix layer and the Instruments list.
This item ships the container and its rules; individual signals are separate items that plug
into it.

What every signal card contains:
- A short title.
- One observation sentence with the user's actual numbers and the time span it covers.
- Optionally, one suggestion sentence phrased as an option, never as an instruction.
- A dismiss control.

Display rules:
- At most two cards are visible at a time.
- Each signal is either a caution or a positive. If both kinds qualify, show the
  highest-priority caution and the highest-priority positive. Otherwise show the two
  highest-priority cards of the kind that qualifies.
- Priority order: each signal item states its own priority, and the framework respects it.
- When no signal qualifies, show a single quiet line: "No signals — nothing outside your usual
  range."

Lifecycle rules:
- Signals are re-evaluated when a session is completed and when Stats is opened.
- A card disappears on its own as soon as its condition is no longer true.
- A dismissed card does not reappear for 14 days, even if its condition stays true. After that
  it may appear again.
- A signal appears only when its own data-sufficiency conditions are met. Missing data is never
  treated as zero.

Tone rules (apply to every signal, now and in future):
- Observations only, against the user's own history.
- No claims about causes, no references to past "successful" blocks or outcomes, and no medical
  language.
- Never suggest eating less and never state a calorie number.

Documentation:
- Update the Stats documentation to record that the earlier "no rest / deload / recovery
  suggestion" non-feature has been deliberately replaced by these signal rules.
- Add a note to the app philosophy documentation, next to its non-goals (a coaching-first
  experience, advanced predictive analytics), that signals are rule-based observations against
  the user's own history, not coaching.

Why: signals turn the Mix and Instruments data into insight, but only if they are rare, correct
and never nagging.

Out of scope:
- Any individual signal (separate items).
- Signals on the Home screen, notifications, or an insights history screen.
- Buttons that create sessions, edit the calendar or change plans from a card.
- Settings to mute signal types or tune thresholds.
```

**Acceptance Criteria**

- With three cautions and one positive qualifying, exactly two cards show: the top-priority caution and the positive.
- With three cautions and no positive, the two highest-priority cautions show.
- With nothing qualifying, the single "No signals" line shows, and no empty card placeholders.
- Dismissing a card removes it immediately. It doesn't return on the next session completion or the next Stats open within 14 days, even though its condition is still true.
- On day 15 after dismissal, with the condition still true, the card can show again.
- A card whose condition stops being true after a new session disappears the next time Stats is opened.
- No signal card, and nothing from the Signals layer, appears on the Home screen.
- Every card displays a time span in its observation sentence.

**Unit Tests Required**

- **Add** selection tests covering the caution + positive pairing, same-kind fallback, priority ordering and the maximum of two.
- **Add** lifecycle tests covering re-evaluation on session completion, auto-removal when the condition clears, and the 14-day dismissal cooldown at both boundaries (day 14 hidden, day 15 eligible).
- **Add** an empty-state test for the "No signals" line.
- **Add** a test using a stub signal that reports insufficient data; it must never be shown.
- **Add** a test that the Home screen renders no signal content.

---

## Tier 3 — Signals

Individual cards, ordered by how soon each has enough data to appear. Item 9 works from day one on existing data and should ship with the framework so the framework has a real first card. Items 10–14 need several weeks of effort ratings; users with survey history have those from day one (D-5). Item 15 needs watch heart-rate data and measured distances. All thresholds below are starting values, to be revisited once real data shows how often each card fires.

---

### 9. Progression Rate (Positive Signal)

**Overview**

For lifters, the clearest sign a block is working is how often each exercise matches or beats its last performance. This signal reports that rate over the last 4 weeks against the 4 weeks before, and appears only when it is both high and improving. It needs no new data: it runs entirely on logged sets, so it can appear from the first day the framework ships. It also gives the framework the positive card it needs to avoid feeling like constant criticism.

This is a progression measure, not a personal record measure. Matching the previous session counts as progress, while a PR requires strictly beating the all-time best. The two must not be confused or share rules.

**Copilot Prompt**

```markdown
Add a positive signal: Progression Rate.

Definition:
- For every Resistance exercise performed in a session, compare that session's best on the
  exercise's native metric (estimated 1RM for weighted exercises, reps for bodyweight
  exercises) with the same exercise's previous session.
- Equal or better counts as a progression; worse counts as not. An exercise's first-ever session
  is not counted.
- Progression rate = progressions ÷ exercise-sessions counted.

When it appears:
- Compute the rate for the last 28 days and for the 28 days before that.
- Show when the recent rate is at least 75%, it improved by at least 10 percentage points,
  and each 28-day period contains at least 8 counted exercise-sessions.
- Kind: positive. Priority: the highest among positives.

Copy (numbers are the user's):
- Observation: "Resistance progression rate is 81% over the last 4 weeks, up from 62%."
- Suggestion: "The current approach is working."

Why: reinforce what is working with a measured, specific readout, and give the Signals layer its
first positive card from day one.

Out of scope:
- A negative variant (falling progression rate).
- Comparing against planned targets.
- Any change to personal record rules.
```

**Acceptance Criteria**

- A user with 20 counted exercise-sessions in each period, rates of 80% (recent) and 65% (prior), sees the card with "80%" and "65%".
- Rates of 80% and 75% (a 5-point improvement) show no card.
- A recent rate of 70% with a 20-point improvement shows no card.
- 7 counted exercise-sessions in either period show no card, whatever the rates.
- A session matching the previous session exactly counts as a progression.
- A bodyweight exercise is compared by reps and a weighted exercise by estimated 1RM, following the existing classification.
- An exercise's first-ever session is excluded from both the numerator and the denominator.

**Unit Tests Required**

- **Add** rate calculation tests covering an equal value (counts), a worse value (doesn't count), a first session (excluded), and mixed weighted and bodyweight exercises.
- **Add** threshold boundary tests: exactly 75%, exactly +10 points, exactly 8 exercise-sessions.
- **Add** a test that the progression comparison is independent of the PR comparison (a tie counts as progression but is not a PR).
- **Keep unchanged:** existing PR tests must pass without modification.

---

### 10. Modality Mix Shift (Caution)

**Overview**

This merges the original "resistance dominance" and "isometric collapse" ideas into one rule: a modality the user normally trains has shrunk to less than half its usual share of their load. It only fires for modalities the user genuinely trains, so a pure lifter is never told to do yoga. It names the modality that grew, which is usually the useful part.

**Copilot Prompt**

```markdown
Add a caution signal: Modality Mix Shift.

Definition:
- Use the load split and baseline defined for the Mix layer.
- A modality is "regularly trained" when its baseline share (the 12 weeks before the current
  28 days) is at least 10%.
- The signal fires when a regularly trained modality's share of load over the last 28 days has
  fallen to less than half of its baseline share.

When it appears:
- Only when the Mix layer is showing load (not time) for the same period.
- When more than one modality qualifies, report the one with the largest relative drop.
- Kind: caution. Priority: below Cross-Modality Interference and above Sustained High Load.

Copy (numbers are the user's):
- Observation: "Isometric is 4% of your load over the last 4 weeks, down from its usual 12%.
  Resistance has grown to 68%."
- Suggestion: "An isometric session this week would bring your mix back toward usual."

Why: in a multi-modality app, drift in the mix is the most basic imbalance worth surfacing, and
it must respect what each user actually trains.

Out of scope:
- Suggesting a modality the user doesn't regularly train.
- Targets or "ideal" mixes that don't come from the user's own history.
```

**Acceptance Criteria**

- A baseline isometric share of 12% and a recent share of 5% fire the card, naming Isometric and the modality with the largest recent share.
- A baseline isometric share of 12% and a recent share of 6% (exactly half) show no card.
- A baseline isometric share of 8% (not regularly trained) never fires, even if the recent share is 0%.
- When the Mix layer is showing "by time", this card doesn't appear.
- With two modalities qualifying, only the one with the larger relative drop is reported.

**Unit Tests Required**

- **Add** tests for the regularly-trained threshold (exactly 10%), the half-share boundary (exactly half doesn't fire), and choosing between two qualifying modalities.
- **Add** a test that the signal uses the same load and baseline figures as the Mix layer (shared source).
- **Add** a test that it is suppressed when the Mix layer is in time mode.

---

### 11. Cross-Modality Interference After Hard Sports Sessions (Caution)

**Overview**

This is the signal only OmniTrain can produce, because Strong and Hevy never see the sports session. It merges the original "post-sports interference" and "sports crowding" ideas: after hard sports sessions, does the next lifting day consistently come in below the user's usual performance on the same lifts?

Comparing raw volume would mislead, because the day after BJJ might just be arm day. The signal therefore compares each lift against its own recent level. It needs a pattern (3 qualifying cases in the last 45 days), not a single bad day.

**Copilot Prompt**

```markdown
Add a caution signal: Interference After Hard Sports Sessions.

Definitions:
- Hard sports session: a sports session whose load is in the user's top 25% of rated sports
  sessions over the last 90 days. At least 8 rated sports sessions are required in that 90-day
  period before anything can be classified as hard.
- Follow-up resistance session: the first session with Resistance efforts that starts within 36
  hours after a hard sports session ends.
- Performance dip: across the exercises in the follow-up session, compare each exercise's best
  on its native metric with that exercise's own average over the prior 28 days. The average
  excludes other follow-up sessions. The session dips when these exercises average at least 10%
  below their own recent level.

When it appears:
- At least 3 dipped follow-up sessions in the last 45 days.
- Kind: caution. Priority: the highest among cautions.
- When sports load over the last 21 days is at least 30% higher than the 21 days before, add
  that fact as a second observation sentence.

Copy (numbers are the user's):
- Observation: "After 3 of your last 4 hard sports sessions, your next lifting day came in
  11–16% below your usual on the same lifts."
- Optional second observation: "Sports load is up 38% over the last 3 weeks."
- Suggestion: "A lighter or isometric-focused day after hard sports sessions is one option."

Why: how training in one modality affects another is the core insight a multi-modality app can
offer.

Out of scope:
- Recommending specific sports-to-lifting gaps or schedules.
- Classifying hard sessions by heart rate.
- Any calendar or planning action.
```

**Acceptance Criteria**

- A user with 3 dipped follow-up sessions in the last 45 days, and at least 8 rated sports sessions in the last 90, sees the card with the actual count and dip range.
- With 2 dipped follow-ups in 45 days, no card appears.
- A resistance session starting 37 hours after a hard sports session is not treated as a follow-up.
- A follow-up session whose exercises average 9% below their own recent level is not a dip.
- A user with 7 rated sports sessions in the last 90 days never sees this card.
- A follow-up session containing only exercises never trained before is excluded, not counted as a dip.
- The second observation sentence appears only when sports load rose at least 30% over the last 21 days.

**Unit Tests Required**

- **Add** tests for hard-session classification covering the top-25% boundary, the minimum of 8 rated sessions, and unrated sports sessions (never hard).
- **Add** tests for follow-up detection covering the 36-hour boundary on both sides and the first session only.
- **Add** dip tests covering the per-exercise comparison against its own average, excluding other follow-ups from that average, the 10% boundary, and exercises with no history.
- **Add** pattern tests covering exactly 3 in 45 days and a case that falls outside the window.
- **Add** tests that the optional sports-load sentence is included and excluded correctly.

---

### 12. Fuel vs Load (Caution)

**Overview**

Nutrition is logged in the same app as training, which makes this cross-domain signal possible: training load has climbed for several weeks while intake hasn't moved. It is strictly observational and deliberately one-directional. It never suggests eating less, never names a calorie number, and has no reverse version. It only uses weeks where the user logged food consistently, because an under-logged week looks exactly like an under-eaten one.

**Copilot Prompt**

```markdown
Add a caution signal: Fuel vs Load.

Definition:
- Compare the last 3 weeks with the 3 weeks before.
- Training load uses the Mix layer definition.
- Intake is the average daily calories over logged days only.

When it appears:
- All 6 weeks are consistently logged (food logged on at least 5 of 7 days in each week).
- Load over the last 3 weeks is at least 20% higher than the previous 3 weeks.
- Average daily intake over the last 3 weeks is unchanged (within 5%) or lower.
- The Mix layer is showing load (not time) for these weeks.
- Kind: caution. Priority: below Modality Mix Shift.

Copy (numbers are the user's):
- Observation: "Training load is up 27% over the last 3 weeks; your average daily intake is
  unchanged."
- Suggestion: "Worth checking that intake is keeping up with training."

Hard rules:
- Never suggest eating less, never state a calorie amount or target, and never compare against
  anything other than the user's own logs.
- There is no reverse version (load down → eat less).

Why: training and fuel live in the same app; showing when they diverge is a genuine
cross-domain observation that single-purpose apps can't make.

Out of scope:
- Macro-level versions of this signal.
- Any suggestion involving specific amounts.
- Changes to nutrition targets.
```

**Acceptance Criteria**

- With all 6 weeks consistently logged, load up 25% and intake up 2%, the card shows with the user's load percentage.
- One of the 6 weeks logged on only 4 of 7 days shows no card, whatever the other figures.
- Load up 19% shows no card.
- Intake up 6% shows no card.
- No card text anywhere contains a calorie amount or suggests reducing intake.
- A user whose load dropped 30% while intake stayed flat sees no nutrition-related card.

**Unit Tests Required**

- **Add** tests for the consistent-logging gate (exactly 5 of 7 days passes, 4 of 7 fails in any single week).
- **Add** boundary tests for load (+20%) and intake (±5%).
- **Add** a test that intake averages count logged days only.
- **Add** a copy test that the rendered text contains no calorie number and no reduction wording.
- **Add** a test that the reverse direction never produces a card.

---

### 13. Protein Consistency (Caution)

**Overview**

Protein is the one nutrition figure that is safe to be specific about for people training for strength. This signal notices when average protein intake has fallen well below the user's own protein target, or below their own usual level if no target is set, over consistently logged days, while they keep training resistance. Where bodyweight is on file, the card expresses intake per kilogram of bodyweight, which is how the figure is usually discussed. It only points to a commonly cited reference when the user has no target of their own.

**Copilot Prompt**

```markdown
Add a caution signal: Protein Consistency.

Definition:
- Use the last 14 days that have food logged. At least 10 of the last 14 calendar days must be
  logged.
- Compare average daily protein over those logged days with the user's own daily protein target
  when one is set. Otherwise compare with the user's own average over the 8 weeks before
  (consistently logged weeks only).

When it appears:
- Average protein is at least 15% below the comparison figure.
- The user has at least 2 sessions with Resistance efforts in those 14 days.
- Kind: caution. Priority: below Fuel vs Load.

Copy:
- Observation, with a target set: "Protein has averaged 118 g/day over the last 2 weeks,
  about 20% under your 150 g target."
- Observation, without a target: "Protein has averaged 118 g/day over the last 2 weeks,
  down from your usual 145 g."
- When bodyweight is on file, add the per-kilogram figure (e.g., "1.3 g/kg") using the user's
  latest recorded bodyweight.
- Suggestion, with a target set: "Bringing protein back toward your target is one option."
- Suggestion, without a target: "Commonly cited guidance for strength training is around
  1.6 g/kg of bodyweight." Use this only when bodyweight is on file; otherwise omit the
  suggestion.

Hard rules:
- No calorie amounts or calorie suggestions.
- Protein amounts follow the user's unit conventions for nutrition.

Why: protein intake directly supports resistance training and is safe to be specific about;
this closes the loop between the Fuel row and training.

Out of scope:
- Creating or changing targets.
- Other macros.
- Meal timing.
```

**Acceptance Criteria**

- With a 150 g target, 12 of 14 days logged, a 120 g average and 3 resistance sessions, the card shows "under your 150 g target".
- With a 150 g target and a 130 g average (13% under), no card shows.
- With 9 of the last 14 days logged, no card shows.
- With no target, the comparison uses the user's own 8-week average and the copy says "down from your usual".
- With no target and a bodyweight on file, the card shows a g/kg figure and the 1.6 g/kg reference. With no target and no bodyweight, it shows neither the per-kg figure nor the reference.
- With a target set, the 1.6 g/kg reference never appears.
- With one resistance session in the 14 days, no card shows.

**Unit Tests Required**

- **Add** tests for target versus own-baseline comparison, including a target changed during the window (use the target stored for each day; targets are already saved by date).
- **Add** boundary tests for the logged-days gate (10 of 14) and the 15% threshold.
- **Add** tests that the per-kg figure uses the latest recorded bodyweight and is omitted when none is on file.
- **Add** copy tests: the reference appears only when there is no target and bodyweight is on file.
- **Add** a test for the resistance-session requirement.

---

### 14. Sustained High Load (Caution)

**Overview**

This replaces the original "missing deload" idea without its unsupported claims about past successful blocks. It observes that the user has put together 5 or more consecutive weeks well above their usual weekly load, without any easier week. If their own history shows a habit of easier weeks, it says so as a plain fact about their history, not as evidence of what worked. It depends on the longest stretch of rated history, so it becomes available last among the load-based signals.

**Copilot Prompt**

```markdown
Add a caution signal: Sustained High Load.

Definitions (using the Mix layer's load):
- Usual weekly load: the average weekly load over the 12 weeks before the streak being examined.
- Higher-load week: a completed week whose load is at least 110% of the usual weekly load.
- Easier week: a completed week whose load is at least 20% below the usual weekly load.

When it appears:
- The most recent 5 or more completed weeks are all higher-load weeks, with no easier week
  among them.
- At least 8 weeks of rated history exist before the streak.
- The Mix layer is showing load for this period.
- Kind: caution. Priority: below Protein Consistency.

History fact:
- When the user's earlier history shows easier weeks recurring at a regular interval (every 3–5
  weeks, at least twice), include it as a plain fact.

Copy (numbers are the user's):
- Observation: "You've had 6 consecutive weeks above your usual training load, with no easier
  week."
- Optional history fact: "Earlier in your history, you usually had an easier week every 4 weeks."
- Suggestion: "An easier week is one option."

Why: long runs of elevated load are worth noticing; stating them against the user's own history
keeps this an observation rather than a diagnosis.

Out of scope:
- Claims about which blocks were successful.
- Recommending how much easier a week should be.
- Planning actions.
- Load-ratio scores.
```

**Acceptance Criteria**

- With 5 completed consecutive weeks each at 115% of the usual weekly load and 10 weeks of rated history before them, the card shows "5 consecutive weeks".
- With 4 such weeks, no card shows.
- A streak containing one week at 105% of usual resets the count at that week.
- The current, incomplete week is never counted.
- The history fact appears only when easier weeks recurred at a 3–5 week interval at least twice earlier. Otherwise that sentence is absent.
- With 7 weeks of rated history before the streak, no card shows.

**Unit Tests Required**

- **Add** tests for the usual-weekly-load baseline, taken from before the streak so the streak doesn't inflate its own baseline.
- **Add** boundary tests: 110% for higher-load weeks, 20% below for easier weeks, and the 5-week and 8-week minimums.
- **Add** a test that the incomplete current week is excluded.
- **Add** tests for detecting the recurring easier-week pattern: present, irregular, and only once.

---

### 15. Cardio Efficiency Drift (Caution)

**Overview**

For endurance work, the most honest fatigue readout is efficiency: at the same heart rate, is the user moving slower than a month ago? Pace alone swings with route and weather. Pace at a given heart rate is much more stable, which is why this signal waits for watch heart-rate data.

It uses only measured distances: GPS, or distances the user entered or corrected. Device-estimated distances are excluded, because the estimate itself drifts with fatigue; that includes outdoor efforts that fell back to the estimate for lack of a GPS fix. If lifting load is elevated at the same time, that is added as a plain second observation. The two facts are shown side by side without claiming one caused the other.

**Copilot Prompt**

```markdown
Add a caution signal: Cardio Efficiency Drift.

Eligible efforts:
- Timed Cardio efforts with a measured distance (GPS, or entered or corrected by the user) and
  an average heart rate.
- Efforts with device-estimated distance or no heart rate are never used, whether the effort was
  indoor or an outdoor effort that had no GPS fix.

Definition:
- Efficiency = distance covered per heartbeat, i.e., pace relative to average heart rate.
- Compare the same exercise across efforts of comparable duration (within ±10% of each other).
- Recent window: last 14 days. Reference window: 28–42 days ago.

When it appears:
- Efficiency in the recent window is at least 5% worse than in the reference window.
- Each window contains at least 3 eligible, comparable efforts.
- Kind: caution. Priority: below Sustained High Load.
- When Resistance load over the last 28 days is at least 15% above the user's usual level (Mix
  layer baseline), add that as a second observation sentence.

Copy (numbers are the user's):
- Observation: "At similar durations, your runs are about 6% less efficient (slower pace at the
  same heart rate) than 4–6 weeks ago."
- Optional second observation: "Lifting load is 18% above your usual over the same period."
- Suggestion: "Accumulated fatigue is a common reason for this; an easier week is one option."

Why: pace at a given heart rate is the most reliable endurance fatigue signal, and it only
works with measured distances.

Out of scope:
- Heart-rate zones or training-effect scores.
- Efforts with estimated distance.
- Weather or terrain adjustments.
- Comparing across different exercises (e.g., runs against rides).
```

**Acceptance Criteria**

- A user with 4 comparable GPS runs with heart rate in each window, and 7% worse efficiency recently, sees the card.
- With 4% worse efficiency, no card shows.
- With 2 eligible efforts in either window, no card shows.
- A treadmill run with estimated distance is never counted. The same run, after the user corrects its distance, is counted.
- An outdoor run that fell back to the estimate for lack of a GPS fix is never counted unless the user corrects its distance.
- A run without heart rate is never counted.
- Runs of 30 and 45 minutes are never compared with each other.
- The lifting-load sentence appears only when Resistance load is at least 15% above its usual level.

**Unit Tests Required**

- **Add** eligibility tests covering each distance source (including the no-fix fallback), missing heart rate, and corrected distances becoming eligible.
- **Add** tests for comparable-duration grouping at the ±10% boundary.
- **Add** efficiency calculation and drift threshold tests (exactly 5%).
- **Add** minimum-count tests (exactly 3 per window).
- **Add** tests that the optional lifting-load sentence is included and excluded correctly.
- **Add** a test that different cardio exercises are never compared with each other.

---

## Deferred

| Item | Why it was excluded |
|---|---|
| **Wear OS parity for items 2–4** | Inherited by the Wear OS cloning job in the 2026-09-21 watch shipping plan. Everything these items add travels in the shared watch↔phone format (D-1). |
| **Per-session skip on the effort prompt** | Owner decision (D-4): the prompt must be answered once it appears, on the phone and on the watch. The settings toggle is the opt-out. |
| **A word under every number on the effort prompt** | Tried before; it didn't fit the tile row. The end labels carry the scale (D-4). |
| **Asking the user whether an effort is indoor or outdoor** | The exercise decides, with a no-fix fallback (D-2). No extra tap. |
| **Balanced Recovery positive card** (original #8) | Three compound conditions that rarely all hold, plus a vague claim. It adds noise without a clear readout. Progression Rate covers the positive side for now. |
| **Claims about "successful" blocks or past outcomes** | No definition of success exists, most users won't have enough completed blocks, and a correlation over two or three blocks presented as insight destroys trust the first time it's wrong. |
| **Action buttons on cards** (add session, edit calendar) | This is a planning feature disguised as Stats. It belongs to the planning roadmap, not the instrument panel. |
| **Insights history screen** | Adds a screen to maintain for little value in v1. Cards expire when their conditions clear. |
| **Signals on the Home screen** | Home belongs to logging (LOG SET is the primary action). Signals stay on Stats. |
| **Notifications for signals** | Signals should be calm readouts, not nudges. Revisit only if usage data shows users miss them. |
| **Mute settings and tunable thresholds** | Premature. Thresholds get tuned centrally once real data shows how often each card fires. |
| **Negative Progression Rate variant** | Overlaps with Interference and Sustained High Load. Add later only if there's a gap. |
| **PR events for holds, cardio and rounds** | Would change the shared PR definition that the toast, Session Summary and Records & Trends rely on. Descriptive bests cover the need for now. |
| **Heart-rate-based load, zones, training-effect scores** | Heart rate exists only when the watch is worn. The effort rating stays the universal load measure. |
| **Indoor efficiency with estimated distance; app-side stride model or calibration** | Estimation error is as large as the signal. The platform estimate plus user correction is sufficient. |
| **Time-range selector on Stats** | The window chip plus Records & Trends (all-time) cover the need without adding a control. |
| **Store listing, privacy and permission updates** | Still a hard release gate from the Release 2 plan. The declarations must now also cover per-effort heart rate and step collection. |

---

## Suggested Batching

1. **PR 1 — Effort rating (phone):** Item 1. Mostly a relabel, a recolor and a new "change it from the Summary" control. Ship immediately, independently of everything else, so every new answer carries the new meaning.
2. **PR 2 — Watch capture add-ons (in the watch v1 branch):** Items 2 and 3, watchOS only, before the watch release is cut. On-device verification waits on the watchOS app target (O-2).
3. **PR 3 — Distance source and correction:** Item 4. Touches the watch recording and the phone's session edit flow; merge before the watch release so no unlabelled estimates ever exist.
4. **PR 4 — New Stats structure:** Items 5 and 6 together. The old sections can't be removed until Records & Trends holds their depth.
5. **PR 5 — Mix layer and load definition:** Item 7. Defines the shared load and baseline that PR 7 onwards reuse.
6. **PR 6 — Signals framework and first card:** Items 8 and 9. The framework ships with a real positive card instead of an empty container.
7. **PR 7 — Training balance signals:** Items 10 and 11. Both depend on the load split and baseline from PR 5.
8. **PR 8 — Fuel signals:** Items 12 and 13. Both share the consistent-logging gate and the Fuel row context.
9. **PR 9 — Long-horizon signals:** Items 14 and 15. These need the most history (weeks of ratings, watch heart rate, measured distances), so they ship last.
