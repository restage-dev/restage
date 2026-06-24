import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/auth_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// Print the authenticated identity, or report "not signed in" / "the
/// credential has expired" with an appropriate exit code.
class WhoamiCommand extends Command<int> {
  /// Construct a whoami command.
  WhoamiCommand({
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
  String get name => 'whoami';

  @override
  String get description => 'Print the authenticated identity.';

  @override
  Future<int> run() async {
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln('Not signed in. Run `restage login`.');
      return 1;
    }
    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: Uri.parse(credential.endpoint),
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
      _stdout.writeln(user.email ?? '(unknown identity)');
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
    } finally {
      if (_httpClient == null) api.close();
    }
  }
}
