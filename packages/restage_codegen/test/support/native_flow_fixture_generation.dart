import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/restage_codegen.dart' show formatGeneratedDart;
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';

import '../helpers.dart';

/// Compiler-owned native mount fixture output.
const nativeFlowFixturePath =
    '../restage/test/fixtures/compiled_surfaces/restage.generated/native_flow.restage.g.dart';

/// Authored native mount fixture input.
const nativeFlowFixtureSourcePath =
    '../restage/test/fixtures/compiled_surfaces/native_flow.dart';

/// Exact authored native mount input, keyed by its fixture source path.
Map<String, String> nativeFlowFixtureSourceInputs() => {
      nativeFlowFixtureSourcePath:
          File(nativeFlowFixtureSourcePath).readAsStringSync(),
    };

/// Native source, production output, and its exact retained formatting.
final class NativeFlowFixtureCandidate {
  const NativeFlowFixtureCandidate({
    required this.source,
    required this.result,
    required this.bundle,
    required this.generated,
    required this.rendered,
  });

  final String source;
  final TestBuilderResult result;
  final RestageSurfacePublicationBundle bundle;
  final String generated;
  final String rendered;
}

/// Compiles the original authored native flow through its package owner.
Future<NativeFlowFixtureCandidate> compileNativeFlowFixture() async {
  final source = nativeFlowFixtureSourceInputs()[nativeFlowFixtureSourcePath]!;
  final rw =
      await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
    {'apps_examples|lib/native_flow.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: rw,
    flattenOutput: true,
  );
  requireFixtureBuild(result);
  final bundle = readFixtureCompilerBundle(rw);
  final generated = utf8.decode(
    bundle.ownedOutputs['lib/restage.generated/native_flow.restage.g.dart']!,
  );
  return NativeFlowFixtureCandidate(
    source: source,
    result: result,
    bundle: bundle,
    generated: generated,
    rendered: formatNativeFlowFixture(generated),
  );
}

/// Preserves the retained fixture package's Dart language formatting.
String formatNativeFlowFixture(String generated) =>
    formatGeneratedDart(generated, languageVersion: Version(3, 5, 0));

/// Rejects a failed production build before reading its outputs.
void requireFixtureBuild(TestBuilderResult result) {
  if (!result.succeeded) throw StateError(result.errors.join('\n'));
}

/// Reads the valid compiler-owned publication bundle.
RestageSurfacePublicationBundle readFixtureCompilerBundle(TestReaderWriter rw) {
  final bundle = RestageSurfacePublicationBundle.fromJson(
    jsonDecode(
      rw.testing.readString(
        AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
      ),
    ),
  );
  if (!bundle.valid) throw StateError(bundle.errors.join('\n'));
  return bundle;
}
