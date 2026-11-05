// A callback type id spells back as the Dart function type it names.
import 'package:restage_codegen/src/callback_type_id.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  for (final (id, dart) in [
    ('()->void', 'void Function()'),
    ('(dart:core#bool,dart:core#int)->void', 'void Function(bool, int)'),
    (
      '(package:flutter/src/gestures/tap.dart#TapDownDetails)->void',
      'void Function(TapDownDetails)',
    ),
    ('(dart:core#double)->dart:core#String', 'String Function(double)'),
    (
      '(dart:core#List<dart:core#Locale>?)->dart:ui#Locale?',
      'Locale? Function(List<Locale>?)',
    ),
  ]) {
    test('$id is $dart', () => expect(dartTypeOfCallbackTypeId(id), dart));
  }

  test('named parameters are refused', () {
    expect(
      () => dartTypeOfCallbackTypeId('(count:dart:core#int)->void'),
      throwsFormatException,
    );
  });

  test('a zero-argument FutureOr callback keeps design events', () {
    const entry = WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'Tile',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: '',
      flutterType: 'package:test_pkg/w.dart#Tile',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'onTap',
          type: PropertyType.event,
          description: '',
          callbackTypeId: '()->dart:async#FutureOr<void>',
        ),
      ],
    );
    expect(
      emitFactoryFunction(entry),
      contains("source.voidHandler(const <Object>['onTap'])"),
    );
  });

  test('a typed event emits the app callback read', () {
    const entry = WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'Pad',
      library: WidgetLibrary.core,
      category: WidgetCategory.input,
      description: '',
      flutterType: 'package:test_pkg/w.dart#Pad',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'onHover',
          type: PropertyType.event,
          description: '',
          callbackTypeId: '(dart:core#bool,dart:core#int)->void',
        ),
      ],
    );
    expect(
      emitFactoryFunction(entry),
      contains(
        "RestageDecoders.nativeCallback<void Function(bool, int)>("
        "source, const <Object>['onHover'], 'Pad.onHover')",
      ),
    );
  });
}
