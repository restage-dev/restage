import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The customer-library `capabilityVersion` stamp (the capability-floor
/// fold-in). A customer library whose widget now RENDERS a customer
/// structured property is using a NEW render capability; its declared
/// `@RestageLibrary(capabilityVersion:)` must be stamped into BOTH the catalog
/// `LibraryInfo` AND the generated registration so the SDK pre-render floor
/// fail-closes an under-capable client. A library that admits a structured
/// widget but declares NO capability version fails the build LOUD. A
/// scalar-only / built-in-structured-only library is NEVER forced to declare
/// one and stays byte-stable (`version: '0.0.0'`, no `capabilityVersion`).
void main() {
  group('customer capabilityVersion stamp (structured-admitting)', () {
    const structuredWithCapver = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      @RestageLibrary(
        library: WidgetLibrary.custom('acme.design_system'),
        capabilityVersion: 3,
      )
      const restageLibrary = 0;

      class Badge {
        const Badge({required this.label});
        final String label;
      }

      @RestageWidget(
        name: 'BadgeCard',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration,
        description: 'A card that renders a badge.',
      )
      class BadgeCard {
        const BadgeCard({required this.badge});
        @RestageProperty(description: 'The badge to render.')
        final Badge badge;
      }
    ''';

    test(
        'the CATALOG stamps the declared capabilityVersion on a '
        'structured-admitting library', () async {
      final rw = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      rw.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        structuredWithCapver,
      );
      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': structuredWithCapver},
        rootPackage: 'apps_examples',
        readerWriter: rw,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("name: 'BadgeCard'"),
              contains('capabilityVersion: 3'),
            ),
          ),
        },
      );
    });

    test(
        'the REGISTRATION passes the declared capabilityVersion on a '
        'structured-admitting library', () async {
      final rw = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      rw.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        structuredWithCapver,
      );
      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': structuredWithCapver},
        rootPackage: 'apps_examples',
        readerWriter: rw,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('registerWidgetLibrary'),
              contains('capabilityVersion: 3'),
            ),
          ),
        },
      );
    });

    test(
        'a structured-admitting library with NO declared capabilityVersion '
        'FAILS the build LOUD', () async {
      const structuredNoCapver = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageLibrary(library: WidgetLibrary.custom('acme.design_system'))
        const restageLibrary = 0;

        class Badge {
          const Badge({required this.label});
          final String label;
        }

        @RestageWidget(
          name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration,
          description: 'A card that renders a badge.',
        )
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'The badge to render.')
          final Badge badge;
        }
      ''';
      final rw = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      rw.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        structuredNoCapver,
      );
      // The walker log.severe-s each issue then throws; testBuilder captures
      // the thrown build error and surfaces the diagnostics via onLog. Assert
      // BOTH a SEVERE naming the missing capability version AND no catalog.
      final severe = <String>[];
      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': structuredNoCapver},
        rootPackage: 'apps_examples',
        readerWriter: rw,
        onLog: (record) {
          if (record.level >= Level.SEVERE) severe.add(record.message);
        },
      );
      expect(
        severe.join('\n'),
        allOf(
          contains('acme.design_system'),
          contains('capability version'),
        ),
      );
      expect(
        rw.testing.exists(AssetId('apps_examples', 'lib/user_catalog.g.dart')),
        isFalse,
        reason: 'a fail-loud build must not emit a catalog',
      );
    });

    test(
        'a SCALAR-only library is NOT forced to declare a capabilityVersion '
        'and stays byte-stable (0.0.0, no capver)', () async {
      const scalarOnly = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'PlainButton',
          library: WidgetLibrary.custom('acme.simple'),
          category: WidgetCategory.input,
          description: 'CTA.',
        )
        class PlainButton {
          const PlainButton({required this.label});
          @RestageProperty(description: 'The label.')
          final String label;
        }
      ''';
      final rw = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      rw.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        scalarOnly,
      );
      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': scalarOnly},
        rootPackage: 'apps_examples',
        readerWriter: rw,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("name: 'PlainButton'"),
              contains("version: '0.0.0'"),
              isNot(contains('capabilityVersion:')),
            ),
          ),
        },
      );
    });

    test(
        'a SCALAR-only library that DECLARES a capabilityVersion HAS it stamped '
        '(so its widgets can be referenced in a surface)', () async {
      const scalarDeclared = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageLibrary(
          library: WidgetLibrary.custom('acme.simple'),
          capabilityVersion: 2,
        )
        const acmeSimpleLibrary = 0;

        @RestageWidget(
          name: 'PlainButton',
          library: WidgetLibrary.custom('acme.simple'),
          category: WidgetCategory.input,
          description: 'CTA.',
        )
        class PlainButton {
          const PlainButton({required this.label});
          @RestageProperty(description: 'The label.')
          final String label;
        }
      ''';
      final rw = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      rw.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        scalarDeclared,
      );
      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': scalarDeclared},
        rootPackage: 'apps_examples',
        readerWriter: rw,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("name: 'PlainButton'"),
              contains('capabilityVersion: 2'),
            ),
          ),
        },
      );
    });
  });
}
