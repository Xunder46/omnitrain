/// What one frame's send learned about whether the radio took it.
///
/// Plan: `docs/plans/2026-10-08-19b-honest-delivery-plan/`,
/// D-196. Scenario S-206.
///
/// [delivered] means the frame was handed to the platform radio while the
/// counterpart was reachable — the strongest claim the platform supports, and
/// it never means the counterpart applied it: neither the plugin's Dart surface
/// nor WCSession carries an acknowledgement. [undelivered] means the frame was
/// not handed over: the counterpart was not reachable, or the radio refused it.
///
/// No send throws for a non-delivery: the caller reads the result and decides
/// whether the frame is still owed (D-190, D-196).
library;

enum WatchDelivery { delivered, undelivered }
