import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_shared/restage_shared.dart';

/// The control-plane RPC operation for generated publication uploads.
///
/// This operation is intentionally separate from the legacy draft and
/// lifecycle methods. It accepts one canonical
/// [SurfacePublicationUploadRequest] JSON document and performs publication
/// atomically.
const String surfacePublicationUploadMethod = 'publishPublication';

/// The additive control-plane operation for a Measurement-bound publication.
const String measurementBoundSurfacePublicationUploadMethod =
    'publishMeasurementBound';

/// Exact bytes for one publication-declared artifact in an additive publication upload.
@experimental
@immutable
final class MeasurementBoundSurfacePublicationArtifactWire {
  /// Creates one immutable artifact tuple.
  MeasurementBoundSurfacePublicationArtifactWire({
    required this.path,
    required List<int> bytes,
  }) : _bytes = Uint8List.fromList(bytes);

  /// Canonical surface publication artifact path.
  final String path;

  final Uint8List _bytes;

  /// Defensive copy of the exact artifact bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Target-neutral additive upload assembled from one exact generated closure.
@experimental
@immutable
final class MeasurementBoundSurfacePublicationUploadWire {
  /// Creates an immutable additive upload and retains its inert proof.
  MeasurementBoundSurfacePublicationUploadWire({
    required this.proof,
    required List<MeasurementBoundSurfacePublicationArtifactWire>
    declaredArtifactClosure,
  }) : declaredArtifactClosure = List.unmodifiable(declaredArtifactClosure);

  /// Complete local proof over exact publication bytes and the generated draft.
  final MeasurementPublicationCandidateProofV1 proof;

  /// Exact publication-declared artifact paths and bytes.
  final List<MeasurementBoundSurfacePublicationArtifactWire>
  declaredArtifactClosure;

  /// Exact assembled publication upload bytes.
  Uint8List get publicationUploadCanonicalBytes =>
      proof.assembledPublicationUploadCanonicalBytes;

  /// Exact selected one-entry publication manifest bytes.
  Uint8List get selectedSingleEntryPublicationManifestCanonicalBytes =>
      proof.selectedPublicationManifestCanonicalBytes;

  /// Exact generated target-neutral draft bytes.
  Uint8List get measurementPublicationDraftCanonicalBytes =>
      proof.measurementPublicationDraft.canonicalBytes;

  /// Inert target-neutral reference recomputed from [proof].
  Uint8List get candidateReferenceCanonicalBytes =>
      proof.reference.canonicalBytes;
}

/// Result of one generated publication upload.
@experimental
@immutable
final class SurfacePublicationUploadResult {
  /// Construct a publication result.
  const SurfacePublicationUploadResult({
    required this.family,
    required this.storedRevision,
    required this.identityFrozen,
    this.activeRevision,
  });

  /// Exact family published by the operation.
  final SurfaceFamilyReferenceResult family;

  /// Newly stored immutable revision. This is not necessarily the revision
  /// selected for delivery when the identity is frozen.
  final int storedRevision;

  /// Active revision after the operation, when the control response provides
  /// it. This may remain unchanged when the identity is frozen.
  final int? activeRevision;

  /// Identity-wide freeze state after the operation.
  final bool identityFrozen;

  /// Wire-shaped spelling for callers that need to mirror the generated DTO.
  int get storedPublishedRevision => storedRevision;

  /// Wire-shaped spelling for the active delivery pointer.
  int? get activePublishedRevision => activeRevision;

  /// Stable description used by both surface publication commands.
  String get stateDescription =>
      'stored revision $storedRevision; '
      'active revision ${activeRevision ?? 'none'}; '
      'identity frozen: $identityFrozen.';

  /// Decode the small control response returned by the publication operation.
  factory SurfacePublicationUploadResult.fromWire(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'The publication response did not contain a stored revision.',
      );
    }
    final family = SurfaceFamilyReferenceResult.fromJson(value['family']);
    final storedRevision = value['storedPublishedRevision'];
    final activeRevision = value['activePublishedRevision'];
    final identityFrozen = value['identityFrozen'];
    if (storedRevision is! int || storedRevision < 1) {
      throw const FormatException(
        'The publication response did not contain a valid stored revision.',
      );
    }
    if (activeRevision != null &&
        (activeRevision is! int || activeRevision < 1)) {
      throw const FormatException(
        'The publication response contained an invalid active revision.',
      );
    }
    if (identityFrozen is! bool) {
      throw const FormatException(
        'The publication response did not contain freeze state.',
      );
    }
    return SurfacePublicationUploadResult(
      family: family,
      storedRevision: storedRevision,
      activeRevision: activeRevision as int?,
      identityFrozen: identityFrozen,
    );
  }

  /// Encode the generated publication-result JSON shape.
  Map<String, dynamic> toJson() => {
    '__className__': 'SurfaceContractPublicationResult',
    'family': family.toJson(),
    'storedPublishedRevision': storedRevision,
    if (activeRevision != null) 'activePublishedRevision': activeRevision,
    'identityFrozen': identityFrozen,
  };
}

/// Finalized backend result returned by an additive Measurement publication.
@experimental
@immutable
final class MeasurementBoundSurfacePublicationUploadResult {
  /// Construct a finalized result from authoritative backend output.
  MeasurementBoundSurfacePublicationUploadResult({
    required this.publicationResult,
    required this.publicationBindingReference,
    required this.bundledPublicationEntry,
  }) {
    if (bundledPublicationEntry.reference != publicationBindingReference) {
      throw ArgumentError(
        'The finalized bundled entry does not match its binding reference.',
      );
    }
  }

  /// Final publication result.
  final SurfacePublicationUploadResult publicationResult;

  /// Backend-finalized publication binding reference.
  final MeasurementPublicationBindingReferenceV1 publicationBindingReference;

  /// Backend-finalized exact bundled publication entry.
  final MeasurementPublicationBundledRegistryEntryV1 bundledPublicationEntry;

  /// Decode the accepted additive result shape.
  factory MeasurementBoundSurfacePublicationUploadResult.fromWire(
    Object? value,
  ) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'The Measurement publication response was malformed.',
      );
    }
    try {
      return MeasurementBoundSurfacePublicationUploadResult(
        publicationResult: SurfacePublicationUploadResult.fromWire(
          value['publicationResult'],
        ),
        publicationBindingReference:
            MeasurementPublicationBindingReferenceV1.fromCanonicalBytes(
              _decodeByteDataWire(
                value['publicationBindingReferenceCanonicalBytes'],
              ),
            ),
        bundledPublicationEntry:
            MeasurementPublicationBundledRegistryEntryV1.fromCanonicalBytes(
              _decodeByteDataWire(
                value['bundledPublicationEntryCanonicalBytes'],
              ),
            ),
      );
    } on Object {
      throw const FormatException(
        'The Measurement publication response was malformed.',
      );
    }
  }
}

/// Typed client for the one-operation generated publication path.
@experimental
final class SurfacePublicationApi {
  /// Build a publication API client backed by [api].
  SurfacePublicationApi(this._api);

  final RestageApi _api;

  /// Submit [request] as one canonical publication operation.
  ///
  /// The request is serialized with the shared strict codec and sent as the
  /// generated publication upload model. No draft-save or follow-up publish
  /// call is made.
  Future<SurfacePublicationUploadResult> publish({
    required String project,
    required String app,
    required String environment,
    required SurfacePublicationUploadRequest request,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final canonicalJson =
        SurfacePublicationUploadRequestV1Codec.encodeCanonicalJson(request);
    final raw = await _api.call('surface', surfacePublicationUploadMethod, {
      'projectSlug': project,
      'appSlug': app,
      'environmentSlug': environment,
      'upload': <String, dynamic>{
        '__className__': 'SurfacePublicationUpload',
        'canonicalJson': canonicalJson,
      },
      'environmentTargetId': ?environmentTargetId,
      'runtimePlane': ?runtimePlane?.wireName,
      'organizationId': ?organizationId,
    });
    try {
      return SurfacePublicationUploadResult.fromWire(raw);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'The publication response could not be decoded.',
      );
    }
  }

  /// Submit one inert target-neutral candidate through the additive operation.
  ///
  /// The upload contains no caller-selected binding, revision, ordinal, or
  /// activation state. Those values are finalized by the control plane.
  Future<MeasurementBoundSurfacePublicationUploadResult>
  publishMeasurementBound({
    required String project,
    required String app,
    required String environment,
    required MeasurementBoundSurfacePublicationUploadWire upload,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    final raw = await _api.call(
      'surface',
      measurementBoundSurfacePublicationUploadMethod,
      {
        'projectSlug': project,
        'appSlug': app,
        'environmentSlug': environment,
        'upload': <String, dynamic>{
          '__className__': 'MeasurementBoundSurfacePublicationUpload',
          'publicationUploadCanonicalBytes': _encodeByteDataWire(
            upload.publicationUploadCanonicalBytes,
          ),
          'selectedSingleEntryPublicationManifestCanonicalBytes':
              _encodeByteDataWire(
                upload.selectedSingleEntryPublicationManifestCanonicalBytes,
              ),
          'declaredArtifactClosure': [
            for (final artifact in upload.declaredArtifactClosure)
              <String, dynamic>{
                '__className__': 'MeasurementBoundSurfacePublicationArtifact',
                'path': artifact.path,
                'bytes': _encodeByteDataWire(artifact.bytes),
              },
          ],
          'measurementPublicationDraftCanonicalBytes': _encodeByteDataWire(
            upload.measurementPublicationDraftCanonicalBytes,
          ),
          'candidateReferenceCanonicalBytes': _encodeByteDataWire(
            upload.candidateReferenceCanonicalBytes,
          ),
        },
        'environmentTargetId': ?environmentTargetId,
        'runtimePlane': ?runtimePlane?.wireName,
        'organizationId': ?organizationId,
      },
    );
    try {
      return MeasurementBoundSurfacePublicationUploadResult.fromWire(raw);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'The Measurement publication response could not be decoded.',
      );
    }
  }
}

String _encodeByteDataWire(List<int> bytes) =>
    "decode('${base64Encode(bytes)}', 'base64')";

Uint8List _decodeByteDataWire(Object? value) {
  if (value is! String) {
    throw const FormatException(
      'The Measurement publication response omitted canonical bytes.',
    );
  }
  final match = RegExp(
    r"^decode\('([A-Za-z0-9+/]*={0,2})', 'base64'\)$",
  ).firstMatch(value);
  if (match == null) {
    throw const FormatException(
      'The Measurement publication response contained malformed bytes.',
    );
  }
  try {
    final encoded = match.group(1)!;
    final bytes = base64Decode(encoded);
    if (bytes.isEmpty || base64Encode(bytes) != encoded) {
      throw const FormatException('noncanonical bytes');
    }
    return bytes;
  } on FormatException {
    throw const FormatException(
      'The Measurement publication response contained malformed bytes.',
    );
  }
}
