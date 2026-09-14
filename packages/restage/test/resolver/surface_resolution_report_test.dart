import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';

import '../measurement/support/measurement_outbox_test_support.dart'
    show alternateBindingReference;
import '../support/canonical_assignment_fixture.dart';
import '../support/hosted_artifact_delivery.dart';
import '../surface_screen/surface_screen_test_support.dart';

const _surface = 'pro_upgrade';
const _selection = const <String, Object?>{
  'selectedRouteId': 'route-a',
  'audienceRevisionRef': 'audience-v2',
  'routingRevisionOrdinal': 3,
  'rolloutAllocationId': 'allocation-a',
  'rolloutBranch': 'control',
  'defaultSelectionReason': 'no-match'
};

const _receipt = '  opaque.receipt+/= 雪  ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final supportDirectory =
        await Directory.systemTemp.createTemp('restage-configure-');
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

  for (final selection in <Object?>[
    _selection,
    null,
    {'unexpected': true},
    {'selectedRouteId': 'x' * 257},
    {'routingRevisionOrdinal': -1},
    'malformed',
  ]) {
    test('general delivery preserves optional selection $selection', () async {
      final reports = <SurfaceResolutionReport>[];
      _configure(reports.add);
      final fixture = _ResolutionFixture(selection: selection);
      final first = await fixture.resolver.resolve(_surface);
      fixture.failDelivery = true;
      final held = await fixture.resolver.resolve(_surface);
      expect(first.bytes, orderedEquals(fixture.blob));
      expect(held.bytes, orderedEquals(first.bytes));
      expect(held.cacheHit, isTrue);
      final expected = identical(selection, _selection)
          ? SurfaceRoutingSelectionProvenanceV1.fromJson(_selection)
          : null;
      expect(routingSelectionProvenanceFor(first), expected);
      expect(routingSelectionProvenanceFor(held),
          same(routingSelectionProvenanceFor(first)));
      expect(reports, [
        for (final source in [
          SurfaceResolutionSource.fresh,
          SurfaceResolutionSource.holdLastGood
        ])
          SurfaceResolutionReport(
            surface: _surface,
            source: source,
            selectedRouteId: expected?.selectedRouteId,
            audienceRevisionRef: expected?.audienceRevisionRef,
            routingRevisionOrdinal: expected?.routingRevisionOrdinal,
            rolloutAllocationId: expected?.rolloutAllocationId,
            rolloutBranch: expected?.rolloutBranch,
            defaultSelectionReason: expected?.defaultSelectionReason,
          ),
      ]);
    });

    for (final failSecond in [false, true]) {
      testWidgets(
          'typed delivery preserves optional selection $selection with failure=$failSecond',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        final reports = <SurfaceResolutionReport>[];
        await tester.runAsync(() async => _configure(reports.add));
        final fixture = stringScreenFixture();
        var fail = false;
        final body = {
          ...fixture
              .delivery(hostedBlob: fixture.blob, publishedRevision: 8)
              .toJson(),
          if (selection != null) 'routingSelectionProvenance': selection,
        };
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: fixture.hostedDelivery.client((_) async => fail
              ? http.Response('', 503)
              : http.Response(jsonEncode(body), 200)),
        );
        final resolver = RestageScreenResolver(
          apiKey: 'rs_pk_test',
          environment: RestageEnvironment.sandbox,
          rpcClientProvider: () => client,
        );
        Future<void> mount() async {
          await tester.pumpWidget(MaterialApp(
              home: RestageScreen(
            screen: fixture.ref,
            resolver: resolver,
            unavailable: SurfaceScreenUnavailablePolicy.fallback(
                builder: (_, error) => Text('$error')),
          )));
          await tester.pumpAndSettle();
          expect(find.text('Bundled screen'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        }

        await mount();
        fail = failSecond;
        await mount();
        final expected = identical(selection, _selection)
            ? SurfaceRoutingSelectionProvenanceV1.fromJson(_selection)
            : null;
        expect(reports, [
          for (final source in [
            SurfaceResolutionSource.fresh,
            failSecond
                ? SurfaceResolutionSource.holdLastGood
                : SurfaceResolutionSource.fresh
          ])
            SurfaceResolutionReport(
              surface: fixture.ref.slug,
              source: source,
              selectedRouteId: expected?.selectedRouteId,
              audienceRevisionRef: expected?.audienceRevisionRef,
              routingRevisionOrdinal: expected?.routingRevisionOrdinal,
              rolloutAllocationId: expected?.rolloutAllocationId,
              rolloutBranch: expected?.rolloutBranch,
              defaultSelectionReason: expected?.defaultSelectionReason,
            ),
        ]);
      });
    }
  }

  test('each selection fact participates in report equality and text', () {
    final complete = SurfaceResolutionReport(
      surface: _surface,
      source: SurfaceResolutionSource.fresh,
      selectedRouteId: 'route-a',
      audienceRevisionRef: 'audience-v2',
      routingRevisionOrdinal: 3,
      rolloutAllocationId: 'allocation-a',
      rolloutBranch: 'control',
      defaultSelectionReason: 'no-match',
    );
    final equal = SurfaceResolutionReport(
      surface: _surface,
      source: SurfaceResolutionSource.fresh,
      selectedRouteId: 'route-a',
      audienceRevisionRef: 'audience-v2',
      routingRevisionOrdinal: 3,
      rolloutAllocationId: 'allocation-a',
      rolloutBranch: 'control',
      defaultSelectionReason: 'no-match',
    );
    expect(complete, equal);
    expect(complete.hashCode, equal.hashCode);
    expect(complete.toString(), contains('selectedRouteId: route-a'));
    expect(complete.toString(), contains('audienceRevisionRef: audience-v2'));
    expect(complete.toString(), contains('routingRevisionOrdinal: 3'));
    expect(complete.toString(), contains('rolloutAllocationId: allocation-a'));
    expect(complete.toString(), contains('rolloutBranch: control'));
    expect(complete.toString(), contains('defaultSelectionReason: no-match'));

    for (final other in [
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
        audienceRevisionRef: 'audience-v2',
        routingRevisionOrdinal: 3,
        rolloutAllocationId: 'allocation-a',
        rolloutBranch: 'control',
        defaultSelectionReason: 'no-match',
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
        selectedRouteId: 'route-a',
        routingRevisionOrdinal: 3,
        rolloutAllocationId: 'allocation-a',
        rolloutBranch: 'control',
        defaultSelectionReason: 'no-match',
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
        selectedRouteId: 'route-a',
        audienceRevisionRef: 'audience-v2',
        rolloutAllocationId: 'allocation-a',
        rolloutBranch: 'control',
        defaultSelectionReason: 'no-match',
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
        selectedRouteId: 'route-a',
        audienceRevisionRef: 'audience-v2',
        routingRevisionOrdinal: 3,
        rolloutBranch: 'control',
        defaultSelectionReason: 'no-match',
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
        selectedRouteId: 'route-a',
        audienceRevisionRef: 'audience-v2',
        routingRevisionOrdinal: 3,
        rolloutAllocationId: 'allocation-a',
        defaultSelectionReason: 'no-match',
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
        selectedRouteId: 'route-a',
        audienceRevisionRef: 'audience-v2',
        routingRevisionOrdinal: 3,
        rolloutAllocationId: 'allocation-a',
        rolloutBranch: 'control',
      ),
    ]) {
      expect(complete, isNot(other));
    }
  });

  for (final source in SurfaceResolutionSource.values) {
    testWidgets('mounted paywall reports and labels $source', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final reports = <SurfaceResolutionReport>[];
      await tester.runAsync(() async => _configure((report) {
            reports.add(report);
            throw StateError('Host callback failed');
          }));
      final fixture = _ResolutionFixture();
      final delegate = source == SurfaceResolutionSource.bundled
          ? RestageVariantResolver(
              apiKey: 'rs_pk_test',
              environment: RestageEnvironment.sandbox,
              assetFallback: _FixedVariantResolver(fixture.bundled),
            )
          : fixture.resolver;
      final resolver = _RecordingPaywallResolver(delegate);
      Future<void> mount() async {
        await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(id: _surface, resolver: resolver),
        ));
        await tester.pumpAndSettle();
      }

      if (source == SurfaceResolutionSource.holdLastGood) {
        await mount();
        expect(find.text('Hosted paywall'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.failDelivery = true;
        reports.clear();
      }
      await mount();
      expect(
          find.text(source == SurfaceResolutionSource.bundled
              ? 'Bundled paywall'
              : 'Hosted paywall'),
          findsOneWidget);
      final payload = resolver.payload!;
      final leaf = switch (payload) {
        BlobPaywallPayload(:final variant) => variant,
        FlowPaywallPayload(:final flow) => flow,
      };
      expect(surfaceResolutionSourceFor(leaf), source);
      expect(reports,
          [SurfaceResolutionReport(surface: _surface, source: source)]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('mounted hosted flow reports fresh', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final reports = <SurfaceResolutionReport>[];
    await tester.runAsync(() async => _configure(reports.add));
    final bytes = rfwScreenBlob(text: 'Hosted flow', event: 'next');
    final document = FlowDocument(
      flow: 'first_run',
      version: 1,
      schemaVersion: 1,
      minClient: 1,
      initial: 'welcome',
      actions: const {},
      screenArtifacts: {
        'welcome': ScreenArtifact(
            path: 'welcome.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: 1,
            contentHash: FlowContentHash.compute(bytes)),
      },
      states: {
        'welcome': ScreenFlowState(
            screen: 'welcome', on: {'next': FlowTransition.goto('done')}),
        'done': EndFlowState(result: const {}),
      },
    );
    final delivery = HostedArtifactFixture();
    final body = delivery.deliveryBody(SurfaceDocument(
      surfaceType: Surface.onboarding,
      surfaceSlug: 'first_run',
      version: 1,
      minClient: 1,
      publishedAt: DateTime.utc(2026),
      payload: FlowSurfacePayload(
          flowDocument: document, screenBlobs: {'welcome': bytes}),
    ));
    final resolver = ServerFlowResolver(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient:
          delivery.client((_) async => http.Response(jsonEncode(body), 200)),
    );
    await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<Map<String, Object?>>(
      flow: OnboardingFlowRef<Map<String, Object?>>(
          id: 'first_run',
          version: 1,
          minClient: 1,
          surface: Surface.onboarding,
          decodeResult: (result) => result),
      resolver: resolver,
      unavailable:
          FlowUnavailablePolicy.fallback(builder: (_, error) => Text('$error')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Hosted flow'), findsOneWidget);
    expect(reports, const [
      SurfaceResolutionReport(
          surface: 'first_run', source: SurfaceResolutionSource.fresh)
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mounted typed screen reports fresh', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final reports = <SurfaceResolutionReport>[];
    await tester.runAsync(() async => _configure(reports.add));
    final fixture = stringScreenFixture();
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: fixture.hostedDelivery.client((_) async => http.Response(
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(hostedBlob: fixture.blob, publishedRevision: 8)),
          200)),
    );
    await tester.pumpWidget(MaterialApp(
        home: RestageScreen(
      screen: fixture.ref,
      resolver: RestageScreenResolver(
          apiKey: 'rs_pk_test',
          environment: RestageEnvironment.sandbox,
          rpcClientProvider: () => client),
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
          builder: (_, error) => Text('$error')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Bundled screen'), findsOneWidget);
    expect(reports, [
      SurfaceResolutionReport(
          surface: fixture.ref.slug, source: SurfaceResolutionSource.fresh)
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('a fresh resolution reports fresh and labels its variant', () async {
    final reports = <SurfaceResolutionReport>[];
    _configure(reports.add);
    final fixture = _ResolutionFixture();

    final resolved = await fixture.resolver.resolve(_surface);

    expect(resolved.bytes, orderedEquals(fixture.blob));
    expect(resolved.cacheHit, isFalse);
    expect(surfaceResolutionSourceFor(resolved), SurfaceResolutionSource.fresh);
    expect(reports, const [
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
      ),
    ]);
  });

  test('a held resolution reports held and keeps exact provenance', () async {
    final reports = <SurfaceResolutionReport>[];
    _configure(reports.add);
    final fixture = _ResolutionFixture();
    final first = await fixture.resolver.resolve(_surface);
    final reference = alternateBindingReference();
    final assignment = canonicalAssignmentFixture();
    // Seed non-null provenance on the cached payload to exercise its copy path.
    attachMeasurementPublicationBindingReference(
      first,
      reference,
      canonicalExperimentAssignment: assignment,
    );
    fixture.failDelivery = true;

    final second = await fixture.resolver.resolve(_surface);

    expect(fixture.deliveryCalls, 2);
    expect(second.bytes, orderedEquals(first.bytes));
    expect(second.cacheHit, isTrue);
    expect(second.paywallPublishedVersion, first.paywallPublishedVersion);
    expect(surfaceResolutionSourceFor(first), SurfaceResolutionSource.fresh);
    expect(surfaceResolutionSourceFor(second),
        SurfaceResolutionSource.holdLastGood);
    expect(measurementPublicationBindingReferenceFor(first), same(reference));
    expect(measurementPublicationBindingReferenceFor(second),
        same(measurementPublicationBindingReferenceFor(first)));
    expect(measurementExperimentAssignmentFor(second), same(assignment));
    expect(routingSelectionReceiptFor(first), _receipt);
    expect(routingSelectionReceiptFor(second),
        same(routingSelectionReceiptFor(first)));
    expect(reports, const [
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.holdLastGood,
      ),
    ]);
  });

  test('a bundled resolution reports bundled and labels the fallback',
      () async {
    final reports = <SurfaceResolutionReport>[];
    _configure(reports.add);
    final fixture = _ResolutionFixture()..failDelivery = true;

    final resolved = await fixture.resolver.resolve(_surface);

    expect(resolved, same(fixture.bundled));
    expect(
        surfaceResolutionSourceFor(resolved), SurfaceResolutionSource.bundled);
    expect(reports, const [
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.bundled,
      ),
    ]);
  });

  test('all three sources resolve without an opted-in callback', () async {
    _configure();
    final fixture = _ResolutionFixture();
    final fresh = await fixture.resolver.resolve(_surface);
    fixture.failDelivery = true;
    final held = await fixture.resolver.resolve(_surface);
    final bundledFixture = _ResolutionFixture()..failDelivery = true;
    final bundled = await bundledFixture.resolver.resolve(_surface);

    expect(surfaceResolutionSourceFor(fresh), SurfaceResolutionSource.fresh);
    expect(
        surfaceResolutionSourceFor(held), SurfaceResolutionSource.holdLastGood);
    expect(bundled, same(bundledFixture.bundled));
    expect(
        surfaceResolutionSourceFor(bundled), SurfaceResolutionSource.bundled);
  });

  test('a throwing callback cannot fail any resolution source', () async {
    final sources = <SurfaceResolutionSource>[];
    _configure((report) {
      sources.add(report.source);
      throw StateError('Host callback failed');
    });
    final fixture = _ResolutionFixture();
    final fresh = await fixture.resolver.resolve(_surface);
    fixture.failDelivery = true;
    final held = await fixture.resolver.resolve(_surface);
    final bundledFixture = _ResolutionFixture()..failDelivery = true;
    final bundled = await bundledFixture.resolver.resolve(_surface);

    expect(fresh.bytes, orderedEquals(fixture.blob));
    expect(held.bytes, orderedEquals(fixture.blob));
    expect(bundled, same(bundledFixture.bundled));
    expect(sources, SurfaceResolutionSource.values);
  });

  test('source can be overwritten without rebinding provenance', () {
    final payload = Object();
    final reference = alternateBindingReference();
    attachMeasurementPublicationBindingReference(
      payload,
      reference,
      routingSelectionReceipt: _receipt,
      surfaceResolutionSource: SurfaceResolutionSource.fresh,
    );
    attachMeasurementPublicationBindingReference(
      payload,
      null,
      surfaceResolutionSource: SurfaceResolutionSource.holdLastGood,
    );

    expect(surfaceResolutionSourceFor(payload),
        SurfaceResolutionSource.holdLastGood);
    expect(measurementPublicationBindingReferenceFor(payload), same(reference));
    expect(routingSelectionReceiptFor(payload), _receipt);
  });

  test('reconfiguration and reset clear the opted-in callback', () {
    _configure((_) {});
    expect(Restage.configuredSurfaceResolutionCallback, isNotNull);
    _configure();
    expect(Restage.configuredSurfaceResolutionCallback, isNull);
    _configure((_) {});
    Restage.debugReset();
    expect(Restage.configuredSurfaceResolutionCallback, isNull);
  });

  test('the report has value equality', () {
    const report = SurfaceResolutionReport(
      surface: _surface,
      source: SurfaceResolutionSource.holdLastGood,
      reason: 'Delivery unavailable',
    );
    final equal = SurfaceResolutionReport(
      surface: 'pro_${'upgrade'}',
      source: SurfaceResolutionSource.holdLastGood,
      reason: 'Delivery unavailable',
    );
    expect(report, equal);
    expect(report.hashCode, equal.hashCode);
    expect(report.surface, _surface);
    expect(report.source, SurfaceResolutionSource.holdLastGood);
    expect(report.reason, 'Delivery unavailable');
    expect(
        report.toString(),
        'SurfaceResolutionReport(surface: pro_upgrade, source: '
        'SurfaceResolutionSource.holdLastGood, reason: Delivery unavailable, selectedRouteId: null, audienceRevisionRef: null, routingRevisionOrdinal: null, rolloutAllocationId: null, rolloutBranch: null, defaultSelectionReason: null)');
    for (final other in const [
      SurfaceResolutionReport(
        surface: 'other',
        source: SurfaceResolutionSource.holdLastGood,
        reason: 'Delivery unavailable',
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.fresh,
        reason: 'Delivery unavailable',
      ),
      SurfaceResolutionReport(
        surface: _surface,
        source: SurfaceResolutionSource.holdLastGood,
      ),
    ]) {
      expect(report, isNot(other));
    }
  });
}

void _configure([void Function(SurfaceResolutionReport)? callback]) {
  Restage.configure(
    apiKey: 'rs_pk_test',
    analyticsEnabled: false,
    measurementEnabled: false,
    onSurfaceResolution: callback,
  );
}

final class _ResolutionFixture {
  _ResolutionFixture({Object? selection}) {
    final body = delivery.deliveryBody(
      testBlobDocument(blob, version: 7),
      extra: {
        'routingSelectionReceipt': _receipt,
        if (selection != null) 'routingSelectionProvenance': selection
      },
    );
    resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://example.com',
      assetFallback: _FixedVariantResolver(bundled),
      httpClient: delivery.client((request) async {
        expect(request.url.path, '/sdk/v1/surface');
        deliveryCalls++;
        if (failDelivery) return http.Response.bytes([], 503);
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  final delivery = HostedArtifactFixture();
  final blob = _paywallBlob('Hosted paywall');
  final bundled = ResolvedVariant(
    bytes: _paywallBlob('Bundled paywall'),
    paywallId: _surface,
    surfaceVersion: '1',
  );
  late final RestageVariantResolver resolver;
  bool failDelivery = false;
  int deliveryCalls = 0;
}

final class _FixedVariantResolver implements VariantResolver {
  _FixedVariantResolver(this.variant);

  final ResolvedVariant variant;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      variant;
}

Uint8List _paywallBlob(String text) => Uint8List.fromList(encodeLibraryBlob(
      parseLibraryFile(
          'import restage.core; widget Paywall = Text(text: "$text");'),
    ));

final class _RecordingPaywallResolver
    implements VariantResolver, PresentationPaywallResolver {
  _RecordingPaywallResolver(this.delegate);
  final RestageVariantResolver delegate;
  ResolvedPaywallPayload? payload;

  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) =>
      delegate.resolve(id, placementId: placementId, locale: locale);

  @override
  Future<ResolvedPaywallPayload> resolvePayloadForPresentation(String id,
      {String? placementId, Locale? locale}) async {
    return payload = await delegate.resolvePayloadForPresentation(id,
        placementId: placementId, locale: locale);
  }
}
