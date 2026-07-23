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
}) =>
    PropertyEntry(
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
            _familyProperty(name, PropertyType.stringList),
          _familyProperty(
            'maybeIntegers',
            PropertyType.stringList,
            required: false,
          ),
          _familyProperty(
            'fallbackIntegers',
            PropertyType.stringList,
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
  ('ControlledInt', 'value'):
      const ScalarNode(A2uiScalarType.integer, nullable: true),
  ('ControlledIntPair', 'first'):
      const ScalarNode(A2uiScalarType.integer, nullable: true),
  ('ControlledIntPair', 'second'):
      const ScalarNode(A2uiScalarType.integer, nullable: true),
  ('ControlledLeafFamilies', 'enabled'):
      const ScalarNode(A2uiScalarType.boolean),
  ('ControlledLeafFamilies', 'label'): const ScalarNode(A2uiScalarType.string),
  ('ControlledLeafFamilies', 'choice'): EnumNode(
    members: const ['alpha', 'beta'],
    dartTypeName: 'ControlledChoice',
    libraryUri: _fixtureUri,
  ),
  ('ControlledLeafFamilies', 'strings'):
      const ListNode(element: ScalarNode(A2uiScalarType.string)),
  ('ControlledLeafFamilies', 'integers'):
      const ListNode(element: ScalarNode(A2uiScalarType.integer)),
  ('ControlledLeafFamilies', 'doubles'):
      const ListNode(element: ScalarNode(A2uiScalarType.number)),
  ('ControlledLeafFamilies', 'numbers'): const ListNode(
    element: ScalarNode(
      A2uiScalarType.number,
      preserveNumericRuntimeType: true,
    ),
  ),
  ('ControlledLeafFamilies', 'booleans'):
      const ListNode(element: ScalarNode(A2uiScalarType.boolean)),
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
    "import 'package:genui/genui.dart';",
    "import 'package:a2ui_core/a2ui_core.dart'\n"
        '    show CreateSurfaceMessage, UpdateComponentsMessage, '
        'UpdateDataModelMessage;\n'
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:genui/genui.dart';",
  );
  final appendix = _pass1TestAppendix.replaceFirst(
    '__ALTERNATE_EXACT_CATALOG_ID__',
    alternateRegistration.documentId,
  );
  return '$withTestImports\n\n${appendix.trimRight()}\n';
}

void main() {
  test(
      'controlled enum schema admits literal, path, and call while ordinary '
      'enum stays literal-only', () {
    final controlledRegistration = emitA2uiCatalog(
      _catalog(),
      richShapes: _shapes,
      eventSeam: _events,
      pairingSeam: _pairings,
    );
    final controlledProperties = controlledRegistration.components
        .singleWhere((component) => component.name == 'ControlledLeafFamilies')
        .dataSchema['properties']! as Map<String, Object?>;
    expect(controlledProperties['choice'], {
      'oneOf': <Object?>[
        {
          'type': 'string',
          'enum': <Object?>['alpha', 'beta'],
        },
        {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': const ['path'],
        },
        {
          'type': 'object',
          'properties': {
            'call': {'type': 'string'},
            'args': {'type': 'object', 'additionalProperties': true},
          },
          'required': const ['call'],
        },
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
        "'choice':S.combined(oneOf:[S.string(enumValues:"
        "<Object?>['alpha','beta'])",
      ),
    );

    final ordinaryCatalog = _ordinaryEnumCatalog();
    final ordinaryRegistration = emitA2uiCatalog(
      ordinaryCatalog,
      richShapes: _ordinaryEnumShapes,
    );
    final ordinaryProperties = ordinaryRegistration
        .components.single.dataSchema['properties']! as Map<String, Object?>;
    expect(ordinaryProperties['choice'], {
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
        "'choice':S.string(enumValues:<Object?>['alpha','beta'])",
      ),
    );
    expect(
      compactOrdinarySource,
      isNot(contains("'choice':S.combined(oneOf:")),
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
      reason: 'run with REGEN_A2UI_CONTROLLED_SCALAR=1 to create '
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
const _alternateExactCatalogId = '__ALTERNATE_EXACT_CATALOG_ID__';

final class _ControlledIntFunction implements ClientFunction {
  _ControlledIntFunction(this.controller);

  final StreamController<Object?> controller;
  int executeCount = 0;

  @override
  String get name => 'currentInt';

  @override
  String get description => 'Emits the current integer.';

  @override
  Schema get argumentSchema => S.object(properties: const {});

  @override
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.number;

  @override
  Stream<Object?> execute(JsonMap args, ExecutionContext context) {
    executeCount++;
    return controller.stream;
  }
}

final class _ControlledValueFunction implements ClientFunction {
  _ControlledValueFunction(this.name, this.controller);

  @override
  final String name;
  final StreamController<Object?> controller;

  @override
  String get description => 'Emits a controlled proof value.';

  @override
  Schema get argumentSchema => S.object(properties: const {});

  @override
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.any;

  @override
  Stream<Object?> execute(JsonMap args, ExecutionContext context) =>
      controller.stream;
}

final class _LateAfterCancelClientFunction implements ClientFunction {
  _LateAfterCancelClientFunction(
    this.name,
    this.events, {
    this.cancelFuture,
  });

  @override
  final String name;
  final List<String> events;
  final Future<void>? cancelFuture;
  final List<_LateAfterCancelStream> executions = [];

  @override
  String get description => 'Delivers deterministic events after cancel.';

  @override
  Schema get argumentSchema => S.object(additionalProperties: true);

  @override
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.number;

  @override
  Stream<Object?> execute(JsonMap args, ExecutionContext context) {
    final sequence = executions.length + 1;
    events.add('execute:$name:$sequence');
    final stream = _LateAfterCancelStream(
      onCancel: () => events.add('cancel:$name:$sequence'),
      cancelFuture: cancelFuture,
    );
    executions.add(stream);
    return stream;
  }
}

final class _LateAfterCancelStream extends Stream<Object?> {
  _LateAfterCancelStream({
    required this.onCancel,
    this.cancelFuture,
  });

  final VoidCallback onCancel;
  final Future<void>? cancelFuture;
  void Function(Object?)? _handleData;
  var _isPaused = false;
  var _isCancelled = false;
  var cancelCount = 0;

  void emitLate(Object? value) => _handleData?.call(value);

  @override
  StreamSubscription<Object?> listen(
    void Function(Object?)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _handleData = onData;
    return _LateAfterCancelSubscription(this);
  }
}

final class _LateAfterCancelSubscription
    implements StreamSubscription<Object?> {
  _LateAfterCancelSubscription(this.stream);

  final _LateAfterCancelStream stream;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;

  @override
  Future<void> cancel() {
    if (!stream._isCancelled) {
      stream._isCancelled = true;
      stream.cancelCount++;
      stream.onCancel();
    }
    return stream.cancelFuture ?? Future<void>.value();
  }

  @override
  bool get isPaused => stream._isPaused;

  @override
  void onData(void Function(Object?)? handleData) {
    stream._handleData = handleData;
  }

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    stream._isPaused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() {
    stream._isPaused = false;
  }
}

final class _ItemConfiguration {
  const _ItemConfiguration({
    required this.type,
    required this.data,
    required this.id,
    required this.surfaceId,
    required this.dataContext,
  });

  final String type;
  final Map<String, Object?> data;
  final String id;
  final String surfaceId;
  final DataContext dataContext;
}

CatalogItem? _itemNamed(List<CatalogItem> items, String type) {
  for (final item in items) {
    if (item.name == type) return item;
  }
  return null;
}

Widget _buildConfiguredItem(
  BuildContext context,
  Catalog catalog,
  List<CatalogItem> items,
  _ItemConfiguration configuration,
) =>
    catalog.buildWidget(
      CatalogItemContext(
        data: configuration.data,
        id: configuration.id,
        type: configuration.type,
        buildChild: (id, [dataContext]) => const SizedBox.shrink(),
        dispatchEvent: (_) {},
        buildContext: context,
        dataContext: configuration.dataContext,
        getComponent: (_) => null,
        getCatalogItem: (type) => _itemNamed(items, type),
        surfaceId: configuration.surfaceId,
        reportError: (error, stack) => Error.throwWithStackTrace(
          error,
          stack ?? StackTrace.current,
        ),
      ),
    );

Future<void> _pumpConfiguredItem(
  WidgetTester tester,
  ValueNotifier<_ItemConfiguration> configuration,
) async {
  final items = buildRestageCatalogItems();
  final catalog = Catalog(items, catalogId: restageA2uiCatalogId);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ValueListenableBuilder<_ItemConfiguration>(
          valueListenable: configuration,
          builder: (context, value, _) =>
              _buildConfiguredItem(context, catalog, items, value),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpTwoConfiguredItems(
  WidgetTester tester,
  ValueNotifier<List<_ItemConfiguration>> configurations,
) async {
  final items = buildRestageCatalogItems();
  final catalog = Catalog(items, catalogId: restageA2uiCatalogId);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) =>
            ValueListenableBuilder<List<_ItemConfiguration>>(
          valueListenable: configurations,
          builder: (context, values, _) => Column(
            children: [
              for (final value in values)
                _buildConfiguredItem(context, catalog, items, value),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Map<String, Object?> _controlledFamiliesComponent(Object choice) => {
      'id': 'root',
      'component': 'ControlledLeafFamilies',
      'enabled': true,
      'label': 'surface',
      'choice': choice,
      'strings': const <String>[],
      'integers': const <int>[],
      'doubles': const <double>[],
      'numbers': const <num>[],
      'booleans': const <bool>[],
      'maybeNumbers': const <num?>[],
    };

final class _DirectConfiguration {
  const _DirectConfiguration({
    required this.source,
    required this.sourcePresent,
    required this.dataContext,
    required this.surfaceId,
    required this.catalogId,
    required this.componentId,
    required this.field,
    required this.selfPath,
    this.reportError,
  });

  final Object? source;
  final bool sourcePresent;
  final DataContext dataContext;
  final String surfaceId;
  final String catalogId;
  final String componentId;
  final String field;
  final String selfPath;
  final void Function(Object error, StackTrace? stack)? reportError;
}

_DirectConfiguration _directConfiguration(
  DataContext dataContext, {
  Object? source = 7,
  bool sourcePresent = true,
  String surfaceId = 'surface-a',
  String catalogId = restageA2uiCatalogId,
  String componentId = 'root',
  String field = 'value',
  String? selfPath,
  void Function(Object error, StackTrace? stack)? reportError,
}) =>
    _DirectConfiguration(
      source: source,
      sourcePresent: sourcePresent,
      dataContext: dataContext,
      surfaceId: surfaceId,
      catalogId: catalogId,
      componentId: componentId,
      field: field,
      selfPath: selfPath ?? '$componentId.$field',
      reportError: reportError,
    );

Future<void> _pumpDirectControlled(
  WidgetTester tester,
  ValueNotifier<_DirectConfiguration> configuration, {
  void Function(ValueChanged<Object?> writer)? captureWriter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ValueListenableBuilder<_DirectConfiguration>(
        valueListenable: configuration,
        builder: (context, value, _) => _RestageA2uiControlledValue(
          dataContext: value.dataContext,
          source: value.source,
          sourcePresent: value.sourcePresent,
          surfaceId: value.surfaceId,
          catalogId: value.catalogId,
          componentId: value.componentId,
          field: value.field,
          selfPath: value.selfPath,
          reportError: value.reportError ??
              (error, stack) => Error.throwWithStackTrace(
                    error,
                    stack ?? StackTrace.current,
                  ),
          builder: (context, raw, present, kind, write) {
            captureWriter?.call(write);
            return Column(
              children: [
                Text(
                  'direct-value:${present ? raw ?? 'null' : 'absent'}:'
                  '${kind.name}',
                ),
                GestureDetector(
                  key: const ValueKey('direct-write-41'),
                  onTap: () => write(41),
                  child: const Text('direct-write-41'),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapAndPump(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
}

void main() {
  testWidgets(
      'private helper distinguishes numeric list literal runtime types',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final dataContext = DataContext(model, DataPath.root);
    final configuration = ValueNotifier(
      _directConfiguration(dataContext, source: <num>[1]),
    );
    addTearDown(configuration.dispose);

    await _pumpDirectControlled(tester, configuration);
    expect(find.text('direct-value:[1]:literal'), findsOneWidget);
    configuration.value = _directConfiguration(
      dataContext,
      source: <num>[1.0],
    );
    await tester.pump();
    expect(find.text('direct-value:[1.0]:literal'), findsOneWidget);
  });

  testWidgets('retained post-dispose writers are inert for every writer route',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final plainContext = DataContext(model, DataPath.root);
    plainContext.update(DataPath('explicit-target'), 7);
    late ValueChanged<Object?> retainedWriter;
    final configuration = ValueNotifier(
      _directConfiguration(
        plainContext,
        source: const <String, Object?>{'path': 'explicit-target'},
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpDirectControlled(
      tester,
      configuration,
      captureWriter: (writer) => retainedWriter = writer,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    retainedWriter(41);
    expect(plainContext.getValue<Object?>(DataPath('explicit-target')), 7);

    configuration.value = _directConfiguration(
      plainContext,
      selfPath: 'literal-self.value',
    );
    await _pumpDirectControlled(
      tester,
      configuration,
      captureWriter: (writer) => retainedWriter = writer,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    retainedWriter(41);
    expect(
      plainContext.getValue<Object?>(DataPath('literal-self.value')),
      isNull,
    );

    final callController = StreamController<Object?>.broadcast(sync: true);
    addTearDown(callController.close);
    final function = _ControlledIntFunction(callController);
    final callContext = DataContext(
      model,
      DataPath.root,
      functions: <ClientFunction>[function],
    );
    configuration.value = _directConfiguration(
      callContext,
      source: const <String, Object?>{'call': 'currentInt'},
      selfPath: 'call-self.value',
    );
    await _pumpDirectControlled(
      tester,
      configuration,
      captureWriter: (writer) => retainedWriter = writer,
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    retainedWriter(41);
    expect(
      callContext.getValue<Object?>(DataPath('call-self.value')),
      isNull,
    );
  });

  testWidgets('componentId alone resets the retained helper state',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final dataContext = DataContext(model, DataPath.root);
    const selfPath = 'stable-self.value';
    final configuration = ValueNotifier(
      _directConfiguration(
        dataContext,
        componentId: 'component-a',
        selfPath: selfPath,
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpDirectControlled(tester, configuration);
    await _tapAndPump(tester, const ValueKey('direct-write-41'));
    expect(find.text('direct-value:41:localOverride'), findsOneWidget);
    configuration.value = _directConfiguration(
      dataContext,
      componentId: 'component-b',
      selfPath: selfPath,
    );
    await tester.pump();
    expect(find.text('direct-value:7:literal'), findsOneWidget);
    expect(dataContext.getValue<Object?>(DataPath(selfPath)), 41);
  });

  testWidgets(
      'obsolete asynchronous cancel failures are swallowed (genui 0.10.1) '
      'without corrupting state',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final cancellation = Completer<void>();
    final events = <String>[];
    final function = _LateAfterCancelClientFunction(
      'failingCancel',
      events,
      cancelFuture: cancellation.future,
    );
    final dataContext = DataContext(
      model,
      DataPath.root,
      functions: <ClientFunction>[function],
    );
    final oldErrors = <Object>[];
    final newErrors = <Object>[];
    final configuration = ValueNotifier(
      _directConfiguration(
        dataContext,
        source: const <String, Object?>{'call': 'failingCancel'},
        reportError: (error, stack) => oldErrors.add(error),
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpDirectControlled(tester, configuration);
    await tester.pump();
    expect(function.executions, hasLength(1));
    configuration.value = _directConfiguration(
      dataContext,
      reportError: (error, stack) => newErrors.add(error),
    );
    await tester.pump();
    expect(events.last, 'cancel:failingCancel:1');
    expect(find.text('direct-value:7:literal'), findsOneWidget);

    // Seed the backing document + snapshot the bound path so a HIDDEN document
    // mutation from the failed obsolete cancel is caught directly — rendered
    // output alone would not reveal a stale write into the data model.
    dataContext.update(DataPath('cancel-integrity-probe'), 'intact');
    final boundValueBeforeCancel = dataContext.getValue<Object?>(
      DataPath('root.value'),
    );

    // Documents upstream genui 0.10.1 behavior: an OBSOLETE (already-rebound-
    // away) binding's failed async cancellation is no longer awaited/consumed by
    // genui (0.9.2 routed its error to the old reportError). The subscription's
    // cancel future is the test's own; ignore its error so it does not surface
    // as an unhandled async error, then assert the failure is NOT reported and
    // state is not corrupted.
    cancellation.future.ignore();
    cancellation.completeError(
      StateError('deterministic cancel failure'),
      StackTrace.current,
    );
    await tester.pump();
    expect(oldErrors, isEmpty);
    expect(newErrors, isEmpty);
    expect(find.text('direct-value:7:literal'), findsOneWidget);
    // Document integrity, read straight off the DataContext: the failed obsolete
    // cancel mutated NOTHING — the seeded probe and the bound path are intact.
    expect(
      dataContext.getValue<Object?>(DataPath('cancel-integrity-probe')),
      'intact',
    );
    expect(
      dataContext.getValue<Object?>(DataPath('root.value')),
      boundValueBeforeCancel,
    );

    configuration.value = _directConfiguration(
      dataContext,
      source: 8,
      reportError: (error, stack) => newErrors.add(error),
    );
    await tester.pump();
    expect(find.text('direct-value:8:literal'), findsOneWidget);
    // ...and the seeded document value still survives the subsequent rebind.
    expect(
      dataContext.getValue<Object?>(DataPath('cancel-integrity-probe')),
      'intact',
    );
  });

  testWidgets(
      'literal refreshes before write then retains value and null overrides',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final dataContext = DataContext(model, DataPath.root);
    final configuration = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledInt',
        data: const {'value': 7},
        id: 'root',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpConfiguredItem(tester, configuration);
    expect(find.text('controlled-value:7'), findsOneWidget);
    expect(model.getValue<Object?>(DataPath('root.value')), isNull);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {'value': 8},
      id: 'root',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('controlled-value:8'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('controlled-write-41'));
    expect(find.text('controlled-value:41'), findsOneWidget);
    expect(model.getValue<Object?>(DataPath('root.value')), 41);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {'value': 9},
      id: 'root',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('controlled-value:41'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('controlled-write-null'));
    expect(find.text('controlled-value:null'), findsOneWidget);
    expect(model.getValue<Object?>(DataPath('root.value')), isNull);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {'value': 10},
      id: 'root',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('controlled-value:null'), findsOneWidget);
  });

  testWidgets('path takes precedence, writes through, and rebinds A to B',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final controller = StreamController<Object?>.broadcast(sync: true);
    addTearDown(controller.close);
    final function = _ControlledIntFunction(controller);
    final dataContext = DataContext(
      model,
      DataPath.root,
      functions: <ClientFunction>[function],
    );
    dataContext
      ..update(DataPath('answer-a'), 9)
      ..update(DataPath('answer-b'), 12);
    final configuration = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledInt',
        data: const {
          'value': {'path': 'answer-a', 'call': 'currentInt'},
        },
        id: 'root',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpConfiguredItem(tester, configuration);
    expect(find.text('controlled-value:9'), findsOneWidget);
    expect(function.executeCount, 0);

    dataContext.update(DataPath('answer-a'), 10);
    await tester.pump();
    await tester.pump();
    expect(find.text('controlled-value:10'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('controlled-write-41'));
    expect(dataContext.getValue<Object?>(DataPath('answer-a')), 41);
    expect(find.text('controlled-value:41'), findsOneWidget);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {
        'value': {'path': 'answer-b'},
      },
      id: 'root',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('controlled-value:12'), findsOneWidget);

    dataContext.update(DataPath('answer-b'), 13);
    await tester.pump();
    await tester.pump();
    expect(find.text('controlled-value:13'), findsOneWidget);
  });

  testWidgets(
      'call identity, immediate cancellation, epoch, and disposal are exact',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final events = <String>[];
    final firstFunction = _LateAfterCancelClientFunction('lateInt', events);
    final secondFunction =
        _LateAfterCancelClientFunction('lateIntTwo', events);
    final dataContext = DataContext(
      model,
      DataPath.root,
      functions: <ClientFunction>[firstFunction, secondFunction],
    );
    final firstCall = <String, Object?>{
      'call': 'lateInt',
      'args': <String, Object?>{
        'numbers': <Object?>[1, 2],
        'nested': <String, Object?>{'x': 1, 'y': 2},
      },
    };
    final equalDistinctCall = <String, Object?>{
      'args': <String, Object?>{
        'nested': <String, Object?>{'y': 2.0, 'x': 1.0},
        'numbers': <Object?>[1.0, 2.0],
      },
      'call': 'lateInt',
    };
    final changedListCall = <String, Object?>{
      'call': 'lateInt',
      'args': <String, Object?>{
        'numbers': <Object?>[2, 1],
        'nested': <String, Object?>{'x': 1, 'y': 2},
      },
    };
    final configuration = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledInt',
        data: {'value': firstCall},
        id: 'root',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpConfiguredItem(tester, configuration);
    await tester.pump();
    expect(firstFunction.executions, hasLength(1));
    firstFunction.executions.single.emitLate(13);
    await tester.pump();
    expect(find.text('controlled-value:13'), findsOneWidget);
    firstFunction.executions.single.emitLate(14);
    await tester.pump();
    expect(find.text('controlled-value:14'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('controlled-write-41')));
    expect(firstFunction.executions.single.cancelCount, 1);
    expect(events.last, 'cancel:lateInt:1');
    await tester.pump();
    expect(find.text('controlled-value:41'), findsOneWidget);
    firstFunction.executions.single.emitLate(99);
    await tester.pump();
    expect(find.text('controlled-value:41'), findsOneWidget);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: {'value': equalDistinctCall},
      id: 'root',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(firstFunction.executions, hasLength(1));
    expect(find.text('controlled-value:41'), findsOneWidget);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: {'value': changedListCall},
      id: 'root',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    await tester.pump();
    expect(firstFunction.executions, hasLength(2));
    firstFunction.executions.first.emitLate(77);
    await tester.pump();
    expect(find.text('controlled-value:null'), findsOneWidget);
    firstFunction.executions.last.emitLate(23);
    await tester.pump();
    expect(find.text('controlled-value:23'), findsOneWidget);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {
        'value': {
          'call': 'lateIntTwo',
          'args': <String, Object?>{},
        },
      },
      id: 'root',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    await tester.pump();
    expect(firstFunction.executions.last.cancelCount, 1);
    expect(secondFunction.executions, hasLength(1));
    expect(
      events.indexOf('cancel:lateInt:2'),
      lessThan(events.indexOf('execute:lateIntTwo:1')),
    );
    firstFunction.executions.last.emitLate(88);
    secondFunction.executions.single.emitLate(31);
    await tester.pump();
    expect(find.text('controlled-value:31'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(secondFunction.executions.single.cancelCount, 1);
  });

  testWidgets(
      'every leaf family preserves literal conversion, defaults, and isolated overrides',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final dataContext = DataContext(model, DataPath.root);
    final configuration = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledLeafFamilies',
        data: const {
          'enabled': 1,
          'label': 123,
          'choice': 'alpha',
          'strings': <Object?>['a', 2, null],
          'integers': <Object?>[1, 2.9, '3', null],
          'doubles': <Object?>[1, 2.5, '3'],
          'numbers': <Object?>[1, 2.5, '3'],
          'booleans': <Object?>[true, 1, false],
          'maybeNumbers': <Object?>[1, null, 2.5, '3'],
        },
        id: 'families',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpConfiguredItem(tester, configuration);
    expect(find.text('families-enabled:false'), findsOneWidget);
    expect(find.text('families-label:123'), findsOneWidget);
    expect(find.text('families-choice:alpha'), findsOneWidget);
    expect(find.text('families-strings:a'), findsOneWidget);
    expect(find.text('families-integers:1,2'), findsOneWidget);
    expect(find.text('families-doubles:1.0,2.5'), findsOneWidget);
    expect(find.text('families-numbers:1,2.5'), findsOneWidget);
    expect(find.text('families-number-types:int,double'), findsOneWidget);
    expect(find.text('families-booleans:true,false'), findsOneWidget);
    expect(find.text('families-maybe-integers:null'), findsOneWidget);
    expect(find.text('families-maybe-numbers:1,null,2.5,null'), findsOneWidget);
    expect(find.text('families-fallback-integers:7,8'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('families-write-scalars'));
    expect(find.text('families-enabled:true'), findsOneWidget);
    expect(find.text('families-label:local'), findsOneWidget);
    expect(find.text('families-choice:beta'), findsOneWidget);
    expect(dataContext.getValue<Object?>(DataPath('families.enabled')), true);
    expect(dataContext.getValue<Object?>(DataPath('families.label')), 'local');
    expect(
      dataContext.getValue<Object?>(DataPath('families.choice')),
      'beta',
    );

    configuration.value = _ItemConfiguration(
      type: 'ControlledLeafFamilies',
      data: const {
        'enabled': false,
        'label': 'producer',
        'choice': 'alpha',
        'strings': <String>['next'],
        'integers': <int>[8],
        'doubles': <double>[8.5],
        'numbers': <num>[8, 8.5],
        'booleans': <bool>[false],
        'maybeIntegers': <int>[9],
        'maybeNumbers': <num?>[9, null],
      },
      id: 'families',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('families-enabled:true'), findsOneWidget);
    expect(find.text('families-label:local'), findsOneWidget);
    expect(find.text('families-choice:beta'), findsOneWidget);
    expect(find.text('families-strings:next'), findsOneWidget);
    expect(find.text('families-integers:8'), findsOneWidget);
    expect(find.text('families-maybe-integers:9'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('families-write-lists'));
    expect(find.text('families-strings:local'), findsOneWidget);
    expect(find.text('families-integers:41'), findsOneWidget);
    expect(find.text('families-doubles:4.5'), findsOneWidget);
    expect(find.text('families-numbers:4,4.5'), findsOneWidget);
    expect(find.text('families-number-types:int,double'), findsOneWidget);
    expect(find.text('families-booleans:false'), findsOneWidget);
    expect(find.text('families-maybe-numbers:4,null,4.5'), findsOneWidget);
    expect(find.text('families-fallback-integers:9'), findsOneWidget);
    expect(find.text('families-maybe-integers:9'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('families-write-null-list'));
    expect(find.text('families-maybe-integers:null'), findsOneWidget);
    configuration.value = _ItemConfiguration(
      type: 'ControlledLeafFamilies',
      data: const {
        'enabled': false,
        'label': 'late',
        'choice': 'alpha',
        'strings': <String>['late'],
        'integers': <int>[99],
        'doubles': <double>[99],
        'numbers': <num>[99],
        'booleans': <bool>[true],
        'maybeIntegers': <int>[99],
        'maybeNumbers': <num?>[99],
        'fallbackIntegers': <int>[99],
      },
      id: 'families',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('families-maybe-integers:null'), findsOneWidget);
    expect(find.text('families-integers:41'), findsOneWidget);
  });

  testWidgets('bool, string, enum, and integer list paths stay two-way reactive',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final dataContext = DataContext(model, DataPath.root)
      ..update(DataPath('enabled-path'), 1)
      ..update(DataPath('label-path'), 41)
      ..update(DataPath('choice-path'), 'alpha')
      ..update(DataPath('integers-path'), <Object?>[1, 2.8, 'x']);
    final configuration = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledLeafFamilies',
        data: const {
          'enabled': {'path': 'enabled-path'},
          'label': {'path': 'label-path'},
          'choice': {'path': 'choice-path'},
          'strings': <String>[],
          'integers': {'path': 'integers-path'},
          'doubles': <double>[],
          'numbers': <num>[],
          'booleans': <bool>[],
          'maybeNumbers': <num?>[],
        },
        id: 'families',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpConfiguredItem(tester, configuration);
    expect(find.text('families-enabled:true'), findsOneWidget);
    expect(find.text('families-label:41'), findsOneWidget);
    expect(find.text('families-choice:alpha'), findsOneWidget);
    expect(find.text('families-integers:1,2'), findsOneWidget);

    dataContext
      ..update(DataPath('enabled-path'), 'false')
      ..update(DataPath('label-path'), false)
      ..update(DataPath('choice-path'), 'beta')
      ..update(DataPath('integers-path'), <Object?>[3.9, 4]);
    await tester.pump();
    await tester.pump();
    expect(find.text('families-enabled:false'), findsOneWidget);
    expect(find.text('families-label:false'), findsOneWidget);
    expect(find.text('families-choice:beta'), findsOneWidget);
    expect(find.text('families-integers:3,4'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('families-write-scalars'));
    await _tapAndPump(tester, const ValueKey('families-write-lists'));
    expect(dataContext.getValue<Object?>(DataPath('enabled-path')), true);
    expect(dataContext.getValue<Object?>(DataPath('label-path')), 'local');
    expect(
      dataContext.getValue<Object?>(DataPath('choice-path')),
      'beta',
    );
    expect(
      dataContext.getValue<Object?>(DataPath('integers-path')),
      const <int>[41],
    );

    dataContext
      ..update(DataPath('enabled-path'), 0)
      ..update(DataPath('label-path'), 99)
      ..update(DataPath('choice-path'), 'alpha')
      ..update(DataPath('integers-path'), <Object?>[5.8]);
    await tester.pump();
    await tester.pump();
    expect(find.text('families-enabled:false'), findsOneWidget);
    expect(find.text('families-label:99'), findsOneWidget);
    expect(find.text('families-choice:alpha'), findsOneWidget);
    expect(find.text('families-integers:5'), findsOneWidget);
  });

  testWidgets(
      'call conversions stay reactive until write and list cancellation rejects late data',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final enabledController = StreamController<Object?>.broadcast(sync: true);
    final labelController = StreamController<Object?>.broadcast(sync: true);
    final choiceController = StreamController<Object?>.broadcast(sync: true);
    addTearDown(enabledController.close);
    addTearDown(labelController.close);
    addTearDown(choiceController.close);
    final events = <String>[];
    final integerFunction = _LateAfterCancelClientFunction(
      'currentIntegers',
      events,
    );
    final dataContext = DataContext(
      model,
      DataPath.root,
      functions: <ClientFunction>[
        _ControlledValueFunction('currentEnabled', enabledController),
        _ControlledValueFunction('currentLabel', labelController),
        _ControlledValueFunction('currentChoice', choiceController),
        integerFunction,
      ],
    );
    final configuration = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledLeafFamilies',
        data: const {
          'enabled': {'call': 'currentEnabled'},
          'label': {'call': 'currentLabel'},
          'choice': {'call': 'currentChoice'},
          'strings': <String>[],
          'integers': {'call': 'currentIntegers'},
          'doubles': <double>[],
          'numbers': <num>[],
          'booleans': <bool>[],
          'maybeNumbers': <num?>[],
        },
        id: 'families',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(configuration.dispose);

    await _pumpConfiguredItem(tester, configuration);
    await tester.pump();
    expect(integerFunction.executions, hasLength(1));
    enabledController.add(0);
    labelController.add(12);
    choiceController.add('beta');
    integerFunction.executions.single.emitLate(<Object?>[1, 2.8, 'x']);
    await tester.pump();
    expect(find.text('families-enabled:true'), findsOneWidget);
    expect(find.text('families-label:12'), findsOneWidget);
    expect(find.text('families-choice:beta'), findsOneWidget);
    expect(find.text('families-integers:1,2'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('families-write-lists')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('families-write-lists')));
    expect(integerFunction.executions.single.cancelCount, 1);
    expect(events.last, 'cancel:currentIntegers:1');
    await tester.pump();
    expect(find.text('families-integers:41'), findsOneWidget);
    integerFunction.executions.single.emitLate(<int>[99]);
    await tester.pump();
    expect(find.text('families-integers:41'), findsOneWidget);

    await _tapAndPump(tester, const ValueKey('families-write-scalars'));
    enabledController.add(null);
    labelController.add('late');
    choiceController.add('alpha');
    await tester.pump();
    expect(find.text('families-enabled:false'), findsOneWidget);
    expect(find.text('families-label:local'), findsOneWidget);
    expect(find.text('families-choice:beta'), findsOneWidget);
  });

  testWidgets('kind and component identity changes clear an override',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final controller = StreamController<Object?>.broadcast(sync: true);
    addTearDown(controller.close);
    final function = _ControlledIntFunction(controller);
    final dataContext = DataContext(
      model,
      DataPath.root,
      functions: <ClientFunction>[function],
    );
    dataContext.update(DataPath('answer'), 8);
    final configuration = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledInt',
        data: const {'value': 5},
        id: 'control-a',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(configuration.dispose);
    await _pumpConfiguredItem(tester, configuration);
    await _tapAndPump(tester, const ValueKey('controlled-write-41'));

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {
        'value': {'path': 'answer'},
      },
      id: 'control-a',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('controlled-value:8'), findsOneWidget);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {
        'value': {'call': 'currentInt'},
      },
      id: 'control-a',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    await tester.pump();
    controller.add(19);
    await tester.pump();
    expect(find.text('controlled-value:19'), findsOneWidget);

    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {'value': 6},
      id: 'control-a',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    await _tapAndPump(tester, const ValueKey('controlled-write-41'));
    configuration.value = _ItemConfiguration(
      type: 'ControlledInt',
      data: const {'value': 7},
      id: 'control-b',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('controlled-value:7'), findsOneWidget);
  });

  testWidgets('two fields and two component IDs do not cross-talk',
      (tester) async {
    final model = InMemoryDataModel();
    addTearDown(model.dispose);
    final dataContext = DataContext(model, DataPath.root);
    final pair = ValueNotifier(
      _ItemConfiguration(
        type: 'ControlledIntPair',
        data: const {'first': 1, 'second': 2},
        id: 'pair',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    );
    addTearDown(pair.dispose);
    await _pumpConfiguredItem(tester, pair);
    await _tapAndPump(tester, const ValueKey('pair-write-first'));
    expect(find.text('pair-first:11'), findsOneWidget);
    expect(find.text('pair-second:2'), findsOneWidget);
    pair.value = _ItemConfiguration(
      type: 'ControlledIntPair',
      data: const {'first': 3, 'second': 4},
      id: 'pair',
      surfaceId: 'surface-a',
      dataContext: dataContext,
    );
    await tester.pump();
    expect(find.text('pair-first:11'), findsOneWidget);
    expect(find.text('pair-second:4'), findsOneWidget);
    await _tapAndPump(tester, const ValueKey('pair-write-second'));
    expect(find.text('pair-first:11'), findsOneWidget);
    expect(find.text('pair-second:22'), findsOneWidget);

    final components = ValueNotifier(<_ItemConfiguration>[
      _ItemConfiguration(
        type: 'ControlledInt',
        data: const {'value': 1},
        id: 'control-a',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
      _ItemConfiguration(
        type: 'ControlledInt',
        data: const {'value': 2},
        id: 'control-b',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    ]);
    addTearDown(components.dispose);
    await _pumpTwoConfiguredItems(tester, components);
    await tester.tap(
      find.byKey(const ValueKey('controlled-write-41')).first,
    );
    await tester.pump();
    expect(find.text('controlled-value:41'), findsOneWidget);
    expect(find.text('controlled-value:2'), findsOneWidget);
    components.value = <_ItemConfiguration>[
      _ItemConfiguration(
        type: 'ControlledInt',
        data: const {'value': 9},
        id: 'control-a',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
      _ItemConfiguration(
        type: 'ControlledInt',
        data: const {'value': 3},
        id: 'control-b',
        surfaceId: 'surface-a',
        dataContext: dataContext,
      ),
    ];
    await tester.pump();
    expect(find.text('controlled-value:41'), findsOneWidget);
    expect(find.text('controlled-value:3'), findsOneWidget);
  });

  testWidgets('semantic context axes and field identity reset independently',
      (tester) async {
    expect(_alternateExactCatalogId, isNot(restageA2uiCatalogId));
    final firstModel = InMemoryDataModel();
    final secondModel = InMemoryDataModel();
    addTearDown(firstModel.dispose);
    addTearDown(secondModel.dispose);
    final firstContext = DataContext(firstModel, DataPath.root);
    final configuration = ValueNotifier(
      _directConfiguration(firstContext),
    );
    addTearDown(configuration.dispose);
    await _pumpDirectControlled(tester, configuration);
    await _tapAndPump(tester, const ValueKey('direct-write-41'));
    expect(find.text('direct-value:41:localOverride'), findsOneWidget);

    final equivalentContext = DataContext(firstModel, DataPath.root);
    configuration.value = _directConfiguration(equivalentContext);
    await tester.pump();
    expect(find.text('direct-value:41:localOverride'), findsOneWidget);

    configuration.value = _directConfiguration(
      equivalentContext,
      surfaceId: 'surface-b',
    );
    await tester.pump();
    expect(find.text('direct-value:7:literal'), findsOneWidget);
    await _tapAndPump(tester, const ValueKey('direct-write-41'));

    configuration.value = _directConfiguration(
      equivalentContext,
      surfaceId: 'surface-b',
      catalogId: _alternateExactCatalogId,
    );
    await tester.pump();
    expect(find.text('direct-value:7:literal'), findsOneWidget);
    await _tapAndPump(tester, const ValueKey('direct-write-41'));

    final secondContext = DataContext(secondModel, DataPath.root);
    configuration.value = _directConfiguration(
      secondContext,
      surfaceId: 'surface-b',
      catalogId: _alternateExactCatalogId,
    );
    await tester.pump();
    expect(find.text('direct-value:7:literal'), findsOneWidget);
    await _tapAndPump(tester, const ValueKey('direct-write-41'));

    final nestedContext = DataContext(secondModel, DataPath('nested'));
    configuration.value = _directConfiguration(
      nestedContext,
      surfaceId: 'surface-b',
      catalogId: _alternateExactCatalogId,
    );
    await tester.pump();
    expect(find.text('direct-value:7:literal'), findsOneWidget);
    await _tapAndPump(tester, const ValueKey('direct-write-41'));

    configuration.value = _directConfiguration(
      nestedContext,
      surfaceId: 'surface-b',
      catalogId: _alternateExactCatalogId,
      field: 'otherValue',
    );
    await tester.pump();
    expect(find.text('direct-value:7:literal'), findsOneWidget);
  });

  testWidgets(
      'real SurfaceController validates and renders a controlled enum path reference',
      (tester) async {
    const surfaceId = 'enum-path-surface';
    final controller = SurfaceController(catalogs: [buildRestageCatalog()]);
    final submissions = <ChatMessage>[];
    final submissionSubscription = controller.onSubmit.listen(submissions.add);
    addTearDown(submissionSubscription.cancel);
    addTearDown(controller.dispose);
    controller
      ..handleMessage(
        CreateSurfaceMessage(
          surfaceId: surfaceId,
          catalogId: restageA2uiCatalogId,
        ),
      )
      ..handleMessage(
        UpdateDataModelMessage(
          surfaceId: surfaceId,
          path: 'choice-path',
          value: 'alpha',
        ),
      )
      ..handleMessage(
        UpdateComponentsMessage(
          surfaceId: surfaceId,
          components: [
            _controlledFamiliesComponent(
              const <String, Object?>{'path': 'choice-path'},
            ),
          ],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Surface(surfaceContext: controller.contextFor(surfaceId)),
      ),
    );
    await tester.pump();
    expect(
      submissions,
      isEmpty,
      reason: 'the real GenUI validator must accept the enum path reference',
    );
    expect(find.text('families-choice:alpha'), findsOneWidget);

    controller.handleMessage(
      UpdateDataModelMessage(
        surfaceId: surfaceId,
        path: 'choice-path',
        value: 'beta',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('families-choice:beta'), findsOneWidget);
    expect(submissions, isEmpty);
  });

  testWidgets(
      'real SurfaceController validates and renders a controlled enum call reference',
      (tester) async {
    const surfaceId = 'enum-call-surface';
    final choiceController = StreamController<Object?>.broadcast(sync: true);
    addTearDown(choiceController.close);
    final catalog = buildRestageCatalog().copyWith(
      newFunctions: [
        _ControlledValueFunction('currentChoice', choiceController),
      ],
    );
    final controller = SurfaceController(catalogs: [catalog]);
    final submissions = <ChatMessage>[];
    final submissionSubscription = controller.onSubmit.listen(submissions.add);
    addTearDown(submissionSubscription.cancel);
    addTearDown(controller.dispose);
    controller
      ..handleMessage(
        CreateSurfaceMessage(
          surfaceId: surfaceId,
          catalogId: restageA2uiCatalogId,
        ),
      )
      ..handleMessage(
        UpdateComponentsMessage(
          surfaceId: surfaceId,
          components: [
            _controlledFamiliesComponent(
              const <String, Object?>{'call': 'currentChoice'},
            ),
          ],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Surface(surfaceContext: controller.contextFor(surfaceId)),
      ),
    );
    await tester.pump();
    expect(
      submissions,
      isEmpty,
      reason: 'the real GenUI validator must accept the enum call reference',
    );

    choiceController.add('beta');
    await tester.pump();
    expect(find.text('families-choice:beta'), findsOneWidget);
    choiceController.add('alpha');
    await tester.pump();
    expect(find.text('families-choice:alpha'), findsOneWidget);
    expect(submissions, isEmpty);
  });

  testWidgets('real Surface rebuild retains same ID and resets changed ID',
      (tester) async {
    const surfaceId = 'full-surface';
    final controller = SurfaceController(catalogs: [buildRestageCatalog()]);
    addTearDown(controller.dispose);
    controller
      ..handleMessage(
        CreateSurfaceMessage(
          surfaceId: surfaceId,
          catalogId: restageA2uiCatalogId,
        ),
      )
      ..handleMessage(
        UpdateComponentsMessage(
          surfaceId: surfaceId,
          components: const [
            {
              'id': 'root',
              'component': 'ControlledScalarHost',
              'child': 'control-a',
            },
            {'id': 'control-a', 'component': 'ControlledInt', 'value': 17},
          ],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Surface(surfaceContext: controller.contextFor(surfaceId)),
      ),
    );
    await tester.pump();
    expect(find.text('controlled-value:17'), findsOneWidget);
    await _tapAndPump(tester, const ValueKey('controlled-write-41'));
    expect(find.text('controlled-value:41'), findsOneWidget);

    controller.handleMessage(
      UpdateComponentsMessage(
        surfaceId: surfaceId,
        components: const [
          {
            'id': 'root',
            'component': 'ControlledScalarHost',
            'child': 'control-a',
          },
          {'id': 'control-a', 'component': 'ControlledInt', 'value': 99},
        ],
      ),
    );
    await tester.pump();
    expect(find.text('controlled-value:41'), findsOneWidget);

    controller.handleMessage(
      UpdateComponentsMessage(
        surfaceId: surfaceId,
        components: const [
          {
            'id': 'root',
            'component': 'ControlledScalarHost',
            'child': 'control-b',
          },
          {'id': 'control-b', 'component': 'ControlledInt', 'value': 23},
        ],
      ),
    );
    await tester.pump();
    expect(find.text('controlled-value:23'), findsOneWidget);
  });
}
''';
