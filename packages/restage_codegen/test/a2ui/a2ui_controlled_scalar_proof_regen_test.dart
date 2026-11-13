import 'dart:io';

import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _fixtureUri =
    'package:controlled_scalar_fixture/controlled_scalar_fixture.dart';
const _fixtureImport = 'controlled_scalar_fixture.dart';
const _generatedPath =
    '../restage_a2ui/test/generated/controlled_scalar_state_machine_test.dart';

PropertyEntry _familyProperty(
  String name,
  PropertyType type, {
  bool required = true,
  String? enumType,
  CatalogValueShape? valueShape,
  DefaultValueSource? defaultSource,
}) => PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: name,
  type: type,
  description: '',
  required: required,
  enumType: enumType,
  valueShape: valueShape,
  defaultSource: defaultSource,
);

Catalog _catalog() => catalogWith([
  entry(
    name: 'ControlledInt',
    flutterType: '$_fixtureUri#ControlledIntFixture',
    properties: [
      prop('value', PropertyType.integer, required: true),
      prop('onChanged', PropertyType.event, required: true),
    ],
  ),
  entry(
    name: 'ControlledIntPair',
    flutterType: '$_fixtureUri#ControlledIntPairFixture',
    properties: [
      prop('first', PropertyType.integer, required: true),
      prop('second', PropertyType.integer, required: true),
      prop('onFirst', PropertyType.event, required: true),
      prop('onSecond', PropertyType.event, required: true),
    ],
  ),
  entry(
    name: 'ControlledLeafFamilies',
    flutterType: '$_fixtureUri#ControlledLeafFamiliesFixture',
    properties: [
      _familyProperty('enabled', PropertyType.boolean),
      _familyProperty('label', PropertyType.string),
      _familyProperty(
        'choice',
        PropertyType.enumValue,
        enumType: 'ControlledChoice',
        valueShape: const EnumShape(
          propertyType: PropertyType.enumValue,
          enumRef: DartTypeRef(
            libraryUri: _fixtureUri,
            symbolName: 'ControlledChoice',
          ),
        ),
      ),
      for (final name in const [
        'strings',
        'integers',
        'doubles',
        'numbers',
        'booleans',
        'maybeNumbers',
      ])
        _familyProperty(name, PropertyType.structured),
      _familyProperty(
        'maybeIntegers',
        PropertyType.structured,
        required: false,
      ),
      _familyProperty(
        'fallbackIntegers',
        PropertyType.structured,
        required: false,
        defaultSource: const LiteralDefault(<int>[7, 8]),
      ),
      for (final name in const [
        'onEnabled',
        'onLabel',
        'onChoice',
        'onStrings',
        'onIntegers',
        'onDoubles',
        'onNumbers',
        'onBooleans',
        'onMaybeIntegers',
        'onMaybeNumbers',
        'onFallbackIntegers',
      ])
        prop(name, PropertyType.event, required: true),
    ],
  ),
  entry(
    name: 'ControlledScalarHost',
    flutterType: '$_fixtureUri#ControlledScalarHostFixture',
    properties: [prop('child', PropertyType.widget, required: true)],
  ),
]);

Catalog _ordinaryEnumCatalog() => catalogWith([
  entry(
    name: 'OrdinaryEnum',
    flutterType: '$_fixtureUri#ControlledLeafFamiliesFixture',
    properties: [
      _familyProperty(
        'choice',
        PropertyType.enumValue,
        enumType: 'ControlledChoice',
        valueShape: const EnumShape(
          propertyType: PropertyType.enumValue,
          enumRef: DartTypeRef(
            libraryUri: _fixtureUri,
            symbolName: 'ControlledChoice',
          ),
        ),
      ),
    ],
  ),
]);

final _ordinaryEnumShapes = <(String, String), A2uiSchemaNode>{
  ('OrdinaryEnum', 'choice'): EnumNode(
    members: const ['alpha', 'beta'],
    dartTypeName: 'ControlledChoice',
    libraryUri: _fixtureUri,
  ),
};

final _shapes = <(String, String), A2uiSchemaNode>{
  ('ControlledInt', 'value'): const ScalarNode(
    A2uiScalarType.integer,
    nullable: true,
  ),
  ('ControlledIntPair', 'first'): const ScalarNode(
    A2uiScalarType.integer,
    nullable: true,
  ),
  ('ControlledIntPair', 'second'): const ScalarNode(
    A2uiScalarType.integer,
    nullable: true,
  ),
  ('ControlledLeafFamilies', 'enabled'): const ScalarNode(
    A2uiScalarType.boolean,
  ),
  ('ControlledLeafFamilies', 'label'): const ScalarNode(A2uiScalarType.string),
  ('ControlledLeafFamilies', 'choice'): EnumNode(
    members: const ['alpha', 'beta'],
    dartTypeName: 'ControlledChoice',
    libraryUri: _fixtureUri,
  ),
  ('ControlledLeafFamilies', 'strings'): const ListNode(
    element: ScalarNode(A2uiScalarType.string),
  ),
  ('ControlledLeafFamilies', 'integers'): const ListNode(
    element: ScalarNode(A2uiScalarType.integer),
  ),
  ('ControlledLeafFamilies', 'doubles'): const ListNode(
    element: ScalarNode(A2uiScalarType.number),
  ),
  ('ControlledLeafFamilies', 'numbers'): const ListNode(
    element: ScalarNode(
      A2uiScalarType.number,
      preserveNumericRuntimeType: true,
    ),
  ),
  ('ControlledLeafFamilies', 'booleans'): const ListNode(
    element: ScalarNode(A2uiScalarType.boolean),
  ),
  ('ControlledLeafFamilies', 'maybeIntegers'): const ListNode(
    element: ScalarNode(A2uiScalarType.integer),
    nullable: true,
  ),
  ('ControlledLeafFamilies', 'maybeNumbers'): const ListNode(
    element: ScalarNode(
      A2uiScalarType.number,
      nullable: true,
      preserveNumericRuntimeType: true,
    ),
    nullable: true,
  ),
  ('ControlledLeafFamilies', 'fallbackIntegers'): const ListNode(
    element: ScalarNode(A2uiScalarType.integer),
    nullable: true,
  ),
};

const _events = <(String, String), A2uiCallbackSignature>{
  ('ControlledInt', 'onChanged'): A2uiCallbackWriteBack(
    A2uiScalarType.integer,
    nullable: true,
    isList: false,
  ),
  ('ControlledIntPair', 'onFirst'): A2uiCallbackWriteBack(
    A2uiScalarType.integer,
    nullable: true,
    isList: false,
  ),
  ('ControlledIntPair', 'onSecond'): A2uiCallbackWriteBack(
    A2uiScalarType.integer,
    nullable: true,
    isList: false,
  ),
  ('ControlledLeafFamilies', 'onEnabled'): A2uiCallbackWriteBack(
    A2uiScalarType.boolean,
    nullable: false,
    isList: false,
  ),
  ('ControlledLeafFamilies', 'onLabel'): A2uiCallbackWriteBack(
    A2uiScalarType.string,
    nullable: false,
    isList: false,
  ),
  ('ControlledLeafFamilies', 'onChoice'): A2uiCallbackWriteBack(
    A2uiScalarType.string,
    nullable: false,
    isList: false,
  ),
  ('ControlledLeafFamilies', 'onStrings'): A2uiCallbackWriteBack(
    A2uiScalarType.string,
    nullable: false,
    isList: true,
  ),
  ('ControlledLeafFamilies', 'onIntegers'): A2uiCallbackWriteBack(
    A2uiScalarType.integer,
    nullable: false,
    isList: true,
  ),
  ('ControlledLeafFamilies', 'onDoubles'): A2uiCallbackWriteBack(
    A2uiScalarType.number,
    nullable: false,
    isList: true,
  ),
  ('ControlledLeafFamilies', 'onNumbers'): A2uiCallbackWriteBack(
    A2uiScalarType.number,
    nullable: false,
    isList: true,
    preserveNumericRuntimeType: true,
  ),
  ('ControlledLeafFamilies', 'onBooleans'): A2uiCallbackWriteBack(
    A2uiScalarType.boolean,
    nullable: false,
    isList: true,
  ),
  ('ControlledLeafFamilies', 'onMaybeIntegers'): A2uiCallbackWriteBack(
    A2uiScalarType.integer,
    nullable: true,
    isList: true,
  ),
  ('ControlledLeafFamilies', 'onMaybeNumbers'): A2uiCallbackWriteBack(
    A2uiScalarType.number,
    nullable: true,
    isList: true,
    elementNullable: true,
    preserveNumericRuntimeType: true,
  ),
  ('ControlledLeafFamilies', 'onFallbackIntegers'): A2uiCallbackWriteBack(
    A2uiScalarType.integer,
    nullable: true,
    isList: true,
  ),
};

const _pairings = <(String, String), String>{
  ('ControlledIntPair', 'onFirst'): 'first',
  ('ControlledIntPair', 'onSecond'): 'second',
  ('ControlledLeafFamilies', 'onEnabled'): 'enabled',
  ('ControlledLeafFamilies', 'onLabel'): 'label',
  ('ControlledLeafFamilies', 'onChoice'): 'choice',
  ('ControlledLeafFamilies', 'onStrings'): 'strings',
  ('ControlledLeafFamilies', 'onIntegers'): 'integers',
  ('ControlledLeafFamilies', 'onDoubles'): 'doubles',
  ('ControlledLeafFamilies', 'onNumbers'): 'numbers',
  ('ControlledLeafFamilies', 'onBooleans'): 'booleans',
  ('ControlledLeafFamilies', 'onMaybeIntegers'): 'maybeIntegers',
  ('ControlledLeafFamilies', 'onMaybeNumbers'): 'maybeNumbers',
  ('ControlledLeafFamilies', 'onFallbackIntegers'): 'fallbackIntegers',
};

String _emittedTestSource() {
  final catalog = _catalog();
  final registration = emitA2uiCatalog(
    catalog,
    richShapes: _shapes,
    eventSeam: _events,
    pairingSeam: _pairings,
  );
  final alternateRegistration = emitA2uiCatalog(
    catalog,
    richShapes: _shapes,
    eventSeam: _events,
    pairingSeam: _pairings,
    usageByWidget: const {
      'ControlledInt': 'Alternate exact catalog identity for semantic proof.',
    },
  );
  final emitted = emitA2uiCatalogDart(
    catalog,
    registration: registration,
    richShapes: _shapes,
    eventSeam: _events,
    pairingSeam: _pairings,
  );
  final normalized = formatGeneratedDart(
    emitted.replaceAll(_fixtureUri, _fixtureImport),
  ).trimRight();
  final withMaterialImport = normalized.replaceFirst(
    "import 'package:flutter/widgets.dart';",
    "import 'package:flutter/material.dart';",
  );
  final withTestImports = withMaterialImport.replaceFirst(
    "import 'package:a2ui_core/a2ui_core.dart';",
    "import 'package:a2ui_core/a2ui_core.dart';\nimport "
        "'package:flutter_test/flutter_test.dart';",
  );
  final appendix = _pass1TestAppendix.replaceFirst(
    '__ALTERNATE_EXACT_CATALOG_ID__',
    alternateRegistration.documentId,
  );
  final formatted = formatGeneratedDart('$withTestImports\n\n$appendix');
  return '${formatted.trimRight()}\n';
}

void main() {
  test('controlled enum schema admits literal, path, and call while ordinary '
      'enum stays literal-only', () {
    final controlledRegistration = emitA2uiCatalog(
      _catalog(),
      richShapes: _shapes,
      eventSeam: _events,
      pairingSeam: _pairings,
    );
    final controlledProperties =
        controlledRegistration.components
                .singleWhere(
                  (component) => component.name == 'ControlledLeafFamilies',
                )
                .dataSchema['properties']!
            as Map<String, Object?>;
    expect(controlledProperties['props_choice'], {
      'oneOf': <Object?>[
        {
          'type': 'string',
          'enum': <Object?>['alpha', 'beta'],
        },
        {r'$ref': r'common_types.json#/$defs/DataBinding'},
        {r'$ref': r'common_types.json#/$defs/FunctionCall'},
      ],
    });
    final controlledSource = emitA2uiCatalogDart(
      _catalog(),
      registration: controlledRegistration,
      richShapes: _shapes,
      eventSeam: _events,
      pairingSeam: _pairings,
    );
    final compactControlledSource = controlledSource.replaceAll(
      RegExp(r'\s+'),
      '',
    );
    expect(
      compactControlledSource,
      contains(
        [
          "'props_choice':S.combined(oneOf:[S.string(enumValues:",
          "<Object?>['alpha','beta'])",
        ].join(),
      ),
    );

    final ordinaryCatalog = _ordinaryEnumCatalog();
    final ordinaryRegistration = emitA2uiCatalog(
      ordinaryCatalog,
      richShapes: _ordinaryEnumShapes,
    );
    final ordinaryProperties =
        ordinaryRegistration.components.single.dataSchema['properties']!
            as Map<String, Object?>;
    expect(ordinaryProperties['props_choice'], {
      'type': 'string',
      'enum': <Object?>['alpha', 'beta'],
    });
    final ordinarySource = emitA2uiCatalogDart(
      ordinaryCatalog,
      registration: ordinaryRegistration,
      richShapes: _ordinaryEnumShapes,
    );
    final compactOrdinarySource = ordinarySource.replaceAll(RegExp(r'\s+'), '');
    expect(
      compactOrdinarySource,
      contains(
        "'props_choice':S.string(enumValues:<Object?>['alpha','beta'])",
      ),
    );
    expect(
      compactOrdinarySource,
      isNot(contains("'props_choice':S.combined(oneOf:")),
    );
  });

  test('the controlled-scalar runtime proof is writer-owned and current', () {
    final source = _emittedTestSource();
    final file = File(_generatedPath);
    if (Platform.environment['REGEN_A2UI_CONTROLLED_SCALAR'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(source);
    }
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'run with REGEN_A2UI_CONTROLLED_SCALAR=1 to create '
          '$_generatedPath',
    );
    expect(
      file.readAsStringSync(),
      source,
      reason: 'the controlled-scalar runtime proof has emitter drift',
    );
  });
}

const _pass1TestAppendix = r'''
final class _SignalFunction extends FunctionImplementation {
  _SignalFunction(this.current) : super(name: 'currentValue', argumentSchema: S.object());
  final Signal<Object?> current;
  int executions = 0;
  @override
  Object? execute(Map<String, dynamic> args, DataContext context, [CancellationSignal? cancellationSignal]) { executions++; return current; }
}

DataContext _context(DataModel model, {String path = '/', Signal<Object?>? value}) => DataContext(model, (_, _, _) => value?.value, path, protocolVersion: A2uiProtocolVersion.v1_0);

final class _DirectConfiguration {
  const _DirectConfiguration({required this.context, this.source = 7, this.present = true, this.surface = 's', this.catalog = restageA2uiCatalogId, this.component = 'root', this.field = 'value', this.selfPath = '/local/value'});
  final DataContext context;
  final Object? source;
  final bool present;
  final String surface, catalog, component, field, selfPath;
}

// Stands in for the upstream node's resolved props; tests set the resolved value.
Signal<NodeProps> _resolved(Object? value) => signal<NodeProps>({'props_value': value});

Future<void> _pumpDirect(WidgetTester tester, ValueNotifier<_DirectConfiguration> configuration, Signal<NodeProps> resolved, {void Function(ValueChanged<Object?>)? capture}) async {
  await tester.pumpWidget(MaterialApp(home: ValueListenableBuilder<_DirectConfiguration>(
    valueListenable: configuration,
    builder: (context, c, _) => _RestageA2uiControlledValue(
      dataContext: c.context, resolvedProps: resolved, propertyName: 'props_value',
      source: c.source, sourcePresent: c.present,
      surfaceId: c.surface, catalogId: c.catalog, componentId: c.component,
      field: c.field, selfPath: c.selfPath,
      builder: (context, raw, present, kind, write) {
        capture?.call(write);
        return Text('${present ? raw ?? 'null' : 'absent'}:${kind.name}');
      },
    ),
  )));
}

// A template parent from another catalog; generated components take id lists only.
final _rowsCatalog = CatalogImplementation(id: 'test:rows', protocolVersion: A2uiProtocolVersion.v1_0, components: [
  ComponentImplementation(name: 'Rows', schema: S.object(properties: {'children': CommonSchemas.childList}), builder: (context, node, props, buildChild) {
    final children = node.props.peek()['children'];
    return Column(children: [if (children is List) for (final child in children) if (child is ComponentNode<ComponentImplementation>) buildChild(child)]);
  }),
]);

MessageProcessor<ComponentImplementation> _processor({List<FunctionImplementation> functions = const [], ValidationConfig validationConfig = const ValidationConfig(allowOrphanComponents: true)}) {
  final catalog = CatalogImplementation(id: restageA2uiCatalogId, components: buildRestageCatalogItems(), functions: functions, protocolVersion: A2uiProtocolVersion.v1_0);
  final processor = MessageProcessor<ComponentImplementation>(catalogs: [catalog, _rowsCatalog], defaultVersion: A2uiProtocolVersion.v1_0, validationConfig: validationConfig);
  addTearDown(processor.dispose);
  return processor;
}

Map<String, Object?> _component(String type, Map<String, Object?> values, {String id = 'root'}) => {
  'id': id, 'component': type,
  for (final entry in values.entries) 'props_${entry.key}': entry.value,
};

Future<SurfaceModel<ComponentImplementation>> _mount(WidgetTester tester, MessageProcessor<ComponentImplementation> processor, List<Map<String, Object?>> components, {Map<String, Object?> data = const {}}) async {
  processor.processMessages({'version': '1.0', 'createSurface': {'surfaceId': 's', 'catalogId': restageA2uiCatalogId, 'dataModel': data, 'components': components}});
  final surface = processor.model.getSurface('s')!;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: A2uiSurface(surface: surface))));
  return surface;
}

void _update(MessageProcessor<ComponentImplementation> processor, List<Map<String, Object?>> components) => processor.processMessages({'version': '1.0', 'updateComponents': {'surfaceId': 's', 'components': components}});

Map<String, Object?> _families(Object? Function(String, Object?) source) => {
  for (final entry in <String, Object?>{
    'enabled': true, 'label': 'remote', 'choice': 'alpha',
    'strings': <String>['a'], 'integers': <int>[1], 'doubles': <double>[1.5],
    'numbers': <num>[1, 1.5], 'booleans': <bool>[true], 'maybeNumbers': <num?>[1, null, 1.5],
    'maybeIntegers': <int>[1],
  }.entries) entry.key: source(entry.key, entry.value),
};

void main() {
  testWidgets('literal presence, null, numeric representation and overrides remain distinct', (tester) async {
    final model = DataModel(); addTearDown(model.dispose);
    final context = _context(model);
    final c = ValueNotifier(_DirectConfiguration(context: context, source: <num>[1])); addTearDown(c.dispose);
    final resolved = _resolved(<num>[1]);
    late ValueChanged<Object?> write;
    await _pumpDirect(tester, c, resolved, capture: (value) => write = value);
    expect(find.text('[1]:literal'), findsOneWidget);
    resolved.value = {'props_value': <num>[1.0]};
    c.value = _DirectConfiguration(context: context, source: <num>[1.0]); await tester.pump();
    expect(find.text('[1.0]:literal'), findsOneWidget);
    resolved.value = {};
    c.value = _DirectConfiguration(context: context, source: null, present: false); await tester.pump();
    expect(find.text('absent:literal'), findsOneWidget);
    resolved.value = {'props_value': null};
    c.value = _DirectConfiguration(context: context, source: null); await tester.pump();
    expect(find.text('null:literal'), findsOneWidget);
    write(null); await tester.pump();
    resolved.value = {'props_value': 9};
    c.value = _DirectConfiguration(context: context, source: 9); await tester.pump();
    expect(find.text('null:localOverride'), findsOneWidget);
    write(41); await tester.pump();
    expect(model.get('/local/value'), 41);
    expect(find.text('41:localOverride'), findsOneWidget);
  });

  testWidgets('each semantic identity axis independently resets an override', (tester) async {
    final first = DataModel(); final second = DataModel();
    addTearDown(first.dispose); addTearDown(second.dispose);
    final context = _context(first);
    final c = ValueNotifier(_DirectConfiguration(context: context)); addTearDown(c.dispose);
    late ValueChanged<Object?> write;
    await _pumpDirect(tester, c, _resolved(7), capture: (value) => write = value);
    write(41); await tester.pump();
    c.value = _DirectConfiguration(context: _context(first)); await tester.pump();
    expect(find.text('41:localOverride'), findsOneWidget);
    for (final changed in [
      _DirectConfiguration(context: context, surface: 'other'),
      _DirectConfiguration(context: context, catalog: '__ALTERNATE_EXACT_CATALOG_ID__'),
      _DirectConfiguration(context: _context(second)),
      _DirectConfiguration(context: _context(first, path: '/nested')),
      _DirectConfiguration(context: context, component: 'other'),
      _DirectConfiguration(context: context, field: 'other'),
      _DirectConfiguration(context: context, selfPath: '/other'),
    ]) {
      c.value = _DirectConfiguration(context: context); await tester.pump();
      write(41); await tester.pump();
      c.value = changed; await tester.pump();
      expect(find.text('7:literal'), findsOneWidget);
    }
  });

  testWidgets('path write-through, rebinding, kind transitions and retained writers after disposal', (tester) async {
    final model = DataModel(); addTearDown(model.dispose);
    model.set('/a', 1); model.set('/b', 2);
    final context = _context(model);
    final c = ValueNotifier(_DirectConfiguration(context: context, source: const {'@path': '/a'})); addTearDown(c.dispose);
    final resolved = _resolved(1);
    late ValueChanged<Object?> write;
    await _pumpDirect(tester, c, resolved, capture: (value) => write = value);
    write(41); await tester.pump(); expect(model.get('/a'), 41);
    resolved.value = {'props_value': 2};
    c.value = _DirectConfiguration(context: context, source: const {'@path': '/b'}); await tester.pump();
    expect(find.text('2:path'), findsOneWidget);
    resolved.value = {'props_value': 12}; await tester.pump(); expect(find.text('12:path'), findsOneWidget);
    write(13); await tester.pump(); expect(model.get('/b'), 13); expect(model.get('/a'), 41);
    await tester.pumpWidget(const SizedBox.shrink()); write(55); expect(model.get('/b'), 13);
    for (final source in [7, const {'@call': 'value'}]) {
      c.value = _DirectConfiguration(context: context, source: source);
      await _pumpDirect(tester, c, _resolved(7), capture: (value) => write = value);
      await tester.pumpWidget(const SizedBox.shrink()); write(55);
      expect(model.get('/local/value'), isNull);
    }
  });

  testWidgets('call equality, catalog and argument rebinding, override and disposal follow resolved props', (tester) async {
    final model = DataModel(); addTearDown(model.dispose);
    final context = _context(model);
    final c = ValueNotifier(_DirectConfiguration(context: context, source: const {'@call': 'value', 'args': {'path': 'business', 'call': 'business'}})); addTearDown(c.dispose);
    final resolved = _resolved(7);
    late ValueChanged<Object?> write;
    await _pumpDirect(tester, c, resolved, capture: (v) => write = v);
    expect(find.text('7:call'), findsOneWidget);
    resolved.value = {'props_value': 8}; await tester.pump(); expect(find.text('8:call'), findsOneWidget);
    write(41); await tester.pump(); resolved.value = {'props_value': 9}; await tester.pump(); expect(find.text('41:localOverride'), findsOneWidget);
    c.value = _DirectConfiguration(context: context, source: const {'@call': 'value', 'args': {'call': 'business', 'path': 'business'}}); await tester.pump();
    expect(find.text('41:localOverride'), findsOneWidget);
    c.value = _DirectConfiguration(context: context, source: const {'@call': 'value', 'args': {'path': 'changed'}}); await tester.pump();
    expect(find.text('9:call'), findsOneWidget);
    write(41); await tester.pump();
    c.value = _DirectConfiguration(context: context, source: const {'@call': 'value', 'catalogId': 'other', 'args': {'path': 'changed'}}); await tester.pump();
    expect(find.text('9:call'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); resolved.value = {'props_value': 10}; await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('generated literal, path and call controls render and preserve local overrides', (tester) async {
    for (final source in [7, const {'@path': '/value'}, const {'@call': 'currentValue'}]) {
      final signalValue = signal<Object?>(7);
      final function = _SignalFunction(signalValue);
      final processor = _processor(functions: [function]);
      final surface = await _mount(tester, processor, [_component('ControlledInt', {'value': source})], data: {'value': 7});
      expect(find.text('controlled-value:7'), findsOneWidget);
      expect(function.executions, source is Map && source.containsKey('@call') ? 1 : 0, reason: 'The generated helper reuses upstream resolved properties.');
      await tester.tap(find.byKey(const ValueKey('controlled-write-41'))); await tester.pump();
      expect(find.text('controlled-value:41'), findsOneWidget);
      if (source is Map && source.containsKey('@path')) {
        expect(surface.dataModel.get('/value'), 41);
        surface.dataModel.set('/value', 12); await tester.pump();
        expect(find.text('controlled-value:12'), findsOneWidget);
      } else {
        expect(surface.dataModel.get('/restage_root/props_value'), 41);
        signalValue.value = 13;
        _update(processor, [_component('ControlledInt', {'value': source is Map ? source : 13})]); await tester.pump();
        expect(find.text('controlled-value:41'), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('controlled-write-null'))); await tester.pump();
      expect(find.text('controlled-value:null'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('valid component IDs have safe injective literal and call storage', (tester) async {
    const storageById = {
      'constructor': 'restage_constructor',
      'prototype': 'restage_prototype',
      '__proto__': 'restage___proto__',
      'restage_constructor': 'restage_restage_constructor',
      'café': 'restage_caf%C3%A9',
    };
    expect(storageById.values.toSet(), hasLength(storageById.length));
    for (final entry in storageById.entries) {
      for (final source in [7, const {'@call': 'currentValue'}]) {
        final value = signal<Object?>(7);
        final processor = _processor(functions: [_SignalFunction(value)], validationConfig: ValidationConfig.strict);
        final surface = await _mount(tester, processor, [
          _component('ControlledScalarHost', {'child': entry.key}),
          _component('ControlledInt', {'value': source}, id: entry.key),
        ]);
        expect(find.text('controlled-value:7'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('controlled-write-41')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('controlled-value:41'), findsOneWidget);
        expect(surface.dataModel.get('/${entry.value}/props_value'), 41);
        value.value = 12; await tester.pump();
        expect(find.text('controlled-value:41'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('all scalar/list families preserve defaults, enum writes and independent overrides', (tester) async {
    for (final pathBound in [false, true]) {
      final processor = _processor();
      final values = _families((_, value) => value);
      final sources = _families((key, value) => pathBound ? {'@path': '/$key'} : value);
      final surface = await _mount(tester, processor, [_component('ControlledLeafFamilies', sources)], data: values);
      expect(find.text('families-choice:alpha'), findsOneWidget);
      expect(find.text('families-fallback-integers:7,8'), findsOneWidget);
      expect(find.text('families-number-types:int,double'), findsOneWidget);
      final fixture = tester.widget<p0.ControlledLeafFamiliesFixture>(find.byType(p0.ControlledLeafFamiliesFixture));
      fixture.onEnabled(false); fixture.onLabel('local'); fixture.onChoice(p0.ControlledChoice.beta);
      fixture.onStrings(['local']); fixture.onIntegers([41]); fixture.onDoubles([4.5]); fixture.onNumbers([4, 4.5]); fixture.onBooleans([false]); fixture.onMaybeNumbers([4, null, 4.5]); fixture.onMaybeIntegers(null); fixture.onFallbackIntegers([9]);
      await tester.pump();
      for (final text in ['families-enabled:false', 'families-label:local', 'families-choice:beta', 'families-strings:local', 'families-integers:41', 'families-doubles:4.5', 'families-numbers:4,4.5', 'families-booleans:false', 'families-maybe-numbers:4,null,4.5', 'families-maybe-integers:null', 'families-fallback-integers:9']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(surface.dataModel.get(pathBound ? '/choice' : '/restage_root/props_choice'), 'beta');
      _update(processor, [_component('ControlledLeafFamilies', sources)]); await tester.pump();
      expect(find.text('families-label:local'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a controlled binding that resolves to nothing uses the constructor default', (tester) async {
    final processor = _processor();
    final values = _families((_, value) => value);
    await _mount(tester, processor, [_component('ControlledLeafFamilies', {...values, 'fallbackIntegers': {'@path': '/missing'}})], data: values);
    expect(find.text('families-fallback-integers:7,8'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final literalNull = _processor();
    await _mount(tester, literalNull, [_component('ControlledLeafFamilies', {...values, 'fallbackIntegers': null})], data: values);
    expect(find.text('families-fallback-integers:null'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('clearing a path-bound control removes the value and shows the default', (tester) async {
    final processor = _processor();
    final values = {..._families((_, value) => value), 'fallback': <int>[1, 2]};
    final surface = await _mount(tester, processor, [_component('ControlledLeafFamilies', {..._families((_, value) => value), 'fallbackIntegers': {'@path': '/fallback'}})], data: values);
    expect(find.text('families-fallback-integers:1,2'), findsOneWidget);
    tester.widget<p0.ControlledLeafFamiliesFixture>(find.byType(p0.ControlledLeafFamiliesFixture)).onFallbackIntegers(null);
    await tester.pump();
    expect(surface.dataModel.get('/fallback'), isNull);
    expect(find.text('families-fallback-integers:7,8'), findsOneWidget);
    surface.dataModel.set('/fallback', <int>[3]); await tester.pump();
    expect(find.text('families-fallback-integers:3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('literal write-back in a template keeps one slot per row', (tester) async {
    final processor = _processor();
    final surface = await _mount(tester, processor, [
      {'id': 'root', 'component': 'Rows', 'catalogId': 'test:rows', 'children': {'componentId': 'cell', 'path': '/rows'}},
      _component('ControlledInt', {'value': 7}, id: 'cell'),
    ], data: {'rows': [<String, Object?>{}, <String, Object?>{}]});
    expect(find.text('controlled-value:7'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('controlled-write-41')).first); await tester.pump();
    expect(surface.dataModel.get('/restage_cell/context_%2Frows%2F0/props_value'), 41);
    expect(surface.dataModel.get('/restage_cell/context_%2Frows%2F1/props_value'), isNull);
    expect(find.text('controlled-value:41'), findsOneWidget);
    expect(find.text('controlled-value:7'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('two fields do not cross-talk and changing the child ID resets its override', (tester) async {
    final processor = _processor();
    await _mount(tester, processor, [_component('ControlledIntPair', {'first': 1, 'second': 2})]);
    await tester.tap(find.byKey(const ValueKey('pair-write-first'))); await tester.pump();
    _update(processor, [_component('ControlledIntPair', {'first': 3, 'second': 4})]); await tester.pump();
    expect(find.text('pair-first:11'), findsOneWidget); expect(find.text('pair-second:4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pair-write-second'))); await tester.pump();
    expect(find.text('pair-first:11'), findsOneWidget); expect(find.text('pair-second:22'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final next = _processor();
    await _mount(tester, next, [_component('ControlledScalarHost', {'child': 'a'}), _component('ControlledInt', {'value': 7}, id: 'a')]);
    await tester.tap(find.byKey(const ValueKey('controlled-write-41'))); await tester.pump();
    _update(next, [_component('ControlledInt', {'value': 8}, id: 'a')]); await tester.pump();
    expect(find.text('controlled-value:41'), findsOneWidget);
    _update(next, [_component('ControlledScalarHost', {'child': 'b'}), _component('ControlledInt', {'value': 9}, id: 'b')]); await tester.pump();
    expect(find.text('controlled-value:9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
''';
