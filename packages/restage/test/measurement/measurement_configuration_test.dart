import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/measurement/measurement_host_construction_owner.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_ingest_transport.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/measurement/measurement_worker_delivery.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;

import '../support/hosted_artifact_delivery.dart';
import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

import '../support/restage_runtime_test_support.dart';

void main() {
  installRestageRuntimeTestSupport();

  test('measurement configuration controls new host sessions', () async {
    final bindingReadPort = _CountingBindingReadPort();
    final ingestAdapter = _RecordingIngestAdapter();
    var hostedLookups = 0;
    var nonceCalls = 0;
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
      MeasurementHostSessionConstructionAuthority.forTesting(
        transport: MeasurementIngestTransport.adapter(ingestAdapter),
        hostedBindingReadPortLookup: () {
          hostedLookups += 1;
          return bindingReadPort;
        },
        nonceBytesSource: () {
          nonceCalls += 1;
          return List<int>.filled(32, 1);
        },
      ),
    );
    addTearDown(restore);
    final payload = BlobPaywallPayload(
      attachMeasurementPublicationBindingReference(
        ResolvedVariant(
          bytes: Uint8List.fromList(const <int>[1]),
          paywallId: 'measurement-configuration',
          surfaceVersion: 'measurement-configuration.v1',
        ),
        _bindingReference,
      ),
    );

    Restage.configure(apiKey: 'rs_pk_measurement_configuration');
    final defaultSession =
        await MeasurementHostSessionController.openForResolvedArtifact(payload);

    expect(
        defaultSession.debugState, MeasurementHostSessionDebugState.disabled);
    expect(hostedLookups, 1);
    expect(bindingReadPort.references, [_bindingReference]);
    expect(nonceCalls, 0);
    expect(ingestAdapter.requests, isEmpty);

    hostedLookups = 0;
    bindingReadPort.references.clear();
    Restage.configure(
      apiKey: 'rs_pk_measurement_configuration',
      measurementEnabled: false,
    );
    final disabledSession =
        await MeasurementHostSessionController.openForResolvedArtifact(payload);
    final directDisabledSession = await MeasurementHostSessionController.open(
      MeasurementHostSessionOpenRequest.hosted(
        bindingReference: _bindingReference,
        bindingReadPort: bindingReadPort,
      ),
    );

    expect(
        disabledSession.debugState, MeasurementHostSessionDebugState.disabled);
    expect(
      directDisabledSession.debugState,
      MeasurementHostSessionDebugState.disabled,
    );
    expect(hostedLookups, 0);
    expect(bindingReadPort.references, isEmpty);
    expect(nonceCalls, 0);
    expect(ingestAdapter.requests, isEmpty);

    Restage.configure(
      apiKey: 'rs_pk_measurement_configuration',
      analyticsEnabled: false,
      measurementEnabled: true,
    );
    final restoredSession =
        await MeasurementHostSessionController.openForResolvedArtifact(payload);

    expect(
        restoredSession.debugState, MeasurementHostSessionDebugState.disabled);
    expect(hostedLookups, 1);
    expect(bindingReadPort.references, [_bindingReference]);
    expect(nonceCalls, 0);
    expect(ingestAdapter.requests, isEmpty);
  });

  testWidgets(
      'hosted resolver paint carries one served assignment into the worker frame',
      (tester) async {
    final binding = AdmittedBundledPublicationFixture.build(
      includeOrderedCapture: false,
    ).binding;
    final edge = base64UrlEncode(utf8.encode(
      binding.exactArtifactGraph.rootEdgeToken.value,
    )).replaceAll('=', '');
    const outcomeCarrier = 'Y2Fub25pY2FsLXNlcnZlZC1hc3NpZ25tZW50';
    final served = CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment.checkout'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.checkout.1'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.checkout.1'),
      armId: ExperimentPublicArmIdV1('arm.treatment'),
      outcomeLinkCarrier: outcomeCarrier,
    );
    final bindingContext = ExactMeasurementPublicationContextRefV1(
      bindingReference: binding.reference,
      surfaceIdentity: binding.publishedSurfaceRevision.surfaceIdentity,
      surfaceRevisionId: binding.publishedSurfaceRevision.revisionId,
      artifactGraphHash: binding.exactArtifactGraph.canonicalDigest,
      measurementManifestHash:
          binding.completeMeasurementManifest.canonicalDigest,
    );
    final frames = <MeasurementFactFrameV1>[];
    late Directory support;
    late HttpServer server;
    await tester.runAsync(() async {
      support = await Directory.systemTemp.createTemp(
        'restage-host-assignment-frame-',
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.forEach((request) async {
          final body = await _readRequest(request);
          final ingest = _ingestFromRequestEnvelope(body);
          frames.add(ingest.factFrame);
          await _respondAccepted(request, ingest);
        }),
      );
    });
    addTearDown(
      () => tester.runAsync(() async {
        await support.delete(recursive: true);
      }),
    );
    addTearDown(
      () => tester.runAsync(() async {
        await server.close(force: true);
      }),
    );
    final readPort = _AcceptedBindingReadPort(binding);
    final lifecycle = ConstructionOwnerLifecycleProbe();
    final owner = MeasurementHostConstructionOwner.forTesting(
      profileReadPort: _ProfileReadPort(
        MeasurementHostConstructionProfile(
          publicationContext: bindingContext,
          endpoint:
              'http://${server.address.host}:${server.port}/sdk/v1/measurement',
          analyticsEnabled: true,
          policyStatus: MeasurementHostConstructionPolicyStatus.supported,
          measurementClassAdmitted: true,
          remainingSessionBudget: 1,
          deliveryAdapterAvailable: true,
          configurationFingerprint: 'host-assignment-frame.v1',
        ),
      ),
      pathResolver: _SupportPathResolver(support.path),
    );
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
      MeasurementHostSessionConstructionAuthority.forWorkerOwnedDeliveryTesting(
        constructionOwner: owner,
        hostedBindingReadPortLookup: () => readPort,
        nonceBytesSource: () => List<int>.filled(32, 7),
        lifecycleRegistrar: lifecycle,
      ),
    );
    addTearDown(() {
      restore();
      owner.debugRuntime?.debugKillWorkerForTesting();
    });
    final delivery = HostedArtifactFixture();
    final blob = Uint8List.fromList(
      encodeLibraryBlob(
        parseLibraryFile('''
import restage.core;
import restage.measurement;

widget Paywall = MeasurementSourcePresented(
  pointTokens: ["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"],
  carriers: ["mrv1.$edge.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"],
  child: Text(text: "Served assignment")
);
'''),
      ),
    );
    final document = SurfaceDocument(
      surfaceType: Surface.paywall,
      surfaceSlug: 'checkout',
      version: 42,
      minClient: 1,
      payload: BlobSurfacePayload(minClient: 1, blob: blob),
      publishedAt: DateTime.utc(2026, 9, 7),
    );
    final deliveryResponse = Completer<http.Response>();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_assignment_frame',
      environment: RestageEnvironment.production,
      baseUrl: 'https://surfaces.example.com',
      httpClient: delivery.client((_) => deliveryResponse.future),
    );
    Restage.configure(
      apiKey: 'rs_pk_assignment_frame',
      baseUrl: 'https://surfaces.example.com',
    );
    SurfaceAssignmentKeyProvider.current = () => 'assignment-frame';
    final global = <RestageEvent>[];
    final local = <RestageEvent>[];
    final subscription = Restage.events.listen(global.add);
    addTearDown(subscription.cancel);

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'checkout',
          resolver: resolver,
          onEvent: local.add,
        ),
      ),
    );
    await tester.pump();
    deliveryResponse.complete(
      http.Response(
        jsonEncode({
          ...delivery.describe(document),
          'assignment': served.toJson(),
        }),
        200,
        headers: {
          'Restage-Measurement-Publication-Binding-V1':
              base64UrlEncode(binding.reference.canonicalBytes)
                  .replaceAll('=', ''),
        },
      ),
    );
    await _pumpUntil(tester, () => owner.debugActiveSessionCount == 1);
    expect(owner.debugActiveSessionCount, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final event = global.whereType<PaywallViewed>().single;
    final localEvent = local.whereType<PaywallViewed>().single;
    final assignment = Restage.assignmentFor(
      'checkout',
      surfaceType: Surface.paywall,
    );
    expect(identical(event, localEvent), isTrue);
    expect(event.variantId, served.armId.value);
    expect(event.surfaceVersion, '42');
    expect(assignment?.variantId, served.armId.value);
    expect(
      jsonEncode(event.analyticsProperties),
      isNot(contains(outcomeCarrier)),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _pumpUntil(tester, () => frames.isNotEmpty);

    final frame = frames.single;
    expect(
      frame.rootPresentation.toJson()['kind'],
      'successfulFirstPaint',
    );
    expect(frame.experimentAssignment?.outcomeLinkCarrier, outcomeCarrier);
    expect(owner.debugWorkerSpawnCount, 1);
    owner.debugRuntime?.debugKillWorkerForTesting();
  });
}

final _bindingReference = MeasurementPublicationBindingReferenceV1(
  publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
    authorityId: MeasurementPublicationAuthorityId(
      'authority.measurement.configuration',
    ),
    externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
    candidateReference: MeasurementPublicationCandidateReferenceV1(
      candidateDigest: CanonicalDigest('a' * 64),
      selectedPublicationManifestDigest: CanonicalDigest('b' * 64),
      declaredArtifactBytesDigest: CanonicalDigest('c' * 64),
      assembledPublicationUploadDigest: CanonicalDigest('d' * 64),
      measurementPublicationDraftDigest: CanonicalDigest('e' * 64),
    ),
    immutablePublicationDigest: CanonicalDigest('f' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('c' * 64),
  ),
  bindingDigest: CanonicalDigest('1' * 64),
);

final class _CountingBindingReadPort
    implements MeasurementPublicationBindingReadPort {
  final references = <MeasurementPublicationBindingReferenceV1>[];

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  ) {
    references.add(bindingReference);
    return Future<MeasurementPublicationBindingReadResult>.value(
      const MeasurementPublicationBindingAbsent(),
    );
  }
}

final class _AcceptedBindingReadPort
    implements MeasurementPublicationBindingReadPort {
  _AcceptedBindingReadPort(this.binding);

  final MeasurementPublicationBindingV1 binding;

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  ) async =>
      MeasurementPublicationBindingReadAccepted(
        reference: binding.reference,
        binding: binding,
        registeredPublicationAttestation: RegisteredPublicationAttestationV1(
          bindingReference: binding.reference,
          attestationDigest: CanonicalDigest('9' * 64),
        ),
      );
}

final class _RecordingIngestAdapter implements MeasurementIngestRpcAdapter {
  final requests = <String>[];

  @override
  Future<MeasurementIngestRpcOutcome> submit(
    String canonicalRequestBase64,
  ) {
    requests.add(canonicalRequestBase64);
    return Future<MeasurementIngestRpcOutcome>.value(
      const MeasurementIngestRpcRejected(),
    );
  }
}

final class _ProfileReadPort
    implements MeasurementHostConstructionProfileReadPort {
  const _ProfileReadPort(this.profile);

  final MeasurementHostConstructionProfile profile;

  @override
  Future<MeasurementHostConstructionProfileReadResult> readExact(
    ExactMeasurementPublicationContextRefV1 publicationContext,
  ) async =>
      publicationContext == profile.publicationContext
          ? MeasurementHostConstructionProfileReadAccepted(profile)
          : const MeasurementHostConstructionProfileReadRejected(
              MeasurementHostConstructionPolicyStatus.stale,
            );
}

final class _SupportPathResolver
    implements MeasurementWorkerOwnedDeliveryPathResolver {
  const _SupportPathResolver(this.path);

  final String path;

  @override
  Future<String> resolveApplicationSupportPath() async => path;
}

Future<Uint8List> _readRequest(HttpRequest request) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

MeasurementIngestRequestV1 _ingestFromRequestEnvelope(Uint8List body) {
  final envelope = jsonDecode(utf8.decode(body, allowMalformed: false))
      as Map<String, Object?>;
  return MeasurementIngestRequestV1.fromBase64(
    envelope['canonicalRequestBase64']! as String,
  );
}

Future<void> _respondAccepted(
  HttpRequest request,
  MeasurementIngestRequestV1 ingest,
) async {
  final frame = ingest.factFrame;
  final receipt = MeasurementIngestReceiptV1.accepted(
    acceptedObservationCount: frame.facts.length,
    captureSessionNonce: frame.captureSessionNonce,
    factFrameSha256: ingest.factFrameSha256,
    isFinal: frame.isFinal,
    persistedAtMicros: 4100000,
    publicationBindingReference: frame.publishedContext.bindingReference,
    receiptId: 'receipt.host-assignment.0001',
    requestSha256: ingest.requestSha256,
    rootObservationUnitKey: 'root.host-assignment.0001',
    sequence: frame.sequence,
  );
  request.response
    ..statusCode = HttpStatus.ok
    ..write('{"receiptCanonicalBase64":"${receipt.canonicalReceiptBase64}"}');
  await request.response.close();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('Timed out waiting for hosted worker-owned delivery');
}
