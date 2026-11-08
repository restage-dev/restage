import 'package:meta/meta.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// Diagnostic build inputs, separate from the installed screen contract.
@immutable
final class SurfaceCompilationProvenance {
  /// Records hashes of app inputs and toolchain inputs without source text.
  factory SurfaceCompilationProvenance({
    required String sourceHash,
    required String toolchainHash,
    required Map<String, String> packageVersions,
  }) {
    SurfaceContractJson.requireSha256(sourceHash, 'provenance.sourceHash');
    SurfaceContractJson.requireSha256(
      toolchainHash,
      'provenance.toolchainHash',
    );
    if (packageVersions.isEmpty || packageVersions.length > 64) {
      throw const FormatException('Invalid compilation package versions.');
    }
    final packages = packageVersions.keys.toList()..sort();
    final canonicalVersions = <String, String>{};
    for (final package in packages) {
      final version = packageVersions[package]!;
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(package) ||
          version.isEmpty ||
          version.length > 128 ||
          version.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw const FormatException('Invalid compilation package version.');
      }
      canonicalVersions[package] = version;
    }
    return SurfaceCompilationProvenance._(
      sourceHash,
      toolchainHash,
      Map.unmodifiable(canonicalVersions),
    );
  }

  const SurfaceCompilationProvenance._(
    this.sourceHash,
    this.toolchainHash,
    this.packageVersions,
  );

  /// Decodes diagnostic metadata strictly.
  factory SurfaceCompilationProvenance.fromJson(Object? value) {
    const path = 'compilationProvenance';
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.exactKeys(
      json,
      const {'sourceHash', 'toolchainHash', 'packageVersions'},
      path,
    );
    final versions = SurfaceContractJson.requireObject(
      json['packageVersions'],
      '$path.packageVersions',
    );
    return SurfaceCompilationProvenance(
      sourceHash: SurfaceContractJson.requiredString(json, 'sourceHash', path),
      toolchainHash:
          SurfaceContractJson.requiredString(json, 'toolchainHash', path),
      packageVersions: {
        for (final key in versions.keys)
          key: SurfaceContractJson.requiredString(versions, key, path),
      },
    );
  }

  /// Digest of app code, imported application libraries and build settings.
  final String sourceHash;

  /// Digest of the compiler and SDK inputs used by this compilation.
  final String toolchainHash;

  /// Resolved compiler and SDK versions, in package-name order.
  final Map<String, String> packageVersions;

  /// Encodes diagnostic metadata; these fields never enter contract hashes.
  Map<String, Object?> toJson() => {
        'sourceHash': sourceHash,
        'toolchainHash': toolchainHash,
        'packageVersions': packageVersions,
      };
}
