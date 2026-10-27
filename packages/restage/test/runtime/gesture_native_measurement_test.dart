import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

import '../fixtures/gesture_bindings_source.dart';

const _surface = LibraryName(['gesture', 'measured']);

Widget _mount(
    GestureTapScreen screen, void Function(String, DynamicMap) event) {
  final runtime = Runtime()
    ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
    ..update(_surface, decodeLibraryBlob(base64Decode(gestureMeasuredTapBlob)));
  registerMeasurementRfwPresentationLibrary(runtime);
  return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: RestageNativeValues(
              bindings: gestureMeasuredTapBindings(screen),
              child: RemoteWidget(
                  runtime: runtime,
                  data:
                      DynamicContent({'context': gestureMeasuredTapContext()}),
                  widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
                  onEvent: event))));
}

TapGestureRecognizer _recognizer(WidgetTester tester) =>
    (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan).recognizer!
        as TapGestureRecognizer;

void main() {
  testWidgets('published native details emit each exact Measurement route once',
      (tester) async {
    final events = <Object>[];
    final down = TapDownDetails(
        globalPosition: const Offset(31, 42),
        localPosition: const Offset(7, 9));
    final up = TapUpDetails(kind: PointerDeviceKind.stylus);
    final move = TapMoveDetails(
        kind: PointerDeviceKind.mouse, delta: const Offset(2, 3));
    final screen = GestureTapScreen(
        seen: (name, details) => events.add(('native.$name', details)),
        up: (details) => events.add(('native.up', details)));
    await tester.pumpWidget(_mount(screen, (name, args) {
      expect(name, kMeasurementPublicationTapEventNameV1);
      events.add(('measure', args[kMeasurementPublicationRouteArgumentKeyV1]));
    }));
    final recognizer = _recognizer(tester);
    recognizer.onTapDown!(down);
    recognizer.onTapUp!(up);
    recognizer.onTapMove!(move);
    recognizer.onSecondaryTapDown!(down);
    recognizer.onSecondaryTapUp!(up);
    recognizer.onTertiaryTapDown!(down);
    recognizer.onTertiaryTapUp!(up);
    final expected = <Object>[];
    for (final (field, name, details) in [
      ('onTapDown', 'down', down),
      ('onTapUp', 'up', up),
      ('onTapMove', 'move', move),
      ('onSecondaryTapDown', 'secondary.down', down),
      ('onSecondaryTapUp', 'secondary.up', up),
      ('onTertiaryTapDown', 'tertiary.down', down),
      ('onTertiaryTapUp', 'tertiary.up', up)
    ]) {
      expected.add(('native.$name', details));
      expected.add(('measure', gestureMeasuredTapRoutes[field]));
    }
    expect(events, expected);
    expect(
        events
            .whereType<(String, Object?)>()
            .where((event) => event.$1 == 'measure'),
        hasLength(7));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(recognizer.onTapDown, isNull);
  });

  testWidgets(
      'native callback exception stops the existing measure-after-effect path',
      (tester) async {
    final failure = StateError('native failure');
    final routes = <String>[];
    final screen = GestureTapScreen(seen: (_, __) => throw failure, up: (_) {});
    await tester.pumpWidget(_mount(
        screen,
        (_, args) => routes
            .add(args[kMeasurementPublicationRouteArgumentKeyV1]! as String)));
    final down = TapDownDetails();
    expect(() => screen.seen('down', down), throwsA(same(failure)));
    expect(() => _recognizer(tester).onTapDown!(down), throwsA(same(failure)));
    expect(routes, isEmpty);
    _recognizer(tester).onTapUp!(TapUpDetails(kind: PointerDeviceKind.touch));
    expect(routes, [gestureMeasuredTapRoutes['onTapUp']]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
      'pending callbacks retain their published route until native settlement',
      (tester) async {
    final events = <String>[];
    final baseline =
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
    final screen = GestureTapScreen(
        seen: (name, _) => events.add('native.$name'),
        up: (_) => events.add('native.up'));
    await tester.pumpWidget(_mount(screen, (_, args) {
      final carrier = args[kMeasurementPublicationRouteArgumentKeyV1];
      final name = gestureMeasuredTapRoutes.entries
          .singleWhere((entry) => entry.value == carrier)
          .key;
      events.add('measure.$name');
    }));
    final recognizer = _recognizer(tester);
    final paragraph =
        tester.renderObject<RenderParagraph>(find.byType(RichText));
    final point = paragraph.localToGlobal(paragraph.size.center(Offset.zero));
    final pointer = await tester.startGesture(point);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(const SizedBox());
    await pointer.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events,
        ['native.down', 'measure.onTapDown', 'native.up', 'measure.onTapUp']);
    expect(recognizer.onTapDown, isNull);
    expect(recognizer.onTapUp, isNull);
    expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount, baseline);
  });
  testWidgets(
      'Measurement leaves the shared borrowed recognizer with its owner',
      (tester) async {
    var calls = 0;
    final recognizer = TapGestureRecognizer()..onTap = (() => calls++);
    final callback = recognizer.onTap;
    void down(TapDownDetails details) {}
    recognizer.onTapDown = down;
    final screen = GestureBorrowedScreen(recognizer: recognizer);
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(_surface,
          decodeLibraryBlob(base64Decode(gestureMeasuredBorrowedBlob)));
    registerMeasurementRfwPresentationLibrary(runtime);
    final events = <String>[];
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: gestureMeasuredBorrowedBindings(screen),
            child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(
                    {'context': gestureMeasuredBorrowedContext()}),
                widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
                onEvent: (name, _) => events.add(name)))));
    final spans = (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
        .children!
        .cast<TextSpan>();
    expect(
        spans.map((span) => span.recognizer), everyElement(same(recognizer)));
    expect(gestureMeasuredBorrowedRoutes, isEmpty);
    recognizer.onTap!();
    expect(calls, 1);
    expect(events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(recognizer.onTap, same(callback));
    expect(recognizer.onTapDown, same(down));
    recognizer.dispose();
  });
}
