import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The `usage` seam: `@a2ui.Config.usage` is read from target configuration
/// (it never joins the catalog wire format) and threaded into the
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
            AssetId(
              'apps_examples',
              'lib/generated/restage_a2ui_catalog.g.dart',
            ),
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
  group('UserA2uiCatalogBuilder — usage note threaded from config', () {
    test(
        'a widget with @a2ui.Config.usage emits a fragment using the '
        'usage text, not the description', () async {
      const source = '''
        import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @a2ui.Config.usage('Use Note for a short aside.')
        @RestageWidget(
          name: 'Note',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a short aside widget',
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
        import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @a2ui.Config.usage('   ')
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

    test('a lookalike RestageProperty cannot alter production pairing output',
        () async {
      const preamble = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
            hide RestageProperty;

        class RestageProperty {
          const RestageProperty({this.writeBackValue});
          final String? writeBackValue;
        }

        @RestageWidget(
          name: 'Control',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
          description: 'a controlled value',
        )
        class Control {
          const Control({
            required this.value,
            required this.count,
            required this.onChanged,
          });
          /// Current value.
          final String value;
          /// An unrelated count.
          final int count;
      ''';
      const baseline = '''
        $preamble
          /// Reports a changed value.
          final void Function(String) onChanged;
        }
      ''';
      const lookalike = '''
        $preamble
          /// Reports a changed value.
          @RestageProperty(writeBackValue: 'count')
          final void Function(String) onChanged;
        }
      ''';

      final baselineResult = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/control.dart': baseline,
      });
      final lookalikeResult = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/control.dart': lookalike,
      });

      expect(baselineResult.$1, isTrue);
      expect(lookalikeResult.$1, isTrue);
      expect(lookalikeResult.$2, baselineResult.$2);
    });

    test('a substituted super-formal input reaches generated A2UI', () async {
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        class BaseControl<T> {
          const BaseControl({required this.value});
          /// Current value.
          final T value;
        }

        /// A concrete customer control.
        @RestageWidget(
          name: 'Control',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
        )
        class Control extends BaseControl<String> {
          const Control({required super.value});
        }
      ''';

      final (succeeded, dart) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/control.dart': source,
      });

      expect(succeeded, isTrue);
      expect(dart, contains('Control('));
      expect(dart, contains('value:'));
    });

    test('an inherited field write-back shorthand matches the class map',
        () async {
      const classMap = '''
        import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        class BaseControl {
          const BaseControl({required this.value, required this.onChanged});
          /// Current value.
          final String value;
          /// Reports a changed value.
          final void Function(String) onChanged;
        }

        /// A concrete customer control.
        @a2ui.Config.writeBackValues({'onChanged': 'value'})
        @RestageWidget(
          name: 'Control',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
        )
        class Control extends BaseControl {
          const Control({required super.value, required super.onChanged});
        }
      ''';
      const fieldShorthand = '''
        import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        class BaseControl {
          const BaseControl({required this.value, required this.onChanged});
          /// Current value.
          final String value;
          /// Reports a changed value.
          @a2ui.Config.writeBackValue('value')
          final void Function(String) onChanged;
        }

        /// A concrete customer control.
        @RestageWidget(
          name: 'Control',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
        )
        class Control extends BaseControl {
          const Control({required super.value, required super.onChanged});
        }
      ''';

      final classMapResult = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/control.dart': classMap,
      });
      final fieldResult = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/control.dart': fieldShorthand,
      });

      expect(classMapResult.$1, isTrue);
      expect(fieldResult.$1, isTrue);
      expect(fieldResult.$2, classMapResult.$2);
    });

    test('an unresolved write-back map reference fails the production build',
        () async {
      const source = '''
        import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        /// An invalid controlled value.
        @a2ui.Config.writeBackValues({'missingCallback': 'missingValue'})
        @RestageWidget(
          name: 'Control',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
        )
        class Control {
          const Control({required this.value});

          /// Current value.
          final String value;
        }
      ''';

      final (succeeded, dart) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/control.dart': source,
      });

      expect(succeeded, isFalse);
      expect(dart, isEmpty);
    });
  });
}
