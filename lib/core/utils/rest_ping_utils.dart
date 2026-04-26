/// Returns true when a rest-period ping alert should fire.
///
/// Parameters:
/// - [elapsed]   seconds that have elapsed in the current rest window
/// - [interval]  configured ping interval in seconds (0 = disabled)
/// - [lastPinged] the elapsed-seconds value at which the last ping fired
///               (0 means no ping has fired yet in this rest window)
bool shouldFireRestPing({
  required int elapsed,
  required int interval,
  required int lastPinged,
}) {
  if (interval == 0) return false;
  if (elapsed == 0) return false;
  if (elapsed % interval != 0) return false;
  return elapsed > lastPinged;
}
