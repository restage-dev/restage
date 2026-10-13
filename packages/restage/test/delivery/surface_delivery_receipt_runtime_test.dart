import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_uploader.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart' show SurfaceDocument;
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../flow/flow_test_support.dart';
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

/// One hosted delivery: a surface document served fresh, its content, and the
/// receipt route, all answered by the same mock client.
final class _Hosted {
  _Hosted(this.document) : delivery = HostedArtifactFixture() {
    body = delivery.deliveryBody(document);
  }

  final SurfaceDocument document;
  final HostedArtifactFixture delivery;
  late final Map<String, Object?> body;
  final List<http.Request> receiptPosts = <http.Request>[];
  int surfaceStatus = 200;

  late final http.Client client = delivery.client((request) async {
    switch (request.url.path) {
      case '/sdk/v1/surface':
        if (surfaceStatus != 200) {
          return http.Response(
            '',
            surfaceStatus,
            headers: {'retry-after': '5'},
          );
        }
        return http.Response(jsonEncode(body), 200);
      case kSurfaceDeliveryReceiptPath:
        receiptPosts.add(request);
        return http.Response('', 204);
      default:
        return http.Response('', 404);
    }
  });

  void configure({bool deliveryReceiptsEnabled = true}) {
    Restage.configure(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: deliveryReceiptsEnabled,
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
    SurfaceDeliveryReceiptUploader.instance.debugHttpClient = client;
  }

  List<Map<String, Object?>> receipts(int post) =>
      ((jsonDecode(receiptPosts[post].body) as Map)['receipts'] as List)
          .cast<Map<Object?, Object?>>()
          .map((receipt) => receipt.cast<String, Object?>())
          .toList();
}

/// Mounts the paywall and lets real I/O finish until [ready] finds a widget.
Future<void> _mount(WidgetTester tester, String id, Finder ready) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: id,
            errorBuilder: (_, __) => const Text('unavailable'),
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 100; attempt += 1) {
      await tester.pump();
      if (ready.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Pauses the app and lets the flush post over real I/O.
Future<void> _pause(WidgetTester tester, List<http.Request> posts) async {
  final before = posts.length;
  await tester.runAsync(() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (var attempt = 0; attempt < 100; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (posts.length > before) break;
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final supportDirectory =
        await Directory.systemTemp.createTemp('restage-receipts-');
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

  testWidgets('a fresh presentation posts one painted receipt on pause',
      (tester) async {
    final hosted = _Hosted(
      testBlobDocument(_blob('Hello'), surfaceSlug: 'pro', version: 12),
    );
    await tester.runAsync(() async => hosted.configure());

    await _mount(tester, 'pro', find.text('Hello'));
    expect(find.text('Hello'), findsOneWidget);
    await _unmount(tester);
    await _pause(tester, hosted.receiptPosts);

    expect(hosted.receiptPosts, hasLength(1));
    final post = hosted.receiptPosts.single;
    expect(post.headers['Authorization'], 'Bearer $_apiKey');
    final receipt = hosted.receipts(0).single;
    expect(receipt['surfaceType'], 'paywall');
    expect(receipt['surfaceSlug'], 'pro');
    expect(receipt['publishedVersion'], 12);
    expect(receipt['source'], 'fresh');
    expect(receipt['reason'], 'none');
    expect(receipt['outcome'], 'painted');
    expect(receipt['latencyBucket'], isNot('unknown'));
    expect(receipt['platform'], 'android');
    expect(receipt['appBuild'], 412);
    expect(receipt['routeId'], '');
    expect(receipt['count'], 1);
  });

  testWidgets('a throttled service with a held copy reports holdLastGood',
      (tester) async {
    final hosted = _Hosted(
      testBlobDocument(_blob('Hello'), surfaceSlug: 'pro', version: 12),
    );
    await tester.runAsync(() async => hosted.configure());

    await _mount(tester, 'pro', find.text('Hello'));
    await _unmount(tester);
    await _pause(tester, hosted.receiptPosts);
    hosted.surfaceStatus = 429;
    await _mount(tester, 'pro', find.text('Hello'));
    expect(find.text('Hello'), findsOneWidget);
    await _unmount(tester);
    await _pause(tester, hosted.receiptPosts);

    expect(hosted.receiptPosts, hasLength(2));
    final receipt = hosted.receipts(1).single;
    expect(receipt['source'], 'holdLastGood');
    expect(receipt['reason'], 'throttled');
    expect(receipt['outcome'], 'painted');
    expect(receipt['publishedVersion'], 12);
  });

  testWidgets('content that does not decode reports a render failure',
      (tester) async {
    final hosted = _Hosted(
      testBlobDocument(const [1, 2, 3], surfaceSlug: 'broken', version: 3),
    );
    await tester.runAsync(() async => hosted.configure());

    await _mount(tester, 'broken', find.text('unavailable'));
    expect(find.text('unavailable'), findsOneWidget);
    await _unmount(tester);
    await _pause(tester, hosted.receiptPosts);

    expect(hosted.receiptPosts, hasLength(1));
    final receipt = hosted.receipts(0).single;
    expect(receipt['source'], 'fresh');
    expect(receipt['outcome'], 'renderFailed');
    expect(receipt['reason'], 'decodeFailed');
    expect(receipt['latencyBucket'], 'unknown');
  });

  testWidgets('a compiled flow shown from its original screens is painted',
      (tester) async {
    final batch = SurfaceDeliveryReceiptBatch.instance
      ..enabled = true
      ..deviceSource = (() async => (platform: 'android', appBuild: 412));
    batch.open(
      surfaceType: nativeWelcomeFlowRef.surface,
      surfaceSlug: nativeWelcomeFlowRef.id,
      publishedVersion: 0,
      source: SurfaceResolutionSource.bundled,
      reason: SurfaceDeliveryReceiptReason.offline,
      routeId: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativeWelcomeFlowSurface(
          resolver:
              StaticFlowResolver(nativeWelcomeFlowRef.compiled!.resolve()),
          actions: NativeWelcomeFlowActions(permission: (_, __) async => true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NativeWelcome), findsOneWidget);
    await _unmount(tester);

    final receipt = (await batch.drain()).counts.keys.single;
    expect(receipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
    expect(receipt.source, SurfaceResolutionSource.bundled);
    expect(receipt.surfaceType, Surface.onboarding);
  });

  testWidgets('receipts can be turned off', (tester) async {
    final hosted = _Hosted(
      testBlobDocument(_blob('Hello'), surfaceSlug: 'pro', version: 12),
    );
    await tester.runAsync(
      () async => hosted.configure(deliveryReceiptsEnabled: false),
    );

    await _mount(tester, 'pro', find.text('Hello'));
    expect(find.text('Hello'), findsOneWidget);
    await _unmount(tester);
    await _pause(tester, hosted.receiptPosts);

    expect(hosted.receiptPosts, isEmpty);
  });
}
