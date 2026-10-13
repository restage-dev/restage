import 'package:restage_cli/src/measurement/overview_figures.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_models.dart';

enum ConsolePanel { projects, apps, surfaces, detail, actions }

class ConsoleContext {
  const ConsoleContext({
    required this.organizationSlug,
    required this.project,
    required this.appId,
    required this.app,
    required this.environmentTargetId,
    required this.namedEnvironmentId,
    required this.environment,
    required this.runtimePlane,
  });

  final String? organizationSlug;
  final String project;
  final int appId;
  final String app;
  final int environmentTargetId;
  final int namedEnvironmentId;
  final String environment;
  final RuntimePlane runtimePlane;

  String get environmentLabel => '$environment (${runtimePlane.wireName})';

  ConsoleContext copyWith({
    String? organizationSlug,
    String? project,
    int? appId,
    String? app,
    int? environmentTargetId,
    int? namedEnvironmentId,
    String? environment,
    RuntimePlane? runtimePlane,
  }) => ConsoleContext(
    organizationSlug: organizationSlug ?? this.organizationSlug,
    project: project ?? this.project,
    appId: appId ?? this.appId,
    app: app ?? this.app,
    environmentTargetId: environmentTargetId ?? this.environmentTargetId,
    namedEnvironmentId: namedEnvironmentId ?? this.namedEnvironmentId,
    environment: environment ?? this.environment,
    runtimePlane: runtimePlane ?? this.runtimePlane,
  );
}

class ConsoleProject {
  const ConsoleProject({required this.slug, required this.name});

  final String slug;
  final String name;
}

class ConsoleAppTarget {
  const ConsoleAppTarget({
    required this.appId,
    required this.slug,
    required this.name,
  });

  final int appId;
  final String slug;
  final String name;
}

class ConsoleEnvironmentTarget {
  const ConsoleEnvironmentTarget({
    required this.environmentTargetId,
    required this.namedEnvironmentId,
    required this.slug,
    required this.runtimePlane,
  });

  final int environmentTargetId;
  final int namedEnvironmentId;
  final String slug;
  final RuntimePlane runtimePlane;

  String get label => '$slug (${runtimePlane.wireName})';
}

class ConsoleSurface {
  const ConsoleSurface({
    required this.surfaceType,
    required this.slug,
    required this.name,
    this.contractVersion,
    this.sourceKind,
    this.payloadKind,
    this.hasManifestIdentity = false,
  });

  final String surfaceType;
  final String slug;
  final String name;

  /// Positive standalone-screen family version, when the current generated
  /// manifest supplied one.
  final int? contractVersion;

  /// Authored source kind from the generated identity.
  final String? sourceKind;

  /// Payload kind from the generated identity.
  final String? payloadKind;

  /// Whether this surface was resolved from the current generated manifest.
  final bool hasManifestIdentity;
}

/// One head of the app's build, as the console shows it.
class ConsoleBuildHead {
  const ConsoleBuildHead({
    required this.head,
    required this.version,
    required this.libraries,
    required this.updatedAt,
    this.sourceCommit,
    this.sourceDirty = false,
  });

  /// The environment slug, or `user/<handle>`.
  final String head;

  /// The version this head points at.
  final int version;

  /// The app widget libraries that version registers, by namespace.
  final Map<String, int> libraries;

  /// When the head last moved.
  final DateTime updatedAt;

  /// The commit the build came from, when the push knew it.
  final String? sourceCommit;

  /// Whether that commit's tree carried local changes.
  final bool sourceDirty;
}

class ConsoleActivityEntry {
  const ConsoleActivityEntry({
    required this.operation,
    required this.surfaceSlug,
    required this.exitCode,
    required this.message,
  });

  final String operation;
  final String surfaceSlug;
  final int exitCode;
  final String message;
}

class ConsoleSnapshot {
  const ConsoleSnapshot({
    required this.context,
    required this.projects,
    required this.apps,
    required this.environments,
    required this.surfaces,
    this.builds = const [],
  });

  final ConsoleContext context;
  final List<ConsoleProject> projects;
  final List<ConsoleAppTarget> apps;
  final List<ConsoleEnvironmentTarget> environments;
  final List<ConsoleSurface> surfaces;

  /// The heads the selected app's build holds.
  final List<ConsoleBuildHead> builds;
}

class ConsoleState {
  const ConsoleState({
    required this.loading,
    required this.focusedPanel,
    required this.projectIndex,
    required this.appIndex,
    required this.environmentIndex,
    required this.surfaceIndex,
    this.error,
    this.context,
    this.projects = const [],
    this.apps = const [],
    this.environments = const [],
    this.surfaces = const [],
    this.builds = const [],
    this.overview,
    this.overviewLoading = false,
    this.overviewError,
    this.status,
    this.auditLog = const [],
    this.auditVerdict,
    this.auditError,
    this.operationMessage,
    this.activity = const [],
    this.commandOutput,
  });

  const ConsoleState.loading()
    : loading = true,
      focusedPanel = ConsolePanel.projects,
      projectIndex = 0,
      appIndex = 0,
      environmentIndex = 0,
      surfaceIndex = 0,
      error = null,
      context = null,
      projects = const [],
      apps = const [],
      environments = const [],
      surfaces = const [],
      builds = const [],
      overview = null,
      overviewLoading = false,
      overviewError = null,
      status = null,
      auditLog = const [],
      auditVerdict = null,
      auditError = null,
      operationMessage = null,
      activity = const [],
      commandOutput = null;

  final bool loading;
  final String? error;
  final ConsoleContext? context;
  final List<ConsoleProject> projects;
  final List<ConsoleAppTarget> apps;
  final List<ConsoleEnvironmentTarget> environments;
  final List<ConsoleSurface> surfaces;
  final List<ConsoleBuildHead> builds;
  final OverviewFigures? overview;
  final bool overviewLoading;
  final String? overviewError;
  final ConsolePanel focusedPanel;
  final int projectIndex;
  final int appIndex;
  final int environmentIndex;
  final int surfaceIndex;
  final SurfaceStatusResult? status;
  final List<SurfaceAuditLogEntry> auditLog;
  final SurfaceChainVerdictResult? auditVerdict;
  final String? auditError;
  final String? operationMessage;
  final List<ConsoleActivityEntry> activity;

  /// The last command run from the command line, with everything it printed.
  final ConsoleCommandOutput? commandOutput;

  ConsoleSurface? get selectedSurface {
    if (surfaces.isEmpty) return null;
    final index = surfaceIndex.clamp(0, surfaces.length - 1);
    return surfaces[index];
  }

  /// The build head the selected environment renders through, if any.
  ConsoleBuildHead? get selectedBuild {
    final environment = selectedEnvironment;
    if (environment == null) return null;
    for (final build in builds) {
      if (build.head == environment.slug) return build;
    }
    return null;
  }

  ConsoleEnvironmentTarget? get selectedEnvironment {
    if (environments.isEmpty) return null;
    final index = environmentIndex.clamp(0, environments.length - 1);
    return environments[index];
  }

  ConsoleState copyWith({
    bool? loading,
    String? error,
    ConsoleContext? context,
    List<ConsoleProject>? projects,
    List<ConsoleAppTarget>? apps,
    List<ConsoleEnvironmentTarget>? environments,
    List<ConsoleSurface>? surfaces,
    List<ConsoleBuildHead>? builds,
    OverviewFigures? overview,
    bool clearOverview = false,
    bool? overviewLoading,
    String? overviewError,
    bool clearOverviewError = false,
    ConsolePanel? focusedPanel,
    int? projectIndex,
    int? appIndex,
    int? environmentIndex,
    int? surfaceIndex,
    SurfaceStatusResult? status,
    bool clearStatus = false,
    List<SurfaceAuditLogEntry>? auditLog,
    SurfaceChainVerdictResult? auditVerdict,
    String? auditError,
    bool clearAuditError = false,
    String? operationMessage,
    List<ConsoleActivityEntry>? activity,
    ConsoleCommandOutput? commandOutput,
  }) => ConsoleState(
    loading: loading ?? this.loading,
    error: error ?? this.error,
    context: context ?? this.context,
    projects: projects ?? this.projects,
    apps: apps ?? this.apps,
    environments: environments ?? this.environments,
    surfaces: surfaces ?? this.surfaces,
    builds: builds ?? this.builds,
    overview: clearOverview ? null : overview ?? this.overview,
    overviewLoading: overviewLoading ?? this.overviewLoading,
    overviewError: clearOverviewError
        ? null
        : overviewError ?? this.overviewError,
    focusedPanel: focusedPanel ?? this.focusedPanel,
    projectIndex: projectIndex ?? this.projectIndex,
    appIndex: appIndex ?? this.appIndex,
    environmentIndex: environmentIndex ?? this.environmentIndex,
    surfaceIndex: surfaceIndex ?? this.surfaceIndex,
    status: clearStatus ? null : status ?? this.status,
    auditLog: auditLog ?? this.auditLog,
    auditVerdict: auditVerdict ?? this.auditVerdict,
    auditError: clearAuditError ? null : auditError ?? this.auditError,
    operationMessage: operationMessage ?? this.operationMessage,
    activity: activity ?? this.activity,
    commandOutput: commandOutput ?? this.commandOutput,
  );
}

/// One command run from the console's command line, and its output.
class ConsoleCommandOutput {
  const ConsoleCommandOutput({required this.arguments, required this.result});

  /// The arguments after `restage`.
  final List<String> arguments;

  /// What the command returned and printed.
  final ConsoleOperationResult result;

  /// Everything the command printed, stdout first.
  List<String> get lines => [
    if (result.targetDescription != null) 'Target: ${result.targetDescription}',
    ...result.stdout.trimRight().split('\n'),
    if (result.stderr.trim().isNotEmpty)
      ...result.stderr.trimRight().split('\n'),
  ].where((line) => line.isNotEmpty).toList(growable: false);
}

class ConsoleLoadException implements Exception {
  const ConsoleLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ConsoleOperationResult {
  const ConsoleOperationResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.targetDescription,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final String? targetDescription;

  bool get succeeded => exitCode == 0;
}

abstract interface class ConsoleOperationExecutor {
  Future<ConsoleOperationResult> kill({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required bool frozen,
    bool confirmedProduction = false,
  });

  Future<ConsoleOperationResult> rollback({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required int toVersion,
    required bool freeze,
    bool confirmedProduction = false,
  });

  /// Read-only rollback preview: how rolling back to [toVersion] is expected
  /// to affect live clients (the cohort-impact classification). Never mutates
  /// and never gates the rollback.
  Future<ConsoleOperationResult> rollbackPreview({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required int toVersion,
  });

  Future<ConsoleOperationResult> freeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  });

  Future<ConsoleOperationResult> unfreeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  });

  Future<ConsoleOperationResult> push({
    required ConsoleContext context,
    required ConsoleSurface surface,
  });

  /// Publishes the latest revision pushed for [surface].
  Future<ConsoleOperationResult> publish({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  });

  /// Runs any `restage` command with [arguments], in the console's project.
  Future<ConsoleOperationResult> runCommand(
    List<String> arguments, {
    ConsoleContext? context,
  });

  /// Pushes the app's build to the context's environment head.
  Future<ConsoleOperationResult> pushBuild({required ConsoleContext context});
}

/// Commands the console's command line does not run, and why.
const consoleExcludedCommands = <String, String>{
  'console': 'The console is already open.',
  'login':
      'Sign-in waits for approval in a browser. Run `restage login` in a '
      'terminal, then reopen the console.',
};

/// The arguments of a `restage ...` line typed into the console, or null when
/// [line] is not one. Single and double quotes group words.
List<String>? consoleCommandArguments(String line) {
  final trimmed = line.trim();
  if (trimmed != 'restage' && !trimmed.startsWith('restage ')) return null;
  final arguments = <String>[];
  final current = StringBuffer();
  var inWord = false;
  String? quote;
  for (final char in trimmed.substring('restage'.length).split('')) {
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        current.write(char);
      }
    } else if (char == '"' || char == "'") {
      quote = char;
      inWord = true;
    } else if (char.trim().isEmpty) {
      if (inWord) {
        arguments.add(current.toString());
        current.clear();
        inWord = false;
      }
    } else {
      current.write(char);
      inWord = true;
    }
  }
  if (inWord) arguments.add(current.toString());
  return arguments;
}
