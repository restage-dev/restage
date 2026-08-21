import 'package:restage_cli/src/api/experiment_activation_api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;
import 'package:test/test.dart';

void main() {
  group('ExperimentActivationApi', () {
    test(
      'rejects empty command bytes before invoking its authority transport',
      () async {
        var calls = 0;
        final api = ExperimentActivationApi(
          transport: (bytes) async {
            calls += 1;
            return bytes;
          },
        );

        await expectLater(
          api.executeCanonicalBytes(const []),
          throwsA(isA<measurement.CanonicalFormatException>()),
        );
        expect(calls, isZero);
      },
    );
  });
}
