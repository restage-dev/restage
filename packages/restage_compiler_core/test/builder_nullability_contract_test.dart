import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _nullableInt = ValueType('int', nullable: true);
const _contract =
    WidgetBuilderContract(parameters: [WidgetBuilderParameter.buildContext]);

Catalog _catalog({
  bool nullable = true,
  bool required = false,
  bool defaultCallback = false,
}) =>
    Catalog(
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
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'builder',
              type: PropertyType.widgetBuilder,
              description: 'Builder',
              builderContract: _contract,
              constructorNullable: nullable,
              constructorDefault:
                  defaultCallback ? const DartConstNull() : null,
              required: required,
              sinceVersion: 19,
            ),
          ],
        ),
      ],
    );

rfw.RemoteWidgetLibrary _library(Map<String, Object?> arguments) =>
    rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration(
        'Root',
        null,
        rfw.ConstructorCall('Host', arguments),
      ),
    ]);

rfw.ConstructorCall _continuation(
  rfw.BlobNode body, {
  ValueType type = _nullableInt,
  ValueProgram? values,
  Map<String, Object?> captures = const {},
  String scope = 'frame',
}) {
  final program = BuilderProgram(
    values: values ??
        ValueProgram(
          nodes: [
            ValueNode('literal', type, value: type.nullable ? null : 7),
          ],
          root: 0,
        ),
    result: const BuilderResult.body(0, values: {'v0': 0, 'v1': 0}),
    bodyCount: 1,
  );
  return rfw.ConstructorCall(kBuilderContinuationWidgetName, {
    'version': 1,
    'program': program.encode(),
    'captures': captures,
    'bodies': [rfw.WidgetBuilderDeclaration(scope, body)],
  });
}

rfw.WidgetBuilderArgReference _value([String scope = 'frame']) =>
    rfw.WidgetBuilderArgReference(scope, const ['values', 'v0']);
rfw.WidgetBuilderArgReference _nulls({
  String scope = 'frame',
  String field = 'v0',
}) =>
    rfw.WidgetBuilderArgReference(scope, ['nulls', field]);
rfw.ConstructorCall _button(Object value) => rfw.ConstructorCall('Button', {
      'onTap': rfw.EventHandler('pick', {'value': value}),
    });

List<SurfaceScreenContractGap> _gaps(
  rfw.BlobNode body, {
  bool nullable = false,
  ValueType type = _nullableInt,
}) =>
    surfaceScreenContractGaps(
      _library({'builder': _continuation(body, type: type)}),
      context: SurfaceScreenHostDataSchema(const {}),
      events: SurfaceScreenEventSchema(
        events: [
          SurfaceScreenEvent(
            id: 'pick',
            arguments: SurfaceScreenEventValueArguments(
              nullable
                  ? const SurfaceScreenEventNullableShapeV1(
                      SurfaceScreenEventScalarShapeV1(
                        SurfaceScreenEventScalarKind.integer,
                      ),
                    )
                  : const SurfaceScreenEventScalarShapeV1(
                      SurfaceScreenEventScalarKind.integer,
                    ),
            ),
          ),
        ],
      ),
    );

rfw.ConstructorCall _inner({
  ValueType captureType = ValueType.integer,
  String scope = 'inner',
  Object? capture,
  rfw.BlobNode? body,
}) =>
    _continuation(
      body ?? _button(_value(scope)),
      scope: scope,
      values: ValueProgram(
        nodes: [ValueNode('capture', captureType, name: 'c0')],
        root: 0,
        captures: {'c0': captureType},
      ),
      captures: {'c0': capture ?? _value()},
    );

void main() {
  test('R2 optional nullable builder null has the same capability as omission',
      () {
    final catalog = _catalog();
    final omitted = deriveSurfaceCapability(_library({}), catalog);
    final explicitNull =
        deriveSurfaceCapability(_library({'builder': null}), catalog);
    expect(explicitNull.builtInFloor, omitted.builtInFloor);
    expect(explicitNull.builtInFloor, 1);
    expect(
      deriveSurfaceCapability(
        _library({
          'builder': _continuation(const rfw.ConstructorCall('Body', {})),
        }),
        catalog,
      ).builtInFloor,
      19,
    );
  });

  test(
      'R2 required nullable builder uses canonical null marker '
      'and rejects absence', () {
    final catalog = _catalog(required: true);
    expect(
      deriveSurfaceCapability(
        _library({
          'builder': {RfwConstructorPresenceProtocol.markerKey: 1},
        }),
        catalog,
      ).builtInFloor,
      1,
    );
    expect(
      () => deriveSurfaceCapability(_library({}), catalog),
      throwsFormatException,
    );
    expect(
      () => deriveSurfaceCapability(_library({'builder': null}), catalog),
      throwsFormatException,
    );
  });

  test(
      'R2 existing presence envelope preserves and validates nullable builders',
      () {
    const marker = RfwConstructorPresenceProtocol.markerKey;
    const value = RfwConstructorPresenceProtocol.valueKey;
    for (final catalog in [
      _catalog(required: true),
      _catalog(defaultCallback: true),
    ]) {
      expect(
        deriveSurfaceCapability(
          _library({
            'builder': {marker: 1},
          }),
          catalog,
        ).builtInFloor,
        1,
      );
      expect(
        deriveSurfaceCapability(
          _library({
            'builder': {
              marker: 1,
              value: _continuation(const rfw.ConstructorCall('Body', {})),
            },
          }),
          catalog,
        ).builtInFloor,
        19,
      );
      for (final malformed in <Object?>[
        null,
        <String, Object?>{},
        _continuation(const rfw.ConstructorCall('Body', {})),
        <String, Object?>{marker: 2},
        {marker: 1.0},
        {marker: 1, 'unknown': true},
        {marker: 1, value: 'bad'},
      ]) {
        expect(
          () => deriveSurfaceCapability(
            _library({'builder': malformed}),
            catalog,
          ),
          throwsFormatException,
        );
      }
    }
  });

  test('R2 nonnullable null and malformed supplied builder programs refuse',
      () {
    for (final required in [false, true]) {
      expect(
        () => deriveSurfaceCapability(
          _library({'builder': null}),
          _catalog(nullable: false, required: required),
        ),
        throwsFormatException,
      );
    }
    for (final malformed in <Object>[
      'bad',
      <String, Object?>{},
      const rfw.ConstructorCall(
        kBuilderContinuationWidgetName,
        {'version': 1, 'program': 'bad', 'captures': <String, Object?>{}},
      ),
    ]) {
      expect(
        () => deriveSurfaceCapability(
          _library({'builder': malformed}),
          _catalog(),
        ),
        throwsFormatException,
      );
    }
  });

  test('R3 unguarded nullable frame cannot satisfy a required integer event',
      () {
    expect(
      _gaps(_button(_value())).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
    expect(
      _gaps(_button(_value()), nullable: true).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
    expect(_gaps(_button(_value()), type: ValueType.integer), isEmpty);
  });

  test('R3 compiler null discriminator preserves the missing event branch', () {
    final emitted = _button(rfw.Switch(_nulls(), {false: _value()}));
    expect(
      _gaps(emitted, nullable: true).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
    expect(
      _gaps(emitted).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
    expect(
      _gaps(_button(rfw.Switch(_nulls(), {false: _value(), true: 0}))),
      isEmpty,
    );
  });

  test('R3 matching false widget branch refines only its own frame field', () {
    expect(_gaps(rfw.Switch(_nulls(), {false: _button(_value())})), isEmpty);
    expect(
      _gaps(rfw.Switch(_nulls(), {false: _button(_value())}), nullable: true),
      isEmpty,
    );
    expect(
      _gaps(
        rfw.Switch(_nulls(), {
          true: const rfw.ConstructorCall('Body', {}),
          null: _button(_value()),
        }),
      ),
      isEmpty,
    );
    for (final input in [_nulls(field: 'v1'), _nulls(scope: 'different')]) {
      expect(
        _gaps(rfw.Switch(input, {false: _button(_value())}))
            .map((gap) => '$gap'),
        ['argument "value" of event "pick"'],
      );
    }
    expect(
      _gaps(rfw.Switch(_nulls(), {true: _button(_value())}))
          .map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
  });

  test(
      'R3 nested captures preserve nullable types unless guarded '
      'by matching frame', () {
    expect(() => _gaps(_inner()), throwsFormatException);
    expect(
      _gaps(_inner(captureType: _nullableInt)).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
    expect(
      _gaps(_inner(captureType: _nullableInt), nullable: true)
          .map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
    expect(_gaps(rfw.Switch(_nulls(), {false: _inner()})), isEmpty);
    expect(
      _gaps(
        _inner(capture: rfw.Switch(_nulls(), {false: _value(), true: 0})),
      ),
      isEmpty,
    );
    final nullableCapture = rfw.Switch(_nulls(), {false: _value()});
    expect(
      () => _gaps(_inner(capture: nullableCapture)),
      throwsFormatException,
    );
    expect(
      _gaps(
        _inner(captureType: _nullableInt, capture: nullableCapture),
        nullable: true,
      ).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
    expect(
      _gaps(
        _inner(
          captureType: _nullableInt,
          capture: nullableCapture,
          body: const rfw.ConstructorCall('Body', {}),
        ),
      ),
      isEmpty,
    );
    expect(
      () => _gaps(rfw.Switch(_nulls(field: 'v1'), {false: _inner()})),
      throwsFormatException,
    );
  });

  test(
      'R3 null guard cannot cross a nested builder scope that shadows its name',
      () {
    final inner = _continuation(_button(_value()));
    expect(
      _gaps(rfw.Switch(_nulls(), {false: inner})).map((gap) => '$gap'),
      ['argument "value" of event "pick"'],
    );
  });
}
