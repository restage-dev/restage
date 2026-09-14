import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Assignment request API level compiled into the 2.0 SDK.
const int assignmentSdkApiLevel = 2;

/// Reads fixed platform and installed-build observations for hosted assignment.
Future<String?> readSurfaceAssignmentBuiltIns() async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          TargetPlatform.linux => 'linux',
          TargetPlatform.macOS => 'macos',
          TargetPlatform.windows => 'windows',
          TargetPlatform.fuchsia => null,
        };
  if (platform == null) return null;
  final package = await PackageInfo.fromPlatform();
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(package.buildNumber)) return null;
  final ordinal = int.tryParse(package.buildNumber);
  if (ordinal == null || ordinal > kMaximumPortableJsonInteger) return null;
  return base64UrlEncode(CanonicalJsonCodec.encode({
    'appBuildOrdinal': ordinal,
    'platform': platform,
    'sdkApiLevel': assignmentSdkApiLevel,
  })).replaceAll('=', '');
}
