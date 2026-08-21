import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/governed_measurement_transport.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  test('fails closed before a host authority is installed', () async {
    final challengeResult = await Restage.measurement.issueLinkChallenge(
      _challengeRequest(),
    );
    final linkResult = await Restage.measurement.linkSubject(_linkRequest());
    final resetResult = await Restage.measurement.resetSubject(
      _subjectOperation(MeasurementSubjectOperationAction.resetSubject),
    );
    final withdrawResult = await Restage.measurement.withdrawConsent(
      _subjectOperation(MeasurementSubjectOperationAction.withdrawConsent),
    );
    final privacyReceipt = await Restage.privacy.request(_privacyRequest());

    expect(challengeResult, isA<MeasurementLinkChallengeFailedV1>());
    expect(
      (challengeResult as MeasurementLinkChallengeFailedV1).failure.code,
      MeasurementLinkFailureCode.temporarilyUnavailable,
    );
    expect(linkResult, isA<MeasurementLinkFailedV1>());
    expect(
      (linkResult as MeasurementLinkFailedV1).failure.code,
      MeasurementLinkFailureCode.temporarilyUnavailable,
    );
    expect(resetResult, isA<MeasurementSubjectOperationFailedV1>());
    expect(
      (resetResult as MeasurementSubjectOperationFailedV1).failure.code,
      MeasurementLinkFailureCode.temporarilyUnavailable,
    );
    expect(withdrawResult, isA<MeasurementSubjectOperationFailedV1>());
    expect(
      (withdrawResult as MeasurementSubjectOperationFailedV1).failure.code,
      MeasurementLinkFailureCode.temporarilyUnavailable,
    );
    expect(privacyReceipt.status, RestagePrivacyCoordinatorStatus.failed);
    expect(privacyReceipt.domainResults, hasLength(1));
    expect(
      (privacyReceipt.domainResults.single as RestagePrivacyDomainFailedV1)
          .failure
          .code,
      RestagePrivacyFailureCode.temporarilyUnavailable,
    );
  });

  test(
    'forwards the direct request without activating SDK authority',
    () async {
      final port = _RecordingPort();
      GovernedMeasurementPortRegistry.debugInstall(port);
      final challengeRequest = _challengeRequest();
      final request = _linkRequest();

      await Restage.measurement.issueLinkChallenge(challengeRequest);
      final result = await Restage.measurement.linkSubject(request);

      expect(port.challengeCalls, 1);
      expect(port.lastChallengeRequest, same(challengeRequest));
      expect(port.linkCalls, 1);
      expect(port.lastLinkRequest, same(request));
      expect(result, isA<MeasurementLinkFailedV1>());
      expect(
        (result as MeasurementLinkFailedV1).failure.code,
        MeasurementLinkFailureCode.notAllowed,
      );
    },
  );

  test(
    'routes reset and withdrawal only to their matching explicit methods',
    () async {
      final port = _RecordingPort();
      GovernedMeasurementPortRegistry.debugInstall(port);

      await Restage.measurement.resetSubject(
        _subjectOperation(MeasurementSubjectOperationAction.resetSubject),
      );
      await Restage.measurement.withdrawConsent(
        _subjectOperation(MeasurementSubjectOperationAction.withdrawConsent),
      );
      final mismatchedReset = await Restage.measurement.resetSubject(
        _subjectOperation(MeasurementSubjectOperationAction.withdrawConsent),
      );
      final mismatchedWithdraw = await Restage.measurement.withdrawConsent(
        _subjectOperation(MeasurementSubjectOperationAction.resetSubject),
      );

      expect(port.resetCalls, 1);
      expect(port.withdrawCalls, 1);
      expect(mismatchedReset, isA<MeasurementSubjectOperationFailedV1>());
      expect(
        (mismatchedReset as MeasurementSubjectOperationFailedV1).failure.code,
        MeasurementLinkFailureCode.notAllowed,
      );
      expect(mismatchedWithdraw, isA<MeasurementSubjectOperationFailedV1>());
      expect(
        (mismatchedWithdraw as MeasurementSubjectOperationFailedV1)
            .failure
            .code,
        MeasurementLinkFailureCode.notAllowed,
      );
    },
  );

  test(
    'legacy analytics identity remains disjoint from governed operations',
    () async {
      final port = _RecordingPort();
      GovernedMeasurementPortRegistry.debugInstall(port);
      Restage.configure(apiKey: 'legacy-test-key', identity: () async => null);

      Restage.reset();

      expect(port.linkCalls, 0);
      expect(port.challengeCalls, 0);
      expect(port.resetCalls, 0);
      expect(port.withdrawCalls, 0);
      expect(port.privacyCalls, 0);
    },
  );

  test('privacy forwards a closed coordinator request unchanged', () async {
    final port = _RecordingPort();
    GovernedMeasurementPortRegistry.debugInstall(port);
    final request = _privacyRequest();

    final receipt = await Restage.privacy.request(request);

    expect(port.privacyCalls, 1);
    expect(port.lastPrivacyRequest, same(request));
    expect(receipt.status, RestagePrivacyCoordinatorStatus.failed);
  });

  test('configure installs an explicit governed transport seam', () async {
    final port = _RecordingPort();
    Restage.configure(
      apiKey: 'direct-test-key',
      governedMeasurementTransport: port,
    );

    await Restage.measurement.linkSubject(_linkRequest());

    expect(port.linkCalls, 1);
  });
}

final class _RecordingPort implements RestageGovernedMeasurementTransport {
  int challengeCalls = 0;
  int linkCalls = 0;
  int resetCalls = 0;
  int withdrawCalls = 0;
  int privacyCalls = 0;
  MeasurementLinkChallengeRequestV1? lastChallengeRequest;
  MeasurementLinkRequestV1? lastLinkRequest;
  RestagePrivacyRequestV1? lastPrivacyRequest;

  @override
  Future<MeasurementLinkChallengeOperationResultV1> issueLinkChallenge(
    MeasurementLinkChallengeRequestV1 request,
  ) async {
    challengeCalls += 1;
    lastChallengeRequest = request;
    return const MeasurementLinkChallengeOperationResultV1.failed(
      MeasurementLinkFailureV1(code: MeasurementLinkFailureCode.notAllowed),
    );
  }

  @override
  Future<MeasurementLinkOperationResultV1> linkSubject(
    MeasurementLinkRequestV1 request,
  ) async {
    linkCalls += 1;
    lastLinkRequest = request;
    return const MeasurementLinkOperationResultV1.failed(
      MeasurementLinkFailureV1(code: MeasurementLinkFailureCode.notAllowed),
    );
  }

  @override
  Future<MeasurementSubjectOperationResultV1> resetSubject(
    MeasurementSubjectOperationRequestV1 request,
  ) async {
    resetCalls += 1;
    return const MeasurementSubjectOperationResultV1.failed(
      MeasurementLinkFailureV1(code: MeasurementLinkFailureCode.notAllowed),
    );
  }

  @override
  Future<MeasurementSubjectOperationResultV1> withdrawConsent(
    MeasurementSubjectOperationRequestV1 request,
  ) async {
    withdrawCalls += 1;
    return const MeasurementSubjectOperationResultV1.failed(
      MeasurementLinkFailureV1(code: MeasurementLinkFailureCode.notAllowed),
    );
  }

  @override
  Future<RestagePrivacyReceiptV1> requestPrivacy(
    RestagePrivacyRequestV1 request,
  ) async {
    privacyCalls += 1;
    lastPrivacyRequest = request;
    return RestagePrivacyReceiptV1(
      targets: request.targets,
      action: request.action,
      correlationId: request.correlationId,
      status: RestagePrivacyCoordinatorStatus.failed,
      domainResults: request.targets.domains
          .map(
            (domain) => RestagePrivacyDomainResult.failed(
              domain: domain,
              action: request.action,
              failure: const RestagePrivacyDomainFailureV1(
                code: RestagePrivacyFailureCode.notAllowed,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

MeasurementLinkChallengeRequestV1 _challengeRequest() =>
    MeasurementLinkChallengeRequestV1(
      operationId: 'challenge-op-1',
      target: _target(),
      subjectPolicyRef: _subjectPolicyRef(),
      purposePolicyRef: _purposePolicyRef(),
      subjectKind: MeasurementSubjectKind.identifiedUser,
      action: MeasurementLinkAction.linkSubject,
      expectedSubjectGeneration: 1,
      requesterBinding: MeasurementRequesterBinding([12, 13]),
    );

MeasurementLinkRequestV1 _linkRequest() => MeasurementLinkRequestV1(
      challenge: _challenge(),
      assertionBytes: [1, 2, 3],
      consentEvidence: MeasurementConsentEvidence([8, 9]),
      regionEvidence: MeasurementRegionEvidence([10, 11]),
      expectedSubjectGeneration: 1,
    );

MeasurementLinkChallengeV1 _challenge() {
  final issuedAt = DateTime.utc(2026, 8, 14, 12);
  return MeasurementLinkChallengeV1(
    operationId: 'link-op-1',
    challengeNonce: List<int>.filled(32, 7),
    target: _target(),
    subjectPolicyRef: _subjectPolicyRef(),
    purposePolicyRef: _purposePolicyRef(),
    subjectKind: MeasurementSubjectKind.identifiedUser,
    action: MeasurementLinkAction.linkSubject,
    expectedSubjectGeneration: 1,
    requesterBinding: MeasurementRequesterBinding([12, 13]),
    serverIssuedAt: issuedAt,
    expiresAt: issuedAt.add(measurementLinkMaximumChallengeLifetime),
  );
}

MeasurementSubjectOperationRequestV1 _subjectOperation(
  MeasurementSubjectOperationAction action,
) =>
    MeasurementSubjectOperationRequestV1(
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

RestagePrivacyRequestV1 _privacyRequest() => RestagePrivacyRequestV1(
      targets: RestagePrivacyTargets.measurement,
      action: RestagePrivacyAction.delete,
      authorities: [
        RestagePrivacyDomainAuthority(
          domain: RestagePrivacyDomain.measurement,
          requestCanonicalBytes: _subjectOperation(
            MeasurementSubjectOperationAction.resetSubject,
          ).canonicalBytes,
        ),
      ],
    );

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
