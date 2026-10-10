import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Authority classification for an authoring transport operation.
enum DeliveryOperationAccess { read, review, write }

/// Closed delivery operations and their actual CLI and MCP entry paths.
enum DeliveryOperation {
  placementList(
    'delivery placements list',
    'placementDirectory',
    'readPage',
    DeliveryOperationAccess.read,
  ),
  placementRead(
    'delivery placements show',
    'placementDirectory',
    'readPlacement',
    DeliveryOperationAccess.read,
  ),
  placementObservedHistory(
    'delivery observed-history',
    'placementDirectory',
    'readObservedHistory',
    DeliveryOperationAccess.read,
  ),
  placementSimulate(
    'delivery simulate',
    'placementDirectory',
    'simulatePage',
    DeliveryOperationAccess.read,
  ),
  deliveryPolicyRead(
    'delivery plan read',
    'deliveryPolicy',
    'readPolicy',
    DeliveryOperationAccess.read,
  ),
  deliveryPolicyTimeline(
    'delivery plan timeline',
    'deliveryPolicy',
    'readTimeline',
    DeliveryOperationAccess.read,
  ),
  deliveryPolicyHistory(
    'delivery plan history',
    'deliveryPolicy',
    'readHistory',
    DeliveryOperationAccess.read,
  ),
  deliveryPolicyFit(
    'delivery plan fit',
    'deliveryPolicy',
    'readFit',
    DeliveryOperationAccess.read,
  ),
  deliveryPolicySimulate(
    'delivery plan simulate',
    'deliveryPolicy',
    'simulate',
    DeliveryOperationAccess.read,
  ),
  deliveryPolicyReview(
    'delivery plan review',
    'deliveryPolicy',
    'review',
    DeliveryOperationAccess.review,
  ),
  deliveryPolicyPublish(
    'delivery plan publish',
    'deliveryPolicy',
    'publish',
    DeliveryOperationAccess.write,
  ),
  deliveryPolicyUndoReview(
    'delivery plan undo',
    'deliveryPolicy',
    'undoReview',
    DeliveryOperationAccess.review,
  ),
  placementSampleImport(
    'delivery sample import',
    null,
    null,
    DeliveryOperationAccess.read,
  ),
  placementSamplePrepare(
    'delivery sample review',
    'placementSample',
    'prepare',
    DeliveryOperationAccess.review,
  ),
  placementSampleStore(
    'delivery sample upload',
    'placementSample',
    'store',
    DeliveryOperationAccess.write,
  ),
  placementSampleBind(
    'delivery sample bind',
    'placementSample',
    'bind',
    DeliveryOperationAccess.write,
  ),
  placementSampleRead(
    'delivery sample show',
    'placementSample',
    'read',
    DeliveryOperationAccess.read,
  ),
  placementSampleReadImage(
    'delivery sample download',
    'placementSample',
    'readImage',
    DeliveryOperationAccess.read,
  ),
  placementSampleDelete(
    'delivery sample delete',
    'placementSample',
    'delete',
    DeliveryOperationAccess.write,
  );

  const DeliveryOperation(
    this.cliPath,
    this.rpcOwner,
    this.rpcMethod,
    this.access,
  );

  /// Actual registered command path after the binary name.
  final String cliPath;

  /// RPC endpoint owner; local import has no RPC operation.
  final String? rpcOwner;

  /// Exact RPC method; local import has no mutation or read RPC.
  final String? rpcMethod;

  /// Whether the operation reads, reviews, or writes authored state.
  final DeliveryOperationAccess access;

  /// Public operation identity.
  String get id => name;

  /// Actual registered MCP name.
  String get mcpName =>
      'restage_${name.replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match[0]!.toLowerCase()}')}';

  /// Review and storage operations change server-owned authoring state.
  bool get mutates => access != DeliveryOperationAccess.read;

  /// Every mutation uses the existing live-plane guard.
  bool get liveGuarded => mutates;

  /// Strict public decoder for the canonical request bytes.
  Object decodeRequest(List<int> bytes) => switch (this) {
    placementList => PlacementDirectoryRequestV1.fromCanonicalBytes(bytes),
    placementRead => PlacementReadRequestV1.fromCanonicalBytes(bytes),
    placementObservedHistory =>
      PlacementObservedHistoryReadRequestV1.fromCanonicalBytes(bytes),
    placementSimulate => PlacementSimulationPageRequestV1.fromCanonicalBytes(
      bytes,
    ),
    deliveryPolicyRead => DeliveryPolicyReadRequestV1.fromCanonicalBytes(bytes),
    deliveryPolicyTimeline =>
      DeliveryPolicyTimelineRequestV1.fromCanonicalBytes(bytes),
    deliveryPolicyHistory => DeliveryPolicyHistoryRequestV1.fromCanonicalBytes(
      bytes,
    ),
    deliveryPolicyFit => DeliveryPolicyFitReadRequestV1.fromCanonicalBytes(
      bytes,
    ),
    deliveryPolicySimulate =>
      DeliveryPolicySimulationRequestV1.fromCanonicalBytes(bytes),
    deliveryPolicyReview => DeliveryPolicyReviewRequestV1.fromCanonicalBytes(
      bytes,
    ),
    deliveryPolicyPublish => DeliveryPolicyPublishRequestV1.fromCanonicalBytes(
      bytes,
    ),
    deliveryPolicyUndoReview =>
      DeliveryPolicyUndoReviewRequestV1.fromCanonicalBytes(bytes),
    placementSampleImport => PlacementScreenCaptureV1.fromCanonicalBytes(bytes),
    placementSamplePrepare => PlacementSamplePrepareV1.fromCanonicalBytes(
      bytes,
    ),
    placementSampleStore => PlacementSampleStoreV1.fromCanonicalBytes(bytes),
    placementSampleBind => PlacementSampleBindV1.fromCanonicalBytes(bytes),
    placementSampleRead ||
    placementSampleReadImage => PlacementSampleReadV1.fromCanonicalBytes(bytes),
    placementSampleDelete => PlacementSampleDeleteV1.fromCanonicalBytes(bytes),
  };

  /// Strict public decoder for document results; an image result stays bytes.
  Object decodeResult(List<int> bytes) => switch (this) {
    placementList => PlacementDirectoryPageV1.fromCanonicalBytes(bytes),
    placementRead => PlacementReadV1.fromCanonicalBytes(bytes),
    placementObservedHistory => PlacementObservedHistoryV1.fromCanonicalBytes(
      bytes,
    ),
    placementSimulate => PlacementSimulationPageV1.fromCanonicalBytes(bytes),
    deliveryPolicyRead => DeliveryPolicyReadV1.fromCanonicalBytes(bytes),
    deliveryPolicyTimeline => DeliveryPolicyTimelineV1.fromCanonicalBytes(
      bytes,
    ),
    deliveryPolicyHistory => DeliveryPolicyHistoryV1.fromCanonicalBytes(bytes),
    deliveryPolicyFit => DeliveryPolicyFitReadV1.fromCanonicalBytes(bytes),
    deliveryPolicySimulate => DeliveryPolicySimulationV1.fromCanonicalBytes(
      bytes,
    ),
    deliveryPolicyReview || deliveryPolicyUndoReview =>
      DeliveryPolicyReviewV1.fromCanonicalBytes(bytes),
    deliveryPolicyPublish => DeliveryPolicyPublishResultV1.fromCanonicalBytes(
      bytes,
    ),
    placementSampleImport => PlacementSampleDraftV1.fromCanonicalBytes(bytes),
    placementSamplePrepare => PlacementSampleUploadTicketV1.fromCanonicalBytes(
      bytes,
    ),
    placementSampleStore => PlacementSampleStoredV1.fromCanonicalBytes(bytes),
    placementSampleBind => PlacementScreenSampleRefV1.fromCanonicalBytes(bytes),
    placementSampleRead => PlacementSampleReadResultV1.fromCanonicalBytes(
      bytes,
    ),
    placementSampleReadImage => validatePlacementScreenSamplePng(
      Uint8List.fromList(bytes),
    ).bytes,
    placementSampleDelete => PlacementSampleDeleteResultV1.fromCanonicalBytes(
      bytes,
    ),
  };
}

/// Operation lookup shared by the CLI and MCP parity census.
final deliveryOperations = Map<String, DeliveryOperation>.unmodifiable({
  for (final operation in DeliveryOperation.values) operation.id: operation,
});
