import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';

final class _FakeChannel implements SurfaceUpdateChannel {
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) =>
      Stream.value(SurfaceUpdate(surface));
}

final class _FakeDeliveryChannel implements DeliveryUpdateChannel {
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) =>
      Stream.value(SurfaceUpdate(surface));

  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(
    DeliveryPolicyScopeV1 scope, {
    PlacementDeliveryWatchV1? watch,
    Future<PlacementRefreshProbeV1> Function()? reconnectProbe,
  }) =>
      Stream.value(scope);
}

void main() {
  test('SurfaceRef value equality', () {
    expect(const SurfaceRef(surfaceType: 'paywall', slug: 'pro'),
        const SurfaceRef(surfaceType: 'paywall', slug: 'pro'));
    expect(const SurfaceRef(surfaceType: 'paywall', slug: 'pro'),
        isNot(const SurfaceRef(surfaceType: 'onboarding', slug: 'pro')));
    expect(const SurfaceRef(surfaceType: 'paywall', slug: 'pro').hashCode,
        const SurfaceRef(surfaceType: 'paywall', slug: 'pro').hashCode);
  });

  test('a custom channel is implementable and emits typed updates', () async {
    const ref = SurfaceRef(surfaceType: 'paywall', slug: 'pro');
    final update = await _FakeChannel().watch(ref).first;
    expect(update.surface, ref);
    expect(_FakeChannel(), isNot(isA<DeliveryUpdateChannel>()));
  });

  test('delivery capability preserves exact target, owner and family',
      () async {
    final delivery = (readPlacementDeliveryFixture().response.decisions.first
            as PlacementBatchAvailableV1)
        .publicDelivery;
    final channel = _FakeDeliveryChannel();
    final child = delivery.dependencyClosure
        .singleWhere((scope) => !scope.root.isPlacement);
    final general = DeliveryPolicyScopeV1(
        root: child.root, family: const DeliveryFamilySelectorV1.general());
    expect(await channel.watchDelivery(child).first, child);
    expect(await channel.watchDelivery(general).first, general);
    expect(child, isNot(general));
    expect(child.target, delivery.mount.placement.target);
  });

  test('placement probe results retain exact digest and throttle duration', () {
    final digest = CanonicalDigest('a' * 64);
    final unchanged = PlacementRefreshProbeV1.unchanged(digest)
        as PlacementRefreshUnchangedV1;
    expect(unchanged.decisionIdentityDigest, digest);
    expect(const PlacementRefreshProbeV1.requiresResolution(),
        isA<PlacementRefreshRequiresResolutionV1>());
    final throttled =
        const PlacementRefreshProbeV1.rateLimited(Duration(seconds: 7))
            as PlacementRefreshRateLimitedV1;
    expect(throttled.retryAfter, const Duration(seconds: 7));
    expect(const PlacementRefreshProbeV1.unavailable(),
        isA<PlacementRefreshUnavailableV1>());
  });
}
