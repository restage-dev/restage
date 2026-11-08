import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;
import 'package:shared_preferences/shared_preferences.dart';

import 'flow_test_support.dart' show registerThrowingWidget, screenBlob;
import '../support/hosted_artifact_delivery.dart';

const int _installed = RestageBuiltInCatalogCapabilities.currentVersion;
const int _refFloor = _installed + 2;
final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final support = Directory.systemTemp.createTempSync('restage-restart-');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  binding.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async => support.path);
  tearDownAll(() async {
    await Restage.debugResetAndWait();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
    await support.delete(recursive: true);
  });
  setUp(Restage.debugReset);
  tearDown(Restage.debugResetAndWait);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_abc123';

  // How the mount reaches its resolver: the configured default, a configured
  // flowResolver, or the widget's own resolver.
  for (final route in ['default', 'configured', 'widget']) {
    for (final active in [true, false]) {
      if (route == 'default' && !active) continue;
      testWidgets(
          'a delivered flow that throws restarts in its compiled original '
          'without refetching: $route resolver, active=$active',
          (tester) async {
        registerThrowingWidget();
        SurfaceAssignmentKeyProvider.current = () => 'anon';
        addTearDown(SurfaceAssignmentKeyProvider.clear);
        final throwing = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(
            'import acme.throwing; widget OnboardingScreen = ThrowingWidget();')));
        final originalBytes = screenBlob('Original', 'next');
        final requests = <http.Request>[];
        final server = _server(
            _envelope(
                _doc(version: active ? 2 : 1, screenBytes: throwing), throwing),
            onRequest: requests.add);
        ServerFlowResolver resolver() => ServerFlowResolver(
              baseUrl: baseUrl,
              apiKey: apiKey,
              active: active,
              bundle: _TestBundle(const {}),
              httpClient: server,
            );
        Restage.configure(
          apiKey: apiKey,
          baseUrl: baseUrl,
          analyticsEnabled: false,
          measurementEnabled: false,
          deliveryReceiptsEnabled: false,
          flowResolver: route == 'configured' ? resolver() : null,
        );
        Restage.debugRestageRpcClient = RestageRpcClient(
            apiKey: apiKey, baseUrl: baseUrl, httpClient: server);
        final flow = SurfaceFlowRef<Map<String, Object?>>(
          id: 'first_run',
          version: 1,
          minClient: _refFloor,
          surface: Surface.onboarding,
          decodeResult: (result) => result,
          compiled: CompiledFlow(
            documentJson: utf8.decode(FlowDocumentCodec.encodeCanonicalJson(
                _doc(screenBytes: originalBytes))),
            screens: {'welcome': () => const Text('Welcome original')},
          ),
        );
        FlowUnavailableError? unavailable;
        await tester.pumpWidget(MaterialApp(
          home: RestageFlowGraph<Map<String, Object?>>(
            flow: flow,
            resolver: route == 'widget' ? resolver() : null,
            onFlowUnavailable: (e) => unavailable = e,
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 50));
          tester.takeException();
        }
        await tester.pumpAndSettle();
        tester.takeException();
        final shown = find.text('Welcome original').evaluate().length;
        final fetches = requests.length;
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(unavailable?.reason, 'render_failed');
        expect(shown, 1);
        expect(fetches, 1);
      });
    }
  }
}

FlowDocument _doc({
  required Uint8List screenBytes,
  int version = 1,
}) =>
    FlowDocument(
      flow: 'first_run',
      version: version,
      schemaVersion: 1,
      minClient: _installed,
      initial: 'welcome',
      actions: const {},
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: _installed,
          contentHash: FlowContentHash.compute(screenBytes),
        ),
      },
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    );

Uint8List _envelope(FlowDocument document, Uint8List screenBytes) {
  final surface = SurfaceDocument(
    surfaceType: Surface.onboarding,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: FlowSurfacePayload(
      flowDocument: document,
      screenBlobs: {'welcome': screenBytes},
    ),
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

MockClient _server(Uint8List envelope,
        {void Function(http.Request request)? onRequest}) =>
    _delivery.client((request) async {
      onRequest?.call(request);
      return http.Response(
          jsonEncode({..._delivery.describeEnvelope(envelope)}), 200);
    });

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
