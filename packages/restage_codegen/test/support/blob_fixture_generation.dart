import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:package_config/package_config.dart';
import 'package:restage_codegen/builder.dart';

import '../../tool/src/codegen_fixture_roster.dart';
import '../helpers.dart';

const _mountPackage = 'apps_examples';
const _examplePackage = 'restage_example';
const _skipPackages = <String>{
  'flutter',
  'sky_engine',
  'restage',
  'restage_core',
  'restage_shared',
  'rfw',
  'rfw_catalog_schema',
  'intl',
};

/// Runs the production builders for exactly the selected source group.
Future<TestBuilderResult> buildBlobFixtures(
  List<String> ids, {
  bool navigation = false,
}) async {
  final rw = await _seedRealCorpus(ids);
  final sources = <String, String>{
    for (final id in ids)
      '$_mountPackage|lib/paywalls/$id.dart': rw.testing.readString(
        AssetId(_mountPackage, 'lib/paywalls/$id.dart'),
      ),
  };
  return await testBuilders(
    [
      restageCodegenBuilder(BuilderOptions.empty),
      if (navigation) paywallFlowBuilder(BuilderOptions.empty),
    ],
    sources,
    rootPackage: _mountPackage,
    readerWriter: rw,
    flattenOutput: true,
  );
}

/// Captures the complete golden roster from an actual production build.
Map<String, List<int>> captureBlobFixture(
  TestBuilderResult result,
  String fixture,
) {
  if (!result.succeeded || result.errors.isNotEmpty) {
    throw StateError('Fixture build failed: ${result.errors.join('\n')}');
  }
  return {
    for (final entry in blobFixtureArtifacts(fixture).entries)
      entry.key: result.readerWriter.testing.readBytes(
        AssetId(_mountPackage, entry.value),
      ),
  };
}

/// Builds a [TestReaderWriter] whose in-memory filesystem can resolve the real
/// example paywall sources end-to-end.
///
/// The base [readerWriterWithFilesystemSources] seeds `flutter`, `restage` (+
/// its transitive closure), `rfw_catalog_schema`, and the catalog data.
/// On top of that, this:
///   * seeds the `restage_material` source closure (the example sources import
///     it for `RestagePager` etc.), which the base does not reach; and
///   * re-homes the `restage_example|lib` files the paywalls reach — the four
///     `widgets/*_plan_selector.dart` selectors plus the paywalls themselves —
///     into the synthetic `apps_examples` package the harness mounts under, so
///     their relative `../widgets/...` imports resolve.
///
/// Cross-package directives into already-seeded packages ([_skipPackages]) are
/// not re-walked.
Future<TestReaderWriter> _seedRealCorpus(List<String> paywallIds) async {
  final rw = await readerWriterWithFilesystemSources(
    rootPackage: _mountPackage,
    includeFlutter: true,
  );
  final config = await loadPackageConfigUri((await Isolate.packageConfig)!);
  final reader = PackageAssetReader(config, 'restage_codegen');

  final seen = <AssetId>{};
  final queue = Queue<AssetId>()
    ..add(AssetId('restage_material', 'lib/restage_material.dart'))
    ..add(AssetId('restage_cupertino', 'lib/restage_cupertino.dart'));
  for (final id in paywallIds) {
    queue.add(AssetId(_examplePackage, 'lib/paywalls/$id.dart'));
  }

  while (queue.isNotEmpty) {
    final id = queue.removeFirst();
    if (!seen.add(id)) continue;
    if (_skipPackages.contains(id.package)) continue;
    if (!id.path.startsWith('lib/')) continue;
    if (!await reader.canRead(id)) continue;
    final bytes = await reader.readAsBytes(id);
    // The example package is re-homed under the synthetic mount package so its
    // relative imports resolve; every other package keeps its real id.
    final target =
        id.package == _examplePackage ? AssetId(_mountPackage, id.path) : id;
    rw.testing.writeBytes(target, bytes);
    if (!id.path.endsWith('.dart')) continue;
    _directiveDeps(id, utf8.decode(bytes)).forEach(queue.add);
  }
  return rw;
}

/// The `package:`/`asset:` Dart-file dependencies declared by [source]
/// (resolved against [from]). `dart:` imports and non-package schemes are
/// skipped — they need no seeding.
Iterable<AssetId> _directiveDeps(AssetId from, String source) sync* {
  final parsed = parseString(
    content: source,
    path: from.path,
    throwIfDiagnostics: false,
  );
  for (final directive in parsed.unit.directives) {
    if (directive is! UriBasedDirective) continue;
    final uriText = directive.uri.stringValue;
    if (uriText == null) continue;
    final uri = Uri.tryParse(uriText);
    if (uri == null || uri.scheme == 'dart') continue;
    if (uri.hasScheme && uri.scheme != 'package' && uri.scheme != 'asset') {
      continue;
    }
    final id = AssetId.resolve(uri, from: from);
    if (id.path.endsWith('.dart')) yield id;
  }
}
