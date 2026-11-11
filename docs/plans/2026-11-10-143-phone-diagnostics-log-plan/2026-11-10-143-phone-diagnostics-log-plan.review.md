# Review: 143 phone diagnostics log · D-14301..D-14307, S-14301..S-14316 · working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 3 · tests: governor-run per brief; not re-run here (no counts pasted)
Diff vs Predicted Files: conforms, with naming and one extra file — see below
## Findings
1. [Minor] lib/features/settings/settings_screen.dart:1053 — `_copy` awaits `Clipboard.setData` with no
   try/catch, and `_SettingsRow.onTap` is a `VoidCallback?` (settings_screen.dart:1088), so a clipboard
   failure is an unhandled async exception: the user gets no feedback and the row keeps claiming copy
   works. Fix: wrap the await in try/catch and on failure show nothing (or a generic failure message).
   Guard: none required for a Minor; a mock `Clipboard.setData` throw test would be the natural one.
2. [Minor] docs/state_management/watch_diagnostics.md:82 — "(memory only on web)" understates the code:
   `openDefaultDiagnosticsStorage` also falls back to `InMemoryDiagnosticsStorage` when the support
   directory cannot be resolved within the 2 s timeout (lib/core/services/diagnostics_storage_default_io.dart:12-22).
   The doc is not false about the normal path, but the fallback reason is missing. Fix: "(memory on web,
   or when the directory cannot be resolved in time)".
3. [Minor] lib/core/services/diagnostics_lifecycle_observer.dart:19 + lib/main.dart:374 — the observer is
   never removed and `runStartup` can run more than once in a process: `test/startup_failure_screen_test.dart`
   calls `runStartup` three times, so three observers (each holding its log and storage) stay attached to
   the shared `WidgetsBinding` for the test process. For the app's one call it is fine, as the brief
   anticipates. Fix (optional): no disposal hook exists here; test-only concern, no change needed for
   this plan.

No other findings.

## Question verdicts
1. Observation only — OK. Every hook is sync and self-swallowing; no `await` was added or reordered:
   `note` wraps everything in try/catch (diagnostics_log.dart:69-89), `events()` catches
   (diagnostics_log.dart:104-109), `FileDiagnosticsStorage` catches every op (diagnostics_storage_io.dart).
   All six `_report` sites checked: `onFailure` still fires on every path it fired before; the three
   failure-path `_report` calls now pass `record: false` only to avoid double-recording beside the
   `frame_sent`/`frame_handler_failed` note. `send` still returns the same `WatchDelivery` on every path
   (asserted across working/throwing/no log in S-14313, test/diagnostics_watch_transport_test.dart).
2. Privacy — OK. `_reason` (watch_transport.dart:495-499) is `timeout` / `PlatformException.code` /
   `runtimeType`, never a message; `_logName` (watch_transport.dart:485-491) uses frame `type` or the
   fixed-vocabulary `request` name (`routines`/`snapshot`, watch_transport.dart:89-90,123,168 — not
   payload); `session` is the session id only; the Settings header carries version/build/platform/count/
   UTC time. `noteLaunch`'s `previous=` reuses only earlier recorded details, all of the same safe
   vocabulary. The three `97531` shareText assertions cover the message-leak class.
3. Log logic and startup — OK. First-use count, torn line, compaction, coalescing and back-off all match
   D-14301 and have tests (S-14302 relaunch count, S-14303 torn line, S-14302 back-off, S-14306).
   `FileDiagnosticsStorage` compaction rewrites at most `capacity` lines (~3000, a few hundred KB) with a
   flushed `.tmp` + rename whose failure leaves the original; sync IO on the main isolate is the plan's
   stated cost model. `openDefaultDiagnosticsStorage` has no throwing path: the 2 s timeout and any error
   fall to memory; `WidgetsFlutterBinding.ensureInitialized()` (lib/main.dart:189) precedes `addObserver`
   (lib/main.dart:374), and `noteLaunch`/`DiagnosticsLog` construction cannot throw out of `_runStartup`.
   See finding 3 for the never-removed observer.
4. Settings row — OK. `_count` is read at first build and after a copy, not ticked live (the plan's
   stated behaviour); `messenger`/`theme` captured before the await and `mounted` checked after
   (settings_screen.dart:1055-1061); the row sits between `_WatchSection` and the `SizedBox` before
   HEALTH (settings_screen.dart:160-166), asserted by position in the widget test; `_WatchSection` and
   the read-only `Apple Watch` row are untouched by the diff. Clipboard failure is finding 1.
5. Claims — OK. Every type, file and test name the docs name exists (checked against the diff and the
   files read this run): `DiagnosticsLog`, `DiagnosticsLifecycleObserver`, the five test files, the
   bound 3000/3300, 60 s coalescing, 120-char cut, `phone-diagnostics.jsonl`, the note kinds and reason
   rule. Only the "(memory only on web)" incompleteness of finding 2. `theme_and_settings.md` and
   `watch-app-setup-and-qa.md` step 39 describe what the code and test show.

## Docs delta
- docs/state_management/watch_diagnostics.md MODIFIED -> applied (true sentences, tests exist; finding 2)
- docs/theme_and_settings.md MODIFIED -> applied (true, tied to S-14315)
- docs/watch-app-setup-and-qa.md ADDED -> applied (step 39)
- Doc edits the table does not name: none.

## Assumption Log rulings
- A-1: process assumption, nothing to verify in code — ratified.
- A-2: clipboard, no share sheet — matches the code (Clipboard.setData, no new package) — ratified.
- A-4: no `frame_dropped` note — verified: `_dispatch` returns before noting when `_handler == null`
  (watch_transport.dart:455-456) and the message listener attaches only in `onIncoming`, after the
  handler is set (watch_transport.dart:468-471) — ratified.
- A-3: log runs off iOS too, row only with a watch link state — matches the factory (`kIsWeb`/non-iOS →
  null) and the Settings placement — ratified.

## Scenario coverage
S-14301..S-14308 -> test/diagnostics_log_test.dart (named per scenario, plus the failed-rewrite back-off)
S-14309, S-14310, S-14311, S-14312, S-14313 -> test/diagnostics_watch_transport_test.dart
S-14314 -> test/diagnostics_lifecycle_test.dart
S-14315 -> test/settings_diagnostics_test.dart
S-14316 -> test/diagnostics_wiring_source_test.dart
No scenario without a test that would fail without the change.

## Diff vs Predicted Files detail
- All plan Predicted Files appear. Names differ from the plan's P1 list: `diagnostics_storage_stub.dart`
  is delivered as `diagnostics_storage_default.dart` + `diagnostics_storage_default_io.dart` +
  `diagnostics_storage_default_stub.dart` (same conditional-export shape as
  `startup_failure_diagnostic_writer.dart`); `diagnostics_storage_io.dart` as planned.
- `lib/features/home/home_screen.dart` is in the brief's file list (the MyApp→Settings pass-through), not
  in the plan's Phases table — accepted per brief.
- `.claude/crew.md` (2 lines) is in the diff but outside the plan; it is crew bookkeeping, not reviewed.

## Resolution (lead, 2026-11-10)

1. Fixed: `_copy` catches a clipboard failure and announces nothing. No unit guard (a mock channel that throws would need a test of its own; accepted as Minor).
2. Fixed in the doc ("memory only on web, and for a run in which the directory cannot be resolved within two seconds").
3. Accepted: test-only accumulation in `startup_failure_screen_test.dart`.

Verified: full `flutter test` +7358 ~2 all passed (before these two edits; the touched Settings, docs and UI-standards tests re-run: 61 passed); `flutter analyze` 181 issues (baseline); invariant grep clean; mutation pass over the log, the transport hooks, the observer, the wiring and the Settings row: 20 mutants killed (one survived and was closed by `test S-14310 a failed energy_live send is never coalesced`), one accepted (the empty-read guard in compaction: unreachable in a test, as on the watch). Plan changes: `frame_dropped` was removed (A-4).
