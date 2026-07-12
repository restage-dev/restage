import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The `usage` seam: `@RestageWidget(usage:)` is read straight off the
/// annotation (it never joins the catalog wire format) and threaded into the
/// generated catalog's system-prompt fragments — `"<name>: <text>"`, falling
/// back to the widget's `description` when `usage` is absent.
///
/// Drives the real `UserA2uiCatalogBuilder` over a customer package, mirroring
/// the harness in `a2ui_builder_coverage_fail_loud_test.dart`.
Future<(bool succeeded, String dart)> _runBuilder(
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
  final result = await testBuilder(
    const UserA2uiCatalogBuilder(BuilderOptions.empty),
    {for (final e in sources.entries) 'apps_examples|${e.key}': e.value},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final dart = result.succeeded
      ? String.fromCharCodes(
          result.readerWriter.testing.readBytes(
            AssetId('apps_examples', 'lib/restage_a2ui_catalog.g.dart'),
          ),
        )
      : '';
  return (result.succeeded, dart);
}

/// The shared `@RestageLibrary` barrel declaring the custom library.
const _libraryDeclaration = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  @RestageLibrary(
    library: WidgetLibrary.custom('acme.widgets'),
    capabilityVersion: 1,
  )
  const restageLibrary = 0;
''';

void main() {
  group('UserA2uiCatalogBuilder — usage note threaded from the annotation', () {
    test(
        'a widget with @RestageWidget(usage:) emits a fragment using the '
        'usage text, not the description', () async {
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'Note',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a short aside widget',
          usage: 'Use Note for a short aside.',
        )
        class Note {
          const Note({required this.text});
          @RestageProperty(description: 'the note text')
          final String text;
        }
      ''';

      final (succeeded, dart) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/note.dart': source,
      });

      expect(succeeded, isTrue);
      expect(dart, contains("'Note: Use Note for a short aside.'"));
      // The fragment list carries only the usage text for this widget — the
      // description-sourced schema field (a separate concern) may still
      // appear elsewhere in the file, so assert on the fragment line itself
      // rather than the description text's absence from the whole file.
      expect(
        dart,
        isNot(contains("'Note: a short aside widget'")),
      );
    });

    test(
        'a widget WITHOUT usage but WITH a description falls back to the '
        'description in its fragment line', () async {
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'Badge',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a small status badge',
        )
        class Badge {
          const Badge({required this.text});
          @RestageProperty(description: 'the badge text')
          final String text;
        }
      ''';

      final (succeeded, dart) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/badge.dart': source,
      });

      expect(succeeded, isTrue);
      expect(dart, contains("'Badge: a small status badge'"));
    });

    test(
        'a widget with a whitespace-only usage falls back to its description '
        '(no blank fragment line)', () async {
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'Chip',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a small selectable chip',
          usage: '   ',
        )
        class Chip {
          const Chip({required this.text});
          @RestageProperty(description: 'the chip text')
          final String text;
        }
      ''';

      final (succeeded, dart) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/chip.dart': source,
      });

      expect(succeeded, isTrue);
      expect(dart, contains("'Chip: a small selectable chip'"));
      expect(dart, isNot(contains("'Chip: '")));
      expect(dart, isNot(contains("'Chip:    '")));
    });
  });
}
