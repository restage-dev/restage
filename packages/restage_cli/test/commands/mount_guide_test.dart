import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/surface_publish_operation.dart';
import 'package:restage_shared/restage_shared.dart' show SurfaceSourceKind;
import 'package:test/test.dart';

void main() {
  test('a paywall can be mounted by its slug', () {
    final guide = mountGuide(SurfaceSourceKind.paywall, 'pro');
    expect(guide, contains("RestagePaywall(id: 'pro')"));
    expect(guide, contains('<Name>Surface()'));
  });

  test('a screen or flow needs its generated mount compiled in', () {
    for (final kind in [
      SurfaceSourceKind.screen,
      SurfaceSourceKind.flowGraph,
    ]) {
      final guide = mountGuide(kind, 'welcome');
      expect(guide, contains('no mount by id'));
      expect(guide, isNot(contains('RestagePaywall')));
    }
  });

  test('a screen or flow names the generated widget its version emitted', () {
    for (final kind in [
      SurfaceSourceKind.screen,
      SurfaceSourceKind.flowGraph,
    ]) {
      final guide = mountGuide(
        kind,
        'lumen_onboarding',
        mountName: 'LumenOnboardingFlowSurface',
      );
      expect(
        guide,
        contains(
          "In your app, call Restage.configure(apiKey: 'rs_pk_...', baseUrl: "
          "...) once with this environment's key, then add "
          'LumenOnboardingFlowSurface(...) where it should appear. New '
          'versions reach app builds made from the same surface code. '
          'Guide: https://docs.restage.dev/delivery/'
          'hosted-delivery',
        ),
      );
      expect(guide, isNot(contains('no mount by id')));
    }
  });

  group('mountLine', () {
    SurfaceStatusResult status({
      required String sourceKind,
      String? activeMountName,
      String? inactiveMountName,
    }) => SurfaceStatusResult(
      surfaceType: 'onboarding',
      surfaceSlug: 'lumen_onboarding',
      environmentSlug: 'production',
      liveVersion: 2,
      locked: false,
      deliveryShape: 'flow',
      draftOrigin: 'code',
      sourceKind: sourceKind,
      versions: [
        SurfaceVersionResult(
          version: 2,
          publishedAt: DateTime.utc(2026, 9),
          contentHash: 'b',
          isActive: true,
          mountName: activeMountName,
        ),
        SurfaceVersionResult(
          version: 1,
          publishedAt: DateTime.utc(2026, 8),
          contentHash: 'a',
          isActive: false,
          mountName: inactiveMountName,
        ),
      ],
    );

    test('a paywall mounts by its slug', () {
      expect(
        mountLine(status(sourceKind: 'paywall')),
        "RestagePaywall(id: 'lumen_onboarding')",
      );
    });

    test('a flow names the live version\'s generated widget', () {
      expect(
        mountLine(
          status(
            sourceKind: 'flowGraph',
            activeMountName: 'LumenOnboardingFlowSurface',
            inactiveMountName: 'OlderFlowSurface',
          ),
        ),
        'LumenOnboardingFlowSurface(...)',
      );
    });

    test('a live version that names no widget has no line', () {
      expect(
        mountLine(
          status(sourceKind: 'screen', inactiveMountName: 'OlderSurface'),
        ),
        isNull,
      );
    });
  });
}
