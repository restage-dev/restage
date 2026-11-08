import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'governed_measurement_transport.dart';
import 'install_self_erasure.dart';

/// Explicit coordinator over independently-authoritative privacy domains.
///
/// It accepts only the closed request vocabulary and forwards opaque
/// domain-specific authority carriers. It is not a shared identity, retention,
/// deletion, or transaction authority.
final class RestagePrivacy {
  /// Internal construction used by the SDK facade.
  @internal
  RestagePrivacy.internal({
    InstallSelfErasureContext? Function()? selfErasureContext,
  }) : _selfErasureContext = selfErasureContext;

  final InstallSelfErasureContext? Function()? _selfErasureContext;
  final _selfErasure = InstallSelfErasure();

  /// Discards process-local state while preserving durable retry authority.
  @internal
  void debugResetSelfErasure() => _selfErasure.discardMemory();

  /// Requests an explicit operation, or erases this installation when omitted.
  Future<RestagePrivacyReceiptV1> request([
    RestagePrivacyRequestV1? request,
  ]) async {
    GovernedMeasurementPortRegistry.warnIfPrivacyUnavailable();
    if (request == null) {
      return _selfErasure.request(_selfErasureContext?.call());
    }
    try {
      return await GovernedMeasurementPortRegistry.measurement.requestPrivacy(
        request,
      );
    } on Object {
      return unavailablePrivacyReceipt(request);
    }
  }
}
