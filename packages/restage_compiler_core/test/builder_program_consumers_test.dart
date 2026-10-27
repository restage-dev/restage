import 'dart:convert';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _values = ValueProgram(
  nodes: [ValueNode('literal', ValueType.integer, value: 7)],
  root: 0,
);
const _program = BuilderProgram(
  values: _values,
  result: BuilderResult.body(0, values: {'v0': 0}),
  bodyCount: 1,
);

Map<String, Object?> _slot({
  BuilderProgram program = _program,
  Map<String, Object?> captures = const {},
  rfw.ConstructorCall? body,
}) =>
    {
      'version': 1,
      'program': program.encode(),
      'captures': captures,
      'bodies': [
        rfw.WidgetBuilderDeclaration(
          'frame',
          body ?? const rfw.ConstructorCall('Body', {}),
        ),
      ],
    };

rfw.RemoteWidgetLibrary _library(Object? value) => rfw.RemoteWidgetLibrary(
      const [],
      [
        rfw.WidgetDeclaration(
          'Root',
          null,
          rfw.ConstructorCall('Host', {'builder': value}),
        ),
      ],
    );

Catalog _catalog({WidgetBuilderContract? contract}) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1')},
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Host',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'Host',
          flutterType: 'package:fixture/host.dart#Host',
          childrenSlot: ChildrenSlot.none,
          properties: [
            if (contract != null)
              PropertyEntry(
                wireId: WireId('p0001'),
                name: 'builder',
                type: PropertyType.widgetBuilder,
                description: 'Builder',
                builderContract: contract,
              ),
          ],
        ),
        WidgetEntry(
          wireId: WireId('w0002'),
          name: 'Body',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'Body',
          flutterType: 'package:fixture/host.dart#Body',
          childrenSlot: ChildrenSlot.none,
          properties: const [],
          sinceVersion: 21,
        ),
      ],
    );

rfw.RfwCatalogOccurrenceResolutionInput _resolution() =>
    rfw.RfwCatalogOccurrenceResolutionInput(
      artifactProvenance: 'fixture.artifact',
      sourceLibraryIdentity: 'fixture.library',
      sourceDeclarationIdentity: 'fixture.root',
      renderEntryNames: const ['Root'],
      localSymbols: [rfw.RfwCatalogLocalSymbol(name: 'Root')],
      catalogConstructors: [
        for (final entry in _catalog().widgets)
          rfw.RfwCatalogConstructorProvenance(
            constructorName: entry.name,
            catalogLibraryNamespace: entry.library.namespace,
            catalogWidgetWireId: entry.wireId,
          ),
      ],
    );

List<SurfaceScreenContractGap> _gaps(
  Object? value, {
  SurfaceScreenHostDataSchema? context,
}) =>
    surfaceScreenContractGaps(
      _library(value),
      events: SurfaceScreenEventSchema(
        events: [
          SurfaceScreenEvent(
            id: 'pick',
            arguments: const SurfaceScreenEventValueArguments(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKind.integer,
              ),
            ),
          ),
        ],
      ),
      context: context ?? SurfaceScreenHostDataSchema(const {}),
    );

void main() {
  test('installed continuation keeps capability, frame events and occurrences',
      () {
    final call = rfw.ConstructorCall(
        kBuilderContinuationWidgetName,
        _slot(
            body: const rfw.ConstructorCall('Body', {
          'onTap': rfw.EventHandler('pick', {
            'value': rfw.WidgetBuilderArgReference('frame', ['values', 'v0'])
          })
        })));
    final library = _library(call);
    expect(surfaceFeatureClientFloor(library), 19);
    expect(deriveSurfaceCapability(library, _catalog()).builtInFloor, 21);
    expect(_gaps(call), isEmpty);
    final resolved = ResolvedRfwCatalogOccurrenceSet.resolve(
        parsedLibrary: library, input: _resolution());
    expect(
        resolved
            .inspectFinalBody(library)
            .constructorCalls
            .map((call) => call.name),
        containsAll(['Host', kBuilderContinuationWidgetName, 'Body']));
    expect(
        () => surfaceFeatureClientFloor(_library(
            const rfw.ConstructorCall(kBuilderContinuationWidgetName, {}))),
        throwsFormatException);
  });

  test('custom generated factories require the expression vocabulary when used',
      () {
    const custom = WidgetLibrary.custom('example.widgets');
    final host = WidgetEntry(
      wireId: WireId('w0001'),
      name: 'Host',
      library: custom,
      category: null,
      description: 'Host',
      flutterType: 'package:fixture/host.dart#Host',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'builder',
          type: PropertyType.integer,
          description: 'Computed integer',
        ),
      ],
    );
    final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      widgets: [host],
      libraries: {
        custom: const LibraryInfo(version: '1', capabilityVersion: 1),
      },
    );
    expect(
      deriveSurfaceCapability(
        _library({
          'version': 1,
          'program': _values.encode(),
          'captures': <String, Object?>{},
        }),
        catalog,
      ).requiredLibraries.single.minGenerated,
      3,
    );
    expect(
      deriveSurfaceCapability(_library(7), catalog)
          .requiredLibraries
          .single
          .minGenerated,
      1,
    );
    expect(
      deriveSurfaceCapability(
        rfw.RemoteWidgetLibrary(const [], [
          rfw.WidgetDeclaration(
            'Root',
            null,
            rfw.ConstructorCall('Host', {
              'ignored': {
                'version': 1,
                'program': _values.encode(),
                'captures': <String, Object?>{},
              },
            }),
          ),
        ]),
        catalog,
      ).requiredLibraries.single.minGenerated,
      1,
    );
    expect(
      generatedCodeFloor(
        _catalog(
          contract: const WidgetBuilderContract(
            parameters: [WidgetBuilderParameter.buildContext],
          ),
        ).widgets.first,
        _catalog(),
      ),
      3,
    );
  });

  test('actual program use raises the floor even inside nested maps and lists',
      () {
    expect(
      surfaceFeatureClientFloor(
        _library({
          'nested': [_slot()],
        }),
      ),
      19,
    );
    expect(surfaceFeatureClientFloor(_library({'label': 'plain'})), 1);
    expect(
      deriveSurfaceCapability(_library(_slot()), _catalog()).builtInFloor,
      21,
    );
    expect(
      surfaceFeatureClientFloor(
        _library({
          'version': 1,
          'program': _values.encode(),
          'captures': <String, Object?>{},
        }),
      ),
      19,
    );
  });

  test('unknown operations and declared floors cannot bypass closed decoding',
      () {
    final json = jsonDecode(_program.encode()) as Map<String, Object?>;
    final nodes = (json['values']! as Map)['nodes']! as List;
    (nodes.first as Map)['op'] = 'host.execute';
    final slot = {..._slot(), 'program': jsonEncode(json)};
    expect(
      () => surfaceFeatureClientFloor(_library(slot)),
      throwsFormatException,
    );
    expect(
      () => surfaceFeatureClientFloor(_library({..._slot(), 'floor': 19})),
      throwsFormatException,
    );
    expect(
      () => surfaceFeatureClientFloor(
        _library({..._slot(), 'program': 'arbitrary'}),
      ),
      throwsFormatException,
    );
  });

  test('envelopes require exact versions, capture names, and body counts', () {
    for (final slot in [
      {..._slot(), 'version': 2},
      {
        ..._slot(),
        'captures': {'undeclared': 3},
      },
      {..._slot(), 'bodies': <Object>[]},
      {
        ..._slot(),
        'bodies': [const rfw.ConstructorCall('Body', {})],
      },
    ]) {
      expect(
        () => surfaceFeatureClientFloor(_library(slot)),
        throwsFormatException,
      );
    }
  });

  test('native parameter identity and result nullability match the catalog',
      () {
    const contract = WidgetBuilderContract(
      parameters: [
        WidgetBuilderParameter.buildContext,
        WidgetBuilderParameter.orientation,
      ],
    );
    const values = ValueProgram(
      nodes: [ValueNode('parameter', ValueType.string, name: 'arg1')],
      root: 0,
      parameters: {'arg1': ValueType.string},
    );
    const program = BuilderProgram(
      values: values,
      result: BuilderResult.body(0),
      bodyCount: 1,
    );
    expect(
      deriveSurfaceCapability(
        _library(_slot(program: program)),
        _catalog(contract: contract),
      ).builtInFloor,
      21,
    );
    expect(
      () => deriveSurfaceCapability(
        _library(_slot(program: program)),
        _catalog(
          contract: const WidgetBuilderContract(
            parameters: [
              WidgetBuilderParameter.buildContext,
              WidgetBuilderParameter.boxConstraints,
            ],
          ),
        ),
      ),
      throwsFormatException,
    );
    const nullable = BuilderProgram(
      values: _values,
      result: BuilderResult.nullResult(),
      bodyCount: 1,
      nullableResult: true,
    );
    expect(
      () => deriveSurfaceCapability(
        _library(_slot(program: nullable)),
        _catalog(contract: contract),
      ),
      throwsFormatException,
    );
  });

  test('context parameters use only installed typed projections', () {
    const name = 'context:device:screenWidth';
    final type = builderContextValueType(name)!;
    final values = ValueProgram(
      nodes: [ValueNode('parameter', type, name: name)],
      root: 0,
      parameters: {name: type},
    );
    final program = BuilderProgram(
      values: values,
      result: const BuilderResult.body(0),
      bodyCount: 1,
    );
    expect(surfaceFeatureClientFloor(_library(_slot(program: program))), 19);
    const invalid = BuilderProgram(
      values: ValueProgram(
        nodes: [ValueNode('parameter', ValueType.integer, name: 'arg0')],
        root: 0,
        parameters: {'arg0': ValueType.integer},
      ),
      result: BuilderResult.body(0),
      bodyCount: 1,
    );
    expect(
      () => surfaceFeatureClientFloor(_library(_slot(program: invalid))),
      throwsFormatException,
    );
  });

  test('occurrences and final inspection retain deferred bodies and captures',
      () {
    const values = ValueProgram(
      nodes: [ValueNode('capture', ValueType.integer, name: 'c0')],
      root: 0,
      captures: {'c0': ValueType.integer},
    );
    const program = BuilderProgram(
      values: values,
      result: BuilderResult.body(0, values: {'v0': 0}),
      bodyCount: 1,
    );
    final library = _library(
      _slot(
        program: program,
        captures: {
          'c0': const rfw.DataReference(['context', 'count']),
        },
        body: const rfw.ConstructorCall('Body', {
          'onTap': rfw.EventHandler('pick', {
            'value': rfw.WidgetBuilderArgReference('frame', ['values', 'v0']),
          }),
        }),
      ),
    );
    final resolved = ResolvedRfwCatalogOccurrenceSet.resolve(
      parsedLibrary: library,
      input: _resolution(),
    );
    expect(
      resolved.occurrences.map((entry) => entry.constructorCall.name),
      unorderedEquals(['Host', 'Body']),
    );
    final finalBody = resolved.inspectFinalBody(library);
    expect(finalBody.events.single.eventName, 'pick');
    expect(finalBody.dataReferences.single.parts, ['context', 'count']);
    expect(
      () => ResolvedRfwCatalogOccurrenceSet.resolve(
        parsedLibrary: _library({..._slot(), 'bodies': <Object>[]}),
        input: _resolution(),
      ),
      throwsFormatException,
    );
  });

  test(
      'typed event projection checks body frame values without evaluating them',
      () {
    rfw.ConstructorCall body(Object value) => rfw.ConstructorCall('Body', {
          'onTap': rfw.EventHandler('pick', {'value': value}),
        });
    expect(
      _gaps(
        _slot(
          body: body(
            const rfw.WidgetBuilderArgReference(
              'frame',
              ['values', 'v0'],
            ),
          ),
        ),
      ),
      isEmpty,
    );
    const strings = BuilderProgram(
      values: ValueProgram(
        nodes: [ValueNode('literal', ValueType.string, value: 'seven')],
        root: 0,
      ),
      result: BuilderResult.body(0, values: {'v0': 0}),
      bodyCount: 1,
    );
    expect(
      _gaps(
        _slot(
          program: strings,
          body: body(
            const rfw.WidgetBuilderArgReference(
              'frame',
              ['values', 'v0'],
            ),
          ),
        ),
      ).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
  });

  test('capture shape claims are checked against the declared host data', () {
    const values = ValueProgram(
      nodes: [ValueNode('capture', ValueType.integer, name: 'c0')],
      root: 0,
      captures: {'c0': ValueType.integer},
    );
    const program = BuilderProgram(
      values: values,
      result: BuilderResult.body(0),
      bodyCount: 1,
    );
    final slot = _slot(
      program: program,
      captures: {
        'c0': const rfw.DataReference(['context', 'count']),
      },
    );
    expect(
      _gaps(
        slot,
        context: SurfaceScreenHostDataSchema(const {
          'count': SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.integer,
          ),
        }),
      ),
      isEmpty,
    );
    expect(
      () => _gaps(
        slot,
        context: SurfaceScreenHostDataSchema(const {
          'count': SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.string,
          ),
        }),
      ),
      throwsFormatException,
    );
  });

  test('nested builder captures retain outer frame typing', () {
    const inner = BuilderProgram(
      values: ValueProgram(
        nodes: [ValueNode('capture', ValueType.integer, name: 'c0')],
        root: 0,
        captures: {'c0': ValueType.integer},
      ),
      result: BuilderResult.body(0, values: {'v0': 0}),
      bodyCount: 1,
    );
    final innerSlot = _slot(
      program: inner,
      captures: {
        'c0': const rfw.WidgetBuilderArgReference('frame', ['values', 'v0']),
      },
      body: const rfw.ConstructorCall('Body', {
        'onTap': rfw.EventHandler('pick', {
          'value': rfw.WidgetBuilderArgReference('frame', ['values', 'v0']),
        }),
      }),
    );
    expect(
      _gaps(_slot(body: rfw.ConstructorCall('Host', {'builder': innerSlot}))),
      isEmpty,
    );
  });

  test('every return selecting a shared body supplies its event frame values',
      () {
    const values = ValueProgram(
      nodes: [
        ValueNode('literal', ValueType.boolean, value: true),
        ValueNode('literal', ValueType.integer, value: 7),
      ],
      root: 0,
    );
    const program = BuilderProgram(
      values: values,
      result: BuilderResult.branch(
        0,
        BuilderResult.body(0, values: {'v0': 1}),
        BuilderResult.body(0),
      ),
      bodyCount: 1,
    );
    final slot = _slot(
      program: program,
      body: const rfw.ConstructorCall('Body', {
        'onTap': rfw.EventHandler('pick', {
          'value': rfw.WidgetBuilderArgReference('frame', ['values', 'v0']),
        }),
      }),
    );
    expect(
      _gaps(slot).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
  });
}
