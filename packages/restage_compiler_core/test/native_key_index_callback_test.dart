import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const contract =
    ScalarCallbackContract(parameters: [ScalarCallbackParameter.valueKey]);
Map<String, Object?> slot(ValueType type, {bool parameter = false}) => {
      'nativeKeyIndex': {
        'version': 1,
        'program': ValueProgram(
                nodes: [
              ValueNode(parameter ? 'parameter' : 'capture', type,
                  name: 'callback')
            ],
                root: 0,
                captures: parameter ? {} : {'callback': type},
                parameters: parameter ? {'callback': type} : {})
            .encode(),
        'captures': <String, Object?>{
          if (!parameter)
            'callback': NativeBindingContract(
                    type: type.nativeType ?? 'wrong', nullable: type.nullable)
                .reference('installed')
        },
      }
    };
void main() {
  test('raw native key callback preview requires its installed host', () {
    final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core:
              const LibraryInfo(version: '1', capabilityVersion: 24)
        },
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
                    name: 'callback',
                    type: PropertyType.scalarCallback,
                    description: 'Index callback',
                    scalarContract: contract,
                    constructorNullable: true)
              ])
        ]);
    rfw.RemoteWidgetLibrary library(Object value) =>
        rfw.RemoteWidgetLibrary(const [], [
          rfw.WidgetDeclaration(
              'Root', null, rfw.ConstructorCall('Host', {'callback': value}))
        ]);
    expect(
        nativeBindingsNeedInstalledHost(
            library(slot(const ValueType.native('flutter.ChildIndexGetter'))),
            catalog),
        isTrue);
    const scalar = ValueProgram(
        nodes: [ValueNode('literal', ValueType.integer, value: 0)], root: 0);
    expect(
        nativeBindingsNeedInstalledHost(
            library({
              'version': 1,
              'program': scalar.encode(),
              'captures': <String, Object?>{}
            }),
            catalog),
        isFalse);
  });

  for (final nullable in [false, true]) {
    test(
        'native key callback validates exact nominal result nullable=$nullable',
        () {
      final value = slot(
          ValueType.native('flutter.ChildIndexGetter', nullable: nullable));
      final scope = RfwProgramScope([value], operations: {});
      expect(() => validateRfwScalarContract(value, contract, scope: scope),
          returnsNormally);
      expect(
          scope.nativeBindings['installed'],
          NativeBindingContract(
              type: 'flutter.ChildIndexGetter', nullable: nullable));
    });
  }
  test(
      'native key callback refuses another nominal value, scalar, parameters and slot',
      () {
    for (final type in [
      const ValueType.native('flutter.Key'),
      ValueType.string,
      ValueType.nullType
    ]) {
      expect(() => validateRfwScalarContract(slot(type), contract),
          throwsFormatException);
    }
    final value = slot(const ValueType.native('flutter.ChildIndexGetter'));
    expect(() => validateRfwScalarContract({...value, 'extra': true}, contract),
        throwsFormatException);
    expect(
        () => validateRfwScalarContract(
            value,
            const ScalarCallbackContract(
                parameters: [ScalarCallbackParameter.itemIndex])),
        throwsFormatException);
    expect(
        () => validateRfwScalarContract(
            slot(const ValueType.native('flutter.ChildIndexGetter'),
                parameter: true),
            contract),
        throwsFormatException);
  });
  test(
      'native reconciliation metadata refuses scalar and different native keys',
      () {
    for (final type in [
      ValueType.string,
      const ValueType.native('flutter.Color')
    ]) {
      final program = BuilderProgram(
          values: ValueProgram(
              nodes: [ValueNode('capture', type, name: 'key')],
              root: 0,
              captures: {'key': type}),
          result: const BuilderResult.body(0, key: 0, keyType: 'nativeKey'),
          bodyCount: 1);
      expect(program.validate, throwsFormatException);
    }
    for (final nullable in [false, true]) {
      final type = ValueType.native('flutter.Key', nullable: nullable);
      final program = BuilderProgram(
          values: ValueProgram(
              nodes: [ValueNode('capture', type, name: 'key')],
              root: 0,
              captures: {'key': type}),
          result: const BuilderResult.body(0, key: 0, keyType: 'nativeKey'),
          bodyCount: 1);
      expect(program.validate, returnsNormally);
    }
  });
}
