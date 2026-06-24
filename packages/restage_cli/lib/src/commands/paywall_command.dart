import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/paywall_list_command.dart';
import 'package:restage_cli/src/commands/paywall_publish_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';

/// Parent of the paywall subcommands.
///
/// `package:args`'s [CommandRunner] dispatches to a [Command] which can
/// itself host subcommands — the conventional shape for a noun-verb CLI
/// (`restage paywall list`, `restage paywall publish`, …). Adding a new
/// paywall-scoped command is a single `addSubcommand` call here.
class PaywallCommand extends Command<int> {
  /// Construct a paywall command group.
  PaywallCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) {
    addSubcommand(
      PaywallListCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
    addSubcommand(
      PaywallPublishCommand(
        stdout: stdout,
        stderr: stderr,
        interactive: interactive,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get name => 'paywall';

  @override
  String get description =>
      'Inspect and publish paywalls in the current project and app.';
}
