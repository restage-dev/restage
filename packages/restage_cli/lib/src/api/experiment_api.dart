import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// A route answered with a result addressed to another operation, correlation,
/// or target.
///
/// The exception carries no values: the caller reports a deterministic error
/// without reflecting an unverified response back to the operator.
@experimental
final class ExperimentResponseMismatchException implements Exception {
  /// Creates the response-binding failure.
  const ExperimentResponseMismatchException();

  @override
  String toString() =>
      'The experiment route answered with a result bound to another '
      'operation, correlation, or target.';
}

/// A paged read returned a cursor the drain had already followed.
///
/// Following it again would not terminate, so the drain stops instead.
@experimental
final class ExperimentPageCursorRepeatedException implements Exception {
  /// Creates the repeated-cursor failure.
  const ExperimentPageCursorRepeatedException();

  @override
  String toString() =>
      'The experiment route repeated a page cursor the read had already '
      'followed.';
}

/// One drained multi-page read: every page accepted, or the refusal that
/// stopped it.
@experimental
sealed class ExperimentPageDrain<T> {
  const ExperimentPageDrain();
}

/// Every page of a drain was accepted.
@experimental
final class ExperimentPagesAccepted<T> extends ExperimentPageDrain<T> {
  /// Creates the accepted drain over [value].
  const ExperimentPagesAccepted(this.value);

  /// The accumulation across every drained page.
  final T value;
}

/// A page refused, ending the drain at that page.
@experimental
final class ExperimentPagesRefused<T> extends ExperimentPageDrain<T> {
  /// Creates the refused drain carrying [refusal].
  const ExperimentPagesRefused(this.refusal);

  /// The refusal the route answered the interrupted page with.
  final ExperimentAuthoringRefusedV1 refusal;
}

/// Discovery accumulated across every page of one drain.
@experimental
final class ExperimentDiscovery {
  /// Creates a drained discovery projection.
  const ExperimentDiscovery({
    required this.target,
    required this.organizationLabel,
    required this.appLabel,
    required this.environmentLabel,
    required this.namedEnvironments,
    required this.runtimePlanes,
    required this.surfaceCapabilities,
    required this.metricCapabilities,
    required this.actionAvailability,
  });

  /// The exact target every drained page addressed.
  final TargetCoordinate target;

  /// Organization label carried by the last page.
  final String organizationLabel;

  /// App label carried by the last page.
  final String appLabel;

  /// Environment label carried by the last page.
  final String environmentLabel;

  /// Selectable named environments in source order.
  final List<ExperimentNamedEnvironmentOptionV1> namedEnvironments;

  /// Selectable runtime planes in source order.
  final List<ExperimentRuntimePlaneOptionV1> runtimePlanes;

  /// Compatible published surfaces, keyed by identity and revision together.
  final List<ExperimentSurfaceCapabilityV1> surfaceCapabilities;

  /// Metric capabilities in source order.
  final List<ExperimentMetricCapabilityV1> metricCapabilities;

  /// Action availability carried by the last page.
  final List<ExperimentActionAvailabilityV1> actionAvailability;
}

/// Semantic experiment authoring over the shared authenticated transport.
///
/// Requests and results are the public schema's own documents, decoded by the
/// schema itself, so this client and the generated adapter read one byte-exact
/// contract. Authority is the route's: this client forwards a refusal as it
/// arrives and never pre-authorizes an action.
@experimental
final class ExperimentApi {
  /// Creates a client over the shared RPC transport.
  ExperimentApi(this._api, {int maximumAttempts = 3})
    : _maximumAttempts = maximumAttempts {
    if (maximumAttempts < 1) {
      throw ArgumentError.value(
        maximumAttempts,
        'maximumAttempts',
        'Must be at least 1',
      );
    }
  }

  final RestageApi _api;
  final int _maximumAttempts;

  /// Sends [request] to [target] and returns the route's typed result.
  ///
  /// An outcome that leaves the operation unapplied is retried with the same
  /// canonical bytes, so a retried write reuses its idempotency key exactly.
  Future<ExperimentAuthoringResultV1> execute({
    required ExperimentAuthoringRequestV1 request,
    required TargetCoordinate target,
  }) async {
    final arguments = <String, dynamic>{
      'organizationId': target.organizationId.value,
      'appId': target.appId.value,
      'environmentTargetId': target.environmentTargetId.value,
      'namedEnvironmentId': target.namedEnvironmentId.value,
      'runtimePlane': target.runtimePlane.wireName,
      'requestBytes': encodeByteDataWire(request.canonicalBytes),
    };

    for (var attempt = 1; ; attempt++) {
      final bool retryable;
      try {
        final result = _decodeResult(
          await _api.call(_endpointName, request.operation.wireName, arguments),
        );
        _requireBoundTo(result, request: request, target: target);
        retryable =
            result is ExperimentAuthoringRefusedV1 && result.refusal.retryable;
        if (!retryable || attempt == _maximumAttempts) return result;
      } on RestageApiException catch (error) {
        if (error.statusCode < 500 || attempt == _maximumAttempts) rethrow;
      } on http.ClientException {
        if (attempt == _maximumAttempts) rethrow;
      }
    }
  }

  /// Drains discovery at [target] until the route reports no further page.
  ///
  /// Sections concatenate in source order across pages; an empty continuation
  /// page is ordinary. Surfaces are kept by identity and revision together, so
  /// one surface with two revisions contributes both.
  Future<ExperimentPageDrain<ExperimentDiscovery>> discoverEveryPage({
    required TargetCoordinate target,
    required String correlationId,
    int pageSize = 100,
  }) async {
    final namedEnvironments = <ExperimentNamedEnvironmentOptionV1>[];
    final runtimePlanes = <ExperimentRuntimePlaneOptionV1>[];
    final surfaceCapabilities = <ExperimentSurfaceCapabilityV1>[];
    final metricCapabilities = <ExperimentMetricCapabilityV1>[];
    final seenSurfaces = <(String, String)>{};
    ExperimentTargetDiscoveryV1? lastPage;
    final seenCursors = <String>{};
    String? cursor;

    do {
      final result = await execute(
        request: experimentRequest(
          operation:
              ExperimentAuthoringOperationV1.discoverTargetsAndCapabilities,
          correlationId: correlationId,
          payload: {'pageSize': pageSize, 'pageCursor': ?cursor},
        ),
        target: target,
      );
      if (result is ExperimentAuthoringRefusedV1) {
        return ExperimentPagesRefused(result);
      }
      final page =
          (result as ExperimentAuthoringAcceptedV1).response
              as ExperimentTargetDiscoveryV1;
      namedEnvironments.addAll(page.namedEnvironments);
      runtimePlanes.addAll(page.runtimePlanes);
      metricCapabilities.addAll(page.metricCapabilities);
      for (final capability in page.surfaceCapabilities) {
        final key = (
          capability.surfaceReference.surfaceId.value,
          capability.surfaceReference.surfaceRevisionId.value,
        );
        if (seenSurfaces.add(key)) surfaceCapabilities.add(capability);
      }
      lastPage = page;
      cursor = _nextCursor(page.nextPageCursor, seenCursors);
    } while (cursor != null);

    return ExperimentPagesAccepted(
      ExperimentDiscovery(
        target: lastPage.target,
        organizationLabel: lastPage.organizationLabel,
        appLabel: lastPage.appLabel,
        environmentLabel: lastPage.environmentLabel,
        namedEnvironments: List.unmodifiable(namedEnvironments),
        runtimePlanes: List.unmodifiable(runtimePlanes),
        surfaceCapabilities: List.unmodifiable(surfaceCapabilities),
        metricCapabilities: List.unmodifiable(metricCapabilities),
        actionAvailability: List.unmodifiable(lastPage.actionAvailability),
      ),
    );
  }

  /// Drains the experiment list at [target] until no further page is reported.
  Future<ExperimentPageDrain<List<ExperimentListEntryV1>>> listEveryPage({
    required TargetCoordinate target,
    required String correlationId,
    int pageSize = 100,
  }) async {
    final entries = <ExperimentListEntryV1>[];
    final seenCursors = <String>{};
    String? cursor;

    do {
      final result = await execute(
        request: experimentRequest(
          operation: ExperimentAuthoringOperationV1.listExperiments,
          correlationId: correlationId,
          payload: {'pageSize': pageSize, 'pageCursor': ?cursor},
        ),
        target: target,
      );
      if (result is ExperimentAuthoringRefusedV1) {
        return ExperimentPagesRefused(result);
      }
      final page =
          (result as ExperimentAuthoringAcceptedV1).response
              as ExperimentListViewV1;
      entries.addAll(page.experiments);
      cursor = _nextCursor(page.nextPageCursor, seenCursors);
    } while (cursor != null);

    return ExperimentPagesAccepted(List.unmodifiable(entries));
  }
}

/// Builds one strict request document for a read operation.
@experimental
ExperimentAuthoringRequestV1 experimentRequest({
  required ExperimentAuthoringOperationV1 operation,
  required String correlationId,
  required Map<String, Object?> payload,
  String? idempotencyKey,
}) => ExperimentAuthoringRequestV1.fromJson({
  'correlationId': correlationId,
  'idempotencyKey': ?idempotencyKey,
  'kind': 'experimentAuthoringRequest',
  'operation': operation.wireName,
  'payload': payload,
  'schemaVersion': kMeasurementSchemaVersion,
});

/// Returns a deterministic correlation for a caller-retained write retry key.
///
/// The digest covers a canonical request marker, operation, payload, and key.
@experimental
String experimentRetryCorrelationId({
  required ExperimentAuthoringOperationV1 operation,
  required Map<String, Object?> payload,
  required String idempotencyKey,
}) {
  final retryRequest = experimentRequest(
    operation: operation,
    correlationId: _retryCorrelationIdentityMarker,
    payload: payload,
    idempotencyKey: idempotencyKey,
  );
  return 'correlation-${crypto.sha256.convert(retryRequest.canonicalBytes)}';
}

const _retryCorrelationIdentityMarker = 'retry-correlation-identity-v1';

const _endpointName = 'experimentAuthoring';

/// The next page cursor, refusing one the drain has already followed.
String? _nextCursor(String? cursor, Set<String> seen) {
  if (cursor == null) return null;
  if (!seen.add(cursor)) {
    throw const ExperimentPageCursorRepeatedException();
  }
  return cursor;
}

void _requireBoundTo(
  ExperimentAuthoringResultV1 result, {
  required ExperimentAuthoringRequestV1 request,
  required TargetCoordinate target,
}) {
  if (result.operation != request.operation ||
      result.correlationId != request.correlationId) {
    throw const ExperimentResponseMismatchException();
  }
  if (result is! ExperimentAuthoringAcceptedV1) return;
  // Every response that names a target must name the one that was requested.
  if (result.response case final ExperimentTargetBoundViewV1 view
      when view.target != target) {
    throw const ExperimentResponseMismatchException();
  }
}

ExperimentAuthoringResultV1 _decodeResult(Object? rawResponse) =>
    ExperimentAuthoringResultV1.fromCanonicalBytes(
      decodeByteDataWire(
        rawResponse,
        maximumBytes: experimentAuthoringMaximumResultBytes,
        malformed: (detail) =>
            CanonicalFormatException('The experiment result $detail'),
      ),
    );
