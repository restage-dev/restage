import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('uses a distinct validated presentation reservation identifier', () {
    final reservation =
        GeneratedPresentationReferenceId('presentation.checkout.primary');
    final eventReference =
        GeneratedReferenceId('presentation.checkout.primary');

    expect(reservation.value, 'presentation.checkout.primary');
    expect(reservation, isNot(eventReference));
    expect(
      () => GeneratedPresentationReferenceId('Presentation.Checkout'),
      throwsArgumentError,
    );
  });
}
