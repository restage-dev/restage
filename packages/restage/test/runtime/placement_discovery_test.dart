import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/placement_discovery.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  final discovery = PlacementDiscovery.instance;
  final reports = <PlacementDiscoveryReportV1>[];

  void pin(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        discovery.reset();
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
      },
    );
  });
  tearDown(discovery.reset);

  pin('drawn duplicate occurrences report only declared public facts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      key: const ValueKey('sentinel_context'),
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/sentinel-route'),
          builder: (_) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Mount(child: SizedBox(width: 80, height: 20)),
              _Mount(child: SizedBox(width: 80, height: 30)),
              Text('sentinel-widget-text'),
            ],
          ),
        ),
      ],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/sentinel-route'),
        builder: (_) => const SizedBox(),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(reports, hasLength(1));
    final report = reports.single;
    expect(report.mounts, hasLength(1));
    expect(report.bounds.map((bound) => bound.occurrenceIndex), [0, 1]);
    expect(report.bounds.map((bound) => bound.logicalBounds.y), [0, 20]);
    expect(report.bounds.map((bound) => bound.logicalBounds.height), [20, 30]);
    expect(
        report.appBuildContractHash, report.buildContract.appBuildContractHash);
    final wire = utf8.decode(report.canonicalBytes);
    expect(wire, isNot(contains('sentinel')));
    expect(report.toJson().keys.toSet(),
        {'mounts', 'buildContract', 'appBuildContractHash', 'bounds'});
    expect(report.bounds.first.toJson().keys.toSet(), {
      'key',
      'hostContractHash',
      'logicalBounds',
      'logicalViewport',
      'occurrenceIndex'
    });

    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(reports, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  pin('reports require committed paint and registration disposal clears bounds',
      (tester) async {
    final key = GlobalKey<_MountState>();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: _Mount(
            key: key,
            painted: false,
            child: const SizedBox(width: 20, height: 10)),
      ),
    ));
    await tester.pump();
    expect(reports, isEmpty);

    key.currentState!.registration.markPainted();
    await tester.pump();
    expect(reports, hasLength(1));
    key.currentState!.registration.markPainted();
    await tester.pump();
    expect(reports, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 251));
    expect(reports, hasLength(2));
    expect(reports.last.bounds, isEmpty);
  });

  pin('continuous scroll changes coalesce into one settled report',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          height: 100,
          child: SingleChildScrollView(
            controller: scroll,
            child: const Column(children: [
              _Mount(child: SizedBox(width: 80, height: 30)),
              SizedBox(height: 500),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(reports, hasLength(1));

    for (var step = 1; step <= 20; step++) {
      scroll.jumpTo(step.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    expect(reports, hasLength(1));
    await tester.pump(const Duration(milliseconds: 251));
    expect(reports, hasLength(2));
    expect(reports.last.bounds.single.logicalBounds.y, -20);
  });

  pin('logical bounds remove fractional DPR while retaining rotation and offscreen positions',
      (tester) async {
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(300, 180);
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (value) {
        context = value;
        return Align(
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: const Offset(-5.5, 7.25),
            child: Transform.rotate(
              angle: math.pi / 2,
              alignment: Alignment.topLeft,
              child: const _Mount(child: SizedBox(width: 20, height: 10)),
            ),
          ),
        );
      }),
    ));
    await tester.pump();
    final view = placementOwningView(context.findRenderObject())!;
    final frame = discovery.captureFrame(view: view);
    expect(frame.viewport.width, 200);
    expect(frame.viewport.height, 120);
    final rect = frame.mounts.single.rect;
    expect(rect.x, -15.5);
    expect(rect.y, 7.25);
    expect(rect.width, 10);
    expect(rect.height, 20);
  });

  pin('renderless registration preserves Flex ParentData ancestry',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        _Mount(child: Expanded(child: SizedBox(height: 20))),
        SizedBox(width: 25),
      ]),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(reports.single.bounds.single.logicalBounds.width, 775);
  });

  pin('two owning views retain their own logical geometry and duplicate identities',
      (tester) async {
    final secondary = _SecondaryView(tester.view)
      ..devicePixelRatio = 2
      ..physicalSize = const Size(160, 140);
    late BuildContext firstContext;
    late BuildContext secondContext;
    await tester.pumpWidget(
        ViewCollection(views: [
          View(
              view: tester.view,
              child: Builder(builder: (context) {
                firstContext = context;
                return const Directionality(
                    textDirection: TextDirection.ltr,
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: _Mount(child: SizedBox(width: 12, height: 9))));
              })),
          View(
              view: secondary,
              child: Builder(builder: (context) {
                secondContext = context;
                return const Directionality(
                    textDirection: TextDirection.ltr,
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: _Mount(child: SizedBox(width: 25, height: 17))));
              })),
        ]),
        wrapWithView: false);
    await tester.pump();
    await tester.pump();
    final first = discovery.captureFrame(
        view: placementOwningView(firstContext.findRenderObject())!);
    final second = discovery.captureFrame(
        view: placementOwningView(secondContext.findRenderObject())!);
    expect(first.mounts.single.rect.width, 12);
    expect(second.mounts.single.rect.width, 25);
    expect(second.viewport.width, 80);
    expect(second.viewport.height, 70);
    expect(reports.single.bounds.map((bound) => bound.occurrenceIndex).toSet(),
        {0, 1});
    expect(
        utf8.decode(reports.single.canonicalBytes), isNot(contains('viewId')));
  });

  pin('observed build inputs replace the offline snapshot without dropping mounts',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (value) {
      context = value;
      return const _Mount(child: SizedBox(width: 20, height: 10));
    }));
    await tester.pump();
    final view = placementOwningView(context.findRenderObject())!;
    final before = discovery.captureFrame(view: view);
    expect(before.buildContract.buildOrdinal, isNull);
    discovery.updateBuildInputs(platform: 'android', buildOrdinal: 42);
    final after = discovery.captureFrame(view: view);
    expect(after.buildContract.buildOrdinal, 42);
    expect(after.mounts, hasLength(1));
    expect(after.buildContract.appBuildContractHash,
        isNot(before.buildContract.appBuildContractHash));
    expect(before.isCurrent, isFalse);
  });

  pin('a report carries the display version outside the build contract',
      (tester) async {
    discovery.updateBuildInputs(
        platform: 'android', buildOrdinal: 42, appVersion: '2.4.1');
    await tester
        .pumpWidget(const _Mount(child: SizedBox(width: 20, height: 10)));
    await tester.pump();
    await tester.pump();
    final report = reports.single;
    expect(report.appVersion, '2.4.1');
    expect(report.buildContract.toJson().toString(), isNot(contains('2.4.1')));
    discovery.updateBuildInputs(
        platform: 'android', buildOrdinal: 42, appVersion: '2.4.2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reports.last.appVersion, '2.4.2');
    discovery.updateBuildInputs(platform: 'android', buildOrdinal: 43);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reports.last.buildContract.buildOrdinal, 43);
    expect(reports.last.appVersion, '2.4.2');
  });

  pin('remembered declarations merge the batch roster without dropping live occurrences',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (value) {
      context = value;
      return const _Mount(child: SizedBox(width: 20, height: 10));
    }));
    await tester.pump();
    final view = placementOwningView(context.findRenderObject())!;
    final before = discovery.captureFrame(view: view);
    final host = _host();
    final remembered = PlacementMountRequestV1(
        key: PlacementKeyV1.named(slug: 'seen_card'),
        hostContractHash: host.contentHash);
    discovery.rememberDeclarations(
        mounts: [remembered], contractsByHash: {host.contentHash: host});
    final after = discovery.captureFrame(view: view);
    expect(after.mounts, hasLength(1));
    expect(after.mounts.single.key.slug, 'home_card');
    expect(after.buildContract.mounts.map((mount) => mount.key.slug),
        ['home_card', 'seen_card']);
    expect(before.isCurrent, isFalse);
    await tester.pump();
    final settled = discovery.captureFrame(view: view);
    discovery.rememberDeclarations(
        mounts: [remembered], contractsByHash: {host.contentHash: host});
    expect(settled.isCurrent, isTrue);
    expect(discovery.buildContract, settled.buildContract);
  });
}

InstalledCapability _capability() =>
    InstalledCapability(builtInCatalogVersion: 1, installedLibraries: const []);

SurfaceHostContractV1 _host() => SurfaceHostContractV1(
    hosting: const SurfaceHostingV1(
        contentKind: SurfaceContentKindV1.single,
        presentation: SurfacePresentationV1.inline),
    providedContext: const SurfaceScreenHostDataSchema.empty(),
    handledEvents: SurfaceScreenEventSchema(events: const []));

class _Mount extends StatefulWidget {
  const _Mount({super.key, required this.child, this.painted = true});
  final Widget child;
  final bool painted;

  @override
  State<_Mount> createState() => _MountState();
}

class _MountState extends State<_Mount> {
  late final PlacementDiscoveryRegistration registration;

  @override
  void initState() {
    super.initState();
    final host = _host();
    registration = PlacementDiscovery.instance.register(
      context: context,
      mount: PlacementMountRequestV1(
          key: PlacementKeyV1.named(slug: 'home_card'),
          hostContractHash: host.contentHash),
      hostContract: host,
      isCurrent: () => mounted,
    );
    if (widget.painted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => registration.markPainted());
    }
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
