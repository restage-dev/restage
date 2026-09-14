import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage_shared/restage_shared.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../support/hosted_artifact_delivery.dart';
import 'flow_test_support.dart' show screenBlob, StaticFlowResolver;

final class _NoAssets extends CachingAssetBundle {
  final List<String> reads = [];

  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    throw FlutterError('No bundled assets: $key');
  }
}

void main() {
  setUp(Restage.debugReset);

  testWidgets(
      'generated native flow preserves actions, history, child flow and typed completion',
      (tester) async {
    final bundle = _NoAssets();
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    var granted = false;
    var actions = 0;
    NativeWelcomeFlowResult? completed;
    await tester.pumpWidget(MaterialApp(
        home: NativeWelcomeFlowSurface(
      resolver: AssetFlowResolver(bundle: bundle),
      actions: NativeWelcomeFlowActions(permission: (_, __) {
        actions++;
        return granted;
      }),
      onComplete: (result) => completed = result,
    )));
    await tester.pumpAndSettle();
    final originalState = tester.state(find.byType(NativeWelcome));
    await tester.tap(find.text('Welcome original'));
    await tester.pumpAndSettle();
    final blockedAtWelcome = find.text('Welcome original').evaluate().length;
    granted = true;
    await tester.tap(find.text('Welcome original'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<RestageFlowView<NativeWelcomeFlowResult>>(
          find.byType(RestageFlowView<NativeWelcomeFlowResult>),
        )
        .controller;
    controller.back();
    await tester.pumpAndSettle();
    final restoredState = tester.state(find.byType(NativeWelcome));
    await tester.tap(find.text('Welcome original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferences original'));
    await tester.pumpAndSettle();
    final beforeChildCompletion = completed;
    await tester.tap(find.text('Offer original'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(blockedAtWelcome, 1);
    expect(identical(originalState, restoredState), isTrue);
    expect(actions, 3);
    expect(beforeChildCompletion, isNull);
    expect(completed?.completed, isTrue);
    expect(events.whereType<FlowUnavailable>(), isEmpty);
    expect(bundle.reads, isNotEmpty);
  });

  testWidgets(
      'generated builder parameters preserve arguments without restarting on rebuild',
      (tester) async {
    var completed = false;
    final resolver = AssetFlowResolver(bundle: _NoAssets());
    Widget mount() => MaterialApp(
            home: NativeNamedFlowSurface(
          nativeNamedScreenBuilder: () =>
              const NativeNamed(title: 'App argument'),
          resolver: resolver,
          onComplete: (_) => completed = true,
        ));
    await tester.pumpWidget(mount());
    await tester.pumpAndSettle();
    final before = tester
        .widget<RestageFlowView<NativeNamedFlowResult>>(
          find.byType(RestageFlowView<NativeNamedFlowResult>),
        )
        .controller;
    await tester.pumpWidget(mount());
    await tester.pumpAndSettle();
    final after = tester
        .widget<RestageFlowView<NativeNamedFlowResult>>(
          find.byType(RestageFlowView<NativeNamedFlowResult>),
        )
        .controller;
    await tester.tap(find.text('App argument'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(identical(before, after), isTrue);
    expect(completed, isTrue);
  });

  testWidgets('class-authored flow uses the same generated native mount',
      (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(
        home: NativeClassFlowSurface(
      resolver: AssetFlowResolver(bundle: _NoAssets()),
      onComplete: (_) => completed = true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferences original'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(completed, isTrue);
  });

  testWidgets('generated paywall mounts its original and keeps custom events',
      (tester) async {
    final events = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
        home: NativeOfferSurface(
      resolver: AssetVariantResolver(bundle: _NoAssets()),
      onEvent: events.add,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offer original'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(events.whereType<PaywallViewed>(), hasLength(1));
    expect(events.whereType<PaywallCustomEvent>(), hasLength(1));
  });

  for (final compatible in [true, false]) {
    test(
        'active ${compatible ? 'compatible' : 'incompatible'} flow is gated by compiled contract without assets',
        () async {
      final bundle = _NoAssets();
      final original = nativeWelcomeFlowRef.compiled!;
      final delivered = _delivered(original.document, version: 2);
      final document = compatible
          ? delivered.document
          : delivered.document.copyWith(
              states: {
                ...delivered.document.states,
                'native_welcome': const ScreenFlowState(
                    screen: 'native_welcome',
                    on: {'different': GotoFlowTransition('native_preferences')})
              },
            );
      final resolver = _server(document, delivered.screenBlobs, bundle);
      final result = await resolver.resolveActiveRoot(nativeWelcomeFlowRef);
      expect(result.document.version, compatible ? 2 : 1);
      expect(result.compiled == null, compatible);
      expect(bundle.reads, isEmpty);
    });
  }

  testWidgets(
      'generated flow mounts compatible hosted content using its compiled baseline',
      (tester) async {
    final bundle = _NoAssets();
    SurfaceAssignmentKeyProvider.current = () async => 'native-hosted-test';
    addTearDown(SurfaceAssignmentKeyProvider.clear);
    final delivered =
        _delivered(nativeOfferFlowRef.compiled!.document, version: 2);
    await tester.pumpWidget(MaterialApp(
        home: NativeOfferFlowSurface(
      resolver: _server(delivered.document, delivered.screenBlobs, bundle),
    )));
    await tester.pumpAndSettle();
    final deliveredCount =
        find.text('Delivered paywall_native_offer').evaluate().length;
    final originalCount = find.text('Offer original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(deliveredCount, 1);
    expect(originalCount, 0);
    expect(bundle.reads, isEmpty);
  });

  testWidgets(
      'hosted experiment path falls back to complete compiled closure before starting',
      (tester) async {
    final bundle = _NoAssets();
    final fixture = HostedArtifactFixture();
    SurfaceAssignmentKeyProvider.current = () async => 'native-flow-test';
    addTearDown(SurfaceAssignmentKeyProvider.clear);
    final resolver = ServerFlowResolver(
      baseUrl: 'https://flows.example.test',
      apiKey: 'rs_pk_test_abc',
      active: true,
      bundle: bundle,
      httpClient: fixture.client((_) async => http.Response('', 503)),
    );
    await tester.pumpWidget(MaterialApp(
        home: NativeWelcomeFlowSurface(
      resolver: resolver,
      actions: NativeWelcomeFlowActions(permission: (_, __) => true),
    )));
    await tester.pumpAndSettle();
    final renderedOriginal = find.text('Welcome original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(renderedOriginal, 1);
    expect(bundle.reads, isEmpty);
  });

  testWidgets(
      'a running delivered flow fails closed without replaying its original',
      (tester) async {
    final original = nativeWelcomeFlowRef.compiled!;
    final delivered = _delivered(original.document);
    final missingNext = ResolvedFlow(
      document: delivered.document,
      screenBlobs: {'native_welcome': delivered.screenBlobs['native_welcome']!},
      cacheHit: false,
    );
    var actions = 0;
    FlowUnavailableError? unavailable;
    await tester.pumpWidget(MaterialApp(
        home: NativeWelcomeFlowSurface(
      resolver: StaticFlowResolver(missingNext),
      actions: NativeWelcomeFlowActions(permission: (_, __) {
        actions++;
        return true;
      }),
      onFlowUnavailable: (error) => unavailable = error,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivered native_welcome'));
    await tester.pumpAndSettle();
    final originalVisible = find.text('Welcome original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(actions, 1);
    expect(unavailable?.reason, 'missing_screen_blob');
    expect(originalVisible, 0);
  });
}

ResolvedFlow _delivered(FlowDocument document, {int? version}) {
  final blobs = {
    for (final entry in document.screenArtifacts.entries)
      entry.key: screenBlob('Delivered ${entry.key}',
          entry.key == 'native_welcome' ? 'next' : 'done'),
  };
  return ResolvedFlow(
    document: document
        .copyWith(version: version ?? document.version, screenArtifacts: {
      for (final entry in document.screenArtifacts.entries)
        entry.key: ScreenArtifact(
            path: entry.value.path,
            version: entry.value.version,
            schemaVersion: entry.value.schemaVersion,
            minClient: entry.value.minClient,
            contentHash: FlowContentHash.compute(blobs[entry.key]!)),
    }),
    screenBlobs: blobs,
    cacheHit: false,
  );
}

ServerFlowResolver _server(
    FlowDocument document, Map<String, Uint8List> blobs, AssetBundle bundle) {
  final fixture = HostedArtifactFixture();
  final envelope = SurfaceDocumentCodec.encode(SurfaceDocument(
    surfaceType: Surface.onboarding,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: FlowSurfacePayload(flowDocument: document, screenBlobs: blobs),
    publishedAt: DateTime.utc(2026),
  ));
  return ServerFlowResolver(
    baseUrl: 'https://flows.example.test',
    apiKey: 'rs_pk_test_abc',
    active: true,
    bundle: bundle,
    httpClient: fixture.client((_) async =>
        http.Response(jsonEncode(fixture.describeEnvelope(envelope)), 200)),
  );
}
