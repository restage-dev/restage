import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/surface_publish_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';

/// Parent of the surface subcommands.
///
/// An engagement surface (onboarding, message, survey) is authored in Dart,
/// compiled to a flow document plus per-screen blobs by the build step, and
/// published to the backend through the shared delivery substrate. Adding a
/// new surface-scoped command is a single `addSubcommand` call here.
class SurfaceCommand extends Command<int> {
  /// Construct a surface command group.
  SurfaceCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) {
    addSubcommand(
      SurfacePublishCommand(
        stdout: stdout,
        stderr: stderr,
        interactive: interactive,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get name => 'surface';

  @override
  String get description =>
      'Assemble and publish engagement surfaces (onboarding, message, '
      'survey) in the current project and app.';
}
