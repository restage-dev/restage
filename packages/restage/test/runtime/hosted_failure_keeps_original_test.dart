import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/flow/flow_resolver.dart';
import 'package:restage/src/resolver/placement_mount_resolver.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../support/placement_delivery_fixture.dart';

/// How the delivery service answers, and the reason a mount then reports.
enum _Server {
  /// A signed fallback decision: nothing is published.
  nothingPublished('unavailable'),

  /// The service fails with a server error.
  error('serverError'),

  /// The service limits the request rate.
  throttled('throttled'),

  /// The service refuses the request outright, as origin does, on a 4xx.
  refused('invalidAuthority'),

  /// A transient service failure, whatever reason its body names.
  transientRefusal('serverError'),

  /// The edge denies the key before origin sees the request.
  edgeDenied('invalidAuthority'),

  /// The edge cannot place the device's network; the key is fine.
  edgeNetwork('serverError'),

  /// The request never reaches the service.
  offline('offline'),

  /// A well-formed JSON reply that is not the canonical encoding.
  malformed('decodeFailed'),

  /// The device's inputs change after the request left; it is not sent again.
  stale('stale');

  const _Server(this.reason);

  final String reason;
}

var _staleInstalls = 0;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '42',
        buildSignature: '');
    Restage.debugReset();
    InstalledWidgetLibraries.reset();
    _staleInstalls = 0;
    debugResetAppBuildOrdinal();
    debugResetOsVersion();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
  });
  tearDown(() {
    Restage.debugReset();
    sharedSurfaceArtifactStore = null;
  });

  for (final server in _Server.values) {
    for (final liveRefresh in [
      const <SurfaceRefreshTrigger>{},
      const {SurfaceRefreshTrigger.appResume},
    ]) {
      final label = '${server.name}, live refresh ${liveRefresh.length}';

      testWidgets('a flow mount renders its compiled original: $label',
          (tester) async {
        final requests = <PlacementBatchModeV1>[];
        final reports = _configure(server, liveRefresh, requests: requests);
        final failures = <FlowUnavailableError>[];
        await tester.pumpWidget(MaterialApp(
            home: NativeClassFlowSurface(onFlowUnavailable: failures.add)));
        await _finish(tester,
            resume: liveRefresh.isNotEmpty,
            until: () => _reported(reports, server.reason));
        final shown = find.text('Preferences original').evaluate().length;
        await tester.pumpWidget(const SizedBox());
        expect(shown, 1, reason: failures.toString());
        expect(failures, isEmpty);
        _expectReportedFallback(reports, server.reason);
        _expectOneMountRequest(requests);
      });

      testWidgets('a screen mount renders its compiled original: $label',
          (tester) async {
        final requests = <PlacementBatchModeV1>[];
        final reports = _configure(server, liveRefresh, requests: requests);
        await tester.pumpWidget(const MaterialApp(
            home: Scaffold(body: NativeNoticeSurface('Notice original'))));
        await _finish(tester,
            resume: liveRefresh.isNotEmpty,
            until: () => _reported(reports, server.reason));
        final shown = find.textContaining('Notice original').evaluate().length;
        await tester.pumpWidget(const SizedBox());
        expect(shown, 1);
        _expectReportedFallback(reports, server.reason);
        _expectOneMountRequest(requests);
      });

      testWidgets('a paywall mount renders its compiled original: $label',
          (tester) async {
        final requests = <PlacementBatchModeV1>[];
        final reports = _configure(server, liveRefresh, requests: requests);
        await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: NativeOfferSurface())));
        await _finish(tester,
            resume: liveRefresh.isNotEmpty,
            until: () => _reported(reports, server.reason));
        final shown = find.text('Offer original').evaluate().length;
        await tester.pumpWidget(const SizedBox());
        expect(shown, 1);
        _expectReportedFallback(reports, server.reason);
        _expectOneMountRequest(requests);
      });
    }
  }

  testWidgets(
      'a hosted fetch that fails before slow local candidates keeps the '
      'compiled flow', (tester) async {
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    final failures = <FlowUnavailableError>[];
    await tester.pumpWidget(MaterialApp(
        home: NativeClassFlowSurface(
            resolver: _RejectedFetch(), onFlowUnavailable: failures.add)));
    await tester.pump(Restage.renderDeadline);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final shown = find.text('Preferences original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(shown, 1, reason: failures.toString());
    expect(failures, isEmpty);
  });

  testWidgets('a failing flow resolver never names an exception type',
      (tester) async {
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    final failures = <FlowUnavailableError>[];
    await tester.pumpWidget(MaterialApp(
        home: NativeClassFlowSurface(
            resolver: const _ThrowingFlow(), onFlowUnavailable: failures.add)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(failures.single.reason, 'resolve_failed');
    expect(failures.single.message, isNot(contains('Instance of')));
    expect(failures.single.message, isNot(contains('_Stale')));
  });

  testWidgets('a failing paywall resolver never names an exception type',
      (tester) async {
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    final events = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
        home: NativeOfferSurface(
            resolver: const _ThrowingPaywall(), onEvent: events.add)));
    await tester.pumpAndSettle();
    tester.takeException();
    final shown = find.text('Offer original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    final failure = events.whereType<PaywallLoadFailed>().single;
    expect(shown, 1);
    expect(failure.message, isNot(contains('Instance of')));
    expect(failure.message, isNot(contains('_Stale')));
  });

  final mounts = <String, (Widget, String)>{
    'flow': (const NativeClassFlowSurface(), 'Preferences original'),
    'paywall': (
      const Scaffold(body: NativeOfferSurface()),
      'Offer original',
    ),
  };
  for (final MapEntry(key: kind, value: (mount, original)) in mounts.entries) {
    testWidgets('a cold-start app resume sends one $kind mount request',
        (tester) async {
      final requests = <PlacementBatchModeV1>[];
      _configure(_Server.nothingPublished, {SurfaceRefreshTrigger.appResume},
          requests: requests, delay: const Duration(milliseconds: 200));
      await tester.pumpWidget(MaterialApp(home: mount));
      await tester.pump(const Duration(milliseconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final shown = find.text(original).evaluate().length;
      await tester.pumpWidget(const SizedBox());
      expect(shown, 1);
      _expectOneMountRequest(requests);
    });

    testWidgets('a reload during a $kind first load runs once it settles',
        (tester) async {
      final requests = <PlacementBatchModeV1>[];
      var inFlight = 0;
      var overlapped = false;
      _configure(_Server.nothingPublished, const {},
          requests: requests,
          delay: const Duration(milliseconds: 200), onMountRequest: (started) {
        inFlight += started ? 1 : -1;
        if (inFlight > 1) overlapped = true;
      });
      await tester.pumpWidget(MaterialApp(home: mount));
      await tester.pump(const Duration(milliseconds: 10));
      unawaited(Restage.reloadSurfaces());
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final shown = find.text(original).evaluate().length;
      await tester.pumpWidget(const SizedBox());
      expect(shown, 1);
      expect(requests.where((mode) => mode == PlacementBatchModeV1.mount),
          hasLength(2));
      expect(overlapped, isFalse);
    });
  }

  testWidgets(
      'a request gathered before new widgets are installed is gathered again '
      'before it is sent', (tester) async {
    final requests = <PlacementBatchModeV1>[];
    final reports =
        _configure(_Server.nothingPublished, const {}, requests: requests);
    var installed = false;
    SurfaceAssignmentKeyProvider.current = () {
      if (!installed) {
        installed = true;
        InstalledWidgetLibraries.add(RestageWidgetLibraries.fromVocabulary(
            core: {'LateWidget': buildText}));
      }
      return null;
    };
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NativeOfferSurface())));
    await _finish(tester, until: () => _reported(reports, 'unavailable'));
    await tester.pumpWidget(const SizedBox());
    expect(installed, isTrue);
    _expectOneMountRequest(requests);
    _expectReportedFallback(reports, 'unavailable');
  });

  testWidgets('a mount that must register first sends no keyless request',
      (tester) async {
    final requests = <PlacementBatchModeV1>[];
    final reports =
        _configure(_Server.nothingPublished, const {}, requests: requests);
    SurfaceAssignmentKeyProvider.install(
        key: () => null,
        identityGeneration: () => 0,
        registration: () async => null);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NativeOfferSurface())));
    await _finish(tester,
        until: () => _reported(reports, 'enrollmentRequired'));
    final shown = find.text('Offer original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(shown, 1);
    expect(requests, isNot(contains(PlacementBatchModeV1.mount)));
    _expectReportedFallback(reports, 'enrollmentRequired');
  });

  test('a queued fetch keeps the earlier answer until its own arrives',
      () async {
    var calls = 0;
    final second = Completer<void>();
    Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
        analyticsEnabled: false,
        measurementEnabled: false,
        deliveryReceiptsEnabled: false);
    debugSetOsVersion(19);
    Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
    final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          calls += 1;
          if (calls == 1) return http.Response('', 503);
          await second.future;
          final batch =
              PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes);
          return http.Response.bytes(
              _nothingPublished(batch).canonicalBytes, 200);
        }));
    Restage.debugRestageRpcClient = client;
    addTearDown(client.close);
    final resolver = PlacementPaywallResolver(
        registry: Restage.placementRegistry!,
        declaration:
            PlacementMountBinding(definition: nativeOfferPlacementDefinition)
                .capture(),
        id: 'native_offer',
        originalResolver: const _ThrowingPaywall());
    final key = resolver.storeKey;
    final first = resolver.fresh(key, sendAssignmentKey: false);
    final queued = resolver.fresh(key, sendAssignmentKey: false);
    await first;
    // The queued fetch has started but has no answer yet.
    await Future<void>.delayed(Duration.zero);
    final afterFirst = resolver.fallbackReasonFor(key);
    second.complete();
    await queued;
    expect(afterFirst, 'serverError');
    expect(resolver.fallbackReasonFor(key), 'unavailable');
  });

  testWidgets(
      'a first-route flow mount reaches the service when other surfaces '
      'draw other widgets', (tester) async {
    final requests = <PlacementBatchModeV1>[];
    final reports = _configure(_Server.nothingPublished, const {},
        requests: requests, extraSurfaces: [_otherVocabularyDefinition()]);
    final failures = <FlowUnavailableError>[];
    await tester.pumpWidget(_RebuildingHost(failures: failures));
    await _finish(tester);
    final shown = find.text('Preferences original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(shown, 1, reason: failures.toString());
    expect(requests, contains(PlacementBatchModeV1.mount));
    _expectReportedFallback(reports, 'unavailable');
  });
}

void _expectOneMountRequest(List<PlacementBatchModeV1> requests) => expect(
    requests.where((mode) => mode == PlacementBatchModeV1.mount), hasLength(1));

bool _reported(List<SurfaceResolutionReport> reports, String reason) =>
    reports.any((report) =>
        report.source == SurfaceResolutionSource.bundled &&
        report.reason == reason);

void _expectReportedFallback(
    List<SurfaceResolutionReport> reports, String reason) {
  expect(
      reports.where((report) =>
          report.source == SurfaceResolutionSource.bundled &&
          report.reason == reason),
      isNotEmpty,
      reason: reports.toString());
}

List<SurfaceResolutionReport> _configure(
    _Server server, Set<SurfaceRefreshTrigger> liveRefresh,
    {List<PlacementBatchModeV1>? requests,
    Duration delay = Duration.zero,
    void Function(bool started)? onMountRequest,
    List<RestageSurfaceRef> extraSurfaces = const []}) {
  final reports = <SurfaceResolutionReport>[];
  Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://example.com',
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
      surfaces: [
        nativeClassFlowPlacementDefinition(),
        nativeNoticePlacementDefinition(),
        nativeOfferPlacementDefinition(),
        ...extraSurfaces,
      ],
      liveRefresh: liveRefresh,
      onSurfaceResolution: reports.add);
  debugResetInstallObservations();
  debugSetOsVersion(19);
  SurfaceMeteringKeyProvider.clear();
  Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
  final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (request.url.path != '/sdk/v1/placements/resolve') {
          return http.Response('', 404);
        }
        final batch =
            PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes);
        requests?.add(batch.mode);
        final mount = batch.mode == PlacementBatchModeV1.mount;
        if (mount) onMountRequest?.call(true);
        try {
          await Future<void>.delayed(delay);
        } finally {
          if (mount) onMountRequest?.call(false);
        }
        final decided = _nothingPublished(batch).canonicalBytes;
        switch (server) {
          case _Server.offline:
            throw http.ClientException('offline');
          case _Server.error:
            return http.Response('', 503);
          case _Server.throttled:
            return http.Response('', 429);
          case _Server.refused:
            return http.Response.bytes(
                PlacementBatchRefusedV1(
                        reason: PlacementBatchRefusalReasonV1.invalidAuthority)
                    .canonicalBytes,
                400);
          case _Server.transientRefusal:
            return http.Response.bytes(
                PlacementBatchRefusedV1(
                        reason: PlacementBatchRefusalReasonV1.invalidAuthority)
                    .canonicalBytes,
                503);
          case _Server.edgeDenied:
            return http.Response(
                jsonEncode({'error': 'hosted_access_denied'}), 403);
          case _Server.edgeNetwork:
            return http.Response(
                jsonEncode({'error': 'client_network_unavailable'}), 403);
          case _Server.nothingPublished:
            return http.Response.bytes(decided, 200);
          case _Server.malformed:
            final pretty = const JsonEncoder.withIndent(' ')
                .convert(jsonDecode(utf8.decode(decided)));
            return http.Response.bytes(utf8.encode(pretty), 200);
          case _Server.stale:
            _staleInstalls += 1;
            InstalledWidgetLibraries.add(RestageWidgetLibraries.fromVocabulary(
                core: {'Stale$_staleInstalls': buildText}));
            return http.Response.bytes(decided, 200);
        }
      }));
  Restage.debugRestageRpcClient = client;
  addTearDown(client.close);
  return reports;
}

PlacementBatchResolvedV1 _nothingPublished(PlacementBatchRequestV1 request) {
  final target = readPlacementDeliveryFixture().target;
  return PlacementBatchResolvedV1(
      request: request,
      expectedTarget: target,
      decisions: [
        for (final mount in request.mounts)
          PlacementBatchEntryV1.useFallback(
              PlacementMountDescriptorV1(
                  placement:
                      PlacementIdentityV1(target: target, key: mount.key),
                  hostContractHash: mount.hostContractHash),
              PlacementBatchRefusalReasonV1.unavailable,
              const []),
      ],
      artifacts: const []);
}

Future<void> _finish(WidgetTester tester,
    {bool resume = false, bool Function()? until}) async {
  // A cold start reports the app resumed while the first resolve is in flight.
  if (resume) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pump(const Duration(seconds: 2));
  // An abandoned response body releases on the real event loop.
  for (var i = 0; i < 100 && !(until?.call() ?? i >= 10); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Fails its fetch at once while local candidates outlast the deadline.
final class _RejectedFetch
    with RacedSurfaceReporting<ResolvedFlow>
    implements
        FlowResolver,
        ActiveArmFlowResolver,
        RacedSurfaceResolver<ResolvedFlow> {
  @override
  bool get activeArmEnabled => true;

  @override
  SurfaceArtifactStore get store => MemorySurfaceArtifactStore();

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      throw StateError('Only the raced root is resolved.');

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) =>
      resolve(flow);

  @override
  Future<ResolvedFlow?> fresh(SurfaceStoreKey key,
          {required bool sendAssignmentKey, Future<void>? keyDeadline}) async =>
      throw const SurfaceRequestPublicationRejected();

  @override
  Future<ResolvedFlow?> bestLocal(SurfaceStoreKey key) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return null;
  }
}

final class _Stale implements Exception {
  const _Stale();
}

final class _ThrowingFlow implements FlowResolver {
  const _ThrowingFlow();

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      throw const _Stale();
}

final class _ThrowingPaywall implements VariantResolver {
  const _ThrowingPaywall();

  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      throw const _Stale();
}

/// A surface whose widgets no other surface in this file draws.
GeneratedPlacementDefinition _otherVocabularyDefinition() {
  final host = readPlacementDeliveryFixture()
      .request
      .buildContract
      .contractsByHash
      .values
      .first;
  return GeneratedPlacementDefinition(
      defaultSurface: const PaywallRef('other_offer'),
      defaultSurfaceLocator: DeliverySurfaceLocatorV1(
          surfaceType: DeliverySurfaceTypeId('paywall'),
          slug: 'other_offer',
          family: const DeliveryFamilySelectorV1.general()),
      key: PlacementKeyV1.generatedDefault(
          surfaceType: DeliverySurfaceTypeId('paywall'), slug: 'other_offer'),
      hostContract: host,
      vocabulary: const SurfaceVocabulary(
          widgets: RestageWidgetLibraries.fromVocabulary(
              core: {'OtherOfferBadge': buildText})));
}

/// An app's first route: a flow mount whose parent rebuilds after the first
/// frame with a new completion closure.
final class _RebuildingHost extends StatefulWidget {
  const _RebuildingHost({required this.failures});

  final List<FlowUnavailableError> failures;

  @override
  State<_RebuildingHost> createState() => _RebuildingHostState();
}

final class _RebuildingHostState extends State<_RebuildingHost> {
  var _builds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => mounted ? setState(() {}) : null);
  }

  @override
  Widget build(BuildContext context) {
    _builds += 1;
    final builds = _builds;
    return MaterialApp(
        home: NativeClassFlowSurface(
            onFlowUnavailable: widget.failures.add,
            onComplete: (_) => debugPrint('completed after $builds builds')));
  }
}
