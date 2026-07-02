import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/auth_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// Print the signed-in identity plus the current project config context.
class StatusCommand extends Command<int> {
  /// Construct a status command.
  StatusCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser.addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      help: 'Directory to start the restage_config.yaml search from.',
    );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'status';

  @override
  String get description => 'Print sign-in and active project context.';

  @override
  Future<int> run() async {
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln('Not signed in. Run `restage login`.');
      return 1;
    }

    final loaded = await loadRestageConfig(
      from: Directory(argResults?['directory'] as String? ?? '.'),
    );
    final Uri apiEndpoint;
    try {
      apiEndpoint = resolveApiEndpoint(
        config: loaded?.config,
        credential: credential,
      );
    } on EndpointConfigurationException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }

    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: apiEndpoint,
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }

    try {
      final user = await AuthApi(api).whoami();
      if (user == null) {
        _stderr.writeln(
          'The stored credential is no longer accepted by the server. '
          'Run `restage login` to refresh it.',
        );
        return 1;
      }

      _stdout.writeln('signed in as ${user.email ?? '(unknown identity)'}');
      _stdout.writeln('endpoint: $apiEndpoint');

      if (loaded == null) {
        _stdout.writeln('no restage_config.yaml - run `restage init`.');
        return 0;
      }

      final config = loaded.config;
      if (config.organization != null) {
        _stdout.writeln('organization: ${config.organization}');
      }
      _stdout.writeln('project: ${config.project}');
      _stdout.writeln('app: ${config.app}');
      if (config.defaultEnvironment != null) {
        _stdout.writeln('environment: ${config.defaultEnvironment}');
      }
      return 0;
    } on RestageApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        _stderr.writeln(
          'The stored credential is no longer accepted by the server. '
          'Run `restage login` to refresh it.',
        );
        return 1;
      }
      _stderr.writeln('Could not contact the backend: ${e.body}');
      return 2;
    } on SocketException catch (e) {
      _stderr.writeln('Could not contact the backend: $e');
      return 2;
    } finally {
      if (_httpClient == null) api.close();
    }
  }
}
