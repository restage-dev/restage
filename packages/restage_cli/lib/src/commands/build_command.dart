import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/build_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';

/// Parent of the render-bundle build commands.
final class BuildCommand extends Command<int> {
  BuildCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    RenderBundleArtifactBuilder? builder,
  }) {
    addSubcommand(
      BuildPushCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
        builder: builder,
      ),
    );
  }

  @override
  String get name => 'build';

  @override
  String get description => 'Build and upload an isolated render bundle.';
}
