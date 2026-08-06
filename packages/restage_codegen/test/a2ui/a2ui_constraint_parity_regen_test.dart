import 'dart:convert';
import 'dart:io';

import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'a2ui_safe_pattern_corpus.dart';

const _fixtureRelativePath =
    '../restage_a2ui/test/generated/constraint_parity_fixture.dart';
const _fixtureImport = 'constraint_parity_fixture.dart';
const _generatedPath =
    '../restage_a2ui/test/generated/constraint_parity_catalog.g.dart';
const _documentPath =
    '../restage_a2ui/test/generated/constraint_parity_catalog.a2ui.json';

String _fixtureUri() => Uri.file(
      File(_fixtureRelativePath).resolveSymbolicLinksSync(),
    ).toString();

Catalog _catalog(String fixtureUri) => catalogWith([
      entry(
        name: 'ConstraintParity',
        flutterType: '$fixtureUri#ConstraintParityFixture',
        properties: const [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'count',
            type: PropertyType.integer,
            description: '',
            required: true,
            constraints: RestageConstraints(
              minimum: 0.5,
              maximum: 9.5,
              allowedValues: [1, 2],
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'tags',
            type: PropertyType.stringList,
            description: '',
            required: true,
            constraints: RestageConstraints(minItems: 1, maxItems: 3),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'ratio',
            type: PropertyType.real,
            description: '',
            required: true,
            constraints: RestageConstraints(
              exclusiveMinimum: 0.25,
              exclusiveMaximum: 0.75,
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'code',
            type: PropertyType.string,
            description: '',
            required: true,
            constraints: RestageConstraints(
              pattern: r'^[A-Z]{2}[0-9]+$',
              minLength: 3,
              maxLength: 8,
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'items',
            type: PropertyType.unknown,
            description: '',
            required: true,
            constraints: RestageConstraints(minItems: 1, maxItems: 4),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'legacyCount',
            type: PropertyType.real,
            description: '',
            required: true,
            validationRule: ValidationExpr(
              expression: 'range(-10, 10)',
              message: 'Keep count within the authored range.',
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'legacyMode',
            type: PropertyType.string,
            description: '',
            required: true,
            validationRule: ValidationExpr(
              expression: 'oneOf("compact", "expanded")',
              message: 'Choose an authored mode.',
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'legacyCode',
            type: PropertyType.string,
            description: '',
            required: true,
            validationRule: ValidationExpr(
              expression: r'matches("^[a-z]+$")',
              message: 'Use lowercase ASCII letters.',
            ),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onCountChanged',
            type: PropertyType.event,
            description: '',
            required: true,
          ),
        ],
      ),
      for (var index = 0; index < acceptedA2uiPatternCases.length; index++)
        entry(
          name: _patternWidgetName(index),
          flutterType: '$fixtureUri#PatternCorpusFixture',
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'typedPattern',
              type: PropertyType.string,
              description: '',
              required: true,
              constraints: RestageConstraints(
                pattern: acceptedA2uiPatternCases[index].pattern,
              ),
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'legacyPattern',
              type: PropertyType.string,
              description: '',
              required: true,
              validationRule: ValidationExpr(
                expression: _legacyPatternExpression(
                  acceptedA2uiPatternCases[index].pattern,
                ),
                message: 'Pattern corpus case $index.',
              ),
            ),
          ],
        ),
    ]);

String _patternWidgetName(int index) =>
    'PatternCorpus${index.toString().padLeft(2, '0')}';

String _legacyPatternExpression(String pattern) =>
    'matches(${jsonEncode(pattern)})';

A2uiRichShapes _richShapes(String fixtureUri) {
  final recursiveId = '$fixtureUri#ConstraintRecursiveItem';
  final recursive = ObjectNode(
    defId: recursiveId,
    construction: A2uiClassConstruction(
      dartTypeName: 'ConstraintRecursiveItem',
      libraryUri: fixtureUri,
      parameters: const [
        A2uiConstructorParameter(name: 'label', named: true),
        A2uiConstructorParameter(name: 'children', named: true),
      ],
    ),
    fields: {
      'label': const ScalarNode(A2uiScalarType.string),
      'children': ListNode(element: RefNode(recursiveId)),
    },
    required: const {'label', 'children'},
  );
  return <(String, String), A2uiSchemaNode>{
    ('ConstraintParity', 'count'):
        const ScalarNode(A2uiScalarType.integer, nullable: true),
    ('ConstraintParity', 'tags'): const ListNode(
      element: ScalarNode(A2uiScalarType.string),
      nullable: true,
    ),
    ('ConstraintParity', 'items'): ListNode(element: recursive, nullable: true),
  };
}

const _eventSeam = <(String, String), A2uiCallbackSignature>{
  ('ConstraintParity', 'onCountChanged'): A2uiCallbackWriteBack(
    A2uiScalarType.integer,
    nullable: true,
    isList: false,
  ),
};
const _pairingSeam = <(String, String), String>{
  ('ConstraintParity', 'onCountChanged'): 'count',
};

void main() {
  test('constraint parity generated fixture is current', () {
    final fixtureUri = _fixtureUri();
    final catalog = _catalog(fixtureUri);
    final patternEntries = catalog.widgets
        .where((widget) => widget.name.startsWith('PatternCorpus'))
        .toList();
    expect(
      patternEntries,
      hasLength(acceptedA2uiPatternCases.length),
      reason: 'every accepted pattern must have a real emitted widget',
    );
    expect(
      patternEntries.map((widget) => widget.properties.length),
      everyElement(2),
      reason: 'every accepted widget must have typed and legacy properties',
    );
    final richShapes = _richShapes(fixtureUri);
    final registration = emitA2uiCatalog(
      catalog,
      richShapes: richShapes,
      eventSeam: _eventSeam,
      pairingSeam: _pairingSeam,
    );
    final emitted = emitA2uiCatalogDart(
      catalog,
      registration: registration,
      richShapes: richShapes,
      eventSeam: _eventSeam,
      pairingSeam: _pairingSeam,
    );
    final normalized = formatGeneratedDart(
      emitted.replaceAll(fixtureUri, _fixtureImport),
    ).trimRight();
    final generatedFile = File(_generatedPath);
    if (Platform.environment['REGEN_A2UI_DART_GOLDEN'] == '1') {
      generatedFile.parent.createSync(recursive: true);
      generatedFile.writeAsStringSync('$normalized\n');
    }
    expect(
      generatedFile.existsSync(),
      isTrue,
      reason: 'run with REGEN_A2UI_DART_GOLDEN=1 to generate $_generatedPath',
    );
    expect(normalized, generatedFile.readAsStringSync().trimRight());

    const encoder = JsonEncoder.withIndent('  ');
    final document = encoder.convert(registration.toJson());
    final documentFile = File(_documentPath);
    if (Platform.environment['REGEN_A2UI_GOLDEN'] == '1') {
      documentFile.parent.createSync(recursive: true);
      documentFile.writeAsStringSync('$document\n');
    }
    expect(
      documentFile.existsSync(),
      isTrue,
      reason: 'run with REGEN_A2UI_GOLDEN=1 to generate $_documentPath',
    );
    expect(document, documentFile.readAsStringSync().trimRight());
  });
}
