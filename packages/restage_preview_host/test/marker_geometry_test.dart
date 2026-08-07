import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart'
    show
        RestageWidgetFactory,
        RestageWidgetLibraryRegistration,
        WidgetLibrary,
        kReservedPreviewConstructorName,
        kReservedPreviewLibraryName;
import 'package:restage_preview_host/src/geometry_registry.dart';
import 'package:restage_preview_host/src/marker_library.dart';
import 'package:restage_preview_host/src/protocol.dart' show RenderEnv;
import 'package:restage_preview_host/src/raw_rfw_render_surface.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

void main() {
  testWidgets(
    'marker attach/detach sweeps frame rects, retains zero size, and diffs',
    (tester) async {
      final frameKey = GlobalKey();
      late final GeometryRegistry registry;
      registry = GeometryRegistry(
        frameRenderBox: () =>
            frameKey.currentContext?.findRenderObject() as RenderBox?,
      );
      final snapshots = <Map<String, Rect>>[];
      registry.snapshots.listen(snapshots.add);

      Widget frame({required bool includeZero, required bool includeSized}) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: frameKey,
              width: 200,
              height: 150,
              child: Stack(
                children: <Widget>[
                  if (includeSized)
                    Positioned(
                      left: 10,
                      top: 20,
                      child: GeometryMarker(
                        path: '["main","children",0]',
                        registry: registry,
                        child: const SizedBox(width: 30, height: 40),
                      ),
                    ),
                  if (includeZero)
                    Positioned(
                      left: 80,
                      top: 90,
                      child: GeometryMarker(
                        path: '["main","children",1]',
                        registry: registry,
                        child: const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(frame(includeZero: true, includeSized: true));
      expect(registry.registeredPathCount, 2);
      expect(snapshots, hasLength(1));
      expect(
        snapshots.single['["main","children",0]'],
        const Rect.fromLTWH(10, 20, 30, 40),
      );
      expect(
        snapshots.single['["main","children",1]'],
        const Rect.fromLTWH(80, 90, 0, 0),
      );

      await tester.pump();
      expect(snapshots, hasLength(1), reason: 'idle sweep must be suppressed');

      await tester.pumpWidget(frame(includeZero: false, includeSized: true));
      expect(registry.registeredPathCount, 1);
      expect(snapshots, hasLength(2));
      expect(snapshots.last.keys, <String>['["main","children",0]']);

      await tester.pumpWidget(frame(includeZero: false, includeSized: false));
      expect(registry.registeredPathCount, 0);
      expect(snapshots, hasLength(3));
      expect(snapshots.last, isEmpty);

      registry.dispose();
    },
  );

  testWidgets('marker snapshots transform full scale and rotation bounds',
      (tester) async {
    final frameKey = GlobalKey();
    late final GeometryRegistry registry;
    registry = GeometryRegistry(
      frameRenderBox: () =>
          frameKey.currentContext?.findRenderObject() as RenderBox?,
    );
    addTearDown(registry.dispose);
    final snapshots = <Map<String, Rect>>[];
    registry.snapshots.listen(snapshots.add);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          key: frameKey,
          width: 200,
          height: 150,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 10,
                top: 20,
                child: Transform.scale(
                  scaleX: 2,
                  scaleY: 0.5,
                  alignment: Alignment.topLeft,
                  child: GeometryMarker(
                    path: '["main","children",0]',
                    registry: registry,
                    child: const SizedBox(width: 30, height: 40),
                  ),
                ),
              ),
              Positioned(
                left: 90,
                top: 20,
                child: Transform.rotate(
                  angle: math.pi / 2,
                  alignment: Alignment.topLeft,
                  child: GeometryMarker(
                    path: '["main","children",1]',
                    registry: registry,
                    child: const SizedBox(width: 30, height: 40),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(snapshots, hasLength(1));
    final scaled = snapshots.single['["main","children",0]']!;
    expect(scaled.left, closeTo(10, 1e-9));
    expect(scaled.top, closeTo(20, 1e-9));
    expect(scaled.width, closeTo(60, 1e-9));
    expect(scaled.height, closeTo(20, 1e-9));

    final rotated = snapshots.single['["main","children",1]']!;
    expect(rotated.left, closeTo(50, 1e-9));
    expect(rotated.top, closeTo(20, 1e-9));
    expect(rotated.width, closeTo(40, 1e-9));
    expect(rotated.height, closeTo(30, 1e-9));
  });

  test('coalesces scheduling and skips detached render boxes', () {
    final scheduled = <FrameCallback>[];
    final snapshots = <Map<String, Rect>>[];
    final registry = GeometryRegistry(
      frameRenderBox: () => null,
      schedulePostFrameCallback: scheduled.add,
    );
    addTearDown(registry.dispose);
    registry.snapshots.listen(snapshots.add);
    final first = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints.tightFor(
        width: 10,
        height: 10,
      ),
    );
    final second = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints.tightFor(
        width: 20,
        height: 20,
      ),
    );

    registry
      ..register('["main","children",0]', first)
      ..register('["main","children",1]', second);
    expect(scheduled, hasLength(1));

    scheduled.removeAt(0)(Duration.zero);
    expect(snapshots, isEmpty, reason: 'detached boxes must be skipped');
    expect(scheduled, hasLength(1), reason: 'active registry re-arms once');

    registry
      ..unregister('["main","children",0]', first)
      ..unregister('["main","children",1]', second);
    scheduled.removeAt(0)(Duration.zero);
    expect(snapshots, isEmpty, reason: 'unchanged empty snapshot is idle');
    expect(scheduled, isEmpty);
  });

  testWidgets('marker library exposes one strict passthrough builder',
      (tester) async {
    final registry = GeometryRegistry(frameRenderBox: () => null);
    addTearDown(registry.dispose);
    final library = buildMarkerWidgetLibrary(registry);
    expect(library.widgets.keys, <String>[kReservedPreviewConstructorName]);
    const child = SizedBox(width: 2, height: 3);
    final publicMarker = GeometryMarker(
      path: '["public"]',
      registry: registry,
      child: null,
    );
    expect(publicMarker, isA<SingleChildRenderObjectWidget>());
    expect(publicMarker.child, isNull);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(),
      ),
    );
    final built = library.widgets.entries.single.value(
      tester.element(find.byType(SizedBox).first),
      const _MarkerDataSource(
        path: '["main"]',
        childWidget: child,
      ),
    );
    expect(built, isNot(isA<RenderObjectWidget>()));
    expect(built, isNot(isA<GeometryMarker>()));
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: built),
    );
    await tester.pump();
    expect(find.byWidget(child), findsOneWidget);
    expect(registry.registeredPathCount, 1);

    expect(
      () => library.widgets.entries.single.value(
        tester.element(find.byType(SizedBox).first),
        const _MarkerDataSource(path: null, childWidget: child),
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'renderless marker replaces descendant registration without duplicates',
    (tester) async {
      final frameKey = GlobalKey();
      final registry = GeometryRegistry(
        frameRenderBox: () =>
            frameKey.currentContext?.findRenderObject() as RenderBox?,
      );
      addTearDown(registry.dispose);
      final builder = buildMarkerWidgetLibrary(registry).widgets.values.single;

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));
      final first = builder(
        context,
        const _MarkerDataSource(
          path: '["main"]',
          childWidget: SizedBox(
            key: ValueKey<String>('first'),
            width: 10,
            height: 12,
          ),
        ),
      );
      final replacement = builder(
        context,
        const _MarkerDataSource(
          path: '["main"]',
          childWidget: SizedBox(
            key: ValueKey<String>('replacement'),
            width: 20,
            height: 24,
          ),
        ),
      );

      Widget frame(Widget child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            key: frameKey,
            width: 100,
            height: 100,
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        );
      }

      await tester.pumpWidget(frame(first));
      await tester.pump();
      expect(registry.registeredPathCount, 1);
      expect(
        registry.capture()['["main"]'],
        const Rect.fromLTWH(0, 0, 10, 12),
      );

      await tester.pumpWidget(frame(replacement));
      await tester.pump();
      expect(registry.registeredPathCount, 1);
      expect(
        registry.capture()['["main"]'],
        const Rect.fromLTWH(0, 0, 20, 24),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(registry.registeredPathCount, 0);
    },
  );

  testWidgets(
    'an earlier customer library with ordinary marker cannot steal '
    'instrumentation',
    (tester) async {
      var customerMarkerBuilds = 0;
      final registry = GeometryRegistry(frameRenderBox: () => null);
      addTearDown(registry.dispose);
      final registrations = <RestageWidgetLibraryRegistration>[
        RestageWidgetLibraryRegistration(
          library: const WidgetLibrary.custom('acme.widgets'),
          widgets: <RestageWidgetFactory>[
            RestageWidgetFactory(
              name: 'marker',
              builder: (_, __) {
                customerMarkerBuilds += 1;
                return const SizedBox();
              },
            ),
          ],
        ),
        RestageWidgetLibraryRegistration(
          library: const WidgetLibrary.custom(kReservedPreviewLibraryName),
          widgets: <RestageWidgetFactory>[
            RestageWidgetFactory(
              name: kReservedPreviewConstructorName,
              builder: (_, __) {
                customerMarkerBuilds += 100;
                return const SizedBox();
              },
            ),
          ],
        ),
      ];
      final library = RemoteWidgetLibrary(
        const <Import>[
          Import(LibraryName(<String>['restage', 'editor'])),
          Import(LibraryName(<String>['acme', 'widgets'])),
          Import(LibraryName(<String>['restage', 'core'])),
        ],
        <WidgetDeclaration>[
          WidgetDeclaration(
            'Preview',
            null,
            ConstructorCall(kReservedPreviewConstructorName, <String, Object?>{
              'path': '["main"]',
              'child': const ConstructorCall('Text', <String, Object?>{
                'text': 'not stolen',
              }),
            }),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RawRfwRenderSurface.library(
            epoch: 1,
            library: library,
            data: const <String, Object?>{},
            environment: RenderEnv(
              theme: const <String, Object?>{},
              brightness: 'light',
              locale: 'en-US',
              textScale: 1,
              zoom: 1,
              frame: const Size(100, 100),
            ),
            registrations: registrations,
            geometryRegistry: registry,
            entryWidgetName: 'Preview',
            onRemoteEvent: (_, __) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(GeometryMarker), findsNothing);
      expect(registry.registeredPathCount, 1);
      expect(find.text('not stolen'), findsOneWidget);
      expect(customerMarkerBuilds, 0);
    },
  );
}

final class _MarkerDataSource implements DataSource {
  const _MarkerDataSource({required this.path, required this.childWidget});

  final String? path;
  final Widget childWidget;

  @override
  T? v<T extends Object>(List<Object> argsKey) =>
      argsKey.length == 1 && argsKey.single == 'path' && path is T
          ? path as T
          : null;

  @override
  Widget child(List<Object> argsKey) => childWidget;

  @override
  Widget? optionalChild(List<Object> argsKey) => childWidget;

  @override
  List<Widget> childList(List<Object> argsKey) => const <Widget>[];

  @override
  bool isList(List<Object> argsKey) => false;

  @override
  bool isMap(List<Object> argsKey) => false;

  @override
  int length(List<Object> argsKey) => 0;

  @override
  Widget builder(List<Object> argsKey, DynamicMap builderArg) => childWidget;

  @override
  Widget? optionalBuilder(List<Object> argsKey, DynamicMap builderArg) => null;

  @override
  VoidCallback? voidHandler(
    List<Object> argsKey, [
    DynamicMap? extraArguments,
  ]) =>
      null;

  @override
  T? handler<T extends Function>(
    List<Object> argsKey,
    HandlerGenerator<T> generator,
  ) =>
      null;
}
