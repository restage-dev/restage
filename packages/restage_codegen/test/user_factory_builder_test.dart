import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('UserFactoryBuilder', () {
    test('emits user_factories.g.dart when @RestageWidget classes are found',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeBadge',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.action,
          description: 'Promo badge.',
        )
        class AcmeBadge {
          const AcmeBadge({required this.label});
          @RestageProperty(description: 'Visible label.', required: true)
          final String label;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_badge.dart'),
        widgetSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/acme_badge.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
              contains("import 'package:flutter/widgets.dart'"),
              contains(
                "import 'package:restage/restage.dart'",
              ),
              // Generated file does not import rfw directly — the SDK
              // re-exports DataSource / ArgumentDecoders /
              // LocalWidgetBuilder, so the customer package isn't
              // required to depend on rfw.
              isNot(contains("import 'package:rfw/rfw.dart'")),
              contains(
                "import 'package:apps_examples/widgets/acme_badge.dart'",
              ),
              contains('void registerRestageCustomerWidgets()'),
              contains("WidgetLibrary.custom('acme.design_system')"),
              contains(
                "RestageWidgetFactory(name: 'AcmeBadge', "
                'builder: _buildAcmeBadge)',
              ),
              contains(
                'Widget _buildAcmeBadge(BuildContext context, '
                'DataSource source)',
              ),
              // An all-simple-property package (no structured
              // types) still emits the customer library aliased (`as s0`),
              // so the constructor must be qualified with that alias. A
              // bare `AcmeBadge(...)` reference is undefined under the
              // prefixed import and fails analysis.
              contains('return s0.AcmeBadge('),
              isNot(contains('return AcmeBadge(')),
            ]),
          ),
        },
      );
    });

    test(
        'generated user_factories.g.dart ANALYZES CLEAN for an all-simple '
        'package with no structured-type properties', () async {
      // The durable net: a string pin on the aliased call shape is
      // analyze-blind as a class, so this resolves the generated library
      // through the analyzer and asserts zero error-severity diagnostics.
      // Before the fix the constructor emitted bare (`AcmeBadge(...)`) under
      // the prefixed import (`as s0`), an `undefined_function` error this
      // resolution catches. The widget is a real `StatelessWidget` so the
      // generated factory's `Widget` return type checks against it.
      const widgetSource = '''
        import 'package:flutter/widgets.dart';
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeBadge',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.action,
          description: 'Promo badge.',
        )
        class AcmeBadge extends StatelessWidget {
          const AcmeBadge({required this.label, super.key});
          @RestageProperty(description: 'Visible label.', required: true)
          final String label;
          @override
          Widget build(BuildContext context) => Text(label);
        }
      ''';

      // The fixture is a real `StatelessWidget`, so the builder needs the
      // Flutter sources loaded to resolve it — hence `apps_examples` (which
      // carries Flutter in its pubspec) rather than the dart-only root.
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_badge.dart'),
        widgetSource,
      );

      // `testBuilders` (plural) + `flattenOutput` leaves the generated asset
      // readable back off `result.readerWriter` — the same shape the
      // onboarding compile fixtures use.
      final result = await testBuilders(
        [const UserFactoryBuilder(BuilderOptions.empty)],
        {'apps_examples|lib/widgets/acme_badge.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final generated = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );

      await resolveSources(
        {
          'apps_examples|lib/widgets/acme_badge.dart': widgetSource,
          'apps_examples|lib/user_factories.g.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('apps_examples', 'lib/user_factories.g.dart'),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
                'Generated user_factories.g.dart did not resolve.');
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(
            errors,
            isEmpty,
            reason: 'generated factories must analyze clean; a bare '
                'constructor under a prefixed import is undefined_function',
          );
        },
        resolverFor: 'apps_examples|lib/user_factories.g.dart',
        rootPackage: 'apps_examples',
        readAllSourcesFromFilesystem: true,
      );
    });

    test('same-named cross-library widget constructors analyze clean',
        () async {
      String widgetSource(String catalogName) => '''
        import 'package:flutter/widgets.dart';
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: '$catalogName',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.action,
          description: 'Promo badge.',
        )
        class Badge extends StatelessWidget {
          const Badge({required this.label, super.key});
          @RestageProperty(description: 'Visible label.', required: true)
          final String label;
          @override
          Widget build(BuildContext context) => Text(label);
        }
      ''';
      final firstSource = widgetSource('FirstBadge');
      final secondSource = widgetSource('SecondBadge');
      final sources = {
        'apps_examples|lib/widgets/first_badge.dart': firstSource,
        'apps_examples|lib/widgets/second_badge.dart': secondSource,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      for (final entry in sources.entries) {
        final path = entry.key.substring(entry.key.indexOf('|') + 1);
        readerWriter.testing.writeString(
          AssetId('apps_examples', path),
          entry.value,
        );
      }

      final result = await testBuilders(
        [const UserFactoryBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final generated = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );
      expect(generated, contains('return s0.Badge('));
      expect(generated, contains('return s1.Badge('));

      await resolveSources(
        {
          ...sources,
          'apps_examples|lib/user_factories.g.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('apps_examples', 'lib/user_factories.g.dart'),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
              'Same-name generated user_factories.g.dart did not resolve.',
            );
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: generated);
        },
        resolverFor: 'apps_examples|lib/user_factories.g.dart',
        rootPackage: 'apps_examples',
        readAllSourcesFromFilesystem: true,
      );
    });

    test('case-distinct constructor presence locals analyze clean', () async {
      const widgetSource = r'''
        import 'package:flutter/widgets.dart';
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'CaseDistinctProbe',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'Case-distinct constructor probe.',
        )
        class CaseDistinctProbe extends StatelessWidget {
          const CaseDistinctProbe({
            this.foo = 'lower',
            this.Foo = 'upper',
            super.key,
          });

          @RestageProperty(description: 'Lower-case value.')
          final String? foo;

          @RestageProperty(description: 'Upper-case value.')
          final String? Foo;

          @override
          Widget build(BuildContext context) => Text('${foo ?? ''}${Foo ?? ''}');
        }
      ''';
      final sources = {
        'apps_examples|lib/widgets/case_distinct_probe.dart': widgetSource,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/case_distinct_probe.dart'),
        widgetSource,
      );

      final result = await testBuilders(
        [const UserFactoryBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final generated = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );

      await resolveSources(
        {
          ...sources,
          'apps_examples|lib/user_factories.g.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('apps_examples', 'lib/user_factories.g.dart'),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
              'Case-distinct generated user_factories.g.dart did not resolve.',
            );
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: generated);
        },
        resolverFor: 'apps_examples|lib/user_factories.g.dart',
        rootPackage: 'apps_examples',
        readAllSourcesFromFilesystem: true,
      );
    });

    test('does not emit user_factories.g.dart when no @RestageWidget classes',
        () async {
      const plainSource = '''
        class Plain { const Plain(); }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/plain.dart'),
        plainSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/plain.dart': plainSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });
  });
}
