import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_sdk_runtime_session.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

TargetCoordinate target(
        {int org = 1,
        int app = 2,
        int environment = 3,
        int named = 4,
        RuntimePlane plane = RuntimePlane.sandbox}) =>
    TargetCoordinate(
        organizationId: OrganizationId(org),
        appId: ApplicationId(app),
        environmentTargetId: EnvironmentTargetId(environment),
        namedEnvironmentId: NamedEnvironmentId(named),
        runtimePlane: plane);

void main() {
  test(
      'one runtime shares target session, every transition rotates including switch-back',
      () {
    final runtime = MeasurementSdkRuntimeSession();
    final first = runtime.forTarget(target());
    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(runtime.forTarget(target()), first);
    for (final other in [
      target(org: 2),
      target(app: 3),
      target(environment: 4),
      target(named: 5),
      target(plane: RuntimePlane.live)
    ]) {
      final before = runtime.forTarget(target());
      final changed = runtime.forTarget(other);
      expect(changed, isNot(before));
      expect(runtime.forTarget(target()), isNot(before));
    }
    final beforeReset = runtime.forTarget(target());
    runtime.reset();
    expect(runtime.forTarget(target()), isNot(beforeReset));
    expect(MeasurementSdkRuntimeSession().forTarget(target()),
        isNot(runtime.forTarget(target())));
  });
  test('reported runtime version matches actual package version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
        RegExp(r'^version: (.+)$', multiLine: true)
            .firstMatch(pubspec)!
            .group(1),
        measurementReportedSdkVersion);
  });
}
