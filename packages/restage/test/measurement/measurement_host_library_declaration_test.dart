import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_rfw_presentation.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('the measurement presentation builds exactly its declared constructors',
      () {
    final declared = hostInstalledRfwLibrary(
      kMeasurementRfwPresentationLibrary.parts.join('.'),
    );

    expect(declared, isNotNull);
    expect(
      buildMeasurementRfwPresentationLocalWidgetLibrary().widgets.keys.toSet(),
      declared!.constructors,
    );
  });
}
