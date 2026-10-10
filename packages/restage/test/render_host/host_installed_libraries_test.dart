import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_rfw_presentation.dart';
import 'package:restage/src/render_host/geometry_registry.dart';
import 'package:restage/src/render_host/manifest.dart';
import 'package:restage/src/render_host/marker_library.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' show LocalWidgetLibrary;

void main() {
  test('the host installs exactly the declared host libraries', () {
    final installed = <String, LocalWidgetLibrary>{
      kPreviewInstrumentationRfwLibrary.namespace: buildMarkerWidgetLibrary(
        GeometryRegistry(frameRenderBox: () => null),
      ),
      kMeasurementRfwPresentationLibrary.parts.join('.'):
          buildMeasurementRfwPresentationLocalWidgetLibrary(),
    };

    expect(
      installed.keys.toSet(),
      kHostInstalledRfwLibraries.map((library) => library.namespace).toSet(),
    );
    for (final library in kHostInstalledRfwLibraries) {
      expect(
        installed[library.namespace]!.widgets.keys.toSet(),
        library.constructors,
        reason: library.namespace,
      );
    }
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
