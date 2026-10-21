import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

/// Lists live versions a local build's library contracts would stop
/// rendering, the same as `restage surface check-libraries`.
final checkLibrariesTool = Tool(
  name: 'restage_check_libraries',
  description:
      "List every version of the app in use, in every environment, that this "
      "build's custom widget library contracts would stop rendering: what a "
      'surface serves, what a delivery rule routes to, and what a running '
      'experiment arm serves. Reads the contract snapshots pushes recorded in '
      '.restage/library-contracts and the last build\'s drafts in '
      '.restage/build/library-contracts of the project directory. An empty list '
      'means all versions in use render on this build.',
  inputSchema: Schema.object(
    properties: localProjectProperties(),
    required: ['projectDirectory'],
  ),
);

/// Reads the local snapshots and the live versions, then compares them.
Future<CallToolResult> handleCheckLibraries(
  ToolContext ctx,
  CallToolRequest request,
) async {
  final directory = Directory(request.str('projectDirectory'));
  final root = await libraryContractRoot(directory);
  final Map<String, int> since;
  try {
    since = localCompatibleSince(root);
  } on FormatException catch (error) {
    return mcpError(error.message);
  }
  if (since.isEmpty) {
    return jsonResult(<String, Object?>{'breaks': const <Object?>[]});
  }
  final config = (await loadRestageConfig(from: directory))?.config;
  final project = request.optStr('projectSlug') ?? config?.project;
  final app = request.optStr('appSlug') ?? config?.app;
  if (project == null || app == null) {
    return mcpError(
      'Name projectSlug and appSlug, or add a restage_config.yaml to the '
      'project directory.',
    );
  }
  return ctx.authed('checking library contracts', (api) async {
    final live = await LibraryRequirementsApi(api).liveLibraryRequirements(
      project: project,
      app: app,
      organizationId: request.optInt('organizationId'),
    );
    return jsonResult(<String, Object?>{
      'breaks': libraryBreaksJson(
        findLibraryBreaks(live: live, compatibleSince: since),
      ),
    });
  });
}

/// Records a package's drafted library contracts, the same as
/// `restage library record`.
final recordLibrariesTool = Tool(
  name: 'restage_record_libraries',
  description:
      "Record the custom widget library contracts the package's last build "
      'drafted, so the package can be published with them. An app records '
      'its own when a surface that uses them is pushed. A version recorded '
      'before stays as it is. Fails when the build drafted nothing; run '
      '`dart run build_runner build` in the package first.',
  inputSchema: Schema.object(
    properties: {'projectDirectory': projectDirectoryProperty},
    required: ['projectDirectory'],
  ),
);

/// Records the drafts under the package that holds the project directory.
Future<CallToolResult> handleRecordLibraries(CallToolRequest request) async {
  final root = libraryPackageRoot(Directory(request.str('projectDirectory')));
  final LibraryRecordResult result;
  try {
    result = recordLibraryDrafts(root);
  } on FormatException catch (error) {
    return mcpError(error.message);
  } on IOException catch (error) {
    return mcpError('The library contracts could not be recorded: $error');
  }
  if (result.isEmpty) {
    return mcpError(
      'No library contracts in .restage/build/library-contracts. Run '
      '`dart run build_runner build` in the package first.',
    );
  }
  return jsonResult(libraryRecordJson(result));
}
