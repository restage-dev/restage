import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/delivery/surface_artifact_store_io.dart'
    show surfaceReadAheadIsolateName;

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

  test('a write it cannot keep reports the failure', () async {
    await store.write(key, entry(1));
    await Process.run('chmod', ['555', root.path]);
    addTearDown(() => Process.run('chmod', ['755', root.path]));
    await expectLater(store.write(key, entry(2)), throwsA(anything));
    expect((await store.read(key))!.artifactBytes, entry(1).artifactBytes);
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

  test('keys follow this store\'s writes and removes after one scan', () async {
    const other = SurfaceStoreKey(
      scope: '0123456789abcdef',
      surfaceType: 'onboarding',
      slug: 'welcome',
      contractVersion: 0,
    );
    await store.write(key, entry(1));
    expect(await store.keys(), <SurfaceStoreKey>[key]);
    // A file another writer adds after the scan is not listed.
    await createSurfaceArtifactStore(directory: () async => root.path)
        .write(other, entry(2));
    expect(await store.keys(), <SurfaceStoreKey>[key]);

    await store.write(other, entry(3));
    expect(await store.keys(), unorderedEquals([key, other]));
    await store.remove(key);
    expect(await store.keys(), <SurfaceStoreKey>[other]);
    await store.clear();
    expect(await store.keys(), isEmpty);
  });

  test('a scope read returns one scope and type, and indexes every key',
      () async {
    const otherType = SurfaceStoreKey(
        scope: '0123456789abcdef',
        surfaceType: 'onboarding',
        slug: 'welcome',
        contractVersion: 0);
    const otherScope = SurfaceStoreKey(
        scope: 'fedcba9876543210',
        surfaceType: 'paywall',
        slug: 'annual-offer',
        contractVersion: 3);
    final writer = createSurfaceArtifactStore(directory: () async => root.path);
    for (final (index, written) in [key, otherType, otherScope].indexed) {
      await writer.write(written, entry(index));
    }
    File('${root.path}/unreadable.surface').writeAsBytesSync([1, 2, 3]);
    final read = await readStoreScope(
        store, key.scope, const {'paywall'}, _servedVersions);
    expect(read, [(key, 0)]);
    expect(await store.keys(), unorderedEquals([key, otherType, otherScope]));
  });

  test('a scope read takes other scopes from their headers alone', () async {
    const otherScope = SurfaceStoreKey(
        scope: 'fedcba9876543210',
        surfaceType: 'paywall',
        slug: 'annual-offer',
        contractVersion: 3);
    final writer = createSurfaceArtifactStore(directory: () async => root.path);
    await writer.write(key, entry(0));
    await writer.write(otherScope, entry(1));
    // The other scope's body is cut off after its header.
    for (final file in root.listSync().whereType<File>()) {
      final bytes = file.readAsBytesSync();
      final headerLength = ByteData.sublistView(bytes, 4, 8).getUint32(0);
      if (String.fromCharCodes(bytes.sublist(8, 8 + headerLength))
          .contains(otherScope.scope)) {
        file.writeAsBytesSync(bytes.sublist(0, 8 + headerLength));
      }
    }
    final fresh = createSurfaceArtifactStore(directory: () async => root.path);
    final read = await readStoreScope(
        fresh, key.scope, const {'paywall'}, _servedVersions);
    expect(read, [(key, 0)]);
    expect(await fresh.keys(), unorderedEquals([key, otherScope]));
  });

  test('an off-isolate scope read runs its pass in the read-ahead isolate',
      () async {
    await store.write(key, entry(1));
    final offIsolate = createSurfaceArtifactStore(
        directory: () async => root.path, readsOffIsolate: true);
    final (isolate, keys) = await readStoreScope(
        offIsolate, key.scope, const {'paywall'}, _isolateOf);
    expect(isolate, surfaceReadAheadIsolateName);
    expect(keys, [key]);
    expect(await offIsolate.keys(), [key]);
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

List<(SurfaceStoreKey, Object?)> _servedVersions(StoredScopeRows rows) =>
    [for (final (key, value) in rows) (key, value.sidecar['servedVersion'])];

(String?, List<SurfaceStoreKey>) _isolateOf(StoredScopeRows rows) =>
    (Isolate.current.debugName, [for (final (key, _) in rows) key]);
