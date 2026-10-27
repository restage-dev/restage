import 'dart:convert';
import 'dart:io';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

final _catalog = decodeCatalog(
  File('../restage_core/lib/src/widget_catalog/catalog.json')
      .readAsStringSync(),
);
const _native = SurfaceScreenHostDataNativeBindingShapeV1(
  NativeBindingContract(type: 'flutter.TextScaler', nullable: true),
);
const _string = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.string,
);
const _scaler =
    '{kind: "nativeBinding", key: "scaler", type: "flutter.TextScaler", nullable: true}';
const _color =
    '{kind: "nativeBinding", key: "color", type: "flutter.Color", nullable: false}';

SurfaceCapabilityDerivation _derive(String body,
        {SurfaceScreenHostDataSchema? context}) =>
    deriveSurfaceCapability(
      rfw.parseLibraryFile('import restage.core; $body'),
      _catalog,
      hostDataContract: context ?? const SurfaceScreenHostDataSchema.empty(),
    );

void main() {
  test('capability inspection does not relax native program admission', () {
    const type = ValueType.native('flutter.TextScaler', nullable: true);
    const values = ValueProgram(
        nodes: [ValueNode('capture', type, name: 'scaler')],
        root: 0,
        captures: {'scaler': type});
    final malformed = {
      'kind': 'nativeBinding',
      'key': 'scaler',
      'type': 'flutter.TextScaler',
      'nullable': true,
      'extra': 1
    };
    final library = rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration(
          'Root',
          null,
          rfw.ConstructorCall('Text', {
            'textScaler': {
              'version': 1,
              'program': values.encode(),
              'captures': {'scaler': malformed}
            }
          }))
    ]);
    expect(deriveSurfaceCapability(library, _catalog).builtInFloor, 24);
    expect(
        () => surfaceScreenContractGaps(library,
            events: SurfaceScreenEventSchema(events: []),
            context: SurfaceScreenHostDataSchema({'scaler': _native})),
        throwsFormatException);

    const declared = NativeBindingContract(
        type: 'installed.message',
        call: NativeCallContract(
            inputs: [],
            result: ValueType.string,
            implementation: 'message-v1'));
    final operations = {
      'native.call': NativeCallValueOperation({'message': declared})
    };
    final wrong = NativeBindingContract(
        type: declared.type,
        call: const NativeCallContract(
            inputs: [],
            result: ValueType.string,
            implementation: 'message-v2'));
    final call = ValueProgram(nodes: [
      ValueNode('native.call', ValueType.string, value: {
        'binding': 'message',
        'contract': wrong.toJson(),
        'captures': <String, String>{}
      })
    ], root: 0);
    final invalidCall = rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration(
          'Root',
          null,
          rfw.ConstructorCall('Text', {
            'text': {
              'version': 1,
              'program': call.encode(),
              'captures': <String, Object?>{}
            }
          }))
    ]);
    expect(
        () => deriveSurfaceCapability(invalidCall, _catalog,
            operations: operations),
        throwsFormatException);
    final outsideLocal = rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration(
          'Root',
          null,
          rfw.ConstructorCall('Text', {
            'textScaler': {
              'kind': 'nativeLocal',
              'slot': 'missing',
              'type': 'flutter.TextScaler',
              'nullable': true
            }
          }))
    ]);
    expect(() => deriveSurfaceCapability(outsideLocal, _catalog),
        throwsFormatException);
  });

  test(
      'native decoder binding references require SDK24 through local forwarding',
      () {
    for (final source in [
      'widget Root = Text(text: "Hi", textScaler: $_scaler);',
      'widget Inner = Text(text: "Hi", textScaler: args.value); widget Root = Inner(value: $_scaler);',
      'widget Root = ColoredBox(color: $_color);',
      'widget Root = Text(text: \"Hi\", key: {kind: \"nativeBinding\", key: \"key\", type: \"flutter.Key\", nullable: false});',
      'widget Root = Text(text: \"Hi\", textScaler: {kind: \"nativeBinding\", key: data.slot, type: \"flutter.TextScaler\", nullable: data.nullable, extra: 1});',
      'widget Root = TextRich(textSpan: {style: {color: $_color}});',
    ]) {
      final result = _derive(source);
      expect(result.builtInFloor, 24, reason: source);
      final required = CapabilityManifest(
        builtInFloor: result.builtInFloor,
        requiredLibraries: result.requiredLibraries,
      );
      for (final installed in [23, 24]) {
        expect(
            BlobRenderCapabilityGate.evaluate(
              required: required,
              installed: InstalledCapability(
                  builtInCatalogVersion: installed,
                  installedLibraries: const []),
            ).accepted,
            installed == 24,
            reason: source);
      }
    }
  });

  test('same-shaped app data and legacy native values retain their floors', () {
    for (final source in [
      'widget Root = Text(text: $_scaler);',
      'widget Root = Text(text: "Hi", textScaler: {kind: "linear", factor: 1.0});',
      'widget Root = ColoredBox(color: 4278190080);',
      'widget Root = TextRich(textSpan: {text: "Hi", style: {fontWeight: 700}});',
      'widget Root = TextRich(textSpan: {text: "Hi", unused: $_color});',
    ]) {
      expect(_derive(source).builtInFloor, lessThan(24), reason: source);
    }
  });

  test('scalar widget keys retain their floors', () {
    final baseline = _derive('widget Root = Text(text: "Hi");').builtInFloor;
    expect(baseline, lessThan(24));
    for (final value in ['"ordinary"', '42', '1.5', 'true', 'null']) {
      for (final source in [
        'widget Root = Text(text: "Hi", key: $value);',
        'widget Inner = Text(text: "Hi", key: args.value); widget Root = Inner(value: $value);',
        'widget Root = Text(text: "Hi", key: switch data.choice {true: ${value == 'null' ? 'args.absent' : value}, default: "ordinary"});',
        'widget Repeat = switch data.more {true: Text(text: "Hi", key: $value), default: Repeat()}; widget Root = Repeat();',
      ]) {
        // Capability inspection does not admit raw scalar keys to the native
        // decoder. Authored scalar ValueKey behavior has its own byte oracle.
        expect(_derive(source).builtInFloor, baseline, reason: source);
      }
    }
    expect(
        _derive('widget Inner = Text(text: "Hi", key: args.value); widget Root = Inner();')
            .builtInFloor,
        baseline);
  });

  test(
      'native Key use retains floors host requirements and conservative bounds',
      () {
    const reference =
        '{kind:"nativeBinding",key:"original",type:"flutter.Key",nullable:false}';
    const type = ValueType.native('flutter.Key');
    const program = ValueProgram(
        nodes: [ValueNode('capture', type, name: 'key')],
        root: 0,
        captures: {'key': type});
    final schema = SurfaceScreenHostDataSchema(const {
      'original': SurfaceScreenHostDataNativeBindingShapeV1(
          NativeBindingContract(type: 'flutter.Key'))
    });
    for (final source in [
      'widget Root = Text(text:"Hi",key:$reference);',
      'widget Inner = Text(text:"Hi",key:args.value); widget Root=Inner(value:$reference);',
      'widget Root = Text(text:"Hi",key:switch data.choice {true:$reference,default:args.absent});',
      'widget Repeat = switch data.more {true:Text(text:"Hi",key:$reference),default:Repeat()}; widget Root=Repeat();',
      'widget Root = Text(text:"Hi",key:data.context.original);',
      'widget Root = Text(text:"Hi",key:data.context.unknown);',
      'widget Root = Text(text:"Hi",key:{version:1,program:${jsonEncode(program.encode())},captures:{key:$reference}});',
    ]) {
      final library = rfw.parseLibraryFile(source);
      final result =
          deriveSurfaceCapability(library, _catalog, hostDataContract: schema);
      expect(result.builtInFloor, 24, reason: source);
      expect(nativeBindingsNeedInstalledHost(library, _catalog), isTrue,
          reason: source);
      final required = CapabilityManifest(
          builtInFloor: result.builtInFloor,
          requiredLibraries: result.requiredLibraries);
      for (final installed in [23, 24]) {
        expect(
            BlobRenderCapabilityGate.evaluate(
                required: required,
                installed: InstalledCapability(
                    builtInCatalogVersion: installed,
                    installedLibraries: const [])).accepted,
            installed == 24,
            reason: source);
      }
    }
    String forwarded(int count) => [
          'widget W0=Text(text:"Hi",key:args.value);',
          for (var index = 1; index <= count; index++)
            'widget W$index=W${index - 1}(value:args.value);',
          'widget Root=W$count(value:"ordinary");'
        ].join(' ');
    expect(_derive(forwarded(2)).builtInFloor, lessThan(24));
    expect(_derive(forwarded(70)).builtInFloor, 24);
  });

  test('Key qualification preserves unrelated and future property versions',
      () {
    Catalog withVersion(String property) {
      final json = jsonDecode(encodeCatalog(_catalog)) as Map<String, dynamic>;
      final text = (json['widgets'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['name'] == 'Text');
      final entry = (text['properties'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['name'] == property);
      entry['sinceVersion'] = 25;
      return decodeCatalog(jsonEncode(json));
    }

    final scalar =
        rfw.parseLibraryFile('widget Root=Text(text:"Hi",key:"ordinary");');
    expect(
        deriveSurfaceCapability(scalar, withVersion('text')).builtInFloor, 25);
    expect(deriveSurfaceCapability(scalar, withVersion('key')).builtInFloor,
        _derive('widget Root=Text(text:"Hi");').builtInFloor);
    const reference =
        '{kind:"nativeBinding",key:"original",type:"flutter.Key",nullable:false}';
    const type = ValueType.native('flutter.Key');
    const program = ValueProgram(
        nodes: [ValueNode('capture', type, name: 'key')],
        root: 0,
        captures: {'key': type});
    final schema = SurfaceScreenHostDataSchema(const {
      'original': SurfaceScreenHostDataNativeBindingShapeV1(
          NativeBindingContract(type: 'flutter.Key'))
    });
    for (final key in [
      reference,
      'data.context.original',
      '{version:1,program:${jsonEncode(program.encode())},captures:{key:$reference}}',
    ]) {
      final native =
          rfw.parseLibraryFile('widget Root=Text(text:"Hi",key:$key);');
      expect(
          deriveSurfaceCapability(native, withVersion('key'),
                  hostDataContract: schema)
              .builtInFloor,
          25,
          reason: key);
    }
  });

  test('ordinary JSON data with native-looking keys stays ordinary data', () {
    const custom = WidgetLibrary.custom('example.data');
    final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          custom: const LibraryInfo(version: '1', capabilityVersion: 1)
        },
        widgets: [
          WidgetEntry(
              wireId: WireId('w9000'),
              name: 'DataCard',
              library: custom,
              category: WidgetCategory.decoration,
              description: 'App data',
              flutterType: 'package:example/data.dart#DataCard',
              childrenSlot: ChildrenSlot.none,
              properties: [
                PropertyEntry(
                    wireId: WireId('p9000'),
                    name: 'data',
                    type: PropertyType.dataReference,
                    description: 'Data')
              ])
        ]);
    final result = deriveSurfaceCapability(
        rfw.parseLibraryFile(
            'import example.data; widget Root = DataCard(data: $_scaler);'),
        catalog);
    expect(result.builtInFloor, lessThan(24));
  });

  test('only declared native context paths in use require SDK24', () {
    final schema = SurfaceScreenHostDataSchema({
      'native': _native,
      'values': SurfaceScreenHostDataObjectShapeV1(const {
        'scaler': _native,
        'name': _string,
      }),
      'title': _string,
      'items': SurfaceScreenHostDataListShapeV1(
          SurfaceScreenHostDataObjectShapeV1(const {'scaler': _native})),
    });
    for (final root in [
      'Text(text: "Hi", textScaler: data.context.native)',
      'Text(text: "Hi", textScaler: data.context.values.scaler)',
      'Column(children: [...for item in data.context.items: '
          'Text(text: "Hi", textScaler: item.scaler)])',
    ]) {
      expect(_derive('widget Root = $root;', context: schema).builtInFloor, 24,
          reason: root);
    }
    expect(
        _derive('widget Root = Text(text: data.context.title);',
                context: schema)
            .builtInFloor,
        lessThan(24));
    expect(
        _derive('widget Root = Text(text: data.context.values.name);',
                context: schema)
            .builtInFloor,
        lessThan(24));
    expect(
        _derive('widget Root = Text(text: "Hi");', context: schema)
            .builtInFloor,
        lessThan(24));
    expect(
        _derive('widget Root = Text(text: data.context.missing);',
                context: schema)
            .builtInFloor,
        lessThan(24));
  });

  test('raw preview resolves every typed inline-span context child', () {
    const color = NativeBindingContract(type: 'flutter.Color');
    const recognizer = NativeBindingContract(type: 'flutter.GestureRecognizer');
    const key = NativeBindingContract(type: 'flutter.Key');
    final cases = <(String, Object?, Object?)>[
      ('style', {'color': color.reference('color')}, {'color': 4278190080}),
      ('recognizer', recognizer.reference('recognizer'), {'kind': 'tap'}),
      (
        'children',
        [
          {
            'text': 'Child',
            'style': {'color': color.reference('color')}
          }
        ],
        [
          {
            'text': 'Child',
            'style': {'color': 4278190080}
          }
        ]
      ),
    ];
    for (final (field, native, ordinary) in cases) {
      final library = rfw.parseLibraryFile('import restage.core; '
          'widget Root = TextRich(textSpan: {text: "Hi", $field: data.context.value});');
      expect(nativeBindingsNeedInstalledHost(library, _catalog), isTrue,
          reason: 'missing $field');
      expect(
          nativeBindingsNeedInstalledHost(library, _catalog,
              context: {'value': native}),
          isTrue,
          reason: 'native $field');
      expect(
          nativeBindingsNeedInstalledHost(library, _catalog,
              context: {'value': key.reference('opaque')}),
          isTrue,
          reason: 'opaque reference cannot stand in for $field');
      expect(
          nativeBindingsNeedInstalledHost(library, _catalog,
              context: {'value': ordinary}),
          isFalse,
          reason: 'ordinary $field');
      expect(
          nativeBindingsNeedInstalledHost(library, _catalog,
              context: {'value': null}),
          isFalse,
          reason: 'null $field');
    }
    final nested = rfw.parseLibraryFile('import restage.core; '
        'widget Inner = TextRich(textSpan: args.span); '
        'widget Root = Inner(span: {children: data.context.children});');
    expect(
        nativeBindingsNeedInstalledHost(nested, _catalog, context: {
          'children': [
            {
              'text': 'Child',
              'children': [
                {
                  'text': 'Nested',
                  'style': {'color': 4278190080}
                }
              ]
            }
          ],
        }),
        isFalse);
    expect(
        nativeBindingsNeedInstalledHost(nested, _catalog, context: {
          'children': [
            {
              'text': 'Child',
              'children': [
                {
                  'text': 'Nested',
                  'recognizer': recognizer.reference('recognizer')
                }
              ]
            }
          ],
        }),
        isTrue);
  });

  test('native context is opaque to JSON captures and path traversal', () {
    final schema = SurfaceScreenHostDataSchema(const {'native': _native});
    final events = SurfaceScreenEventSchema(events: [
      SurfaceScreenEvent(
          id: 'send',
          arguments: const SurfaceScreenEventValueArguments(
            SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKind.jsonValue),
          )),
    ]);
    expect(
        surfaceScreenContractGaps(
          rfw.parseLibraryFile(
              'widget Root = Text(text: data.context.native.key);'),
          context: schema,
          events: events,
        ),
        isNotEmpty);
    expect(
        surfaceScreenContractGaps(
          rfw.parseLibraryFile(
              'widget Root = Text(onTap: event "send" {value: data.context.native});'),
          context: schema,
          events: events,
        ),
        isNotEmpty);
  });
}
