import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_ingest_transport.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

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
