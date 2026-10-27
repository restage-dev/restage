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
    expect(
      kHostInstalledRfwLibraries.map((library) => library.namespace),
      unorderedEquals([
        kReservedPreviewLibraryName,
        kMeasurementPresentationLibraryName,
        'restage.core',
      ]),
    );
    expect(
      hostInstalledRfwLibrary('restage.core')!.constructors,
      {kBuilderContinuationWidgetName},
    );
  });

  test('a bundle manifest may not claim a reserved catalog namespace', () {
    for (final library in kHostInstalledRfwLibraries
        .where((library) => library.reservesCatalogNamespace)) {
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

  test('ordinary core metadata is admitted but hidden constructors are refused',
      () {
    Map<String, Object?> catalog(String namespace, String name) => {
          'libraries': <String, Object?>{namespace: <String, Object?>{}},
          'widgets': [
            {'library': namespace, 'name': name, 'properties': <Object?>[]},
          ],
        };
    for (final name in ['Text', 'Column']) {
      expect(
        () => RenderBundleManifest(
          formatVersion: 1,
          catalog: catalog('restage.core', name),
        ),
        returnsNormally,
      );
    }
    for (final namespace in ['restage.core', 'acme.widgets']) {
      expect(
        () => RenderBundleManifest(
          formatVersion: 1,
          catalog: catalog(namespace, kBuilderContinuationWidgetName),
        ),
        throwsFormatException,
      );
    }
  });
}
