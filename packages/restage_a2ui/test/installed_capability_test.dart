import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui/src/installed_capability.dart';

void main() {
  group('A2uiAvailableLibrary', () {
    test('value equality + canonical fields', () {
      const a = A2uiAvailableLibrary(namespace: 'acme.widgets', version: 3);
      const b = A2uiAvailableLibrary(namespace: 'acme.widgets', version: 3);
      const c = A2uiAvailableLibrary(namespace: 'acme.widgets', version: 4);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.namespace, 'acme.widgets');
      expect(a.version, 3);
    });
  });

  group('A2uiInstalledCapability', () {
    test('canonicalizes availableLibraries to namespace order', () {
      final cap = A2uiInstalledCapability(
        catalogContentVersion: 2,
        availableLibraries: const [
          A2uiAvailableLibrary(namespace: 'z.widgets', version: 1),
          A2uiAvailableLibrary(namespace: 'a.widgets', version: 5),
        ],
      );
      expect(cap.availableLibraries.map((l) => l.namespace), [
        'a.widgets',
        'z.widgets',
      ]);
      expect(cap.catalogContentVersion, 2);
    });

    test('fromStampJson parses a Restage catalog capability stamp block', () {
      final cap = A2uiInstalledCapability.fromStampJson(const {
        'catalogContentVersion': 4,
        'availableLibraries': [
          {'namespace': 'acme.widgets', 'version': 3},
        ],
        'perItemSinceVersion': {'Text': 1, 'AcmeBanner': 5},
      });
      expect(cap.catalogContentVersion, 4);
      expect(cap.availableLibraries.single.namespace, 'acme.widgets');
      expect(cap.availableLibraries.single.version, 3);
    });

    test('fromStampJson tolerates an absent availableLibraries list', () {
      final cap = A2uiInstalledCapability.fromStampJson(const {
        'catalogContentVersion': 1,
      });
      expect(cap.catalogContentVersion, 1);
      expect(cap.availableLibraries, isEmpty);
    });

    test('fromStampJson fails closed on a malformed stamp', () {
      expect(
        () => A2uiInstalledCapability.fromStampJson(const {
          'catalogContentVersion': 'not-an-int',
        }),
        throwsFormatException,
      );
      expect(
        () => A2uiInstalledCapability.fromStampJson(const {
          'catalogContentVersion': 2,
          'availableLibraries': [
            {'namespace': 'acme', 'version': 'bad'},
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
