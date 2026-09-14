import 'package:package_info_plus/package_info_plus.dart';

/// The app build number this platform reports.
Future<String?> readPlatformAppBuildNumber() async =>
    (await PackageInfo.fromPlatform()).buildNumber;
