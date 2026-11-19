/// Canonical constants for the daily water tracker.
///
/// Water has no goal — like macros and sodium, it is tracked and stored
/// for the historical record only. Each tap is a "step" of
/// [waterStepMlFor(unit)] milliliters, chosen by the volume unit from
/// `SettingsState`; the day's stored volume is the source of truth and
/// the on-screen total is derived at the display boundary. The watch
/// wire counts whole taps of the phone's current step
/// (`volumeMl ~/ step`), with [kWaterGlassMl] only the metric default.
/// Never hard-code `250` or `237` —
/// always go through these constants so the unit, the storage layer, and
/// the widget all agree.
library;

const int kWaterGlassMl = 250;

/// One step of 8 fl oz in milliliters (8 × 29.5735 = 236.59, rounded to
/// 237) — the per-tap amount when the preferred volume unit is fluid
/// ounces.
const int kWaterOzStepMl = 237;

/// The per-tap step for [unit]: [kWaterOzStepMl] when the normalised
/// unit is fluid ounces (`floz`, `fl oz` or `oz`, any case), else
/// [kWaterGlassMl]. An unknown or null unit is ml. Unit normalisation is
/// inlined here (like `SettingsState`, which cannot import
/// `UnitFormatter` back) so this constants file stays leaf-like.
int waterStepMlFor(String? unit) {
  final normalized = unit?.toLowerCase().trim();
  return normalized == 'floz' || normalized == 'fl oz' || normalized == 'oz'
      ? kWaterOzStepMl
      : kWaterGlassMl;
}

/// Whole taps of [stepMl] in [volumeMl] — the count of the day's water as
/// whole per-tap steps, floored (948 ml at 237 ml per tap is 4). The phone's
/// water tracker and the watch's `water_down` frame both call it, so they
/// cannot disagree. [stepMl] is the phone's current per-tap step; the
/// positional form (`volumeMl` only) falls back to [kWaterGlassMl], the
/// metric (kg) step — it is only the default, not the rule for every unit.
int waterGlassesFor(int volumeMl, [int stepMl = kWaterGlassMl]) =>
    volumeMl ~/ stepMl;

/// The most wrist taps one day's water row records (plan 94 D-3). A tap past
/// it is acknowledged but changes nothing; it bounds the row and the
/// `water_down` frame's `appliedTapIds` (schema `maxItems`).
const int kWatchWaterTapsPerDay = 500;
