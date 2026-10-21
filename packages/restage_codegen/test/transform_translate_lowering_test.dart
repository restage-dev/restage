import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
    'resolved app TransformTranslate cannot bind the native catalog entry',
    () async {
      const source = '''
import 'package:flutter/widgets.dart';

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

class TransformTranslate extends StatelessWidget {
  const TransformTranslate({required this.offset});
  final Offset offset;
  @override
  Widget build(BuildContext context) => const Text('App widget');
}

@PaywallSource(id: 'foreign_identity')
class IdentitySurface extends StatelessWidget {
  const IdentitySurface();
  @override
  Widget build(BuildContext context) => TransformTranslate(offset: const Offset(1, 2));
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
          contains("Widget 'TransformTranslate' is not a known catalog widget"),
        ),
      );
    },
  );

  for (final scenario in <String, (String, String)>{
    'function': (
      'Widget TransformTranslate({required Offset offset}) => '
          "const Text('Foreign helper');",
      'TransformTranslate(offset: const Offset(1, 2))',
    ),
  }.entries) {
    test(
        'resolved dependency ${scenario.key} TransformTranslate '
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
          contains('TransformTranslate'),
        ),
      );
    });
  }

  test(
    'unresolved TransformTranslate retains the catalog name fallback',
    () async {
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
        await parseExpressionForTest(
          'TransformTranslate(offset: const Offset(1, 2))',
        ),
      );
      expect(result.issues, isEmpty);
      expect(result.dsl, startsWith('TransformTranslate('));
    },
  );

  test('native translation compiles resolved Flutter source at capability 13',
      () async {
    final expressions = {
      'literal': '''
      Transform.translate(
        offset: const Offset(-12.5, 8),
        transformHitTests: false,
        filterQuality: FilterQuality.low,
        child: const SizedBox(width: 30, height: 20),
      )''',
      'integer': 'Transform.translate(offset: const Offset(12, -8))',
      'zero': 'Transform.translate(offset: Offset.zero)',
      'live': 'Transform.translate(offset: Offset(dx, dy))',
      'aliased': '''
      flutter.Transform.translate(
        offset: flutter.Offset(dx, dy),
        child: const flutter.SizedBox(width: 30, height: 20),
      )''',
    };
    final sources = {
      for (final scenario in expressions.entries)
        'apps_examples|lib/paywalls/translate_${scenario.key}.dart': '''
          import 'package:flutter/widgets.dart';
          import 'package:flutter/widgets.dart' as flutter;

          class PaywallSource {
            const PaywallSource({required this.id});
            final String id;
          }

          @PaywallSource(id: 'translate_${scenario.key}')
          class TranslationSurface extends StatelessWidget {
            const TranslationSurface({required this.dx, required this.dy});
            final double dx;
            final double dy;
            @override
            Widget build(BuildContext context) => ${scenario.value};
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
          AssetId('apps_examples', 'assets/paywalls/translate_$id.rfwtxt'),
        ),
      );
      final transform = library.widgets.single.root as fmt.ConstructorCall;
      expect(transform.name, 'TransformTranslate', reason: id);
      final offset = transform.arguments['offset']! as Map<Object?, Object?>;
      if (id == 'live' || id == 'aliased') {
        for (final axis in {'x': 'dx', 'y': 'dy'}.entries) {
          expect(
            offset[axis.key],
            isA<fmt.DataReference>().having(
              (reference) => reference.parts,
              'parts',
              ['context', axis.value],
            ),
          );
        }
      } else {
        expect(
          offset,
          switch (id) {
            'literal' => {'x': -12.5, 'y': 8.0},
            'integer' => {'x': 12.0, 'y': -8.0},
            _ => {'x': 0.0, 'y': 0.0},
          },
        );
      }
      if (id == 'literal') {
        expect(transform.arguments['transformHitTests'], false);
        expect(transform.arguments['filterQuality'], 'low');
        final child = transform.arguments['child']! as fmt.ConstructorCall;
        expect(child.name, 'SizedBox');
        expect(child.arguments, {'width': 30.0, 'height': 20.0});
      }
      for (final path in ['translate_$id', 'screens/paywall_translate_$id']) {
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
          13,
          reason: path,
        );
      }
    }
  });
}
