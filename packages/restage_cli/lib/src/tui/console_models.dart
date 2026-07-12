import 'package:restage_cli/src/api/surface_models.dart';

enum ConsolePanel { projects, apps, surfaces, detail, actions }

class ConsoleContext {
  const ConsoleContext({
    required this.organizationSlug,
    required this.project,
    required this.app,
    required this.environment,
  });

  final String? organizationSlug;
  final String project;
  final String app;
  final String environment;

  ConsoleContext copyWith({
    String? organizationSlug,
    String? project,
    String? app,
    String? environment,
  }) => ConsoleContext(
    organizationSlug: organizationSlug ?? this.organizationSlug,
    project: project ?? this.project,
    app: app ?? this.app,
    environment: environment ?? this.environment,
  );
}

class ConsoleProject {
  const ConsoleProject({required this.slug, required this.name});

  final String slug;
  final String name;
}

class ConsoleAppTarget {
  const ConsoleAppTarget({required this.slug, required this.name});

  final String slug;
  final String name;
}

class ConsoleEnvironmentTarget {
  const ConsoleEnvironmentTarget({required this.slug});

  final String slug;
}

class ConsoleSurface {
  const ConsoleSurface({
    required this.surfaceType,
    required this.slug,
    required this.name,
  });

  final String surfaceType;
  final String slug;
  final String name;
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
  });

  final ConsoleContext context;
  final List<ConsoleProject> projects;
  final List<ConsoleAppTarget> apps;
  final List<ConsoleEnvironmentTarget> environments;
  final List<ConsoleSurface> surfaces;
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
    this.status,
    this.auditLog = const [],
    this.auditVerdict,
    this.auditError,
    this.operationMessage,
    this.activity = const [],
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
      status = null,
      auditLog = const [],
      auditVerdict = null,
      auditError = null,
      operationMessage = null,
      activity = const [];

  final bool loading;
  final String? error;
  final ConsoleContext? context;
  final List<ConsoleProject> projects;
  final List<ConsoleAppTarget> apps;
  final List<ConsoleEnvironmentTarget> environments;
  final List<ConsoleSurface> surfaces;
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

  ConsoleSurface? get selectedSurface {
    if (surfaces.isEmpty) return null;
    final index = surfaceIndex.clamp(0, surfaces.length - 1);
    return surfaces[index];
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
    ConsolePanel? focusedPanel,
    int? projectIndex,
    int? appIndex,
    int? environmentIndex,
    int? surfaceIndex,
    SurfaceStatusResult? status,
    List<SurfaceAuditLogEntry>? auditLog,
    SurfaceChainVerdictResult? auditVerdict,
    String? auditError,
    bool clearAuditError = false,
    String? operationMessage,
    List<ConsoleActivityEntry>? activity,
  }) => ConsoleState(
    loading: loading ?? this.loading,
    error: error ?? this.error,
    context: context ?? this.context,
    projects: projects ?? this.projects,
    apps: apps ?? this.apps,
    environments: environments ?? this.environments,
    surfaces: surfaces ?? this.surfaces,
    focusedPanel: focusedPanel ?? this.focusedPanel,
    projectIndex: projectIndex ?? this.projectIndex,
    appIndex: appIndex ?? this.appIndex,
    environmentIndex: environmentIndex ?? this.environmentIndex,
    surfaceIndex: surfaceIndex ?? this.surfaceIndex,
    status: status ?? this.status,
    auditLog: auditLog ?? this.auditLog,
    auditVerdict: auditVerdict ?? this.auditVerdict,
    auditError: clearAuditError ? null : auditError ?? this.auditError,
    operationMessage: operationMessage ?? this.operationMessage,
    activity: activity ?? this.activity,
  );
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
  });

  final int exitCode;
  final String stdout;
  final String stderr;

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
  });

  Future<ConsoleOperationResult> unfreeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
  });

  Future<ConsoleOperationResult> publish({
    required ConsoleContext context,
    required ConsoleSurface surface,
  });
}
