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
