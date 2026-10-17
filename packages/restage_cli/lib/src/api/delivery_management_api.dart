import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/discovery_models.dart' show RuntimePlane;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_routing_api.dart'
    show decodeSurfaceRoutingException;
import 'package:restage_cli/src/delivery/delivery_operations.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_shared/restage_shared.dart';

/// The service returned malformed or differently addressed delivery evidence.
@experimental
final class DeliveryManagementResponseException implements Exception {
  /// Creates a response-binding failure.
  const DeliveryManagementResponseException();

  @override
  String toString() => 'The service returned an invalid delivery result.';
}

/// Delivery management through the shared authenticated RPC transport.
@experimental
final class DeliveryManagementApi {
  /// Reuses the existing client, target resolution, and credentials.
  DeliveryManagementApi(this._api);

  final RestageApi _api;

  /// Dispatches a decoded public request through its typed operation wrapper.
  Future<CanonicalValue> invoke({
    required DeliveryOperation operation,
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required CanonicalValue request,
    bool acceptFit = false,
  }) {
    final addressed = switch (request) {
      PlacementDirectoryRequestV1 value => value.target,
      PlacementReadRequestV1 value => value.target,
      PlacementObservedHistoryReadRequestV1 value => value.target,
      PlacementSimulationPageRequestV1 value => value.target,
      DeliveryPolicyReadRequestV1 value => value.scope.target,
      DeliveryPolicyTimelineRequestV1 value => value.scope.target,
      DeliveryPolicyHistoryRequestV1 value => value.scope.target,
      DeliveryPolicyFitReadRequestV1 value =>
        value.scope?.target ?? value.publication!.surface.target,
      DeliveryPolicySimulationRequestV1 value => value.scope.target,
      DeliveryPolicyReviewRequestV1 value => value.scope.target,
      DeliveryPolicyPublishRequestV1 value => value.reviewRef.scope.target,
      DeliveryPolicyUndoReviewRequestV1 value => value.scope.target,
      _ => throw const FormatException('Unknown delivery request.'),
    };
    if (addressed != target) {
      throw const FormatException(
        'The delivery request is for another target.',
      );
    }
    Future<CanonicalValue> call<Q>(
      Future<CanonicalValue> Function({
        required String projectSlug,
        required String appSlug,
        required int environmentTargetId,
        required RuntimePlane runtimePlane,
        required int organizationId,
        required Q request,
      })
      method,
      Q payload,
    ) => method(
      projectSlug: projectSlug,
      appSlug: appSlug,
      environmentTargetId: target.environmentTargetId.value,
      runtimePlane: RuntimePlane.fromWireName(target.runtimePlane.name),
      organizationId: target.organizationId.value,
      request: payload,
    );
    return switch ((operation, request)) {
      (
        DeliveryOperation.placementList,
        final PlacementDirectoryRequestV1 value,
      ) =>
        call(readPage, value),
      (DeliveryOperation.placementRead, final PlacementReadRequestV1 value) =>
        call(readPlacement, value),
      (
        DeliveryOperation.placementObservedHistory,
        final PlacementObservedHistoryReadRequestV1 value,
      ) =>
        call(readObservedHistory, value),
      (
        DeliveryOperation.placementSimulate,
        final PlacementSimulationPageRequestV1 value,
      ) =>
        call(simulatePage, value),
      (
        DeliveryOperation.deliveryPolicyRead,
        final DeliveryPolicyReadRequestV1 value,
      ) =>
        call(readPolicy, value),
      (
        DeliveryOperation.deliveryPolicyTimeline,
        final DeliveryPolicyTimelineRequestV1 value,
      ) =>
        call(readTimeline, value),
      (
        DeliveryOperation.deliveryPolicyHistory,
        final DeliveryPolicyHistoryRequestV1 value,
      ) =>
        call(readHistory, value),
      (
        DeliveryOperation.deliveryPolicyFit,
        final DeliveryPolicyFitReadRequestV1 value,
      ) =>
        call(readFit, value),
      (
        DeliveryOperation.deliveryPolicySimulate,
        final DeliveryPolicySimulationRequestV1 value,
      ) =>
        call(simulatePolicy, value),
      (
        DeliveryOperation.deliveryPolicyReview,
        final DeliveryPolicyReviewRequestV1 value,
      ) =>
        call(review, value),
      (
        DeliveryOperation.deliveryPolicyPublish,
        final DeliveryPolicyPublishRequestV1 value,
      ) =>
        publish(
          projectSlug: projectSlug,
          appSlug: appSlug,
          environmentTargetId: target.environmentTargetId.value,
          runtimePlane: RuntimePlane.fromWireName(target.runtimePlane.name),
          organizationId: target.organizationId.value,
          request: value,
          acceptFit: acceptFit,
        ),
      (
        DeliveryOperation.deliveryPolicyUndoReview,
        final DeliveryPolicyUndoReviewRequestV1 value,
      ) =>
        call(undoReview, value),
      _ => throw const FormatException(
        'The request does not match the delivery operation.',
      ),
    };
  }

  /// Reads the authoritative placement directory at one exact target.
  Future<PlacementDirectoryPageV1> readPage({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required PlacementDirectoryRequestV1 request,
  }) => _policy(
    'readPage',
    owner: 'placementDirectory',
    maximumRequestBytes: kMaximumPlacementManagementRequestBytes,
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.target,
    request: request,
    decode: PlacementDirectoryPageV1.fromCanonicalBytes,
    matches: (result) =>
        result.target == request.target && result.items.length <= request.limit,
  );

  /// Reads one exact namespace-qualified placement and its original evidence.
  Future<PlacementReadV1> readPlacement({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required PlacementReadRequestV1 request,
  }) => _policy(
    'readPlacement',
    owner: 'placementDirectory',
    maximumRequestBytes: kMaximumPlacementManagementRequestBytes,
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.target,
    request: request,
    decode: PlacementReadV1.fromCanonicalBytes,
    matches: (result) =>
        result.target == request.target &&
        result.key == request.key &&
        (request.observedHistory == null ||
            result.observedHistory == null ||
            (result.observedHistory!.requestedFromMicros ==
                    request.observedHistory!.fromMicros &&
                result.observedHistory!.requestedUntilMicros ==
                    request.observedHistory!.untilMicros)),
  );

  /// Reads observed successful first paints with explicit UTC coverage.
  Future<PlacementObservedHistoryV1> readObservedHistory({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required PlacementObservedHistoryReadRequestV1 request,
  }) => _policy(
    'readObservedHistory',
    owner: 'placementDirectory',
    maximumRequestBytes: kMaximumPlacementManagementRequestBytes,
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.target,
    request: request,
    decode: PlacementObservedHistoryV1.fromCanonicalBytes,
    matches: (result) =>
        result.target == request.target &&
        result.placement == request.query.placement &&
        result.requestedFromMicros == request.query.fromMicros &&
        result.requestedUntilMicros == request.query.untilMicros,
  );

  /// Probes both delivery stages over only the caller's explicit bounded keys.
  Future<PlacementSimulationPageV1> simulatePage({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required PlacementSimulationPageRequestV1 request,
  }) => _policy(
    'simulatePage',
    owner: 'placementDirectory',
    maximumRequestBytes: kMaximumPlacementManagementRequestBytes,
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.target,
    request: request,
    decode: PlacementSimulationPageV1.fromCanonicalBytes,
    matches: (result) =>
        result.target == request.target &&
        result.evaluatedKeys.every(request.keys.contains),
  );

  /// Reads the current complete policy for an exact owner and family.
  Future<DeliveryPolicyReadV1> readPolicy({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicyReadRequestV1 request,
  }) => _policy(
    'readPolicy',
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.scope.target,
    request: request,
    decode: DeliveryPolicyReadV1.fromCanonicalBytes,
    matches: (result) => result.scope == request.scope,
  );

  /// Reads the server's authoritative schedule and rule ordering.
  Future<DeliveryPolicyTimelineV1> readTimeline({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicyTimelineRequestV1 request,
  }) => _policy(
    'readTimeline',
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.scope.target,
    request: request,
    decode: DeliveryPolicyTimelineV1.fromCanonicalBytes,
    matches: (result) => result.policy.scope == request.scope,
  );

  /// Reads immutable revisions and preserves the server's continuation.
  Future<DeliveryPolicyHistoryV1> readHistory({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicyHistoryRequestV1 request,
  }) => _policy(
    'readHistory',
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.scope.target,
    request: request,
    decode: DeliveryPolicyHistoryV1.fromCanonicalBytes,
    matches: (result) =>
        result.scope == request.scope &&
        (request.pageSize == null ||
            result.revisions.length <= request.pageSize!) &&
        (request.beforeOrdinal == null ||
            result.revisions.every(
              (row) => row.revision!.ordinal < request.beforeOrdinal!,
            )),
  );

  /// Reads fit for an exact owner or the exact reference returned by a push.
  Future<DeliveryPolicyFitReadV1> readFit({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicyFitReadRequestV1 request,
  }) => _policy(
    'readFit',
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.scope?.target ?? request.publication!.surface.target,
    request: request,
    decode: DeliveryPolicyFitReadV1.fromCanonicalBytes,
    matches: (result) =>
        result.request == request &&
        (request.pageSize == null ||
            result.entries.length <= request.pageSize!) &&
        result.entries.every(
          (entry) => request.scope != null
              ? entry.scope == request.scope
              : entry.publication == request.publication,
        ),
  );

  /// Simulates one policy using the supplied public request inputs.
  Future<DeliveryPolicySimulationV1> simulatePolicy({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicySimulationRequestV1 request,
  }) => _policy(
    'simulate',
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.scope.target,
    request: request,
    decode: DeliveryPolicySimulationV1.fromCanonicalBytes,
    matches: (result) => result.scope == request.scope,
  );

  /// Asks the server to freeze a complete candidate and its impact review.
  Future<DeliveryPolicyReviewV1> review({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicyReviewRequestV1 request,
  }) => _policy(
    'review',
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.scope.target,
    request: request,
    decode: DeliveryPolicyReviewV1.fromCanonicalBytes,
    matches: (result) =>
        result.scope == request.scope &&
        result.candidatePlan == request.candidatePlan &&
        result.expectedHeadOrdinal == request.expectedHeadOrdinal &&
        result.reason == request.reason,
  );

  /// Publishes only a server review, acknowledgement, and operation identity.
  Future<DeliveryPolicyPublishResultV1> publish({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicyPublishRequestV1 request,
    bool acceptFit = false,
  }) => _policy(
    'publish',
    acceptFit: acceptFit,
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.reviewRef.scope.target,
    request: request,
    decode: DeliveryPolicyPublishResultV1.fromCanonicalBytes,
    matches: (result) =>
        (result.revision == null ||
            result.revision!.scope == request.reviewRef.scope) &&
        (result.current == null ||
            result.current!.scope == request.reviewRef.scope),
  );

  /// Produces a complete restoration review; publishing remains a separate call.
  Future<DeliveryPolicyReviewV1> undoReview({
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required DeliveryPolicyUndoReviewRequestV1 request,
  }) => _policy(
    'undoReview',
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
    target: request.scope.target,
    request: request,
    decode: DeliveryPolicyReviewV1.fromCanonicalBytes,
    matches: (result) =>
        result.scope == request.scope &&
        result.expectedHeadOrdinal == request.expectedHeadOrdinal &&
        result.reason == request.reason,
  );

  Future<T> _policy<T>(
    String method, {
    String owner = 'deliveryPolicy',
    int maximumRequestBytes = kMaximumPlacementManagementRequestBytes,
    required String projectSlug,
    required String appSlug,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required int organizationId,
    required TargetCoordinate target,
    required CanonicalValue request,
    required T Function(List<int>) decode,
    required bool Function(T) matches,
    bool acceptFit = false,
  }) async {
    if (target.organizationId.value != organizationId ||
        target.environmentTargetId.value != environmentTargetId ||
        target.runtimePlane.name != runtimePlane.wireName) {
      throw const FormatException(
        'The delivery request is for another target.',
      );
    }
    final bytes = request.canonicalBytes;
    if (bytes.length > maximumRequestBytes) {
      throw const FormatException(
        'The delivery request exceeds its byte limit.',
      );
    }
    final Object? raw;
    try {
      raw = await _api.call(owner, method, {
        'projectSlug': projectSlug,
        'appSlug': appSlug,
        'environmentTargetId': environmentTargetId,
        'runtimePlane': runtimePlane.wireName,
        'organizationId': organizationId,
        'requestBytes': encodeByteDataWire(bytes),
        if (acceptFit) 'acceptFit': true,
      });
    } on RestageApiException catch (error) {
      final refusal = decodeSurfaceRoutingException(error.body);
      if (refusal != null) throw refusal;
      rethrow;
    }
    try {
      final result = decode(
        decodeByteDataWire(
          raw,
          maximumBytes: kMaximumPlacementResponseBytes,
          malformed: (_) => const DeliveryManagementResponseException(),
        ),
      );
      if (!matches(result)) throw const DeliveryManagementResponseException();
      return result;
    } on CanonicalFormatException {
      throw const DeliveryManagementResponseException();
    }
  }
}
