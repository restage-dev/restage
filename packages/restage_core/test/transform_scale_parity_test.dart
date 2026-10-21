import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['test', 'scaling']);
const _marker = RfwConstructorPresenceProtocol.markerKey;
const _value = RfwConstructorPresenceProtocol.valueKey;
const _version = RfwConstructorPresenceProtocol.version;

Runtime _runtime(String arguments) => Runtime()
  ..update(_core, buildCoreWidgetLibrary())
  ..update(_surface, parseLibraryFile('''
    import restage.core;
    widget Surface = TransformScale(
      $arguments,
      child: Container(width: 30.0, height: 20.0, color: 4278190080),
    );
  '''));

Widget _panel(Widget child) => SizedBox(
      width: 200,
      height: 200,
      child: Center(child: child),
    );

Widget _pair(Widget native, Runtime runtime, DynamicContent data,
        {TextDirection direction = TextDirection.ltr}) =>
    Directionality(
      textDirection: direction,
      child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
        _panel(native),
        _panel(RemoteWidget(
          runtime: runtime,
          data: data,
          widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
        )),
      ])),
    );

void _expectParity(WidgetTester tester) {
  final transforms = find.byType(Transform);
  expect(transforms, findsNWidgets(2));
  final native = tester.widget<Transform>(transforms.at(0));
  final delivered = tester.widget<Transform>(transforms.at(1));
  expect(delivered.transform, native.transform);
  expect(delivered.origin, native.origin);
  expect(delivered.alignment, native.alignment);
  expect(delivered.transformHitTests, native.transformHitTests);
  expect(delivered.filterQuality, native.filterQuality);
  final nativeRender = tester.renderObject<RenderTransform>(transforms.at(0));
  final deliveredRender =
      tester.renderObject<RenderTransform>(transforms.at(1));
  expect(deliveredRender.size, const Size(30, 20));
  expect(deliveredRender.size, nativeRender.size);
  for (final point in [
    Offset.zero,
    const Offset(30, 20),
    const Offset(15, 10)
  ]) {
    expect(
      deliveredRender.child!.localToGlobal(point, ancestor: deliveredRender),
      nativeRender.child!.localToGlobal(point, ancestor: nativeRender),
    );
  }
  expect(tester.takeException(), isNull);
}

void main() {
  final factors =
      <({String name, String wire, double? scale, double? x, double? y})>[
    (name: 'uniform integer', wire: 'scale: 2', scale: 2, x: null, y: null),
    (name: 'single x integer', wire: 'scaleX: 2', scale: null, x: 2, y: null),
    (name: 'single y integer', wire: 'scaleY: 3', scale: null, x: null, y: 3),
    (
      name: 'both axes',
      wire: 'scaleX: -2, scaleY: 1.5',
      scale: null,
      x: -2,
      y: 1.5
    ),
    (name: 'zero', wire: 'scale: 0', scale: 0, x: null, y: null),
    (name: 'negative', wire: 'scale: -1', scale: -1, x: null, y: null),
    (name: 'fractional', wire: 'scale: 0.5', scale: 0.5, x: null, y: null),
    (
      name: 'null uniform with axis',
      wire: 'scale: data.absent, scaleX: 2',
      scale: null,
      x: 2,
      y: null
    ),
  ];
  for (final factor in factors) {
    for (final alignment in ['omitted', 'null', 'concrete', 'directional']) {
      testWidgets('${factor.name} and $alignment alignment match native',
          (tester) async {
        final alignmentWire = switch (alignment) {
          'omitted' => '',
          'null' => 'alignment: {"$_marker": $_version},',
          'concrete' => 'alignment: {"$_marker": $_version, "$_value": '
              '{x: 1.0, y: -1.0}},',
          _ => 'alignment: {"$_marker": $_version, "$_value": '
              '{start: -1.0, y: 1.0}},',
        };
        final runtime = _runtime('''
          ${factor.wire}, $alignmentWire
          origin: {x: 4, y: -3},
          transformHitTests: false,
          filterQuality: "medium"
        ''');
        addTearDown(runtime.dispose);
        final native = alignment == 'omitted'
            ? Transform.scale(
                scale: factor.scale,
                scaleX: factor.x,
                scaleY: factor.y,
                origin: const Offset(4, -3),
                transformHitTests: false,
                filterQuality: FilterQuality.medium,
                child: Container(
                    width: 30, height: 20, color: const Color(0xFF000000)),
              )
            : Transform.scale(
                scale: factor.scale,
                scaleX: factor.x,
                scaleY: factor.y,
                alignment: switch (alignment) {
                  'null' => null,
                  'concrete' => const Alignment(1, -1),
                  _ => AlignmentDirectional.bottomStart,
                },
                origin: const Offset(4, -3),
                transformHitTests: false,
                filterQuality: FilterQuality.medium,
                child: Container(
                    width: 30, height: 20, color: const Color(0xFF000000)),
              );
        await tester.pumpWidget(_pair(native, runtime, DynamicContent(),
            direction: TextDirection.rtl));
        _expectParity(tester);
      });
    }
  }

  testWidgets(
      'mounted nullable alignment and integral factor updates preserve native state',
      (tester) async {
    final state =
        ValueNotifier<({double factor, AlignmentGeometry? alignment})>(
      (factor: 2, alignment: const Alignment(1, -1)),
    );
    addTearDown(state.dispose);
    final runtime = _runtime('''
      scale: data.context.factor,
      alignment: {"$_marker": $_version, "$_value": data.context.alignment},
      origin: {x: 4, y: -3}
    ''');
    addTearDown(runtime.dispose);
    final data = DynamicContent({
      'context': {
        'factor': 2,
        'alignment': {'x': 1.0, 'y': -1.0},
      },
    });
    await tester.pumpWidget(_pair(
      ValueListenableBuilder<({double factor, AlignmentGeometry? alignment})>(
        valueListenable: state,
        builder: (context, value, child) => Transform.scale(
          scale: value.factor,
          alignment: value.alignment,
          origin: const Offset(4, -3),
          child:
              Container(width: 30, height: 20, color: const Color(0xFF000000)),
        ),
      ),
      runtime,
      data,
    ));
    final delivered =
        tester.renderObject<RenderTransform>(find.byType(Transform).last);
    _expectParity(tester);
    for (final factor in [0, -1, 3, 1.5]) {
      state.value = (factor: factor.toDouble(), alignment: null);
      data.update('context', {'factor': factor});
      await tester.pump();
      _expectParity(tester);
      expect(tester.widget<Transform>(find.byType(Transform).last).alignment,
          isNull);
      expect(tester.renderObject(find.byType(Transform).last), same(delivered));
    }
    state.value = (factor: 2, alignment: AlignmentDirectional.topEnd);
    data.update('context', {
      'factor': 2,
      'alignment': {'start': 1.0, 'y': -1.0},
    });
    await tester.pump();
    _expectParity(tester);
    expect(tester.renderObject(find.byType(Transform).last), same(delivered));
  });

  for (final transformHitTests in [true, false]) {
    testWidgets('native hit testing is preserved ($transformHitTests)',
        (tester) async {
      final runtime = Runtime()
        ..update(_core, buildCoreWidgetLibrary())
        ..update(_surface, parseLibraryFile('''
          import restage.core;
          widget Surface = TransformScale(
            scale: 0.5, transformHitTests: $transformHitTests,
            child: GestureDetector(onTap: event "tap" {},
              child: Container(width: 30.0, height: 20.0, color: 4278190080)),
          );
        '''));
      addTearDown(runtime.dispose);
      var nativeTaps = 0;
      var deliveredTaps = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
          _panel(Transform.scale(
              scale: 0.5,
              transformHitTests: transformHitTests,
              child: GestureDetector(
                  onTap: () => nativeTaps++,
                  child: Container(
                      width: 30, height: 20, color: const Color(0xFF000000))))),
          _panel(RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
              onEvent: (name, arguments) => deliveredTaps++)),
        ])),
      ));
      for (final transform in [
        find.byType(Transform).first,
        find.byType(Transform).last
      ]) {
        final render = tester.renderObject<RenderTransform>(transform);
        await tester.tapAt(render.localToGlobal(const Offset(2, 2)));
      }
      expect(nativeTaps, transformHitTests ? 0 : 1);
      expect(deliveredTaps, nativeTaps);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid factor relations retain native debug assertions',
      (tester) async {
    for (final mixed in [false, true]) {
      expect(
          () => Transform.scale(
              scale: mixed ? 2 : null, scaleX: mixed ? 3 : null),
          throwsAssertionError);
      final runtime =
          _runtime(mixed ? 'scale: 2, scaleX: 3' : 'scale: data.absent');
      addTearDown(runtime.dispose);
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_surface, 'Surface'))));
      expect(tester.takeException(), isAssertionError);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
