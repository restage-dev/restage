import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';

import 'fixtures/compiled_surfaces/native_flow.dart';
import 'flow/flow_test_support.dart' as support;

class _NoAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('No $key');
}

class _BaselineAssets extends CachingAssetBundle {
  _BaselineAssets(this.baseline);
  final ResolvedFlow baseline;
  final reads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    final bytes = key == 'assets/onboarding/flows/first_run.flow.json'
        ? FlowDocumentCodec.encodeCanonicalJson(baseline.document)
        : {
            for (final entry in baseline.document.screenArtifacts.entries)
              'assets/onboarding/screens/${entry.value.path}':
                  baseline.screenBlobs[entry.key]!,
          }[key];
    if (bytes == null) throw FlutterError('No $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _UnrenderableResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      ResolvedVariant(
        bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
import restage.core;
widget Paywall = MissingWidget();
'''))),
        surfaceVersion: '1',
        paywallId: id,
      );
}

void main() {
  setUp(Restage.debugReset);

  for (final compiled in [false, true]) {
    test('valid bundle remains usable with partial native metadata: $compiled',
        () async {
      final baseline = support.resolvedFlow();
      final assets = _BaselineAssets(baseline);
      final flow = OnboardingFlowRef<support.FirstRunResult>(
        id: support.firstRunFlowRef.id,
        version: support.firstRunFlowRef.version,
        minClient: support.firstRunFlowRef.minClient,
        surface: Surface.onboarding,
        decodeResult: support.FirstRunResult.decode,
        compiled: compiled
            ? CompiledFlow(
                documentJson: utf8.decode(
                    FlowDocumentCodec.encodeCanonicalJson(baseline.document)),
                screens: const {},
              )
            : null,
      );
      var requests = 0;
      final resolver = ServerFlowResolver(
        apiKey: 'rs_pk_dev_fallback',
        baseUrl: 'https://flows.example.test',
        active: true,
        bundle: assets,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('', 503);
        }),
      );
      Object? failure;
      ResolvedFlow? resolved;
      try {
        resolved = await resolver.resolveActiveRoot(flow);
      } on Object catch (e) {
        failure = e;
      }

      expect(failure, isNull);
      expect(resolved!.screenBlobs.length, 2);
      expect(requests, greaterThan(0));
    });
  }

  testWidgets(
      'existing public RFW view composition admits controller dispatcher',
      (tester) async {
    final controller = RestageFlowController<support.FirstRunResult>(
      flow: support.firstRunFlowRef,
      resolver: support.StaticFlowResolver(support.resolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    final loading = controller.load();
    await tester.pumpWidget(MaterialApp(
        home: RestageEventDispatcher(
      onEvent: controller.handleEvent,
      child: RestageFlowView(controller: controller),
    )));
    await tester.pumpAndSettle();
    await loading;
    Object? failure;
    try {
      surfaceEvent(const SurfaceEvent<void>('next'))();
    } on Object catch (e) {
      failure = e;
    }
    await tester.pumpAndSettle();
    final profiles = find.text('Profile').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();

    expect(failure, isNull);
    expect(profiles, 1);
  });

  testWidgets('initial render failure reaches generated paywall original',
      (tester) async {
    final events = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
        home: NativeOfferSurface(
      resolver: _UnrenderableResolver(),
      onEvent: events.add,
    )));
    await tester.pumpAndSettle();
    final originals = find.text('Offer original').evaluate().length;
    final failures =
        events.whereType<PaywallLoadFailed>().map((e) => e.errorCode).toList();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(failures, contains('render_error'));
    expect(originals, 1);
  });

  test('incomplete native reference without assets fails as unavailable',
      () async {
    var requests = 0;
    final resolver = ServerFlowResolver(
      apiKey: 'rs_pk_dev_fallback',
      baseUrl: 'https://flows.example.test',
      active: true,
      bundle: _NoAssets(),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 503);
      }),
    );
    Object? failure;
    try {
      await resolver.resolveActiveRoot(nativeNamedFlowRef);
    } on Object catch (e) {
      failure = e;
    }

    expect(failure, isA<FlowUnavailableError>());
    expect(requests, 0);
  });

  testWidgets('public flow view dispatches native screen events',
      (tester) async {
    var completed = false;
    final controller = RestageFlowController<NativeClassResult>(
      flow: nativeClassFlowRef,
      actions: null,
      onEvent: (_) {},
      onUnavailable: (_) {},
      resolver: AssetFlowResolver(bundle: _NoAssets()),
      onComplete: (_) => completed = true,
    );
    final loading = controller.load();
    await tester.pumpWidget(MaterialApp(
        home: RestageEventDispatcher(
      onEvent: controller.handleEvent,
      child: RestageFlowView(controller: controller),
    )));
    await tester.pumpAndSettle();
    await loading;
    await tester.tap(find.text('Preferences original'));
    await tester.pumpAndSettle();
    final error = tester.takeException();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();

    expect(error, isNull);
    expect(completed, isTrue);
  });
}
