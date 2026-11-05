// An event slot typed by the catalog's callbackTypeId takes the app's callback
// of exactly that type; a design event or a measured value-returning callback
// is refused.
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

const _hover = '(dart:core#bool,dart:core#int)->void';
const _format = '(dart:core#double)->dart:core#String';

PropertyEntry _event(String typeId, {String? signature}) => PropertyEntry(
    wireId: WireId.unallocatedProperty,
    description: '',
    name: 'onEvent',
    type: PropertyType.event,
    callbackSignature: signature,
    callbackTypeId: typeId);

Map<String, Object?> _native(String type, {bool measured = false}) => {
      'nativeEvent':
          NativeBindingContract(type: type, nullable: true).reference('cb'),
      if (measured)
        'measurement':
            const rfw.EventHandler(kMeasurementPublicationTapEventNameV1, {}),
    };

int _validate(Object? value, String typeId, {String? signature}) =>
    validateRfwPropertyCallbacks(
        value, _event(typeId, signature: signature), _catalog,
        scope: RfwProgramScope([value], operations: {}));

void main() {
  test('a two-argument slot takes a measured callback of its type', () {
    expect(_validate(_native(_hover, measured: true), _hover), 24);
    expect(() => _validate(_native('(dart:core#bool)->void'), _hover),
        throwsFormatException);
  });

  test('a value-returning slot takes an unmeasured callback of its type', () {
    expect(_validate(_native(_format), _format), 24);
  });

  test('a measured value-returning callback is refused', () {
    expect(() => _validate(_native(_format, measured: true), _format),
        throwsFormatException);
  });

  test('a design event cannot fill a typed slot', () {
    expect(() => _validate(const rfw.EventHandler('hover', {}), _hover),
        throwsFormatException);
    expect(_validate(const rfw.EventHandler('tap', {}), '()->void'), 1);
  });

  test('design events keep working where they did before', () {
    // A declared payload, as on Switch.onChanged.
    expect(
        _validate(
            const rfw.EventHandler('toggle', {}), '(dart:core#bool)->void',
            signature: 'ValueChanged<bool>'),
        1);
    // A zero-argument callback, as on CupertinoListTile.onTap; the app's
    // void closure still fills it.
    const futureOr = '()->dart:async#FutureOr<void>';
    expect(_validate(const rfw.EventHandler('tap', {}), futureOr), 1);
    expect(_validate(_native('()->void'), futureOr), 24);
  });
}
