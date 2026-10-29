import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
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
    await _settle(tester);

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

  pin('frames that change nothing rebuild neither the build nor the report',
      (tester) async {
    final ticker = ValueNotifier(0);
    addTearDown(ticker.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        const _Mount(child: SizedBox(width: 80, height: 20)),
        // An animation elsewhere on screen draws every frame.
        ValueListenableBuilder<int>(
            valueListenable: ticker,
            builder: (_, value, __) => SizedBox(height: 10, width: value + 1)),
      ]),
    ));
    await _settle(tester);
    expect(reports, hasLength(1));
    final build = discovery.buildContract;
    for (var frame = 1; frame <= 30; frame++) {
      ticker.value = frame;
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(identical(discovery.buildContract, build), isTrue);
    expect(reports, hasLength(1));

    discovery.updateBuildInputs(platform: 'android', buildOrdinal: 7);
    expect(identical(discovery.buildContract, build), isFalse);
    expect(discovery.buildContract.buildOrdinal, 7);
  });

  pin('an unpainted mount reports its declaration and bounds follow paint',
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
    await tester.pump(const Duration(milliseconds: 251));
    expect(reports, hasLength(1));
    expect(reports.single.mounts.single.key.slug, 'home_card');
    expect(reports.single.bounds, isEmpty);

    key.currentState!.registration.markPainted();
    await _settle(tester);
    expect(reports, hasLength(2));
    expect(reports.last.bounds, hasLength(1));
    key.currentState!.registration.markPainted();
    await tester.pump();
    expect(reports, hasLength(2));

    // Unmounting adds nothing the server does not already hold.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 251));
    expect(reports, hasLength(2));
  });

  pin('scrolling a reported mount sends no further report', (tester) async {
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
    await _settle(tester);
    expect(reports, hasLength(1));

    for (var step = 1; step <= 20; step++) {
      scroll.jumpTo(step.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 251));
    for (var step = 21; step <= 40; step++) {
      scroll.jumpTo(step.toDouble());
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(reports, hasLength(1));
    expect(reports.single.bounds.single.logicalBounds.y, 0);
  });

  pin('a refused report is retried, and once accepted not sent again',
      (tester) async {
    final attempts = <PlacementDiscoveryReportV1>[];
    var accept = false;
    discovery.configure(
      installedCapability: _capability,
      platform: 'android',
      report: (report) async {
        attempts.add(report);
        return accept;
      },
    );
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
    await _settle(tester);
    expect(attempts, hasLength(1));

    // The first send was refused; the retry carries the same facts.
    accept = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(attempts, hasLength(2));
    expect(attempts.last.bounds, hasLength(1));

    for (var step = 1; step <= 20; step++) {
      scroll.jumpTo(step.toDouble());
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(seconds: 31));
    expect(attempts, hasLength(2));
  });

  pin('a new viewport size or a new mount reports once, a remount never',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app({required bool second, required bool first}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            if (first) const _Mount(child: SizedBox(width: 80, height: 30)),
            if (second)
              const _Mount(
                  slug: 'promo', child: SizedBox(width: 80, height: 30)),
          ]),
        );
    await tester.pumpWidget(app(first: true, second: false));
    await _settle(tester);
    expect(reports, hasLength(1));

    await tester.pumpWidget(app(first: false, second: false));
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pumpWidget(app(first: true, second: false));
    await _settle(tester);
    expect(reports, hasLength(1));

    tester.view.physicalSize = const Size(800, 400);
    await _settle(tester);
    expect(reports, hasLength(2));
    expect(reports.last.bounds.single.logicalViewport.width, 800);

    // Back to portrait: the server must not keep the landscape bounds.
    tester.view.physicalSize = const Size(400, 800);
    await _settle(tester);
    expect(reports, hasLength(3));
    expect(reports.last.bounds.single.logicalViewport.width, 400);

    await tester.pumpWidget(app(first: true, second: true));
    await _settle(tester);
    expect(reports, hasLength(4));
    expect(reports.last.mounts.map((mount) => mount.key.slug).toSet(),
        {'home_card', 'promo'});
  });

  pin('a pushed route reports its settled bounds, never a transition frame',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Align(
        alignment: Alignment.topLeft,
        child: _Mount(child: SizedBox(width: 80, height: 30)),
      ),
    ));
    await _settle(tester);
    expect(reports, hasLength(1));

    unawaited(navigator.currentState!.push(CupertinoPageRoute<void>(
      builder: (_) => const Align(
        alignment: Alignment.topLeft,
        child: _Mount(slug: 'promo', child: SizedBox(width: 80, height: 30)),
      ),
    )));
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _settle(tester);
    expect([
      for (final report in reports)
        for (final bound in report.bounds) bound.logicalBounds.x
    ], everyElement(0));
    // The covered home route reports nothing from its offstage position.
    expect(reports.last.bounds.single.key.slug, 'promo');
  });

  pin('a re-layout reports the new settled bounds', (tester) async {
    Widget app(double top) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(children: [
              SizedBox(height: top),
              const _Mount(child: SizedBox(width: 80, height: 30)),
            ]),
          ),
        );
    await tester.pumpWidget(app(0));
    await _settle(tester);
    await tester.pumpWidget(app(300));
    await _settle(tester);
    await tester.pumpWidget(app(0));
    await _settle(tester);
    expect([for (final report in reports) report.bounds.single.logicalBounds.y],
        [0, 300, 0]);
  });

  pin('a placement on a later page reports where its page shows it',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pages = PageController();
    addTearDown(pages.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: PageView(controller: pages, children: const [
        SizedBox.expand(),
        Align(
          alignment: Alignment(0, -0.5),
          child: _Mount(child: SizedBox(width: 80, height: 30)),
        ),
      ]),
    ));
    unawaited(pages.animateToPage(1,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _settle(tester);
    expect(reports, hasLength(1));
    final bounds = reports.single.bounds.single.logicalBounds;
    expect((bounds.x, bounds.y), (160, 192.5));
  });

  pin('a placement in a pinned header stays put while the list scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: CustomScrollView(controller: scroll, slivers: [
        const SliverAppBar(
          pinned: true,
          title: _Mount(child: SizedBox(width: 80, height: 30)),
        ),
        SliverList.list(children: [
          for (var row = 0; row < 40; row++) const SizedBox(height: 100),
        ]),
      ]),
    ));
    await _settle(tester);
    final drawn = reports.single.bounds.single.logicalBounds.y;
    for (final offset in [100.0, 300.0, 900.0, 50.0]) {
      scroll.jumpTo(offset);
      await _settle(tester);
    }
    expect(reports, hasLength(1));
    expect(drawn, lessThan(56));
  });

  for (final (name, pinned) in [('pinned', true), ('unpinned', false)]) {
    pin('a placement in a collapsing $name header reports once across scroll stops',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(MaterialApp(
        home: CustomScrollView(controller: scroll, slivers: [
          SliverAppBar(
            pinned: pinned,
            expandedHeight: 240,
            flexibleSpace: const FlexibleSpaceBar(
              background: Align(
                child: _Mount(child: SizedBox(width: 80, height: 30)),
              ),
            ),
          ),
          SliverList.list(children: [
            for (var row = 0; row < 40; row++) const SizedBox(height: 100),
          ]),
        ]),
      ));
      await _settle(tester);
      for (final offset in [40.0, 90.0, 150.0, 400.0, 20.0, 0.0]) {
        scroll.jumpTo(offset);
        await _settle(tester);
      }
      expect(reports, hasLength(1));
      expect(reports.single.bounds.single.logicalBounds.y, 105);
    });
  }

  pin('a placement in a sticky header reports once across scroll stops',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(controller: scroll, slivers: [
        SliverList.list(children: [
          for (var row = 0; row < 5; row++) const SizedBox(height: 100),
        ]),
        const SliverPersistentHeader(pinned: true, delegate: _Header()),
        SliverList.list(children: [
          for (var row = 0; row < 40; row++) const SizedBox(height: 100),
        ]),
      ]),
    ));
    await _settle(tester);
    for (final offset in [100.0, 300.0, 600.0, 900.0, 200.0]) {
      scroll.jumpTo(offset);
      await _settle(tester);
    }
    expect(reports, hasLength(1));
    expect(reports.single.bounds.single.logicalBounds.y, 510);
  });

  pin('a header placement opened scrolled reports, then updates at the start',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController(initialScrollOffset: 150);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: CustomScrollView(controller: scroll, slivers: [
        const SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          flexibleSpace: FlexibleSpaceBar(
            background: Align(
              child: _Mount(child: SizedBox(width: 80, height: 30)),
            ),
          ),
        ),
        SliverList.list(children: [
          for (var row = 0; row < 40; row++) const SizedBox(height: 100),
        ]),
      ]),
    ));
    await _settle(tester);
    expect(reports, hasLength(1));
    expect(reports.single.bounds, hasLength(1));
    scroll.jumpTo(300);
    await _settle(tester);
    expect(reports, hasLength(1));
    scroll.jumpTo(0);
    await _settle(tester);
    expect(reports, hasLength(2));
    expect(reports.last.bounds.single.logicalBounds.y, 105);
  });

  pin('a placement below the fold reports its place in the content',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController(initialScrollOffset: 900);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(controller: scroll, children: [
        for (var row = 0; row < 12; row++) const SizedBox(height: 100),
        const _Mount(child: SizedBox(height: 100)),
        for (var row = 0; row < 20; row++) const SizedBox(height: 100),
      ]),
    ));
    await _settle(tester);
    scroll.jumpTo(700);
    await _settle(tester);
    expect(reports, hasLength(1));
    expect(reports.single.bounds.single.logicalBounds.y, 1200);
  });

  pin('a still placement reports while another never stops moving',
      (tester) async {
    final motion = AnimationController(
        vsync: const TestVSync(), duration: const Duration(milliseconds: 400))
      ..repeat(reverse: true);
    addTearDown(motion.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(children: [
          const _Mount(slug: 'still', child: SizedBox(width: 80, height: 30)),
          AnimatedBuilder(
            animation: motion,
            builder: (_, child) => Transform.translate(
                offset: Offset(100 * motion.value, 0), child: child),
            child: const _Mount(
                slug: 'moving', child: SizedBox(width: 80, height: 30)),
          ),
        ]),
      ),
    ));
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(reports, isNotEmpty);
    expect(reports.last.mounts.map((mount) => mount.key.slug).toSet(),
        {'still', 'moving'});
    expect(reports.last.bounds.map((bound) => bound.key.slug), ['still']);
    motion.stop();
  });

  pin('a mount painted soon after it registers reports once, with bounds',
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
    await tester.pump(const Duration(milliseconds: 100));
    key.currentState!.registration.markPainted();
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(reports, hasLength(1));
    expect(reports.single.bounds, hasLength(1));
  });

  pin('a launch reports its facts again on a new UTC day', (tester) async {
    var now = DateTime.utc(2026, 10, 27, 23, 59);
    discovery.configure(
      installedCapability: _capability,
      platform: 'android',
      now: () => now,
      report: (report) async {
        reports.add(report);
        return true;
      },
    );
    await tester
        .pumpWidget(const _Mount(child: SizedBox(width: 20, height: 10)));
    await _settle(tester);
    tester.binding.scheduleFrame();
    await _settle(tester);
    expect(reports, hasLength(1));

    // Any later frame observes again.
    now = now.add(const Duration(minutes: 2));
    tester.binding.scheduleFrame();
    await _settle(tester);
    expect(reports, hasLength(2));
    expect(reports.last.bounds, hasLength(1));
  });

  for (final ordinal in [7, null]) {
    pin('a report waits for the observed build inputs (ordinal $ordinal)',
        (tester) async {
      discovery.configure(
        installedCapability: _capability,
        platform: 'android',
        report: (report) async {
          reports.add(report);
          return true;
        },
        buildInputsPending: true,
      );
      await tester
          .pumpWidget(const _Mount(child: SizedBox(width: 20, height: 10)));
      await _settle(tester);
      expect(reports, isEmpty);

      discovery.updateBuildInputs(platform: 'android', buildOrdinal: ordinal);
      await _settle(tester);
      expect(reports.single.buildContract.buildOrdinal, ordinal);
    });
  }

  pin('a new build reports a remounted placement again', (tester) async {
    await tester
        .pumpWidget(const _Mount(child: SizedBox(width: 20, height: 10)));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    expect(reports, hasLength(1));

    discovery.updateBuildInputs(platform: 'android', buildOrdinal: 7);
    await _settle(tester);
    expect(reports, hasLength(2));
    expect(reports.last.mounts, isEmpty);

    await tester
        .pumpWidget(const _Mount(child: SizedBox(width: 20, height: 10)));
    await _settle(tester);
    expect(reports, hasLength(3));
    expect(reports.last.buildContract.buildOrdinal, 7);
    expect(reports.last.mounts.single.key.slug, 'home_card');
    expect(reports.last.bounds, hasLength(1));
  });

  pin('a report accepted after a new configuration never suppresses its first report',
      (tester) async {
    final inFlight = Completer<bool>();
    discovery.configure(
      installedCapability: _capability,
      platform: 'android',
      report: (_) => inFlight.future,
    );
    await tester.pumpWidget(const _Mount(
        key: ValueKey('first'), child: SizedBox(width: 20, height: 10)));
    await _settle(tester);

    discovery.configure(
      installedCapability: _capability,
      platform: 'android',
      report: (report) async {
        reports.add(report);
        return true;
      },
    );
    await tester.pumpWidget(const _Mount(
        key: ValueKey('second'), child: SizedBox(width: 20, height: 10)));
    inFlight.complete(true);
    await _settle(tester);
    expect(reports, hasLength(1));
    expect(reports.single.bounds, hasLength(1));
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
    await _settle(tester);
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
    await _settle(tester);
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
    await _settle(tester);
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

// The settle window, then the report debounce.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 251));
  await tester.pump(const Duration(milliseconds: 251));
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
  const _Mount({
    super.key,
    required this.child,
    this.painted = true,
    this.slug = 'home_card',
  });
  final Widget child;
  final bool painted;
  final String slug;

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
          key: PlacementKeyV1.named(slug: widget.slug),
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

class _Header extends SliverPersistentHeaderDelegate {
  const _Header();

  @override
  double get minExtent => 50;

  @override
  double get maxExtent => 50;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      const Align(
        alignment: Alignment.centerLeft,
        child: _Mount(child: SizedBox(width: 80, height: 30)),
      );

  @override
  bool shouldRebuild(_Header oldDelegate) => false;
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
