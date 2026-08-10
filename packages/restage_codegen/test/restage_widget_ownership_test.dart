import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/restage_widget_package_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
    'infers exact owner, Dart name, null category, typed const, and subclass',
    () async {
      final report = await _probe({
        'lib/widgets/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          /// A customer card.
          @RestageWidget()
          class ProductCard {
            const ProductCard();
          }
        ''',
        'lib/product_widgets.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          export 'widgets/card.dart';

          final class ProductLibrary extends WidgetLibrary {
            const ProductLibrary();
            @override
            final String namespace = 'acme.product';
          }

          const WidgetLibrary productLibrary = ProductLibrary();

          @RestageLibrary(library: productLibrary)
          const restageProductLibrary = 0;
        ''',
        'lib/admin_widgets.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageLibrary(
            library: WidgetLibrary.custom('acme.admin'),
          )
          const restageAdminLibrary = 0;
        ''',
      });

      expect(
        report,
        contains(
          'widget=package:apps_examples/widgets/card.dart#ProductCard|'
          'ProductCard|acme.product|null',
        ),
      );
      expect(report, isNot(contains('issue=')));
    },
  );

  test('preserves explicit name and category overrides', () async {
    final report = await _probe({
      'lib/widgets/card.dart': '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        /// A customer card.
        @RestageWidget(
          name: 'HeroCard',
          category: WidgetCategory.decoration,
        )
        class ProductCard {
          const ProductCard();
        }
      ''',
      'lib/product_widgets.dart': _barrel(
        namespace: 'acme.product',
        export: 'widgets/card.dart',
      ),
    });

    expect(report, contains('|HeroCard|acme.product|decoration'));
    expect(report, isNot(contains('issue=')));
  });

  test('reports no owner with export-or-explicit guidance', () async {
    final report = await _probe({
      'lib/card.dart': '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        /// A customer card.
        @RestageWidget()
        class ProductCard {
          const ProductCard();
        }
      ''',
    });

    expect(report, contains('has no owning @RestageLibrary export'));
    expect(report, contains('provide an explicit `library` override'));
  });

  test('sorts several owners and accepts explicit disambiguation', () async {
    final ambiguous = await _probe({
      'lib/card.dart': _card(),
      'lib/zeta.dart': _barrel(
        namespace: 'acme.zeta',
        export: 'card.dart',
      ),
      'lib/alpha.dart': _barrel(
        namespace: 'acme.alpha',
        export: 'card.dart',
      ),
    });
    expect(
      ambiguous,
      contains(
        'multiple owning @RestageLibrary exports: '
        '"acme.alpha", "acme.zeta"',
      ),
    );

    final selected = await _probe({
      'lib/card.dart': _card(explicitLibrary: 'acme.zeta'),
      'lib/zeta.dart': _barrel(
        namespace: 'acme.zeta',
        export: 'card.dart',
      ),
      'lib/alpha.dart': _barrel(
        namespace: 'acme.alpha',
        export: 'card.dart',
      ),
    });
    expect(selected, contains('|ProductCard|acme.zeta|null'));
    expect(selected, isNot(contains('issue=')));
  });

  test('rejects an explicit owner mismatch against exact exports', () async {
    final report = await _probe({
      'lib/card.dart': _card(explicitLibrary: 'acme.other'),
      'lib/zeta.dart': _barrel(
        namespace: 'acme.zeta',
        export: 'card.dart',
      ),
      'lib/alpha.dart': _barrel(
        namespace: 'acme.alpha',
        export: 'card.dart',
      ),
    });

    expect(report, contains('explicitly selects "acme.other"'));
    expect(report, contains('are "acme.alpha", "acme.zeta"'));
  });

  test('same bare name in another library is not ownership evidence', () async {
    final report = await _probe({
      'lib/owned/card.dart': _card(),
      'lib/unowned/card.dart': _card(),
      'lib/catalog.dart': _barrel(
        namespace: 'acme.product',
        export: 'owned/card.dart',
      ),
    });

    expect(report, contains('owned/card.dart#ProductCard|ProductCard|'));
    expect(
      report,
      allOf(
        contains('unowned/card.dart#ProductCard|'),
        contains('ProductCard has no owning @RestageLibrary export'),
      ),
    );
  });

  test('rejects an explicit whitespace-only name', () async {
    final report = await _probe({
      'lib/card.dart': _card(explicitName: '   '),
      'lib/catalog.dart': _barrel(
        namespace: 'acme.product',
        export: 'card.dart',
      ),
    });

    expect(report, contains('has an empty explicit `name`'));
    expect(report, contains('omit the override to use the Dart class name'));
  });
}

String _card({String? explicitLibrary, String? explicitName}) => '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  /// A customer card.
  @RestageWidget(
    ${explicitName == null ? '' : "name: '$explicitName',"}
    ${explicitLibrary == null ? '' : "library: WidgetLibrary.custom('$explicitLibrary'),"}
  )
  class ProductCard {
    const ProductCard();
  }
''';

String _barrel({required String namespace, required String export}) => '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  export '$export';

  @RestageLibrary(library: WidgetLibrary.custom('$namespace'))
  const restageLibrary = 0;
''';

Future<String> _probe(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final assetMap = {
    for (final entry in sources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  for (final entry in assetMap.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  String? report;
  await testBuilder(
    _OwnershipProbeBuilder((value) => report = value),
    assetMap,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    outputs: {
      'apps_examples|lib/ownership_probe.txt': anything,
    },
  );
  return report!;
}

final class _OwnershipProbeBuilder implements Builder {
  const _OwnershipProbeBuilder(this.onReport);

  final void Function(String) onReport;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['ownership_probe.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final sources = <ResolvedPackageLibrary>[];
    await for (final assetId in buildStep.findAssets(Glob('lib/**.dart'))) {
      final LibraryElement library;
      try {
        library = await buildStep.resolver.libraryFor(
          assetId,
          allowSyntaxErrors: true,
        );
      } on NonLibraryAssetException {
        continue;
      }
      sources.add((assetId: assetId, library: library));
    }
    final facts = indexRestageWidgetPackage(sources);
    final lines = <String>[];
    for (final source in sources) {
      final result = visitRestageWidgetsInPackage(
        source.library,
        source.assetId,
        packageFacts: facts,
      );
      for (final widget in result.widgets) {
        lines.add(
          'widget=${widget.flutterType}|${widget.name}|'
          '${widget.library.namespace}|${widget.category?.name}',
        );
      }
      for (final issue in result.issues) {
        lines.add('issue=${issue.location}|${issue.message}');
      }
    }
    lines.sort();
    final report = const LineSplitter().convert(lines.join('\n')).join('\n');
    onReport(report);
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/ownership_probe.txt'),
      report,
    );
  }
}
