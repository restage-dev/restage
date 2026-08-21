import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/observations.dart';
import 'package:restage_measurement_schema/src/publication_binding.dart';

/// Maximum accepted canonical request payload before decoding or allocation.
const int measurementIngestMaximumRequestBytes = 512 * 1024;

/// Maximum accepted embedded canonical fact frame before decoding or
/// allocation.
const int measurementIngestMaximumFactFrameBytes = 256 * 1024;

/// Maximum canonical receipt bytes accepted from the sole ingest route.
///
/// A receipt repeats only bounded request-derived provenance plus a small
/// server-owned completion record, so it remains bounded by the owning
/// request contract rather than introducing an independent transport limit.
const int measurementIngestMaximumReceiptBytes =
    measurementIngestMaximumRequestBytes;

const int _maximumPresentedPoints = 1024;

const int _maximumInteractionCounters = 256;

const int _maximumMissingnessEntries = 256;

const int _maximumCounterValue = 65535;

const String _digestPattern = r'^[0-9a-f]{64}$';

const String _noncePattern = r'^[A-Za-z0-9._:-]{1,128}$';

const String _lineagePattern = r'^[a-z0-9][a-z0-9._-]{0,127}$';

/// A closed decode or validation failure at the measurement ingest boundary.
final class MeasurementIngestCodecException implements Exception {
  /// Creates a failure with a stable local reason.
  const MeasurementIngestCodecException(this.reason);

  /// Machine-readable local failure reason.
  final String reason;

  @override
  String toString() => 'MeasurementIngestCodecException($reason)';
}

/// Exact canonical request and its nested, validated subjectless fact frame.
final class MeasurementIngestRequestV1 {
  MeasurementIngestRequestV1._({
    required Uint8List canonicalBytes,
    required this.canonicalRequestBase64,
    required this.requestSha256,
    required this.factFrame,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes);

  /// Encodes [factFrame] as the exact authenticated ingest request envelope.
  ///
  /// The frame is already validated and retains its one raw SHA-256 value, so
  /// encoding never re-hashes or re-decodes the frame bytes.
  factory MeasurementIngestRequestV1.fromFactFrame(
    MeasurementFactFrameV1 factFrame,
  ) {
    final canonicalBytes = CanonicalJsonCodec.encode({
      'factFrameCanonicalBase64': _base64Url(factFrame._canonicalBytes),
      'factFrameSha256': factFrame.frameSha256.hex,
      'kind': 'authenticatedMeasurementIngestRequest',
      'schemaVersion': kMeasurementSchemaVersion,
    });
    return MeasurementIngestRequestV1._(
      canonicalBytes: canonicalBytes,
      canonicalRequestBase64: _base64Url(canonicalBytes),
      requestSha256: _rawSha256(canonicalBytes).hex,
      factFrame: factFrame,
    );
  }

  /// Strictly decodes a canonical request transported as unpadded base64url.
  factory MeasurementIngestRequestV1.fromBase64(String encoded) {
    final canonicalBytes = _decodeBase64Url(
      encoded,
      path: 'authenticatedMeasurementIngestRequest',
      maximumBytes: measurementIngestMaximumRequestBytes,
    );
    try {
      final reader = _IngestObjectReader(
        decodeCanonicalObject(canonicalBytes),
        allowedKeys: const {
          'factFrameCanonicalBase64',
          'factFrameSha256',
          'kind',
          'schemaVersion',
        },
        requiredKeys: const {
          'factFrameCanonicalBase64',
          'factFrameSha256',
          'kind',
          'schemaVersion',
        },
        path: 'authenticatedMeasurementIngestRequest',
      );
      _requireDocument(reader, 'authenticatedMeasurementIngestRequest');
      final frameBytes = _decodeBase64Url(
        reader.string('factFrameCanonicalBase64'),
        path: 'authenticatedMeasurementIngestRequest.factFrameCanonicalBase64',
        maximumBytes: measurementIngestMaximumFactFrameBytes,
      );
      final claimedDigest = _requireSha256(
        reader.string('factFrameSha256'),
        'authenticatedMeasurementIngestRequest.factFrameSha256',
      );
      final factFrame = MeasurementFactFrameV1.fromCanonicalBytes(frameBytes);
      if (factFrame.frameSha256.hex != claimedDigest) {
        throw const MeasurementIngestCodecException('frame_hash_mismatch');
      }
      return MeasurementIngestRequestV1._(
        canonicalBytes: canonicalBytes,
        canonicalRequestBase64: encoded,
        requestSha256: _rawSha256(canonicalBytes).hex,
        factFrame: factFrame,
      );
    } on MeasurementIngestCodecException {
      rethrow;
    } on Object {
      throw const MeasurementIngestCodecException('invalid_canonical_request');
    }
  }

  final Uint8List _canonicalBytes;

  /// Exact canonical request bytes, returned as a defensive copy.
  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  /// Exact unpadded base64url carrier for [canonicalBytes].
  final String canonicalRequestBase64;

  /// Raw SHA-256 of [canonicalBytes].
  final String requestSha256;

  /// Validated fact frame embedded by this request.
  final MeasurementFactFrameV1 factFrame;

  /// Exact embedded fact-frame bytes, returned as a defensive copy.
  Uint8List get factFrameCanonicalBytes => factFrame.canonicalBytes;

  /// Raw SHA-256 of the exact embedded fact-frame bytes.
  String get factFrameSha256 => factFrame.frameSha256.hex;
}

/// Exact canonical receipt emitted after one authenticated ingest succeeds.
///
/// The receipt is a closed server assertion over the accepted request and its
/// publication binding. It contains no local journal/session coordinate.
final class MeasurementIngestReceiptV1 extends CanonicalValue {
  MeasurementIngestReceiptV1._({
    required Uint8List canonicalBytes,
    required this.acceptedObservationCount,
    required this.captureSessionNonce,
    required this.factFrameSha256,
    required this.isFinal,
    required this.persistedAtMicros,
    required this.publicationBindingReference,
    required this.receiptId,
    required this.requestSha256,
    required this.rootObservationUnitKey,
    required this.sequence,
  })  : _canonicalBytes = Uint8List.fromList(canonicalBytes),
        receiptSha256 = _rawSha256(canonicalBytes).hex {
    if (_canonicalBytes.isEmpty ||
        _canonicalBytes.length > measurementIngestMaximumReceiptBytes ||
        acceptedObservationCount < 0 ||
        acceptedObservationCount > kMaximumPortableJsonInteger ||
        !RegExp(_noncePattern).hasMatch(captureSessionNonce) ||
        !RegExp(_digestPattern).hasMatch(factFrameSha256) ||
        persistedAtMicros <= 0 ||
        !RegExp(_lineagePattern).hasMatch(receiptId) ||
        !RegExp(_digestPattern).hasMatch(requestSha256) ||
        !_isObservationUnitKey(rootObservationUnitKey) ||
        sequence <= 0) {
      throw ArgumentError('Invalid measurement ingest receipt');
    }
  }

  /// Encodes one accepted server receipt using the closed canonical shape.
  factory MeasurementIngestReceiptV1.accepted({
    required int acceptedObservationCount,
    required String captureSessionNonce,
    required String factFrameSha256,
    required bool isFinal,
    required int persistedAtMicros,
    required MeasurementPublicationBindingReferenceV1
        publicationBindingReference,
    required String receiptId,
    required String requestSha256,
    required String rootObservationUnitKey,
    required int sequence,
  }) {
    final canonicalBytes = CanonicalJsonCodec.encode({
      'acceptedObservationCount': acceptedObservationCount,
      'captureSessionNonce': captureSessionNonce,
      'disposition': 'accepted',
      'factFrameSha256': factFrameSha256,
      'final': isFinal,
      'kind': 'measurementIngestReceipt',
      'persistedAtMicros': persistedAtMicros,
      'publicationBindingReference': publicationBindingReference.toJson(),
      'receiptId': receiptId,
      'requestSha256': requestSha256,
      'rootObservationUnitKey': rootObservationUnitKey,
      'schemaVersion': kMeasurementSchemaVersion,
      'sequence': sequence,
    });
    return MeasurementIngestReceiptV1._(
      canonicalBytes: canonicalBytes,
      acceptedObservationCount: acceptedObservationCount,
      captureSessionNonce: captureSessionNonce,
      factFrameSha256: factFrameSha256,
      isFinal: isFinal,
      persistedAtMicros: persistedAtMicros,
      publicationBindingReference: publicationBindingReference,
      receiptId: receiptId,
      requestSha256: requestSha256,
      rootObservationUnitKey: rootObservationUnitKey,
      sequence: sequence,
    );
  }

  /// Strictly decodes canonical receipt bytes from the sole ingest route.
  factory MeasurementIngestReceiptV1.fromCanonicalBytes(
    List<int> suppliedBytes,
  ) {
    if (suppliedBytes.isEmpty ||
        suppliedBytes.length > measurementIngestMaximumReceiptBytes) {
      throw const MeasurementIngestCodecException('receipt_too_large');
    }
    final canonicalBytes = Uint8List.fromList(suppliedBytes);
    try {
      final reader = _IngestObjectReader(
        decodeCanonicalObject(canonicalBytes),
        allowedKeys: const {
          'acceptedObservationCount',
          'captureSessionNonce',
          'disposition',
          'factFrameSha256',
          'final',
          'kind',
          'persistedAtMicros',
          'publicationBindingReference',
          'receiptId',
          'requestSha256',
          'rootObservationUnitKey',
          'schemaVersion',
          'sequence',
        },
        requiredKeys: const {
          'acceptedObservationCount',
          'captureSessionNonce',
          'disposition',
          'factFrameSha256',
          'final',
          'kind',
          'persistedAtMicros',
          'publicationBindingReference',
          'receiptId',
          'requestSha256',
          'rootObservationUnitKey',
          'schemaVersion',
          'sequence',
        },
        path: 'measurementIngestReceipt',
      );
      _requireDocument(reader, 'measurementIngestReceipt');
      if (reader.string('disposition') != 'accepted') {
        throw const MeasurementIngestCodecException(
          'invalid_receipt_disposition',
        );
      }
      final receipt = MeasurementIngestReceiptV1._(
        canonicalBytes: canonicalBytes,
        acceptedObservationCount: reader.integer('acceptedObservationCount'),
        captureSessionNonce: reader.string('captureSessionNonce'),
        factFrameSha256: _requireSha256(
          reader.string('factFrameSha256'),
          'measurementIngestReceipt.factFrameSha256',
        ),
        isFinal: reader.boolean('final'),
        persistedAtMicros: reader.integer('persistedAtMicros'),
        publicationBindingReference:
            MeasurementPublicationBindingReferenceV1.fromJson(
          reader.object('publicationBindingReference'),
        ),
        receiptId: reader.string('receiptId'),
        requestSha256: _requireSha256(
          reader.string('requestSha256'),
          'measurementIngestReceipt.requestSha256',
        ),
        rootObservationUnitKey: reader.string('rootObservationUnitKey'),
        sequence: reader.integer('sequence'),
      );
      if (!_sameBytes(
        CanonicalJsonCodec.encode(receipt.toJson()),
        canonicalBytes,
      )) {
        throw const MeasurementIngestCodecException('noncanonical_receipt');
      }
      return receipt;
    } on MeasurementIngestCodecException {
      rethrow;
    } on Object {
      throw const MeasurementIngestCodecException('invalid_canonical_receipt');
    }
  }

  /// Strictly decodes the unpadded canonical receipt carrier returned by HTTP.
  factory MeasurementIngestReceiptV1.fromBase64(String encoded) =>
      MeasurementIngestReceiptV1.fromCanonicalBytes(
        _decodeBase64Url(
          encoded,
          path: 'measurementIngestReceipt',
          maximumBytes: measurementIngestMaximumReceiptBytes,
        ),
      );

  final Uint8List _canonicalBytes;

  /// Number of observations committed by this accepted request.
  final int acceptedObservationCount;

  /// Exact capture-session nonce accepted by the server.
  final String captureSessionNonce;

  /// Raw SHA-256 of the accepted canonical fact frame.
  final String factFrameSha256;

  /// Whether the accepted frame finalizes its capture session.
  final bool isFinal;

  /// Server-owned persistence time for the accepted receipt.
  final int persistedAtMicros;

  /// Exact immutable publication binding asserted by the receipt.
  final MeasurementPublicationBindingReferenceV1 publicationBindingReference;

  /// Opaque server-owned receipt coordinate.
  final String receiptId;

  /// Raw SHA-256 of the exact canonical request the server accepted.
  final String requestSha256;

  /// Opaque root observation-unit coordinate issued by the server.
  final String rootObservationUnitKey;

  /// Accepted monotone frame sequence.
  final int sequence;

  /// Raw SHA-256 of [canonicalBytes].
  final String receiptSha256;

  /// Exact canonical receipt bytes, returned as a defensive copy.
  @override
  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  /// Exact unpadded base64url carrier for [canonicalBytes].
  String get canonicalReceiptBase64 => _base64Url(_canonicalBytes);

  @override
  Map<String, Object?> toJson() => {
        'acceptedObservationCount': acceptedObservationCount,
        'captureSessionNonce': captureSessionNonce,
        'disposition': 'accepted',
        'factFrameSha256': factFrameSha256,
        'final': isFinal,
        'kind': 'measurementIngestReceipt',
        'persistedAtMicros': persistedAtMicros,
        'publicationBindingReference': publicationBindingReference.toJson(),
        'receiptId': receiptId,
        'requestSha256': requestSha256,
        'rootObservationUnitKey': rootObservationUnitKey,
        'schemaVersion': kMeasurementSchemaVersion,
        'sequence': sequence,
      };
}

/// Strict, bounded, subjectless measurement fact frame.
final class MeasurementFactFrameV1 {
  MeasurementFactFrameV1._({
    required Uint8List canonicalBytes,
    required this.bounds,
    required this.captureSessionNonce,
    required this.facts,
    required this.isFinal,
    required this.missingness,
    required this.publishedContext,
    required this.rootPresentation,
    required this.sequence,
    required this.truncation,
  })  : _canonicalBytes = Uint8List.fromList(canonicalBytes),
        frameSha256 = _rawSha256(canonicalBytes);

  /// Strictly decodes the canonical bytes for one accepted fact frame.
  factory MeasurementFactFrameV1.fromCanonicalBytes(List<int> suppliedBytes) {
    if (suppliedBytes.length > measurementIngestMaximumFactFrameBytes) {
      throw const MeasurementIngestCodecException('frame_too_large');
    }
    final canonicalBytes = Uint8List.fromList(suppliedBytes);
    try {
      final reader = _IngestObjectReader(
        decodeCanonicalObject(canonicalBytes),
        allowedKeys: const {
          'bounds',
          'captureSessionNonce',
          'facts',
          'finality',
          'kind',
          'missingness',
          'publishedContext',
          'retryPolicy',
          'rootPresentation',
          'schemaVersion',
          'sequence',
          'truncation',
        },
        requiredKeys: const {
          'bounds',
          'captureSessionNonce',
          'facts',
          'finality',
          'kind',
          'missingness',
          'publishedContext',
          'retryPolicy',
          'rootPresentation',
          'schemaVersion',
          'sequence',
          'truncation',
        },
        path: 'measurementFactFrame',
      );
      _requireDocument(reader, 'measurementFactFrame');
      final bounds = MeasurementFactBounds.fromJson(reader.object('bounds'));
      final nonce = reader.string('captureSessionNonce');
      if (!RegExp(_noncePattern).hasMatch(nonce)) {
        throw const MeasurementIngestCodecException('invalid_capture_nonce');
      }
      final sequence = reader.integer('sequence');
      if (sequence <= 0) {
        throw const MeasurementIngestCodecException('invalid_sequence');
      }
      final facts = _decodeFacts(reader.list('facts'), bounds);
      final missingness =
          _decodeMissingness(reader.list('missingness'), bounds);
      final publishedContext = ExactMeasurementPublicationContextRefV1.fromJson(
        reader.object('publishedContext'),
      );
      final rootPresentation = MeasurementSuccessfulRootPresentationV1.fromJson(
        reader.object('rootPresentation'),
      );
      final isFinal = _decodeFinality(reader.object('finality'));
      _decodeRetryPolicy(reader.object('retryPolicy'));
      final truncation = MeasurementTruncation.fromJson(
        reader.object('truncation'),
        maximumCounterValue: bounds.maximumCounterValue,
      );
      return MeasurementFactFrameV1._(
        canonicalBytes: canonicalBytes,
        bounds: bounds,
        captureSessionNonce: nonce,
        facts: facts,
        isFinal: isFinal,
        missingness: missingness,
        publishedContext: publishedContext,
        rootPresentation: rootPresentation,
        sequence: sequence,
        truncation: truncation,
      );
    } on MeasurementIngestCodecException {
      rethrow;
    } on Object {
      throw const MeasurementIngestCodecException('invalid_canonical_frame');
    }
  }

  final Uint8List _canonicalBytes;

  /// Exact canonical fact-frame bytes, returned as a defensive copy.
  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  /// The one raw SHA-256 computed while validating this frame.
  final CanonicalDigest frameSha256;

  /// Per-frame hard bounds.
  final MeasurementFactBounds bounds;

  /// Opaque retry coordinate, not a subject identifier.
  final String captureSessionNonce;

  /// Bounded source facts selected only by compiler-owned identities.
  final List<MeasurementFact> facts;

  /// Whether this frame completes its capture session.
  final bool isFinal;

  /// Explicit missing or unavailable source-state counts.
  final List<MeasurementMissingness> missingness;

  /// Exact immutable publication context for this fact frame.
  final ExactMeasurementPublicationContextRefV1 publishedContext;

  /// Successful-root-presentation proof marker.
  final MeasurementSuccessfulRootPresentationV1 rootPresentation;

  /// Monotone frame sequence within a capture session.
  final int sequence;

  /// Explicit truncation evidence.
  final MeasurementTruncation truncation;
}

/// Per-frame bounds admitted before fact values are materialized.
final class MeasurementFactBounds {
  /// Creates one bounded fact-frame limit set.
  const MeasurementFactBounds({
    required this.maximumCounterValue,
    required this.maximumPresentedPoints,
    required this.maximumInteractionCounters,
    required this.maximumMissingnessEntries,
  });

  /// Decodes a closed fact-frame bounds object.
  factory MeasurementFactBounds.fromJson(Map<String, Object?> values) {
    final reader = _IngestObjectReader(
      values,
      allowedKeys: const {
        'maximumCounterValue',
        'maximumInteractionCounters',
        'maximumMissingnessEntries',
        'maximumPresentedPoints',
      },
      requiredKeys: const {
        'maximumCounterValue',
        'maximumInteractionCounters',
        'maximumMissingnessEntries',
        'maximumPresentedPoints',
      },
      path: 'measurementFactFrame.bounds',
    );
    final maximumCounterValue = reader.integer('maximumCounterValue');
    final maximumPresentedPoints = reader.integer('maximumPresentedPoints');
    final maximumInteractionCounters = reader.integer(
      'maximumInteractionCounters',
    );
    final maximumMissingnessEntries = reader.integer(
      'maximumMissingnessEntries',
    );
    if (maximumCounterValue <= 0 ||
        maximumCounterValue > _maximumCounterValue) {
      throw const MeasurementIngestCodecException('counter_bound_out_of_range');
    }
    if (maximumPresentedPoints <= 0 ||
        maximumPresentedPoints > _maximumPresentedPoints) {
      throw const MeasurementIngestCodecException(
        'presented_point_bound_out_of_range',
      );
    }
    if (maximumInteractionCounters < 0 ||
        maximumInteractionCounters > _maximumInteractionCounters) {
      throw const MeasurementIngestCodecException(
        'interaction_counter_bound_out_of_range',
      );
    }
    if (maximumMissingnessEntries < 0 ||
        maximumMissingnessEntries > _maximumMissingnessEntries) {
      throw const MeasurementIngestCodecException(
        'missingness_bound_out_of_range',
      );
    }
    return MeasurementFactBounds(
      maximumCounterValue: maximumCounterValue,
      maximumPresentedPoints: maximumPresentedPoints,
      maximumInteractionCounters: maximumInteractionCounters,
      maximumMissingnessEntries: maximumMissingnessEntries,
    );
  }

  /// Maximum retained counter value.
  final int maximumCounterValue;

  /// Maximum distinct successfully presented points.
  final int maximumPresentedPoints;

  /// Maximum facts that may retain an interaction counter.
  final int maximumInteractionCounters;

  /// Maximum distinct missingness entries.
  final int maximumMissingnessEntries;
}

/// Explicit marker that a frame was gated by successful first paint.
final class MeasurementSuccessfulRootPresentationV1 {
  const MeasurementSuccessfulRootPresentationV1._();

  /// Decodes the one accepted root-presentation proof marker.
  factory MeasurementSuccessfulRootPresentationV1.fromJson(
    Map<String, Object?> values,
  ) {
    final reader = _IngestObjectReader(
      values,
      allowedKeys: const {'kind'},
      requiredKeys: const {'kind'},
      path: 'measurementFactFrame.rootPresentation',
    );
    if (reader.string('kind') != 'successfulFirstPaint') {
      throw const MeasurementIngestCodecException(
        'invalid_root_presentation_marker',
      );
    }
    return const MeasurementSuccessfulRootPresentationV1._();
  }

  /// Canonical object representation emitted by bounded capture.
  Map<String, Object?> toJson() => const {'kind': 'successfulFirstPaint'};
}

/// One bounded counter with explicit saturation evidence.
final class MeasurementCounter {
  /// Creates one bounded counter.
  const MeasurementCounter({required this.value, required this.saturated});

  /// Decodes a closed counter object.
  factory MeasurementCounter.fromJson(
    Map<String, Object?> values, {
    required String path,
    required int maximumCounterValue,
  }) {
    final reader = _IngestObjectReader(
      values,
      allowedKeys: const {'saturated', 'value'},
      requiredKeys: const {'saturated', 'value'},
      path: path,
    );
    final value = reader.integer('value');
    if (value < 0 || value > maximumCounterValue) {
      throw const MeasurementIngestCodecException('counter_out_of_range');
    }
    return MeasurementCounter(
      value: value,
      saturated: reader.boolean('saturated'),
    );
  }

  /// Bounded counter value.
  final int value;

  /// Whether the upper bound was reached.
  final bool saturated;

  /// Closed counter representation.
  Map<String, Object?> toJson() => {'saturated': saturated, 'value': value};
}

/// One fact selected only by compiler-owned occurrence and lineage IDs.
final class MeasurementFact {
  /// Creates one validated fact value.
  const MeasurementFact({
    required this.occurrenceId,
    required this.lineageId,
    required this.interactionState,
    required this.interactionCount,
  });

  /// Decodes one closed subjectless fact object.
  factory MeasurementFact.fromJson(
    Map<String, Object?> values, {
    required MeasurementFactBounds bounds,
  }) {
    final reader = _IngestObjectReader(
      values,
      allowedKeys: const {
        'interactionCount',
        'interactionState',
        'lineageId',
        'occurrenceId',
      },
      requiredKeys: const {'interactionState', 'lineageId', 'occurrenceId'},
      path: 'measurementFactFrame.facts[]',
    );
    final interactionState = _measurementFactInteractionState(
      reader.string('interactionState'),
    );
    final occurrenceId = _requireSha256(
      reader.string('occurrenceId'),
      'measurementFactFrame.facts[].occurrenceId',
    );
    final lineageId = reader.string('lineageId');
    if (!RegExp(_lineagePattern).hasMatch(lineageId)) {
      throw const MeasurementIngestCodecException('invalid_lineage');
    }
    final interactionRaw = reader.optionalObject('interactionCount');
    final interactionCount = interactionRaw == null
        ? null
        : MeasurementCounter.fromJson(
            interactionRaw,
            path: 'measurementFactFrame.facts[].interactionCount',
            maximumCounterValue: bounds.maximumCounterValue,
          );
    final carriesCounter = switch (interactionState) {
      MeasurementFactInteractionState.observedZero ||
      MeasurementFactInteractionState.observedValue ||
      MeasurementFactInteractionState.observedCapped =>
        true,
      _ => false,
    };
    if (carriesCounter && interactionCount == null) {
      throw const MeasurementIngestCodecException(
        'observed_state_missing_counter',
      );
    }
    if (!carriesCounter && interactionCount != null) {
      throw const MeasurementIngestCodecException(
        'transport_truncated_has_counter',
      );
    }
    if (interactionState == MeasurementFactInteractionState.observedZero &&
        (interactionCount!.value != 0 || interactionCount.saturated)) {
      throw const MeasurementIngestCodecException('invalid_observed_zero');
    }
    if (interactionState == MeasurementFactInteractionState.observedValue &&
        (interactionCount!.value <= 0 ||
            interactionCount.value >= bounds.maximumCounterValue ||
            interactionCount.saturated)) {
      throw const MeasurementIngestCodecException('invalid_observed_value');
    }
    if (interactionState == MeasurementFactInteractionState.observedCapped &&
        (!interactionCount!.saturated ||
            interactionCount.value != bounds.maximumCounterValue)) {
      throw const MeasurementIngestCodecException('invalid_observed_capped');
    }
    return MeasurementFact(
      occurrenceId: occurrenceId,
      lineageId: lineageId,
      interactionState: interactionState,
      interactionCount: interactionCount,
    );
  }

  /// Exact occurrence digest.
  final String occurrenceId;

  /// Exact lineage identifier.
  final String lineageId;

  /// Closed interaction evidence for this successful presentation.
  final MeasurementFactInteractionState interactionState;

  /// Interaction counter when transport retained one for this presented point.
  final MeasurementCounter? interactionCount;

  /// Closed identity key for bounded monotonicity validation.
  String get identity => '$occurrenceId\u0000$lineageId';

  /// Exact retained source-fact payload excluding frame-only coordinates.
  Map<String, Object?> toJson() => {
        if (interactionCount != null)
          'interactionCount': interactionCount!.toJson(),
        'interactionState': interactionState.wireName,
        'lineageId': lineageId,
        'occurrenceId': occurrenceId,
      };
}

/// Closed interaction evidence carried by one successful presentation fact.
enum MeasurementFactInteractionState {
  /// A retained interaction counter has observed no interactions yet.
  observedZero('observedZero'),

  /// A retained interaction counter has observed one or more interactions.
  observedValue('observedValue'),

  /// A retained interaction counter reached its configured saturation cap.
  observedCapped('observedCapped'),

  /// The presentation was retained but no interaction-counter capacity
  /// remained.
  transportTruncated('transportTruncated');

  const MeasurementFactInteractionState(this.wireName);

  /// Exact canonical wire spelling.
  final String wireName;
}

/// Explicit count of a missing or unavailable source state, never a zero.
final class MeasurementMissingness {
  /// Creates one missingness entry.
  const MeasurementMissingness({required this.state, required this.count});

  /// Decodes one closed missingness entry.
  factory MeasurementMissingness.fromJson(
    Map<String, Object?> values, {
    required int maximumCounterValue,
  }) {
    final reader = _IngestObjectReader(
      values,
      allowedKeys: const {'count', 'state'},
      requiredKeys: const {'count', 'state'},
      path: 'measurementFactFrame.missingness[]',
    );
    final state = _observationState(reader.string('state'));
    if (!_isMissingnessState(state)) {
      throw const MeasurementIngestCodecException('invalid_missingness_state');
    }
    final count = reader.integer('count');
    if (count <= 0 || count > maximumCounterValue) {
      throw const MeasurementIngestCodecException('invalid_missingness_count');
    }
    return MeasurementMissingness(state: state, count: count);
  }

  /// Explicit non-observed state.
  final ObservationState state;

  /// Positive bounded count.
  final int count;
}

/// One independent bounded truncation dimension.
final class MeasurementTruncationDimension {
  /// Creates one monotone truncation dimension.
  const MeasurementTruncationDimension({
    required this.droppedCount,
    required this.truncated,
  });

  /// Decodes one closed truncation dimension.
  factory MeasurementTruncationDimension.fromJson(
    Map<String, Object?> values, {
    required int maximumCounterValue,
    required String path,
  }) {
    final reader = _IngestObjectReader(
      values,
      allowedKeys: const {'droppedCount', 'truncated'},
      requiredKeys: const {'droppedCount', 'truncated'},
      path: path,
    );
    final droppedCount = reader.integer('droppedCount');
    if (droppedCount < 0 || droppedCount > maximumCounterValue) {
      throw const MeasurementIngestCodecException('invalid_truncation_count');
    }
    final truncated = reader.boolean('truncated');
    if (truncated != (droppedCount > 0)) {
      throw const MeasurementIngestCodecException('inconsistent_truncation');
    }
    return MeasurementTruncationDimension(
      droppedCount: droppedCount,
      truncated: truncated,
    );
  }

  /// Number of distinct routes dropped by this independent bound.
  final int droppedCount;

  /// Whether this independent bound has dropped at least one route.
  final bool truncated;

  /// Closed canonical representation.
  Map<String, Object?> toJson() => {
        'droppedCount': droppedCount,
        'truncated': truncated,
      };
}

/// Explicit independent truncation evidence that cannot later be cleared.
final class MeasurementTruncation {
  /// Creates typed truncation evidence.
  const MeasurementTruncation({
    required this.presentedPoints,
    required this.interactionCounters,
  });

  /// Decodes a closed typed truncation object.
  factory MeasurementTruncation.fromJson(
    Map<String, Object?> values, {
    required int maximumCounterValue,
  }) {
    final reader = _IngestObjectReader(
      values,
      allowedKeys: const {'interactionCounters', 'presentedPoints'},
      requiredKeys: const {'interactionCounters', 'presentedPoints'},
      path: 'measurementFactFrame.truncation',
    );
    return MeasurementTruncation(
      presentedPoints: MeasurementTruncationDimension.fromJson(
        reader.object('presentedPoints'),
        maximumCounterValue: maximumCounterValue,
        path: 'measurementFactFrame.truncation.presentedPoints',
      ),
      interactionCounters: MeasurementTruncationDimension.fromJson(
        reader.object('interactionCounters'),
        maximumCounterValue: maximumCounterValue,
        path: 'measurementFactFrame.truncation.interactionCounters',
      ),
    );
  }

  /// Truncation from the presented-point budget.
  final MeasurementTruncationDimension presentedPoints;

  /// Truncation from the interaction-counter budget.
  final MeasurementTruncationDimension interactionCounters;

  /// Closed canonical representation.
  Map<String, Object?> toJson() => {
        'interactionCounters': interactionCounters.toJson(),
        'presentedPoints': presentedPoints.toJson(),
      };
}

List<MeasurementFact> _decodeFacts(
  List<Object?> rawFacts,
  MeasurementFactBounds bounds,
) {
  if (rawFacts.length > bounds.maximumPresentedPoints) {
    throw const MeasurementIngestCodecException(
      'presented_point_bound_exceeded',
    );
  }
  final facts = <MeasurementFact>[];
  var priorIdentity = '';
  var interactionCounterCount = 0;
  for (final raw in rawFacts) {
    final fact = MeasurementFact.fromJson(
      _requireObject(raw, 'measurementFactFrame.facts[]'),
      bounds: bounds,
    );
    if (fact.identity.compareTo(priorIdentity) <= 0) {
      throw const MeasurementIngestCodecException('facts_not_strictly_ordered');
    }
    priorIdentity = fact.identity;
    if (fact.interactionCount != null) {
      interactionCounterCount += 1;
      if (interactionCounterCount > bounds.maximumInteractionCounters) {
        throw const MeasurementIngestCodecException(
          'interaction_counter_bound_exceeded',
        );
      }
    }
    facts.add(fact);
  }
  return List.unmodifiable(facts);
}

List<MeasurementMissingness> _decodeMissingness(
  List<Object?> rawMissingness,
  MeasurementFactBounds bounds,
) {
  if (rawMissingness.length > bounds.maximumMissingnessEntries) {
    throw const MeasurementIngestCodecException('missingness_bound_exceeded');
  }
  final entries = <MeasurementMissingness>[];
  var priorState = '';
  for (final raw in rawMissingness) {
    final entry = MeasurementMissingness.fromJson(
      _requireObject(raw, 'measurementFactFrame.missingness[]'),
      maximumCounterValue: bounds.maximumCounterValue,
    );
    if (entry.state.wireName.compareTo(priorState) <= 0) {
      throw const MeasurementIngestCodecException(
        'missingness_not_strictly_ordered',
      );
    }
    priorState = entry.state.wireName;
    entries.add(entry);
  }
  return List.unmodifiable(entries);
}

bool _decodeFinality(Map<String, Object?> values) {
  final reader = _IngestObjectReader(
    values,
    allowedKeys: const {'kind'},
    requiredKeys: const {'kind'},
    path: 'measurementFactFrame.finality',
  );
  return switch (reader.string('kind')) {
    'pending' => false,
    'final' => true,
    _ => throw const MeasurementIngestCodecException('unknown_finality'),
  };
}

void _decodeRetryPolicy(Map<String, Object?> values) {
  final reader = _IngestObjectReader(
    values,
    allowedKeys: const {'kind'},
    requiredKeys: const {'kind'},
    path: 'measurementFactFrame.retryPolicy',
  );
  if (reader.string('kind') != 'byteIdenticalSameSequence') {
    throw const MeasurementIngestCodecException('unsupported_retry_policy');
  }
}

void _requireDocument(_IngestObjectReader reader, String expectedKind) {
  if (reader.integer('schemaVersion') != kMeasurementSchemaVersion) {
    throw const MeasurementIngestCodecException('unsupported_schema_version');
  }
  if (reader.string('kind') != expectedKind) {
    throw const MeasurementIngestCodecException('unexpected_document_kind');
  }
}

String _requireSha256(String value, String path) {
  if (!RegExp(_digestPattern).hasMatch(value)) {
    throw MeasurementIngestCodecException('invalid_sha256:$path');
  }
  return value;
}

CanonicalDigest _rawSha256(List<int> bytes) =>
    CanonicalDigest(sha256.convert(bytes).toString());

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decodeBase64Url(
  String value, {
  required String path,
  required int maximumBytes,
}) {
  if (value.isEmpty ||
      value.contains('=') ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value) ||
      value.length > ((maximumBytes * 4 + 2) ~/ 3)) {
    throw MeasurementIngestCodecException('invalid_base64url:$path');
  }
  try {
    final decoded = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (decoded.length > maximumBytes || _base64Url(decoded) != value) {
      throw MeasurementIngestCodecException('invalid_base64url:$path');
    }
    return decoded;
  } on MeasurementIngestCodecException {
    rethrow;
  } on FormatException {
    throw MeasurementIngestCodecException('invalid_base64url:$path');
  }
}

ObservationState _observationState(String value) {
  for (final state in ObservationState.values) {
    if (state.wireName == value) return state;
  }
  throw const MeasurementIngestCodecException('unknown_observation_state');
}

MeasurementFactInteractionState _measurementFactInteractionState(
  String value,
) {
  for (final state in MeasurementFactInteractionState.values) {
    if (state.wireName == value) return state;
  }
  throw const MeasurementIngestCodecException('unknown_interaction_state');
}

bool _isMissingnessState(ObservationState state) => switch (state) {
      ObservationState.structurallyInapplicable ||
      ObservationState.sourceUnavailable ||
      ObservationState.transportTruncated ||
      ObservationState.domainRejected ||
      ObservationState.rightCensored ||
      ObservationState.latePending ||
      ObservationState.semanticNull =>
        true,
      _ => false,
    };

bool _isObservationUnitKey(String value) =>
    value.length <= 128 && RegExp(r'^[a-z0-9][a-z0-9._:-]*$').hasMatch(value);

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _IngestObjectReader {
  _IngestObjectReader(
    this._values, {
    required Set<String> allowedKeys,
    required Set<String> requiredKeys,
    required this.path,
  }) {
    final unknown = _values.keys.toSet().difference(allowedKeys);
    if (unknown.isNotEmpty) {
      throw MeasurementIngestCodecException(
        '$path contains unknown keys: ${(unknown.toList()..sort()).join(', ')}',
      );
    }
    final missing = requiredKeys.difference(_values.keys.toSet());
    if (missing.isNotEmpty) {
      throw MeasurementIngestCodecException(
        '$path is missing keys: ${(missing.toList()..sort()).join(', ')}',
      );
    }
  }

  final Map<String, Object?> _values;
  final String path;

  String string(String key) {
    final value = _values[key];
    if (value is! String) {
      throw MeasurementIngestCodecException('$path.$key must be a string');
    }
    return value;
  }

  int integer(String key) {
    final value = _values[key];
    if (value is! int) {
      throw MeasurementIngestCodecException('$path.$key must be an integer');
    }
    return value;
  }

  bool boolean(String key) {
    final value = _values[key];
    if (value is! bool) {
      throw MeasurementIngestCodecException('$path.$key must be a Boolean');
    }
    return value;
  }

  Map<String, Object?> object(String key) => _requireObject(
        _values[key],
        '$path.$key',
      );

  Map<String, Object?>? optionalObject(String key) {
    if (!_values.containsKey(key)) return null;
    return _requireObject(_values[key], '$path.$key');
  }

  List<Object?> list(String key) {
    final value = _values[key];
    if (value is! List<Object?>) {
      throw MeasurementIngestCodecException('$path.$key must be a list');
    }
    return value;
  }
}

Map<String, Object?> _requireObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw MeasurementIngestCodecException('$path must be an object');
  }
  return value;
}
