import 'package:restage_cli/src/commands/surface_payload.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('unionRequiredLibraries', () {
    test('keeps the greatest version per namespace in canonical order', () {
      expect(
        unionRequiredLibraries([
          const [
            LibraryRequirement(namespace: 'z.widgets', minVersion: 2),
            LibraryRequirement(namespace: 'a.widgets', minVersion: 1),
          ],
          const [
            LibraryRequirement(namespace: 'z.widgets', minVersion: 4),
            LibraryRequirement(namespace: 'a.widgets', minVersion: 3),
          ],
        ]),
        const [
          LibraryRequirement(namespace: 'a.widgets', minVersion: 3),
          LibraryRequirement(namespace: 'z.widgets', minVersion: 4),
        ],
      );
    });

    test('returns an empty list for empty sidecar requirements', () {
      expect(unionRequiredLibraries(const [[], []]), isEmpty);
    });
  });

  group('publishCapabilityWarning', () {
    test('does not warn for baseline capabilities', () {
      expect(
        publishCapabilityWarning(
          CapabilityManifest(
            builtInFloor: kBaselineCatalogVersion,
            requiredLibraries: const [],
          ),
        ),
        isNull,
      );
    });

    test('names elevated catalog and library requirements', () {
      final warning = publishCapabilityWarning(
        CapabilityManifest(
          builtInFloor: kBaselineCatalogVersion + 1,
          requiredLibraries: const [
            LibraryRequirement(namespace: 'example.widgets', minVersion: 2),
          ],
        ),
      );

      expect(
        warning,
        'Note for devices: this publication renders only in app builds that '
        'register the built-in widget catalog at content version '
        '${kBaselineCatalogVersion + 1} or later and the app widget library '
        '"example.widgets" at version 2 or later. Installs of older app '
        'builds show their configured fallback. This is about device '
        'delivery; dashboard previews depend on a build push instead.',
      );
    });
  });

  test('SurfacePayloadException remains a publication assembly failure', () {
    const error = SurfacePayloadException('payload failed');
    expect(error.message, 'payload failed');
    expect(error, isA<Exception>());
  });
}
