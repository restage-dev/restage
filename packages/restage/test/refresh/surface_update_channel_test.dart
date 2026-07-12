import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

final class _FakeChannel implements SurfaceUpdateChannel {
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) =>
      Stream.value(SurfaceUpdate(surface));
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
  });
}
