import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../restage_rpc_client/restage_rpc_client.dart';
import 'measurement_runtime_capture.dart';

/// One retained canonical request ready for delivery or a byte-identical retry.
@internal
final class MeasurementIngestSubmission {
  MeasurementIngestSubmission._(this.request);

  /// Validates [factFrame] once through the shared schema contract and encodes
  /// the exact authenticated request envelope.
  factory MeasurementIngestSubmission.fromFactFrame(
    MeasurementFactFrame factFrame,
  ) =>
      MeasurementIngestSubmission._(
        MeasurementIngestRequestV1.fromFactFrame(
          factFrame.validatedIngestFrameV1,
        ),
      );

  /// Shared canonical request retained for every retry attempt.
  final MeasurementIngestRequestV1 request;

  /// Exact unpadded base64url request carrier for the RPC adapter.
  String get canonicalRequestBase64 => request.canonicalRequestBase64;
}

/// Internal adapter seam for the SDK's authenticated measurement RPC.
@internal
abstract interface class MeasurementIngestRpcAdapter {
  /// Submits only the exact canonical request carrier.
  Future<MeasurementIngestRpcOutcome> submit(String canonicalRequestBase64);
}

/// Why a measurement delivery attempt did not produce a server-observed
/// outcome.
@internal
enum MeasurementIngestUnavailableReason {
  /// The resolved runtime configuration disabled measurement delivery.
  disabled,

  /// No HTTP/RPC adapter is available in this SDK composition.
  noAdapter,

  /// The authenticated session was absent, invalid, or changed.
  unauthenticated,

  /// The service denied access to the configured session.
  forbidden,

  /// The service reported a retryable unavailable condition.
  serviceUnavailable,

  /// The service returned a status outside the accepted closed mapping.
  unexpectedStatus,

  /// A successful response did not carry the strict receipt shape.
  malformedResponse,

  /// The adapter did not complete with a typed RPC outcome.
  transportFailure,
}

/// Typed result of one internal measurement-delivery attempt.
@internal
sealed class MeasurementIngestTransportOutcome {
  const MeasurementIngestTransportOutcome();
}

/// The service durably accepted the request.
@internal
final class MeasurementIngestTransportAccepted
    extends MeasurementIngestTransportOutcome {
  /// Creates an accepted transport outcome.
  const MeasurementIngestTransportAccepted({
    required this.receiptCanonicalBase64,
  });

  /// Exact canonical receipt carrier supplied by the service.
  final String receiptCanonicalBase64;
}

/// The service rejected the canonical request.
@internal
final class MeasurementIngestTransportRejected
    extends MeasurementIngestTransportOutcome {
  /// Creates a rejected transport outcome.
  const MeasurementIngestTransportRejected();
}

/// The service detected a durable conflict for the retry coordinate.
@internal
final class MeasurementIngestTransportConflict
    extends MeasurementIngestTransportOutcome {
  /// Creates a conflicting transport outcome.
  const MeasurementIngestTransportConflict();
}

/// Delivery did not create a server-observed measurement outcome.
@internal
final class MeasurementIngestTransportUnavailable
    extends MeasurementIngestTransportOutcome {
  /// Creates a non-interfering unavailable transport outcome.
  const MeasurementIngestTransportUnavailable(this.reason);

  /// Closed reason that is distinct from a server-observed zero.
  final MeasurementIngestUnavailableReason reason;
}

/// Internal transport for canonical measurement fact-frame ingestion.
///
/// The transport is deliberately unexported from the public SDK barrel. It
/// retains one canonical request carrier for every retry and maps only the
/// closed RPC outcome set into the SDK's internal delivery result.
@internal
final class MeasurementIngestTransport {
  /// Creates a transport that must not attempt delivery when disabled.
  const MeasurementIngestTransport.disabled()
      : _adapter = null,
        _mode = _MeasurementIngestTransportMode.disabled;

  /// Creates a transport with no HTTP/RPC adapter installed.
  const MeasurementIngestTransport.noAdapter()
      : _adapter = null,
        _mode = _MeasurementIngestTransportMode.noAdapter;

  /// Creates a transport connected to an internal HTTP/RPC adapter.
  const MeasurementIngestTransport.adapter(MeasurementIngestRpcAdapter adapter)
      : _adapter = adapter,
        _mode = _MeasurementIngestTransportMode.adapter;

  /// Creates the production adapter backed by the existing RPC client.
  MeasurementIngestTransport.rpc(RestageRpcClient client)
      : _adapter = _RestageRpcMeasurementIngestAdapter(client),
        _mode = _MeasurementIngestTransportMode.adapter;

  final MeasurementIngestRpcAdapter? _adapter;
  final _MeasurementIngestTransportMode _mode;

  /// Delivers [submission], retaining byte-identical request input on retries.
  Future<MeasurementIngestTransportOutcome> submit(
    MeasurementIngestSubmission submission,
  ) async {
    switch (_mode) {
      case _MeasurementIngestTransportMode.disabled:
        return const MeasurementIngestTransportUnavailable(
          MeasurementIngestUnavailableReason.disabled,
        );
      case _MeasurementIngestTransportMode.noAdapter:
        return const MeasurementIngestTransportUnavailable(
          MeasurementIngestUnavailableReason.noAdapter,
        );
      case _MeasurementIngestTransportMode.adapter:
        break;
    }

    try {
      final outcome = await _adapter!.submit(
        submission.canonicalRequestBase64,
      );
      return switch (outcome) {
        MeasurementIngestRpcAccepted() => MeasurementIngestTransportAccepted(
            receiptCanonicalBase64: outcome.receiptCanonicalBase64,
          ),
        MeasurementIngestRpcRejected() =>
          const MeasurementIngestTransportRejected(),
        MeasurementIngestRpcConflict() =>
          const MeasurementIngestTransportConflict(),
        MeasurementIngestRpcUnauthenticated() =>
          const MeasurementIngestTransportUnavailable(
            MeasurementIngestUnavailableReason.unauthenticated,
          ),
        MeasurementIngestRpcUnavailable(:final reason) =>
          MeasurementIngestTransportUnavailable(_mapUnavailableReason(reason)),
      };
    } on Object {
      return const MeasurementIngestTransportUnavailable(
        MeasurementIngestUnavailableReason.transportFailure,
      );
    }
  }
}

MeasurementIngestUnavailableReason _mapUnavailableReason(
  MeasurementIngestRpcUnavailableReason reason,
) =>
    switch (reason) {
      MeasurementIngestRpcUnavailableReason.forbidden =>
        MeasurementIngestUnavailableReason.forbidden,
      MeasurementIngestRpcUnavailableReason.serviceUnavailable =>
        MeasurementIngestUnavailableReason.serviceUnavailable,
      MeasurementIngestRpcUnavailableReason.unexpectedStatus =>
        MeasurementIngestUnavailableReason.unexpectedStatus,
      MeasurementIngestRpcUnavailableReason.malformedResponse =>
        MeasurementIngestUnavailableReason.malformedResponse,
      MeasurementIngestRpcUnavailableReason.transportFailure =>
        MeasurementIngestUnavailableReason.transportFailure,
    };

final class _RestageRpcMeasurementIngestAdapter
    implements MeasurementIngestRpcAdapter {
  const _RestageRpcMeasurementIngestAdapter(this._client);

  final RestageRpcClient _client;

  @override
  Future<MeasurementIngestRpcOutcome> submit(
    String canonicalRequestBase64,
  ) =>
      _client.ingestMeasurement(canonicalRequestBase64);
}

enum _MeasurementIngestTransportMode { disabled, noAdapter, adapter }
