import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/catalog_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/render_bundles/package_resolution.dart';

/// What the uploaded catalog is for.
const catalogPurpose =
    "The widget catalog lists your app's own widgets in the dashboard "
    "editor's palette and lets the editor draw placeholders for them. "
    'Devices never read it, and dashboard previews draw the real widgets '
    'from a build push.';

/// The generated widget catalog under [projectRoot], or null when the code
/// generator has not written one.
File? findGeneratedWidgetCatalog(Directory projectRoot) {
  final candidates = [
    p.join(projectRoot.path, '.restage', 'build', 'widget_catalog'),
    if (_packageName(projectRoot) case final package?)
      p.join(
        projectRoot.path,
        '.dart_tool',
        'build',
        'generated',
        package,
        'lib',
        'src',
        'widget_catalog',
      ),
  ];
  for (final directory in candidates) {
    final file = File(p.join(directory, 'catalog.json'));
    if (file.existsSync()) return file;
  }
  return null;
}

String? _packageName(Directory projectRoot) {
  try {
    return readProjectPackageName(projectRoot);
  } on StateError {
    return null;
  }
}

/// Upload the generated widget catalog when one exists.
class CatalogPushCommand extends Command<int> {
  /// Construct a catalog push command.
  CatalogPushCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser
      ..addOption(
        'project',
        help: 'Project slug (overrides restage_config.yaml).',
      )
      ..addOption('app', help: 'App slug (overrides restage_config.yaml).')
      ..addOption(
        'organization',
        help: 'Organization slug (overrides restage_config.yaml).',
      )
      ..addOption('organization-id', hide: true)
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help:
            'Directory to start the restage_config.yaml search from. '
            'Defaults to the current working directory.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'push';

  @override
  String get description =>
      'Upload the generated widget catalog for the current project and app.';

  @override
  Future<int> run() async {
    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loaded = await loadRestageConfig(from: directory);
    final projectRoot = loaded?.source.parent ?? directory.absolute;
    final catalogFile = findGeneratedWidgetCatalog(projectRoot);
    if (catalogFile == null) {
      _stdout.writeln(
        'No generated widget catalog in ${projectRoot.path}; nothing to push. '
        'Run `dart run build_runner build` first. An app that declares no '
        'widgets of its own with @RestageWidget has no catalog to push. '
        '$catalogPurpose',
      );
      return 0;
    }

    final project =
        (argResults?['project'] as String?) ?? loaded?.config.project;
    final app = (argResults?['app'] as String?) ?? loaded?.config.app;
    if (project == null || app == null) {
      _stderr.writeln(
        missingProjectContextSentence(
          hasConfig: loaded != null,
          projectMissing: project == null,
        ),
      );
      return 1;
    }

    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln(notSignedInSentence());
      return 1;
    }

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
      final configuredOrganization = await resolveConfiguredOrganization(
        api: api,
        config: loaded?.config,
        stderr: _stderr,
        preferredSlug: argResults?['organization'] as String?,
        organizationId: organizationIdOption(argResults),
      );
      if (configuredOrganization == null) return 1;

      final version = await CatalogApi(api).push(
        project: project,
        app: app,
        catalogJson: await catalogFile.readAsString(),
        organizationId: configuredOrganization.organizationId,
      );
      _stdout.writeln(
        'Uploaded widget catalog ${p.relative(catalogFile.path, from: projectRoot.path)} '
        'as version $version. $catalogPurpose',
      );
      return 0;
    } on RestageApiException catch (e) {
      return _handleApiException(e);
    } on SocketException catch (e) {
      _stderr.writeln('Could not upload the widget catalog: $e');
      return 2;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  int _handleApiException(RestageApiException e) {
    final catalog = decodeCatalogTypedException(e.body);
    if (catalog != null) {
      _stderr.writeln(renderCatalogException(catalog));
      return 1;
    }

    final outcome = renderApiError(e);
    _stderr.writeln(outcome.message);
    return outcome.exitCode;
  }
}
