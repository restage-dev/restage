import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['test', 'translation']);

void main() {
  for (final transformHitTests in [true, false]) {
    testWidgets('translation preserves geometry and hits ($transformHitTests)',
        (tester) async {
      final offset = ValueNotifier(const Offset(-12.5, 8));
      addTearDown(offset.dispose);
      final data = DynamicContent({'dx': -12.5, 'dy': 8});
      final runtime = Runtime()
        ..update(_core, buildCoreWidgetLibrary())
        ..update(_surface, parseLibraryFile('''
          import restage.core;
          widget Surface = TransformTranslate(
            offset: {x: data.dx, y: data.dy},
            transformHitTests: $transformHitTests,
            filterQuality: "low",
            child: GestureDetector(
              onTap: event "tap" {},
              child: Container(width: 30.0, height: 20.0, color: 4278190080),
            ),
          );
        '''));
      addTearDown(runtime.dispose);
      var nativeTaps = 0;
      var deliveredTaps = 0;
      Widget panel(Widget child) => SizedBox(
            width: 200,
            height: 200,
            child: Center(child: child),
          );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              panel(ValueListenableBuilder<Offset>(
                valueListenable: offset,
                builder: (context, value, child) => Transform.translate(
                  offset: value,
                  transformHitTests: transformHitTests,
                  filterQuality: FilterQuality.low,
                  child: GestureDetector(
                    onTap: () => nativeTaps++,
                    child: Container(
                      width: 30,
                      height: 20,
                      color: const Color(0xFF000000),
                    ),
                  ),
                ),
              )),
              panel(RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
                onEvent: (name, arguments) {
                  expect(name, 'tap');
                  deliveredTaps++;
                },
              )),
            ],
          ),
        ),
      ));
      await tester.pump();
      final transforms = find.byType(Transform);
      expect(transforms, findsNWidgets(2));
      final native = tester.renderObject<RenderTransform>(transforms.at(0));
      final delivered = tester.renderObject<RenderTransform>(transforms.at(1));
      for (final value in [
        const Offset(-12.5, 8),
        const Offset(50.25, -35.5),
        Offset.zero,
        const Offset(-50, 35),
      ]) {
        offset.value = value;
        data.update('dx', value.dx);
        data.update('dy', value.dy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.renderObject(transforms.at(0)), same(native));
        expect(tester.renderObject(transforms.at(1)), same(delivered));
        final nativeWidget = tester.widget<Transform>(transforms.at(0));
        final deliveredWidget = tester.widget<Transform>(transforms.at(1));
        expect(deliveredWidget.transform, nativeWidget.transform);
        expect(deliveredWidget.transform.storage[12], value.dx);
        expect(deliveredWidget.transform.storage[13], value.dy);
        expect(delivered.transformHitTests, transformHitTests);
        expect(delivered.filterQuality, FilterQuality.low);
        expect(delivered.size, const Size(30, 20));
        expect(delivered.size, native.size);
        for (final render in [native, delivered]) {
          final origin = render.localToGlobal(Offset.zero);
          expect(
            render.child!.localToGlobal(Offset.zero),
            origin + value,
          );
          final hitCenter = origin +
              const Offset(15, 10) +
              (transformHitTests ? value : Offset.zero);
          final before = nativeTaps + deliveredTaps;
          await tester.tapAt(hitCenter);
          await tester.pump();
          expect(nativeTaps + deliveredTaps, before + 1);
          if (value.dx.abs() > 30) {
            final missCenter = origin +
                const Offset(15, 10) +
                (transformHitTests ? Offset.zero : value);
            await tester.tapAt(missCenter);
            await tester.pump();
            expect(nativeTaps + deliveredTaps, before + 1);
          }
        }
        expect(deliveredTaps, nativeTaps);
      }
    });
  }

  testWidgets('omitted translation options retain native defaults',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(_surface, parseLibraryFile('''
        import restage.core;
        widget Surface = TransformTranslate(offset: {x: 12, y: -8});
      '''));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
      ),
    ));
    final actual = tester.widget<Transform>(find.byType(Transform));
    final native = Transform.translate(offset: const Offset(12, -8));
    expect(actual.transform, native.transform);
    expect(actual.transformHitTests, native.transformHitTests);
    expect(actual.filterQuality, native.filterQuality);
    expect(actual.origin, native.origin);
    expect(actual.alignment, native.alignment);
    expect(actual.child, isNull);
    expect(tester.takeException(), isNull);
  });
}
