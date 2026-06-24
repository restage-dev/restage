import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/auth_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// Revoke the stored credential and remove the local credentials file.
///
/// Best-effort against the backend: if the server rejects or is
/// unreachable, the local file is still removed so the user is not
/// stranded with a credential the tool cannot use.
class LogoutCommand extends Command<int> {
  /// Construct a logout command.
  LogoutCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient;

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'logout';

  @override
  String get description =>
      'Revoke the stored credential and remove the local credentials '
      'file.';

  @override
  Future<int> run() async {
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stdout.writeln('Not signed in.');
      return 0;
    }
    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: Uri.parse(credential.endpoint),
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (e) {
      // Stored credential points at an insecure endpoint — never send
      // it. Still remove the local file so the user is not stranded.
      _stderr.writeln(e.toString());
      await store.delete();
      _stdout.writeln('Signed out (local credential removed).');
      return 0;
    }
    try {
      await AuthApi(api).logout();
    } on RestageApiException catch (e) {
      _stderr.writeln(
        'Server-side revoke failed (HTTP ${e.statusCode}); removing '
        'local credential anyway.',
      );
    } finally {
      if (_httpClient == null) api.close();
    }
    await store.delete();
    _stdout.writeln('Signed out.');
    return 0;
  }
}
