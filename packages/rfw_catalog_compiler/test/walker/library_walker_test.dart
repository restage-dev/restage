import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/walker/library_walker.dart';
import 'package:rfw_catalog_compiler/src/walker/walker_issue_codes.dart';
import 'package:test/test.dart';

void main() {
  group('walkRestageLibrary — enumeration', () {
    test(
        'enumerates @RestageWidget classes from the export namespace and '
        'excludes a plain class', () async {
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        export 'widgets/acme_button.dart';
        export 'widgets/plain.dart';

        @RestageLibrary(library: WidgetLibrary.custom('acme.design_system'))
        const _sentinel = 0;
      ''';
      const button = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A CTA button.',
        )
        class AcmeButton { const AcmeButton(); }
      ''';
      const plain = 'class Plain { const Plain(); }';

      final result = await resolveSources(
        {
          'customer_app|lib/restage_imports.dart': barrel,
          'customer_app|lib/widgets/acme_button.dart': button,
          'customer_app|lib/widgets/plain.dart': plain,
        },
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      expect(result.diagnostics, isEmpty);
      // Only the annotated class is enumerated; the plain class is excluded.
      expect(result.widgetClasses, hasLength(1));
      expect(result.widgetClasses.single.name, 'AcmeButton');
      expect(
        result.widgetClasses.single.library.identifier,
        endsWith('widgets/acme_button.dart'),
      );
    });

    test(
        'enumerates two @RestageWidget classes from one library and orders '
        'all classes by fully-qualified name', () async {
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        export 'widgets/b_pack.dart';
        export 'widgets/a_pack.dart';

        @RestageLibrary(library: WidgetLibrary.custom('acme.design_system'))
        const _sentinel = 0;
      ''';
      const bPack = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'BetaOne',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A CTA button.',
        )
        class BetaOne { const BetaOne(); }

        @RestageWidget(
          name: 'BetaTwo',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A CTA button.',
        )
        class BetaTwo { const BetaTwo(); }
      ''';
      const aPack = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AlphaOne',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A CTA button.',
        )
        class AlphaOne { const AlphaOne(); }
      ''';

      final result = await resolveSources(
        {
          'customer_app|lib/restage_imports.dart': barrel,
          'customer_app|lib/widgets/b_pack.dart': bPack,
          'customer_app|lib/widgets/a_pack.dart': aPack,
        },
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      expect(result.diagnostics, isEmpty);
      // Both annotated classes in b_pack appear — no library-level dedup.
      expect(result.widgetClasses, hasLength(3));
      // Classes are sorted by fully-qualified name (`<library URI>#<name>`):
      // every a_pack class sorts before every b_pack class because the
      // library identifier is the primary sort component.
      expect(
        result.widgetClasses.map((c) => c.name),
        ['AlphaOne', 'BetaOne', 'BetaTwo'],
      );
      expect(
        result.widgetClasses[0].library.identifier,
        endsWith('widgets/a_pack.dart'),
      );
      expect(
        result.widgetClasses[1].library.identifier,
        endsWith('widgets/b_pack.dart'),
      );
      expect(
        result.widgetClasses[2].library.identifier,
        endsWith('widgets/b_pack.dart'),
      );
    });
  });

  group('walkRestageLibrary — declaration', () {
    test('parses library and package from a valid @RestageLibrary', () async {
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          package: 'acme_design_system',
        )
        const _sentinel = 0;
      ''';

      final result = await resolveSources(
        {'customer_app|lib/restage_imports.dart': barrel},
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      expect(result.declaration, isNotNull);
      expect(result.declaration!.library.namespace, 'acme.design_system');
      expect(result.declaration!.package, 'acme_design_system');
      expect(result.diagnostics, isEmpty);
    });

    test('returns a null declaration when no @RestageLibrary is present',
        () async {
      const barrel = 'const _unrelated = 0;';
      final result = await resolveSources(
        {'customer_app|lib/restage_imports.dart': barrel},
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );
      expect(result.declaration, isNull);
      expect(result.widgetClasses, isEmpty);
      expect(result.diagnostics, isEmpty);
    });

    test('emits restageLibraryMalformed when the annotation is not const',
        () async {
      // The annotation argument references an undefined identifier, so
      // `computeConstantValue()` returns null. `_firstAnnotationNamed`'s
      // source-text fallback still recognizes the `@RestageLibrary` annotation.
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageLibrary(library: undefinedLibraryIdentifier)
        const _sentinel = 0;
      ''';

      final result = await resolveSources(
        {'customer_app|lib/restage_imports.dart': barrel},
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      expect(result.declaration, isNull);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.code, restageLibraryMalformed);
      expect(result.diagnostics.single.severity, DiagnosticSeverity.error);
    });
  });

  group('walkRestageLibrary — filtering', () {
    test('rejects a reserved built-in namespace with an error', () async {
      // A customer barrel that claims a built-in namespace must be rejected
      // immediately: the walk does not proceed and the declaration is null.
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageLibrary(library: WidgetLibrary.core)
        const _sentinel = 0;
      ''';

      final result = await resolveSources(
        {'customer_app|lib/restage_imports.dart': barrel},
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      expect(result.declaration, isNull);
      expect(result.widgetClasses, isEmpty);
      expect(result.diagnostics, hasLength(1));
      expect(
        result.diagnostics.single.code,
        restageLibraryReservedNamespace,
      );
      expect(result.diagnostics.single.severity, DiagnosticSeverity.error);
    });

    test(
        'drops a @RestageWidget class from a foreign package and emits a '
        'warning, but keeps the declaration', () async {
      // The barrel lives in `customer_app` but the @RestageLibrary.package
      // names `acme_design_system`. The @RestageWidget class is declared in
      // `customer_app` (not in `acme_design_system`), so it is foreign: it
      // must be dropped with a warning, but the walk still proceeds.
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        export 'widgets/customer_button.dart';

        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          package: 'acme_design_system',
        )
        const _sentinel = 0;
      ''';
      const customerButton = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'CustomerButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A button in the wrong package.',
        )
        class CustomerButton { const CustomerButton(); }
      ''';

      final result = await resolveSources(
        {
          'customer_app|lib/restage_imports.dart': barrel,
          'customer_app|lib/widgets/customer_button.dart': customerButton,
        },
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      // The walk proceeds — declaration is present.
      expect(result.declaration, isNotNull);
      // The foreign class is excluded from widgetClasses.
      expect(result.widgetClasses, isEmpty);
      // A warning is emitted for the dropped class.
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.code, restageLibraryForeignWidget);
      expect(result.diagnostics.single.severity, DiagnosticSeverity.warning);
    });

    test(
        "keeps a @RestageWidget class from the barrel's own package when "
        '@RestageLibrary.package is null', () async {
      // When @RestageLibrary.package is null the effective package is the
      // barrel's own package (`customer_app`). A @RestageWidget class
      // declared in `customer_app` should be kept with no diagnostic.
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        export 'widgets/own_button.dart';

        @RestageLibrary(library: WidgetLibrary.custom('acme.design_system'))
        const _sentinel = 0;
      ''';
      const ownButton = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'OwnButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A button in the barrels own package.',
        )
        class OwnButton { const OwnButton(); }
      ''';

      final result = await resolveSources(
        {
          'customer_app|lib/restage_imports.dart': barrel,
          'customer_app|lib/widgets/own_button.dart': ownButton,
        },
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      // The own-package class is kept.
      expect(result.widgetClasses, hasLength(1));
      expect(result.widgetClasses.single.name, 'OwnButton');
      // No diagnostics for a clean walk.
      expect(result.diagnostics, isEmpty);
    });

    test(
        'keeps the own-package widget and drops the foreign one in the same '
        'walk', () async {
      // The barrel lives in `customer_app` with no @RestageLibrary.package, so
      // the effective package is `customer_app`. It exports TWO @RestageWidget
      // classes: one declared in `customer_app` (matches → kept) and one
      // declared in `foreign_pkg` (foreign → dropped). This proves the filter
      // is per-class, not all-or-nothing.
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        export 'widgets/own_widget.dart';
        export 'package:foreign_pkg/foreign_widget.dart';

        @RestageLibrary(library: WidgetLibrary.custom('acme.design_system'))
        const _sentinel = 0;
      ''';
      const ownWidget = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'OwnWidget',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A widget in the barrels own package.',
        )
        class OwnWidget { const OwnWidget(); }
      ''';
      const foreignWidget = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'ForeignWidget',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'A widget in a different package.',
        )
        class ForeignWidget { const ForeignWidget(); }
      ''';

      final result = await resolveSources(
        {
          'customer_app|lib/restage_imports.dart': barrel,
          'customer_app|lib/widgets/own_widget.dart': ownWidget,
          'foreign_pkg|lib/foreign_widget.dart': foreignWidget,
        },
        (resolver) async {
          final lib = await resolver.libraryFor(
            AssetId('customer_app', 'lib/restage_imports.dart'),
          );
          return walkRestageLibrary(
            barrel: lib,
            barrelAssetId: AssetId('customer_app', 'lib/restage_imports.dart'),
          );
        },
        readAllSourcesFromFilesystem: true,
      );

      // The walk proceeds — declaration is present.
      expect(result.declaration, isNotNull);
      // Only the own-package widget survives the per-class filter.
      expect(result.widgetClasses, hasLength(1));
      expect(result.widgetClasses.single.name, 'OwnWidget');
      expect(
        result.widgetClasses.single.library.identifier,
        endsWith('widgets/own_widget.dart'),
      );
      // Exactly one warning, for the dropped foreign widget.
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.code, restageLibraryForeignWidget);
    });
  });
}
