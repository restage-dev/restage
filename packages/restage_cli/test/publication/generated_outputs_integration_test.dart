import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

/// End-to-end producer/consumer agreement against REAL generated output.
///
/// Every other test in this directory builds its fixtures by hand, which proves
/// the consumer reads what it is given but cannot prove the producer writes what
/// the consumer expects. Both sides passed their own unit tests while disagreeing
/// about whether text-role entries belong in the index; only running the real
/// generated index through the real loader surfaced it. This is that check.
///
/// The generated index is reproducible build output and is not tracked, so a
/// checkout that has not run the generator skips loudly rather than failing —
/// but a checkout that HAS run it gets the full comparison.
const _packages = <String, String>{
  // Public-bound; always present.
  'restage_example': '../../apps/examples',
  // Private; absent from the extracted public tree, hence discovered rather
  // than required.
  'restage_widgetbook_example': '../restage_widgetbook_example',
};

void main() {
  group('generated output index resolves against shipped bundles', () {
    for (final entry in _packages.entries) {
      test(entry.key, () async {
        final root = Directory(
          p.normalize(p.join(Directory.current.path, entry.value)),
        );
        final indexFile = File(
          p.join(root.path, 'lib', 'generated', 'restage.outputs.json'),
        );
        if (!indexFile.existsSync()) {
          markTestSkipped(
            'No generated output index at ${indexFile.path}. Run '
            '`dart run build_runner build` in ${entry.value} to exercise this.',
          );
          return;
        }

        // (1) The real index decodes through the consumer's strict decoder.
        final index = RestageOutputIndex.decodeJson(
          indexFile.readAsStringSync(),
        );
        expect(index.packageName, entry.key);
        expect(index.entries, isNotEmpty);

        // (2) The recorded fingerprint verifies against the real manifest bytes.
        final manifestFile = File(
          p.join(root.path, index.publicationManifestPath),
        );
        expect(
          manifestFile.existsSync(),
          isTrue,
          reason:
              'the index names a manifest that does not exist: '
              '${index.publicationManifestPath}',
        );
        final manifestSource = manifestFile.readAsStringSync();
        expect(
          CapabilitySidecar.hashBlob(utf8.encode(manifestSource)),
          index.generationFingerprint,
          reason: 'the index is stale against its own publication manifest',
        );

        // (3) The production load path resolves the package root with no
        //     ambiguity and no "generation required".
        final loaded = await const RestagePublicationOutputsLoader().load(
          projectRoot: root,
        );
        expect(loaded.index.entries, hasLength(index.entries.length));

        // (4) Index and manifest agree exactly. This bijection is the drift
        //     detector that caught the text-role disagreement, so it is
        //     asserted against real output rather than a fixture.
        final manifest = SurfacePublicationManifestV1Codec.decodeJson(
          loaded.publicationManifestSource,
        );
        loaded.index.validateAgainstManifest(manifest);

        // (5) Every recorded locator resolves to real bytes at the recorded
        //     hash, inside the container the locator names.
        final containers = <String, Map<String, List<int>>>{};
        for (final locator in index.entries) {
          final bundleFile = File(p.join(root.path, locator.bundle));
          expect(
            bundleFile.existsSync(),
            isTrue,
            reason: '${locator.path} names a missing bundle ${locator.bundle}',
          );
          final entries = containers.putIfAbsent(locator.bundle, () {
            final bundle = RestageBundleCodec.decode(
              bundleFile.readAsBytesSync(),
            );
            return <String, List<int>>{
              for (final packaged in bundle.entries)
                packaged.logicalPath: packaged.bytes,
            };
          });
          final bytes = entries[locator.entry];
          expect(
            bytes,
            isNotNull,
            reason: '${locator.bundle} does not carry ${locator.entry}',
          );
          expect(
            'sha256:${crypto.sha256.convert(bytes!)}',
            locator.sha256,
            reason:
                'packaged bytes for ${locator.path} do not match the '
                'hash the index recorded',
          );
        }
      });
    }
  });
}
