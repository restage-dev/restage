// The compatibility fixture intentionally exercises the compiler's public
// experimental diff taxonomy to distinguish free renames from add/remove.
// ignore_for_file: experimental_member_use

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_shared/restage_shared.dart'
    show kReservedPreviewConstructorName, kReservedPreviewLibraryName;
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _statusPanelSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'Status.',
        )
        class StatusPanel {
          const StatusPanel(this.label, {this.subtitle});

          @RestageProperty(description: 'Label.', required: true)
          final String label;

          @RestageProperty(description: 'Subtitle.')
          final String? subtitle;
        }
      ''';

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

    test('fails before allocation and suggests events for a likely rename',
        () async {
      const eventLog = '''
{"kind":"alloc","type":"widget","id":"w0042","name":"CatalogShowcase","source":"package:apps_examples/widgets/status_panel.dart#CatalogShowcase","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"alloc","type":"property","id":"p0099","owner":"w0042","name":"label","source":"package:apps_examples/widgets/status_panel.dart#CatalogShowcase.label","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"alloc","type":"property","id":"p0100","owner":"w0042","name":"analyticsId","source":"package:apps_examples/widgets/status_panel.dart#CatalogShowcase.analyticsId","at":"2026-05-14T00:00:00.000Z","by":"test"}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/widgets/status_panel.dart'),
          _statusPanelSource,
        )
        ..writeString(
          AssetId('apps_examples', 'wire_ids.events.jsonl'),
          eventLog,
        );
      final logs = <String>[];

      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/widgets/status_panel.dart': _statusPanelSource,
          'apps_examples|wire_ids.events.jsonl': eventLog,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        allOf(
          contains('Potential @RestageWidget rename'),
          contains('No wire IDs were allocated'),
          contains(
            '{"at":"2026-05-26T00:00:00.000Z",'
            '"by":"restage-codegen-user-catalog-allocator",'
            '"cascade":true,"from":"CatalogShowcase",'
            '"fromSource":"package:apps_examples/widgets/status_panel.dart#'
            'CatalogShowcase","id":"w0042","kind":"rename",'
            '"to":"StatusPanel",'
            '"toSource":"package:apps_examples/widgets/status_panel.dart#'
            'StatusPanel","type":"widget"}',
          ),
          contains(
            '{"at":"2026-05-26T00:00:00.000Z",'
            '"by":"restage-codegen-user-catalog-allocator",'
            '"id":"w0042","kind":"deprecate",'
            '"reason":"Replaced by StatusPanel","type":"widget"}',
          ),
        ),
      );
    });

    test('suggests a source-only rename when a widget moves and changes shape',
        () async {
      const eventLog = '''
{"kind":"alloc","type":"widget","id":"w0042","name":"StatusPanel","source":"package:apps_examples/widgets/old/status_panel.dart#StatusPanel","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"alloc","type":"property","id":"p0099","owner":"w0042","name":"label","source":"package:apps_examples/widgets/old/status_panel.dart#StatusPanel.label","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"alloc","type":"property","id":"p0100","owner":"w0042","name":"analyticsId","source":"package:apps_examples/widgets/old/status_panel.dart#StatusPanel.analyticsId","at":"2026-05-14T00:00:00.000Z","by":"test"}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/widgets/new/status_panel.dart'),
          _statusPanelSource,
        )
        ..writeString(
          AssetId('apps_examples', 'wire_ids.events.jsonl'),
          eventLog,
        );
      final logs = <String>[];

      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/widgets/new/status_panel.dart': _statusPanelSource,
          'apps_examples|wire_ids.events.jsonl': eventLog,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        allOf(
          contains('Potential @RestageWidget rename'),
          contains('No wire IDs were allocated'),
          contains(
            '"cascade":true,"from":"StatusPanel",'
            '"fromSource":"package:apps_examples/widgets/old/'
            'status_panel.dart#StatusPanel","id":"w0042","kind":"rename",'
            '"to":"StatusPanel",'
            '"toSource":"package:apps_examples/widgets/new/'
            'status_panel.dart#StatusPanel","type":"widget"',
          ),
        ),
      );
    });

    test('replays rename events across a renamed widget class', () async {
      const eventLog = '''
{"kind":"alloc","type":"widget","id":"w0042","name":"CatalogShowcase","source":"package:apps_examples/widgets/status_panel.dart#CatalogShowcase","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"alloc","type":"property","id":"p0099","owner":"w0042","name":"label","source":"package:apps_examples/widgets/status_panel.dart#CatalogShowcase.label","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"alloc","type":"property","id":"p0100","owner":"w0042","name":"analyticsId","source":"package:apps_examples/widgets/status_panel.dart#CatalogShowcase.analyticsId","at":"2026-05-14T00:00:00.000Z","by":"test"}
{"kind":"rename","type":"widget","id":"w0042","from":"CatalogShowcase","to":"StatusPanel","fromSource":"package:apps_examples/widgets/status_panel.dart#CatalogShowcase","toSource":"package:apps_examples/widgets/status_panel.dart#StatusPanel","cascade":true,"at":"2026-05-26T00:00:00.000Z","by":"restage-codegen-user-catalog-allocator"}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'lib/widgets/status_panel.dart'),
          _statusPanelSource,
        )
        ..writeString(
          AssetId('apps_examples', 'wire_ids.events.jsonl'),
          eventLog,
        );

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/widgets/status_panel.dart': _statusPanelSource,
          'apps_examples|wire_ids.events.jsonl': eventLog,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("wireId: WireId('w0042')"),
              contains("wireId: WireId('p0099')"),
              contains("wireId: WireId('p0100')"),
              contains("wireId: WireId('p0101')"),
              contains("name: 'StatusPanel'"),
              isNot(contains("WireId('w0043')")),
              isNot(contains("WireId('p0102')")),
            ),
          ),
        },
      );
    });

    test('propagates source constraint metadata into generated user catalog',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'ConstrainedCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'Constraint propagation proof.',
        )
        class ConstrainedCard {
          const ConstrainedCard({
            required this.count,
            required this.label,
            required this.legacy,
          });

          @RestageProperty(
            description: 'Count.',
            constraints: RestageConstraints(
              minimum: 1,
              maximum: 10,
              allowedValues: [1, 2, null],
            ),
          )
          final int count;

          @RestageProperty(
            description: 'Label.',
            constraints: RestageConstraints(
              allowedValues: ['short', 'long', null],
              pattern: r'^[a-z]+',
              minLength: 2,
              maxLength: 8,
            ),
          )
          final String label;

          @RestageProperty(
            description: 'Legacy.',
            validationRule: ValidationExpr(
              expression: 'legacy(value) == true',
              message: 'Exact legacy message.',
            ),
          )
          final String legacy;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/constrained_card.dart'),
        widgetSource,
      );

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/widgets/constrained_card.dart': widgetSource,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            predicate<String>(
              (source) {
                final normalized = source
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .replaceAll('( ', '(')
                    .replaceAll('[ ', '[')
                    .replaceAll(' ]', ']');
                return normalized.contains(
                      'constraints: RestageConstraints(minimum: 1, '
                      'maximum: 10, allowedValues: [1, 2, null])',
                    ) &&
                    normalized.contains(
                      'constraints: RestageConstraints(allowedValues: '
                      "['short', 'long', null], pattern: '^[a-z]+', "
                      'minLength: 2, maxLength: 8)',
                    ) &&
                    normalized.contains(
                      'validationRule: ValidationExpr(expression: '
                      "'legacy(value) == true', message: "
                      "'Exact legacy message.')",
                    );
              },
              'emits exact source constraints and legacy message',
            ),
          ),
        },
      );
    });

    test('rejects mixed source constraint metadata at production boundary',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'ConflictedCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'Conflict proof.',
        )
        class ConflictedCard {
          const ConflictedCard({required this.label});

          @RestageProperty(
            description: 'Label.',
            constraints: RestageConstraints(minLength: 1),
            validationRule: ValidationExpr(
              expression: 'legacy(value)',
              message: 'Legacy message.',
            ),
          )
          final String label;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/conflicted_card.dart'),
        widgetSource,
      );
      final logs = <String>[];

      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/conflicted_card.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        allOf(contains('ConflictedCard.label'), contains('validationRule')),
      );
    });

    test('rejects invalid source constraint metadata before output', () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'InvalidBoundsCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'Invalid bounds proof.',
        )
        class InvalidBoundsCard {
          const InvalidBoundsCard({required this.count});

          @RestageProperty(
            description: 'Count.',
            constraints: RestageConstraints(minimum: 10, maximum: 1),
          )
          final int count;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/invalid_bounds_card.dart'),
        widgetSource,
      );

      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/invalid_bounds_card.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('InvalidBoundsCard'),
          contains('properties[0]'),
          contains('contradictory'),
        ),
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

    test('RFW builder fails loud for an A2UI-only scalar-list field', () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'IntegerListPanel',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.layout,
          description: 'Integer list panel.',
        )
        class IntegerListPanel {
          const IntegerListPanel({required this.values});

          @RestageProperty(description: 'Integer values.')
          final List<int> values;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/integer_list_panel.dart'),
        widgetSource,
      );

      final logs = <String>[];
      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/widgets/integer_list_panel.dart': widgetSource,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(logs.join('\n'), contains('Unsupported property type List<int>'));
    });

    test('emits an issue when two files declare the same (library, name)',
        () async {
      const fileA = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'Same',
          description: 'one',
        )
        class A { const A(); }
      ''';
      const fileB = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'Same',
          description: 'two',
        )
        class B { const B(); }
      ''';
      const barrel = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        export 'a.dart';
        export 'b.dart';

        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
        )
        const restageLibrary = 0;
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(AssetId('apps_examples', 'lib/a.dart'), fileA)
        ..writeString(AssetId('apps_examples', 'lib/b.dart'), fileB)
        ..writeString(AssetId('apps_examples', 'lib/catalog.dart'), barrel);

      // The cross-file collision causes the builder to log severe issues
      // and throw a `StateError`. `testBuilder` captures these as a failed
      // build with the issue text in `result.errors`.
      final logs = <String>[];
      final result = await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        const {
          'apps_examples|lib/a.dart': fileA,
          'apps_examples|lib/b.dart': fileB,
          'apps_examples|lib/catalog.dart': barrel,
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
    test('rejects preview-only namespace and constructor claims', () {
      expect(
        () => allocateUserCatalogFromWidgets(
          package: 'apps_examples',
          widgets: [
            entry(
              name: 'Badge',
              properties: const [],
              library: const WidgetLibrary.custom(
                kReservedPreviewLibraryName,
              ),
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => allocateUserCatalogFromWidgets(
          package: 'apps_examples',
          widgets: [
            entry(
              name: kReservedPreviewConstructorName,
              properties: const [],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

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

    test('class rename carries IDs forward without add/remove catalog diff',
        () {
      final before = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          entry(
            name: 'CatalogShowcase',
            library: const WidgetLibrary.custom('acme.design_system'),
            properties: [
              prop('label', PropertyType.string, required: true),
            ],
            flutterType: 'package:apps_examples/status.dart#CatalogShowcase',
          ),
        ],
      );
      final renameEvents = <WireIdEvent>[
        ...before.newEvents,
        RenameWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          from: 'CatalogShowcase',
          to: 'StatusPanel',
          fromSource: 'package:apps_examples/status.dart#CatalogShowcase',
          toSource: 'package:apps_examples/status.dart#StatusPanel',
          cascade: true,
          at: '2026-05-26T00:00:00.000Z',
          by: 'test',
        ),
      ];

      final after = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          entry(
            name: 'StatusPanel',
            library: const WidgetLibrary.custom('acme.design_system'),
            properties: [
              prop('label', PropertyType.string, required: true),
            ],
            flutterType: 'package:apps_examples/status.dart#StatusPanel',
          ),
        ],
        existingEvents: renameEvents,
      );

      expect(after.newEvents, isEmpty);
      expect(after.catalog.widgets.single.wireId, WireId('w0001'));
      expect(
        after.catalog.widgets.single.properties.single.wireId,
        WireId('p0001'),
      );
      final diff = diffCatalogs(before.catalog, after.catalog);
      expect(diff.whereType<EntryAdded>(), isEmpty);
      expect(diff.whereType<EntryRemoved>(), isEmpty);
      expect(
        diff,
        [
          EntryRenamed(
            kind: WireIdKind.widget,
            affected: WireIdRef(
              library: 'acme.design_system',
              wireId: WireId('w0001'),
            ),
          ),
        ],
      );
    });

    test('explicit deprecation admits an identical-shape replacement', () {
      final before = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          entry(
            name: 'OldPanel',
            properties: [prop('label', PropertyType.string)],
          ),
        ],
      );

      final replacement = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          entry(
            name: 'NewPanel',
            properties: [prop('label', PropertyType.string)],
          ),
        ],
        existingEvents: [
          ...before.newEvents,
          DeprecateWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            reason: 'Replaced by NewPanel',
            at: '2026-05-26T00:00:00.000Z',
            by: 'test',
          ),
        ],
      );

      expect(replacement.catalog.widgets.single.wireId, WireId('w0002'));
      expect(
        replacement.catalog.widgets.single.properties.single.wireId,
        WireId('p0002'),
      );
    });

    test('reintroducing a deprecated exact key allocates fresh IDs', () {
      final before = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          entry(
            name: 'OldPanel',
            properties: [prop('label', PropertyType.string)],
          ),
        ],
      );

      final reintroduced = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          entry(
            name: 'OldPanel',
            properties: [prop('label', PropertyType.string)],
          ),
        ],
        existingEvents: [
          ...before.newEvents,
          DeprecateWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            reason: 'Retired before reintroduction',
            at: '2026-05-26T00:00:00.000Z',
            by: 'test',
          ),
        ],
      );

      expect(reintroduced.catalog.widgets.single.wireId, WireId('w0002'));
      expect(
        reintroduced.catalog.widgets.single.properties.single.wireId,
        WireId('p0002'),
      );
    });

    test('later cascade refuses live IDs at current and legacy sources', () {
      WidgetEntry statusPanel(String source) => entry(
            name: 'StatusPanel',
            properties: [prop('label', PropertyType.string)],
            flutterType: source,
          );

      final first = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          statusPanel('package:apps_examples/old.dart#StatusPanel'),
        ],
      );
      final legacyMove = RenameWireIdEvent(
        type: WireIdKind.widget,
        id: WireId('w0001'),
        from: 'StatusPanel',
        to: 'StatusPanel',
        fromSource: 'package:apps_examples/old.dart#StatusPanel',
        toSource: 'package:apps_examples/mid.dart#StatusPanel',
        at: '2026-05-25T00:00:00.000Z',
        by: 'test',
      );
      final atCurrentSource = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: [
          statusPanel('package:apps_examples/mid.dart#StatusPanel'),
        ],
        existingEvents: [...first.newEvents, legacyMove],
      );

      expect(
        atCurrentSource.newEvents.whereType<AllocWireIdEvent>().single.id,
        WireId('p0002'),
      );
      final cascade = RenameWireIdEvent(
        type: WireIdKind.widget,
        id: WireId('w0001'),
        from: 'StatusPanel',
        to: 'StatusPanel',
        fromSource: 'package:apps_examples/mid.dart#StatusPanel',
        toSource: 'package:apps_examples/new.dart#StatusPanel',
        cascade: true,
        at: '2026-05-27T00:00:00.000Z',
        by: 'test',
      );

      expect(
        () => allocateUserCatalogFromWidgets(
          package: 'apps_examples',
          widgets: [
            statusPanel('package:apps_examples/new.dart#StatusPanel'),
          ],
          existingEvents: [
            ...first.newEvents,
            legacyMove,
            ...atCurrentSource.newEvents,
            cascade,
          ],
        ),
        throwsA(
          predicate(
            (error) =>
                error is WireIdReplayException &&
                error.toString().contains('duplicate active descendant') &&
                error.toString().contains('p0001') &&
                error.toString().contains('p0002'),
          ),
        ),
      );
    });

    test('source move refuses an existing live widget identity', () {
      final events = <WireIdEvent>[
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          name: 'StatusPanel',
          source: 'package:apps_examples/old.dart#StatusPanel',
          at: '2026-05-25T00:00:00.000Z',
          by: 'test',
        ),
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0002'),
          name: 'StatusPanel',
          source: 'package:apps_examples/new.dart#StatusPanel',
          at: '2026-05-25T00:01:00.000Z',
          by: 'test',
        ),
        RenameWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          from: 'StatusPanel',
          to: 'StatusPanel',
          fromSource: 'package:apps_examples/old.dart#StatusPanel',
          toSource: 'package:apps_examples/new.dart#StatusPanel',
          cascade: true,
          at: '2026-05-25T00:02:00.000Z',
          by: 'test',
        ),
      ];

      expect(
        () => allocateUserCatalogFromWidgets(
          package: 'apps_examples',
          widgets: [
            entry(
              name: 'StatusPanel',
              properties: const [],
              flutterType: 'package:apps_examples/new.dart#StatusPanel',
            ),
          ],
          existingEvents: events,
        ),
        throwsA(
          predicate(
            (error) =>
                error is WireIdReplayException &&
                error.toString().contains('duplicate active widget') &&
                error.toString().contains('w0001') &&
                error.toString().contains('w0002'),
          ),
        ),
      );
    });
  });
}
