import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

// Its name does not say Test, so the SDK talks to the platform as in an app.
final class _AppLikeBinding extends AutomatedTestWidgetsFlutterBinding {}

void main() {
  test('the platform keeps the choice of the last configure', () async {
    void configure({required bool analytics}) => Restage.configure(
          apiKey: 'rs_pk_test',
          baseUrl: 'https://example.com',
          analyticsEnabled: analytics,
          measurementEnabled: false,
          deliveryReceiptsEnabled: false,
        );
    // Before runApp: no binding yet.
    configure(analytics: true);
    final binding = _AppLikeBinding();
    final saved = <Object?>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('restage/early_request'),
      (call) async {
        if (call.method == 'saveChoice') saved.add(call.arguments);
        return null;
      },
    );
    configure(analytics: false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(saved, isNotEmpty);
    expect(saved.last, {
      'hosted': true,
      'analytics': false,
      'measurement': false,
    });
  });
}
