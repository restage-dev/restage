import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

import 'generated/interactive_catalog.g.dart' as interactive;
import 'generated/rich_shape_catalog.g.dart' as rich;

/// The document↔CatalogItem schema tie (the drift guard for the standalone
/// A2UI document's per-component data schema).
///
/// The standalone document (`<catalog>.a2ui.json`) carries each component's full
/// data schema so a producer can generate payloads against the document alone.
/// That schema is projected — by the build-time toolchain — from the SAME
/// fixture shapes/seams, replicating what the generated `CatalogItem.dataSchema`
/// genui renders + projects the LLM contract from. This test pins the two EQUAL
/// against the REAL genui SDK: it reads each `CatalogItem.dataSchema.value` and
/// asserts it equals the document's component schema. If the document projector
/// and the CatalogItem schema expression ever diverge, this fails — that is the
/// whole reason it exists (the document carries the schema a second time, so the
/// drift vector is closed by a guard, not by hope).
///
/// Two committed catalogs are tied so coverage spans both projection surfaces:
///  * **rich-shape** — nested objects, lists-of-objects, String-keyed maps,
///    named records, nullable fields, and a recursive `CommentThread` (a
///    `$ref`/`$defs` document, where the `component` discriminator is overlaid
///    as a `$ref` sibling, exactly as genui's `dataSchema` getter does);
///  * **interactive** — write-back fields whose schema is the value-reference
///    `oneOf` (literal / `{path}` binding / `{call}` function-call) plus
///    dispatch widgets, so the write-back projection is pinned to genui too.
void main() {
  _tieGroup(
    label: 'rich-shape',
    items: rich.buildRestageCatalogItems(),
    documentPath: 'test/generated/rich_shape_catalog.a2ui.json',
  );
  _tieGroup(
    label: 'interactive',
    items: interactive.buildRestageCatalogItems(),
    documentPath: 'test/generated/interactive_catalog.a2ui.json',
  );
}

void _tieGroup({
  required String label,
  required List<CatalogItem> items,
  required String documentPath,
}) {
  test('$label: every document component schema == its genui '
      'CatalogItem.dataSchema (against real genui)', () {
    final document =
        jsonDecode(File(documentPath).readAsStringSync())
            as Map<String, Object?>;
    final components = ((document['a2uiCatalog']! as Map)['components']! as Map)
        .cast<String, Object?>();

    expect(items, isNotEmpty);
    expect(
      components.keys.toSet(),
      {for (final item in items) item.name},
      reason:
          'the document and the generated catalog must cover the same '
          'component set',
    );

    for (final item in items) {
      final componentSchema = (components[item.name]! as Map)
          .cast<String, Object?>();
      // The document component schema IS genui's canonical component-schema
      // format (data + the injected `component` discriminator), so it must
      // equal `CatalogItem.dataSchema.value` — the same shape genui projects
      // the LLM contract from — outright.
      expect(
        _canonicalJson(componentSchema),
        _canonicalJson(item.dataSchema.value),
        reason:
            '$label component "${item.name}": the standalone document component '
            'schema must equal the genui CatalogItem.dataSchema.value',
      );
    }
  });
}

/// Canonicalizes [node] to a JSON string with map keys sorted (so the
/// comparison is order-independent for object members) and list order preserved
/// (so it stays order-SENSITIVE for `required`/`enum`/`anyOf`/`oneOf`, where
/// order is significant). Both sides pass through this, normalizing the
/// in-memory builder map (a `json_schema_builder` `Schema`, an extension type
/// over `Map`) and the parsed-from-disk document to the same plain JSON shape.
String _canonicalJson(Object? node) => jsonEncode(_canonical(node));

Object? _canonical(Object? node) {
  if (node is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in node.entries) {
      sorted[entry.key as String] = _canonical(entry.value);
    }
    return sorted;
  }
  if (node is List) {
    return [for (final element in node) _canonical(element)];
  }
  return node;
}
