import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/build_list_command.dart';
import 'package:restage_cli/src/commands/build_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';

/// Parent of the render-bundle build commands.
final class BuildCommand extends Command<int> {
  BuildCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    RenderBundleArtifactBuilder? builder,
    RenderBundleCatalogProducer? catalog,
    BundleSourceReader? source,
    ReleaseRecorderOpener? openRecorder,
    RenderBundlePushReceipt? recordReceipt,
    Uri? defaultEndpoint,
    Map<String, String>? environment,
  }) {
    addSubcommand(
      BuildPushCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
        builder: builder,
        catalog: catalog,
        source: source,
        openRecorder: openRecorder,
        recordReceipt: recordReceipt,
        defaultEndpoint: defaultEndpoint,
        environment: environment,
      ),
    );
    addSubcommand(
      BuildListCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      "Build and upload the app's render bundle, or list its builds.";
}
