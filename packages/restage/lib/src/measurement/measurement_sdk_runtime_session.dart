import 'dart:math';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Runtime-owned build metadata, kept aligned with this package's pubspec.
const measurementReportedSdkVersion = '2.0.0';

/// Anonymous memory-only session shared by every root in one SDK target.
/// Switching back to a previously visited target never recovers its old nonce.
final class MeasurementSdkRuntimeSession {
  TargetCoordinate? _target;
  String? _nonce;

  String forTarget(TargetCoordinate target) {
    if (_target != target || _nonce == null) {
      final random = Random.secure();
      _nonce = List.generate(
              32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      _target = target;
    }
    return _nonce!;
  }

  void reset() {
    _target = null;
    _nonce = null;
  }
}
