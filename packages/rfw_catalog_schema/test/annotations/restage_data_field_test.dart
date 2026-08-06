import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

class _ParameterAnnotatedValue {
  const _ParameterAnnotatedValue(
    @RestageDataField(description: 'Parameter description.') this.parameter,
  );

  final String parameter;
}

class _FieldAnnotatedValue {
  const _FieldAnnotatedValue(this.field);

  @RestageDataField(description: 'Field description.')
  final String field;
}

class _GetterAnnotatedValue {
  const _GetterAnnotatedValue(this.value);

  final String value;

  @RestageDataField(description: 'Getter description.')
  String get exposed => value;
}

void main() {
  test('RestageDataField is a narrow const description annotation', () {
    const annotation = RestageDataField(description: 'Nested value.');

    expect(annotation.description, 'Nested value.');
    expect(
      const [
        _ParameterAnnotatedValue('parameter'),
        _FieldAnnotatedValue('field'),
        _GetterAnnotatedValue('getter'),
      ].map((value) => value.runtimeType),
      hasLength(3),
      reason: 'parameter, field, and getter targets must all compile',
    );
  });
}
