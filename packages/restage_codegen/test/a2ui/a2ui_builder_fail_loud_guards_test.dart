import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Fail-loud builder guards that must survive the customer-only assembly path.
/// These three
/// guards are NOT covered by `a2ui_builder_hardening_test.dart` (which covers
/// reserved-built-in-namespace claims, conflicting `@RestageLibrary`
/// capabilityVersion, and an A2UI-unrepresentable STRUCTURED field). Each
/// proves
/// the build fails LOUD — a specific diagnostic + no silent drop — rather than
/// emitting a partial/wrong catalog.
///
/// Shape mirrors the hardening suite: plant sources on `apps_examples`, run the
/// `UserA2uiCatalogBuilder`, and assert `result.succeeded` is false with the
/// guard's specific message captured through `onLog`.
Future<(bool succeeded, String logs)> _runBuilder(
  Map<String, String> sources,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(
      AssetId('apps_examples', entry.key),
      entry.value,
    );
  }
  final logs = <String>[];
  final result = await testBuilder(
    const UserA2uiCatalogBuilder(BuilderOptions.empty),
    {for (final e in sources.entries) 'apps_examples|${e.key}': e.value},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
  return (result.succeeded, logs.join('\n'));
}

void main() {
  group(
      'UserA2uiCatalogBuilder — fail-loud guards survive customer-only '
      'assembly', () {
    test(
        'a duplicate (library, name) across files fails loud — the flat A2UI '
        'catalog cannot carry two components of the same name', () async {
      const fileA = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.widgets'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        @RestageWidget(
          name: 'Dup',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'first Dup',
        )
        class DupA {
          const DupA({required this.x});
          @RestageProperty(description: 'x') final String x;
        }
      ''';
      const fileB = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'Dup',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'second Dup',
        )
        class DupB {
          const DupB({required this.y});
          @RestageProperty(description: 'y') final String y;
        }
      ''';

      final (succeeded, logs) =
          await _runBuilder({'lib/a.dart': fileA, 'lib/b.dart': fileB});

      expect(succeeded, isFalse);
      expect(logs, contains('share name in acme.widgets#Dup'));
    });

    test(
        'a custom library contributing a widget but declaring NO capability '
        'version fails loud (the custom-library capability axis cannot be '
        'stamped)', () async {
      // A widget in `acme.orphan` with NO `@RestageLibrary('acme.orphan')`
      // anywhere — the library has no declared capability version.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'Orphan',
          library: WidgetLibrary.custom('acme.orphan'),
          category: WidgetCategory.decoration,
          description: 'a widget whose library declares no capability version',
        )
        class Orphan {
          const Orphan({required this.x});
          @RestageProperty(description: 'x') final String x;
        }
      ''';

      final (succeeded, logs) = await _runBuilder({'lib/orphan.dart': source});

      expect(succeeded, isFalse);
      expect(logs, contains('acme.orphan'));
      expect(logs, contains('declares no capability version'));
    });

    test(
        'a constructor parameter whose type the A2UI catalog cannot represent '
        'fails loud (constructor/catalog mismatch), never a silent drop',
        () async {
      // `Object` is not an A2UI-representable property type. The constructor
      // declares it as required, so the catalog cannot carry the widget — the
      // build must fail loud naming the widget + property, not emit a widget
      // missing the parameter.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.widgets'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        @RestageWidget(
          name: 'Mismatch',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a constructor param the catalog cannot represent',
        )
        class Mismatch {
          const Mismatch({required this.thing});
          @RestageProperty(description: 'an unrepresentable param')
          final Object thing;
        }
      ''';

      final (succeeded, logs) =
          await _runBuilder({'lib/mismatch.dart': source});

      expect(succeeded, isFalse);
      expect(logs, contains('Unsupported property type'));
      expect(logs, contains('Mismatch'));
      expect(logs, contains('thing'));
    });
  });
}
