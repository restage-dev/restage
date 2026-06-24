import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('UserCatalogBuilder', () {
    test('emits user_catalog.g.dart when @RestageWidget classes are found',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'CTA.',
        )
        class AcmeButton {
          const AcmeButton();
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_button.dart'),
        widgetSource,
      );

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/acme_button.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains('final Catalog kUserCatalog'),
              contains("wireId: WireId('w0001')"),
              isNot(contains('WireId.unallocated')),
              contains("name: 'AcmeButton'"),
              contains("library: WidgetLibrary.custom('acme.design_system')"),
            ),
          ),
        },
      );
    });

    test('replays customer widget and property IDs from root event log',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'CTA.',
        )
        class AcmeButton {
          const AcmeButton(this.label);

          @RestageProperty(description: 'Label.', required: true)
          final String label;
        }
      ''';
      const eventLog = '''
{"kind":"alloc","type":"widget","id":"w0042","name":"AcmeButton","source":"package:apps_examples/widgets/acme_button.dart#AcmeButton","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"alloc","type":"property","id":"p0099","owner":"w0042","name":"label","source":"package:apps_examples/widgets/acme_button.dart#AcmeButton.label","at":"2026-05-14T00:00:00.000Z","by":"test"}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/widgets/acme_button.dart'),
          widgetSource,
        )
        ..writeString(
          AssetId('apps_examples', 'wire_ids.events.jsonl'),
          eventLog,
        );

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/widgets/acme_button.dart': widgetSource,
          'apps_examples|wire_ids.events.jsonl': eventLog,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("wireId: WireId('w0042')"),
              contains("wireId: WireId('p0099')"),
              isNot(contains('WireId.unallocated')),
            ),
          ),
        },
      );
    });

    test('does not emit user_catalog.g.dart when no @RestageWidget classes',
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
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/plain.dart': plainSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        // Empty `outputs:` asserts the builder produced no outputs.
        outputs: const {},
      );
    });

    test('emits an issue when two files declare the same (library, name)',
        () async {
      const fileA = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'Same',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.layout,
          description: 'one',
        )
        class A { const A(); }
      ''';
      const fileB = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'Same',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.layout,
          description: 'two',
        )
        class B { const B(); }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(AssetId('apps_examples', 'lib/a.dart'), fileA)
        ..writeString(AssetId('apps_examples', 'lib/b.dart'), fileB);

      // The cross-file collision causes the builder to log severe issues
      // and throw a `StateError`. `testBuilder` captures these as a failed
      // build with the issue text in `result.errors`.
      final logs = <String>[];
      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
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
        contains('Multiple @RestageWidget classes across this package '
            'share name in acme.design_system#Same'),
      );
    });

    test('allows the same widget name across different library namespaces',
        () async {
      const fileA = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'Button',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'Acme button.',
        )
        class AcmeButton { const AcmeButton(); }
      ''';
      const fileB = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'Button',
          library: WidgetLibrary.custom('beta.design_system'),
          category: WidgetCategory.input,
          description: 'Beta button.',
        )
        class BetaButton { const BetaButton(); }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(AssetId('apps_examples', 'lib/acme.dart'), fileA)
        ..writeString(AssetId('apps_examples', 'lib/beta.dart'), fileB);

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        const {
          'apps_examples|lib/acme.dart': fileA,
          'apps_examples|lib/beta.dart': fileB,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("wireId: WireId('w0001')"),
              contains("wireId: WireId('w0002')"),
              contains("library: WidgetLibrary.custom('acme.design_system')"),
              contains("library: WidgetLibrary.custom('beta.design_system')"),
              isNot(contains('WireId.unallocated')),
            ),
          ),
        },
      );
    });

    test('rejects token defaults from the annotation production path',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'CTA.',
        )
        class AcmeButton {
          const AcmeButton({this.color});

          @RestageProperty(
            description: 'Color.',
            defaultSource: TokenRefDefault(
              WireIdRef(
                library: 'acme.design_system',
                wireId: WireId.unallocatedDesignToken,
              ),
            ),
          )
          final String? color;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_button.dart'),
        widgetSource,
      );

      final logs = <String>[];
      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/acme_button.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        contains('cannot preserve a design-token default'),
      );
    });

    test('aggregates widgets across multiple lib files in stable order',
        () async {
      const fileB = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'B',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.layout,
          description: 'b',
        )
        class B { const B(); }
      ''';
      const fileA = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'A',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.layout,
          description: 'a',
        )
        class A { const A(); }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(AssetId('apps_examples', 'lib/b.dart'), fileB)
        ..writeString(AssetId('apps_examples', 'lib/a.dart'), fileA);

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/b.dart': fileB,
          'apps_examples|lib/a.dart': fileA,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            // 'A' should appear before 'B' regardless of file iteration
            // order — entries are sorted by (library namespace, name) for
            // byte-deterministic emit.
            predicate<String>(
              (s) {
                final aIndex = s.indexOf("name: 'A'");
                final bIndex = s.indexOf("name: 'B'");
                return aIndex >= 0 && bIndex > aIndex;
              },
              "emits 'A' before 'B' in deterministic order",
            ),
          ),
        },
      );
    });
  });

  group('UserCatalogAllocation', () {
    test('replays its generated event log without minting new IDs', () {
      final widgets = [
        entry(
          name: 'AcmeButton',
          library: const WidgetLibrary.custom('acme.design_system'),
          properties: [
            prop('label', PropertyType.string, required: true),
          ],
          flutterType: 'package:apps_examples/widgets/acme_button.dart#'
              'AcmeButton',
        ),
      ];

      final first = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: widgets,
      );
      expect(first.newEvents, hasLength(2));
      expect(first.catalog.widgets.single.wireId, WireId('w0001'));
      expect(
        first.catalog.widgets.single.properties.single.wireId,
        WireId('p0001'),
      );

      final second = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: widgets,
        existingEvents: parseWireIdEventsJsonl(
          encodeWireIdEventsJsonl(first.newEvents),
        ),
      );

      expect(second.newEvents, isEmpty);
      expect(second.catalog.widgets.single.wireId, WireId('w0001'));
      expect(
        second.catalog.widgets.single.properties.single.wireId,
        WireId('p0001'),
      );
    });
  });
}
