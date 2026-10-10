import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/flow/flow_resolver.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/surface_screen/surface_screen_types.dart';

void main() {
  test('each built-in hosted resolver has a raceable side', () {
    const apiKey = 'rs_pk_test';
    const baseUrl = 'https://surfaces.example.com';

    expect(
      racedResolverOf<ResolvedPaywallPayload>(RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
      )),
      isNotNull,
    );
    expect(
      racedResolverOf<ResolvedFlow>(
        ServerFlowResolver(baseUrl: baseUrl, apiKey: apiKey, active: true),
      ),
      isNotNull,
    );
    expect(
      racedResolverOf<ResolvedSurfaceScreen>(RestageScreenResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
      )),
      isNotNull,
    );
  });

  test('a resolver without one, or asked for another type, has none', () {
    expect(racedResolverOf<ResolvedFlow>(Object()), isNull);
    expect(
      racedResolverOf<ResolvedFlow>(RestageVariantResolver(
        apiKey: 'rs_pk_test',
        environment: RestageEnvironment.production,
      )),
      isNull,
    );
  });

  test('a keyless delivery never replaces a keyed one written meanwhile',
      () async {
    SurfaceAssignmentKeyProvider.local = () => 'held';
    addTearDown(() => SurfaceAssignmentKeyProvider.local = null);
    final store = _GatedReadStore();
    const key = SurfaceStoreKey(
      scope: 'scope',
      surfaceType: 'paywall',
      slug: 'pro',
      contractVersion: 0,
    );

    final keyless = persistAcceptedDelivery(store, key, _entry(null));
    await pumpEventQueue();
    final keyed = persistAcceptedDelivery(store, key, _entry('held'));
    await pumpEventQueue();
    store.releaseReads.complete();
    await Future.wait([keyless, keyed]);

    expect(
      (await store.read(key))?.sidecar['assignmentKey'],
      'held',
    );
  });
}

StoredSurface _entry(String? assignmentKey) => StoredSurface(
      descriptorJson: Uint8List.fromList(const [123, 125]),
      artifactBytes: Uint8List(0),
      sidecar: {if (assignmentKey != null) 'assignmentKey': assignmentKey},
    );

final class _GatedReadStore implements SurfaceArtifactStore {
  final MemorySurfaceArtifactStore _inner = MemorySurfaceArtifactStore();
  final Completer<void> releaseReads = Completer<void>();

  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) async {
    final value = await _inner.read(key);
    await releaseReads.future;
    return value;
  }

  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) =>
      _inner.write(key, value);

  @override
  Future<void> remove(SurfaceStoreKey key) => _inner.remove(key);

  @override
  Future<List<SurfaceStoreKey>> keys() => _inner.keys();

  @override
  Future<void> clear() => _inner.clear();
}
