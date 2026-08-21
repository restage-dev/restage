import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test(
    'direct link requests copy transient bytes and round-trip canonically',
    () {
      final assertionBytes = <int>[1, 2, 3, 4];
      final request = _linkRequest(assertionBytes: assertionBytes);
      assertionBytes[0] = 99;

      expect(request.assertionBytes, [1, 2, 3, 4]);
      final decoded = MeasurementLinkRequestV1.fromCanonicalBytes(
        request.canonicalBytes,
      );
      expect(decoded.assertionBytes, request.assertionBytes);
      expect(decoded.requestFingerprint.hex, request.requestFingerprint.hex);

      final changed = _linkRequest(assertionBytes: [9, 2, 3, 4]);
      expect(
        changed.requestFingerprint.hex,
        isNot(request.requestFingerprint.hex),
      );
    },
  );

  test('challenges enforce a 256-bit nonce and five-minute lifetime', () {
    final challenge = _challenge(subjectKind: MeasurementSubjectKind.account);
    expect(challenge.challengeNonce, List<int>.filled(32, 7));
    expect(
      challenge.expiresAt.difference(challenge.serverIssuedAt),
      measurementLinkMaximumChallengeLifetime,
    );

    expect(
      () => _challenge(nonce: List<int>.filled(31, 7)),
      throwsArgumentError,
    );
    expect(
      () => _challenge(
        expiresAt: challenge.serverIssuedAt.add(
          measurementLinkMaximumChallengeLifetime + const Duration(seconds: 1),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('link receipts and coarse failures are closed canonical unions', () {
    final receipt = MeasurementLinkReceiptV1(
      operationId: 'link-op-1',
      target: _target(),
      subjectPolicyRef: _subjectPolicyRef(),
      purposePolicyRef: _purposePolicyRef(),
      subjectKind: MeasurementSubjectKind.identifiedUser,
      linkGeneration: 2,
      result: MeasurementLinkReceiptResult.linked,
      provenance: MeasurementLinkProvenance.directHostAssertion,
    );
    final accepted = MeasurementLinkOperationResultV1.accepted(receipt);
    final decoded = MeasurementLinkOperationResultV1.fromCanonicalBytes(
      accepted.canonicalBytes,
    );

    expect(decoded, isA<MeasurementLinkAcceptedV1>());
    expect(
      (decoded as MeasurementLinkAcceptedV1).receipt.canonicalBytes,
      receipt.canonicalBytes,
    );
    expect(receipt.toJson().containsKey('assertionBytesBase64Url'), isFalse);

    const failed = MeasurementLinkOperationResultV1.failed(
      MeasurementLinkFailureV1(
        code: MeasurementLinkFailureCode.temporarilyUnavailable,
      ),
    );
    final extraKey = Map<String, Object?>.from(failed.toJson())
      ..['unexpected'] = true;
    expect(
      () => MeasurementLinkOperationResultV1.fromJson(extraKey),
      throwsA(isA<CanonicalFormatException>()),
    );

    final wrongVersion = Map<String, Object?>.from(failed.toJson())
      ..['schemaVersion'] = 2;
    expect(
      () => MeasurementLinkOperationResultV1.fromJson(wrongVersion),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test('subject operations carry explicit action and receipt authority', () {
    final request = _subjectOperation(
      action: MeasurementSubjectOperationAction.withdrawConsent,
    );
    final decodedRequest =
        MeasurementSubjectOperationRequestV1.fromCanonicalBytes(
      request.canonicalBytes,
    );
    expect(
      decodedRequest.action,
      MeasurementSubjectOperationAction.withdrawConsent,
    );

    final receipt = MeasurementSubjectOperationReceiptV1(
      operationId: 'subject-op-1',
      target: _target(),
      subjectPolicyRef: _subjectPolicyRef(),
      purposePolicyRef: _purposePolicyRef(),
      subjectKind: MeasurementSubjectKind.identifiedUser,
      action: MeasurementSubjectOperationAction.withdrawConsent,
      subjectGeneration: 3,
    );
    final result = MeasurementSubjectOperationResultV1.accepted(receipt);
    final decodedResult =
        MeasurementSubjectOperationResultV1.fromCanonicalBytes(
      result.canonicalBytes,
    );
    expect(decodedResult, isA<MeasurementSubjectOperationAcceptedV1>());
    expect(
      (decodedResult as MeasurementSubjectOperationAcceptedV1).receipt.action,
      MeasurementSubjectOperationAction.withdrawConsent,
    );
  });

  test(
    'direct challenge issuance is a closed canonical request/result path',
    () {
      final request = MeasurementLinkChallengeRequestV1(
        operationId: 'challenge-op-1',
        target: _target(),
        subjectPolicyRef: _subjectPolicyRef(),
        purposePolicyRef: _purposePolicyRef(),
        subjectKind: MeasurementSubjectKind.account,
        action: MeasurementLinkAction.linkSubject,
        expectedSubjectGeneration: 3,
        requesterBinding: MeasurementRequesterBinding([4, 5, 6]),
      );
      final decoded = MeasurementLinkChallengeRequestV1.fromCanonicalBytes(
        request.canonicalBytes,
      );
      expect(decoded.requestFingerprint, request.requestFingerprint);
      expect(decoded.subjectKind, MeasurementSubjectKind.account);

      final accepted = MeasurementLinkChallengeOperationResultV1.accepted(
        _challenge(subjectKind: MeasurementSubjectKind.account),
      );
      expect(
        MeasurementLinkChallengeOperationResultV1.fromCanonicalBytes(
          accepted.canonicalBytes,
        ),
        isA<MeasurementLinkChallengeAcceptedV1>(),
      );

      final invalid = Map<String, Object?>.from(request.toJson())
        ..['action'] = 'unexpected';
      expect(
        () => MeasurementLinkChallengeRequestV1.fromJson(invalid),
        throwsA(isA<CanonicalFormatException>()),
      );
    },
  );

  test(
    'privacy coordinator preserves independent domain authority and status',
    () {
      final measurementAuthority = <int>[1, 2, 3];
      final request = RestagePrivacyRequestV1(
        targets: RestagePrivacyTargets.both,
        action: RestagePrivacyAction.delete,
        correlationId: 'privacy-correlation-1',
        authorities: [
          RestagePrivacyDomainAuthority(
            domain: RestagePrivacyDomain.measurement,
            requestCanonicalBytes: measurementAuthority,
          ),
          RestagePrivacyDomainAuthority(
            domain: RestagePrivacyDomain.commerce,
            requestCanonicalBytes: [4, 5, 6],
          ),
        ],
      );
      measurementAuthority[0] = 99;
      final decoded = RestagePrivacyRequestV1.fromCanonicalBytes(
        request.canonicalBytes,
      );
      expect(decoded.authorities.first.requestCanonicalBytes, [1, 2, 3]);
      expect(decoded.requestFingerprint, request.requestFingerprint);

      final receipt = RestagePrivacyReceiptV1(
        targets: RestagePrivacyTargets.both,
        action: RestagePrivacyAction.delete,
        correlationId: request.correlationId,
        status: RestagePrivacyCoordinatorStatus.partial,
        domainResults: [
          RestagePrivacyDomainResult.withReceipt(
            RestagePrivacyDomainReceipt(
              domain: RestagePrivacyDomain.measurement,
              action: RestagePrivacyAction.delete,
              status: RestagePrivacyDomainStatus.completed,
              operationId: 'privacy-measurement-op-1',
              receiptCanonicalBytes: [7, 8, 9],
            ),
          ),
          const RestagePrivacyDomainResult.failed(
            domain: RestagePrivacyDomain.commerce,
            action: RestagePrivacyAction.delete,
            failure: RestagePrivacyDomainFailureV1(
              code: RestagePrivacyFailureCode.temporarilyUnavailable,
            ),
          ),
        ],
      );
      final decodedReceipt = RestagePrivacyReceiptV1.fromCanonicalBytes(
        receipt.canonicalBytes,
      );
      expect(decodedReceipt.status, RestagePrivacyCoordinatorStatus.partial);
      expect(decodedReceipt.domainResults, hasLength(2));
      expect(
        decodedReceipt.domainResults.last,
        isA<RestagePrivacyDomainFailedV1>(),
      );
    },
  );

  test(
    'privacy coordinator rejects missing domains and dishonest aggregate state',
    () {
      expect(
        () => RestagePrivacyRequestV1(
          targets: RestagePrivacyTargets.both,
          action: RestagePrivacyAction.delete,
          authorities: [
            RestagePrivacyDomainAuthority(
              domain: RestagePrivacyDomain.measurement,
              requestCanonicalBytes: [1],
            ),
          ],
        ),
        throwsArgumentError,
      );

      expect(
        () => RestagePrivacyReceiptV1(
          targets: RestagePrivacyTargets.measurement,
          action: RestagePrivacyAction.delete,
          status: RestagePrivacyCoordinatorStatus.completed,
          domainResults: [
            const RestagePrivacyDomainResult.failed(
              domain: RestagePrivacyDomain.measurement,
              action: RestagePrivacyAction.delete,
              failure: RestagePrivacyDomainFailureV1(
                code: RestagePrivacyFailureCode.notAllowed,
              ),
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
}

MeasurementLinkRequestV1 _linkRequest({required List<int> assertionBytes}) {
  return MeasurementLinkRequestV1(
    challenge: _challenge(),
    assertionBytes: assertionBytes,
    consentEvidence: MeasurementConsentEvidence([8, 9]),
    regionEvidence: MeasurementRegionEvidence([10, 11]),
    expectedSubjectGeneration: 1,
  );
}

MeasurementLinkChallengeV1 _challenge({
  MeasurementSubjectKind subjectKind = MeasurementSubjectKind.identifiedUser,
  List<int>? nonce,
  DateTime? expiresAt,
}) {
  final issuedAt = DateTime.utc(2026, 8, 14, 12);
  return MeasurementLinkChallengeV1(
    operationId: 'link-op-1',
    challengeNonce: nonce ?? List<int>.filled(32, 7),
    target: _target(),
    subjectPolicyRef: _subjectPolicyRef(),
    purposePolicyRef: _purposePolicyRef(),
    subjectKind: subjectKind,
    action: MeasurementLinkAction.linkSubject,
    expectedSubjectGeneration: 1,
    requesterBinding: MeasurementRequesterBinding([12, 13]),
    serverIssuedAt: issuedAt,
    expiresAt:
        expiresAt ?? issuedAt.add(measurementLinkMaximumChallengeLifetime),
  );
}

MeasurementSubjectOperationRequestV1 _subjectOperation({
  required MeasurementSubjectOperationAction action,
}) {
  return MeasurementSubjectOperationRequestV1(
    operationId: 'subject-op-1',
    target: _target(),
    subjectPolicyRef: _subjectPolicyRef(),
    purposePolicyRef: _purposePolicyRef(),
    subjectKind: MeasurementSubjectKind.identifiedUser,
    action: action,
    requesterBinding: MeasurementRequesterBinding([12, 13]),
    assertionBytes: [1, 2, 3],
    consentEvidence: MeasurementConsentEvidence([8, 9]),
    regionEvidence: MeasurementRegionEvidence([10, 11]),
    expectedSubjectGeneration: 1,
  );
}

TargetCoordinate _target() => TargetCoordinate(
      organizationId: OrganizationId(1),
      appId: ApplicationId(2),
      environmentTargetId: EnvironmentTargetId(3),
      namedEnvironmentId: NamedEnvironmentId(4),
      runtimePlane: RuntimePlane.live,
    );

SubjectPolicyRefV1 _subjectPolicyRef() => SubjectPolicyRefV1(
      subjectPolicyId: SubjectPolicyId('subject-policy-v1'),
      revisionId: SubjectPolicyRevisionId('subject-policy-v1-r1'),
      semanticHash: _digest('a'),
    );

PurposePolicyRefV1 _purposePolicyRef() => PurposePolicyRefV1(
      revisionId: PurposePolicyRevisionId('purpose-policy-v1-r1'),
      semanticHash: _digest('b'),
    );

CanonicalDigest _digest(String character) =>
    CanonicalDigest(List<String>.filled(64, character).join());
