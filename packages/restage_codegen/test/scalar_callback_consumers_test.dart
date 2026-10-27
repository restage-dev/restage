import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_property_capability.dart';
import 'package:restage_shared/restage_shared.dart'
    show ValueNode, ValueProgram, ValueType;
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

Catalog _catalog({bool requiredCallback = false}) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1')},
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'GridHost',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'Grid host',
          flutterType: 'package:fixture/grid.dart#GridHost',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
                wireId: WireId('p0001'),
                name: 'findChildIndexCallback',
                type: PropertyType.scalarCallback,
                description: 'Find an index',
                required: requiredCallback,
                scalarContract: const ScalarCallbackContract(
                    parameters: [ScalarCallbackParameter.valueKey]))
          ],
        )
      ],
    );

void main() {
  for (final requiredCallback in [false, true]) {
    test(
        'A2UI explicitly refuses ${requiredCallback ? 'required' : 'optional'} scalar callbacks',
        () {
      final plan =
          classifyA2uiCatalogDart(_catalog(requiredCallback: requiredCallback));
      expect(plan.widgets, isEmpty);
      final drop = plan.coverage.droppedWidgets.single;
      expect(drop.widgetName, 'GridHost');
      expect(drop.fieldName, 'findChildIndexCallback');
      expect(drop.reason, A2uiDartCoverageReason.unsupportedScalarCallback);
      expect(plan.coverage.omittedFields, isEmpty);
    });
  }

  test('Widgetbook rejects scalar callbacks in widget and structured contexts',
      () {
    for (final context in WidgetbookPropertyContext.values) {
      expect(
          widgetbookPropertyCapability(PropertyType.scalarCallback,
              context: context),
          WidgetbookPropertyCapability.rejected);
    }
    expect(
        widgetbookFiniteChoiceTransport(PropertyType.scalarCallback), isNull);
  });

  test('catalog validator rejects a scalar literal in a callback slot', () {
    final library = rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration('Root', null,
          rfw.ConstructorCall('GridHost', {'findChildIndexCallback': 3}))
    ]);
    final issues = validateModelAgainstCatalog(library, _catalog());
    expect(issues.single.code, IssueCode.propertyValueTypeMismatch);
    expect(issues.single.message, contains('scalarCallback'));
  });

  for (final (type, value, accepted) in [
    (ValueType.integer, 3, true),
    (ValueType.string, '3', false),
  ]) {
    test(
        'catalog validator checks ${type.kind} callback result against its slot',
        () {
      final program = ValueProgram(
        nodes: [ValueNode('literal', type, value: value)],
        root: 0,
      );
      final library = rfw.RemoteWidgetLibrary(const [], [
        rfw.WidgetDeclaration(
            'Root',
            null,
            rfw.ConstructorCall('GridHost', {
              'findChildIndexCallback': {
                'version': 1,
                'program': program.encode(),
                'captures': <String, Object?>{},
              },
            })),
      ]);
      if (accepted) {
        expect(validateModelAgainstCatalog(library, _catalog()), isEmpty);
      } else {
        expect(() => validateModelAgainstCatalog(library, _catalog()),
            throwsFormatException);
      }
    });
  }
}
