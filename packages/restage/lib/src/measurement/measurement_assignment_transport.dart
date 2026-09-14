import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import 'measurement_assignment_diagnostics.dart';

/// One assignment-delivery attempt: its diagnostic and the accepted assignment.
///
/// The assignment is the service's committed decision, retained verbatim. The
/// SDK never derives, repairs, or substitutes one.
@internal
final class MeasurementAssignmentDelivery {
  /// Creates one delivery outcome.
  const MeasurementAssignmentDelivery({
    required this.diagnostic,
    this.assignment,
  });

  /// Closed delivery state observed after the service's durable decision.
  final MeasurementAssignmentDeliveryDiagnostic diagnostic;

  /// The accepted assignment, or `null` when the service admitted none.
  final CanonicalSurfaceExperimentAssignmentV1? assignment;
}

/// Dependency-inversion seam for an exact service-owned assignment contract.
///
/// [Request] and [Result] belong to the frozen engine/service contract. The
/// SDK neither serializes a substitute carrier nor interprets assignment
/// selection or ITT state; it accepts only what the internal composition owner
/// maps out of the service result.
@internal
abstract interface class MeasurementAssignmentTypedAdapter<
    Request extends Object, Result extends Object> {
  /// Delivers one exact engine/service request without SDK translation.
  Future<Result> deliver(Request request);

  /// Maps only the service result's delivery diagnostic into the SDK state.
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(Result result);

  /// Reads the assignment the service committed, or `null` when it admitted
  /// none.
  CanonicalSurfaceExperimentAssignmentV1? assignmentFor(Result result);
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

  /// Delivers [request] and retains the accepted assignment with its
  /// diagnostic.
  Future<MeasurementAssignmentDelivery> deliver(Request request) async {
    switch (_mode) {
      case _MeasurementAssignmentTransportMode.disabled:
        return const MeasurementAssignmentDelivery(
          diagnostic: MeasurementAssignmentDeliveryUnavailable(
            MeasurementAssignmentUnavailableReason.disabled,
          ),
        );
      case _MeasurementAssignmentTransportMode.noAdapter:
        return const MeasurementAssignmentDelivery(
          diagnostic: MeasurementAssignmentDeliveryUnavailable(
            MeasurementAssignmentUnavailableReason.noAdapter,
          ),
        );
      case _MeasurementAssignmentTransportMode.adapter:
        break;
    }

    try {
      final adapter = _adapter!;
      final result = await adapter.deliver(request);
      return MeasurementAssignmentDelivery(
        diagnostic: adapter.diagnosticFor(result),
        assignment: adapter.assignmentFor(result),
      );
    } on Object {
      return const MeasurementAssignmentDelivery(
        diagnostic: MeasurementAssignmentDeliveryUnavailable(
          MeasurementAssignmentUnavailableReason.transportFailure,
        ),
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
