import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_surface_identity.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('surface ID is byte-identical to the frozen publication line', () {
    final screen = measurementSurfaceIdForSelectorV1(
      MeasurementPublicationSelectorV1(
        surface: Surface.onboarding,
        slug: 'welcome',
        sourceKind: SurfaceSourceKind.screen,
        contractVersion: 3,
      ),
    );
    final paywall = measurementSurfaceIdForSelectorV1(
      MeasurementPublicationSelectorV1(
        surface: Surface.paywall,
        slug: 'premium',
        sourceKind: SurfaceSourceKind.paywall,
      ),
    );

    expect(
      screen.value,
      'surface.v1.'
      'bfed7da133b84d189bc2d3b64c745954f9450f43873c505dd2a4652943b60a25',
    );
    expect(
      paywall.value,
      'surface.v1.'
      '37c9a6412178b76c18c2e55d10e69fb5f1e9ff3907b3d11dcd32929f8a20818f',
    );
  });
}
