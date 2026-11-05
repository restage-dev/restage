import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'dart:io';

import 'package:test/test.dart';

const _catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '',
    libraries: {},
    widgets: []);

PropertyEntry _event(String? signature) => PropertyEntry(
    wireId: WireId.unallocatedProperty,
    description: '',
    name: 'onChanged',
    type: PropertyType.event,
    required: false,
    callbackSignature: signature);

Map<String, Object?> _slot(String type) => {
      'nativeEvent':
          NativeBindingContract(type: type, nullable: true).reference('cb'),
      'measurement':
          const rfw.EventHandler(kMeasurementPublicationTapEventNameV1, {}),
    };

void main() {
  group('a typed native event', () {
    for (final (signature, type) in [
      (null, '()->void'),
      ('ValueChanged<bool>', '(dart:core#bool)->void'),
      ('ValueChanged<bool?>', '(dart:core#bool?)->void'),
      ('ValueChanged<DateTime>', '(dart:core#DateTime)->void'),
      (
        'ValueChanged<List<String>>',
        '(dart:core#List<dart:core#String>)->void'
      ),
    ]) {
      test('${signature ?? 'VoidCallback'} takes `$type` only', () {
        expect(eventNativeType(_event(signature)), type);
        expect(
            validateRfwPropertyCallbacks(
                _slot(type), _event(signature), _catalog,
                scope: RfwProgramScope([_slot(type)], operations: {})),
            24);
        for (final other in {
          '()->void',
          '(dart:core#bool)->void',
          '(dart:core#int)->void'
        }..remove(type)) {
          expect(
              () => validateRfwPropertyCallbacks(
                  _slot(other), _event(signature), _catalog),
              throwsFormatException,
              reason: other);
        }
      });
    }

    test('with a signature the grammar does not admit takes none', () {
      expect(eventNativeType(_event('void Function(int, int)')), isNull);
      expect(
          () => validateRfwPropertyCallbacks(_slot('(dart:core#int)->void'),
              _event('void Function(int, int)'), _catalog),
          throwsFormatException);
    });
  });

  group('a catalog callback type', () {
    PropertyEntry stub(String id) => PropertyEntry(
        wireId: WireId.unallocatedProperty,
        description: '',
        name: 'onEvent',
        type: PropertyType.event,
        required: false,
        callbackTypeId: id);

    test("the committed Checkbox.onChanged takes the app's bool? callback", () {
      final catalog = decodeCatalog(
          File('../restage_material/lib/src/widget_catalog/catalog.json')
              .readAsStringSync());
      final onChanged = catalog.widgets
          .singleWhere((widget) => widget.name == 'Checkbox')
          .properties
          .singleWhere((property) => property.name == 'onChanged');
      const id = '(dart:core#bool?)->void';
      expect(eventNativeType(onChanged), id);
      expect(
          validateRfwPropertyCallbacks(_slot(id), onChanged, _catalog,
              scope: RfwProgramScope([_slot(id)], operations: {})),
          24);
      expect(
          () => validateRfwPropertyCallbacks(
              _slot('(dart:core#bool)->void'), onChanged, _catalog),
          throwsFormatException);
    });

    for (final (name, id, other) in [
      (
        'void Function(int, int)?',
        '(dart:core#int,dart:core#int)->void',
        '(dart:core#int,dart:core#double)->void',
      ),
      (
        'ValueChanged<Axis>?',
        '(package:flutter/src/painting/basic_types.dart#Axis)->void',
        '(package:flutter/src/painting/basic_types.dart#Axis?)->void',
      ),
    ]) {
      test('$name takes its exact parameter types only', () {
        expect(
            validateRfwPropertyCallbacks(_slot(id), stub(id), _catalog,
                scope: RfwProgramScope([_slot(id)], operations: {})),
            24);
        expect(
            () =>
                validateRfwPropertyCallbacks(_slot(other), stub(id), _catalog),
            throwsFormatException);
      });
    }
  });
}
