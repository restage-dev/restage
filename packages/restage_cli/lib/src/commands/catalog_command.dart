import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/catalog_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// Parent of the widget catalog subcommands.
class CatalogCommand extends Command<int> {
  /// Construct a catalog command group.
  CatalogCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) {
    addSubcommand(
      CatalogPushCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get name => 'catalog';

  @override
  String get description =>
      'Upload the widget catalog for the current project and app.';
}
