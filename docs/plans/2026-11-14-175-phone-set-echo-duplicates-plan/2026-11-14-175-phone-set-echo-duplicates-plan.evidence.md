# Evidence: 2026-11-14-175-phone-set-echo-duplicates-plan

Baselines collected by the Conductor (2026-11-14) during planning, before any code change.
Implementers append their own run outputs below each section.

## Doc sizes (against the 52 KB band, rule docs/documentation_standard.md)

- `docs/watch_session_capture.md` — 40.3 KB
- `docs/watch_session_sync.md` — 45.1 KB
- Both have headroom; the planned deltas are a few hundred bytes each.

## Sweep standing numbers (pre-fix, from 172's investigation, findings §2/§8)

- Contract sweep at 2000 seeds (`--dart-define=CONVERGENCE_SEEDS=2000`,
  `S-14509 every random seed converges`): 19 stalls, heal-only list of 13:
  [209, 270, 316, 899, 1662, 2043, 2380, 2387, 2510, 2669, 3189, 3548, 4098] (byte-identical across runs).
- Kill sweep at 2000 (`S-16310`): 19 stalls, heal-only list of 11:
  [352, 565, 209, 270, 2043, 316, 2380, 899, 2387, 2510, 2669].
- Stable heal core (shrunk to the 4-action echo trace, findings §3):
  [209, 270, 316, 899, 1662].
- Expected post-fix: heal-only lists empty in all three sweeps; the register's `heal`
  entry text states the measured count.

## Ratchet baselines (test/watch_convergence_random_test.dart)

- `shippingRatchet = (kSeedCount * 6 / 200).ceil()` (:232-235) — at 200 seeds = 6; heal
  is excluded from its count (:285-289).
- `phoneKillRatchetPer200 = 10` (:341-344) — heal excluded (:395-399).
- Decision rule (D-17508): touch only on a measured non-heal class shrink; never raise.

## `flutter analyze` baseline

- (fill from the last gateway lint run: issue count at HEAD; plan-175 must stay at or
  under it. Known: exits non-zero while the repo carries pre-existing info notices.)

## Phase 1 — red at HEAD (prove-red)

- (implementer pastes the failing counts per test name here)

## Phase 2 — fix green

- (implementer pastes pass/fail counts per suite)

## Phase 3 — 2000-seed re-measure

- (paste heal-only lists and class counts for all three sweeps; note any gateway
  timeout with its command)

## Phase 4 — Swift pin + corpus

- (paste swift-test result; corpus re-record byte-equality for trace-echo)

## Phase 5 — residue sweep + final gate

- (paste the two greps and final lint/test counts)
