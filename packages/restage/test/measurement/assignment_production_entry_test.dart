import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/restage_rpc_client/uuid_v4.dart';
import 'package:restage/src/resolver/surface_assignment_built_ins.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../surface_screen/surface_screen_test_support.dart';
import '../support/supported_policy_revisions_body.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';

void main() {
  setUp(debugResetAppBuildOrdinal);
  tearDown(debugResetAppBuildOrdinal);
  TestWidgetsFlutterBinding.ensureInitialized();
  const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory supportDirectory;
  setUp(() async {
    supportDirectory =
        await Directory.systemTemp.createTemp('restage-configure-');
    messenger.setMockMethodCallHandler(
        supportChannel,
        (call) async => call.method == 'getApplicationSupportDirectory'
            ? supportDirectory.path
            : null);
    await Restage.debugResetAndWait();
    SharedPreferences.setMockInitialValues({});
    debugSetOsVersion(null);
    PackageInfo.setMockInitialValues(
        appName: 'Example',
        packageName: 'example.app',
        version: '1.0.0',
        buildNumber: '42',
        buildSignature: '');
  });
  tearDown(() async {
    try {
      await Restage.debugResetAndWait();
    } finally {
      messenger.setMockMethodCallHandler(supportChannel, null);
      await supportDirectory.delete(recursive: true);
    }
  });

  test('the compiled assignment API level is 3', () {
    expect(assignmentSdkApiLevel, 3);
  });

  test(
      'configure registers and retains assignment through hosted screen resolution',
      () async {
    final fixture = stringScreenFixture();
    final registrationRequests = <Map<String, dynamic>>[];
    final surfaceRequests = <Map<String, dynamic>>[];
    final assignment = CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment.message'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.message'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.message'),
      armId: ExperimentPublicArmIdV1('arm.treatment'),
      outcomeLinkCarrier: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    final client = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_assignment',
      httpClient: fixture.hostedDelivery.client((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/sdk/v1/measurement-assignment-credential') {
          registrationRequests.add(body);
          final prefs = await SharedPreferences.getInstance();
          expect(
              prefs.getKeys().where(
                  (key) => key.startsWith('restage.assignmentRegistration.')),
              isNotEmpty);
          expect(
              body.keys,
              everyElement(isIn([
                'registrationNonce',
                'registrationCreatedAtMicros',
                'credentialHandle'
              ])));
          expect(
              base64Url.decode(
                  base64Url.normalize(body['registrationNonce'] as String)),
              hasLength(32));
          return http.Response(
              jsonEncode({
                'credentialHandle': body['credentialHandle'] ??
                    'credential.screen.${registrationRequests.length}',
                'expiresAtMicros': 4102444800000000,
              }),
              200);
        }
        surfaceRequests.add(body);
        final descriptor = jsonDecode(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
          fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8),
        )) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({...descriptor, 'assignment': assignment.toJson()}),
            200);
      }),
    );
    void configure() {
      Restage.configure(
          apiKey: 'rs_pk_assignment', baseUrl: 'https://surfaces.example.com');
      Restage.debugRestageRpcClient = client;
    }

    configure();
    final resolved =
        await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(resolved.origin, SurfaceScreenOrigin.hosted);
    expect(measurementExperimentAssignmentFor(resolved), assignment);
    expect(registrationRequests, hasLength(1));
    expect(surfaceRequests.single['assignmentKey'], 'credential.screen.1');
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('appBuildOrdinal', 42),
    );
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('platform', 'android'),
    );
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('sdkApiLevel', 3),
    );
    expect(surfaceRequests.single.containsKey('assignmentCanonicalBase64'),
        isFalse);

    final resolvedAgain =
        await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(measurementExperimentAssignmentFor(resolvedAgain), assignment);
    expect(surfaceRequests, hasLength(2));

    configure();
    await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(registrationRequests[1]['registrationNonce'],
        registrationRequests[0]['registrationNonce']);
    expect(registrationRequests[1]['credentialHandle'], 'credential.screen.1');
    expect(surfaceRequests[2]['assignmentCanonicalBase64'], isNotNull);
    expect(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
            surfaceRequests[2]['assignmentCanonicalBase64'] as String)))),
        assignment.toJson());

    Restage.reset();
    await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(registrationRequests.last['registrationNonce'],
        isNot(registrationRequests.first['registrationNonce']));
    expect(registrationRequests.last.containsKey('credentialHandle'), isFalse);
    expect(
        surfaceRequests.last.containsKey('assignmentCanonicalBase64'), isFalse);
  });
  test(
      'refused registration reuses durable nonce and leaves ordinary delivery unassigned',
      () async {
    final fixture = stringScreenFixture();
    final registrations = <Map<String, dynamic>>[];
    final requests = <Map<String, dynamic>>[];
    final client = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_assignment',
      httpClient: fixture.hostedDelivery.client((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('assignment-credential')) {
          registrations.add(body);
          return http.Response('{}', 409);
        }
        requests.add(body);
        return http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8),
            ),
            200);
      }),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      Restage.configure(
          apiKey: 'rs_pk_assignment', baseUrl: 'https://surfaces.example.com');
      Restage.debugRestageRpcClient = client;
      final resolved =
          await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
      expect(measurementExperimentAssignmentFor(resolved), isNull);
    }
    expect(registrations, hasLength(2));
    expect(registrations.first, registrations.last);
    for (final request in requests) {
      expect(request.containsKey('assignmentKey'), isFalse);
      expect(request.containsKey('assignmentCanonicalBase64'), isFalse);
    }
  });

  test(
      'unavailable build metadata never becomes a fabricated build observation',
      () async {
    final fixture = stringScreenFixture();
    for (final buildNumber in ['', '1.2.3', '-1', '9007199254740992']) {
      PackageInfo.setMockInitialValues(
          appName: 'Example',
          packageName: 'example.app',
          version: '1.0.0',
          buildNumber: buildNumber,
          buildSignature: '');
      late Map<String, dynamic> seen;
      Restage.configure(
          apiKey: 'rs_pk_metadata', baseUrl: 'https://surfaces.example.com');
      Restage.debugRestageRpcClient = RestageRpcClient(
        baseUrl: 'https://surfaces.example.com',
        apiKey: 'rs_pk_metadata',
        httpClient: fixture.hostedDelivery.client((request) async {
          if (request.url.path.endsWith('assignment-credential')) {
            return http.Response('{}', 503);
          }
          seen = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
              SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
                fixture.delivery(
                    hostedBlob: fixture.blob, publishedRevision: 8),
              ),
              200);
        }),
      );
      await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
      final carrier = seen['sdkBuiltInsCanonicalBase64'] as String;
      final observations = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(carrier)))) as Map;
      expect(observations.containsKey('appBuildOrdinal'), isFalse,
          reason: buildNumber);
      expect(observations['platform'], 'android', reason: buildNumber);
      expect(observations['sdkApiLevel'], 3, reason: buildNumber);
    }
  });

  test(
      'collection opt-outs send observations but no credential or assignment carriers',
      () async {
    final fixture = stringScreenFixture();
    for (final disabled in ['analytics', 'measurement']) {
      final requests = <Map<String, dynamic>>[];
      Restage.configure(
        apiKey: 'rs_pk_disabled',
        baseUrl: 'https://surfaces.example.com',
        analyticsEnabled: disabled != 'analytics',
        measurementEnabled: disabled != 'measurement',
      );
      Restage.debugRestageRpcClient = RestageRpcClient(
        baseUrl: 'https://surfaces.example.com',
        apiKey: 'rs_pk_disabled',
        httpClient: fixture.hostedDelivery.client((request) async {
          expect(request.url.path, '/sdk/v1/surface');
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
              SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
                fixture.delivery(
                    hostedBlob: fixture.blob, publishedRevision: 8),
              ),
              200);
        }),
      );
      final resolved =
          await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
      expect(measurementExperimentAssignmentFor(resolved), isNull);
      expect(requests, hasLength(1));
      for (final key in [
        'assignmentKey',
        'assignmentCanonicalBase64',
      ]) {
        expect(requests.single.containsKey(key), isFalse,
            reason: '$disabled $key');
      }
      expect(requests.single.containsKey('sdkBuiltInsCanonicalBase64'), isTrue,
          reason: '$disabled observations');
    }
  });

  test(
      'measurement off still reports observations without an assignment credential',
      () async {
    final fixture = stringScreenFixture();
    final surfaceRequests = <Map<String, dynamic>>[];
    Restage.configure(
      apiKey: 'rs_pk_observations',
      baseUrl: 'https://surfaces.example.com',
      measurementEnabled: false,
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_observations',
      httpClient: fixture.hostedDelivery.client((request) async {
        expect(request.url.path, '/sdk/v1/surface');
        surfaceRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8),
            ),
            200);
      }),
    );
    await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(surfaceRequests, hasLength(1));
    expect(surfaceRequests.single.containsKey('sdkBuiltInsCanonicalBase64'),
        isTrue);
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('appBuildOrdinal', 42),
    );
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('platform', 'android'),
    );
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('sdkApiLevel', 3),
    );
    expect(surfaceRequests.single.containsKey('assignmentKey'), isFalse);
  });

  test(
      'analytics off still reports observations without an assignment credential',
      () async {
    final fixture = stringScreenFixture();
    final surfaceRequests = <Map<String, dynamic>>[];
    Restage.configure(
      apiKey: 'rs_pk_observations',
      baseUrl: 'https://surfaces.example.com',
      analyticsEnabled: false,
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_observations',
      httpClient: fixture.hostedDelivery.client((request) async {
        expect(request.url.path, '/sdk/v1/surface');
        surfaceRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8),
            ),
            200);
      }),
    );
    await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(surfaceRequests, hasLength(1));
    expect(surfaceRequests.single.containsKey('sdkBuiltInsCanonicalBase64'),
        isTrue);
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('appBuildOrdinal', 42),
    );
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('platform', 'android'),
    );
    expect(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          surfaceRequests.single['sdkBuiltInsCanonicalBase64'] as String)))),
      containsPair('sdkApiLevel', 3),
    );
    expect(surfaceRequests.single.containsKey('assignmentKey'), isFalse);
  });

  Future<void> captureGeneralAnalyticsRequest(
    List<Map<String, dynamic>> surfaceRequests, {
    bool analyticsEnabled = true,
    bool measurementEnabled = true,
  }) async {
    final fixture = stringScreenFixture();
    Restage.configure(
      apiKey: 'rs_pk_analytics',
      baseUrl: 'https://surfaces.example.com',
      analyticsEnabled: analyticsEnabled,
      measurementEnabled: measurementEnabled,
    );
    final client = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_analytics',
      httpClient: fixture.hostedDelivery.client((request) async {
        if (request.url.path.endsWith('assignment-credential')) {
          return http.Response('{}', 503);
        }
        expect(request.url.path, '/sdk/v1/surface');
        surfaceRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 404);
      }),
    );
    Restage.debugRestageRpcClient = client;
    await client.fetchSurface(surfaceType: 'paywall', surfaceSlug: 'example');
  }

  test('the general active request carries the policy revision support report',
      () async {
    final surfaceRequests = <Map<String, dynamic>>[];
    await captureGeneralAnalyticsRequest(surfaceRequests);
    expect(surfaceRequests, hasLength(1));
    withoutSupportedPolicyRevisions(surfaceRequests.single);
  });

  test('the typed screen request carries the policy revision support report',
      () async {
    final fixture = stringScreenFixture();
    final surfaceRequests = <Map<String, dynamic>>[];
    Restage.configure(
      apiKey: 'rs_pk_support',
      baseUrl: 'https://surfaces.example.com',
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_support',
      httpClient: fixture.hostedDelivery.client((request) async {
        if (request.url.path.endsWith('assignment-credential')) {
          return http.Response('{}', 503);
        }
        expect(request.url.path, '/sdk/v1/surface');
        surfaceRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
            fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8),
          ),
          200,
        );
      }),
    );
    final resolved =
        await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(resolved.origin, SurfaceScreenOrigin.hosted);
    expect(surfaceRequests, hasLength(1));
    withoutSupportedPolicyRevisions(surfaceRequests.single);
  });

  test('policy revision support is reported when measurement is disabled',
      () async {
    final surfaceRequests = <Map<String, dynamic>>[];
    await captureGeneralAnalyticsRequest(surfaceRequests,
        measurementEnabled: false);
    expect(surfaceRequests, hasLength(1));
    withoutSupportedPolicyRevisions(surfaceRequests.single);
  });

  test('analytics disabled mints nothing and sends nothing', () async {
    final surfaceRequests = <Map<String, dynamic>>[];
    await captureGeneralAnalyticsRequest(surfaceRequests,
        analyticsEnabled: false);
    expect(surfaceRequests, hasLength(1));
    expect(surfaceRequests.single.containsKey('analyticsAnonymousId'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('restage.analytics.anonymous_id'), isFalse);
  });

  test('analytics on with measurement off still sends its identifier',
      () async {
    final surfaceRequests = <Map<String, dynamic>>[];
    await captureGeneralAnalyticsRequest(surfaceRequests,
        measurementEnabled: false);
    expect(surfaceRequests, hasLength(1));
    expect(
        isValidUuidV4(surfaceRequests.single['analyticsAnonymousId'] as String),
        isTrue);
  });

  test('reconfigure disabling analytics stops sending its identifier',
      () async {
    final surfaceRequests = <Map<String, dynamic>>[];
    await captureGeneralAnalyticsRequest(surfaceRequests);
    expect(surfaceRequests, hasLength(1));
    expect(
        isValidUuidV4(surfaceRequests.first['analyticsAnonymousId'] as String),
        isTrue);
    await captureGeneralAnalyticsRequest(surfaceRequests,
        analyticsEnabled: false);
    expect(surfaceRequests, hasLength(2));
    expect(surfaceRequests.last.containsKey('analyticsAnonymousId'), isFalse);
  });

  test('typed screen resolution sends the analytics identifier', () async {
    final fixture = stringScreenFixture();
    final surfaceRequests = <Map<String, dynamic>>[];
    Restage.configure(
      apiKey: 'rs_pk_analytics',
      baseUrl: 'https://surfaces.example.com',
      analyticsEnabled: true,
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_analytics',
      httpClient: fixture.hostedDelivery.client((request) async {
        if (request.url.path.endsWith('assignment-credential')) {
          return http.Response('{}', 503);
        }
        expect(request.url.path, '/sdk/v1/surface');
        surfaceRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8),
            ),
            200);
      }),
    );
    final resolved =
        await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(resolved.origin, SurfaceScreenOrigin.hosted);
    expect(surfaceRequests, hasLength(1));
    expect(
        isValidUuidV4(surfaceRequests.single['analyticsAnonymousId'] as String),
        isTrue);
  });

  test('no base URL reports no observations', () async {
    Restage.configure(apiKey: 'rs_pk_no_base_url');
    expect(await SurfaceCanonicalCarrierProvider.builtIns(), isNull);
  });

  test('bundled-only setup creates no enrollment transport or carriers',
      () async {
    Restage.configure(apiKey: 'rs_pk_bundled');
    expect(Restage.activeRpcClient, isNull);
    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
    expect(await SurfaceCanonicalCarrierProvider.builtIns(), isNull);
    expect(await SurfaceCanonicalCarrierProvider.heldAssignment(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs
            .getKeys()
            .where((key) => key.startsWith('restage.assignmentRegistration.')),
        isEmpty);
  });
}
