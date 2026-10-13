import 'dart:io';
import 'dart:isolate';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../../tool/derive_render_bundle_engine_set.dart';

/// Identifier the pinned Flutter version's engine files serve under.
///
/// It moves only when the set itself moves, so a change here is a deliberate
/// republish of every bundle's engine base.
const _pinnedEngineSetId =
    '9140d63144c2c037701c4e3386927b3651e36b69fca953d651d119e0bbe7c3d5';

const _derivationTool =
    'packages/restage_shared/tool/derive_render_bundle_engine_set.dart';

const _builderSource =
    'restage_cli/lib/src/render_bundles/flutter_render_bundle_builder.dart';

final _builderVersionPattern = RegExp(
  r"^const requiredRenderBundleFlutterVersion = '([^']*)';$",
  multiLine: true,
);

void main() {
  test('the newest set keeps its identifier and canonical form', () {
    final set = newestRenderBundleEngineSet;
    expect(
      set.id,
      _pinnedEngineSetId,
      reason: 'The engine base URL carries this identifier. Re-derive with '
          '$_derivationTool and update every place that pins it.',
    );
    expect(set.canonicalForm, startsWith('restage.render-bundle-engine-set.'));
    expect(
      set.canonicalForm,
      contains('\nflutter ${set.flutterVersion}\n'),
    );
    expect(
      set.canonicalForm,
      contains('\nskwasm.wasm sha256:'),
    );
  });

  test('sets are pinned once per Flutter version, oldest first', () {
    expect(renderBundleEngineSets, isNotEmpty);
    final identifiers = <String>{};
    for (var index = 0; index < renderBundleEngineSets.length; index++) {
      final set = renderBundleEngineSets[index];
      expect(
        identifiers.add(set.id),
        isTrue,
        reason: 'Two sets share an identifier, so they would share a path.',
      );
      expect(renderBundleEngineSetById(set.id), same(set));
      expect(
        renderBundleEngineSetForFlutterVersion(set.flutterVersion),
        same(set),
      );
      if (index == 0) continue;
      expect(
        _compareVersions(
          renderBundleEngineSets[index - 1].flutterVersion,
          set.flutterVersion,
        ),
        lessThan(0),
        reason: 'Sets are appended in Flutter version order.',
      );
    }
    expect(newestRenderBundleEngineSet, same(renderBundleEngineSets.last));
  });

  test('the build toolchain pin and the newest set name one version', () {
    final source = File(
      '${_packagesDirectory()}/$_builderSource',
    );
    expect(
      source.existsSync(),
      isTrue,
      reason: 'The build toolchain pin is read from ${source.path}.',
    );
    final matches =
        _builderVersionPattern.allMatches(source.readAsStringSync()).toList();
    expect(
      matches,
      hasLength(1),
      reason: 'Exactly one statement declares the build toolchain pin in '
          '$_builderSource.',
    );
    expect(
      matches.single.group(1),
      newestRenderBundleEngineSet.flutterVersion,
      reason: 'A bundle built on one Flutter version would look for the engine '
          'of another. Re-derive the set with $_derivationTool and append it.',
    );
  });

  test('the newest set matches the installed Flutter SDK', () {
    final sdkRoot = findFlutterSdkRoot();
    if (sdkRoot == null) {
      markTestSkipped('No Flutter SDK is reachable from this machine.');
      return;
    }
    final expected = newestRenderBundleEngineSet;
    expect(
      readFlutterVersion(sdkRoot),
      expected.flutterVersion,
      reason: 'The installed SDK ships engine files this set does not name. '
          'Derive the set for it with $_derivationTool and append it.',
    );

    final derived = deriveRenderBundleEngineSet(sdkRoot);
    expect(
      derived.files.map((file) => file.path).toList(),
      expected.files.map((file) => file.path).toList(),
      reason: 'The SDK holds a different set of engine files. Re-derive with '
          '$_derivationTool.',
    );
    expect(
      derived.files,
      expected.files,
      reason:
          'An engine file changed under the same Flutter version. Re-derive '
          'with $_derivationTool.',
    );
    expect(derived.id, expected.id);
    expect(
      derived.files.any((file) => file.path.endsWith('.symbols')),
      isFalse,
      reason: 'Source maps are left out of the set and out of a bundle.',
    );
  });

  test('a bundle path maps to the set entry the loader asks for', () {
    const bundlePath = '${renderBundleEnginePathPrefix}chromium/canvaskit.wasm';
    final set = newestRenderBundleEngineSet;
    final enginePath = bundlePath.substring(
      renderBundleEnginePathPrefix.length,
    );
    final file = set.fileForPath(enginePath);
    expect(file, isNotNull);
    expect(set.holds(path: enginePath, contentHash: file!.contentHash), isTrue);
    expect(
      set.holds(path: enginePath, contentHash: 'sha256:${'0' * 64}'),
      isFalse,
    );
    expect(set.fileForPath('canvaskit/canvaskit.wasm'), isNull);
    expect(set.fileForPath('skwasm.js.symbols'), isNull);
    expect(set.byteLength, 29268643);
  });

  test('a set refuses a shape the loader could not resolve', () {
    RenderBundleEngineFile file(String path) => RenderBundleEngineFile(
          path: path,
          contentHash: 'sha256:${'a' * 64}',
          byteLength: 1,
        );

    expect(() => file('../escape.wasm'), throwsFormatException);
    expect(() => file('/absolute.wasm'), throwsFormatException);
    expect(() => file('has space.wasm'), throwsFormatException);
    expect(
      () => RenderBundleEngineFile(
        path: 'a.wasm',
        contentHash: 'sha256:${'A' * 64}',
        byteLength: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineFile(
        path: 'a.wasm',
        contentHash: 'sha256:${'a' * 64}',
        byteLength: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        files: <RenderBundleEngineFile>[file('b.wasm'), file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        files: <RenderBundleEngineFile>[file('a.wasm'), file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: 'latest',
        files: <RenderBundleEngineFile>[file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        files: const <RenderBundleEngineFile>[],
      ),
      throwsFormatException,
    );
  });
}

/// Directory holding every package, resolved through this package's own URI.
String _packagesDirectory() {
  final uri = Isolate.resolvePackageUriSync(
    Uri.parse('package:restage_shared/restage_shared.dart'),
  );
  if (uri == null) {
    throw StateError('This package could not resolve its own location.');
  }
  final path = uri.toFilePath().replaceAll(r'\', '/');
  const suffix = '/restage_shared/lib/restage_shared.dart';
  if (!path.endsWith(suffix)) {
    throw StateError('Unexpected package layout at $path.');
  }
  return path.substring(0, path.length - suffix.length);
}

int _compareVersions(String left, String right) {
  final leftParts = left.split('.').map(int.parse).toList();
  final rightParts = right.split('.').map(int.parse).toList();
  for (var index = 0; index < 3; index++) {
    final order = leftParts[index].compareTo(rightParts[index]);
    if (order != 0) return order;
  }
  return 0;
}
