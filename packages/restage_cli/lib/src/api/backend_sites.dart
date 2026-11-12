import 'dart:io';

import 'package:restage_cli/src/api/default_endpoint.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:restage_shared/restage_shared.dart' show isRestageCloudApi;

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

/// Where a new sign-in goes, and the file that named it when a project did.
typedef SignInBackend = ({Uri endpoint, String? namedBy});

/// Whether a project file may send a sign-in to [endpoint]: a Restage Cloud
/// API over https, or this machine.
bool isTrustedProjectBackend(Uri endpoint) {
  if (isRestageCloudApi(endpoint)) return true;
  final host = endpoint.host;
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  return InternetAddress.tryParse(host)?.isLoopback ?? false;
}

/// A project file names a server a sign-in is not sent to.
final class UntrustedSignInBackendException implements Exception {
  /// The server [namedBy] names.
  const UntrustedSignInBackendException(this.endpoint, this.namedBy);

  /// The server the project file names.
  final Uri endpoint;

  /// The file that names it.
  final String namedBy;

  /// The refusal, worded for the CLI or for the MCP server.
  String message({bool mcp = false}) =>
      '$namedBy names ${endpoint.origin}, which is not a Restage server, so '
      '${mcp ? 'restage_login' : '`restage login`'} will not send a sign-in '
      'there. Try `restage login --endpoint ${endpoint.origin}`'
      '${mcp ? ' in a terminal' : ''} if you trust that server.';

  @override
  String toString() => message();
}

/// The backend a new sign-in uses: [flag], else [backendUrlVariable], else
/// the backend the project at or above [from] names, else [fallback].
///
/// Throws [UntrustedSignInBackendException] when the project names a server
/// that [isTrustedProjectBackend] refuses.
Future<SignInBackend> signInBackend({
  String? flag,
  Map<String, String>? environment,
  Directory? from,
  required Uri fallback,
}) async {
  // A given value wins even when malformed, so the sign-in reports it.
  final named = (environment ?? Platform.environment)[backendUrlVariable];
  for (final given in [flag, named]) {
    if (given != null && given.isNotEmpty) {
      return (endpoint: Uri.parse(given), namedBy: null);
    }
  }
  final project = await projectBackend(from: from);
  if (project == null) return (endpoint: fallback, namedBy: null);
  if (!isTrustedProjectBackend(project.endpoint)) {
    throw UntrustedSignInBackendException(project.endpoint, project.namedBy);
  }
  return project;
}

/// The backend the project at or above [from] names: `endpoint` in the
/// restage_config.yaml commands use, else `base_url` for
/// restage_codegen:user_factories in the package's build.yaml.
Future<({Uri endpoint, String namedBy})?> projectBackend({
  Directory? from,
}) async {
  final start = (from ?? Directory.current).absolute;
  try {
    final loaded = await loadRestageConfig(from: start);
    if (_endpoint(loaded?.config.endpoint) case final endpoint?) {
      return (endpoint: endpoint, namedBy: 'restage_config.yaml');
    }
  } on RestageConfigFormatException {
    // A config that doesn't parse names nothing here; commands report it.
  }
  var directory = start;
  while (true) {
    final build = File(p.join(directory.path, 'build.yaml'));
    if (build.existsSync()) {
      final baseUrl = _endpoint(
        _string(_readYaml(build), const [
          'targets',
          r'$default',
          'builders',
          'restage_codegen:user_factories',
          'options',
          'base_url',
        ]),
      );
      if (baseUrl != null) return (endpoint: baseUrl, namedBy: 'build.yaml');
    }
    // build.yaml belongs to the package; its root ends the search.
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) return null;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

Object? _readYaml(File file) {
  try {
    return loadYaml(file.readAsStringSync());
  } on Object {
    return null;
  }
}

String? _string(Object? node, List<String> path) {
  var current = node;
  for (final key in path) {
    if (current is! YamlMap) return null;
    current = current[key];
  }
  return current is String ? current : null;
}
