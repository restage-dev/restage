// This is a completeness check on the decoder routing table, not a proof that
// any repair works. The repairs are proved by the render tests.

import 'dart:io';

import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Per-widget scalar types plus every uniformly repaired property type.
final Set<PropertyType> _sweptPropertyTypes = <PropertyType>{
  PropertyType.length,
  PropertyType.real,
  ...typeLevelRepairedPropertyTypes,
};

const _catalogPaths = [
  'packages/restage_core/lib/src/widget_catalog/catalog.json',
  'packages/restage_material/lib/src/widget_catalog/catalog.json',
  'packages/restage_cupertino/lib/src/widget_catalog/catalog.json',
];

Directory _findWorkspaceRoot() {
  final start = Directory.current.absolute;
  var candidate = start;

  while (true) {
    final pubspec = File('${candidate.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      final declaresWorkspace = pubspec.readAsLinesSync().any(
            (line) => line.trim() == 'name: restage_workspace',
          );
      if (declaresWorkspace) {
        return candidate;
      }
    }

    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      fail(
        'Workspace root not found while walking up from ${start.path}: '
        'no pubspec.yaml declares "name: restage_workspace".',
      );
    }
    candidate = parent;
  }
}

void main() {
  test('every layout-double scalar is routed, exempt, or deferred', () {
    final unknown = <String>[];
    final unclassified = <String>[];
    final classificationTables = scalarDecoderClassificationTablesForTesting;
    final coveredSlots = scalarDecoderCoveredSlotsForTesting;

    for (final roster in classificationTables) {
      for (final entry in roster.entries) {
        final classification = entry.value;
        if (classification is String &&
            classification.contains('UNCLASSIFIED')) {
          unclassified.add('(${entry.key.$1}, ${entry.key.$2})');
        }
      }
    }

    // Anchor paths so the same catalogs are read however the runner is invoked;
    // a path miss must fail instead of quietly leaving nothing to check.
    final workspaceRoot = _findWorkspaceRoot();
    final catalogPaths = [
      for (final path in _catalogPaths) '${workspaceRoot.path}/$path',
    ];

    for (final path in catalogPaths) {
      final file = File(path);
      if (!file.existsSync()) {
        fail('Catalog file missing at expected path: $path');
      }
      final catalog = requireNativeCatalog(
        decodeCatalog(file.readAsStringSync()),
      );
      for (final widget in catalog.widgets) {
        for (final property in widget.properties) {
          if (!_sweptPropertyTypes.contains(property.type)) {
            continue;
          }
          final key = (widget.name, property.name);
          if (!coveredSlots.contains(key)) {
            unknown.add('(${widget.name}, ${property.name})');
          }
        }
      }
    }

    expect(
      unclassified,
      isEmpty,
      reason: 'UNCLASSIFIED scalar decoder roster entries:\n'
          '${unclassified.join('\n')}',
    );

    expect(
      unknown,
      isEmpty,
      reason: 'Unrouted, unexempted layout-double slots:\n'
          '${unknown.join('\n')}',
    );
  });
}
