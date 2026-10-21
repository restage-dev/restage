import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/package_info');

  testWidgets('a failed app-version read can be retried', (tester) async {
    var reads = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      if (++reads == 1) throw PlatformException(code: 'unavailable');
      return {
        'appName': 'Example',
        'packageName': 'example.app',
        'version': '2.4.1',
        'buildNumber': '412',
        'buildSignature': '',
      };
    });

    expect(await readDeliveryAppVersion(), isNull);
    expect(await readDeliveryAppVersion(), '2.4.1');
    expect(reads, 2);
  });
}
