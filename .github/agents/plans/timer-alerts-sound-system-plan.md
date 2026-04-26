# Feature: Timer Alerts & Sound System

## Overview
Replace the static `SystemSound.play` alert with bundled audio assets via `just_audio`,
add user-configurable sound preferences to SettingsState, surface them in a new
**SOUNDS & ALERTS** section in SettingsScreen, and wire a periodic rest-ping into the
existing 1-second ticker in WorkoutSessionScreen.

## Requirements
- Bundle 5 `.mp3` sound assets in `assets/sounds/` (manual step — Aleks)
- Add `just_audio` and `audio_session` dependencies to `pubspec.yaml`
- Refactor `TimerAlertService` from a static class to an instance class with pre-loaded `AudioPlayer` map
- Audio session configured for ducking (not pausing) so background music continues
- Three new SettingsState preferences: `effortTimerSound`, `restPingInterval`, `restPingSound`
- New SOUNDS & ALERTS section in SettingsScreen (between PREFERENCES and APPEARANCE)
- Rest ping fires from the existing `_ticker` — no new timers
- Full unit/widget test coverage; no tests depend on live audio playback

## Acceptance Criteria
- [ ] `just_audio` and `audio_session` resolve without errors in `pubspec.yaml`
- [ ] `TimerAlertService` is an instance class created in `main.dart` and injected like other state objects
- [ ] All 5 audio assets are pre-loaded during `initialize()` — zero playback latency
- [ ] `fireEffortTimerAlert` plays specified sound + `heavyImpact` haptic (web skipped)
- [ ] `fireRestPingAlert` plays specified sound + `lightImpact` haptic (web skipped)
- [ ] `playPreview` plays sound with no haptic (for Settings picker)
- [ ] Background music ducks briefly during alert, resumes immediately (audio session ambient/ducking)
- [ ] Three new preferences persist across app restarts with correct defaults
- [ ] Invalid stored values fall back to defaults without errors
- [ ] `validSoundIds` (5 entries) and `restPingIntervalOptions` (7 entries) on `SettingsState`
- [ ] SOUNDS & ALERTS section appears between PREFERENCES and APPEARANCE in SettingsScreen
- [ ] All three rows show correct current values; bottom sheets work with tap-to-preview for sound rows
- [ ] Rest ping fires at correct interval boundaries (60 s, 120 s, …) — never at 0 s
- [ ] Rest ping does NOT double-fire on the same boundary
- [ ] Rest ping stops when rest record closes
- [ ] With interval = Off (0): no rest ping logic runs
- [ ] All existing tests pass (no regressions)

## Scenarios
_Populated by Developer agent during Phase 0 / implementation._

---

## Iteration 1

### Pre-condition (Manual — Aleks)
Before agents begin Phase 1, complete:
1. Source 5 CC0/royalty-free sound effects (freesound.org, pixabay.com/sound-effects, or zapsplat.com):
   - `boxing_bell.mp3` — Classic 3-hit boxing bell
   - `digital_buzzer.mp3` — Short electronic buzzer
   - `soft_chime.mp3` — Single gentle chime
   - `double_tap.mp3` — Two quick taps/clicks
   - `signal_tone.mp3` — Brief ascending two-note signal
2. Trim to 0.5–2.0 s; normalize to −14 LUFS; export as MP3 128 kbps+, mono.
3. Place in `assets/sounds/` in the project root.
4. Add to `pubspec.yaml` under `flutter > assets:` — `- assets/sounds/`
5. Commit. Agents proceed once this is done.

---

### Phase 1: `just_audio` Plugin & `TimerAlertService` Refactor (`@developer`)

**Context for agent:**
`TimerAlertService` currently lives at `lib/core/utils/timer_alert_service.dart` as a static
class with one method `fireTimerExpiredAlert()`. Two call sites exist in
`lib/features/session/workout_session_screen.dart` (lines 587 and 595), both using
`unawaited(TimerAlertService.fireTimerExpiredAlert())`. No other production call sites exist.

#### Steps
1. [ ] Add to `pubspec.yaml` dependencies:
   ```yaml
   just_audio: ^0.9.40
   audio_session: ^0.1.21
   ```
   Run `flutter pub get` to confirm resolution.

2. [ ] Refactor `lib/core/utils/timer_alert_service.dart`:
   - Remove `static` pattern entirely.
   - Add private `Map<String, AudioPlayer> _players = {}`.
   - Add `Future<void> initialize()`:
     - Configures `AudioSession` with `AudioSessionConfiguration` in ambient/notification
       mode (ducking enabled — `AudioSessionConfiguration(
         avAudioSessionCategory: AVAudioSessionCategory.ambient,
         avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers |
             AVAudioSessionCategoryOptions.duckOthers,
         androidAudioAttributes: AndroidAudioAttributes(
           contentType: AndroidAudioContentType.sonification,
           usage: AndroidAudioUsage.notificationEvent,
           flags: AndroidAudioFlags.audibilityEnforced,
         ),
         androidWillPauseWhenDucked: false,
       )`)
     - Creates one `AudioPlayer` per sound ID; calls `await player.setAsset('assets/sounds/$soundId.mp3')`.
     - Stores in `_players`.
     - Guard: on web (`kIsWeb`) skip audio initialisation entirely (just_audio web support
       is unreliable in background; haptic is also skipped on web already).
   - Add `Future<void> fireEffortTimerAlert(String soundId)`:
     - Resolve player: `_players[soundId] ?? _players['boxing_bell']`.
     - `await player.seek(Duration.zero); unawaited(player.play());`
     - `if (!kIsWeb) await HapticFeedback.heavyImpact();`
   - Add `Future<void> fireRestPingAlert(String soundId)`:
     - Same but fallback `'soft_chime'`, haptic `lightImpact`.
   - Add `Future<void> playPreview(String soundId)`:
     - Same as `fireEffortTimerAlert` but no haptic at all.
   - Add `Future<void> dispose()`: iterates `_players.values` and calls `player.dispose()`.

3. [ ] Update `lib/main.dart`:
   - Import `timer_alert_service.dart`.
   - Instantiate: `final timerAlertService = TimerAlertService();`
   - Call `await timerAlertService.initialize();` after `settingsState.initialize()`.
   - Pass `timerAlertService` into `MyApp(...)`.

4. [ ] Propagate `TimerAlertService` through `MyApp` → any screen that constructs
   `WorkoutSessionScreen` or `SettingsScreen`:
   - Add `timerAlertService` field to `MyApp` and thread it through to `HomeScreen`
     (and any other top-level screen wrappers that hold navigation to those two screens).

5. [ ] Update `lib/features/session/workout_session_screen.dart`:
   - Add `final TimerAlertService timerAlertService;` constructor parameter (required).
   - Replace both static call sites:
     ```dart
     // Before:
     unawaited(TimerAlertService.fireTimerExpiredAlert());
     // After:
     unawaited(widget.timerAlertService.fireEffortTimerAlert(
       widget.settingsState?.effortTimerSound ?? 'boxing_bell',
     ));
     ```
   - Add `override dispose()` hook to call `// timerAlertService is app-owned; do not dispose here`.

6. [ ] Update **all** `WorkoutSessionScreen(...)` call sites to pass `timerAlertService`:
   - `lib/features/home/home_screen.dart` (5 occurrences — lines ~275, 349, 368, 437, 566)
   - `lib/features/exercise/exercise_detail_screen.dart` (1 occurrence)
   - `lib/features/calendar/day_session_list_screen.dart` (1 occurrence)
   - `lib/features/routine/my_routines_screen.dart` (1 occurrence)
   - `lib/features/session/session_summary_screen.dart` (1 occurrence)
   - All test files: `widget_test.dart`, `unsaved_changes_dialog_test.dart`,
     `session_finish_timers_test.dart`, `session_edit_duration_test.dart`,
     `screen_widget_test.dart` — use a no-op `FakeTimerAlertService` (see Phase 5).

7. [ ] Verify no remaining `TimerAlertService.fire` static references exist in the codebase.

#### Affected Files
- `pubspec.yaml`
- `lib/core/utils/timer_alert_service.dart`
- `lib/main.dart`
- `lib/app.dart` (if `MyApp` stores state objects — thread through here)
- `lib/features/session/workout_session_screen.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/exercise/exercise_detail_screen.dart`
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/routine/my_routines_screen.dart`
- `lib/features/session/session_summary_screen.dart`
- Test files referencing `WorkoutSessionScreen`

---

### Phase 2: `SettingsState` Preferences (`@developer`, parallel with Phase 1)

**Context for agent:**
`lib/state/settings/settings_state.dart` uses `_repository.getPreferenceString` /
`setPreferenceString` for all persisted preferences. Follow the exact pattern of
`setPreferredWeightUnit` (normalise → persist → update field → `notifyListeners()`).

#### Steps
1. [ ] Add constants (inside `SettingsState` class):
   ```dart
   static const String _effortTimerSoundKey = 'effort_timer_sound';
   static const String _restPingIntervalKey  = 'rest_ping_interval';
   static const String _restPingSoundKey     = 'rest_ping_sound';

   static const List<String> validSoundIds = [
     'boxing_bell', 'digital_buzzer', 'soft_chime', 'double_tap', 'signal_tone',
   ];

   static const Map<String, String> soundDisplayNames = {
     'boxing_bell':    'Boxing Bell',
     'digital_buzzer': 'Digital Buzzer',
     'soft_chime':     'Soft Chime',
     'double_tap':     'Double Tap',
     'signal_tone':    'Signal Tone',
   };

   static const List<({int value, String label})> restPingIntervalOptions = [
     (value: 0,   label: 'Off'),
     (value: 30,  label: '30s'),
     (value: 45,  label: '45s'),
     (value: 60,  label: '1 min'),
     (value: 90,  label: '1.5 min'),
     (value: 120, label: '2 min'),
     (value: 180, label: '3 min'),
   ];
   ```

2. [ ] Add private fields with defaults:
   ```dart
   String _effortTimerSound = 'boxing_bell';
   int    _restPingInterval  = 0;
   String _restPingSound     = 'soft_chime';
   ```

3. [ ] Add getters:
   ```dart
   String get effortTimerSound => _effortTimerSound;
   int    get restPingInterval  => _restPingInterval;
   String get restPingSound     => _restPingSound;
   ```

4. [ ] Add setters (persist → update field → notify):
   ```dart
   Future<void> setEffortTimerSound(String soundId) async {
     final v = validSoundIds.contains(soundId) ? soundId : 'boxing_bell';
     _effortTimerSound = v;
     await _repository.setPreferenceString(_effortTimerSoundKey, v);
     notifyListeners();
   }

   Future<void> setRestPingInterval(int seconds) async {
     final valid = restPingIntervalOptions.map((o) => o.value).toList();
     final v = valid.contains(seconds) ? seconds : 0;
     _restPingInterval = v;
     await _repository.setPreferenceString(
       _restPingIntervalKey, v.toString());
     notifyListeners();
   }

   Future<void> setRestPingSound(String soundId) async {
     final v = validSoundIds.contains(soundId) ? soundId : 'soft_chime';
     _restPingSound = v;
     await _repository.setPreferenceString(_restPingSoundKey, v);
     notifyListeners();
   }
   ```

5. [ ] Extend `_loadFromPrefs()` to load all three:
   - `effortTimerSound`: load string, validate against `validSoundIds`, default `'boxing_bell'`.
   - `restPingInterval`: load string, parse int, validate against `restPingIntervalOptions` values, default `0`.
   - `restPingSound`: load string, validate, default `'soft_chime'`.

#### Affected Files
- `lib/state/settings/settings_state.dart`

---

### Phase 3: Settings UI — Sounds & Alerts Section (`@developer`, after Phase 1 + 2)

**Context for agent:**
`lib/features/settings/settings_screen.dart` renders two `OmniSurface` cards:
`_MeasurementsSection` (PREFERENCES) and the APPEARANCE grid. The new SOUNDS & ALERTS
section is an additional `OmniSurface` inserted **between** them. `SettingsScreen`
currently receives only `settingsState`; `timerAlertService` must be added as a
required constructor param.

#### Steps
1. [ ] Add `final TimerAlertService timerAlertService;` to `SettingsScreen` constructor.
   Update the one production call site in `lib/features/home/home_screen.dart` (line ~758)
   and all test call sites.

2. [ ] In `SettingsScreen.build`, between `_MeasurementsSection` and the APPEARANCE card,
   insert:
   ```dart
   const SizedBox(height: 24),
   _SoundsAlertsSection(
     settingsState: settingsState,
     timerAlertService: timerAlertService,
     theme: theme,
   ),
   ```

3. [ ] Implement `_SoundsAlertsSection` (private `StatelessWidget` in the same file):
   - Section header `'SOUNDS & ALERTS'` — same `labelSmall` letterspaced style as APPEARANCE header.
   - **Row 1 — Effort Timer Sound**
     - `ListTile` / equivalent: leading label `'Effort Timer Sound'`,
       subtitle `'Plays when a round or interval finishes'`,
       trailing muted text = `SettingsState.soundDisplayNames[settingsState.effortTimerSound]`.
     - `onTap` → `_showSoundPicker(context, 'effort')`.
   - **Row 2 — Rest Ping**
     - Leading `'Rest Ping'`, subtitle `'Periodic alert during rest between sets'`.
     - Trailing: label from `restPingIntervalOptions` matching `settingsState.restPingInterval`.
     - `onTap` → `_showIntervalPicker(context)`.
   - **Row 3 — Rest Ping Sound**
     - Leading `'Rest Ping Sound'`, subtitle `'Sound for periodic rest alerts'`.
     - Trailing: `soundDisplayNames[settingsState.restPingSound]`.
     - Always visible (even when interval is Off).
     - `onTap` → `_showSoundPicker(context, 'rest')`.

4. [ ] Implement `_showSoundPicker(BuildContext context, String type)`:
   - `showModalBottomSheet` with `OmniSurface` (or `Container` styled with `theme.colorScheme.surface`).
   - Title text (e.g. `'Effort Timer Sound'` or `'Rest Ping Sound'`).
   - For each entry in `SettingsState.validSoundIds`:
     - `ListTile` with sound display name.
     - Trailing `Icon(Icons.check)` in `theme.colorScheme.primary` if currently selected.
     - `onTap`:
       1. Call `timerAlertService.playPreview(soundId)` (fire and forget — `unawaited`).
       2. Call `settingsState.setEffortTimerSound(soundId)` or `setRestPingSound(soundId)`.
       3. Do **not** close the sheet — let the user audition each option freely.
         Add a close button or tap outside to dismiss.

5. [ ] Implement `_showIntervalPicker(BuildContext context)`:
   - Same `showModalBottomSheet` pattern.
   - For each entry in `SettingsState.restPingIntervalOptions`:
     - `ListTile` with label. Trailing check if currently selected.
     - `onTap`: call `settingsState.setRestPingInterval(option.value)` then
       `Navigator.pop(context)` (no preview for intervals).

#### Affected Files
- `lib/features/settings/settings_screen.dart`
- `lib/features/home/home_screen.dart`
- Test files referencing `SettingsScreen`

---

### Phase 4: Rest Ping Firing Logic (`@developer`, after Phase 1 + 2, parallel with Phase 3)

**Context for agent:**
`WorkoutSessionScreen` has a 1-second `_ticker` (a `Timer.periodic`) that calls `setState`.
`widget.workoutState.hasRestRecord(effortId, entryIndex)` returns `true` when an entry has
an open rest record. `widget.workoutState.getRestElapsedSeconds(effortId, entryIndex)` returns
elapsed seconds as an `int`.

`_exercises` is a `List<Map<String, dynamic>>` where each map has keys `'id'` (effortId)
and `'entries'` (list of logged entries — current set is `_currentSet`). The rest record
for the current entry uses index `_currentSet - 1`.

#### Steps
1. [ ] Add to `_WorkoutSessionScreenState`:
   ```dart
   final Map<String, int> _lastRestPingFiredAt = {};
   ```

2. [ ] Extract a pure static helper (can be top-level function in the same file):
   ```dart
   bool _shouldFireRestPing({
     required int elapsed,
     required int interval,
     required int lastPinged,
   }) {
     if (interval == 0) return false;
     if (elapsed == 0) return false;
     if (elapsed % interval != 0) return false;
     return elapsed > lastPinged;
   }
   ```
   (Pure function — no state access. Makes it directly unit-testable.)

3. [ ] In the `_ticker` callback, after the existing `setState(() {})` call, add:
   ```dart
   _checkRestPings();
   ```

4. [ ] Implement `_checkRestPings()`:
   ```dart
   void _checkRestPings() {
     final interval = widget.settingsState?.restPingInterval ?? 0;
     if (interval == 0) return;

     for (final exercise in _exercises) {
       final effortId = exercise['id'] as String;
       final entryIndex = _currentSet - 1; // currently active entry
       if (!widget.workoutState.hasRestRecord(effortId, entryIndex)) continue;

       final elapsed = widget.workoutState.getRestElapsedSeconds(
         effortId, entryIndex);
       final lastPinged = _lastRestPingFiredAt[effortId] ?? 0;

       if (_shouldFireRestPing(
         elapsed: elapsed,
         interval: interval,
         lastPinged: lastPinged,
       )) {
         _lastRestPingFiredAt[effortId] = elapsed;
         unawaited(widget.timerAlertService.fireRestPingAlert(
           widget.settingsState?.restPingSound ?? 'soft_chime',
         ));
       }
     }
   }
   ```
   > Note: only the currently active entry (`_currentSet - 1`) is checked per exercise,
   > consistent with how the existing rest overlay works.

5. [ ] Clear the map entry when rest closes. Locate where `recordRestEnd` is called (inside
   `_logSet` or the method that starts the next timer) and add:
   ```dart
   _lastRestPingFiredAt.remove(effortId);
   ```

6. [ ] In `dispose()`, add: `_lastRestPingFiredAt.clear();`

#### Affected Files
- `lib/features/session/workout_session_screen.dart`

---

### Phase 5: Tests (`@developer`, after all phases)

**Context for agent:**
Existing test files: `test/settings_state_test.dart`, `test/screen_widget_test.dart`,
`test/interaction_flow_test.dart`. Follow the existing mock pattern using
`MockWorkoutRepository` for state tests.

#### Steps
1. [ ] Create `FakeTimerAlertService` (can live in `test/helpers/fake_timer_alert_service.dart`
   or top of each test file that needs it):
   ```dart
   class FakeTimerAlertService extends TimerAlertService {
     @override
     Future<void> initialize() async {}
     @override
     Future<void> fireEffortTimerAlert(String soundId) async {}
     @override
     Future<void> fireRestPingAlert(String soundId) async {}
     @override
     Future<void> playPreview(String soundId) async {}
     @override
     Future<void> dispose() async {}
   }
   ```
   Use this wherever tests construct `WorkoutSessionScreen` or `SettingsScreen`.

2. [ ] Add to `test/settings_state_test.dart` — SettingsState preference tests:
   - Default: `effortTimerSound == 'boxing_bell'`, `restPingInterval == 0`,
     `restPingSound == 'soft_chime'`
   - Set/get round-trip for each of the three fields
   - `setEffortTimerSound('invalid_id')` → value stays `'boxing_bell'`
   - Loading invalid sound ID from repository → falls back to default (simulate via
     `repository.setPreferenceString('effort_timer_sound', 'garbage')` before init)
   - Loading invalid `restPingInterval` from repo → falls back to `0`
   - `validSoundIds.length == 5`
   - `restPingIntervalOptions.length == 7`

3. [ ] Add to `test/screen_widget_test.dart` or a new `test/settings_sounds_test.dart`:
   - SOUNDS & ALERTS section header renders
   - All three rows render with correct default trailing text
     (`'Boxing Bell'`, `'Off'`, `'Soft Chime'`)
   - Section order: PREFERENCES visible, then SOUNDS & ALERTS, then APPEARANCE
     (find their positions in widget tree)
   - Tapping Effort Timer Sound row opens bottom sheet (find `'Boxing Bell'` in sheet)
   - Tapping Rest Ping Interval row opens bottom sheet (find `'Off'` or `'1 min'` etc.)

4. [ ] Add unit tests for `_shouldFireRestPing` helper:
   - `elapsed: 60, interval: 60, lastPinged: 0` → `true`
   - `elapsed: 60, interval: 60, lastPinged: 60` → `false` (already fired)
   - `elapsed: 0, interval: 60, lastPinged: 0` → `false` (never at 0)
   - `elapsed: 61, interval: 60, lastPinged: 0` → `false` (not on boundary)
   - `elapsed: 120, interval: 60, lastPinged: 60` → `true`
   - `elapsed: 30, interval: 60, lastPinged: 0` → `false` (not yet)
   - `elapsed: 60, interval: 0, lastPinged: 0` → `false` (Off)

5. [ ] Update all existing test call sites for `WorkoutSessionScreen(` and `SettingsScreen(`
   to pass `FakeTimerAlertService()` instance.

6. [ ] Run full test suite; fix any regressions from the new required constructor params.

#### Affected Files
- `test/settings_state_test.dart`
- `test/screen_widget_test.dart`
- `test/interaction_flow_test.dart`
- `test/session_finish_timers_test.dart`
- `test/session_edit_duration_test.dart`
- `test/widget_test.dart`
- `test/unsaved_changes_dialog_test.dart`
- `test/helpers/fake_timer_alert_service.dart` (new)
- Possibly new `test/settings_sounds_test.dart`

---

## Progress
- [ ] Manual: Source & place audio files (`assets/sounds/`, update `pubspec.yaml`)
- [x] Phase 1: `just_audio` + `TimerAlertService` refactor
- [x] Phase 2: `SettingsState` sound preferences
- [x] Phase 3: Settings UI — SOUNDS & ALERTS section
- [x] Phase 4: Rest ping firing logic
- [x] Phase 5: Tests
- [x] Code Review fixes: `timerAlertService` required everywhere, `_checkRestPings` active-entry-only, dead methods removed
- [x] Follow-up: Web-only diagnostic logs for effort/rest/preview timer alerts
- [x] Follow-up: testing-only constructor for web override and diagnostic log unit coverage

## Phase Status: **Complete**
_Leave empty — specialist agents add notes here after completing phases._

---

## Execution Order

| Phase | Depends On | Agent | Notes |
|---|---|---|---|
| Manual: audio files | — | Aleks | Must complete before Phase 1 |
| Phase 1: `just_audio` + service | Audio files in `assets/sounds/` | `@developer` | Foundation |
| Phase 2: SettingsState | — (independent) | `@developer` | Can run in parallel with Phase 1 |
| Phase 3: Settings UI | Phase 1 + 2 | `@developer` | Blocked until both done |
| Phase 4: Rest ping logic | Phase 1 + 2 | `@developer` | Can run in parallel with Phase 3 |
| Phase 5: Tests | All phases | `@developer` | Run last |

**Fastest path:** Aleks sources audio while Phase 2 runs. Phase 1 starts once files are placed. Phases 3 and 4 run in parallel after 1 + 2. Phase 5 closes it out.
