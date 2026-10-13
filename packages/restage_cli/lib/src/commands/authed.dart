import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/config/config_target_check.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/discovery/context_discovery.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';

/// The sinks, prompt and injectables every command shares.
class CommandIo {
  /// Construct command I/O.
  const CommandIo({
    required this.stdout,
    required this.stderr,
    required this.interactive,
    this.credentialStore,
    this.httpClient,
  });

  /// Output sink.
  final StringSink stdout;

  /// Error sink.
  final StringSink stderr;

  /// Prompt source.
  final Interactive interactive;

  /// Credential store, or null for the default location.
  final FileCredentialStore? credentialStore;

  /// Injected HTTP client, or null for one per command.
  final http.Client? httpClient;
}

/// Register the selector options [scope] needs.
void addScopeOptions(ArgParser parser, OperationScope scope) {
  if (scope != OperationScope.account) {
    parser.addOption(
      'organization',
      help: 'Organization slug (overrides restage_config.yaml).',
    );
  }
  if (scope.index >= OperationScope.project.index) {
    parser.addOption(
      'project',
      help: 'Project slug (overrides restage_config.yaml).',
    );
  }
  if (scope.index >= OperationScope.app.index) {
    parser.addOption('app', help: 'App slug (overrides restage_config.yaml).');
  }
  if (scope == OperationScope.target) {
    parser.addOption(
      'env',
      help:
          'Environment slug (overrides restage_config.yaml '
          '`defaultEnvironment`).',
    );
  }
  parser.addOption(
    'directory',
    abbr: 'C',
    defaultsTo: '.',
    help: 'Directory to start the restage_config.yaml search from.',
  );
  if (scope == OperationScope.target) {
    addRuntimePlaneOption(parser);
    addOrganizationIdOption(parser);
  }
}

/// What an authenticated command body works with.
class AuthedContext {
  const AuthedContext._({
    required this.io,
    required this.api,
    required this.credential,
    required this.apiEndpoint,
    required this.config,
    this.organization,
    this.project,
    this.app,
    this.target,
    this.snapshot,
  });

  /// The command's I/O.
  final CommandIo io;

  /// Authenticated backend client.
  final RestageApi api;

  /// The stored credential.
  final Credential credential;

  /// Endpoint that may receive [credential].
  final Uri apiEndpoint;

  /// The loaded restage_config.yaml, if any.
  final RestageConfig? config;

  /// The resolved organization, below target scope.
  final OrganizationSummary? organization;

  /// The resolved project slug, below target scope.
  final String? project;

  /// The resolved app, below target scope.
  final AppSummary? app;

  /// The resolved exact target, at target scope.
  final LifecycleContext? target;

  /// The admitted scope used to resolve organization, project and app.
  final ProgrammaticScopeSnapshot? snapshot;

  /// Output sink.
  StringSink get stdout => io.stdout;

  /// Error sink.
  StringSink get stderr => io.stderr;

  /// The resolved organization id, when the scope names one.
  int? get organizationId =>
      target?.organizationId ?? organization?.organizationId;
}

/// Resolve credential, config, endpoint and [scope], then run [body].
///
/// Every backend refusal renders through [renderApiError]; the client is
/// closed afterwards unless it was injected.
Future<int> runAuthed(
  CommandIo io,
  ArgResults? argResults,
  OperationScope scope,
  Future<int> Function(AuthedContext ctx) body,
) async {
  final stderr = io.stderr;
  final store = io.credentialStore ?? FileCredentialStore.atDefaultLocation();
  final credential = await store.read();
  if (credential == null) {
    stderr.writeln(notSignedInSentence());
    return 1;
  }
  final loaded = await loadRestageConfig(
    from: Directory(_option(argResults, 'directory') ?? '.'),
  );
  final config = loaded?.config;
  final Uri apiEndpoint;
  final RestageApi api;
  try {
    apiEndpoint = resolveApiEndpoint(config: config, credential: credential);
    api = RestageApi(
      endpoint: apiEndpoint,
      httpClient: io.httpClient,
      credential: credential,
    );
  } on EndpointConfigurationException catch (e) {
    stderr.writeln(e.toString());
    return 1;
  } on InsecureEndpointException catch (e) {
    stderr.writeln(e.toString());
    return 1;
  }
  try {
    final ctx = await _resolveScope(
      io: io,
      argResults: argResults,
      scope: scope,
      api: api,
      credential: credential,
      apiEndpoint: apiEndpoint,
      config: config,
    );
    if (ctx == null) return 1;
    if (loaded != null && config != null) {
      RestageConfig? confirmed;
      final target = ctx.target;
      if (target != null &&
          target.project == config.project &&
          target.app == config.app &&
          target.environment == config.defaultEnvironment &&
          (config.organization == null ||
              config.organization == target.organizationSlug) &&
          (config.plane == null || config.plane == target.runtimePlane)) {
        confirmed = config.withResolvedIds(
          organizationId: target.organizationId,
          appId: target.appId,
          environmentTargetId: target.environmentTargetId,
          namedEnvironmentId: target.namedEnvironmentId,
        );
      } else if (ctx.organization case final organization?
          when config.organization == null ||
              organization.slug == config.organization) {
        if (ctx.project == config.project &&
            ctx.app?.slug == config.app &&
            ctx.app?.appId != null) {
          confirmed = config.withConfirmedAppIds(
            organization.organizationId,
            ctx.app!.appId!,
          );
        } else if (ctx.project == null || ctx.project == config.project) {
          confirmed = config.withConfirmedOrganizationId(
            organization.organizationId,
          );
        }
      }
      if (confirmed != null && confirmed.toYaml() != config.toYaml()) {
        await writeRestageConfig(loaded.source, confirmed);
      }
    }
    return await body(ctx);
  } on TargetSelectionException catch (e) {
    stderr.writeln(e.message);
    return 1;
  } on RestageApiException catch (e) {
    final outcome = renderApiError(e);
    stderr.writeln(outcome.message);
    return outcome.exitCode;
  } on SocketException catch (e) {
    stderr.writeln('Could not contact the backend: $e');
    return 2;
  } on http.ClientException catch (e) {
    stderr.writeln('Could not contact the backend: $e');
    return 2;
  } finally {
    if (io.httpClient == null) api.close();
  }
}

String? _option(ArgResults? argResults, String name) =>
    argResults != null && argResults.options.contains(name)
    ? argResults[name] as String?
    : null;

Future<AuthedContext?> _resolveScope({
  required CommandIo io,
  required ArgResults? argResults,
  required OperationScope scope,
  required RestageApi api,
  required Credential credential,
  required Uri apiEndpoint,
  required RestageConfig? config,
}) async {
  AuthedContext build({
    OrganizationSummary? organization,
    String? project,
    AppSummary? app,
    LifecycleContext? target,
    ProgrammaticScopeSnapshot? snapshot,
  }) => AuthedContext._(
    io: io,
    api: api,
    credential: credential,
    apiEndpoint: apiEndpoint,
    config: config,
    organization: organization,
    project: project,
    app: app,
    target: target,
    snapshot: snapshot,
  );

  if (scope == OperationScope.account) return build();
  if (scope == OperationScope.target) {
    final target = await _resolveTarget(
      io: io,
      argResults: argResults,
      api: api,
      credential: credential,
      apiEndpoint: apiEndpoint,
      config: config,
    );
    return target == null ? null : build(target: target);
  }
  final preferredOrganization =
      _option(argResults, 'organization') ?? config?.organization;
  final hintId = preferredOrganization == config?.organization
      ? config?.organizationId
      : null;
  var snapshot = await readProgrammaticScope(api, organizationId: hintId);
  OrganizationSummary? organization;
  if (preferredOrganization != null) {
    organization = snapshot.organizations
        .where((candidate) => candidate.slug == preferredOrganization)
        .firstOrNull;
    if (organization == null) {
      io.stderr.writeln('No organization found for `$preferredOrganization`.');
      return null;
    }
    if (organization.organizationId != snapshot.organizationId) {
      snapshot = await readProgrammaticScope(
        api,
        organizationId: organization.organizationId,
      );
    }
  } else if (snapshot.organizations.length == 1) {
    organization = snapshot.organizations.single;
  } else if (snapshot.organizations.isEmpty) {
    io.stderr.writeln(noOrganizationSentence);
    return null;
  } else if (io.interactive.isInteractive) {
    organization = await io.interactive
        .select<OrganizationSummary>('Which organization?', [
          for (final candidate in snapshot.organizations)
            (label: candidate.slug, value: candidate),
        ]);
    if (organization.organizationId != snapshot.organizationId) {
      snapshot = await readProgrammaticScope(
        api,
        organizationId: organization.organizationId,
      );
    }
  } else {
    io.stderr.writeln(ambiguousOrganizationSentence(snapshot.organizations));
    return null;
  }
  if (scope == OperationScope.organization) {
    return build(organization: organization, snapshot: snapshot);
  }
  final project =
      _option(argResults, 'project') ??
      config?.project ??
      (await pickOne<ProjectSummary>(
        interactive: io.interactive,
        stderr: io.stderr,
        prompt: 'Which project?',
        options: [
          for (final project in snapshot.projects)
            (label: '${project.name} (${project.slug})', value: project),
        ],
        missingFlag: '--project <slug>',
      ))?.slug;
  if (project == null) return null;
  if (!snapshot.projects.any((candidate) => candidate.slug == project)) {
    io.stderr.writeln('No option found for --project <slug>: $project.');
    return null;
  }
  if (scope == OperationScope.project) {
    return build(
      organization: organization,
      project: project,
      snapshot: snapshot,
    );
  }
  final apps = snapshot.apps(project);
  final preferredApp = _option(argResults, 'app') ?? config?.app;
  final app = preferredApp != null
      ? apps.where((candidate) => candidate.slug == preferredApp).firstOrNull
      : await pickOne<AppSummary>(
          interactive: io.interactive,
          stderr: io.stderr,
          prompt: 'Which app?',
          options: [
            for (final candidate in apps)
              (
                label: '${candidate.name} (${candidate.slug})',
                value: candidate,
              ),
          ],
          missingFlag: '--app <slug>',
        );
  if (app == null && preferredApp != null) {
    io.stderr.writeln('No option found for --app <slug>: $preferredApp.');
  }
  if (app == null) return null;
  return build(
    organization: organization,
    project: project,
    app: app,
    snapshot: snapshot,
  );
}

Future<LifecycleContext?> _resolveTarget({
  required CommandIo io,
  required ArgResults? argResults,
  required RestageApi api,
  required Credential credential,
  required Uri apiEndpoint,
  required RestageConfig? config,
}) async {
  final stderr = io.stderr;
  final project = _option(argResults, 'project') ?? config?.project;
  final app = _option(argResults, 'app') ?? config?.app;
  if (project == null || app == null) {
    stderr.writeln(
      missingProjectContextSentence(
        hasConfig: config != null,
        projectMissing: project == null,
      ),
    );
    return null;
  }
  final fromFlag = _option(argResults, 'env');
  final environment = (fromFlag != null && fromFlag.isNotEmpty)
      ? fromFlag
      : (config?.defaultEnvironment?.isNotEmpty ?? false)
      ? config!.defaultEnvironment!
      : io.interactive.isInteractive
      ? await io.interactive.prompt('Environment slug?')
      : null;
  if (environment == null || environment.isEmpty) {
    stderr.writeln(environmentRequiredSentence());
    return null;
  }
  final organizationSlug = resolveOrganizationSlug(argResults, config);
  final resolved = await resolveTargetInteractively(
    api: api,
    interactive: io.interactive,
    projectSlug: project,
    appSlug: app,
    environmentSlug: environment,
    organizationSlug: organizationSlug,
    organizationId:
        organizationIdOption(argResults) ??
        (config?.organization == organizationSlug
            ? config?.organizationId
            : null),
    environmentTargetId:
        config?.project == project &&
            config?.app == app &&
            config?.defaultEnvironment == environment &&
            config?.organization == organizationSlug &&
            (organizationIdOption(argResults) == null ||
                config?.organizationId == organizationIdOption(argResults)) &&
            (argResults == null || !argResults.wasParsed('plane'))
        ? config?.environmentTargetId
        : null,
    runtimePlane: resolveRuntimePlane(argResults, config),
    configuredPlane: config?.plane,
  );
  return LifecycleContext(
    credential: credential,
    apiEndpoint: apiEndpoint,
    project: project,
    app: app,
    environment: environment,
    organizationId: resolved.organizationId,
    organizationSlug: resolved.organizationSlug,
    appId: resolved.appId,
    namedEnvironmentId: resolved.target.namedEnvironmentId,
    environmentTargetId: resolved.target.environmentTargetId,
    runtimePlane: resolved.target.runtimePlane,
    planeIsImplicit: resolved.planeIsImplicit,
  );
}
