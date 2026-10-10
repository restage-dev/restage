import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';

void main() {
  late Directory root;
  late SurfaceArtifactStore store;

  const key = SurfaceStoreKey(
    scope: '0123456789abcdef',
    surfaceType: 'paywall',
    slug: 'annual-offer',
    contractVersion: 3,
  );

  StoredSurface entry(int seed) => StoredSurface(
        descriptorJson: Uint8List.fromList('{"v":$seed}'.codeUnits),
        artifactBytes: Uint8List.fromList(<int>[seed, 1, 2, 3]),
        sidecar: <String, Object?>{
          'servedVersion': seed,
          'receipt': <String, Object?>{'route': 'default'},
        },
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('surface_store_test');
    store = createSurfaceArtifactStore(directory: () async => root.path);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('round-trips an entry across store instances', () async {
    await store.write(key, entry(7));

    final reopened =
        createSurfaceArtifactStore(directory: () async => root.path);
    final read = await reopened.read(key);

    expect(read, isNotNull);
    expect(read!.descriptorJson, entry(7).descriptorJson);
    expect(read.artifactBytes, entry(7).artifactBytes);
    expect(read.sidecar, entry(7).sidecar);
    expect(await reopened.keys(), <SurfaceStoreKey>[key]);
  });

  test('a write replaces the previous entry and leaves no temp files',
      () async {
    await store.write(key, entry(1));
    await store.write(key, entry(2));

    expect((await store.read(key))!.artifactBytes, entry(2).artifactBytes);
    final files = root.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('.surface'));
  });

  test('keys differ by scope, type, slug and contract version', () async {
    const other = SurfaceStoreKey(
      scope: '0123456789abcdef',
      surfaceType: 'paywall',
      slug: 'annual-offer',
      contractVersion: 4,
    );
    await store.write(key, entry(1));

    expect(await store.read(other), isNull);
    expect(key, isNot(other));
    expect(
      key,
      const SurfaceStoreKey(
        scope: '0123456789abcdef',
        surfaceType: 'paywall',
        slug: 'annual-offer',
        contractVersion: 3,
      ),
    );
  });

  test('a corrupt or truncated file reads as null', () async {
    await store.write(key, entry(5));
    final file = root.listSync().whereType<File>().single;
    final bytes = await file.readAsBytes();

    await file.writeAsBytes(bytes.sublist(0, bytes.length - 1));
    expect(await store.read(key), isNull);

    await file.writeAsBytes(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(await store.read(key), isNull);
    expect(await store.keys(), isEmpty);
  });

  test('remove drops one entry', () async {
    const other = SurfaceStoreKey(
      scope: '0123456789abcdef',
      surfaceType: 'onboarding',
      slug: 'welcome',
      contractVersion: 0,
    );
    await store.write(key, entry(1));
    await store.write(other, entry(2));
    await store.remove(key);

    expect(await store.read(key), isNull);
    expect(await store.read(other), isNotNull);
    expect(await store.keys(), <SurfaceStoreKey>[other]);
  });

  test('clear removes every entry', () async {
    await store.write(key, entry(1));
    await store.clear();

    expect(await store.read(key), isNull);
    expect(await store.keys(), isEmpty);
  });

  test('without a usable directory the store keeps entries in memory',
      () async {
    final memoryOnly = createSurfaceArtifactStore(
      directory: () async => throw const FileSystemException('unavailable'),
    );
    await memoryOnly.write(key, entry(9));

    expect((await memoryOnly.read(key))!.artifactBytes, entry(9).artifactBytes);
  });

  test('scopeFor is stable, 16 hex characters, and environment-sensitive', () {
    final production = SurfaceStoreKey.scopeFor(
        apiKey: 'rk_live_1', environment: 'production');
    final sandbox =
        SurfaceStoreKey.scopeFor(apiKey: 'rk_live_1', environment: 'sandbox');

    expect(production, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(
      production,
      SurfaceStoreKey.scopeFor(apiKey: 'rk_live_1', environment: 'production'),
    );
    expect(production, isNot(sandbox));
  });
}
