import 'package:flutter_test/flutter_test.dart';
import 'package:restage_render_host/src/geometry_registry.dart';
import 'package:restage_render_host/src/manifest.dart';
import 'package:restage_render_host/src/marker_library.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('the marker library builds exactly its declared constructors', () {
    final markers = buildMarkerWidgetLibrary(
      GeometryRegistry(frameRenderBox: () => null),
    );

    expect(
      markers.widgets.keys.toSet(),
      kPreviewInstrumentationRfwLibrary.constructors,
    );
    // The other declared library is the SDK's measurement presentation, which
    // its own package pins.
    expect(kHostInstalledRfwLibraries, hasLength(2));
  });

  test('a bundle manifest may not declare a host library', () {
    for (final library in kHostInstalledRfwLibraries) {
      expect(
        () => RenderBundleManifest(
          formatVersion: 1,
          catalog: <String, Object?>{
            'libraries': <String, Object?>{
              library.namespace: <String, Object?>{},
            },
            'widgets': const <Object?>[],
          },
        ),
        throwsFormatException,
        reason: library.namespace,
      );
    }
  });
}
