/// Canonical constants for the daily water tracker.
///
/// Water has no goal — like macros and sodium, it is tracked and stored
/// for the historical record only. Each glass the user logs is fixed at
/// [kWaterGlassMl] milliliters; the day's stored volume is the source of
/// truth and the on-screen glass count is derived at the display
/// boundary (`volumeMl ~/ kWaterGlassMl`). Never hard-code `250` —
///// always go through this constant so the unit, the storage layer, and
/// the widget all agree.
library;

const int kWaterGlassMl = 250;

/// Whole glasses in [volumeMl] — the one place the display count is derived
/// (250 ml → 1, 350 ml → 1, 0 ml → 0). The phone's water tracker and the
/// watch's `water_down` frame both call it, so they cannot disagree.
int waterGlassesFor(int volumeMl) => volumeMl ~/ kWaterGlassMl;

/// The most wrist taps one day's water row records (plan 94 D-3). A tap past
/// it is acknowledged but changes nothing; it bounds the row and the
/// `water_down` frame's `appliedTapIds` (schema `maxItems`).
const int kWatchWaterTapsPerDay = 500;
