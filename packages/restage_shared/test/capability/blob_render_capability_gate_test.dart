import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('InstalledLibrary', () {
    test('round-trips through JSON with a version', () {
      const lib = InstalledLibrary(namespace: 'acme.widgets', version: 3);
      final decoded = InstalledLibrary.fromJson(lib.toJson());
      expect(decoded, lib);
      expect(decoded.namespace, 'acme.widgets');
      expect(decoded.version, 3);
    });

    test('round-trips an unversioned library (null version preserved)', () {
      const lib = InstalledLibrary(namespace: 'acme.widgets');
      expect(lib.version, isNull);
      final json = lib.toJson();
      final decoded = InstalledLibrary.fromJson(json);
      expect(decoded, lib);
      expect(decoded.version, isNull);
    });

    test('value equality is by namespace + version', () {
      expect(
        const InstalledLibrary(namespace: 'a', version: 1),
        const InstalledLibrary(namespace: 'a', version: 1),
      );
      expect(
        const InstalledLibrary(namespace: 'a', version: 1),
        isNot(const InstalledLibrary(namespace: 'a', version: 2)),
      );
      expect(
        const InstalledLibrary(namespace: 'a', version: 1),
        isNot(const InstalledLibrary(namespace: 'a')),
      );
    });
  });

  group('InstalledCapability', () {
    test('versionOf returns the version of a present, versioned library', () {
      final cap = InstalledCapability(
        builtInCatalogVersion: 5,
        installedLibraries: const [
          InstalledLibrary(namespace: 'acme.widgets', version: 4),
        ],
      );
      expect(cap.versionOf('acme.widgets'), 4);
    });

    test('versionOf returns null for an absent library', () {
      final cap = InstalledCapability(
        builtInCatalogVersion: 5,
        installedLibraries: const [],
      );
      expect(cap.versionOf('acme.widgets'), isNull);
    });

    test('versionOf returns null for a present but unversioned library', () {
      final cap = InstalledCapability(
        builtInCatalogVersion: 5,
        installedLibraries: const [InstalledLibrary(namespace: 'acme.widgets')],
      );
      expect(cap.versionOf('acme.widgets'), isNull);
    });

    test('equality is order-independent (canonicalized by namespace)', () {
      final a = InstalledCapability(
        builtInCatalogVersion: 5,
        installedLibraries: const [
          InstalledLibrary(namespace: 'b.lib', version: 1),
          InstalledLibrary(namespace: 'a.lib', version: 2),
        ],
      );
      final b = InstalledCapability(
        builtInCatalogVersion: 5,
        installedLibraries: const [
          InstalledLibrary(namespace: 'a.lib', version: 2),
          InstalledLibrary(namespace: 'b.lib', version: 1),
        ],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('round-trips through JSON, preserving a null library version', () {
      final cap = InstalledCapability(
        builtInCatalogVersion: 7,
        installedLibraries: const [
          InstalledLibrary(namespace: 'acme.widgets', version: 2),
          InstalledLibrary(namespace: 'acme.unversioned'),
        ],
      );
      final decoded = InstalledCapability.fromJson(cap.toJson());
      expect(decoded, cap);
      expect(decoded.versionOf('acme.unversioned'), isNull);
      expect(decoded.versionOf('acme.widgets'), 2);
    });
  });

  group('BlobRenderCapabilityGate.evaluate', () {
    CapabilityManifest manifest({
      required int floor,
      List<LibraryRequirement> libraries = const [],
    }) =>
        CapabilityManifest(builtInFloor: floor, requiredLibraries: libraries);

    InstalledCapability installed({
      required int catalog,
      List<InstalledLibrary> libraries = const [],
    }) =>
        InstalledCapability(
          builtInCatalogVersion: catalog,
          installedLibraries: libraries,
        );

    test('accepts when the floor is met and there are no libraries', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(floor: 3),
        installed: installed(catalog: 3),
      );
      expect(verdict.accepted, isTrue);
      expect(verdict, isA<BlobRenderAccepted>());
    });

    test('accepts when the floor is met and every library is satisfied', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(
          floor: 2,
          libraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          ],
        ),
        installed: installed(
          catalog: 5,
          libraries: const [
            InstalledLibrary(namespace: 'acme.widgets', version: 3),
          ],
        ),
      );
      expect(verdict.accepted, isTrue);
    });

    test('rejects on the catalog floor with a parity diagnostic', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(floor: 5),
        installed: installed(catalog: 3),
      );
      expect(verdict.accepted, isFalse);
      final rejected = verdict as BlobRenderRejected;
      expect(rejected.reason, BlobRenderRejectionReason.capabilityFloorRaised);
      expect(
        rejected.message,
        'requires built-in catalog version 5, above the installed 3',
      );
    });

    test('rejects an unregistered required library ("not registered")', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(
          floor: 1,
          libraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          ],
        ),
        installed: installed(catalog: 5),
      );
      final rejected = verdict as BlobRenderRejected;
      expect(
        rejected.reason,
        BlobRenderRejectionReason.requiredLibraryUnsatisfied,
      );
      expect(
        rejected.message,
        'requires library "acme.widgets" >= v2 (not registered)',
      );
    });

    test('rejects an unversioned installed library', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(
          floor: 1,
          libraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          ],
        ),
        installed: installed(
          catalog: 5,
          libraries: const [InstalledLibrary(namespace: 'acme.widgets')],
        ),
      );
      final rejected = verdict as BlobRenderRejected;
      expect(
        rejected.message,
        'requires library "acme.widgets" >= v2 '
        '(registered without a capability version)',
      );
    });

    test('rejects a stale installed library ("installed vN")', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(
          floor: 1,
          libraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
          ],
        ),
        installed: installed(
          catalog: 5,
          libraries: const [
            InstalledLibrary(namespace: 'acme.widgets', version: 1),
          ],
        ),
      );
      final rejected = verdict as BlobRenderRejected;
      expect(
        rejected.message,
        'requires library "acme.widgets" >= v3 (installed v1)',
      );
    });

    test('checks the catalog floor before libraries', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(
          floor: 9,
          libraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          ],
        ),
        installed: installed(catalog: 1),
      );
      final rejected = verdict as BlobRenderRejected;
      expect(rejected.reason, BlobRenderRejectionReason.capabilityFloorRaised);
    });
  });

  group('kBlobGateLogicRevision', () {
    test('is a positive constant (bumped when gate semantics change)', () {
      expect(kBlobGateLogicRevision, greaterThanOrEqualTo(1));
    });
  });

  group('verdict identity + totality matrix', () {
    // Verdict identity by construction: the server's eligibility evaluator and
    // the client's render gate both call THIS exact evaluate(). A matrix over
    // its decision space is therefore the identity guarantee — the same inputs
    // cannot yield different verdicts on the two sides, because it is one pure,
    // deterministic, total function.

    InstalledCapability installed(
      int floor, [
      List<InstalledLibrary> libs = const [],
    ]) =>
        InstalledCapability(
          builtInCatalogVersion: floor,
          installedLibraries: libs,
        );

    CapabilityManifest manifest(
      int floor, [
      List<LibraryRequirement> reqs = const [],
    ]) =>
        CapabilityManifest(builtInFloor: floor, requiredLibraries: reqs);

    test('is deterministic: identical inputs yield an equal verdict', () {
      final required = manifest(5, const [
        LibraryRequirement(namespace: 'a', minVersion: 2),
      ]);
      final have = installed(5, const [
        InstalledLibrary(namespace: 'a', version: 1),
      ]);
      final first = BlobRenderCapabilityGate.evaluate(
        required: required,
        installed: have,
      );
      final second = BlobRenderCapabilityGate.evaluate(
        required: required,
        installed: have,
      );
      expect(first, second);
      expect(first.accepted, second.accepted);
    });

    test(
        'is total over the floor x single-library matrix: always a verdict, '
        'never a throw, with the floor checked before libraries', () {
      const requiredFloor = 5;
      for (final floorDelta in const [-1, 0, 1]) {
        for (final libState in const [
          'none',
          'absent',
          'unversioned',
          'stale',
          'exact',
          'newer',
        ]) {
          final installedFloor = requiredFloor + floorDelta;
          final reqs = libState == 'none'
              ? const <LibraryRequirement>[]
              : const [LibraryRequirement(namespace: 'lib', minVersion: 3)];
          final libs = switch (libState) {
            'unversioned' => const [InstalledLibrary(namespace: 'lib')],
            'stale' => const [InstalledLibrary(namespace: 'lib', version: 2)],
            'exact' => const [InstalledLibrary(namespace: 'lib', version: 3)],
            'newer' => const [InstalledLibrary(namespace: 'lib', version: 4)],
            _ => const <InstalledLibrary>[],
          };
          final verdict = BlobRenderCapabilityGate.evaluate(
            required: manifest(requiredFloor, reqs),
            installed: installed(installedFloor, libs),
          );
          final where = 'floorDelta=$floorDelta libState=$libState';

          if (floorDelta < 0) {
            // The floor is checked FIRST: an unmet floor rejects regardless of
            // library state.
            expect(verdict, isA<BlobRenderRejected>(), reason: where);
            expect(
              (verdict as BlobRenderRejected).reason,
              BlobRenderRejectionReason.capabilityFloorRaised,
              reason: where,
            );
            continue;
          }
          switch (libState) {
            case 'none' || 'exact' || 'newer':
              expect(verdict, const BlobRenderAccepted(), reason: where);
            case 'absent' || 'unversioned' || 'stale':
              expect(verdict, isA<BlobRenderRejected>(), reason: where);
              expect(
                (verdict as BlobRenderRejected).reason,
                BlobRenderRejectionReason.requiredLibraryUnsatisfied,
                reason: where,
              );
          }
        }
      }
    });

    test('rejects on the FIRST unsatisfied library (deterministic order)', () {
      final verdict = BlobRenderCapabilityGate.evaluate(
        required: manifest(1, const [
          LibraryRequirement(namespace: 'first', minVersion: 2),
          LibraryRequirement(namespace: 'second', minVersion: 2),
        ]),
        // 'first' is stale and 'second' is absent — the first failure wins.
        installed: installed(1, const [
          InstalledLibrary(namespace: 'first', version: 1),
        ]),
      );
      expect(verdict, isA<BlobRenderRejected>());
      expect((verdict as BlobRenderRejected).message, contains('first'));
      expect(verdict.message, isNot(contains('second')));
    });
  });
}
