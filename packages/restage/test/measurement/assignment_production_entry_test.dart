import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/resolver/surface_assignment_built_ins.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../surface_screen/surface_screen_test_support.dart';

void main() {
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

  test('assignment API level matches the compiled SDK major version', () {
    final pubspec = [
      File('pubspec.yaml'),
      File('packages/restage/pubspec.yaml')
    ].firstWhere((file) =>
        file.existsSync() &&
        file.readAsStringSync().startsWith('name: restage\n'));
    final major = RegExp(r'^version: ([0-9]+)\.', multiLine: true)
        .firstMatch(pubspec.readAsStringSync())!
        .group(1)!;
    expect(assignmentSdkApiLevel, int.parse(major));
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
        {'appBuildOrdinal': 42, 'platform': 'android', 'sdkApiLevel': 2});
    expect(surfaceRequests.single.containsKey('assignmentCanonicalBase64'),
        isFalse);

    final cached =
        await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(measurementExperimentAssignmentFor(cached), assignment);
    expect(surfaceRequests, hasLength(1));

    configure();
    await Restage.defaultSurfaceScreenResolver.resolve(fixture.ref);
    expect(registrationRequests[1]['registrationNonce'],
        registrationRequests[0]['registrationNonce']);
    expect(registrationRequests[1]['credentialHandle'], 'credential.screen.1');
    expect(surfaceRequests[1]['assignmentCanonicalBase64'], isNotNull);
    expect(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
            surfaceRequests[1]['assignmentCanonicalBase64'] as String)))),
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
      expect(seen.containsKey('sdkBuiltInsCanonicalBase64'), isFalse,
          reason: buildNumber);
    }
  });

  test('collection opt-outs send no credential or assignment carriers',
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
        'sdkBuiltInsCanonicalBase64'
      ]) {
        expect(requests.single.containsKey(key), isFalse,
            reason: '$disabled $key');
      }
    }
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
