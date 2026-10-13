import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_uploader.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/hosted_artifact_delivery.dart';

const String _baseUrl = 'https://example.com';
const String _apiKey = 'rs_pk_test';

Uint8List _blob(String text) {
  final source = '''
    import restage.core;
    widget Paywall = Text(text: "$text");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final supportDirectory =
        await Directory.systemTemp.createTemp('restage-receipt-timer-');
    addTearDown(() async {
      try {
        await Restage.debugResetAndWait();
      } finally {
        messenger.setMockMethodCallHandler(supportChannel, null);
        await supportDirectory.delete(recursive: true);
      }
    });
    messenger.setMockMethodCallHandler(
      supportChannel,
      (call) async => call.method == 'getApplicationSupportDirectory'
          ? supportDirectory.path
          : null,
    );
    await Restage.debugResetAndWait();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugSetOsVersion(null);
    PackageInfo.setMockInitialValues(
      appName: 'Example',
      packageName: 'example.app',
      version: '1.0.0',
      buildNumber: '412',
      buildSignature: '',
    );
  });

  // The runtime is reset only in tearDown, after the framework's pending-timer
  // check, so a flush timer left behind by the mount would fail this test.
  testWidgets('a resolved and unmounted surface leaves no timer behind',
      (tester) async {
    final delivery = HostedArtifactFixture();
    final body = delivery.deliveryBody(
      testBlobDocument(_blob('Hello'), surfaceSlug: 'pro', version: 12),
    );
    final client = delivery.client((request) async {
      if (request.url.path == '/sdk/v1/surface') {
        return http.Response(jsonEncode(body), 200);
      }
      return http.Response('', 404);
    });
    await tester.runAsync(() async {
      Restage.configure(
        apiKey: _apiKey,
        baseUrl: _baseUrl,
        analyticsEnabled: false,
        measurementEnabled: false,
        resolver: RestageVariantResolver(
          apiKey: _apiKey,
          environment: RestageEnvironment.production,
          baseUrl: _baseUrl,
          httpClient: client,
        ),
      );
      Restage.debugRestageRpcClient = RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: client,
      );
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RestagePaywall(id: 'pro'))),
      );
      for (var attempt = 0; attempt < 100; attempt += 1) {
        await tester.pump();
        if (find.text('Hello').evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(SurfaceDeliveryReceiptUploader.instance.hasPeriodicTimer, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(SurfaceDeliveryReceiptUploader.instance.hasPeriodicTimer, isFalse);
    expect(SurfaceDeliveryReceiptBatch.instance.openCount, 0);
  });
}
