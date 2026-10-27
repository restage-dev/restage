import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ColorSpace;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _color = NativeBindingContract(type: 'flutter.Color');
const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);

class _CustomColor extends Color {
  const _CustomColor() : super(0xff345678);
  @override
  double get r => 0.123456789;
  @override
  ColorSpace get colorSpace => ColorSpace.displayP3;
}

class _Source extends Fake implements DataSource {
  _Source(this.values);
  final Object? values;
  Object? at(List<Object> path) {
    var value = values;
    for (final key in path) {
      value = switch (value) {
        final Map map => map[key],
        final List list when key is int => list[key],
        _ => null,
      };
    }
    return value;
  }

  @override
  bool isMap(List<Object> path) => at(path) is Map;
  @override
  bool isList(List<Object> path) => at(path) is List;
  @override
  int length(List<Object> path) => (at(path) as List).length;
  @override
  T? v<T extends Object>(List<Object> path) {
    if (T == Object || T == Color) {
      throw StateError('Native objects must not cross scalar reads');
    }
    final value = at(path);
    return value is T ? value : null;
  }
}

Map<String, Object?> _envelope(ValueProgram program) => {
      'version': valueProgramVersion,
      'program': program.encode(),
      'captures': <String, Object?>{},
    };

void main() {
  testWidgets('ordinary source retains the actual color in native factories',
      (tester) async {
    final fixtures = jsonDecode(
            File('test/fixtures/native_color_sources.json').readAsStringSync())
        as Map;
    final swatch = <int, Color>{500: const Color(0xff123456)};
    final material = MaterialColor(0xff123456, swatch);
    final accent = MaterialAccentColor(0xff123456, swatch);
    for (final entry in fixtures.entries) {
      final fixture = entry.value as Map;
      final runtime = Runtime()
        ..update(_core, LocalWidgetLibrary(kCoreLibraryFactories))
        ..update(
            _root,
            rfw.parseLibraryFile(
                'import restage.core; widget Root = ${fixture['dsl']};'));
      for (final color in [
        const _CustomColor(),
        material,
        accent,
        Colors.blue
      ]) {
        await tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: RestageNativeValues(
                bindings: {
                  'color': NativeBinding(contract: _color, value: color),
                },
                child: RemoteWidget(
                    runtime: runtime,
                    data: DynamicContent({
                      'context': {
                        fixture['key'] as String: _color.reference('color')
                      }
                    }),
                    widget: const FullyQualifiedWidgetName(_root, 'Root')))));
        expect(tester.takeException(), isNull, reason: entry.key as String);
        switch (entry.key) {
          case 'style':
            final style = tester.widget<Text>(find.text('color')).style!;
            expect(style.color, same(color));
            expect(style.decorationColor, same(color));
            expect(style.shadows!.single.color, same(color));
          case 'gradient':
            final decoration = tester
                .widget<DecoratedBox>(find.byType(DecoratedBox))
                .decoration as BoxDecoration;
            expect(decoration.gradient!.colors, everyElement(same(color)));
          case 'shadow':
            final decoration = tester
                .widget<DecoratedBox>(find.byType(DecoratedBox))
                .decoration as BoxDecoration;
            expect(decoration.boxShadow!.single.color, same(color));
          default:
            final actual =
                tester.widget<ColoredBox>(find.byType(ColoredBox)).color;
            expect(actual, same(color));
            expect(actual.runtimeType, color.runtimeType);
            expect(actual.hashCode, color.hashCode);
            expect(actual.r, color.r);
            expect(actual.colorSpace, color.colorSpace);
            if (actual is ColorSwatch<int>) {
              expect(actual[500], same((color as ColorSwatch<int>)[500]));
            }
        }
        await tester.pumpWidget(const SizedBox());
      }
      runtime.dispose();
    }
    swatch[500] = const Color(0xffabcdef);
    expect(material[500], same(swatch[500]));
    expect(accent[500], same(swatch[500]));
  });

  testWidgets(
      'nested color readers preserve native filters and Paint semantics',
      (tester) async {
    const color = _CustomColor();
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'color': NativeBinding(contract: _color, value: color),
        },
        child: Builder(builder: (context) {
          final source = RestageValueBinding.dataSource(
              _Source({
                'color': _color.reference('color'),
                'filter': {
                  'type': 'mode',
                  'color': _color.reference('color'),
                  'blendMode': 'srcIn'
                },
                'paint': {
                  'color': _color.reference('color'),
                  'colorFilter': {
                    'type': 'mode',
                    'color': _color.reference('color'),
                    'blendMode': 'srcIn'
                  }
                },
              }),
              context);
          final filter = ColorFilter.mode(color, BlendMode.srcIn);
          final nativePaint = Paint()
            ..color = color
            ..colorFilter = filter;
          expect(RestageDecoders.colorFilter(source, ['filter']), filter);
          final paint = RestageDecoders.paint(source, ['paint'])!;
          expect(paint.color, nativePaint.color);
          expect(paint.color.colorSpace, nativePaint.color.colorSpace);
          expect(paint.colorFilter, nativePaint.colorFilter);
          return const SizedBox();
        })));
    expect(tester.takeException(), isNull);
  });

  testWidgets('computed colors evaluate once and retain original map aliases',
      (tester) async {
    const call = NativeBindingContract(
        type: 'installed.color',
        call: NativeCallContract(
            inputs: [],
            result: ValueType.native('flutter.Color'),
            implementation: 'color-constructor'));
    final swatch = <int, Color>{500: Colors.red};
    var calls = 0;
    final values = <MaterialColor>[];
    final adapter = NativeCallAdapter(call, (inputs, captures) {
      calls++;
      final result = MaterialColor(0xff123456, swatch);
      values.add(result);
      return NativeBinding(contract: _color, value: result);
    });
    final program = ValueProgram(nodes: [
      ValueNode('native.call', const ValueType.native('flutter.Color'), value: {
        'binding': 'make',
        'contract': call.toJson(),
        'captures': <String, String>{},
      })
    ], root: 0);
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'make': NativeBinding(contract: call, value: adapter),
        },
        child: Builder(builder: (context) {
          final source = RestageValueBinding.dataSource(
              _Source({
                'first': _envelope(program),
                'second': _envelope(program),
              }),
              context);
          expect(RestageValueBinding.isNativeValue(source, ['first']), isTrue);
          expect(calls, 0);
          final first =
              RestageDecoders.color(source, ['first'])! as MaterialColor;
          expect(calls, 1);
          expect(RestageDecoders.color(source, ['first']), same(first));
          final second =
              RestageDecoders.color(source, ['second'])! as MaterialColor;
          expect(calls, 2);
          expect(identical(first, second), isFalse);
          expect(first, same(values.first));
          expect(second, same(values.last));
          swatch[500] = Colors.blue;
          expect(first[500], same(Colors.blue));
          expect(second[500], same(Colors.blue));
          return const SizedBox();
        })));
    expect(tester.takeException(), isNull);
  });

  testWidgets('native Color locals retain each callback invocation object',
      (tester) async {
    const colorType = ValueType.native('flutter.Color');
    const call = NativeBindingContract(
        type: 'installed.color',
        call: NativeCallContract(
            inputs: [], result: colorType, implementation: 'local-color'));
    final program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('native.call', colorType, value: {
                'binding': 'make',
                'contract': call.toJson(),
                'captures': <String, String>{},
              }),
              const ValueNode('local.write', colorType,
                  inputs: [0], name: 'color'),
            ],
            root: 1,
            locals: {'color': colorType}),
        result: const BuilderResult.body(0, values: {'native': 1}),
        bodyCount: 1);
    late RestageBuilderBinding binding;
    late BuildContext host;
    final made = <MaterialColor>[];
    final seen = <Color>[];
    final runtime = Runtime()
      ..update(
          _core,
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Host': (context, source) {
              host = context;
              binding =
                  RestageBuilderBinding(source, ['slot'], context: context);
              return const SizedBox();
            },
            'Body': (context, source) {
              source = RestageValueBinding.dataSource(source, context);
              final value = RestageDecoders.color(source, ['color'])!;
              seen.add(value);
              expect(source.v<String>(['leaked']), isNull);
              return ColoredBox(color: value);
            },
          }))
      ..update(
          _root,
          rfw.parseLibraryFile('import restage.core; widget Root = Host(slot: '
              '$kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(program.encode())}, captures: {}, '
              'bodies: [(frame) => Body(color: {kind: "nativeLocal", slot: "color", type: "flutter.Color", nullable: false}, leaked: frame.values.native)]));'));
    addTearDown(runtime.dispose);
    final bodies = <Widget>[];
    late StateSetter update;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'make': NativeBinding(
              contract: call,
              value: NativeCallAdapter(call, (_, __) {
                final color = MaterialColor(0xff123456, {500: Colors.red});
                made.add(color);
                return NativeBinding(contract: _color, value: color);
              })),
        },
        child: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return Column(children: [
            RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(_root, 'Root')),
            ...bodies,
          ]);
        })));
    expect(made, isEmpty);
    for (var index = 0; index < 2; index++) {
      bodies.add(binding.build(host, {}));
      update(() {});
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(seen.last, same(made[index]));
    }
    expect(identical(made.first, made.last), isFalse);
    expect(seen.first, same(made.first));
    binding.dispose();
  });

  testWidgets('nullable results and native failures occur at Color demand',
      (tester) async {
    const call = NativeBindingContract(
        type: 'installed.nullableColor',
        call: NativeCallContract(
            inputs: [],
            result: ValueType.native('flutter.Color', nullable: true),
            implementation: 'nullable-color'));
    var calls = 0;
    final failure = StateError('native color construction');
    final program = ValueProgram(nodes: [
      ValueNode('native.call', call.call!.result, value: {
        'binding': 'make',
        'contract': call.toJson(),
        'captures': <String, String>{}
      })
    ], root: 0);
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'make': NativeBinding(
              contract: call,
              value: NativeCallAdapter(call, (_, __) {
                if (++calls > 1) throw failure;
                return null;
              })),
        },
        child: Builder(builder: (context) {
          final source = RestageValueBinding.dataSource(
              _Source({
                'null': _envelope(program),
                'failure': _envelope(program),
                'scalar': _envelope(ValueProgram(nodes: [
                  const ValueNode('literal', ValueType.integer,
                      value: 0xff123456)
                ], root: 0)),
              }),
              context);
          expect(
              RestageValueBinding.isNativeValue(source, ['failure']), isTrue);
          expect(calls, 0);
          expect(RestageDecoders.color(source, ['null']), isNull);
          expect(RestageDecoders.color(source, ['null']), isNull);
          expect(calls, 1);
          expect(() => RestageDecoders.color(source, ['failure']),
              throwsA(same(failure)));
          expect(calls, 2);
          expect(RestageDecoders.color(source, ['scalar']),
              const Color(0xff123456));
          return const SizedBox();
        })));
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing wrong and unbound native colors fail closed',
      (tester) async {
    const nullable =
        NativeBindingContract(type: 'flutter.Color', nullable: true);
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'null': NativeBinding<Color?>(contract: nullable, value: null),
          'wrong': NativeBinding(contract: _color, value: Object()),
        },
        child: Builder(builder: (context) {
          DataSource source(Object? value) =>
              RestageValueBinding.dataSource(_Source(value), context);
          expect(RestageDecoders.color(source(nullable.reference('null')), []),
              isNull);
          expect(RestageDecoders.color(source(null), []), isNull);
          for (final reference in [
            _color.reference('missing'),
            _color.reference('wrong'),
            _color.reference('null'),
            {..._color.reference('missing'), 'type': 'flutter.Key'},
            {
              'kind': 'nativeLocal',
              'slot': 'missing',
              'type': 'flutter.Color',
              'nullable': false
            },
          ]) {
            expect(() => RestageDecoders.color(source(reference), []),
                throwsFormatException);
            expect(() => RestageDecoders.color(_Source(reference), []),
                throwsFormatException);
          }
          return const SizedBox();
        })));
    expect(tester.takeException(), isNull);
  });
}
