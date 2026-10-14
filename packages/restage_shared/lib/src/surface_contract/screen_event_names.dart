import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kLocalValueSetEventName, kMeasurementPublicationTapEventNameV1;

/// Purchase and restore event names reserved by the runtime. Publishing
/// refuses a surface that emits one, and the runtime drops them.
const Set<String> kReservedCommerceEventNames = <String>{
  'purchase',
  'restore',
  'restage.purchase',
  'restage.restore',
  'restage.purchase.succeeded',
  'restage.purchase.pending',
  'restage.purchase.cancelled',
  'restage.purchase.failed',
  'restage.restore.succeeded',
  'restage.restore.noPurchases',
  'restage.restore.failed',
};

/// Events a screen may emit that its event contract never covers: the
/// runtime consumes them before validating screen events.
const Set<String> kScreenEventNamesOutsideContract = <String>{
  kLocalValueSetEventName,
  kMeasurementPublicationTapEventNameV1,
};
