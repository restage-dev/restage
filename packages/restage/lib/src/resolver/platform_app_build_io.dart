import 'package:package_info_plus/package_info_plus.dart';

/// The app build number this platform reports.
Future<String?> readPlatformAppBuildNumber() async =>
    (await PackageInfo.fromPlatform()).buildNumber;

/// The app display version this platform reports, such as `2.4.1`.
Future<String?> readPlatformAppVersion() async =>
    (await PackageInfo.fromPlatform()).version;
