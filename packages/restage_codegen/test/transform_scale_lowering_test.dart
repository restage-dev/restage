import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
    'resolved app TransformScale cannot bind the native catalog entry',
    () async {
      const source = '''
import 'package:flutter/widgets.dart';

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

class TransformScale extends StatelessWidget {
  const TransformScale({required this.scale});
  final double scale;
  @override
  Widget build(BuildContext context) => const Text('App widget');
}

@PaywallSource(id: 'foreign_identity')
class IdentitySurface extends StatelessWidget {
  const IdentitySurface();
  @override
  Widget build(BuildContext context) => TransformScale(scale: 2.0);
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      final id = AssetId('apps_examples', 'lib/paywalls/foreign_identity.dart');
      readerWriter.testing.writeString(id, source);
      final messages = <String>[];
      final result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {id.toString(): source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => messages.add(record.message),
        outputs: const {},
      );
      expect(result.succeeded, isFalse);
      expect(
        messages.join('\n'),
        allOf(
          contains('[unknownWidget]'),
          contains("Widget 'TransformScale' is not a known catalog widget"),
        ),
      );
    },
  );

  for (final scenario in <String, (String, String)>{
    'function': (
      'Widget TransformScale({required double scale}) => '
          "const Text('Foreign helper');",
      'TransformScale(scale: 2.0)',
    ),
  }.entries) {
    test(
        'resolved dependency ${scenario.key} TransformScale '
        'cannot bind native entry', () async {
      final source = '''
import 'package:flutter/widgets.dart';
import 'package:restage_core/foreign_identity_probe.dart';

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

@PaywallSource(id: 'foreign_callable')
class IdentitySurface extends StatelessWidget {
  const IdentitySurface();
  @override
  Widget build(BuildContext context) => ${scenario.value.$2};
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      final id = AssetId('apps_examples', 'lib/paywalls/foreign_callable.dart');
      readerWriter.testing
        ..writeString(
          AssetId('restage_core', 'lib/foreign_identity_probe.dart'),
          "import 'package:flutter/widgets.dart';\n${scenario.value.$1}",
        )
        ..writeString(id, source);
      final messages = <String>[];
      final result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {id.toString(): source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => messages.add(record.message),
        outputs: const {},
      );
      expect(result.succeeded, isFalse);
      expect(
        messages.join('\n'),
        allOf(
          anyOf(
            contains('[unknownWidget]'),
            contains('[unrecognizedMethodCall]'),
          ),
          contains('TransformScale'),
        ),
      );
    });
  }

  test('unresolved TransformScale retains the catalog name fallback', () async {
    final catalog = decodeCatalog(
      File(
        '../restage_core/lib/src/widget_catalog/catalog.json',
      ).readAsStringSync(),
    );
    final translator = ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    );
    final result = translator.translate(
      await parseExpressionForTest('TransformScale(scale: 2.0)'),
    );
    expect(result.issues, isEmpty);
    expect(result.dsl, startsWith('TransformScale('));
  });

  test('native scaling compiles resolved source with nullable presence at 14',
      () async {
    final expressions = {
      'uniform': '''
Transform.scale(
        scale: -1,
        child: const SizedBox(width: 30, height: 20),
      )''',
      'axes': '''
Transform.scale(
        scaleX: 0,
        scaleY: 1.5,
        origin: const Offset(4, -3),
        alignment: null,
        transformHitTests: false,
        filterQuality: FilterQuality.medium,
        child: const SizedBox(width: 30, height: 20),
      )''',
      'x': 'Transform.scale(scaleX: 2)',
      'y': 'Transform.scale(scaleY: -3)',
      'null_uniform': 'Transform.scale(scale: null, scaleX: 2)',
      'concrete':
          'Transform.scale(scale: 2, alignment: const Alignment(1, -1))',
      'directional': '''
flutter.Transform.scale(
        scale: 2, alignment: flutter.AlignmentDirectional.centerStart,
      )''',
      'live': 'Transform.scale(scale: factor, alignment: alignment)',
      'conditional': '''
Transform.scale(
        scale: enabled ? 0 : -1,
        alignment: enabled ? AlignmentDirectional.topEnd : null,
      )''',
    };
    final sources = {
      for (final scenario in expressions.entries)
        'apps_examples|lib/paywalls/scale_${scenario.key}.dart': '''
          import 'package:flutter/widgets.dart';
          import 'package:flutter/widgets.dart' as flutter;
          class PaywallSource {
            const PaywallSource({required this.id});
            final String id;
          }
          @PaywallSource(id: 'scale_${scenario.key}')
          class ScaleSurface extends StatelessWidget {
            const ScaleSurface({required this.factor,
              required this.enabled});
            final double factor;
            final bool enabled;
            @override
            Widget build(BuildContext context) {
              ${scenario.key == 'live' ? 'final alignment = enabled ? const Alignment(1, -1) : null;' : ''}
              return ${scenario.value};
            }
          }
        ''',
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    for (final source in sources.entries) {
      readerWriter.testing.writeString(AssetId.parse(source.key), source.value);
    }
    final result = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    for (final id in expressions.keys) {
      final library = fmt.parseLibraryFile(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/paywalls/scale_$id.rfwtxt'),
        ),
      );
      final transform = library.widgets.single.root as fmt.ConstructorCall;
      expect(transform.name, 'TransformScale', reason: id);
      final args = transform.arguments;
      if (id == 'uniform') {
        expect(args['scale'], -1.0);
        expect(args.containsKey('alignment'), isFalse);
        final child = args['child']! as fmt.ConstructorCall;
        expect(child.arguments, {'width': 30.0, 'height': 20.0});
      } else if (id == 'axes') {
        expect(args['scaleX'], 0.0);
        expect(args['scaleY'], 1.5);
        expect(args['origin'], {'x': 4.0, 'y': -3.0});
        expect(args['alignment'], {
          RfwConstructorPresenceProtocol.markerKey:
              RfwConstructorPresenceProtocol.version,
        });
        expect(args['transformHitTests'], false);
        expect(args['filterQuality'], 'medium');
      } else if (id == 'x' || id == 'null_uniform') {
        expect(args['scaleX'], 2.0);
      } else if (id == 'y') {
        expect(args['scaleY'], -3.0);
      } else {
        final presence = args['alignment']! as Map<Object?, Object?>;
        expect(
          presence[RfwConstructorPresenceProtocol.markerKey],
          RfwConstructorPresenceProtocol.version,
        );
        final value = presence[RfwConstructorPresenceProtocol.valueKey];
        if (id == 'live') {
          expect(value, isA<fmt.Switch>());
          expect(args['scale'], isA<fmt.DataReference>());
        } else if (id == 'concrete') {
          expect(value, {'x': 1.0, 'y': -1.0});
        } else if (id == 'directional') {
          expect(value, {'start': -1.0, 'y': 0.0});
        } else {
          expect(value, isA<fmt.Switch>());
        }
      }
      for (final path in ['scale_$id', 'screens/paywall_scale_$id']) {
        expect(
          readerWriter.testing.readBytes(
            AssetId('apps_examples', 'assets/paywalls/$path.rfw'),
          ),
          isNotEmpty,
        );
        final sidecar = jsonDecode(
          readerWriter.testing.readString(
            AssetId('apps_examples', 'assets/paywalls/$path.capability.json'),
          ),
        ) as Map<String, dynamic>;
        expect(
          (sidecar['manifest'] as Map<String, dynamic>)['builtInFloor'],
          14,
          reason: path,
        );
      }
    }
  });

  test('numeric widening belongs only to the native scale identity', () {
    WidgetEntry probe(String nativeType, WidgetLibrary library) => WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'TransformScale',
          flutterType: nativeType,
          library: library,
          category: WidgetCategory.decoration,
          description: 'Scale probe.',
          childrenSlot: ChildrenSlot.none,
          properties: const [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'scale',
              type: PropertyType.real,
              description: 'Factor.',
              constructorNullable: true,
            ),
          ],
        );
    for (final type in [
      'package:flutter/src/widgets/basic.dart#Transform.scale',
      'package:example/widgets.dart#TransformScale',
    ]) {
      for (final library in [
        WidgetLibrary.core,
        const WidgetLibrary.custom('example.widgets'),
      ]) {
        final source = emitFactoryFunction(probe(type, library))!;
        expect(
          source.contains('RestageDecoders.number('),
          type.startsWith('package:flutter/') && library == WidgetLibrary.core,
        );
      }
    }
  });
}
