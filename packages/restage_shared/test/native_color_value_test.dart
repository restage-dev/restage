import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('exact color literals and constructors enforce their closed types', () {
    final literal = ValueProgram(nodes: [
      ValueNode('literal', colorValueType, value: argbColorValue(0xff123456))
    ], root: 0);
    literal.validate();
    for (final name in canonicalMaterialColorNames) {
      ValueProgram(nodes: [
        ValueNode('literal', colorValueType,
            value: {...argbColorValue(0xff123456), 'material': name})
      ], root: 0)
          .validate();
    }
    for (final value in [
      {'a': 1.0},
      {...argbColorValue(0xff123456), 'unexpected': 0},
      {...argbColorValue(0xff123456), 'r': 'red'},
      {...argbColorValue(0xff123456), 'material': 'custom'},
    ]) {
      expect(
          () => ValueProgram(
                  nodes: [ValueNode('literal', colorValueType, value: value)],
                  root: 0)
              .validate(),
          throwsFormatException);
    }
    const packed = ValueProgram(nodes: [
      ValueNode('literal', ValueType.integer, value: 0xff123456),
      ValueNode('argbColor', colorValueType, inputs: [0])
    ], root: 1);
    packed.validate();
    expect(
        () => const ValueProgram(nodes: [
              ValueNode('literal', ValueType.real, value: 1.0),
              ValueNode('argbColor', colorValueType, inputs: [0])
            ], root: 1)
                .validate(),
        throwsFormatException);
    expect(
        () => const ValueProgram(nodes: [
              ValueNode('literal', ValueType.integer, value: 1),
              ValueNode('record', colorValueType, inputs: [0])
            ], root: 1)
                .validate(),
        throwsFormatException);
    expect(
        () => const ValueProgram(nodes: [
              ValueNode('literal', ValueType.integer, value: 1),
              ValueNode('argbColor', ValueType.integer, inputs: [0])
            ], root: 1)
                .validate(),
        throwsFormatException);
  });
}
