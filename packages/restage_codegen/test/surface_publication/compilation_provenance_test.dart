import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compilation_provenance.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
    'compilation provenance separates SDK upgrades from app and part edits',
    () async {
      final original = await _compile();
      final sdk = await _compile(sdkVersion: '2.0.0');
      final compiler = await _compile(compilerVersion: '2.0.0');
      final compilerSource = await _compile(compilerSource: '2');
      final analyzer = await _compile(analyzerVersion: '2.0.0');
      final helper = await _compile(helper: '2');
      final generatedHelper = await _compile(generatedHelper: '2');
      final generatedLibrary = await _compile(generatedLibrary: '2');
      final app = await _compile(screen: 'final value = shade + 1;');
      expect(sdk.sourceHash, original.sourceHash);
      expect(sdk.toolchainHash, isNot(original.toolchainHash));
      expect(compiler.sourceHash, original.sourceHash);
      expect(compiler.toolchainHash, isNot(original.toolchainHash));
      expect(compilerSource.sourceHash, original.sourceHash);
      expect(compilerSource.toolchainHash, isNot(original.toolchainHash));
      expect(analyzer.sourceHash, original.sourceHash);
      expect(analyzer.toolchainHash, isNot(original.toolchainHash));
      expect(helper.sourceHash, isNot(original.sourceHash));
      expect(helper.toolchainHash, original.toolchainHash);
      expect(generatedHelper.sourceHash, isNot(original.sourceHash));
      expect(generatedHelper.toolchainHash, original.toolchainHash);
      expect(generatedLibrary.sourceHash, isNot(original.sourceHash));
      expect(generatedLibrary.toolchainHash, original.toolchainHash);
      expect(app.sourceHash, isNot(original.sourceHash));
      expect(app.toolchainHash, original.toolchainHash);
      expect(original.packageVersions['restage_codegen'], '1.0.0');
    },
  );

  test(
    'compilation provenance is ordered and ignores Restage generated parts',
    () async {
      final original = await _compile();
      final reordered = await _compile(
        reverse: true,
        generated: 'changed output',
      );
      expect(reordered.toJson(), original.toJson());
    },
  );
}

Future<SurfaceCompilationProvenance> _compile({
  String sdkVersion = '1.0.0',
  String compilerVersion = '1.0.0',
  String helper = '1',
  String generatedHelper = '1',
  String generatedLibrary = '1',
  String compilerSource = '1',
  String analyzerVersion = '1.0.0',
  String screen = 'final value = shade;',
  String generated = 'original output',
  bool reverse = false,
}) async {
  final sources = <String, Object>{
    'probe|pubspec.yaml':
        'name: probe\ndependencies:\n'
        '  restage: ^$sdkVersion\n  design: any\n'
        'dev_dependencies:\n  restage_codegen: ^$compilerVersion\n',
    'probe|lib/screen.dart':
        "import 'package:restage/restage.dart';\n"
        "import 'package:design/design.dart';\n$screen",
    'probe|lib/restage.generated/screen.restage.g.dart': generated,
    'probe|lib/user_factories.g.dart': generated,
    'probe|lib/restage_surfaces.g.dart': generated,
    'design|pubspec.yaml': 'name: design\nversion: 1.0.0\n',
    'design|lib/design.dart':
        "import 'api.g.dart'; part 'palette.dart'; part 'palette.g.dart';",
    'design|lib/palette.dart': "part of 'design.dart'; const shade = $helper;",
    'design|lib/palette.g.dart':
        "part of 'design.dart'; const tone = $generatedHelper;",
    'design|lib/api.g.dart': 'const generatedApi = $generatedLibrary;',
    'restage|pubspec.yaml': 'name: restage\nversion: $sdkVersion\n',
    'restage|lib/restage.dart': 'class Surface {}',
    for (final name in [
      'restage_codegen',
      'restage_compiler_core',
      'rfw_catalog_compiler',
    ])
      '$name|pubspec.yaml':
          'name: $name\nversion: $compilerVersion\n'
          'dependencies:\n  analyzer: any\n',
    'analyzer|pubspec.yaml': 'name: analyzer\nversion: $analyzerVersion\n',
    'restage_codegen|lib/compiler.dart': 'const version = $compilerSource;',
  };
  final writer = TestReaderWriter(rootPackage: 'probe');
  await testBuilder(
    _ProvenanceBuilder(),
    reverse ? Map.fromEntries(sources.entries.toList().reversed) : sources,
    rootPackage: 'probe',
    readerWriter: writer,
    flattenOutput: true,
  );
  return SurfaceCompilationProvenance.fromJson(
    jsonDecode(writer.testing.readString(AssetId('probe', 'provenance.json'))),
  );
}

class _ProvenanceBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': ['provenance.json'],
  };

  @override
  Future<void> build(BuildStep step) async {
    final library = await step.resolver.libraryFor(
      AssetId(step.inputId.package, 'lib/screen.dart'),
    );
    final provenance = await collectCompilationProvenance(
      step,
      [library],
      compilerAssets: [AssetId('restage_codegen', 'lib/compiler.dart')],
    );
    await step.writeAsString(
      AssetId(step.inputId.package, 'provenance.json'),
      jsonEncode(provenance!.toJson()),
    );
  }
}
