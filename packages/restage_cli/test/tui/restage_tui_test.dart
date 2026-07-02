import 'package:nocterm/nocterm.dart' as nocterm;
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:restage_cli/src/tui/restage_tui.dart';
import 'package:test/test.dart';

void main() {
  test('console launcher disables Nocterm hot reload', () async {
    final controller = ConsoleController(repository: _FakeConsoleRepository());
    final enableHotReloadValues = <bool>[];
    nocterm.Component? launchedApp;

    final exitCode = await runRestageConsoleWithRunner(
      controller,
      runApp:
          (
            nocterm.Component app, {
            bool enableHotReload = true,
            nocterm.TerminalBackend? backend,
          }) async {
            launchedApp = app;
            enableHotReloadValues.add(enableHotReload);
          },
    );

    expect(exitCode, 0);
    expect(launchedApp, isNotNull);
    expect(enableHotReloadValues, [false]);
  });
}

class _FakeConsoleRepository implements ConsoleRepository {
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
    environments: [ConsoleEnvironmentTarget(slug: 'staging')],
    surfaces: [
      ConsoleSurface(surfaceType: 'paywall', slug: 'pro', name: 'Pro'),
    ],
  );

  @override
  Future<SurfaceStatusResult> status(
    ConsoleSurface surface, {
    required ConsoleContext context,
  }) async => SurfaceStatusResult(
    surfaceType: surface.surfaceType,
    surfaceSlug: surface.slug,
    environmentSlug: context.environment,
    liveVersion: null,
    locked: false,
    deliveryShape: 'blob',
    versions: const [],
  );

  @override
  Future<List<SurfaceAuditLogEntry>> auditLog({
    required ConsoleContext context,
  }) async => const [];

  @override
  Future<SurfaceChainVerdictResult> surfaceChainVerdict({
    required ConsoleContext context,
  }) async => const SurfaceChainVerdictResult(
    status: 'pending',
    verifiedThroughEntryId: null,
    verifiedThroughOccurredAt: null,
    failedEntryId: null,
    failedCheck: null,
    lastRunAt: null,
  );
}
