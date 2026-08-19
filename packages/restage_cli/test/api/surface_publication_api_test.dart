import 'dart:typed_data';

import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('sends one canonical typed upload operation', () async {
    final payload = BlobSurfacePayload(
      minClient: 1,
      blob: Uint8List.fromList(const <int>[1, 2, 3]),
    );
    final publication = SurfacePublicationV1(
      surface: Surface.paywall,
      slug: 'checkout',
      sourceKind: SurfaceSourceKind.paywall,
      payloadKind: SurfacePayloadKind.blob,
      payloadContentHash: payload.contentHash,
    );
    final request = SurfacePublicationUploadRequestV1(
      publication: publication,
      payload: payload.canonicalBytes,
    );
    final api = _RecordingApi(<String, dynamic>{
      'family': {
        '__className__': 'SurfaceContractFamilyReference',
        'surfaceType': 'paywall',
        'surfaceSlug': 'checkout',
        'sourceKind': 'paywall',
      },
      'storedPublishedRevision': 5,
      'activePublishedRevision': 4,
      'identityFrozen': false,
    });

    final result = await SurfacePublicationApi(api).publish(
      project: 'demo',
      app: 'mobile',
      environment: 'dev',
      request: request,
      environmentTargetId: 11,
      runtimePlane: RuntimePlane.sandbox,
      organizationId: 7,
    );

    expect(api.endpointName, 'surface');
    expect(api.methodName, surfacePublicationUploadMethod);
    expect(api.args!['projectSlug'], 'demo');
    expect(api.args!['appSlug'], 'mobile');
    expect(api.args!['environmentSlug'], 'dev');
    expect(api.args!['environmentTargetId'], 11);
    expect(api.args!['runtimePlane'], 'sandbox');
    expect(api.args!['organizationId'], 7);
    final upload = api.args!['upload'] as Map<String, dynamic>;
    expect(upload['__className__'], 'SurfacePublicationUpload');
    final decoded = SurfacePublicationUploadRequestV1Codec.decodeJson(
      upload['canonicalJson'] as String,
    );
    expect(decoded.publication.surface, publication.surface);
    expect(decoded.publication.slug, publication.slug);
    expect(decoded.publication.sourceKind, publication.sourceKind);
    expect(decoded.publication.payloadKind, publication.payloadKind);
    expect(
      decoded.publication.payloadContentHash,
      publication.payloadContentHash,
    );
    expect(result.storedRevision, 5);
    expect(result.activeRevision, 4);
    expect(
      result.stateDescription,
      'stored revision 5; active revision 4; identity frozen: false.',
    );
    expect(result.family.familyAddress, 'non-versioned paywall');
    expect(result.identityFrozen, isFalse);
  });

  test('decodes the generated stored-revision response form', () async {
    final api = _RecordingApi(<String, dynamic>{
      'family': {
        '__className__': 'SurfaceContractFamilyReference',
        'surfaceType': 'paywall',
        'surfaceSlug': 'checkout',
        'sourceKind': 'paywall',
      },
      'storedPublishedRevision': 8,
      'identityFrozen': true,
    });
    final payload = BlobSurfacePayload(
      minClient: 1,
      blob: Uint8List.fromList(const <int>[4, 5, 6]),
    );
    final request = SurfacePublicationUploadRequestV1(
      publication: SurfacePublicationV1(
        surface: Surface.paywall,
        slug: 'checkout',
        sourceKind: SurfaceSourceKind.paywall,
        payloadKind: SurfacePayloadKind.blob,
        payloadContentHash: payload.contentHash,
      ),
      payload: payload.canonicalBytes,
    );

    final result = await SurfacePublicationApi(api).publish(
      project: 'demo',
      app: 'mobile',
      environment: 'dev',
      request: request,
    );

    expect(result.storedRevision, 8);
    expect(result.activeRevision, isNull);
    expect(result.identityFrozen, isTrue);
    expect(
      result.stateDescription,
      'stored revision 8; active revision none; identity frozen: true.',
    );
  });

  test('rejects a response missing generated family state', () {
    expect(
      () => SurfacePublicationUploadResult.fromWire({
        'storedPublishedRevision': 8,
        'identityFrozen': false,
      }),
      throwsFormatException,
    );
  });
}

final class _RecordingApi implements RestageApi {
  _RecordingApi(this.response);

  final dynamic response;
  String? endpointName;
  String? methodName;
  Map<String, dynamic>? args;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    this.endpointName = endpointName;
    this.methodName = methodName;
    this.args = args;
    return response;
  }

  @override
  void close() {}
}
