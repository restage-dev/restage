import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/delivery_input_budget.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_request_inputs.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

  setUp(() {
    Restage.debugReset();
    debugResetAppBuildOrdinal();
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(packageInfo, null);
    Restage.debugReset();
    debugResetAppBuildOrdinal();
  });

  testWidgets('a slow app-version read cannot hold the request past its budget',
      (tester) async {
    final platform = Completer<Map<String, Object?>>();
    var versionReads = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(packageInfo, (_) {
      versionReads++;
      return platform.future;
    });
    final budget = DeliveryInputBudget(const Duration(milliseconds: 20));
    addTearDown(budget.close);
    final pending = SurfaceRequestInputs.gather(
      budget: budget,
      surface: 'message',
      slug: 'welcome',
      sendAssignmentKey: false,
    );
    var completed = false;
    unawaited(pending.then((_) => completed = true));
    await tester.pump(const Duration(milliseconds: 21));
    expect(completed, isTrue);
    final inputs = await pending;
    expect(versionReads, 1);
    final report = SdkInstalledLibrariesV1.fromCanonicalBytes(base64Url.decode(
      base64Url.normalize(inputs.sdkInstalledLibraries!),
    ));
    expect(report.appVersion, isNull);
    expect(report.builtInCatalogVersion,
        inputs.installedCapability.builtInCatalogVersion);

    platform.complete({
      'appName': 'Example',
      'packageName': 'example.app',
      'version': '2.4.1',
      'buildNumber': '412',
      'buildSignature': '',
    });
    await tester.pump();
    expect(await readDeliveryAppVersion(), '2.4.1');
    expect(versionReads, 1);
  });
}
