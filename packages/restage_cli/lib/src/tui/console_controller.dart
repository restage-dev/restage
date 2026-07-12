import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart'
    show kCohortImpactNotePrefix;
import 'package:restage_cli/src/tui/console_models.dart';

abstract interface class ConsoleRepository {
  Future<ConsoleSnapshot> load();
  Future<SurfaceStatusResult> status(
    ConsoleSurface surface, {
    required ConsoleContext context,
  });
  Future<List<SurfaceAuditLogEntry>> auditLog({
    required ConsoleContext context,
  });
  Future<SurfaceChainVerdictResult> surfaceChainVerdict({
    required ConsoleContext context,
  });
}

class ConsoleController {
  ConsoleController({
    required ConsoleRepository repository,
    ConsoleOperationExecutor? operationExecutor,
  }) : _repository = repository,
       _operationExecutor = operationExecutor;

  final ConsoleRepository _repository;
  final ConsoleOperationExecutor? _operationExecutor;
  ConsoleState _state = const ConsoleState.loading();
  int _exitCode = 0;

  ConsoleState get state => _state;
  int get exitCode => _exitCode;

  Future<void> load() async {
    try {
      final snapshot = await _repository.load();
      _state = ConsoleState(
        loading: false,
        focusedPanel: ConsolePanel.projects,
        projectIndex: 0,
        appIndex: 0,
        environmentIndex: _environmentIndex(snapshot),
        surfaceIndex: 0,
        context: snapshot.context,
        projects: snapshot.projects,
        apps: snapshot.apps,
        environments: snapshot.environments,
        surfaces: snapshot.surfaces,
      );
      await refreshStatus();
      await refreshAudit();
    } on ConsoleLoadException catch (e) {
      _state = ConsoleState(
        loading: false,
        focusedPanel: ConsolePanel.projects,
        projectIndex: 0,
        appIndex: 0,
        environmentIndex: 0,
        surfaceIndex: 0,
        error: e.message,
      );
    }
  }

  Future<void> refreshStatus() async {
    final surface = _state.selectedSurface;
    final context = _state.context;
    if (surface == null || context == null) return;
    final status = await _repository.status(surface, context: context);
    _state = _state.copyWith(status: status);
  }

  Future<void> refreshAudit() async {
    final context = _state.context;
    if (context == null) return;
    try {
      final verdict = await _repository.surfaceChainVerdict(context: context);
      final auditLog = await _repository.auditLog(context: context);
      _state = _state.copyWith(
        auditVerdict: verdict,
        auditLog: auditLog,
        clearAuditError: true,
      );
    } on ConsoleLoadException catch (e) {
      _state = _state.copyWith(auditError: e.message);
    }
  }

  int _environmentIndex(ConsoleSnapshot snapshot) {
    final index = snapshot.environments.indexWhere(
      (environment) => environment.slug == snapshot.context.environment,
    );
    return index < 0 ? 0 : index;
  }

  void focusNextPanel() {
    final values = ConsolePanel.values;
    final next = (values.indexOf(_state.focusedPanel) + 1) % values.length;
    _state = _state.copyWith(focusedPanel: values[next]);
  }

  void focusPanel(ConsolePanel panel) {
    _state = _state.copyWith(focusedPanel: panel);
  }

  void focusPreviousPanel() {
    final values = ConsolePanel.values;
    final next = (values.indexOf(_state.focusedPanel) - 1) % values.length;
    _state = _state.copyWith(focusedPanel: values[next]);
  }

  Future<void> moveUp() async {
    if (_state.surfaceIndex == 0) return;
    _state = _state.copyWith(surfaceIndex: _state.surfaceIndex - 1);
    await refreshStatus();
  }

  Future<void> moveDown() async {
    if (_state.surfaceIndex >= _state.surfaces.length - 1) return;
    _state = _state.copyWith(surfaceIndex: _state.surfaceIndex + 1);
    await refreshStatus();
  }

  Future<void> selectSurface(int index) async {
    if (_state.surfaces.isEmpty) return;
    final clamped = index.clamp(0, _state.surfaces.length - 1).toInt();
    if (clamped == _state.surfaceIndex) return;
    _state = _state.copyWith(surfaceIndex: clamped);
    await refreshStatus();
  }

  Future<void> selectEnvironment(int index) async {
    final environments = _state.environments;
    final context = _state.context;
    if (environments.isEmpty || context == null) return;
    final clamped = index.clamp(0, environments.length - 1).toInt();
    if (clamped == _state.environmentIndex) return;
    final environment = environments[clamped];
    _state = _state.copyWith(
      environmentIndex: clamped,
      context: context.copyWith(environment: environment.slug),
    );
    await refreshStatus();
  }

  void quit() {
    _exitCode = 0;
  }

  Future<void> killSelected({
    required String reason,
    required bool frozen,
    bool confirmedProduction = false,
  }) async {
    await _runSelectedOperation(
      (executor, context, surface) => executor.kill(
        context: context,
        surface: surface,
        reason: reason,
        frozen: frozen,
        confirmedProduction: confirmedProduction,
      ),
      operation: 'kill',
    );
  }

  Future<void> rollbackSelected({
    required String reason,
    required int toVersion,
    required bool freeze,
    bool confirmedProduction = false,
  }) async {
    await _runSelectedOperation(
      (executor, context, surface) => executor.rollback(
        context: context,
        surface: surface,
        reason: reason,
        toVersion: toVersion,
        freeze: freeze,
        confirmedProduction: confirmedProduction,
      ),
      operation: 'rollback',
    );
  }

  /// Run the read-only rollback preview for the selected surface and return
  /// its cohort-impact note, or null when the preview could not run (the
  /// failure is surfaced through the operation message). A pure read: no
  /// activity entry, no status refresh, never gates the rollback.
  Future<String?> previewRollback({required int toVersion}) async {
    final executor = _operationExecutor;
    final context = _state.context;
    final surface = _state.selectedSurface;
    if (executor == null) {
      _state = _state.copyWith(operationMessage: 'Operations unavailable.');
      return null;
    }
    if (context == null || surface == null) {
      _state = _state.copyWith(operationMessage: 'No surface selected.');
      return null;
    }
    final result = await executor.rollbackPreview(
      context: context,
      surface: surface,
      toVersion: toVersion,
    );
    if (!result.succeeded) {
      _state = _state.copyWith(operationMessage: _operationMessage(result));
      return null;
    }
    final note = result.stdout
        .trim()
        .split('\n')
        .where((line) => line.startsWith(kCohortImpactNotePrefix))
        .join('\n');
    return note;
  }

  /// Surface a message in the operation-message slot without running an
  /// operation (e.g. a confirm refused because the selection changed).
  void reportOperationMessage(String message) {
    _state = _state.copyWith(operationMessage: message);
  }

  Future<void> freezeSelected({required String reason}) async {
    await _runSelectedOperation(
      (executor, context, surface) =>
          executor.freeze(context: context, surface: surface, reason: reason),
      operation: 'freeze',
    );
  }

  Future<void> unfreezeSelected({required String reason}) async {
    await _runSelectedOperation(
      (executor, context, surface) =>
          executor.unfreeze(context: context, surface: surface, reason: reason),
      operation: 'unfreeze',
    );
  }

  Future<void> publishSelected() async {
    await _runSelectedOperation(
      (executor, context, surface) =>
          executor.publish(context: context, surface: surface),
      operation: 'publish',
    );
  }

  Future<void> _runSelectedOperation(
    Future<ConsoleOperationResult> Function(
      ConsoleOperationExecutor executor,
      ConsoleContext context,
      ConsoleSurface surface,
    )
    run, {
    required String operation,
  }) async {
    final executor = _operationExecutor;
    final context = _state.context;
    final surface = _state.selectedSurface;
    if (executor == null) {
      _state = _state.copyWith(operationMessage: 'Operations unavailable.');
      return;
    }
    if (context == null || surface == null) {
      _state = _state.copyWith(operationMessage: 'No surface selected.');
      return;
    }

    _state = _state.copyWith(operationMessage: 'Running...');
    final result = await run(executor, context, surface);
    final message = _operationMessage(result);
    _state = _state.copyWith(
      operationMessage: message,
      activity: _recordActivity(
        operation: operation,
        surface: surface,
        result: result,
        message: message,
      ),
    );
    if (result.succeeded) {
      await refreshStatus();
      await refreshAudit();
    }
  }

  List<ConsoleActivityEntry> _recordActivity({
    required String operation,
    required ConsoleSurface surface,
    required ConsoleOperationResult result,
    required String message,
  }) {
    return [
      ConsoleActivityEntry(
        operation: operation,
        surfaceSlug: surface.slug,
        exitCode: result.exitCode,
        message: message,
      ),
      ..._state.activity,
    ].take(5).toList(growable: false);
  }

  String _operationMessage(ConsoleOperationResult result) {
    final output = result.succeeded ? result.stdout : result.stderr;
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      return result.succeeded
          ? 'Operation succeeded.'
          : 'Operation failed (${result.exitCode}).';
    }
    return trimmed.split('\n').last;
  }
}
