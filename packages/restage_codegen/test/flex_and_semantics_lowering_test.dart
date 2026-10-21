// Row and Column carry textBaseline, which baseline alignment requires, and
// Semantics carries its flags. A custom widget's TextBaseline parameter
// decodes like any built-in enum.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

String _paywall(String name, String body) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
    return $body;
  }
}
''';

Future<TestBuilderResult> _build(Map<String, String> bodies) async {
  final sources = {
    for (final MapEntry(:key, :value) in bodies.entries)
      '$_package|lib/paywalls/$key.dart': _paywall('P$key', value),
  };
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return await testBuilders(
    [restageCodegenBuilder(BuilderOptions.empty)],
    sources,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

const _customWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

@RestageWidget(
  name: 'Baseline',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.layout,
  description: 'Aligns a label on a baseline.',
)
class Baseline {
  const Baseline({required this.textBaseline});
  @RestageProperty(description: 'The baseline to align on.')
  final TextBaseline textBaseline;
}
''';

void main() {
  group('lowering', () {
    late TestBuilderResult result;

    setUpAll(() async {
      result = await _build({
        'row_baseline': 'const Row(crossAxisAlignment: '
            'CrossAxisAlignment.baseline, textBaseline: '
            "TextBaseline.alphabetic, children: [Text('a'), Text('b')])",
        'semantics_header': "const Semantics(header: true, label: 'Plans', "
            "child: Text('Plans'))",
      });
    });

    String widget(String id) => result.readerWriter.testing
        .readString(AssetId(_package, 'assets/paywalls/$id.rfwtxt'))
        .split('\n')
        .singleWhere((line) => line.startsWith('widget '));

    test('every fixture compiles', () {
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    });

    test('Row carries textBaseline', () {
      expect(
        widget('row_baseline'),
        allOf(
          contains('crossAxisAlignment: "baseline"'),
          contains('textBaseline: "alphabetic"'),
        ),
      );
    });

    test('Semantics carries header', () {
      expect(widget('semantics_header'), contains('header: true'));
    });
  });

  test('baseline alignment without textBaseline is refused', () async {
    final result = await _build({
      'no_baseline': 'const Column(crossAxisAlignment: '
          "CrossAxisAlignment.baseline, children: [Text('a')])",
    });
    expect(
      result.errors.join('\n'),
      allOf(
        contains('[${IssueCode.missingRequiredSlot.name}] '
            'lib/paywalls/no_baseline.dart:'),
        contains('sets no textBaseline'),
      ),
    );
  });

  group('custom TextBaseline parameter', () {
    Future<TestBuilderResult> run(Builder builder) async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
        includeFlutter: true,
      );
      readerWriter.testing
          .writeString(AssetId(_package, 'lib/widgets.dart'), _customWidget);
      return testBuilder(
        builder,
        {'$_package|lib/widgets.dart': _customWidget},
        rootPackage: _package,
        readerWriter: readerWriter,
        flattenOutput: true,
      );
    }

    test('the catalog carries it as an enum', () async {
      final result =
          await run(const UserCatalogJsonBuilder(BuilderOptions.empty));
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final catalog = decodeCatalog(
        result.readerWriter.testing.readString(
          AssetId(_package, 'lib/src/widget_catalog/catalog.json'),
        ),
      );
      final property = catalog.widgets
          .singleWhere((w) => w.name == 'Baseline')
          .properties
          .singleWhere((p) => p.name == 'textBaseline');
      expect(property.type, PropertyType.enumValue);
    });

    test('the factory decodes it by name', () async {
      final result = await run(const UserFactoryBuilder(BuilderOptions.empty));
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final dart = result.readerWriter.testing
          .readString(AssetId(_package, 'lib/user_factories.g.dart'));
      expect(dart, matches(RegExp(r'enumByName<(\w+\.)?TextBaseline>')));
    });
  });
}
