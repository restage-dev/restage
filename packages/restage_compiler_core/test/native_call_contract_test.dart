import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const native = ValueType.native('flutter.Key');
const call = NativeBindingContract(
    type: 'installed.key',
    call: NativeCallContract(
        inputs: [ValueType.integer],
        captures: {'counter': ValueType.integer},
        result: native,
        implementation: 'key-body-v1'));
ValueProgram program(
        {Map<String, String> captures = const {'counter': 'count'},
        ValueType result = native}) =>
    ValueProgram(
        nodes: [
          const ValueNode('literal', ValueType.integer, value: 7),
          ValueNode('native.call', result, inputs: [
            0
          ], value: {
            'binding': 'makeKey',
            'contract': call.toJson(),
            'captures': captures,
          })
        ],
        root: 1,
        locals: {'count': ValueType.integer});
Map<String, ValueOperation> operations(
        [NativeBindingContract contract = call]) =>
    {
      'native.call': NativeCallValueOperation({'makeKey': contract})
    };

void main() {
  test('call declarations include implementation identity and fail closed', () {
    expect(NativeBindingContract.fromJson(call.toJson()), call);
    final changed = NativeBindingContract(
        type: call.type,
        call: NativeCallContract(
            inputs: call.call!.inputs,
            captures: call.call!.captures,
            result: native,
            implementation: 'key-body-v2'));
    expect(changed, isNot(call));
    final schema = SurfaceScreenHostDataSchema(
        {'makeKey': const SurfaceScreenHostDataNativeBindingShapeV1(call)});
    final registry = nativeCallOperations(schema, {});
    expect(() => program().validate(operations: registry), returnsNormally);
    expect(() => program().validate(operations: operations(changed)),
        throwsFormatException);
    expect(() => program().validate(), throwsFormatException);
    expect(
        () => program(captures: {'counter': 'missing'})
            .validate(operations: registry),
        throwsFormatException);
    expect(() => program(captures: {}).validate(operations: registry),
        throwsFormatException);
    expect(
        () => program(result: ValueType.string).validate(operations: registry),
        throwsFormatException);
    expect(valueProgramRequiredCapability(program(), operations: registry), 24);
    expect(
        valueProgramRequiredCapability(const ValueProgram(
            nodes: [ValueNode('literal', ValueType.integer, value: 1)],
            root: 0)),
        19);
  });
  test('native literals, implicit equality and string conversion are refused',
      () {
    expect(ValueType.fromJson(native.toJson()).accepts(native), isTrue);
    expect(native.accepts(const ValueType.native('flutter.Color')), isFalse);
    expect(
        () => const ValueProgram(nodes: [
              ValueNode('literal', native, value: {'type': 'flutter.Key'})
            ], root: 0)
                .validate(),
        throwsFormatException);
    expect(
        () => const ValueProgram(nodes: [
              ValueNode(
                  'literal', ValueType.native('flutter.Key', nullable: true),
                  value: null)
            ], root: 0)
                .validate(),
        throwsFormatException);
    expect(
        () => const ValueProgram(
            nodes: [
              ValueNode('parameter', ValueType('list', item: native),
                  name: 'keys')
            ],
            root: 0,
            parameters: {'keys': ValueType('list', item: native)}).validate(),
        throwsFormatException);
    for (final op in ['==', '!=', 'string']) {
      final value = ValueProgram(
          nodes: [
            const ValueNode('parameter', native, name: 'key'),
            ValueNode(op, op == 'string' ? ValueType.string : ValueType.boolean,
                inputs: op == 'string' ? [0] : [0, 0]),
          ],
          root: 1,
          parameters: {'key': native});
      expect(value.validate, throwsFormatException, reason: op);
    }
  });
  test('nativeLocal must belong to the declared lexical frame', () {
    final reference = {
      'kind': 'nativeLocal',
      'slot': 'key',
      'type': 'flutter.Key',
      'nullable': false
    };
    Map<String, Object?> envelope(Map<String, Object?> value) => {
          'version': 1,
          'program': const BuilderProgram(
                  values: ValueProgram(
                      nodes: [
                        ValueNode('literal', ValueType.integer, value: 1)
                      ],
                      root: 0,
                      locals: {'key': native}),
                  result: BuilderResult.body(0),
                  bodyCount: 1)
              .encode(),
          'captures': <String, Object?>{},
          'bodies': [
            rfw.WidgetBuilderDeclaration(
                'frame', rfw.ConstructorCall('Body', {'key': value}))
          ],
        };
    expect(
        RfwProgramScope([envelope(reference)], operations: {})
            .requiredCapability,
        24);
    expect(
        () => RfwProgramScope([reference], operations: {})
            .requireNativeValue(reference, native),
        throwsFormatException);
    for (final invalid in [
      {...reference, 'slot': 'other'},
      {...reference, 'type': 'flutter.Color'},
      {...reference, 'frameId': 'forged'}
    ]) {
      expect(
          () => RfwProgramScope([envelope(invalid)], operations: {})
              .requireNativeValue(invalid, native,
                  context:
                      const ValueOperationContext(locals: {'key': native})),
          throwsFormatException);
    }
  });
  test(
      'only declared historical native key outputs give reference records authority',
      () {
    const key = NativeBindingContract(type: 'flutter.Key');
    Map<String, Object?> envelope(Object? reference,
            {bool keyOutput = true, bool indirect = false}) =>
        {
          'version': 1,
          'program': BuilderProgram(
                  values: ValueProgram(
                      nodes: [
                        const ValueNode(
                            'capture', nativeBindingReferenceValueType,
                            name: 'key'),
                        if (indirect) ...[
                          const ValueNode('literal', ValueType.boolean,
                              value: true),
                          const ValueNode(
                              'conditional', nativeBindingReferenceValueType,
                              inputs: [1, 0, 0]),
                        ],
                      ],
                      root: indirect ? 2 : 0,
                      captures: {'key': nativeBindingReferenceValueType}),
                  result: BuilderResult.body(0,
                      key: keyOutput ? (indirect ? 2 : 0) : null,
                      keyType: keyOutput ? 'nativeBinding' : 'Object'),
                  bodyCount: 1)
              .encode(),
          'captures': {'key': reference},
          'bodies': [
            const rfw.WidgetBuilderDeclaration(
                'frame', rfw.ConstructorCall('Text', {'text': 'Hi'}))
          ],
        };
    final valid =
        RfwProgramScope([envelope(key.reference('key'))], operations: {});
    expect(valid.nativeBindings, {'key': key});
    expect(valid.requiredCapability, 24);
    final ordinary = RfwProgramScope(
        [envelope(key.reference('key'), keyOutput: false)],
        operations: {});
    expect(ordinary.nativeBindings, isEmpty);
    expect(ordinary.requiredCapability, lessThan(24));
    for (final invalid in [
      {...key.reference('key'), 'extra': 1},
      const NativeBindingContract(type: 'flutter.Color').reference('key'),
      rfw.DataReference(['context', 'unproved']),
    ]) {
      expect(() => RfwProgramScope([envelope(invalid)], operations: {}),
          throwsFormatException);
    }
    expect(
        () => RfwProgramScope([envelope(key.reference('key'), indirect: true)],
            operations: {}),
        throwsFormatException);
  });
  test(
      'actual native call use is tracked separately from installed declarations',
      () {
    final envelope = {
      'version': 1,
      'program': program().encode(),
      'captures': <String, Object?>{}
    };
    final scope = RfwProgramScope([envelope], operations: operations());
    expect(scope.nativeCalls, {'makeKey': call});
    expect(scope.requiredCapability, 24);
    expect(
        RfwProgramScope([const rfw.ConstructorCall('Text', {})],
                operations: operations())
            .requiredCapability,
        1);
  });
  test('native captures require the original declared host binding', () {
    const key = NativeBindingContract(type: 'flutter.Key');
    final schema = SurfaceScreenHostDataSchema(
        {'key': const SurfaceScreenHostDataNativeBindingShapeV1(key)});
    const value = ValueProgram(
        nodes: [ValueNode('capture', native, name: 'key')],
        root: 0,
        captures: {'key': native});
    rfw.RemoteWidgetLibrary library(String input) =>
        rfw.RemoteWidgetLibrary(const [], [
          rfw.WidgetDeclaration(
              'Root',
              null,
              rfw.ConstructorCall('Text', {
                'text': {
                  'version': 1,
                  'program': value.encode(),
                  'captures': {
                    'key': rfw.DataReference(['context', input])
                  }
                }
              }))
        ]);
    expect(
        surfaceScreenContractGaps(library('key'),
            events: SurfaceScreenEventSchema(events: const []),
            context: schema),
        isEmpty);
    expect(
        () => surfaceScreenContractGaps(library('missing'),
            events: SurfaceScreenEventSchema(events: const []),
            context: schema),
        throwsFormatException);
  });
}
