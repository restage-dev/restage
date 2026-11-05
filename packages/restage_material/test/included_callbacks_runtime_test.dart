// Callbacks a design fills with the app's own closure: Flutter calls it with
// its own arguments, and a returned value reaches Flutter.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart' hide Switch;

const _root = LibraryName(['test']);

Widget _remote(String root, String type, Object callback) {
  final runtime = Runtime()
    ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
    ..update(const LibraryName(['restage', 'material']),
        buildMaterialWidgetLibrary())
    ..update(
        _root,
        rfw.parseLibraryFile('import restage.core; import restage.material; '
            'widget Root = $root;'));
  addTearDown(runtime.dispose);
  final binding = NativeBinding<Object?>(
      contract: NativeBindingContract(type: type, nullable: false),
      value: callback);
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: RestageNativeValues(
          bindings: {'cb': binding},
          child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent({
              'context': {
                'cb': {
                  'kind': 'nativeBinding',
                  'key': 'cb',
                  'type': type,
                  'nullable': false,
                },
              },
            }),
            widget: const FullyQualifiedWidgetName(_root, 'Root'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('TabBar.onHover gets both of Flutter\'s arguments',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_remote(
        'DefaultTabController(length: 2, child: TabBar('
            'tabs: [Tab(text: "A"), Tab(text: "B")], '
            'onHover: {nativeEvent: data.context.cb}))',
        '(dart:core#bool,dart:core#int)->void',
        (bool hovering, int index) => calls.add('$hovering $index')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('B')));
    await tester.pump();
    expect(calls, contains('true 1'));
  });

  testWidgets('GestureDetector.onTapDown gets Flutter\'s TapDownDetails',
      (tester) async {
    final calls = <TapDownDetails>[];
    await tester.pumpWidget(_remote(
        'GestureDetector(onTapDown: {nativeEvent: data.context.cb}, '
            'child: SizedBox(width: 40.0, height: 40.0, '
            'child: ColoredBox(color: 0xFF000000)))',
        '(package:flutter/src/gestures/tap.dart#TapDownDetails)->void',
        calls.add));
    await tester.tapAt(tester.getCenter(find.descendant(
        of: find.byType(RemoteWidget), matching: find.byType(ColoredBox))));
    await tester.pump();
    expect(calls.single.localPosition, const Offset(20, 20));
  });

  testWidgets('Slider.semanticFormatterCallback returns to Flutter',
      (tester) async {
    final semantics = tester.ensureSemantics();
    String format(double value) => 'at ${(value * 100).round()}';
    await tester.pumpWidget(_remote(
        'Slider(value: 0.5, onChanged: event "c" {}, '
            'semanticFormatterCallback: {nativeEvent: data.context.cb})',
        '(dart:core#double)->dart:core#String',
        format));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.semanticFormatterCallback, same(format));
    expect(find.semantics.byValue('at 50'), findsOne);
    semantics.dispose();
  });
}
