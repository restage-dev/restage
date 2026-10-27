import 'dart:io';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

Map<String, Object?> _envelope(ValueType type,
    {bool collection = false, bool scalar = false, String name = 'arg0'}) {
  final values = ValueProgram(
      nodes: [ValueNode('parameter', type, name: name)],
      root: 0,
      parameters: {name: type});
  return {
    'version': 1,
    'program': scalar
        ? values.encode()
        : BuilderProgram(
                values: values,
                result: const BuilderResult.body(0),
                bodyCount: 1,
                collection: collection,
                nullableResult: collection)
            .encode(),
    'captures': <String, Object?>{},
    if (!scalar)
      'bodies': [
        rfw.WidgetBuilderDeclaration(
            'frame', const rfw.ConstructorCall('SizedBox', {}))
      ],
  };
}

void main() {
  final catalog = decodeCatalog(
      File('../restage_core/lib/src/widget_catalog/catalog.json')
          .readAsStringSync());
  final property = catalog.widgets
      .singleWhere((widget) => widget.name == 'LayoutBuilder')
      .properties
      .singleWhere((property) => property.name == 'builder');
  test('native context envelope is qualified by the actual catalog callback',
      () {
    final envelope = _envelope(builderContextNativeValueType);
    final scope = RfwProgramScope([envelope], operations: {});
    expect(scope.requiredCapability, 24);
    expect(
        validateRfwPropertyCallbacks(envelope, property, catalog, scope: scope),
        19);
    for (final contract in [
      null,
      const WidgetBuilderContract(parameters: []),
      const WidgetBuilderContract(
          parameters: [WidgetBuilderParameter.itemIndex]),
      const WidgetBuilderContract(parameters: [
        WidgetBuilderParameter.buildContext,
        WidgetBuilderParameter.buildContext
      ]),
    ]) {
      final invalid = PropertyEntry(
          wireId: property.wireId,
          name: property.name,
          type: PropertyType.widgetBuilder,
          description: 'Callback',
          builderContract: contract);
      expect(
          () => validateRfwPropertyCallbacks(envelope, invalid, catalog,
              scope: scope),
          throwsFormatException);
    }
    final scalar = PropertyEntry(
        wireId: property.wireId,
        name: property.name,
        type: PropertyType.scalarCallback,
        description: 'Key callback',
        scalarContract: const ScalarCallbackContract(
            parameters: [ScalarCallbackParameter.valueKey]));
    expect(
        () => validateRfwPropertyCallbacks(envelope, scalar, catalog,
            scope: scope),
        throwsFormatException);
  });

  test(
      'generic decoding refuses forged nullable scalar and collection contexts',
      () {
    for (final envelope in [
      _envelope(const ValueType.native('forged.BuildContext')),
      _envelope(ValueType.native(builderContextNativeValueType.nativeType!,
          nullable: true)),
      _envelope(ValueType.string),
      _envelope(builderContextNativeValueType, collection: true),
      _envelope(builderContextNativeValueType, scalar: true),
      _envelope(builderContextNativeValueType, name: 'arg2'),
    ]) {
      expect(() => RfwProgramScope([envelope], operations: {}),
          throwsFormatException);
    }
    final wrongPosition =
        _envelope(builderContextNativeValueType, name: 'arg1');
    expect(() => validateRfwPropertyCallbacks(wrongPosition, property, catalog),
        throwsFormatException);
  });
}
