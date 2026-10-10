import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/restage_rpc_client/bounded_http_client.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../flow/flow_test_support.dart' as flows;
import '../surface_screen/surface_screen_test_support.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_fetch';
const _surfacePath = '/sdk/v1/surface';

/// A server that accepts every request and never answers.
MockClient _silentServer(List<String> paths) => MockClient((request) {
      paths.add(request.url.path);
      return Completer<http.Response>().future;
    });

final class _NoAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('No $key');
}

final class _FlowAssets extends CachingAssetBundle {
  _FlowAssets(this.flow);

  final ResolvedFlow flow;

  @override
  Future<ByteData> load(String key) async {
    final bytes = key == 'assets/onboarding/flows/first_run.flow.json'
        ? FlowDocumentCodec.encodeCanonicalJson(flow.document)
        : {
            for (final entry in flow.document.screenArtifacts.entries)
              'assets/onboarding/screens/${entry.value.path}':
                  flow.screenBlobs[entry.key]!,
          }[key];
    if (bytes == null) throw FlutterError('No $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  Future<void> passDeadline(WidgetTester tester) async {
    await tester.pump(Restage.renderDeadline);
    await tester.pump();
  }

  // Lets the stalled background fetch time out before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(BoundedHttpClient.defaultTimeout);
    await tester.pumpWidget(const SizedBox());
  }

  Widget screenHost(RestageRpcClient client) {
    final fixture = stringScreenFixture();
    return MaterialApp(
      home: RestageScreen<String>(
        screen: fixture.ref,
        resolver: RestageScreenResolver(
          apiKey: _apiKey,
          environment: RestageEnvironment.production,
          baseUrl: _baseUrl,
          assetFallback: FixedBundledScreenResolver(fixture.bundled()),
          rpcClientProvider: () => client,
        ),
        unavailable: SurfaceScreenUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason.name}'),
        ),
      ),
    );
  }

  testWidgets('a screen renders its bundled copy at the render deadline',
      (tester) async {
    final paths = <String>[];
    await tester.pumpWidget(screenHost(RestageRpcClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      httpClient: _silentServer(paths),
    )));
    await settle(tester, () => paths.isNotEmpty);
    expect(paths, [_surfacePath]);
    expect(find.text('Bundled screen'), findsNothing);

    await passDeadline(tester);

    expect(find.text('Bundled screen'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'a screen renders its bundled copy at the render deadline when its '
      'content never arrives', (tester) async {
    final fixture = stringScreenFixture();
    final paths = <String>[];
    final client = RestageRpcClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path != _surfacePath) {
          return Completer<http.Response>().future;
        }
        return http.Response(
          jsonEncode(SurfaceScreenDeliveryDescriptorV1Codec.encode(
            fixture.delivery(
              hostedBlob: rfwScreenBlob(text: 'Hosted screen', event: 'tap'),
            ),
          )),
          200,
        );
      }),
    );
    await tester.pumpWidget(screenHost(client));
    await settle(tester, () => paths.length > 1);
    expect(paths, hasLength(2));
    expect(find.text('Bundled screen'), findsNothing);

    await passDeadline(tester);

    expect(find.text('Bundled screen'), findsOneWidget);
    expect(find.text('Hosted screen'), findsNothing);
    await unmount(tester);
  });

  testWidgets(
      'a paywall renders its original at the render deadline when the server '
      'never answers', (tester) async {
    final paths = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: NativeOfferSurface(
        resolver: RestageVariantResolver(
          apiKey: _apiKey,
          environment: RestageEnvironment.production,
          baseUrl: _baseUrl,
          httpClient: _silentServer(paths),
          assetFallback: AssetVariantResolver(bundle: _NoAssets()),
        ),
      ),
    ));
    await settle(tester, () => paths.isNotEmpty);
    expect(paths, [_surfacePath]);
    expect(find.text('Offer original'), findsNothing);

    await passDeadline(tester);
    await settle(
      tester,
      () => find.text('Offer original').evaluate().isNotEmpty,
    );

    expect(find.text('Offer original'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'a flow renders its bundled baseline at the render deadline when the '
      'server never answers', (tester) async {
    final paths = <String>[];
    final controller = RestageFlowController<flows.FirstRunResult>(
      flow: flows.firstRunFlowRef,
      resolver: ServerFlowResolver(
        apiKey: _apiKey,
        baseUrl: _baseUrl,
        active: true,
        bundle: _FlowAssets(flows.resolvedFlow()),
        httpClient: _silentServer(paths),
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);
    unawaited(controller.load());
    await tester.pumpWidget(MaterialApp(
      home: RestageEventDispatcher(
        onEvent: controller.handleEvent,
        child: RestageFlowView(controller: controller),
      ),
    ));
    await settle(tester, () => paths.isNotEmpty);
    expect(paths, [_surfacePath]);
    expect(find.text('Welcome'), findsNothing);

    await passDeadline(tester);
    await settle(tester, () => find.text('Welcome').evaluate().isNotEmpty);

    expect(find.text('Welcome'), findsOneWidget);
    await unmount(tester);
  });
}
