# Review: Stats PR 7b — Cross-Modality Interference caution signal

Base `b3b91fa`; work uncommitted. Review only; no edits to code/tests/docs.

## Verified (positive evidence)

- **Rule vs D-1301–D-1313.** `analyseInterference` implements the rated-sports
  population, the nearest-rank inclusive threshold, the 36 h follow-up with the
  id tie-break, the 28-day prior window that excludes *every* follow-up, the
  unweighted mean shortfall, the 45-day pattern floor, the whole-percent range
  and the guarded 30% rise. Hand-checked against the evidence file's computed
  values; no divergence found.
- **Copy.** `crossModalityInterferenceCopy` emits the shipped string
  character-for-character (en dash U+2013, range collapse when `lo == hi`,
  verbatim suggestion, second sentence only when the rise is present).
- **Plug-in.** `InterferenceSignal` is one class, one import and one registry
  entry; it calls `interferenceSessions()` and nothing else, and the structural
  guards prove no history walk, no PR API and no second percentage derivation.
- **Mix untouched.** `_sessionSplit` is an extraction of the existing walk;
  `computeMixLayer` / `computeMixPeriod` keep the same measure, segments,
  percents, counts, strip and null-on-no-time behaviour.
  `test/mix_layer_service_test.dart` and `test/mix_layer_screen_test.dart` are
  unedited and green.
- **Scope.** `gateway.sh git-status` shows only the expected files, no strays.
- **Tests.** `gateway.sh test test/interference_test.dart
  test/interference_sessions_service_test.dart
  test/interference_signal_screen_test.dart` → `+51: All tests passed!`
- **Mutation evidence.** Five recorded pairs (36 h bound, dip tolerance,
  priority 500→300, rating gate, Sports component → whole load) are red before
  and green after, and all are restored.

## Findings

1. **blocker — `docs/signals.md`:264, 282, 305–307 and `docs/stats_screen.md`:176** —
   the added prose restates values the source owns: "three times" for
   `kInterferenceMinDippedFollowUps`, "the top quartile" for
   `kInterferenceHardPercentile`, and the whole float-tolerance sentence
   (`1e-9`, `0.9`, `0.09999999999999998`, "one tenth", "nine per cent") for
   `kInterferenceMinDip`. `documentation_standard.md` §3.4 forbids restating a
   value beside the constant that owns it, and §5 makes it a review blocker
   rather than a suggestion. → Keep the constant names and the test pointers;
   delete the values (the tolerance's *reason* can stay without the numbers).
2. **major — `docs/signals.md`:272 vs `lib/core/models/interference.dart`:163** —
   the doc (and the constant's own comment at `interference.dart`:10, and
   D-1302) say the hard window is `kInterferenceHardWindowDays` *local calendar
   days*; the implementation subtracts a fixed `Duration(days: …)` span, so the
   two disagree by the DST offset and S-2015 locks the duration reading. →
   Either use calendar components or drop "local calendar days" from both the
   doc and the constant comment, so the prose and the test agree.
3. **minor — `test/interference_test.dart` (`S-2008`)** — the plan's S-2008 asks
   for two fixtures; only the 12-session one exists and it asserts `n == 4`
   alone. The 9-session variant (threshold `sorted[6]`, loads 7/8/9 hard) is
   absent, so the nearest-rank arithmetic is untested at a second population
   size. → Add the 9-session variant, asserting the hard ids.
4. **minor — `lib/core/models/interference.dart`:266–278, 288–296** — two hard
   sessions can share one follow-up, and the rule iterates the `followUps`
   *list*, so that session contributes twice to `k` and to `comparableInWindow`.
   The copy then reports more "hard sports sessions" than there were dipped
   lifting days. D-1309 says "dipped follow-ups", D-1310 says "hard sessions",
   so the plan is ambiguous and no test pins either reading. → Decide the
   semantics and pin it with a guard test (dedupe by follow-up id, or state that
   counting is per hard session).

### Carried (outside the fix set)

5. **nit — `lib/core/models/interference.dart`:348** — the rise threshold is the
   literals `10 * recent < 13 * prior` while `kInterferenceSportsLoadRisePercent`
   is declared and never read; the contract test pins both, so drift is caught,
   but the constant is not the single source it reads as.
6. **nit — `lib/core/models/interference.dart`:366–368** — the copy hardcodes
   "3 weeks" while the window is `kInterferenceSportsLoadWindowDays`; S-2007
   pins the string, not the relation.
7. **nit — fixture deviation (informational)** — F-2001 moves the 41-load
   sports session from day 40 to day 46 to hit the plan's pinned 38% rise; the
   plan's literal fixture would yield no sentence. The plan's pinned outcome is
   what is asserted, and the evidence file records the deviation.
8. **nit — `docs/signals.md`:267–340** — the section describes behaviour in
   prose where §4.2 asks for a pointer. It does name a test per bullet and
   matches the section's pre-existing style for the other two signals, so this
   is style, not a violation to fix in this PR.

## Doc hygiene

- DOC STANDARD: ❌ REJECT — `docs/signals.md`:264, 282, 305–307;
  `docs/stats_screen.md`:176 — class 4 (numeric value defined in source).
- DOC FALSIFICATION: ❌ REJECT — `docs/signals.md`:272 — "local calendar days"
  is not what the code computes → align prose and code (finding 2).
- DOC FALSIFICATION: ✅ PASS otherwise — every other added claim checked against
  the post-change code (registry size, the adapter's read path, the service
  entry, the copy) holds, and every test name cited exists.
- Doc hygiene: no hex literals, no line numbers, no roadmap or
  scheduled-change language in the added text.

## Global conventions (`docs/global_conventions.md`)

PASS (3 rules): effort-kind drives analytics (the follow-up requires a
set-effort section, bests are per exercise on the exercise's own axis); reuse
the canonical owner (shared load split and shared best/section helpers, Mix
untouched); instrument panel not influencer (one restrained caution sentence).

N/A (4 rules): units + canonical storage, theme tokens only, card chrome via
`OmniSurface`/`OmniCardHeader`, timestamps are source data — no units, styling,
card chrome or persisted timestamp is added or changed by this diff.

---

VERDICT: CHANGES_REQUESTED
