import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identity_policy.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// The exact number of bytes in a governed-link challenge nonce.
const int measurementLinkChallengeNonceBytes = 32;

/// The maximum lifetime admitted for a governed-link challenge.
const Duration measurementLinkMaximumChallengeLifetime = Duration(minutes: 5);

/// Maximum bytes in one opaque per-domain privacy authority carrier.
///
/// The carrier is intentionally not decoded by the coordinator. The owning
/// domain validates its own exact request before making any authority claim.
const int restagePrivacyMaximumDomainAuthorityBytes = 256 * 1024;

/// Maximum bytes in one opaque per-domain privacy receipt carrier.
const int restagePrivacyMaximumDomainReceiptBytes = 256 * 1024;

/// A governed subject kind supported by the explicit Measurement API.
enum MeasurementSubjectKind {
  /// A host/IDP-authenticated user subject.
  identifiedUser('identifiedUser'),

  /// A host/IDP-authenticated account subject with a frozen membership view.
  account('account');

  const MeasurementSubjectKind(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical subject-kind spelling.
  static MeasurementSubjectKind fromWire(String value) =>
      _enumFromWire(values, value, 'subjectKind');
}

/// The exact action bound into a governed-link assertion and challenge.
enum MeasurementLinkAction {
  /// Direct host/IDP link.
  linkSubject('linkSubject');

  const MeasurementLinkAction(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical link-action spelling.
  static MeasurementLinkAction fromWire(String value) =>
      _enumFromWire(values, value, 'linkAction');
}

/// Provenance recorded on a successful governed-subject link.
enum MeasurementLinkProvenance {
  /// The host assertion was verified directly by Measurement.
  directHostAssertion('directHostAssertion');

  const MeasurementLinkProvenance(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical provenance spelling.
  static MeasurementLinkProvenance fromWire(String value) =>
      _enumFromWire(values, value, 'provenance');
}

/// The only link result represented by a successful link receipt.
enum MeasurementLinkReceiptResult {
  /// Measurement committed the requested link generation.
  linked('linked');

  const MeasurementLinkReceiptResult(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical link-result spelling.
  static MeasurementLinkReceiptResult fromWire(String value) =>
      _enumFromWire(values, value, 'result');
}

/// Coarse, existence-hiding failure classes for governed Measurement calls.
enum MeasurementLinkFailureCode {
  /// The authenticated proof did not verify.
  invalidProof('invalidProof'),

  /// A proof or challenge is no longer fresh.
  expiredProof('expiredProof'),

  /// Consent, region, policy, or requester authority did not permit the call.
  notAllowed('notAllowed'),

  /// The operation conflicts with an exact prior request or generation.
  conflict('conflict'),

  /// The operation could not be completed without making an authority claim.
  temporarilyUnavailable('temporarilyUnavailable');

  const MeasurementLinkFailureCode(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical link-failure spelling.
  static MeasurementLinkFailureCode fromWire(String value) =>
      _enumFromWire(values, value, 'failureCode');
}

/// Explicit subject operation other than linking.
enum MeasurementSubjectOperationAction {
  /// Reset the governed subject link state.
  resetSubject('resetSubject'),

  /// Withdraw consent for future governed Measurement operations.
  withdrawConsent('withdrawConsent');

  const MeasurementSubjectOperationAction(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical subject-operation spelling.
  static MeasurementSubjectOperationAction fromWire(String value) =>
      _enumFromWire(values, value, 'subjectOperation');
}

/// A bounded opaque transient byte value used as authenticated evidence.
abstract base class _TransientProofBytes {
  _TransientProofBytes(List<int> bytes, {required String label})
      : _bytes = _copyBytes(bytes, label);

  final Uint8List _bytes;

  /// Defensive copy of the transient proof bytes.
  List<int> get bytes => List<int>.unmodifiable(_bytes);

  /// Unpadded base64url representation used only while forwarding a request.
  String get base64Url => _encodeBase64Url(_bytes);
}

/// Independently authenticated consent evidence supplied by the host.
final class MeasurementConsentEvidence extends _TransientProofBytes {
  /// Creates transient consent evidence.
  MeasurementConsentEvidence(super.bytes) : super(label: 'consent evidence');
}

/// Independently authenticated region evidence supplied by the host.
final class MeasurementRegionEvidence extends _TransientProofBytes {
  /// Creates transient region evidence.
  MeasurementRegionEvidence(super.bytes) : super(label: 'region evidence');
}

/// Requester binding evidence supplied by the host or its configured IDP.
final class MeasurementRequesterBinding extends _TransientProofBytes {
  /// Creates transient requester binding evidence.
  MeasurementRequesterBinding(super.bytes) : super(label: 'requester binding');
}

/// Public command to issue one direct host/IDP challenge.
///
/// This request is deliberately direct-only. The server authenticates the SDK
/// caller, resolves the exact target from that caller, and rejects any target
/// mismatch before issuing a challenge.
final class MeasurementLinkChallengeRequestV1 extends CanonicalValue {
  /// Creates one exact direct challenge issuance request.
  MeasurementLinkChallengeRequestV1({
    required this.operationId,
    required this.target,
    required this.subjectPolicyRef,
    required this.purposePolicyRef,
    required this.subjectKind,
    required this.action,
    required this.expectedSubjectGeneration,
    required this.requesterBinding,
  }) {
    _requireOpaqueId(operationId, 'operationId');
    if (action != MeasurementLinkAction.linkSubject) {
      throw ArgumentError.value(
        action,
        'action',
        'A direct challenge may issue only the linkSubject action',
      );
    }
    _requireNonNegativeGeneration(
      expectedSubjectGeneration,
      'expectedSubjectGeneration',
    );
  }

  /// Decodes exact canonical direct challenge-request bytes.
  factory MeasurementLinkChallengeRequestV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementLinkChallengeRequestV1.fromJson(
            decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementLinkChallengeRequest',
      );

  /// Decodes one strict direct challenge-request object.
  factory MeasurementLinkChallengeRequestV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'expectedSubjectGeneration',
        'kind',
        'operationId',
        'purposePolicyRef',
        'requesterBindingBase64Url',
        'schemaVersion',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      requiredKeys: const {
        'action',
        'expectedSubjectGeneration',
        'kind',
        'operationId',
        'purposePolicyRef',
        'requesterBindingBase64Url',
        'schemaVersion',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      path: 'measurementLinkChallengeRequest',
    );
    _validateDocument(reader, 'measurementLinkChallengeRequest');
    return MeasurementLinkChallengeRequestV1(
      operationId: reader.string('operationId'),
      target: TargetCoordinate.fromJson(reader.object('target')),
      subjectPolicyRef: SubjectPolicyRefV1.fromJson(
        reader.object('subjectPolicyRef'),
      ),
      purposePolicyRef: PurposePolicyRefV1.fromJson(
        reader.object('purposePolicyRef'),
      ),
      subjectKind: MeasurementSubjectKind.fromWire(
        reader.string('subjectKind'),
      ),
      action: MeasurementLinkAction.fromWire(reader.string('action')),
      expectedSubjectGeneration: reader.integer('expectedSubjectGeneration'),
      requesterBinding: MeasurementRequesterBinding(
        _decodeBase64Url(
          reader.string('requesterBindingBase64Url'),
          path: 'measurementLinkChallengeRequest.requesterBindingBase64Url',
        ),
      ),
    );
  }

  /// Opaque caller-chosen idempotency identifier.
  final String operationId;

  /// Exact client-declared target, checked against authenticated authority.
  final TargetCoordinate target;

  /// Exact immutable subject policy requested by the caller.
  final SubjectPolicyRefV1 subjectPolicyRef;

  /// Exact immutable purpose policy requested by the caller.
  final PurposePolicyRefV1 purposePolicyRef;

  /// Direct host/IDP subject kind.
  final MeasurementSubjectKind subjectKind;

  /// The closed direct challenge action.
  final MeasurementLinkAction action;

  /// Exact subject generation precondition.
  final int expectedSubjectGeneration;

  /// Authenticated host/IDP requester binding evidence.
  final MeasurementRequesterBinding requesterBinding;

  /// Retry fingerprint. The service recomputes it before using persistence.
  CanonicalDigest get requestFingerprint => canonicalSha256(
        CanonicalHashDomain.measurementLinkChallengeRequest,
        canonicalBytes,
      );

  @override
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        'expectedSubjectGeneration': expectedSubjectGeneration,
        'kind': 'measurementLinkChallengeRequest',
        'operationId': operationId,
        'purposePolicyRef': purposePolicyRef.toJson(),
        'requesterBindingBase64Url': requesterBinding.base64Url,
        'schemaVersion': kMeasurementSchemaVersion,
        'subjectKind': subjectKind.wireName,
        'subjectPolicyRef': subjectPolicyRef.toJson(),
        'target': target.toJson(),
      };
}

/// Value result of a direct challenge issuance call.
sealed class MeasurementLinkChallengeOperationResultV1 extends CanonicalValue {
  const MeasurementLinkChallengeOperationResultV1();

  /// Creates a successful direct challenge issuance result.
  const factory MeasurementLinkChallengeOperationResultV1.accepted(
    MeasurementLinkChallengeV1 challenge,
  ) = MeasurementLinkChallengeAcceptedV1;

  /// Creates a coarse direct challenge issuance failure.
  const factory MeasurementLinkChallengeOperationResultV1.failed(
    MeasurementLinkFailureV1 failure,
  ) = MeasurementLinkChallengeFailedV1;

  /// Decodes one strict direct challenge issuance result.
  factory MeasurementLinkChallengeOperationResultV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementLinkChallengeOperationResultV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementLinkChallengeOperationResult',
      );

  /// Decodes one strict direct challenge issuance result object.
  factory MeasurementLinkChallengeOperationResultV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'challenge', 'failure', 'kind', 'schemaVersion'},
      requiredKeys: const {'kind', 'schemaVersion'},
      path: 'measurementLinkChallengeOperationResult',
    );
    _validateUnionDocument(
      reader,
      'measurementLinkChallengeOperationResult',
      const {'accepted', 'failed'},
    );
    return switch (reader.string('kind')) {
      'accepted' => MeasurementLinkChallengeAcceptedV1(
          MeasurementLinkChallengeV1.fromJson(
            _requireUnionObject(reader, 'challenge', 'failure'),
          ),
        ),
      'failed' => MeasurementLinkChallengeFailedV1(
          MeasurementLinkFailureV1.fromJson(
            _requireUnionObject(reader, 'failure', 'challenge'),
          ),
        ),
      _ => throw const CanonicalFormatException(
          'Unknown measurement link challenge result',
        ),
    };
  }
}

/// Successful direct challenge issuance result.
final class MeasurementLinkChallengeAcceptedV1
    extends MeasurementLinkChallengeOperationResultV1 {
  /// Creates a successful result.
  const MeasurementLinkChallengeAcceptedV1(this.challenge);

  /// Server-issued exact challenge.
  final MeasurementLinkChallengeV1 challenge;

  @override
  Map<String, Object?> toJson() => {
        'challenge': challenge.toJson(),
        'kind': 'accepted',
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Failed direct challenge issuance result.
final class MeasurementLinkChallengeFailedV1
    extends MeasurementLinkChallengeOperationResultV1 {
  /// Creates a coarse failed result.
  const MeasurementLinkChallengeFailedV1(this.failure);

  /// Existence-hiding failure.
  final MeasurementLinkFailureV1 failure;

  @override
  Map<String, Object?> toJson() => {
        'failure': failure.toJson(),
        'kind': 'failed',
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// A challenge issued by Measurement for one exact governed-link operation.
final class MeasurementLinkChallengeV1 extends CanonicalValue {
  /// Creates a bounded, immutable governed-link challenge.
  MeasurementLinkChallengeV1({
    required this.operationId,
    required List<int> challengeNonce,
    required this.target,
    required this.subjectPolicyRef,
    required this.purposePolicyRef,
    required this.subjectKind,
    required this.action,
    required this.expectedSubjectGeneration,
    required this.requesterBinding,
    required DateTime serverIssuedAt,
    required DateTime expiresAt,
  })  : _challengeNonce = _requireExactBytes(
          challengeNonce,
          measurementLinkChallengeNonceBytes,
          'challenge nonce',
        ),
        serverIssuedAt = serverIssuedAt.toUtc(),
        expiresAt = expiresAt.toUtc() {
    _requireOpaqueId(operationId, 'operationId');
    _requireNonNegativeGeneration(
      expectedSubjectGeneration,
      'expectedSubjectGeneration',
    );
    final lifetime = expiresAt.difference(this.serverIssuedAt);
    if (lifetime.isNegative ||
        lifetime > measurementLinkMaximumChallengeLifetime) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'Challenge expiry must be within five minutes of server issue time',
      );
    }
  }

  /// Decodes exact canonical challenge bytes.
  factory MeasurementLinkChallengeV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementLinkChallengeV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementLinkChallenge',
      );

  /// Decodes one strict challenge object.
  factory MeasurementLinkChallengeV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'challengeNonceBase64Url',
        'expectedSubjectGeneration',
        'expiresAtMicros',
        'kind',
        'operationId',
        'purposePolicyRef',
        'requesterBindingBase64Url',
        'schemaVersion',
        'serverIssuedAtMicros',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      requiredKeys: const {
        'action',
        'challengeNonceBase64Url',
        'expectedSubjectGeneration',
        'expiresAtMicros',
        'kind',
        'operationId',
        'purposePolicyRef',
        'requesterBindingBase64Url',
        'schemaVersion',
        'serverIssuedAtMicros',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      path: 'measurementLinkChallenge',
    );
    _validateDocument(reader, 'measurementLinkChallenge');
    return MeasurementLinkChallengeV1(
      operationId: reader.string('operationId'),
      challengeNonce: _decodeBase64Url(
        reader.string('challengeNonceBase64Url'),
        path: 'measurementLinkChallenge.challengeNonceBase64Url',
      ),
      target: TargetCoordinate.fromJson(reader.object('target')),
      subjectPolicyRef: SubjectPolicyRefV1.fromJson(
        reader.object('subjectPolicyRef'),
      ),
      purposePolicyRef: PurposePolicyRefV1.fromJson(
        reader.object('purposePolicyRef'),
      ),
      subjectKind: MeasurementSubjectKind.fromWire(
        reader.string('subjectKind'),
      ),
      action: MeasurementLinkAction.fromWire(reader.string('action')),
      expectedSubjectGeneration: reader.integer('expectedSubjectGeneration'),
      requesterBinding: MeasurementRequesterBinding(
        _decodeBase64Url(
          reader.string('requesterBindingBase64Url'),
          path: 'measurementLinkChallenge.requesterBindingBase64Url',
        ),
      ),
      serverIssuedAt: _dateFromMicros(reader.integer('serverIssuedAtMicros')),
      expiresAt: _dateFromMicros(reader.integer('expiresAtMicros')),
    );
  }

  /// Exact challenge operation identifier.
  final String operationId;

  /// One-use 256-bit challenge nonce.
  final Uint8List _challengeNonce;

  /// Defensive copy of the transient one-use challenge nonce.
  List<int> get challengeNonce => List<int>.unmodifiable(_challengeNonce);

  /// Exact resolved target bound by the challenge.
  final TargetCoordinate target;

  /// Exact subject-policy revision bound by the challenge.
  final SubjectPolicyRefV1 subjectPolicyRef;

  /// Exact purpose-policy revision bound by the challenge.
  final PurposePolicyRefV1 purposePolicyRef;

  /// Governed subject kind bound by the challenge.
  final MeasurementSubjectKind subjectKind;

  /// Exact link action bound by the challenge.
  final MeasurementLinkAction action;

  /// Subject/link generation expected by the authority.
  final int expectedSubjectGeneration;

  /// Host/IDP requester binding evidence.
  final MeasurementRequesterBinding requesterBinding;

  /// Server issue time in UTC.
  final DateTime serverIssuedAt;

  /// Challenge expiry in UTC.
  final DateTime expiresAt;

  @override
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        'challengeNonceBase64Url': _encodeBase64Url(challengeNonce),
        'expectedSubjectGeneration': expectedSubjectGeneration,
        'expiresAtMicros': expiresAt.microsecondsSinceEpoch,
        'kind': 'measurementLinkChallenge',
        'operationId': operationId,
        'purposePolicyRef': purposePolicyRef.toJson(),
        'requesterBindingBase64Url': requesterBinding.base64Url,
        'schemaVersion': kMeasurementSchemaVersion,
        'serverIssuedAtMicros': serverIssuedAt.microsecondsSinceEpoch,
        'subjectKind': subjectKind.wireName,
        'subjectPolicyRef': subjectPolicyRef.toJson(),
        'target': target.toJson(),
      };
}

/// A direct host/IDP request to link a governed Measurement subject.
final class MeasurementLinkRequestV1 extends CanonicalValue {
  /// Creates a transient direct link request.
  MeasurementLinkRequestV1({
    required this.challenge,
    required List<int> assertionBytes,
    required this.consentEvidence,
    required this.regionEvidence,
    this.expectedSubjectGeneration,
  }) : _assertionBytes = _copyBytes(assertionBytes, 'assertion bytes') {
    if (challenge.action != MeasurementLinkAction.linkSubject) {
      throw ArgumentError.value(
        challenge.action,
        'challenge.action',
        'A direct request requires the linkSubject action',
      );
    }
    _requireOptionalGeneration(expectedSubjectGeneration);
    if (expectedSubjectGeneration != null &&
        expectedSubjectGeneration != challenge.expectedSubjectGeneration) {
      throw ArgumentError(
        'The request generation precondition must match the challenge',
      );
    }
  }

  /// Decodes exact canonical direct-link request bytes.
  factory MeasurementLinkRequestV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementLinkRequestV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementLinkRequest',
      );

  /// Decodes one strict direct-link request object.
  factory MeasurementLinkRequestV1.fromJson(Map<String, Object?> json) {
    final fields = _linkRequestReader(json, 'measurementLinkRequest');
    return MeasurementLinkRequestV1(
      challenge: MeasurementLinkChallengeV1.fromJson(
        fields.object('challenge'),
      ),
      assertionBytes: _decodeBase64Url(
        fields.string('assertionBytesBase64Url'),
        path: 'measurementLinkRequest.assertionBytesBase64Url',
      ),
      consentEvidence: MeasurementConsentEvidence(
        _decodeBase64Url(
          fields.string('consentEvidenceBase64Url'),
          path: 'measurementLinkRequest.consentEvidenceBase64Url',
        ),
      ),
      regionEvidence: MeasurementRegionEvidence(
        _decodeBase64Url(
          fields.string('regionEvidenceBase64Url'),
          path: 'measurementLinkRequest.regionEvidenceBase64Url',
        ),
      ),
      expectedSubjectGeneration: fields.optionalInteger(
        'expectedSubjectGeneration',
      ),
    );
  }

  /// Exact challenge and operation binding.
  final MeasurementLinkChallengeV1 challenge;

  final Uint8List _assertionBytes;

  /// Defensive copy of the transient host assertion bytes.
  List<int> get assertionBytes => List<int>.unmodifiable(_assertionBytes);

  /// Independently authenticated consent evidence.
  final MeasurementConsentEvidence consentEvidence;

  /// Independently authenticated region evidence.
  final MeasurementRegionEvidence regionEvidence;

  /// Optional exact generation precondition.
  final int? expectedSubjectGeneration;

  /// The SDK-computed retry fingerprint. The service recomputes it and never
  /// treats a client-provided digest as authority.
  CanonicalDigest get requestFingerprint => canonicalSha256(
        CanonicalHashDomain.measurementLinkRequest,
        canonicalBytes,
      );

  @override
  Map<String, Object?> toJson() => {
        'assertionBytesBase64Url': _encodeBase64Url(assertionBytes),
        'challenge': challenge.toJson(),
        'consentEvidenceBase64Url': consentEvidence.base64Url,
        if (expectedSubjectGeneration != null)
          'expectedSubjectGeneration': expectedSubjectGeneration,
        'kind': 'measurementLinkRequest',
        'regionEvidenceBase64Url': regionEvidence.base64Url,
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// A successful governed-subject link receipt.
final class MeasurementLinkReceiptV1 extends CanonicalValue {
  /// Creates a receipt containing Measurement authority only.
  MeasurementLinkReceiptV1({
    required this.operationId,
    required this.target,
    required this.subjectPolicyRef,
    required this.purposePolicyRef,
    required this.subjectKind,
    required this.linkGeneration,
    required this.result,
    required this.provenance,
  }) {
    _requireOpaqueId(operationId, 'operationId');
    _requireNonNegativeGeneration(linkGeneration, 'linkGeneration');
  }

  /// Decodes exact canonical receipt bytes.
  factory MeasurementLinkReceiptV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementLinkReceiptV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementLinkReceipt',
      );

  /// Decodes one strict receipt object.
  factory MeasurementLinkReceiptV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'kind',
        'linkGeneration',
        'operationId',
        'provenance',
        'purposePolicyRef',
        'result',
        'schemaVersion',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      requiredKeys: const {
        'kind',
        'linkGeneration',
        'operationId',
        'provenance',
        'purposePolicyRef',
        'result',
        'schemaVersion',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      path: 'measurementLinkReceipt',
    );
    _validateDocument(reader, 'measurementLinkReceipt');
    final generation = reader.integer('linkGeneration');
    _requireNonNegativeGeneration(generation, 'linkGeneration');
    return MeasurementLinkReceiptV1(
      operationId: reader.string('operationId'),
      target: TargetCoordinate.fromJson(reader.object('target')),
      subjectPolicyRef: SubjectPolicyRefV1.fromJson(
        reader.object('subjectPolicyRef'),
      ),
      purposePolicyRef: PurposePolicyRefV1.fromJson(
        reader.object('purposePolicyRef'),
      ),
      subjectKind: MeasurementSubjectKind.fromWire(
        reader.string('subjectKind'),
      ),
      linkGeneration: generation,
      result: MeasurementLinkReceiptResult.fromWire(reader.string('result')),
      provenance: MeasurementLinkProvenance.fromWire(
        reader.string('provenance'),
      ),
    );
  }

  /// Measurement operation identifier.
  final String operationId;

  /// Exact target named by Measurement.
  final TargetCoordinate target;

  /// Exact subject-policy revision used by Measurement.
  final SubjectPolicyRefV1 subjectPolicyRef;

  /// Exact purpose-policy revision used by Measurement.
  final PurposePolicyRefV1 purposePolicyRef;

  /// Subject kind linked by Measurement.
  final MeasurementSubjectKind subjectKind;

  /// Measurement-owned link generation.
  final int linkGeneration;

  /// Closed successful operation result.
  final MeasurementLinkReceiptResult result;

  /// Direct host/IDP provenance only.
  final MeasurementLinkProvenance provenance;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'measurementLinkReceipt',
        'linkGeneration': linkGeneration,
        'operationId': operationId,
        'provenance': provenance.wireName,
        'purposePolicyRef': purposePolicyRef.toJson(),
        'result': result.wireName,
        'schemaVersion': kMeasurementSchemaVersion,
        'subjectKind': subjectKind.wireName,
        'subjectPolicyRef': subjectPolicyRef.toJson(),
        'target': target.toJson(),
      };
}

/// A coarse governed-link failure that hides subject and policy existence.
final class MeasurementLinkFailureV1 extends CanonicalValue {
  /// Creates a coarse link failure.
  const MeasurementLinkFailureV1({required this.code});

  /// Decodes exact canonical failure bytes.
  factory MeasurementLinkFailureV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementLinkFailureV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementLinkFailure',
      );

  /// Decodes one strict failure object.
  factory MeasurementLinkFailureV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'code', 'kind', 'schemaVersion'},
      requiredKeys: const {'code', 'kind', 'schemaVersion'},
      path: 'measurementLinkFailure',
    );
    _validateDocument(reader, 'measurementLinkFailure');
    return MeasurementLinkFailureV1(
      code: MeasurementLinkFailureCode.fromWire(reader.string('code')),
    );
  }

  /// Coarse existence-hiding failure class.
  final MeasurementLinkFailureCode code;

  @override
  Map<String, Object?> toJson() => {
        'code': code.wireName,
        'kind': 'measurementLinkFailure',
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Value result of a direct host/IDP link call.
sealed class MeasurementLinkOperationResultV1 extends CanonicalValue {
  const MeasurementLinkOperationResultV1();

  /// Creates a successful result.
  const factory MeasurementLinkOperationResultV1.accepted(
    MeasurementLinkReceiptV1 receipt,
  ) = MeasurementLinkAcceptedV1;

  /// Creates a coarse failed result.
  const factory MeasurementLinkOperationResultV1.failed(
    MeasurementLinkFailureV1 failure,
  ) = MeasurementLinkFailedV1;

  /// Decodes one strict result union.
  factory MeasurementLinkOperationResultV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementLinkOperationResultV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementLinkOperationResult',
      );

  /// Decodes one result union object.
  factory MeasurementLinkOperationResultV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'failure', 'kind', 'receipt', 'schemaVersion'},
      requiredKeys: const {'kind', 'schemaVersion'},
      path: 'measurementLinkOperationResult',
    );
    _validateUnionDocument(reader, 'measurementLinkOperationResult', const {
      'accepted',
      'failed',
    });
    final kind = reader.string('kind');
    return switch (kind) {
      'accepted' => _decodeAcceptedLinkResult(reader),
      'failed' => _decodeFailedLinkResult(reader),
      _ => throw CanonicalFormatException(
          'Unknown measurement link result "$kind"',
        ),
    };
  }
}

/// Successful link result.
final class MeasurementLinkAcceptedV1 extends MeasurementLinkOperationResultV1 {
  /// Creates a successful link result.
  const MeasurementLinkAcceptedV1(this.receipt);

  /// Measurement-owned receipt.
  final MeasurementLinkReceiptV1 receipt;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'accepted',
        'receipt': receipt.toJson(),
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Failed link result.
final class MeasurementLinkFailedV1 extends MeasurementLinkOperationResultV1 {
  /// Creates a coarse failed link result.
  const MeasurementLinkFailedV1(this.failure);

  /// Existence-hiding failure.
  final MeasurementLinkFailureV1 failure;

  @override
  Map<String, Object?> toJson() => {
        'failure': failure.toJson(),
        'kind': 'failed',
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Request for an explicit reset or consent-withdrawal operation.
final class MeasurementSubjectOperationRequestV1 extends CanonicalValue {
  /// Creates a transient governed-subject operation request.
  MeasurementSubjectOperationRequestV1({
    required this.operationId,
    required this.target,
    required this.subjectPolicyRef,
    required this.purposePolicyRef,
    required this.subjectKind,
    required this.action,
    required this.requesterBinding,
    required List<int> assertionBytes,
    required this.consentEvidence,
    required this.regionEvidence,
    this.expectedSubjectGeneration,
  }) : _assertionBytes = _copyBytes(assertionBytes, 'assertion bytes') {
    _requireOpaqueId(operationId, 'operationId');
    _requireOptionalGeneration(expectedSubjectGeneration);
  }

  /// Decodes exact canonical subject-operation request bytes.
  factory MeasurementSubjectOperationRequestV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementSubjectOperationRequestV1.fromJson(
            decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementSubjectOperationRequest',
      );

  /// Decodes one strict subject-operation request object.
  factory MeasurementSubjectOperationRequestV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'assertionBytesBase64Url',
        'consentEvidenceBase64Url',
        'expectedSubjectGeneration',
        'kind',
        'operationId',
        'purposePolicyRef',
        'regionEvidenceBase64Url',
        'requesterBindingBase64Url',
        'schemaVersion',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      requiredKeys: const {
        'action',
        'assertionBytesBase64Url',
        'consentEvidenceBase64Url',
        'kind',
        'operationId',
        'purposePolicyRef',
        'regionEvidenceBase64Url',
        'requesterBindingBase64Url',
        'schemaVersion',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      path: 'measurementSubjectOperationRequest',
    );
    _validateDocument(reader, 'measurementSubjectOperationRequest');
    return MeasurementSubjectOperationRequestV1(
      operationId: reader.string('operationId'),
      target: TargetCoordinate.fromJson(reader.object('target')),
      subjectPolicyRef: SubjectPolicyRefV1.fromJson(
        reader.object('subjectPolicyRef'),
      ),
      purposePolicyRef: PurposePolicyRefV1.fromJson(
        reader.object('purposePolicyRef'),
      ),
      subjectKind: MeasurementSubjectKind.fromWire(
        reader.string('subjectKind'),
      ),
      action: MeasurementSubjectOperationAction.fromWire(
        reader.string('action'),
      ),
      requesterBinding: MeasurementRequesterBinding(
        _decodeBase64Url(
          reader.string('requesterBindingBase64Url'),
          path: 'measurementSubjectOperationRequest.requesterBindingBase64Url',
        ),
      ),
      assertionBytes: _decodeBase64Url(
        reader.string('assertionBytesBase64Url'),
        path: 'measurementSubjectOperationRequest.assertionBytesBase64Url',
      ),
      consentEvidence: MeasurementConsentEvidence(
        _decodeBase64Url(
          reader.string('consentEvidenceBase64Url'),
          path: 'measurementSubjectOperationRequest.consentEvidenceBase64Url',
        ),
      ),
      regionEvidence: MeasurementRegionEvidence(
        _decodeBase64Url(
          reader.string('regionEvidenceBase64Url'),
          path: 'measurementSubjectOperationRequest.regionEvidenceBase64Url',
        ),
      ),
      expectedSubjectGeneration: reader.optionalInteger(
        'expectedSubjectGeneration',
      ),
    );
  }

  /// Exact operation identifier.
  final String operationId;

  /// Exact target named by the host.
  final TargetCoordinate target;

  /// Exact subject-policy revision.
  final SubjectPolicyRefV1 subjectPolicyRef;

  /// Exact purpose-policy revision.
  final PurposePolicyRefV1 purposePolicyRef;

  /// Governed subject kind.
  final MeasurementSubjectKind subjectKind;

  /// Explicit operation.
  final MeasurementSubjectOperationAction action;

  /// Host/IDP requester binding evidence.
  final MeasurementRequesterBinding requesterBinding;

  final Uint8List _assertionBytes;

  /// Defensive copy of the transient host assertion bytes.
  List<int> get assertionBytes => List<int>.unmodifiable(_assertionBytes);

  /// Authenticated consent evidence.
  final MeasurementConsentEvidence consentEvidence;

  /// Authenticated region evidence.
  final MeasurementRegionEvidence regionEvidence;

  /// Optional exact generation precondition.
  final int? expectedSubjectGeneration;

  /// SDK-computed retry fingerprint; the service recomputes it.
  CanonicalDigest get requestFingerprint => canonicalSha256(
        CanonicalHashDomain.measurementSubjectOperationRequest,
        canonicalBytes,
      );

  @override
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        'assertionBytesBase64Url': _encodeBase64Url(assertionBytes),
        'consentEvidenceBase64Url': consentEvidence.base64Url,
        if (expectedSubjectGeneration != null)
          'expectedSubjectGeneration': expectedSubjectGeneration,
        'kind': 'measurementSubjectOperationRequest',
        'operationId': operationId,
        'purposePolicyRef': purposePolicyRef.toJson(),
        'regionEvidenceBase64Url': regionEvidence.base64Url,
        'requesterBindingBase64Url': requesterBinding.base64Url,
        'schemaVersion': kMeasurementSchemaVersion,
        'subjectKind': subjectKind.wireName,
        'subjectPolicyRef': subjectPolicyRef.toJson(),
        'target': target.toJson(),
      };
}

/// Receipt for an explicit reset or consent-withdrawal operation.
final class MeasurementSubjectOperationReceiptV1 extends CanonicalValue {
  /// Creates a Measurement-owned subject-operation receipt.
  MeasurementSubjectOperationReceiptV1({
    required this.operationId,
    required this.target,
    required this.subjectPolicyRef,
    required this.purposePolicyRef,
    required this.subjectKind,
    required this.action,
    required this.subjectGeneration,
  }) {
    _requireOpaqueId(operationId, 'operationId');
    _requireNonNegativeGeneration(subjectGeneration, 'subjectGeneration');
  }

  /// Decodes exact canonical subject-operation receipt bytes.
  factory MeasurementSubjectOperationReceiptV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementSubjectOperationReceiptV1.fromJson(
            decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementSubjectOperationReceipt',
      );

  /// Decodes one strict receipt object.
  factory MeasurementSubjectOperationReceiptV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'kind',
        'operationId',
        'purposePolicyRef',
        'schemaVersion',
        'subjectGeneration',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      requiredKeys: const {
        'action',
        'kind',
        'operationId',
        'purposePolicyRef',
        'schemaVersion',
        'subjectGeneration',
        'subjectKind',
        'subjectPolicyRef',
        'target',
      },
      path: 'measurementSubjectOperationReceipt',
    );
    _validateDocument(reader, 'measurementSubjectOperationReceipt');
    final generation = reader.integer('subjectGeneration');
    _requireNonNegativeGeneration(generation, 'subjectGeneration');
    return MeasurementSubjectOperationReceiptV1(
      operationId: reader.string('operationId'),
      target: TargetCoordinate.fromJson(reader.object('target')),
      subjectPolicyRef: SubjectPolicyRefV1.fromJson(
        reader.object('subjectPolicyRef'),
      ),
      purposePolicyRef: PurposePolicyRefV1.fromJson(
        reader.object('purposePolicyRef'),
      ),
      subjectKind: MeasurementSubjectKind.fromWire(
        reader.string('subjectKind'),
      ),
      action: MeasurementSubjectOperationAction.fromWire(
        reader.string('action'),
      ),
      subjectGeneration: generation,
    );
  }

  /// Exact operation identifier.
  final String operationId;

  /// Exact target.
  final TargetCoordinate target;

  /// Exact subject-policy revision.
  final SubjectPolicyRefV1 subjectPolicyRef;

  /// Exact purpose-policy revision.
  final PurposePolicyRefV1 purposePolicyRef;

  /// Governed subject kind.
  final MeasurementSubjectKind subjectKind;

  /// Explicit operation.
  final MeasurementSubjectOperationAction action;

  /// Resulting Measurement-owned generation.
  final int subjectGeneration;

  @override
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        'kind': 'measurementSubjectOperationReceipt',
        'operationId': operationId,
        'purposePolicyRef': purposePolicyRef.toJson(),
        'schemaVersion': kMeasurementSchemaVersion,
        'subjectGeneration': subjectGeneration,
        'subjectKind': subjectKind.wireName,
        'subjectPolicyRef': subjectPolicyRef.toJson(),
        'target': target.toJson(),
      };
}

/// Value result for reset and consent-withdrawal operations.
sealed class MeasurementSubjectOperationResultV1 extends CanonicalValue {
  const MeasurementSubjectOperationResultV1();

  /// Creates a successful subject-operation result.
  const factory MeasurementSubjectOperationResultV1.accepted(
    MeasurementSubjectOperationReceiptV1 receipt,
  ) = MeasurementSubjectOperationAcceptedV1;

  /// Creates a coarse failed subject-operation result.
  const factory MeasurementSubjectOperationResultV1.failed(
    MeasurementLinkFailureV1 failure,
  ) = MeasurementSubjectOperationFailedV1;

  /// Decodes exact canonical subject-operation result bytes.
  factory MeasurementSubjectOperationResultV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementSubjectOperationResultV1.fromJson(
            decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementSubjectOperationResult',
      );

  /// Decodes one strict subject-operation result union.
  factory MeasurementSubjectOperationResultV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'failure', 'kind', 'receipt', 'schemaVersion'},
      requiredKeys: const {'kind', 'schemaVersion'},
      path: 'measurementSubjectOperationResult',
    );
    _validateUnionDocument(reader, 'measurementSubjectOperationResult', const {
      'accepted',
      'failed',
    });
    return switch (reader.string('kind')) {
      'accepted' => MeasurementSubjectOperationAcceptedV1(
          MeasurementSubjectOperationReceiptV1.fromJson(
            _requireUnionObject(reader, 'receipt', 'failure'),
          ),
        ),
      'failed' => MeasurementSubjectOperationFailedV1(
          MeasurementLinkFailureV1.fromJson(
            _requireUnionObject(reader, 'failure', 'receipt'),
          ),
        ),
      _ => throw const CanonicalFormatException(
          'Unknown measurement subject-operation result',
        ),
    };
  }
}

/// Successful subject-operation result.
final class MeasurementSubjectOperationAcceptedV1
    extends MeasurementSubjectOperationResultV1 {
  /// Creates a successful result.
  const MeasurementSubjectOperationAcceptedV1(this.receipt);

  /// Measurement-owned receipt.
  final MeasurementSubjectOperationReceiptV1 receipt;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'accepted',
        'receipt': receipt.toJson(),
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Failed subject-operation result.
final class MeasurementSubjectOperationFailedV1
    extends MeasurementSubjectOperationResultV1 {
  /// Creates a coarse failed result.
  const MeasurementSubjectOperationFailedV1(this.failure);

  /// Existence-hiding failure.
  final MeasurementLinkFailureV1 failure;

  @override
  Map<String, Object?> toJson() => {
        'failure': failure.toJson(),
        'kind': 'failed',
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Closed target selection for the domain-independent privacy coordinator.
///
/// `commerce` is only an opaque domain selection here. This vocabulary does
/// not define a Commerce request, identity, receipt shape, or fallback path.
enum RestagePrivacyTargets {
  /// Run the Measurement domain operation only.
  measurement('measurement'),

  /// Forward an opaque request to the independently-owned Commerce domain.
  commerce('commerce'),

  /// Run both independently-owned domain operations without a shared
  /// transaction, identity, retention clock, tombstone, or rollback.
  both('both');

  const RestagePrivacyTargets(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Domains that must appear exactly once, in canonical order.
  List<RestagePrivacyDomain> get domains => switch (this) {
        RestagePrivacyTargets.measurement => const [
            RestagePrivacyDomain.measurement,
          ],
        RestagePrivacyTargets.commerce => const [RestagePrivacyDomain.commerce],
        RestagePrivacyTargets.both => const [
            RestagePrivacyDomain.measurement,
            RestagePrivacyDomain.commerce,
          ],
      };

  /// Parses a stable canonical target selection.
  static RestagePrivacyTargets fromWire(String value) =>
      _enumFromWire(values, value, 'targets');
}

/// One independently-authoritative privacy domain.
enum RestagePrivacyDomain {
  /// The Measurement domain.
  measurement('measurement'),

  /// The independently-owned Commerce domain.
  commerce('commerce');

  const RestagePrivacyDomain(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical domain spelling.
  static RestagePrivacyDomain fromWire(String value) =>
      _enumFromWire(values, value, 'domain');
}

/// Closed privacy operation action.
enum RestagePrivacyAction {
  /// Produce the domain-local privacy export.
  export('export'),

  /// Perform the domain-local ordered deletion.
  delete('delete');

  const RestagePrivacyAction(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical action spelling.
  static RestagePrivacyAction fromWire(String value) =>
      _enumFromWire(values, value, 'action');
}

/// One domain-local privacy lifecycle status.
enum RestagePrivacyDomainStatus {
  /// The domain durably accepted the operation.
  accepted('accepted'),

  /// The domain has started durable, resumable work.
  inProgress('inProgress'),

  /// The domain completed the operation under its own policy.
  completed('completed'),

  /// The domain failed without an alternate-domain fallback.
  failed('failed');

  const RestagePrivacyDomainStatus(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical domain-status spelling.
  static RestagePrivacyDomainStatus fromWire(String value) =>
      _enumFromWire(values, value, 'domainStatus');
}

/// Closed coordinator status across independently-owned domains.
enum RestagePrivacyCoordinatorStatus {
  /// Every selected domain completed.
  completed('completed'),

  /// Selected domains reached different terminal or progress states.
  partial('partial'),

  /// Every selected domain failed.
  failed('failed');

  const RestagePrivacyCoordinatorStatus(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical coordinator-status spelling.
  static RestagePrivacyCoordinatorStatus fromWire(String value) =>
      _enumFromWire(values, value, 'coordinatorStatus');
}

/// Coarse, domain-independent failure classes for a privacy operation.
enum RestagePrivacyFailureCode {
  /// The domain-specific authenticated proof did not verify.
  invalidProof('invalidProof'),

  /// A domain-specific authenticated proof is no longer fresh.
  expiredProof('expiredProof'),

  /// Policy, consent, region, or requester authority denied the operation.
  notAllowed('notAllowed'),

  /// The operation conflicts with its durable idempotency state.
  conflict('conflict'),

  /// The domain could not make an authority claim safely.
  temporarilyUnavailable('temporarilyUnavailable');

  const RestagePrivacyFailureCode(this.wireName);

  /// Stable canonical spelling.
  final String wireName;

  /// Parses a stable canonical failure spelling.
  static RestagePrivacyFailureCode fromWire(String value) =>
      _enumFromWire(values, value, 'privacyFailureCode');
}

/// Opaque, domain-specific authenticated request material.
///
/// The coordinator copies and transports this canonical carrier but does not
/// decode it. The selected domain is solely responsible for interpreting it;
/// this prevents the coordinator from becoming a shared identity authority.
final class RestagePrivacyDomainAuthority {
  /// Creates one bounded opaque domain authority carrier.
  RestagePrivacyDomainAuthority({
    required this.domain,
    required List<int> requestCanonicalBytes,
  }) : _requestCanonicalBytes = _copyPrivacyCarrier(
          requestCanonicalBytes,
          label: 'privacy domain authority',
          maximumBytes: restagePrivacyMaximumDomainAuthorityBytes,
        );

  /// Decodes one strict nested domain authority object.
  factory RestagePrivacyDomainAuthority.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'domain', 'requestCanonicalBase64Url'},
      requiredKeys: const {'domain', 'requestCanonicalBase64Url'},
      path: path,
    );
    return RestagePrivacyDomainAuthority(
      domain: RestagePrivacyDomain.fromWire(reader.string('domain')),
      requestCanonicalBytes: _decodePrivacyCarrier(
        reader.string('requestCanonicalBase64Url'),
        path: '$path.requestCanonicalBase64Url',
        maximumBytes: restagePrivacyMaximumDomainAuthorityBytes,
      ),
    );
  }

  /// Independently-owned domain that receives this carrier.
  final RestagePrivacyDomain domain;

  final Uint8List _requestCanonicalBytes;

  /// Defensive copy of the domain-local canonical request carrier.
  List<int> get requestCanonicalBytes =>
      List<int>.unmodifiable(_requestCanonicalBytes);

  /// Strict nested JSON representation.
  Map<String, Object?> toJson() => {
        'domain': domain.wireName,
        'requestCanonicalBase64Url': _encodeBase64Url(_requestCanonicalBytes),
      };
}

/// Public, domain-independent privacy coordinator request.
///
/// A selected domain receives exactly one opaque authority carrier. The
/// optional correlation id is convenience metadata only: it is not identity,
/// proof, or cross-domain transaction authority.
final class RestagePrivacyRequestV1 extends CanonicalValue {
  /// Creates a closed privacy coordinator request.
  RestagePrivacyRequestV1({
    required this.targets,
    required this.action,
    required List<RestagePrivacyDomainAuthority> authorities,
    this.correlationId,
  }) : authorities = List<RestagePrivacyDomainAuthority>.unmodifiable(
          List<RestagePrivacyDomainAuthority>.of(authorities),
        ) {
    if (correlationId case final value?) {
      _requireOpaqueId(value, 'correlationId');
    }
    _requireExactPrivacyAuthorityDomains(targets, this.authorities);
  }

  /// Decodes exact canonical privacy coordinator request bytes.
  factory RestagePrivacyRequestV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        RestagePrivacyRequestV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'restagePrivacyRequest',
      );

  /// Decodes one strict privacy coordinator request object.
  factory RestagePrivacyRequestV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'authorities',
        'correlationId',
        'kind',
        'schemaVersion',
        'targets',
      },
      requiredKeys: const {
        'action',
        'authorities',
        'kind',
        'schemaVersion',
        'targets',
      },
      path: 'restagePrivacyRequest',
    );
    _validateDocument(reader, 'restagePrivacyRequest');
    final authorityValues = reader.list('authorities');
    return RestagePrivacyRequestV1(
      targets: RestagePrivacyTargets.fromWire(reader.string('targets')),
      action: RestagePrivacyAction.fromWire(reader.string('action')),
      authorities: List<RestagePrivacyDomainAuthority>.generate(
        authorityValues.length,
        (index) => RestagePrivacyDomainAuthority.fromJson(
          requireCanonicalObject(
            authorityValues[index],
            'restagePrivacyRequest.authorities[$index]',
          ),
          path: 'restagePrivacyRequest.authorities[$index]',
        ),
        growable: false,
      ),
      correlationId: reader.optionalString('correlationId'),
    );
  }

  /// Selected independently-owned domain or domains.
  final RestagePrivacyTargets targets;

  /// Requested domain-local action.
  final RestagePrivacyAction action;

  /// Exact, ordered domain-local authority carriers.
  final List<RestagePrivacyDomainAuthority> authorities;

  /// Optional opaque convenience correlation id.
  final String? correlationId;

  /// Retry fingerprint. Each domain still owns its own idempotency state.
  CanonicalDigest get requestFingerprint => canonicalSha256(
        CanonicalHashDomain.restagePrivacyRequest,
        canonicalBytes,
      );

  @override
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        'authorities': authorities
            .map((authority) => authority.toJson())
            .toList(growable: false),
        if (correlationId != null) 'correlationId': correlationId,
        'kind': 'restagePrivacyRequest',
        'schemaVersion': kMeasurementSchemaVersion,
        'targets': targets.wireName,
      };
}

/// Coarse failure emitted by one independently-owned privacy domain.
final class RestagePrivacyDomainFailureV1 {
  /// Creates a coarse domain failure.
  const RestagePrivacyDomainFailureV1({required this.code});

  /// Decodes one strict nested domain failure object.
  factory RestagePrivacyDomainFailureV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'code', 'kind', 'schemaVersion'},
      requiredKeys: const {'code', 'kind', 'schemaVersion'},
      path: path,
    );
    _validateDocument(reader, 'restagePrivacyDomainFailure');
    return RestagePrivacyDomainFailureV1(
      code: RestagePrivacyFailureCode.fromWire(reader.string('code')),
    );
  }

  /// Coarse existence-hiding failure class.
  final RestagePrivacyFailureCode code;

  /// Strict nested JSON representation.
  Map<String, Object?> toJson() => {
        'code': code.wireName,
        'kind': 'restagePrivacyDomainFailure',
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Independent domain receipt held inside a coordinator result.
///
/// The receipt carrier remains opaque to the coordinator, so each domain keeps
/// its own receipt schema and retention semantics.
final class RestagePrivacyDomainReceipt {
  /// Creates one bounded opaque domain receipt.
  RestagePrivacyDomainReceipt({
    required this.domain,
    required this.action,
    required this.status,
    required this.operationId,
    required List<int> receiptCanonicalBytes,
  }) : _receiptCanonicalBytes = _copyPrivacyCarrier(
          receiptCanonicalBytes,
          label: 'privacy domain receipt',
          maximumBytes: restagePrivacyMaximumDomainReceiptBytes,
        ) {
    if (status == RestagePrivacyDomainStatus.failed) {
      throw ArgumentError.value(
        status,
        'status',
        'A failed domain result cannot contain a receipt',
      );
    }
    _requireOpaqueId(operationId, 'operationId');
  }

  /// Decodes one strict nested domain receipt object.
  factory RestagePrivacyDomainReceipt.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'domain',
        'operationId',
        'receiptCanonicalBase64Url',
        'status',
      },
      requiredKeys: const {
        'action',
        'domain',
        'operationId',
        'receiptCanonicalBase64Url',
        'status',
      },
      path: path,
    );
    return RestagePrivacyDomainReceipt(
      domain: RestagePrivacyDomain.fromWire(reader.string('domain')),
      action: RestagePrivacyAction.fromWire(reader.string('action')),
      status: RestagePrivacyDomainStatus.fromWire(reader.string('status')),
      operationId: reader.string('operationId'),
      receiptCanonicalBytes: _decodePrivacyCarrier(
        reader.string('receiptCanonicalBase64Url'),
        path: '$path.receiptCanonicalBase64Url',
        maximumBytes: restagePrivacyMaximumDomainReceiptBytes,
      ),
    );
  }

  /// Domain that issued the receipt.
  final RestagePrivacyDomain domain;

  /// Domain-local action represented by the receipt.
  final RestagePrivacyAction action;

  /// Domain-local lifecycle status, never `failed` for a receipt.
  final RestagePrivacyDomainStatus status;

  /// Opaque domain-local operation identifier.
  final String operationId;

  final Uint8List _receiptCanonicalBytes;

  /// Defensive copy of the domain-local canonical receipt carrier.
  List<int> get receiptCanonicalBytes =>
      List<int>.unmodifiable(_receiptCanonicalBytes);

  /// Strict nested JSON representation.
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        'domain': domain.wireName,
        'operationId': operationId,
        'receiptCanonicalBase64Url': _encodeBase64Url(_receiptCanonicalBytes),
        'status': status.wireName,
      };
}

/// Closed per-domain result union within a privacy coordinator receipt.
sealed class RestagePrivacyDomainResult {
  const RestagePrivacyDomainResult();

  /// Creates a domain result with its independent receipt and status.
  const factory RestagePrivacyDomainResult.withReceipt(
    RestagePrivacyDomainReceipt receipt,
  ) = RestagePrivacyDomainReceiptResultV1;

  /// Creates a coarse domain failure without a cross-domain fallback.
  const factory RestagePrivacyDomainResult.failed({
    required RestagePrivacyDomain domain,
    required RestagePrivacyAction action,
    required RestagePrivacyDomainFailureV1 failure,
  }) = RestagePrivacyDomainFailedV1;

  /// Decodes one strict nested domain result union.
  factory RestagePrivacyDomainResult.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'domain',
        'failure',
        'kind',
        'receipt',
        'schemaVersion',
      },
      requiredKeys: const {'kind', 'schemaVersion'},
      path: path,
    );
    _validateUnionDocument(reader, path, const {'receipt', 'failed'});
    return switch (reader.string('kind')) {
      'receipt' => RestagePrivacyDomainReceiptResultV1(
          RestagePrivacyDomainReceipt.fromJson(
            _requireUnionObject(reader, 'receipt', 'failure'),
            path: '$path.receipt',
          ),
        ),
      'failed' => RestagePrivacyDomainFailedV1(
          domain: RestagePrivacyDomain.fromWire(reader.string('domain')),
          action: RestagePrivacyAction.fromWire(reader.string('action')),
          failure: RestagePrivacyDomainFailureV1.fromJson(
            _requireUnionObject(reader, 'failure', 'receipt'),
            path: '$path.failure',
          ),
        ),
      _ => throw const CanonicalFormatException(
          'Unknown privacy domain result',
        ),
    };
  }

  /// Domain responsible for this result.
  RestagePrivacyDomain get domain;

  /// Domain-local action represented by this result.
  RestagePrivacyAction get action;

  /// Domain-local status represented by this result.
  RestagePrivacyDomainStatus get status;

  /// Strict nested JSON representation.
  Map<String, Object?> toJson();
}

/// A nonfailed independent domain result.
final class RestagePrivacyDomainReceiptResultV1
    extends RestagePrivacyDomainResult {
  /// Creates a result carrying an independent receipt.
  const RestagePrivacyDomainReceiptResultV1(this.receipt);

  /// Domain-local receipt.
  final RestagePrivacyDomainReceipt receipt;

  @override
  RestagePrivacyDomain get domain => receipt.domain;

  @override
  RestagePrivacyAction get action => receipt.action;

  @override
  RestagePrivacyDomainStatus get status => receipt.status;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'receipt',
        'receipt': receipt.toJson(),
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// A coarse failed independent domain result.
final class RestagePrivacyDomainFailedV1 extends RestagePrivacyDomainResult {
  /// Creates a failed result without an alternate-domain fallback.
  const RestagePrivacyDomainFailedV1({
    required this.domain,
    required this.action,
    required this.failure,
  });

  @override
  final RestagePrivacyDomain domain;

  @override
  final RestagePrivacyAction action;

  /// Domain-local coarse failure.
  final RestagePrivacyDomainFailureV1 failure;

  @override
  RestagePrivacyDomainStatus get status => RestagePrivacyDomainStatus.failed;

  @override
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        'domain': domain.wireName,
        'failure': failure.toJson(),
        'kind': 'failed',
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// Domain-independent privacy coordinator receipt.
///
/// The coordinator reports independent domain results honestly. It does not
/// perform a shared transaction, rollback a completed domain, or combine
/// identity, retention, tombstone, or deletion state.
final class RestagePrivacyReceiptV1 extends CanonicalValue {
  /// Creates a closed coordinator receipt.
  RestagePrivacyReceiptV1({
    required this.targets,
    required this.action,
    required this.status,
    required List<RestagePrivacyDomainResult> domainResults,
    this.correlationId,
  }) : domainResults = List<RestagePrivacyDomainResult>.unmodifiable(
          List<RestagePrivacyDomainResult>.of(domainResults),
        ) {
    if (correlationId case final value?) {
      _requireOpaqueId(value, 'correlationId');
    }
    _requireExactPrivacyResultDomains(targets, action, this.domainResults);
    if (_coordinatorStatusFor(this.domainResults) != status) {
      throw ArgumentError.value(
        status,
        'status',
        'Coordinator status must match the independent domain results',
      );
    }
  }

  /// Decodes exact canonical coordinator receipt bytes.
  factory RestagePrivacyReceiptV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        RestagePrivacyReceiptV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'restagePrivacyReceipt',
      );

  /// Decodes one strict coordinator receipt object.
  factory RestagePrivacyReceiptV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'action',
        'correlationId',
        'domainResults',
        'kind',
        'schemaVersion',
        'status',
        'targets',
      },
      requiredKeys: const {
        'action',
        'domainResults',
        'kind',
        'schemaVersion',
        'status',
        'targets',
      },
      path: 'restagePrivacyReceipt',
    );
    _validateDocument(reader, 'restagePrivacyReceipt');
    final values = reader.list('domainResults');
    return RestagePrivacyReceiptV1(
      targets: RestagePrivacyTargets.fromWire(reader.string('targets')),
      action: RestagePrivacyAction.fromWire(reader.string('action')),
      status: RestagePrivacyCoordinatorStatus.fromWire(
        reader.string('status'),
      ),
      domainResults: List<RestagePrivacyDomainResult>.generate(
        values.length,
        (index) => RestagePrivacyDomainResult.fromJson(
          requireCanonicalObject(
            values[index],
            'restagePrivacyReceipt.domainResults[$index]',
          ),
          path: 'restagePrivacyReceipt.domainResults[$index]',
        ),
        growable: false,
      ),
      correlationId: reader.optionalString('correlationId'),
    );
  }

  /// Selected independently-owned domain or domains.
  final RestagePrivacyTargets targets;

  /// Requested domain-local action.
  final RestagePrivacyAction action;

  /// Honest aggregate status across the selected domains.
  final RestagePrivacyCoordinatorStatus status;

  /// Exact ordered independent domain results.
  final List<RestagePrivacyDomainResult> domainResults;

  /// Optional opaque convenience correlation id from the request.
  final String? correlationId;

  @override
  Map<String, Object?> toJson() => {
        'action': action.wireName,
        if (correlationId != null) 'correlationId': correlationId,
        'domainResults': domainResults
            .map((result) => result.toJson())
            .toList(growable: false),
        'kind': 'restagePrivacyReceipt',
        'schemaVersion': kMeasurementSchemaVersion,
        'status': status.wireName,
        'targets': targets.wireName,
      };
}

void _requireExactPrivacyAuthorityDomains(
  RestagePrivacyTargets targets,
  List<RestagePrivacyDomainAuthority> authorities,
) {
  final expected = targets.domains;
  if (authorities.length != expected.length) {
    throw ArgumentError.value(
      authorities,
      'authorities',
      'Expected exactly one authority carrier for each selected domain',
    );
  }
  for (var index = 0; index < expected.length; index++) {
    if (authorities[index].domain != expected[index]) {
      throw ArgumentError.value(
        authorities,
        'authorities',
        'Authority carriers must name selected domains in canonical order',
      );
    }
  }
}

void _requireExactPrivacyResultDomains(
  RestagePrivacyTargets targets,
  RestagePrivacyAction action,
  List<RestagePrivacyDomainResult> domainResults,
) {
  final expected = targets.domains;
  if (domainResults.length != expected.length) {
    throw ArgumentError.value(
      domainResults,
      'domainResults',
      'Expected exactly one result for each selected domain',
    );
  }
  for (var index = 0; index < expected.length; index++) {
    final result = domainResults[index];
    if (result.domain != expected[index] || result.action != action) {
      throw ArgumentError.value(
        domainResults,
        'domainResults',
        'Results must name selected domains and the requested action exactly',
      );
    }
  }
}

RestagePrivacyCoordinatorStatus _coordinatorStatusFor(
  List<RestagePrivacyDomainResult> results,
) {
  if (results.every(
    (result) => result.status == RestagePrivacyDomainStatus.completed,
  )) {
    return RestagePrivacyCoordinatorStatus.completed;
  }
  if (results.every(
    (result) => result.status == RestagePrivacyDomainStatus.failed,
  )) {
    return RestagePrivacyCoordinatorStatus.failed;
  }
  return RestagePrivacyCoordinatorStatus.partial;
}

Uint8List _copyPrivacyCarrier(
  List<int> bytes, {
  required String label,
  required int maximumBytes,
}) {
  final copy = _copyBytes(bytes, label);
  if (copy.length > maximumBytes) {
    throw ArgumentError.value(bytes, label, 'Exceeds the bounded carrier size');
  }
  return copy;
}

Uint8List _decodePrivacyCarrier(
  String value, {
  required String path,
  required int maximumBytes,
}) {
  final decoded = _decodeBase64Url(value, path: path);
  if (decoded.length > maximumBytes) {
    throw CanonicalFormatException('$path exceeds the bounded carrier size');
  }
  return decoded;
}

CanonicalObjectReader _linkRequestReader(
  Map<String, Object?> json,
  String path, {
  Set<String> extraKeys = const {},
}) {
  final keys = <String>{
    'assertionBytesBase64Url',
    'challenge',
    'consentEvidenceBase64Url',
    'expectedSubjectGeneration',
    'kind',
    'regionEvidenceBase64Url',
    'schemaVersion',
    ...extraKeys,
  };
  final required = <String>{
    'assertionBytesBase64Url',
    'challenge',
    'consentEvidenceBase64Url',
    'kind',
    'regionEvidenceBase64Url',
    'schemaVersion',
    ...extraKeys,
  };
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: keys,
    requiredKeys: required,
    path: path,
  );
  _validateDocument(reader, path);
  return reader;
}

MeasurementLinkAcceptedV1 _decodeAcceptedLinkResult(
  CanonicalObjectReader reader,
) =>
    MeasurementLinkAcceptedV1(
      MeasurementLinkReceiptV1.fromJson(
        _requireUnionObject(reader, 'receipt', 'failure'),
      ),
    );

MeasurementLinkFailedV1 _decodeFailedLinkResult(CanonicalObjectReader reader) =>
    MeasurementLinkFailedV1(
      MeasurementLinkFailureV1.fromJson(
        _requireUnionObject(reader, 'failure', 'receipt'),
      ),
    );

Map<String, Object?> _requireUnionObject(
  CanonicalObjectReader reader,
  String requiredKey,
  String forbiddenKey,
) {
  final value = reader.optionalObject(requiredKey);
  if (value == null) {
    throw CanonicalFormatException(
      '${reader.path}.$requiredKey is required for ${reader.string('kind')}',
    );
  }
  if (reader.optionalObject(forbiddenKey) != null) {
    throw CanonicalFormatException(
      '${reader.path} may not contain both $requiredKey and $forbiddenKey',
    );
  }
  return value;
}

void _validateUnionDocument(
  CanonicalObjectReader reader,
  String path,
  Set<String> allowedKinds,
) {
  final version = reader.integer('schemaVersion');
  if (version != kMeasurementSchemaVersion) {
    throw CanonicalFormatException(
      '$path.schemaVersion $version is unsupported',
    );
  }
  final kind = reader.string('kind');
  if (!allowedKinds.contains(kind)) {
    throw CanonicalFormatException('$path.kind "$kind" is unsupported');
  }
}

T _enumFromWire<T extends Enum>(List<T> values, String value, String path) {
  for (final candidate in values) {
    final wireName = (candidate as dynamic).wireName as String;
    if (wireName == value) return candidate;
  }
  throw CanonicalFormatException('$path contains unknown value "$value"');
}

void _validateDocument(CanonicalObjectReader reader, String kind) {
  validateCanonicalDocument(reader, expectedKind: kind);
}

String _requireOpaqueId(String value, String name) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'Expected a bounded opaque operation or correlation identifier',
    );
  }
  return value;
}

void _requireNonNegativeGeneration(int value, String name) {
  if (value < 0 || value > kMaximumPortableJsonInteger) {
    throw ArgumentError.value(
      value,
      name,
      'Expected a non-negative generation',
    );
  }
}

void _requireOptionalGeneration(int? value) {
  if (value != null) {
    _requireNonNegativeGeneration(value, 'expectedSubjectGeneration');
  }
}

Uint8List _copyBytes(List<int> bytes, String label) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, label, 'Must not be empty');
  }
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError.value(bytes, label, 'Must contain octets only');
    }
  }
  return Uint8List.fromList(bytes);
}

Uint8List _requireExactBytes(List<int> bytes, int length, String label) {
  final copy = _copyBytes(bytes, label);
  if (copy.length != length) {
    throw ArgumentError.value(
      bytes,
      label,
      'Must contain exactly $length bytes',
    );
  }
  return copy;
}

String _encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decodeBase64Url(String value, {required String path}) {
  if (value.isEmpty ||
      value.contains('=') ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw CanonicalFormatException('$path must be unpadded base64url');
  }
  try {
    final decoded = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (_encodeBase64Url(decoded) != value) {
      throw CanonicalFormatException('$path is not canonical base64url');
    }
    return decoded;
  } on FormatException {
    throw CanonicalFormatException('$path must be unpadded base64url');
  }
}

DateTime _dateFromMicros(int micros) {
  if (micros < 0 || micros > kMaximumPortableJsonInteger) {
    throw const CanonicalFormatException(
      'Timestamp is outside the portable range',
    );
  }
  return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
}
