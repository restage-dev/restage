@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'browser configure keeps hosted requests ordinary without delivery support',
      () async {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    PackageInfo.setMockInitialValues(
        appName: 'Web',
        packageName: 'example.web',
        version: '1.0.0',
        buildNumber: '42',
        buildSignature: '');
    final requests = <http.Request>[];
    Restage.configure(
        apiKey: 'rs_pk_web', baseUrl: 'https://surfaces.example.com');
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_web',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 404);
      }),
    );
    try {
      expect(kIsWeb, isTrue);
      await Restage.activeRpcClient!
          .fetchSurface(surfaceType: 'message', surfaceSlug: 'welcome');
      expect(requests.map((r) => r.url.path), ['/sdk/v1/surface']);
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      for (final key in [
        'assignmentKey',
        'sdkBuiltInsCanonicalBase64',
        'assignmentCanonicalBase64'
      ]) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
      expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
      expect(await SurfaceCanonicalCarrierProvider.builtIns(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getKeys().where(
              (key) => key.startsWith('restage.assignmentRegistration.')),
          isEmpty);
    } finally {
      Restage.debugReset();
    }
  });
}
