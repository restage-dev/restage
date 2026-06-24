import 'package:build/build.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogPerBuildCache', () {
    test('keys the merged catalog by input package — no cross-package leak',
        () async {
      // A stub loader that stamps the catalog with the requesting package, so a
      // leak — package B receiving package A's merged catalog — is observable.
      // The real loader merges `buildStep.inputId.package`'s custom catalog, so
      // a single cross-pass cache would serve one package's customs to another.
      final cache = CatalogPerBuildCache(
        load: (buildStep) async => _stamped(buildStep.inputId.package),
      );

      final a = await cache.getOrLoad(_FakeBuildStep('pkg_a'));
      final b = await cache.getOrLoad(_FakeBuildStep('pkg_b'));

      expect(a.generatedAt, 'pkg_a');
      // The cross-pass-cache bug would serve pkg_a's catalog here.
      expect(b.generatedAt, 'pkg_b');
    });

    test('still shares one load across BuildSteps of the SAME package',
        () async {
      var loads = 0;
      final cache = CatalogPerBuildCache(
        load: (buildStep) async {
          loads += 1;
          return _stamped(buildStep.inputId.package);
        },
      );

      final first = await cache.getOrLoad(_FakeBuildStep('pkg_a'));
      final second = await cache.getOrLoad(_FakeBuildStep('pkg_a'));

      // One load shared across the package's BuildSteps (the original
      // within-pass dedup the cache exists for).
      expect(loads, 1);
      expect(identical(first, second), isTrue);
    });
  });
}

Catalog _stamped(String stamp) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: stamp,
      libraries: const {},
      widgets: const [],
    );

/// A minimal [BuildStep] exposing only the surface the cache uses:
/// [inputId] (the cache key) and [canRead] (the dependency registration).
class _FakeBuildStep implements BuildStep {
  _FakeBuildStep(this._package);

  final String _package;

  @override
  AssetId get inputId => AssetId(_package, 'lib/paywalls/example.dart');

  @override
  Future<bool> canRead(AssetId id) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
