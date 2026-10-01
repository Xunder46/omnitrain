/// The envelope every phone-origin message is built from, in one place.
///
/// `PROTOCOL.md` pins the shape of an envelope: version, id, type, origin and
/// `sentAt`, with `payload` carrying what the message is about. Those fields
/// belong to the protocol rather than to any one producer, so a sender cannot
/// spell them differently — the same reason the timestamp shape lives in
/// `wire_timestamps.dart`.
library;

import 'message_validator.dart';
import 'wire_timestamps.dart';

/// A message the phone originates.
///
/// [sessionId] is omitted when there is none to name: reference data has no
/// session, and neither does a receipt — a quick-log taken with no workout
/// running names one the phone does not hold, so naming it would be a claim the
/// receiver would act on.
Map<String, Object?> phoneEnvelope({
  required String type,
  required String messageId,
  required Map<String, Object?> payload,
  required DateTime sentAt,
  String? sessionId,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': ?sessionId,
  'type': type,
  'origin': 'phone',
  'sentAt': utcIso(sentAt),
  'payload': payload,
};
