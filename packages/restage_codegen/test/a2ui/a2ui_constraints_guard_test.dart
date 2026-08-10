import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('unknown constraint extensions fail loud with sorted context', () {
    final constraints = RestageConstraints.withExtensions(
      minimum: 1,
      extensions: const {
        'x-zeta': true,
        'x-alpha': {'future': 1},
      },
    );
    final catalog = _allocatedCatalog(
      constraints,
    );
    expect(catalog.widgets.single.properties.single.constraints, constraints);

    expect(
      () => classifyA2uiCatalogDart(catalog),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('widget "ConstraintWidget"'),
            contains('property "count"'),
            contains('x-alpha, x-zeta'),
          ),
        ),
      ),
    );
  });

  test('known constraints are accepted and projected onto the property', () {
    const constraints = RestageConstraints(
      minimum: 1,
      maximum: 5,
      allowedValues: [1, 3, 5],
    );
    final propagated = _allocatedCatalog(constraints);
    expect(
      propagated.widgets.single.properties.single.constraints,
      constraints,
    );
    final constrained = classifyA2uiCatalogDart(
      propagated,
    ).widgets.single;

    final rootProperties =
        a2uiWidgetDataSchemaMapForPlan(constrained)['properties']! as Map;
    final props = rootProperties['props']! as Map;
    expect(
      (props['properties']! as Map)['count'],
      {
        'type': 'integer',
        'description': 'Count.',
        'minimum': 1,
        'maximum': 5,
        'enum': [1, 3, 5],
      },
    );
  });
}

Catalog _catalog([
  RestageConstraints constraints = RestageConstraints.empty,
]) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-07-20T00:00:00.000Z',
      libraries: {
        const WidgetLibrary.custom('fixture.design_system'):
            const LibraryInfo(version: '1.0.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ConstraintWidget',
          library: const WidgetLibrary.custom('fixture.design_system'),
          category: WidgetCategory.input,
          description: 'Constraint widget.',
          flutterType: 'package:fixture/fixture.dart#ConstraintWidget',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'count',
              type: PropertyType.integer,
              description: 'Count.',
              constraints: constraints,
            ),
          ],
        ),
      ],
    );

Catalog _allocatedCatalog([
  RestageConstraints constraints = RestageConstraints.empty,
]) =>
    allocateUserCatalogFromWidgets(
      package: 'fixture.design_system',
      widgets: _catalog(constraints).widgets,
    ).catalog;
