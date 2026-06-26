import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// RED-first coverage for the A2UI build phase's fail-closed-LOUD walk guards —
/// the new fail-paths the existing happy-path suite + the drift-guard tie do
/// not exercise. Each drives the real `UserA2uiCatalogBuilder` over a
/// deliberately malformed customer package and asserts the build FAILS LOUD
/// (never a silent drop / last-wins / built-in overwrite).
void main() {
  group('UserA2uiCatalogBuilder — fail-closed-LOUD walk guards', () {
    test(
        'a customer @RestageWidget claiming a BUILT-IN namespace is rejected '
        'loud (it would otherwise overwrite the built-in library metadata)',
        () async {
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'Spoof',
          library: WidgetLibrary.core,
          category: WidgetCategory.input,
          description: 'claims a reserved built-in namespace',
        )
        class Spoof {
          const Spoof();
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/spoof.dart'),
        source,
      );

      final logs = <String>[];
      final result = await testBuilder(
        const UserA2uiCatalogBuilder(BuilderOptions.empty),
        const {'apps_examples|lib/spoof.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        contains('declares the built-in namespace "restage.core"'),
      );
    });

    test(
        'two conflicting @RestageLibrary capabilityVersion declarations fail '
        'loud (never nondeterministic last-wins)', () async {
      const fileA = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageLibrary(
          library: WidgetLibrary.custom('acme.widgets'),
          capabilityVersion: 1,
        )
        const restageLibraryA = 0;
      ''';
      const fileB = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageLibrary(
          library: WidgetLibrary.custom('acme.widgets'),
          capabilityVersion: 2,
        )
        const restageLibraryB = 0;
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(AssetId('apps_examples', 'lib/a.dart'), fileA)
        ..writeString(AssetId('apps_examples', 'lib/b.dart'), fileB);

      final logs = <String>[];
      final result = await testBuilder(
        const UserA2uiCatalogBuilder(BuilderOptions.empty),
        const {
          'apps_examples|lib/a.dart': fileA,
          'apps_examples|lib/b.dart': fileB,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        contains('conflicting @RestageLibrary capabilityVersion for '
            '"acme.widgets"'),
      );
    });

    test(
        'a customer structured property whose data class has an '
        'A2UI-unrepresentable field fails the build LOUD rather than '
        'silently dropping the widget', () async {
      // `BadData` is a customer data class (it has a generative constructor
      // with parameters), so it is marked `structured` — but its `Set<String>`
      // field is not A2UI-representable, so the shape reflector scopes the
      // whole object out. The widget must NOT silently vanish from the
      // catalog; the build must fail loud, naming the widget and property.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        class BadData {
          const BadData({required this.ids});
          final Set<String> ids;
        }

        @RestageWidget(
          name: 'BadCard',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'carries an A2UI-unrepresentable structured property',
        )
        class BadCard {
          const BadCard({required this.data});
          @RestageProperty(description: 'the data')
          final BadData data;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/bad_card.dart'),
        source,
      );

      final logs = <String>[];
      final result = await testBuilder(
        const UserA2uiCatalogBuilder(BuilderOptions.empty),
        const {'apps_examples|lib/bad_card.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(
        result.succeeded,
        isFalse,
        reason: 'a structured widget the A2UI emitter cannot represent must '
            'fail the build loud, never silently drop from the catalog',
      );
      expect(logs.join('\n'), contains('BadCard'));
      expect(logs.join('\n'), contains('data'));
    });
  });
}
