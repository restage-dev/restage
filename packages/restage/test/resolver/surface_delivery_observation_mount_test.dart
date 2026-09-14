import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart';
import '../support/hosted_artifact_delivery.dart';
import '../surface_screen/surface_screen_test_support.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_abc123';
const _installed = RestageBuiltInCatalogCapabilities.currentVersion;
const _flowRef = OnboardingFlowRef<Map<String, Object?>>(
  id: 'first_run',
  version: 1,
  minClient: _installed + 2,
  surface: Surface.onboarding,
  decodeResult: _decodeMapResult,
);
final _delivery = HostedArtifactFixture();

String _carrier(String platform, {int build = 42}) =>
    SurfaceDeliveryObservations(
      presentationCountry: 'SE',
      platform: platform,
      appBuildOrdinal: build,
      deviceClass: 'phone',
      sdkApiLevel: 2,
    ).canonicalBuiltInsBase64()!;

void _setBuild(int build) => PackageInfo.setMockInitialValues(
      appName: 'Example',
      packageName: 'example.app',
      version: '1.0.0',
      buildNumber: '$build',
      buildSignature: '',
    );

/// Runs [body] with the platform pinned, resetting inside the test body so
/// the binding's foundation-vars-unset invariant never trips.
Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  setUp(debugResetAppBuildOrdinal);
  tearDown(debugResetAppBuildOrdinal);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    _setBuild(42);
  });
  tearDown(SurfaceCanonicalCarrierProvider.clear);
  tearDown(() {
    Restage.debugReset();
  });

  testWidgets(
      'hosted flow requests use the mount observations without ambient reads',
      (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      var ambientReads = 0;
      SurfaceDeliveryObservationCell? cell;
      SurfaceCanonicalCarrierProvider.installBuiltIns(() async {
        ambientReads += 1;
        return _carrier('ambient');
      });
      final bytes = screenBlob('Welcome', 'next');
      final document = _screenDocument(screenBytes: bytes);
      final server = _ControlledServer(onRequest: () {
        cell ??= currentSurfaceDeliveryObservationCell();
      });
      final resolver = ServerFlowResolver(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        active: true,
        bundle: _bundleFor(document, bytes),
        httpClient: server.client,
      );
      await tester.pumpWidget(_host(resolver));
      await _waitFor(() => server.requests.isNotEmpty);
      server.respondJson(
          0, _contentBody(_envelope(document, {'welcome': bytes})));
      await tester.pumpAndSettle();
      expect(server.requests, hasLength(1));
      expect(cell, isNotNull);
      expect(_requestBody(server.requests.single)['sdkBuiltInsCanonicalBase64'],
          cell!.valueIfRead!.canonicalBuiltInsBase64());
      expect(_requestBody(server.requests.single)['sdkBuiltInsCanonicalBase64'],
          isNot(_carrier('ambient')));
      expect(ambientReads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets(
      'typed screen requests use the mount observations without ambient reads',
      (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      var ambientReads = 0;
      SurfaceDeliveryObservationCell? cell;
      SurfaceCanonicalCarrierProvider.installBuiltIns(() async {
        ambientReads += 1;
        return _carrier('ambient');
      });
      final fixture = stringScreenFixture();
      final surfaceRequests = <Map<String, dynamic>>[];
      final client = RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          cell ??= currentSurfaceDeliveryObservationCell();
          surfaceRequests.add((jsonDecode(request.body) as Map).cast());
          return http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(fixture
                .delivery(hostedBlob: fixture.blob, publishedRevision: 8)),
            200,
          );
        }),
      );
      await tester.pumpWidget(MaterialApp(
          home: RestageScreen(
        screen: fixture.ref,
        resolver: RestageScreenResolver(
          apiKey: _apiKey,
          environment: RestageEnvironment.values.first,
          rpcClientProvider: () => client,
        ),
        unavailable: SurfaceScreenUnavailablePolicy.fallback(
          builder: (_, error) => const SizedBox.shrink(),
        ),
      )));
      await tester.pumpAndSettle();
      expect(surfaceRequests, hasLength(1));
      expect(cell, isNotNull);
      expect(surfaceRequests.single['sdkBuiltInsCanonicalBase64'],
          cell!.valueIfRead!.canonicalBuiltInsBase64());
      expect(surfaceRequests.single['sdkBuiltInsCanonicalBase64'],
          isNot(_carrier('ambient')));
      expect(ambientReads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a paywall blob mount observes through its presentation cell',
      (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      var ambientReads = 0;
      SurfaceDeliveryObservationCell? cell;
      SurfaceCanonicalCarrierProvider.installBuiltIns(() async {
        ambientReads += 1;
        return _carrier('ambient');
      });
      SurfaceAssignmentKeyProvider.install(
        key: () => 'actor-a',
        identityGeneration: () => 0,
      );
      final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      widget Paywall = Text(text: "Hosted paywall");
    ''')));
      final envelope = SurfaceDocumentCodec.encode(SurfaceDocument(
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 1,
        minClient: _installed,
        payload: BlobSurfacePayload(minClient: _installed, blob: bytes),
        publishedAt: DateTime.utc(2026),
      ));
      final server = _ControlledServer(onRequest: () {
        cell ??= currentSurfaceDeliveryObservationCell();
      });
      final resolver = RestageVariantResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.sandbox,
        baseUrl: _baseUrl,
        httpClient: server.client,
        assetFallback: AssetVariantResolver(bundle: _TestBundle({})),
      );
      await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
      ));
      await _waitFor(() => server.requests.isNotEmpty);
      server.respondJson(0, _contentBody(envelope));
      await tester.pumpAndSettle();
      expect(find.text('Hosted paywall'), findsOneWidget);
      expect(server.requests, hasLength(1));
      expect(cell, isNotNull);
      expect(_requestBody(server.requests.single)['sdkBuiltInsCanonicalBase64'],
          cell!.valueIfRead!.canonicalBuiltInsBase64());
      expect(_requestBody(server.requests.single)['sdkBuiltInsCanonicalBase64'],
          isNot(_carrier('ambient')));
      expect(ambientReads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a paywall flow mount observes through its presentation cell',
      (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      var ambientReads = 0;
      SurfaceDeliveryObservationCell? cell;
      SurfaceCanonicalCarrierProvider.installBuiltIns(() async {
        ambientReads += 1;
        return _carrier('ambient');
      });
      SurfaceAssignmentKeyProvider.install(
        key: () => 'actor-a',
        identityGeneration: () => 0,
      );
      final bytes = screenBlob('Paywall flow', 'next');
      final document = _screenDocument(screenBytes: bytes, flow: 'pro_upgrade');
      final bundle = _TestBundle({
        'assets/paywalls/pro_upgrade.flow.json':
            Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
        'assets/paywalls/screens/welcome.rfw': bytes,
      });
      final server = _ControlledServer(onRequest: () {
        cell ??= currentSurfaceDeliveryObservationCell();
      });
      final resolver = RestageVariantResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.sandbox,
        baseUrl: _baseUrl,
        httpClient: server.client,
        assetFallback: AssetVariantResolver(bundle: bundle),
      );
      await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
      ));
      await _waitFor(() => server.requests.isNotEmpty);
      server.respondNotFound(0);
      await tester.pumpAndSettle();
      expect(find.text('Paywall flow'), findsOneWidget);
      expect(server.requests, hasLength(1));
      expect(cell, isNotNull);
      expect(_requestBody(server.requests.single)['sdkBuiltInsCanonicalBase64'],
          cell!.valueIfRead!.canonicalBuiltInsBase64());
      expect(_requestBody(server.requests.single)['sdkBuiltInsCanonicalBase64'],
          isNot(_carrier('ambient')));
      expect(ambientReads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets(
      'a remounted screen decides again after the device region changes',
      (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      SurfaceCanonicalCarrierProvider.installBuiltIns(
          () async => _carrier('ambient'));
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      final fixture = stringScreenFixture();
      final surfaceRequests = <Map<String, dynamic>>[];
      final cells = <SurfaceDeliveryObservationCell>[];
      final client = RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          cells.add(currentSurfaceDeliveryObservationCell()!);
          surfaceRequests.add((jsonDecode(request.body) as Map).cast());
          return http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(fixture
                .delivery(hostedBlob: fixture.blob, publishedRevision: 8)),
            200,
          );
        }),
      );
      final resolver = RestageScreenResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.values.first,
        rpcClientProvider: () => client,
      );
      for (final region in ['SE', 'US']) {
        tester.binding.platformDispatcher.localeTestValue =
            Locale('en', region);
        await tester.pumpWidget(MaterialApp(
          home: RestageScreen(
            screen: fixture.ref,
            resolver: resolver,
            unavailable: SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, error) => Text('$error'),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Bundled screen'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(surfaceRequests, hasLength(2));
      expect(cells, hasLength(2));
      expect(identical(cells.first, cells.last), isFalse);
      expect(cells.map((cell) => cell.valueIfRead?.presentationCountry),
          ['SE', 'US']);
      expect(
        surfaceRequests.map((request) => request['sdkBuiltInsCanonicalBase64']),
        cells
            .map((cell) => cell.valueIfRead!.canonicalBuiltInsBase64())
            .toList(),
      );
      expect(surfaceRequests.first['sdkBuiltInsCanonicalBase64'],
          isNot(surfaceRequests.last['sdkBuiltInsCanonicalBase64']));
      expect(fixture.hostedDelivery.artifactRequests, hasLength(1));
    });
  });

  testWidgets('a screen mounted after dispose reads through its own cell',
      (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      var ambientReads = 0;
      SurfaceCanonicalCarrierProvider.installBuiltIns(() async {
        ambientReads += 1;
        return _carrier('ambient');
      });
      final fixture = stringScreenFixture();
      final surfaceRequests = <Map<String, dynamic>>[];
      final cells = <SurfaceDeliveryObservationCell>[];
      _setBuild(42);
      for (var mount = 0; mount < 2; mount += 1) {
        final client = RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: fixture.hostedDelivery.client((request) async {
            cells.add(currentSurfaceDeliveryObservationCell()!);
            surfaceRequests.add((jsonDecode(request.body) as Map).cast());
            return http.Response(
              SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(fixture
                  .delivery(hostedBlob: fixture.blob, publishedRevision: 8)),
              200,
            );
          }),
        );
        await tester.pumpWidget(MaterialApp(
            home: RestageScreen(
          screen: fixture.ref,
          resolver: RestageScreenResolver(
            apiKey: _apiKey,
            environment: RestageEnvironment.values.first,
            rpcClientProvider: () => client,
          ),
          unavailable: SurfaceScreenUnavailablePolicy.fallback(
            builder: (_, error) => const SizedBox.shrink(),
          ),
        )));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(surfaceRequests, hasLength(2));
      expect(cells, hasLength(2));
      expect(identical(cells.first, cells.last), isFalse);
      // The build cannot change while the app runs, so both readings carry it.
      expect(cells.map((cell) => cell.valueIfRead?.appBuildOrdinal), [42, 42]);
      expect(
          surfaceRequests
              .map((request) => request['sdkBuiltInsCanonicalBase64']),
          cells
              .map((cell) => cell.valueIfRead!.canonicalBuiltInsBase64())
              .toList());
      expect(ambientReads, 0);
    });
  });
}

Widget _host(
  FlowResolver resolver, {
  void Function(FlowUnavailableError error)? onFlowUnavailable,
}) =>
    MaterialApp(
      home: RestageFlowGraph<Map<String, Object?>>(
        flow: _flowRef,
        resolver: resolver,
        onFlowUnavailable: onFlowUnavailable,
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text('UNAVAILABLE:${error.reason}'),
        ),
      ),
    );

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

FlowDocument _screenDocument({
  required Uint8List screenBytes,
  String flow = 'first_run',
  int version = 1,
  String screenId = 'welcome',
  String artifactPath = 'welcome.rfw',
  Map<String, Object?> terminalResult = const {'completed': true},
}) {
  return FlowDocument(
    flow: flow,
    version: version,
    schemaVersion: 1,
    minClient: _installed,
    initial: screenId,
    actions: const {},
    screenArtifacts: {
      screenId: ScreenArtifact(
        path: artifactPath,
        version: 1,
        schemaVersion: 1,
        minClient: _installed,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: {
      screenId: ScreenFlowState(
        screen: screenId,
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: terminalResult),
    },
  );
}

Uint8List _envelope(
  FlowDocument document,
  Map<String, Uint8List> screenBlobs, {
  Surface surfaceType = Surface.onboarding,
}) {
  return SurfaceDocumentCodec.encode(SurfaceDocument(
    surfaceType: surfaceType,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: FlowSurfacePayload(
      flowDocument: document,
      screenBlobs: screenBlobs,
    ),
    publishedAt: DateTime.utc(2026),
  ));
}

Map<String, Object?> _contentBody(Uint8List envelope) => {
      ..._delivery.describeEnvelope(envelope),
    };

Map<String, Object?> _requestBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

AssetBundle _bundleFor(
  FlowDocument document,
  Uint8List screenBytes, {
  Surface surfaceType = Surface.onboarding,
}) {
  return _bundleForClosure(
    surfaceType: surfaceType,
    documents: [document],
    screenAssets: {'welcome.rfw': screenBytes},
  );
}

AssetBundle _bundleForClosure({
  required Surface surfaceType,
  required List<FlowDocument> documents,
  required Map<String, Uint8List> screenAssets,
}) =>
    _TestBundle(_bundleAssets(
      surfaceType: surfaceType,
      documents: documents,
      screenAssets: screenAssets,
    ));

Map<String, Uint8List> _bundleAssets({
  required Surface surfaceType,
  required List<FlowDocument> documents,
  required Map<String, Uint8List> screenAssets,
}) {
  final surface = surfaceType.wireName;
  return {
    for (final document in documents)
      'assets/$surface/flows/${document.flow}.flow.json':
          Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
    for (final entry in screenAssets.entries)
      'assets/$surface/screens/${entry.key}': entry.value,
  };
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.value();
  }
  fail('Controlled test boundary did not become ready.');
}

final class _ControlledServer {
  _ControlledServer({void Function()? onRequest}) {
    client = _delivery.client((request) {
      onRequest?.call();
      requests.add(request);
      final response = Completer<http.Response>();
      responses.add(response);
      return response.future;
    });
  }

  late final MockClient client;
  final List<http.Request> requests = [];
  final List<Completer<http.Response>> responses = [];

  void respondJson(int index, Map<String, Object?> body) {
    responses[index].complete(http.Response(jsonEncode(body), 200));
  }

  void respondNotFound(int index) {
    responses[index].complete(http.Response('', 404));
  }

  void completeOutstandingWithNotFound() {
    for (final response in responses) {
      if (!response.isCompleted) response.complete(http.Response('', 404));
    }
  }
}

final class _TestBundle extends CachingAssetBundle {
  _TestBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
