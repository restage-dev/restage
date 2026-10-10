import 'dart:convert';

import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'flow_experiment_test_support.dart';

const _ns = 'acme.widgets';

LibraryRequirement _requires(int minVersion) =>
    LibraryRequirement(namespace: _ns, minVersion: minVersion);

void main() {
  group('LibraryCompatibility.evaluate', () {
    final cases = <(InstalledLibrary?, int, LibraryCompatibility)>[
      (null, 1, LibraryCompatibility.missing),
      (const InstalledLibrary(namespace: _ns), 1, LibraryCompatibility.missing),
      (
        const InstalledLibrary(namespace: _ns, version: 2),
        3,
        LibraryCompatibility.tooOld,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 3),
        3,
        LibraryCompatibility.satisfied,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 4),
        3,
        LibraryCompatibility.satisfied,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 1),
        3,
        LibraryCompatibility.satisfied,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 3),
        3,
        LibraryCompatibility.satisfied,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4),
        3,
        LibraryCompatibility.contractBroken,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4),
        4,
        LibraryCompatibility.satisfied,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4),
        5,
        LibraryCompatibility.tooOld,
      ),
      (
        const InstalledLibrary(namespace: _ns, version: 6, compatibleSince: 4),
        1,
        LibraryCompatibility.contractBroken,
      ),
    ];
    for (final (installed, minVersion, expected) in cases) {
      test('$installed requiring v$minVersion is ${expected.name}', () {
        expect(
          LibraryCompatibility.evaluate(installed, _requires(minVersion)),
          expected,
        );
      });
    }

    test('rejects a library from another namespace', () {
      expect(
        () => LibraryCompatibility.evaluate(
          const InstalledLibrary(namespace: 'other.widgets', version: 1),
          _requires(1),
        ),
        throwsArgumentError,
      );
    });

    test('evaluateIn looks the library up by namespace', () {
      final installed = InstalledCapability(
        builtInCatalogVersion: 1,
        installedLibraries: const [
          InstalledLibrary(namespace: 'other.widgets', version: 9),
          InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4),
        ],
      );
      expect(
        LibraryCompatibility.evaluateIn(installed, _requires(3)),
        LibraryCompatibility.contractBroken,
      );
      expect(
        LibraryCompatibility.evaluateIn(
          installed,
          const LibraryRequirement(namespace: 'absent.widgets', minVersion: 1),
        ),
        LibraryCompatibility.missing,
      );
    });

    test('describeInstalled names the declared break', () {
      expect(LibraryCompatibility.describeInstalled(null), 'not registered');
      expect(
        LibraryCompatibility.describeInstalled(
          const InstalledLibrary(namespace: _ns),
        ),
        'registered without a capability version',
      );
      expect(
        LibraryCompatibility.describeInstalled(
          const InstalledLibrary(namespace: _ns, version: 2),
        ),
        'installed v2',
      );
      expect(
        LibraryCompatibility.describeInstalled(
          const InstalledLibrary(
            namespace: _ns,
            version: 4,
            compatibleSince: 4,
          ),
        ),
        'installed v4, compatible since v4',
      );
    });
  });

  group('InstalledLibrary.compatibleSince', () {
    test('is written only when above 1', () {
      expect(
        const InstalledLibrary(namespace: _ns, version: 4).toJson(),
        {'namespace': _ns, 'version': 4},
      );
      expect(
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 1)
            .toJson(),
        {'namespace': _ns, 'version': 4},
      );
      expect(
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 3)
            .toJson(),
        {'namespace': _ns, 'version': 4, 'compatibleSince': 3},
      );
    });

    test('null and 1 are the same value', () {
      const implicit = InstalledLibrary(namespace: _ns, version: 4);
      const explicit =
          InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 1);
      expect(explicit, implicit);
      expect(explicit.hashCode, implicit.hashCode);
      expect(
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4),
        isNot(implicit),
      );
    });

    test('round-trips through JSON', () {
      const library =
          InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4);
      expect(InstalledLibrary.fromJson(library.toJson()), library);
    });

    test('fromJson rejects a value outside 1..version', () {
      for (final json in <Map<String, dynamic>>[
        {'namespace': _ns, 'version': 4, 'compatibleSince': 0},
        {'namespace': _ns, 'version': 4, 'compatibleSince': 5},
        {'namespace': _ns, 'version': 4, 'compatibleSince': '2'},
        {'namespace': _ns, 'version': null, 'compatibleSince': 1},
        {'namespace': _ns, 'version': 4, 'compatibleSince': null},
      ]) {
        expect(
          () => InstalledLibrary.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('keeps the canonical bytes of a capability without a break', () {
      final capability = InstalledCapability(
        builtInCatalogVersion: 5,
        installedLibraries: const [
          InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 1),
        ],
      );
      expect(
        jsonEncode(capability.toJson()),
        '{"builtInCatalogVersion":5,"installedLibraries":'
        '[{"namespace":"acme.widgets","version":4}]}',
      );
    });
  });

  group('flow experiment contract', () {
    FlowExperimentClientContractV1 contractWith(InstalledLibrary library) =>
        experimentClientContract(
          installedCapability: InstalledCapability(
            builtInCatalogVersion: 5,
            installedLibraries: [library],
          ),
        );

    test('keeps its canonical bytes when no break is declared', () {
      final implicit =
          contractWith(const InstalledLibrary(namespace: _ns, version: 4));
      final explicit = contractWith(
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 1),
      );
      expect(explicit.canonicalBytes, implicit.canonicalBytes);
      expect(
        utf8.decode(implicit.canonicalBytes),
        contains('"installedLibraries":[{"namespace":"acme.widgets",'
            '"version":4}]'),
      );
    });

    test('round-trips a declared break through the strict decoder', () {
      final contract = contractWith(
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4),
      );
      final bytes = contract.canonicalBytes;
      expect(
        utf8.decode(bytes),
        contains('{"compatibleSince":4,"namespace":"acme.widgets",'
            '"version":4}'),
      );
      final decoded = FlowExperimentClientContractV1.decode(bytes);
      expect(
        decoded.installedCapability.installedLibraries.single,
        const InstalledLibrary(namespace: _ns, version: 4, compatibleSince: 4),
      );
      expect(decoded.contentHash, contract.contentHash);
      expect(
        decoded.contentHash,
        isNot(
          contractWith(
            const InstalledLibrary(namespace: _ns, version: 4),
          ).contentHash,
        ),
      );
    });

    String withLibraryJson(String libraryJson) {
      final canonical = utf8.decode(
        contractWith(const InstalledLibrary(namespace: _ns, version: 4))
            .canonicalBytes,
      );
      return canonical.replaceFirst(
        '{"namespace":"acme.widgets","version":4}',
        libraryJson,
      );
    }

    test('rejects an explicit compatibleSince of 1 as noncanonical', () {
      expect(
        () => FlowExperimentClientContractV1.decode(
          utf8.encode(
            withLibraryJson(
              '{"compatibleSince":1,"namespace":"acme.widgets","version":4}',
            ),
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects a compatibleSince above the version', () {
      expect(
        () => FlowExperimentClientContractV1.decode(
          utf8.encode(
            withLibraryJson(
              '{"compatibleSince":5,"namespace":"acme.widgets","version":4}',
            ),
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects any other unknown key', () {
      expect(
        () => FlowExperimentClientContractV1.decode(
          utf8.encode(
            withLibraryJson(
              '{"namespace":"acme.widgets","since":2,"version":4}',
            ),
          ),
        ),
        throwsFormatException,
      );
    });
  });
}
