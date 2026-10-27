import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _screen = LibraryName(['test']);

class _Nonlinear extends TextScaler {
  const _Nonlinear(this.extra);
  final double extra;
  @override
  double scale(double fontSize) => fontSize + extra + fontSize * fontSize / 100;
  @override
  double get textScaleFactor => 1 + extra / 14 + .14;
}

Widget _remote(String value, {bool rich = true}) {
  final root = rich
      ? 'TextRich(textSpan: {text: "Small", style: {fontSize: 12.0}, children: [{text: "Large", style: {fontSize: 32.0}}]}, $value)'
      : 'Text(text: "Small", fontSize: 12.0, $value)';
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_screen, parseLibraryFile('''
import restage.core;
widget Root = $root;
'''));
  return RemoteWidget(
    runtime: runtime,
    data: DynamicContent(),
    widget: const FullyQualifiedWidgetName(_screen, 'Root'),
  );
}

Widget _frame(Widget child,
        {TextScaler ambient = TextScaler.noScaling, bool bold = false}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(textScaler: ambient, boldText: bold),
        child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14), child: child),
      ),
    );

void main() {
  for (final rich in [false, true]) {
    testWidgets('computed native scaler preserves actual identity, rich=$rich',
        (tester) async {
      const type = ValueType.native('flutter.TextScaler', nullable: true);
      const contract =
          NativeBindingContract(type: 'flutter.TextScaler', nullable: true);
      const program = ValueProgram(
          nodes: [ValueNode('capture', type, name: 'scaler')],
          root: 0,
          captures: {'scaler': type});
      final child = _remote(
          'textScaler: {version: 1, program: ${jsonEncode(program.encode())}, '
          'captures: {scaler: {kind: "nativeBinding", key: "scaler", type: "flutter.TextScaler", nullable: true}}}',
          rich: rich);
      const actual = _Nonlinear(9);
      const ambient = _Nonlinear(2);
      await tester.pumpWidget(_frame(
          RestageNativeValues(bindings: {
            'scaler': NativeBinding(contract: contract, value: actual),
          }, child: child),
          ambient: ambient));
      expect(tester.takeException(), isNull);
      expect(
          tester
              .renderObject<RenderParagraph>(find.byType(RichText))
              .textScaler,
          same(actual));
      await tester.pumpWidget(_frame(
          RestageNativeValues(bindings: {
            'scaler':
                NativeBinding<TextScaler?>(contract: contract, value: null),
          }, child: child),
          ambient: ambient));
      expect(tester.takeException(), isNull);
      expect(
          tester
              .renderObject<RenderParagraph>(find.byType(RichText))
              .textScaler,
          same(ambient));
    });
  }

  for (final value in [const _Nonlinear(6), null]) {
    testWidgets('declared scaler call returns its actual nullable value $value',
        (tester) async {
      const type = ValueType.native('flutter.TextScaler', nullable: true);
      const valueContract =
          NativeBindingContract(type: 'flutter.TextScaler', nullable: true);
      const call = NativeBindingContract(
          type: 'installed.scaler',
          call: NativeCallContract(
              inputs: [], result: type, implementation: 'test.scaler.v1'));
      final program = ValueProgram(nodes: [
        ValueNode('native.call', type, value: {
          'binding': 'makeScaler',
          'contract': call.toJson(),
          'captures': <String, String>{},
        })
      ], root: 0);
      var calls = 0;
      final runtime = Runtime()
        ..update(
            _core,
            LocalWidgetLibrary({
              'Probe': (context, source) {
                source = RestageValueBinding.dataSource(source, context);
                expect(RestageDecoders.textScaler(context, source, ['value']),
                    same(value));
                expect(RestageDecoders.textScaler(context, source, ['value']),
                    same(value));
                return const SizedBox();
              }
            }))
        ..update(
            _screen,
            parseLibraryFile('import restage.core; widget Root = Probe(value: '
                '{version: 1, program: ${jsonEncode(program.encode())}, captures: {}});'));
      addTearDown(runtime.dispose);
      await tester.pumpWidget(RestageNativeValues(
          bindings: {
            'makeScaler': NativeBinding(
                contract: call,
                value: NativeCallAdapter(call, (_, __) {
                  calls++;
                  return value == null
                      ? null
                      : NativeBinding(contract: valueContract, value: value);
                })),
          },
          child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_screen, 'Root'))));
      expect(tester.takeException(), isNull);
      expect(calls, 1);
    });
  }

  testWidgets('native local scaler reaches the deferred native text body',
      (tester) async {
    const type = ValueType.native('flutter.TextScaler');
    const contract = NativeBindingContract(type: 'flutter.TextScaler');
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('capture', type, name: 'scaler'),
              ValueNode('local.write', type, name: 'scaler', inputs: [0]),
            ],
            root: 0,
            captures: {'scaler': type},
            locals: {'scaler': type}),
        result: BuilderResult.let(1, BuilderResult.body(0)),
        bodyCount: 1);
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _screen,
          parseLibraryFile(
              'import restage.core; widget Root = LayoutBuilder(builder: '
              '$kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(program.encode())}, '
              'captures: {scaler: {kind: "nativeBinding", key: "scaler", type: "flutter.TextScaler", nullable: false}}, '
              'bodies: [(frame) => Text(text: "Local", textScaler: {kind: "nativeLocal", slot: "scaler", type: "flutter.TextScaler", nullable: false})]));'));
    addTearDown(runtime.dispose);
    const actual = _Nonlinear(8);
    await tester.pumpWidget(_frame(RestageNativeValues(
        bindings: {
          'scaler': NativeBinding(contract: contract, value: actual),
        },
        child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_screen, 'Root')))));
    expect(tester.takeException(), isNull);
    expect(
        tester.renderObject<RenderParagraph>(find.byType(RichText)).textScaler,
        same(actual));
  });

  for (final failure in ['missing', 'nominal', 'dartType', 'nullability']) {
    testWidgets('computed scaler refuses $failure binding', (tester) async {
      final type = ValueType.native(
          failure == 'nominal' ? 'flutter.Color' : 'flutter.TextScaler',
          nullable: true);
      final contract =
          NativeBindingContract(type: type.nativeType!, nullable: true);
      final program = ValueProgram(
          nodes: [ValueNode('capture', type, name: 'scaler')],
          root: 0,
          captures: {'scaler': type});
      final reference =
          '{kind: "nativeBinding", key: "scaler", type: ${jsonEncode(type.nativeType)}, nullable: true}';
      final child = _remote(
          'textScaler: {version: 1, program: ${jsonEncode(program.encode())}, captures: {scaler: $reference}}');
      await tester.pumpWidget(_frame(RestageNativeValues(bindings: {
        if (failure != 'missing')
          'scaler': NativeBinding(
              contract: failure == 'nullability'
                  ? const NativeBindingContract(type: 'flutter.TextScaler')
                  : contract,
              value: failure == 'dartType'
                  ? Object()
                  : failure == 'nominal'
                      ? const Color(0xff112233)
                      : const _Nonlinear(3)),
      }, child: child)));
      expect(tester.takeException(), isNotNull);
    });
  }

  testWidgets(
      'computed null and omitted scaler remain null while wrong scalar kinds fail',
      (tester) async {
    for (final (type, value) in [
      (ValueType.nullType, null),
      (ValueType.integer, 3),
      (ValueType.string, 'wrong')
    ]) {
      final program = ValueProgram(
          nodes: [ValueNode('literal', type, value: value)], root: 0);
      final runtime = Runtime()
        ..update(
            _core,
            LocalWidgetLibrary({
              'Probe': (context, source) {
                source = RestageValueBinding.dataSource(source, context);
                expect(RestageDecoders.textScaler(context, source, ['absent']),
                    isNull);
                if (value == null) {
                  expect(RestageDecoders.textScaler(context, source, ['value']),
                      isNull);
                } else {
                  expect(
                      () => RestageDecoders.textScaler(
                          context, source, ['value']),
                      throwsFormatException);
                }
                return const SizedBox();
              }
            }))
        ..update(
            _screen,
            parseLibraryFile('import restage.core; widget Root = Probe(value: '
                '{version: 1, program: ${jsonEncode(program.encode())}, captures: {}});'));
      addTearDown(runtime.dispose);
      await tester.pumpWidget(RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_screen, 'Root')));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('none and linear recipes match native overrides', (tester) async {
    for (final (recipe, expected) in [
      ('{kind: "none"}', TextScaler.noScaling),
      ('{kind: "linear", factor: 1.6}', const TextScaler.linear(1.6)),
    ]) {
      await tester.pumpWidget(_frame(
          Row(children: [
            Text.rich(
                const TextSpan(
                    text: 'Small',
                    style: TextStyle(fontSize: 12),
                    children: [
                      TextSpan(text: 'Large', style: TextStyle(fontSize: 32)),
                    ]),
                textScaler: expected),
            _remote('textScaler: $recipe'),
          ]),
          ambient: const _Nonlinear(5)));
      final paragraphs = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .toList();
      expect(paragraphs, hasLength(2));
      for (final size in [12.0, 32.0]) {
        expect(paragraphs[1].textScaler.scale(size),
            paragraphs[0].textScaler.scale(size));
      }
      expect(paragraphs[1].size, paragraphs[0].size);
    }
  });

  testWidgets('typed native scaler bindings preserve actual nullable values',
      (tester) async {
    const scaler = _Nonlinear(7);
    const contract =
        NativeBindingContract(type: 'flutter.TextScaler', nullable: true);
    final child = _remote(
        'textScaler: {kind: "nativeBinding", key: "scaler", type: "flutter.TextScaler", nullable: true}');
    Widget scope(TextScaler? value) => _frame(
        RestageNativeValues(bindings: {
          'scaler': NativeBinding(contract: contract, value: value),
        }, child: child),
        ambient: scaler);
    await tester.pumpWidget(scope(scaler));
    expect(
        tester.renderObject<RenderParagraph>(find.byType(RichText)).textScaler,
        same(scaler));
    await tester.pumpWidget(scope(null));
    expect(
        tester.renderObject<RenderParagraph>(find.byType(RichText)).textScaler,
        same(scaler));
  });

  testWidgets('native references isolate mounts and rebuild on replacement',
      (tester) async {
    final firstChild = _remote('textScaler: {kind: "native", key: "shared"}');
    final secondChild = _remote('textScaler: {kind: "native", key: "shared"}');
    const first = _Nonlinear(2);
    final second = const _Nonlinear(9).clamp(maxScaleFactor: 2);
    Widget mounts(TextScaler value) => _frame(Row(children: [
          RestageNativeValues(
              textScalers: {'shared': value},
              child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.noScaling),
                  child: firstChild)),
          RestageNativeValues(
              textScalers: {'shared': second}, child: secondChild),
        ]));
    await tester.pumpWidget(mounts(first));
    var paragraphs = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .toList();
    expect(paragraphs[0].textScaler, same(first));
    expect(paragraphs[1].textScaler, same(second));
    for (final size in [12.0, 32.0]) {
      expect(paragraphs[0].textScaler.scale(size), first.scale(size));
      expect(paragraphs[1].textScaler.scale(size), second.scale(size));
    }
    const replacement = _Nonlinear(6);
    await tester.pumpWidget(mounts(replacement));
    paragraphs = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .toList();
    expect(paragraphs[0].textScaler, same(replacement));
    expect(paragraphs[1].textScaler, same(second));
  });

  testWidgets('nonlinear scaling matches native mixed-size text layout',
      (tester) async {
    const scaler = _Nonlinear(4);
    await tester.pumpWidget(_frame(Row(children: [
      const Text.rich(
          TextSpan(text: 'Small', style: TextStyle(fontSize: 12), children: [
            TextSpan(text: 'Large', style: TextStyle(fontSize: 32)),
          ]),
          textScaler: scaler),
      RestageNativeValues(
          textScalers: {'root': scaler},
          child: _remote('textScaler: {kind: "native", key: "root"}')),
    ])));
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .toList();
    for (final size in [12.0, 32.0]) {
      expect(paragraphs[1].textScaler.scale(size),
          paragraphs[0].textScaler.scale(size));
    }
    expect(paragraphs[1].size, paragraphs[0].size);
  });

  testWidgets('plain Text preserves its explicit nonlinear scaler',
      (tester) async {
    const scaler = _Nonlinear(4);
    await tester.pumpWidget(_frame(Row(children: [
      const Text('Small', style: TextStyle(fontSize: 12), textScaler: scaler),
      RestageNativeValues(
          textScalers: {'root': scaler},
          child: _remote('textScaler: {kind: "native", key: "root"}',
              rich: false)),
    ])));
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .toList();
    expect(paragraphs[1].textScaler, same(scaler));
    expect(paragraphs[1].size, paragraphs[0].size);
  });

  testWidgets('a computed nullable native scaler preserves ambient inheritance',
      (tester) async {
    const scaler = _Nonlinear(4);
    await tester.pumpWidget(_frame(
        RestageNativeValues(
            textScalers: const {'nullable': null},
            child: _remote('textScaler: {kind: "native", key: "nullable"}')),
        ambient: scaler));
    expect(
        tester.renderObject<RenderParagraph>(find.byType(RichText)).textScaler,
        same(scaler));
  });

  testWidgets('omitted override inherits scaler and boldText', (tester) async {
    const scaler = _Nonlinear(4);
    await tester.pumpWidget(_frame(_remote(''), ambient: scaler, bold: true));
    final paragraph =
        tester.renderObject<RenderParagraph>(find.byType(RichText));
    expect(paragraph.textScaler, same(scaler));
    expect(paragraph.text.style!.fontWeight, FontWeight.bold);
  });

  testWidgets('an explicit native reference without its scope fails',
      (tester) async {
    await tester.pumpWidget(
        _frame(_remote('textScaler: {kind: "native", key: "absent"}')));
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('native mutual exclusion of scaler overrides is preserved',
      (tester) async {
    await tester.pumpWidget(
        _frame(_remote('textScaler: {kind: "none"}, textScaleFactor: 2.0')));
    expect(tester.takeException(), isNotNull);
  });
}
