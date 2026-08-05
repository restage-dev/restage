import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The shared value-shape resolver CAN return an opaque shape — one carrying
/// `PropertyType.unknown` — and the structured walker's fallback cannot lower
/// one: the property-type-to-kind mapping rejects `unknown` by design, with a
/// throw that fails the build.
///
/// What keeps that throw unreachable is ORDERING: each opaque shape is
/// intercepted by its own arm before the fallback runs. That is an invariant of
/// the walker, not of the resolver, and it is easy to break by moving an arm or
/// by adding a new opaque shape without an arm to match.
///
/// These tests pin it from both sides. Note the two failure modes differ: drop
/// the record interception and the fallback resolves an opaque shape and
/// THROWS; drop the map interception and the fallback resolves nothing, so the
/// field is silently dropped instead. Loud and quiet respectively, which is
/// why both are asserted rather than one standing in for the other.
String _nestedWidget(String fieldDeclaration) => '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  class Entry {
    const Entry({required this.label, required this.meta});
    final String label;
    $fieldDeclaration
  }
  @RestageWidget(name: 'SectionHeader',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration, description: 'h')
  class SectionHeader {
    const SectionHeader({required this.entry});
    @RestageProperty(description: 'e') final Entry entry;
  }
''';

void main() {
  Future<void> expectFieldCarriesOpaqueShape(
    String fieldDeclaration,
    String fieldName,
    bool Function(ScalarShape shape) predicate,
  ) async {
    final result = await runWidgetVisitorOn({
      'lib/header.dart': _nestedWidget(fieldDeclaration),
    });

    // A build that reaches the fallback DIES rather than recording an issue,
    // so the observable evidence is that nothing was produced at all. Assert
    // that directly: without it the test still fails, but only by throwing
    // deep inside a lookup, which tells a future reader nothing about why.
    expect(
      result.structuredTypes,
      isNotEmpty,
      reason: 'the walk produced nothing, which is what reaching the resolver '
          'fallback does — it throws on an opaque shape and fails the build '
          'before any type is emitted',
    );

    final entry = result.structuredTypes.firstWhere((s) => s.name == 'Entry');
    final fields = entry.fields.where((f) => f.name == fieldName).toList();
    expect(
      fields,
      hasLength(1),
      reason: 'the field must be materialized by its own arm, not dropped; '
          'got ${entry.fields.map((f) => f.name).toList()}',
    );
    expect(fields.single.type, PropertyType.unknown);
    expect(predicate(fields.single.valueShape! as ScalarShape), isTrue);
  }

  test('a record field is intercepted before the resolver fallback', () async {
    await expectFieldCarriesOpaqueShape(
      'final ({int order, bool pinned}) meta;',
      'meta',
      (shape) => shape.isOpaqueRecord,
    );
  });

  test('a map field is intercepted before the resolver fallback', () async {
    await expectFieldCarriesOpaqueShape(
      'final Map<String, int> meta;',
      'meta',
      (shape) => shape.isOpaqueStringKeyedMap,
    );
  });
}
