import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_svg/src/native_values.dart';
import 'package:rfw/rfw.dart';

class _Source extends Fake implements DataSource {
  _Source(this.values);
  final Map<String, Object?> values;
  Object? at(List<Object> path) {
    Object? value = values;
    for (final key in path) {
      value = value is Map
          ? value[key]
          : value is List && key is int && key >= 0 && key < value.length
          ? value[key]
          : null;
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
    final value = at(path);
    return value is T ? value : null;
  }
}

void main() {
  testWidgets(
    'native SVG consumers retain computed result identity and evaluate once',
    (tester) async {
      Widget error(BuildContext context, Object error, StackTrace stack) =>
          const SizedBox();
      Widget image(BuildContext context, Widget child) => child;
      final cases = <(String, Object, Object? Function(DataSource))>[
        (
          'vector_graphics.BytesLoader',
          const SvgStringLoader('<svg/>'),
          (s) => SvgNativeValues.loader(_context!, s, []),
        ),
        (
          'dart.io.File',
          File('installed.svg'),
          (s) => SvgNativeValues.file(_context!, s, []),
        ),
        (
          'flutter_svg.SvgErrorWidgetBuilder(package:flutter/src/widgets/framework.dart#BuildContext,dart:core#Object,dart:core#StackTrace)->package:flutter/src/widgets/framework.dart#Widget',
          error,
          (s) => SvgNativeValues.errorBuilder(_context!, s, []),
        ),
        (
          'flutter_svg.SvgImageWidgetBuilder(package:flutter/src/widgets/framework.dart#BuildContext,package:flutter/src/widgets/framework.dart#Widget)->package:flutter/src/widgets/framework.dart#Widget',
          image,
          (s) => SvgNativeValues.imageBuilder(_context!, s, []),
        ),
        (
          'dart:typed_data#Uint8List',
          Uint8List.fromList([1, 2]),
          (s) => SvgNativeValues.bytes(s, []),
        ),
        (
          'dart:core#Map<dart:core#String,dart:core#String>',
          <String, String>{'X-Svg': 'original'},
          (s) => SvgNativeValues.headers(s, []),
        ),
        (
          'package:flutter_svg/src/loaders.dart#SvgTheme',
          const SvgTheme(fontSize: 19),
          (s) => SvgNativeValues.theme(s, []),
        ),
        (
          'dart:ui#ColorFilter',
          const ColorFilter.mode(Color(0xff123456), BlendMode.srcIn),
          (s) => SvgNativeValues.colorFilter(s, []),
        ),
      ];
      for (final (type, value, read) in cases) {
        var calls = 0;
        final output = NativeBindingContract(type: type);
        final installed = NativeBindingContract(
          type: 'installed.svg-reader',
          call: NativeCallContract(
            inputs: [],
            result: ValueType.native(type),
            implementation: type,
          ),
        );
        final adapter = NativeCallAdapter(installed, (inputs, captures) {
          calls++;
          return NativeBinding(contract: output, value: value);
        });
        final program = ValueProgram(
          nodes: [
            ValueNode(
              'native.call',
              ValueType.native(type),
              value: {
                'binding': 'factory',
                'contract': installed.toJson(),
                'captures': <String, String>{},
              },
            ),
          ],
          root: 0,
        );
        late DataSource source;
        await tester.pumpWidget(
          RestageNativeValues(
            bindings: {
              'factory': NativeBinding(contract: installed, value: adapter),
            },
            child: Builder(
              builder: (context) {
                _context = context;
                source = RestageValueBinding.dataSource(
                  _Source({
                    'version': 1,
                    'program': program.encode(),
                    'captures': <String, Object?>{},
                  }),
                  context,
                );
                return const SizedBox();
              },
            ),
          ),
        );
        expect(RestageValueBinding.isNativeValue(source, []), isTrue);
        expect(calls, 0, reason: type);
        expect(read(source), same(value), reason: type);
        expect(read(source), same(value), reason: type);
        expect(calls, 1, reason: type);
      }
      await tester.pumpWidget(const SizedBox());
      _context = null;
    },
  );

  testWidgets(
    'wire bytes and headers stay bounded while native values pass unchanged',
    (tester) async {
      for (final (type, value, read)
          in <(String, Object, Object? Function(DataSource))>[
            (
              'dart:typed_data#Uint8List',
              Uint8List(1048577),
              (s) => SvgNativeValues.bytes(s, []),
            ),
            (
              'dart:core#Map<dart:core#String,dart:core#String>',
              {for (var i = 0; i < 1025; i++) '$i': 'value'},
              (s) => SvgNativeValues.headers(s, []),
            ),
          ]) {
        final contract = NativeBindingContract(type: type);
        late DataSource source;
        await tester.pumpWidget(
          RestageNativeValues(
            bindings: {
              'value': NativeBinding(contract: contract, value: value),
            },
            child: Builder(
              builder: (context) {
                source = RestageValueBinding.dataSource(
                  _Source(contract.reference('value')),
                  context,
                );
                return const SizedBox();
              },
            ),
          ),
        );
        expect(read(source), same(value));
      }
      expect(
        () => SvgNativeValues.bytes(
          _Source({'value': List<int>.filled(1048577, 0)}),
          ['value'],
        ),
        throwsArgumentError,
      );
      expect(
        () => SvgNativeValues.headers(
          _Source({
            'value': List<Map<String, String>>.generate(
              1025,
              (i) => {'key': 'X-$i', 'value': 'valid'},
            ),
          }),
          ['value'],
        ),
        throwsArgumentError,
      );
    },
  );
}

BuildContext? _context;
