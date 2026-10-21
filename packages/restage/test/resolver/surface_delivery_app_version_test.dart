import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';

void main() {
  setUp(debugResetAppBuildOrdinal);
  tearDown(debugResetAppBuildOrdinal);

  for (final (label, version, expected) in [
    ('valid', '2.4.1', '2.4.1'),
    ('empty', '', null),
    ('oversized', 'x' * 65, null),
    ('control character', '2.4\u0000.1', null),
  ]) {
    testWidgets('a cached $label app version is reusable across async contexts',
        (tester) async {
      _setVersion(version);
      expect(await tester.runAsync(readDeliveryAppVersion), expected);
      _setVersion('9.9.9');

      var completed = false;
      String? result;
      final read = readDeliveryAppVersion().then((value) {
        result = value;
        completed = true;
      });
      await tester.pump();

      expect(completed, isTrue);
      expect(result, expected);
      await read;
    });
  }
}

void _setVersion(String version) => PackageInfo.setMockInitialValues(
      appName: 'Example',
      packageName: 'example.app',
      version: version,
      buildNumber: '412',
      buildSignature: '',
    );
