import 'package:meta/meta.dart';

import 'measurement_assignment_diagnostics.dart';

/// Dependency-inversion seam for an exact service-owned assignment contract.
///
/// [Request] and [Result] belong to the frozen engine/service contract. The
/// SDK neither serializes a substitute carrier nor interprets assignment
/// selection or ITT state; it accepts only the diagnostic mapping supplied by
/// the internal composition owner.
@internal
abstract interface class MeasurementAssignmentTypedAdapter<
    Request extends Object, Result extends Object> {
  /// Delivers one exact engine/service request without SDK translation.
  Future<Result> deliver(Request request);

  /// Maps only the service result's delivery diagnostic into the SDK state.
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(Result result);
}

/// Fail-closed SDK transport for assignment delivery diagnostics.
@internal
final class MeasurementAssignmentTransport<Request extends Object,
    Result extends Object> {
  /// Creates a transport that never attempts an assignment request.
  const MeasurementAssignmentTransport.disabled()
      : _adapter = null,
        _mode = _MeasurementAssignmentTransportMode.disabled;

  /// Creates a transport with no assignment RPC adapter installed.
  const MeasurementAssignmentTransport.noAdapter()
      : _adapter = null,
        _mode = _MeasurementAssignmentTransportMode.noAdapter;

  /// Creates a transport backed by one injected assignment RPC adapter.
  const MeasurementAssignmentTransport.adapter(
    MeasurementAssignmentTypedAdapter<Request, Result> adapter,
  )   : _adapter = adapter,
        _mode = _MeasurementAssignmentTransportMode.adapter;

  final MeasurementAssignmentTypedAdapter<Request, Result>? _adapter;
  final _MeasurementAssignmentTransportMode _mode;

  /// Delivers [request] and retains only its closed diagnostic result.
  Future<MeasurementAssignmentDeliveryDiagnostic> deliver(
    Request request,
  ) async {
    switch (_mode) {
      case _MeasurementAssignmentTransportMode.disabled:
        return const MeasurementAssignmentDeliveryUnavailable(
          MeasurementAssignmentUnavailableReason.disabled,
        );
      case _MeasurementAssignmentTransportMode.noAdapter:
        return const MeasurementAssignmentDeliveryUnavailable(
          MeasurementAssignmentUnavailableReason.noAdapter,
        );
      case _MeasurementAssignmentTransportMode.adapter:
        break;
    }

    try {
      final adapter = _adapter!;
      final result = await adapter.deliver(request);
      return adapter.diagnosticFor(result);
    } on Object {
      return const MeasurementAssignmentDeliveryUnavailable(
        MeasurementAssignmentUnavailableReason.transportFailure,
      );
    }
  }
}

/// Internal installation point for the single configured assignment transport.
///
/// The type parameters prevent a caller from substituting a different request
/// or result contract for the installed service-owned adapter. A missing or
/// mismatched installation remains fail-closed instead of attempting a
/// fallback transport.
@internal
abstract final class MeasurementAssignmentTransportRegistry {
  static Object? _transport;

  /// Reads the installed transport for one exact request/result contract.
  static MeasurementAssignmentTransport<Request, Result>
      transportFor<Request extends Object, Result extends Object>() {
    final transport = _transport;
    if (transport is MeasurementAssignmentTransport<Request, Result>) {
      return transport;
    }
    return MeasurementAssignmentTransport<Request, Result>.noAdapter();
  }

  /// Replaces the sole installed transport, or restores fail-closed mode.
  static void install<Request extends Object, Result extends Object>(
    MeasurementAssignmentTypedAdapter<Request, Result>? adapter,
  ) {
    _transport = adapter == null
        ? null
        : MeasurementAssignmentTransport<Request, Result>.adapter(adapter);
  }

  /// Installs a focused test adapter through the same replacement seam.
  static void debugInstall<Request extends Object, Result extends Object>(
    MeasurementAssignmentTypedAdapter<Request, Result>? adapter,
  ) =>
      install(adapter);

  /// Clears the installed transport and restores fail-closed behavior.
  static void debugReset() => _transport = null;
}

enum _MeasurementAssignmentTransportMode { disabled, noAdapter, adapter }
