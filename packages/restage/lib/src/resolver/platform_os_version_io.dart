import 'package:device_info_plus/device_info_plus.dart';

import 'surface_delivery_observations.dart'
    show normalizeOsVersionOrdinal, parseMarketingMajorVersion;

/// The operating-system version a platform reports as one ordinal: the
/// marketing major on Apple platforms and the API level on Android.
Future<int?> readPlatformOsVersion(String platform) async {
  final device = DeviceInfoPlugin();
  return switch (platform) {
    'android' =>
      normalizeOsVersionOrdinal((await device.androidInfo).version.sdkInt),
    'ios' => parseMarketingMajorVersion((await device.iosInfo).systemVersion),
    'macos' => normalizeOsVersionOrdinal((await device.macOsInfo).majorVersion),
    _ => null,
  };
}
