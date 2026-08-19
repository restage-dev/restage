import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('RestageBundleCodec', () {
    test('encodes deterministic sorted store-only bundle metadata', () {
      final bundle = RestageBundle(
        packageName: 'example_package',
        authoredLibraryPath: 'lib/features/welcome.dart',
        entries: <RestageBundleEntry>[
          RestageBundleEntry(
            logicalPath: 'assets/general/screens/welcome.rfw',
            role: RestageBundleEntryRoleV1.screenBlob,
            bytes: const <int>[0, 255, 1, 2],
          ),
          RestageBundleEntry(
            logicalPath: 'assets/general/screens/welcome.capability.json',
            role: RestageBundleEntryRoleV1.capabilitySidecar,
            bytes: utf8.encode('{"blobSha256":"sha256:example"}'),
          ),
        ],
      );

      final first = RestageBundleCodec.encode(bundle);
      final second = RestageBundleCodec.encode(bundle);
      final decoded = RestageBundleCodec.decode(first);

      expect(first, orderedEquals(second));
      expect(
        decoded.entries.map((entry) => entry.logicalPath),
        orderedEquals(<String>[
          'assets/general/screens/welcome.capability.json',
          'assets/general/screens/welcome.rfw',
        ]),
      );
      expect(
          decoded.entries[1].bytes, orderedEquals(const <int>[0, 255, 1, 2]));
      expect(decoded.metadata.packageName, 'example_package');
      expect(decoded.metadata.authoredLibraryPath, 'lib/features/welcome.dart');
      expect(
        decoded.metadata.entries.map((entry) => entry.sha256),
        everyElement(matches(RegExp(r'^sha256:[0-9a-f]{64}$'))),
      );
    });
  });
}
