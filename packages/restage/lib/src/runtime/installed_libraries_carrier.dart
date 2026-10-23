import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        SdkInstalledLibrariesV1,
        SdkInstalledLibraryV1,
        sdkInstalledLibrariesMaximumCarrierCharacters;
import 'package:restage_shared/restage_shared.dart' show InstalledCapability;

import 'builtin_catalog_capabilities.dart';
import 'library_runtime_registry.dart';

/// The base64url `sdkInstalledLibraries` report of the registered custom
/// widget libraries and build metadata, or null when they exceed its bounds.
///
/// Omitting the report leaves the server enrolling this build as before.
String? installedLibrariesCarrier({
  InstalledCapability? snapshot,
  String? appVersion,
}) {
  try {
    final report = SdkInstalledLibrariesV1(
      builtInCatalogVersion: snapshot?.builtInCatalogVersion ??
          RestageBuiltInCatalogCapabilities.currentVersion,
      appVersion: appVersion,
      libraries: [
        for (final library in snapshot?.installedLibraries ??
            LibraryRuntimeRegistry.installedSnapshot())
          SdkInstalledLibraryV1(
            namespace: library.namespace,
            version: library.version,
            compatibleSince: library.compatibleSince,
            generated: library.generated,
          ),
      ],
    );
    final carrier = base64UrlEncode(report.canonicalBytes).replaceAll('=', '');
    return carrier.length <= sdkInstalledLibrariesMaximumCarrierCharacters
        ? carrier
        : null;
  } on ArgumentError catch (error) {
    debugPrint('[restage] installed libraries not reported: ${error.message}');
    return null;
  }
}
