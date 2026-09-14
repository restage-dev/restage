import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test(
      'declared scalars preserve exact chosen values and reject unbounded inputs',
      () {
    final category = MeasurementDeclaredAnswerV1.category(
        questionId: 'reason',
        outcomeKey: 'survey.reason',
        propertyName: 'reason',
        categoryLabels: {'cost': 'Too expensive'});
    expect(category.capture('cost'), MeasurementCategoryAnswerV1('cost'));
    expect(category.capture('free form'), isNull);
    expect(category.capture(null), isNull);
    final integer = MeasurementDeclaredAnswerV1.integer(
        questionId: 'count',
        outcomeKey: 'survey.count',
        propertyName: 'count',
        minimum: '-2',
        maximum: '4');
    expect(integer.capture(-2), MeasurementIntegerAnswerV1('-2'));
    expect(integer.capture('4'), MeasurementIntegerAnswerV1('4'));
    expect(integer.capture('04'), isNull);
    expect(integer.capture(5), isNull);
    final decimal = MeasurementDeclaredAnswerV1.scaledDecimal(
        questionId: 'rating',
        outcomeKey: 'survey.rating',
        propertyName: 'rating',
        minimum: '-125',
        maximum: '125',
        scale: 2,
        unit: 'rating');
    expect(decimal.capture('-1.25'),
        MeasurementScaledAnswerV1(coefficient: '-125', scale: 2));
    expect(decimal.capture('1.2'),
        MeasurementScaledAnswerV1(coefficient: '120', scale: 2));
    expect(decimal.capture('1.251'), isNull);
    expect(decimal.capture('1.26'), isNull);
    expect(decimal.capture({'coefficient': '120', 'scale': 2}), isNull);
    expect(MeasurementDeclaredAnswerV1.fromJson(decimal.toJson()), decimal);
    expect(
        () => MeasurementDeclaredAnswerV1.fromJson(
            {...category.toJson(), 'arbitraryProperty': true}),
        throwsA(isA<CanonicalFormatException>()));
  });
}
