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
    'resolved app TabBarView cannot bind the native catalog entry',
    () async {
      const source = '''
import 'package:flutter/widgets.dart';

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

class TabBarView extends StatelessWidget {
  const TabBarView({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => const Text('App widget');
}

@PaywallSource(id: 'foreign_identity')
class IdentitySurface extends StatelessWidget {
  const IdentitySurface();
  @override
  Widget build(BuildContext context) => TabBarView(children: const <Widget>[]);
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
          contains("Widget 'TabBarView' is not a known catalog widget"),
        ),
      );
    },
  );

  for (final scenario in <String, (String, String)>{
    'function': (
      'Widget TabBarView({required List<Widget> children}) => '
          "const Text('Foreign helper');",
      'TabBarView(children: const <Widget>[])',
    ),
    'extension constructor': (
      '''
extension type TabBarView._(Widget value) implements Widget {
  TabBarView({required List<Widget> children})
      : value = const Text('Foreign widget');
}
''',
      'TabBarView(children: const <Widget>[])',
    ),
    'function variable': (
      'final TabBarView = ({required List<Widget> children}) => '
          "const Text('Foreign helper');",
      'TabBarView(children: const <Widget>[])',
    ),
    'callable object': (
      '''
class ForeignCallable {
  const ForeignCallable();
  Widget call({required List<Widget> children}) => const Text('Foreign helper');
}
const TabBarView = ForeignCallable();
''',
      'TabBarView(children: const <Widget>[])',
    ),
    'dynamic receiver': (
      '''
class ForeignReceiver {
  Widget render({required List<Widget> children}) => const Text('Foreign helper');
}
dynamic TabBarView = ForeignReceiver();
''',
      'TabBarView.render(children: const <Widget>[])',
    ),
  }.entries) {
    test(
        'resolved dependency ${scenario.key} TabBarView '
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
          contains('TabBarView'),
        ),
      );
    });
  }

  test('unresolved TabBarView retains the catalog name fallback', () async {
    final catalog = decodeCatalog(
      File(
        '../restage_material/lib/src/widget_catalog/catalog.json',
      ).readAsStringSync(),
    );
    final translator = ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    );
    final result = translator.translate(
      await parseExpressionForTest('TabBarView(children: const <Widget>[])'),
    );
    expect(result.issues, isEmpty);
    expect(result.dsl, startsWith('TabBarView('));
  });

  test('canonical catalog emits the native factory and gesture import',
      () async {
    final catalog = File(
      '../restage_material/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync();
    final result = await testBuilder(
      factoryFunctionBuilder(BuilderOptions.empty),
      {'restage_material|lib/src/widget_catalog/catalog.json': catalog},
      rootPackage: 'restage_material',
      outputs: {
        'restage_material|lib/src/registration.g.dart': decodedMatches(
          predicate<String>(
            (source) {
              final factory = source
                  .split('Widget buildTabBarView(')
                  .last
                  .split('/// Builds')
                  .first;
              return source.contains(
                    "import 'package:flutter/gestures.dart' show DragStartBehavior;",
                  ) &&
                  source.contains("'TabBarView': buildTabBarView") &&
                  factory.contains('return TabBarView(') &&
                  factory.contains('RestageDecoders.positiveLayoutScalar(') &&
                  factory.contains('DragStartBehavior.start') &&
                  factory.contains('Clip.hardEdge') &&
                  !factory.contains('controller:') &&
                  !factory.contains('physics:');
            },
            'native TabBarView factory with positive fractions and gestures',
          ),
        ),
      },
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  });

  group('resolved native TabBarView authoring', () {
    late TestBuilderResult result;
    const arguments = {
      'defaults': '',
      'aliased': '',
      'typedef': '',
      'below_one': 'viewportFraction: 0.75,',
      'equal_one': 'viewportFraction: 1,',
      'above_one': 'viewportFraction: 1.5,',
      'authored_enums':
          'clipBehavior: Clip.none, dragStartBehavior: DragStartBehavior.down,',
      'dynamic': 'viewportFraction: fraction,',
    };

    setUpAll(() async {
      final sources = {
        for (final scenario in arguments.entries)
          'apps_examples|lib/paywalls/tab_${scenario.key}.dart': _source(
            'tab_${scenario.key}',
            scenario.value,
            widgetType: switch (scenario.key) {
              'aliased' => 'flutter.TabBarView',
              'typedef' => 'NativeTabView',
              _ => 'TabBarView',
            },
          ),
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      for (final source in sources.entries) {
        readerWriter.testing
            .writeString(AssetId.parse(source.key), source.value);
      }
      result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    });

    for (final scenario in arguments.keys) {
      test('$scenario emits native composition and capability 15', () {
        final id = 'tab_$scenario';
        final text = result.readerWriter.testing.readString(
          AssetId('apps_examples', 'assets/paywalls/$id.rfwtxt'),
        );
        final root = fmt.parseLibraryFile(text).widgets.single.root
            as fmt.ConstructorCall;
        expect(root.name, 'DefaultTabController');
        expect(root.arguments['length'], 2);
        expect(root.arguments['initialIndex'], 1);
        final scaffold = root.arguments['child']! as fmt.ConstructorCall;
        expect(scaffold.name, 'Scaffold');
        final appBar = scaffold.arguments['appBar']! as fmt.ConstructorCall;
        expect(
          (appBar.arguments['bottom']! as fmt.ConstructorCall).name,
          'TabBar',
        );
        final view = scaffold.arguments['body']! as fmt.ConstructorCall;
        expect(view.name, 'TabBarView');
        expect(
          (view.arguments['children']! as List).map(
            (child) => (child as fmt.ConstructorCall).arguments['text'],
          ),
          ['First page', 'Second page'],
        );
        expect(text, isNot(contains('RestagePager')));
        expect(view.arguments.containsKey('controller'), isFalse);
        expect(view.arguments.containsKey('physics'), isFalse);
        if (scenario == 'defaults' ||
            scenario == 'aliased' ||
            scenario == 'typedef') {
          expect(view.arguments.keys, ['children']);
        } else if (scenario == 'authored_enums') {
          expect(view.arguments['clipBehavior'], 'none');
          expect(view.arguments['dragStartBehavior'], 'down');
        } else if (scenario == 'dynamic') {
          expect(
            view.arguments['viewportFraction'],
            isA<fmt.DataReference>().having(
              (value) => value.parts,
              'parts',
              ['context', 'fraction'],
            ),
          );
        } else {
          expect(
            view.arguments['viewportFraction'],
            {
              'below_one': 0.75,
              'equal_one': 1.0,
              'above_one': 1.5,
            }[scenario],
          );
        }
        for (final path in [id, 'screens/paywall_$id']) {
          final sidecar = jsonDecode(
            result.readerWriter.testing.readString(
              AssetId('apps_examples', 'assets/paywalls/$path.capability.json'),
            ),
          ) as Map<String, dynamic>;
          expect((sidecar['manifest'] as Map)['builtInFloor'], 15);
          expect(
            result.readerWriter.testing.readBytes(
              AssetId('apps_examples', 'assets/paywalls/$path.rfw'),
            ),
            isNotEmpty,
          );
        }
      });
    }
  });

  for (final property in ['controller', 'physics']) {
    test('explicit $property expressions diagnose unsupported native slots',
        () async {
      final source = _source('tab_$property', '$property: $property,');
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      final id = AssetId('apps_examples', 'lib/paywalls/tab_$property.dart');
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
          contains('[unknownProperty]'),
          contains(
            "Property '$property' is not declared on 'TabBarView'",
          ),
        ),
      );
    });
  }
}

String _source(
  String id,
  String arguments, {
  String widgetType = 'TabBarView',
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as flutter;
import 'package:flutter/gestures.dart';

typedef NativeTabView = flutter.TabBarView;

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

@PaywallSource(id: '$id')
class NativeTabs extends StatelessWidget {
  const NativeTabs({required this.fraction, this.controller, this.physics});
  final double fraction;
  final TabController? controller;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: 1,
    child: Scaffold(
      appBar: AppBar(bottom: TabBar(tabs: [Tab(text: 'One'), Tab(text: 'Two')])),
      body: $widgetType(
        $arguments
        children: [Text('First page'), Text('Second page')],
      ),
    ),
  );
}
''';
