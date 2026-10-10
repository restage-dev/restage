import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/placement_authoring.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/authoring/placement_screen_capture.dart'
    show debugPlacementScreenRasterizer;
import 'package:restage/src/runtime/placement_discovery.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_uploader.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';

void main() {
  final discovery = PlacementDiscovery.instance;
  final reports = <PlacementDiscoveryReportV1>[];

  void pin(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugPlacementScreenRasterizer = null;
        discovery.reset();
        Restage.debugReset();
        sharedSurfaceArtifactStore = null;
      }
    });
  }

  setUp(() {
    reports.clear();
    discovery.configure(
        installedCapability: _capability,
        platform: 'android',
        report: (report) async {
          reports.add(report);
          return true;
        });
  });
  tearDown(() {
    debugPlacementScreenRasterizer = null;
    discovery.reset();
  });

  pin('actual offline placement hosts export duplicates before any remote resolve',
      (tester) async {
    _configureSdk();
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(180, 150);
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (value) {
        context = value;
        return const ColoredBox(
          color: Color(0xffffffff),
          child: Align(
            alignment: Alignment.topLeft,
            child: _OfflinePlacementPair(),
          ),
        );
      }),
    ));
    await _drainSdk(tester);
    final pending = capturePlacementScreenSample(
        context: context, screenLabel: 'Home sample', pixelRatio: 1.25);
    await tester.pump();
    final sample = (await tester.runAsync(() => pending))!;
    expect(sample.capture.mounts, hasLength(2));
    expect(sample.capture.mounts.map((mount) => mount.occurrenceIndex), [0, 1]);
    expect(sample.capture.mounts.map((mount) => mount.key.slug),
        ['home_card', 'home_card']);
    expect(sample.capture.mounts.map((mount) => mount.rect.y), [0, 20]);
    expect(sample.capture.mounts.map((mount) => mount.rect.height), [20, 30]);
    expect(sample.capture.mounts.map((mount) => mount.rect.width), [80, 80]);
    expect(sample.capture.buildContract.mounts, hasLength(1));
    expect(sample.capture.buildContract.mounts.single.defaultSurface, isNull);
    expect((sample.capture.pngWidth, sample.capture.pngHeight), (150, 125));
    expect(Restage.debugRestageRpcClient, isNull);
    expect(tester.takeException(), isNull);
    await _exportFixture(tester, sample);
  });

  pin('actual generated host capture exports without extra resolve report or upload requests',
      (tester) async {
    _configureSdk(configured: true);
    final requests = <http.Request>[];
    final events = <RestageEvent>[];
    final recordingClient = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/sdk/v1/placements/resolve') {
        final batch =
            PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes);
        return http.Response.bytes(
            placementFixtureResponse(batch).canonicalBytes, 200);
      }
      return http.Response('', 204);
    });
    final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_capture',
        httpClient: recordingClient);
    Restage.debugRestageRpcClient = client;
    SurfaceDeliveryReceiptUploader.instance.debugHttpClient = recordingClient;
    addTearDown(client.close);
    late BuildContext context;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (value) {
        context = value;
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 80,
            height: 25,
            child: RestagePaywall(
              id: 'original_offer',
              onEvent: events.add,
              placementBinding: const PlacementMountBinding(
                  definition: _generatedOffer, name: 'offer_card'),
              fallbackBuilder: (_) => const SizedBox(width: 80, height: 25),
            ),
          ),
        );
      }),
    ));
    await _drainSdk(tester);
    await tester.runAsync(SurfaceDeliveryReceiptUploader.instance.flush);
    expect(find.text('Welcome'), findsOneWidget,
        reason: 'requests: ${requests.map((request) => request.url.path)}, '
            'events: $events');
    expect(
        requests.where(
            (request) => request.url.path == '/sdk/v1/placements/resolve'),
        isNotEmpty);
    final reportRequests = requests
        .where((request) => request.url.path == '/sdk/v1/placements/report');
    expect(reportRequests, isNotEmpty);
    final lastReport = PlacementDiscoveryReportV1.fromCanonicalBytes(
        reportRequests.last.bodyBytes);
    final count = requests.length;
    final pending = capturePlacementScreenSample(
        context: context, screenLabel: 'Offer sample');
    await tester.pump();
    final sample = (await tester.runAsync(() => pending))!;
    expect(sample.capture.mounts.single.key.slug, 'offer_card');
    expect(sample.capture.mounts.single.rect.width, 80);
    expect(sample.capture.mounts.single.rect.height, 25);
    expect(sample.capture.buildContract.mounts.single.defaultSurface,
        _generatedOffer().defaultSurfaceLocator);
    expect(
        sample.capture.appBuildContractHash, lastReport.appBuildContractHash);
    expect(sample.capture.buildContract.buildOrdinal, 42);
    final manifest = sample.toManifest(target: _target());
    expect(
        validatePlacementScreenSample(
                manifest: manifest, pngBytes: sample.pngBytes)
            .reviewDigest,
        manifest.reviewDigest);
    await tester.pump(const Duration(milliseconds: 300));
    expect(requests, hasLength(count));
    expect(tester.takeException(), isNull);
  });

  pin('actual full-view PNG preserves fractional DPR ceil duplicate bounds and local export',
      (tester) async {
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(150.375, 120.75);
    addTearDown(tester.view.reset);
    final smallBoundary = GlobalKey();
    late BuildContext context;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (value) {
          context = value;
          return Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                  key: smallBoundary,
                  child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Mount(
                            child: ColoredBox(
                                color: Colors.red,
                                child: SizedBox(width: 30, height: 10))),
                        _Mount(
                            child: ColoredBox(
                                color: Colors.green,
                                child: SizedBox(width: 30, height: 15))),
                      ])));
        })));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final requestCount = reports.length;
    ui.Image? rasterImage;
    debugPlacementScreenRasterizer = (rasterize) async {
      rasterImage = await rasterize();
      return rasterImage!;
    };
    final pending = capturePlacementScreenSample(
        context: context, screenLabel: 'Home sample', pixelRatio: 1.25);
    await tester.pump();
    final sample = (await tester.runAsync(() => pending))!;

    expect(sample.pngBytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final png = validatePlacementScreenSamplePng(sample.pngBytes);
    expect(png.width, 126);
    expect(png.height, 101);
    final capture = sample.toCaptureManifest();
    expect(capture.captureScope, PlacementScreenCaptureScopeV1.flutterView);
    expect(capture.logicalViewport.width, 100.25);
    expect(capture.logicalViewport.height, 80.5);
    expect((capture.rasterScale.numerator, capture.rasterScale.denominator),
        (5, 4));
    expect(capture.mounts.map((mount) => mount.occurrenceIndex), [0, 1]);
    expect(capture.mounts.map((mount) => mount.rect.y), [0, 10]);
    expect(capture.mounts.map((mount) => mount.rect.height), [10, 15]);
    expect(capture.pngSha256, png.contentHash);
    expect(capture.pngByteLength, png.byteLength);
    expect(capture.buildContract.buildOrdinal, isNull);
    expect(capture.buildContract.mounts, hasLength(1));
    expect(PlacementScreenCaptureV1.fromCanonicalBytes(capture.canonicalBytes),
        capture);
    expect(utf8.decode(capture.canonicalBytes), isNot(contains('target')));
    expect(() => sample.pngBytes[0] = 0, throwsUnsupportedError);
    expect(() => sample.pngBytes.buffer.asUint8List()[0] = 0,
        throwsUnsupportedError);
    expect(rasterImage!.debugDisposed, isTrue);
    final manifest = sample.toManifest(target: _target());
    expect(
        validatePlacementScreenSample(
                manifest: manifest, pngBytes: sample.pngBytes)
            .reviewDigest,
        manifest.reviewDigest);
    expect(reports.length, requestCount);
  });

  pin('explicit boundary captures only its own frame and keeps offscreen geometry',
      (tester) async {
    final boundary = GlobalKey();
    late BuildContext context;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (value) {
          context = value;
          return Align(
              alignment: Alignment.topLeft,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                RepaintBoundary(
                    key: boundary,
                    child: SizedBox(
                        width: 40.2,
                        height: 30.1,
                        child: Transform.translate(
                            offset: const Offset(-5.5, 2.25),
                            child: const Align(
                                alignment: Alignment.topLeft,
                                child: _Mount(
                                    child: SizedBox(width: 20, height: 10)))))),
                const _Mount(child: SizedBox(width: 20, height: 12)),
              ]));
        })));
    await tester.pump();
    final pending = capturePlacementScreenSample(
        context: context,
        screenLabel: 'Card sample',
        repaintBoundaryKey: boundary,
        pixelRatio: 1.5);
    await tester.pump();
    final sample = (await tester.runAsync(() => pending))!;
    final capture = sample.capture;
    expect(
        capture.captureScope, PlacementScreenCaptureScopeV1.explicitBoundary);
    expect(capture.mounts, hasLength(1));
    expect(capture.mounts.single.rect.x, -5.5);
    expect(capture.mounts.single.rect.y, 2.25);
    expect(capture.mounts.single.clipping, SampleClipping.clipped);
    expect(capture.pngWidth, 61);
    expect(capture.pngHeight, 46);
  });

  pin('capture uses fresh same-frame bounds rather than latest runtime report',
      (tester) async {
    late BuildContext context;
    late StateSetter update;
    var offset = 0.0;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (value) {
          context = value;
          return StatefulBuilder(builder: (_, setState) {
            update = setState;
            return Align(
                alignment: Alignment.topLeft,
                child: Transform.translate(
                    offset: Offset(offset, 0),
                    child:
                        const _Mount(child: SizedBox(width: 20, height: 10))));
          });
        })));
    await tester.pump();
    await tester.pump();
    expect(reports.single.bounds.single.logicalBounds.x, 0);
    update(() => offset = 17.5);
    await tester.pump();
    final pending = capturePlacementScreenSample(
        context: context, screenLabel: 'Moved card');
    await tester.pump();
    final sample = (await tester.runAsync(() => pending))!;
    expect(sample.capture.mounts.single.rect.x, 17.5);
    expect(reports.single.bounds.single.logicalBounds.x, 0);
  });

  for (final change in [
    'geometry',
    'subpixel geometry',
    'selection',
    'build',
    'view',
    'subpixel viewport',
  ]) {
    pin('refuses $change changes during actual raster and disposes image',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(100, 80);
      addTearDown(tester.view.reset);
      late BuildContext context;
      late StateSetter update;
      var offset = 0.0;
      var current = true;
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (value) {
            context = value;
            return StatefulBuilder(builder: (_, setState) {
              update = setState;
              return Align(
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                      offset: Offset(offset, 0),
                      child: _Mount(
                          isCurrent: () => current,
                          child: const SizedBox(width: 20, height: 10))));
            });
          })));
      await tester.pump();
      final entered = Completer<void>();
      final resume = Completer<void>();
      ui.Image? image;
      debugPlacementScreenRasterizer = (rasterize) async {
        image = await rasterize();
        entered.complete();
        await resume.future;
        return image!;
      };
      final pending = capturePlacementScreenSample(
          context: context, screenLabel: 'Pending sample');
      final refused = expectLater(pending, throwsFormatException);
      await tester.pump();
      await tester.runAsync(() => entered.future);
      switch (change) {
        case 'geometry':
          update(() => offset = 5);
        case 'subpixel geometry':
          update(() => offset = 0.0001);
        case 'selection':
          current = false;
        case 'build':
          discovery.updateBuildInputs(platform: 'android', buildOrdinal: 2);
        case 'view':
          tester.view.physicalSize = const Size(110, 80);
        case 'subpixel viewport':
          tester.view.physicalSize = const Size(100.0001, 80);
      }
      await tester.pump();
      resume.complete();
      await tester.runAsync(() => refused);
      expect(image!.debugDisposed, isTrue);
    });
  }

  pin('secondary view capture uses the owning raster instead of the first view',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(120, 90);
    addTearDown(tester.view.reset);
    final secondary = _SecondaryView(tester.view)
      ..devicePixelRatio = 1.5
      ..physicalSize = const Size(120, 105);
    late BuildContext secondaryContext;
    await tester.pumpWidget(
        ViewCollection(views: [
          View(view: tester.view, child: const ColoredBox(color: Colors.red)),
          View(
              view: secondary,
              child: Builder(builder: (context) {
                secondaryContext = context;
                return const Directionality(
                    textDirection: TextDirection.ltr,
                    child: ColoredBox(
                        color: Color(0xff0000ff),
                        child: Align(
                            alignment: Alignment.topLeft,
                            child: _Mount(
                                child: SizedBox(width: 20, height: 10)))));
              })),
        ]),
        wrapWithView: false);
    await tester.pump();
    final pending = capturePlacementScreenSample(
        context: secondaryContext,
        screenLabel: 'Second view',
        pixelRatio: 1.25);
    await tester.pump();
    final sample = (await tester.runAsync(() => pending))!;
    expect(sample.capture.logicalViewport.width, 80);
    expect(sample.capture.logicalViewport.height, 70);
    expect(sample.capture.pngWidth, 100);
    expect(sample.capture.pngHeight, 88);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(sample.pngBytes);
      final frame = await codec.getNextFrame();
      try {
        final bytes = (await frame.image.toByteData())!.buffer.asUint8List();
        expect(bytes.take(4), [0, 0, 255, 255]);
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  pin('native platform view frames refuse before image creation',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (value) {
      context = value;
      return PlatformViewSurface(
          controller: _NativeController(),
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          gestureRecognizers: const {});
    }));
    var rasterCalls = 0;
    debugPlacementScreenRasterizer = (rasterize) {
      rasterCalls++;
      return rasterize();
    };
    final pending = capturePlacementScreenSample(
        context: context, screenLabel: 'Native content');
    final refused = expectLater(pending, throwsUnsupportedError);
    await tester.pump();
    await refused;
    expect(rasterCalls, 0);
  });
}

void _configureSdk({bool configured = false}) {
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
      appName: 'capture',
      packageName: 'example.capture',
      version: '1',
      buildNumber: '42',
      buildSignature: '');
  Restage.debugReset();
  debugResetAppBuildOrdinal();
  debugResetOsVersion();
  sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
  Restage.configure(
      apiKey: configured ? 'rs_pk_capture' : null,
      baseUrl: configured ? 'https://example.com' : null,
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: configured);
  Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
  debugResetInstallObservations();
  debugSetOsVersion(19);
  SurfaceMeteringKeyProvider.clear();
}

Future<void> _drainSdk(WidgetTester tester) async {
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pump(Restage.renderDeadline);
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _exportFixture(
    WidgetTester tester, PlacementScreenSample sample) async {
  final output = Platform.environment['PLACEMENT_SAMPLE_OUTPUT_DIRECTORY'];
  if (output == null) return;
  await tester.runAsync(() async {
    final directory = await Directory(output).create(recursive: true);
    await File('${directory.path}/capture.png').writeAsBytes(sample.pngBytes);
    await File('${directory.path}/capture.json')
        .writeAsBytes(sample.capture.canonicalBytes);
    await File('${directory.path}/build-contract.json')
        .writeAsBytes(sample.capture.buildContract.canonicalBytes);
    await File('${directory.path}/manifest.json')
        .writeAsBytes(sample.toManifest(target: _target()).canonicalBytes);
  });
}

GeneratedPlacementDefinition _generatedOffer() =>
    RestagePaywall.generatedPlacementDefinition(
      id: 'original_offer',
      defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
              surfaceType: DeliverySurfaceTypeId('paywall'),
              slug: 'original_offer',
              family: const DeliveryFamilySelectorV1.general())
          .toJson(),
      hostContractJson: SurfaceHostContractV1(
          hosting: const SurfaceHostingV1(
              contentKind: SurfaceContentKindV1.single,
              presentation: SurfacePresentationV1.inline),
          providedContext: const SurfaceScreenHostDataSchema.empty(),
          handledEvents: SurfaceScreenEventSchema(events: const [])).toJson(),
    );

class _OfflinePlacementPair extends StatelessWidget {
  const _OfflinePlacementPair();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RestagePlacement(
              id: 'home_card',
              fallback: (_) => const ColoredBox(
                  color: Color(0xfff44336),
                  child: SizedBox(width: 80, height: 20))),
          RestagePlacement(
              id: 'home_card',
              fallback: (_) => const ColoredBox(
                  color: Color(0xff4caf50),
                  child: SizedBox(width: 80, height: 30))),
        ],
      );
}

InstalledCapability _capability() =>
    InstalledCapability(builtInCatalogVersion: 1, installedLibraries: const []);

TargetCoordinate _target() => TargetCoordinate(
    organizationId: OrganizationId(1),
    appId: ApplicationId(2),
    environmentTargetId: EnvironmentTargetId(3),
    namedEnvironmentId: NamedEnvironmentId(4),
    runtimePlane: RuntimePlane.sandbox);

class _Mount extends StatefulWidget {
  const _Mount({required this.child, this.isCurrent});
  final Widget child;
  final bool Function()? isCurrent;

  @override
  State<_Mount> createState() => _MountState();
}

class _MountState extends State<_Mount> {
  late final PlacementDiscoveryRegistration registration;

  @override
  void initState() {
    super.initState();
    final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.single,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []));
    registration = PlacementDiscovery.instance.register(
        context: context,
        mount: PlacementMountRequestV1(
            key: PlacementKeyV1.named(slug: 'home_card'),
            hostContractHash: host.contentHash),
        hostContract: host,
        isCurrent: () => mounted && (widget.isCurrent?.call() ?? true));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => registration.markPainted());
  }

  @override
  void dispose() {
    registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SecondaryView extends TestFlutterView {
  _SecondaryView(ui.FlutterView view)
      : super(
            view: view,
            platformDispatcher:
                view.platformDispatcher as TestPlatformDispatcher,
            display: view.display as TestDisplay);

  @override
  int get viewId => 100;

  @override
  void render(ui.Scene scene, {ui.Size? size}) {}

  @override
  void updateSemantics(ui.SemanticsUpdate update) {}
}

class _NativeController extends PlatformViewController {
  @override
  int get viewId => 42;
  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}
  @override
  Future<void> clearFocus() async {}
  @override
  Future<void> dispose() async {}
}
