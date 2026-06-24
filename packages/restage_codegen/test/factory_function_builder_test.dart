import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

/// Properties every emitted `registration.g.dart` shares: the generated
/// banner, the rfw import, and an empty `LocalWidgetBuilder` map. The
/// per-namespace const identifier is checked separately.
Matcher _emittedScaffoldFor(String constMapName) => decodedMatches(
      allOf(
        contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
        contains("import 'package:rfw/rfw.dart' hide Switch;"),
        contains('const Map<String, LocalWidgetBuilder> $constMapName'),
        contains('<String, LocalWidgetBuilder>{}'),
      ),
    );

/// Concatenates message + error text from every SEVERE log record so a
/// `contains(...)` matcher locks the user-visible error wording without
/// caring whether the framework attached the StateError to `error` or
/// folded it into `message`.
String _severeText(Iterable<LogRecord> logs) => logs
    .where((r) => r.level == Level.SEVERE)
    .map((r) => '${r.message} ${r.error ?? ''}')
    .join('\n');

void main() {
  group('FactoryFunctionBuilder scaffold', () {
    test('production native path does not call toConsumerShape', () {
      final source = File(
        'lib/src/factory_function_builder.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('toConsumerShape(')));
    });

    test('production native loaders do not call compatibility decoders', () {
      final factoryBuilder = File(
        'lib/src/factory_function_builder.dart',
      ).readAsStringSync();
      final catalogLoader =
          File('lib/src/catalog_loader.dart').readAsStringSync();

      expect(factoryBuilder, isNot(contains('decodeCatalogCompat')));
      expect(catalogLoader, isNot(contains('decodeCatalogCompat')));
    });

    test('rejects v3 compatibility catalogs through native validation',
        () async {
      const catalogJson = '''
{
  "schemaVersion": 3,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.core": {"version": "0.1.0", "widgetCount": 0, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      final logs = <LogRecord>[];
      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_core|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_core',
        outputs: const {},
        onLog: logs.add,
      );

      expect(
        _severeText(logs),
        contains('Unsupported catalog schemaVersion 3 (expected 4)'),
      );
    });

    test('restage.core catalog → kCoreLibraryFactories empty map', () async {
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.core": {"version": "0.1.0", "widgetCount": 1, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "Center",
      "library": "restage.core",
      "category": "layout",
      "description": "Centers its child within itself.",
      "flutterType": "package:flutter/widgets.dart#Center",
      "childrenSlot": "single",
      "fires": [],
      "properties": [],
      "stability": "volatile"
    }
  ],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_core|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_core',
        outputs: {
          'restage_core|lib/src/registration.g.dart':
              _emittedScaffoldFor('kCoreLibraryFactories'),
        },
      );
    });

    test('restage.material → kMaterialLibraryFactories', () async {
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.material": {"version": "0.1.0", "widgetCount": 0, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_material|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_material',
        outputs: {
          'restage_material|lib/src/registration.g.dart':
              _emittedScaffoldFor('kMaterialLibraryFactories'),
        },
      );
    });

    test('restage.cupertino → kCupertinoLibraryFactories', () async {
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.cupertino": {"version": "0.1.0", "widgetCount": 0, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_cupertino|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_cupertino',
        outputs: {
          'restage_cupertino|lib/src/registration.g.dart':
              _emittedScaffoldFor('kCupertinoLibraryFactories'),
        },
      );
    });

    test('rejects a catalog declaring more than one library', () async {
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.core": {"version": "0.1.0", "widgetCount": 0, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0},
    "restage.material": {"version": "0.1.0", "widgetCount": 0, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      final logs = <LogRecord>[];
      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_core|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_core',
        outputs: const {},
        onLog: logs.add,
      );
      expect(
        _severeText(logs),
        contains('Expected exactly one library'),
      );
    });

    test(
        'populates the const map and emits Flutter import + factory body '
        'for a scalar-eligible widget', () async {
      // Locks the wiring between the eligibility loop, the per-library
      // Flutter import switch, the conditional import emission, and
      // the per-widget factory function emit — exercised end-to-end
      // through the builder rather than through the unit-level
      // factory_emitter tests.
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.material": {"version": "0.1.0", "widgetCount": 1, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "Divider",
      "library": "restage.material",
      "category": "decoration",
      "description": "A thin horizontal line.",
      "flutterType": "package:flutter/material.dart#Divider",
      "childrenSlot": "none",
      "fires": [],
      "properties": [
        {
          "wireId": "p0001",
          "name": "thickness",
          "type": "length",
          "description": "Stroke thickness.",
          "defaultSource": {"kind": "literal", "value": 1.0}
        }
      ],
      "stability": "volatile"
    }
  ],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_material|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_material',
        outputs: {
          'restage_material|lib/src/registration.g.dart': decodedMatches(
            allOf(
              contains("import 'package:flutter/material.dart';"),
              contains("import 'package:rfw/rfw.dart' hide Switch;"),
              contains(
                "'Divider': _buildDivider,",
              ),
              contains(
                'Widget _buildDivider(BuildContext context, DataSource source)',
              ),
              contains('return Divider('),
              contains("source.v<double>(<Object>['thickness']) ?? 1.0"),
            ),
          ),
        },
      );
    });

    test(
        'emits a cross-package import when a curated entry lives outside '
        'the primary Flutter library', () async {
      // Locks the emission of additional `import` lines for widget
      // classes whose `flutterType` URI differs from the library's
      // primary Flutter import. Without this, a Restage-authored
      // widget inside `restage_material` (or a future first-party
      // widget package) would land in `kMaterialLibraryFactories`
      // referencing an undeclared symbol — analyze would catch it,
      // but the catalog-side emit would still succeed and the failure
      // mode would be noisy and far from the root cause.
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.material": {"version": "0.1.0", "widgetCount": 1, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "Package",
      "library": "restage.material",
      "category": "action",
      "description": "Slot binding for surface children.",
      "flutterType": "package:restage_material/src/widgets/package.dart#Package",
      "childrenSlot": "single",
      "fires": [],
      "properties": [
        {
          "wireId": "p0001",
          "name": "slot",
          "type": "string",
          "description": "Slot identifier.",
          "required": true
        },
        {
          "wireId": "p0002",
          "name": "child",
          "type": "widget",
          "description": "Child UI bound to this slot.",
          "required": true
        }
      ],
      "stability": "volatile"
    }
  ],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_material|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_material',
        outputs: {
          'restage_material|lib/src/registration.g.dart': decodedMatches(
            allOf(
              contains("import 'package:flutter/material.dart';"),
              contains(
                "import 'package:restage_material/src/widgets/package.dart';",
              ),
              contains("'Package': _buildPackage,"),
              contains(
                'Widget _buildPackage(BuildContext context, '
                'DataSource source)',
              ),
              contains('return Package('),
            ),
          ),
        },
      );
    });

    test(
        'does NOT emit a redundant direct import for a restage.core widget '
        'when the core barrel is already imported', () async {
      // A first-party widget authored inside restage_core resolves its
      // flutterType to `package:restage_core/src/...`. The core barrel
      // (`package:restage_core/restage_core.dart`) re-exports it and is
      // already imported whenever a factory references core runtime
      // (RestageDecoders / resolveThemeBinding) — so a direct import of the
      // widget source is redundant and trips `unnecessary_import`. The
      // `duration` property forces a RestageDecoders reference (hence the
      // barrel); the assertion locks that the direct import is dropped while
      // the barrel stays.
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.core": {"version": "0.1.0", "widgetCount": 1, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "Gizmo",
      "library": "restage.core",
      "category": "decoration",
      "description": "A first-party core widget.",
      "flutterType": "package:restage_core/src/widgets/gizmo.dart#Gizmo",
      "childrenSlot": "none",
      "fires": [],
      "properties": [
        {
          "wireId": "p0001",
          "name": "fade",
          "type": "duration",
          "description": "Fade duration.",
          "required": false
        }
      ],
      "stability": "volatile"
    }
  ],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {'restage_core|lib/src/widget_catalog/catalog.json': catalogJson},
        rootPackage: 'restage_core',
        outputs: {
          'restage_core|lib/src/registration.g.dart': decodedMatches(
            allOf(
              contains("import 'package:restage_core/restage_core.dart';"),
              isNot(
                contains(
                  "import 'package:restage_core/src/widgets/gizmo.dart';",
                ),
              ),
              contains("'Gizmo': _buildGizmo,"),
            ),
          ),
        },
      );
    });

    test('rejects a non-built-in library namespace', () async {
      const catalogJson = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "acme.design_system": {"version": "0.1.0", "widgetCount": 0, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

      final logs = <LogRecord>[];
      await testBuilder(
        factoryFunctionBuilder(BuilderOptions.empty),
        {
          'acme_design_system|lib/src/widget_catalog/catalog.json': catalogJson,
        },
        rootPackage: 'acme_design_system',
        outputs: const {},
        onLog: logs.add,
      );
      expect(
        _severeText(logs),
        contains('Unsupported library namespace'),
      );
    });
  });
}
