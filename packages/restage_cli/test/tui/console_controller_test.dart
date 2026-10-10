import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:test/test.dart';

void main() {
  test('load populates context, surfaces, and selected status', () async {
    final repo = FakeConsoleRepository();
    final controller = ConsoleController(repository: repo);

    await controller.load();

    expect(controller.state.context?.project, 'default');
    expect(controller.state.environments.map((e) => e.slug), [
      'production',
      'staging',
    ]);
    expect(controller.state.environmentIndex, 1);
    expect(controller.state.surfaces.map((s) => s.slug), contains('pro'));
    expect(controller.state.selectedSurface?.slug, 'pro');
    expect(controller.state.status?.liveVersion, 2);
    expect(controller.state.auditVerdict?.status, 'verified');
    expect(controller.state.auditLog.single.action, 'surfacePublished');
  });

  test(
    'arrow navigation moves selected surface and refreshes status',
    () async {
      final repo = FakeConsoleRepository();
      final controller = ConsoleController(repository: repo);
      await controller.load();

      await controller.moveDown();

      expect(controller.state.selectedSurface?.slug, 'welcome');
      expect(controller.state.status?.surfaceSlug, 'welcome');
    },
  );

  test('selectSurface chooses a surface and refreshes status', () async {
    final repo = FakeConsoleRepository();
    final controller = ConsoleController(repository: repo);
    await controller.load();

    await controller.selectSurface(1);

    expect(controller.state.selectedSurface?.slug, 'welcome');
    expect(controller.state.status?.surfaceSlug, 'welcome');
  });

  test('selectEnvironment updates context and refreshes status', () async {
    final repo = FakeConsoleRepository();
    final controller = ConsoleController(repository: repo);
    await controller.load();

    await controller.selectEnvironment(0);

    expect(controller.state.context?.environment, 'production');
    expect(controller.state.environmentIndex, 0);
    expect(controller.state.status?.environmentSlug, 'production');
    expect(repo.statusEnvironments, ['staging', 'production']);
  });

  test('same-slug cross-plane selection keeps exact target identity', () async {
    final repo = SameSlugConsoleRepository();
    final controller = ConsoleController(repository: repo);

    await controller.load();
    await controller.selectEnvironment(1);

    expect(controller.state.environmentIndex, 1);
    expect(controller.state.context?.environment, 'prod');
    expect(controller.state.context?.environmentTargetId, 32);
    expect(controller.state.context?.namedEnvironmentId, 41);
    expect(controller.state.context?.runtimePlane, RuntimePlane.live);
    expect(repo.statusTargetIds, [31, 32]);
  });

  test('tab cycles panels', () async {
    final controller = ConsoleController(repository: FakeConsoleRepository());
    await controller.load();

    controller.focusNextPanel();

    expect(controller.state.focusedPanel, ConsolePanel.apps);
  });

  test('operations append the last five session activity entries', () async {
    final executor = RecordingConsoleOperationExecutor();
    final controller = ConsoleController(
      repository: FakeConsoleRepository(),
      operationExecutor: executor,
    );
    await controller.load();

    for (var index = 0; index < 6; index++) {
      executor.nextStdout = 'pushed pro $index\n';
      await controller.pushSelected();
    }

    expect(controller.state.activity, hasLength(5));
    expect(controller.state.activity.map((entry) => entry.message), [
      'pushed pro 5',
      'pushed pro 4',
      'pushed pro 3',
      'pushed pro 2',
      'pushed pro 1',
    ]);
    expect(controller.state.activity.first.operation, 'push');
    expect(controller.state.activity.first.surfaceSlug, 'pro');
    expect(controller.state.activity.first.exitCode, 0);
  });

  test('a push keeps every line it printed, notes included', () async {
    final executor = RecordingConsoleOperationExecutor()
      ..nextStdout =
          'Pushed pro (paywall) to staging; stored r2.\n'
          'Not live yet. Type `/restage surface publish pro` to publish it.\n';
    final controller = ConsoleController(
      repository: FakeConsoleRepository(),
      operationExecutor: executor,
    );
    await controller.load();

    await controller.pushSelected();

    expect(controller.state.commandOutput!.arguments, [
      'surface',
      'push',
      'pro',
    ]);
    expect(controller.state.commandOutput!.lines, [
      'Pushed pro (paywall) to staging; stored r2.',
      'Not live yet. Type `/restage surface publish pro` to publish it.',
    ]);
  });

  test('a build keeps every line it printed', () async {
    final executor = RecordingConsoleOperationExecutor()
      ..nextStdout =
          'Pushed default staging version 4.\n'
          'The surfaces were pushed, but the build of default was not.\n';
    final controller = ConsoleController(
      repository: FakeConsoleRepository(),
      operationExecutor: executor,
    );
    await controller.load();

    await controller.pushBuild();

    expect(controller.state.commandOutput!.lines, hasLength(2));
  });

  test('publish runs for the selected surface', () async {
    final executor = RecordingConsoleOperationExecutor()
      ..nextStdout = 'Published "pro" at r3 in staging.\n';
    final controller = ConsoleController(
      repository: FakeConsoleRepository(),
      operationExecutor: executor,
    );
    await controller.load();

    await controller.publishSelected(reason: 'ship new copy');

    expect(controller.state.activity.first.operation, 'publish');
    expect(
      controller.state.operationMessage,
      'Published "pro" at r3 in staging.',
    );
  });

  test('a command line runs any CLI command and keeps its output', () async {
    final executor = RecordingConsoleOperationExecutor()
      ..nextStdout = 'REVISION\tACTIVE\nr3\ttrue\n';
    final controller = ConsoleController(
      repository: FakeConsoleRepository(),
      operationExecutor: executor,
    );
    await controller.load();

    await controller.runCommand(['surface', 'history', 'pro']);

    expect(executor.commands.single, ['surface', 'history', 'pro']);
    expect(controller.state.commandOutput!.lines, [
      'REVISION\tACTIVE',
      'r3\ttrue',
    ]);
    expect(controller.state.activity.first.operation, 'restage');
  });

  test('the command line refuses the commands it cannot host', () async {
    final executor = RecordingConsoleOperationExecutor();
    final controller = ConsoleController(
      repository: FakeConsoleRepository(),
      operationExecutor: executor,
    );
    await controller.load();

    for (final command in ['console', 'login']) {
      await controller.runCommand([command]);
      expect(
        controller.state.operationMessage,
        consoleExcludedCommands[command],
      );
    }
    expect(executor.commands, isEmpty);
  });

  test('a restage line splits into arguments, honoring quotes', () {
    expect(consoleCommandArguments('surface history pro'), isNull);
    expect(consoleCommandArguments('restage'), isEmpty);
    expect(
      consoleCommandArguments(
        'restage surface kill pro --reason "bad copy" --yes',
      ),
      ['surface', 'kill', 'pro', '--reason', 'bad copy', '--yes'],
    );
    expect(consoleCommandArguments("  restage keys revoke  '12'  "), [
      'keys',
      'revoke',
      '12',
    ]);
  });
}

class FakeConsoleRepository implements ConsoleRepository {
  final statusEnvironments = <String>[];
  final statusTargetIds = <int>[];

  @override
  Future<ConsoleSnapshot> load() async => const ConsoleSnapshot(
    context: ConsoleContext(
      organizationSlug: 'restage',
      project: 'default',
      appId: 5,
      app: 'default',
      environmentTargetId: 12,
      namedEnvironmentId: 22,
      environment: 'staging',
      runtimePlane: RuntimePlane.live,
    ),
    projects: [ConsoleProject(slug: 'default', name: 'Default')],
    apps: [ConsoleAppTarget(appId: 5, slug: 'default', name: 'Default')],
    environments: [
      ConsoleEnvironmentTarget(
        environmentTargetId: 13,
        namedEnvironmentId: 23,
        slug: 'production',
        runtimePlane: RuntimePlane.live,
      ),
      ConsoleEnvironmentTarget(
        environmentTargetId: 12,
        namedEnvironmentId: 22,
        slug: 'staging',
        runtimePlane: RuntimePlane.live,
      ),
    ],
    surfaces: [
      ConsoleSurface(surfaceType: 'paywall', slug: 'pro', name: 'Pro'),
      ConsoleSurface(
        surfaceType: 'onboarding',
        slug: 'welcome',
        name: 'Welcome',
      ),
    ],
  );

  @override
  Future<SurfaceStatusResult> status(
    ConsoleSurface surface, {
    required ConsoleContext context,
  }) async {
    statusEnvironments.add(context.environment);
    statusTargetIds.add(context.environmentTargetId);
    return SurfaceStatusResult(
      surfaceType: surface.surfaceType,
      surfaceSlug: surface.slug,
      environmentSlug: context.environment,
      liveVersion: surface.slug == 'pro' ? 2 : null,
      locked: false,
      deliveryShape: surface.surfaceType == 'paywall' ? 'blob' : 'flow',
      versions: const [],
    );
  }

  @override
  Future<List<SurfaceAuditLogEntry>> auditLog({
    required ConsoleContext context,
  }) async => [
    SurfaceAuditLogEntry(
      action: 'surfacePublished',
      actorType: 'human',
      actorEmail: 'owner@example.com',
      outcome: 'success',
      severity: 'notice',
      targetType: 'surface',
      targetId: '42',
      occurredAt: DateTime.parse('2026-06-29T18:17:51.000Z'),
      reason: 'demo publish',
      context: const {'surfaceSlug': 'pro'},
      chain: AuditChain.verified,
      entryId: 99,
    ),
  ];

  @override
  Future<SurfaceChainVerdictResult> surfaceChainVerdict({
    required ConsoleContext context,
  }) async => SurfaceChainVerdictResult(
    status: 'verified',
    verifiedThroughEntryId: 99,
    verifiedThroughOccurredAt: null,
    failedEntryId: null,
    failedCheck: null,
    lastRunAt: DateTime.parse('2026-06-29T18:30:00.000Z'),
  );
}

class SameSlugConsoleRepository extends FakeConsoleRepository {
  @override
  Future<ConsoleSnapshot> load() async => const ConsoleSnapshot(
    context: ConsoleContext(
      organizationSlug: 'restage',
      project: 'default',
      appId: 5,
      app: 'default',
      environmentTargetId: 31,
      namedEnvironmentId: 41,
      environment: 'prod',
      runtimePlane: RuntimePlane.sandbox,
    ),
    projects: [ConsoleProject(slug: 'default', name: 'Default')],
    apps: [ConsoleAppTarget(appId: 5, slug: 'default', name: 'Default')],
    environments: [
      ConsoleEnvironmentTarget(
        environmentTargetId: 31,
        namedEnvironmentId: 41,
        slug: 'prod',
        runtimePlane: RuntimePlane.sandbox,
      ),
      ConsoleEnvironmentTarget(
        environmentTargetId: 32,
        namedEnvironmentId: 41,
        slug: 'prod',
        runtimePlane: RuntimePlane.live,
      ),
    ],
    surfaces: [
      ConsoleSurface(surfaceType: 'paywall', slug: 'pro', name: 'Pro'),
    ],
  );
}

class RecordingConsoleOperationExecutor implements ConsoleOperationExecutor {
  String nextStdout = 'ok\n';

  @override
  Future<ConsoleOperationResult> kill({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required bool frozen,
    bool confirmedProduction = false,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> rollback({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required int toVersion,
    required bool freeze,
    bool confirmedProduction = false,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> rollbackPreview({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required int toVersion,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> freeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> unfreeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> push({
    required ConsoleContext context,
    required ConsoleSurface surface,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> pushBuild({
    required ConsoleContext context,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> publish({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  }) async => _result();

  final commands = <List<String>>[];

  @override
  Future<ConsoleOperationResult> runCommand(List<String> arguments) async {
    commands.add(arguments);
    return _result();
  }

  ConsoleOperationResult _result() =>
      ConsoleOperationResult(exitCode: 0, stdout: nextStdout, stderr: '');
}
