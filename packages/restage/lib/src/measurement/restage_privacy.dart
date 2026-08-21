import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'governed_measurement_transport.dart';

/// Explicit coordinator over independently-authoritative privacy domains.
///
/// It accepts only the closed request vocabulary and forwards opaque
/// domain-specific authority carriers. It is not a shared identity, retention,
/// deletion, or transaction authority.
final class RestagePrivacy {
  /// Internal construction used by the SDK facade.
  @internal
  RestagePrivacy.internal();

  /// Requests one domain-independent privacy operation.
  Future<RestagePrivacyReceiptV1> request(
    RestagePrivacyRequestV1 request,
  ) async {
    try {
      return await GovernedMeasurementPortRegistry.measurement.requestPrivacy(
        request,
      );
    } on Object {
      return unavailablePrivacyReceipt(request);
    }
  }
}
