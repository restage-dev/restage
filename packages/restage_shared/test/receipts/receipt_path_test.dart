import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('a receipt segment keeps ASCII letters, digits, dots and underscores',
      () {
    expect(receiptPathSegment('My App_2.0'), 'my-app_2.0');
    expect(
      receiptPathSegment('onboarding/welcome flow'),
      'onboarding-welcome-flow',
    );
  });

  test('every other character becomes one dash, whatever its encoding', () {
    expect(receiptPathSegment('café'), 'caf-');
    expect(receiptPathSegment('a😀b'), 'a-b');
  });

  test('an empty name is unnamed', () {
    expect(receiptPathSegment(''), 'unnamed');
  });
}
