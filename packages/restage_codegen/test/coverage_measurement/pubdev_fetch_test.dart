import 'dart:io';

import 'package:restage_codegen/src/coverage_measurement/pubdev_fetch.dart';
import 'package:test/test.dart';

void main() {
  group('locatePackageInCache', () {
    late Directory cache;

    setUp(() {
      cache = Directory.systemTemp.createTempSync('b3_fakecache_');
      for (final v in ['2.0.0', '2.0.1', '2.0.10']) {
        Directory(
          '${cache.path}/hosted/pub.dev/gap-$v',
        ).createSync(recursive: true);
      }
    });
    tearDown(() => cache.deleteSync(recursive: true));

    test('pins an exact version when given', () {
      final dir = locatePackageInCache(
        cacheRoot: cache.path,
        package: 'gap',
        version: '2.0.0',
      );
      expect(dir, endsWith('/gap-2.0.0'));
    });

    test('returns null for a pinned version that is not cached', () {
      final dir = locatePackageInCache(
        cacheRoot: cache.path,
        package: 'gap',
        version: '9.9.9',
      );
      expect(dir, isNull);
    });

    test('picks the highest version when unpinned (numeric segment compare)',
        () {
      final dir = locatePackageInCache(cacheRoot: cache.path, package: 'gap');
      // 2.0.10 > 2.0.1 numerically (not lexicographically).
      expect(dir, endsWith('/gap-2.0.10'));
    });

    test('returns null when no matching package is cached', () {
      final dir =
          locatePackageInCache(cacheRoot: cache.path, package: 'absent');
      expect(dir, isNull);
    });

    test('returns null when the cache has no hosted dir', () {
      final empty = Directory.systemTemp.createTempSync('b3_emptycache_');
      addTearDown(() => empty.deleteSync(recursive: true));
      expect(
        locatePackageInCache(cacheRoot: empty.path, package: 'gap'),
        isNull,
      );
    });
  });

  group('compareVersionStrings', () {
    test('orders by numeric segments, not lexicographically', () {
      expect(compareVersionStrings('2.0.10', '2.0.1'), greaterThan(0));
      expect(compareVersionStrings('2.0.1', '2.0.10'), lessThan(0));
      expect(compareVersionStrings('1.0.0', '1.0.0'), 0);
      expect(compareVersionStrings('10.0.0', '9.9.9'), greaterThan(0));
    });
  });

  group('fetchPubPackageToTemp (faked process + cache)', () {
    late Directory fakeCache;

    setUp(() {
      fakeCache = Directory.systemTemp.createTempSync('b3_fetchcache_');
      final lib = Directory('${fakeCache.path}/hosted/pub.dev/gap-1.2.3/lib')
        ..createSync(recursive: true);
      File('${lib.path}/gap.dart').writeAsStringSync('// gap\n');
      File(
        '${fakeCache.path}/hosted/pub.dev/gap-1.2.3/pubspec.yaml',
      ).writeAsStringSync('name: gap\n');
    });
    tearDown(() => fakeCache.deleteSync(recursive: true));

    test('copies the located package to a temp dir and resolves the version',
        () async {
      final calls = <List<String>>[];
      Future<ProcessResult> fakeRun(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        calls.add([exe, ...args]);
        return ProcessResult(0, 0, '', '');
      }

      final fetched = await fetchPubPackageToTemp(
        package: 'gap',
        version: '1.2.3',
        pubCacheRoot: fakeCache.path,
        runProcess: fakeRun,
      );
      addTearDown(fetched.dispose);

      expect(fetched.version, '1.2.3');
      expect(File('${fetched.directory}/lib/gap.dart').existsSync(), isTrue);
      expect(File('${fetched.directory}/pubspec.yaml').existsSync(), isTrue);
      // The temp copy is a fresh location, not the cache dir itself.
      expect(fetched.directory, isNot(contains('hosted/pub.dev')));
      // `pub cache add` then `flutter pub get` were both invoked.
      expect(
        calls.any((c) => c.contains('cache') && c.contains('add')),
        isTrue,
      );
      expect(
        calls.any((c) => c.first == 'flutter' && c.contains('get')),
        isTrue,
      );
    });

    test('throws PubFetchException when pub cache add fails', () async {
      Future<ProcessResult> failRun(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async =>
          ProcessResult(0, 1, '', 'cache add boom');

      await expectLater(
        fetchPubPackageToTemp(
          package: 'gap',
          version: '1.2.3',
          pubCacheRoot: fakeCache.path,
          runProcess: failRun,
        ),
        throwsA(isA<PubFetchException>()),
      );
    });

    test('throws PubFetchException when the package is not cached after add',
        () async {
      Future<ProcessResult> okRun(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async =>
          ProcessResult(0, 0, '', '');

      await expectLater(
        fetchPubPackageToTemp(
          package: 'absent',
          pubCacheRoot: fakeCache.path,
          runProcess: okRun,
        ),
        throwsA(isA<PubFetchException>()),
      );
    });

    test('throws (and cleans up) when flutter pub get fails', () async {
      Future<ProcessResult> getFailsRun(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async =>
          exe == 'flutter'
              ? ProcessResult(0, 1, '', 'pub get boom')
              : ProcessResult(0, 0, '', '');

      await expectLater(
        fetchPubPackageToTemp(
          package: 'gap',
          version: '1.2.3',
          pubCacheRoot: fakeCache.path,
          runProcess: getFailsRun,
        ),
        throwsA(isA<PubFetchException>()),
      );
    });
  });
}
