import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _key =
    ScalarCallbackContract(parameters: [ScalarCallbackParameter.valueKey]);
const _semantic = ScalarCallbackContract(parameters: [
  ScalarCallbackParameter.widget,
  ScalarCallbackParameter.itemIndex
]);
const _constant = ValueProgram(
    nodes: [ValueNode('literal', ValueType.integer, value: 2)], root: 0);

Map<String, Object?> _slot(ValueProgram program) => {
      'version': 1,
      'program': program.encode(),
      'captures': <String, Object?>{},
    };

Catalog _catalog(
        {bool nested = false,
        bool nullable = false,
        bool required = false,
        bool widgetBuilder = false,
        bool builtIn = false,
        List<PropertyEntry> additionalProperties = const []}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        (builtIn
                ? WidgetLibrary.core
                : const WidgetLibrary.custom('example.widgets')):
            const LibraryInfo(version: '1', capabilityVersion: 1)
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Host',
          library: builtIn
              ? WidgetLibrary.core
              : const WidgetLibrary.custom('example.widgets'),
          category: WidgetCategory.layout,
          description: 'Host',
          flutterType: 'package:fixture/host.dart#Host',
          childrenSlot: ChildrenSlot.none,
          properties: [
            nested
                ? PropertyEntry(
                    wireId: WireId('p0001'),
                    name: 'delegate',
                    type: PropertyType.structured,
                    description: 'Delegate',
                    structuredRef: WireIdRef(
                        library: 'example.widgets', wireId: WireId('s0001')))
                : PropertyEntry(
                    wireId: WireId('p0001'),
                    name: 'callback',
                    type: widgetBuilder
                        ? PropertyType.widgetBuilder
                        : PropertyType.scalarCallback,
                    description: 'Callback',
                    builderContract: widgetBuilder
                        ? const WidgetBuilderContract(
                            parameters: [WidgetBuilderParameter.buildContext])
                        : null,
                    scalarContract: widgetBuilder ? null : _key,
                    constructorNullable: nullable,
                    required: required,
                    sinceVersion: widgetBuilder ? 19 : 20),
            ...additionalProperties,
          ],
        )
      ],
      structuredTypes: [
        if (nested)
          StructuredEntry(
              wireId: WireId('s0001'),
              name: 'Delegate',
              library: const WidgetLibrary.custom('example.widgets'),
              description: 'Delegate',
              sourceType: 'package:fixture/delegate.dart#Delegate',
              fields: [
                StructuredField(
                    wireId: WireId('p0002'),
                    name: 'callback',
                    type: PropertyType.scalarCallback,
                    description: 'Callback',
                    scalarContract: _semantic)
              ],
              variants: [
                ConstructorVariant(wireId: WireId('v0001'))
              ])
      ],
    );

rfw.RemoteWidgetLibrary _library(Map<String, Object?> arguments) =>
    rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration(
          'Root', null, rfw.ConstructorCall('Host', arguments))
    ]);

final class _InstalledPredicate implements ValueOperation {
  @override
  String get name => 'test.predicate';
  @override
  int get capability => 23;
  @override
  void validate(ValueNode node, List<ValueType> inputs) {
    if (inputs.isNotEmpty || node.type.kind != 'bool') {
      throw const FormatException('Invalid predicate');
    }
  }

  @override
  Object evaluate(List<Object?> inputs, Object? options) => true;
}

void main() {
  test('nullable callbacks retain sibling exact native color requirements', () {
    const color = {
      'a': 0.812345,
      'r': 0.234567,
      'g': 0.345678,
      'b': 0.456789,
      'colorSpace': 'displayP3',
    };
    for (final widgetBuilder in [false, true]) {
      final catalog = _catalog(
        nullable: true,
        required: true,
        widgetBuilder: widgetBuilder,
        additionalProperties: [
          PropertyEntry(
            wireId: WireId('p0002'),
            name: 'color',
            type: PropertyType.color,
            description: 'Exact native sibling',
          ),
        ],
      );
      final arguments = <String, Object?>{
        'callback': {RfwConstructorPresenceProtocol.markerKey: 1},
        'color': color,
      };
      final exact = deriveSurfaceCapability(_library(arguments), catalog);
      expect(exact.builtInFloor, 19);
      expect(exact.requiredLibraries.single.minGenerated, 3);
      expect(
        deriveSurfaceCapability(
          _library({...arguments, 'color': 0xff123456}),
          catalog,
        ).builtInFloor,
        1,
      );
    }
  });

  test('nested installed operations raise the actual envelope capability floor',
      () {
    const predicate = ValueProgram(
        nodes: [ValueNode('test.predicate', ValueType.boolean)],
        root: 0,
        parameters: {'item': ValueType.integer});
    final program = ValueProgram(nodes: [
      const ValueNode('list', ValueType('list', item: ValueType.integer)),
      ValueNode('grid.indexWhere', ValueType.integer,
          inputs: const [0], value: predicate.encode()),
    ], root: 1);
    final installed = _InstalledPredicate();
    final operations = {...kGridValueOperations, installed.name: installed};
    expect(
        decodeRfwProgramEnvelope(_slot(program), operations: operations)!
            .capability,
        23);
    expect(
        () => decodeRfwProgramEnvelope(_slot(program)), throwsFormatException);
  });

  test('required nullable callbacks use canonical presence for both signatures',
      () {
    const marker = RfwConstructorPresenceProtocol.markerKey;
    const value = RfwConstructorPresenceProtocol.valueKey;
    const builder = BuilderProgram(
        values: _constant, result: BuilderResult.body(0), bodyCount: 1);
    final builderSlot = rfw.ConstructorCall(kBuilderContinuationWidgetName, {
      'version': 1,
      'program': builder.encode(),
      'captures': <String, Object?>{},
      'bodies': [
        const rfw.WidgetBuilderDeclaration(
            'frame', rfw.ConstructorCall('Body', {}))
      ]
    });
    for (final widgetBuilder in [false, true]) {
      final catalog = _catalog(
          nullable: true, required: true, widgetBuilder: widgetBuilder);
      expect(
          deriveSurfaceCapability(
                  _library({
                    'callback': {marker: 1}
                  }),
                  catalog)
              .builtInFloor,
          1);
      expect(
          deriveSurfaceCapability(
                  _library({
                    'callback': {
                      marker: 1,
                      value: widgetBuilder ? builderSlot : _slot(_constant)
                    }
                  }),
                  catalog)
              .builtInFloor,
          widgetBuilder ? 19 : 20);
      expect(() => deriveSurfaceCapability(_library({}), catalog),
          throwsFormatException);
      for (final malformed in <Object?>[
        null,
        rfw.missing,
        <String, Object?>{},
        _slot(_constant),
        {marker: 2},
        {marker: 1.0},
        {marker: 1, 'unknown': true},
        {marker: 1, value: 'bad'},
      ]) {
        expect(
            () => deriveSurfaceCapability(
                _library({'callback': malformed}), catalog),
            throwsFormatException);
      }
    }
  });

  test('explicit native nullable callback preserves null without a program',
      () {
    final catalog = _catalog(nullable: true);
    final property = catalog.widgets.single.properties.single;
    expect(validateRfwPropertyCallbacks(null, property, catalog), 1);
    expect(
        deriveSurfaceCapability(_library({'callback': null}), catalog)
            .builtInFloor,
        deriveSurfaceCapability(_library({}), catalog).builtInFloor);
    for (final widgetBuilder in [false, true]) {
      final builtin =
          _catalog(nullable: true, builtIn: true, widgetBuilder: widgetBuilder);
      expect(
          deriveSurfaceCapability(_library({'callback': null}), builtin)
              .builtInFloor,
          1);
      expect(deriveSurfaceCapability(_library({}), builtin).builtInFloor, 1);
      final required = _catalog(
          nullable: true,
          required: true,
          builtIn: true,
          widgetBuilder: widgetBuilder);
      expect(
          deriveSurfaceCapability(
                  _library({
                    'callback': {RfwConstructorPresenceProtocol.markerKey: 1}
                  }),
                  required)
              .builtInFloor,
          1);
    }
    final structured = _catalog(nested: true);
    expect(
        () => validateRfwPropertyCallbacks({'callback': null},
            structured.widgets.single.properties.single, structured),
        throwsFormatException);
    final nonnullable = _catalog();
    expect(
        () => validateRfwPropertyCallbacks(
            null, nonnullable.widgets.single.properties.single, nonnullable),
        throwsFormatException);
  });

  test(
      'scalar callbacks derive floor20 and generated vocabulary3 from actual slots',
      () {
    final capability = deriveSurfaceCapability(
        _library({'callback': _slot(_constant)}), _catalog());
    expect(capability.builtInFloor, 20);
    expect(capability.requiredLibraries.single.minGenerated, 3);
    expect(kGeneratedVocabularyVersion, 3);
  });

  test(
      'scalar parameter identity and result nullability match exact native signature',
      () {
    const keyType = ValueType('record', fields: {'value': ValueType.string});
    const key = ValueProgram(
        nodes: [ValueNode('literal', ValueType.integer, value: 2)],
        root: 0,
        parameters: {'arg0': keyType});
    validateRfwScalarContract(_slot(key), _key);
    expect(() => validateRfwScalarContract(_slot(key), _semantic),
        throwsFormatException);
    const semantic = ValueProgram(
        nodes: [ValueNode('parameter', ValueType.integer, name: 'arg1')],
        root: 0,
        parameters: {'arg1': ValueType.integer});
    validateRfwScalarContract(_slot(semantic), _semantic);
    expect(() => validateRfwScalarContract(_slot(semantic), _key),
        throwsFormatException);
    const nullable = ValueProgram(
        nodes: [ValueNode('literal', ValueType.nullType, value: null)],
        root: 0);
    validateRfwScalarContract(_slot(nullable), _key);
    expect(
        () => validateRfwScalarContract(
            _slot(nullable),
            const ScalarCallbackContract(
                parameters: [ScalarCallbackParameter.valueKey],
                nullableResult: false)),
        throwsFormatException);
    const widget = ValueProgram(
        nodes: [ValueNode('parameter', ValueType.integer, name: 'arg0')],
        root: 0,
        parameters: {'arg0': ValueType.integer});
    expect(() => validateRfwScalarContract(_slot(widget), _semantic),
        throwsFormatException);
  });

  test(
      'structured callback fields retain signatures and floor through catalog links',
      () {
    const semantic = ValueProgram(
        nodes: [ValueNode('parameter', ValueType.integer, name: 'arg1')],
        root: 0,
        parameters: {'arg1': ValueType.integer});
    final capability = deriveSurfaceCapability(
        _library({
          'delegate': {'callback': _slot(semantic)}
        }),
        _catalog(nested: true));
    expect(capability.builtInFloor, 20);
    expect(capability.requiredLibraries.single.minGenerated, 3);
    const key = ValueProgram(
        nodes: [ValueNode('literal', ValueType.integer, value: 2)],
        root: 0,
        parameters: {
          'arg0': ValueType('record', fields: {'value': ValueType.string})
        });
    expect(
        () => deriveSurfaceCapability(
            _library({
              'delegate': {'callback': _slot(key)}
            }),
            _catalog(nested: true)),
        throwsFormatException);
  });

  test('native scalar parameters require a catalog-declared callback slot', () {
    const program = ValueProgram(
        nodes: [ValueNode('parameter', ValueType.integer, name: 'arg1')],
        root: 0,
        parameters: {'arg1': ValueType.integer});
    final catalog = _catalog(nested: true);
    expect(
        () => deriveSurfaceCapability(
            _library({
              'delegate': {'unknown': _slot(program)}
            }),
            catalog),
        throwsFormatException);
  });

  test('grid operations validate nested closed predicates and derive floor20',
      () {
    const predicate = ValueProgram(
        nodes: [ValueNode('literal', ValueType.boolean, value: true)],
        root: 0,
        parameters: {'item': ValueType.integer});
    final program = ValueProgram(nodes: [
      const ValueNode('literal', ValueType('list', item: ValueType.integer),
          value: [1, 2]),
      ValueNode('grid.indexWhere', ValueType.integer,
          inputs: const [0], value: predicate.encode()),
    ], root: 1);
    expect(
        surfaceFeatureClientFloor(_library({'callback': _slot(program)})), 20);
    const unknown = ValueProgram(
        nodes: [ValueNode('native.execute', ValueType.boolean)],
        root: 0,
        parameters: {'item': ValueType.integer});
    final malformed = ValueProgram(nodes: [
      const ValueNode('literal', ValueType('list', item: ValueType.integer),
          value: [1]),
      ValueNode('grid.indexWhere', ValueType.integer,
          inputs: const [0], value: unknown.encode()),
    ], root: 1);
    expect(
        () =>
            surfaceFeatureClientFloor(_library({'callback': _slot(malformed)})),
        throwsFormatException);
  });
}
