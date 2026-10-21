import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/durable_state.dart';
import 'package:restage_shared/restage_shared.dart'
    show backendSites, defaultDocsOrigin;
import 'package:yaml/yaml.dart';

/// The docs origin for the backend that `endpoint:` in the package's
/// restage_config.yaml names; the published docs without one.
Future<String> projectDocsOrigin(BuildStep buildStep) async {
  final package = buildStep.inputId.package;
  final asset = AssetId(package, 'restage_config.yaml');
  String? source;
  if (await buildStep.canRead(asset)) {
    source = await buildStep.readAsString(asset);
  } else if (await restagePackageRoot(package) case final root?) {
    final file = File.fromUri(root.resolve('restage_config.yaml'));
    if (file.existsSync()) source = file.readAsStringSync();
  }
  return docsOriginForConfig(source);
}

/// The docs origin for the `endpoint:` in a restage_config.yaml [source].
String docsOriginForConfig(String? source) {
  if (source == null) return defaultDocsOrigin;
  try {
    final endpoint = (loadYaml(source) as Map?)?['endpoint'];
    final uri = endpoint is String ? Uri.tryParse(endpoint.trim()) : null;
    return uri == null ? defaultDocsOrigin : backendSites(uri).docs;
  } on Object {
    // A config the CLI cannot read either; the published docs still help.
    return defaultDocsOrigin;
  }
}
