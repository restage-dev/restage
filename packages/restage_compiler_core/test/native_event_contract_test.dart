import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '',
    libraries: {},
    widgets: []);
const _event = PropertyEntry(
    wireId: WireId.unallocatedProperty,
    description: '',
    name: 'onPressed',
    type: PropertyType.event,
    required: false);
const _callback =
    NativeBindingContract(type: kNativeVoidCallbackType, nullable: true);

void main() {
  test('native events require an exact no-argument event slot and signature',
      () {
    final value = {
      'nativeEvent': _callback.reference('callback'),
      'measurement':
          const rfw.EventHandler(kMeasurementPublicationTapEventNameV1, {})
    };
    final scope = RfwProgramScope([value], operations: {});
    expect(validateRfwPropertyCallbacks(value, _event, _catalog, scope: scope),
        24);
    scope.requireNativeValue(value['nativeEvent'],
        const ValueType.native(kNativeVoidCallbackType, nullable: true));
    expect(scope.requiredCapability, 24);
    for (final invalid in [
      {
        'nativeEvent': const NativeBindingContract(type: '(int)->void')
            .reference('callback')
      },
      {'nativeEvent': _callback.reference('callback'), 'unexpected': 0},
      {
        'nativeEvent': _callback.reference('callback'),
        'measurement': const rfw.EventHandler('custom', {})
      },
      {'nativeEvent': 'callback'},
    ]) {
      expect(() => validateRfwPropertyCallbacks(invalid, _event, _catalog),
          throwsFormatException);
    }
    expect(
        () => validateRfwPropertyCallbacks(
            value,
            const PropertyEntry(
                wireId: WireId.unallocatedProperty,
                description: '',
                name: 'onChanged',
                type: PropertyType.event,
                required: false,
                callbackSignature: 'void Function(int)'),
            _catalog),
        throwsFormatException);
    expect(
        () => validateRfwPropertyCallbacks(
            value,
            const PropertyEntry(
                wireId: WireId.unallocatedProperty,
                description: '',
                name: 'value',
                type: PropertyType.scalarCallback,
                scalarContract: ScalarCallbackContract(
                    parameters: [ScalarCallbackParameter.valueKey],
                    nullableResult: true),
                required: false),
            _catalog),
        throwsFormatException);
  });

  test('inline spans admit only their installed no-argument recognizer slots',
      () {
    const property = PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'span',
        type: PropertyType.inlineSpan,
        description: '');
    for (final entry in kTextSpanRecognizerVoidCallbacks.entries) {
      final span = {
        'text': 'Tap',
        'children': [
          {
            'text': 'Child',
            'recognizer': {
              'kind': entry.key,
              for (final name in entry.value)
                name: {'nativeEvent': _callback.reference(name)}
            }
          }
        ]
      };
      expect(validateRfwPropertyCallbacks(span, property, _catalog), 24);
    }
    for (final name in ['onTapDown', 'onUnknown', 'text']) {
      final span = {
        'text': 'Tap',
        'recognizer': {
          'kind': 'tap',
          name: {'nativeEvent': _callback.reference('callback')}
        }
      };
      expect(validateRfwPropertyCallbacks(span, property, _catalog), 1);
    }
  });

  test(
      'native event programs require their installed implementation and lexical scope',
      () {
    const contract = NativeBindingContract(
        type: 'installed.call',
        call: NativeCallContract(
            inputs: [],
            captures: {'count': ValueType.integer},
            result: ValueType.native(kNativeVoidCallbackType),
            implementation: 'callback-v1'));
    final program = ValueProgram(
        nodes: [
          ValueNode(
              'native.call', const ValueType.native(kNativeVoidCallbackType),
              value: {
                'binding': 'factory',
                'contract': contract.toJson(),
                'captures': {'count': 'count'},
              })
        ],
        root: 0,
        outerLocals: {'count': ValueType.integer});
    final value = {
      'nativeEvent': {
        'version': 1,
        'program': program.encode(),
        'captures': <String, Object?>{}
      }
    };
    final operations = {
      'native.call': NativeCallValueOperation({'factory': contract})
    };
    expect(() => RfwProgramScope([value], operations: operations),
        throwsFormatException);
    expect(
        () => RfwProgramScope([value], operations: {}), throwsFormatException);
    final borrowed = {
      'nativeEvent': {
        'kind': 'nativeLocal',
        'slot': 'other',
        'type': kNativeVoidCallbackType,
        'nullable': false
      }
    };
    expect(
        () => RfwProgramScope([borrowed], operations: operations)
            .requireNativeValue(borrowed['nativeEvent'],
                const ValueType.native(kNativeVoidCallbackType)),
        throwsFormatException);
  });
}
