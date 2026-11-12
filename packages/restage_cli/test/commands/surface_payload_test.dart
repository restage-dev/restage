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

  test('SurfacePayloadException remains a publication assembly failure', () {
    const error = SurfacePayloadException('payload failed');
    expect(error.message, 'payload failed');
    expect(error, isA<Exception>());
  });
}
