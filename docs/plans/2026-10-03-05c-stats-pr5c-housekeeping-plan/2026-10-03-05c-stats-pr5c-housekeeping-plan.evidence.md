# Evidence — Stats PR 5c housekeeping

Companion to `2026-10-03-05c-stats-pr5c-housekeeping-plan.md`. Evidence only: no plan content, no
review findings (those go in `2026-10-03-05c-stats-pr5c-housekeeping-plan.review.md`).

## 1. Environment and baselines

| Item | Value |
| --- | --- |
| Branch | `develop` |
| HEAD | `e993751` |
| Working tree before this plan | clean; only the two new files in this folder were added |
| Gateway | `.github/copilot/scripts/macos/gateway.sh` (the only shell interface used) |

Baseline commands, run at HEAD before any change:

```
$ gateway.sh lint
196 issues found. (ran in 3.0s)

$ gateway.sh test
01:26 +3423 ~1: All tests passed!
```

Both final lines are quoted verbatim. `196 issues` with 0 errors is the lint ceiling for this unit;
`+3423 ~1` with 0 failures is the suite floor. Phase 2 step 9 re-runs both and its final lines go in
§6 below.

## 2. Commit hashes cited by the index refreshes

| Unit | Commit | How read |
| --- | --- | --- |
| Stats PR 5a | `9d5dca2` | gateway `git-log` |
| Stats PR 5b | `e993751` | gateway `git-log`; HEAD |
| Stats PR 3a3 | `c25617a9` | gateway `git-log` |
| Stats PR 3d | `8be0918` | gateway `git-log` |

## 3. Search results that fix the scope

### 3.1 The stale comment is unique

Search: `never cleared` and `set once`, whole repo.

| Hit | File | Verdict |
| --- | --- | --- |
| `-- NULL = waiting; set once, never cleared` | `scripts/sqlite_schema.sql` (inbox `applied_at_ms` column) | the item-1 target |
| `Skipped-set marker is never cleared after a real log` | `docs/plans/data-tracking-fixes-plan.md` | unrelated — a different marker, a different feature; left alone |

The 3d plan's own evidence file already recorded the schema comment as deliberately-unfixed drift
("`scripts/sqlite_schema.sql` line 1601 carries the comment … which the new exception makes stale …
Recorded here so the next schema-touching PR can correct the comment"). This unit is that PR.

### 3.2 The correct statement already exists elsewhere

| File | Statement | Verdict |
| --- | --- | --- |
| `docs/db_integration.md` | describes the stamp as cleared by the clear-applied write | already correct — cited, not edited |
| `docs/data_models.md` | same | already correct — cited, not edited |

So item 1 removes a contradiction rather than introducing a claim.

### 3.3 The duplicated transformation

| File | Current expression | Planned |
| --- | --- | --- |
| `hive_workout_repository.dart` | `_watchInboxBox.put(entryId, WatchInboxEntry.fromMap({...staged.toMap(), 'applied_at_ms': null}).toMap())` | `_watchInboxBox.put(entryId, staged.unapplied().toMap())` |
| `mock_workout_repository.dart` | `_watchInbox[entryId] = WatchInboxEntry.fromMap({...staged.toMap(), 'applied_at_ms': null})` | `_watchInbox[entryId] = staged.unapplied()` |

Search `'applied_at_ms': null` over `lib/`: exactly these two hits today. After Phase 1 step 5 it must
be zero hits outside `models.dart`'s `toMap()` key.

`WatchInboxEntry` has no `copyWith`, which is why the duplication was hand-rolled and why the fix is a
purpose-built `unapplied()` rather than a general copy (D-1104).

### 3.4 The three uncapped texts

`lib/features/stats/widgets/mix_layer.dart`: three `Text` widgets carry neither `maxLines` nor
`overflow` — the measure label in `_measureText`, the `'Load baseline: …'` note, and the
unrated-session line. None has a key, so the assertions find them by string: `by time` (renders twice),
`Load baseline: 3 of 4 weeks rated`, `1 unrated session`.

## 4. Doc claim → test table

Every behaviour sentence this unit writes or preserves, with the test that proves it. The reworded
sentences must each keep a verifier; a sentence with no test in this column may not be written.

| Doc sentence (after this unit) | File | Verifying test | Scenario id |
| --- | --- | --- | --- |
| The layer's own arithmetic is presentation only — the flex that turns a measure into a share of the bar | `docs/stats_screen.md` | `test/mix_layer_screen_test.dart` | `S-1601` |
| The tallest week sets one scale for all eight strip columns | `docs/stats_screen.md` | `test/mix_layer_screen_test.dart` | `S-1602`, `S-1609` |
| The Profile measurement header is title-only; the add button lives in the card body | `docs/design_system.md` | `test/header_standardization_test.dart` | `S-011` |
| The inbox's applied stamp is `NULL` while the row waits, stamped once on apply, unset only by `clearWatchInboxApplied` | `scripts/sqlite_schema.sql` | `test/db_seed_test.dart` (executes the schema) + `test/watch_capture_repository_parity_test.dart` | `S-1412` |
| The three layer texts cap to one line and ellipsize | (new) `test/mix_layer_screen_test.dart` assertion | `test/mix_layer_screen_test.dart` | `S-1605` |
| `unapplied()` clears only the stamp and is idempotent | (new) `test/watch_capture_repository_parity_test.dart` test | `test/watch_capture_repository_parity_test.dart` | `D-132` |

Verifier read-backs done while planning:

- `lib/features/profile/profile_screen.dart` renders `OmniCardHeader(title: …)` per measurement
  definition with no `actions`, and the add button is built in the card body — so the current
  `docs/design_system.md` Profile row is the wrong one.
- `test/header_standardization_test.dart`'s Profile group asserts the header has no action
  descendant — so the corrected row has a verifier today.
- `lib/features/stats/widgets/mix_layer.dart` computes the segment flex and the strip's tallest week —
  so the current `docs/stats_screen.md` sentence is loose rather than describing a different widget.

## 5. Red → green log

Each row shows the failure observed **before** the change, the same command after, and the inverse
edit that was used to prove the test can fail.

| Test | Red (before) | Green (after) | Inverse edit | Observed |
| --- | --- | --- | --- | --- |
| Model-rules test for `unapplied()` | `test/watch_capture_repository_parity_test.dart:1334` — compile failure, `The method 'unapplied' isn't defined for the type 'WatchInboxEntry'` | `+37: All tests passed!` | `unapplied()` returns `this` | `Expected: null` / `Actual: <5000>` at line 1335; restored, `+37` again |
| `S-1412` (unchanged test, must fail on the inverse) | n/a — passes before and after | `+37: All tests passed!` | `unapplied()` returns `this` | `Expected: null` / `Actual: <5000>` at line 1160; restored, `+37` again |
| `S-1605` ellipsis assertion | `test/mix_layer_screen_test.dart:876` — 2 failures (Mock + Hive), `Expected: <1> Actual: <null>`, `D-933: by time caps to one line` | `+56: All tests passed!` | `maxLines`/`overflow` removed from `_measureText` | 2 failures in the same file; restored, `+56` again |

The `S-1412` row is the point of the inverse edit: it is byte-identical to its pre-unit form (D-1110)
and checks the outcome independently, through `{...appliedA.toMap(), 'applied_at_ms': null}`. It fails
on the inverse edit without having been touched, which is what proves the two repositories' behaviour
is what changed rather than the assertion.

## 6. Post-change command output

Verbatim final lines.

```
$ gateway.sh test test/watch_capture_repository_parity_test.dart
00:04 +37: All tests passed!

$ gateway.sh test test/mix_layer_screen_test.dart
00:06 +56: All tests passed!

$ gateway.sh test test/db_seed_test.dart
00:01 +9: All tests passed!

$ gateway.sh lint
196 issues found. (ran in 2.9s)

$ gateway.sh test
01:24 +3426 ~1: All tests passed!
```

`196 issues found.` with 0 errors matches the §1 ceiling. `+3426 ~1` is the §1 floor plus this unit's
three new tests (3423 + 3), with the same single skip and no new ones.

## 7. Footprint check

`gateway.sh git-diff --stat` at the end of the unit:

```
docs/design_system.md                              |  2 +-
...026-09-26-03-stats-pr3-distance-series-index.md | 21 ++++++-------
docs/plans/2026-10-02-05-stats-pr5-index.md        | 36 +++++++++++++++++-----
docs/stats_screen.md                               |  8 +++--
lib/data/models/models.dart                        | 14 +++++++++
lib/data/repositories/hive_workout_repository.dart |  8 +----
lib/data/repositories/mock_workout_repository.dart |  5 +--
lib/features/stats/widgets/mix_layer.dart          | 17 +++++++---
scripts/sqlite_schema.sql                          |  2 +-
test/mix_layer_screen_test.dart                    | 20 ++++++++++++
test/watch_capture_repository_parity_test.dart     | 28 +++++++++++++++++
11 files changed, 122 insertions(+), 39 deletions(-)
```

`gateway.sh git-diff --name-only -- docs/plans/` returns exactly the two index files:

```
docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md
docs/plans/2026-10-02-05-stats-pr5-index.md
```

No other plan file moved. `gateway.sh git-status` shows the four untracked paths that were already
untracked before this unit (this plan's own folder, the PR 6 index and the two PR 6 plan folders) and
nothing else.

`dart format` was run on the six changed Dart files. It reflowed pre-existing code in three of them
(the repo is not formatter-clean at HEAD), so those reflows were reverted by hand and only the unit's
own lines remain — which is why `mix_layer_screen_test.dart` is +20 rather than the ~+270 the
formatter produced.

## 8. Out of scope, recorded

| Item | Why not here |
| --- | --- |
| The third `'min'` unit literal | carried out of the 5b review as its own change |
| `MixLayerData`'s `==` / `toString` | same |
| The unobservable `baselineTotal > 0` guard | same |
| `OmniCardHeader`'s half-header cap | a shared-widget change with its own test surface |
| PR (personal record) logic and its two toast tests | untouched by this unit |
