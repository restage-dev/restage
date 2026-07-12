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
      executor.nextStdout = 'published pro $index\n';
      await controller.publishSelected();
    }

    expect(controller.state.activity, hasLength(5));
    expect(controller.state.activity.map((entry) => entry.message), [
      'published pro 5',
      'published pro 4',
      'published pro 3',
      'published pro 2',
      'published pro 1',
    ]);
    expect(controller.state.activity.first.operation, 'publish');
    expect(controller.state.activity.first.surfaceSlug, 'pro');
    expect(controller.state.activity.first.exitCode, 0);
  });
}

class FakeConsoleRepository implements ConsoleRepository {
  final statusEnvironments = <String>[];

  @override
  Future<ConsoleSnapshot> load() async => const ConsoleSnapshot(
    context: ConsoleContext(
      organizationSlug: 'restage',
      project: 'default',
      app: 'default',
      environment: 'staging',
    ),
    projects: [ConsoleProject(slug: 'default', name: 'Default')],
    apps: [ConsoleAppTarget(slug: 'default', name: 'Default')],
    environments: [
      ConsoleEnvironmentTarget(slug: 'production'),
      ConsoleEnvironmentTarget(slug: 'staging'),
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
      chainState: 'chained',
      chainVerified: true,
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
  }) async => _result();

  @override
  Future<ConsoleOperationResult> unfreeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
  }) async => _result();

  @override
  Future<ConsoleOperationResult> publish({
    required ConsoleContext context,
    required ConsoleSurface surface,
  }) async => _result();

  ConsoleOperationResult _result() =>
      ConsoleOperationResult(exitCode: 0, stdout: nextStdout, stderr: '');
}
