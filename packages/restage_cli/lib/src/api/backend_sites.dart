import 'dart:io';

import 'package:restage_cli/src/api/default_endpoint.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

export 'package:restage_shared/restage_shared.dart'
    show backendSites, defaultDocsOrigin;

/// Environment variable naming the backend for a new sign-in or a key.
const backendUrlVariable = 'RESTAGE_BACKEND_URL';

/// The backend Restage commands talk to: the `endpoint:` of [config], else the
/// stored sign-in, else [backendUrlVariable], else Restage Cloud.
Future<Uri> configuredBackend({
  RestageConfig? config,
  FileCredentialStore? credentialStore,
  Map<String, String>? environment,
}) async {
  if (_endpoint(config?.endpoint) case final fromConfig?) return fromConfig;
  try {
    final store = credentialStore ?? FileCredentialStore.atDefaultLocation();
    if (_endpoint((await store.read())?.endpoint) case final signedIn?) {
      return signedIn;
    }
  } on Object {
    // No readable sign-in; fall through to the environment.
  }
  final named = (environment ?? Platform.environment)[backendUrlVariable];
  return _endpoint(named) ?? Uri.parse(defaultRestageEndpoint);
}

Uri? _endpoint(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  return uri == null || !uri.hasAuthority ? null : uri;
}
